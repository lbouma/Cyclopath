/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN;

/* Load temp. VIEWs. */
\i ../../daily/usage/ccp_common.sql

/* NOTE: Before 2008-10-01, this script included deleted byways in the results
   for "byways with n ratings". */

/* before_date is NULL for the nightly cron. If you're recreating
   the counts file, use a date of the form '2014-09-18'. */

CREATE FUNCTION _inline(IN before_date DATE) RETURNS VOID AS $$

DECLARE

   branch_baseline_id INTEGER;
   group_public_id INTEGER;
   rid_inf INTEGER;
   byway_item_type_id INTEGER;
   now_date_string TEXT;
   now_revision INTEGER;

BEGIN

   branch_baseline_id := cp_branch_baseline_id();
   group_public_id := cp_group_public_id();
   rid_inf := cp_rid_inf();
   byway_item_type_id := cp_item_type_id('byway');

   IF before_date IS NULL THEN
      now_date_string := to_char(now(), 'YYYYMMDD:HH24:MI:SS');
      --now_revision := cp_rid_inf();
      --now_revision := cp_rev_max();
      now_revision := NULL;

   ELSE
      now_date_string := to_char(before_date, 'YYYYMMDD:HH24:MI:SS');
      now_revision := id FROM revision
                        WHERE timestamp < before_date
                        ORDER BY timestamp DESC
                        LIMIT 1;
   END IF;

   /*
   RAISE INFO 'branch_baseline_id: %.', branch_baseline_id;
   RAISE INFO 'group_public_id: %.', group_public_id;
   RAISE INFO 'rid_inf: %.', rid_inf;
   RAISE INFO 'byway_item_type_id: %.', byway_item_type_id;
   RAISE INFO 'now_date_string: %.', now_date_string;
   RAISE INFO 'now_revision: %.', now_revision;
   */

   /* SYNC_ME: See pyserver's conf.py: conf.generic_rater_username
                                       conf.bsir_rater_username
                                       conf.cbf7_rater_username
                                       conf.ccpx_rater_username
               We want to ignore these so-called users' rating.
   */

   /* BUG nnnn: This select never omitted the generic raters,
      so the count_ratings.dat file has also had inflated stats.
      And since going statewide, the usage plot in meaningless,
      since ratings spiked to 2e+06 during the update.

      The byway_rating table only records the last modified value
      for a rating, so the following sql won't account for rating
      activity if a user keeps re-rating the same roads. We could
      use byway_rating_event to get around this, but that adds a
      lot more work for us, and also, the byway_rating_event table
      isn't always updated properly, so I don't think it's even
      that accurate. But I'm assuming people don't re-rate roads
      all too often, so this code should be okay to use if you
      need to rebuild the count_ratings.dat file (which is usually
      just appended to one line at a time each night by the daily
      cron job). */

   CREATE TABLE count_ratings AS

   SELECT

      now_date_string AS now,

      (SELECT count(*)
         FROM byway_rating AS brat
        WHERE (branch_id = branch_baseline_id)
          AND (   (before_date IS NULL)
               OR (last_modified < before_date))
          AND username NOT IN ('_r_generic',
                               '_rating_bsir',
                               '_rating_cbf7',
                               '_rating_ccpx')
         ) AS rating_ct,

      (SELECT count(*)
         FROM byway_rating AS brat
        WHERE (branch_id = branch_baseline_id)
          AND (   (    (before_date IS NULL)
                   AND (last_modified >= now() - (interval '24 hours')))
               OR (    (last_modified < before_date)
                   AND (last_modified >= before_date - (interval '24 hours'))))
          AND username NOT IN ('_r_generic',
                               '_rating_bsir',
                               '_rating_cbf7',
                               '_rating_ccpx')
         ) AS rating_new_ct,

      (SELECT count(*)
         FROM geofeature AS feat
         JOIN group_item_access AS gia
           ON (gia.item_id = feat.system_id)
        WHERE (gia.branch_id = branch_baseline_id)
          AND (gia.group_id = group_public_id)
          AND (gia.item_type_id = byway_item_type_id)
          AND (   (    (now_revision IS NULL)
                   AND (gia.valid_until_rid = rid_inf))
               OR (    (now_revision IS NOT NULL)
                   AND (gia.valid_until_rid > now_revision)
                   AND (gia.valid_start_rid <= now_revision)))
         ) AS byway_ct,

      sum((ct >= 1)::INTEGER) AS byway_r1_ct,
      sum((ct >= 2)::INTEGER) AS byway_r2_ct,
      sum((ct >= 3)::INTEGER) AS byway_r3_ct,
      sum((ct >= 5)::INTEGER) AS byway_r5_ct,
      sum((ct >= 10)::INTEGER) AS byway_r10_ct,
      sum((ct >= 25)::INTEGER) AS byway_r25_ct

   FROM (

      SELECT count(*) AS ct
        FROM byway_rating AS brat
        --JOIN geofeature AS feat
        --  ON (brat.byway_stack_id = feat.stack_id)
       WHERE (brat.value >= 0)
         AND (   (before_date IS NULL)
              OR (brat.last_modified < before_date))
         AND (   (brat.username IS NULL)
              OR (brat.username NOT IN
                  (SELECT username from user_ where dont_study)))
         AND brat.username NOT IN ('_r_generic',
                                   '_rating_bsir',
                                   '_rating_cbf7',
                                   '_rating_ccpx')
       GROUP BY brat.byway_stack_id
        ) AS foo
   ;

END; $$ LANGUAGE plpgsql VOLATILE;

/* Send output to /dev/null otherwise data file gets an extraneous newline. */

\o /dev/null
SELECT _inline(NULL);
\o

/* Get the one row of results, which the caller appends to the data file. */

SELECT * FROM count_ratings;

/* Cleanup the table. */

DROP TABLE count_ratings;

/*

  2014.09.18: Rebuild the count_ratings.dat file from scratch.

              The old sql included generated ratings, so the graph
              plots were pretty meaningless. See more comments above.
                
      Comment out the last two selects and uncomment the rebuild_dat call.

      You can test with, e.g.,:
      
      SELECT _inline('2011-06-01'::DATE);
      SELECT * FROM count_ratings;
      DROP TABLE count_ratings;

      SELECT _inline('2011-08-01'::DATE);
      SELECT * FROM count_ratings;
      DROP TABLE count_ratings;

      You can get an idea who rates with:

      SELECT COUNT(*), username
        FROM byway_rating
       GROUP BY username
       ORDER BY count DESC;

      -- 2014.09.18: 608 rows, including 4 generated raters.

*/

CREATE FUNCTION rebuild_dat() RETURNS VOID AS $$
DECLARE

   dsl_row date_since_live%ROWTYPE;
   first_time BOOLEAN;

BEGIN

   first_time := TRUE;

   FOR dsl_row IN SELECT day_ FROM date_since_live LOOP

      PERFORM _inline(dsl_row.day_);

      IF first_time IS TRUE THEN
         CREATE TABLE count_ratings_all AS SELECT * FROM count_ratings;
         first_time := FALSE;
      ELSE
         INSERT INTO count_ratings_all SELECT * FROM count_ratings;
      END IF;

      DROP TABLE count_ratings;

   END LOOP;
END; $$ LANGUAGE plpgsql VOLATILE;

/* Uncomment this and comment out the SELECTs above to rebuild the dat file.
   2014.09.18: ~ 3 hours. */
/*
\o /dev/null
SELECT rebuild_dat();
\o
SELECT * FROM count_ratings_all ORDER BY now ASC;
*/

DROP FUNCTION rebuild_dat();

/* */

DROP FUNCTION _inline(IN before_date DATE);

ROLLBACK;


/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script fixes tags orphaned by a bug in the better_cp campaign.
\qecho 
\qecho See Bugs 2007 and 2237.
\qecho 
\qecho   http://bugs.grouplens.org/show_bug.cgi?id=2007
\qecho 
\qecho   http://bugs.grouplens.org/show_bug.cgi?id=2237
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO minnesota, public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO */
\set VERBOSITY terse

/* ========================================================================= */
/* Step (1) -- Orphaned Link Tags                                            */
/* ========================================================================= */

/* From auditor.sql (also matches the view below, tag_bs_orphan_rows_by_byway):

                   tag_bs id/vers     | byway id/vers

    orphan tag_bs | 1517406 |       1 |  987166 |       3
    orphan tag_bs | 1517407 |       1 |  987166 |       3
    orphan tag_bs | 1517404 |       1 |  987862 |       3
    orphan tag_bs | 1517405 |       1 |  987862 |       3
    orphan tag_bs | 1517422 |       1 | 1009816 |       2
    orphan tag_bs | 1516744 |       1 | 1016023 |       3
    orphan tag_bs | 1516745 |       1 | 1016023 |       3
    orphan tag_bs | 1517424 |       1 | 1017466 |       2
    orphan tag_bs | 1517421 |       1 | 1066228 |       2
    orphan tag_bs | 1517324 |       1 | 1110007 |       3
    orphan tag_bs | 1517325 |       1 | 1110007 |       3
    orphan tag_bs | 1517375 |       1 | 1130129 |       3
    orphan tag_bs | 1517376 |       1 | 1130129 |       3
    orphan tag_bs | 1517373 |       1 | 1130130 |       3
    orphan tag_bs | 1517374 |       1 | 1130130 |       3
    orphan tag_bs | 1517396 |       1 | 1130444 |       2
    orphan tag_bs | 1517397 |       1 | 1130444 |       2
    orphan tag_bs | 1517398 |       1 | 1130445 |       2
    orphan tag_bs | 1517399 |       1 | 1130445 |       2
    orphan tag_bs | 1517400 |       1 | 1130446 |       2
    orphan tag_bs | 1517401 |       1 | 1130446 |       2
    orphan tag_bs | 1517392 |       1 | 1130447 |       2
    orphan tag_bs | 1517393 |       1 | 1130447 |       2
    orphan tag_bs | 1517394 |       1 | 1130448 |       2
    orphan tag_bs | 1517395 |       1 | 1130448 |       2
    orphan tag_bs | 1517390 |       1 | 1130521 |       2
    orphan tag_bs | 1517391 |       1 | 1130521 |       2
    orphan tag_bs | 1517386 |       1 | 1130522 |       2
    orphan tag_bs | 1517387 |       1 | 1130522 |       2
    orphan tag_bs | 1517384 |       1 | 1130524 |       2
    orphan tag_bs | 1517385 |       1 | 1130524 |       2
    orphan tag_bs | 1517388 |       1 | 1130525 |       2
    orphan tag_bs | 1517389 |       1 | 1130525 |       2
    orphan tag_bs | 1521952 |       1 | 1131143 |       5
    orphan tag_bs | 1521953 |       1 | 1131143 |       5
    orphan tag_bs | 1517423 |       1 | 1136214 |       2
    orphan tag_bs | 1516776 |       1 | 1399780 |       2
    orphan tag_bs | 1516777 |       1 | 1399780 |       2
    orphan tag_bs | 1516797 |       1 | 1470611 |       5
    orphan tag_bs | 1516798 |       1 | 1470611 |       5

You'll notice that each of these tag_bses has two versions: the first
version, marked not deleted, and the second version, marked deleted. For each
tag_bs, the byway referenced is deleted in its latest version, which has a
valid_starting_rid well before the tab_bs's. So none of these links should have
been created to begin with!

   SELECT id, version, deleted, valid_starting_rid, valid_before_rid
   FROM tag_bs 
   WHERE id IN (
      1517406
      ,1517407
      ,1517404
      ,1517405
      ,1517422
      ,1516744
      ,1516745
      ,1517424
      ,1517421
      ,1517324
      ,1517325
      ,1517375
      ,1517376
      ,1517373
      ,1517374
      ,1517396
      ,1517397
      ,1517398
      ,1517399
      ,1517400
      ,1517401
      ,1517392
      ,1517393
      ,1517394
      ,1517395
      ,1517390
      ,1517391
      ,1517386
      ,1517387
      ,1517384
      ,1517385
      ,1517388
      ,1517389
      ,1521952
      ,1521953
      ,1517423
      ,1516776
      ,1516777
      ,1516797
      ,1516798
   )
   ORDER BY id ASC, version ASC;

You can verify that each of the byways referenced was marked deleted well 
before the tag_bs was created.

   SELECT id, version, deleted, valid_starting_rid, valid_before_rid
   FROM byway_segment 
   WHERE id IN (
        987166
       , 987166
       , 987862
       , 987862
       ,1009816
       ,1016023
       ,1016023
       ,1017466
       ,1066228
       ,1110007
       ,1110007
       ,1130129
       ,1130129
       ,1130130
       ,1130130
       ,1130444
       ,1130444
       ,1130445
       ,1130445
       ,1130446
       ,1130446
       ,1130447
       ,1130447
       ,1130448
       ,1130448
       ,1130521
       ,1130521
       ,1130522
       ,1130522
       ,1130524
       ,1130524
       ,1130525
       ,1130525
       ,1131143
       ,1131143
       ,1136214
       ,1399780
       ,1399780
       ,1470611
       ,1470611
   )
   ORDER BY id ASC, version ASC;

So why/how were the tag_bses created to begin with? Something was obviously a 
little off in the "Compliance" experiment code.

*/

\qecho Creating helper fcn.: bettercp_cleanup_orphans

CREATE FUNCTION bettercp_cleanup_orphans()
   RETURNS VOID AS $$
   DECLARE
      orphan_link_ids INTEGER[];
      count_orphan_ids INTEGER;
   BEGIN

      CREATE TEMPORARY VIEW tag_bs_orphans AS 
         SELECT ag.id AS tag_bs_id, ag.version AS tag_bs_vers, 
                g.id AS byway_id, g.version AS byway_vers
         FROM tag_bs AS ag
         JOIN byway_segment AS g
            ON (ag.byway_id = g.id
                AND ag.valid_starting_rid < g.valid_before_rid
                AND ag.valid_before_rid > g.valid_starting_rid)
         WHERE
            NOT ag.deleted
            AND g.deleted;

      /* Use this view to compare against the comments writ above. */
      CREATE TEMPORARY VIEW tag_bs_orphans_by_byway AS 
         SELECT *
         FROM (
            SELECT * FROM tag_bs_orphans
            ) AS foo
         ORDER BY byway_id;

      /* Use this to generate the list of IDs to mark deleted; see below. */
      CREATE TEMPORARY VIEW tag_bs_orphans_by_tagbs AS 
         SELECT tag_bs_id, tag_bs_vers
         FROM (
            SELECT * FROM tag_bs_orphans
            ) AS foo
         ORDER BY tag_bs_id;

      CREATE TEMPORARY VIEW tag_bs_orphans_count AS 
         SELECT 
            'count of tag_bs rows which reference already-deleted byways'::TEXT
            AS Comment, COUNT(*) AS count
         FROM (
            SELECT * FROM tag_bs_orphans
            ) AS foo;

      RAISE INFO 'No. of unique tag_bses that ref. already-deleted byways: %',
                 (SELECT count FROM tag_bs_orphans_count);

      /* MAGIC NUMBER: Per the comments above, there should be 40 IDs to
       *               delete. */
      EXECUTE 'SELECT count FROM tag_bs_orphans_count;'
         INTO STRICT count_orphan_ids;

      IF count_orphan_ids != 40 THEN
         RAISE EXCEPTION 'Unexpected count_orphan_ids: %.', count_orphan_ids;
      END IF;

      /* MAGIC NUMBERS: These are the ids from tag_bs_orphans_by_tagbs. 
       * They are hard-coded and not derived programmatically because we want 
       * to be double-extra-sure that we're only marking deleted what we really
       * want to mark deleted. And note that each of these IDs' version is 1. 
       */

      orphan_link_ids := 
         '{1516744
         ,1516745
         ,1516776
         ,1516777
         ,1516797
         ,1516798
         ,1517324
         ,1517325
         ,1517373
         ,1517374
         ,1517375
         ,1517376
         ,1517384
         ,1517385
         ,1517386
         ,1517387
         ,1517388
         ,1517389
         ,1517390
         ,1517391
         ,1517392
         ,1517393
         ,1517394
         ,1517395
         ,1517396
         ,1517397
         ,1517398
         ,1517399
         ,1517400
         ,1517401
         ,1517404
         ,1517405
         ,1517406
         ,1517407
         ,1517421
         ,1517422
         ,1517423
         ,1517424
         ,1521952
         ,1521953}'::INTEGER[];

      RAISE INFO 'Marking 40 rows in tag_bs as deleted:';

      UPDATE 
         tag_bs 
      SET 
         deleted = TRUE
      WHERE 
         id = ANY (orphan_link_ids) 
         AND version = 1;

      RAISE INFO 'After DELETEing, the row count should now be 0: %',
                 (SELECT count FROM tag_bs_orphans_count);

      /* MAGIC NUMBER: 0 rows not deleted. */
      EXECUTE 'SELECT count FROM tag_bs_orphans_count;'
         INTO STRICT count_orphan_ids;
      IF count_orphan_ids != 0 THEN
         RAISE EXCEPTION 'Unexpected count_orphan_ids: %.', count_orphan_ids;
      END IF;

   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ========================================================================= */
/* Step (2) -- Duplicate Link Tags                                           */
/* ========================================================================= */

/* From auditor.sql:
                  tag_bs id1/id2      | byway id |  tag_id                                 |  rev

 duplicate tag_bs | 1516788 | 1516789 |  1023130 | 1516787 | 2010-12-09 17:30:09.563739-06 | 13562
 duplicate tag_bs | 1516790 | 1516791 |  1023088 | 1516787 | 2010-12-09 17:30:09.563739-06 | 13562
 duplicate tag_bs | 1516964 | 1516965 |  1373441 | 1516963 | 2010-12-09 18:08:53.405505-06 | 13585
 duplicate tag_bs | 1516964 | 1516966 |  1373441 | 1516963 | 2010-12-09 18:08:53.405505-06 | 13585
 shares same id2 w/ 1516965 | 1516966 |  1373441 | 1516963 | 2010-12-09 18:08:53.405505-06 | 13585
 duplicate tag_bs | 1517410 | 1517411 |  1087510 | 1516783 | 2010-12-10 09:37:44.176927-06 | 13648
 duplicate tag_bs | 1520272 | 1520308 |  1037296 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520273 | 1520309 |  1019640 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520274 | 1520310 |  1030083 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520275 | 1520311 |  1029905 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520276 | 1520312 |  1025877 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520277 | 1520313 |  1037294 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520278 | 1520314 |  1030075 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520279 | 1520315 |  1011364 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520280 | 1520316 |  1030078 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520281 | 1520317 |  1027011 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520282 | 1520318 |  1029913 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520283 | 1520319 |  1044639 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520284 | 1520320 |  1030101 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520285 | 1520321 |  1037860 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520286 | 1520322 |  1029911 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520287 | 1520323 |  1029903 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520288 | 1520324 |  1032615 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520289 | 1520325 |  1029901 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520290 | 1520326 |  1037323 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520291 | 1520327 |  1019636 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520292 | 1520328 |  1030074 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520293 | 1520329 |  1042850 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520294 | 1520330 |  1037324 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520295 | 1520331 |  1027047 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520296 | 1520332 |  1019364 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520297 | 1520333 |  1030105 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520298 | 1520334 |  1044449 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520299 | 1520335 |  1030094 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520300 | 1520336 |  1043236 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 has since been del 1520301 | 1520337 |  1137386 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520302 | 1520338 |  1029907 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520303 | 1520339 |  1041569 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520304 | 1520340 |  1030107 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520305 | 1520341 |  1019638 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520306 | 1520342 |  1025876 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
 duplicate tag_bs | 1520307 | 1520343 |  1030086 | 1518811 | 2010-12-17 12:05:17.248175-06 | 13995
(42 rows)

NOTE: 2011.08.10: The above SQL was from a few months ago. Out of 42 rows, one 
id2 has two rows (id2 = 1516966) and another id2 (1520337) has since had its 
original tag_bs deleted (id1 = 1520301).

So there are only 40 unique IDs (from the id2 column) to delete.

*/

\qecho Creating helper fcn.: bettercp_cleanup_duplicates

CREATE FUNCTION bettercp_cleanup_duplicates()
   RETURNS VOID AS $$
   DECLARE
      duplicate_link_ids INTEGER[];
      count_duplicate_ids INTEGER;
   BEGIN

      /* EXPLAIN: Why don't we care about deleted duplicates? */

      CREATE TEMPORARY VIEW tag_bs_duplicates AS 
         SELECT a.id as id1,
                b.id as id2,
                a.byway_id,
                a.tag_id,
                r.timestamp,
                r.id as rev
         FROM tag_bs AS a
         JOIN tag_bs AS b 
            ON (a.id < b.id
                AND a.tag_id = b.tag_id
                AND a.byway_id = b.byway_id)
         JOIN revision AS r 
            ON (b.valid_starting_rid = r.id)
         WHERE
            a.valid_before_rid = rid_inf()
            AND NOT a.deleted
            AND b.valid_before_rid = rid_inf()
            AND NOT b.deleted;

      /* Use this view to compare against the comments writ above. */
      CREATE TEMPORARY VIEW tag_bs_duplicates_by_timestamp AS 
         SELECT *
         FROM (
            SELECT * FROM tag_bs_duplicates
            ) AS foo
         ORDER BY timestamp, id1, id2; 

      /* Use this view to generate the list of IDs to delete; see below. */
      CREATE TEMPORARY VIEW tag_bs_duplicates_by_id AS 
         SELECT DISTINCT(id2)
         FROM (
            SELECT * FROM tag_bs_duplicates
            ) AS foo
         ORDER BY id2; 

      CREATE TEMPORARY VIEW tag_bs_duplicates_count AS 
         SELECT 
            'count of tag_bs rows which are duplicates'::TEXT 
            AS Comment, COUNT(DISTINCT(id2)) AS count
         FROM (
            SELECT * FROM tag_bs_duplicates
            ) AS foo;

      RAISE INFO 'Number of tag_bs rows that are duplicates: %',
                 (SELECT count FROM tag_bs_duplicates_count);

      /* MAGIC NUMBER: Per the comments above, there should be 40 IDs to
       *               delete. */
      EXECUTE 'SELECT count FROM tag_bs_duplicates_count;'
         INTO STRICT count_duplicate_ids;

      IF count_duplicate_ids != 40 THEN
         RAISE EXCEPTION 'Unexpected count_duplicate_ids: %.', 
                         count_duplicate_ids;
      END IF;

      /* MAGIC NUMBERS: These are the IDs from tag_bs_duplicates_by_id. */

      duplicate_link_ids :=
         '{1516789
         ,1516791
         ,1516965
         ,1516966
         ,1517411
         ,1520308
         ,1520309
         ,1520310
         ,1520311
         ,1520312
         ,1520313
         ,1520314
         ,1520315
         ,1520316
         ,1520317
         ,1520318
         ,1520319
         ,1520320
         ,1520321
         ,1520322
         ,1520323
         ,1520324
         ,1520325
         ,1520326
         ,1520327
         ,1520328
         ,1520329
         ,1520330
         ,1520331
         ,1520332
         ,1520333
         ,1520334
         ,1520335
         ,1520336
         ,1520338
         ,1520339
         ,1520340
         ,1520341
         ,1520342
         ,1520343}'::INTEGER[];

      RAISE INFO 'Deleting 40 rows from tag_bs:';

      DELETE FROM tag_bs WHERE id = ANY (duplicate_link_ids);

      RAISE INFO 'After DELETEing, the row count should now be 0: %',
                 (SELECT count FROM tag_bs_duplicates_count);

      /* MAGIC NUMBER: 0 rows not deleted. */
      EXECUTE 'SELECT count FROM tag_bs_duplicates_count;'
         INTO STRICT count_duplicate_ids;
      IF count_duplicate_ids != 0 THEN
         RAISE EXCEPTION 'Unexpected count_duplicate_ids: %.',
                         count_duplicate_ids;
      END IF;

   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ========================================================================= */
/* Step (3)                                                                  */
/* ========================================================================= */

\qecho Creating helper fcn.: bettercp_cleanup_tag_bses

CREATE FUNCTION bettercp_cleanup_tag_bses()
   RETURNS VOID AS $$
   BEGIN
      RAISE INFO 'bettercp_cleanup_tag_bses';
      PERFORM bettercp_cleanup_orphans();
      PERFORM bettercp_cleanup_duplicates();
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* */

\qecho Running... maybe....

SELECT run_maybe('minnesota', 'bettercp_cleanup_tag_bses');

/* ========================================================================= */
/* Step (4) -- Cleanup                                                       */
/* ========================================================================= */

DROP FUNCTION bettercp_cleanup_tag_bses();
DROP FUNCTION bettercp_cleanup_duplicates();
DROP FUNCTION bettercp_cleanup_orphans();

/* ========================================================================= */
/* Step (n) -- All done!                                                     */
/* ========================================================================= */

\qecho 
\qecho All done!
\qecho 

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;


/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho This script fixes a tag problem.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Adding to revision table the time that table lock was held.
\qecho

/* Some commits, and especially Shapefile imports, take a long time,
   and [lb] thinks adding how long a commit takes to the revision
   table may provide interesting data and also better context about
   the commit (people might gloss over a changenote, but if the commit
   took four hours, maybe they'll pay more attention). */

CREATE FUNCTION cp_alter_revision_forgiving()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         ALTER TABLE revision ADD COLUMN msecs_holding_lock INTEGER;

      /* ERROR: column "..." of relation "..." already exists
         Use EXCEPTION WHEN OTHERS to catch all postgres exceptions. */
      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'split_from_stack_id already altered';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_revision_forgiving();

DROP FUNCTION cp_alter_revision_forgiving();

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho
\qecho Setting multiple_allowed on appropriate attributes.
\qecho

-- Do attributes have same duplicate problem tag link_values?

UPDATE attribute SET multiple_allowed = TRUE
   WHERE value_internal_name IN (
      '/post/rating'
      , '/route/polarity'
      , '/item/alert_email'
      , '/item/reminder_email'
   );

/* ==================================================================== */
/* Step (3)                                                             */
/* ==================================================================== */

\qecho
\qecho Fixing corrupt tag(s).
\qecho

/*

-- NOTE: The following columns in the following query are all 0 or NULL.
--         direction_id,
--         value_boolean,
--         value_integer,
--         value_real,
--         value_text,
--         value_binary,
--         value_date,
--         line_evt_mval_a,
--         line_evt_mval_b,
--         line_evt_dir_id,
--         tsvect_value_text

SELECT
   system_id AS sys_id
   , branch_id AS br_id
   , stack_id AS stk_id
   , version AS vers
   , lhs_stack_id AS lhs_stkid
   , rhs_stack_id AS rhs_stkid
FROM link_value WHERE rhs_stack_id = 1137386;

 sys_id |  br_id  | stk_id  | vers | lhs_stkid | rhs_stkid 
--------+---------+---------+------+-----------+-----------
 428908 | 2500677 | 1520337 |    1 |   1518811 |   1137386
 430836 | 2500677 | 1520301 |    1 |   1518811 |   1137386
 430837 | 2500677 | 1520301 |    2 |   1518811 |   1137386
 385453 | 2500677 | 1354130 |    1 |   1354129 |   1137386
 396295 | 2500677 | 1415752 |    1 |   1415753 |   1137386
 396296 | 2500677 | 1415752 |    2 |   1415753 |   1137386

The problem: Stack IDs 1520337 and 1520301 are same LHS and RHS items.
             Now, Cyclopath does support multiple link_values for, e.g.,
             private link_values, like ratings and item_watchers, but
             the lhs_stack_id is a tag. So there are two link_values with
             the same tag on an item.

SELECT * from _tag_lv WHERE rhs_stk_id = 1137386;
 sys_id | brn_id  | stk_id  | v | del | rvt |      name      | start_rid | until_rid  | acs | infer | rhs_stk_id | vb | vi | vr | vt | vx | vd 
--------+---------+---------+---+-----+-----+----------------+-----------+------------+-----+-------+------------+----+----+----+----+----+----
 385078 | 2500677 | 1518811 | 1 | f   | f   | bike boulevard |     13837 | 2000000000 |   8 | 0x20  |    1137386 |    |    |    |    |    | 
 385078 | 2500677 | 1518811 | 1 | f   | f   | bike boulevard |     13837 | 2000000000 |   8 | 0x20  |    1137386 |    |    |    |    |    | 
 385078 | 2500677 | 1518811 | 1 | f   | f   | bike boulevard |     13837 | 2000000000 |   8 | 0x20  |    1137386 |    |    |    |    |    | 

SELECT * from _lv_tag WHERE rhs_stk_id = 1137386;
 sys_id | brn_id  | stk_id  | v | del | rvt | start_rid | until_rid  | acs | infer | rhs_stk_id |      tag       | tacs | tinfer 
--------+---------+---------+---+-----+-----+-----------+------------+-----+-------+------------+----------------+------+--------
 430837 | 2500677 | 1520301 | 2 | t   | f   |     14629 | 2000000000 |   9 | 0x0   |    1137386 | bike boulevard |    8 | 0x20
 430836 | 2500677 | 1520301 | 1 | f   | f   |     13993 |      14629 |   9 | 0x0   |    1137386 | bike boulevard |    8 | 0x20
 428908 | 2500677 | 1520337 | 1 | f   | f   |     13995 | 2000000000 |   9 | 0x0   |    1137386 | bike boulevard |    8 | 0x20



SELECT *
FROM _lv_tag AS lvt1
JOIN _lv_tag AS lvt2
   ON (    (lvt1.lhs_stk_id = lvt2.lhs_stk_id)
       AND (lvt1.rhs_stk_id = lvt2.rhs_stk_id)
       AND (lvt1.stk_id < lvt2.stk_id))

--WHERE
--lvt1.lhs_stk_id = 1409158
--AND lvt1. rhs_stk_id = 2538637

ORDER BY
   lvt1.start_rid DESC
   , lvt1.lhs_stk_id
   , lvt1.rhs_stk_id
   , lvt2.lhs_stk_id
   , lvt2.rhs_stk_id

   ;

-- Speed limit attr also duplicated...
SELECT * FROM _lv WHERE lhs_stk_id = 1823216 AND rhs_stk_id = 2538637;



 sys_id  | brn_id  | stk_id  | v | del | rvt | start_rid | until_rid  | acs | infer | lhs_stk_id | rhs_stk_id |      tag       | tacs | tinfer |
 sys_id  | brn_id  | stk_id  | v | del | rvt | start_rid | until_rid  | acs | infer | lhs_stk_id | rhs_stk_id |      tag       | tacs | tinfer 
---------+---------+---------+---+-----+-----+-----------+------------+-----+-------+------------+------------+----------------+------+--------+---------+---------+---------+---+-----+-----+-----------+------------+-----+-------+------------+------------+----------------+------+--------
 1253575 | 2500677 | 2538640 | 1 | f   | f   |     22222 | 2000000000 |   8 | 0x0   |    1409158 |    2538637 | hill           |    8 | 0x20   |
 1253620 | 2500677 | 2538668 | 1 | f   | f   |     22222 | 2000000000 |   8 | 0x20  |    1409158 |    2538637 | hill           |    8 | 0x20


SELECT * FROM _by WHERE stk_id = 2538637;

 sys_id  | brn_id  | stk_id  | v | del | rvt |    name     | start_rid | until_rid  | acs | infer |         len          
---------+---------+---------+---+-----+-----+-------------+-----------+------------+-----+-------+----------------------
 1253572 | 2500677 | 2538637 | 1 | f   | f   | W 31st St S |     22222 | 2000000000 |   8 | 0x20  |                 94.6



SELECT *
FROM _lv AS lv1
JOIN _lv AS lv2
   ON (
          (lv1.lhs_stk_id = lv2.lhs_stk_id)
      AND (lv1.rhs_stk_id = lv2.rhs_stk_id)
      AND (lv1.stk_id < lv2.stk_id)
   )
ORDER BY
     lv1.lhs_stk_id
   , lv1.rhs_stk_id
   , lv2.lhs_stk_id
   , lv2.rhs_stk_id

   ;


-- 88 rows ccpv3_demo / 69 rows ccpv3_live:
SELECT *
FROM _lv AS lv1
JOIN _lv AS lv2
--FROM _lv_tag AS lv1
--JOIN _lv_tag AS lv2
--FROM _lv_attr AS lv1
--JOIN _lv_attr AS lv2
--FROM _lv_annot AS lv1
--JOIN _lv_annot AS lv2
--FROM _lv_post AS lv1
--JOIN _lv_post AS lv2
--FROM _lv_td AS lv1
--JOIN _lv_td AS lv2
   ON (
          (lv1.lhs_stk_id = lv2.lhs_stk_id)
      AND (lv1.rhs_stk_id = lv2.rhs_stk_id)
      AND (lv1.stk_id < lv2.stk_id)
   )
WHERE
       lv1.del IS FALSE AND lv2.del IS FALSE
   AND lv1.until_rid = 2000000000 AND lv2.until_rid = 2000000000
ORDER BY
     lv1.lhs_stk_id
   , lv1.rhs_stk_id
   , lv2.lhs_stk_id
   , lv2.rhs_stk_id

   ;
-- tags (_lv_tag): 2
-- attrs (_lv_attr): 83
-- annots (_lv_annot): 0
-- posts (_lv_post): 3
-- threads (_lv_td): 0

-- This one has three link_values for the same post?
select * from _lv_post where lhs_stk_id = 1558808 and rhs_stk_id = 2498796;
 sys_id | brn_id  | stk_id  | v | del | rvt | start_rid | until_rid  | acs | infer | lhs_stk_id | rhs_stk_id |            post             | aacs | ainfer 
--------+---------+---------+---+-----+-----+-----------+------------+-----+-------+------------+------------+-----------------------------+------+--------
 402877 | 2500677 | 1558809 | 1 | f   | f   |     16113 | 2000000000 |   9 | 0x0   |    1558808 |    2498796 | Hi,\r\rI see you've created |    8 | 0x20
 402878 | 2500677 | 1558810 | 1 | f   | f   |     16113 | 2000000000 |   9 | 0x0   |    1558808 |    2498796 | Hi,\r\rI see you've created |    8 | 0x20
 402879 | 2500677 | 1558811 | 1 | f   | f   |     16113 | 2000000000 |   9 | 0x0   |    1558808 |    2498796 | Hi,\r\rI see you've created |    8 | 0x20



select * from _lv where rhs_stk_id = 1043258;





SELECT
-- *
   lv1.stk_id, lv2.stk_id
   , lv1.lhs_stk_id, lv1.rhs_stk_id
FROM _lv AS lv1
JOIN _lv AS lv2
   ON (
          (lv1.lhs_stk_id = lv2.lhs_stk_id)
      AND (lv1.rhs_stk_id = lv2.rhs_stk_id)
      AND (lv1.stk_id < lv2.stk_id)
   )
JOIN attribute AS attr
   ON (lv1.lhs_stk_id = attr.stack_id)
JOIN item_versioned AS at_iv
   ON (attr.stack_id = at_iv.stack_id)
JOIN item_stack AS at_is
   ON (at_iv.stack_id = at_is.stack_id)
WHERE
   at_iv.valid_until_rid = 2000000000
   AND at_iv.branch_id = 2500677
   AND
   attr.multiple_allowed IS FALSE
   AND
       lv1.until_rid = 2000000000
   AND lv2.until_rid = 2000000000
   AND
       lv1.del = FALSE
   AND lv2.del = FALSE

--AND lv1.lhs_stk_id = 1823216 AND lv1.rhs_stk_id = 2538637

ORDER BY
--     lv1.lhs_stk_id
--   , lv1.rhs_stk_id
--   , lv2.lhs_stk_id
--   , lv2.rhs_stk_id
     lv1.stk_id , lv2.stk_id
   ;
-- 83 rows lvals deleted or not.
-- 83 rows lvals not deleted.

ccpv1_live=> select * from annot_bs where annot_id = 1355571 and byway_id = 1367363;
   id    | version | deleted | annot_id | byway_id | valid_starting_rid | valid_before_rid 
---------+---------+---------+----------+----------+--------------------+------------------
 1367360 |       1 | f       |  1355571 |  1367363 |               3979 |             3980
 1367367 |       1 | f       |  1355571 |  1367363 |               3979 |             3980
 1367360 |       2 | t       |  1355571 |  1367363 |               3980 |       2000000000
 1367367 |       2 | t       |  1355571 |  1367363 |               3980 |       2000000000

ccpv3_demo=> select * from _lv where lhs_stk_id = 1409158 and rhs_stk_id = 2538643;
 sys_id  | brn_id  | stk_id  | v | del | rvt | start_rid | until_rid  | acs | infer | tag | tacs | tinfer | lhs_stk_id | rhs_stk_id | vb | vi | vr | vt | vx | vd 
---------+---------+---------+---+-----+-----+-----------+------------+-----+-------+-----+------+--------+------------+------------+----+----+----+----+----+----
 1253581 | 2500677 | 2538645 | 1 | f   | f   |     22222 | 2000000000 |   8 | 0x0   |     |    8 | 0x0    |    1409158 |    2538643 |    |    |    |    |    | 
 1253621 | 2500677 | 2538669 | 1 | f   | f   |     22222 | 2000000000 |   8 | 0x20  |     |    8 | 0x20   |    1409158 |    2538643 |    |    |    |    |    | 

ccpv3_demo=> select * from _lv_tag where lhs_stk_id = 1409158 and rhs_stk_id = 2538643;
 sys_id  | brn_id  | stk_id  | v | del | rvt | start_rid | until_rid  | acs | infer | lhs_stk_id | rhs_stk_id | tag  | tacs | tinfer 
---------+---------+---------+---+-----+-----+-----------+------------+-----+-------+------------+------------+------+------+--------
 1253581 | 2500677 | 2538645 | 1 | f   | f   |     22222 | 2000000000 |   8 | 0x0   |    1409158 |    2538643 | hill |    8 | 0x20
 1253621 | 2500677 | 2538669 | 1 | f   | f   |     22222 | 2000000000 |   8 | 0x20  |    1409158 |    2538643 | hill |    8 | 0x20


*/


UPDATE group_item_access SET deleted = TRUE WHERE stack_id = 2538714;
UPDATE item_versioned SET deleted = TRUE WHERE stack_id = 2538714;


/* ==================================================================== */
/* Step (4)                                                             */
/* ==================================================================== */

\qecho
\qecho Fixing corrupt geofeature_layer.
\qecho

/* Fix a bug from the CcpV2 upgrade scripts.
   See: 209-geofeat_lyr_majortrail.sql
   */

UPDATE geofeature_layer SET feat_type = 'byway'
   WHERE feat_type = 'byway_alley';

/* ==================================================================== */
/* Step (5)                                                             */
/* ==================================================================== */

\qecho
\qecho Adding split_from_stack_id to link_value table.
\qecho

CREATE FUNCTION cp_user_new_forgiving()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         ALTER TABLE link_value ADD COLUMN split_from_stack_id INTEGER;

      /* ERROR: column "..." of relation "link_value" already exists
         Use EXCEPTION WHEN OTHERS to catch 'em all. */
      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'split_from_stack_id already altered';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_user_new_forgiving();

DROP FUNCTION cp_user_new_forgiving();

/* ==================================================================== */
/* Step (6)                                                             */
/* ==================================================================== */

/* BUG nnnn: FIXME: Or EXPLAIN, if okay: Why aren't these two LINE_STRINGs?

ccpv3_demo=> select id, feat_type, layer_name, geometry_type from geofeature_layer;

 id  |  feat_type  |   layer_name    | geometry_type 
-----+-------------+-----------------+---------------
 105 | route       | default         | POLYGON
 106 | track       | default         | POLYGON

*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


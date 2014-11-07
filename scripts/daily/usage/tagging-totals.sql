/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: ~26 mins. */

BEGIN;

/* Load temp. VIEWs. */
\i /ccp/dev/cp_cron/scripts/daily/usage/ccp_common.sql

-- view for latest revision for each day since tags went live
CREATE TEMPORARY VIEW day_rid AS
SELECT to_char(day_, 'YYYYMMDD') AS day_,max(id)
FROM date_since_live
   LEFT OUTER JOIN revision
      ON (date_since_live.day_ >= date_trunc('day',revision.timestamp))
   WHERE day_ >= '2009-04-29'
      AND date_trunc('day',revision.timestamp) >= '2009-04-29'
GROUP BY day_
ORDER BY day_;

-- view for tag_points that refer to existing points for the dates the
-- tag_points existed (sometimes uses point valid revisions, since tag_points
-- don't seem to be set correctly to deleted when a point is deleted)
/* This is/was a CcpV1 problem. This can probably be deleted:
CREATE TEMPORARY VIEW valid_tag_point AS
SELECT tag_point.id, tag_id, point_id,
       case
       when tag_point.valid_start_rid >=  point.valid_start_rid
          then tag_point.valid_start_rid
       else  point.valid_start_rid
       end as valid_start_rid,
       case
       when tag_point.valid_until_rid <=  point.valid_until_rid
          then tag_point.valid_until_rid
       else  point.valid_until_rid
       end as valid_until_rid
   from tag_point
   left outer join point
   on (point_id = point.id and
       (point.valid_start_rid < tag_point.valid_until_rid
       or point.valid_until_rid > tag_point.valid_start_rid))
   where not tag_point.deleted and not point.deleted;
*/

-- view for total tag applications to points in the system
CREATE TEMPORARY VIEW total_point_tags AS
   SELECT day_, count(lv_stack_id)
   FROM day_rid
   LEFT OUTER JOIN gf_tag
      ON (day_rid.max >= gf_tag.lv_valid_start_rid
          AND day_rid.max <= gf_tag.lv_valid_until_rid)
   WHERE gf_type_id = 14 -- cp_item_type_id('waypoint')
   GROUP BY day_
   ORDER BY day_;

-- view for total number of unique tags on points
CREATE TEMPORARY VIEW unique_point_tags AS
   SELECT DISTINCT
      day_, gf_tag.lhs_stack_id
   FROM day_rid
   LEFT OUTER JOIN gf_tag
      ON (day_rid.max >= gf_tag.lv_valid_start_rid
          AND day_rid.max <= gf_tag.lv_valid_until_rid)
   WHERE gf_type_id = 14 -- cp_item_type_id('waypoint')
   ;

-- view for tag_bs's that refer to existing byways for the dates the tag_bs's
-- existed (using block valid revisions, since tag_bs's don't seem to be set
-- correctly to deleted when a block is deleted)
/* This is/was a CcpV1 problem. This can probably be deleted:
create temp view valid_tag_bs as
select tag_bs.id,tag_id,byway_id,
       case
       when tag_bs.valid_start_rid >=  byway_segment.valid_start_rid
          then tag_bs.valid_start_rid
       else  byway_segment.valid_start_rid
       end as valid_start_rid,
       case
       when tag_bs.valid_until_rid <=  byway_segment.valid_until_rid
          then tag_bs.valid_until_rid
       else  byway_segment.valid_until_rid
       end as valid_until_rid
   from tag_bs
   left outer join byway_segment
   on (byway_id = byway_segment.id and
       (byway_segment.valid_start_rid < tag_bs.valid_until_rid
       or byway_segment.valid_until_rid > tag_bs.valid_start_rid))
   where not tag_bs.deleted and not byway_segment.deleted;
*/

-- view for total tag applications to byways in the system
CREATE TEMPORARY VIEW total_byway_tags AS
   SELECT day_, count(lv_stack_id)
   FROM day_rid
   LEFT OUTER JOIN gf_tag
      ON (day_rid.max >= gf_tag.lv_valid_start_rid
          AND day_rid.max <= gf_tag.lv_valid_until_rid)
   WHERE gf_type_id = 7 -- cp_item_type_id('byway')
   GROUP BY day_
   ORDER BY day_;

-- view for total tag applications to byways excluding initial set
CREATE TEMPORARY VIEW total_byway_nondefault_tags AS
   SELECT day_, count(lv_stack_id)
   FROM day_rid
   LEFT OUTER JOIN gf_tag
      ON (day_rid.max >= gf_tag.lv_valid_start_rid
          AND day_rid.max <= gf_tag.lv_valid_until_rid)
   WHERE gf_type_id = 7 -- cp_item_type_id('byway')
      AND lhs_stack_id NOT IN (SELECT stack_id FROM non_nondefault_tags)
   GROUP BY day_
   ORDER BY day_;

-- view for total number of unique tags on byways
CREATE TEMPORARY VIEW unique_byway_tags AS
   SELECT DISTINCT
      day_, gf_tag.lhs_stack_id
   FROM day_rid
   LEFT OUTER JOIN gf_tag
      ON (day_rid.max >= gf_tag.lv_valid_start_rid
          AND day_rid.max <= gf_tag.lv_valid_until_rid)
   WHERE gf_type_id = 7 -- cp_item_type_id('byway')
   ;

-- VIEWS END --

--begin read only;

-- total tag applications to points in the system
\o tag_apps_points_count.out
-- 2013.04.24: 20 secs. on [lb]'s laptop.
SELECT * FROM total_point_tags;

-- total tag applications to byways in the system
\o tag_apps_byways_count.out
-- FIXME: 2013.04.24: [lb] canceled the request, it was too much (memory use)
SELECT * FROM total_byway_tags;

-- total tag applications to byways excluding initial set
\o tag_apps_nondefault_byways_count.out
-- FIXME: 2013.04.24: [lb] is not going to test this, it's prob. too much.
SELECT * FROM total_byway_nondefault_tags;

-- total tag applications in the system
\o tag_apps_count.out
-- FIXME: 2013.04.24: This request is also too much.
SELECT day_, sum(count)
   FROM
      (SELECT * FROM total_point_tags
      UNION ALL
      SELECT * FROM total_byway_tags) AS all_tag_apps
GROUP BY day_
ORDER BY day_;

-- total nondefault tag applications in the system
\o tag_apps_nondefault_count.out
-- FIXME: 2013.04.24: And this one; it's going to take a lot of memory.
SELECT day_, sum(count)
   FROM
      (SELECT * FROM total_point_tags
      UNION ALL
      SELECT * FROM total_byway_nondefault_tags) AS all_tag_apps
GROUP BY day_
ORDER BY day_;

-- total number of unique tags on points
\o tags_unique_points_count.out
-- 2013.04.24: 20 secs. on [lb]'s laptop.
SELECT day_, count(*)
FROM unique_point_tags
GROUP BY day_
ORDER BY day_;

-- total number of unique tags on byways
\o tags_unique_byways_count.out
-- FIXME: 2013.04.24: Memory-heavy request.
SELECT day_, count(*)
FROM unique_byway_tags
GROUP BY day_
ORDER BY day_;

-- total number of unique tags
\o tags_unique_count.out
-- FIXME: 2013.04.24: Memory-heavy request.
SELECT day_, count(*)
FROM
   (SELECT DISTINCT
       day_, all_unique_tag_apps.lhs_stack_id
       FROM
         (SELECT * FROM unique_point_tags
         UNION ALL
         SELECT * FROM unique_byway_tags
         ) AS all_unique_tag_apps
   ) AS all_distinct
GROUP BY day_
ORDER BY day_;

-- number of byways with tags
\o byways_with_tags_count.out
-- FIXME: 2013.04.24: Memory-heavy request.
--        Like all the other memory-heavy requests, the memory usage
--        stair-climbs at a 45-degree angle until it's all gone...
--        but this doesn't happen with gf_type_id = 14 (waypoint) --
--        so what gives?? Is is the join on day_rid? We should probably iterate
--        once per day rather than trying to do them all at once!
SELECT
   day_,
   sum((ct >= 1)::int),
   sum((ct >= 2)::int),
   sum((ct >= 3)::int),
   sum((ct >= 5)::int),
   sum((ct >= 10)::int)
FROM (SELECT day_, rhs_stack_id, count(*) AS ct
   FROM
      (SELECT DISTINCT
            day_, gf_tag.lhs_stack_id, gf_tag.rhs_stack_id
         FROM day_rid
         LEFT OUTER JOIN gf_tag
            ON (day_rid.max >= gf_tag.lv_valid_start_rid
                AND day_rid.max <= gf_tag.lv_valid_until_rid)
         WHERE gf_type_id = 7 -- cp_item_type_id('byway')
       ) AS distinct_tag_bs
   GROUP BY day_, rhs_stack_id
   ) AS tag_counts
GROUP BY day_
ORDER BY day_;

-- number of points with tags
\o points_with_tags_count.out
SELECT
   day_,
   sum((ct >= 1)::int),
   sum((ct >= 2)::int),
   sum((ct >= 3)::int),
   sum((ct >= 5)::int),
   sum((ct >= 10)::int)
FROM
   (SELECT day_, rhs_stack_id, count(*) AS ct
   FROM
      (SELECT DISTINCT
            day_, gf_tag.lhs_stack_id, gf_tag.rhs_stack_id
         FROM day_rid
         LEFT OUTER JOIN gf_tag
            ON (day_rid.max >= gf_tag.lv_valid_start_rid
                AND day_rid.max <= gf_tag.lv_valid_until_rid)
         WHERE gf_type_id = 14 -- cp_item_type_id('waypoint')
       ) AS distinct_tag_bs
   GROUP BY day_, rhs_stack_id
   ) AS tag_counts
GROUP BY day_
ORDER BY day_;

/* Reset \o */
\o

ROLLBACK;


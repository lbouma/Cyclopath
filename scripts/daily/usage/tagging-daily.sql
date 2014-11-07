/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: ~ 1 min. */

-- This scripts analyses daily tagging applications.

BEGIN;

/* Load temp. VIEWs. */
\i /ccp/dev/cp_cron/scripts/daily/usage/ccp_common.sql

CREATE TEMPORARY VIEW gf_tag_days AS
   SELECT
      date_trunc('day', timestamp) AS day_,
      gf_type_id,
      count(*) AS ct
   FROM gf_tag
   GROUP BY day_, gf_type_id;

-- view for tag applications to byways per day
CREATE TEMPORARY VIEW byway_tag_apps AS
   SELECT
      to_char(dates.day_, 'YYYYMMDD'),
      COALESCE(ct, 0)
   FROM date_since_live AS dates
   LEFT OUTER JOIN (
      SELECT * FROM gf_tag_days
      WHERE gf_type_id = 7 -- cp_item_type_id('byway')
      ) AS tag_bs
   ON (dates.day_ = tag_bs.day_)
   WHERE dates.day_ > '2009-04-29'
ORDER BY dates.day_;

-- view for tag applications to points per day
CREATE TEMPORARY VIEW point_tag_apps AS
   SELECT
      to_char(dates.day_, 'YYYYMMDD'),
      COALESCE(ct, 0)
   FROM date_since_live AS dates
   LEFT OUTER JOIN (
      SELECT * FROM gf_tag_days
      WHERE gf_type_id = 14 -- cp_item_type_id('waypoint')
      ) AS tag_bs
   ON (dates.day_ = tag_bs.day_)
   WHERE dates.day_ > '2009-04-29'
ORDER BY dates.day_;

-- view for nondefault tags
-- view for tag applications to byways per day excluding non default tags
CREATE TEMPORARY VIEW byway_nondefault_tag_apps AS
   SELECT
      to_char(dates.day_, 'YYYYMMDD'),
      COALESCE(ct, 0)
   FROM date_since_live AS dates
   LEFT OUTER JOIN (
      SELECT
         date_trunc('day', timestamp) AS day_,
         gf_type_id,
         count(*) AS ct
      FROM gf_tag
      WHERE gf_type_id = 7 -- cp_item_type_id('byway')
         AND lhs_stack_id NOT IN (SELECT stack_id FROM non_nondefault_tags)
      GROUP BY day_, gf_type_id
      ) AS tag_bs
   ON (dates.day_ = tag_bs.day_)
   WHERE dates.day_ > '2009-04-29'
ORDER BY dates.day_;

-- BEGIN READ ONLY;

-- tag applications per day

\o tag_apps_daily.out
SELECT to_char, sum(coalesce)
   FROM
      (SELECT * FROM byway_tag_apps
      UNION ALL
      SELECT * FROM point_tag_apps) AS all_apps
GROUP BY to_char
ORDER BY to_char;

-- tag applications per day excluding initial set

\o tag_apps_nondefault_daily.out
SELECT to_char,sum(coalesce)
   FROM
      (SELECT * FROM byway_nondefault_tag_apps
      UNION ALL
      SELECT * FROM point_tag_apps) AS all_apps
GROUP BY to_char
ORDER BY to_char;
  
-- tag applications to byways per day

\o tag_apps_byways_daily.out
SELECT * FROM byway_tag_apps;

-- tag applications to points per day

\o tag_apps_points_daily.out
SELECT * FROM point_tag_apps;

/* Reset \o */
\o

ROLLBACK;


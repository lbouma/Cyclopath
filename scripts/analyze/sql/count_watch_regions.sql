/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN;

/* Load temp. VIEWs. */
\i ../../daily/usage/ccp_common.sql

/* MAYBE: Use an _inline plpgsql fcn., like count_ratings.sql, so we don't
          have to use inline cp_*() fcns in the WHERE clause, which is slow.
          */
CREATE TEMPORARY VIEW watched_regions AS
   SELECT
      gia.stack_id
      , gia.group_id
   FROM link_value AS lv
   JOIN item_versioned AS iv
      ON (lv.system_id = iv.system_id)
   JOIN attribute AS attr
      ON (lv.lhs_stack_id = attr.stack_id)
   JOIN group_item_access AS gia
      ON (lv.system_id = gia.item_id)
   WHERE
      attr.value_internal_name = '/item/alert_email'
      AND iv.valid_until_rid = cp_rid_inf()
      AND NOT iv.deleted
      AND gia.link_rhs_type_id = cp_item_type_id('region')
      AND gia.group_id NOT IN (SELECT group_id FROM devs_user_ids)
      ;

SELECT
   to_char(now(), 'YYYYMMDD:HH24:MI:SS') AS now,
   (SELECT count(*) FROM watched_regions)
      AS region_ct,
   sum((ct >= 1)::int) AS user_r1_ct,
   sum((ct >= 2)::int) AS user_r2_ct,
   sum((ct >= 3)::int) AS user_r3_ct,
   sum((ct >= 5)::int) AS user_r5_ct,
   sum((ct >= 10)::int) AS user_r10_ct,
   sum((ct >= 25)::int) AS user_r25_ct
   FROM (
      SELECT count(*) AS ct
      FROM watched_regions
      GROUP BY group_id
   ) AS foo;

ROLLBACK;


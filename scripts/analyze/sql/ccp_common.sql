/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2014.09.18: Script time: < 1 min. */

/* Don't ignore _userscored usernames.
   All but one are dont_study -- the _user_anon_instance
   user isn't, and it's group_id is something we want, too.
   Same with all the usernames that include 'test': they
   are all marked don_t study.
      No: WHERE ... u.username LIKE E'\\_%'
   */

CREATE TEMPORARY VIEW real_user_ids AS
   SELECT DISTINCT(gm.group_id)
   FROM group_membership AS gm
   JOIN user_ AS u
      ON (gm.user_id = u.id)
   JOIN group_ AS gr
      ON (gm.group_id = gr.stack_id)
   WHERE
      gr.access_scope_id = 1 -- cp_access_scope_id('private')
      AND NOT u.dont_study;

CREATE TEMPORARY VIEW devs_user_ids AS
   SELECT DISTINCT(gm.group_id)
   FROM group_membership AS gm
   JOIN user_ AS u
      ON (gm.user_id = u.id)
   JOIN group_ AS gr
      ON (gm.group_id = gr.stack_id)
   WHERE
      gr.access_scope_id = 1 -- cp_access_scope_id('private')
      AND u.dont_study;

CREATE TEMPORARY VIEW byway AS
   SELECT
      gia.stack_id
      , gia.group_id
      , gf.geofeature_layer_id
   FROM geofeature AS gf
   JOIN item_versioned AS iv
      ON (gf.system_id = iv.system_id)
   JOIN group_item_access AS gia
      ON (gf.system_id = gia.item_id)
   WHERE
      iv.valid_until_rid = cp_rid_inf()
      AND NOT iv.deleted
      AND gia.item_type_id = cp_item_type_id('byway')
      ;

CREATE TEMPORARY VIEW user_rating AS
   SELECT * FROM byway_rating
   WHERE
      /* System users. */
      username NOT LIKE E'\\_%'
      /* Ratings saved during lab study for CSCW 2008. */
      AND username NOT LIKE E'^test%';

CREATE TEMPORARY VIEW _gf AS
   SELECT
      gia.stack_id
      , gia.group_id
      , gia.item_type_id
      , gf.geofeature_layer_id
   FROM geofeature AS gf
   JOIN item_versioned AS iv
      ON (gf.system_id = iv.system_id)
   JOIN group_item_access AS gia
      ON (gf.system_id = gia.item_id)
   WHERE
      iv.valid_until_rid = cp_rid_inf()
      AND NOT iv.deleted
      ;

CREATE TEMPORARY VIEW gf_tag AS
   SELECT
      lv.stack_id AS lv_stack_id,
      lv.lhs_stack_id AS lhs_stack_id,
      lv.rhs_stack_id AS rhs_stack_id,
      lv_iv.valid_start_rid AS lv_valid_start_rid,
      lv_iv.valid_until_rid AS lv_valid_until_rid,
      gf_gia.item_type_id AS gf_type_id,
      revision.timestamp
   FROM link_value AS lv
   JOIN item_versioned AS lv_iv
      ON (lv.system_id = lv_iv.system_id)
   JOIN group_item_access AS lv_gia
      ON (lv.system_id = lv_gia.item_id)
   JOIN tag AS tag
      ON (lv.lhs_stack_id = tag.stack_id)
   JOIN geofeature AS gf
      ON (lv.rhs_stack_id = gf.stack_id)
   JOIN item_versioned AS gf_iv
      ON (gf.system_id = gf_iv.system_id)
   JOIN group_item_access AS gf_gia
      ON (gf.system_id = gf_gia.item_id)
   LEFT OUTER JOIN revision
      ON lv_iv.valid_start_rid = revision.id
   WHERE
      lv_gia.group_id NOT IN (SELECT group_id FROM devs_user_ids)
      AND NOT lv_iv.deleted
      AND NOT gf_iv.deleted;

/* EXPLAIN: What are "nondefault tags"?
            Is this tag list incomplete (like, needs 'bike lane') or
            is this list specifically like this for a reason? */
/* FIXME: In tagging-totals.sql in CcpV1, there was one list with five
          tags listed, and in tagging-daily.sql there was a list with
          just three entries. (hill and prohibited being the diff.) Hmm. */
CREATE TEMPORARY VIEW nondefault_tags AS
   SELECT tag.stack_id FROM tag
   JOIN item_versioned AS tag_iv
      USING (system_id)
   WHERE 
      tag_iv.name NOT IN (
         'bikelane',
         'unpaved',
         'closed',
         'hill',
         'prohibited'
         )
      AND valid_until_rid = cp_rid_inf();
CREATE TEMPORARY VIEW non_nondefault_tags AS
   SELECT tag.stack_id FROM tag
   JOIN item_versioned AS tag_iv
      USING (system_id)
   WHERE 
      tag_iv.name IN (
         'bikelane',
         'unpaved',
         'closed',
         'hill',
         'prohibited'
         )
      AND valid_until_rid = cp_rid_inf();


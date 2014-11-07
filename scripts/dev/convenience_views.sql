/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/*

   Usage:

    psql -U cycling ccpv3_test < /ccp/dev/cp/scripts/dev/convenience_views.sql
    psql -U cycling ccpv3_lite < /ccp/dev/cp/scripts/dev/convenience_views.sql

   */

\qecho
\qecho Adding convenient Cyclopath table views.
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

-- DEVs: Make sure your search_path is set appropriately.

/* ==================================================================== */
/* Public instance                                                      */
/* ==================================================================== */

/* C.f. mapserver/tilecache_update.py */

DROP VIEW IF EXISTS public.tiles_mapserver_zoom_view;
CREATE VIEW public.tiles_mapserver_zoom_view AS SELECT
   skin_name               AS skn
   --, ccp_branch_id       AS
   --, ccp_group_id        AS
   , zoom_level            AS zm
   , geofeature_layer_id   AS gfl
   , do_draw               AS drw
   , pen_color_s           AS dr_clrs
   , pen_color_i           AS dr_clri
   , pen_width             AS dwi
   , pen_gutter            AS dgu
   , do_shadow             AS shd
   , shadow_width          AS shw
   , shadow_color_s        AS sh_clrs
   , shadow_color_i        AS sh_clri
   , do_label              AS lbl
   , label_size            AS lbs
   , label_color_s         AS lb_clrs
   , label_color_i         AS lb_clri
   , labelo_width          AS low
   , labelo_color_s        AS lo_clrs
   , labelo_color_i        AS lo_clri
   , l_bold                AS lbld
   , l_force               AS lfor
   , l_partials            AS lpar
   , l_outlinewidth        AS lolw
   , l_minfeaturesize      AS lmfz
   , l_restrict_named      AS lrst
   , l_restrict_stack_ids  AS lrsd
   , l_strip_trail_suffix  AS lstr
   , l_only_bike_facils    AS loly
   , p_min                 AS pmin
   , p_new                 AS pnew
   , d_geom_len            AS dlen
   , d_geom_area           AS drea
   , l_geom_len            AS llen
   , l_geom_area           AS lrea
FROM
   public.tiles_mapserver_zoom
ORDER BY
   skin_name ASC
   , zoom_level ASC
   , geofeature_layer_id DESC
   ;

/* ==================================================================== */
/* ${INSTANCE} instance                                                 */
/* ==================================================================== */

\qecho
\qecho (Re-)Making item views.
\qecho

/* ITEM TABLE VIEW: Item_Versioned. */

DROP VIEW IF EXISTS _iv;
CREATE OR REPLACE VIEW _iv AS
   SELECT
      iv.system_id                     AS    sys_id
      , iv.branch_id                   AS    brn_id
      , iv.stack_id                    AS    stk_id
      , iv.version                     AS         v
      , iv.deleted                     AS         d
      , iv.reverted                    AS         r
      , SUBSTRING(iv.name FOR 40)      AS       nom
      , iv.valid_start_rid             AS     start
      , CASE WHEN iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE iv.valid_until_rid::TEXT END
                                       AS     until
      , iv_is.access_style_id          AS         a
      , '0x' || to_hex(iv_is.access_infer_id::INT)
                                       AS       nfr
   FROM item_versioned AS iv
   LEFT OUTER JOIN item_stack AS iv_is
      ON (iv.stack_id = iv_is.stack_id)
   ORDER BY
      iv.stack_id ASC
      , iv.version DESC
   ;

/* ITEM TABLE VIEW: Item_Revisionless. */

DROP VIEW IF EXISTS _ir;
CREATE OR REPLACE VIEW _ir AS
   SELECT
      ir.system_id                     AS    sys_id
      , ir.branch_id                   AS    brn_id
      , ir.stack_id                    AS    stk_id
      , ir.version                     AS         v
      , ir.acl_grouping                AS         g
      , iv.deleted                     AS         d
      , iv.reverted                    AS         r
      , SUBSTRING(iv.name FOR 40)      AS       nom
      , iv.valid_start_rid             AS     start
      , CASE WHEN iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE iv.valid_until_rid::TEXT END
                                       AS     until
      , iv_is.access_style_id          AS         a
      , '0x' || to_hex(iv_is.access_infer_id::INT)
                                       AS       nfr
      , TO_CHAR(ir.edited_date, 'YY.MM.DD|HH24:MI')
                                       AS edited_date
      , CASE WHEN ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE ir.edited_user END
                                       AS      unom
      , ir.edited_addr                 AS      addr
      , ir.edited_host                 AS      host
      , ir.edited_what                 AS      what
   FROM item_revisionless AS ir
   LEFT OUTER JOIN item_versioned AS iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS iv_is
      ON (iv_is.stack_id = ir.stack_id)
   ORDER BY
      --ir.stack_id DESC
      --, ir.version DESC
      --, ir.acl_grouping DESC
      ir.edited_date DESC
   ;

DROP VIEW IF EXISTS _ir2;
CREATE OR REPLACE VIEW _ir2 AS
   SELECT
      ir.system_id                     AS    sys_id
      , ir.branch_id                   AS    brn_id
      , ir.stack_id                    AS    stk_id
      , ir.version                     AS         v
      , ir.acl_grouping                AS         g
      , iv.deleted                     AS         d
      , iv.reverted                    AS         r
      , SUBSTRING(iv.name FOR 40)      AS       nom
      , iv.valid_start_rid             AS     start
      , CASE WHEN iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE iv.valid_until_rid::TEXT END
                                       AS     until
      , iv_is.access_style_id          AS         a
      , '0x' || to_hex(iv_is.access_infer_id::INT)
                                       AS       nfr
      , TO_CHAR(ir.edited_date, 'YY.MM.DD|HH24:MI')
                                       AS edited_date
      , CASE WHEN ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE ir.edited_user END
                                       AS      unom
      , ir.edited_addr                 AS      addr
      , ir.edited_host                 AS      host
      , ir.edited_what                 AS      what
   FROM item_revisionless AS ir
   LEFT OUTER JOIN item_versioned AS iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS iv_is
      ON (iv_is.stack_id = ir.stack_id)
   ORDER BY
      ir.stack_id DESC
      , ir.version DESC
      , ir.acl_grouping DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* ITEM TABLE VIEW: Branch. */

DROP VIEW IF EXISTS _br;
CREATE OR REPLACE VIEW _br AS
   SELECT
      br_iv.system_id                  AS    sys_id
      , br_iv.branch_id                AS    brn_id
      , br_iv.stack_id                 AS    stk_id
      , br_iv.version                  AS         v
      , br_iv.deleted                  AS         d
      , br_iv.reverted                 AS         r
      , SUBSTRING(br_iv.name FOR 40)   AS       nom
      , br_iv.valid_start_rid          AS     start
      , CASE WHEN br_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE br_iv.valid_until_rid::TEXT END
                                       AS     until
      , br_is.access_style_id          AS         a
      , '0x' || to_hex(br_is.access_infer_id::INT)
                                       AS       nfr
      , br.parent_id                   AS   par_sid
      , br.last_merge_rid              AS   mrg_rid
      , br.conflicts_resolved          AS      xcon
      , '...' || SUBSTRING(br.import_callback
                  FROM LENGTH(br.import_callback) - 15)
                                       AS import_callback
      , '...' || SUBSTRING(br.export_callback
                  FROM LENGTH(br.export_callback) - 15)
                                       AS export_callback
      , br.tile_skins                  AS     skins
      -- , br.coverage_area            AS   covrage
      , to_char(ST_Area(br.coverage_area),
                'FM999999999999999D9') AS area
   FROM branch AS br
   LEFT OUTER JOIN item_versioned AS br_iv
        USING (system_id)
   LEFT OUTER JOIN item_stack AS br_is
        ON (br_iv.stack_id = br_is.stack_id)
   ORDER BY
      br_iv.stack_id ASC
      , br_iv.version DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* ITEM TABLE VIEW: Annotation. */

DROP VIEW IF EXISTS _annot;
DROP VIEW IF EXISTS _an;
CREATE OR REPLACE VIEW _an AS
   SELECT
      an_iv.system_id                  AS       sys_id
      , an_iv.branch_id                AS       brn_id
      , an_iv.stack_id                 AS       stk_id
      , an_iv.version                  AS            v
      , an_iv.deleted                  AS            d
      , an_iv.reverted                 AS            r
      , SUBSTRING(an_iv.name FOR 40)   AS          nom
      , an_iv.valid_start_rid          AS        start
      , CASE WHEN an_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE an_iv.valid_until_rid::TEXT END
                                       AS        until
      , an_is.access_style_id          AS            a
      , '0x' || to_hex(an_is.access_infer_id::INT)
                                       AS   nfr
      , SUBSTRING(annot.comments FOR 50) AS   comments
   FROM annotation AS annot
   LEFT OUTER JOIN item_versioned AS an_iv
        USING (system_id)
   LEFT OUTER JOIN item_stack AS an_is
        ON (an_iv.stack_id = an_is.stack_id)
   -- ORDER BY
   --    an_iv.stack_id ASC
   --    , an_iv.version DESC
   ;

/* ITEM TABLE VIEW: Attribute. */

DROP VIEW IF EXISTS _attr;
DROP VIEW IF EXISTS _at;
CREATE OR REPLACE VIEW _at AS
   SELECT
      at_iv.system_id                  AS        sys_id
      , at_iv.branch_id                AS        brn_id
      , at_iv.stack_id                 AS        stk_id
      , at_iv.version                  AS             v
      , at_iv.deleted                  AS             d
      , at_iv.reverted                 AS             r
      , SUBSTRING(at_iv.name FOR 40)   AS           nom
      , at_iv.valid_start_rid          AS         start
      , CASE WHEN at_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE at_iv.valid_until_rid::TEXT END
                                       AS         until
      , at_is.access_style_id          AS             a
      , '0x' || to_hex(at_is.access_infer_id::INT)
                                       AS           nfr
      , attr.value_internal_name       AS internal_name
      , attr.spf_field_name            AS    field_name
      , attr.value_type                AS         vtype
      , attr.value_hints               AS         vhint
      , attr.value_units               AS         vunit
      , attr.value_minimum             AS          vmin
      , attr.value_maximum             AS          vmax
      , attr.value_stepsize            AS        vssize
      , attr.gui_sortrank              AS       sortrnk
      , attr.applies_to_type_id        AS   apply_ttype
      , attr.uses_custom_control       AS   uses_custom
      , attr.value_restraints          AS        vrstrn
      , attr.multiple_allowed          AS       mult_ok
      , attr.is_directional            AS        is_dir
   FROM attribute AS attr
   LEFT OUTER JOIN item_versioned AS at_iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS at_is
      ON (at_iv.stack_id = at_is.stack_id)
   -- ORDER BY
   --    at_iv.stack_id ASC
   --    , at_iv.version DESC
   ;

/* ITEM TABLE VIEW: Tag. */

/* MAYBE: It'd be nice to maybe display usage count...
          would have to join link_value and item_versioned
          and get latest rev, non-deleted items for
          branch... */

DROP VIEW IF EXISTS _tag;
DROP VIEW IF EXISTS _tg;
CREATE OR REPLACE VIEW _tg AS
   SELECT
      tg_iv.system_id                  AS       sys_id
      , tg_iv.branch_id                AS       brn_id
      , tg_iv.stack_id                 AS       stk_id
      , tg_iv.version                  AS            v
      , tg_iv.deleted                  AS            d
      , tg_iv.reverted                 AS            r
      , SUBSTRING(tg_iv.name FOR 40)   AS          nom
      -- , tg_iv.tsvect_name           AS       tsvect
      , tg_iv.valid_start_rid          AS        start
      , CASE WHEN tg_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE tg_iv.valid_until_rid::TEXT END
                                       AS        until
      , tg_is.access_style_id          AS            a
      , '0x' || to_hex(tg_is.access_infer_id::INT)
                                       AS          nfr
   FROM tag AS tag
   LEFT OUTER JOIN item_versioned AS tg_iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS tg_is
      ON (tg_iv.stack_id = tg_is.stack_id)
   ORDER BY
      tg_iv.name ASC
   ;

/* ITEM TABLE VIEW: Post. */

DROP VIEW IF EXISTS _po;
CREATE OR REPLACE VIEW _po AS
   SELECT
      po_iv.system_id                  AS        sys_id
      , po_iv.branch_id                AS        brn_id
      , po_iv.stack_id                 AS        stk_id
      , po_iv.version                  AS             v
      , po_iv.deleted                  AS             d
      , po_iv.reverted                 AS             r
      , SUBSTRING(po_iv.name FOR 40)   AS           nom
      , po_iv.valid_start_rid          AS         start
      , CASE WHEN po_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE po_iv.valid_until_rid::TEXT END
                                       AS         until
      , po_is.access_style_id          AS             a
      , '0x' || to_hex(po_is.access_infer_id::INT)
                                       AS           nfr
      , po.thread_stack_id             AS           thd
      , SUBSTRING(po.body FOR 40)      AS           bod
      , po.polarity                    AS           pol
      -- , po.tsvect_body              AS        tsvect
      , TO_CHAR(po_ir.edited_date, 'YYYY.MM.DD|HH24:MI')
                                       AS          edte
      , CASE WHEN po_ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE po_ir.edited_user END
                                       AS          unom
      , po_ir.edited_addr              AS          addr
      , po_ir.edited_host              AS          host
      , po_ir.edited_what              AS          what
      , td.system_id                   AS        td_sys
      , td.branch_id                   AS        td_brn
      , td.stack_id                    AS        td_stk
      , td.version                     AS          td_v
      , td_iv.deleted                  AS          td_d
      , td_iv.reverted                 AS          td_r
      , SUBSTRING(td_iv.name FOR 40)   AS        td_nom
      , td_iv.valid_start_rid          AS      td_start
      , CASE WHEN td_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE td_iv.valid_until_rid::TEXT END
                                       AS      td_until
      , td_is.access_style_id          AS          td_a
      , '0x' || to_hex(td_is.access_infer_id::INT)
                                       AS        td_nfr
      , td.ttype                       AS         ttype
      , td.thread_type_id              AS         typid
   FROM post AS po
   LEFT OUTER JOIN item_revisionless AS po_ir
      ON (po.system_id = po_ir.system_id
          AND po_ir.acl_grouping = 1)
   LEFT OUTER JOIN item_versioned AS po_iv
      ON (po.system_id = po_iv.system_id)
   LEFT OUTER JOIN item_stack AS po_is
      ON (po_iv.stack_id = po_is.stack_id)
   /* CAVEAT/MAYBE: You get (# of posts) * (# of thread versions) rows
                    because we're select ordering by thread version desc
                    and distincting on stack_id, version, acl_grouping. */
   LEFT OUTER JOIN thread AS td
      ON (po.thread_stack_id = td.stack_id)
   LEFT OUTER JOIN item_revisionless AS td_ir
      ON (td.system_id = td_ir.system_id
          AND td_ir.acl_grouping = 1)
   LEFT OUTER JOIN item_versioned AS td_iv
      ON (td.system_id = td_iv.system_id)
   LEFT OUTER JOIN item_stack AS td_is
      ON (td_iv.stack_id = td_is.stack_id)
   ORDER BY
        td_ir.stack_id DESC
      , td_ir.version DESC
      , td_ir.acl_grouping DESC
      , po_ir.stack_id DESC
      , po_ir.version DESC
      , po_ir.acl_grouping DESC
   ;

/* ITEM TABLE VIEW: Thread. */

DROP VIEW IF EXISTS _td;
CREATE OR REPLACE VIEW _td AS
   SELECT
      td.system_id                     AS        sys_id
      , td.branch_id                   AS        brn_id
      , td.stack_id                    AS        stk_id
      , td.version                     AS             v
      , td_iv.deleted                  AS             d
      , td_iv.reverted                 AS             r
      , SUBSTRING(td_iv.name FOR 40)   AS           nom
      , td_iv.valid_start_rid          AS         start
      , CASE WHEN td_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE td_iv.valid_until_rid::TEXT END
                                       AS         until
      , td_is.access_style_id          AS             a
      , '0x' || to_hex(td_is.access_infer_id::INT)
                                       AS           nfr
      , td.ttype                       AS         ttype
      , td.thread_type_id              AS         typid
      , TO_CHAR(td_ir.edited_date, 'YYYY.MM.DD|HH24:MI')
                                       AS edited_date
      , CASE WHEN td_ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE td_ir.edited_user END
                                       AS edited_user
      , td_ir.edited_addr              AS edited_addr
      , td_ir.edited_host              AS edited_host
      , td_ir.edited_what              AS edited_what
   FROM thread AS td
   LEFT OUTER JOIN item_revisionless AS td_ir
      ON (td.system_id = td_ir.system_id
          AND td_ir.acl_grouping = 1)
   LEFT OUTER JOIN item_versioned AS td_iv
      ON (td.system_id = td_iv.system_id)
   LEFT OUTER JOIN item_stack AS td_is
      ON (td_iv.stack_id = td_is.stack_id)
   ORDER BY
      --  td_ir.branch_id ASC
      --, td_ir.stack_id DESC
      --, td_ir.version DESC
      --, td_ir.acl_grouping DESC
      td_ir.edited_date DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* ITEM TABLE VIEW: Link_Value. */

/* FIXME: Need a good view for link_value, which shows lhs type and
          name, etc.
          For now, we make special views, but it'd be nice to have
          a one-size-fits-all view. */

DROP VIEW IF EXISTS _lv;
CREATE OR REPLACE VIEW _lv AS
   SELECT
      lv_iv.system_id                  AS       sys_id
      , lv_iv.branch_id                AS       brn_id
      , lv_iv.stack_id                 AS       stk_id
      , lv_iv.version                  AS            v
      , lv_iv.deleted                  AS            d
      , lv_iv.reverted                 AS            r
      --, SUBSTRING(lv_iv.name FOR 40) AS          nom
      , lv_iv.valid_start_rid          AS        start
      , CASE WHEN lv_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE lv_iv.valid_until_rid::TEXT END
                                       AS        until
      --, SUBSTRING(lv_iv.name FOR 50) AS          nom
      , lv_is.access_style_id          AS            a
      , '0x' || to_hex(lv_is.access_infer_id::INT)
                                       AS          nfr
      , lval.lhs_stack_id              AS          lhs
      , lval.rhs_stack_id              AS          rhs
      , lval.value_boolean             AS           vb
      , lval.value_integer             AS           vi
      , lval.value_real                AS           vr
      , lval.value_text                AS           vt
      , lval.value_binary              AS           vx
      , lval.value_date                AS           vd
   FROM link_value AS lval
   LEFT OUTER JOIN item_versioned AS lv_iv
      ON (lval.system_id = lv_iv.system_id)
   LEFT OUTER JOIN item_stack AS lv_is
      ON (lv_iv.stack_id = lv_is.stack_id)
   ORDER BY
      lv_iv.stack_id ASC
      , lv_iv.version DESC
   ;

/* ITEM TABLE VIEW: Tag-Link_Value. */

DROP VIEW IF EXISTS _tag_lv;
DROP VIEW IF EXISTS _tg_lv;
CREATE OR REPLACE VIEW _tg_lv AS
   SELECT
      tg_iv.system_id                  AS       sys_id
      , tg_iv.branch_id                AS       brn_id
      , tg_iv.stack_id                 AS       stk_id
      , tg_iv.version                  AS            v
      , tg_iv.deleted                  AS            d
      , tg_iv.reverted                 AS            r
      , SUBSTRING(tg_iv.name FOR 40)   AS          nom
      -- , tg_iv.tsvect_name           AS       tsvect
      , tg_iv.valid_start_rid          AS        start
      , CASE WHEN tg_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE tg_iv.valid_until_rid::TEXT END
                                       AS        until
      , tg_is.access_style_id          AS            a
      , '0x' || to_hex(tg_is.access_infer_id::INT)
                                       AS          nfr
      , tg_lv.rhs_stack_id             AS   rhs_stk_id
      --, tg_lv.value_boolean          AS           vb
      --, tg_lv.value_integer          AS           vi
      --, tg_lv.value_real             AS           vr
      --, tg_lv.value_text             AS           vt
      --, tg_lv.value_binary           AS           vx
      --, tg_lv.value_date             AS           vd
   FROM tag AS tag
   LEFT OUTER JOIN item_versioned AS tg_iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS tg_is
      ON (tg_iv.stack_id = tg_is.stack_id)
   LEFT OUTER JOIN link_value AS tg_lv
      ON (tg_lv.lhs_stack_id = tag.stack_id)
   ORDER BY
      tg_iv.name ASC
   --    tg_iv.stack_id ASC
   --    , tg_iv.version DESC
   ;

/* ITEM TABLE VIEW: Link_Value-Tag. */

DROP VIEW IF EXISTS _lv_tag;
DROP VIEW IF EXISTS _lv_tg;
CREATE OR REPLACE VIEW _lv_tg AS
   SELECT
      lv_iv.system_id                  AS       sys_id
      , lv_iv.branch_id                AS       brn_id
      , lv_iv.stack_id                 AS       stk_id
      , lv_iv.version                  AS            v
      , lv_iv.deleted                  AS            d
      , lv_iv.reverted                 AS            r
      --, SUBSTRING(lv_iv.name FOR 40) AS          nom
      , lv_iv.valid_start_rid          AS        start
      , CASE WHEN lv_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE lv_iv.valid_until_rid::TEXT END
                                       AS        until
      , lv_is.access_style_id          AS            a
      , '0x' || to_hex(lv_is.access_infer_id::INT)
                                       AS          nfr
      , tg_lv.lhs_stack_id             AS          lhs
      , tg_lv.rhs_stack_id             AS          rhs
      --, SUBSTRING(tag.name FOR 50)   AS          tag
      , SUBSTRING(tg_iv.name FOR 50)   AS          tag
      , tg_is.access_style_id          AS         tacs
      , '0x' || to_hex(tg_is.access_infer_id::INT)
                                       AS       tinfer
   FROM link_value AS tg_lv
   LEFT OUTER JOIN item_versioned AS lv_iv
      ON (tg_lv.system_id = lv_iv.system_id)
   LEFT OUTER JOIN item_stack AS lv_is
      ON (lv_iv.stack_id = lv_is.stack_id)
   JOIN tag AS tag
      ON (tg_lv.lhs_stack_id = tag.stack_id)
   LEFT OUTER JOIN item_versioned AS tg_iv
      ON (tag.system_id = tg_iv.system_id)
   LEFT OUTER JOIN item_stack AS tg_is
      ON (tg_iv.stack_id = tg_is.stack_id)
   ORDER BY
      tg_iv.name ASC
      , lv_iv.stack_id ASC
      , lv_iv.version DESC
   ;

/* ITEM TABLE VIEW: Link_Value-Attribute. */

DROP VIEW IF EXISTS _lv_attr;
DROP VIEW IF EXISTS _lv_at;
CREATE OR REPLACE VIEW _lv_at AS
   SELECT
      lv_iv.system_id                  AS       sys_id
      , lv_iv.branch_id                AS       brn_id
      , lv_iv.stack_id                 AS       stk_id
      , lv_iv.version                  AS            v
      , lv_iv.deleted                  AS            d
      , lv_iv.reverted                 AS            r
      --, SUBSTRING(lv_iv.name FOR 40) AS          nom
      , lv_iv.valid_start_rid          AS        start
      , CASE WHEN lv_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE lv_iv.valid_until_rid::TEXT END
                                       AS        until
      , lv_is.access_style_id          AS            a
      , '0x' || to_hex(lv_is.access_infer_id::INT)
                                       AS          nfr
      , at_lv.lhs_stack_id             AS          lhs
      , at_lv.rhs_stack_id             AS          rhs
      , SUBSTRING(attr.value_internal_name FOR 50)
                                       AS         attr
      , at_is.access_style_id          AS         aacs
      , '0x' || to_hex(at_is.access_infer_id::INT)
                                       AS         anfr
      , at_lv.value_boolean            AS           vb
      , at_lv.value_integer            AS           vi
      , at_lv.value_real               AS           vr
      , at_lv.value_text               AS           vt
      , at_lv.value_binary             AS           vx
      , at_lv.value_date               AS           vd
   FROM link_value AS at_lv
   LEFT OUTER JOIN item_versioned AS lv_iv
      ON (at_lv.system_id = lv_iv.system_id)
   LEFT OUTER JOIN item_stack AS lv_is
      ON (lv_iv.stack_id = lv_is.stack_id)
   JOIN attribute AS attr
      ON (at_lv.lhs_stack_id = attr.stack_id)
   LEFT OUTER JOIN item_versioned AS at_iv
      ON (attr.system_id = at_iv.system_id)
   LEFT OUTER JOIN item_stack AS at_is
      ON (at_iv.stack_id = at_is.stack_id)
   ORDER BY
      attr.value_internal_name ASC
      , lv_iv.stack_id ASC
      , lv_iv.version DESC
   ;

/* ITEM TABLE VIEW: Link_Value-Annotation. */

DROP VIEW IF EXISTS _lv_annot;
DROP VIEW IF EXISTS _lv_an;
CREATE OR REPLACE VIEW _lv_an AS
   SELECT
      lv_iv.system_id                  AS       sys_id
      , lv_iv.branch_id                AS       brn_id
      , lv_iv.stack_id                 AS       stk_id
      , lv_iv.version                  AS            v
      , lv_iv.deleted                  AS            d
      , lv_iv.reverted                 AS            r
      --, SUBSTRING(lv_iv.name FOR 40) AS          nom
      , lv_iv.valid_start_rid          AS        start
      , CASE WHEN lv_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE lv_iv.valid_until_rid::TEXT END
                                       AS        until
      , lv_is.access_style_id          AS            a
      , '0x' || to_hex(lv_is.access_infer_id::INT)
                                       AS          nfr
      , at_lv.lhs_stack_id             AS          lhs
      , at_lv.rhs_stack_id             AS          rhs
      , SUBSTRING(annot.comments FOR 50) AS      annot
      , at_is.access_style_id          AS         aacs
      , '0x' || to_hex(at_is.access_infer_id::INT)
                                       AS         anfr
   FROM link_value AS at_lv
   LEFT OUTER JOIN item_versioned AS lv_iv
      ON (at_lv.system_id = lv_iv.system_id)
   LEFT OUTER JOIN item_stack AS lv_is
      ON (lv_iv.stack_id = lv_is.stack_id)
   JOIN annotation AS annot
      ON (at_lv.lhs_stack_id = annot.stack_id)
   LEFT OUTER JOIN item_versioned AS at_iv
      ON (annot.system_id = at_iv.system_id)
   LEFT OUTER JOIN item_stack AS at_is
      ON (at_iv.stack_id = at_is.stack_id)
   ORDER BY
      lv_iv.stack_id ASC
      , lv_iv.version DESC
   ;

/* ITEM TABLE VIEW: Link_Value-Post. */

DROP VIEW IF EXISTS _lv_post;
DROP VIEW IF EXISTS _lv_po;
CREATE OR REPLACE VIEW _lv_po AS
   SELECT
      lv_iv.system_id                  AS       sys_id
      , lv_iv.branch_id                AS       brn_id
      , lv_iv.stack_id                 AS       stk_id
      , lv_iv.version                  AS            v
      , lv_iv.deleted                  AS            d
      , lv_iv.reverted                 AS            r
      --, SUBSTRING(lv_iv.name FOR 40) AS          nom
      , lv_iv.valid_start_rid          AS        start
      , CASE WHEN lv_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE lv_iv.valid_until_rid::TEXT END
                                       AS        until
      , lv_is.access_style_id          AS            a
      , '0x' || to_hex(lv_is.access_infer_id::INT)
                                       AS          nfr
      , at_lv.lhs_stack_id             AS          lhs
      , at_lv.rhs_stack_id             AS          rhs
      , SUBSTRING(post.body FOR 25)    AS         post
      -- , post.polarity               AS     polarity
      , at_is.access_style_id          AS         aacs
      , '0x' || to_hex(at_is.access_infer_id::INT)
                                       AS         anfr
   FROM link_value AS at_lv
   LEFT OUTER JOIN item_versioned AS lv_iv
      ON (at_lv.system_id = lv_iv.system_id)
   LEFT OUTER JOIN item_stack AS lv_is
      ON (lv_iv.stack_id = lv_is.stack_id)
   JOIN post AS post
      ON (at_lv.lhs_stack_id = post.stack_id)
   LEFT OUTER JOIN item_versioned AS at_iv
      ON (post.system_id = at_iv.system_id)
   LEFT OUTER JOIN item_stack AS at_is
      ON (at_iv.stack_id = at_is.stack_id)
   ORDER BY
      lv_iv.stack_id ASC
      , lv_iv.version DESC
   ;

/* ITEM TABLE VIEW: Link_Value-Thread. */

DROP VIEW IF EXISTS _lv_td;
CREATE OR REPLACE VIEW _lv_td AS
   SELECT
      lv_iv.system_id                  AS       sys_id
      , lv_iv.branch_id                AS       brn_id
      , lv_iv.stack_id                 AS       stk_id
      , lv_iv.version                  AS            v
      , lv_iv.deleted                  AS            d
      , lv_iv.reverted                 AS            r
      --, SUBSTRING(lv_iv.name FOR 40) AS          nom
      , lv_iv.valid_start_rid          AS        start
      , CASE WHEN lv_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE lv_iv.valid_until_rid::TEXT END
                                       AS        until
      , lv_is.access_style_id          AS            a
      , '0x' || to_hex(lv_is.access_infer_id::INT)
                                       AS          nfr
      , at_lv.lhs_stack_id             AS          lhs
      , at_lv.rhs_stack_id             AS          rhs
      , at_is.access_style_id          AS         aacs
      , '0x' || to_hex(at_is.access_infer_id::INT)
                                       AS         anfr
      -- , td.ttype
      -- , td.thread_type_id
   FROM link_value AS at_lv
   LEFT OUTER JOIN item_versioned AS lv_iv
      ON (at_lv.system_id = lv_iv.system_id)
   LEFT OUTER JOIN item_stack AS lv_is
      ON (lv_iv.stack_id = lv_is.stack_id)
   JOIN thread AS td
      ON (at_lv.lhs_stack_id = td.stack_id)
   LEFT OUTER JOIN item_versioned AS at_iv
      ON (td.system_id = at_iv.system_id)
   LEFT OUTER JOIN item_stack AS at_is
      ON (at_iv.stack_id = at_is.stack_id)
   ORDER BY
      lv_iv.stack_id ASC
      , lv_iv.version DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* ITEM TABLE VIEW: Geofeature. */

/* FIXME: Geofeature views. */

/* ITEM TABLE VIEW: Byway. */

DROP VIEW IF EXISTS _by;
CREATE OR REPLACE VIEW _by AS
   SELECT
      by_iv.system_id                  AS       sys_id
      , by_iv.branch_id                AS       brn_id
      , by_iv.stack_id                 AS       stk_id
      , by_iv.version                  AS            v
      , by_iv.deleted                  AS            d
      , by_iv.reverted                 AS            r
      , SUBSTRING(by_iv.name FOR 40)   AS          nom
      -- , by_iv.tsvect_name           AS       tsvect
      , by_iv.valid_start_rid          AS        start
      , CASE WHEN by_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE by_iv.valid_until_rid::TEXT END
                                       AS        until
      , by_is.access_style_id          AS            a
      , '0x' || to_hex(by_is.access_infer_id::INT)
                                       AS          nfr
      , to_char(ST_Length(by_.geometry),
                'FM999999999999999D9') AS          len
      , by_.geofeature_layer_id        AS          gfl
      , by_.z                          AS            z
      , by_.beg_node_id                AS       beg_nd
      , by_.fin_node_id                AS       fin_nd
      , by_.is_disconnected            AS         disc
      , by_.split_from_stack_id        AS          spl
      , by_.one_way                    AS           ow
   FROM geofeature AS by_
   LEFT OUTER JOIN item_versioned AS by_iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS by_is
      ON (by_iv.stack_id = by_is.stack_id)
   --LEFT OUTER JOIN group_item_access AS by_gia
   --   ON (by_iv.system_id = by_gia.system_id)
   WHERE
      -- MAGIC_NUMBER: Item_Type.BYWAY == 7.
      -- (Postgres fcns. in WHERE clauses are slow, so
      --  use MAGIC_NUMBER and not cp_item_type().)
      -- --by_gia.item_type_id = 7
      -- by_gia.item_type_id = (
      --    SELECT id FROM item_type WHERE type_name='byway')
      by_.geofeature_layer_id IN
         (SELECT id FROM geofeature_layer WHERE feat_type = 'byway')
   ORDER BY
      by_iv.stack_id DESC
      , by_iv.branch_id DESC
      , by_iv.version DESC
   ;

/* ITEM TABLE VIEW: Region. */

DROP VIEW IF EXISTS _reg;
DROP VIEW IF EXISTS _rg;
CREATE OR REPLACE VIEW _rg AS
   SELECT
      reg_iv.system_id                 AS       sys_id
      , reg_iv.branch_id               AS       brn_id
      , reg_iv.stack_id                AS       stk_id
      , reg_iv.version                 AS            v
      , reg_iv.deleted                 AS            d
      , reg_iv.reverted                AS            r
      , SUBSTRING(reg_iv.name FOR 40)  AS          nom
      , reg_iv.valid_start_rid          AS       start
      , CASE WHEN reg_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE reg_iv.valid_until_rid::TEXT END
                                       AS        until
      , reg_is.access_style_id         AS            a
      , '0x' || to_hex(reg_is.access_infer_id::INT)
                                       AS          nfr
      , reg_.z                         AS            z
      , to_char(ST_Area(reg_.geometry),
                'FM999999999999999D9') AS         area
   FROM geofeature AS reg_
   LEFT OUTER JOIN item_versioned AS reg_iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS reg_is
      ON (reg_iv.stack_id = reg_is.stack_id)
   WHERE
      reg_.geofeature_layer_id IN
         (SELECT id FROM geofeature_layer WHERE feat_type = 'region')
   ORDER BY
      --reg_iv.name ASC
      reg_iv.stack_id ASC
      , reg_iv.version DESC
   ;

/* ITEM TABLE VIEW: Waypoint. */

DROP VIEW IF EXISTS _wp;
CREATE OR REPLACE VIEW _wp AS
   SELECT
      wpt_iv.system_id                 AS       sys_id
      , wpt_iv.branch_id               AS       brn_id
      , wpt_iv.stack_id                AS       stk_id
      , wpt_iv.version                 AS            v
      , wpt_iv.deleted                 AS            d
      , wpt_iv.reverted                AS            r
      , SUBSTRING(wpt_iv.name FOR 40)  AS          nom
      , wpt_iv.valid_start_rid         AS        start
      , CASE WHEN wpt_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE wpt_iv.valid_until_rid::TEXT END
                                       AS        until
      , wpt_is.access_style_id         AS            a
      , '0x' || to_hex(wpt_is.access_infer_id::INT)
                                       AS          nfr
      -- Skipping: geometry
      , St_AsText(wpt_.geometry)       AS         geom
   FROM geofeature AS wpt_
   LEFT OUTER JOIN item_versioned AS wpt_iv
      USING (system_id)
   LEFT OUTER JOIN item_stack AS wpt_is
      ON (wpt_iv.stack_id = wpt_is.stack_id)
   WHERE
      wpt_.geofeature_layer_id IN
         (SELECT id FROM geofeature_layer WHERE feat_type = 'waypoint')
   ORDER BY
      wpt_iv.stack_id ASC
      , wpt_iv.version DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* TABLE VIEW: Revision. */

/* The SUBSTRING on DATE_TRUNC is a hack: 16 is all chars up to the :seconds,
   since DATE_TRUNC doesn't really truncate in the string, in that it just
   changes values to 0. And there's not another string function to help us.
   So just use our vast counting skills and truncate the string at said count.
   */
DROP VIEW IF EXISTS _rev;
CREATE OR REPLACE VIEW _rev AS
   SELECT
      rev.id                           AS id
      /* NOTE: "timestamp" is a special value, so naming "tstamp". */
      , SUBSTRING(DATE_TRUNC('minute', rev.timestamp)::TEXT FOR 16)
                                       AS tstamp
      , rev.host                       AS host
      /* NOTE: "user" is a special value, so naming "unom". */
      , rev.username                   AS unom
      -- , rev.comment                 AS comment
      , SUBSTRING(rev.comment FOR 30)
                                       AS comment
      -- , rev.bbox                    AS bbox
      -- , rev.geosummary              AS geosummary
      -- , rev.geometry                AS geometry
      , to_char(ST_Perimeter(rev.bbox), 'FM999999999999999D9')
                                       AS bbox_perim
      , to_char(ST_Perimeter(rev.geosummary), 'FM999999999999999D9')
                                       AS gsum_perim
      , to_char(ST_Perimeter(rev.geometry), 'FM999999999999999D9')
                                       AS geom_perim
      -- , rev.permission              AS _prm -- DEPRECATED
      -- , rev.visibility              AS _vis -- DEPRECATED
      , rev.branch_id                  AS br_id
      , rev.is_revertable              AS rvtok
      , rev.reverted_count             AS rvtct
      , rev.msecs_holding_lock         AS lcktm
      , rev.alert_on_activity          AS alrt
   FROM
      revision AS rev
   ORDER BY
      rev.id DESC
   ;

/* TABLE VIEW: Group Revision. */

DROP VIEW IF EXISTS _grev;
CREATE OR REPLACE VIEW _grev AS
   SELECT
      rev.id                           AS id
      , SUBSTRING(
         DATE_TRUNC('minute', rev.timestamp)::TEXT
            FOR 16)                    AS tstamp
    --, rev.host                       AS host
      , rev.username                   AS unom
      , gr.name                        AS gnom
      , gr.stack_id                    AS grid
      , SUBSTRING(rev.comment FOR 30)
                                       AS comment
      -- , rev.permission              AS _prm -- DEPRECATED
      -- , rev.visibility              AS _vis -- DEPRECATED
      , rev.branch_id                  AS br_id
      , rev.is_revertable              AS rvtok
      , rev.reverted_count             AS rvtct
      , rev.msecs_holding_lock         AS lcktm
      , rev.alert_on_activity          AS alrt
      /* group_revision: */
      , grev.visible_items             AS n_vis
      , grev.is_revertable             AS ok_rvt
      -- Skipping: grev.date_created, which is same as rev.timestamp.
      -- Ignore grev.bbox and grev.geosummary and just show deets about geom.
      , to_char(ST_Perimeter(grev.geometry), 'FM999999999999999D9')
                                       AS grev_geom
   FROM group_revision AS grev
   LEFT OUTER JOIN group_ AS gr
      ON (grev.group_id = gr.stack_id)
   LEFT OUTER JOIN revision AS rev
      ON (rev.id = grev.revision_id)
   WHERE
   --     gr.valid_start_rid <= grev.revision_id
   -- AND gr.valid_until_rid > grev.revision_id
          gr.valid_start_rid <= grev.revision_id
      AND grev.revision_id < gr.valid_until_rid
   ORDER BY
      rev.id DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* TABLE VIEW: Node Endpoint. */

DROP VIEW IF EXISTS _nde;
CREATE OR REPLACE VIEW _nde AS
   SELECT
      nde.system_id                    AS       sys_id
      , nde.branch_id                  AS       brn_id
      , nde.stack_id                   AS       stk_id
      , nde.version                    AS            v
      , nde.reference_n                AS        ref_n
      , nde.referencers                AS       refers
      , nde.elevation_m                AS       elev_m
      , nde.dangle_okay                AS  dangle_okay
      , nde.a_duex_rues                AS  a_duex_rues
      , nde_iv.deleted                 AS            d
      , nde_iv.reverted                AS            r
      --, nde_iv.name                  AS          nom
      , nde_iv.valid_start_rid         AS        start
      , CASE WHEN nde_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE nde_iv.valid_until_rid::TEXT END
                                       AS        until
      , St_AsText(nxy.endpoint_xy)     AS        nd_xy
   FROM node_endpoint AS nde
   LEFT OUTER JOIN item_versioned AS nde_iv
      USING (system_id)
   LEFT OUTER JOIN node_endpt_xy AS nxy
      ON (nde.stack_id = nxy.node_stack_id)
   ORDER BY
      nde.stack_id DESC
      , nde.branch_id DESC
      , nde.version DESC
   ;

/* TABLE VIEW: Node Byway. */

DROP VIEW IF EXISTS _nby;
CREATE OR REPLACE VIEW _nby AS
   SELECT
      _nby.id                          AS           id
      , _nby.branch_id                 AS       brn_id
      , _nby.node_stack_id             AS    nd_stk_id
      , _nby.byway_stack_id            AS    by_stk_id
      , St_AsText(_nby.node_vertex_xy) AS        nd_xy
   FROM
      node_byway AS _nby
   ORDER BY
      _nby.node_stack_id DESC
      , _nby.byway_stack_id DESC
      , _nby.branch_id DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* TABLE VIEW: Group Item Access. */

DROP VIEW IF EXISTS _gia;
CREATE OR REPLACE VIEW _gia AS
   SELECT
      gia.item_id                      AS sys_id
      , gia.branch_id                  AS brn_id
      , gia.stack_id                   AS stk_id
      , gia.version                    AS v
      , gia.deleted                    AS d
      , gia.reverted                   AS r
      , gia.name                       AS nom
      , gia.group_id                   AS grp_id
      , group_.name                    AS grp_name
      , gia.access_level_id            AS a
      , gia.acl_grouping               AS g
      , gia.valid_start_rid            AS start
      , CASE WHEN gia.valid_until_rid = 2000000000
        THEN 'inf' ELSE gia.valid_until_rid::TEXT END
                                       AS until
      , gia.item_type_id               AS it
      , item_type.type_name            AS ityp
   -- , gia.item_layer_id              AS lyr
   -- , gfl.layer_name                 AS lnom
      , gia.link_lhs_type_id           AS lt
      , gia.link_rhs_type_id           AS rt
   -- , gia.tsvect_name                AS tsvnom
      , gia.session_id                 AS sessid
   FROM
      group_item_access AS gia
   LEFT OUTER JOIN
      group_ ON (gia.group_id = group_.stack_id)
   LEFT OUTER JOIN
      item_type ON (gia.item_type_id = item_type.id)

   -- 2013.08.06: item_layer_id is deprecated; nothing uses it.
   --LEFT OUTER JOIN
   --   geofeature_layer AS gfl
   --   ON (gia.item_layer_id = gfl.id)

   ORDER BY
      gia.stack_id DESC
      , gia.version DESC
      , gia.acl_grouping DESC
      , gia.group_id ASC
   ;

/* TABLE VIEW: New Item Policy. */

DROP VIEW IF EXISTS nip;
DROP VIEW IF EXISTS _nip;
CREATE OR REPLACE VIEW _nip AS
   SELECT
      -- system_id
      stack_id
      , branch_id
      --, version AS v
      -- MAYBE: Join to get group name.
      , group_id
      , name
      , access_style_id AS a_sty
      -- SYNC_ME: Search: Access Style IDs.
      , CASE access_style_id
         WHEN 0 THEN 'nothingset'
         WHEN 1 THEN 'all_access'
         WHEN 2 THEN 'permissive'
         WHEN 3 THEN 'restricted'
         WHEN 4 THEN '_reserved1'
         WHEN 5 THEN 'pub_choice'
         WHEN 6 THEN 'usr_choice'
         WHEN 7 THEN 'usr_editor'
         WHEN 8 THEN 'pub_editor'
         WHEN 9 THEN 'all_denied'
         ELSE 'UNKNOWN' END
            AS a_sty_nom
      , super_acl AS sup_a
      , target_item_type_id AS typ_id
      , (SELECT type_name FROM item_type WHERE id = target_item_type_id)
         AS typ_nom
      -- NOT USED: , target_item_layer AS typ_lr
      , link_left_type_id AS l_typ
      -- NOT USED: , link_left_stack_id AS l_sid
      , link_left_min_access_id AS l_acl
      , link_right_type_id AS r_typ
      -- NOT USED: , link_right_stack_id AS r_sid
      , link_right_min_access_id AS r_acl
      , processing_order AS rank
      , stop_on_match AS stop
   FROM
      new_item_policy
   WHERE
      valid_until_rid = cp_rid_inf()
      AND NOT deleted
      AND NOT reverted
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* TABLE VIEW: Route. */

DROP VIEW IF EXISTS _rt;
CREATE OR REPLACE VIEW _rt AS
   SELECT
        rt.system_id                   AS sys_id
      , rt.branch_id                   AS brn_id
      , rt.stack_id                    AS stk_id
      , rt.version                     AS v
      , rt_ir.acl_grouping             AS g
      , rt_iv.deleted                  AS d -- del
      , rt_iv.reverted                 AS r -- rvt
      , SUBSTRING(rt_iv.name FOR 24)   AS nom
      , rt_iv.valid_start_rid          AS start
      , CASE WHEN rt_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE rt_iv.valid_until_rid::TEXT END
                                       AS until
      , rt_is.access_style_id          AS a
      , '0x' || to_hex(rt_is.access_infer_id::INT)
                                       AS nfr
      --, rt_is.cloned_from_id         AS cln_id
      --, rt_is.stealth_secret         AS is_stlsct
      , SUBSTRING(rt.beg_addr FOR 15)  AS beg_addr
      --, rt.beg_nid                     AS beg_nid
      , SUBSTRING(rt.fin_addr FOR 15)  AS fin_addr
      --, rt.fin_nid                     AS fin_nid
      , rt.n_steps                     AS nst -- n_steps
      , rt.rsn_len                     AS len -- rsn_len
      --, rt.rsn_min                     AS rsn_min
      --, rt.rsn_max                     AS rsn_max
      , rt.travel_mode                 AS tmd -- tx_md
      , rt_ps.p1_priority              AS p1p -- p1_pri
      , rt_ps.p2_depart_at             AS p2d -- p2_dprt
      , rt_ps.p2_transit_pref          AS p2p -- p2_pref
      , rt_ps.p3_weight_type           AS p3t -- p3_wtype
      , rt_ps.p3_burden_pump           AS p3b -- p3_burd
      , rt_ps.p3_spalgorithm           AS p3s -- p3_spalg
      , rt_ps.p3_rating_pump           AS p3r -- p3_ratg
      , rt_ps.p3_weight_attr           AS p3w -- p3_wattr
      , rt_ps.tags_use_defaults        AS tgd -- tag_defs
      , SUBSTRING(rt.details FOR 16)   AS deets
      , TO_CHAR(rt_ir.edited_date, 'YYYY.MM.DD|HH24:MI')
                                       AS edited_date
      , CASE WHEN rt_ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE rt_ir.edited_user END
                                       AS edited_user
      , rt_ir.edited_addr              AS edited_addr
      , rt_ir.edited_host              AS edited_host
      , rt_ir.edited_what              AS edited_what
   FROM route AS rt
   LEFT OUTER JOIN item_revisionless AS rt_ir
      ON (rt.system_id = rt_ir.system_id
          AND rt_ir.acl_grouping = 1)
   LEFT OUTER JOIN item_versioned AS rt_iv
      ON (rt.system_id = rt_iv.system_id)
   LEFT OUTER JOIN item_stack AS rt_is
      ON (rt.stack_id = rt_is.stack_id)
   LEFT OUTER JOIN route_parameters AS rt_ps
      ON (rt.stack_id = rt_ps.route_stack_id)
   ORDER BY
        rt_ir.branch_id ASC
      , rt_ir.stack_id DESC
      , rt_ir.version DESC
      , rt_ir.acl_grouping DESC
   ;
/*
   For the _rt view, we left outer join all the secondary tables,
   so we expect to see as many rows in route as in the view.
   Doing a count ensures we're doing it right -- and, indeed,
   [lb] originally forgot the WHERE acl_grouping=1, and the
   counts made me notice.

      SELECT COUNT(*) FROM route;
       count  
      --------
       141799

      SELECT COUNT(*) FROM _rt;
       count  
      --------
       141799

   You can also remove the 'left outer's to test that every route
   has an entry in each of the secondary tables. Here are the counts:

      INNER JOIN item_revisionless: 141799
      INNER JOIN item_versioned: 141799
      INNER JOIN item_stack: 141799
      INNER JOIN route_parameters: 141799
      All good!

   --------------------------------------------------------------

   Also, note that CcpV1 has about 4 to 5 times as many routes as
   were really requested, because it cloned a route whenever it
   was edited, auto-updated (which happened for every view!), or
   had its permissions altered.

*/

/* ITEM TABLE VIEW: route (1). */

DROP VIEW IF EXISTS _rt1;
CREATE OR REPLACE VIEW _rt1 AS
   SELECT
        rt.system_id                   AS sys_id
      --, rt.branch_id                   AS brn_id
      , rt.stack_id                    AS stk_id
      , rt.version                     AS v
      , rt_ir.acl_grouping             AS g
      , rt_iv.deleted                  AS d -- del
      , rt_iv.reverted                 AS r -- rvt
      , SUBSTRING(rt_iv.name FOR 23)   AS nom
      , rt_iv.valid_start_rid          AS start
      , CASE WHEN rt_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE rt_iv.valid_until_rid::TEXT END
                                       AS until
      , rt_is.access_style_id          AS a
      , '0x' || to_hex(rt_is.access_infer_id::INT)
                                       AS nfr
      ----, rt_is.cloned_from_id         AS cln_id
      ----, rt_is.stealth_secret         AS is_stlsct
      --, SUBSTRING(rt.beg_addr FOR 10)  AS beg_addr
      ----, rt.beg_nid                     AS beg_nid
      --, SUBSTRING(rt.fin_addr FOR 10)  AS fin_addr
      ----, rt.fin_nid                     AS fin_nid
      , rt.n_steps                     AS nstps -- n_steps
      , (rt.rsn_len / 1000.0)::INTEGER AS kliks
      ----, rt.rsn_min                     AS rsn_min
      ----, rt.rsn_max                     AS rsn_max
      , rt.travel_mode                 AS txm -- tx_md
      /*
      , rt_ps.p1_priority              AS p1p -- p1_pri
      , rt_ps.p2_depart_at             AS p2d -- p2_dprt
      , rt_ps.p2_transit_pref          AS p2p -- p2_pref
      , rt_ps.p3_weight_type           AS p3t -- p3_wtype
      , rt_ps.p3_burden_pump           AS p3b -- p3_burd
      , rt_ps.p3_spalgorithm           AS p3s -- p3_spalg
      , rt_ps.p3_rating_pump           AS p3r -- p3_ratg
      , rt_ps.p3_weight_attr           AS p3w -- p3_wattr
      , rt_ps.tags_use_defaults        AS tgd -- tag_defs
      */
      , SUBSTRING(rt.details FOR 5)    AS deets
      , TO_CHAR(rt_ir.edited_date, 'YY.MM.DD|HH24:MI')
                                       AS edited_date
      , CASE WHEN rt_ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE rt_ir.edited_user END
                                       AS edited_user
      , rt_ir.edited_addr              AS edited_addr
      , rt_ir.edited_host              AS edited_host
      , rt_ir.edited_what              AS edited_what
   FROM route AS rt
   LEFT OUTER JOIN item_revisionless AS rt_ir
      ON (rt.system_id = rt_ir.system_id
          AND rt_ir.acl_grouping = 1)
   LEFT OUTER JOIN item_versioned AS rt_iv
      ON (rt.system_id = rt_iv.system_id)
   LEFT OUTER JOIN item_stack AS rt_is
      ON (rt.stack_id = rt_is.stack_id)
   LEFT OUTER JOIN route_parameters AS rt_ps
      ON (rt.stack_id = rt_ps.route_stack_id)
   ORDER BY
        rt_ir.branch_id ASC
      , rt_ir.stack_id DESC
      , rt_ir.version DESC
      , rt_ir.acl_grouping DESC
   ;

/* ITEM TABLE VIEW: route (2). */

DROP VIEW IF EXISTS _rt2;
CREATE OR REPLACE VIEW _rt2 AS
   SELECT
        rt.system_id                   AS sys_id
      --, rt.branch_id                   AS brn_id
      , rt.stack_id                    AS stk_id
      , rt.version                     AS v
      , rt_ir.acl_grouping             AS g
      , rt_iv.deleted                  AS d -- del
      --, rt_iv.reverted                 AS r -- rvt
      , SUBSTRING(rt_iv.name FOR 23)   AS nom
      /*
      , rt_iv.valid_start_rid          AS start
      , CASE WHEN rt_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE rt_iv.valid_until_rid::TEXT END
                                       AS until
      , rt_is.access_style_id          AS acs
      , '0x' || to_hex(rt_is.access_infer_id::INT)
                                       AS nfr
      --, rt_is.cloned_from_id         AS cln_id
      --, rt_is.stealth_secret         AS is_stlsct
      */
      , SUBSTRING(rt.beg_addr FOR 10)  AS beg_addr
      ----, rt.beg_nid                     AS beg_nid
      , SUBSTRING(rt.fin_addr FOR 10)  AS fin_addr
      ----, rt.fin_nid                     AS fin_nid
      , rt.n_steps                     AS nst -- n_steps
      , rt.rsn_len                     AS len -- rsn_len
      ----, rt.rsn_min                     AS rsn_min
      ----, rt.rsn_max                     AS rsn_max
      , rt.travel_mode                 AS txm -- tx_md
      , rt_ps.p1_priority              AS p1p -- p1_pri
      , CASE WHEN ((rt_ps.p2_depart_at IS NOT NULL)
                   AND (rt_ps.p2_depart_at <> ''))
                  THEN 'X' ELSE '' END AS p2d -- p2_dprt
      , rt_ps.p2_transit_pref          AS p2p -- p2_pref
      , rt_ps.p3_weight_type           AS p3t -- p3_wtype
      , rt_ps.p3_burden_pump           AS p3b -- p3_burd
      , rt_ps.p3_spalgorithm           AS p3s -- p3_spalg
      , rt_ps.p3_rating_pump           AS p3r -- p3_ratg
      , SUBSTRING(rt_ps.p3_weight_attr FOR 10)
                                       AS p3w -- p3_wattr
      , rt_ps.tags_use_defaults        AS tgd -- tag_defs
      --, SUBSTRING(rt.details FOR 5)    AS deets
      , TO_CHAR(rt_ir.edited_date, 'YY.MM.DD|HH24:MI')
                                       AS edited_date
      , CASE WHEN rt_ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE rt_ir.edited_user END
                                       AS edited_user
      /*
      , rt_ir.edited_addr              AS edited_addr
      , rt_ir.edited_host              AS edited_host
      , rt_ir.edited_what              AS edited_what
      */
   FROM route AS rt
   LEFT OUTER JOIN item_revisionless AS rt_ir
      ON (rt.system_id = rt_ir.system_id
          AND rt_ir.acl_grouping = 1)
   LEFT OUTER JOIN item_versioned AS rt_iv
      ON (rt.system_id = rt_iv.system_id)
   LEFT OUTER JOIN item_stack AS rt_is
      ON (rt.stack_id = rt_is.stack_id)
   LEFT OUTER JOIN route_parameters AS rt_ps
      ON (rt.stack_id = rt_ps.route_stack_id)
   ORDER BY
        rt_ir.branch_id ASC
      , rt_ir.stack_id DESC
      , rt_ir.version DESC
      , rt_ir.acl_grouping DESC
   ;

/* ITEM TABLE VIEW: route_step. */

DROP VIEW IF EXISTS _rt_step;
CREATE OR REPLACE VIEW _rt_step AS
   SELECT
      route_id AS rt_id
      , route_stack_id AS rt_stk_id
      , route_version AS rt_v
      , step_number AS step_n
      , byway_id AS by_id
      , byway_stack_id AS by_stk_id
      , byway_version AS by_v
      , SUBSTRING(step_name FOR 40) AS rs_nom
      , forward AS fwd
      , beg_time AS beg_tm
      , fin_time AS fin_tm
      , CASE travel_mode
         WHEN 0 THEN 'undefined'
         WHEN 1 THEN 'bicycle'
         WHEN 2 THEN 'transit'
         WHEN 3 THEN 'walking'
         WHEN 4 THEN 'autocar'
         ELSE 'UNKNOWN' END
            AS tx_mode
      , ST_Length(transit_geometry)::BIGINT AS tx_geom_len
      , ST_Area(ST_Box2D(transit_geometry))::BIGINT AS tx_geom_area
   FROM
      route_step
   ORDER BY
      route_id ASC
      , route_stack_id ASC
      , route_version ASC
      , step_number ASC
   ;

/* ITEM TABLE VIEW: route_step. */

DROP VIEW IF EXISTS _rt_stop;
CREATE OR REPLACE VIEW _rt_stop AS
   SELECT
      route_id AS rt_id
      , route_stack_id AS rt_stk_id
      , route_version AS rt_v
      , stop_number AS stop_n
      , SUBSTRING(name FOR 40) AS rs_nom
      , x AS x
      , y AS y
      , node_id AS nd_id
      , is_transit_stop AS txstop
      , is_pass_through AS pthru
      , internal_system_id AS int_sid
      , external_result AS ext_res
   FROM
      route_stop
   ORDER BY
      route_id ASC
      , route_stack_id ASC
      , route_version ASC
      , stop_number ASC
   ;

/* ITEM TABLE VIEW: routed_ports. */

DROP VIEW IF EXISTS _ports;
CREATE OR REPLACE VIEW _ports AS
   SELECT
      instance AS long___instance
      , branch_id AS branch_id
      , routed_pers AS pX
      , purpose AS purpose
      , port AS port
      , ready AS ready
      , pid AS pid
      , last_modified AS start_time
   FROM
      routed_ports
   ORDER BY
      instance ASC
      , branch_id ASC
      , routed_pers DESC
      , purpose ASC
      , port ASC
      , ready DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* TABLE VIEW: Track. */

DROP VIEW IF EXISTS _tr;
CREATE OR REPLACE VIEW _tr AS
   SELECT
        tr.system_id                   AS sys_id
      , tr.branch_id                   AS brn_id
      , tr.stack_id                    AS stk_id
      , tr.version                     AS v
      , tr_ir.acl_grouping             AS g
      , tr_iv.deleted                  AS d -- del
      , tr_iv.reverted                 AS r -- rvt
      , SUBSTRING(tr_iv.name FOR 24)   AS nom
      , tr_iv.valid_start_rid          AS start
      , CASE WHEN tr_iv.valid_until_rid = 2000000000
        THEN 'inf' ELSE tr_iv.valid_until_rid::TEXT END
                                       AS until
      , tr_is.access_style_id          AS a
      , '0x' || to_hex(tr_is.access_infer_id::INT)
                                       AS nfr
      --, tr_is.cloned_from_id         AS cln_id
      --, tr_is.stealth_secret         AS is_stlsct
      , SUBSTRING(tr.comments FOR 16)  AS comments
      , TO_CHAR(tr_ir.edited_date, 'YYYY.MM.DD|HH24:MI')
                                       AS edited_date
      , CASE WHEN tr_ir.edited_user LIKE '_user_anon_%'
             THEN '_anon' ELSE tr_ir.edited_user END
                                       AS edited_user
      , tr_ir.edited_addr              AS edited_addr
      , tr_ir.edited_host              AS edited_host
      , tr_ir.edited_what              AS edited_what
   FROM track AS tr
   LEFT OUTER JOIN item_revisionless AS tr_ir
      ON (tr.system_id = tr_ir.system_id
          AND tr_ir.acl_grouping = 1)
   LEFT OUTER JOIN item_versioned AS tr_iv
      ON (tr.system_id = tr_iv.system_id)
   LEFT OUTER JOIN item_stack AS tr_is
      ON (tr.stack_id = tr_is.stack_id)
   ORDER BY
        tr_ir.branch_id ASC
      , tr_ir.stack_id DESC
      , tr_ir.version DESC
      , tr_ir.acl_grouping DESC
   ;
/*
   See comments above, for route. We're just checking that we
   made intermediate table rows for every track row.

      SELECT COUNT(*) FROM track;
       count  
      --------
       

      SELECT COUNT(*) FROM _tr;
       count  
      --------
       

      INNER JOIN item_revisionless: 
      INNER JOIN item_versioned: 
      INNER JOIN item_stack: 
      INNER JOIN route_parameters: 
      All good!

*/

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* ITEM TABLE VIEW: tiles_cache_byway_cluster. */

DROP VIEW IF EXISTS _tclust;
CREATE OR REPLACE VIEW _tclust AS
   SELECT
      branch_id AS brn_id,
      cluster_id AS c_id,
      cluster_name AS cluster_name,
      byway_count AS bway_cnt,
      winningest_gfl_id AS gfl_id,
      winningest_bike_facil AS bk_fac,
      is_cycle_route AS cyc_rt,
      label_priority AS lbl_pri,
      ST_Length(geometry)::BIGINT AS geom_len,
      ST_Area(ST_Box2D(geometry))::BIGINT AS geom_area
   FROM
      tiles_cache_byway_cluster
   ORDER BY
      --geom_len DESC
      geom_area DESC
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

/* ITEM TABLE VIEW: state_cities. */

DROP VIEW IF EXISTS public._mncities;
CREATE OR REPLACE VIEW public._mncities AS
   SELECT
      state_city_id AS c_id
      , state_name AS state
      , municipal_name AS municipal_name
      , mun_id AS m_id
      , population AS popul
      , area AS area
      , perimeter AS perim
      --, geometry AS geom
   FROM
      public.state_cities
   ORDER BY
      municipal_name
   ;

/* ITEM TABLE VIEW: state_counties. */

DROP VIEW IF EXISTS public._mncounties;
CREATE OR REPLACE VIEW public._mncounties AS
   SELECT
      county_id AS c_id
      , state_name AS state
      , county_name AS county_name
      , county_num AS cnum
      , area AS area
      , perimeter AS perim
      --, geometry AS geom
   FROM
      public.state_counties
   ORDER BY
      county_num
   ;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Creating geofeature layer convenience views
\qecho

DROP VIEW IF EXISTS _gfl;
CREATE OR REPLACE VIEW _gfl AS
   SELECT *
      FROM geofeature_layer AS gfl
      ORDER BY gfl.feat_type, gfl.id;

CREATE FUNCTION gfl_feat_type_view_create(IN feat_type TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'DROP VIEW IF EXISTS gfl_' || feat_type || ';';
      EXECUTE
         'CREATE OR REPLACE VIEW gfl_' || feat_type || ' AS
            SELECT *
               FROM geofeature_layer AS gfl
               WHERE gfl.feat_type = ''' || feat_type || '''
               ORDER BY id
               ;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION gfl_feat_type_view_create_all()
   RETURNS VOID AS $$
   DECLARE
      layer RECORD;
   BEGIN
      -- Create view for each geofeature type
      FOR layer IN SELECT DISTINCT feat_type FROM geofeature_layer LOOP
         PERFORM gfl_feat_type_view_create(layer.feat_type);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT gfl_feat_type_view_create_all();

DROP FUNCTION gfl_feat_type_view_create_all();
DROP FUNCTION gfl_feat_type_view_create(IN feat_type TEXT);

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Creating log_event_joined convenience view
\qecho

DROP VIEW IF EXISTS _lej;
CREATE OR REPLACE VIEW _lej AS
   SELECT id
        , event_id AS eid
        , facility AS facil
        , CASE WHEN username LIKE '_user_anon_%'
               THEN '_anon' ELSE username END
            AS uname
        , client_host AS host
        , TO_CHAR(timestamp_client, 'YYYY.MM.DD|HH24:MI')
          AS ts_client
        --, TO_CHAR(created, 'YYYY.MM.DD|HH24:MI')
        --  AS created_date
        --, browid
        --, sessid
        , key_ AS key
        , value AS val
     FROM log_event_joined
    --WHERE facility LIKE 'error/%'
    --  AND created > '${time_stamp}'
    ORDER BY id DESC;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Creating item type layer convenience view
\qecho

DROP VIEW IF EXISTS _it;
CREATE OR REPLACE VIEW _it AS
   SELECT *
      FROM item_type AS it
      ORDER BY it.id;

/* ==================================================================== */
/* Ministry of Silly Views                                              */
/* ==================================================================== */

/* We need to recreate this view for the export-import schema-data. */

/* C.f. scripts/schema/ccpv1/051-apache-logs.sq */
DROP VIEW IF EXISTS date_since_live;
CREATE VIEW date_since_live AS
   SELECT '2008-05-08'::DATE + date_series.a AS day_
   FROM generate_series(0, (current_date - '2008-05-08')) AS date_series(a);

/* ==================================================================== */
/* Function Definitions                                                 */
/* ==================================================================== */

/* E.g., SELECT cp_tag_sid('County'); */
DROP FUNCTION IF EXISTS cp_tag_sid(IN tag_name TEXT);
CREATE FUNCTION cp_tag_sid(IN tag_name TEXT)
   RETURNS INTEGER AS $$
   BEGIN
      RETURN iv.stack_id::INTEGER FROM tag
         LEFT OUTER JOIN item_versioned AS iv USING (system_id)
         WHERE LOWER(iv.name) = LOWER(tag_name)
           AND NOT iv.deleted
           AND iv.valid_until_rid = cp_rid_inf();
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


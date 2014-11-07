/* Copyright  (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script recreates views affected by new arbitrary attributes schema. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script recreates views affected by new arbitrary attributes schema.
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.18 min. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.02 min. [mn]]
\qecho 

/* FIXME: 2011.04.22: Are these views still useful??
 *        If so, would removing replacing cp_rid_inf() with the constant 
 *        speed any of these up?
 */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Drop the old views                                       */
/* ==================================================================== */

\qecho 
\qecho Dropping obsolete views
\qecho 

/* NOTE Because of VIEW dependencies, it's messy to try to keep VIEWs around
        while we ALTER a bunch of tables. Also, most of the VIEWs are 
        fragmented, referencing tables we archived in the previous 
        script, and also still referencing tables in the instance schemas.

        So, rather than archive the views, just delete 'em; this doesn't 
        cause any data loss, and we can always rebuild the views later 
        (that is, we rebuild some of the views later, but some of the 
        views we won't rebuild).
   */

/* NOTE These commands are ordered so as not to cause dependency issues. */

/* Drop the item views; most of these will not be recreated, as they get 
   replaced by actual tables in the new model. */

/* annotations */
\qecho ...annotations
DROP VIEW annotation_geo;
DROP VIEW annot_bs_geo;

/* tags */
\qecho ...tags
DROP VIEW tag_geo;
DROP VIEW tag_obj_geo;
DROP VIEW tag_bs_geo;
DROP VIEW tag_point_geo;
DROP VIEW tag_region_geo;

/* posts */
\qecho ...posts
DROP VIEW post_geo;
DROP VIEW post_obj_geo;
DROP VIEW post_bs_geo;
DROP VIEW post_point_geo;
DROP VIEW post_region_geo;
DROP VIEW post_route_geo;

/* Drop the GIS dependent views first. */
\qecho ...GIS dependent views
DROP VIEW gis_rt_endpoints;
DROP VIEW gis_rt_start;
DROP VIEW gis_rt_end;
/* Drop the GIS base views second. */
\qecho ...GIS base views
DROP VIEW gis_basemaps;
DROP VIEW gis_blocks;
DROP VIEW gis_points;
DROP VIEW gis_regions;
DROP VIEW gis_rt_blocks;
DROP VIEW gis_tag_points;

/* route_endpoints: this view will be recreated later */
\qecho ...route_endpoints
DROP VIEW route_endpoints;

/* routes */
\qecho ...routes
DROP VIEW route_geo;
DROP VIEW route_step_geo;

\qecho 
\qecho Dropping *_current, *_joined_current, & *_all views
\qecho 

/* FIXME From Landon to Andrew: What should we do with these colorado Views? */
DROP VIEW IF EXISTS node_usage_count;
DROP VIEW IF EXISTS node_usage;
DROP VIEW IF EXISTS cdot_bs_best;
DROP VIEW IF EXISTS tiger_bs_divided;

/* bmpolygon_joined_current is not used anywhere */
/* This view will not be recreated. */
DROP VIEW bmpolygon_joined_current;

/* This view will be recreated. */
DROP VIEW byway_current;

/* This view will be recreated. */
DROP VIEW byway_joined_current;

/* This view will not be recreated. */
DROP VIEW watch_region_all;

/* The GIS views are invalid; we'll recreate them in a later script, after
   implementing branching and access control. */

\qecho 
\qecho Removing dropped views from PostGIS''s geometry_columns table
\qecho 

/* c.f. 086-mn-schema-tables.sql */
CREATE TEMPORARY VIEW tables_views (name, schemaname) 
   AS SELECT tablename, schemaname FROM pg_tables 
      UNION SELECT viewname, schemaname FROM pg_views;

/* Delete the PostGIS rows for the VIEWs we just deleted. */

\qecho ...from the instance schema: @@@instance@@@
DELETE FROM geometry_columns 
   WHERE f_table_name NOT IN (SELECT DISTINCT name FROM tables_views 
                              WHERE schemaname='@@@instance@@@')
         AND f_table_schema = '@@@instance@@@';

\qecho ...from the public schema
DELETE FROM geometry_columns 
   WHERE f_table_name NOT IN (SELECT DISTINCT name FROM tables_views 
                              WHERE schemaname='public')
         AND f_table_schema = 'public';

/* ==================================================================== */
/* Step (2) -- Create helper fcn. to register geometry columns          */
/* ==================================================================== */

\qecho 
\qecho Creating helper function
\qecho 

/* Create a helper fcn. for setting up geometry columns in views. See the 
   PostGIS 1.5.1 manual, section 4.3.4: Mannualy Registering Geometry Columns 
   in geometry_columns. */
/* NOTE This is a Convenience fcn. for Cyclopath.
        This is not a temporary fcn.; we will not be deleting it. */
CREATE FUNCTION cp_register_view_geometry(IN table_name TEXT, 
                                          IN column_name TEXT,
                                          IN geometry_type TEXT,
                                          IN geometry_dims INTEGER,
                                          IN geometry_srid INTEGER)
   RETURNS VOID AS $$
   DECLARE
      sql TEXT;
      geom_cols TEXT;
   BEGIN
      /* NOTE The user can explicitly set the geometry type, or we can use the 
              PostGIS fcn, GeometryType(). The latter is convenient, but it 
              can take a while on views that we haven't optimized, since it 
              needs to analyze a row's geometry to see what type it is. So,
              ideally, most callees can specify geometry_type = '' and we'll 
              substitute in GeometryType(). */
      IF geometry_type = '' THEN
         geom_cols := '
            ST_CoordDim(' || column_name || '), 
            ST_SRID(' || column_name || '), 
            GeometryType(' || column_name || ')
            FROM ' || table_name || ' LIMIT 1';
      ELSE
         geom_cols := '
            ' || geometry_dims || ', 
            ' || geometry_srid || ', 
            ''' || geometry_type || '''';
      END IF;
      /* NOTE PostGIS documentation has "type" in quotes -- because-why?
                 INSERT INTO geometry_columns(
                    f_table_catalog, f_table_schema, f_table_name, 
                    f_geometry_column, coord_dimension, srid, "type") */
      sql := '
         INSERT INTO geometry_columns(
            f_table_catalog, f_table_schema, f_table_name, 
            f_geometry_column, coord_dimension, srid, type)
         SELECT '''', ''@@@instance@@@'', ''' || table_name || ''', 
             ''' || column_name || ''', ' || geom_cols || ';';
      --RAISE INFO 'cp_register_view_geometry: % / %', table_name, column_name;
      EXECUTE sql;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (3) -- NEW VIEWS / FEATURE-VERSIONED CONVENIENCE VIEWS          */
/* ==================================================================== */

\qecho 
\qecho Creating convenience views
\qecho 

CREATE FUNCTION iv_view_create(IN tbl_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 
         'CREATE VIEW iv_' || tbl_name || ' AS 
            SELECT is_iv.*, 
                   iv.name, iv.deleted, 
                   iv.valid_start_rid, iv.valid_until_rid 
               FROM ' || tbl_name || ' AS is_iv 
            JOIN item_versioned AS iv
               USING (id, version);';
      EXECUTE 
         'CREATE VIEW iv_cur_' || tbl_name || ' AS 
            SELECT is_iv.*, 
                   iv.name, iv.deleted, 
                   iv.valid_start_rid, iv.valid_until_rid 
               FROM ' || tbl_name || ' AS is_iv 
            JOIN item_versioned AS iv
               ON is_iv.id = iv.id
                  AND is_iv.version = iv.version
                  AND iv.valid_until_rid = cp_rid_inf()
                  AND NOT iv.deleted;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Creating iv_* views
\qecho 

SELECT iv_view_create('geofeature');
SELECT iv_view_create('link_value');
SELECT iv_view_create('attachment');
SELECT iv_view_create('tag');
SELECT iv_view_create('annotation');
SELECT iv_view_create('thread');
SELECT iv_view_create('post');
SELECT iv_view_create('attribute');

\qecho 
\qecho Registering appropriate geometry columns
\qecho 

SELECT cp_register_view_geometry('iv_geofeature', 'geometry', '', 0, 0);
SELECT cp_register_view_geometry('iv_cur_geofeature', 'geometry', '', 0, 0);

\qecho 
\qecho Cleaning up
\qecho 

DROP FUNCTION iv_view_create(IN tbl_name TEXT);

/* ==================================================================== */
/* Step (4) -- NEW VIEWS / GEOFEATURE TYPE CONVENIENCE VIEWS            */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

CREATE FUNCTION iv_gf_layer_view_create(IN layer_name TEXT)
   RETURNS VOID AS $$
   DECLARE
      view_name TEXT;
   BEGIN
      /* gf_* */
      view_name := 'gf_' || layer_name;
      EXECUTE 
         'CREATE VIEW ' || view_name || ' AS 
            SELECT gf.* 
            FROM geofeature AS gf 
            JOIN geofeature_layer AS gfl
               ON (gfl.id = gf.geofeature_layer_id
                   AND gfl.feat_type = ''' || layer_name || ''');';
      PERFORM cp_register_view_geometry(view_name, 'geometry', '', 0, 0);
      /* iv_gf_* */
      /* FIXME Are these views being created? Maybe dropped before 62? */
      view_name := 'iv_gf_' || layer_name;
      EXECUTE 
         'CREATE VIEW ' || view_name || ' AS 
            SELECT gf.*, 
                   iv.name, iv.deleted, 
                   iv.valid_start_rid, iv.valid_until_rid
            FROM geofeature AS gf 
            JOIN item_versioned AS iv
               USING (id, version)
            JOIN geofeature_layer AS gfl
               ON (gfl.id = gf.geofeature_layer_id
                   AND gfl.feat_type = ''' || layer_name || ''');';
      PERFORM cp_register_view_geometry(view_name, 'geometry', '', 0, 0);
      /* iv_gf_cur_* */
      view_name := 'iv_gf_cur_' || layer_name;
      EXECUTE 
         'CREATE VIEW ' || view_name || ' AS 
            SELECT gf.*, 
                   iv.name, iv.deleted, 
                   iv.valid_start_rid, iv.valid_until_rid
            FROM geofeature AS gf 
            JOIN item_versioned AS iv
               ON gf.id = iv.id
                  AND gf.version = iv.version
                  AND iv.valid_until_rid = cp_rid_inf()
                  AND NOT iv.deleted
            JOIN geofeature_layer AS gfl
               ON (gfl.id = gf.geofeature_layer_id
                   AND gfl.feat_type = ''' || layer_name || ''')';
      PERFORM cp_register_view_geometry(view_name, 'geometry', '', 0, 0);
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION iv_gf_layer_view_create_all()
   RETURNS VOID AS $$
   DECLARE
      feat_type_layer RECORD;
   BEGIN
      /* Create view for each geofeature type */
      FOR feat_type_layer IN 
            SELECT DISTINCT feat_type FROM geofeature_layer LOOP
         PERFORM iv_gf_layer_view_create(feat_type_layer.feat_type);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Creating geofeature type convenience views
\qecho 

SELECT iv_gf_layer_view_create_all();

\qecho 
\qecho Cleaning up
\qecho 

DROP FUNCTION iv_gf_layer_view_create_all();
DROP FUNCTION iv_gf_layer_view_create(IN layer_name TEXT);

/* ==================================================================== */
/* Step (5) -- Recreate watch region view                               */
/* ==================================================================== */

\qecho 
\qecho Recreating watch_region_all view as region_watched_all
\qecho 

/* c.f. 064-regions.sql */

/* Combined view of private watch regions and public regions watched. */
CREATE VIEW region_watched_all AS (
   SELECT rw.id, rw.name, rw.geometry, rw.username 
   FROM iv_gf_region_watched AS rw
   WHERE NOT rw.deleted
         AND rw.notify_email
)
UNION (
   SELECT rg.id, rg.name, rg.geometry, rg.username
   FROM iv_gf_region AS rg
   JOIN region_watcher AS rw
      ON (rw.region_id = rg.id)
   WHERE NOT rg.deleted
         AND rg.valid_until_rid = cp_rid_inf());

/* PostGIS requires us to manually register Geometry columns in Views */
SELECT cp_register_view_geometry('region_watched_all', 'geometry', '', 0, 0);

/* ==================================================================== */
/* Step (6) -- NEW VIEWS / ATTACHMENT-GEOFEATURE BY ATTC & FEAT TYPES   */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

/* NOTE These change after access control is implemented. */

CREATE FUNCTION feat_get_geom_type(IN feat_layer TEXT)
   RETURNS TEXT AS $$
   DECLARE
      geom_type TEXT;
      gfl_row RECORD;
   BEGIN
      geom_type := '';
      IF feat_layer = '' THEN
         geom_type := 'GEOMETRY';
      ELSE
         EXECUTE 'SELECT DISTINCT geometry_type::TEXT 
            FROM geofeature_layer WHERE feat_type = ''' 
               || feat_layer || ''';' 
               INTO STRICT gfl_row;
         geom_type := gfl_row.geometry_type;
      END IF;
      --RAISE INFO '==== feat_get_geom_type: ''%s''', geom_type;
      RETURN geom_type;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION feat_attc_view_get_name(IN feat_layer TEXT, IN attc_type TEXT)
   RETURNS TEXT AS $$
   DECLARE
      view_name TEXT;
   BEGIN
      view_name := attc_type;
      IF feat_layer != '' THEN
         view_name := view_name || '_' || feat_layer;
      END IF;
      view_name := view_name || '_geo';
      RETURN view_name;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION feat_attc_view_create(IN feat_layer TEXT, IN attc_type TEXT, 
                                      IN attc_columns TEXT)
   RETURNS VOID AS $$
   DECLARE
      view_name TEXT;
      gfl_join_on TEXT;
      exec_stmt TEXT;
      dimension INTEGER;
   BEGIN
      --RAISE INFO '==== feat_attc_view_create: feat_layer: %', feat_layer;
      view_name := feat_attc_view_get_name(feat_layer, attc_type);
      IF feat_layer = '' THEN
         gfl_join_on := 'ON (gf.geofeature_layer_id = gfl.id)';
      ELSE 
         gfl_join_on := 'ON (gf.geofeature_layer_id = gfl.id 
                             AND gfl.feat_type = ''' || feat_layer || ''')';
      END IF;
      --RAISE INFO '==== feat_attc_view_create: %', view_name;
      exec_stmt :=  
         'CREATE VIEW ' || view_name || ' AS 
            SELECT
              lv_iv.id AS id,
              lv_iv.version AS version,
              (at_iv.deleted OR lv_iv.deleted OR gf_iv.deleted) AS deleted,
              GREATEST(at_iv.valid_start_rid, 
                       lv_iv.valid_start_rid,
                       gf_iv.valid_start_rid) AS valid_start_rid,
              LEAST(at_iv.valid_until_rid, 
                    lv_iv.valid_until_rid,
                    gf_iv.valid_until_rid) AS valid_until_rid,
              lv.lhs_id AS lhs_id,
              lv.rhs_id AS rhs_id,
              gfl.feat_type AS feat_type,'
              -- NOTE For attachment_geo, attc_type is incorrectly 'attachment'
              || '''' || attc_type || '''::TEXT AS attc_type,
              gf.geometry AS geometry
              ' || attc_columns || '
            FROM ' || attc_type || ' AS at 
               JOIN item_versioned AS at_iv 
                  ON (at_iv.id = at.id AND at_iv.version = at.version)
               JOIN link_value AS lv ON (lv.lhs_id = at.id)
               JOIN item_versioned AS lv_iv 
                  ON (lv_iv.id = lv.id AND lv_iv.version = lv.version)
               JOIN geofeature AS gf ON (lv.rhs_id = gf.id)
               JOIN item_versioned AS gf_iv 
                  ON (gf_iv.id = gf.id AND gf_iv.version = gf.version)
               JOIN geofeature_layer AS gfl ' || gfl_join_on || '
            WHERE at_iv.valid_start_rid < lv_iv.valid_until_rid
              AND at_iv.valid_start_rid < gf_iv.valid_until_rid
              AND lv_iv.valid_start_rid < at_iv.valid_until_rid
              AND lv_iv.valid_start_rid < gf_iv.valid_until_rid
              AND gf_iv.valid_start_rid < at_iv.valid_until_rid
              AND gf_iv.valid_start_rid < lv_iv.valid_until_rid;';
      --RAISE INFO '... ... Execute : %', exec_stmt;
      EXECUTE exec_stmt;
      --RAISE INFO '... ... cp_register_view_geometry: %', view_name;
      /* PostGIS requires us to manually register Geometry columns in Views */
      dimension := 2;
      PERFORM cp_register_view_geometry(view_name, 'geometry', 
                  (SELECT feat_get_geom_type(feat_layer)),
                  dimension, (SELECT cp_srid()));
      --RAISE INFO '===DONE!';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* NOTE annotation_byway_geo is an inefficient view! However, this view is no
        longer needed once access control is implemented, it's purpose being 
        handled by the new table, group_item_access. 
        
        So we'll create this view for now while we make the new schema, but 
        we'll drop it after we setup branching and permissions. */
CREATE FUNCTION feat_attc_view_create_all()
   RETURNS VOID AS $$
   DECLARE
      feat_layer RECORD;
   BEGIN
      /* Create view for each geofeature type and also one for all types */
      /* NOTE The query:

                 SELECT DISTINCT feat_type 
                    FROM geofeature_layer UNION (SELECT '' AS feat_type);

               returns:

                  '', 'byway', 'region', 'region_watched', 
                  'region_work_hint', 'route', 'terrain', 'track', 'waypoint' 
               */
      FOR feat_layer IN SELECT DISTINCT feat_type FROM geofeature_layer 
            UNION (SELECT '' AS feat_type) LOOP
         --RAISE INFO '====== Processing ====== / ''%''', feat_layer.feat_type;
         PERFORM feat_attc_view_create(feat_layer.feat_type, 'attachment', '');
         PERFORM feat_attc_view_create(feat_layer.feat_type, 'tag', 
            ' , at_iv.name AS name');
         PERFORM feat_attc_view_create(feat_layer.feat_type, 'annotation', 
            ' , at.comments AS comments');
         --RAISE INFO ' ===== feat_attc_view_create: % / thread', 
         --   feat_layer.feat_type;
         PERFORM feat_attc_view_create(feat_layer.feat_type, 'thread', 
            ' , at_iv.name AS name');
         PERFORM feat_attc_view_create(feat_layer.feat_type, 'post', 
            ' , at.body AS body');
         PERFORM feat_attc_view_create(feat_layer.feat_type, 'attribute', 
            ', at.value_type AS value_type
             , at.value_restraints AS value_restraints
             , at.multiple_allowed AS multiple_allowed
             , at.value_units AS value_units
             , at.value_hints AS value_hints
             , at.value_minimum AS value_minimum
             , at.value_maximum AS value_maximum
             , at.value_stepsize AS value_stepsize
             , at.gui_sortrank AS gui_sortrank
             , lv.value_boolean AS value_boolean
             , lv.value_integer AS value_integer
             , lv.value_real AS value_real
             , lv.value_text AS value_text
             , lv.value_binary AS value_binary
             , lv.value_date AS value_date');
         --RAISE INFO ' ===== feat_attc_view_create done: %', 
         --              feat_layer.feat_type;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Creating attc_feat and attc_geo views
\qecho 

SELECT feat_attc_view_create_all();

\qecho 
\qecho Dropping temporary helper fcns.
\qecho 

DROP FUNCTION feat_attc_view_create_all();
DROP FUNCTION feat_attc_view_create(IN feat_layer TEXT, IN attc_type TEXT, 
                                    IN attc_columns TEXT);
DROP FUNCTION feat_attc_view_get_name(IN feat_layer TEXT, IN attc_type TEXT);
DROP FUNCTION feat_get_geom_type(IN feat_layer TEXT);

/* ==================================================================== */
/* Step (7) -- Recreate byway-ratings view                              */
/* ==================================================================== */

\qecho 
\qecho Recreating byway_joined_current view as tiles_draw_byway
\qecho 

/* c.f. 035-ratings.sql */

/* tiles_draw_byway is used by mapserver to make tiles */
CREATE VIEW tiles_draw_byway AS
   SELECT iv.id,
          iv.version,
          iv.name, 
          gfl.draw_class_id,
          gf.geometry,
          byway_rating.value AS generic_rating
   FROM geofeature AS gf 
   JOIN item_versioned AS iv
      ON gf.id = iv.id
         AND gf.version = iv.version
         AND iv.valid_until_rid = cp_rid_inf()
         AND NOT iv.deleted
   JOIN geofeature_layer AS gfl
      ON (gfl.id = gf.geofeature_layer_id
          AND gfl.feat_type = 'byway')
   JOIN byway_rating 
      ON byway_rating.byway_id = gf.id
   WHERE byway_rating.username = '_r_generic';

/* PostGIS requires us to manually register Geometry columns in Views */
SELECT cp_register_view_geometry('tiles_draw_byway', 'geometry', '', 0, 0);

\qecho 
\qecho Recreating bmpolygon_joined_current view as tiles_draw_terrain
\qecho 

/* c.f. 017-tilecache-state.sql */

/* FIXME Should all iv_gf_cur_* VIEWs just include draw_class_id? */
/*       CREATE VIEW iv_gf_cur_terrain AS */
/* FIXME Who uses this function??
CREATE VIEW tiles_draw_terrain AS
   SELECT iv.id,
          iv.version,
          iv.name, 
          gfl.draw_class_id,
          gf.geometry
   FROM geofeature AS gf 
   JOIN item_versioned AS iv
      ON gf.id = iv.id
         AND gf.version = iv.version
         AND iv.valid_until_rid = cp_rid_inf()
         AND NOT iv.deleted
   JOIN geofeature_layer AS gfl
      ON (gfl.id = gf.geofeature_layer_id
          AND gfl.feat_type = 'terrain');

-- PostGIS requires us to manually register Geometry columns in Views
SELECT cp_register_view_geometry('tiles_draw_terrain', 'geometry', '', 0, 0);
*/

/* ==================================================================== */
/* Step (8) -- NEW VIEWS / CACHE TABLES                                 */
/* ==================================================================== */

/* One of the goals of the new database is to be able to push geometry quickly 
   and litely to the client, and one of the pieces of information the client 
   needs when rendering the geometry is whether or not the geometry has notes 
   (annotations). We can also indicate a few other things, like if it has posts
   associated with it. */

/* NOTE These tables are not needed. Two things make them unnecessary:
        (1) Access control's group_item_access table; and 
        (2) How the new Map_Canvas_Update class organizes WFS calls. */

/* NOTE Keeping these views for posterity, in case I change my mind about these
        views in the future. 

CREATE VIEW geofeature_annotations AS
   SELECT gf.*, annot.comments
      FROM iv_geofeature AS gf
         JOIN iv_link_value AS lv ON gf.id = lv.rhs_id 
         JOIN iv_annotation AS annot ON lv.lhs_id = annot.id
      WHERE gf.valid_start_rid < lv.valid_until_rid
            AND gf.valid_start_rid < annot.valid_until_rid
            AND lv.valid_start_rid < gf.valid_until_rid
            AND lv.valid_start_rid < annot.valid_until_rid
            AND annot.valid_start_rid < gf.valid_until_rid
            AND annot.valid_start_rid < lv.valid_until_rid
            AND annot.deleted IS FALSE;
SELECT cp_register_view_geometry('geofeature_annotations', 'geometry', 
                                 '', 0, 0);

CREATE VIEW geofeature_annot_count AS
   SELECT id, version, COUNT(*) AS annot_count
      FROM geofeature_annotations
      GROUP BY id, version;

CREATE VIEW geofeature_posts AS
   SELECT gf.*, post.body
      FROM iv_geofeature AS gf
         JOIN iv_link_value AS lv ON gf.id = lv.rhs_id 
         JOIN iv_post AS post ON lv.lhs_id = post.id
      WHERE gf.valid_start_rid < lv.valid_until_rid
            AND gf.valid_start_rid < post.valid_until_rid
            AND lv.valid_start_rid < gf.valid_until_rid
            AND lv.valid_start_rid < post.valid_until_rid
            AND post.valid_start_rid < gf.valid_until_rid
            AND post.valid_start_rid < lv.valid_until_rid
            AND post.deleted IS FALSE;
SELECT cp_register_view_geometry('geofeature_posts', 'geometry', '', 0, 0);

CREATE VIEW geofeature_post_count AS
   SELECT id, version, COUNT(*) AS post_count
      FROM geofeature_posts
      GROUP BY id, version;

CREATE VIEW geofeature_with_counts AS
   SELECT gf.*, 
          CASE WHEN gf_ac.annot_count IS NULL THEN 0
               ELSE gf_ac.annot_count END AS counts_annot,
          CASE WHEN gf_pc.post_count IS NULL THEN 0
               ELSE gf_pc.post_count END AS counts_post
      FROM geofeature AS gf
         LEFT OUTER JOIN geofeature_annot_count AS gf_ac
            USING (id, version)
         LEFT OUTER JOIN geofeature_post_count AS gf_pc
            USING (id, version);
SELECT cp_register_view_geometry('geofeature_with_counts', 'geometry', 
                                 '', 0, 0);

*/

/* ==================================================================== */
/* Step (9) -- Clean up                                                 */
/* ==================================================================== */

\qecho 
\qecho Cleaning up
\qecho 

/* FIXME Delete this or move it: this fcn. is used in script 102-apb-64...
DROP FUNCTION cp_register_view_geometry(IN table_name TEXT, 
                                        IN column_name TEXT,
                                        IN geometry_type TEXT,
                                        IN geometry_dims INTEGER,
                                        IN geometry_srid INTEGER);
*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


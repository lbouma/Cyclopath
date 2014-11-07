/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script drops a lot of the views we recreated in 

     102-apb-23-views_-instance.sql

   since the group_item_access table means we don't need these views.

   More specifically, the views do not respect permissions or branching. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script drops views obsoleted by permissions and branching.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO */
\set VERBOSITY terse

/* NOTE This script is very similar to 102-apb-24-views_-instance.sql (which
        creates the views we're dropping herein). So this script is organized 
        like the other script. */

/* ==================================================================== */
/* Step (1) -- Archive the old views                                    */
/* ==================================================================== */

/* This is from the original script; it doesn't apply to us. We opt to 
   delete the views rather than archive them, since we just created them 
   a few scripts ago to help with converting data from the old schema to 
   the new schema, but now they're meaningless to us. */

/* ==================================================================== */
/* Step (2) -- Create helper fcn. to unregister geometry columns        */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

CREATE FUNCTION drop_view_verbose(IN view_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      /* During testing, if you dump/reload the database, those VIEWs that 
         reference columns that got renamed/dropped are not reloaded, so we 
         catch exceptions where the VIEW doesn't exist -- we're trying to 
         drop it anyway, so if it's already dropped, who cares. */
      BEGIN
         EXECUTE 'DROP VIEW ' || view_name;
         RAISE INFO 'Dropped view: %', view_name;
      EXCEPTION WHEN undefined_table THEN
         RAISE INFO 'No such view: %', view_name;
      END;
      /* PostGIS requires us to manually register Geometry columns in Views */
      PERFORM de_register_view_geometry(view_name, 'geometry');
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION de_register_view_geometry(IN table_name TEXT, 
                                          IN column_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE '
         DELETE FROM geometry_columns 
            WHERE f_table_catalog = ''''
               AND f_table_schema = ''@@@instance@@@''
               AND f_table_name = ''' || table_name || '''
               AND f_geometry_column = ''' || column_name || '''
         ;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (3) -- NEW VIEWS / FEATURE-VERSIONED CONVENIENCE VIEWS          */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

CREATE FUNCTION iv_view_drop(IN tbl_name TEXT)
   RETURNS VOID AS $$
   DECLARE
      view_name TEXT;
   BEGIN
      /* Drop the iv_* table. */
      view_name := 'iv_' || tbl_name || '';
      /* FIXME These views don't exist?! Heh? */
      PERFORM drop_view_verbose(view_name);
      /* Drop the iv_cur_* table. */
      view_name := 'iv_cur_' || tbl_name || '';
      PERFORM drop_view_verbose(view_name);
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Dropping iv_* convenience views obsoleted by group_item_access.
\qecho 

SELECT iv_view_drop('geofeature');
SELECT iv_view_drop('link_value');
SELECT iv_view_drop('attachment');
SELECT iv_view_drop('tag');
SELECT iv_view_drop('annotation');
SELECT iv_view_drop('thread');
SELECT iv_view_drop('post');
SELECT iv_view_drop('attribute');

\qecho 
\qecho Cleaning up geometry rows from geometry_columns
\qecho 

/* FIXME This views don't exist?! Heh?
FIXME NOTE The column is nonetheless registered! */
SELECT de_register_view_geometry('iv_geofeature', 'geometry');
SELECT de_register_view_geometry('iv_cur_geofeature', 'geometry');

\qecho 
\qecho Cleaning up
\qecho 

DROP FUNCTION iv_view_drop(IN tbl_name TEXT);

/* ==================================================================== */
/* Step (4) -- Drop watch region view                                   */
/* ==================================================================== */

\qecho 
\qecho Dropping region_watched_all
\qecho 

/* c.f. 064-regions.sql */

/* Combined view of private watch regions and public regions watched. */
/* FIXME These views don't exist?! Heh? */
SELECT drop_view_verbose('region_watched_all');

/* ==================================================================== */
/* Step (5) -- NEW VIEWS / GEOFEATURE TYPE CONVENIENCE VIEWS            */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

CREATE FUNCTION iv_gf_layer_view_drop(IN layer_name TEXT)
   RETURNS VOID AS $$
   DECLARE
      view_name TEXT;
   BEGIN
      /* gf_* */
      view_name := 'gf_' || layer_name;
      PERFORM drop_view_verbose(view_name);
      /* iv_gf_* */
      view_name := 'iv_gf_' || layer_name;
      /* FIXME These views don't exist?! Heh? */
      PERFORM drop_view_verbose(view_name);
      /* iv_gf_cur_* */
      view_name := 'iv_gf_cur_' || layer_name;
      PERFORM drop_view_verbose(view_name);
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION iv_gf_layer_view_drop_all()
   RETURNS VOID AS $$
   DECLARE
      feat_type_layer RECORD;
   BEGIN
      /* Drop view for each geofeature type */
      /* NOTE We removed two rows previously so we UNION 'em back in */
      FOR feat_type_layer IN 
            SELECT DISTINCT feat_type FROM geofeature_layer 
            UNION (SELECT 'region_watched' AS feat_type) 
            UNION (SELECT 'region_work_hint' AS feat_type) LOOP
         PERFORM iv_gf_layer_view_drop(feat_type_layer.feat_type);
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Dropping gf_* convenience views obsoleted by group_item_access.
\qecho 

SELECT iv_gf_layer_view_drop_all();

\qecho 
\qecho Cleaning up
\qecho 

DROP FUNCTION iv_gf_layer_view_drop_all();
DROP FUNCTION iv_gf_layer_view_drop(IN layer_name TEXT);

/* ==================================================================== */
/* Step (6) -- NEW VIEWS / ATTACHMENT-GEOFEATURE BY ATTC & FEAT TYPES   */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcns.
\qecho 

/* C.f. 102-apb-23-views_-instance.sql */
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

/* C.f. 102-apb-23-views_-instance.sql */
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

CREATE FUNCTION feat_attc_view_drop(IN feat_layer TEXT, IN attc_type TEXT)
   RETURNS VOID AS $$
   DECLARE
      view_name TEXT;
      gfl_join_on TEXT;
      exec_stmt TEXT;
      dimension INTEGER;
   BEGIN
      view_name := feat_attc_view_get_name(feat_layer, attc_type);
      RAISE INFO 'Dropping feat_attc view ''%''', view_name;
      PERFORM drop_view_verbose(view_name);
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION feat_attc_view_drop_all()
   RETURNS VOID AS $$
   DECLARE
      feat_layer RECORD;
   BEGIN
      /* Drop view for each geofeature type and also one for all types */
      /* NOTE We removed two rows previously so we UNION 'em back in */
      FOR feat_layer IN SELECT DISTINCT feat_type FROM geofeature_layer 
            UNION (SELECT 'region_watched' AS feat_type) 
            UNION (SELECT 'region_work_hint' AS feat_type) 
            UNION (SELECT '' AS feat_type) LOOP
         RAISE INFO 'Dropping feat_attc views for ''%''', feat_layer.feat_type;
         PERFORM feat_attc_view_drop(feat_layer.feat_type, 'attachment');
         PERFORM feat_attc_view_drop(feat_layer.feat_type, 'tag'); 
         PERFORM feat_attc_view_drop(feat_layer.feat_type, 'annotation');
         PERFORM feat_attc_view_drop(feat_layer.feat_type, 'thread');
         PERFORM feat_attc_view_drop(feat_layer.feat_type, 'post');
         PERFORM feat_attc_view_drop(feat_layer.feat_type, 'attribute');
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Dropping feat_attc views
\qecho 

SELECT feat_attc_view_drop_all();

\qecho 
\qecho Cleaning up
\qecho 

DROP FUNCTION feat_attc_view_drop_all();
DROP FUNCTION feat_attc_view_drop(IN feat_layer TEXT, IN attc_type TEXT);
DROP FUNCTION feat_attc_view_get_name(IN feat_layer TEXT, IN attc_type TEXT);
DROP FUNCTION feat_get_geom_type(IN feat_layer TEXT);

/* ==================================================================== */
/* Step (7) -- Recreate byway-ratings view                              */
/* ==================================================================== */

\qecho 
\qecho Dropping tiles_draw_byway
\qecho 

/* NOTE We still need this fcn., but we'll recreate it in the next script,
        since this script is just for destroying things. */

-- FIXME!:
SELECT drop_view_verbose('tiles_draw_byway');

/* FIXME This View was not created 'cause I don't know who actually uses it.
SELECT drop_view_verbose('tiles_draw_terrain');
*/

/* ==================================================================== */
/* Step (8) -- NEW VIEWS / CACHE TABLES                                 */
/* ==================================================================== */

/* NOTE: These views were previously dropped and were not re-created.
         So nothing to do, except to mention that we're not doing anything.

SELECT drop_view_verbose('geofeature_annotations');
SELECT drop_view_verbose('geofeature_annot_count');
SELECT drop_view_verbose('geofeature_posts');
SELECT drop_view_verbose('geofeature_post_count');
SELECT drop_view_verbose('geofeature_with_counts');
*/

/* ==================================================================== */
/* Step (9) -- Clean up                                                 */
/* ==================================================================== */

\qecho 
\qecho Cleaning up
\qecho 

DROP FUNCTION de_register_view_geometry(IN table_name TEXT, 
                                        IN column_name TEXT);
DROP FUNCTION drop_view_verbose(IN view_name TEXT);

/* ==================================================================== */
/* Step (10) -- NOTEs                                                   */
/* ==================================================================== */

/* You can see how the PostGIS geometry table is populated w/ this command:

   select f_table_schema,f_table_name,f_geometry_column from geometry_columns 
      where f_table_schema = 'minnesota' order by f_table_schema,f_table_name;

   In a previous script, 102-apb-24-aattrs-views___.sql, we removed rows from 
   geometry_columns whose tables we archived or deleted, so, at this point in 
   the scripts, geometry_columns should only contain valid data.
   
   E.g. these tables have valid rows in the table:

      apache_event                    
      tiles_cache_byway_names                
      coverage_area                   
      group_item_access            
      group_revision              
      revision                        
      route_endpoints                 

   These tables' rows are okay, too, but we need to rebuild the views in 
   a later script. And 

      gis_basemaps                    
      gis_blocks                     
      gis_points                      
      gis_regions                     
      gis_rt_blocks                 
      gis_rt_end                      
      gis_rt_endpoints                
      gis_rt_start                    
      gis_tag_points                  

   This table's row can be removed, since we're removing work hints leftovers 
   from V2:

   This table's rows are also okay, but we want to eventually address it:

      work_hint

set search_path to minnesota, public, archive_minnesota_1, archive_1;
set search_path to colorado, public, archive_colorado_1, archive_1;
select * from  geometry_columns order by f_table_schema, f_table_name;
*/

/* FYI Here's the geometry_column table before [apb]:

cycling2=> select f_table_name,f_geometry_column from geometry_columns 
cycling2->    where f_table_schema = 'public' order by f_table_name;
       f_table_name        | f_geometry_column 
---------------------------+-------------------
 bikeways_qgis             | geometry
 node_endpoint                | geometry
 mndot_basemap             | geo_multi
 mndot_basemap             | geometry
 mndot_basemap_muni        | geometry
 mndot_bikeways            | geometry
 mndot_bikeways            | geometry_buf
 overlap_bike_paths_200903 | geometry
 route_digest              | end_xy
 route_digest              | start_xy
 wh_raw                    | geometry
 wh_trial                  | geometry
 wh_view_event             | geometry
 wh_viewport               | geometry
(14 rows)

FIXME Where did the above rows go? I don't see them anymore......

cycling2=> select f_table_name,f_geometry_column from geometry_columns 
cycling2->    where f_table_schema = 'minnesota' order by f_table_name;
       f_table_name       | f_geometry_column 
--------------------------+-------------------
 apache_event             | geometry
 basemap_polygon          | geometry
 bmpolygon_joined_current | geometry
 byway_joined_current     | geometry
 tiles_cache_byway_names  | geometry
 byway_segment            | geometry
 county                   | geometry
 coverage_area            | geometry
 gis_basemaps             | geometry
 gis_blocks               | geometry
 gis_points               | geometry
 gis_regions              | geometry
 gis_rt_blocks            | geometry
 gis_rt_end               | geometry
 gis_rt_endpoints         | geometry
 gis_rt_start             | geometry
 gis_tag_points           | geometry
 point                    | geometry
 region                   | geometry
 revision                 | geosummary
 revision                 | geometry
 revision                 | bbox
 route_endpoints          | geometry
 urban_area               | geometry
 watch_region             | geometry
 work_hint                | geometry
(26 rows)

NOTE: 'colorado' rows same as 'minnesota'

*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;


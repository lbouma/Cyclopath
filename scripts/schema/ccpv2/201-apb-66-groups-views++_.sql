/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script recreates a few legacy views that we archived, then recreated,
   then dropped, since our earlier recreations didn't honor permissions and 
   branching (though we needed these views temporarily to help us populate the
   new schema). The views are used by mapserver. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script recreates views used by mapserver.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Recreate byway-ratings view                              */
/* ==================================================================== */

/* 20110920: Delete this. Use byway.Many(), so GrAC is respected. */

/*
\qecho 
\qecho Recreating byway_joined_current view as tiles_draw_byway
\qecho 
*/

/* FIXME Does the byway ratings view ignore permissions?
         Or does it just load the public group's byways? */

/* FIXME Make a bug: Allow user to generate branch-group tiles?? */

/* FIXME Search usage of this view and verify it's used correctly. */

/* c.f. 035-ratings.sql */

/* tiles_draw_byway is used by mapserver to make tiles */
/* This view needs to respek permissions and branches. */
/* FIXME Should draw_class_id be a part of group_item_access? */
/* FIXME draw_class_id changed to draw_class_viewer/editor/owner
         -- is draw_class_viewer appropriate for this view? */

/* FIXME: The views herein for MapServer may need to accept 
 *        a branch ID... and MapServer, then, as well!
 *        (So we can make tiles for branches.) */

/*
CREATE FUNCTION create_view_tiles_draw_byway()
   RETURNS VOID AS $$
   DECLARE
      group_public_id INTEGER;
      access_level_id_ INTEGER;
      branch_baseline_id INTEGER;
      item_type_id_ INTEGER;
      rid_inf INTEGER;
   BEGIN
      -- Cache costly plpgsql values that don't change.
      group_public_id := cp_group_public_id();
      access_level_id_ := cp_access_level_id('viewer');
      branch_baseline_id := cp_branch_baseline_id();
      item_type_id_ := cp_item_type_id('byway');
      rid_inf := cp_rid_inf();
      EXECUTE '
         CREATE VIEW tiles_draw_byway AS
            SELECT 
               gia.stack_id,
               gia.name, 
               gf.geometry,
               gfl.draw_class_viewer,
               brg.value AS generic_rating
            FROM group_item_access AS gia
            JOIN geofeature AS gf
               ON gf.system_id = gia.item_id
            JOIN geofeature_layer AS gfl
               ON gfl.id = gf.geofeature_layer_id
            JOIN byway_rating AS brg
               ON brg.byway_stack_id = gia.stack_id
            WHERE 
               gia.group_id = ' || group_public_id || '
               AND gia.access_level_id <= ' || access_level_id_ || '
               AND brg.branch_id = ' || branch_baseline_id || '
               AND gia.item_type_id = ' || item_type_id_ || '
               AND gia.valid_until_rid = ' || rid_inf || '
               AND NOT gia.deleted
               AND brg.username = ''_r_generic'';
         ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT create_view_tiles_draw_byway();

DROP FUNCTION create_view_tiles_draw_byway();
*/

/* PostGIS requires us to manually register Geometry columns in Views */
/*
SELECT cp_register_view_geometry('tiles_draw_byway', 'geometry', '', 0, 0);
*/

/* Don't repopulate the tiles_cache_byway_names table -- it'll get updated when
 * tilecache_update.py runs. */

\qecho 
\qecho Recreating bmpolygon_joined_current view as tiles_draw_terrain
\qecho 

/* c.f. 017-tilecache-state.sql */

/* FIXME Should all iv_gf_cur_* VIEWs just include draw_class_id? */
/*       CREATE VIEW iv_gf_cur_terrain AS */
/* FIXME Who uses this function??
         This fcn. is used by MapServer! */

/* FIXME: 20111003: BUG nnnn: Put this in tilecache_update.py. 
                              See also draw_param_joined. */

CREATE FUNCTION create_view_tiles_draw_terrain()
   RETURNS VOID AS $$
   DECLARE
      group_public_id INTEGER;
      access_level_id_ INTEGER;
      branch_baseline_id INTEGER;
      item_type_id_ INTEGER;
      rid_inf INTEGER;
   BEGIN
      /* Cache costly plpgsql values that don't change. */
      group_public_id := cp_group_public_id();
      access_level_id_ := cp_access_level_id('viewer');
      branch_baseline_id := cp_branch_baseline_id();
      item_type_id_ := cp_item_type_id('terrain');
      rid_inf := cp_rid_inf();
      /* FIXME: Why does this view use version, but the byway view (above)
                does not? */
      EXECUTE '
         CREATE VIEW tiles_draw_terrain AS
            SELECT 
               gia.stack_id,
               gia.version,
               gia.name, 
               gf.geometry,
               gfl.draw_class_viewer
            FROM group_item_access AS gia
            JOIN geofeature AS gf
               ON gf.system_id = gia.item_id
            JOIN geofeature_layer AS gfl
               ON gfl.id = gf.geofeature_layer_id
            WHERE 
               gia.group_id = ' || group_public_id || '
               AND gia.access_level_id <= ' || access_level_id_ || '
               AND gia.item_type_id = ' || item_type_id_ || '
               AND gia.valid_until_rid = ' || rid_inf || '
               AND NOT gia.deleted;
         ';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT create_view_tiles_draw_terrain();

DROP FUNCTION create_view_tiles_draw_terrain();

-- PostGIS requires us to manually register Geometry columns in Views
SELECT cp_register_view_geometry('tiles_draw_terrain', 'geometry', '', 0, 0);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


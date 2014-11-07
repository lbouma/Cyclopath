/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script and the next script prepare the database for the new 
   item_versioned implementation. This script applies to all Cyclopath 
   instances (i.e., to the public schema); see the next script for 
   instance-specific changes.
   
   In this script, we prepare the geofeature_layer table. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

\qecho 
\qecho This script combines the old *_type tables into a single table
\qecho 

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Create archival schema                                   */
/* ==================================================================== */

/* To play it safe, don't destroy data; rather, move it to its own schema. */

\qecho 
\qecho Moving geofeature type tables to archival schema
\qecho 

ALTER TABLE basemap_polygon_type SET SCHEMA archive_1;
ALTER TABLE byway_type SET SCHEMA archive_1;
ALTER TABLE point_type SET SCHEMA archive_1;
ALTER TABLE region_type SET SCHEMA archive_1;
ALTER TABLE route_type SET SCHEMA archive_1;
ALTER TABLE track_type SET SCHEMA archive_1;
ALTER TABLE watch_region_type SET SCHEMA archive_1;
ALTER TABLE work_hint_type SET SCHEMA archive_1;

/* ==================================================================== */
/* Step (2) -- RENAME 'code' TO 'id'                                    */
/* ==================================================================== */

/* The team decided to change the name 'code' to 'id' since the the term 
   'code' is ambiguous -- it could mean a lot of things, like the code you're 
   reading now (SQL code, python code, etc.), or it could mean that you've 
   encoded something, etc. So we just use 'id', whose meaning is well known -- 
   an ID is an arbitrary, unique value used to identify an object. */

ALTER TABLE draw_class RENAME code TO id;

ALTER TABLE draw_param RENAME draw_class_code TO draw_class_id;

ALTER TABLE draw_param_joined RENAME draw_class_code TO draw_class_id;

ALTER TABLE tag_preference_type RENAME code TO id;

/* ==================================================================== */
/* Step (3) -- GEOFEATURE TYPE TABLE                                    */
/* ==================================================================== */

/* == geofeature_layer == */

/* The geofeature_layer table holds the list of geometry type layers, 
   it indicates to the client how to draw the different layers on the map,
   and it indicates the type of PostGIS geometry represented. */

/* The original schema maps the following PostGIS types to the following 
   tables:

      POLYGON       region, watch_region, work_hint
      LINESTRING    basemap_polygon, byway_segment, byway_name_cache 
                                                    (tiles_cache_byway_names)
      POINT         point

   We're ignoring the following tables, which have geometry but not a draw 
   class:

      POLYGON       county, region, watch_region, work_hint
      MULTIPOLYGON  revision, urban_area */

/* NOTE The *_type code is hard-coded for some usages, such as byway_type
        (to see, just grep the pypyserver for [^a-zA-Z0-9]42[^a-zA-Z0-9] 
        42 is the byway layer type, 'Expressway Ramp').
        
        Unfortunately (or not?), we can't use the old type tables' layer IDs
        to populate the new table, since some of the old tables use the same 
        IDs.
        
        We could add another column to the primary key, perhaps type_name 
        (like 'byway', 'region', etc.) but this would require messing with 
        the foreign keys in other tables.
        
        Fortunately, if you examine the code, only byway_segment's codes are 
        hard-coded, so we keep those the same but we assign new codes to the 
        rows from the other tables. (We also fix the magic numbers in pyserver,
        but it's tedious to find magic numbers, so for now this task is a 
        FIXME.) */

CREATE SEQUENCE geofeature_layer_id_seq;

CREATE TABLE geofeature_layer (
   id INTEGER NOT NULL DEFAULT nextval('geofeature_layer_id_seq'),
   feat_type TEXT NOT NULL,
   layer_name TEXT NOT NULL,
   geometry_type TEXT NOT NULL,
   draw_class_id INTEGER NOT NULL,
   restrict_usage BOOLEAN NOT NULL DEFAULT TRUE,
   last_modified TIMESTAMP WITH TIME ZONE NOT NULL
   /* NOTE We don't create triggers on last_modified quite yet -- we'll copy 
           the existing tables first so we retain their last_modified dates. */
);

/* Mark owned-by, so the sequence gets dropped if the table is dropped. */
ALTER SEQUENCE geofeature_layer_id_seq OWNED BY geofeature_layer.id;

ALTER TABLE geofeature_layer 
   ADD CONSTRAINT geofeature_layer_pkey 
   PRIMARY KEY (id);

ALTER TABLE geofeature_layer 
   ADD CONSTRAINT geofeature_layer_draw_class_id_fkey 
   FOREIGN KEY (draw_class_id) REFERENCES draw_class(id) 
      DEFERRABLE;

/* Make sure our JOINs w/ Geofeature are speedy. */
CREATE INDEX geofeature_layer_feat_type ON geofeature_layer (feat_type);
CREATE INDEX geofeature_layer_layer_name ON geofeature_layer (layer_name);
CREATE INDEX geofeature_layer_geometry_type 
   ON geofeature_layer (geometry_type);
CREATE INDEX geofeature_layer_draw_class_id 
   ON geofeature_layer (draw_class_id);

/* Create the last_modified triggers */

/* 2010: These cannot be created yet, not even after marshalling the data:
 *       if we copy data, make the triggers, and then commit, the triggers run
 *       on commit (which seems funny!). Thanks, Fernando, for the find. 
 * 2012: Well, let's at least create them. We can disable them and re-enable
 *       them from ccpv2-add_constraints, like we do from elsewhere... */
CREATE TRIGGER geofeature_layer_i
   BEFORE INSERT ON geofeature_layer
   FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER geofeature_layer_u
   BEFORE UPDATE ON geofeature_layer 
   FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
/* Disable the new triggers. We'll enable them after the upgrade scripts run. 
   See: db_load_add_constraints.sql. */
ALTER TABLE geofeature_layer DISABLE TRIGGER geofeature_layer_i;
ALTER TABLE geofeature_layer DISABLE TRIGGER geofeature_layer_u;

/* == Marshal the data == */

/* Lazy fingers cheat! Utility fcns. to the rescue. */

CREATE FUNCTION populate_geofeature_feat_type(IN tbl_name TEXT, 
      IN feat_type TEXT, IN geom_type TEXT, IN restrict_usage BOOLEAN) 
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 
         'INSERT INTO geofeature_layer (id, feat_type, layer_name, 
            geometry_type, draw_class_id, restrict_usage, last_modified) 
          SELECT 
            code, 
            ''' || feat_type || ''', 
            text, 
            ''' || geom_type || ''', 
            draw_class_code, 
            ' || restrict_usage || ', 
            last_modified
          FROM ' || tbl_name || ';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION populate_geofeature_feat_type_auto_inc(IN tbl_name TEXT, 
      IN feat_type TEXT, IN geom_type TEXT, IN restrict_usage BOOLEAN) 
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 
         'INSERT INTO geofeature_layer (feat_type, layer_name, 
            geometry_type, draw_class_id, restrict_usage, last_modified) 
          SELECT 
            ''' || feat_type || ''', 
            text, 
            ''' || geom_type || ''', 
            draw_class_code, 
            ' || restrict_usage || ', 
            last_modified
          FROM ' || tbl_name || ';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Copying old type table data into new geofeature_layer table
\qecho 

/* Since byway_type.code is hard-coded in pyserver (and rather than fix the
   hard-coding), we use those values for id, which range from 1 to 42. For the
   remaining *_type tables, we assign new ID values. */

/* NOTE Renaming byway_segment => byway */
SELECT populate_geofeature_feat_type('archive_1.byway_type', 
                                     'byway', 'LINESTRING', FALSE);

/* Set the sequence to 101; this is an arbitrary value, really. We just don't
   want the new IDs to conflict with those from byway. */

/* SYNC_ME: Search geofeature_layer table. Search draw_class table, too. */
ALTER SEQUENCE geofeature_layer_id_seq RESTART WITH 101;

/* Finally we can grab rows from the rest of *_type tables. */

/* NOTE Renaming basemap_polygon => terrain */
SELECT populate_geofeature_feat_type_auto_inc('archive_1.basemap_polygon_type',
                                              'terrain', 'POLYGON', TRUE);
/* Skipping: byway_name_cache (tiles_cache_byway_names), since it's a generated
 *           table. */
/* NOTE Renaming point => waypoint */
SELECT populate_geofeature_feat_type_auto_inc('archive_1.point_type', 
                                              'waypoint', 'POINT', TRUE);
SELECT populate_geofeature_feat_type_auto_inc('archive_1.region_type', 
                                              'region', 'POLYGON', TRUE);
/* NOTE We could not specify a type for route or just call it a polygon.
        In the instance script, all routes store the 'empty' polygon. */
SELECT populate_geofeature_feat_type_auto_inc('archive_1.route_type', 
                                              'route', 'POLYGON', TRUE);
/* FIXME: This should be POLYGON, like route, and not LINESTRING? */
SELECT populate_geofeature_feat_type_auto_inc('archive_1.track_type', 
                                              'track', 'POLYGON', TRUE);
/* NOTE Renaming watch_region => region_watched */
/* FIXME The region_watched geofeature_layer is a stop-gap solution. Once
         permissions is implemented, this type goes away and these things 
         become just regions. */
SELECT populate_geofeature_feat_type_auto_inc('archive_1.watch_region_type', 
                                              'region_watched', 'POLYGON', 
                                              TRUE);
/* NOTE Renaming work_hint => region_work_hint */
SELECT populate_geofeature_feat_type_auto_inc('archive_1.work_hint_type', 
                                              'region_work_hint', 'POLYGON', 
                                              TRUE);

/* NOTE At this point, we've extracted all the rows from these tables:
           basemap_polygon_type, byway_type, point_type, region_type, 
           route_type, track_type, watch_region_type, work_hint_type */

/* Util. fcn. cleanup. */

DROP FUNCTION populate_geofeature_feat_type_auto_inc(IN tbl_name TEXT, 
   IN feat_type TEXT, IN geom_type TEXT, IN restrict_usage BOOLEAN);
DROP FUNCTION populate_geofeature_feat_type(IN tbl_name TEXT, 
   IN feat_type TEXT, IN geom_type TEXT, IN restrict_usage BOOLEAN); 

/* Type enum used by link_value tables. */

/* FIXME -- Bug 1398 / Upgrade to PostgreSQL 8.3 */
/* CREATE TYPE value_type_enum AS ENUM ('boolean', 'integer', 'real', 
   'text', 'binary', 'feature_id'); */

/* ==================================================================== */
/* Step (4) -- NEW VIEWS / GEOFEATURE TYPE CONVENIENCE VIEWS            */
/* ==================================================================== */

\qecho 
\qecho Creating geofeature layer convenience views
\qecho 

/* FIXME Is gfl_ a good prefixxing convention? */

CREATE FUNCTION gfl_feat_type_view_create(IN feat_type TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 
         'CREATE VIEW gfl_' || feat_type || ' AS 
            SELECT * 
               FROM geofeature_layer AS gfl
               WHERE gfl.feat_type = ''' || feat_type || ''';';
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
/* Step (5) -- Make the item type lookup                                */
/* ==================================================================== */

/* The item type lookup is used by the attribute as well as the new item policy
 * table used by the access control system. */

\qecho 
\qecho Disabling NOTICEs to avoid noise
\qecho 

--SET client_min_messages = 'warning';

\qecho 
\qecho Creating the public item type lookup table
\qecho 

CREATE TABLE item_type (
   id INTEGER NOT NULL,
   type_name TEXT
);

ALTER TABLE item_type ADD CONSTRAINT item_type_pkey PRIMARY KEY (id);

CREATE INDEX item_type_type_name ON item_type (type_name);

\qecho 
\qecho Enabling noisy NOTICEs
\qecho 

SET client_min_messages = 'notice';

/* ==================================================================== */
/* Step (6) -- Define the item types                                    */
/* ==================================================================== */

\qecho 
\qecho Populating item_type
\qecho 

/* SYNC_ME: Search: Item_Type table. */
INSERT INTO item_type (id, type_name) VALUES ( 1, 'attachment');
INSERT INTO item_type (id, type_name) VALUES ( 2, 'geofeature');
INSERT INTO item_type (id, type_name) VALUES ( 3, 'link_value');
INSERT INTO item_type (id, type_name) VALUES ( 4, 'annotation');
INSERT INTO item_type (id, type_name) VALUES ( 5, 'attribute');
INSERT INTO item_type (id, type_name) VALUES ( 6, 'branch');
INSERT INTO item_type (id, type_name) VALUES ( 7, 'byway');
INSERT INTO item_type (id, type_name) VALUES ( 8, 'post');
INSERT INTO item_type (id, type_name) VALUES ( 9, 'region');
INSERT INTO item_type (id, type_name) VALUES (10, 'route');
INSERT INTO item_type (id, type_name) VALUES (11, 'tag');
INSERT INTO item_type (id, type_name) VALUES (12, 'terrain');
INSERT INTO item_type (id, type_name) VALUES (13, 'thread');
INSERT INTO item_type (id, type_name) VALUES (14, 'waypoint');
INSERT INTO item_type (id, type_name) VALUES (15, 'workhint');
INSERT INTO item_type (id, type_name) VALUES (16, 'group_membership');
INSERT INTO item_type (id, type_name) VALUES (17, 'new_item_policy');
INSERT INTO item_type (id, type_name) VALUES (18, 'group');
INSERT INTO item_type (id, type_name) VALUES (19, 'route_step');
INSERT INTO item_type (id, type_name) VALUES (20, 'group_revision');
INSERT INTO item_type (id, type_name) VALUES (21, 'track');
INSERT INTO item_type (id, type_name) VALUES (22, 'track_point');
INSERT INTO item_type (id, type_name) VALUES (23, 'addy_coordinate');
INSERT INTO item_type (id, type_name) VALUES (24, 'addy_geocode');
INSERT INTO item_type (id, type_name) VALUES (25, 'item_name');
INSERT INTO item_type (id, type_name) VALUES (26, 'grac_error');
INSERT INTO item_type (id, type_name) VALUES (27, 'work_item');
INSERT INTO item_type (id, type_name) VALUES (28, 'nonwiki_item');
INSERT INTO item_type (id, type_name) VALUES (29, 'merge_job');
INSERT INTO item_type (id, type_name) VALUES (30, 'route_analysis_job');
INSERT INTO item_type (id, type_name) VALUES (31, 'job_base');
INSERT INTO item_type (id, type_name) VALUES (32, 'work_item_step');
INSERT INTO item_type (id, type_name) VALUES (33, 'merge_job_download');
INSERT INTO item_type (id, type_name) VALUES (34, 'group_item_access');
/* DEPRECATED: item_watcher is replaced by private link_attributes.
INSERT INTO item_type (id, type_name) VALUES (35, 'item_watcher');
INSERT INTO item_type (id, type_name) VALUES (36, 'item_watcher_change');
*/
-- This has since been renamed from 'messaging' to 'item_event_alert'.
INSERT INTO item_type (id, type_name) VALUES (37, 'messaging');
/* DEPRECATED: byway_node is replaced by node_endpoint.
     INSERT INTO item_type (id, type_name) VALUES (38, 'byway_node'); */
/* DEPRECATED: route_waypoint is renamed to route_stop.
     INSERT INTO item_type (id, type_name) VALUES (39, 'route_waypoint'); */
INSERT INTO item_type (id, type_name) VALUES (40, 
                                          'route_analysis_job_download');
INSERT INTO item_type (id, type_name) VALUES (41, 'branch_conflict');
INSERT INTO item_type (id, type_name) VALUES (42, 'merge_export_job');
INSERT INTO item_type (id, type_name) VALUES (43, 'merge_import_job');
INSERT INTO item_type (id, type_name) VALUES (44, 'node_endpoint');
INSERT INTO item_type (id, type_name) VALUES (45, 'node_byway');
INSERT INTO item_type (id, type_name) VALUES (46, 'node_traverse');
INSERT INTO item_type (id, type_name) VALUES (47, 'route_stop');
-- 2013.04.04: For fetching basic item info (like access_style_id).
-- No: INSERT INTO item_type (id, type_name) VALUES (48, 'item_stack');
-- No: INSERT INTO item_type (id, type_name) VALUES (49, 'item_versioned');
INSERT INTO item_type (id, type_name) VALUES (50, 'item_user_access');
-- No: INSERT INTO item_type (id, type_name) VALUES (51, 'item_user_watching');
INSERT INTO item_type (id, type_name) VALUES (52, 'link_geofeature');
INSERT INTO item_type (id, type_name) VALUES (53, 'conflation_job');
INSERT INTO item_type (id, type_name) VALUES (54, 'link_post');
INSERT INTO item_type (id, type_name) VALUES (55, 'link_attribute');

/* ==================================================================== */
/* Step (7) -- Renaming functions                                       */
/* ==================================================================== */

\qecho 
\qecho Renaming existing functions.
\qecho 

/* FIXME: To help keep track of which SQL functions are ours and which ones are
 *        PostGIS's and Postgres's, we should prefix all Cyclopath fcns. with 
 *        "cp_". 
 *
 *        There's a (partial?) list of fcns. in 102-apb-54-groups-functs__.sql.
 *        For now, [lb] is just renaming rid_inf... */

ALTER FUNCTION rid_inf() RENAME TO cp_rid_inf;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


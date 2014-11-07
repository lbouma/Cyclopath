/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script generalizes the item tables.

   The original schema stores different geofeatures in their own tables 
   (like byway_segment, point, basemap_polygon, region, etc.); this script 
   turns all of those tables into just one table, the geofeature table.

   This script also generalizes geofeature attributes. Historically, Cyclopath
   has stored attributes about a feature in that feature's table, such as
   storing lane_count, shoulder_width, speed_limit, etc., in the byway_segment
   table. This script creates a link_value table and a set of attachment
   tables, such as tag, annotation, and attribute, so we can add attributes to
   features without having to alter tables and add new columns.

   This script also standardizes the vocabulary used to describe system 
   objects. There are a myriad of changes. The biggest change is that features 
   are now called 'items', mostly so we don't confuse them with  
   'geofeatures'. The complete list of vocabulary changes is on the Wiki. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script implements the arbitrary attributes schema (Bug 1051).
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO */
--\set VERBOSITY terse

/* ==================================================================== */
/* Step (1) -- ARCHIVAL SCHEMA                                          */
/* ==================================================================== */

/* To play it safe, don't destroy data; rather, move it to its own schema. */

\qecho 
\qecho Moving tables to archive schema
\qecho 

ALTER TABLE annot_bs SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE annotation SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE basemap_polygon SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE byway_segment SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE point SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE post SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE post_bs SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE post_point SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE post_region SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE post_revision SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE post_route SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE region SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE route SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE track SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE tag SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE tag_bs SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE tag_point SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE tag_region SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE thread SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE watch_region SET SCHEMA archive_@@@instance@@@_1;
/* NOTE: Archiving work_hint but not consuming data. We also include two work
 *      hint support tables, rp_region_popularity and rp_region_sequence. */
ALTER TABLE work_hint SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE rp_region_popularity SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE rp_region_sequence SET SCHEMA archive_@@@instance@@@_1;

/* --% REMAINDERS: Each of the tables above has data we want to keep. 
   --%             To make sure we move all the data from the old 
   --%             tables to the new, we use a comment that looks like --%
   --%             to indicate what columns we've processed. */

\qecho 
\qecho Dropping obsolete views
\qecho 

/* It gets messy when trying to maintain archived views -- you're 
   better off just dropping the view and recreating it later, after 
   you've altered the database. We drop most of the views and recreate 
   them in the next script, but in this script, we create a table with 
   the same name as one of the views, so we need to drop it now. */
DROP VIEW geofeature;

\qecho 
\qecho Moving obsolete tables to archive schema
\qecho 

ALTER TABLE county SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE urban_area SET SCHEMA archive_@@@instance@@@_1;

/* ==================================================================== */
/* Step (2) -- Update PostGIS Table                                     */
/* ==================================================================== */

\qecho 
\qecho Updating geometry_columns for archived PostGIS tables
\qecho 

/* c.f. 086-mn-schema-tables.sql */
CREATE TEMPORARY VIEW tables_views (name, schemaname) 
   AS SELECT tablename, schemaname FROM pg_tables 
      UNION SELECT viewname, schemaname FROM pg_views;

UPDATE geometry_columns SET f_table_schema = 'archive_@@@instance@@@_1' 
   WHERE f_table_name IN (SELECT DISTINCT name FROM tables_views 
                          WHERE schemaname='archive_@@@instance@@@_1')
         AND f_table_schema = '@@@instance@@@';

/* ==================================================================== */
/* Step (3) -- SPECIAL REVISION ZERO                                    */
/* ==================================================================== */

/* Here we introduce two new revisions -- 0 and 1.

   0 is the no-revision revision, i.e., it carries no information.
   1 is the big-bang revision,    i.e., from the beginning of time.

   Ideally, revision 0 has no purpose and should not be assigned to 
   any item in the database. In this manner, if the code ever sees 
   a revision of 0, it knows something's amiss. However, in the old 
   database, both routes and watch_regions are all version 1 and all 
   share the valid_start_rid of 0. So, in the new database, if you see 
   a 0, think old watch_region or route. */

\qecho 
\qecho Creating special revisions 0 and 1
\qecho 

-- SELECT revision_create_special_revisions();
INSERT INTO revision 
   (id, timestamp, host, username, skip_geometry, permission, comment) 
VALUES 
   (0, now(), '_DUMMY', '_script', TRUE, 1, 'Special Revision 0');
/* FIXME: 2012.09.14: Postgres hanging here, but only on schema-upgrade, 
                      and not when running this script via terminal cxpx.
*/

\qecho Created rev 0...

/* Colorado already has id = 1, so use WHERE NOT EXISTS. */
INSERT INTO revision 
   (id, timestamp, host, username, skip_geometry, permission, comment) 
SELECT 
   1, now(), '_DUMMY', '_script', TRUE, 1, 'Special Revision 1' 
WHERE 
   NOT EXISTS (SELECT id FROM revision WHERE id = 1);

\qecho ... created rev 1.

/* Bug 2408: To handle existing tracks, we assign dummy revision IDs
   starting at 1, so those IDs better exist. */

CREATE FUNCTION revision_make_special_revisions()
   RETURNS VOID AS $$
   DECLARE
      rid_max INTEGER;
      rid_cur INTEGER;
      rexists INTEGER;
   BEGIN
      EXECUTE 'SELECT MAX(id) FROM revision WHERE id < cp_rid_inf();'
         INTO STRICT rid_max;
      RAISE INFO 'Making missing revisions from 2 to %.', rid_max;
      FOR rid_cur IN 2..rid_max LOOP
         rexists := id FROM revision WHERE id = rid_cur;
         IF rexists IS NULL THEN
            RAISE INFO 'Making missing revision %.', rid_cur;
            INSERT INTO revision 
               (id, timestamp, host, username, skip_geometry, permission, 
                comment)
               SELECT 
               rid_cur, now(), '_DUMMY', '_script', TRUE, 1, '[No-op]'
            WHERE 
               NOT EXISTS (SELECT id FROM revision WHERE id = rid_cur);
         /* ELSE: Revision ID already exists; do nothing. */
         END IF;
      END LOOP;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT revision_make_special_revisions();

DROP FUNCTION revision_make_special_revisions();

/* ==================================================================== */
/* Step (4.1) -- RENAME 'byway_name_cache' TO 'tiles_cache_byway_names' */
/* ==================================================================== */

/* To reflect which tables and views are used exclusively by MapServer 
 * and tilecache_update, we prefix said entities' names with 'tiles_cache_'
 * (tables) or 'tiles_draw_' (views). */

ALTER TABLE byway_name_cache RENAME TO tiles_cache_byway_names;
ALTER INDEX byway_name_cache_gist RENAME TO tiles_cache_byway_gist;
ALTER INDEX byway_name_cache_name RENAME TO tiles_cache_byway_name;
ALTER TABLE byway_name_cache_id_seq RENAME TO tiles_cache_byway_id_seq;

/* Don't forget to register the name change with the geometry table. */
UPDATE geometry_columns SET f_table_name = 'tiles_cache_byway_names' 
   WHERE f_table_name  = 'byway_name_cache';

/* ==================================================================== */
/* Step (4.2) -- RENAME 'code' TO 'id'                                  */
/* ==================================================================== */

/* See the previous SQL script for an explanation on why we do this. */

ALTER TABLE tiles_cache_byway_names RENAME COLUMN draw_class_code 
                                               TO draw_class_id;

/* NOTE These tables' type_codes are always 1, 2, or 3 */
ALTER TABLE route_tag_preference RENAME COLUMN type_code TO tpt_id;
/* NOTE These tables' type_codes are always 0, 1, 2, or 3 */
ALTER TABLE tag_preference RENAME COLUMN type_code TO tpt_id;
ALTER TABLE tag_preference_event RENAME COLUMN type_code TO tpt_id;

/* NOTE work_hint's type_code is always 2. */
/* NOTE work_hint is still broken by Bug 1977, oh well. */
--ALTER TABLE work_hint RENAME type_code TO geofeature_layer_id;

/* ==================================================================== */
/* Step (4.3) -- SRID Convenience function                              */
/* ==================================================================== */

\qecho 
\qecho Creating cp_srid() convenience function.
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* MAYBE: 2012.09.14: This should be in public schema. */
CREATE FUNCTION cp_srid()
   RETURNS INTEGER AS $$
   BEGIN
      IF '@@@instance@@@' = 'minnesota' THEN
         RETURN 26915;
      ELSIF '@@@instance@@@' = 'colorado' THEN
         RETURN 26913;
      ELSE
         RAISE EXCEPTION 'Not a recognized instance! Please tell me its srid.';
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (5) -- ITEM VERSIONED TABLE                                     */
/* ==================================================================== */

/* The item_versioned table applies versioning information to an object. An 
   object is something we want users to be able to manipulate, such as 
   geometry, like points, byways and regions, as well as things that may 
   apply to geometry, like tags, notes, posts, and attributes. */

/* Historically, the db has stored versioning ids and version numbers in just 
   the child tables to which they pertain. In the new db, we put all of that
   information into a parent table and use foreign keys from the child tables. 
   */

\qecho 
\qecho Disabling NOTICEs to avoid noise
\qecho 

--SET client_min_messages = 'warning';

\qecho 
\qecho Creating table '''item_versioned'''
\qecho 

/* NOTE Renaming feature_versioned to item_versioned so as not to confuse with
        geofeature. Also, not just geofeatures are versioned, but also 
        attachments, link_values, and (in a later SQL script) branches. */

/* NOTE Postgres 8.2 doesn't recognize ALTER SEQUENCE, so use ALTER TABLE */
ALTER TABLE feature_id_seq RENAME TO item_versioned_id_seq;

CREATE TABLE item_versioned (
   id INTEGER DEFAULT nextval('item_versioned_id_seq') NOT NULL,
   version INTEGER NOT NULL,
   deleted BOOLEAN NOT NULL,
   /* Bug 2695: Branchy Items Need to be 'Revertable'. */
   reverted BOOLEAN NOT NULL DEFAULT FALSE,
   name TEXT,
   valid_start_rid INTEGER NOT NULL,
   valid_until_rid INTEGER NOT NULL
   /* NOTE: We create indexes and add constraints in the very last scripts,
    *       otherwise some of the intermediate scripts take on the order of
    *       hours to run, rather than on the order of minutes. */
);

ALTER TABLE item_versioned 
   ADD CONSTRAINT item_versioned_pkey 
   PRIMARY KEY (id, version);

/* 2013.04.23: So that we can make tiles that don't constantly change every
time we update the database because the branch stack IDs change, update the
sequence value to something that won't get used in the conceivable near future,
long enough for us to remain in beta before going live... This also affects the
Cycloplan Shapefile, wherein the branch ID is also stored. */
-- 2013.04.23: Latest stack_id is 2647420.
-- ccpv1_live=> select * from minnesota.feature_id_seq; ==> 1585832
-- ccpv1_live=> select * from colorado.feature_id_seq; ==> 468932

ALTER SEQUENCE item_versioned_id_seq START WITH 1654321;
ALTER SEQUENCE item_versioned_id_seq RESTART WITH 1654321;

\qecho 
\qecho Enabling noisy NOTICEs
\qecho 

SET client_min_messages = 'notice';

/* ==================================================================== */
/* Step (6) -- GEOMETRY TABLES                                          */
/* ==================================================================== */

/* == geofeature == */

/* The geofeature table contains a feature's geometry and z-level. */

/* Note that there's a historical geofeature view which is similar to this new 
   table but missing the z-level. We're basically making that view a table and
   adding the z-level column. (Which is good, because the view grew over the 
   years to join more and more tables, and it's slow to load.) */

/* Create the geofeature table. */

\qecho 
\qecho Disabling NOTICEs to avoid noise
\qecho 

--SET client_min_messages = 'warning';

\qecho 
\qecho Creating table '''geofeature'''
\qecho 

CREATE TABLE geofeature (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   geofeature_layer_id INTEGER NOT NULL,
   z INTEGER NOT NULL,
   /* Mostly byway-specific columns. It's less complicated for some of these
    * columns to remain here (i.e., instead of making a new byway table).
    * It also makes for quicker client load times (i.e., if we made 'z' and
    * 'one_way' in attributes, we'd have to fetch those, and attrs. aren't the
    * quickest fetch). */
   -- NOTE: Using smallint rather than integer; saving 2 bytes of storage, ha!
   -- FIXME: colorado has NULL one_way columns, so not saying 'NOT NULL'
   --        one_way SMALLINT NOT NULL DEFAULT 0,
   one_way SMALLINT,
   beg_node_id INTEGER, -- NOT NULL, -- I.e., "Beginning Node ID"
   fin_node_id INTEGER, -- NOT NULL, -- I.e., "Finishing Node ID"
   split_from_id INTEGER,
   /* NOTE The two columns, username and notify_email, are maintained 
           temporarily; they'll be removed in a later script, after permissions
           is implemented. (They belong to the old watch_region table, and they
           got implemented here before permissions was tackled, and now it 
           doesn't make sense (like a good use of time) to correct the SQL, 
           since much of it has already been debugged and seen some reviews.) 
           */
   username TEXT NOT NULL DEFAULT '',
   notify_email BOOLEAN DEFAULT FALSE NOT NULL
);

ALTER TABLE geofeature 
   ADD CONSTRAINT geofeature_pkey 
   PRIMARY KEY (id, version);

\qecho 
\qecho Enabling noisy NOTICEs
\qecho 

SET client_min_messages = 'notice';

/* Setup the geometry column and constraints. See the PostGIS docs for more. */

/* First, we create a new function to return the SRID of the instance.

   NOTE This is rather hacky -- if we introduce a new instance, we need to 
        remember to update this function.

   NOTE The magic number 26915 is the European Petroleum Survey Group (EPSG) 
        ID that identifies the Coordinate Reference System (CRS) used to 
        encode the the geometry coordinates. Specifically, NAD83 / UTM Zone 15N
        (EPSG:26915), which includes Minneapolis.
   
        26913 is the SRID that includes Denver, CO. */

\qecho 
\qecho Adding geometry column to geofeature
\qecho 

\set dimension 2
SELECT AddGeometryColumn('geofeature', 'geometry', (SELECT cp_srid()), 
                         'GEOMETRY', :dimension);

/* ==================================================================== */
/* Step (7) -- ATTACHMENT TABLES                                        */
/* ==================================================================== */

/* The link_value table associates features, values, and attachments.

   For instance, a byway feature could be associated with the speed_limit
   attribute, in which case the value (an int) represents the speed limit of 
   the byway. Another example is linking a point to a discussions post -- here,
   the value (a string) represents the user's post body.

   To simplify our lives as developers and to keep things easy to understand, 
   we create columns for each of the values types (bool, int, string, etc.), 
   rather than creating separate tables for each of the value types (which is
   how some SQL purists might attack this problem). Having just one table means
   we save on JOINs, but it also means most of our link_value table cells will
   be null. */

\qecho 
\qecho Disabling NOTICEs to avoid noise
\qecho 

--SET client_min_messages = 'warning';

\qecho 
\qecho Creating '''attachment''' and support tables
\qecho 

\qecho Creating table '''attachment'''
/* FIXME: Delete this table. (I'm not sure I even ever join against it anymore,
 *        anyway. */
CREATE TABLE attachment (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL
);

ALTER TABLE attachment 
   ADD CONSTRAINT attachment_pkey 
   PRIMARY KEY (id, version);

/* NOTE: 2011.04.20: lhs_id and rhs_id used to be called attc_id and feat_id,
 *                   but you can link attachments to other attachments, like
 *                   posts to attributes, so renaming to left-hand-side and
 *                   right-hand-side, per
 *          https://secure.wikimedia.org/wikipedia/en/wiki/Sides_of_an_equation
 */

/* SYNC_ME: Search: Link_Value table. */
/* SYNC_ME: Direction MAGIC NUMBERS.
 *          -1 (reverse direction), 0 (both directions), 1 (forward). */
\qecho Creating table '''link_value'''
CREATE TABLE link_value (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   lhs_id INTEGER NOT NULL,
   rhs_id INTEGER NOT NULL,
/* FIXME: Redundant (if line_evt_dir_id). */
   direction_id INTEGER NOT NULL DEFAULT 0,
   value_boolean BOOLEAN,
   value_integer INTEGER,
   value_real REAL,
   value_text TEXT,
   value_binary BYTEA,
   value_date DATE,
   /* BUG nnnn: Linear Events? */
   /* The M-Value is a 'measurement'-value, or what GIS calls the distance (in
    * whatever units you choose) from the start of the line segment to the
    * point the M-Value indicates. */
   /* BUG nnnn: Should rhs be a new byway_collection type, or something?
    *           We could use that to draw bikelanes...!!! =) */
   line_evt_mval_a INTEGER,
   line_evt_mval_b INTEGER,
   line_evt_dir_id INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE link_value 
   ADD CONSTRAINT link_value_pkey 
   PRIMARY KEY (id, version);

/* Attachment Support Tables */

/* Each of the attachment tables holds a foreign key to the attachment table. 
   In fact, most of the attachment tables do not have any more columns than
   this, but merely exist to distinguish between different types of
   attachments. */

/* The tag table. */

\qecho Creating table '''tag'''
CREATE TABLE tag (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL
);

ALTER TABLE tag 
   ADD CONSTRAINT tag_pkey 
   PRIMARY KEY (id, version);

/* The annotation table. */

\qecho Creating table '''annotation'''
CREATE TABLE annotation (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   comments TEXT
);

ALTER TABLE annotation 
   ADD CONSTRAINT annotation_pkey 
   PRIMARY KEY (id, version);

/* The thread (discussions) table. */

\qecho Creating table '''thread'''
CREATE TABLE thread (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   /* FIXME: route reactions. replace with an enum. then delete col. */
   ttype TEXT NOT NULL DEFAULT 'general',
   /* FIXME: route reactions. this is the enum: */
   thread_type_id INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE thread 
   ADD CONSTRAINT thread_pkey 
   PRIMARY KEY (id, version);

/* The (thread) post table. */

\qecho Creating table '''post'''
CREATE TABLE post (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   thread_id INTEGER NOT NULL,
   body TEXT,
   /* BUG nnnn: polarity should be a link_value, i.e.,
                btw. a route and an attr, i.e., /post/polarity. 
                Or maybe use a name that's more clean:
                  i.e., /route/polarity, the Route Thumber.
                See: scriptes/setup/runic/link_attributes_populate.py
   */
   polarity INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE post 
   ADD CONSTRAINT post_pkey 
   PRIMARY KEY (id, version);

/* The attribute (definition) table. */

\qecho Creating table '''attribute'''
CREATE TABLE attribute (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   value_internal_name TEXT,  /* Used by developers, e.g., "/byway/lane_count",
                                 as opposed to name in Item_Versioned, e.g., 
                                 "Total number of lanes" */
   spf_field_name TEXT,       /* The 10-char. max. Shapefile field name. */
   value_type TEXT NOT NULL,  /* integer, boolean, text, binary, real, date */
   value_hints TEXT,          /* E.g., for one way: "incl. both directions" */ 
   value_units TEXT,          /* E.g., for speed limit: "mph" */
   value_minimum INTEGER,     /* Minimum value for numeric value_type */
   value_maximum INTEGER,     /* Maximum value for numeric value_type */
   value_stepsize INTEGER,    /* For numeric value_type GUI control */
   gui_sortrank INTEGER,      /* Let user decide how to order edit controls */
   applies_to_type_id INTEGER,/* which items this attr applies; null if all */
   uses_custom_control BOOLEAN NOT NULL DEFAULT FALSE,
                              /* If true, means GUI uses custom control;
                                 otherwise, the GUI uses built-in control */
   /* Bug 2409 and Bug 2410 -- Implement the next two. */
   value_restraints TEXT,
   multiple_allowed BOOLEAN NOT NULL DEFAULT FALSE,
   /* Bug nnnn */
   is_directional BOOLEAN NOT NULL DEFAULT FALSE
);

ALTER TABLE attribute 
   ADD CONSTRAINT attribute_pkey 
   PRIMARY KEY (id, version);

/* The watcher table. */

/* NOTE The watcher table will be implemented later, after we implement 
        branching and permissions (otherwise we'd create it here and 
        just ALTER it later, so what's the point). */

\qecho 
\qecho Enabling noisy NOTICEs
\qecho 

SET client_min_messages = 'notice';

/* ====== */
/* ROUTES */
/* ====== */

/* Regarding the existing route table:
      z is always 160
      type_code is always 2

prod_mirror=> select count(*) from route where visibility = 1;  ==>  52
prod_mirror=> select count(*) from route where visibility = 2;  ==>  62
prod_mirror=> select count(*) from route where visibility = 3;  ==>  103442
prod_mirror=> select * from visibility 
 code | text  
------+-------
    1 | all
    2 | owner
    3 | noone
prod_mirror=> select count(*) from route where permission = 1;  ==>  23
prod_mirror=> select count(*) from route where permission = 2;  ==>  953
prod_mirror=> select count(*) from route where permission = 3;  ==>  102580
prod_mirror=> select * from permissions;
 code |  text   
------+---------
    1 | public
    2 | shared
    3 | private
prod_mirror=> select distinct(version) from route
 version 
---------
       6
       4
       5
       8
       1
       2
       9
       3
       7
      10
prod_mirror=> select distinct(deleted) from route;
 deleted 
---------
 f
 t
name is now settable (no longer always NULL)
type_code is always 2
z is always 160

   */

\qecho 
\qecho (Re-)Creating table '''route'''
\qecho 

/* We're just dropping columns that are now in item_versioned and geofeature.
 */
CREATE TABLE route (

   /* The stack_id and version reference item_versioned. */
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,

   /* Basic route settings. (Note that the from and to addrs -- 'waypoints', as
      of Route Sharing -- are stored in a separate table). */
   /* MAYBE: Shouldn't depart_at be a TIMESTAMP WITH TIME ZONE NOT NULL? */
   depart_at TEXT,
   /* MAGIC_NUMBER: travel_mode 1 is 'bicycle'. */
   travel_mode SMALLINT NOT NULL DEFAULT 1,
   transit_pref SMALLINT,
   use_defaults BOOLEAN,

   /* The route details value is basically a built-in annotation. */
   /* MAYBE: Convert details into a note? Maybe we can promote the original
    *        note, and then let other users add other notes? Or maybe instead 
    *        of adding more notes, of users create a discussion... if the
    *        latter (discussion), details make more sense here since it has a
    *        1-to-1 relationship with each route. */
-- FIXME: Make sure this column gets copied. It may be being ignored, 
-- since it was NULL until route sharing...
   details TEXT,

   /* Moved to item_versioned:
   name TEXT,
   deleted BOOLEAN NOT NULL,
   valid_start_rid INTEGER NOT NULL,
   valid_until_rid INTEGER NOT NULL,
   */

   /* Moved to geofeature:
FIXME: Verify geofeature_type_id is set to same as type_code...
   geofeature_layer_id (formerly: type_code) INTEGER NOT NULL,
   z INTEGER NOT NULL,
   */

   /* Route Sharing, circa Spring 2012, removes from_addr and to_addr and makes
         them "calculated" values (when fetching routes, they're found in 
         route_waypoint).
      NOTE: In a later script, we'll restore these.
      NOTE: In CcpV2, we rename route_waypoint/from_addr/to_addr 
                                 to route_stop/beg_addr/fin_addr.
    Omitted:
     from_addr TEXT,
     to_addr TEXT,
   */

   /* NOTE: source has nothing to do with the user; it indicates what piece of
            code was involved with making the new route version... */
   source TEXT,

/* FIXME: These columns will eventually be dropped. */

   /* FIXME: drop owner_name. */
   owner_name TEXT,
   /* FIXME: drop host. */
   host INET,
   /* FIXME: drop session_id. */
   session_id TEXT,
   /* FIXME: Where does created belong? Maybe the GIA value is sufficient? */
   created TIMESTAMP WITH TIME ZONE NOT NULL,
   /* FIXME: drop link_hash_id. */
   link_hash_id TEXT,
   /* FIXME: drop cloned_from_id. */
   cloned_from_id INTEGER,

   /* These two columns will be removed later when we implement
    * group_item_acecss. */
   permission INTEGER DEFAULT 3 NOT NULL,
   visibility INTEGER DEFAULT 3 NOT NULL
);

ALTER TABLE route
   ADD CONSTRAINT route_pkey
   PRIMARY KEY (id, version);

/* Don't add the foreign key constraints yet. If we do, the next script can't
 * complete: after dropping the primary key to populate the table, and then
 * when we try to recreate the primary key, we'll get the error:
 *
 *  ERROR: cannot ALTER TABLE "route" because it has pending trigger events
 *
 * We'll create these constraints via the ccpv2-add_constraints script.

ALTER TABLE route
   ADD CONSTRAINT route_owner_name_fkey
      FOREIGN KEY (owner_name) REFERENCES user_(username) DEFERRABLE;

ALTER TABLE route
   ADD CONSTRAINT route_travel_mode_fkey
      FOREIGN KEY (travel_mode) REFERENCES travel_mode(id) DEFERRABLE;

*/

/* Skipping foreign-key constraints:
      route_permission_fkey and route_visibility_fkey
   since we're dropping those columns later. */

/* Skipping constraints: 
      route_enforce_permissions and route_enforce_visibility
   since we're dropping those columns later. */

\qecho 
\qecho Creating trigger on table '''route'''
\qecho 

CREATE TRIGGER route_ic
   BEFORE INSERT ON route
   FOR EACH ROW EXECUTE PROCEDURE public.set_created();

/* Disable the new trigger. We'll enable it once we've populated the table. 
   See: db_load_add_constraints.sql. */
\qecho ... disabling trigger
ALTER TABLE route DISABLE TRIGGER route_ic;

\qecho 
\qecho Dropping foreign key constraints from '''route_feedback'''
\qecho 

/* NOTE: The V1->V2 upgrade scripts used to run with foreign key constraints
         instact (and sometimes created 'em along with the tables) but this
         has a noticeable performance impact and the foreign key constraints
         don't really do us any good... so drop 'em now and recreate them
         later. */

ALTER TABLE route_feedback DROP CONSTRAINT route_feedback_route_id_fkey;

\qecho 
\qecho Dropping foreign key constraints from '''route_step'''
\qecho 

ALTER TABLE route_step DROP CONSTRAINT route_step_byway_id_fkey;
ALTER TABLE route_step DROP CONSTRAINT route_step_route_id_fkey;

\qecho 
\qecho Dropping foreign key constraints from '''route_waypoint'''
\qecho 

ALTER TABLE route_waypoint DROP CONSTRAINT route_waypt_route_id_fkey;

\qecho 
\qecho Renaming table '''route_waypoint''' to '''route_stop'''
\qecho 

/* A waypoint is technically an x,y point on a GPS map (search the Web; this is
   the most common definition). So 'rstop' seems like a better term: i.e.,
   "what are the stops along the route?". */

ALTER TABLE route_waypoint RENAME TO route_stop;

ALTER INDEX route_waypoint_pkey
   RENAME TO route_stop_pkey; 

ALTER TABLE route_stop RENAME COLUMN waypt_number TO stop_number;

/* Fix 'bus_stop' boolean to conform to standards: prefix with 'is_'.
   Also, they're not all 'bus' stops: we also have light rail, commuter train,
   and magic carpet stops. */

ALTER TABLE route_stop RENAME COLUMN bus_stop TO is_transit_stop;

/* Fix the name of 'is_dest' and invert its meaning so the default is False
   (in Cyclopath, we like things to default to nothingness).
   NOTE: is_dest does not mean "is destination", i.e., is the final stop of the
         route. Rather, it means "is any destintation, including intermediate 
         destinations". The reason this value defaults to True in CcpV1 is
         because it's almost always True -- all route_stops (including the
         first one and last one, and all intermediate ones) are is_dest because
         they're all stops along the route. In pyserver, is_dest is always set
         to True whenever a route is calculated. The only time you end up with
         is_dest=False is when a user drags a route in flashclient to edit the
         route -- we make a new route_stop, but it's not a real stop. So let's
         call this 'rstop' a pass-through stop, i.e., the user wants to travel
         through that stop but not actually stop there (so we don't want to
         label that point on the map as a stop, but we want the route planner
         to use it as an intermediate origin/destination). */

ALTER TABLE route_stop ADD COLUMN is_pass_through BOOLEAN DEFAULT FALSE;
UPDATE route_stop SET is_pass_through = FALSE WHERE is_dest = TRUE;
UPDATE route_stop SET is_pass_through = TRUE WHERE is_dest = FALSE;
ALTER TABLE route_stop ALTER COLUMN is_pass_through SET NOT NULL;
ALTER TABLE route_stop DROP COLUMN is_dest;

\qecho 
\qecho Renaming table '''route_views''' to '''route_view'''
\qecho 

/* NOTE: Conventional database table naming schemes tend to avoid pluralizing
         table names unless the contents of one row are many. Which is why
         route_views is being renamed: each row of the table is just a single
         view (i.e., one username and one route_id). */

ALTER TABLE route_views RENAME TO route_view;

ALTER INDEX route_views_pkey RENAME TO route_view_pkey;

/* Rename the foreign key constraint (by dropping it and recreating anew). */
ALTER TABLE route_view DROP CONSTRAINT route_views_username_fkey;
ALTER TABLE route_view 
   ADD CONSTRAINT route_view_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username) 
      DEFERRABLE;

ALTER TRIGGER last_viewed_i ON route_view RENAME TO route_view_last_viewed_i;

/* FIXME: Can the route_view table be consumed by the soon-to-be-re-implemented
          item_watching feature? */

\qecho 
\qecho Skipping support table: '''travel_mode'''
\qecho 

/*  Skipping: travel_mode. It's a support table for route sharing. */

/* ====== */
/* TRACKS */
/* ====== */

/* Regarding the existing track table:
      visibility can be ignored -- it's always 3/'noone'
      permissions is 2 or 3 -- shared or private -- but never 1/public
        (FIXME: It might only ever be 3, actually.)
      z is always 0
      version _does_ increase (as name and comments change)
      type_code is always 2
      deleted is t or f
   */

\qecho 
\qecho (Re-)Creating table '''track'''
\qecho 

CREATE TABLE track (
   id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   owner_name TEXT,
   host INET,
   source TEXT,
   /* The comments will later be converted to link_valued annotations.
      See: 201-apb-60-groups-pvt_ins3.sql */
   comments TEXT,
   created TIMESTAMP WITH TIME ZONE NOT NULL,
   permission INTEGER DEFAULT 3 NOT NULL,
   --?session_id TEXT,
   visibility INTEGER DEFAULT 3 NOT NULL
);

ALTER TABLE track 
   ADD CONSTRAINT track_pkey 
   PRIMARY KEY (id, version);

\qecho 
\qecho Creating trigger on table '''track'''
\qecho 

CREATE TRIGGER track_ic
   BEFORE INSERT ON track
   FOR EACH ROW EXECUTE PROCEDURE public.set_created();

\qecho ... disabling trigger
ALTER TABLE track DISABLE TRIGGER track_ic;

/* ==================================================================== */
/* Step (7.5)                                                           */
/* ==================================================================== */

/* BUG nnnn: track_point needs a primary key... */

/* Bug 2729 - Database: Some tables have duplicate rows (and no primary key) */
CREATE FUNCTION duplicates_fix_track_point()
   RETURNS VOID AS $$
   BEGIN
      RAISE INFO 'Bug 2729: Removing duplicates from track_point...';
      ALTER TABLE track_point SET SCHEMA archive_@@@instance@@@_1;
      CREATE TABLE track_point (
         id INTEGER,
         track_id INTEGER NOT NULL,
         track_version INTEGER NOT NULL,
         --x INTEGER NOT NULL,
         --y INTEGER NOT NULL,
         -- 2013.05.11: For Conflation, we're keeping it reals.
         x REAL NOT NULL,
         y REAL NOT NULL,
         timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
         altitude REAL,
         bearing REAL,
         speed REAL,
         orientation REAL,
         temperature REAL
      );
      INSERT INTO track_point
         (id, track_id, track_version, x, y, timestamp,
          altitude, bearing, speed, orientation, temperature)
         SELECT DISTINCT (id), track_id, track_version, x::REAL, y::REAL,
          timestamp, altitude, bearing, speed, orientation, temperature
         FROM archive_@@@instance@@@_1.track_point ORDER BY id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT duplicates_fix_track_point();
/* NOTE: In a later script, we'll add a step_number column and then add a
         primary key. */

/* BUG 2407: track_point id should be like route_step.step_number. */
/* BUG 2407: What's track_point.track_version? When you change comments, 
 *           that bumps version, and then new tracks are saved with new 
 *           version #? seems weird... */
ALTER TABLE track_point ADD COLUMN step_number INTEGER;
/* NOTE: Should also be NOT NULL; added in a later script. */

/* ==================================================================== */
/* Step (8) -- FIX TRACK TABLE                                          */
/* ==================================================================== */

\qecho 
\qecho Fixing overlapping track.valid_*_rid values
\qecho 

/* BUG 2408: Tracks violate the unique start rid contract...

select * from track order by id asc, version asc;

old track versions all have valid_before_rid of 0!

SELECT * 
FROM item_versioned AS iv1
JOIN item_versioned AS iv2
ON (    iv1.branch_id = iv2.branch_id 
    AND iv1.stack_id = iv2.stack_id
    AND iv1.valid_start_rid = iv2.valid_start_rid
    AND (   iv1.system_id != iv2.system_id
         OR iv1.version != iv2.version
         OR iv1.deleted != iv2.deleted
         OR iv1.name != iv2.name
         OR iv1.valid_until_rid != iv2.valid_until_rid))
ORDER BY iv1.branch_id,iv1.stack_id,iv1.version
   ;
*/

CREATE FUNCTION track_fix_rids()
   RETURNS VOID AS $$
   BEGIN
      UPDATE archive_@@@instance@@@_1.track
         SET valid_starting_rid = version;
      EXECUTE '
         UPDATE archive_@@@instance@@@_1.track
            SET valid_before_rid = version + 1
            WHERE valid_before_rid != ' || cp_rid_inf() || ';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT track_fix_rids();

DROP FUNCTION track_fix_rids();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;


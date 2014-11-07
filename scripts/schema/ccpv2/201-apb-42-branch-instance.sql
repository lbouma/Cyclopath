/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adds the new branch tables and creates a branch for the public
   base map. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

/* PERFORMACE NOTE: If you create indexes and foreign keys on the tables being
 *                  updated herein, the script execution time explodes, from 
 *                  around 10 minutes to over three hours. */
/*      2011.04.23: The script time decreased, from 10.5 to 2.35 minutes.... 
 *                  to 1.14 minutes on the following Monday, after I added back
 *                  primary keys. */

\qecho 
\qecho This script adds the new branch tables and creates a branch for the 
\qecho public base map
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 1.14 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.59 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Create branch and branch_conflict tables                 */
/* ==================================================================== */

\qecho 
\qecho Creating table '''branch'''
\qecho 

/* NOTE: Including branch_id (same as stack_id) since branch derives 
 *       from item_versioned (so it shares its columns). */

CREATE TABLE branch (
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
   parent_id INTEGER DEFAULT NULL, -- parent's stack_id
   last_merge_rid INTEGER DEFAULT 0,
   conflicts_resolved BOOLEAN DEFAULT TRUE,
   import_callback TEXT,
   export_callback TEXT,
   /* tile_skins is a comma-separated list of skins to use to tile, or NULL or
    * empty if the branch does not get tiles. */
   tile_skins TEXT DEFAULT NULL
);

ALTER TABLE branch
   ADD CONSTRAINT branch_pkey 
   PRIMARY KEY (system_id);

/* 2013.01.12: Wow, great last minute ideas! Consuming coverage_area herein.
               Makes sense, non? See Bug nnnn. */
\set dimension 2
SELECT AddGeometryColumn('branch', 'coverage_area', (SELECT cp_srid()), 
                         'GEOMETRY', :dimension);

\qecho 
\qecho Creating table '''branch_conflict'''
\qecho 

CREATE TABLE branch_conflict (
   branch_system_id INTEGER NOT NULL,
   item_id_left INTEGER NOT NULL,
   item_id_right INTEGER NOT NULL,
   conflict_resolved BOOLEAN DEFAULT FALSE
);

ALTER TABLE branch_conflict 
   ADD CONSTRAINT branch_conflict_pkey 
   PRIMARY KEY (branch_system_id, item_id_left, item_id_right);

/* ==================================================================== */
/* Step (2) -- Create Public Base Map branch ("Baseline")               */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcn. to create branch for public base map
\qecho 

CREATE FUNCTION basemap_create()
   RETURNS INTEGER AS $$
   DECLARE
      public_map_name TEXT;
      iv_system_id INTEGER;
      iv_stack_id INTEGER;
   BEGIN
      IF '@@@instance@@@' = 'minnesota' THEN
         public_map_name := 'Mpls-St. Paul';
      ELSIF '@@@instance@@@' = 'colorado' THEN
         public_map_name := 'Denver-Boulder';
      ELSE
         RAISE EXCEPTION 'Not a recognized instance! @@@instance@@@.';
      END IF;
      INSERT INTO item_versioned 
         (version, name, deleted, reverted,
          valid_start_rid, valid_until_rid)
      VALUES 
         (1, public_map_name, FALSE, FALSE, 1, cp_rid_inf());
      iv_system_id := CURRVAL('item_versioned_system_id_seq');
      iv_stack_id := CURRVAL('item_stack_stack_id_seq');
      /* Don't forget to set the branch_id to stack_id. */
      EXECUTE 'UPDATE item_versioned 
               SET branch_id = stack_id 
               WHERE system_id = ' || iv_system_id || ';';
      /* Create the branch row. */
      /* MAGIC NUMBER: 'bikeways' is named after
                       mapserver/skins/skin_bikeways.py */
      INSERT INTO branch
         (system_id, branch_id, stack_id, version, tile_skins) 
         VALUES (iv_system_id, iv_stack_id, iv_stack_id, 1, 'bikeways');
      -- NO! RETURN iv_system_id;
      RETURN iv_stack_id;
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Creating convenience fcn. to get ID of public base map
\qecho 

/* NOTE This is a Convenience fcn. for pyserver.
        This is not a temporary fcn.; we will not be deleting it. */
/* NOTE This fcn. used to be defined in the public schema, but that was in
        error: the fcn. uses the instance's key_value_pair table, so it 
        worked in some instances (pyserver) but failed in others (mapserver)
        that didn't explicitly set the search_path (or something, I [lb] 
        don't really remember the problem, which happened two weeks before I 
        got around to writing this comment...!). */
CREATE FUNCTION cp_branch_baseline_id()
   RETURNS INTEGER AS $$
   BEGIN
      RETURN value::INTEGER FROM @@@instance@@@.key_value_pair 
         WHERE key = 'cp_branch_baseline_id';
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Creating branch for public base map
\qecho 

INSERT INTO key_value_pair (key, value) 
   VALUES ('cp_branch_baseline_id', basemap_create());

\qecho 
\qecho Public base map created with branch ID:
SELECT cp_branch_baseline_id();
\qecho 

\qecho 
\qecho Cleaning up helper fcn.
\qecho 

DROP FUNCTION basemap_create();

/* ==================================================================== */
/* Step (3) -- Add Branch IDs to Item_Versioned and revision tables     */
/* ==================================================================== */

/* ================================== */
/* Branching: Helper fcn.             */
/* ================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

CREATE FUNCTION item_table_add_branch_id(IN table_name TEXT)
   RETURNS VOID AS $$
   DECLARE
      branch_baseline_id INTEGER;
   BEGIN
      branch_baseline_id := cp_branch_baseline_id();
      /* == Branch ID == */
      /* Populate the branch column */
      EXECUTE 'UPDATE ' || table_name || 
         ' SET branch_id = ' || branch_baseline_id || ';';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ================================== */
/* Branching: Apply all               */
/* ================================== */

\qecho 
\qecho Adding and populating Branch ID columns
\qecho 

/* Start w/ the base table */
\qecho ...item_versioned
SELECT item_table_add_branch_id('item_versioned');
/* Do the intermediate tables */
\qecho ...attachment
SELECT item_table_add_branch_id('attachment');
\qecho ...geofeature
SELECT item_table_add_branch_id('geofeature');
\qecho ...link_value
SELECT item_table_add_branch_id('link_value');
/* Do the attachment tables */
\qecho ...tag
SELECT item_table_add_branch_id('tag');
\qecho ...annotation
SELECT item_table_add_branch_id('annotation');
\qecho ...thread
SELECT item_table_add_branch_id('thread');
\qecho ...post
SELECT item_table_add_branch_id('post');
\qecho ...attribute
SELECT item_table_add_branch_id('attribute');
/* Do the geofeature tables */
\qecho ...route
SELECT item_table_add_branch_id('route');
\qecho ...track
SELECT item_table_add_branch_id('track');
/* Do the attachment and geofeature support tables */
\qecho ...aadt
SELECT item_table_add_branch_id('aadt');
\qecho ...byway_rating
SELECT item_table_add_branch_id('byway_rating');
\qecho ...byway_rating_event
SELECT item_table_add_branch_id('byway_rating_event');
\qecho ...reaction_reminder
SELECT item_table_add_branch_id('reaction_reminder');
/* 2012.10.04: Route Feedback Drag. */
/* NOTE: Skipping:
           route_feedback:      has route system ID
           route_feedback_drag: has old_route and new_route
                                system IDs
         but route_feedback_stretch just has a branch stack ID,
         so we need to know the branch.
   MAYBE: route_feedback_stretch has a route_feedback_drag ID, so
          we probably do not need the branch ID here, since we can
          get it from old_route or new_route? */
\qecho ...route_feedback_stretch
SELECT item_table_add_branch_id('route_feedback_stretch');
\qecho ...route_priority
SELECT item_table_add_branch_id('route_priority');
\qecho ...route_tag_preference
SELECT item_table_add_branch_id('route_tag_preference');
/* MAYBE: We probably don't need the branch ID in route_view, since we have a
          route stack ID, and routes are not used across branches (or could
          they be?). */
\qecho ...route_view
SELECT item_table_add_branch_id('route_view');
\qecho ...tag_preference
SELECT item_table_add_branch_id('tag_preference');
\qecho ...tag_preference_event
SELECT item_table_add_branch_id('tag_preference_event');

/* Also do the revision table */
\qecho ...revision
SELECT item_table_add_branch_id('revision');

/* ================================== */
/* Branching: Cleanup                 */
/* ================================== */

DROP FUNCTION item_table_add_branch_id(IN table_name TEXT);

/* ==================================================================== */
/* Step (4) -- Add branch constraints                                   */
/* ==================================================================== */

/* NOTE Postgresql is unhappy with us doing more to the tables, complaining, 

           ERROR: cannot ALTER TABLE "item_versioned" 
                  because it has pending trigger events

        Consequently, commit the above changes and we'll continue with the
        remaining changes in the next script.

        2011.04.23: This is good, anyway. If we create indices or constraints 
        and then do a lot of inserts or updates, it takes a really long time.
        */

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

/* This used to not take so long, or at least my notes suggest as much. 
 * As of 2011.04.23, this is taking tens of minutes, not tens of seconds! */

\qecho 
\qecho Done!
\qecho 

COMMIT;


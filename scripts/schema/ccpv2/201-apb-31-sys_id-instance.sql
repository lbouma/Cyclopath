/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This and the following scripts introduce branching and permissions to the 
   database schema.

   This is a major change. It touches most of the tables in the database. 
   
   This script prepares the new item ID scheme. It renames id to stack_id and 
   creates two new IDs, system_id and branch_id. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho
\qecho This script adds system_id & branch_id and renames id to stack_id
\qecho
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.51 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.19 min. [mn]]
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (0) -- Preamble: No code, just comments                         */
/* ==================================================================== */

/* Setting up branching requires lots of changes to existing tables.

   Because of existing foreign keys and constraints, this process is a little
   convoluted -- we have to create columns and shuffle data around before we
   can correct foreign keys and constraints, and in some cases we have to
   commit one set of changes before we can proceed with another. As such, this 
   is the first of many scripts needed to complete this operation. */

/* ==================================================================== */
/* Step (1) -- Item_Versioned: Rename ID sequence                       */
/* ==================================================================== */

\qecho 
\qecho Renaming Item_Versioned sequence, from id to stack id seq
\qecho 

/* 2012.09.21: There's a new table, item_stack, which now maintains the stack
               ID, and though the table won't be defined for a number of 
               scripts, it makes things easier to rename it now. */
/* Old CcpV2: 
    ALTER TABLE item_versioned_id_seq RENAME TO item_versioned_stack_id_seq; */
ALTER TABLE item_versioned_id_seq RENAME TO item_stack_stack_id_seq;

/* ==================================================================== */
/* Step (2) -- Item_Versioned: Add system_id, branch_id,          */
/*             stack_id cols                                            */
/* ==================================================================== */

\qecho 
\qecho Creating Item_Versioned cols: system_id, stack_id, and branch_id
\qecho 

ALTER TABLE item_versioned ADD COLUMN system_id INTEGER;
ALTER TABLE item_versioned RENAME COLUMN id TO stack_id;
ALTER TABLE item_versioned ADD COLUMN branch_id INTEGER;

/* NOTE: We'll add indices in the next SQL script, when we fix CONSTRAINTs. */

/* ==================================================================== */
/* Step (3) -- Item_Versioned: Create System ID sequence                */
/* ==================================================================== */

\qecho 
\qecho Initializing system_id for all rows in item_versioned
\qecho 

/* FIXME Should this be public or instance? If public, move to public file */
--CREATE SEQUENCE public.item_versioned_system_id_seq;
CREATE SEQUENCE item_versioned_system_id_seq;

/* Populate 'system_id' -- set a unique value for every row in the table */
UPDATE item_versioned SET system_id = NEXTVAL('item_versioned_system_id_seq');

ALTER SEQUENCE item_versioned_system_id_seq OWNED BY item_versioned.system_id;

/* ==================================================================== */
/* Step (4) -- Revision: Add branch_id col                        */
/* ==================================================================== */

\qecho 
\qecho Creating revision column: branch_id
\qecho 

/* FIXME 2010.11.11: Still not quite sure we need this column... */

ALTER TABLE revision ADD COLUMN branch_id INTEGER;

-- FIXME Check that this is in group_revision

/* ==================================================================== */
/* Step (5) -- Add System and Branch IDs: Create helper function        */
/* ==================================================================== */

\qecho 
\qecho Creating temporary helper fcn. to alter dependent tables
\qecho 

CREATE FUNCTION item_table_update_id_cols(IN table_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      -- == Stack ID ==
      -- Change 'id' to 'stack_id'
      EXECUTE 'ALTER TABLE ' || table_name || ' RENAME COLUMN id TO stack_id;';
      -- == System ID ==
      EXECUTE 'ALTER TABLE ' || table_name || ' ADD COLUMN system_id INTEGER;';
      -- == Branch ID ==
      EXECUTE 'ALTER TABLE ' || table_name || ' ADD COLUMN branch_id INTEGER;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ==================================================================== */
/* Step (6) -- Add System and Branch IDs: Attachment tables             */
/* ==================================================================== */

\qecho 
\qecho Fixing ID columns in Attachment tables
\qecho 

\qecho ...tag
SELECT item_table_update_id_cols('tag');
\qecho ...annotation
SELECT item_table_update_id_cols('annotation');
\qecho ...thread
SELECT item_table_update_id_cols('thread');
\qecho ...post
SELECT item_table_update_id_cols('post');
\qecho ...attribute
SELECT item_table_update_id_cols('attribute');
-- Save the base table for last, so we don't have to fudge and use CASCADE
\qecho ...attachment
SELECT item_table_update_id_cols('attachment');

/* 2012.11.01: Don't forget post's thread_id, which is the stack_id, not the
 * system_id. */
ALTER TABLE post RENAME COLUMN thread_id TO thread_stack_id;

/* DFER We'll change the Geofeature support tables in a later script, since the
        operation isn't easily generalizable. */

/* ==================================================================== */
/* Step (7) -- Add System and Branch IDs: Geofeature tables             */
/* ==================================================================== */

\qecho 
\qecho Adding System ID to Geofeature tables
\qecho 

-- Do the child tables first
\qecho ...route
SELECT item_table_update_id_cols('route');
\qecho ...track
SELECT item_table_update_id_cols('track');
-- Do the intermediate table second
\qecho ...geofeature
SELECT item_table_update_id_cols('geofeature');

\qecho 
\qecho Geofeature: Renaming 'split_from_id' => 'split_from_stack_id'
\qecho 

ALTER TABLE geofeature RENAME COLUMN split_from_id TO split_from_stack_id;

/* ==================================================================== */
/* Step (8) -- Add System and Branch IDs: Link_Value table              */
/* ==================================================================== */

\qecho 
\qecho Adding System ID to Link_Value table
\qecho 

SELECT item_table_update_id_cols('link_value');

\qecho 
\qecho Link_Value: Changing fkey names
\qecho 

ALTER TABLE link_value
   RENAME COLUMN rhs_id TO rhs_stack_id;
ALTER TABLE link_value
   RENAME COLUMN lhs_id TO lhs_stack_id;

/* ==================================================================== */
/* Step (9) -- Add System and Branch IDs: Cleanup                       */
/* ==================================================================== */

DROP FUNCTION item_table_update_id_cols(IN table_name TEXT);

/* ==================================================================== */
/* Step (10) -- Add Branch ID to *versioned* support tables             */
/* ==================================================================== */

/* ================================== */
/* Support tables: Helper fcn.        */
/* ================================== */

\qecho 
\qecho Creating helper fcn. for versioned support tables
\qecho 

CREATE FUNCTION item_table_fix_id_versioned(
      IN table_name TEXT, IN idvers_prefix TEXT)
   RETURNS VOID AS $$
   BEGIN
      -- == Stack ID ==
      -- Rename the existing *_id, which is the stack ID
      EXECUTE 'ALTER TABLE ' || table_name || ' 
                  RENAME COLUMN ' || idvers_prefix || '_id 
                             TO ' || idvers_prefix || '_stack_id;';
      -- == System ID ==
      -- Create a column for system id, using same name as that just renamed
      EXECUTE 'ALTER TABLE ' || table_name || ' 
                  ADD COLUMN ' || idvers_prefix || '_id INTEGER;';
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ================================== */
/* Support tables: Disable triggers   */
/* ================================== */

/* NOTE route_feedback has a fail() trigger if you try updating rows, so we 
        need to disable it to update the table */
ALTER TABLE route_feedback       DISABLE TRIGGER route_feedback_i;
ALTER TABLE route_feedback       DISABLE TRIGGER route_feedback_u;

/* 2012.10.04: Route Feedback Drag. */
ALTER TABLE route_feedback_drag  DISABLE TRIGGER route_feedback_drag_i;
ALTER TABLE route_feedback_drag  DISABLE TRIGGER route_feedback_drag_u;

ALTER TABLE aadt                 DISABLE TRIGGER aadt_ilm;
ALTER TABLE aadt                 DISABLE TRIGGER aadt_u;

ALTER TABLE byway_rating         DISABLE TRIGGER byway_rating_ilm;
ALTER TABLE byway_rating         DISABLE TRIGGER byway_rating_u;

ALTER TABLE byway_rating_event   DISABLE TRIGGER byway_rating_event_i;
ALTER TABLE byway_rating_event   DISABLE TRIGGER byway_rating_event_u;

ALTER TABLE tag_preference       DISABLE TRIGGER tag_preference_ilm;
ALTER TABLE tag_preference       DISABLE TRIGGER tag_preference_u;

ALTER TABLE tag_preference_event DISABLE TRIGGER tag_preference_event_i;
ALTER TABLE tag_preference_event DISABLE TRIGGER tag_preference_event_u;

/* ================================== */
/* Support tables: Apply all          */
/* ================================== */

\qecho 
\qecho Fixing ID columns in versioned support tables
\qecho 

\qecho ...route_feedback
SELECT item_table_fix_id_versioned('route_feedback', 'route');
/* 2012.10.04: Route Feedback Drag. */
\qecho ...route_feedback_drag (old_route)
SELECT item_table_fix_id_versioned('route_feedback_drag', 'old_route');
\qecho ...route_feedback_drag (new_route)
SELECT item_table_fix_id_versioned('route_feedback_drag', 'new_route');
\qecho ...route_step (byway)
SELECT item_table_fix_id_versioned('route_step', 'byway');
\qecho ...route_step (route)
SELECT item_table_fix_id_versioned('route_step', 'route');
\qecho ...route_stop (route)
SELECT item_table_fix_id_versioned('route_stop', 'route');
\qecho ...track_point (track)
SELECT item_table_fix_id_versioned('track_point', 'track');

/* ================================== */
/* Support tables: Cleanup            */
/* ================================== */

DROP FUNCTION item_table_fix_id_versioned(
   IN table_name TEXT, IN idvers_prefix TEXT);

/* ==================================================================== */
/* Step (11) -- Add Branch ID to *versionless* support tables           */
/* ==================================================================== */

/* These tables only have IDs (no Versions) */

/* ================================== */
/* Support tables: Helper fcn.        */
/* ================================== */

\qecho 
\qecho Creating helper fcn. for versionless support tables
\qecho 

CREATE FUNCTION item_table_fix_id_versionless(
      IN table_name TEXT, IN id_prefix TEXT, IN add_branch_col BOOLEAN)
   RETURNS VOID AS $$
   BEGIN
      -- == Stack ID ==
      -- Change '*_id' to '*_stack_id'
      EXECUTE 'ALTER TABLE ' || table_name || ' 
                  RENAME COLUMN ' || id_prefix || '_id 
                             TO ' || id_prefix || '_stack_id;';
      -- == Branch ID ==
      IF (add_branch_col) THEN
         EXECUTE 'ALTER TABLE ' || table_name || ' 
                     ADD COLUMN branch_id INTEGER;';
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ================================== */
/* Support tables: Apply all          */
/* ================================== */

\qecho 
\qecho Changing ID to stack ID and adding branch ID to support tables
\qecho 

-- FIXME Are aadt, byway_rating, etc. still referencing archived tables?

\qecho ...aadt
SELECT item_table_fix_id_versionless('aadt', 'byway', TRUE);
\qecho ...byway_rating
SELECT item_table_fix_id_versionless('byway_rating', 'byway', TRUE);
\qecho ...byway_rating_event
SELECT item_table_fix_id_versionless('byway_rating_event', 'byway', TRUE);
\qecho ...reaction_reminder
SELECT item_table_fix_id_versionless('reaction_reminder', 'route', TRUE);
/* 2012.10.04: Route Feedback Drag. */
\qecho ...route_feedback_stretch
SELECT item_table_fix_id_versionless('route_feedback_stretch', 'byway', TRUE);
\qecho ...route_priority
SELECT item_table_fix_id_versionless('route_priority', 'route', TRUE);
\qecho ...route_tag_preference (route)
SELECT item_table_fix_id_versionless('route_tag_preference', 'route', TRUE);
\qecho ...route_tag_preference (tag)
SELECT item_table_fix_id_versionless('route_tag_preference', 'tag', FALSE);
\qecho ...route_view
SELECT item_table_fix_id_versionless('route_view', 'route', TRUE);
\qecho ...tag_preference
SELECT item_table_fix_id_versionless('tag_preference', 'tag', TRUE);
\qecho ...tag_preference_event
SELECT item_table_fix_id_versionless('tag_preference_event', 'tag', TRUE);

/* ================================== */
/* Support tables: Cleanup            */
/* ================================== */

DROP FUNCTION item_table_fix_id_versionless(
   IN table_name TEXT, IN id_prefix TEXT, IN add_branch_col BOOLEAN);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


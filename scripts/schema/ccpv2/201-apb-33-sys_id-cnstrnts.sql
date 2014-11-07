/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script fixes constraints to use system_id and branch_id. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script corrects table constraints affected by the new ids
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.39 mins. (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.08 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (0)                                                             */
/* ==================================================================== */

/* Bug 2729 - Colorado: Database: Some tables have duplicate rows 
              (i.e., no primary key). */
CREATE FUNCTION colorado_fix_aadt()
   RETURNS VOID AS $$
   BEGIN
      -- Absorb the contents of from_table
      /* BUG 2729: Colorado data has duplicate rows, i.e., same id and version.
       *           So we have to use DISTINCT here... */
      -- FIXME: Make sure aadt (and other tables) make branch_id NOT NULL
      IF '@@@instance@@@' = 'colorado' THEN
         RAISE INFO 'Bug 2729: Fixing colorado.aadt';
         ALTER TABLE aadt SET SCHEMA archive_@@@instance@@@_1;
         CREATE TABLE aadt (
            byway_stack_id INTEGER NOT NULL,
            aadt INTEGER NOT NULL,
            last_modified TIMESTAMP WITH TIME ZONE NOT NULL,
            branch_id INTEGER);
         CREATE TRIGGER aadt_ilm
            BEFORE INSERT ON aadt
            FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
         CREATE TRIGGER aadt_u
            BEFORE UPDATE ON aadt
            FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
         ALTER TABLE aadt DISABLE TRIGGER aadt_ilm;
         ALTER TABLE aadt DISABLE TRIGGER aadt_u;
         INSERT INTO aadt
            (byway_stack_id, branch_id, aadt, last_modified)
            SELECT DISTINCT (byway_stack_id), branch_id, aadt, last_modified
            FROM archive_@@@instance@@@_1.aadt ORDER BY byway_stack_id;
         /* We need to recreate the primary key since we're about to drop it,
          * but branch_id isn't set, so don't include it in the pkey. */
         ALTER TABLE aadt
            ADD CONSTRAINT aadt_pkey
            PRIMARY KEY (byway_stack_id);
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT colorado_fix_aadt();

/* ==================================================================== */
/* Step (1) -- Drop old constraints                                     */
/* ==================================================================== */

/* ================================== */
/* * Versionless * Support tables     */
/* ================================== */

\qecho 
\qecho Dropping primary keys on versionless support tables
\qecho 

/* These tables reference an item at any version, i.e., they use an item's 
   stack_id and branch_id, but not version. */

ALTER TABLE aadt                 DROP CONSTRAINT aadt_pkey;
ALTER TABLE byway_rating         DROP CONSTRAINT byway_rating_pkey;
ALTER TABLE route_priority       DROP CONSTRAINT route_priority_pkey;
ALTER TABLE route_tag_preference DROP CONSTRAINT route_tag_preference_pkey;
ALTER TABLE tag_preference       DROP CONSTRAINT tag_preference_pkey;

DROP INDEX byway_rating_byway_id;
DROP INDEX byway_rating_last_modified;
ALTER TABLE byway_rating 
   DROP CONSTRAINT username_fk;

ALTER TABLE byway_rating_event 
   DROP CONSTRAINT byway_rating_event_username_fkey;

ALTER TABLE route_tag_preference 
   DROP CONSTRAINT route_tag_preference_type_code_fkey;

DROP INDEX tag_preference_tag_id;
ALTER TABLE tag_preference 
   DROP CONSTRAINT tag_preference_type_code_fkey;
ALTER TABLE tag_preference 
   DROP CONSTRAINT tag_preference_username_fkey;

ALTER TABLE tag_preference_event 
   DROP CONSTRAINT tag_preference_event_type_code_fkey;

ALTER TABLE tag_preference_event 
   DROP CONSTRAINT tag_preference_event_username_fkey;

/* FIXME: Are we missing: reaction_reminder, route_view, route_feeback_drag,
 *        route_feedback_stretch? */

/* */

DROP INDEX revision_geometry;

ALTER TABLE revision 
   DROP CONSTRAINT revision_enforce_permissions;
ALTER TABLE revision 
   DROP CONSTRAINT revision_enforce_visibility;

ALTER TABLE revision 
   DROP CONSTRAINT revision_permission_fkey;
ALTER TABLE revision 
   DROP CONSTRAINT revision_username_fk;

/* ==================================================================== */
/* Step (5) -- Set ID sequence defaults                                 */
/* ==================================================================== */

\qecho 
\qecho Setting System ID sequence as default
\qecho 

ALTER TABLE item_versioned 
   ALTER COLUMN system_id 
      SET DEFAULT NEXTVAL('item_versioned_system_id_seq');

/* ==================================================================== */
/* Step (6) -- Change primary keys                                      */
/* ==================================================================== */

\qecho 
\qecho Creating helper fcn.
\qecho 

CREATE FUNCTION item_table_change_primary_key(IN table_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      EXECUTE 'ALTER TABLE ' || table_name || ' 
                  DROP CONSTRAINT ' || table_name || '_pkey;';

      EXECUTE 'ALTER TABLE ' || table_name || ' 
                  ADD CONSTRAINT ' || table_name || '_pkey 
                  PRIMARY KEY (system_id);';
   END;
$$ LANGUAGE plpgsql VOLATILE;

\qecho 
\qecho Changing Primary key on Item_Versioned and derived tables
\qecho 

/* Base tables. */
\qecho ...item_versioned
SELECT item_table_change_primary_key('item_versioned');
/* Intermediate tables. */
\qecho ...attachment
SELECT item_table_change_primary_key('attachment');
\qecho ...geofeature
SELECT item_table_change_primary_key('geofeature');
\qecho ...link_value
SELECT item_table_change_primary_key('link_value');
/* Attachment tables. */
\qecho ...tag
SELECT item_table_change_primary_key('tag');
\qecho ...annotation
SELECT item_table_change_primary_key('annotation');
\qecho ...thread
SELECT item_table_change_primary_key('thread');
\qecho ...post
SELECT item_table_change_primary_key('post');
\qecho ...attribute
SELECT item_table_change_primary_key('attribute');
/* Geofeature tables. */
\qecho ...route
SELECT item_table_change_primary_key('route');
\qecho ...track
SELECT item_table_change_primary_key('track');

\qecho 
\qecho Removing helper fcn.
\qecho 

DROP FUNCTION item_table_change_primary_key(IN table_name TEXT);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


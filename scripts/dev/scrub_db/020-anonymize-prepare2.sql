/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script drops constraints and indexes columns so that the next few 
 * scripts run efficiently. */

/* FIXME: These scripts do not remove the indices. Should we remove them, 
          or should we keep the indices (and add to the trunk)? */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script drops constraints and indexes columns so that the next 
\qecho few scripts run efficiently.
\qecho 
--\qecho [EXEC. TIME: 2011.04.25/Huffy: ~ x mins (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.02.12: 0.13 mins. [runic]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Create column indices on tables shared in CCPs V1 and V2.*/
/* ==================================================================== */

DROP INDEX IF EXISTS log_event_username;
CREATE INDEX log_event_username ON log_event (username);
DROP INDEX IF EXISTS log_event_kvp_event_id;
CREATE INDEX log_event_kvp_event_id ON log_event_kvp (event_id);

--DROP INDEX IF EXISTS revision_feedback_username;
--CREATE INDEX revision_feedback_username ON revision_feedback (username);
DROP INDEX IF EXISTS revision_feedback_link_rf_id;
CREATE INDEX revision_feedback_link_rf_id ON revision_feedback_link (rf_id);
DROP INDEX IF EXISTS revision_username;
CREATE INDEX revision_username ON revision (username);

--DROP INDEX IF EXISTS route_feedback_username;
--CREATE INDEX route_feedback_username ON route_feedback (username);

--DROP INDEX IF EXISTS group_revision_group_id;
--CREATE INDEX group_revision_group_id ON group_revision (group_id);

DROP INDEX IF EXISTS tag_preference_username;
CREATE INDEX tag_preference_username ON tag_preference (username);
DROP INDEX IF EXISTS tag_preference_event_username;
CREATE INDEX tag_preference_event_username ON tag_preference_event (username);

DROP INDEX IF EXISTS byway_rating_username;
CREATE INDEX byway_rating_username ON byway_rating (username);
DROP INDEX IF EXISTS byway_rating_event_username;
CREATE INDEX byway_rating_event_username ON byway_rating_event (username);

/* ==================================================================== */
/* Step (2) -- Create column indices on tables new in Cyclopath V2.     */
/* ==================================================================== */

CREATE FUNCTION scrub_tables_v1()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         DROP INDEX IF EXISTS region_watcher_username;
         CREATE INDEX region_watcher_username ON region_watcher (username);

         DROP INDEX IF EXISTS thread_read_event_username;
         CREATE INDEX thread_read_event_username 
                   ON thread_read_event(username);

         DROP INDEX IF EXISTS thread_watcher_username;
         CREATE INDEX thread_watcher_username ON thread_watcher (username);

      EXCEPTION WHEN undefined_table THEN
         /* No-op: this is the V2 database. */
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE FUNCTION scrub_tables_v2()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         DROP INDEX IF EXISTS group_membership_user_id;
         CREATE INDEX group_membership_user_id ON group_membership (user_id);
         DROP INDEX IF EXISTS group_membership_group_id;
         CREATE INDEX group_membership_group_id ON group_membership (group_id);
         DROP INDEX IF EXISTS group_membership_username;
         CREATE INDEX group_membership_username ON group_membership (username);

         --DROP INDEX IF EXISTS group__stack_id;
         --CREATE INDEX group__stack_id ON group_ (stack_id);
         DROP INDEX IF EXISTS group__access_scope_id;
         CREATE INDEX group__access_scope_id ON group_ (access_scope_id);
         DROP INDEX IF EXISTS group__name;
         CREATE INDEX group__name ON group_ (name);

         --DROP INDEX IF EXISTS group_item_access_group_id;
         --CREATE INDEX group_item_access_group_id 
         --          ON group_item_access (group_id);
         DROP INDEX IF EXISTS group_item_access_item_id;
         CREATE INDEX group_item_access_item_id 
                   ON group_item_access (item_id);
         --DROP INDEX IF EXISTS group_item_access_level_id;
         --CREATE INDEX group_item_access_level_id 
         --          ON group_item_access (access_level_id);
         DROP INDEX IF EXISTS group_item_access_item_type_id;
         CREATE INDEX group_item_access_item_type_id 
                   ON group_item_access (item_type_id);

         DROP INDEX IF EXISTS item_event_read_username;
         CREATE INDEX item_event_read_username ON item_event_read(username);

         /* 2013.04.22: [lb] preserved some tables in the V1->V2 schema upgrade
            so link_attributes_populate.py can use them first (that script then
            deletes these tables). But we run from the upgrade scripts... */

         PERFORM cp_constraint_drop_safe('route_view',
                                         'route_view_username_fkey');
         PERFORM cp_constraint_drop_safe('watch_region',
                                         'watch_region_username_fkey');
         PERFORM cp_constraint_drop_safe('region_watcher',
                                         'region_watcher_username_fkey');
         -- Skipping/Nothing to do ([lb] assumes missing fkey constraint?):
         --    thread_watcher

      EXCEPTION WHEN undefined_table THEN
         /* No-op: this is the V1 database. */
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT scrub_tables_v1();
SELECT scrub_tables_v2();

DROP FUNCTION scrub_tables_v1();
DROP FUNCTION scrub_tables_v2();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


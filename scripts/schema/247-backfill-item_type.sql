/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho
\qecho Backfill item_type with deprecated so does not look like missing rows
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Backfill item_type with deprecated so does not look like missing rows
\qecho

INSERT INTO item_type (id, type_name) VALUES (35, 'item_watcher_DEPRECATED');
INSERT INTO item_type (id, type_name) VALUES (36,
                                             'item_watcher_change_DEPRECATED');
INSERT INTO item_type (id, type_name) VALUES (38, 'byway_node_DEPRECATED');
INSERT INTO item_type (id, type_name) VALUES (39, 'route_waypoint_DEPRECATED');
INSERT INTO item_type (id, type_name) VALUES (48, 'item_stack_INTERMEDIATE');
INSERT INTO item_type (id, type_name) VALUES (49,
                                            'item_versioned_INTERMEDIATE');
INSERT INTO item_type (id, type_name) VALUES (51,
                                            'item_user_watching_INTERMEDIATE');

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Item_Type: Add item_revisionless item_type
\qecho

DELETE FROM item_type WHERE id = 59;
INSERT INTO item_type (id, type_name) VALUES (59, 'item_revisionless');

/* ==================================================================== */
/*                                                                      */
/* ==================================================================== */

\qecho
\qecho Bugfix: Unrenamed columns in user_preference_event table
\qecho


DROP FUNCTION IF EXISTS update_user_preference_event_table();

CREATE FUNCTION update_user_preference_event_table()
   RETURNS VOID AS $$
   BEGIN
      BEGIN
         ALTER TABLE user_preference_event
            RENAME COLUMN rf_transit_pref TO rf_p2_transit_pref;
         ALTER TABLE user_preference_event
            RENAME COLUMN rf_priority TO rf_p1_priority;
      EXCEPTION
         WHEN OTHERS THEN
            /* E.g., "ERROR: constraint "..." does not exist" */
            /* No-op. */
            RAISE INFO 'Skipping user_preference_event: already updated.';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT update_user_preference_event_table();

DROP FUNCTION update_user_preference_event_table();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


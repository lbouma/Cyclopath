/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho This script fixes misc problems.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Fixing item_event_alert table.
\qecho

/* Update item_event_alert table. */

CREATE SEQUENCE item_event_alert_id_seq;
ALTER TABLE item_event_alert ALTER COLUMN messaging_id
   SET DEFAULT NEXTVAL('item_event_alert_id_seq');

ALTER TABLE item_event_alert ADD COLUMN branch_id INTEGER NOT NULL;

ALTER TABLE item_event_alert RENAME COLUMN latest_rev TO latest_rid;

ALTER TABLE item_event_alert ADD COLUMN watcher_stack_id INTEGER NOT NULL;

ALTER TABLE item_event_alert ADD COLUMN ripens_at TIMESTAMP
   WITH TIME ZONE DEFAULT NULL;

ALTER TRIGGER messaging_date_created_i ON item_event_alert
   RENAME TO item_event_alert_date_created_i;

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

/* FIXME: This runs after the MetC update.... */

\qecho
\qecho Hiding unused MetC attributes from flashclient.
\qecho

UPDATE attribute SET uses_custom_control = TRUE
WHERE value_internal_name IN (
   '/metc_bikeways/bike_facil'
   , '/metc_bikeways/alt_names'
   , '/metc_bikeways/line_side'
   , '/metc_bikeways/from_munis'
   , '/metc_bikeways/surf_type'
   , '/metc_bikeways/jurisdiction'
);

/* ==================================================================== */
/* Step (3)                                                             */
/* ==================================================================== */

\qecho
\qecho Adding alert-me-on-revision-activity option.
\qecho

ALTER TABLE revision ADD COLUMN alert_on_activity BOOLEAN DEFAULT FALSE;

/* CcpV1 emails users by default, so we should, too.
   Note that users can still disable all alerts via enable_watchers_email,
   so we might send an unwanted/unexpected email once, but the user can
   at least opt out of more emails. Also, in CcpV2, when a user saves a
   new revision, we ask them if they want an email when their revision
   is reverted or if a thread is started about it. */
UPDATE revision SET alert_on_activity = TRUE;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


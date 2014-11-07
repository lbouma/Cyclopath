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
\qecho Fixing item read event and alerting table names.
\qecho

/* Update item_event_read table. */

ALTER TABLE item_read_event_bug_nnnn RENAME TO item_event_read;

ALTER TRIGGER item_read_event_ic ON item_event_read
    RENAME TO item_event_read_ic;

ALTER TRIGGER item_read_event_ir ON item_event_read
    RENAME TO item_event_read_ir;

ALTER TABLE item_read_event_id_seq RENAME TO item_event_read_id_seq;

/* Update messaging table. */

ALTER TABLE messaging RENAME TO item_event_alert;
/* In CcpV1, tw_email_pending uses post_id and thread_id;
             wr_email_pending uses wrid and rid;
             and the tables are populated until digest emails
             the users, and then the tables are cleared.
   In CcpV2, we mark date_emailed so we keep a record of emails we send.
*/

/* date_alerted should be NULL until the user views the alert. */
ALTER TABLE item_event_alert ALTER COLUMN date_alerted DROP NOT NULL;

UPDATE item_type SET type_name = 'item_event_alert'
               WHERE type_name = 'messaging';

/* Deprecate old tables. */

/* The CcpV2 upgrade created a table called watcher_events
   to consume CcpV1's tw_email_pending and wr_email_pending,
   which are used to send digest emails, but item_event_alert
   is the new implementation.
*/
ALTER TABLE watcher_events_bug_nnnn RENAME TO __delete_me_ccpv2_watcher_events;

/*

See: link_attributes_populate.py, which processed item_watcher table.

Also: the new /item/alert_email attribute link_values were populated
from CcpV1's region_watcher table, thread_watcher table, and records
in region with notify_email. CcpV2 is smart enough to treat all items
equally, so now it's implemented using just one table.

*/

ALTER TABLE item_watcher_bug_nnnn RENAME TO __delete_me_ccpv1_item_watcher;
ALTER TABLE        region_watcher RENAME TO __delete_me_ccpv1_region_watcher;
ALTER TABLE        thread_watcher RENAME TO __delete_me_ccpv1_thread_watcher;
ALTER TABLE          watch_region RENAME TO __delete_me_ccpv1_watch_region;
/*

BUG nnnn: Someday, when we're confident, do this:

DROP TABLE __delete_me_ccpv1_item_watcher;
DROP TABLE __delete_me_ccpv1_region_watcher;
DROP TABLE __delete_me_ccpv1_thread_watcher;
DROP TABLE __delete_me_ccpv1_watch_region;
DROP TABLE __delete_me_ccpv2_watcher_events;
*/

/* This is from an SQL snippet in 201-apb-71-wtchrs-instance.sql. */
CREATE OR REPLACE FUNCTION cp_revision_at_date(IN timestamp_ TIMESTAMP)
   RETURNS INTEGER AS $$
   BEGIN
      RETURN MAX(id) FROM @@@instance@@@.revision 
         WHERE ((timestamp_ < timestamp)
                AND (id NOT IN (0, cp_rid_inf())));
   END;
$$ LANGUAGE plpgsql VOLATILE;
/*
   Test with, e.g.,

      -- Cannot use current_timestamp, as in, SELECT current_timestamp,
      -- because any time after the last revision returns 0 rows.

      SELECT cp_revision_at_date('2012-10-10 10:14:53.877202-05'::TIMESTAMP);
       cp_revision_at_date 
      ---------------------
                     22281
*/

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


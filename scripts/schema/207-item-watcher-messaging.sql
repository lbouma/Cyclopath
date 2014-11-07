/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the third-generation watching and messaging tables. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

/* FIXME
 *
 *
 *       Implement watching...
 *       this file is not implemented, I think it's just a start... argh.
 */

\qecho 
\qecho This script creates the third-generation watching and messaging tables.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho 
\qecho Creating watcher and messenging table.
\qecho 

/* BUG nnnn: Need script to go through existing old item_watcher table and make
 * new items for everyone. Probably easier to do using Python than to do in
 * SQL. */
/* FIXME: These *_bug_nnnn tables are also in the anonymizer scripts. */
CREATE FUNCTION make_bug_nnnn_tables()
   RETURNS VOID AS $$
   BEGIN
      IF NOT EXISTS (SELECT * 
                        FROM pg_tables 
                        WHERE schemaname='@@@instance@@@' 
                              AND tablename = 'item_watcher_bug_nnnn') THEN
         ALTER TABLE item_watcher RENAME TO item_watcher_bug_nnnn;
         ALTER TABLE item_read_event RENAME TO item_read_event_bug_nnnn;
         ALTER TABLE watcher_events RENAME TO watcher_events_bug_nnnn;
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT make_bug_nnnn_tables();

DROP FUNCTION make_bug_nnnn_tables();

/* */

DROP TABLE IF EXISTS item_watcher;
DROP TABLE IF EXISTS item_watcher_change;
DROP TABLE IF EXISTS messaging;

/* */

/* C.f. CREATE TABLE work_item..... */
/*

2013.03.27: Deprecated. Replaced by private link_value attributes.

CREATE TABLE item_watcher (
   -- ** Item Versioned columns
   system_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   stack_id INTEGER NOT NULL,
   version INTEGER NOT NULL,
-- FIXME: This comment same as one in 205-mr_do-work_item-n-jobs.sql.
   / * FIXME Should we include the four missing columns from item_versioned to
     *       avoid the join? Should we do this to the attachment and geofeature
     *       tables? HALF-ANSWER: If we did, we could nix the item_versioned 
     *       table. It has name, that the children don't copy. And tsvect_name.
     *       Maybe created_by. And valid_start_rid and valid_until_rid. But
     *       then group_item_access has a problem, doesn't it? I guess we
     *       need IV to provide the link to GIA, so, really, the GRAC tables
     *       __should_not__ have these? Or maybe the hybrid model is okay? Ok,
     *       ok: if you go through GIA and link to IV, then it makes sense not
     *       to have these columns, but if you bypass GIA, and then bypass IV,
     *       maybe, yeah, it makes sense to have these columns. But remember
     *       they're outside the tsvect search index. And outside other things.
     * /
   / *
   deleted BOOLEAN NOT NULL DEFAULT FALSE,
   reverted BOOLEAN NOT NULL DEFAULT FALSE,
   name TEXT, -- A description of the policy
   valid_start_rid INTEGER NOT NULL,
   valid_until_rid INTEGER NOT NULL,
   * /
   for_username TEXT NOT NULL,
   item_type_id INTEGER NOT NULL,
   item_stack_id INTEGER NOT NULL
);
*/

/* NOTE: See 201-apb-71-wtchrs-instance.sql: already create item_watcher_pkey
         constraint for the original table that we just renamed.... */
/*
ALTER TABLE item_watcher 
   ADD CONSTRAINT item_watcher2_pkey
   PRIMARY KEY (system_id);
*/

/* */

/*

2013.03.27: Deprecated. Replaced by private link_value attributes.

DROP TABLE IF EXISTS item_watcher_change;
CREATE TABLE item_watcher_change (
   item_watcher_id INTEGER NOT NULL,
   change_num INTEGER NOT NULL,
   last_modified TIMESTAMP WITH TIME ZONE NOT NULL,
   is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
   notifiers_dat TEXT,
   notifiers_raw BYTEA
);

ALTER TABLE item_watcher_change 
   ADD CONSTRAINT item_watcher_change_pkey 
   PRIMARY KEY (item_watcher_id, change_num);

CREATE TRIGGER item_watcher_change_last_modified_i 
   BEFORE INSERT ON item_watcher_change 
   FOR EACH ROW EXECUTE PROCEDURE public.set_last_modified();

*/

/* */

DROP TABLE IF EXISTS messaging;
CREATE TABLE messaging (
   messaging_id INTEGER NOT NULL,
   username TEXT NOT NULL,
   latest_rev INTEGER NOT NULL, -- later renamed: latest_rid
   item_id INTEGER NOT NULL,
   item_stack_id INTEGER NOT NULL,
   date_created TIMESTAMP WITH TIME ZONE NOT NULL,
   date_alerted TIMESTAMP WITH TIME ZONE NOT NULL,
   --server_side BOOLEAN NOT NULL,
   msg_type_id INTEGER NOT NULL,
   /* FIXME: Figure this out better: */
   service_delay INTEGER,
   notifier_dat TEXT,
   notifier_raw BYTEA
);

ALTER TABLE messaging 
   ADD CONSTRAINT messaging_pkey 
   PRIMARY KEY (messaging_id);

CREATE TRIGGER messaging_date_created_i
   BEFORE INSERT ON messaging
   FOR EACH ROW EXECUTE PROCEDURE public.set_date_created();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

--ROLLBACK;
COMMIT;


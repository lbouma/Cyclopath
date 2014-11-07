/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script generalizes the watch_region watcher and thread_watcher models.
   Users can now watch anything under revision control. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script adds item readers and watchers
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Make some tables                                         */
/* ==================================================================== */

\qecho 
\qecho Creating item watcher tables
\qecho 

CREATE TABLE item_read_event (
   id INTEGER NOT NULL,
   created TIMESTAMP WITH TIME ZONE NOT NULL,
   -- user_id INTEGER NOT NULL,
   username TEXT NOT NULL,
   item_id INTEGER NOT NULL,
   revision_id INTEGER NOT NULL
);

ALTER TABLE item_read_event 
   ADD CONSTRAINT item_read_event_pkey 
   PRIMARY KEY (id);

CREATE SEQUENCE item_read_event_id_seq;

ALTER TABLE item_read_event 
   ALTER COLUMN id 
      SET DEFAULT NEXTVAL('item_read_event_id_seq');

ALTER SEQUENCE item_read_event_id_seq OWNED BY item_read_event.id;

/* */

CREATE TABLE item_watcher (
   username TEXT NOT NULL,
   stack_id INTEGER NOT NULL,
   branch_id INTEGER NOT NULL,
   enable_email BOOLEAN DEFAULT FALSE,
   enable_digest BOOLEAN DEFAULT FALSE
);

ALTER TABLE item_watcher 
   ADD CONSTRAINT item_watcher_pkey 
   PRIMARY KEY (username, stack_id, branch_id);

/* */

CREATE TABLE watcher_events (
   -- user_id INTEGER NOT NULL,
   username TEXT NOT NULL,
   /* In CcpV1, tw_email_pending uses post_id and thread_id;
                wr_email_pending uses wrid and rid. */
   item_id INTEGER NOT NULL,
   other_id INTEGER, -- FIXME: Acts as either thread ID or revision ID
   is_digest BOOLEAN DEFAULT FALSE,
   date_emailed TIMESTAMP WITH TIME ZONE
);

ALTER TABLE watcher_events 
   ADD CONSTRAINT watcher_events_pkey 
   PRIMARY KEY (username, item_id);

/* */

/* 2013.04.17: item_findability is meant to replace route_view. This may be
               useful for other classes, like track.
 */
CREATE TABLE item_findability (
   item_stack_id INTEGER NOT NULL,
   username TEXT NOT NULL,
   user_id INTEGER NOT NULL,
   -- squelch: 0 undefined, 1 off/always show, 2 searches only, 3 always hide
   library_squelch INTEGER NOT NULL DEFAULT 0,
   show_in_history BOOLEAN NOT NULL DEFAULT FALSE,
   -- This was WITHOUT TIME ZONE. We want WITH, RIGHT?
   last_viewed TIMESTAMP WITH TIME ZONE NOT NULL,
   branch_id INTEGER NOT NULL
);

ALTER TABLE item_findability
   ADD CONSTRAINT item_findability_pkey
   -- The primary key is reversed in CcpV1 (route_id, username),
   -- which seems backwards... users will have many records, and
   -- stack IDs will be used by few users, so the btree should be
   -- better off if the username is the first key.
   PRIMARY KEY (username, item_stack_id);

ALTER TABLE item_findability
   ADD CONSTRAINT item_findability_username_fkey
   FOREIGN KEY (username) REFERENCES user_ (username)
      DEFERRABLE;

/* We cannot do this until the item_stack table is created. ;)
ALTER TABLE item_findability
   ADD CONSTRAINT item_findability_item_stack_id_fkey
   FOREIGN KEY (item_stack_id) REFERENCES item_stack (stack_id)
      DEFERRABLE;
*/

CREATE INDEX item_findability_item_stack_id
   ON item_findability (item_stack_id);

CREATE INDEX item_findability_branch_id
   ON item_findability (branch_id);

/* MAYBE: This is on INSERT... what about UPDATE? */
CREATE TRIGGER item_findability_last_viewed_i BEFORE INSERT ON item_findability
   FOR EACH ROW EXECUTE PROCEDURE set_last_viewed();
CREATE TRIGGER item_findability_last_viewed_u BEFORE UPDATE ON item_findability
   FOR EACH ROW EXECUTE PROCEDURE set_last_viewed();

\qecho ... disabling triggers while populating table...
--ALTER TABLE item_findability DISABLE TRIGGER item_findability_last_viewed_i;
ALTER TABLE item_findability DISABLE TRIGGER item_findability_last_viewed_u;

/* ==================================================================== */
/* Step (2) -- Populate new item_watcher table                          */
/* ==================================================================== */

/* The 'item_watcher' table is translated from region_watcher 
   and thread_watcher */

\qecho 
\qecho Adding region, region_region, and thread watchers to watcher table
\qecho 

/* Add watchers of public regions */
INSERT INTO item_watcher (username, stack_id, branch_id, enable_email)
   (SELECT username, region_id, cp_branch_baseline_id(), TRUE 
    FROM region_watcher);

/* Add watchers of private regions */
INSERT INTO item_watcher (username, stack_id, branch_id, enable_email)
   (SELECT
      gf.username,
      gf.stack_id,
      gf.branch_id,
      gf.notify_email
   FROM geofeature AS gf
      WHERE gf.username != '');

/* Add watchers of public discussions */
INSERT INTO item_watcher (username, stack_id, branch_id, enable_email)
   (SELECT username, thread_id, cp_branch_baseline_id(), TRUE 
    FROM thread_watcher);

\qecho 
\qecho Setting enable_digest from user_ table
\qecho 

UPDATE item_watcher AS wr SET enable_digest = 
   (SELECT enable_wr_digest FROM user_ WHERE wr.username = user_.username);
UPDATE item_watcher AS wr SET enable_digest = 
   (SELECT enable_wr_digest FROM user_ WHERE wr.username = user_.username);

\qecho 
\qecho Archiving old tables
\qecho 

/* 2013.03.26: Hold onto these tables for sanity checking. We'll drop
               them when we call link_attributes_populate.py from
               upgrade_ccpv1-v2.sh.
ALTER TABLE region_watcher SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE thread_watcher SET SCHEMA archive_@@@instance@@@_1;
*/
/* 2013.03.26: I guess we might as well temporarily resurrect watch_region,
               too. */
ALTER TABLE archive_@@@instance@@@_1.watch_region SET SCHEMA @@@instance@@@;

/* ==================================================================== */
/* Step (3) -- Populate new watcher events table                        */
/* ==================================================================== */

/* We can ignore watcher_events, since this tracks emails we need to send */

\qecho 
\qecho The email-pending tables are usually empty:
\qecho 

SELECT * FROM tw_email_pending;
SELECT * FROM wr_email_pending;

\qecho 
\qecho This code is somewhat untested: the SQL works but I have not 
\qecho tested in pyserver or flashclient, so expect this code to change.
\qecho 

\qecho 
\qecho Populating watcher-events from old email-pending tables
\qecho 

/* NOTE The two tables, tw_email_pending and wr_email_pending, are 
        often empty, since they are cleared out every night after 
        digest emails are sent. So sometimes this code is just a 
        no-op. Hence, it does not get tested often; I've only 
        had the pleasure of seeing it run once, and it failed 
        miserably (I was storing stack IDs as system IDs, oops!). */

/* NOTE The ORDER BY and LIMIT 1 mean we only store the latest version 
        that changed -- not a big deal, we don't want to yammer on in 
        multiple emails that something changed, rather, we just want to 
        tell the user once. */

/* FIXME: 20111122: This is failing! Probably don't want to copy this stuff
 *        over, anyway. Just run the watcher script one last time from CcpV1
 *        before freezing the site.

INSERT 0 0
ERROR:  duplicate key value violates unique constraint "watcher_events_pkey"

INSERT INTO watcher_events 
   (username, item_id, other_id, is_digest, date_emailed)
   (SELECT 
      ep.username, 
      (SELECT iv.system_id FROM item_versioned AS iv
         WHERE iv.stack_id = ep.post_id ORDER BY iv.version DESC LIMIT 1), 
      (SELECT iv.system_id FROM item_versioned AS iv
         WHERE iv.stack_id = ep.thread_id ORDER BY iv.version DESC LIMIT 1), 
      TRUE, 
      NULL 
   FROM tw_email_pending AS ep);

*/

/* The old wr_email_pending table stores the revision ID and the stack ID 
   of the changed revision. We just store the system ID -- the revision ID 
   can be gleaned from the system ID. */

/* FIXME: 2011.Aug: what about rid? */

/* FIXME: 20111122: See previous comment.

INSERT INTO watcher_events 
   (username, item_id, other_id, is_digest, date_emailed)
   (SELECT 
      ep.username, 
      (SELECT iv.system_id FROM item_versioned AS iv
         WHERE iv.stack_id = ep.wrid ORDER BY iv.version DESC LIMIT 1), 
      NULL, 
      TRUE, 
      NULL 
   FROM wr_email_pending AS ep);

*/

\qecho 
\qecho Archiving old tables
\qecho 

ALTER TABLE tw_email_pending SET SCHEMA archive_@@@instance@@@_1;
ALTER TABLE wr_email_pending SET SCHEMA archive_@@@instance@@@_1;

/* NOTE There is no historical record of watcher-events, except in 
        the apache log, so we cannot further populate watcher-events
        (without writing a (complicated?) algorithm to parse said log).
        (In the new database, we leave watcher-events and mark them as 
        completed -- this helps us recover in case of error, and also 
        lets us keep a historical record of watcher-events -- rather 
        than deleting rows after we send emails.) */

/* ==================================================================== */
/* Step (4) -- Populate new item-read table                             */
/* ==================================================================== */

\qecho 
\qecho Populating item-read-event table
\qecho 

/* The 'item_read_event' table is translated from thread_read_event */
/* In addition to a timestamp, we store the revision when the item was read.
   This makes it easy to check in the future if something about the item has 
   changed. For instance, if a user is watching a byway and an attribute 
   changes, we can just check revision IDs, rather than figuring out an 
   item's revision's date. */
/* NOTE The old table stored just the stack_id -- but here, we're storing 
        the system_id. It's a little more work to see if someone's seen the 
        current version of some item, but storing the system_id is very 
        flexible -- it even tracks if you've seen historical versions of 
         the item or not. */

INSERT INTO item_read_event (id, created, username, item_id, revision_id)
   (SELECT id, created, username, 
      (SELECT iv.system_id 
         FROM item_versioned AS iv
            WHERE iv.stack_id = tre.thread_id
            /* NOTE Ignoring version, since it's always 1. */
                  -- AND version = 1
         ),
      (SELECT MAX(id)
         FROM revision
            WHERE (timestamp < tre.created)
                  AND id NOT IN (0, cp_rid_inf()))
      FROM thread_read_event AS tre);

/* Update the sequence. */

SELECT SETVAL('item_read_event_id_seq', NEXTVAL('thread_read_event_id_seq'));

\qecho 
\qecho Archiving old tables and sequences
\qecho 

ALTER TABLE thread_read_event SET SCHEMA archive_@@@instance@@@_1;

/* NOTE For whatever reason, the seq also got archived, so no need to:
   ALTER SEQUENCE thread_read_event_id_seq SET SCHEMA archive_@@@instance@@@_1;
*/

/* ==================================================================== */
/* Step (5) -- Populate new item_findability table                      */
/* ==================================================================== */

\qecho 
\qecho Populating item-findability table from route_view, route, and track.
\qecho 

-- ALTER TABLE item_findability DISABLE TRIGGER item_findability_last_viewed_u;
INSERT INTO item_findability
   (item_stack_id, username, user_id, library_squelch,
    show_in_history, last_viewed, branch_id)
   -- FIXME: MAGIC_NUMBER: 0 means no library_squelch.
   (SELECT route_stack_id,
           username,
           (SELECT cp_user_id(username)),
           1, -- MAGIC_NUMBER: library_squelch 1: show in library.
           active,
           last_viewed,
           branch_id
    FROM route_view);
/* Haha: Cannot enable trigger again this transaction.
    cannot ALTER TABLE "item_findability" because it has pending trigger events
ALTER TABLE item_findability ENABLE TRIGGER item_findability_last_viewed_u;
*/

/* See notes in 201-apb-60-groups-pvt_ins3.sql.

   For (visibility, permissions):
     (1,1-2): route is public, and lack of item_findability record means
              library_squelch is 0, so nothing to do;
     (2,2-3): same as (1,*);
     (3,2-3): these have visibility noone but have user arbiter records,
              so exclude these from item_findability; there are also a
              handful of items linked from posts that also should not be
              findable.
   */

/* Routes that are 3,* are not shown in the library (but are searchable?) */

/* NOTE: In Michael's [ml]'s route sharing model, when you change a route's
         visibility or permissions, you clone the route and mark the first copy
         deleted. So here we can do WHERE version = 1 and get unique records
         we not have to worry about visibility (or created_by) changing. */
DELETE FROM item_findability WHERE item_stack_id IN
   (SELECT stack_id FROM route
    WHERE visibility = 3 AND created_by IS NOT NULL);
INSERT INTO item_findability
   (item_stack_id,
    username,
    user_id,
    library_squelch,
    show_in_history,
    branch_id)
   (SELECT
      stack_id,
      created_by,
      (SELECT cp_user_id(created_by)),
      3, -- MAGIC_NUMBER: 3 means never show in/always hide from library
      FALSE,
      branch_id
    FROM
      route
    WHERE
      version = 1
      AND visibility = 3
      AND created_by IS NOT NULL);

/* Tracks are all 3,3 */

DELETE FROM item_findability WHERE item_stack_id IN
   (SELECT stack_id FROM track
    WHERE visibility = 3 AND created_by IS NOT NULL);
INSERT INTO item_findability
   (item_stack_id,
    username,
    user_id,
    library_squelch,
    show_in_history,
    branch_id)
   (SELECT
      stack_id,
      created_by,
      (SELECT cp_user_id(created_by)),
      3, -- MAGIC_NUMBER: 3 means never show in/always hide from library
      FALSE,
      branch_id
    FROM
      track
    WHERE
      version = 1
      AND visibility = 3
      AND created_by IS NOT NULL);

/* Link-routes... */

\qecho 
\qecho Populating item-findability table from post_route and route_view
\qecho 

/* We've already disabled these routes in the user's library, but now we have
   to disable the handful of linked routes that have public GIA records. */
INSERT INTO item_findability
   (item_stack_id, username, user_id,
    library_squelch, show_in_history, branch_id)
   (SELECT
      DISTINCT ON (rt.stack_id) stack_id,
      '_user_anon_@@@instance@@@',
      (SELECT cp_user_id('_user_anon_@@@instance@@@')),
      2, -- FIXME: MAGIC_NUMBER: 2 means never show in library.
      FALSE,
      branch_id
    FROM route AS rt
    JOIN archive_@@@instance@@@_1.post_route AS prt
      ON (prt.route_id = rt.stack_id)
    WHERE
      rt.version = 1
      AND rt.visibility = 3
      AND rt.permission = 2);

/* Fix any records we deleted to write library_restrict. */
--ALTER TABLE item_findability DISABLE TRIGGER item_findability_last_viewed_u;
UPDATE item_findability SET
   show_in_history = show_in_history_, last_viewed = last_viewed_
   FROM (SELECT   route_view.route_stack_id
                , route_view.active AS show_in_history_
                , route_view.last_viewed AS last_viewed_
         FROM route_view) AS foo
   WHERE foo.route_stack_id = item_findability.item_stack_id;
--ALTER TABLE item_findability ENABLE TRIGGER item_findability_last_viewed_u;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


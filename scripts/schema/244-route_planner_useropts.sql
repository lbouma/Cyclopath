/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho
\qecho Update user_ and user_preference tables per latest p3 changes..
\qecho

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Update user_ and user_preference tables.
\qecho

/* The planner's travel_mode ID indicates if this is p1, p2 or p3 planner.
   MAGIC_NUMBER: The rf_planner value is from Travel_Mode. */
ALTER TABLE user_ ADD COLUMN rf_planner INTEGER NOT NULL DEFAULT 0;

/* MAGIC_NUMBERs: Travel_Mode.wayward == 5, Travel_Mode.transit == 2. */
UPDATE user_ SET rf_planner = (
   SELECT CASE WHEN rf_use_multimodal THEN 2 ELSE 5 END);

/* The user_preference_event table records when a user requests a new route
and tries new planner options... it's probably a pretty silly table. [lb]
knows [rp] et al used to use this table for research. It's similar to the
log_event table: we (supposedly) use it to analyze how users interact with
the application. But if that was the case -- that we use it to analyze user
behavior -- wouldn't we have realized long ago how hopeless the p1 priority
setting is? I mean, I would watch over the shoulders of users and see most
of them try all nine tick marks (the bikeability slider) and each user would
be lucky just to get two meaningfully different routes.... argh, I know I've
beat this horse before (yes, yes, we get it! the p1 planner is horribly
broken). I guess my gripe isn't that we got something wrong, it's that we were
so confident that we wouldn't get anything wrong, that we were blind to all
the things we got wrong! And -- just as worse -- any time someone questioned
whether something was right, they were told they were wrong.... Anyway, update
the user_preference_event table, and maybe someday just make these pickleable
log_event entries so that we don't have to maintain this silly table. */
ALTER TABLE user_preference_event ADD COLUMN rf_planner INTEGER;

DROP TRIGGER user_preference_event_u ON user_preference_event;

/* MAGIC NUMBER: 5 is Travel_Mode.wayward, 2 is transit. */
UPDATE user_preference_event SET rf_planner = (
   SELECT CASE WHEN rf_use_multimodal IS TRUE THEN 2 ELSE 5 END);

CREATE TRIGGER user_preference_event_u BEFORE UPDATE ON user_preference_event
  FOR EACH STATEMENT EXECUTE PROCEDURE fail();

/* Rename columns to associate explicitly with their planner. */
ALTER TABLE user_ RENAME COLUMN rf_priority TO rf_p1_priority;
ALTER TABLE user_ RENAME COLUMN rf_transit_pref TO rf_p2_transit_pref;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


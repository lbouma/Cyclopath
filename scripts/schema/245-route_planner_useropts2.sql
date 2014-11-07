/* Copyright (c) 2006-2014 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho
\qecho Do things that would have been in last script were not for triggers
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
\qecho Do things that would have been in last script were not for triggers
\qecho

/* The rf_use_multimodal is replaced by rf_planner travel_mode id. */
ALTER TABLE user_ DROP COLUMN rf_use_multimodal;

/* Again, replace rf_use_multimodal with rf_planner. */
ALTER TABLE user_preference_event DROP COLUMN rf_use_multimodal;

/* This is how settings should be stored: as opaque pickles. This pickle
   stores all the values that are currently their own column. I [lb]
   didn't delete the old columns because there's still code that uses the
   existing columns, but at least we can start transitioning code
   to start using the database-agnostic approach. */
ALTER TABLE user_ ADD COLUMN routefinder_settings TEXT;
ALTER TABLE user_preference_event ADD COLUMN routefinder_settings TEXT;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


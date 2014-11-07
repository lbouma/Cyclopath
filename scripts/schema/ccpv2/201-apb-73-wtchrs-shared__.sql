/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script cleans up after implementing watchers, removing old resources 
   from the public schema. */

\qecho 
\qecho This script cleans up the public schema after implementing watchers
\qecho 
\qecho [EXEC. TIME: 2011.04.22/Huffy: ~ 0.15 mins (incl. mn. and co.).]
\qecho [EXEC. TIME: 2013.04.23/runic:   0.00 min. [mn]]
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Change user_ table's column names                        */
/* ==================================================================== */

\qecho 
\qecho Renaming watcher columns in user_ table
\qecho 

/* The item_watcher tables has its own enable_email and enable_digest columns
   that, if not NULL, override the global settings in the user_ table. */

ALTER TABLE user_ RENAME COLUMN enable_wr_email TO enable_watchers_email;
ALTER TABLE user_ RENAME COLUMN enable_wr_digest TO enable_watchers_digest;

\qecho 
\qecho Renaming watcher columns in user_preference_event table
\qecho 

ALTER TABLE user_preference_event 
   RENAME COLUMN enable_wr_email TO enable_watchers_email;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


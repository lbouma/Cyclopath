/* Copyright (c) 2006-2012 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adds support for the Google Transit Feed Specification. */

\qecho 
\qecho This script adds support for the Google Transit Feed Specification.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Update viz table                                         */
/* ==================================================================== */

\qecho 
\qecho Updating the viz table.
\qecho 

/* SYNC_ME: Search: viz table. */

INSERT INTO viz (id, name) VALUES (6, 'Transit Type');

/* ==================================================================== */
/* Step (2) -- Update user preferences table                            */
/* ==================================================================== */

ALTER TABLE user_ ADD COLUMN rf_transit_pref REAL NOT NULL DEFAULT 0;
ALTER TABLE user_ ADD COLUMN rf_use_multimodal BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE user_preference_event ADD COLUMN rf_transit_pref REAL;
ALTER TABLE user_preference_event ADD COLUMN rf_use_multimodal BOOLEAN;

/* ==================================================================== */
/* Step (3) -- Defer this section for a later release....               */
/* ==================================================================== */

/* FIXME: Missing columns to save multimodal routes. */

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


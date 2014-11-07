/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance

   */

\qecho 
\qecho Add a timestamp to aadt.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

\qecho
\qecho Add a timestamp to aadt.
\qecho

ALTER TABLE aadt ADD COLUMN aadt_year INTEGER;

UPDATE aadt SET aadt_year = date_part('year', last_modified);

/* MnDOT provides AADT and HCAADT, or heavy commercial aadt. */

--ALTER TABLE aadt ADD COLUMN is_heavy_commercial BOOLEAN;
ALTER TABLE aadt ADD COLUMN aadt_type TEXT DEFAULT '';

SELECT cp_constraint_drop_safe('aadt', 'aadt_pkey');
ALTER TABLE aadt
   ADD CONSTRAINT aadt_pkey
   PRIMARY KEY (branch_id, byway_stack_id, aadt_year, aadt_type,
                last_modified);

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

\qecho
\qecho Add cols to geofeature and node_endpoint for Statewide Cyclopath.
\qecho

/* BUG nnnn/MAYBE: Move line segment columns to new table... byway_segment?! */

ALTER TABLE geofeature ADD COLUMN control_of_access INTEGER;

/* Deprecated: [lb] added confidences to work with the MnDOT
   import script (statewide_mndot_import.py), but the newer
   import script (hausdorff_import.py) handles confidences by just
   adding them to the exported Shapefile. So the confidences
   column might get dropped in the future, unless we want the
   hausdorff script to also maintain confidences in the database,
   so that user's can work with these values, too (e.g., via
   flashclient, other than only having access to these values
   via a Shapefile.) */
ALTER TABLE node_endpoint ADD COLUMN confidences INTEGER;

/* ==================================================================== */
/* Step (3)                                                             */
/* ==================================================================== */

\qecho
\qecho Add CBF7 and BSIR generic rater user_ accounts.
\qecho

/* SEE: FUNCTION cp_user_new(username_, user_email, user_pass). */
/* SYNC_ME: This name matches conf.cbf7_rater_username. */
SELECT cp_user_new('_rating_cbf7', 'info@cyclopath.org', 'nopass');
/* SYNC_ME: This name matches conf.bsir_rater_username. */
SELECT cp_user_new('_rating_bsir', 'info@cyclopath.org', 'nopass');
/* SYNC_ME: This name matches conf.ccpx_rater_username. */
SELECT cp_user_new('_rating_ccpx', 'info@cyclopath.org', 'nopass');
/* SYNC_ME: These names match conf.generic_rater_username, et al.
            See also: conf.rater_usernames. */
UPDATE user_ SET
   login_permitted = FALSE,
   email = 'info@cyclopath.org',
   enable_watchers_email = FALSE,
   enable_email = FALSE,
   enable_email_research = FALSE,
   dont_study = TRUE
   WHERE username IN ('_r_generic',
                      '_rating_bsir',
                      '_rating_cbf7',
                      '_rating_ccpx');

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


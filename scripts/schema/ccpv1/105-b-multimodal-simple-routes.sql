/* Copyright (c) 2006-2012 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adds support for the Google Transit Feed Specification. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script adds a travel_mode column to the route table.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Alter route table                                        */
/* ==================================================================== */

\qecho 
\qecho Updating column restraints.
\qecho 

ALTER TABLE route ALTER COLUMN travel_mode SET NOT NULL;
ALTER TABLE route ALTER COLUMN travel_mode SET DEFAULT 1;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


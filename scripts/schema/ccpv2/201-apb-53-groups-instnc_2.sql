/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script adjusts constraints on tables we just updated. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script adjusts constraints on tables we just updated.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Alter revision table                                     */
/* ==================================================================== */

\qecho 
\qecho Setting revision.is_revertable NOT NULL
\qecho 

ALTER TABLE revision ALTER COLUMN is_revertable SET NOT NULL;

ALTER TABLE revision ALTER COLUMN reverted_count SET NOT NULL;

ALTER TABLE revision 
   ALTER COLUMN is_revertable 
      SET DEFAULT FALSE;

ALTER TABLE revision 
   ALTER COLUMN reverted_count 
      SET DEFAULT 0;

/* ==================================================================== */
/* Step (2) -- Drop instance fcns. being replaced by public fcn.        */
/* ==================================================================== */

/* The fcn., revision_geosummary_update, was an instance fcn. because it used
 * hard-coded SRID values, but now we've got the new cp_srid() fcn., so in the
 * next public script, we'll recreate this instance fcn. as a public fcn. 
 * 2012.08.14: Or, instead of using a SQL fcn., we'll just code this in
 *             pyserver, in revision.py. */

\qecho 
\qecho Dropping instance fcn., revision_geosummary_update
\qecho 

DROP FUNCTION revision_geosummary_update(INTEGER);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


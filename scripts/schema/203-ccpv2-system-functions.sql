/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the cp_constraint_drop_safe fcn. */

\qecho 
\qecho This script creates the cp_constraint_drop_safe fcn.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Create the function                                      */
/* ==================================================================== */

DROP FUNCTION IF EXISTS cp_constraint_drop_safe(
                              IN table_name TEXT, 
                              IN constraint_name TEXT);

/* */

/* NOTE: This fcn. is useful to Pyserver, so we won't be dropping it. */
CREATE FUNCTION cp_constraint_drop_safe(IN table_name TEXT, 
                                        IN constraint_name TEXT)
   RETURNS VOID AS $$
   BEGIN
      BEGIN
         EXECUTE 'ALTER TABLE ' || table_name || 
                     ' DROP CONSTRAINT ' || constraint_name || 
                     ' CASCADE;';
      EXCEPTION 
         WHEN syntax_error_or_access_rule_violation THEN
            /* E.g., "ERROR: constraint "..." does not exist" */
            /* No-op. */
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ======================================================================== */
/* Step (n) -- All done!                                                    */
/* ======================================================================== */

\qecho 
\qecho Done!
\qecho 

--ROLLBACK;
COMMIT;


/* Copyright (c) 2006-2012 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script adds the run_maybe fcn.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO public;

/* Prevent PL/pgSQL from printing verbose "CONTEXT" after RAISE INFO */
\set VERBOSITY terse

/* ========================================================================= */
/* Step (1) -- run_maybe                                                     */
/* ========================================================================= */

\qecho Creating helper fcn.: run_maybe

/* NOTE This is a Convenience fcn. for developers.
        This is not a temporary fcn.; we will not be deleting it. */
CREATE FUNCTION run_maybe(IN instance_name TEXT, IN fcn_to_run_maybe TEXT)
   RETURNS VOID AS $$
   BEGIN
      IF NOT cp_instance_verify_itamae(instance_name) THEN
         /* This is not the desired instance. */
         RAISE INFO 'These aren''t the droids you''re looking for.';
      ELSE
         /* This is it! */
         RAISE INFO 'This is the itamae''s % instance!', instance_name;
         /* Run the fcn. */
         EXECUTE 'SELECT ' || fcn_to_run_maybe || '();';
      END IF;
   END;
$$ LANGUAGE plpgsql VOLATILE;

/* ========================================================================= */
/* Step (n) -- All done!                                                     */
/* ========================================================================= */

\qecho 
\qecho Done!
\qecho 

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;


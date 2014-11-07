/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script creates a unique constraint on the
\qecho unsubscribe_proof uuid column.
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
\qecho Creating unsubscribe_proof column constraint.
\qecho

-- We cannot do this in the previous script because 'ERROR:
-- cannot ALTER TABLE "user_" because it has pending trigger events'.

SELECT cp_constraint_drop_safe('user_', 'user__unsubscribe_proof_u');
ALTER TABLE public.user_ ADD CONSTRAINT user__unsubscribe_proof_u
   UNIQUE (unsubscribe_proof);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


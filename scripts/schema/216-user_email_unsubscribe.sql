/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script creates the unsubscribe_proof uuid column.
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
\qecho Creating unsubscribe_proof column.
\qecho

/* MAYBE: There's a mathematically insignificant chance that the
          UUID already exists. If we have find this happening, we'll
          want to update CycloAuth.php and/or cp_user_new() to try
          again if making a new row fails. */
CREATE FUNCTION cp_alter_user__forgiving()
   RETURNS VOID AS $$
   BEGIN
      BEGIN

         ALTER TABLE user_ ADD COLUMN unsubscribe_proof UUID
            DEFAULT MD5(RANDOM()::TEXT)::UUID;

      /* ERROR: column "..." of relation "..." already exists
         Use EXCEPTION WHEN OTHERS to catch all postgres exceptions. */
      EXCEPTION WHEN OTHERS THEN
         RAISE INFO 'split_from_stack_id already altered';
      END;
   END;
$$ LANGUAGE plpgsql VOLATILE;

SELECT cp_alter_user__forgiving();

DROP FUNCTION cp_alter_user__forgiving();

/* Make a random UUID. */
UPDATE user_ SET unsubscribe_proof = MD5(RANDOM()::TEXT)::UUID;

DROP INDEX IF EXISTS user__unsubscribe_proof_i;
CREATE INDEX user__unsubscribe_proof_i ON public.user_ (unsubscribe_proof);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


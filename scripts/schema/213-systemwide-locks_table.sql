/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script creates the locks table.
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
\qecho Creating locks table.
\qecho 

/* This is for future tilecache_update behavior. */

DROP TABLE IF EXISTS public.async_locks;
CREATE TABLE public.async_locks (
   lock_name TEXT NOT NULL,
   date_created TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE public.async_locks 
   ADD CONSTRAINT async_locks_pkey 
   PRIMARY KEY (lock_name);

CREATE TRIGGER async_locks_date_created_ic
   BEFORE INSERT ON public.async_locks
   FOR EACH ROW EXECUTE PROCEDURE public.set_date_created();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

--ROLLBACK;
COMMIT;


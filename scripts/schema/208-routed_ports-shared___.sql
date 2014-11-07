/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates the routed_ports table. */

\qecho 
\qecho This script creates the routed_ports tables.
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
\qecho Creating routed_ports table.
\qecho 

/* Explicitly using public prefix for developers whose .psqlrcs interfere. */
DROP TABLE IF EXISTS public.routed_ports;
CREATE TABLE public.routed_ports (
   pid INTEGER NOT NULL,
   port INTEGER NOT NULL,
   ready BOOLEAN NOT NULL DEFAULT FALSE,
   instance TEXT NOT NULL,
   branch_id INTEGER NOT NULL,
   routed_pers TEXT NOT NULL,
   purpose TEXT NOT NULL,
   last_modified TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE public.routed_ports 
   ADD CONSTRAINT routed_ports_pkey 
   PRIMARY KEY (port);

CREATE TRIGGER routed_ports_u BEFORE UPDATE ON routed_ports 
   FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER routed_ports_i BEFORE INSERT ON routed_ports
   FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

--ROLLBACK;
COMMIT;
   

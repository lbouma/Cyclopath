/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script creates and populates a table of zip codes.
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
\qecho Creating zipcode table.
\qecho

CREATE TABLE public.zipcodes (
   zipcode INTEGER NOT NULL,
   city TEXT,
   state TEXT,
   latitude REAL,
   longitude REAL,
   timezone INTEGER,
   /* This is the daylight savings time flah.
   MAGIC_NUMBER: 1 if DST is observed in this ZIP code, else 0. */
   observes_dst INTEGER
   );

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

ALTER TABLE public.zipcodes
   ADD CONSTRAINT zipcodes_pkey
   PRIMARY KEY (zipcode);

DROP INDEX IF EXISTS zipcodes_city;
CREATE INDEX zipcodes_city ON public.zipcodes (city);

DROP INDEX IF EXISTS zipcodes_state;
CREATE INDEX zipcodes_state ON public.zipcodes (state);

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


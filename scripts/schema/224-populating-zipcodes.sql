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

/* Hrmmm... this seems easier than bothering to also checkin the input file
   separately in the repository and than running a script on it...
   let's just dump all the input here! =) */

/* DEVS: First, run /ccp/dev/cp/scripts/dev/pyzipcode-setup.py. */
   -- "zip","city","state","latitude","longitude","timezone","dst"

/* Only superuser can copy...

      @run-as-superuser
 */

COPY public.zipcodes (
      zipcode, city, state,
      latitude, longitude,
      timezone, observes_dst)
   FROM '/ccp/var/zipcodes/2004.08.10.zipcode.csv'
   WITH CSV HEADER;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho
\qecho Done!
\qecho

--ROLLBACK;
COMMIT;


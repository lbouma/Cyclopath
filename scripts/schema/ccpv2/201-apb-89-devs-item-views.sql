/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* This script creates convenience views for developers.

   */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script creates convenience views for developers.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) --                                                          */
/* ==================================================================== */

\qecho 
\qecho Creating convenience views for developers.
\qecho 

/* 2014.07.02: [lb] deleted the contents of this script to simplify
               egrep results.

                See: scripts/dev/convenience_views.sql

                */

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

/* Reset PL/pgSQL verbosity */
\set VERBOSITY default

COMMIT;


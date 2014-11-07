/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This scripts creates an archival schema for public tables. */

/* Tell schema-update to run this script as -U Postgres, since only sudo can
   new make schemas:

      @run-as-superuser 
   
   */

\qecho 
\qecho This script creates an archival schema for old public tables
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* ==================================================================== */
/* Step (1) -- Create archival schema                                   */
/* ==================================================================== */

\qecho 
\qecho Creating archival schema
\qecho 

/* Since implementing arb. attrs. is somewhat intrusive, rather than muck with 
   the existing tables and risk losing or warping data, we create a new schema 
   to hold the old tables and data. This has two useful implications: (1) We
   can name the new tables the same as the existing tables and not worry about
   namespace conflicts, and (2) we can more easily compare the new tables to 
   the old tables to make sure we've copied all of our data successfully. */

/* Create an archival schema for the old tables. */
CREATE SCHEMA archive_1 AUTHORIZATION cycling;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

COMMIT;


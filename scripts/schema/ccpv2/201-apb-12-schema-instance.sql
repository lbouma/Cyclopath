/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates an archival schema for old instance tables. */

/* Tell schema-update to run this script as -U Postgres, since only sudo can
   new make schemas:

      @run-as-superuser 
   
   */

/* We also need to run against each instance of Cyclopath

      @once-per-instance 

   */

\qecho 
\qecho This script creates an archival schema for old instance tables
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* ==================================================================== */
/* Step (1) -- Create archival schema                                   */
/* ==================================================================== */

\qecho 
\qecho Creating archival schema
\qecho 

/* NOTE I'm not particularly jazzed about how we name instances, 
        i.e., 'minnesota' and 'colorado'. Like, would it be better to 
        use common prefixes, like "city_mpls" or "city_denver"?
        Anyway, I don't anticipate we'll have a ton of instances, 
        so this non-jazzing isn't really a concern. 
        
        We'll at least name all archival schemas with a common 
        prefix, 'archive_', so at least those'll be grouped. */

/* Create an archival schema for instance-specific tables. */
CREATE SCHEMA archive_@@@instance@@@_1 AUTHORIZATION cycling;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


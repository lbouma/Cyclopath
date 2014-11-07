
/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Recreate views used by db_export_shapefiles.sh. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

\qecho 
\qecho This script deletes the archival schemas.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1) -- Drop the archival instance schema                        */
/* ==================================================================== */

\qecho Dropping archival instance schema
DROP SCHEMA archive_@@@instance@@@_1 CASCADE;

\qecho Dropping archival schema geometry_columns rows
DELETE FROM geometry_columns WHERE f_table_schema = 'archive_@@@instance@@@_1';

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script deletes the archival schemas. */

\qecho 
\qecho This script deletes the archival schemas.
\qecho 

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Run this script just once, 
   for all instances of Cyclopath */
SET search_path TO public;

/* ==================================================================== */
/* Step (1) -- Drop the public archival schema                          */
/* ==================================================================== */

\qecho Dropping public archival schema
DROP SCHEMA archive_1 CASCADE;

/* FIXME

There are a bunch of notices, but mostly pertaining to the archival schemas.
However, some of the notices apply to what's not archived:

Dropping public archival schema
NOTICE:  ...
NOTICE:  drop cascades to table archive_1.work_hint_type
NOTICE:  drop cascades to constraint work_hint_type_code_fkey on table minnesota.work_hint
NOTICE:  drop cascades to constraint work_hint_type_code_fkey on table colorado.work_hint
NOTICE:  drop cascades to constraint tiger_codes_byway_code_fkey on table colorado.tiger_codes
NOTICE:  drop cascades to constraint cdot_codes_type_code_fkey on table colorado.cdot_codes
NOTICE:  ...
DROP SCHEMA

*/

\qecho Dropping archival schema geometry_columns rows
DELETE FROM geometry_columns WHERE f_table_schema = 'archive_1';

/* ==================================================================== */
/* Step (2) -- Drop the [obsolete] work_hint_status table.              */
/* ==================================================================== */

\qecho Dropping work_hint table.
DROP TABLE work_hint_status CASCADE;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;



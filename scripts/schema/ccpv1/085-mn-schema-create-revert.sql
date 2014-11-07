/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* NOTE: This script needs to be run as postgres. */

BEGIN TRANSACTION;

DROP SCHEMA minnesota;

ALTER TABLE upgrade_event DROP COLUMN schema;

COMMIT;

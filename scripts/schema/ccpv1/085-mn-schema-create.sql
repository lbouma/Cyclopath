/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Create schema for tables containing data specific to the Twin Cities.
   @run-as-superuser
 */

BEGIN TRANSACTION;

CREATE SCHEMA minnesota AUTHORIZATION cycling;

ALTER TABLE upgrade_event ADD COLUMN schema TEXT DEFAULT 'public';

COMMIT;

/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/** add host column to the database **/
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE route
   ADD COLUMN host INET;

COMMIT;

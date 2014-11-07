/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/*
 * @once-per-instance
 */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path to @@@instance@@@, public;

ALTER TABLE reaction_reminder ADD COLUMN id SERIAL;

COMMIT;


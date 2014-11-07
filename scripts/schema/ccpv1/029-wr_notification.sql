/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE user_ ADD COLUMN enable_wr_email BOOL NOT NULL DEFAULT true;

COMMIT;


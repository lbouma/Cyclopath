/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Changes the x and y values of tracks to type REAL. */
/* @once-per-instance */
BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

ALTER TABLE track_point alter column x type REAL;
ALTER TABLE track_point alter column y type REAL;

COMMIT;


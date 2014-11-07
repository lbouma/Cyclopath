/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds the split_from_id column to byways.  It is only non-null 
   for a byway version that was just newly created from a split (if it's 
   edited later on, the new version will have a null split_from_id */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE byway_segment ADD COLUMN split_from_id INT;

COMMIT;

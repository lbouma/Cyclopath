/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script will permanently remove flags from the database and cannot be
   undone!  Run scripts 044 and 045 first.

   NOTE: this will result in there being multiple versions of some byways in
   the byway_segment table in which the only apparent change is the version and
   revision numbers.  We have determined that this is acceptable. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

-- Drop all views that depend on flags
DROP VIEW byway_current;
DROP VIEW byway_segment_bikelane;
DROP VIEW byway_segment_closed;
DROP VIEW byway_segment_unpaved;

ALTER TABLE byway_segment DROP bike_lanes;
ALTER TABLE byway_segment DROP closed;
ALTER TABLE byway_segment DROP paved;

-- Recreate byway_current convenience view.
CREATE VIEW byway_current AS
SELECT * FROM byway_segment bs
WHERE bs.deleted = FALSE AND bs.valid_before_rid = rid_inf();

COMMIT;
VACUUM FULL ANALYZE byway_segment;

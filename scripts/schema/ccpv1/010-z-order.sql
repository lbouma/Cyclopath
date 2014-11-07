/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script adds the z column to geometric features and populates it with
   default values. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE basemap_polygon ADD COLUMN z INT;
UPDATE basemap_polygon SET z = 110 WHERE type_code = 2;
UPDATE basemap_polygon SET z = 120 WHERE type_code = 3;
ALTER TABLE basemap_polygon ALTER COLUMN z SET NOT NULL;

ALTER TABLE point ADD COLUMN z INT;
UPDATE point SET z = 140;
ALTER TABLE point ALTER COLUMN z SET NOT NULL;

ALTER TABLE byway_segment ADD COLUMN z INT;
UPDATE byway_segment SET z = 131 WHERE type_code IN (1, 2, 11, 42);  -- small
UPDATE byway_segment SET z = 131 WHERE type_code = 21;  -- medium
UPDATE byway_segment SET z = 131 WHERE type_code = 14;  -- bike trail
UPDATE byway_segment SET z = 131 WHERE type_code = 31;  -- large
UPDATE byway_segment SET z = 133 WHERE type_code = 41;  -- expressway
ALTER TABLE byway_segment ALTER COLUMN z SET NOT NULL;

\d basemap_polygon;
\d byway_segment;
\d point;

COMMIT;
-- ROLLBACK;

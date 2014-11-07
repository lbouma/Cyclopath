/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates a common 'coverage_area' table in each instance */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO minnesota, public;
CREATE TABLE coverage_area (name text);
SELECT AddGeometryColumn('coverage_area', 'geometry', 26915, 'POLYGON', 2);
INSERT INTO coverage_area (name, geometry)
  SELECT countyname, geometry FROM county WHERE countyname = 'metro7';

SET search_path TO colorado, public;
CREATE TABLE coverage_area (name text);
SELECT AddGeometryColumn('coverage_area', 'geometry', 26913, 'POLYGON', 2);
INSERT INTO coverage_area (name, geometry)
  SELECT name, wkb_geometry FROM drcog_boundary;

\qecho Minnesota
SELECT name, ST_Area(geometry) AS area FROM minnesota.coverage_area;
\qecho Colorado
SELECT name, ST_Area(geometry) AS area FROM colorado.coverage_area;

--ROLLBACK;
COMMIT;

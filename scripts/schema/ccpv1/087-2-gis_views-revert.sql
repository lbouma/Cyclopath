
/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Note: this needs to be run @once-per-instance, but schema-upgrade.py doesn't
currently work with revert scripts so you'll have to enter the instance schema
names manually. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path = @@@instance@@@, public;

DROP VIEW gis_regions;
DROP VIEW gis_points;
DROP VIEW gis_tag_points;
DROP VIEW gis_blocks;
DROP VIEW gis_basemaps;
DROP VIEW gis_rt_endpoints;
DROP VIEW gis_rt_start;
DROP VIEW gis_rt_end;
DROP VIEW gis_rt_blocks;
DROP VIEW route_endpoints;

DELETE FROM geometry_columns WHERE f_table_schema = '@@@instance@@@' AND
  (f_table_name LIKE 'gis_%' OR f_table_name = 'route_endpoints');

DROP FUNCTION has_tag(int, text);

COMMIT;

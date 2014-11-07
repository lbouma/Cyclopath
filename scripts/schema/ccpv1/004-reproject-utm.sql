/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script reprojects the data from geographic WGS84 (EPSG 4326) to
   NAD83-based UTM Zone 15N (EPSG 26915). */

\set srid 26915

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

DELETE FROM byway_node WHERE id = 0;

ALTER TABLE byway_segment DROP CONSTRAINT enforce_srid_geometry;
UPDATE byway_segment SET geometry = Transform(geometry, :srid);
ALTER TABLE byway_segment ADD CONSTRAINT enforce_srid_geometry CHECK(srid(geometry) = :srid);
SELECT UpdateGeometrySRID('byway_segment', 'geometry', :srid);
DROP INDEX byway_segment_gist;
CREATE INDEX byway_segment_gist ON byway_segment
  USING GIST ( geometry GIST_GEOMETRY_OPS );
\d byway_segment;
SELECT astext(geometry) FROM byway_segment LIMIT 2;

UPDATE geometry_columns SET srid = :srid WHERE f_table_name = 'byway_joined_current';

ALTER TABLE byway_node DROP CONSTRAINT enforce_srid_geometry;
UPDATE byway_node SET geometry = Transform(geometry, :srid);
ALTER TABLE byway_node ADD CONSTRAINT enforce_srid_geometry CHECK(srid(geometry) = :srid);
SELECT UpdateGeometrySRID('byway_node', 'geometry', :srid);
DROP INDEX byway_node_gist;
CREATE INDEX byway_node_gist ON byway_node
  USING GIST ( geometry GIST_GEOMETRY_OPS );
\d byway_node;
SELECT astext(geometry) FROM byway_node LIMIT 2;

SELECT * FROM geometry_columns;

COMMIT;
-- ROLLBACK;

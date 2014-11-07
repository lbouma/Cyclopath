/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Byway Node table. It does _not_ populate it. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/** Tables **/

CREATE TABLE byway_node (
  id INT UNIQUE NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);  
SELECT AddGeometryColumn('byway_node', 'geometry', 4326, 'POINT', 2);
ALTER TABLE byway_node ADD CONSTRAINT enforce_valid_geometry
  CHECK (IsValid(geometry));
CREATE INDEX byway_node_gist ON byway_node
  USING GIST ( geometry GIST_GEOMETRY_OPS );
ALTER TABLE byway_node ALTER geometry SET NOT NULL;

ALTER TABLE byway_segment ADD COLUMN start_node_id INT;
ALTER TABLE byway_segment ADD COLUMN start_node_version INT;
ALTER TABLE byway_segment
  ADD FOREIGN KEY (start_node_id, start_node_version) REFERENCES byway_node;

ALTER TABLE byway_segment ADD COLUMN end_node_id INT;
ALTER TABLE byway_segment ADD COLUMN end_node_version INT;
ALTER TABLE byway_segment
  ADD FOREIGN KEY (end_node_id, end_node_version) REFERENCES byway_node;

ALTER TABLE byway_segment ALTER byway_type_code SET NOT NULL;
ALTER TABLE byway_segment ALTER geometry SET NOT NULL;

\d byway_node;
\d byway_segment;

COMMIT;

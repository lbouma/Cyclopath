/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Point table. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;


/** Point tables **/

CREATE TABLE point_type (
  code INT PRIMARY KEY,
  draw_class_code INT NOT NULL REFERENCES draw_class (code) DEFERRABLE,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER point_type_u BEFORE UPDATE ON point_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER point_type_ilm BEFORE INSERT ON point_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
  

CREATE TABLE point (
  id INT UNIQUE NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  name TEXT,
  type_code INT NOT NULL REFERENCES point_type (code) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);
SELECT AddGeometryColumn('point', 'geometry', 26915, 'POINT', 2);
ALTER TABLE point ALTER COLUMN geometry SET NOT NULL;
ALTER TABLE point ADD CONSTRAINT enforce_valid_geometry
  CHECK (IsValid(geometry));
CREATE INDEX point_gist ON point USING GIST ( geometry GIST_GEOMETRY_OPS );


/** Instances **/

INSERT INTO draw_class (code, text,        color)
                VALUES (5,    'point',     X'fe766a'::INT);
INSERT INTO point_type (code, draw_class_code, text)
                VALUES (2,    5,               'default');

COPY draw_param (draw_class_code, zoom, width, label) FROM STDIN;
5	13	2	f
5	14	4	f
5	15	6	t
5	16	8	t
5	17	9	t
5	18	10	t
5	19	11	t
\.

\d point_type;
SELECT * FROM point_type;
\d point;
SELECT * FROM draw_class;
SELECT * FROM draw_param_joined WHERE draw_class_code = 5;
COMMIT;

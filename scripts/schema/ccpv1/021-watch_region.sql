/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Watch Region tables. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/** Watch Region tables **/

CREATE TABLE watch_region_type (
  code INT PRIMARY KEY,
  draw_class_code INT NOT NULL REFERENCES draw_class (code) DEFERRABLE,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER watch_region_u BEFORE UPDATE ON watch_region_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER watch_region_ilm BEFORE INSERT ON watch_region_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

/* Technically watch_regions don't need versioning, but to make it 
   more compatible with existing features, it will have the versioning
   columns. */
CREATE TABLE watch_region ( 
  id INT UNIQUE NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  name TEXT,
  username TEXT NOT NULL REFERENCES user_ (username) DEFERRABLE,
  color INT NOT NULL,
  notify_email BOOL NOT NULL DEFAULT true,
  type_code INT NOT NULL REFERENCES watch_region_type (code) DEFERRABLE,
  valid_starting_rid INT NOT NULL,
  valid_before_rid INT NOT NULL,
  z INT NOT NULL,
  PRIMARY KEY (id)
);
SELECT AddGeometryColumn('watch_region', 'geometry', 26915, 'POLYGON', 2);
/*ALTER TABLE watch_region ADD CONSTRAINT enforce_valid_geometry
  CHECK (IsValid(geometry));*/
CREATE INDEX watch_region_gist ON watch_region
  USING GIST ( geometry GIST_GEOMETRY_OPS );

/** Instances **/

INSERT INTO draw_class (code, text, color)
                VALUES (6,    'watch_region', X'3300ff'::INT);
INSERT INTO watch_region_type (code, draw_class_code, text)
                       VALUES (2,    6,               'default');

COPY draw_param (draw_class_code, zoom, width, label) FROM STDIN;
6	9	4	f
6	10	4	f
6	11	4	f
6	12	4	f
6	13	6	f
6	14	6	f
6	15	8	f
6	16	8	f
6	17	10	f
6	18	10	f
6	19	10	f
\.

\d watch_region_type;
SELECT * FROM watch_region_type;
\d watch_region;
SELECT * FROM draw_class;
SELECT * FROM draw_param_joined WHERE draw_class_code = 6;
COMMIT;

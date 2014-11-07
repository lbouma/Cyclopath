/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Basemap Polygon table. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;


/** Basemap Polygon tables **/

CREATE TABLE basemap_polygon_type (
  code INT PRIMARY KEY,
  draw_class_code INT NOT NULL REFERENCES draw_class (code) DEFERRABLE,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER basemap_polygon_type_u BEFORE UPDATE ON basemap_polygon_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER basemap_polygon_type_ilm BEFORE INSERT ON basemap_polygon_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
  

CREATE TABLE basemap_polygon (
  id INT UNIQUE NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  name TEXT,
  type_code INT NOT NULL REFERENCES basemap_polygon_type (code) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);
SELECT AddGeometryColumn('basemap_polygon', 'geometry', 26915, 'POLYGON', 2);
ALTER TABLE basemap_polygon ADD CONSTRAINT enforce_valid_geometry
  CHECK (IsValid(geometry));
CREATE INDEX basemap_polygon_gist ON basemap_polygon
  USING GIST ( geometry GIST_GEOMETRY_OPS );


/** Instances **/

ALTER TABLE draw_class ADD COLUMN color INT;
UPDATE draw_class SET color = X'ffffff'::INT WHERE code = 11;
UPDATE draw_class SET color = X'fffa73'::INT WHERE code = 21;
UPDATE draw_class SET color = X'fffa73'::INT WHERE code = 31;
UPDATE draw_class SET color = X'f2bf24'::INT WHERE code = 41;
ALTER TABLE draw_class ALTER color SET NOT NULL;
INSERT INTO draw_class (code, text,        color)
                VALUES (1,    'shadow',    X'ab9e89'::INT);
INSERT INTO draw_class (code, text,        color)
                VALUES (2,    'openspace', X'a7cc95'::INT);
INSERT INTO draw_class (code, text,        color)
                VALUES (3,    'water',     X'99b3cc'::INT);

COPY basemap_polygon_type (code, draw_class_code, text) FROM STDIN;
2	2	openspace
3	3	water
\.

\d basemap_polygon_type;
SELECT * FROM basemap_polygon_type;
\d basemap_polygon;
\d draw_class;
SELECT * FROM draw_class;
COMMIT;

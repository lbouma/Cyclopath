/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Byway table and friends and the Revision table. */


/** Last-modified stuff **/

/* Many tables (those tied into the Revision mechanism) have more
   sophisticated revision tracking and do not use this function. */

CREATE OR REPLACE FUNCTION set_last_modified() RETURNS TRIGGER AS '
  BEGIN 
    NEW.last_modified = now();
    RETURN NEW;
  END
' LANGUAGE 'plpgsql';


/** Tables **/

CREATE SEQUENCE feature_id_seq;


CREATE TABLE draw_class (
  code INT PRIMARY KEY,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER draw_class_u BEFORE UPDATE ON draw_class 
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER draw_class_i BEFORE INSERT ON draw_class
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();


CREATE TABLE draw_param (
  draw_class_code INT NOT NULL REFERENCES draw_class (code) DEFERRABLE,
  zoom INT NOT NULL,
  width REAL NOT NULL,
  label BOOL NOT NULL,
  last_modified TIMESTAMP NOT NULL,
  PRIMARY KEY (draw_class_code, zoom)
);
CREATE TRIGGER draw_param_u BEFORE UPDATE ON draw_param 
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER draw_param_i BEFORE INSERT ON draw_param
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();


CREATE TABLE byway_type (
  code INT PRIMARY KEY,
  draw_class_code INT NOT NULL REFERENCES draw_class (code) DEFERRABLE,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER byway_type_u BEFORE UPDATE ON byway_type 
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER byway_type_i BEFORE INSERT ON byway_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();


CREATE TABLE revision (
  id SERIAL PRIMARY KEY,
  timestamp TIMESTAMP NOT NULL,
  host text NOT NULL,
  username TEXT,
  comment TEXT
);


CREATE TABLE byway_segment (
  id INT UNIQUE NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  name TEXT,
  name2 TEXT,
  byway_type_code INT REFERENCES byway_type (code) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);
SELECT AddGeometryColumn('byway_segment', 'geometry', 4326, 'LINESTRING', 2);
ALTER TABLE byway_segment ADD CONSTRAINT enforce_valid_geometry
  CHECK (IsValid(geometry));
CREATE INDEX byway_segment_gist ON byway_segment
  USING GIST ( geometry GIST_GEOMETRY_OPS );


/** Instances **/

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO draw_class VALUES (11, 'small');
INSERT INTO draw_class VALUES (21, 'medium');
INSERT INTO draw_class VALUES (31, 'large');
INSERT INTO draw_class VALUES (41, 'super');

/* These values are mostly guesses. I fully expect to tweak them later. */
INSERT INTO draw_param VALUES (11, 19, 13.0, TRUE); 
INSERT INTO draw_param VALUES (11, 18, 13.0, TRUE);
INSERT INTO draw_param VALUES (11, 17, 13.0, TRUE);
INSERT INTO draw_param VALUES (11, 16, 12.0, TRUE);
INSERT INTO draw_param VALUES (11, 15, 10.0, TRUE);
INSERT INTO draw_param VALUES (11, 14,  4.0, FALSE);
INSERT INTO draw_param VALUES (11, 13,  2.0, FALSE);

INSERT INTO draw_param VALUES (21, 19, 15.0, TRUE); 
INSERT INTO draw_param VALUES (21, 18, 15.0, TRUE);
INSERT INTO draw_param VALUES (21, 17, 15.0, TRUE);
INSERT INTO draw_param VALUES (21, 16, 14.0, TRUE);
INSERT INTO draw_param VALUES (21, 15, 12.0, TRUE);
INSERT INTO draw_param VALUES (21, 14, 11.0, TRUE);
INSERT INTO draw_param VALUES (21, 13, 10.0, TRUE);
INSERT INTO draw_param VALUES (21, 12,  4.0, FALSE);
INSERT INTO draw_param VALUES (21, 11,  3.0, FALSE);
INSERT INTO draw_param VALUES (21, 10,  2.0, FALSE);
INSERT INTO draw_param VALUES (21,  9,  1.5, FALSE);

INSERT INTO draw_param VALUES (31, 19, 15.0, TRUE); 
INSERT INTO draw_param VALUES (31, 18, 15.0, TRUE);
INSERT INTO draw_param VALUES (31, 17, 15.0, TRUE);
INSERT INTO draw_param VALUES (31, 16, 14.0, TRUE);
INSERT INTO draw_param VALUES (31, 15, 12.0, TRUE);
INSERT INTO draw_param VALUES (31, 14, 11.0, TRUE);
INSERT INTO draw_param VALUES (31, 13, 10.0, TRUE);
INSERT INTO draw_param VALUES (31, 12,  6.0, FALSE);
INSERT INTO draw_param VALUES (31, 11,  5.0, FALSE);
INSERT INTO draw_param VALUES (31, 10,  4.0, FALSE);
INSERT INTO draw_param VALUES (31,  9,  3.0, FALSE);
INSERT INTO draw_param VALUES (31,  8,  2.0, FALSE);
INSERT INTO draw_param VALUES (31,  7,  1.5, FALSE);

INSERT INTO draw_param VALUES (41, 19, 15.0, TRUE); 
INSERT INTO draw_param VALUES (41, 18, 15.0, TRUE);
INSERT INTO draw_param VALUES (41, 17, 15.0, TRUE);
INSERT INTO draw_param VALUES (41, 16, 14.0, TRUE);
INSERT INTO draw_param VALUES (41, 15, 13.0, TRUE);
INSERT INTO draw_param VALUES (41, 14, 12.0, TRUE);
INSERT INTO draw_param VALUES (41, 13, 11.0, TRUE);
INSERT INTO draw_param VALUES (41, 12, 10.0, TRUE);
INSERT INTO draw_param VALUES (41, 11,  9.0, TRUE);
INSERT INTO draw_param VALUES (41, 10,  7.0, FALSE);
INSERT INTO draw_param VALUES (41,  9,  6.0, FALSE);
INSERT INTO draw_param VALUES (41,  8,  5.0, FALSE);
INSERT INTO draw_param VALUES (41,  7,  4.0, FALSE);
INSERT INTO draw_param VALUES (41,  6,  3.0, FALSE);

INSERT INTO byway_type VALUES (41, 41, 'Limited-Access Expressway');
INSERT INTO byway_type VALUES (31, 31, 'Primary Highway');
INSERT INTO byway_type VALUES (21, 21, 'Secondary Road');
INSERT INTO byway_type VALUES (11, 11, 'Local Road');
INSERT INTO byway_type VALUES (12, 11, '4WD Road');
INSERT INTO byway_type VALUES (13, 21, 'Bicycle Expressway');
INSERT INTO byway_type VALUES (14, 11, 'Bicycle Trail');
INSERT INTO byway_type VALUES ( 1, 11, 'Unknown');
INSERT INTO byway_type VALUES ( 2, 11, 'Other');

COMMIT;

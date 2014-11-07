/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script does some general setup (once for all instances) necessary for
tracks. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO public;

CREATE TABLE track_type (
  code INT PRIMARY KEY,
  draw_class_code INT NOT NULL REFERENCES draw_class(code) DEFERRABLE,
  text TEXT NOT NULL,
  last_modified TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE TRIGGER track_type_u BEFORE UPDATE ON track_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER track_type_ilm BEFORE INSERT ON track_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

INSERT INTO draw_class (code, text, color)
                VALUES (10, 'track', X'009900'::INT);
INSERT INTO track_type (code, draw_class_code, text)
                VALUES (2, 10, 'default');

COPY draw_param (draw_class_code, zoom, width, label) FROM STDIN;
10	9	3	f
10	10	3	f
10	11	3	f
10	12	3	f
10	13	3	f
10	14	3	f
10	15	6	f
10	16	9	f
10	17	12	f
10	18	15	f
10	19	18	f
\.

COMMIT;


/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script updates the route table to include geofeature related columns */
BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/** Route table updates **/

CREATE TABLE route_type (
  code INT PRIMARY KEY,
  draw_class_code INT NOT NULL REFERENCES draw_class (code) DEFERRABLE,
  text TEXT NOT NULL,
  last_modified TIMESTAMP NOT NULL
);
CREATE TRIGGER route_type_u BEFORE UPDATE ON route_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER route_type_ilm BEFORE INSERT ON route_type
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();

/** Update the types **/
INSERT INTO draw_class (code, text, color) 
                VALUES (8,    'route', X'00c4ff'::INT);
INSERT INTO route_type (code, draw_class_code, text)
                VALUES (2,    8,               'default');

ALTER TABLE route ADD deleted BOOLEAN;
UPDATE route SET deleted=false WHERE deleted IS NULL;
ALTER TABLE route ALTER COLUMN deleted SET NOT NULL;

ALTER TABLE route ADD type_code INT REFERENCES route_type (code) DEFERRABLE;
UPDATE route SET type_code=2 WHERE type_code IS NULL;
ALTER TABLE route ALTER COLUMN type_code SET NOT NULL;

ALTER TABLE route ADD valid_starting_rid INT;
UPDATE route SET valid_starting_rid=0 WHERE valid_starting_rid IS NULL;
ALTER TABLE route ALTER COLUMN valid_starting_rid SET NOT NULL;

ALTER TABLE route ADD valid_before_rid INT;
UPDATE route SET valid_before_rid=rid_inf() WHERE valid_before_rid IS NULL;
ALTER TABLE route ALTER COLUMN valid_before_rid SET NOT NULL;

ALTER TABLE route ADD version INT;
UPDATE route SET version=1 WHERE version IS NULL;
ALTER TABLE route ALTER COLUMN version SET NOT NULL;

ALTER TABLE route ADD z INT;
UPDATE route SET z=160 WHERE z IS NULL;
ALTER TABLE route ALTER COLUMN z SET NOT NULL;

COPY draw_param (draw_class_code, zoom, width, label) FROM STDIN;
8	9	5	f
8	10	6	f
8	11	7	f
8	12	8	f
8	13	9	f
8	14	10	f
8	15	11	f
8	16	12	f
8	17	13	f
8	18	14	f
8	19	15	f
\.

COMMIT;

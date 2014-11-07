/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Route and Route_Step tables. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;


CREATE TABLE route_step (
  route_id INT NOT NULL,
  step_number INT NOT NULL,
  byway_id INT NOT NULL,
  byway_version INT NOT NULL,
  forward BOOLEAN NOT NULL,
  last_modified TIMESTAMP NOT NULL,
  PRIMARY KEY (route_id, step_number),
  FOREIGN KEY (byway_id, byway_version)
    REFERENCES byway_segment (id, version) DEFERRABLE
);
CREATE TRIGGER route_step_u BEFORE UPDATE ON route_step
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER route_step_ilm BEFORE INSERT ON route_step
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();


CREATE TABLE route (
  id INT PRIMARY KEY,
  owner_name TEXT,
  name TEXT,
  last_modified TIMESTAMP NOT NULL,
  FOREIGN KEY (owner_name) REFERENCES user_(username) DEFERRABLE
);
CREATE TRIGGER route_u BEFORE UPDATE ON route
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER route_ilm BEFORE INSERT ON route
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();


CREATE TABLE route_digest (
  id SERIAL PRIMARY KEY,
  username TEXT,
  last_modified TIMESTAMP NOT NULL,
  FOREIGN KEY (username) REFERENCES user_(username) DEFERRABLE
);
SELECT AddGeometryColumn('route_digest', 'start_xy', 26915, 'POINT', 2);
ALTER TABLE route_digest ALTER COLUMN start_xy SET NOT NULL;
ALTER TABLE route_digest ADD CONSTRAINT enforce_valid_start_xy
  CHECK (IsValid(start_xy));
CREATE INDEX start_xy_gist ON route_digest USING GIST (start_xy);
SELECT AddGeometryColumn('route_digest', 'end_xy', 26915, 'POINT', 2);
ALTER TABLE route_digest ALTER COLUMN end_xy SET NOT NULL;
ALTER TABLE route_digest ADD CONSTRAINT enforce_valid_end_xy
  CHECK (IsValid(end_xy));
CREATE INDEX end_xy_gist ON route_digest USING GIST (end_xy);
CREATE TRIGGER route_digest_u BEFORE UPDATE ON route_digest
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();
CREATE TRIGGER route_digest_ilm BEFORE INSERT ON route_digest
  FOR EACH ROW EXECUTE PROCEDURE set_last_modified();


\d route
\d route_step
\d route_digest

--ROLLBACK;
COMMIT;

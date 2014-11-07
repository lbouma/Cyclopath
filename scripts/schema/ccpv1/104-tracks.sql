/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the initial tables needed for saving tracks. */
/* @once-per-instance */
BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

CREATE TABLE track (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  owner_name TEXT,
  name TEXT,
  host inet,
  source TEXT,
  comments TEXT,
  deleted BOOL NOT NULL,
  type_code INT NOT NULL,
  valid_starting_rid INT NOT NULL,
  valid_before_rid INT NOT NULL,
  version INT NOT NULL,
  z INT NOT NULL,
  created TIMESTAMP WITH TIME ZONE NOT NULL,
  permission INT NOT NULL DEFAULT 3,
  visibility INT NOT NULL DEFAULT 3,
  PRIMARY KEY (id, version),
  FOREIGN KEY (owner_name) REFERENCES user_(username) DEFERRABLE,
  FOREIGN KEY (type_code) REFERENCES track_type(code) DEFERRABLE,
  FOREIGN KEY (permission) REFERENCES permissions(code),
  FOREIGN KEY (visibility) REFERENCES visibility(code)
);

CREATE TRIGGER track_ic BEFORE INSERT ON track
  FOR EACH ROW EXECUTE PROCEDURE set_created();

ALTER TABLE track ADD CONSTRAINT enforce_version CHECK (version >= 1);
ALTER TABLE track ADD CONSTRAINT enforce_permissions
   CHECK (visibility = 3 OR owner_name IS NOT NULL OR permission = 1);

CREATE TABLE track_point (
  id SERIAL,
  track_id INT NOT NULL,
  track_version INT NOT NULL,
  x INT NOT NULL,
  y INT NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
  altitude REAL,
  bearing REAL,
  speed REAL,
  orientation REAL,
  temperature REAL,
  FOREIGN KEY (track_id, track_version) REFERENCES track(id, version)
);

CREATE INDEX track_point_track_id_version ON track_point(track_id, 
                                                         track_version);
CREATE INDEX track_point_track_id ON track_point(track_id);
CREATE INDEX track_point_track_version ON track_point(track_version);
CREATE INDEX track_point_timestamp ON track_point(timestamp);

COMMIT;


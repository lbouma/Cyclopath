/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the tables required for linking revisions to posts.
   @once-per-instance */

SET search_path TO @@@instance@@@, public;

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

CREATE TABLE post_revision (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  post_id INT NOT NULL,
  rev_id INT NOT NULL,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

CREATE OR REPLACE VIEW post_revision_geo AS
SELECT
  pg.id AS id,
  pg.version AS version,
  pg.deleted AS deleted,
  pg.post_id,
  pg.rev_id,
  r.geosummary AS geometry,
  pg.valid_starting_rid AS valid_starting_rid,
  pg.valid_before_rid AS valid_before_rid
FROM post_revision pg JOIN revision r ON pg.rev_id = r.id;

CREATE OR REPLACE VIEW post_obj_geo AS (
  SELECT
    id,
    version,
    deleted,
    post_id,
    byway_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
  FROM post_bs_geo
UNION
  SELECT
    id,
    version,
    deleted,
    post_id,
    point_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
  FROM post_point_geo
UNION
  SELECT
    id,
    version,
    deleted,
    post_id,
    region_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
  FROM post_region_geo
UNION
  SELECT
    id,
    version,
    deleted,
    post_id,
    rev_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
  FROM post_revision_geo
);

COMMIT;

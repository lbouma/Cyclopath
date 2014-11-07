/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the initial tables needed for tagging of points and
   byways. Note that while tags are technically versioned features, they are
   immutable in the current implementation. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

DROP VIEW geofeature;

CREATE TABLE tag (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL CHECK (version = 1),
  deleted BOOL NOT NULL,
  label TEXT NOT NULL UNIQUE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);
CREATE INDEX tag_valid_starting_rid on tag (valid_starting_rid);
CREATE INDEX tag_valid_before_rid on tag (valid_before_rid);

CREATE TABLE tag_bs (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  /* FIXME: Cannot reference only part of a primary key */
  tag_id INT NOT NULL,   -- REFERENCES tag (id) DEFERRABLE,
  byway_id INT NOT NULL, -- REFERENCES byway_segment (id) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);
CREATE INDEX tag_bs_tag_id on tag_bs (tag_id);
CREATE INDEX tag_bs_byway_id on tag_bs (byway_id);
CREATE INDEX tag_bs_valid_starting_rid on tag_bs (valid_starting_rid);
CREATE INDEX tag_bs_valid_before_rid on tag_bs (valid_before_rid);

CREATE TABLE tag_point (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  tag_id INT NOT NULL,   -- REFERENCES tag (id) DEFERRABLE,
  point_id INT NOT NULL, -- REFERENCES point (id) DEFERRABLE,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);
CREATE INDEX tag_point_tag_id on tag_point (tag_id);
CREATE INDEX tag_point_point_id on tag_point (point_id);
CREATE INDEX tag_point_valid_starting_rid on tag_point (valid_starting_rid);
CREATE INDEX tag_point_valid_before_rid on tag_point (valid_before_rid);

/* c.f. annot_bs_geo */
CREATE VIEW tag_bs_geo AS
SELECT
  tb.id AS id,
  tb.version AS version,
  (bs.deleted OR tb.deleted) AS deleted,
  tag_id,
  byway_id,
  bs.geometry AS geometry,
  GREATEST(tb.valid_starting_rid, bs.valid_starting_rid) AS valid_starting_rid,
  LEAST(tb.valid_before_rid, bs.valid_before_rid) AS valid_before_rid
FROM tag_bs tb JOIN byway_segment bs ON tb.byway_id = bs.id
WHERE
  tb.valid_starting_rid < bs.valid_before_rid
  AND bs.valid_starting_rid < tb.valid_before_rid;

CREATE VIEW tag_point_geo AS
SELECT
  tp.id AS id,
  tp.version AS version,
  (p.deleted OR tp.deleted) AS deleted,
  tag_id,
  point_id,
  p.geometry AS geometry,
  GREATEST(tp.valid_starting_rid, p.valid_starting_rid) AS valid_starting_rid,
  LEAST(tp.valid_before_rid, p.valid_before_rid) AS valid_before_rid
FROM tag_point tp JOIN point p ON tp.point_id = p.id
WHERE
  tp.valid_starting_rid < p.valid_before_rid
  AND p.valid_starting_rid < tp.valid_before_rid;

/* Union of the two preceding views for use in tag_geo view */
CREATE VIEW tag_obj_geo AS
  SELECT
    id,
    version,
    deleted,
    tag_id,
    byway_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
    FROM tag_bs_geo
UNION
  SELECT
    id,
    version,
    deleted,
    tag_id,
    point_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
    FROM tag_point_geo;

/* c.f. annotation_geo; returns tags with geometry */
CREATE view tag_geo as
SELECT
  t.id AS id,
  t.version AS version,
  (t.deleted or tb.deleted) as deleted,
  label,
  tb.geometry as geometry,
  GREATEST(t.valid_starting_rid, tb.valid_starting_rid) AS valid_starting_rid,
  LEAST(t.valid_before_rid, tb.valid_before_rid) AS valid_before_rid
FROM tag t JOIN tag_obj_geo tb ON t.id = tb.tag_id
WHERE
  t.valid_starting_rid < tb.valid_before_rid
  AND tb.valid_starting_rid < t.valid_before_rid;

/* A view containing common columns of versioned geometric tables. */

create view geofeature as
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from basemap_polygon
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from point
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from byway_segment
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from annotation_geo
union
  select id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  from tag_geo;

\d tag
\d tag_bs
\d tag_point
\d tag_bs_geo
\d tag_point_geo
\d tag_point_bs_geo
\d tag_geo
\d geofeature

--ROLLBACK;
COMMIT;

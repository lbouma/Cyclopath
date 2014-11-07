/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* Aability to link routes to posts. */

/* FIXME: This is made into a link_value btw. a post and a route. Is that okay?
 *        Or should this be an attribute like /post/revision? */
CREATE TABLE post_route (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  post_id INT NOT NULL,
  route_id INT NOT NULL,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

CREATE OR REPLACE VIEW post_route_geo AS
SELECT
  pg.id AS id,
  pg.version AS version,
  (g.deleted OR pg.deleted) AS deleted,
  post_id,
  route_id,
  g.geometry AS geometry,
  GREATEST(pg.valid_starting_rid, g.valid_starting_rid) AS valid_starting_rid,
  LEAST(pg.valid_before_rid, g.valid_before_rid) AS valid_before_rid
FROM post_route pg JOIN route_geo g ON pg.route_id = g.id
WHERE
  pg.valid_starting_rid > g.valid_starting_rid
  AND g.valid_starting_rid < pg.valid_before_rid;

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
    route_id AS obj_id,
    geometry,
    valid_starting_rid,
    valid_before_rid
    FROM post_route_geo
);

/* Modify the thread and post tables. */

ALTER TABLE thread ADD COLUMN ttype TEXT NOT NULL DEFAULT 'general';

/* 2012.09.20: EXPLAIN: So, polarity is a like or dislike, but also counts as
 * one post? */
ALTER TABLE post ADD COLUMN polarity INT NOT NULL DEFAULT 0;

/* Update post_geo */

CREATE OR REPLACE VIEW post_geo as
SELECT
  p.id,
  p.version AS version,
  (p.deleted or pg.deleted) as deleted,
  -- ERROR:  cannot change number of columns in view
  --   (see geofeature view)
  --p.polarity as polarity,
  pg.obj_id as gf_id,
  pg.geometry as geometry,
  GREATEST(p.valid_starting_rid, pg.valid_starting_rid) AS valid_starting_rid,
  LEAST(p.valid_before_rid, pg.valid_before_rid) AS valid_before_rid
FROM post p JOIN post_obj_geo pg ON p.id = pg.post_id
WHERE
  p.valid_starting_rid <= pg.valid_before_rid
  AND pg.valid_starting_rid < p.valid_before_rid;

CREATE OR REPLACE VIEW geofeature AS
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM basemap_polygon
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM point
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM byway_segment
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM region
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM annotation_geo
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM tag_geo
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM route_geo
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM post_geo;

/* Functions */

/* FIXME: reactions. convert this to Python fcn. */
CREATE OR REPLACE FUNCTION total_polarity(tid INT)
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT SUM(p.polarity) INTO ans
   FROM post p
   WHERE p.thread_id = tid
         AND p.valid_before_rid = rid_inf();

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

/* FIXME: reactions. convert this to Python fcn. */
CREATE OR REPLACE FUNCTION unread_posts(tid INT, u TEXT)
RETURNS INT AS $$
DECLARE ans INT;
DECLARE last_viewed timestamp with time zone;
BEGIN
   SELECT COALESCE(MAX(created), '-infinity') INTO last_viewed
   FROM thread_read_event tre
   WHERE tre.username = u 
         AND tre.thread_id = tid;

   IF u = '' THEN
      SELECT COUNT(*) INTO ans
      FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed
            AND p.body != ''
            AND p.body != 'null'
            AND p.body IS NOT NULL
            AND p.valid_before_rid = rid_inf();
   ELSE
      SELECT COUNT(*) INTO ans
      FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed
            AND COALESCE(r.username, r.host) != u
            AND p.body != ''
            AND p.body != 'null'
            AND p.body IS NOT NULL
            AND p.valid_before_rid = rid_inf();
   END IF;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

/* FIXME: reactions. convert this to Python fcn. */
CREATE OR REPLACE FUNCTION total_posts(tid INT)
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(*) INTO ans
   FROM post p 
   WHERE p.thread_id = tid
         AND p.body != ''
         AND p.body != 'null'
         AND p.body IS NOT NULL
         AND p.valid_before_rid = rid_inf();

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

-- Currently, we do not allow revisions with posts and other non-social items
-- together. So, this function can easily compute whether given revision is a
-- "discussions/reactions"-only revision or not.
/* FIXME: reactions. convert this to Python fcn. */
CREATE OR REPLACE FUNCTION is_social_rev(rid INT)
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans FROM post WHERE valid_starting_rid = rid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

-- To speed up "near my edits" queries.
CREATE INDEX rev_username ON revision(username);

/* Ask Me Later Stuff */

CREATE TABLE reaction_reminder (
  route_id    INT NOT NULL,
  email       TEXT NOT NULL,
  request_ts  TIMESTAMP NOT NULL DEFAULT NOW(),
  reminder_ts TIMESTAMP NOT NULL,
  sent        BOOLEAN NOT NULL DEFAULT FALSE
);

COMMIT;


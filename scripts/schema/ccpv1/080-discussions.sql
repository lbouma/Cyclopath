/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script creates the Thread, Post and related tables. */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* The objects themselves */

CREATE TABLE thread (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  title TEXT,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

CREATE TABLE post (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  body TEXT,
  thread_id INT NOT NULL,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

/* Attaching places to posts */

CREATE TABLE post_point (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  post_id INT NOT NULL,
  point_id INT NOT NULL,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

CREATE TABLE post_bs (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  post_id INT NOT NULL,
  byway_id INT NOT NULL,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

CREATE TABLE post_region (
  id INT NOT NULL DEFAULT nextval('feature_id_seq'),
  version INT NOT NULL,
  deleted BOOL NOT NULL,
  post_id INT NOT NULL,
  region_id INT NOT NULL,
  valid_starting_rid INT NOT NULL REFERENCES revision (id) DEFERRABLE,
  valid_before_rid INT REFERENCES revision (id) DEFERRABLE,
  PRIMARY KEY (id, version)
);

CREATE OR REPLACE VIEW post_bs_geo AS
SELECT
  pg.id AS id,
  pg.version AS version,
  (g.deleted OR pg.deleted) AS deleted,
  post_id,
  byway_id,
  g.geometry AS geometry,
  GREATEST(pg.valid_starting_rid, g.valid_starting_rid) AS valid_starting_rid,
  LEAST(pg.valid_before_rid, g.valid_before_rid) AS valid_before_rid
FROM post_bs pg JOIN byway_segment g ON pg.byway_id = g.id
WHERE
  pg.valid_starting_rid < g.valid_before_rid
  AND g.valid_starting_rid < pg.valid_before_rid;

CREATE OR REPLACE VIEW post_point_geo AS
SELECT
  pg.id AS id,
  pg.version AS version,
  (g.deleted OR pg.deleted) AS deleted,
  post_id,
  point_id,
  g.geometry AS geometry,
  GREATEST(pg.valid_starting_rid, g.valid_starting_rid) AS valid_starting_rid,
  LEAST(pg.valid_before_rid, g.valid_before_rid) AS valid_before_rid
FROM post_point pg JOIN point g ON pg.point_id = g.id
WHERE
  pg.valid_starting_rid < g.valid_before_rid
  AND g.valid_starting_rid < pg.valid_before_rid;

CREATE OR REPLACE VIEW post_region_geo AS
SELECT
  pg.id AS id,
  pg.version AS version,
  (g.deleted OR pg.deleted) AS deleted,
  post_id,
  region_id,
  g.geometry AS geometry,
  GREATEST(pg.valid_starting_rid, g.valid_starting_rid) AS valid_starting_rid,
  LEAST(pg.valid_before_rid, g.valid_before_rid) AS valid_before_rid
FROM post_region pg JOIN region g ON pg.region_id = g.id
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
);

CREATE OR REPLACE VIEW post_geo as
SELECT
  p.id,
  p.version AS version,
  (p.deleted or pg.deleted) as deleted,
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
  FROM annotation_geo
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM tag_geo
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM post_geo;


/* Watching */

CREATE TABLE thread_read_event (
  id SERIAL PRIMARY KEY,
  username TEXT NOT NULL REFERENCES user_ (username) DEFERRABLE,
  thread_id INT NOT NULL,
  created TIMESTAMP NOT NULL  
);

CREATE TRIGGER thread_read_event_i before insert on thread_read_event
  FOR EACH ROW EXECUTE PROCEDURE set_created();

CREATE TABLE thread_watcher (
  thread_id INT NOT NULL,
  username TEXT NOT NULL,
  PRIMARY KEY (thread_id, username)
);

CREATE TABLE tw_email_pending (
  thread_id INT NOT NULL,
  post_id INT NOT NULL,
  username TEXT NOT NULL,
  PRIMARY KEY (thread_id, post_id, username)
);

/* Some utility functions */

CREATE OR REPLACE FUNCTION contains_text(tid INT, txt TEXT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post
   WHERE thread_id = tid AND body ~ txt;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION contains_user(tid INT, u TEXT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
   WHERE p.thread_id = tid AND COALESCE(r.username, r.host) ~ u;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION intersects_geom(tid INT, geom GEOMETRY) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post p JOIN post_geo pg ON (p.id = pg.post_id)
   WHERE p.thread_id = tid AND ST_Intersects(pg.geometry, geom);

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION unread_posts(tid INT, u TEXT)
RETURNS INT AS $$
DECLARE ans INT;
DECLARE last_viewed TIMESTAMP;
BEGIN
   SELECT COALESCE(MAX(created), '-infinity') INTO last_viewed
   FROM thread_read_event tre
   WHERE tre.username = u 
         AND tre.thread_id = tid;

   IF u = '' THEN
      SELECT COUNT(*) INTO ans
      FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed;
   ELSE
      SELECT COUNT(*) INTO ans
      FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
      WHERE p.thread_id = tid
            AND r.timestamp > last_viewed
            AND COALESCE(r.username, r.host) != u;
   END IF;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION total_posts(tid INT)
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(*) INTO ans
   FROM post p 
   WHERE p.thread_id = tid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION lp_user(tid INT) 
RETURNS TEXT AS $$
DECLARE ans TEXT;
BEGIN
   SELECT COALESCE(username, host) INTO ans
   FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
   WHERE p.thread_id = tid
   ORDER BY timestamp DESC
   LIMIT 1;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION lp_ts(tid INT) 
RETURNS TIMESTAMP AS $$
DECLARE ans TIMESTAMP;
BEGIN
   SELECT MAX(timestamp) INTO ans
   FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
   WHERE p.thread_id = tid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION format_ts(ts TIMESTAMP) 
RETURNS TEXT AS $$
DECLARE f_ans TEXT;
BEGIN
   IF ts > now() - interval '1 day' THEN
      f_ans := TO_CHAR(ts, 'HH:MIam');
   ELSIF ts > DATE_TRUNC('YEAR', now()) THEN
      f_ans := TO_CHAR(ts, 'Mon DD');
   ELSE
      f_ans := TO_CHAR(ts, 'MM/DD/YYYY');
   END IF;

   RETURN f_ans;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION references_gf(tid INT, gfid INT) 
RETURNS BOOLEAN AS $$
DECLARE ans BOOLEAN;
BEGIN
   SELECT (COUNT(*) > 0) INTO ans
   FROM post p JOIN post_geo pg ON (p.id = pg.id)
   WHERE p.thread_id = tid AND pg.gf_id = gfid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

-- Return no. of threads attached to a geofeature.
CREATE OR REPLACE FUNCTION n_attached_threads(gfid INT) 
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(DISTINCT p.thread_id) INTO ans
   FROM post_geo pg JOIN post p ON (pg.id = p.id)
   WHERE pg.gf_id = gfid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

-- Return no. of posts attached to a geofeature at revision r of the map.
CREATE OR REPLACE FUNCTION n_attached_posts(gfid INT, r INT) 
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(DISTINCT pg.id) INTO ans
   FROM post_geo pg
   WHERE pg.gf_id = gfid
         AND pg.valid_starting_rid <= r;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

-- What-th post after the last read event on a thread by a user?
CREATE OR REPLACE FUNCTION n_after_last_read(pid INT, u TEXT) 
RETURNS INT AS $$
DECLARE ans INT;
BEGIN
   SELECT COUNT(*) INTO ans
   FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
   WHERE p.id = pid
         AND r.timestamp > (SELECT MAX(created)
                            FROM thread_read_event tre
                            WHERE tre.thread_id = p.thread_id
                                  AND tre.username = u);

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

COMMIT;

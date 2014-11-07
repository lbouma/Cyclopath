/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This script makes sure all timestamp fields include the time zone. It has
   to be run manually because the column 'schema' is missing from
   upgrade_event (that's in 085-mn-schema-create.sql).

   @manual-upgrade */

\set TSWTZ 'timestamp with time zone'

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/* Drop views */

DROP VIEW log_event_joined;
DROP VIEW geofeature;
DROP VIEW route_geo;

/* Alter tables */

ALTER TABLE auth_fail_event       ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE byway_rating_event    ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE log_event             ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE user_preference_event ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE revert_event          ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE revision_feedback     ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE route                 ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE route_feedback        ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE tag_preference_event  ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE thread_read_event     ALTER COLUMN created TYPE :TSWTZ;
ALTER TABLE user_preference_event ALTER COLUMN created TYPE :TSWTZ;

ALTER TABLE aadt                  ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE basemap_polygon_type  ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE byway_rating          ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE byway_type            ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE draw_class            ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE draw_param            ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE point_type            ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE region_type           ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE route_type            ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE tag_preference        ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE tag_preference_type   ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE watch_region_type     ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE work_hint_status      ALTER COLUMN last_modified TYPE :TSWTZ;
ALTER TABLE work_hint_type        ALTER COLUMN last_modified TYPE :TSWTZ;

ALTER TABLE ban
  ALTER COLUMN created TYPE :TSWTZ,
  ALTER COLUMN expires TYPE :TSWTZ;

ALTER TABLE user_
  ALTER COLUMN created TYPE :TSWTZ,
  ALTER COLUMN last_modified TYPE :TSWTZ;

ALTER TABLE revision ALTER COLUMN timestamp TYPE :TSWTZ;

/* Recreate views */

CREATE VIEW log_event_joined AS
SELECT *
FROM
  log_event
  LEFT OUTER JOIN log_event_kvp ON (log_event.id = log_event_kvp.event_id);

CREATE VIEW route_geo AS
  SELECT id, owner_name, name, from_addr, to_addr, host, source, use_defaults,
         deleted, type_code, valid_starting_rid, valid_before_rid, version,
         z, created, permission, transient, details,
         (SELECT Collect(geometry) FROM route_step_geo
          WHERE route_id = id AND route_version = version) as geometry
  FROM route;

CREATE VIEW geofeature AS
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

/* Redefine functions */

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

DROP FUNCTION lp_ts(INT);
CREATE FUNCTION lp_ts(tid INT) RETURNS :TSWTZ AS $$
DECLARE ans timestamp with time zone;
BEGIN
   SELECT MAX(timestamp) INTO ans
   FROM post p JOIN revision r ON (p.valid_starting_rid = r.id)
   WHERE p.thread_id = tid;

   RETURN ans;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION format_ts(timestamp without time zone);
CREATE FUNCTION format_ts(ts :TSWTZ) RETURNS TEXT AS $$
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

-- Record the run
INSERT INTO upgrade_event (script_name) VALUES ('084-timezone.sql');

--ROLLBACK;
COMMIT;

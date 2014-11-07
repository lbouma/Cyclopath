/* Update the route_step table to store more information if the step is for
   a transit step from routed_p2. Update route_waypoint to track if it is a
   bus stop or not.

   Update the existing route data to fit the new schema as best as possible.

   @once-per-instance
*/

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;

-- Update the route_waypoint table
ALTER TABLE route_waypoint ADD COLUMN bus_stop BOOLEAN NOT NULL DEFAULT FALSE;


-- Drop geometry views that must be updated to hold transit geometry
DROP VIEW geofeature;
DROP VIEW route_geo;

DROP VIEW gis_rt_blocks;
DROP VIEW gis_rt_endpoints;
DROP VIEW gis_rt_start;
DROP VIEW gis_rt_end;
DROP VIEW route_endpoints; -- can I just say 'Ugh!' - [ml]

DROP VIEW route_step_geo;


-- Epoch start/end times for steps in mm routes
ALTER TABLE route_step ADD COLUMN start_time INT;
ALTER TABLE route_step ADD COLUMN end_time INT;

-- defaults to Travel_Mode.bicycle (all steps in DB are bicycle anyway).
ALTER TABLE route_step ADD COLUMN travel_mode INT DEFAULT 1 
      REFERENCES travel_mode(id);

-- Remove not-null constraints on byway_id and byway_version
ALTER TABLE route_step ALTER COLUMN byway_id DROP NOT NULL;
ALTER TABLE route_step ALTER COLUMN byway_version DROP NOT NULL;

-- Add step_name column to hold byway name or transit name
ALTER TABLE route_step ADD COLUMN step_name TEXT;
--UPDATE route_step SET step_name = byway_segment.name FROM byway_segment WHERE byway_segment.id = route_step.byway_id AND byway_segment.version = route_step.byway_version;

-- Add transit geometry to hold geometry when route goes along a bus route
\set srid '(SELECT SRID(geometry) FROM byway_segment LIMIT 1)'
SELECT AddGeometryColumn('route_step', 'transit_geometry', :srid, 
                         'LINESTRING', 2);
CREATE INDEX route_step_gist ON route_step
       USING GIST ( transit_geometry GIST_GEOMETRY_OPS );

ALTER TABLE route_step ADD CONSTRAINT enforce_valid_byway CHECK 
      ((travel_mode = 1 
        AND byway_id IS NOT NULL AND byway_version IS NOT NULL) 
       OR (travel_mode <> 1 AND transit_geometry IS NOT NULL));

-- Update route table to reference the new travel mode enum, too
ALTER TABLE route ADD CONSTRAINT route_travel_mode_fk FOREIGN KEY (travel_mode)
       REFERENCES travel_mode (id);

-- Redefine the geometry views

CREATE VIEW route_step_geo AS
  SELECT route_id, route_version, step_number, byway_id, byway_version, 
         forward, start_time, end_time, travel_mode, 
         (CASE WHEN transit_geometry IS NOT NULL THEN transit_geometry
          ELSE (SELECT CASE WHEN forward THEN geometry
                       ELSE Reverse(geometry)
                       END
                FROM byway_segment 
                WHERE id = byway_id AND version = byway_version)
          END) AS geometry
  FROM route_step;

CREATE VIEW route_geo AS
  SELECT id, owner_name, name, host, source, use_defaults, 
         travel_mode, transit_pref,
         deleted, type_code, valid_starting_rid, valid_before_rid, version,
         z, created, permission, visibility, details, session_id, link_hash_id,
         (SELECT Collect(geometry) FROM route_step_geo
          WHERE route_id = id AND route_version = version) AS geometry
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

/*
 The following views are copied directly from 087-2-gis_views.sql
 because Postgres's replace view command is very limited (I changed its
 columns but not the columns used by the view, but it's enough to make it
 break).
*/

CREATE VIEW route_endpoints AS
SELECT
  r.id,
  r.host,
  ST_SnapToGrid(ST_StartPoint(fs.geometry), 0.01) AS start_xy,
  ST_SnapToGrid(ST_EndPoint(ls.geometry), 0.01) AS end_xy
FROM
  route r
  JOIN route_step_geo fs 
    ON (fs.route_id = r.id AND fs.route_version = r.version
        AND fs.step_number = 0)
  JOIN route_step_geo ls
    ON (ls.route_id = r.id AND fs.route_version = r.version
        AND ls.step_number = (SELECT MAX(step_number)
                              FROM route_step WHERE route_id = r.id));

CREATE VIEW gis_rt_start AS
SELECT
  COUNT(id) AS routes,
  COUNT(DISTINCT host) AS unique_hosts,
  start_xy::text AS geometry
FROM
  route_endpoints
GROUP BY
  start_xy
ORDER BY
  start_xy;

CREATE VIEW gis_rt_end AS
SELECT
  COUNT(id) AS routes,
  COUNT(DISTINCT host) AS unique_hosts,
  end_xy::text AS geometry
FROM
  route_endpoints
GROUP BY
  end_xy
ORDER BY
  end_xy;

CREATE VIEW gis_rt_endpoints AS
SELECT
  geometry::geometry,
  COALESCE(s.routes, 0) AS start_ct,
  COALESCE(s.unique_hosts, 0) AS start_uip,
  COALESCE(e.routes, 0) AS end_ct,
  COALESCE(e.unique_hosts, 0) AS end_uip
FROM
  gis_rt_start s FULL OUTER JOIN gis_rt_end e USING (geometry);


CREATE VIEW gis_rt_blocks AS
SELECT
  group_concat(DISTINCT b.name) AS name,
  b.id,
  group_concat(DISTINCT b.version::text) AS versions,
  COUNT(rs.route_id) AS route_ct,
  COUNT(DISTINCT r.host) AS route_uip,
  b.geometry
FROM 
  route_step rs JOIN
  route r ON (rs.route_id = r.id AND rs.route_version = r.version) JOIN
  byway_segment b ON (rs.byway_version = b.version AND rs.byway_id = b.id)
GROUP BY
  b.id,
  b.geometry; --group on geometry, not version!

COMMIT;


/* Add a route_waypoint table to the database and convert the from/to
   canonical addresses into waypoints for all past routes.
 
   @once-per-instance
*/

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;

CREATE TABLE route_waypoint (
   route_id INTEGER NOT NULL,
   route_version INTEGER NOT NULL,
   waypt_number INTEGER NOT NULL,

   name TEXT, -- name is null for map clicked points
   x FLOAT NOT NULL,
   y FLOAT NOT NULL,
   is_dest BOOLEAN NOT NULL DEFAULT TRUE,
   node_id INTEGER NOT NULL,
   PRIMARY KEY (route_id, route_version, waypt_number)
);

ALTER TABLE route_waypoint ADD CONSTRAINT route_waypt_route_id_fkey
        FOREIGN KEY (route_id, route_version) REFERENCES route(id, version);

-- Waypoint for the old from_canaddr
INSERT INTO route_waypoint (route_id, route_version, waypt_number, 
                            name, x, y, node_id)
   (SELECT rt.id AS route_id, 
           rt.version AS route_version, 
           0 AS waypt_number,
           rt.from_addr AS name,
           ST_X(ST_StartPoint(ST_GeometryN(geometry, 1))) AS x,
           ST_Y(ST_StartPoint(ST_geometryN(geometry, 1))) AS y,
           (SELECT CASE WHEN rs.forward THEN bs.start_node_id
                   ELSE bs.end_node_id
                   END
            FROM (route_step rs 
                  JOIN byway_segment bs ON (bs.id = rs.byway_id
                                            AND bs.version = rs.byway_version))
            WHERE rs.route_id = rt.id
                  AND rs.route_version = rt.version
            -- ORDER BY gets 1st route step only
            ORDER BY rs.step_number ASC LIMIT 1) AS node_id
    FROM route_geo rt);
        
-- Waypoint for the old to_canaddr
INSERT INTO route_waypoint (route_id, route_version, waypt_number, 
                            name, x, y, node_id)
   (SELECT rt.id AS route_id, 
           rt.version AS route_version, 
           1 AS waypt_number,
           rt.to_addr AS name,
           ST_X(ST_EndPoint(ST_GeometryN(geometry, 
                                         ST_NumGeometries(geometry)))) AS x,
           ST_Y(ST_EndPoint(ST_geometryN(geometry, 
                                         ST_NumGeometries(geometry)))) AS y,
           (SELECT CASE WHEN rs.forward THEN bs.end_node_id
                   ELSE bs.start_node_id
                   END
            FROM (route_step rs 
                  JOIN byway_segment bs ON (bs.id = rs.byway_id
                                            AND bs.version = rs.byway_version))
            WHERE rs.route_id = rt.id
                  AND rs.route_version = rt.version
            -- ORDER BY gets last route step only
            ORDER BY rs.step_number DESC LIMIT 1) AS node_id
    FROM route_geo rt);


/* Must drop geofeature and route_geo so that we can redefine the view
   to remove the from_addr and to_addr columns. */
DROP VIEW geofeature;
DROP VIEW route_geo;

-- FIXME: this will likely break if I rerun these scripts on a clean database
-- because of the gis rt tables, I might need to merge all of route sharing
-- into a single script so this view stuff can be redefined once

CREATE VIEW route_geo AS
  SELECT id, owner_name, name, host, source, use_defaults,
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

ALTER TABLE route DROP from_addr;
ALTER TABLE route DROP to_addr;

COMMIT;


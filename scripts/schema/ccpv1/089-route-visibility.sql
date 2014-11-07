/*
 This is the counterpart to script 087-visibility-enum.sql and upgrades
 the route and related tables to use visibility instead of the transient col
 @once-per-instance
*/

BEGIN TRANSACTION;
SET search_path TO @@@instance@@@, public;
SET CONSTRAINTS ALL DEFERRED;

/* Update route table to include the visibility column, defaults to noone */
ALTER TABLE route ADD visibility INT DEFAULT 3 NOT NULL
   REFERENCES visibility(code);

/* Update all routes with links to have a shared permission */
UPDATE route SET permission = 2 WHERE link_hash_id IS NOT NULL;

/* Remove unnecessary transient column and update dependent objects to 
    use visibility instead. */
ALTER TABLE route DROP CONSTRAINT route_enforce_permissions;
ALTER TABLE route ADD CONSTRAINT route_enforce_permissions
        CHECK (visibility = 3 OR owner_name IS NOT NULL OR permission = 1);

DROP VIEW geofeature;
DROP VIEW route_geo; -- do not need to redefine route_step_geo

CREATE VIEW route_geo AS
  SELECT id, owner_name, name, from_addr, to_addr, host, source, use_defaults,
         deleted, type_code, valid_starting_rid, valid_before_rid, version,
         z, created, permission, visibility, details, session_id, link_hash_id,
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

/* Finally remove transient */
ALTER TABLE route DROP COLUMN transient;

COMMIT;

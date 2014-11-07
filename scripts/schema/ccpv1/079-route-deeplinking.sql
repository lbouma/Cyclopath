/** This SQL script represents a collection of originally 5 scripts needed to
  * update the database model to handle routes with permissions, and to allow
  * deep-linking to saved routes.
  *
  * Additionally, it drops the route_digest table.
  * Each original script section will be prefixed with one of these names:
  *   1. route-permissions
  *   2. revision-permissions
  *   3. route-revision-geometry
  *   4. route-session-hash
  *   5. drop-route-digest
  *
  * Note that individual script's transactions have been removed for a single
  * transaction now, and that this script may take some time to run.
  */


BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

/*** BEGIN SCRIPT: route-permissions ***/

/* Remove all triggers related to last_modified, since we're removing that
   column.  last_modified is no longer needed now that we have created, and
   versioned routes. */
DROP TRIGGER route_u ON route;
DROP TRIGGER route_ilm ON route;
DROP TRIGGER route_step_u ON route_step;
DROP TRIGGER route_step_ilm ON route_step;
DROP TRIGGER route_tag_preference_u ON route_tag_preference;
DROP TRIGGER route_tag_preference_ilm ON route_tag_preference;
DROP TRIGGER route_priority_u ON route_priority;
DROP TRIGGER route_priority_ilm ON route_priority;

/* Remove all last_modified columns. */
ALTER TABLE route DROP COLUMN last_modified;
ALTER TABLE route_step DROP COLUMN last_modified;
ALTER TABLE route_tag_preference DROP COLUMN last_modified;
ALTER TABLE route_priority DROP COLUMN last_modified;

/* We still keep this trigger since it's meant to prevent updates */
ALTER TABLE route_feedback DISABLE TRIGGER route_feedback_u;

/* Create a permissions table that holds 3 permission states:
    1 - public (has no owner)
    2 - shared (requires owner)
    3 - private (requires owner) */
CREATE TABLE permissions (
   code INT PRIMARY KEY,
   text TEXT NOT NULL
);
INSERT INTO permissions VALUES (1, 'public');
INSERT INTO permissions VALUES (2, 'shared');
INSERT INTO permissions VALUES (3, 'private');

/* Initially all routes in the system are private, unlocked transient routes.
   Since 80+% of our routes are as above, these are the defaults. */
ALTER TABLE route ADD permission INT DEFAULT 3 NOT NULL 
   REFERENCES permissions(code);
ALTER TABLE route ADD transient BOOLEAN DEFAULT true NOT NULL;
ALTER TABLE route ADD details TEXT;

/* Ensure that non-transient private or locked routes have an owner.  */
ALTER TABLE route ADD CONSTRAINT route_enforce_permissions 
        CHECK (transient OR owner_name IS NOT NULL OR permission = 1);

/* Add version col to auxiliary route tables */
ALTER TABLE route_step ADD route_version INT;
UPDATE route_step SET route_version=1 WHERE route_version IS NULL;
ALTER TABLE route_step ALTER COLUMN route_version SET NOT NULL;

ALTER TABLE route_feedback ADD route_version INT;
UPDATE route_feedback SET route_version=1 WHERE route_version IS NULL;
ALTER TABLE route_feedback ALTER COLUMN route_Version SET NOT NULL;

/* Route tag preferences and priority are shared for all versions of 
   a route so they do not need a route_version column. */

/* Update primary keys for route and auxiliary tables to include version */
ALTER TABLE route DROP CONSTRAINT route_pkey CASCADE;
ALTER TABLE route ADD CONSTRAINT route_pkey PRIMARY KEY(id, version);

ALTER TABLE route_step DROP CONSTRAINT route_step_pkey;
ALTER TABLE route_step ADD CONSTRAINT route_step_pkey PRIMARY KEY(route_id, 
        route_version, step_number);
ALTER TABLE route_step ADD CONSTRAINT route_step_route_id_fkey FOREIGN KEY
        (route_id, route_version) REFERENCES route(id, version);

ALTER TABLE route_feedback ADD CONSTRAINT route_feedback_route_id_fkey 
        FOREIGN KEY (route_id, route_version) REFERENCES route(id, version); 

ALTER TABLE route_feedback ENABLE TRIGGER route_feedback_u;

/*** END SCRIPT: route-permissions ***/




/*** BEGIN SCRIPT: revision-permissions ***/


/*** END SCRIPT: revision-permissions ***/

/* By default, all revisions are public */
ALTER TABLE revision ADD permission INT DEFAULT 1 NOT NULL 
   REFERENCES permissions(code);

/* Add constraint that private revisions or shared revisions must have 
   an owner */
ALTER TABLE revision ADD CONSTRAINT enforce_permissions 
        CHECK (username IS NOT NULL OR permission = 1);

/*** BEGIN SCRIPT: route-revision-geometry ***/

CREATE VIEW route_step_geo AS
  SELECT route_id, route_version, step_number, byway_id, 
         byway_version, forward,
         (SELECT CASE WHEN forward THEN geometry
                 ELSE Reverse(geometry)
                 END
          FROM byway_segment 
          WHERE id = byway_id AND
                version = byway_version) AS geometry
  FROM route_step;

CREATE VIEW route_geo AS
  SELECT id, owner_name, name, from_addr, to_addr, host, source, use_defaults,
         deleted, type_code, valid_starting_rid, valid_before_rid, version,
         z, created, permission, transient, details,
         (SELECT Collect(geometry) FROM route_step_geo
          WHERE route_id = id AND route_version = version) as geometry
  FROM route;


DROP VIEW geofeature;

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
  FROM annotation_geo
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM region
UNION
  SELECT id, version, deleted, geometry, valid_starting_rid, valid_before_rid
  FROM route_geo;

/*** END SCRIPT: route-revision-geometry ***/




/*** BEGIN SCRIPT: route-session-hash ***/

ALTER TABLE route ADD COLUMN session_id TEXT;
ALTER TABLE route ADD COLUMN link_hash_id TEXT;

/*** END SCRIPT: route-session-hash ***/




/*** BEGIN SCRIPT: drop-route-digest ***/

/* Remove route_digest table, this should have been dumped prior to calling
   this script.  As a precaution a dump from 11-18-09 has already been stored
   in cp-scholarly/misc. */

DROP TABLE route_digest;

/*** END SCRIPT: drop-route-digest ***/

COMMIT;
--ROLLBACK;

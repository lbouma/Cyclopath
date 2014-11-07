/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Make sure geofeature includes route_geo and region; update geosummaries */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

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

/* Update affected revisions. This only needs to be done for regions since
 * there are no routes in the revision history (yet).
 * Revision 12079 = The first post and the first revision after release 42
 */
SELECT 
  valid_starting_rid AS id,
  revision_geosummary_update(valid_starting_rid)
FROM
  region 
WHERE
  valid_starting_rid >= 12079
GROUP BY
  valid_starting_rid;

--ROLLBACK;
COMMIT;

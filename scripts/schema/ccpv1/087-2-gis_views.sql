
/* Copyright (c) 2006-2012 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Views for use in db_export_shapefiles.sh
   @once-per-instance */

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;
SET search_path TO @@@instance@@@, public;

/* NOTE: It should work to define only one has_tag() function in the public
   schema and expect Postgres to use the search_path to determine at query
   execution time which instance schema's tag_bs and tag tables to use.
   However, ogr2ogr (<1.7.0) doesn't support custom search paths.  So, we
   instead reference the schema explicitly within the function and declare it
   once for each instance.
 */

CREATE FUNCTION has_tag(int, text) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT
      tb.id
    FROM
      @@@instance@@@.tag_bs tb JOIN @@@instance@@@.tag t ON (t.id = tb.tag_id)
    WHERE
      tb.byway_id = $1 AND
      t.label = $2 AND
      tb.valid_before_rid = RID_INF() AND
        NOT tb.deleted
   );
$$ LANGUAGE SQL STABLE;

/* 
 Current geofeatures; or:
   blocks
   points
   regions
   basemaps
*/

CREATE VIEW gis_regions AS
SELECT 
  r.id,
  r.version,
  r.name,
  r.comments,
  ARRAY_TO_STRING(
    ARRAY(
      SELECT label 
      FROM tag JOIN tag_region tr ON (tag.id=tag_id)
      WHERE
        region_id=r.id AND
        NOT tr.deleted AND
        tr.valid_before_rid=RID_INF()
      ORDER BY label),
    ',')
  AS tags,
  r.geometry,
  rev.id AS rev_id,
  rev.timestamp AS rev_time,
  rev.username AS rev_user
FROM
  region r LEFT OUTER JOIN
  revision rev ON (rev.id = r.valid_starting_rid)
WHERE
  NOT deleted AND
  valid_before_rid=RID_INF()
ORDER BY
  rev.id;

CREATE VIEW gis_points AS
SELECT 
  p.id,
  p.version,
  p.name,
  p.comments,
  ARRAY_TO_STRING(
    ARRAY(
      SELECT label 
      FROM tag JOIN tag_point tp ON (tag.id=tag_id)
      WHERE
        point_id=p.id AND
        NOT tp.deleted AND
        tp.valid_before_rid=RID_INF()
      ORDER BY label),
    ',')
  AS tags,
  p.geometry,
  rev.id AS rev_id,
  rev.timestamp AS rev_time,
  rev.username AS rev_user
FROM
  point p LEFT OUTER JOIN
  revision rev ON (rev.id = p.valid_starting_rid)
WHERE
  NOT p.deleted AND
  p.valid_before_rid=RID_INF()
ORDER BY
  rev.id;

CREATE VIEW gis_tag_points AS
SELECT 
  p.id,
  p.name,
  t.label AS tag,
  p.geometry
FROM
  point p LEFT OUTER JOIN
  (tag_point tp JOIN tag t ON (tp.tag_id = t.id))
   ON (tp.point_id = p.id AND NOT tp.deleted AND tp.valid_before_rid=RID_INF())
WHERE
  NOT p.deleted AND
  p.valid_before_rid=RID_INF()
ORDER BY
  tag;

CREATE VIEW gis_blocks AS
SELECT 
  b.id,
  b.version,
  b.name,
  value AS rt_default,
  COALESCE(rs.rating,-1) AS rt_usr_avg,
  COALESCE(rs.users,0) AS rt_usr_ct,
  t.text AS type,
  b.one_way,
  b.speed_limit AS speed_lim,
  b.outside_lane_width AS lane_w_out,
  b.shoulder_width AS shld_w,
  b.lane_count AS lane_ct,
  has_tag(b.id, 'unpaved') AS unpaved,
  has_tag(b.id, 'hill') AS hill,
  has_tag(b.id, 'bikelane') AS bikelane,
  has_tag(b.id, 'closed') AS closed,
  ARRAY_TO_STRING(
    ARRAY(
      SELECT label 
      FROM tag JOIN tag_bs tb ON (tag.id=tag_id)
      WHERE
        byway_id=b.id AND
        NOT tb.deleted AND
        tb.valid_before_rid=RID_INF()
      ORDER BY label),
    ',')
  AS tags,
  ARRAY_TO_STRING(
    ARRAY(
      SELECT comments
      FROM annotation a JOIN annot_bs ab ON (a.id=annot_id)
      WHERE
        byway_id=b.id AND
        NOT ab.deleted AND
        ab.valid_before_rid=RID_INF() AND
        NOT a.deleted AND
        a.valid_before_rid=RID_INF()),
    '
')
  AS comments,
  b.geometry,
  rev.id AS rev_id,
  rev.timestamp AS rev_time,
  rev.username AS rev_user
FROM
  byway_segment b JOIN
  byway_type t ON (code=type_code) JOIN
  byway_rating ON (byway_id=b.id AND username='_r_generic') LEFT OUTER JOIN
  (SELECT byway_id, COUNT(username) AS users, AVG(value) AS rating FROM byway_rating WHERE username != '_r_generic' AND value>=0 GROUP BY byway_id) AS rs ON (rs.byway_id=b.id) LEFT OUTER JOIN
  revision rev ON (rev.id = b.valid_starting_rid)
WHERE
  NOT deleted AND
  valid_before_rid=RID_INF()
ORDER BY
  rev.id;

CREATE VIEW gis_basemaps AS
SELECT 
  bp.id,
  bp.name,
  t.text AS type,
  bp.geometry
FROM
  basemap_polygon bp JOIN
  basemap_polygon_type t ON (code=type_code)
WHERE
  NOT deleted AND
  valid_before_rid=RID_INF();

/* 
  Anonymized routes:
    gis_rt_endpoints
    gis_rt_blocks

 NOTE: compute counts separately for start and endpoints and then merge with a
 full outer join.  Convert to text and back so the JOIN works, since geometry
 is not a merge-joinable field.

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

COPY geometry_columns(f_table_catalog, f_table_schema, f_table_name,
		      f_geometry_column, coord_dimension, srid, "type")
FROM STDIN;
	@@@instance@@@	gis_basemaps	geometry	2	26915	POLYGON
	@@@instance@@@	gis_blocks	geometry	2	26915	LINESTRING
	@@@instance@@@	gis_points	geometry	2	26915	POINT
	@@@instance@@@	gis_regions	geometry	2	26915	POLYGON
	@@@instance@@@	gis_tag_points	geometry	2	26915	POINT
	@@@instance@@@	route_endpoints	geometry	2	26915	POINT
	@@@instance@@@	gis_rt_start	geometry	2	26915	POINT
	@@@instance@@@	gis_rt_end	geometry	2	26915	POINT
	@@@instance@@@	gis_rt_blocks	geometry	2	26915	LINESTRING
	@@@instance@@@	gis_rt_endpoints	geometry	2	26915	POINT
\.

COMMIT;

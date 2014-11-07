/* Copyright (c) 2006-2013 Regents of the University of Minnesota
   For licensing terms, see the file LICENSE. */

/* Repair (update to CcpV2) route-ish views we use to create export Shapefiles
   of route OD pairs. */

/* Run this script once against each instance of Cyclopath

      @once-per-instance
      
   */

/*
FIXME: For now, use ogr2ogr, and add to cron job?
       For later, add route-type exports to import/export.
         I.e., Export waypoints (drop gis_tag_points and just add tags and 
                                 attrs as fields, like w/ byway)
               Export regions, terrain
               Export routes: endpoint stats
                              line segment stats
                              OD pairs (very sensitive data?)

(Make) BUG nnnn: Update GIS route OD pair exports to CcpV2.

*/

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

SET search_path TO @@@instance@@@, public;

/* ==================================================================== */
/* Step (1)                                                             */
/* ==================================================================== */

DROP VIEW IF EXISTS route_endpoints CASCADE; -- can I just say 'Ugh!' - [ml]
DROP VIEW IF EXISTS route_step_geo CASCADE;

/* === */

CREATE VIEW route_step_geo AS
   SELECT
      route_id,
      route_stack_id,
      route_version,
      step_number,
      /* Skipping: step_name */
      byway_id,
      byway_stack_id,
      byway_version,
      forward,
      start_time,
      end_time,
      travel_mode,
      (CASE
         WHEN transit_geometry IS NOT NULL THEN
            transit_geometry
         ELSE (
            SELECT
               CASE
                  WHEN rs.forward THEN
                     gf.geometry
                  ELSE
                     Reverse(gf.geometry)
                  END
            FROM
               geofeature AS gf 
            WHERE
               gf.system_id = rs.byway_id
            )
         END) AS geometry
  FROM route_step AS rs;

/* === */

/* EXPLAIN: Why ST_SnapToGrid?
 *          Is this so "close by" points are coalesced?
 *          We could almost switch to a meter at this point... 
 *          NOTE: We group by geometry later, so snapping helps there, too. */

/* FIXME: Don't need route_endpoints, since beg_xy/fin_xy now cached in route.
*/

/* FIXME: Cache route geometry, too... since we're always calculating it,
 *        right? */

CREATE VIEW route_endpoints AS
   SELECT
      DISTINCT ON (rt.stack_id)
      rt.stack_id,
      rt.host,
      /* BUG nnnn: Route to the middle (or non-endpoint) of a line segment. */
      ST_SnapToGrid(ST_StartPoint(beg_rs.geometry), 0.01) AS beg_xy,
      ST_SnapToGrid(  ST_EndPoint(fin_rs.geometry), 0.01) AS fin_xy
   FROM
      route AS rt
   JOIN
      geofeature AS gf
         USING (system_id)
   JOIN
      item_versioned AS iv
         USING (system_id)
   JOIN
      route_step_geo AS beg_rs
         /* BUG nnnn: Route step_number not always 0! */
         ON ((beg_rs.route_id = rt.system_id)
             AND (beg_rs.step_number = rt.rsn_min))
   JOIN
      route_step_geo AS fin_rs
         ON ((fin_rs.route_id = rt.system_id)
             AND (fin_rs.step_number = rt.rsn_max))
   WHERE
      iv.deleted IS FALSE
   GROUP BY
      rt.stack_id,
      rt.version,
      rt.host,
      beg_rs.geometry,
      fin_rs.geometry
   ORDER BY
      rt.stack_id ASC,
      rt.version DESC;

/* ==================================================================== */
/* Step (2)                                                             */
/* ==================================================================== */

DROP VIEW IF EXISTS gis_rt_beg;
CREATE VIEW gis_rt_beg AS
   SELECT
      COUNT(stack_id) AS cnt_routes,
      COUNT(DISTINCT host) AS cnt_ipadys,
      beg_xy::text AS geometry
   FROM
     route_endpoints
   GROUP BY
     beg_xy
   ORDER BY
     beg_xy;

/* === */

DROP VIEW IF EXISTS gis_rt_fin;
CREATE VIEW gis_rt_fin AS
   SELECT
      COUNT(stack_id) AS cnt_routes,
      COUNT(DISTINCT host) AS cnt_ipadys,
      fin_xy::text AS geometry
   FROM
      route_endpoints
   GROUP BY
      fin_xy
   ORDER BY
      fin_xy;

/* === */

DROP VIEW IF EXISTS gis_rt_endpoints;
CREATE VIEW gis_rt_endpoints AS
   SELECT
     geometry::geometry,
     COALESCE(beg_re.cnt_routes, 0) AS beg_routes,
     COALESCE(beg_re.cnt_ipadys, 0) AS beg_ipadys,
     COALESCE(fin_re.cnt_routes, 0) AS fin_routes,
     COALESCE(fin_re.cnt_ipadys, 0) AS fin_ipadys
   FROM
      gis_rt_beg AS beg_re
   FULL OUTER JOIN
      gis_rt_fin AS fin_re
         USING (geometry);

/* === */

/*
FIXME: Add to export. Find all routes within a region, and then
for each route, calculate this (it is too expensive to run on whole map):
*/
/* NOTE: This view chokes [lb]'s laptop, and I've never waited for the end.
         But it runs okay on huffy, in just a few minutes... */
DROP VIEW IF EXISTS gis_rt_line_segs;
CREATE VIEW gis_rt_line_segs AS
   SELECT
      group_concat(DISTINCT bw_iv.name) AS name,
      bw_gf.stack_id,
      -- FIXME: Should this just be a count of the different versions?
      --        Or should we ignore it? I.e., the user changed the route...
      group_concat(DISTINCT bw_gf.version::TEXT) AS versions,
      COUNT(rs.route_id) AS cnt_routes,
      COUNT(DISTINCT rt.host) AS cnt_ipadys,
      bw_gf.geometry
   FROM 
      route_step AS rs
   JOIN
      route AS rt
         ON (rt.system_id = rs.route_id)
   JOIN
      geofeature AS bw_gf
         ON (bw_gf.system_id = rs.byway_id)
   JOIN
      item_versioned AS bw_iv
         ON (bw_iv.system_id = rs.byway_id)
   GROUP BY
      bw_gf.stack_id,
      bw_gf.geometry /* NOTE: group on geometry, not version. */
   ;

/* === */

/* NOTE: Originally, this code didn't check version or deleted, but I [lb]
         think we should only get the latest version of a route and that we
         should ignore deleted. Per the latter, in CcpV1, routes are only
         marked deleted when they're being clone with different permissions,
         so there's one non-deleted route for each deleted route; in CcpV2,
         routes can be removed from user or public route libraries, but it
         won't be marked deleted (it'll just be inaccessible via permissions);
         in either case, we can safely ignore deleted routes and use the latest
         version of a route without worrying about not capturing all the data
         (and if we didn't ignore deleted routes, we'd end up with some routes
         appearing to have been requested more often than they really were). */
/* MAYBE: This data does not capture the number of times a route has been
          _viewed_. */
/* MAYBE: [lb] is uncertain is the resulting geometry should be a geometry
          collection or a multi geometry. In either case, the data appears the
          same in ArcGIS, so I'm assuming it doesn't matter.... */
/* FIXME: Implement this in import/export, and calculate one route at a time so
          we can show progress and be cancelled easily. I.e., get a list of
          route stack IDs first (possible restricted by region, etc.) and then
          calculate the collected geometry for routes one at a time, or in
          small groups, so we don't have to run this whole SQL operation (which
          is costly; it pegs my laptop though it only takes a few minutes on
          huffy). */
/* MAYBE: This calculation omits intermediate route stops. */
/* MAYBE: This calculation only gets the latest route version. */

DROP VIEW IF EXISTS gis_rt_collected;
CREATE VIEW gis_rt_collected AS
   SELECT
      --group_concat(DISTINCT rt_geo.stack_id::TEXT) AS rt_sids,
      --group_concat(DISTINCT rt_geo.name) AS rt_names,
      /* MAYBE: We're coalescing some data, but how can we coalesce 'created'?
       */
      COUNT(rt_geo.stack_id) AS cnt_routes,
      COUNT(DISTINCT rt_geo.host) AS cnt_ipadys,
      geometry
   FROM (
      SELECT
         DISTINCT ON (rt.stack_id)
         rt.stack_id,
         iv.name,
         rt.host,
         ST_Collect(gf.geometry) AS geometry
         -- No difference?: ST_Multi(ST_Collect(gf.geometry)) AS geometry
      FROM route AS rt
      JOIN item_versioned AS iv
         ON (rt.system_id = iv.system_id)
      JOIN route_step AS rs
         ON (rs.route_id = rt.system_id)
      JOIN geofeature AS gf
         ON (rs.byway_id = gf.system_id)
      WHERE
         iv.deleted IS FALSE
      GROUP BY
         rt.stack_id,
         rt.version,
         iv.name,
         rt.host
      ORDER BY
         rt.stack_id ASC,
         rt.version DESC
      ) AS rt_geo
   GROUP BY
      rt_geo.geometry
   ;

/* ==================================================================== */
/* Step (n) -- All done!                                                */
/* ==================================================================== */

\qecho 
\qecho Done!
\qecho 

COMMIT;


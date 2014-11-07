The Statewide data needs to be transformed:
1. Long line segments need to be split (segmentization
   of overlapping roads).
2. Underpass/Overpass must be verified and/or z-levels edited.
3. Dangles must be verified and/or intersections made.

/* Understand how to find intersections using PostGIS. */

-- The && operator uses bboxes, so, e.g., this returns a false positive:

SELECT tbl1.column1, tbl2.column1, tbl1.column2 && tbl2.column2 AS overlaps
FROM ( VALUES
(1, 'LINESTRING(0 10, 10 0)'::geometry),
(2, 'LINESTRING(6 0,  6 10)'::geometry)) AS tbl1,
( VALUES
(3, 'LINESTRING(6 6, 10 10)'::geometry)) AS tbl2;

-- The ST_Intersection command is more precise:

SELECT tbl1.column1, tbl2.column1, ST_AsText(ST_Intersection(tbl1.column2, tbl2.column2)) AS overlaps
FROM ( VALUES
(1, 'LINESTRING(0 10, 10 0)'::geometry),
(2, 'LINESTRING(6 0,  6 10)'::geometry)) AS tbl1,
( VALUES
(3, 'LINESTRING(6 6, 10 10)'::geometry)) AS tbl2;

/* Look for intersections in the CcpV3 database. */

SELECT
  COUNT(*)
  FROM (
    SELECT
      gf1.stack_id,
      gf2.stack_id,
      ST_AsText(ST_Intersection(gf1.geometry, gf2.geometry)) AS overlaps
        FROM geofeature AS gf1
        JOIN item_versioned AS iv1
          ON (iv1.system_id = gf1.system_id)
        JOIN geofeature AS gf2
          ON (gf1.stack_id < gf2.stack_id)
        JOIN item_versioned AS iv2
          ON (iv2.system_id = gf2.system_id)
        WHERE
               iv1.valid_until_rid = 2000000000
           AND iv2.valid_until_rid = 2000000000
           AND iv1.branch_id = 2500677
           AND iv2.branch_id = 2500677
           AND ST_GeometryType(gf1.geometry) = 'ST_LineString'
           AND ST_GeometryType(gf2.geometry) = 'ST_LineString'
           AND st_isvalid(gf1.geometry)
           AND st_isvalid(gf2.geometry)
           AND st_intersects(gf1.geometry, gf2.geometry)
        GROUP BY
          gf1.stack_id,
          gf2.stack_id,
          ST_Intersection(gf1.geometry, gf2.geometry)
  ) AS foo;



/* */

SELECT
  COUNT(*)
  FROM (
    SELECT
      gf1.stack_id
      , gf2.stack_id
      --, ST_AsText(ST_Intersection(gf1.geometry, gf2.geometry)) AS overlaps
        FROM geofeature AS gf1
        JOIN item_versioned AS iv1
          ON (iv1.system_id = gf1.system_id)
        JOIN geofeature AS gf2
          ON (gf1.stack_id < gf2.stack_id)
        JOIN item_versioned AS iv2
          ON (iv2.system_id = gf2.system_id)
        WHERE
               iv1.valid_until_rid = 2000000000
           AND iv2.valid_until_rid = 2000000000
           AND iv1.branch_id = 2500677
           AND iv2.branch_id = 2500677
           AND ST_GeometryType(gf1.geometry) = 'ST_LineString'
           AND ST_GeometryType(gf2.geometry) = 'ST_LineString'
           AND st_isvalid(gf1.geometry)
           AND st_isvalid(gf2.geometry)
           AND ST_Crosses(gf1.geometry, gf2.geometry)
        GROUP BY
          gf1.stack_id
          , gf2.stack_id
          --, ST_Intersection(gf1.geometry, gf2.geometry)
  ) AS foo;

HERE

/* Load the Statewide data. */

Load the spatial database from MnDOT, AndyEGIS_Base.mdb, into ArcMAP.

Export the layer to a Shapefile.

Roadway_Char data: 229,873 line segments.

Create a new database to tinker around in.

  createdb -U postgres --owner=cycling -e --template template0 statewide_test

  createlang -U cycling plpgsql statewide_test

  . /ccp/opt/postgis/Version.config

  # lwpostgis.sql is pre-1.4; 1.4+ uses postgis.sql

  # This doesn't work:
  #   PGUSER=postgres sh /ccp/opt/postgis/utils/postgis_restore.pl \
  #     /ccp/opt/postgis/postgis/postgis.sql \
  #     statewide_test \
  #     /ccp/var/shapefiles/Export_Roadway_Char/roads.sql \
  #     -E UTF8 -T template0

  psql -U postgres -d statewide_test -f /ccp/opt/postgis/postgis/postgis.sql
  psql -U postgres -d statewide_test -f /ccp/opt/postgis/spatial_ref_sys.sql
  psql -U postgres -d statewide_test -f /ccp/opt/postgis/doc/postgis_comments.sql

There's no template_postgis, but we could probably use another database as a template?

  #   dropdb -U postgres statewide_test
  #   createdb -U postgres -e --template template_postgis statewide_test

cd /ccp/var/shapefiles/Export_Roadway_Char

/ccp/opt/postgis/loader/shp2pgsql --help

/ccp/opt/postgis/loader/shp2pgsql \
  -c -D -s 26915 -g geometry -i -I \
  Export_Roadway_Char.shp public.roads > roads.sql

# psql -U postgres -d statewide_test -f roads.sql | tee help 2>&1 &
psql -U postgres statewide_test < roads.sql

psql -U postgres statewide_test

GRANT ALL ON DATABASE statewide_test TO cycling;
GRANT ALL PRIVILEGES ON TABLE roads TO cycling;
GRANT ALL PRIVILEGES ON TABLE geography_columns TO cycling;
GRANT ALL PRIVILEGES ON TABLE geometry_columns TO cycling;
GRANT ALL PRIVILEGES ON TABLE roads_gid_seq TO cycling;
GRANT ALL PRIVILEGES ON TABLE spatial_ref_sys TO cycling;

^D

psql -U cycling statewide_test

select geometry from roads limit 3;

/* Look for intersections in the Statewide database. */

--SELECT
--  COUNT(*)
--  FROM (
    SELECT
      --rd1.gid,
      --rd2.gid,
      rd1.objectid,
      rd2.objectid,
      ST_AsText(ST_Intersection(rd1.geometry, rd2.geometry)) AS overlaps
        FROM roads AS rd1
        JOIN roads AS rd2
          ON (rd1.gid < rd2.gid)
        WHERE
           --    iv1.valid_until_rid = 2000000000
           --AND iv2.valid_until_rid = 2000000000
           --AND iv1.branch_id = 2500677
           --AND iv2.branch_id = 2500677
           --AND ST_GeometryType(rd1.geometry) = 'ST_LineString'
           --AND ST_GeometryType(rd2.geometry) = 'ST_LineString'
           --AND
               st_isvalid(rd1.geometry)
           AND st_isvalid(rd2.geometry)
           AND st_intersects(rd1.geometry, rd2.geometry)
        GROUP BY
          --rd1.gid,
          --rd2.gid,
          rd1.objectid,
          rd2.objectid,
          ST_Intersection(rd1.geometry, rd2.geometry)
;
--  ) AS foo;

 count  
--------
 235322

Time: 103034.685 ms (1m40s)

/* Fix MULTILINESTRINGs */

psql -U postgres statewide_test

select addgeometrycolumn('roads', 'geometry_flat', 26915, 'LINESTRING', 2);
update roads set geometry_flat = Force_2d(GeometryN(geometry, 1));
create index roads_geometry_flat_gist on roads using gist (geometry_flat);

    SELECT
      --rd1.gid,
      --rd2.gid,
      rd1.objectid,
      rd2.objectid,
      ST_AsText(ST_Intersection(rd1.geometry_flat, rd2.geometry_flat)) AS overlaps
        FROM roads AS rd1
        JOIN roads AS rd2
          ON (rd1.gid < rd2.gid)
        WHERE
           --    iv1.valid_until_rid = 2000000000
           --AND iv2.valid_until_rid = 2000000000
           --AND iv1.branch_id = 2500677
           --AND iv2.branch_id = 2500677
           --AND ST_GeometryType(rd1.geometry_flat) = 'ST_LineString'
           --AND ST_GeometryType(rd2.geometry_flat) = 'ST_LineString'
           --AND
               st_isvalid(rd1.geometry_flat)
           AND st_isvalid(rd2.geometry_flat)
           AND st_intersects(rd1.geometry_flat, rd2.geometry_flat)
        GROUP BY
          --rd1.gid,
          --rd2.gid,
          rd1.objectid,
          rd2.objectid,
          ST_Intersection(rd1.geometry_flat, rd2.geometry_flat)
;

-- This returns 0 rows?:
SELECT ST_AsText(ST_MakeLine(sp, ep))
FROM
-- extract the endpoints for every 2-point line segment for each linestring
(SELECT
  ST_PointN(geom, generate_series(1, ST_NPoints(geom)-1)) as sp,
  ST_PointN(geom, generate_series(2, ST_NPoints(geom)  )) as ep
FROM
   -- extract the individual linestrings
  (SELECT ST_ASText((ST_Dump(geometry)).geom)
   FROM roads
WHERE objectid = 229825
   ) AS linestrings
) AS segments;

-- This works: it returns two rows of the two LINESTRINGs in the MULTILINESTRING
select * from (select (st_dump(geometry)).geom, roads.* from roads where objectid = 229825) as foo;

SELECT ST_GeometryType(geometry) FROM roads WHERE objectid = 1;       -- ST_MultiLineString
SELECT ST_GeometryType(geometry) FROM roads WHERE objectid = 229825;  -- ST_MultiLineString
SELECT ST_NumGeometries(geometry) FROM roads WHERE objectid = 1;      -- 1
SELECT ST_NumGeometries(geometry) FROM roads WHERE objectid = 229825; -- 2

SELECT SUM(count*ngeoms) FROM (
SELECT ngeoms, COUNT(*) FROM (
  SELECT ST_NumGeometries(geometry) AS ngeoms
  FROM roads
  --WHERE objectid IN (1, 229825)
  ) AS foo
  GROUP BY ngeoms
  ORDER BY ngeoms ASC
) AS bar
  ;

 ngeoms | count  
--------+--------
      1 | 203909
      2 |  21565
      3 |   3356
      4 |    385
      5 |    106
      6 |     47
      7 |      9
      8 |      5
      9 |      1
        |    490
(10 rows)

  sum   
--------
 259571

55662 multis w/ > 1 geoms

FIXME: List all columns and SELECT INTO a new table.
We'll keep all columns and use a new table, with its own
geometry column, and we'll not use geometry_flat.

-- THIS WORKS PERFECTLY FINE:
SELECT
  gid, objectid, tis_id, roadway_na,
  ST_ASText((ST_Dump(geometry)).geom)
FROM roads
  WHERE objectid = 229825
;
FIXME: The new table will have to have its own unique ID.
       Which is fine.



FIXME: Some Mulits have overlapping roads. Maybe the new
       proposed intersection tool will fix this?

Or, for this third FIXME, see the following SQL...

/* Look for intersections in the Statewide database. */

SELECT
  COUNT(*)
  FROM (
    SELECT
      --rd1.gid,
      --rd2.gid,
      rd1.objectid
      , rd2.objectid
      --, ST_AsText(ST_Intersection(rd1.geometry, rd2.geometry)) AS overlaps
        FROM roads AS rd1
        JOIN roads AS rd2
          ON (rd1.gid < rd2.gid)
        WHERE
           --    iv1.valid_until_rid = 2000000000
           --AND iv2.valid_until_rid = 2000000000
           --AND iv1.branch_id = 2500677
           --AND iv2.branch_id = 2500677
           --AND ST_GeometryType(rd1.geometry) = 'ST_LineString'
           --AND ST_GeometryType(rd2.geometry) = 'ST_LineString'
           --AND
               st_isvalid(rd1.geometry)
           AND st_isvalid(rd2.geometry)
           --AND st_intersects(rd1.geometry, rd2.geometry)
           AND ST_CROSSES(rd1.geometry, rd2.geometry)
        GROUP BY
          --rd1.gid,
          --rd2.gid,
          rd1.objectid
          , rd2.objectid
          --, ST_Intersection(rd1.geometry, rd2.geometry)
) AS foo;

Time: 110754.549 ms

68033 rows



/* */

-- *** Two line segments, one a complete subsegment of the other

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Within(a,b) AS a_within_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 0, 1 1)') AS a,
      ST_GeomFromText('LINESTRING(0 0, 1 1, 5 5)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_within_b | a_touches_b 
-------------+-------------+----------------+--------------+------------+-------------
 f           | f           | t              | f            | t          | f

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Within(a,b) AS a_within_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 0, 1 1, 5 5)') AS a,
      ST_GeomFromText('LINESTRING(0 0, 1 1)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_within_b | a_touches_b 
-------------+-------------+----------------+--------------+------------+-------------
 f           | f           | t              | t            | f          | f

-- *** an X (two intersecting lines)

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 0, 1 1, 5 5)') AS a,
      ST_GeomFromText('LINESTRING(0 5, 4 1, 5 0)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 f           | t           | t              | f            | f

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 5, 4 1, 5 0)') AS a,
      ST_GeomFromText('LINESTRING(0 0, 1 1, 5 5)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 f           | t           | t              | f            | f

-- *** Lines with a common subsegment

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 0, 1 1, 5 5)') AS a,
      ST_GeomFromText('LINESTRING(0 5, 2 2, 1 1, 5 0)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 t           | f           | t              | f            | f

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 5, 2 2, 1 1, 5 0)') AS a,
      ST_GeomFromText('LINESTRING(0 0, 1 1, 5 5)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 t           | f           | t              | f            | f

-- *** Two line segments, the end of one and beginning of another is shared

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 0, 3 3)') AS a,
      ST_GeomFromText('LINESTRING(2 2, 5 5)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 t           | f           | t              | f            | f

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(2 2, 5 5)') AS a,
      ST_GeomFromText('LINESTRING(0 0, 3 3)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 t           | f           | t              | f            | f

-- *** Two line segments, one's end is in the middle of the other line

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(0 0, 5 5)') AS a,
      ST_GeomFromText('LINESTRING(2 2, 5 0)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 f           | f           | t              | f            | t

SELECT
     ST_Overlaps(a,b) AS a_overlap_b
   , ST_Crosses(a,b) AS a_crosses_b
   , ST_Intersects(a, b) AS a_intersects_b
   , ST_Contains(a,b) AS a_contains_b
   , ST_Touches(a,b) AS a_touches_b
FROM (
   SELECT
      ST_GeomFromText('LINESTRING(2 2, 5 0)') AS a,
      ST_GeomFromText('LINESTRING(0 0, 5 5)') AS b
   ) AS foo
;

 a_overlap_b | a_crosses_b | a_intersects_b | a_contains_b | a_touches_b 
-------------+-------------+----------------+--------------+-------------
 f           | f           | t              | f            | t

/* */


SELECT COUNT(*) FROM (
SELECT      
    a.objectid
    , b.objectid
FROM
    roads as a,
    roads as b
WHERE
    a.gid < b.gid
    AND ST_Intersects(a.geometry, b.geometry)
GROUP BY
    a.objectid
    , b.objectid
    --, ST_Intersection(a.geometry, b.geometry)
ORDER BY
    a.objectid
    , b.objectid
) AS foo
;

(235322 rows)

-- Find the number of unique intersections
SELECT
   COUNT(*)
   , ST_AsText(intersect_pt)
FROM (
SELECT      
    a.objectid
    , b.objectid
    , ST_Intersection(a.geometry, b.geometry) AS intersect_pt
FROM
    roads as a,
    roads as b
WHERE
    a.gid < b.gid
    AND ST_Intersects(a.geometry, b.geometry)
GROUP BY
    a.objectid
    , b.objectid
    , ST_Intersection(a.geometry, b.geometry)
ORDER BY
    a.objectid
    , b.objectid
) AS foo
GROUP BY
   intersect_pt
ORDER BY
   intersect_pt
;

(197170 rows)

SELECT DISTINCT(route_syst) FROM roads ORDER BY route_syst; -- 01 to 23
SELECT DISTINCT(route_sy_1) FROM roads ORDER BY route_sy_1;
SELECT DISTINCT(route_sy_2) FROM roads ORDER BY route_sy_2;
SELECT DISTINCT(route_sy_3) FROM roads ORDER BY route_sy_3;

statewide_test=# SELECT DISTINCT(route_sy_1) FROM roads ORDER BY route_sy_1;
            route_sy_1            
----------------------------------
 County Road
 County State-Aid Highway
 Indian Reservation Road
 Interstate Trunk Highway
 Military Road
 Minnesota Trunk Highway
 Municipal State-Aid Street
 Municipal Street
 National Forest Development Road
 National Monument Road
 National Park Road
 National Wildlife Refuge Road
 Private Jurisdiction Road
 State Forest Road
 State Game Reserve Road
 State Park Road
 Township Road
 Unorganized Township Road
 U.S. Trunk Highway
(19 rows)

SELECT DISTINCT(control_of) FROM roads ORDER BY control_of;
SELECT DISTINCT(control__1) FROM roads ORDER BY control__1;
        control__1         
---------------------------
 No control of access      -- 1
 Partial control of access -- 2
 Full control of access    -- 3
(3 rows)


FIXME: SQL to find dangles -- quantify the #





NOTE: Two previous row counts are for multis, so these are low-ball estimates.


del this:
SELECT SUM(count*ngeoms) FROM (
SELECT ngeoms, COUNT(*) FROM (
  SELECT ST_NumGeometries(geometry) AS ngeoms
  FROM roads
  --WHERE objectid IN (1, 229825)
  ) AS foo
  GROUP BY ngeoms
  ORDER BY ngeoms ASC
) AS bar
  ;









/* */


FIXME: We need counties, parks, etc., as regions...

b. Import each county:

   shp2pgsql -a -D -s 26915 -g geo_multi COUNTY.shp mndot_basemap > COUNTY.sql
   \i COUNTY.sql




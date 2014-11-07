/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

\qecho 
\qecho This script is deprecated.
\qecho 

/* This script creates a view joining TIS data to the MNDOT basemap roads.

   Prerequisites:

     1. Table tis_data, a SQLized version of the TIS text data.

        a. Delete the STDESCR column in the text data.
        b. Create a nice table. Don't forget speed limit.
        c. Import using COPY FROM foo CSV HEADER.
        d. Create indexes and VACUUM ANALYZE.

     2. Table mndot_basemap, a SQLized version of the MNDOT BaseMap
        shapefiles.

        a. Create table (must use anoka.shp, others have missing columns):

           shp2pgsql -p -I -s 26915 -g geo_multi anoka.shp mndot_basemap > mndot_basemap.sql
           \i mndot_basemap.sql  

        b. Import each county:

           shp2pgsql -a -D -s 26915 -g geo_multi COUNTY.shp mndot_basemap > COUNTY.sql
           \i COUNTY.sql

        c. Create mileage columns:

           NOTE: The below assumes that only the first linestring in the
           multilinestring geometry is important. This is safe because nearly
           all of the multlinestring geometries contain only one linestring.

           alter table mndot_basemap add column mile_start double precision;
           alter table mndot_basemap add column mile_end double precision;
           alter table mndot_basemap add column mile_forward boolean;
           update mndot_basemap set mile_start = min2(M(StartPoint(geo_multi)), M(EndPoint(geo_multi)));
           update mndot_basemap set mile_end = max2(M(StartPoint(geo_multi)), M(EndPoint(geo_multi)));
           update mndot_basemap set mile_forward = (M(EndPoint(geo_multi)) >= M(StartPoint(geo_multi)));

        d. Convert 3-d multilinestrings (with M) to 2-d linestrings (no M):

           select addgeometrycolumn('mndot_basemap', 'geometry', 26915, 'LINESTRING', 2);
# 2013.09.13: [lb] notes the Force_2d only extracts the first LINESTRING from
                   a MULTILINESTRING, so this fcn. loses data.
           update mndot_basemap set geometry = Force_2d(GeometryN(geo_multi,1));
           create index mndot_basemap_geometry_gist on mndot_basemap using gist (geometry);

        e. Create some handy indexes:

           create index mndot_basemap_tis_code on mndot_basemap (tis_code);
           create index mndot_basemap_mile_start on mndot_basemap (mile_start);
           create index mndot_basemap_mile_end on mndot_basemap (mile_end);
           vacuum analzye mndot_basemap;

        f. Guess speed limits using guess-speed-limits.sql.

*/

BEGIN TRANSACTION;
SET CONSTRAINTS ALL DEFERRED;

CREATE OR REPLACE VIEW tis_basemap_joined AS
  SELECT
    *, 
    min2(t.endmpt, m.mile_end) - max2(t.stmpt, m.mile_start) AS miles_overlap
  FROM
    mndot_basemap m LEFT OUTER JOIN tisdata t ON (t.tiscode = m.tis_code
                                                  AND m.mile_start < t.endmpt
                                                  AND m.mile_end > t.stmpt);

--COMMIT;
\qecho 
\qecho This script is deprecated.
\qecho 
/* */
ROLLBACK;


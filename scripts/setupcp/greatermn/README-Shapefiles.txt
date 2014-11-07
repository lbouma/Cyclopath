
The /ccp/var/shapefiles/greatermn source
includes two subdirs of Shapefiles:

1. mndot_tda        | MN road network base data
2. muni_city_names  | MN city names to populate lookup table

This data was imported into Cyclopath in Fall, 2013.

See scripts:

  /ccp/dev/cp/scripts/setupcp/greatermn/statewide_mndot_import.py
  /ccp/dev/cp/scripts/setupcp/greatermn/statewide_munis_lookup.py

================
== mndot_tda/ ==

These files were custom produced by Jesse Pearson
for Landon Bouma in October, 2013, for Statewide
Cyclopath.

  STATEWIDE_COUNTIES.shp
  Road_characteristics.shp
  TRAFFIC_VOLUME_AADT.shp
  TRAFFIC_VOLUME_HCADT.shp

---------------

The STATEWIDE_COUNTIES Shapefile is like the Shapefiles
for County Basemap data that you can find online at:

 http://www.dot.state.mn.us/maps/gdma/gis-data.html

 For metadata:

  http://www.dot.state.mn.us/maps/gdma/data/metadata/road_metadata.html

But online you have to download one Shapefile per county.
Jesse combined all of these into one Shapefile.

The County Basemap data is our starting point: all of the
line segments are already segmentized at intersections,
unlike the other three Shapefiles.

---------------

The Road_characteristics Shapefile has interesing bicycle-
related data, like shoulder width and shoulder pavement
type.

This Shapefile contains Multi-lines and is not segmentized,
so it's a little extra work to match this file to the county
data. But it can be done. Especially since the geometry
exactly matches the county data.

---------------

The TRAFFIC_VOLUME_AADT and TRAFFIC_VOLUME_HCADT Shapefiles
contain, obviously, AADT data. The geometry is like that of
the Road_characteristics Shapefile. And HCAADT means
"Heavy commercial annual average daily traffic."

======================
== muni_city_names/ ==

Download from:

 http://www.dot.state.mn.us/maps/gdma/data/datafiles/statewide/muni.zip

See also

 http://www.dot.state.mn.us/maps/gdma/data/metadata/muni.htm

and the main page

 http://www.dot.state.mn.us/maps/gdma/gis-data.html

The source data was created by MnDOT in 2011.

======================
== county/          ==

Download from:

 http://www.dot.state.mn.us/maps/gdma/data/datafiles/statewide/county.zip

See also

 http://www.dot.state.mn.us/maps/gdma/data/metadata/county_att.htm

and the main page

 http://www.dot.state.mn.us/maps/gdma/gis-data.html

The source data was created by MnDOT in 2013, if that's what 'current' means.

===============


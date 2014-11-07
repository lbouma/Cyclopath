#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See the import service.'
assert(False)

# Usage:
#
#  $ export PYSERVER_HOME=/whatever
#  $ ./import_regions.py /path/to/file.shp tag
#
# Warning:
#
#  This script creates a new tag with version 1 if no entries of the tag exist
#  in the database (this tag never existed in the database). This script adds
#  the given tag to all the added regions.
#
# Note: for initial regions import, import neighborhoods with tag
# "neighborhood" and cities with tag "city".

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

import socket
import sys

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from util_ import db_glue
import geometry
# FIXME: In Ccpv2, layers renamed, permission no more.
from item.feat import region
from item.attc import tag
from util_ import geometry

assert(False) # 20110831: This file is still Ccpv1.

# Initialization

filename = sys.argv[1]
tg = sys.argv[2]

layer = ogr.Open(filename).GetLayer(0)
print '%d total features in %s' % (layer.GetFeatureCount(), filename)

# What's the name field? [Rhetorical]

layer_def = layer.GetLayerDefn()
fields = set([layer_def.GetFieldDefn(i).GetName()
              for i in xrange(layer_def.GetFieldCount())])
for namefield in ('BDNAME', 'CTU_NAME', 'NAME', None):
   if (namefield in fields):
      break
print 'name field is %s' % (namefield)

db = db_glue.new()
print 'Connected to database'

regions = region.Many()
db.transaction_begin_rw('revision')
rid = db.revision_create()

# Set up SRS parameters

shapefile_srs = layer.GetSpatialRef()
if (shapefile_srs is None):
   print "Shapefile has no SRS defined, aborting"
   sys.exit(1)
   #shapefile_srs = osr.SpatialReference()
   #shapefile_srs.SetWellKnownGeogCS('WGS84')

my_srs = geometry.spatial_reference_from_srid(conf.default_srid)

xform = osr.CoordinateTransformation(shapefile_srs, my_srs)

# Create regions

print 'Creating features '
matches = 0
skips = 0
while True:
   # Fetch from file
   fe = layer.GetNextFeature()
   if (fe is None):
      # end of file
      break
   # Extract data and reproject
   geo = fe.GetGeometryRef()
   geo.Transform(xform)
   geo.FlattenTo2D()
   # If geometry is a multipolygon (what freak decided 37 cities in this metro
   # could have exclaves and enclaves?), then pick the largest polygon and use
   # that (since regions are currently polygons, see Bug 1191).
   #
   # FIXME: this is kind of a hack...
   if (geo.GetGeometryName() == 'MULTIPOLYGON'):
      geos = list()
      for i in xrange(geo.GetGeometryCount()):
         subg = geo.GetGeometryRef(i)
         geos.append((subg.GetArea(), subg))
      geos.sort(reverse=True)
      print ('Warning: %s is multipolygon with %d components; choosing largest'
             % (fe.GetFieldAsString(namefield), geo.GetGeometryCount()))
      geo = geos[0][1]
   # Create feature
   r = region.One()
   r.version = 0
   r.geometry = geo.Buffer(0).ExportToWkt()
   r.name = fe.GetFieldAsString(namefield) or None
   r.type_code = 2
   r.revision_metadata_set(db, rid)
   # Check validity:
   # - Must be polygon
   # - Must be non-vacuous
   mobr = geo.GetEnvelope()
   if (geo.GetGeometryName() == 'POLYGON'
       and not (abs(mobr[0] - mobr[1]) < 1.0
                and abs(mobr[2] - mobr[3]) < 1.0)):
      regions.add(r)
      matches += 1
      print "Loaded %s (%.1f km^2)." % (r.name, geo.GetArea()/(1000**2))
   else:
      # Type is invalid
      print "Warning: skipping '%s', %f (%s)" % (r.name,
                                                 fe.GetFieldAsDouble('AREA'),
                                                 geo.GetGeometryName())
      skips += 1
print
print '%d features loaded, %d skipped' % (matches, skips)

# Save to database

regions.save(db)

print 'Fixing imported regions: simplifying geometry, setting valid_until_rid'
db.sql("""UPDATE region
          SET
            valid_until_rid = cp_rid_inf(),
            geometry = ST_SimplifyPreserveTopology(geometry, 2)
          WHERE valid_start_rid = %s""", (rid,))

if (tg is not None):
   res = db.sql("SELECT COUNT(*) AS c FROM tag WHERE label='%s'" % tg)

   if (res[0]['c'] == 0):
      print 'Tag %s does not exist. Creating it.' % (tg)
      db.sql("""
INSERT INTO tag (
   version,
   deleted,
   label,
   valid_start_rid,
   valid_until_rid
) VALUES (
   1,
   false,
   %s,
   %s,
   cp_rid_inf()
)""", (tg, rid))
   
   db.sql("""
INSERT INTO tag_region (
   version,
   deleted,
   tag_id,
   region_id,
   valid_start_rid,
   valid_until_rid
) SELECT 1,
         false,
         (select t.id from tag t where t.label = %s),
         r.id,
         %s,
         cp_rid_inf()
  FROM region r
  WHERE NOT EXISTS (SELECT tr.id 
                    FROM tag_region tr 
                    WHERE tr.region_id = r.id)""", (tg, rid))


print 'Saving revision %d to database' % (rid)
db.revision_save(rid, permission.public, socket.gethostname(), '_script',
                 str(sys.argv[1:]), skip_geometry=True)
db.transaction_commit()
db.close()

print 'Done. You may want to:'
print 'VACUUM ANALYZE;'


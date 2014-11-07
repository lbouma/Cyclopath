#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See the import service.'
assert(False)

# Usage:
#
#  $ export PYSERVER_HOME=/whatever
#  $ ./import_bmpolygons.py IN_LUSE2005 OUT_TYPE /path/to/file.shp
#
# where IN_LUSE2005 is the type code in the shapefile (see landuse_notes.pdf),
# and OUT_TYPE is the type code from table basemap_polygon_type.

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
from layers import bmpolygon

# Initialization

typecode = int(sys.argv[2])
lusecode = int(sys.argv[1])
filename = sys.argv[3]

layer = ogr.Open(filename).GetLayer(0)
print '%d total features in %s ' % (layer.GetFeatureCount(), sys.argv[3])

db = db_glue.new()
print 'Connected to database'

pgons = bmpolygon.Many()
rid = db.revision_create()
db.transaction_begin_rw('revision')

# Set up SRS parameters

shapefile_srs = layer.GetSpatialRef()
if (shapefile_srs is None):
   print "Shapefile has no SRS defined, assuming WGS84 lat/lon"
   shapefile_srs = osr.SpatialReference()
   shapefile_srs.SetWellKnownGeogCS('WGS84')

my_srs = osr.SpatialReference()
my_srs.SetProjCS('UTM 15N (NAD83)')
my_srs.SetWellKnownGeogCS('')
my_srs.SetUTM(15, True)

xform = osr.CoordinateTransformation(shapefile_srs, my_srs)

# Create byway segments

print 'Creating features '
i = 0
matches = 0
while True:
   # Progress bar
   i += 1
   if (i % 100 == 0):
      sys.stdout.write('.')
      sys.stdout.flush()
   # Fetch from file
   fe = layer.GetNextFeature()
   if (fe is None):
      # end of file
      break
   if (fe.GetFieldAsInteger('LUSE2005') != lusecode):
      # wrong land use code
      continue
   matches += 1
   # Extract data and reproject
   geo = fe.GetGeometryRef()
   geo.Transform(xform)
   geo.FlattenTo2D()
   # Create feature
   p = bmpolygon.One()
   p.geometry = geo.ExportToWkt()
   p.name = fe.GetFieldAsString('F_NAME') or None
   p.type_code = typecode
   p.valid_start_rid = rid
   # Check validity:
   # - Must be polygon
   # - Must be non-vacuous
   mobr = geo.GetEnvelope()
   if (geo.GetGeometryName() == 'POLYGON'
       and not (abs(mobr[0] - mobr[1]) < 1.0
                and abs(mobr[2] - mobr[3]) < 1.0)):
      pgons.add(p)
   else:
      # Type is invalid
      print "Warning: skipping '%s', %f (%s)" % (p.name,
                                                 fe.GetFieldAsDouble('AREA'),
                                                 geo.GetGeometryName())
print
print '%d features loaded' % (matches)

# Save to database
print 'Saving revision %d to database' % (rid)
pgons.save(db)
db.revision_save(rid, socket.gethostname(), '_' + sys.argv[0],
                 str(sys.argv[1:]))
db.transaction_commit()

print 'Done. You may want to:'
print 'VACUUM ANALYZE;'


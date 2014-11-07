#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See the import service.'
assert(False)

# This script imports standalone bike trails from the MNDOT bikeways shapefile.
#
# Note that it does _not_ set bicycle attributes on roads.
#
# Usage:
#
#   $ PYSERVER_HOME=/whatever
#   $ ./import_mndot_bikeways.py /path/to/file.shp

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
from layers import byway
import util

# Initialization

db = db_glue.new()
print 'Connected to database'

segs = byway.Many()
db.transaction_begin_rw('revision')
rid = db.revision_create()

rows = db.sql('''
SELECT
  name_mb,
  type,
  ST_AsText(GeometryN(geometry, 1)) AS geometry
FROM
  mndot_bikeways
WHERE
  proposed != 'Y'
  AND (conn_gap != 'Y' OR conn_gap IS NULL)
  AND type LIKE '%%Trail'
  AND length2d(geometry) >= 3 
''')
print '%d input rows' % (len(rows))

# Create byway segments

print 'Creating byway segments '
pr = util.Progress_Bar(len(rows))
for row in rows:
   # Create byway segment
   seg = byway.One()
   seg.id = db.sequence_get_next('item_versioned_id_seq')
   seg.geometry = row['geometry']
   seg.name = row['name_mb']
   seg.type_code = 14
   seg.paved = ('Paved' in row['type'])
   seg.valid_start_rid = rid
   seg.beg_node_id = 0
   seg.end_node_id = 0
   seg.save(db)
   pr.inc()
print

# Save to database
print 'Saving revision %d to database' % (rid)
db.revision_save(rid, socket.gethostname(), '_' + sys.argv[0], '')
db.transaction_commit()
db.close()

print 'Done. You may want to:'
print 'VACUUM ANALYZE;'


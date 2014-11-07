#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See the import service.'
assert(False)

# This script builds byway segments based on MNDOT basemap and auxiliary data.
# The main prerequisite is the tis_basemap_joined table/view joining basemap
# and TIS data.
#
# Usage: PYSERVER_HOME=/whatever ./import_mndot_roads.py

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

# Map of MNDOT roadway codes to gfl_byway codes. This is not a particularly
# good map, as the MNDOT codes give limited info on the actual size/import of
# a road.
type_map = { '01': 41,  # Interstate Trunk Highway
             '02': 31,  # U. S. Trunk Highway
             '03': 31,  # Minnesota Trunk Highway
             '04': 21,  # County State-aid Highway
             '05': 21,  # Municipal State-aid Street
             '07': 21,  # County Road
             '08': 21,  # Township Road
             '09': 11,  # Unorganized Township Road
             '10': 11,  # Municipal Street
             '11':  1,  # National Park Road
             '12':  1,  # National Forest Development Road
             '13':  1,  # Indian Reservation Road
             '14':  1,  # State Forest Road
             '15':  1,  # State Park Road
             '16':  1,  # Military Road
             '17':  1,  # National Monument Road
             '18':  1,  # National Wildlife Refuge Road
             '19': 11,  # Frontage Road
             '20':  1,  # State Game Preserve Road
             '22': 42,  # Ramp
             '23':  1,  # Private Jurisdiction Road
             '99':  1,  # (not listed in MNDOT metadata)
             }

# Initialization
db = db_glue.new()
rid = db.revision_create()
db.transaction_begin_rw('revision')
print 'Connected to database.'

# Create byways.
#
# The join can create multiple rows for the same object in mndot_basemap. To
# address this, for each object, we only consider the output row with the
# greatest linear overlap between the mndot_basemap and tisdata data.
#
# Note that MNDOT is skeptical of data quality for the TIS columns.
#
# See Chuck DeLisi data documentation for explanations of codes, etc. Widths
# are in feet. I am assuming that the left and right shoulders are the same.
#
# I have given up on trying to extract lane widths from the DeLisi data,
# particularly since they must be derived from lane count and surface width.
# The data just vary so wildly that I find them impossible to believe.
#
gids_seen = set()
rows = db.sql('''
SELECT
  gid,
  code,
  street_nam,
  streetnam2,
  route_dir,           -- increasing/decreasing-miles half of divided roadway
  mile_forward,        -- true if vertex order same as increasing miles
  ST_AsText(geometry) AS geometry,
  speed_limit_guessed,
  totln,               -- total number of lanes
  dv1way,              -- one-way code
  rst1,                -- right shoulder type code
  rsw1,                -- right shoulder width
  spdlm,               -- speed limit (miles per hour)
  aadt                 -- annual average daily traffic
FROM tis_basemap_joined
ORDER BY miles_overlap''')
print '%d input rows' % (len(rows))
rowcount = 1
for row in rows:
   if (rowcount % 1000 == 0):
      sys.stdout.write('.')
      sys.stdout.flush()
   rowcount += 1
   if (row['gid'] in gids_seen):
      continue
   # initialization
   gids_seen.add(row['gid'])
   bs = byway.One()
   bs.id = db.sequence_get_next('item_versioned_id_seq')
   aadt_row = dict()
   aadt_row['id'] = bs.id
   # name
   bs.name = row['street_nam']
   if (bs.name is not None
       and row['streetnam2'] is not None
       and not row['streetnam2'].startswith('MSAS')):
      bs.name += ' / ' + row['streetnam2']
   if (bs.name == 'Unknown or No Streetname'):
      bs.name = None
   # one-way
   ow = row['dv1way']
   if (ow == 'Z' or ((ow == 'D' or ow == 'O') and row['route_dir'] == 'I')):
      # one-way towards increasing milepoints
      if (row['mile_forward']):
         bs.one_way = +1  # one-way following geometry
      else:
         bs.one_way = -1  # one-way opposing geometry
   elif (ow == 'X' or ((ow == 'D' or ow == 'O') and row['route_dir'] == 'D')):
      # one-way towards decreasing milepoints
      if (row['mile_forward']):
         bs.one_way = -1  # one-way opposing geometry
      else:
         bs.one_way = +1  # one-way following geometry
   else:
      # two-way
      bs.one_way = 0
   # speed limit
   if (row['spdlm'] is not None):
      bs.speed_limit = row['spdlm']
   else:
      bs.speed_limit = row['speed_limit_guessed']
   # lane count, AADT
   bs.lane_count = row['totln']
   aadt_row['aadt'] = row['aadt']
   if (row['route_dir'] in ('D', 'I')):
      # divided highway; shape is only one half
      if (bs.lane_count is not None):
         bs.lane_count /= 2
      if (aadt_row['aadt'] is not None):
         aadt_row['aadt'] /= 2
   # paved shoulder width
   sht = row['rst1']
   if (sht is not None):
      sht = sht[0]
   if (sht in ('G', 'I', 'J')):
      # paved shoulder
      bs.shoulder_width = row['rsw1']
   elif (sht in ('0', 'A', 'B', 'C', 'D', 'E', 'F', 'K', 'L', 'M', 'N', 'S')):
      # no paved shoulder
      bs.shoulder_width = 0
   # miscellaneous
   bs.type_code = type_map[row['code']]
   bs.geometry = row['geometry']
   bs.valid_start_rid = rid
   bs.beg_node_id = 0
   bs.end_node_id = 0
   # save the stuff
   bs.save(db)
   if (aadt_row['aadt'] is not None):
      db.sql('''
INSERT INTO aadt
       (byway_id, aadt)
VALUES (%(id)s, %(aadt)s); ''', aadt_row)

# Save to database
print
print 'Saving revision %d to database' % (rid)
db.revision_save(rid, socket.gethostname(), '_' + sys.argv[0], '')
db.transaction_commit()
db.close()

print 'Done. You may want to:'
print 'VACUUM ANALYZE;'


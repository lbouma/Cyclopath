#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See node_cache_maker.py.'
assert(False)

# This script creates nodes for byway segments which:
#
#   (a) do not have them, or
#
#   (b) are incorrectly marked as loops (start_node_id = end_node_id but start
#       and end are not colocated).
#
# Notes:
#
# + This script is really, really slow: there are repeated queries which do a
#   sequential scan of byway_segment. Figure on about 1 second per
#   byway_segment row.
#
# + This script does not create a new revision, but it does use historically
#   correct node locations.
#
# + Byway segments having two points only and endpoint within epsilon of
#   startpoint will cause a crash.
#
# + start_node_id and end_node_id must be 0, not NULL, for byway segments to
#   be repaired. This is because IS NULL operator doesn't use indexing.

# Usage: PYSERVER_HOME=/whatever ./nodes_build.py EPSILON

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
import revision_query
import util

# Endpoints within this distance (meters) are considered to be equal.
epsilon = float(sys.argv[1])

def main():

   # Initialization
   global db
   db = db_glue.new()
   db.transaction_begin_rw('revision')
   print 'Connected to database'

   # Clean up invalid loops
   db.sql("""
UPDATE byway_segment
SET
   start_node_id = 0,
   end_node_id = 0
WHERE
   start_node_id = end_node_id
   AND start_node_id != 0
   AND Distance(StartPoint(geometry), EndPoint(geometry)) > %g""" % (epsilon))
   print 'Reset %d invalid loops' % (db.rowcount())

   # Create nodes for byway segments

   row_count = 0
   while True:
      b = byway_row()
      row_count += 1
      if (b is None):
         break
      if (row_count % 13 == 1):
         #db.sql("ANALYZE")
         print ('%d rows remain at %s'
                % (db.sql("""
SELECT count(*) FROM byway_segment
WHERE start_node_id = 0 OR end_node_id = 0""")[0]['count'],
                util.nowstr()))

      # new start point ID and geometry
      if (b['start_node_id'] == 0):
         (b['start_node_id_new'], b['start_point_new']) = node_get(b, 'start')
      else:
         b['start_node_id_new'] = b['start_node_id']
         b['start_point_new'] = b['start_point']

      # new end point ID and geometry
      if (b['end_node_id'] == 0):
         if (b['is_loop']):
            b['end_node_id_new'] = b['start_node_id_new']
            b['end_point_new'] = b['start_point_new']
         else:
            (b['end_node_id_new'], b['end_point_new']) = node_get(b, 'end')
      else:
         b['end_node_id_new'] = b['end_node_id']
         b['end_point_new'] = b['end_point']

      # update byway
      db.sql("""UPDATE byway_segment
                SET
                  start_node_id = %(start_node_id_new)d,
                  end_node_id = %(end_node_id_new)d,
                  geometry = SetPoint(SetPoint(geometry, %(point_count)d - 1,
                                               '%(end_point_new)s'),
                                      0, '%(start_point_new)s')
                WHERE
                  id = %(id)d AND version = %(version)d""" % b)

             
   # Save to database
   print 'done'
   db.transaction_commit()
   db.close()
   print 'Done. You may want to VACUUM ANALYZE;'

### Helper functions ###

def byway_row():
   'Return a database row corresponding to a byway which needs node repair.'
   row = db.sql("""
SELECT
  id,
  version,
  valid_start_rid,
  valid_until_rid,
  start_node_id,
  end_node_id,
  StartPoint(geometry) AS start_point,
  EndPoint(geometry) AS end_point,
  NumPoints(geometry) AS point_count,
  Distance(StartPoint(geometry), EndPoint(geometry)) <= %g AS is_loop
FROM byway_segment
WHERE
  start_node_id = 0 OR end_node_id = 0
LIMIT 1
""" % (epsilon))
   if (len(row) == 1):
      return row[0]
   else:
      return None

def node_get(byway_row, which):
   '''Return a (node_id, geometry) pair corresponding appropriate for an
      endpoint of byway byway_row. which should be "start" or "end".'''
   rq = revision_query.Historic(int(byway_row['valid_start_rid']))
   # see if there's anyone out there with a matching start/end node
   for thiswhich in ('start', 'end'):
      rows = db.sql("""SELECT
                         %(thiswhich)s_node_id AS node_id,
                         %(thiswhich)sPoint(geometry) AS point
                       FROM byway_segment
                       WHERE
                         Distance('%(needed_point)s',
                                  %(thiswhich)sPoint(geometry)) <= %(epsilon)g
                         AND %(thiswhich)s_node_id != 0
                         AND %(rq)s
                       LIMIT 1""" % {'thiswhich': thiswhich,
                                     'needed_point': byway_row['%s_point'
                                                               % (which)],
                                     'epsilon': epsilon,
                                     'rq': rq.as_sql_where()})
      if (len(rows) >= 1):
         return (rows[0]['node_id'], rows[0]['point'])
   # nothing - build a new one
   return (db.sequence_get_next('item_versioned_id_seq'),
           byway_row['%s_point' % (which)])

if (__name__ == '__main__'):
   main()


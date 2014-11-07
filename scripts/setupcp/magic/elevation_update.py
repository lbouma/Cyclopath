#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See node_cache_maker.py.'
assert(False)

# Update elevation in node_attribute from a raster file

import optparse
import re

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# 2012.02.05: elevation was consumed by node_endpoint.
g.assurt(False)
from item.util import elevation

from util_ import db_glue
from util_ import geometry
from util_ import misc

assert(False) # Update me from Ccpv1

usage = ('''
/%prog [FILENAME] OPTIONS 
Update elevation table from a raster file for the start node
and end node of all byways. Skip nodes whose elevation is
already in the database

$ export PYSERVER_HOME= location of your pyserver directory
$./%prog

Flags:
--clean -c           truncate the node_attribute table before
                     inserting elevation data (very destructive)

--verbose -v         print all info and errors (otherwise just prints errors)
''')

verbose = False

def main():
   global verbose
   
   op = optparse.OptionParser(usage=usage)
   op.add_option('-c', '--clean', action="store_true", dest="clean")
   op.add_option('-v', '--verbose', action="store_true", dest="verbose") 
   (options, args) = op.parse_args()
 
   if (len(args) == 1):
      # import elevation from a custom file
      elevation.elevation_source_set(filename=args[0])

   clean = options.clean
   verbose = options.verbose

   db = db_glue.new()
   db.transaction_begin_rw('revision')
   insert_elevations(db, clean)
   db.transaction_commit()
   db.close()

# utility info and error functions
def info(str): 
   if (verbose): 
      print str

def error(str): 
   print str

def insert_elevations(db,clean):

   if (clean): 
      info('Truncating node_attribute table.')

   info('Loading byway nodes into memory.')

   # this query is slow (as it is actually 4 queries), 
   # but saves time in the end by retrieving only nodes
   # that need to be updated
   q = (
      """
      SELECT 
         node_id, 
         nodes.geometry 
      FROM (
         (SELECT 
            beg_node_id AS node_id, 
            ST_AsText(StartPoint(geometry)) AS geometry
         FROM geofeature
         ) 
         UNION (SELECT 
            end_node_id as node_id, 
            ST_AsText(EndPoint(geometry)) AS geometry
         FROM geofeature)
         ) AS nodes
      WHERE 
         geometry IS NOT NULL 
         AND node_id NOT IN (SELECT node_id FROM node_attribute)
      GROUP BY node_id, geometry
      """)
   if (clean): 
      q = "TRUNCATE node_attribute; " + q
   rows = db.sql(q)
   info('DONE.')

   pr = misc.Progress_Bar(len(rows))
   for row in rows: 
      node_id = row['node_id']
      loc = geometry.wkt_point_to_xy(row['geometry'])
      #info('Inserting elevation for node (#%d).' % row['node_id'])
      if (loc is not None): 
         elevation.node_elevation_insert(db, node_id, loc)
      else: 
         error('Could not parse point')
      pr.inc()
   print

if __name__ == '__main__':
   main()


#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See the import service.'
assert(False)

# Import a set of lat, long points from CSV and store them in a revision.

import optparse
import csv
import socket

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from util_ import db_glue
import permission

usage = '''
  ./%prog CSVFILE [options]

  --delimiter   The field delimiter to use (default is ',')
  --changenote  The text to use for the revision comment

  This script assumes that the first row of the CSV file contains column names.
  Use --name, --latitude, --longitude, and --comments to indicate which column
  names to use.  Defaults are "name", "latitude", "longitude", and "comments"
  respectively.

Example (using file from http://geonames.usgs.gov/):

  ./%prog /path/to/usgs.csv --name FEATURE_NAME --latitude PRIM_LAT_DEC \\
      --longitude PRIM_LONG_DEC --tag FEATURE_CLASS --delimiter \\|'''

def main():

   op = optparse.OptionParser(usage=usage)
   op.add_option('-n', '--name',       dest='name',      default='name')
   op.add_option('-l', '--latitude',   dest='latitude',  default='latitude')
   op.add_option('-g', '--longitude',  dest='longitude', default='longitude')
   op.add_option('-c', '--comments',   dest='comments',  default='comments')
   op.add_option('-t', '--tag',        dest='tag',       default='tag')
   op.add_option('-d', '--delimiter',  dest='delimiter', default=',')
   op.add_option('-m', '--changenote', dest='changenote',
                 default='Import points from CSV file')

   (opts, args) = op.parse_args()

   if (len(args) == 0):
      op.error('CSVFILE must be specified.')

   csvfile = args[0]

   # Make sure required columns exist
   data = csv.DictReader(open(csvfile), delimiter=opts.delimiter)
   r = data.next();
   if (r.get(opts.name) is None or r.get(opts.latitude) is None or 
       r.get(opts.longitude) is None):
      op.error('One or more required fields not found in column names.')
   
   db = db_glue.new()
   db.transaction_begin_rw()
   
   # Re-open file and import points into temporary table
   db.sql('''CREATE TEMPORARY TABLE point_tmp
               (name text, comments text, tag text, geometry geometry)''');
   data = csv.DictReader(open(csvfile), delimiter=opts.delimiter)
   for r in data:
      name = r.get(opts.name)
      lat  = r.get(opts.latitude)
      long = r.get(opts.longitude)
      tag  = r.get(opts.tag)
      comments = r.get(opts.comments)

      if lat == '' or long == '':
         print 'Latitude or longitude not specified for this point; skipping'
      else:
         db.sql('''INSERT INTO point_tmp (name, comments, tag, geometry)
                   VALUES (%(name)s, %(comments)s, LOWER(%(tag)s),
                   ST_Transform(
                     ST_SetSRID(MakePoint(%(long)s, %(lat)s), %(srid_latlon)s),
                     %(srid_default)s))''', 
                 { 'name': name,
                   'comments': comments,
                   'tag': tag,
                   'long': long,
                   'lat': lat,
                   'srid_latlon': conf.srid_latlon,
                   'srid_default': conf.default_srid
                  })

   # Save points falling within coverage_area to real point table
   rid = db.revision_create();
   for r in db.sql('''SELECT name, comments, tag, geometry FROM point_tmp
                      WHERE ST_Contains((SELECT geometry FROM coverage_area),
                                        geometry)'''):

      # Create point
      r['valid_starting_rid'] = rid
      r['id'] = db.sequence_get_next('feature_id_seq')
      db.sql('''INSERT INTO point
                  (id, version, deleted, type_code, name, comments,
                  valid_starting_rid, valid_before_rid, z, geometry)
                VALUES
                  (%(id)s, 1, false, 2, %(name)s, %(comments)s,
                  %(valid_starting_rid)s, cp_rid_inf(), 140, %(geometry)s)''', 
             (r))

      # Apply tag, if applicable
      if (r['tag'] is not None and r['tag'] != ''):
         db.sql('''INSERT INTO tag (version, deleted, label,
                                    valid_starting_rid, valid_before_rid)
                   SELECT 1, false, %s, %s, cp_rid_inf()
                   WHERE NOT EXISTS (SELECT id FROM tag WHERE label=%s);''',
                (r['tag'], rid, r['tag']))
         db.sql('''INSERT INTO tag_point (version, deleted, tag_id, point_id,
                                          valid_starting_rid, valid_before_rid)
                   VALUES (1, false, (SELECT id FROM tag WHERE label=%s),
                          %s, %s, cp_rid_inf)''',
                (r['tag'], r['id'], rid))
         
   db.revision_save(rid, permission.public, socket.gethostname(), '_script',
                    opts.changenote)
   db.transaction_commit()
   db.close()
   print ('Committed revision %s.' % rid)

if (__name__ == '__main__'):
   main()


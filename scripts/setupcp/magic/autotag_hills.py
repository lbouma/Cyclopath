#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated.'
assert(False)

# Add the hill tag to every current byway at least as steep as a grade
# (default 4%).

import optparse
import os

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

from util_ import db_glue
import wfs_op_base

usage = '''
Add the 'hill' tag to all current byways with grade > min_hill_grade if they
are not already tagged 'hill'.

WARNING/FIXME: This script appears quite general, but has been tested only as
"./autotag_hills.py -e -v". Use caution.

$ export PYSERVER_HOME= location of your pyserver directory
$ ./%prog [min_hill_grade] [OPTIONS]

Flags:
--changenote -m         attach this changenote message to the revision

--verbose    -v         print all info and errors

--wremail    -e         email users about changes in their watched regions
'''

assert(False)  # the next line needs an % operator
changenote_default = "Applied 'hill' tag to all blocks with grade > %d%%."
hill_grade_min_default = 4
verbose = False

def main():
   global verbose

   op = optparse.OptionParser(usage=usage)
   op.add_option('-m', '--changenote', dest="changenote",
                 default=changenote_default)
   op.add_option('-v', '--verbose', action="store_true", dest="verbose")
   op.add_option('-e', '--wremail', action="store_true", dest="wremail") 
   (options, args) = op.parse_args()

   if (len(args) == 0):
      # no grade argument was provided
      hill_grade_min = hill_grade_min_default
   elif (len(args) == 1):
      hill_grade_min = args[0]
   else:
      op.error('More than one argument was provided.')

   try:
      hill_grade_min = float(hill_grade_min)
   except(ValueError):
      hill_grade_min = -1

   if (hill_grade_min <= 0):
      op.error('Grade must be a positive number.')

   verbose = options.verbose
   wremail = options.wremail
   changenote = options.changenote

   db = db_glue.new()
   byway_hills_tag(db, hill_grade_min, changenote, wremail)
   db.commit()
   db.close()

def info(str):
   if (verbose):
      print str

def error(str):
   print str

def byway_hills_tag(db_, min_hill_grade, changenote=None, wr_email=False):
   ''' Tag all hills with grade at least <min_hill_grade>.'''
   info("Adding 'hill' tag to all byways with grade > %.2f." % min_hill_grade)
   db_.transaction_begin_rw()
   rid = db_.revision_create()
   hill_tag_retrieve_sql = '''
INSERT INTO tag (version, deleted, label, valid_start_rid, valid_until_rid)
SELECT 1, false, 'hill', %d, cp_rid_inf()
WHERE 'hill' NOT IN (SELECT label FROM tag);

SELECT id FROM tag WHERE label = 'hill';
''' % rid
   hill_tag_id = db_.sql(hill_tag_retrieve_sql)[0]['id']
   add_hill_tag_sql = '''
INSERT INTO tag_bs (
  version, deleted, tag_id, byway_id, valid_start_rid, valid_until_rid
)
SELECT 1, false, %(hill_tag_id)d, bc.id, %(rid)d, cp_rid_inf()
FROM iv_gf_cur_byway bc
JOIN node_attribute sna
  ON (beg_node_id = sna.node_id)
JOIN node_attribute ena
  ON (end_node_id = ena.node_id)
LEFT JOIN tag_bs
  ON (byway_id = bc.id AND tag_id = %(hill_tag_id)d)
WHERE
  abs((ena.elevation_meters - sna.elevation_meters) * 100 / Length(geometry))
    >= %(min_hill_grade)d
  AND tag_bs.id IS NULL
''' % { 'hill_tag_id' : hill_tag_id,
        'min_hill_grade' : min_hill_grade,
        'rid' : rid }
   db_.sql(add_hill_tag_sql)
   db_.revision_save(rid, os.uname()[1], '_autotagger', changenote, False)

   if (wr_email):
      info('Sending email to watch region users.')
      # hack op_base to reuse code
      class DummyRec: db = db_
      wfs_op_base.Op_Handler(DummyRec()).notify_email(rid, changenote)

if __name__ == '__main__':
   main()

#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See populate_revision_geo.py.'
assert(False)

# This script recomputes all revision geosummaries.
#
# Usage:
#
#   $ export PYSERVER_HOME=/whatever
#   $ ./revision_geosummaries_update.py

assert(False)
# FIXME: See populate_revision_geo (maybe rename that to this and replace
#        this...)

import mx.DateTime as DT
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
import util

db = db_glue.new()

# Create fake ratings so byway fetch will always work
print 'Retrieving revision IDs'
rids = [r['id'] for r in db.sql("""SELECT id FROM revision
                                   WHERE id != cp_rid_inf()
                                   ORDER BY id""")]

#pr = util.Progress_Bar(len(bs))
rid_ct = len(rids)
rid_done = 0
time_start = DT.now()
for rid in rids:
   time_now = DT.now()
   delta_per_rid = (time_now - time_start) / (rid_done or 1)
   print ('rid %d, max %d\n  now %s; per %s; finish %s'
          % (rid, max(rids), str(time_now),
             str(delta_per_rid),
             str(time_now + (delta_per_rid * (rid_ct - rid_done)))))
   db.sql("SELECT cp_revision_geosummary_update(%d)" % (rid))
   rid_done += 1
#   pr.inc()
#print

# Done
db.transaction_commit()
db.close()


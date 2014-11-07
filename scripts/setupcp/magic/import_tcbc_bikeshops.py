#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

print 'This script is deprecated. See the import service.'
assert(False)

# This script imports the TCBC bike shop list.
#
# Usage: PYSERVER_HOME=/whatever

import elementtree.ElementTree as et
from elementtree import TidyTools
import os
import re
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
from item import waypoint
import route
import util

def clean(s):
   return re.sub(r'\s+', ' ', s.strip())

# Init
db = db_glue.new()
db.transaction_begin_rw('revision')
rid = db.revision_create()

body = TidyTools.getbody('../misc/tcbc-bikeshops.html')
rows = body.findall('.//center/table/tbody/tr')

pb = util.Progress_Bar(len(rows))
for row in rows:
   cols = row.findall('./td')
   name = cols[0].find('.//strong').text
   if (name is None):
      name = cols[0].find('./strong/a').text
   assert (name is not None)
   name = clean(name)
   link = cols[0].find('.//a')
   if (link is not None):
      link = link.get('href')
   addr = clean(cols[1].text + ', ' + cols[2].text)
   phone = clean(cols[3].find('./div').text)
   (x, y, canaddr) = db.geocode(addr)
   p = waypoint.One()
   p.name = name
   p.comments = phone
   if (link is not None):
      p.comments += '\n' + link
   p.geometry = 'POINT(%f %f)' % (x, y)
   p.revision_metadata_set(db, rid)
   p.save(db)
   pb.inc()

# Save to database
print
print 'Saving revision %d to database' % (rid)
db.revision_save(rid, socket.gethostname(), '_' + sys.argv[0], '')
db.transaction_commit()
db.close()

print 'Done. You may want to:'
print 'VACUUM ANALYZE;'


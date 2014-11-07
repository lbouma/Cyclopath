#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This script checks if any server crash dumps are present in the given
# directory. If so, it complains and moves the dumps to an archive directory.
# If all's well, there is no output.

import glob
import os
import os.path
import sys
import time

dumpdir = sys.argv[1]
os.chdir(dumpdir)

archivedir = time.strftime('%Y%m%d')

# Set to true if you want this script to do the complaining itself (e.g., if
# you don't have logcheck running).
# See: pyserver.gwis.request.Request.error_handler_exception
verbose = False

# Example directory contents:
#
#   dump.20090923-14:08:27.278995_98.240.216.45_EXCEPT
#   dump.20090923-14:08:27.278995_98.240.216.45_REQUEST
#   dump.20090925-11:22:09.35435_64.122.36.69_EXCEPT
#   dump.20090925-11:22:09.35435_64.122.36.69_REQUEST
#   dump.EXCEPT
#   dump.REQUEST
#
# This matches the longer files (historical crash dumps) but not the shorter
# ones (the most recent crash dump).
dumps = glob.glob('dump*_*')

if (len(dumps) > 0):
   if (verbose):
      print
      print "!!! FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL !!!"
      print
      print "Detected %d new crash dumps in %s." % (len(dumps)/2, dumpdir)
      print "They have been moved to %s/%s." % (dumpdir, archivedir)
      print
      print "The totem holder should investigate immediately!"
      print
      print "!!! FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL !!!"
      
   if (not os.path.exists(archivedir)):
      os.mkdir(archivedir)
      # 2013.05.06: Need to chmod?
      os.chmod(archivedir, 02775)

   for dump in dumps:
      os.rename(dump, '%s/%s' % (archivedir, dump))

   # ***

# ***


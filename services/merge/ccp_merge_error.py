# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import traceback

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
#sys.path.insert(0, os.path.abspath('%s/../../pyserver' % (sys.path[0],)))
#import pyserver_glue

import conf
import g

log = g.log.getLogger('ccp_merg_err')

from util_ import misc

class Ccp_Merge_Error(Exception):

   def __init__(self, message):
      Exception.__init__(self, message)

# ***

if (__name__ == '__main__'):
   pass


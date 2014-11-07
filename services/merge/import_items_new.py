# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from decimal import Decimal
import os
import sys
import time

import conf
import g

log = g.log.getLogger('io_items_new')

from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from util_ import db_glue
from util_ import geometry
from util_ import gml

from merge.import_networking import Import_Networking

class Import_Items_New(Import_Networking):

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Networking.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Import_Networking.reinit(self)

   # *** Entry point.

   #
   def fids_new_consume(self):

      log.info('Processing %d new, unconflated features.' 
               % (len(self.new_fids),))

      log.warning('fids_new_consume: FIXME: Not implemented.')
      pass # FIXME: Implement

   # ***

   # Conflation Notes:
   #
   # Superconflated: i.e., one Ccp line but two Agy lines
   # Is Underconflated the opposite? or called something else?
   #                 i.e., 2 Ccp lines and 1 Agy line.
   # Can we detect either case?

# ***

if (__name__ == '__main__'):
   pass


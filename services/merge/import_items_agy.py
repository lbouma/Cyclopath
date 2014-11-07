# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from decimal import Decimal
import os
import sys
import time

import conf
import g

log = g.log.getLogger('io_items_agy')

from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger

from merge.import_items_new import Import_Items_New

class Import_Items_Agy(Import_Items_New):

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Items_New.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Import_Items_New.reinit(self)

   # ***

   #
   def fids_agy_consume(self):

      # FIXME: RENAME fcn to reflect agy_fids

      # FIXME: What's a good freq?
      prog_log = self.progr_get(log_freq=1, loop_max=len(self.agy_fids))

      self.fids_agy_consume_(prog_log)

   #
   def fids_agy_consume_(self, prog_log):

      # FIXME: Implement this fcn.: consume standup feats.
      # add to disconnft or whatever and connect to netw
      # add to self.match_fts or whatever and consume new attrs

# BUG nnnn: This is Cyclopath Conflation. CcpCft
# FIXME: Nope ^^. This is a new item that the user has said doesn't match to
# any existing Ccp feature that we need to wire to the network. 
#
# FIXME: what're the terms? standin, standup, ....
# i mean, a standup that needs to be wired is the same as a standin whose
# geometry has changed... or a split whose geometry has changed...
#
# FIXME: standalone update feats are from the source layer and do not 
# match any Cyclopath geofeature and are certified to have correct geometry so
# we just have to figure out their node_endpoints... unless they're not line
# segments, and then we don't care?



      for fid in self.agy_fids:
         feat = self.import_lyr.GetFeature(fid)
         if self.debug.debug_skip_standups:
            # Leave the action as 'Import'.
            new_feat = self.temp_layer_add(feat, the_action, the_context)
         else:
            log.error('fids_agy_consume_: Not implemented!')

   # ***

# ***

if (__name__ == '__main__'):
   pass


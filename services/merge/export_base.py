# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import os
import re
import sys
import time

from gwis.query_overlord import Query_Overlord
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from util_ import db_glue
from util_ import geometry
from util_ import gml

from merge.ccp_merge_ceil import Ccp_Merge_Ceil
from merge.import_init import Feat_Skipped

log = g.log.getLogger('export_base')

__all__ = ('Export_Base',)

# *** Export_Base

class Export_Base(Ccp_Merge_Ceil):

   tlyr_export = 'Cyclopath Export'

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Ccp_Merge_Ceil.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Ccp_Merge_Ceil.reinit(self)

   # ***

   #
   def get_output_layer_names(self):
      if self.target_lnames is None:
         self.target_lnames = [Export_Base.tlyr_export,]
      return self.target_lnames

   # ***

   #
   def field_val_setup_all(self, old_byway, context):
      dst_layer = self.target_layers_final[Export_Base.tlyr_export]
      src_feat = None
      just_copy_from = False
      try:
         dst_feat = self.defs.field_val_setup_all(dst_layer, old_byway, 
                                    src_feat, context, just_copy_from,
                                    bad_geom_okay=True)
      except Feat_Skipped:
         g.assurt(False)
      return dst_feat

   # *** Database fcns.

   #
   def setup_qb_src(self, all_errs):
      Ccp_Merge_Ceil.setup_qb_src(self, all_errs)
      # If the user restricted the export by a bbox, figure that out now.
      log.debug('setup_qb_src: self.qb_src: %s' % (self.qb_src),)
      log.debug('setup_qb_src: self.mjob.wtem.job_def.filter_by_region: %s'
                % (self.mjob.wtem.job_def.filter_by_region),)
      if self.qb_src is not None:
         self.qb_src.filters.filter_by_regions = (
            self.mjob.wtem.job_def.filter_by_region)
         Query_Overlord.finalize_query(self.qb_src)

   # ***

   #
   def geodatabases_close(self):
      # Nothing to do and not calling Ccp_Merge_Attrs.geodatabases_close(self).
      # See do_merge_io().
      pass

   #
   def spats_stew(self):
      pass

# ***

if (__name__ == '__main__'):
   pass



# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

log = g.log.getLogger('ccp_export')

from merge.export_base import Export_Base
from merge.export_cyclop import Export_Cyclop

class Ccp_Export(Export_Cyclop):

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Export_Cyclop.__init__(self, mjob, branch_defs)

   # *** 

   #
   def do_export(self):
      okay = self.do_merge_io(self.feature_classes_export)
      return okay


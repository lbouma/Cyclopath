# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This class is the pruppet master. It's the main entry point into the import.
# It calls fcns. in the class hierarchy to do most of the work.

import os
import sys

import conf
import g

log = g.log.getLogger('ccp_import')

from merge.import_base import Import_Base
from merge.import_cyclop import Import_Cyclop

# See http://mediawiki/index.php?title=Tech:Cycloplan/Conflation

# Our (Handler) hierarchy:
#  Ccp_Import
#  Import_Cyclop
#  Import_Items_Ccp
#  Import_Items_Agy
#  Import_Items_New
#  Import_Networking
#  Import_Geowiki
#  Import_Init
#  Import_Stats
#  Import_Base
#  Ccp_Merge_Ceil
#  Ccp_Merge_Layer_Base
#  Ccp_Merge_Attrs
#  Ccp_Merge_Base
#
# Definition hierarchy:
#  [MetC_Bikeways_Defs or other derived custom class]
#  Public_Basemap_Defs
#  Branch_Defs_Base
#
# MergeJob hierarchy:
#  Merge_Job_Import
#  Merge_Job_Base
#  Work_Item_Job

class Ccp_Import(Import_Cyclop):

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Cyclop.__init__(self, mjob, branch_defs)

   # *** 

   #
   def do_import(self):
      okay = self.do_merge_io(self.feature_classes_import)
      return okay

   # ***

# ***


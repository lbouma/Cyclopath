# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('ccp_mrg_ceil')

from merge.ccp_merge_layer_base import Ccp_Merge_Layer_Base

class Ccp_Merge_Ceil(Ccp_Merge_Layer_Base):

   def __init__(self, mjob, branch_defs):
      Ccp_Merge_Layer_Base.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Ccp_Merge_Layer_Base.reinit(self)

   # ***

# ***

if (__name__ == '__main__'):
   pass


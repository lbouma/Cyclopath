# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import re
import socket
import sys
import time
import traceback

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
#sys.path.insert(0, os.path.abspath('%s/../../../pyserver' 
#                % (os.path.abspath(os.curdir),)))
#import pyserver_glue

import conf
import g

log = g.log.getLogger('greater_mn')

# From pyserver
from grax.access_level import Access_Level
from item import item_base
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import route
from item.grac import group
from item.link import link_attribute
from item.link import link_tag
from item.util import ratings
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml

from merge.ccp_export import Ccp_Export
from merge.ccp_import import Ccp_Import
from merge.branches.public_basemap_defs import Public_Basemap_Defs
from merge.branches.metc_bikeways_defs import MetC_Bikeways_Defs

# *** Greater_Mn_Defs

# FIXME: From whence should we derive?
#class Greater_Mn_Defs(Public_Basemap_Defs):
class Greater_Mn_Defs(MetC_Bikeways_Defs):

   # *** Constructor

   def __init__(self, mjob):
      #Public_Basemap_Defs.__init__(self, mjob)
      MetC_Bikeways_Defs.__init__(self, mjob)
      #
      g.assurt(len(self.attrs_by_branch['metc_bikeways']) > 0)

   # *** Entry routine

   # This is boiler plate code for any branch that wants to support merge/IO.

   #
   @staticmethod
   def process_export(mjob):
      if mjob.the_def is None:
         g.assurt(mjob.handler is None)
         mjob.the_def = Greater_Mn_Defs(mjob)
         mjob.handler = Ccp_Export(mjob, mjob.the_def)
      okay = mjob.handler.do_export()
      return okay

   #
   @staticmethod
   def process_import(mjob):
      if mjob.the_def is None:
         g.assurt(mjob.handler is None)
         mjob.the_def = Greater_Mn_Defs(mjob)
         mjob.handler = Ccp_Import(mjob, mjob.the_def)
      okay = mjob.handler.do_import()
      return okay

   # ***

   #
   def init_import_defns(self):

      MetC_Bikeways_Defs.init_import_defns(self)

   #
   def init_field_defns(self):

      MetC_Bikeways_Defs.init_field_defns(self)

   # *** 

# ***

if (__name__ == '__main__'):
   pass


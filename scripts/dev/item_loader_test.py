#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./item_loader_test.py --help
#
# Also:
#
#  $ ./item_loader_test.py |& tee 2012.08.02.item_loader_test.txt

script_name = ('Item Loader Test')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-08-02'

# *** That's all she rote.

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('item_loader_test')

# *** 

from decimal import Decimal
import gc
import psycopg2
import socket
import time
import traceback
import traceback

from grax.access_level import Access_Level
from gwis.query_branch import Query_Branch
from item import item_base
from item import item_versioned
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
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
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debug switches

# FIXME: Just debugging.

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 3
##debug_prog_log.debug_break_loop_cnt = 10

debug_skip_commit = False
#debug_skip_commit = True

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     )

# *** Cli arg. parser

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)
      #
      self.groups_none_use_public = True

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self)
      #
      self.add_argument('--create-tables', dest='create_tables',
         action='store_true', default=False,
         help='recreate the tile cache tables')

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      return ok

# *** Item_Loader_Test

class Item_Loader_Test(Ccp_Script_Base):

   __slots__ = (
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      # Skipping: Ccp_Script_Base.go_main(self)

      do_commit = False

      try:

         #import pdb;pdb.set_trace()

         if self.cli_opts.create_tables:
            self.cleanup_tables()
            self.create_tables()

         self.load_items()

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   # ***

   #
   def query_builder_prepare(self):
      Ccp_Script_Base.query_builder_prepare(self)
      self.qb.filters.skip_geometry_raw = True
      self.qb.filters.skip_geometry_svg = True
      self.qb.filters.skip_geometry_wkt = False
      #
      #revision.Revision.revision_lock_dance(
      #   self.qb.db, caller='item_loader_test.py')

   # ***

   #
   def cleanup_tables(self):

      log.info('Cleaning up old tables...')

      pass

   # ***

   #
   def create_tables(self):
      pass

   # ***

   #
   def load_items(self):

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_freq = 2500

      # DEVS: To load just specific stack IDs:
      # self.qb.load_stack_id_lookup('load_items', self.my_stack_id_list)

      log.debug('load_items: calling load_feats_and_attcs...')
      self.qb.item_mgr.load_feats_and_attcs(self.qb, byway, 
         'search_by_network', self.process_one_byway, prog_log, 
         heavyweight=False, fetch_size=0, keep_running=None)

   #
   def process_one_byway(self, qb, bway, prog_log):

      log.debug('one_byway: %s' % (bway,))

# ***

if (__name__ == '__main__'):
   item_loader_test = Item_Loader_Test()
   item_loader_test.go()


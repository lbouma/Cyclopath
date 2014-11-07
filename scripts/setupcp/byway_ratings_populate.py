#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./byway_ratings_populate.py --help
#
# Also:
#
#  $ ./byway_ratings_populate.py |& tee 2013.05.11.byway_rats_pop.txt
#

script_name = ("Repopulate generic rater's byway_ratings")
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-08-15'

# ***

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue
import time

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

log = g.log.getLogger('bwy_rtgs_pop')

# ***

import copy
import psycopg2
import time
import traceback

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from grax.user import User
from gwis.query_overlord import Query_Overlord
from item import item_base
from item import item_user_access
from item import item_versioned
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.grac import group
from item.link import link_attribute
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from item.util.watcher_frequency import Watcher_Frequency
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debug switches

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 3
##debug_prog_log.debug_break_loop_cnt = 10

debug_skip_commit = False
#debug_skip_commit = True

debug_just_ids = ()
# 2013.11.30: A problem with a byway whose aadt record said -1.
#             So checked aadt > 0, not just that it's nonzero.
#debug_just_ids = (1098910,)
# MNTH 61:              3831394   2774654
# Scenic Dr:            3786178   2772224
# Old North Shore Rd:             2771643
#debug_just_ids = (3786178, 3831394, 2774654, 2772224, 2771643,)

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     or debug_just_ids
                     )

if debugging_enabled:
   log.warning('****************************************')
   log.warning('*                                      *')
   log.warning('*      WARNING: debugging_enabled      *')
   log.warning('*                                      *')
   log.warning('****************************************')

# *** Cli arg. parser

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self)

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      return ok

# *** Byway_Ratings_Populate

class Byway_Ratings_Populate(Ccp_Script_Base):

   #__slots__ = (
   #   'userless_qb',
   #   'bulk_shift',
   #   'bulk_delay',
   #   'stats',
   #   )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      #
      self.userless_qb = None
      #
      self.bulk_shift = []
      self.bulk_delay = 10000
      #
      self.stats = dict()
      self.stats['cnt_total_ratings'] = 0
      self.stats['cnts_rating_values'] = {}

   # ***

   #
   def go_main(self):

      # Skipping: Ccp_Script_Base.go_main(self)

      do_commit = False

      try:

         log.debug('go_main: getting exclusive revision lock...')
         revision.Revision.revision_lock_dance(
            self.qb.db, caller='bike_ratings_populate__go_main')
         log.debug('go_main: database is locked.')

         # Skipping: Get a new revision ID.
         #   self.qb.item_mgr.start_new_revision(self.qb.db)
         #   log.debug('Got rid_new: %d' % (self.qb.item_mgr.rid_new,))

         self.setup_userless_qb()

         self.compute_generic_ratings()

         # Skippping Save the new revision and finalize the sequence numbers.
         #   group_names_or_ids = [group.Many.public_group_id(self.qb),]
         #   complain_to_this_user = '_script'
         #   changenote = ('Recomputed byway ratings for generic rater')
         #   self.finish_script_save_revision(group_names_or_ids,
         #                                    username=complain_to_this_user,
         #                                    changenote=changenote)

         self.print_stats()

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   # ***

   #
   def setup_userless_qb(self):

      self.userless_qb = None

      username = ''
      self.userless_qb = Item_Query_Builder(self.qb.db.clone(),
                                            username,
                                            self.qb.branch_hier,
                                            self.qb.revision)
      self.userless_qb.request_is_local = True
      self.userless_qb.request_is_script = True
      self.userless_qb.filters.gia_userless = True
      g.assurt(not self.userless_qb.revision.allow_deleted)
      self.userless_qb.grac_mgr = self.qb.grac_mgr
      self.userless_qb.item_mgr = self.qb.item_mgr

   # ***

   #
   def compute_generic_ratings(self):

      log.info('compute_generic_ratings: ready, set, populate!')

      time_0 = time.time()

      # 2013.08.15: This is somewhat hacky, simply because the byway_rating
      # table is based on current item revisions. Ideally (Bug nnnn), the
      # byway_rating and byway_rating_event tables should be replaced by a
      # /byway/user_rating attribute (implemented like /item/alert_email).
      #
      # The problem is that a branch uses a parent's byway ratings if the
      # byway in question hasn't been saved to the branch. But a problem
      # arises if you delete a byway in the parent branch (or split a
      # byway in the parent branch, which deletes a byway): the byway_rating
      # recorded for the byway in the parent branch is reset to 0, since the
      # byway and its link_values are deleted (and commit.py's function,
      # byway_ratings_update, only gets undeleted geofeatures and links).
      #
      # So we have to duplicate all of the byway_ratings for the new branch...

      where_ids = ""
      if debug_just_ids:
         stack_ids_str = "'%s'" % "','".join([str(x) for x in debug_just_ids])
         where_ids = ("AND (byway_stack_id IN (%s))" % (stack_ids_str,))
         self.userless_qb.filters.only_stack_ids = stack_ids_str

      # Delete, e.g., ratings by generic_rater_username, cbf7_rater_username,
      # and bsir_rater_username.
      log.debug('compute_generic_ratings: delete generic ratings: %s'
                % (conf.rater_usernames,))
      delete_sql = (
         """
         DELETE FROM byway_rating
         WHERE ((branch_id = %d)
                AND (username IN ('%s'))
                %s)
         """
         % (self.qb.branch_hier[0][0],
            "','".join(conf.rater_usernames),
            where_ids,))
            
      rows = self.qb.db.sql(delete_sql)
      g.assurt(rows is None)

      self.bulk_shift = []
      self.bulk_delay = 10000

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_freq = 2500

      feat_class = byway
      #feat_search_fcn = 'search_by_network'
      feat_search_fcn = 'search_for_items' # E.g. byway.Many().search_for_items
      processing_fcn = self.make_generic_byway_rating
      log.debug('compute_generic_ratings: calling load_feats_and_attcs...')
      self.userless_qb.item_mgr.load_feats_and_attcs(
            self.userless_qb, feat_class, feat_search_fcn,
            processing_fcn, prog_log, heavyweight=False)

      # One last bulk insert.
      if self.bulk_shift:
         byway.Many.bulk_insert_ratings(self.qb, self.bulk_shift)
         del self.bulk_shift

      self.userless_qb.db.close()
      self.userless_qb = None

      log.info('compute_generic_ratings: processed %d features in %s'
               % (prog_log.progress,
                  misc.time_format_elapsed(time_0),))

   #
   def make_generic_byway_rating(self, qb, bway, prog_log):

      #g.assurt(id(qb) == id(self.qb))
      g.assurt(id(qb) == id(self.userless_qb))

      # See above; we've already cleaned up byway_node of all data pertaining
      # to this branch, so skip node_byway.Many.reset_rows_for_byway and just
      # insert.

      # Pass the bulk list so byway doesn't call generic_rating_save.
      # NOTE: Using self.qb, which is what gets committed; userless_qb is just
      #       so we find all byways.
      #byway.One.generic_rating_update(self.qb, bway, self.bulk_shift)
      bway.refresh_generic_rating(self.qb, self.bulk_shift)

      # To help with sanity checking and because devs like stats, remember the
      # counts of each generic rating applied.
      misc.dict_count_inc(self.stats['cnts_rating_values'],
                          int(bway.generic_rating * 10))

      # We only insert every so often.
      if self.bulk_shift and (not (prog_log.progress % self.bulk_delay)):
         # See the fcn. we're calling: it expects a list of quoted tuples,
         # e.g., "(branch_id, byway_stack_id, username, value)"
         byway.Many.bulk_insert_ratings(self.qb, self.bulk_shift)
         self.bulk_shift = []

   # ***

   #
   def print_stats(self):

      log.debug('*** stats: calculated %d byway ratings'
                % (self.stats['cnt_total_ratings'],))

      for rat_val, rat_cnt in self.stats['cnts_rating_values'].iteritems():
         log.debug('*** rat_val: %1d / rat_cnt: %d'
                   % (rat_val, rat_cnt,))

   # ***

# ***

if (__name__ == '__main__'):
   byway_rats_pop = Byway_Ratings_Populate()
   byway_rats_pop.go()


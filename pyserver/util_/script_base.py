# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage: This is a base class for Cyclopath command line scripts.

import copy
import os
import psycopg2
import signal
import sys
import threading
import time

import conf
import g

from grax.item_manager import Item_Manager
from gwis.query_overlord import Query_Overlord
from item.feat import branch
from item.grac import group
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_ import misc

log = g.log.getLogger('script_base')

# *** Ccp script base class

class Ccp_Script_Base(object):

   # If using master and worker scripts, this event fires
   # when the master script intercepts the Ctrl-C event.
   master_ctrl_c_event = None

   __slots__ = (
      'argparser',
      'cli_args',
      'cli_opts',
      'qb',
      'skip_query_builder',
      )

   #
   def __init__(self, argparser):
      self.argparser = argparser
      self.qb = None
      # Some scripts -- like the schema upgrade script -- should be run sans
      # query build. But most of the time, callers want a qb.
      self.skip_query_builder = False

   #
   def go(self):
      '''Parse the command line arguments. If the command line parser didn't
         handle a --help or --version command, call the command processor.'''

      time_0 = time.time()

      # Read the CLI args
      self.cli_args = self.argparser()
      self.cli_opts = self.cli_args.get_opts()

      if not self.cli_args.handled:

         log.info('Welcome to the %s!'
                  % (self.cli_args.script_name,))

         # Prepare the query builder object.
         if not self.skip_query_builder:
            self.query_builder_prepare()

         # Create the Ctrl-C event if we're the master script.
         if self.cli_opts.instance_master:
            # A master scripts waits to commit the revision until all workers
            # complete. Currently, a human operator will then send the master
            # script a Ctrl-C, which triggers the event, and then the master
            # script will cleanup (and probably commit to the database and
            # release the revision table lock).
            Ccp_Script_Base.master_event = threading.Event()
            signal.signal(signal.SIGINT, Ccp_Script_Base.ctrl_c_handler)

         # Call the derived class's go function.
         self.go_main()

         # FIXME: Where is self.cli_args.close_query() ??

      log.info('Script completed in %s'
               % (misc.time_format_elapsed(time_0),))

      # If we run as a script, be sure to return happy exit code.
      return 0

   #
   def go_main(self):
      pass # Abstract.

   # ***

   #
   def query_builder_prepare(self):

      # This base class and its argument parser component only defines CLI
      # switches for the basic query_builder properties, like username, branch,
      # and revision. Currently, only ccp.py defines switches to define the
      # viewport and filters; for all other scripts, viewport and filters are
      # None.

      viewport = self.query_builder_prepare_qvp()

      filters = self.query_builder_prepare_qfs()

      self.qb = self.cli_args.begin_query(viewport, filters)
      g.assurt(id(self.qb) == id(self.cli_args.qb))

      if self.cli_args.master_worker_expected:
         if (self.cli_opts.instance_master
             or (not self.cli_opts.instance_worker)):
            indeliberate = not self.qb.cp_maint_lock_owner
            revision.Revision.revision_lock_dance(
               self.qb.db, caller='script_base.py',
               indeliberate=indeliberate)
         else:
            # This is an instance worker, so revision should be locked.
            try:
               self.qb.db.sql("LOCK TABLE revision NOWAIT")
               # Wait, what, we shouldn't be here.
               log.error(
                  'Worker bee only buzzes when other script --instance-master')
               # Hard stop.
               g.assurt(False)
            except psycopg2.OperationalError, e:
               # Good. The revision table is locked.
               pass
            # Our transaction failed so the cursor must be reset.
            self.qb.db.transaction_rollback()

   #
   def query_builder_destroy(self, do_commit):

      self.cli_args.close_query(do_commit)
      g.assurt(self.cli_args.qb is None)
      self.qb = None

   #
   def query_builder_prepare_qvp(self):
      return None

   #
   def query_builder_prepare_qfs(self):
      return None

   # ***

   #
   def finish_script_save_revision(self, group_names_or_ids,
                                         username=None,
                                         changenote=None,
                                         dont_claim_revision=False,
                                         skip_item_alerts=False):

      groups_ids = []
      g.assurt(group_names_or_ids)
      for group_name_or_id in group_names_or_ids:
         group_id, group_name = group.Many.group_resolve(self.qb.db,
                                                         group_name_or_id)
         g.assurt(group_id)
         groups_ids.append(group_id)

      g.assurt(self.cli_opts.username == self.qb.username)
      if username is None:
         username = self.qb.username
         g.assurt(username)

      if changenote is None:
         changenote = self.cli_opts.changenote
         g.assurt(changenote)

      log.debug('Saving new rev for user %s / groups: %s'
                % (self.cli_opts.username, groups_ids,))

      # NOTE: When making a new branch, self.cli_args.branch_hier does not ==
      # self.qb.branch_hier; the latter has the new branch in it, so use that.

      Item_Manager.revision_save(
         self.qb,
         self.qb.item_mgr.rid_new,
         #self.cli_args.branch_hier,
         self.qb.branch_hier,
         'localhost',
         username,
         changenote,
         groups_ids,
         activate_alerts=False,
         processed_items=None,
         reverted_revs=None,
         skip_geometry_calc=False,
         skip_item_alerts=skip_item_alerts)

      if not dont_claim_revision:
         revision.Revision.revision_claim(self.qb.db, self.qb.item_mgr.rid_new)
      # Otherwise, if a script calls code that uses CURRVAL, it didn't call
      # revision_peek but rather called revision_create, so the sequence value
      # is already okay.

      # Finalize the stack and system IDs we used.
      self.qb.item_mgr.finalize_seq_vals(self.qb.db)

   # ***

   #
   def branch_iterate(self, qb, branch_id, branch_callback, debug_limit=None):

      log.debug('branch_iterate: getting tmp db')
      # Get a new qb, and rather than clone the db, get a new connection, lest
      # we cannot commit ("Cannot commit when multiple cursors open").
      db = db_glue.new()
      username = '' # Using gia_userless, so not really needed.
      branch_hier = copy.copy(qb.branch_hier)
      qb_branches = Item_Query_Builder(db, username, branch_hier, qb.revision)

      if branch_id:
         # Find just the one.
         qb_branches.branch_hier_limit = 1

      # Indicate our non-pyserverness so that gia_userless works.
      qb_branches.request_is_local = True
      qb_branches.request_is_script = True

      # Get all active branches, regardless of user rights.
      qb_branches.filters.gia_userless = True

      # If debugging, just grab a handful of results.
      if debug_limit:
         qb_branches.use_limit_and_offset = True
         qb_branches.filters.pagin_count = int(debug_limit)
      g.assurt(qb_branches.sql_clauses is None)

      # For whatever reason, use a generator. So, in the future, when there are
      # millions of branches, this script runs peacefully.
      g.assurt(not qb_branches.db.dont_fetchall)
      qb_branches.db.dont_fetchall = True

      # Leaving as client: qb_branches.filters.min_access_level

      qb_branches.sql_clauses = branch.Many.sql_clauses_cols_all.clone()

      Query_Overlord.finalize_query(qb_branches)

      branches = branch.Many()
      branches.search_get_items(qb_branches)

      log.info('branch_iterate: found %d branches.'
               % (qb_branches.db.curs.rowcount,))

      # Skipping:
      # prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      # prog_log.log_freq = 1
      # prog_log.loop_max = qb_branches.db.curs.rowcount

      generator = branches.results_get_iter(qb_branches)

      for branch_ in generator:

         # NOTE: We don't correct self.qb, so callers should be sure not to use
         #       its branch_hier thinking it represents this branch_.

         branch_callback(branch_)

         # Skipping:
         # if prog_log.loops_inc():
         #    break

      # Skipping prog_log.loops_fin()

      generator.close()

      log.debug('branch_iterate: closing tmp db')
      qb_branches.db.close()

   # ***

   #
   @staticmethod
   def ctrl_c_handler(signum, frame):
      # E.g., ctrl_c_handler: signum: 2 / frame: None
      #  log.debug('ctrl_c_handler: signum: %s / frame: %s' % (signum, frame,))
      log.debug('ctrl_c_handler: releasing lock...')
      Ccp_Script_Base.master_event.set()

   # ***

   # This is a useful utility fcn. from CcpV1's schema-upgrade.py.
   # Prints a message and gobbles input until newline;
   # Returns True if the input is 'y'.
   def ask_yes_no(self, msg):
      resp = raw_input(msg + ' (y|[N]) ')
      yes = resp.lower() in ('y', 'yes',)
      return yes

   #
   def ask_question(self, msg, default, the_type=str):
      resp = raw_input('%s [%s]: ' % (msg, default,))
      if resp == '':
         resp = default
      else:
         try:
            resp = the_type(resp)
         except ValueError:
            log.error('ask_question: invalid input: %s' % (msg,))
            raise
      return resp

   # ***

# ***

if (__name__ == '__main__'):
   pass


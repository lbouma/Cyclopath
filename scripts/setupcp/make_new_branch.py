#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./make_new_branch.py --help
#
# Also:
#
#  $ ./make_new_branch.py |& tee 2012.08.03.make_new_branch.txt
#

'''

# 2012.08.08: Making leafy branch is finally pretty quick and easy!
#             # Script completed in 11.93 mins.

./make_new_branch.py \
   -U landonb --no-password \
   --new-branch-name 'Metc Bikeways 2012' \
   --last-merge-rid 14124 \
   --callback-class 'MetC_Bikeways_Defs'

./make_new_branch.py \
    -U landonb --no-password \
    --new-branch-name 'Metc Bikeways 2017' \
    --last-merge-rid 14124 \
    --callback-class MetC_Bikeways_Defs \
    --tile-skins bikeways \
    --owners landonb landonb \
    --arbiters landonb mekhyl torre \
    --editors terveen landonb mekhyl torre

/* 2014.07.02: Add individual member: */
SELECT cp_group_membership_new(
   cp_user_id('masstralka'),        -- IN user_id_ INTEGER
   'masstralka',                    -- IN username_ TEXT
   cp_branch_baseline_id(),         -- IN branch_baseline_id INTEGER
   1,                               -- IN rid_beg INTEGER
   cp_rid_inf(),                    -- IN rid_inf INTEGER
   cp_group_shared_id('Metc Bikeways 2012 Editors'),
                                    -- IN group_id_ INTEGER
   cp_access_level_id('editor'));   -- IN access_level_id_ INTEGER

# And update the reports file:
$ cd /ccp/dev/cycloplan_live/htdocs/reports
$ htpasswd .htpasswd 'masstralka'

'''

script_name = ('Make New Branch')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-08-03'

# ***

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

log = g.log.getLogger('make_new_branch')

# ***

import copy
from decimal import Decimal
import gc
import psycopg2
import socket
import time
import traceback

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from grax.user import User
from gwis.exception.gwis_warning import GWIS_Warning
from gwis.query_branch import Query_Branch
from item import item_base
from item import item_versioned
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_byway
from item.feat import node_traverse
from item.feat import route
from item.grac import group
from item.grac import group_membership
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

from new_item_policy_init import New_Item_Policy_Init
from node_cache_maker import Node_Cache_Maker

# *** Debug switches

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

      # Desired operation.
      self.add_argument('--update-branch', dest='update_branch',
         action='store', default=None, type=str,
         help='the name or ID of the existing branch to update')
      #
      self.add_argument('--new-branch-name', dest='new_branch_name',
         action='store', default='', type=str,
         help='the name of the new branch')
      #
      self.add_argument('--purge-branch', dest='purge_branch',
         action='store_true', default=False,
         help='delete all traces of the branch instead of creating it')

      # For new branches.
      #
      # Either:
      self.add_argument('--last-merge-rid', dest='last_merge_rid',
         action='store', default=0, type=int,
         help='the last merge revision ID, or Current if not specified')
      # or:
      self.add_argument('--is-basemap', dest='is_basemap',
         action='store_true', default=False,
         help='make a parenty branch rather than a leafy branch')

      # For new and existing branches.
      #
      self.add_argument('--callback-class', dest='callback_class',
         action='store', default='', type=str,
         help='classname of the branches module w/ process_import/_export')
      #
      self.add_argument('--tile-skins', dest='tile_skins',
         # Note: default is None, not [], so that --tile-skins all alone means
         #       to clear list of skins, so no tiles will be generated.
         action='store', default=None, type=str, nargs='*',
         help='a list of skins to use to make tiles for branch')
      #
      self.add_argument('--owners', dest='owners',
         action='store', default=[], type=str, nargs='*',
         help='a list of usernames to add to branch owners group')
      self.add_argument('--arbiters', dest='arbiters',
         action='store', default=[], type=str, nargs='*',
         help='a list of usernames to add to branch arbiters group')
      self.add_argument('--editors', dest='editors',
         action='store', default=[], type=str, nargs='*',
         help='a list of usernames to add to branch editors group')

      #
      # FIXME: Implement: Create new database from schema dump and populate
      #                   standard tables.
      """
      self.add_argument('--install-db', dest='install_db',
         action='store', default=False, type=str,
         help='install a fresh Cyclopath instead to the named database')
      # FIXME: Implement:
      self.add_argument('--user-owner', dest='user_owner',
         action='store', default=False, type=str,
         help='create the named user and make a basemap owner')
      """

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      if self.cli_opts.username == conf.anonymous_username:
         log.error('Please specify a real username (no anonymous cowards).')
         ok = False
      op_count = (  (1 if (self.cli_opts.update_branch is not None) else 0)
                  + (1 if (self.cli_opts.new_branch_name) else 0)
                  + (1 if (self.cli_opts.purge_branch) else 0))
      if op_count != 1:
            log.error(
         'Specify one: --update-branch, --new-branch-name, or --purge-branch.')
            ok = False
      if self.cli_opts.purge_branch:
         if not self.cli_opts.branch:
            log.error('Please use --branch to specify the branch to purge.')
            ok = False
      if self.cli_opts.last_merge_rid and self.cli_opts.is_basemap:
         log.error('Please specify either --last-merge-rid or --is-basemap.')
         ok = False
      return ok

# *** Make_New_Branch

class Make_New_Branch(Ccp_Script_Base):

   __slots__ = (
      'the_branch',
      'owner_group',
      'arbiter_group',
      'editor_group',
      'sid_owners',
      'sid_arbiters',
      'sid_editors',
      'current_qb',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      #
      self.the_branch = None
      # The branch group.One() object.
      self.owner_group = None
      self.arbiter_group = None
      self.editor_group = None
      # The branch group stack IDs.
      self.sid_owners = 0
      self.sid_arbiters = 0
      self.sid_editors = 0
      #
      self.current_qb = None

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

         if self.cli_opts.update_branch is None:
            if not self.cli_opts.last_merge_rid:
               # Make sure we're being run from a terminal.
               # Run from cron, $TERM is not set. Run from bash, it's 'xterm'.
               if ((os.environ.get('TERM') != "dumb")
                   and (os.environ.get('TERM') is not None)):
                  print '\nPlease confirm the last_merge_rid.\n'
                  self.cli_opts.last_merge_rid = self.ask_question(
                     'last_merge_rid',
                     revision.Revision.revision_max(self.qb.db),
                     the_type=int)
               # else, not interactive and no --last-merge-rid, so we'll
               #       just use the new revision ID that's claimed when
               #       we create the branch.

         log.debug('go_main: getting exclusive revision lock...')
         revision.Revision.revision_lock_dance(
            self.qb.db, caller='make_new_branch.py')
         g.assurt((self.qb.locked_tables == ['revision',])
                  or (self.qb.cp_maint_lock_owner))
         log.debug('go_main: database is locked.')

         # MAYBE: There seems to be an awful lot of boilerplate code here.
         self.qb.grac_mgr = Grac_Manager()
         self.qb.grac_mgr.prepare_mgr('user', self.qb)
         # The script should be run be a real developer-user.
         g.assurt(self.qb.username
                  and (self.qb.username != conf.anonymous_username))
         self.qb.user_group_id = User.private_group_id(self.qb.db,
                                                       self.qb.username)

         # Get a new revision ID.
         self.qb.item_mgr.start_new_revision(self.qb.db)
         log.debug('Got rid_new: %d' % (self.qb.item_mgr.rid_new,))

         #import pdb;pdb.set_trace()

#fixme: is there a way to setup the basemap for new Ccp installs? or in
#general? like, we do not need to clone node IDs... or, okay, there are two
#cases: one is for CcpV1->V2, like, what script to call after running SQL
#scripts; second case is fresh Ccp installs, after users initializes database,
#they will have to create groups and branch and memberships and nips...

         if self.cli_opts.update_branch is not None:
            self.update_branch()
            self.load_groups()
            self.add_members()
            self.init_newips()
         elif self.cli_opts.new_branch_name:
            self.make_groups()
            self.make_branch()
            self.add_members()
            self.init_newips()
            self.clone_nodes()
         else:
            g.assurt(self.cli_opts.purge_branch)
            self.purge_branch()

         # FIXME: Is this correct? Or should username be _script name?
         # Save the new revision and finalize the sequence numbers.
         group_names_or_ids = ['Public',]
         changenote = ('%s branch "%s"'
            % ('Updated' if (self.cli_opts.update_branch is not None)
                  else 'Created new',
               self.qb.branch_hier[0][2],))
         self.finish_script_save_revision(group_names_or_ids,
                                          self.qb.username,
                                          changenote)

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
      #   self.qb.db, caller='make_new_branch.py')

   # ***

   #
   def purge_branch(self):

      log.info('Purging all traces of the branch!')

      # This fcn. is Very Destructive. Double-check that the user isn't being
      # dumb.
      yes = self.ask_yes_no(
         'Are you really, really, REALLY sure you want to do this?')

      if yes:
         self.really_purge_branch_really()

   #
   def really_purge_branch_really(self):

      time_0 = time.time()

      log.info('For real purging all traces of the branch!')

      log.warning('FIXME: This fcn. is not tested all that well.')

      log.debug('purge_branch_: Acquiring revision table lock...')
      revision.Revision.revision_lock_dance(
         self.qb.db, caller='make_new_branch.py')

      # MAYBE: 2012.08.03: This code brute-forces the removal. It's from
      # some copy-n-paste code [lb] has been using (i.e., from a psql
      # command line) so it's not all that well tested. One concern is that
      # there might be violations of foreign key constraints...
      tables = [
         #
         'new_item_policy',
         #
         'node_byway',
         'node_endpoint',
         #
         # FIXME: Delete from route_id where route_id...
         'route',
         #
         'attribute',
         'tag', # Should be empty for leafy branches, anyway...
         'post',
         'thread',
         'annotation',
         'attribute',
         'attachment',
         'geofeature',
         'link_value',
         #
         'tag_preference',
         #
         'merge_job',
         'route_analysis_job',
         # FIXME: Delete from work_item_step where work_item_id...
         'work_item',
         #
         # MAYBE: delete from item_event_read where item_id = ...
         # MAYBE: delete from item_event_alert
         #
         'gtfsdb_cache_links',
         'gtfsdb_cache_register',
         #
         'group_revision',
         'group_membership',
         'group_',
         #
         'group_item_access',
         # FIXME: Delete from branch_conflict where branch_system_id...
         'branch',
         'item_versioned',
         #
         # MAYBE:
         #  delete from revert_event where rid_reverting/rid_victim
         #  'revision',
         #
         # MAYBE:
         #  delete from track_point where track_id...
         #  'track',
         #
         # MAYBE: tilecache tables...
         ]

      for table in tables:
         self.qb.db.sql("DELETE FROM %s WHERE branch_id = %d"
                        % (table, self.qb.branch_hier[0][0],))

      log.debug('purge_branch_: delete from %d tables in %s'
                % (len(tables),
                   misc.time_format_elapsed(time_0),))

   # ***

   #
   def load_groups(self):

      log.info('Loading groups for branch.')

      # MAYBE: Should this be a group or branch fcn, making the special group
      #        names? For now, just getting the basename...
      #
      group_basename = self.the_branch.branch_groups_basename()
      #
      special_name = '%s Owners' % (group_basename,)
      group_id, group_name = group.Many.group_resolve(self.qb.db, special_name)
      if (not group_id) or (not group_name):
         raise Exception('Group named "%s" not found.' % (special_name,))
      self.sid_owners = group_id
      #
      special_name = '%s Arbiters' % (group_basename,)
      group_id, group_name = group.Many.group_resolve(self.qb.db, special_name)
      if (not group_id) or (not group_name):
         raise Exception('Group named "%s" not found.' % (special_name,))
      self.sid_arbiters = group_id
      #
      special_name = '%s Editors' % (group_basename,)
      group_id, group_name = group.Many.group_resolve(self.qb.db, special_name)
      if (not group_id) or (not group_name):
         raise Exception('Group named "%s" not found.' % (special_name,))
      self.sid_editors = group_id
      # Skipping: "All Users", i.e., the Public user group.

   # ***

   #
   def make_groups(self):

      log.info('Making groups for new branch.')

#make same-named-as-branch group
#also make _Arbiter: group (and make making that name a fcn in the group or
#      branch class)

      # FIXME: Check that group names do not exist (probably do same for branch
      # name, too).

      # FIXME: We don't use this group, really, I think all the branchy users
      # are Arbiters, at least that's how it's setup... and individual users
      # get editor access to the branch, anyway, right? Argh...

      common_row = {
         # From item_versioned
         'system_id'          : None, # assigned later
         'branch_id'          : None, # assigned later
         'version'            : 0,
         'deleted'            : False,
         'reverted'           : False,
         # MAGIC_NUMBER: Starting at rid 1.
         'valid_start_rid'    : 1,
         'valid_until_rid'    : None,
         # From groupy_base
         #'group_id'           : new_group_id,
         #'group_name'         : self.cli_opts.new_branch_name,
         # From group
         'access_scope_id'    : Access_Scope.shared,
         }

# FIXME: Make sure these groups do not already exist.

      common_row.update({
         'stack_id'    : self.qb.item_mgr.get_next_client_id(),
         'name'        : '%s Owners' % self.cli_opts.new_branch_name,
         'description' : '%s Owners' % (self.cli_opts.new_branch_name,),
         })
      self.owner_group = group.One(qb=self.qb, row=common_row)
      self.make_groups_group(self.owner_group)
      self.sid_owners = self.owner_group.stack_id

      common_row.update({
         'stack_id'    : self.qb.item_mgr.get_next_client_id(),
         'name'        : '%s Arbiters' % self.cli_opts.new_branch_name,
         'description' : '%s Arbiters' % (self.cli_opts.new_branch_name,),
         })
      self.arbiter_group = group.One(qb=self.qb, row=common_row)
      self.make_groups_group(self.arbiter_group)
      self.sid_arbiters = self.arbiter_group.stack_id

      common_row.update({
         'stack_id'    : self.qb.item_mgr.get_next_client_id(),
         'name'        : '%s Editors' % self.cli_opts.new_branch_name,
         'description' : '%s Editors' % (self.cli_opts.new_branch_name,),
         })
      self.editor_group = group.One(qb=self.qb, row=common_row)
      self.make_groups_group(self.editor_group)
      self.sid_editors = self.editor_group.stack_id

   #
   def make_groups_group(self, the_group):
      if self.stack_id < 0:
         client_id = self.stack_id
      else:
         client_id = None
      the_group.stack_id_correct(self.qb)
      g.assurt(the_group.fresh)
      log.debug('make_groups_group: clearing item_cache')
      self.qb.item_mgr.item_cache_reset()
      self.qb.item_mgr.item_cache_add(the_group, client_id)
      prepared = self.qb.grac_mgr.prepare_item(self.qb,
         the_group, Access_Level.editor, ref_item=None)
      g.assurt(prepared)
      the_group.version_finalize_and_increment(self.qb,
                              self.qb.item_mgr.rid_new)
      the_group.save(self.qb, self.qb.item_mgr.rid_new)

   # ***

   #
   def get_branch_callbacks(self):

      # The callback_class is, e.g., 'MetC_Bikeways_Defs'.
      # E.g.,
      #  merge.branches.metc_bikeways_defs:MetC_Bikeways_Defs:process_import
      #  merge.branches.metc_bikeways_defs:MetC_Bikeways_Defs:process_export
      import_callback = ''
      export_callback = ''
      if self.cli_opts.callback_class:
         import_callback = ('merge.branches.%s:%s:process_import'
                            % (self.cli_opts.callback_class.lower(),
                               self.cli_opts.callback_class,))
         export_callback = ('merge.branches.%s:%s:process_export'
                            % (self.cli_opts.callback_class.lower(),
                               self.cli_opts.callback_class,))

      return import_callback, export_callback

   #
   def get_tile_skin_names(self):
      # We default to _not_ rastering raster tiles.
      tile_skins = None
      if self.cli_opts.tile_skins:
         for skin_name in self.cli_opts.tile_skins:
            g.assurt(',' not in skin_name)
         tile_skins = ','.join(self.cli_opts.tile_skins)
      return tile_skins

   # ***

   #
   def update_branch(self):

      #branch_id = branch.Many.public_branch_id(self.qb)
      #revision_id = self.qb.item_mgr.rid_new
      #rev = revision.Historic(revision_id, allow_deleted=False)
      rev = revision.Current()
      (branch_id, branch_hier) = branch.Many.branch_id_resolve(self.qb.db,
                           self.cli_opts.update_branch, branch_hier_rev=rev)

      # Be sure to get the item_stack table or, when we save, access_style_id
      # won't be set and our not null constraint will complain.
      self.qb.filters.include_item_stack = True

      branches = branch.Many()
      branches.search_by_stack_id(branch_id, self.qb)

      if len(branches) != 1:
         raise Exception('Branch named "%s" not found.'
                         % (self.cli_opts.update_branch,))

      g.assurt(len(branches) == 1)
      the_branch = branches[0]

      # Currently, all branches are 'permissive'.
      g.assurt(the_branch.access_style_id == Access_Style.permissive)

      #

      import_callback, export_callback = self.get_branch_callbacks()

      if ((import_callback or export_callback)
          or (self.cli_opts.tile_skins is not None)):

         if import_callback or export_callback:

            log.debug('Overwriting import_callback: was: "%s" / now: "%s"'
                      % (the_branch.import_callback, import_callback,))
            the_branch.import_callback = import_callback

            log.debug('Overwriting export_callback: was: "%s" / now: "%s"'
                      % (the_branch.export_callback, export_callback,))
            the_branch.export_callback = export_callback

         if self.cli_opts.tile_skins is not None:

            tile_skins = self.get_tile_skin_names()
            log.debug('Overwriting tile_skins: was: "%s" / now: "%s"'
                      % (the_branch.tile_skins, tile_skins,))
            the_branch.tile_skins = tile_skins

         # MAYBE: Call prepare_and_save_item? Or just do it ourselves?
         #        NOTE: grac_mgr.prepare_existing_from_stack_id calls
         #              validize, which calls groups_access_load_from_db...
         #              which we just call ourselves. I think this works.

         is_new_item = False
         the_branch.validize(self.qb, is_new_item,
                             item_base.One.dirty_reason_item_user,
                             ref_item=None)

         rid_new = self.qb.item_mgr.rid_new
         the_branch.version_finalize_and_increment(self.qb, rid_new)
         the_branch.save(self.qb, rid_new)

      self.the_branch = the_branch

   # ***

   #
   def make_branch(self):

      # FIXME: If user specifies --branch, we should make the new branch
      # descend from the specified branch.

      import_callback, export_callback = self.get_branch_callbacks()

      tile_skins = self.get_tile_skin_names()

      # FIXME: Ensure that name is unique! I.e., check the new branch name and
      #        check that the required group names are available.

      if self.cli_opts.is_basemap:
         parent_id = None
      else:
         parent_id = self.qb.branch_hier[0][0]

      last_merge_rid = self.cli_opts.last_merge_rid or self.qb.item_mgr.rid_new

      log.info('Making new branch: "%s" / parent_id: %s / last_merge_rid: %s'
               % (self.cli_opts.new_branch_name, parent_id, last_merge_rid,))

      new_branch = branch.One(
         qb=self.qb,
         row={
            # item_versioned
            'system_id'           : None, # assigned later
            'branch_id'           : None, # assigned later
            'stack_id'            : self.qb.item_mgr.get_next_client_id(),
            'version'             : 0,
            'deleted'             : False,
            'reverted'            : False,
            'name'                : self.cli_opts.new_branch_name,
            'valid_start_rid'     : None,
            'valid_until_rid'     : None,
            # branch
            'parent_id'           : parent_id,
            'last_merge_rid'      : last_merge_rid,
            'conflicts_resolved'  : True,
            'import_callback'     : import_callback,
            'export_callback'     : export_callback,
            'tile_skins'          : tile_skins,
            # Skipping: coverage_area. See gen_tilecache_cfg.py.
            }
         )

      # Make the user who's running the script the branch owner.
      # And give the new branch groups access, too.
      g.assurt(self.qb.user_group_id)
      # Also make an entry for the Public, so it's easy to set this.
      # MAYBE: Maybe these are the groups and there are no other choices?
      # That would really simply the client and other operations involving
      # editing GIA records...
      pub_grp_id = group.Many.public_group_id(self.qb.db)
      #
      target_groups = {
         self.qb.user_group_id   : Access_Level.owner,
         self.sid_editors        : Access_Level.editor,
         self.sid_arbiters       : Access_Level.arbiter,
         self.sid_owners         : Access_Level.owner,
         pub_grp_id              : Access_Level.denied,
         }

      # All branches are access-style 'permissive'. Cyclopath might some day
      # support, e.g., 'usr_choice', on sub-branches, i.e., so an agency can
      # let their users create their own branches. But right now, since
      # branches are pretty specially wired into the system and require special
      # scripts to setup and maintain, we'll just stick with 'permissive'.
      new_branch.access_style_id = Access_Style.permissive
      # access_infer_id is set from item_stack.save_core.get_access_infer().

      # NOTE: We set the valid_start_rid to 1 so that the branch is viewable
      #       at historic revisions, i.e., that the user sees what the parent
      #       branch looked like back then. If we didn't do this, it makes some
      #       operations fail, i.e., valid_start_rid cannot be greater than
      #       last_merge_rid, so importing fails if the user cannot see the
      #       branch at the last_merge_rid.
      # Skipping: self.qb.item_mgr.rid_new.
      first_rid = 1
      new_branch.prepare_and_save_item(self.qb,
            target_groups=target_groups,
            rid_new=first_rid,
            ref_item=None)

      log.info('Created branch: %s (%d)'
               % (new_branch.name, new_branch.stack_id,))

      # Make the branch_hier.
      revision_id = self.qb.item_mgr.rid_new
      rev = revision.Historic(revision_id, allow_deleted=False)
      (branch_id, branch_hier) = branch.Many.branch_id_resolve(self.qb.db,
                                 new_branch.stack_id, branch_hier_rev=rev)
      self.qb.branch_hier_set(branch_hier)
      # not needed: self.qb.revision = branch_hier[0][1]

      # MEH: Set self.cli_args.branch_hier? No one should be using branch_hier
      # from cli_args, so, why bother... let the assurts fly instead.
      # Whatever: self.cli_args.branch_hier = branch_hier

      self.the_branch = new_branch

   # ***

   #
   def add_members(self):

      log.info('Adding branch user group memberships.')

      # MAYBE: Use this script to update the public basemap after the
      #        v1-v2 upgrade? i.e., don't create group memberships in the
      #        upgrade scripts!

      # Group Memberships are saved with the basemap branch ID. We don't need
      # to clone the db, and if we did, we'd want to relock the 'revision'
      # table (i.e., grac_mgr expects: db.locked_tables == ['revision',]).
      basemap_qb = self.qb.clone(db_clone=False)
      # Use the basemap branch. At the Current revision.
      parentest = basemap_qb.branch_hier[-1]
      branch_hier = [(parentest[0], revision.Current(), parentest[2],),]
      basemap_qb.branch_hier_set(branch_hier)

      common_row = {
         # From item_versioned
         'system_id'       : None, # assigned later
         'branch_id'       : None, # assigned later
         'version'         : 0,
         'deleted'         : False,
         'reverted'        : False,
         'name'            : '',
         'valid_start_rid' : 1,
         'valid_until_rid' : None,
         # From groupy_base
         #'group_name'     : None,#self.cli_opts.new_branch_name,
         # From group_membership
         'opt_out'         : False,
         #'group_desc'     : '',
         #'group_scope'    : Access_Scope.shared,
         'access_level_id' : Access_Level.editor,
         }

      usernames = list(set(self.cli_opts.editors
                           + self.cli_opts.arbiters
                           + self.cli_opts.owners))
      self.add_members_to_group(basemap_qb, common_row,
                                self.sid_editors, usernames)

      usernames = list(set(self.cli_opts.arbiters
                           + self.cli_opts.owners))
      self.add_members_to_group(basemap_qb, common_row,
                                self.sid_arbiters, usernames)

      usernames = list(set(self.cli_opts.owners))
      self.add_members_to_group(basemap_qb, common_row,
                                self.sid_owners, usernames)

   #
   def add_members_to_group(self, basemap_qb, common_row,
                                  group_sid, usernames):

      log.debug('add_members_to_group: group_sid: %d.' % (group_sid,))

      grp_mmbs = group_membership.Many()
      grp_mmbs.search_by_group_id(basemap_qb, group_sid)

      group_uids = {}
      for gm in grp_mmbs:
         group_uids[gm.user_id] = gm

      for uname in usernames:
         try:
            user_id = User.user_id_from_username(basemap_qb.db, uname)
         except GWIS_Warning, e:
            user_id = None
            log.warning('add_members_to_group: no such user: %s' % (uname,))
         if user_id:
            if not (user_id in group_uids):
               common_row.update({
                  'stack_id'  : basemap_qb.item_mgr.get_next_client_id(),
                  'group_id'  : group_sid,
                  'user_id'   : user_id,
                  'username'  : uname,
                  })
               new_mmbrship = group_membership.One(qb=basemap_qb,
                                                   row=common_row)
               self.add_members_save_mmbrship(basemap_qb, new_mmbrship)
            else:
               existing_gm = group_uids[user_id]
               g.assurt(existing_gm.access_level_id == Access_Level.editor)
               log.info('add_members: user already member: %s in %s'
                        % (existing_gm.username, existing_gm.group_name,))

   #
   def add_members_save_mmbrship(self, basemap_qb, new_mmbrship):
      # See also: cp_group_membership_new.
      if self.stack_id < 0:
         client_id = self.stack_id
      else:
         client_id = None
      new_mmbrship.stack_id_correct(basemap_qb)
      g.assurt(new_mmbrship.fresh)
      log.debug('add_members_save_mmbrship: clearing item_cache')
      basemap_qb.item_mgr.item_cache_reset()
      basemap_qb.item_mgr.item_cache_add(new_mmbrship, client_id)
      prepared = basemap_qb.grac_mgr.prepare_item(basemap_qb,
         new_mmbrship, Access_Level.editor, ref_item=None)
      g.assurt(prepared)
      new_mmbrship.version_finalize_and_increment(basemap_qb,
                                 basemap_qb.item_mgr.rid_new)
      new_mmbrship.save(basemap_qb, basemap_qb.item_mgr.rid_new)

   # ***

   #
   def reset_current_qb(self):

      self.current_qb = self.qb.clone(db_clone=False)
      branch_hier = copy.copy(self.current_qb.branch_hier)
      branch_hier[0] = (
         branch_hier[0][0], revision.Current(), branch_hier[0][2],)
      self.current_qb.branch_hier_set(branch_hier)

   #
   def init_newips(self):

      log.info('Initializing new item policies.')

      self.reset_current_qb()

      nipi = New_Item_Policy_Init()

      nipi.install_nips(self.current_qb, policy_profile='standard')

   # ***

   #
   def clone_nodes(self):

      log.info('Cloning node data from parent branch.')

      # HACK: Is this cheating? Whatever, it works fine... maybe it's just
      #       clever.

      # Create an instance of the node maker script but set it up sneakily and
      # don't call it's go_main.

      ncm = Node_Cache_Maker()
      ncm.cli_args = ncm.argparser()
      # This doesn't work: ncm.cli_opts = ncm.cli_args.get_opts()
      g.assurt(self.current_qb is not None)
      ncm.qb = self.current_qb
      # Note that ncm.cli_args.qb does not exist because we haven't triggered
      # ncm.query_builder_prepare().
      ncm.cli_args.branch_id = self.qb.branch_hier[0][0]

      # MEH: propagate debug_prog_log to ncm; for now, you can just edit it's
      #      debug_prog_log.

      if not self.cli_opts.is_basemap:
         # Don't call create_tables:
         # NO: ncm.create_tables()
         #     self.reset_current_qb()
         #     ncm.qb = self.current_qb
         # FIXME/CAVEAT: If your new branch has an old last_merge_rid, using
         #               quick_nodes probably doesn't make sense.
         #               Should we check last_merge_rid and maybe do full node
         #               rebuild? Or let the caller call node_cache_maker.py?
         #               See upgrade_ccpv1-v2.sh: it calls make_new_branch.ph
         #               and then node_cache_maker.py...
         ncm.quick_nodes()
         # This one takes a five minutes...
         ncm.add_internals()
      else:
         # If a basemap, there is not geometry yet, so no nodes.
         # But if this is a rebuild of the public basemape after a V1->V2
         # upgrade...
         # FIXME: How do you detect this? Expecting new_branch_name and not
         # using --branch=0 so maybe cli_opts needs a tweaking.
         # FIXME: Implement this if...
         if False:
            ncm.make_nodes()
            ncm.add_internals()
            ncm.update_route()

   # ***

# ***

if (__name__ == '__main__'):
   make_new_branch = Make_New_Branch()
   make_new_branch.go()

# ***
#
# 2012.08.03: [lb]: These are the raw commands from a copy and paste file I've
# been using up until creating the make_new_branch.py script. You *should* (if
# these comments are kept current) be able to run the commands below to achieve
# what's being done above. You'll find these commands useful not just for unit
# testing, but also if you need to recreate part of a branch, i.e., maybe you
# already have a branch but you want to redo the node_endpoint table, well, the
# examples below show you how to call the node_cache_maker script for the
# basemap and branchier branches.

"""

# *** The basics.

export pyserver=$cp/pyserver
export dest_db=ccpv2
export runic=$cp/scripts/setupcp

# Restart Apache.
# E.g., sudo service httpd restart
re

# *** The one-time public basemap scripts you gotta run.

# If you haven't done so already, build the node tables.
# Circa 2012.08.01:
#   --populate-nodes    133005 loops took 47.48 mins. (+5 minutes for commit)
#   --add-internals     154942 loops took 2.84 mins.
#   --update-route      102581 loops took 0.39 mins.
cd $runic
./node_cache_maker.py --create-tables
./node_cache_maker.py --branch 0 \
                      --populate-nodes --add-internals --update-route

# If you haven't done so already, create the new item policies for the basemap.
# Skipping: echo "DELETE FROM minnesota.new_item_policy;" \
#           | psql -U postgres -d $dest_db --no-psqlrc
cd $runic
./new_item_policy_init.py \
   -U landonb --no-password \
   -b 0 \
   --profile='standard' \
   -m "Create new item policies for basemap."

# If you haven't done so already, add the merge_job callbacks for the basemap.
cd $pyserver
./ccp.py -U landonb --no-password \
   -u -t branch \
   -b 0 \
   -m "Add import callback to branch." \
   -e import_callback \
      "merge.branches.metc_bikeways_defs:Public_Basemap_Defs:process_import" \
   -e export_callback \
      "merge.branches.metc_bikeways_defs:Public_Basemap_Defs:process_export"

# *** Make the new branch.

# Add new branch
cd $pyserver
./ccp.py -U landonb --no-password \
  -f request_is_a_test 0 \
  -c -t branch \
  -m "Make Branch: Metc Bikeways 2012" \
  -e name "Metc Bikeways 2012" \
  -e last_merge_rid 14124

# It can take upwards of an hour to *calculate* the node table data, but since
# a new branch has the same data as its parent, we can just copy it, which
# should take only a matter of minutes.
# Skipping:
#   ./node_cache_maker.py --branch "Metc Bikeways 2012" \
#                         --populate-nodes --add-internals --update-route
cd $runic
./node_cache_maker.py --branch "Metc Bikeways 2012" \
                      --quick-nodes --purge-rows
./node_cache_maker.py --branch "Metc Bikeways 2012" \
                      --add-internals --update-route
# 2012.08.08: The branch is already populated, so we need to rebuild...
cd $runic
./node_cache_maker.py --branch "Metc Bikeways 2012" \
                      --populate-nodes --add-internals --update-route

# Make a group for the branch.
# NOTE: Use valid_start_rid = 1, so users can see
#       revisions before the current revision (i.e.,
#       the current revision is > last_merge_rid, so
#       user's wouldn't be able to import because they
#       can't see last_merge_rid). We could just set
#       valid_start_rid to last_merge_rid, but that's
#       also restrictive, so we set it to 1; in most
#       cases, the parent branch is the public basemap,
#       so this is appropriate, and for other cases, we'll
#       still check the user's access to the parent branch.
# 2012.08.13: Deprecated. See well-known group names, below.
#cd $pyserver
#./ccp.py -U landonb --no-password \
#  -f request_is_a_test 0 \
#  -c -t group \
#  -m "Make Group: Metc Bikeways 2012" \
#  -e name "Metc Bikeways 2012" \
#  -e access_scope_id 2 \
#  -e valid_start_rid 1 \
#  -e description "Metc Bikeways 2012"

# Make a group_item_access record to give the new group editor access to the
# new branch.
# FIXME: This makes just one new GIA record; implement acl_grouping?
# 2012.08.13: Deprecated. See well-known group names, below.
#cd $pyserver
#./ccp.py -U landonb --no-password \
#  -f request_is_a_test 0 \
#  -u -t branch \
#  -b "Metc Bikeways 2012" \
#  -f filter_by_text_exact "Metc Bikeways 2012" \
#  -m "Grant Access: Metc Bikeways 2012 - Group <=> Branch." \
#  --gia group_name "Metc Bikeways 2012" \
#  --gia access_level_id 3 \
#  --gia valid_start_rid  1

# 2012.08.08: Adding well-known group names.

./ccp.py -U landonb --no-password \
  -f request_is_a_test 0 \
  -c -t group \
  -m "Make Group: Metc Bikeways 2012 Arbiters" \
  -e name "Metc Bikeways 2012 Arbiters" \
  -e access_scope_id 2 \
  -e valid_start_rid 1 \
  -e description "Metc Bikeways 2012 Arbiters"
./ccp.py -U landonb --no-password \
  -f request_is_a_test 0 \
  -c -t group \
  -m "Make Group: Metc Bikeways 2012 Editors" \
  -e name "Metc Bikeways 2012 Editors" \
  -e access_scope_id 2 \
  -e valid_start_rid 1 \
  -e description "Metc Bikeways 2012 Editors"
#
./ccp.py -U landonb --no-password \
  -f request_is_a_test 0 \
  -u -t branch \
  -b "Metc Bikeways 2012" \
  -f filter_by_text_exact "landonb" \
  -m "Grant Branch Access: landonb" \
  --gia group_name "landonb" \
  --gia access_level_id 1 \
  --gia valid_start_rid 1
./ccp.py -U landonb --no-password \
  -f request_is_a_test 0 \
  -u -t branch \
  -b "Metc Bikeways 2012" \
  -f filter_by_text_exact "Metc Bikeways 2012 Arbiters" \
  -m "Grant Branch Access: Metc Bikeways 2012 Arbiters" \
  --gia group_name "Metc Bikeways 2012 Arbiters" \
  --gia access_level_id 2 \
  --gia valid_start_rid 1
./ccp.py -U landonb --no-password \
  -f request_is_a_test 0 \
  -u -t branch \
  -b "Metc Bikeways 2012" \
  -f filter_by_text_exact "Metc Bikeways 2012 Editors" \
  -m "Grant Branch Access: Metc Bikeways 2012 Editors" \
  --gia group_name "Metc Bikeways 2012 Editors" \
  --gia access_level_id 3 \
  --gia valid_start_rid 1

# *** Setup the new branch's new item policy.

cd $runic
./new_item_policy_init.py \
   -U landonb --no-password \
   -b "Metc Bikeways 2012" \
   --profile='standard' \
   -m "Create new item policies for branch."

# *** Add the merge_job callbacks.

cd $pyserver
./ccp.py -U landonb --no-password \
   -u -t branch \
   -b "Metc Bikeways 2012" \
   -f filter_by_text_exact "Metc Bikeways 2012" \
   -m "Add import callback to branch." \
   -e import_callback \
      "merge.branches.metc_bikeways_defs:MetC_Bikeways_Defs:process_import" \
   -e export_callback \
      "merge.branches.metc_bikeways_defs:MetC_Bikeways_Defs:process_export"

# *** Add users to the new group.

# FIXME: group_membership adds duplicates without checking first...
# so
# DELETE FROM group_membership where group_id = (
#   SELECT stack_id FROM group_
#   WHERE name = 'Metc Bikeways 2012' AND access_scope_id = 2
#   );
# SELECT * FROM group_membership
# WHERE group_id = (SELECT stack_id FROM group_
#                   WHERE name = 'Metc Bikeways 2012' AND access_scope_id = 2);

## Add owners to the MetC group.
#cd $pyserver
#for uname in    \
#    "landonb"   \
#    "mludwig"   \
#    ; do
#  ./ccp.py -U landonb --no-password \
#    -f request_is_a_test 0 \
#    -c -t group_membership \
#    -m "Add users to group: Metc Bikeways 2012 Owners." \
#    -e name "" \
#    -e access_level_id 1 \
#    -e valid_start_rid 1 \
#    -e opt_out 0 \
#    -e username ${uname} \
#    -e group_name "Metc Bikeways 2012 Owners"
#done

# Add arbiters to the MetC group.
cd $pyserver
for uname in      \
    "jane"        \
    "john"        \
    ; do
  ./ccp.py -U landonb --no-password \
    -f request_is_a_test 0 \
    -c -t group_membership \
    -m "Add users to group: Metc Bikeways 2012 Arbiters." \
    -e name "" \
    -e access_level_id 2 \
    -e valid_start_rid 1 \
    -e opt_out 0 \
    -e username ${uname} \
    -e group_name "Metc Bikeways 2012 Arbiters"
done

#########################################################################

# FIXME: What about building tiles for the branch?
#        What about setting up cron jobs or whatnots?

# 2012.08.08: This is old code from the cut-n-paste file but I haven't built
#             tiles in a long, long time.
# This does not work. Trying to oversudo myself, apparently. =)
#   sudo -u www-data \
#     INSTANCE=minnesota nohup \
#     ./tilecache_update.py -N -A -L -Z | tee tcupdate.txt 2>&1 &
# Make sure apache can write to our file.
# FIXME: File path. Should be cp/?
touch $cp_dev/mapserver/tcupdate.txt
chmod 666 $cp_dev/mapserver/tcupdate.txt
# NOTE: You cannot sudo -u ... nohup, so make 'em separate operations.
# FIXME: make this $httpd_user
sudo su - www-data
cd $cp_dev/mapserver
INSTANCE=minnesota nohup ./tilecache_update.py -N -A -L -Z \
                              | tee tcupdate.txt 2>&1 &
INSTANCE=minnesota nohup ./tilecache_update.py -a \
                              | tee tcupdatE.txt 2>&1 &

"""


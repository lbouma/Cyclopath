#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./link_attributes_populate.py --help
#
# Also:
#
#  $ ./link_attributes_populate.py |& tee 2013.03.26.link_attrs_pop.txt
#

# BUG nnnn: Populate new Link_Value-Attributes.
#
# See: 201-apb-88-aattrs-fromtbls.sql
#        '/byway/rating'
#        '/post/rating'
#        '/byway/aadt'
#        '/item/alert_email'
#        '/tag/preference'
# 
# - make new link_values and group_item_access records, etc.
# - update pyserver code to read/write from these records
# - obsolete the old school attributes.

script_name = ('Populate Link Attributes from CcpV1')
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

log = g.log.getLogger('link_attrs_pop')

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

debug_skip_drop_tables = False
debug_skip_drop_tables = True

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
   def prepare(self):
      Ccp_Script_Args.prepare(self)

   #
   def verify_handler(self):
      ok = Ccp_Script_Args.verify_handler(self)
      return ok

# *** Link_Attributes_Populate

class Link_Attributes_Populate(Ccp_Script_Base):

   __slots__ = (
      'attr_alert_email',
      'group_names_or_ids',
      'stats',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      #
      self.attr_alert_email = None
      self.group_names_or_ids = set()
      #
      self.stats = dict()
      self.stats['total_new_links'] = 0

   # ***

   #
   def go_main(self):

      # Skipping: Ccp_Script_Base.go_main(self)

      do_commit = False

      try:

         log.debug('go_main: getting exclusive revision lock...')
         revision.Revision.revision_lock_dance(
            self.qb.db, caller='link_attributes_populate__go_main')
         log.debug('go_main: database is locked.')

         # Get a new revision ID.
         self.qb.item_mgr.start_new_revision(self.qb.db)
         log.debug('Got rid_new: %d' % (self.qb.item_mgr.rid_new,))

         # Get the item watcher attribute.
         internal_name = '/item/alert_email'
         self.attr_alert_email = attribute.Many.get_system_attr(
                                          self.qb, internal_name)
         g.assurt(self.attr_alert_email is not None)

         self.setup_links()

         if not debug_skip_drop_tables:
            self.cleanup_ccpv1()

         # Save the new revision and finalize the sequence numbers.
         # No: group_names_or_ids = ['Public',]
         #     use the actual users' group IDs
         #     also, revision.py has an assert that fires because
         #     nothing that was saved is public.
         log.debug('go_main: saving rev %d for %d groups'
                   % (self.qb.item_mgr.rid_new,
                      len(self.group_names_or_ids),))
         changenote = 'Converted item watchers from CcpV1'
         self.finish_script_save_revision(self.group_names_or_ids,
                                          username='_script',
                                          changenote=changenote)

         log.debug('go_main: created %d new links'
                   % (self.stats['total_new_links'],))

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   # ***

   #
   def setup_links(self):

      # First count some table rows and double-check the upgrade so far. We
      # want to be confident we're getting all the CcpV1 records and making
      # appropriate CcpV2 records.
      try:
         self.setup_links_sanity_check()
      except:
         log.warning('setup_links: old CcpV1 already dropped; moving on...')

      # Now get the unique set of usernames. We're going to create items owned
      # by certain users, and we'll need to setup resources for each user, like
      # the query_builder and the grac_mgr.

      usernames_sql = (
         """
         SELECT DISTINCT (username)
         FROM item_watcher_bug_nnnn
         ORDER BY username
         """)

      # NOTE: We're not bothering with dont_fetchall.
      #       There are only a few hundred rows...

      rows = self.qb.db.sql(usernames_sql)

      log.debug('setup_links: found %d unique users with watchers'
                % (len(rows),))

      if not rows:
         log.error('setup_links: nothing found')
         g.assurt(false)

      for row in rows:

         username = row['username']

         # Hmm. There's no user.One() class to load a user. It's all custom.
         user_rows = self.qb.db.sql(
            "SELECT login_permitted FROM user_ WHERE username = %s"
            % (self.qb.db.quoted(username),))
         g.assurt(len(user_rows) == 1)
         if not user_rows[0]['login_permitted']:
            log.debug('setup_links: skipping: !user_.login_permitted: %s'
                      % (username,))
            continue

         log.verbose2('setup_links: processing username: %s' % (username,))

         g.assurt(isinstance(self.qb.revision, revision.Current))
         rev_cur = revision.Current()

         user_qb = Item_Query_Builder(
            self.qb.db, username, self.qb.branch_hier, rev_cur)
         user_qb.grac_mgr = Grac_Manager()
         user_qb.grac_mgr.prepare_mgr('user', user_qb)
         #
         g.assurt(
            user_qb.username and (user_qb.username != conf.anonymous_username))
         user_qb.user_group_id = User.private_group_id(user_qb.db, 
                                                       user_qb.username)
         #
         # Use the same item_mgr so we pull client stack IDs from the same
         # pool.
         user_qb.item_mgr = self.qb.item_mgr

         # Finalize the query. This sets revision.gids so it'll include the
         # user's private group (and the anonymous and All Users groups).
         Query_Overlord.finalize_query(user_qb)

         # We can still get deleted regions and add links for them.
         user_qb.revision.allow_deleted = True

         # Finally, update the database. Oi, there's a lot of setup!
         self.setup_links_for_user(user_qb)

         # The way Item_Query_Builder works, it usually wires the branch_hier
         # revision to the revision revision.
         g.assurt(self.qb.branch_hier[0][1] == rev_cur)
         # We'll reuse the branch_hier so clear this user's gids.
         self.qb.branch_hier[0][1].gids = None

   #
   def setup_links_for_user(self, user_qb):

      # Skipping: branch_id, since we only run on the basemap.
      users_watchers_sql = (
         """
         SELECT stack_id, enable_email, enable_digest
         FROM item_watcher_bug_nnnn
         WHERE username = %s
         """ % (user_qb.db.quoted(user_qb.username),))

      rows = user_qb.db.sql(users_watchers_sql)

      log.verbose2('setup_links_for_user: found %d watchers'
                  % (len(rows),))

      if not rows:
         log.error('setup_links_for_user: nothing found')
         g.assurt(false)

      skipped_cnt = 0
      missing_cnt = 0
      for row in rows:
         if row['enable_email']:
            rhs_item = self.setup_user_watcher_get_rhs(user_qb,
                                                       row['stack_id'])
            if rhs_item is not None:
               self.setup_user_watcher(user_qb, rhs_item, row['enable_digest'])
            else:
               log.debug('setup_links_for_user: bad stack ID %d for user: %s'
                         % (row['stack_id'], user_qb.username,))
               missing_cnt += 1
         else:
            # This is False only because of CcpV1's watch_region.notify_email.
            skipped_cnt += 1
      if skipped_cnt:
         log.debug('setup_links_for_user: skipped %d watchers for user: %s'
                   % (skipped_cnt, user_qb.username,))
      new_count = len(rows) - (skipped_cnt + missing_cnt)
      if not new_count:
         log.debug('setup_links_for_user: did nothing for user: %s'
                      % (user_qb.username,))
      else:
         log.debug('setup_links_for_user: made %d links for user: %s'
                      % (new_count, user_qb.username,))

   #
   def setup_user_watcher(self, user_qb, rhs_item, enable_digest):

      # This is the logic from CcpV1's Watch_Region_Detail_Panel.mxml.
      #
      #   if enable_email:
      #      if enable_digest:
      #         value = 'Daily';
      #      else:
      #         value = 'Immediate';
      #   else:
      #      value = 'Never';
      #
      # In CcpV1, if the user chooses 'Never' from the watched regions panel,
      # we set user_.enable_email and user_.enable_wr_digest false. Otherwise,
      # enable_email is true and enable_wr_digest is false for immediate email,
      # or true for emailing at the end of the day.
      #
      # There's also watch_region.notify_email, which allows the user to turn
      # their private watch region watchers on and off.
      #
      # In CcpV2, these user_ columns are renamed:
      #   enable_wr_digest => enable_watchers_digest
      #   enable_wr_email => enable_watchers_email
      #   enable_email => enable_email

      # In the item_watcher_bug_nnnn table, enable_email is TRUE for
      # watchers from region_watcher and thread_watcher, and it's set
      # to watch_region.enable_email for the rest. And enable_digest is the
      # same for each user and matches their user_.enable_watchers_digest.

      if not enable_digest:
         value_integer = Watcher_Frequency.immediately
      else:
         #value_integer = Watcher_Frequency.daily
         value_integer = Watcher_Frequency.nightly

      client_id = user_qb.item_mgr.get_next_client_id()

      new_link = link_value.One(
         qb=user_qb,
         row={
            # *** from item_versioned:
            'system_id'             : None, # assigned later
            'branch_id'             : user_qb.branch_hier[0][0],
            'stack_id'              : client_id,
            'version'               : 0,
            'deleted'               : False,
            'reverted'              : False,
            'name'                  : '', # FIXME: Is this right?
            #'valid_start_rid'      : # assigned by 
            #'valid_until_rid'      : #   version_finalize_and_increment
            # NOTE: We don't set valid_start_rid any earlier, like how
            #       some items are assigned valid_start_rid=1 to get
            #       around certain issues.
            # *** from link_value:
            'lhs_stack_id'          : self.attr_alert_email.stack_id,
            'rhs_stack_id'          : rhs_item.stack_id,
            # The item type IDs are saved to the group_item_access table.
            'link_lhs_type_id'      : self.attr_alert_email.item_type_id,
            # NOTE: Using real_item_type_id. See search_by_stack_id.
            #       This is because we just had a stack ID but didn't
            #       know the item type of the stack ID.
            'link_rhs_type_id'      : rhs_item.real_item_type_id,
            'value_boolean'         : None,
            'value_integer'         : value_integer,
            'value_real'            : None,
            'value_text'            : None,
            'value_binary'          : None,
            'value_date'            : None,
            }
         )

      log.verbose2('setup_user_watcher: new_link: %s' % (new_link,))

      g.assurt(new_link.groups_access is None)
      new_link.stack_id_correct(user_qb)
      g.assurt(new_link.fresh)
      log.verbose('setup_user_watcher: not clearing item_cache')
      # NO: user_qb.item_mgr.item_cache_reset()
      user_qb.item_mgr.item_cache_add(new_link, client_id)
      user_qb.item_mgr.item_cache_add(self.attr_alert_email)
      user_qb.item_mgr.item_cache_add(rhs_item)

      prepared = user_qb.grac_mgr.prepare_item(user_qb,
         new_link, Access_Level.editor, ref_item=None)
      g.assurt(prepared)
      log.verbose2(' >> prepare_item: %s' % (new_link,))

      log.verbose2(' >> groups_access/1: %s' % (new_link.groups_access,))

      new_link.version_finalize_and_increment(
                  user_qb, user_qb.item_mgr.rid_new)
      log.verbose2(' >> version_finalize_and_increment: %s' % (new_link,))

      # item.style_change = Access_Infer.usr_editor
      # self.groups_access_style_change(user_qb)
      # log.verbose2(' >> groups_access_style_change: %s' % (new_link,))

      # new_link.prepare_and_save_item(user_qb, 
      #    grac_mgr=None, target_groups=self.target_groups,
      #    rid_new=user_qb.item_mgr.rid_new, ref_item=None)
      new_link.save(user_qb, user_qb.item_mgr.rid_new)
      #log.verbose2('created link: %s' % (new_link,))
      log.verbose2(' >> saved: %s' % (new_link,))

      log.verbose2(' >> groups_access/2: %s' % (new_link.groups_access,))
      # g.assurt(new_link.groups_access)

      # Remember the user's group ID for when we save the revision.
      self.group_names_or_ids.add(user_qb.user_group_id)

      self.stats['total_new_links'] += 1

#      if rhs_item.deleted:
#         conf.break_here('ccpv3')
#      else:
#         conf.break_here('ccpv3')

   # *** Helpers for previous section

   #
   def setup_links_sanity_check(self):

      # The V1->V2 schema scripts processed data from three CcpV1 tables into
      # one CcpV2 table. Double check sanity using maths.

      """
      SELECT COUNT(*) AS FROM item_watcher_bug_nnnn;
      SELECT COUNT(*) AS FROM watch_region;
      SELECT COUNT(*) AS FROM region_watcher;
      SELECT COUNT(*) AS FROM thread_watcher;
      """

      sql_count = "SELECT COUNT(*) AS count FROM item_watcher_bug_nnnn"
      rows = self.qb.db.sql(sql_count)
      g.assurt(len(rows) == 1)
      count_item_watcher_bug_nnnn = rows['count']

      sql_count = "SELECT COUNT(*) AS count FROM watch_region"
      rows = self.qb.db.sql(sql_count)
      g.assurt(len(rows) == 1)
      count_watch_region = rows['count']

      sql_count = "SELECT COUNT(*) AS count FROM region_watcher"
      rows = self.qb.db.sql(sql_count)
      g.assurt(len(rows) == 1)
      count_region_watcher = rows['count']

      sql_count = "SELECT COUNT(*) AS count FROM thread_watcher"
      rows = self.qb.db.sql(sql_count)
      g.assurt(len(rows) == 1)
      count_thread_watcher = rows['count']

      log.debug('setup_links_sanity_check: count_item_watcher_bug_nnnn: %d'
                % (count_item_watcher_bug_nnnn,))
      log.debug('setup_links_sanity_check: count_watch_region: %d'
                % (count_watch_region,))
      log.debug('setup_links_sanity_check: count_region_watcher: %d'
                % (count_region_watcher,))
      log.debug('setup_links_sanity_check: count_thread_watcher: %d'
                % (count_thread_watcher,))

      ccpv1_total = (count_watch_region
                     + count_region_watcher
                     + count_thread_watcher)
      if count_item_watcher_bug_nnnn != ccpv1_total:
         log.warning('Unexpected count mismatch: %d != %d'
                     % (count_item_watcher_bug_nnnn, ccpv1_total,))

      # We also only run on the basemap, since CcpV1 doesn't have branches.
      g.assurt(len(self.qb.branch_hier) == 1)
      g.assurt(self.qb.branch_hier[0][0]
               == branch.Many.baseline_id(self.qb.db))

   #
   def setup_user_watcher_get_rhs(self, user_qb, stack_id):

      # EXPLAIN: Does saving a link_value check the user's access to the
      # geofeature or the attachment? [lb] thinks that commit.py checks,
      # or maybe it's grac_manager's prepare_item_valid_req. Hrm.

      rhs_item = None

      items_fetched = item_user_access.Many()

      items_fetched.search_by_stack_id(stack_id, user_qb)

      if len(items_fetched) > 0:
         g.assurt(len(items_fetched) == 1)
         rhs_item = items_fetched[0]

         #if rhs_item.deleted:
         #   conf.break_here('ccpv3')

         log.verbose2('setup_user_watcher: rhs_item: %s' % (str(rhs_item),))
         log.verbose2('setup_user_watcher: access_level_id: %d'
                     % (rhs_item.access_level_id,))
         log.verbose2('setup_user_watcher: real_item_type_id: %s'
                     % (rhs_item.real_item_type_id,))
         log.verbose2('setup_user_watcher: item_type: %s'
                     % (Item_Type.id_to_str(rhs_item.real_item_type_id),))
         g.assurt(rhs_item.item_type_id == Item_Type.ITEM_USER_ACCESS)
         g.assurt(rhs_item.real_item_type_id) # I.e., Region, Byway, etc.
      else:
         # Don't log an error or the cron job dies.
         log.warning('setup_user_watcher: watched item not found: %d'
                     % (stack_id,))
         # 2013.03.27: There are some regions in CcpV1 being watched that don't
         #             really exist.
         # ccpv1_lite=> select * from region_watcher where region_id = 1558741;
         #
         #               region_id |   username    
         #              -----------+---------------
         #                 1558741 |  [redacted]
         #
         # ccpv1_lite=> select * from region where id = 1558741;
         #              (0 rows)
         # ccpv1_lite=> select * from watch_region where id = 1558741;
         #              (0 rows)
         # Skipping: g.assurt(False)

      return rhs_item

   # ***

   #
   def cleanup_ccpv1(self):

      log.debug('Dropping table item_watcher_bug_nnnn')
      self.qb.db.sql("DROP TABLE IF EXISTS %s.item_watcher_bug_nnnn"
                     % (conf.instance_name,))

      log.debug('Dropping table watch_region')
      self.qb.db.sql("DROP TABLE IF EXISTS %s.watch_region"
                     % (conf.instance_name,))

      log.debug('Dropping table region_watcher')
      self.qb.db.sql("DROP TABLE IF EXISTS %s.region_watcher"
                     % (conf.instance_name,))

      log.debug('Dropping table thread_watcher')
      self.qb.db.sql("DROP TABLE IF EXISTS %s.thread_watcher"
                     % (conf.instance_name,))

   # ***

# ***

if (__name__ == '__main__'):
   link_attrs_pop = Link_Attributes_Populate()
   link_attrs_pop.go()


"""



new rev:
19177

Mar-27 01:33:00  DEBG     grax.item_mgr  #  finalize_seq_vals: stack_id: 2438790
Mar-27 01:33:00  DEBG     grax.item_mgr  #  finalize_seq_vals: system_id: 958904



ccpv3=> select stack_id from attribute where value_internal_name = '/item/alert_email';
 stack_id 
----------
  2436718

./ccp.py -U landonb --no-password -r -t link_value -f only_lhs_stack_id 2436718



"""


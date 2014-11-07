#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  ./new_item_policy_init.py --help
#
#  ./new_item_policy_init.py \
#     -U landonb --no-password \
#     -b 0 \
#     --profile='standard' \
#     -m "Create new item policies for basemap."
#  ./new_item_policy_init.py \
#     -U landonb --no-password \
#     -b "Metc Bikeways 2012" \
#     --profile='standard' \
#     -m "Create new item policies for branch."

# BUG nnnn: This script is good for the public basemap and can be used on
# branches, but it's not as customizable as maybe it could be. I.e., you might
# want to setup the permissions on a branch giving a shared group edit powers
# and the public group all access_style="disabled".

script_name = ('New Branch - New Item Policy Initializer')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2011-08-24'

# *** That's all she rote.

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# *** Module globals
# FIXME: Make sure this always comes before other Ccp imports
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE1
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('nip''nit')

# ***

import traceback

from grax.grac_manager import Grac_Manager
from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from grax.user import User
from item import item_versioned
from item.feat import branch
from item.grac import group
from item.grac import new_item_policy
from item.util import revision
from util_ import db_glue
from util_ import misc
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# ***

debug_skip_commit = False
#debug_skip_commit = True

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

# 2013.03.27: No longer necessary?:
#      # Tell the parent class we expect just one group ID.
#      self.groups_expect_one = True

   # *** Helpers

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self)

      #
      # MAYBE: We'll probably want a new profile, 'commentable', or
      # something, that means a group cannot edit features but can
      # edit posts and/or notes, etc., maybe points, whatnot. Maybe
      # it just restricts certain types, instead, no mostly 'normal',
      # but maybe cannot edit byways and regions, say.
      self.add_argument('-p', '--profile', dest='policy_profile',
         action='store', default='standard',
         choices=(None, 'standard', 'denied',),
         help='policy profile: how to setup group\'s access')

# *** New_Item_Policy_Init

class New_Item_Policy_Init(Ccp_Script_Base):

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   #
   def query_builder_prepare(self):
      Ccp_Script_Base.query_builder_prepare(self)

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      do_commit = False

      try:

         #g.assurt(len(self.cli_args.group_ids) == 1) # See: groups_expect_one
         #log.debug('Creating NIPs for group_name %s [%d] / branch %s'
         #          % (self.cli_args.group_names[0],
         #             self.cli_args.group_ids[0],
         #             self.cli_args.branch_id,))

         log.debug('Creating NIPs for branch: %s / policy_profile: %s'
                   % (self.cli_args.branch_id,
                      self.cli_opts.policy_profile,))

         # MAYBE: In most other scripts, we get the revision lock in
         # query_builder_prepare, but this seems more better, i.e.,
         # get it when you need it, not just willy-nilly on script startup.
         log.debug('go_main: getting exclusive revision lock...')
         revision.Revision.revision_lock_dance(
            self.qb.db, caller='new_item_policy_init.py')
         log.debug('go_main: database is locked.')

         # MAYBE: There seems to be an awful lot of boilerplate code here.
         self.qb.grac_mgr = Grac_Manager()
         self.qb.grac_mgr.prepare_mgr('user', self.qb)
         #
         # NOTE: I'm not sure we need user_group_id... but it's part of the
         #       boilerplate code... maybe put all this in script_base.py.
         g.assurt(self.qb.username
                  and (self.qb.username != conf.anonymous_username))
         self.qb.user_group_id = User.private_group_id(self.qb.db,
                                                       self.qb.username)

         # Get a new revision ID. Using revision_peek than revision_create (we
         # used to use revision_create because our SQL called CURRVAL, but
         # we've fixed our SQL since).
         self.qb.item_mgr.start_new_revision(self.qb.db)
         log.debug('Got rid_new: %d' % (self.qb.item_mgr.rid_new,))

         # Create the new new item policies.
         self.install_nips(self.qb, self.cli_opts.policy_profile)

         # Save the new revision and finalize the sequence numbers.
         group_names_or_ids = ['Public',]
         #group_names_or_ids = [self.cli_args.group_ids[0],]
         self.finish_script_save_revision(group_names_or_ids)

         log.debug('Committing transaction')

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         # FIXME: g.assurt()s that are caught here have empty msgs?
         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   # ***

   #
   def install_nips(self, qb, policy_profile):

      # Delete existing rows.
      new_item_policy.Many.purge_from_branch(qb)

      # Get the group IDs, one for the branch group and one for the branch
      # comptroller's group.

      pub_grp_id = group.Many.public_group_id(qb.db)
      g.assurt(pub_grp_id)

      if policy_profile == 'standard':
         force_style = None
      else:
         g.assurt(policy_profile == 'denied')
         force_style = Access_Style.all_denied

      # Profile tuple list's tuples are ordered thusly:
      #  policy_name, item_type, access_style, [link: lhs type, lhs acl,
      #                                            rhs type, rhs acl,],
      new_item_policy.Many.install_nips(
         qb, New_Item_Policy_Init.profile_standard, pub_grp_id,
         force_style)

      if policy_profile == 'standard':

         if len(qb.branch_hier) == 1:
            # MAGIC_NUMBER: The Basemap Owners group!
            map_name = "Basemap"
         else:
            g.assurt(len(qb.branch_hier) > 1)
            map_name = qb.branch_hier[0][2]

         restrict_scope = Access_Scope.shared

         if len(qb.branch_hier) == 1:
            g.assurt(qb.branch_hier[0][0]
                     == branch.Many.public_branch_id(qb.db))
            grp_name = '%s Owners' % (map_name,)
            grp_id, grp_nm = group.Many.group_resolve(qb.db, grp_name,
                                                      restrict_scope)
            g.assurt(grp_id)
            #
            new_item_policy.Many.install_nips(
               qb, New_Item_Policy_Init.profile_basemap_owners, grp_id)

         # MAGIC_NUMBER: What's a good way to identify the arbiters group?
         #               By convention, each new branch should get two new
         #               groups, one for everyone in the group and one for
         #               the moderators/arbiters/managers/comptrollers.
         # BUG nnnn: Disallow Arbiters:-named groups and usernames.
         grp_name = '%s Arbiters' % (map_name,)
         grp_id, grp_nm = group.Many.group_resolve(qb.db, grp_name,
                                                   restrict_scope)
         g.assurt(grp_id)
         new_item_policy.Many.install_nips(
            qb, New_Item_Policy_Init.profile_leafy_arbiters, grp_id)

         # MAGIC_NUMBER: What's a good way to identify the arbiters group?
         #               By convention, each new branch should get two new
         #               groups, one for everyone in the group and one for
         #               the moderators/arbiters/managers/comptrollers.
         # BUG nnnn: Disallow Editors:-named groups and usernames.
         grp_name = '%s Editors' % (map_name,)
         grp_id, grp_nm = group.Many.group_resolve(qb.db, grp_name,
                                                   restrict_scope)
         g.assurt(grp_id)
         new_item_policy.Many.install_nips(
            qb, New_Item_Policy_Init.profile_leafy_editors, grp_id)

   # ***

   # These profiles are derived from what's in
   #  scripts/schema/201-apb-57-groups-pub_ins3.sql

   profile_standard = [

      # *** Geofeatures
      # Byways are always public, never private; this is by design.
      ('Byways always public',
         'byway', 'pub_editor', None,),
      # Users are allowed to create private regions.
      ('Regions can be made private',
         'region', 'usr_choice', None,),
      # Terrain is not creatable, just viewable.
      # BUG 0694: Editable terrain.
      ('Cannot create Terrain',
         'terrain', 'all_denied', None,),
      # Waypoints are like regions, user private-able.
      # MAYBE: Is 'pub_choice' better than 'usr_choice'?
      ('Waypoints can be made private',
         'waypoint', 'pub_choice', None,),
      # Routes are initially owned and viewable just by the creator.
      ('Routes are private by default and Very Special',
         'route', 'restricted', None,),
      # ... same with tracks.
      ('Tracks are private by default and Also Special',
         'track', 'restricted', None,),

      # *** Attachments
      # Tags are always public.
      ('Tags are always public',
         'tag', 'pub_editor', None,),
      # Notes can be made private.
      # MAYBE: Is 'pub_choice' better than 'usr_choice'?
      ('Notes can be made private',
         'annotation', 'pub_choice', None,),
      # Threads and posts are always public.
      ('Threads are always public',
         'thread', 'pub_editor', None,),
      ('Posts are always public',
         'post', 'pub_editor', None,),
      # 2013.05.12: Only branch editors should be able to make attrs.
      #             At least for now. It doesn't make sense all users
      #             should be able to make attributes -- think of the
      #             clutter! Think of all the accidentally created
      #             attributes! Think of the ton of _useless_ attributes!
      # # Attributes are private-able.
      # ('Attributes can be made private',
      #    'attribute', 'usr_choice', None,),
      # See: profile_leafy_editors.

      # *** Link_Values
      # CAVEAT: By default, link_values are pub_editor (see rule below). For
      #         link_values that we want to make private, put them before the
      #         generic rule (up here) and be sure to use stop_on_match.
      ('Geofeature Email Item Alert links are Always Private',
         'link_value', 'usr_editor',
            'attribute', 'client',
            'geofeature', 'client',
            # link_left_stack_id/name, link_right_stack_id/name, stop_on_match:
            '/item/alert_email', None, True,
            # MAYBE: /item/alert_twitter  # Tweet
            #        /item/alert_sms      # Cell phone text message
            #        /item/alert_client   # Show in flashclient next logon
            # Formerly, or Considered:
            #  /user/watcher
            #  /user/item_alert
            #  /item/watcher/digest
            #  /item/alert_user
            #  /item/user_alert
            ),
      # We don't have an item_type for all items so be deliberate about the
      # other two types of email alert links.
      # MAYBE: This is tedious. Can we just write the attr. defn once for all
      #        three item types?
      ('Attachment Email Item Alert links are Always Private',
         'link_value', 'usr_editor',
            'attribute', 'client',
            'attachment', 'client',
            '/item/alert_email', None, True,),
      ('Nonwiki Email Item Alert links are Always Private',
         'link_value', 'usr_editor',
            'attribute', 'client',
            'nonwiki_item', 'client',
            '/item/alert_email', None, True,),

      # By default, links are editable when their geofeature is...
      ('Set Attachments on Editable Geofeature',
         'link_value', 'pub_editor',
            'attachment', 'client',
            'geofeature', 'editor',),
      # ... but notes can be attached to view-only geofeatures.
      ('Attach Note to Viewable Geofeature',
         'link_value', 'pub_editor',
            # NOTE: Some items, like routes linked to a post, may just have
            #       client access. These routes cannot have notes attached,
            #       unless we give route arbiters ability to choose
            #       link-post-route permissions... but 'viewer' access
            #       means routes show up in the route library, so we'd
            #       need a new group, like Stealth-Secret Group, so that
            #       link-post-route permissions are separate from All Users
            #       group permissions.
            #       Not supported now: 'geofeature', 'client',
            'annotation', 'client',
            'geofeature', 'viewer',),
      # ... and revision feedback is a whole other beast:
      #      an attachment-attribute link_value!
      ('Revision Feedback is always public',
         'link_value', 'pub_editor',
            'post', 'editor',
            'attribute', 'client',
            # link_left_stack_id/name, link_right_stack_id/name, stop_on_match:
            None, '/post/revision', True,
            ),

      # 2013.05.11: Let users run conflation on tracks.
      #             [lb] asks: Is this going to work? Let's find out!
      ('Users can run conflation jobs on tracks',
         'conflation_job', 'usr_editor', None,),

      ]

   # DEVS: This is an interesting idea for easily testing route permissions
   # without having to waste time with the route finder. But the item details
   # panel is missing the sharing tab, so this only gets you the sharing
   # widget's save button...
   # if 'ccpv3' in conf.server_names:
   #    profile_standard.append(
   #       # [lb] wants to test 'restricted' style in flashclient without
   #       #      having to bother (waiting and waiting) for route finder.
   #       ('For testing, waypoints are retricted-style',
   #          'waypoint', 'restricted', None,)
   #    )

   # ***

   profile_basemap_owners = [
      # E.g., give one user rights to create a branch.
      #   ('Branches creatable by landonb',
      #      'branch', 'permissive',
      #      'landonb', None,),
      # E.g., give one group rights to create branches.
      ('Basemap branch owners can create branches',
         'branch', 'permissive', None,),
      #('Basemap branch owners can make private work items',
      #   'work_item', 'usr_editor', None,),
      ]

   # ***

   profile_leafy_arbiters = [
      # Branch arbiters get editor access to all work_items in the branch
      # (i.e., and a checkbox in the UI to enable viewing all jobs, so that
      # they're initially filtered/hidden).
      # FIXME: Implement this: When fetching work items, check user's nip
      #        policy to see if they're allowed to do this.
      ('Branch arbiters can access all branch work items',
         'work_item',
         'all_denied', # style_name
         Access_Level.editor, # super_acl
         ),
      ]

   # ***

   profile_leafy_editors = [

      ('Branch editors can make private work items',
         'work_item', 'usr_editor', None,),

      # 2013.05.12: It seems wise to restrict access to new attributes...
      #  ('Branch editors can make public or private attributes',
      #     'attribute', 'usr_choice', None,),
      ('Branch editors can make public attributes',
         'attribute', 'pub_editor', None,),

      ]

   # ***

# ***

if (__name__ == '__main__'):
   nipi = New_Item_Policy_Init()
   nipi.go()


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from grax.grac_error import Grac_Error
from grax.user import User
from gwis.query_filters import Query_Filters
from gwis.exception.gwis_error import GWIS_Error
from item import grac_record
from item import item_base
from item import item_user_access
from item import link_value
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
#from item.feat import node_byway
from item.feat import node_traverse
from item.grac import group
from item.grac import group_item_access
from item.grac import group_membership
from item.grac import new_item_policy
from item.util import item_factory
from item.util import revision
from item.util.item_type import Item_Type
from util_ import logging2

log = g.log.getLogger('grax.grac_mgr')
# This doesn't override the global setting:
#  log.setLevel(logging2.VERBOSE)
# FIXME/BUG nnnn: What happened to Per-module pyserver logger levels?

class Grac_Manager(object):
   '''The Grac_Manager is used when committing items.'''

   # *** Member variables

   __slots__ = (
      'group_memberships', # List of user's group memberships (FIXME: Impl'mnt)
      #'groups',            # List of groups (FIXME: Implement)
      'new_item_policies', # List of user's new item policies.
      'anonymous_new_ips', # List of anon's new item policies.
      'grac_errors',       # If non-empty, list of items that cannot be saved.
      )

   # *** Constructor

   def __init__(self):
      # These are hydrated by prepare_mgr.
      self.group_memberships = {}
      #self.groups = {} # FIXME: Not used
      self.new_item_policies = None
      self.anonymous_new_ips = None
      self.grac_errors = {}
      # The "reference revision" is used to look for existing items or access.

   # *** Public interfaces

   # ***

   # Setup the GrAC manager. This loads group memberships and new item policies
   # for the current user.
   def prepare_mgr(self, context, qb, load_group_memberships=False):
      # FIXME: 2012.01.19: 'context' is only ever set to 'user', by commit. 
      # Other types of contexts are branch, group, and item. But item-context
      # is handled by the item itself when it's saved. And what might 
      # branch-context be? If a user is a branch arbiter, they go through
      # commit just like everyone else; or maybe it's like some of the scripts
      # we have, that only admins run. Only group context seems plausible --
      # but we don't have any group- or group_memership control in flashclient;
      # currently, group and group_membership commits happen via ccp.py.
      g.assurt(context == 'user') # Nothing else is implemented...
      g.assurt(self.new_item_policies is None)
      g.assurt(self.anonymous_new_ips is None)
      g.assurt(qb.username)
      # Lock any GRAC rows we touch, to guarantee things don't change. This
      # shouldn't really block anything: the new_item_policy table is rarely 
      # updated. (Note that new_item_policy_init.py, which makes the nip table,
      # locks the new_item_policy table, which blocks until all FOR SHARE OFs 
      # close their connections.)
      # BUG nnnn: I bet group_membership should use the same locking mechanism.
      #           We don't have it implemented in flashclient (in which case we
      #           would need it), but we do let ccp.py change group_membership.
      #           So row-lock FOR SHARE OF the user's group_membership rows,
      #           and then table lock the table on update?
      g.assurt(not qb.request_lock_for_share)
      # 2012.09.25: We used to row lock. But I don't think we need to do it.
      # Skipping: qb.request_lock_for_share = True
      #
      # Get the user's group memberships, if requested.
      if load_group_memberships:
         gms = group_membership.Many()
         gms.search_by_context(context, qb)
         for gm in gms:
            # 2013.04.01: This fired on [lb] during shapefile import... but
            # culprit wasn't stale code but fact I had multiple group_mmbrships
            # for the same group. I deleted these by hand. This was probably
            # caused during development of an import script, I can only hope.
            """
            select * from group_membership where access_level_id = 3
               order by group_id,username
            select stack_id,name from group_ where stack_id in
               (2426985, 2432132,2432133,2443002,2443003,2443004)
               order by stack_id;
             stack_id |            name             
            ----------+-----------------------------
              2426985 | Basemap Owners
              2432132 | Basemap Arbiters
              2432133 | Basemap Editors
              2443002 | Metc Bikeways 2012 Owners
              2443003 | Metc Bikeways 2012 Arbiters
              2443004 | Metc Bikeways 2012 Editors
            delete from group_membership where system_id in
               (962711,962710,962709,837266,837265,837268);
            lb's thinks this is old v1-v2 sql (now deleted) that setup
              group memberships that the make_new_branch script now makes.
            """
            # 2013.04.25: Argh. There was a problem in make_new_branch not
            # reducing its collections of usernames to unique sets, so landonb
            # ended up twice in the same group. This should just be an issue
            # with duplicate records -- so not a big problem.
            # No: g.assurt(gm.group_id not in self.group_memberships)
            try:
               earlier_gm = self.group_memberships[gm.group_id]
               g.assurt(gm.access_level_id == earlier_gm.access_level_id)
               # The reason we assert is because it's against the rules to have
               # two group_memberships with the same group_id and user_id. It
               # looks like the group_membership table is missing a constraint.
            except KeyError:
               self.group_memberships[gm.group_id] = gm
      #
      # FIXME: How does the nip work for arbiters? When we implement branch-
      #        roles, "thread moderators" will need owner-rights to all posts
      #        and threads, and "job moderators" will need owner-rights to all
      #        jobs. Should that just be hard-coded in the item class, i.e., 
      #        just checkout all items for a branch, indicate the user who owns
      #        it, and give the moderator owner access? What about on commit?
      #        Is it also hard-coded in commit to give moderators owner access?

      # Get the user's new item policies.
      # Lock the policies we see, until the end of the request. It's rare that 
      # the nip table is ever updated, so this isn't a big concern.

      if qb.username != conf.anonymous_username:
         # This is kind of ugly.
         restore_username = qb.username
         restore_user_id = qb.user_id
         restore_user_group_id = qb.user_group_id
         #
         qb.username = conf.anonymous_username
         qb.user_id = User.user_id_from_username(qb.db,
                                                 conf.anonymous_username)
         qb.user_group_id = group.Many.public_group_id(qb.db)
         #
         self.anonymous_new_ips = self.prepare_mgr_new_ips(qb)
         #
         qb.username = restore_username
         qb.user_id = restore_user_id
         qb.user_group_id = restore_user_group_id
         #
         self.new_item_policies = self.prepare_mgr_new_ips(qb)
      else:
         self.anonymous_new_ips = self.prepare_mgr_new_ips(qb)
         self.new_item_policies = self.anonymous_new_ips

      # 2012.07.31: No longer locking new item policy rows.
      # g.assurt(qb.request_lock_for_share)
      # qb.request_lock_for_share = False
      g.assurt(not qb.request_lock_for_share)

   #
   def prepare_mgr_new_ips(self, qb):
      new_item_policies = []
      nip_sql = new_item_policy.Many().sql_context_user(qb)
      nips_rows = qb.db.sql(nip_sql)
      last_processing_order = -1
      if not nips_rows:
         log.warning('No NIPs for user "%s".' % (qb.username,))
         log.verbose('NIPs SQL: %s' % (nip_sql,))
      for nip_row in nips_rows:
         nip = new_item_policy.One(qb, nip_row)
         g.assurt(nip.processing_order >= last_processing_order)
         last_processing_order = nip.processing_order
         new_item_policies.append(nip)
      #log.verbose4('nips: %s %s' % (nips, type(nips),))
      for nip in new_item_policies:
         #log.verbose('nip %s %s %s' % (nip, type(nip), dir(nip),))
         log.verbose3('nip: %s' % (nip,))
         nip.prepare_policy()
         log.verbose3('prepare: %s' % (nip,))
         log.verbose4(' >> target: %s' % (nip.target_item,))
         log.verbose4(' >>    lhs: %s' % (nip.target_left,))
         log.verbose4(' >>    rhs: %s' % (nip.target_right,))
         log.verbose4(' >> astyle: %s'
               % (nip.access_style_id if not nip.access_style_id else
                  Access_Style.get_access_style_name(nip.access_style_id),))
      log.verbose3('Found %d NIPs for user "%s"' % 
                   (len(new_item_policies), qb.username,))
      return new_item_policies

# BUG nnnn: some link_values have 0 for the lhs_stack_id!
#           but if you search the rhs_stack_id, you'll find a sister link_value
#           that is set properly...
# select * from link_value where stack_id = 1518270;
# The nook:
# select * from link_value join item_versioned using (system_id) where rhs_stack_id = 1365270;
#
# select * from tag join item_versioned using (system_id) where tag.stack_id = 1518211;
# select * from post where stack_id = 1518225;
# select * from annotation where stack_id = 2390467;
# not sure what the missing this could be... i don't see anything missing from
# trunk... though i didn't search deleted...
#
# Problem is also in CcpV1:
#prod_mirror=> select * from post_point where point_id = 1365270;
#   id    | version | deleted | post_id | point_id | valid_starting_rid | valid_before_rid 
#---------+---------+---------+---------+----------+--------------------+------------------
# 1518226 |       1 | f       | 1518225 |  1365270 |              13750 |       2000000000
# 1518270 |       1 | f       |       0 |  1365270 |              13751 |       2000000000
#
# EXPLAIN: How does a 0 id not bug the V1-V2 upgrade scripts, anyway??
# FIXME: This should be part of auditor, don't you think?
# you can probably just delete them...
#
# SELECT COUNT(*) FROM link_value WHERE lhs_stack_id = 0;
# count 
#-------
#     3

   # ***

   # NOTE: prepare_existing means in the database, not in the python.
   #       EXPLAIN: Why not combine with prepare_item_get_from_db?
   def prepare_existing_from_stack_id(self, qb, item_stack_id):
      log.verbose1('prepare_existing_from_stack_id: stack_id: %d' 
                   % (item_stack_id,))
      g.assurt(item_stack_id > 0)

      # MAYBE: Bug nnnn?: Move group_item_access.item_type,
      #                   link_lhs_type_id, and link_rhs_type_id
      #                   to item_stack, since these values never
      #                   change.
      #
      # Fetch the item
      #
      # For now, get the item_type from the group_item_access table,
      # so that we don't make a measly base class object but instead
      # make a proper real object.
      #  items_fetched = item_user_access.Many()
      item_type_sql = (
         """
         SELECT item_type_id
         FROM group_item_access
         WHERE stack_id = %d
         LIMIT 1
         """ % (item_stack_id,)) 
      rows = qb.db.sql(item_type_sql)
      if len(rows) == 1:
         item_type_id = rows[0]['item_type_id']
         item_type = Item_Type.id_to_str(item_type_id)
         item_class = item_factory.get_item_module(item_type)
         log.verbose('prepare_existing_fr_stk_id: item_class: %s' % item_class)
         items_fetched = item_class.Many()
         # PERFORMANCE: commit should bulk-load all items the user has
         # specified to edit or rate or watch, etc. But this is low priority,
         # since the commit command usually applies to tens of blocks, maybe
         # hundreds, but never thousands.
         items_fetched.search_by_stack_id(item_stack_id, qb)
         log.verbose1('prepare_existing_from_stack_id: fetched existing: %s'
                      % (items_fetched,))
         log.verbose1('prepare_existing_from_stack_id: fetched len: %d'
                      % (len(items_fetched),))
      else:
         items_fetched = []
         log.debug(
            '_from_stack_id: grac_err: no item_type_id: stack id %d / %s / %s'
            % (item_stack_id, str(qb), str(qb.filters),))

      if len(items_fetched) > 0:
         g.assurt(len(items_fetched) == 1)
         item = items_fetched[0]
         log.verbose1('verify_access: fetched: %s' % (str(item),))
         g.assurt(not item.fresh)
         g.assurt(not item.valid)
         access_granted = self.prepare_existing(qb,
            item_from_user=item,
            item_from_db=item,
            # 2013.09.11: This fcn. is only called by commit for GIA changes,
            #             so [lb] changed this from client to editor. Commit
            #             uses the Item_Manager to get items being rated, for
            #             which the user only need to be viewer or client.
            access_level_id_min=Access_Level.editor,
            allow_existing=True)
      else:
         item = None
         log.debug(
            '_from_stack_id: grac_err: unknown_item: stack id %d / %s / %s'
            % (item_stack_id, str(qb), str(qb.filters),))
         self.grac_errors_add(item_stack_id, Grac_Error.unknown_item,
                              '/item/update')

      return item

   # ***

   # This is called on GWIS commit, for item.prepare_and_save_item (on import),
   # and for routed (when saving a new route).
   #
   # EXPLAIN: What's the point of access_level_id_min, since it's always
   #          Access_Level.editor?
   def prepare_item(self, qb, item_from_user,
                              access_level_id_min,
                              ref_item):
      log.verbose1('prepare_item: item: %s / acl_min: %d'
                   % (item_from_user, access_level_id_min,))

      # We prepare items being edited, and those from the route finder.
      g.assurt(Access_Level.can_edit(access_level_id_min))
      # MAYBE: Fix usage of isinstance: shouldn't always use it...
      #          http://www.canonical.org/~kragen/isinstance/
      #        Ideally, we'd call a item fcn. instead.
      if isinstance(item_from_user, item_user_access.One):
         # This is an item_user_access item, e.g., geof, attc, lval, and wtem.
         # The client should not specify the item's access level.
         g.assurt(not item_from_user.is_access_valid())
         prepared = True
      elif isinstance(item_from_user, grac_record.One):
         # This is a GrAC record (only used by ccp.py, at least circa 2012).
         prepared = self.prepare_item_check_grac(qb, item_from_user)
      else:
         g.assurt(False)
      # Setup the item. For updates and split-intos, we'll load the existing 
      # or split-from item and its group_item_access records. For link_values,
      # we'll also load the linked items and check the user's access.
      if prepared:
         prepared = self.prepare_item_valid_req(qb,
                           item_from_user, 
                           access_level_id_min,
                           ref_item)
      # If prepared, the item is okay to be saved, otherwise we've lodged one
      # or more errors in self.grac_errors.
      return prepared

   # ***

   # This is just called by commit.recheck_permissions to... recheck 
   # permissions. It should be redundant; we're just checking our math.
   def verify_access_item_update(self, item):
      log.verbose1('verify_access_item_update: %s' % (item,))
      if isinstance(item, item_user_access.One):
         if item.valid:
            if item.dirty != item_base.One.dirty_reason_none:
               if not item.can_know():
                  log.debug('verify_access_item_update: user cannot know: %s' 
                            % (str(item),))
                  error = Grac_Error.unknown_item
               elif not item.can_edit():
                  log.debug('verify_access_item_update: user cannot edit: %s' 
                            % (str(item),))
                  error = Grac_Error.permission_denied
               else:
                  error = None
               if error is not None:
                  log.debug('verify_access_item_updt: grac_err: %s' % (item,))
                  item.valid = False
                  self.grac_errors_add(item.client_id, error, '/item/update')

         if item.valid:
            self.verify_access_item_update_groups(item)

   # *** Helper methods

   # *** Helpers for: general helpers

   #
   def grac_errors_add(self, client_id, error_code, hint_key, hint_value=None):
      g.assurt(client_id != 0)
      # We maintain a dictionary of dictionaries, keyed by the client ID.
      try:
         item_errors = self.grac_errors[client_id]
      except KeyError:
         item_errors = dict()
         self.grac_errors[client_id] = item_errors
      # For each client ID, we maintain a dictionary of error codes and hints.
      try:
         the_error = item_errors[error_code]
      except KeyError:
         the_error = Grac_Error(client_id, error_code)
         item_errors[error_code] = the_error
      the_error.hints_add(hint_key, hint_value)
      log.debug('grac_errors_add: Added: %s' % (the_error,))

   # *** Helpers for: prepare_existing_from_stack_id and prepare_item

   # *** prepare_*() fcns.: prepares item instance

   # This is called when you setup group_membership using ccp.py. Or
   # make_new_branch.py.
   def prepare_item_check_grac(self, qb, item_from_user):
      # This checks that the user has appropriate settings to insert or update
      # the GrAC record (circa 2012, these are just group_membership objects).
      prepared = True
      # BUG 2510: GrAC records are only sent via ccp.py; implement from client.
      g.assurt(qb.request_is_local)
      # Ignoring: qb.request_is_script; ccp.py always uses GWIS, so we always 
      #           require a shared secret.
      if not qb.request_is_secret:
         prepared = False
         log.warning('prepare_item_grac: shared secret missing')
         self.grac_errors_add(item_from_user.client_id, 
            Grac_Error.permission_denied, 'ssec')
      # We also expect that the user is logged in (or faking it from ccp.py 
      # with --no-password)
      if qb.username == conf.anonymous_username:
         prepared = False
         log.warning('prepare_item_grac: must be logged in')
         self.grac_errors_add(item_from_user.client_id, 
            Grac_Error.permission_denied, 'user')
      # BUG 2510: For now, the user has to be a branch owner. If we implement 
      # updating group_membership from a client, we'll want to rethink this.
      # 2012.10.23: [lb] removed code from V1->V2 upgrade scripts that added
      #             himself to basemap owners, so to let ccp.py work, since I
      #             don't have permissions yet, we don't enforce branch
      #             permissions.
      if False:
         try:
            # 2012.08.08: This used to use [-1][0], which is the basemap branch
            # stack ID, but we really want the leafiest branch stack ID, right?
            #branch.Many.branch_enforce_permissions(qb.db, qb.username, 
            #      qb.branch_hier[-1][0], qb.revision, Access_Level.owner)
            branch.Many.branch_enforce_permissions(qb, Access_Level.owner)
         except GWIS_Error, e:
            prepared = False
            log.warning('prepare_item_grac: must be branch owner')
            # NOTE: 'bmap' stands for basemap...
            self.grac_errors_add(item_from_user.client_id, 
               Grac_Error.permission_denied, 'bmap')
      if prepared:
         # Since we're being run from the command line, there is no 'working
         # copy' and there shouldn't be a revision conflict.
         g.assurt(isinstance(qb.revision, revision.Current))
         # For normal items, we also load the item (if it exists) from the
         # database and check that the user's item shares the version
         # (otherwise there's a revision conflict). But from ccp.py, the
         # developer isn't telling us the version #.
         g.assurt(item_from_user.version == 0)
      return prepared

   # ***

   #
   def prepare_item_valid_req(self, qb, item_from_user,
                                        access_level_id_min, 
                                        ref_item):
      prepared = True
      # Prepare the item cache. The item we're examining should not already be
      # cached. If it's a link, we want to make sure the items it links are
      # cached. The item being saved is already cached by the caller (see
      # commit.Op_Handler.process_items), and the caller also guarantees that 
      # link_values are prepared last, after all other item types.
      g.assurt(item_from_user.stack_id in qb.item_mgr.item_cache)
      if isinstance(item_from_user, link_value.One):
         # FIXME: Do link_values need ref_item?
         prepared &= self.prepare_item_linked_item(qb, item_from_user, 'lhs')
         prepared &= self.prepare_item_linked_item(qb, item_from_user, 'rhs')
      if prepared:
         prepared = self.prepare_item_valid_cache(qb,
            item_from_user, access_level_id_min, ref_item)
      return prepared

   #
   def prepare_item_valid_cache(self, qb, item_from_user,
                                          access_level_id_min, 
                                          ref_item):
      prepared = False
      # We're only ever called to see that the user has editor access to an
      # item.
      g.assurt(Access_Level.can_edit(access_level_id_min))
      # See if the user is committing a new item, or updating an existing one.
      item_from_db = None
      if ref_item is not None:
         # Split-from byways or their new link_values.
         item_from_db = ref_item
         log.verbose1('prepare_item_valid_cache: ref_item: item_from_db: %s' 
                      % (item_from_db,))
         # For now we only support byways. And their new link_values.
         g.assurt((isinstance(item_from_user, byway.One))
                  or (isinstance(item_from_user, link_value.One)))
      if item_from_user.fresh:
         # Prepare the new item, a la the new item policies.
         if isinstance(item_from_user, item_user_access.One):
            prepared = self.prepare_new(qb, item_from_user)
            if prepared and (ref_item is not None):
               # We prepared the item with 'new' permissions to verify the user
               # can create it, but the real permissions come from the ref item
               # (the split-from link or byway), so reset groups_access.
               item_from_user.groups_access = None
         elif isinstance(item_from_user, grac_record.One):
            # BUG 2510: Full GRAC GWIS CRUD.
            prepared = True
         if item_from_db is None:
            item_from_db = item_from_user
            log.verbose1('prepare_item_valid_cache: fra_user: item_from_db: %s'
                      % (item_from_db,))
      else:
         # Get item from database so we can check user's existing access level.
         g.assurt(Item_Type.is_id_valid(item_from_user.item_type_id))
         # If the item is a link_value, set the attc type.
         try:
            g.assurt(Item_Type.is_id_valid(item_from_user.link_lhs_type_id))
            link_attc_type_id = item_from_user.link_lhs_type_id
         except AttributeError:
            g.assurt(not isinstance(item_from_user, link_value.One))
            link_attc_type_id = None
         # Get the item from the database in the user's context. We're just
         # checking the user's access.
         # Do we care if we ignore ref_item and fetch from db?
         if item_from_db is None:
            item_from_db = self.prepare_item_get_from_db(qb,
                  item_from_user.item_type_id,
                  item_from_user.stack_id,
                  item_from_user.client_id,
                  link_attc_type_id)
            if item_from_db is None:
               log.debug(
                  'item_from_db: um, item_from_db_not_found: %s'
                  % (str(item_from_user),))
               prepared = False
            else:
               prepared = True
            # FIXME: What's ref_item? Does it matter?
            if ref_item is not None:
               log.debug(
                  'prepare_item_valid_cache: item_from_db, but ref_item: %s'
                  % (str(ref_item),))
         else:
            g.assurt(item_from_db == ref_item)
            g.assurt(item_from_db.is_access_valid())
            prepared = True
         log.verbose('prepare_item_valid_cache: not fresh: item_from_db: %s' 
                     % (item_from_db,))
      # Always make sure user has minimum access required, regardless of
      # new or not.
      if prepared and (item_from_db is not None):
         log.verbose1(' >> item_from_db.valid: %s' % (item_from_db.valid,))
         if isinstance(item_from_user, item_user_access.One):
            # Call prepare_existing, which calls validize.
            prepared = self.prepare_existing(qb, item_from_user,
                                                 item_from_db,
                                                 access_level_id_min,
                                                 allow_existing=False)
         elif isinstance(item_from_user, grac_record.One):
            # BUG 2510: Full GRAC GWIS CRUD.
            #dirty_reason = item_base.One.dirty_reason_item_user
            dirty_reason = item_base.One.dirty_reason_grac_user
            is_new_item = (id(item_from_user) == id(item_from_db))
            #?: is_new_item = (item_from_user.version == 0)
            item_from_user.validize(qb, is_new_item, dirty_reason,
                                        item_from_db)
      else:
         log.verbose1(' >> not prepared or item_from_db is None: %s / %s'
                      % (prepared, item_from_db,))
      return prepared

   # ***

   def prepare_item_linked_item(self, qb, link_from_user, xhs):

      # This fcn. is called for link_values being edited so we can load the
      # link attachment and the link geofeature so we can check they exist 
      # and the user has access.
      
      attr_item_type = 'link_%s_type_id' % xhs # E.g., link_lhs_type_id
      attr_stack_id = '%s_stack_id' % xhs # E.g., lhs_stack_id
      xhs_item_type_id = getattr(link_from_user, attr_item_type)
      g.assurt(Item_Type.is_id_valid(xhs_item_type_id))
      xhs_stack_id = getattr(link_from_user, attr_stack_id)
      g.assurt(xhs_stack_id > 0)
      xhs_item = self.prepare_item_ensure_cached(qb, xhs_item_type_id, 
                                                     xhs_stack_id)

      #if xhs_item is not None:
      #   g.assurt(Item_Type.is_id_valid(xhs_item.item_type_id))
      #   setattr(link_from_user, attr_item_type, xhs_item.item_type_id)

      return (xhs_item is not None)

   #
   def prepare_item_ensure_cached(self, qb, item_type_id, stack_id):
      try:
         # MAYBE: Use item_cache_get instead?
         item = qb.item_mgr.item_cache[stack_id]
      except KeyError:
         log.verbose3(
            'prepare_item_ensure_cached: item_type: %d / stack_id: %d' 
            % (item_type_id, stack_id,))
         g.assurt(stack_id > 0)
         item = self.prepare_item_get_from_db(qb, item_type_id, stack_id, 
                                                  stack_id)
         if item is not None:
            log.verbose('prepare_item_ensure_cached: item_cache: caching: %s' 
                        % (item,))
            #qb.item_mgr.item_cache[stack_id] = item
            g.assurt(stack_id == item.stack_id)
            qb.item_mgr.item_cache_add(item)
         else:
            # EXPLAIN: Who raises GWIS_Error? I think it still happens, just
            # not here.
            log.warning('User sent link with unknown lhs or rhs stack ID: %d'
                        % (stack_id,))
      return item

   # ***

   #
   def prepare_item_get_from_db(self, qb, item_type_id, stack_id, client_id,
                                          link_attc_type_id=None):
      item_from_db = None
      item_type = Item_Type.id_to_str(item_type_id)
      ## Can you smell it? The hack?
      #if item_type == 'link_value':
      #   g.assurt(link_attc_type_id is not None)
      #   attc_type = Item_Type.id_to_str(link_attc_type_id)
      #   item_type = 'link_%s' % attc_type # E.g., link_attribute, link_post
      #else:
      #   g.assurt(link_attc_type_id is None)
      item_class = item_factory.get_item_module(item_type)
      log.verbose('prepare_item_get_from_db: item_class: %s' % item_class)
      items_fetched = item_class.Many()
      try:
         items_fetched.search_by_stack_id(stack_id, qb)
      except AttributeError, e:
         g.assurt(False)
      log.verbose('prepare_item_get_from_db: fetchd: %s' % (items_fetched,))
      #log.verbose('prepare_item_get_from_db: ftd ln: %d' % len(items_fetched))
      g.assurt(len(items_fetched) <= 1)
      try:
         item_from_db = items_fetched[0]
         # Mark the item 'valid'. We don't call validize because we won't be
         # saving this item, we just need it to compare against the item the
         # user is saving.
         # FIXME: Try to do away with this.
         #item_from_db.valid = True
         log.verbose3('prepare_item_get_from_db: fetchd: %s' % (item_from_db,))
      except IndexError:
         # 2013.06.04: Funny. Consider a client that sends an item_watcher for
         # a item that doesn't exist, i.e., so the watcher ID is negative. By
         # now, we've converted that to the next stack ID from the sequence,
         # item_stack_stack_id_seq (which isn't actually claimed, because we
         # only peeked at the value, to handle just this situation -- rather
         # than failing but also claiming a stack ID that's discarded, we make
         # sure not to claim any stack IDs until we know the commit will likely
         # succeeed). Anyway, we'll send the new stack ID back in the
         # GWIS_Error, so don't be confused if you get an unknown item error
         # and can't find the stack ID in the database.
         log.debug(
            '_get_from_db: grac_err: unknown_item: client_id: %d'
            % (client_id,))
         self.grac_errors_add(client_id, Grac_Error.unknown_item, 
                              '/item/update')
      return item_from_db

   # ***

   # Given a fresh item from the user -- that is, a new item created in the 
   # user's working copy that is not saved in the database -- check the 
   # new item policies and assign the indicated permissions. If the user does
   # not have editor access to the new item, it should not be created (saved to
   # the database).
   def prepare_new(self, qb, item_from_user):
      log.verbose1('prepare_new: %s' % (item_from_user,))
      # NOTE: The item is still considered fresh, even though we've assigned it
      #       a new stack ID. This is contrary to flashclient, wherein fresh
      #       means the stack ID is subzero.
      g.assurt(item_from_user.fresh)
      g.assurt(item_from_user.stack_id > 0)
      groups_rights = self.create_rights_get(qb, item_from_user)
      # 2013.03.27: A fcn. called by init_permissions_new expects
      #             groups_rights, so might as well assert now.
      g.assurt(groups_rights)
      self.init_permissions_new(qb, item_from_user, groups_rights)
      if item_from_user.access_level_id != Access_Level.denied:
         prepared = True
         log.verbose1('prepare_new: allowed! %s' 
                      % (item_from_user.__str_abbrev__(),))
      else:
         prepared = False
         self.grac_errors_add(item_from_user.client_id, 
            Grac_Error.permission_denied, '/item/create')
         log.verbose1('prepare_new: denied! %s' % (item_from_user,))
      return prepared

   # Check that the user is allowed to edit the existing item. If the item
   # cannot be updated, then an alert is shown and false is returned.
   #
   # Returns true if the item is successfully prepared and can be updated.
   # 
   def prepare_existing(self, qb, item_from_user,
                                  item_from_db, 
                                  access_level_id_min,
                                  allow_existing=False):
      log.verbose1('prepare_existing: %s / min acl: %d' 
                   % (item_from_user.__str_abbrev__(), access_level_id_min,))

      # The way CcpV2 evolved, commit uses Item_Manager for items that aren't
      # being edited, so we only expect to be called for items being edited.
      # g.assurt(Access_Level.can_edit(access_level_id_min))
      if access_level_id_min != Access_Level.editor:
         log.warning('prepare_existing: acl_id_min not editor: %s'
                     % (access_level_id_min,))

      # If this is an existing item, check the access against the item we just
      # loaded from the database. Note that this fcn. is called from both
      # prepare_item_valid_cache (via prepare_item) as well as
      # prepare_existing_from_stack_id (via commit.py).
      if not item_from_user.fresh:
         # If not fresh, the item is not new; new items are assigned real
         # stack_ids, and that fcn. sets fresh (as opposed to valid, which
         # is set when any item, new or existing, is ready to be saved).
         g.assurt(item_from_user.stack_id > 0)
         if id(item_from_user) != id(item_from_db):
            # This is just a new version of an existing item.
         # BUG nnnn: If the new byway is a copy of a byway from the parent
         # branch that has split_from_stack_id set, so does the copy.
         # I think this is okay... really, byway's newly_split_ is the
         # important one, right?
            g.assurt(not item_from_user.is_access_valid())
            g.assurt((not isinstance(item_from_user, byway.One))
                     or (not item_from_user.newly_split()))
            self.init_access_level_existing(qb, item_from_user, item_from_db)
         # else: The item exists, but the user is not editing the item, they 
         #       just want to edit something related to the item. (I.e., the
         #       item is not changing.)
      # else: otherwise, the item is new. If the item is a new item from the
      # user (via commit or import) we spoof item_from_db and just set it to
      # item_from_user, but for split-into and split-from byways and for new 
      # link_values for the same, item_from_db is really ref_item, i.e., the 
      # item from the parent branch whose everything we copied to the user item
      g.assurt(item_from_user.is_access_valid())
      #
      permitted = Access_Level.is_same_or_more_privileged(
            item_from_user.access_level_id, access_level_id_min)
      permitted = self.prepare_existing_check_errors(permitted,
                                                     item_from_user,
                                                     item_from_db,
                                                     allow_existing)
      #
      # At one point, it seemed like a good idea to load the item's
      # groups_access right here, but no longer. For new items, we load it in
      # init_permissions_new based on the new item policy. For existing items,
      # the item class loads it in validize(), which happens before commit
      # loads the accesses the user sent via GML.
      #
      if permitted:
         is_new_item = (item_from_user.version == 0)

         if ((id(item_from_user) != id(item_from_db))
             or item_from_user.fresh):
            dirty_reason = item_base.One.dirty_reason_item_user
         else:
            # The user is editing GIA records, either directly, or using
            # a style change.
            dirty_reason = item_base.One.dirty_reason_none

         # 2014.01.30: commit ORs in item_base.One.dirty_reason_grac_user...
         #   and this smells like a hack work-around.
         #   (It should be noted that I added that code a few months back,
         #   and rather than back it out, we should make it work, since I
         #   was solving a few other problems....)
         # 
         dirty_reason |= item_from_user.dirty
         item_from_user.dirty = item_base.One.dirty_reason_none

         log.verbose1('calling validize: %s / %s / dty: %s'
                      % (item_from_user, item_from_db, dirty_reason,))
         item_from_user.validize(qb, is_new_item, dirty_reason, item_from_db)
      else:
         # We've already registered an error to send back to the user, but 
         # Flashclient shouldn't cause this, so log a warning as well.
         log.warning('prepare_existing: Denied!: %s (%d)' 
                     % (item_from_db, access_level_id_min,))
      return permitted

   # ***

   # This fcn. determines the user's creation rights on a new item. Since users
   # can belong to more the one group, we might have more than one policy to
   # consider for the given targets. The callee passes the new item that the
   # users wishes to create, and we pass back a collection of rights.
   def create_rights_get(self, qb, new_item):
      log.verbose2('create_rights_get: new_item: %s' % (new_item,))
      groups_rights = []
      nip_lookup = self.new_item_policies
      g.assurt(nip_lookup is not None)
      # Iterate through the list to determine the user's rights.
      i = 0
      while i < len(nip_lookup):
         policy = nip_lookup[i]
         #log.verbose4('create_rights_get: policy: i: %d / %s / %s' 
         #   % (i, policy.to_string_part_i(), policy.to_string_part_ii(),))
         log.verbose4('create_rights_get: loop iter: %d / policy rank: %d'
                      % (i, policy.processing_order,))
         # If the policy matches the targets, collect the rights
         if policy.matches_targets(new_item, qb.item_mgr.item_cache):
            # Only add the policy to the list if the user is allowed to
            # create items.
            if ((policy.access_style_id)
                and (policy.access_style_id != Access_Style.all_denied)
                # FIXME: Is it hacky making arbit_okay something that applies
                #        to existing items, and not to new items? Maybe replace
                #        nip.super_acl with nip.something_else?
                #and (policy.access_style_id != Access_Style.arbit_okay)
                ):
               g.assurt(Access_Style.is_valid(policy.access_style_id))
               log.verbose4('  - creation ok')
               groups_rights.append(policy)
            else:
               log.verbose4('  - skipping record with no creation rights')
            # If the policy is a short-circuit, we're done
            if policy.stop_on_match:
               log.verbose4('  short-circuiting!')
               break
         i = i + 1
      log.verbose2('create_rights_get: groups_rights: %s' % (groups_rights,))
      return groups_rights

   def get_style_from_rights(self, groups_rights):
      log.verbose2('get_style_from_rights: %s' % (groups_rights,))
      # Loop through the matching new item policies and make sure all the
      # records agree. At this point, we don't expect to see "all_denied".
      # NOTE: We could, e.g., give the public usr_choice to an item but give
      # permissive access to a special user group. But we don't have a use case
      # for that behaviour.
      the_style = None
      for rights in groups_rights:
         log.verbose3(' .. get_style_from_rights: rights: %s', rights)
         g.assurt(rights.group_id != 0)
         g.assurt(rights.access_style_id != Access_Style.all_denied)
         # HACK: arbit_okay is an overloaded usage...
         if rights.access_style_id:
            if the_style:
               # For a particular item definition, we expect each group
               # record to specify the same access_style_id, unless it's
               # all_denied. I.e., the access_style_id for the same item
               # will always be all_denied or the same access_style_id.
               g.assurt(rights.access_style_id == the_style)
               pass
            if the_style is not None:
               # MAYBE: Since we loop through groups_rights, we'll end up
               # choosing the style of the last matching new_item_policy... is
               # that what we want?
               # Currently, this happens on the second of the two matching
               # policies:
               #     "Set Attachments on Editable Geofeature"
               #     "Attach Note to Viewable Geofeature"
               if the_style != rights.access_style_id:
                  log.warning(
                     'get_style_from_rights: choosing latter style: %s to %s'
                     % (the_style, rights.access_style_id,))
            the_style = rights.access_style_id
      g.assurt(the_style)
      return the_style

   # CODE_COUSINS: init_permissions_new/init_permissions
   #          pyserver/grax/grac_manager.py::init_permissions_new
   #          flashclient/items/Item_User_Access.as::init_permissions

   # After creating a new item for the working copy, we need to apply
   # permissions per the user's new item policies.
   def init_permissions_new(self, qb, item, groups_rights):

      log.verbose1('init_permissions_new: %s' % str(item))

      # The new item should be... new.
      g.assurt(item.groups_access is None)
      item.groups_access = {}
      item.latest_infer_id = None
      item.latest_infer_username = None

      # Start by denying access to the item. We'll upgrade the user's
      # access as we process the new item policies.
      g.assurt(not item.is_access_valid())
      item.access_level_id = Access_Level.denied

      # Some new items are hydrated from existing items. This includes
      # split-from byways and associated data, like link_values. The
      # node_endpoint item is also gia-less.
      g.assurt((qb.user_group_id > 0) or (not qb.username))

      # For the "usr_choice" option, if the user is not logged on (is
      # anonymous), then the choice is obviously "pub_editor" and not
      # "usr_editor".
      real_user = (qb.username and (qb.username != conf.anonymous_username))

      # Since grac_mgr is in charge here, we can mark the dirty reason as
      # 'auto', meaning the changes are to be trusted.
      #dirty_reason = item_base.One.dirty_reason_item_auto
      dirty_reason = item_base.One.dirty_reason_grac_auto

      the_style = self.get_style_from_rights(groups_rights)

      # Now that we're all in agreement, implement groups_access per the style.
      session_id = None
      if the_style == Access_Style.permissive:
         # For permissive, since the user can assign any group and edit group
         # permissions at will, we'll want to make sure the user is a real
         # user. We could allow anonymous owners of permissive-styled items,
         # maybe by using a session ID record, but the only item with
         # permissive-style permissions is branch. So it makes sense that
         # permissive permissions must be attached to a private user group.
         # (It also simplifies this fcn., since at the end of it we just make
         # one GIA record.)
         g.assurt(real_user)
         group_id = qb.user_group_id
         # Owners can do what they want with an item's GIA records.
         item.access_level_id = Access_Level.owner
         log.debug('init_permissions_new: new permissive item for usr-owner')
      elif the_style == Access_Style.restricted:
         # This is for routes and tracks, generally.
         if not real_user:
            # This happens for anon users getting routes.
            group_id = group.Many.session_group_id(qb.db)
            item.access_level_id = Access_Level.arbiter
            g.assurt(qb.session_id)
            session_id = qb.session_id
            log.debug('init_permissions_new: new restricted item for session')
         else:
            # The route finder doesn't set style_change, so just make the user
            # the arbiter of the route. The route_view.active column indicates
            # if this route is shown in the user's library.
            group_id = qb.user_group_id
            item.access_level_id = Access_Level.arbiter
            # MAYBE: Let users see all their old routes.
            log.debug('init_permissions_new: new restricted item for usr-arbr')
         # Skipping: We could make a public record and set it denied... meh.
         #           In fact, it seems that style_change can/should come later.
         #           I.e., the first record is the user's private/arbiter GIA
         #           record, and then a subsequent request deliberately changes
         #           the permissions (as opposed to creating a new item and
         #           changing its permissions at the same time).
         #           Don't care: item.style_change # We might process it later.
      else:
         item.access_level_id = Access_Level.editor
         # See if the user has a choice regarding item access.
         # BUG nnnn: Support usr_editor, i.e., private items.
         if the_style in (Access_Style.usr_choice, Access_Style.pub_choice,):
            if not item.style_change:
               raise GWIS_Error('Missing style_change')
            # FIXME: Should we make sure access_style_id is set, or should
            # we just default to public if the client doesn't say in the XML?
            # g.assurt(item.access_style_id in ('usr_editor', 'pub_editor',))
            if real_user and (item.style_change == Access_Infer.usr_editor):
               group_id = qb.user_group_id
               the_style = Access_Style.usr_editor
            else:
               # Otherwise, 'pub_editor'.
               if item.style_change != Access_Infer.pub_editor:
                  raise GWIS_Error(
                     'Unexpected style_change: want usr_editor or pub_editor')
               group_id = group.Many.public_group_id(qb.db)
               the_style = Access_Style.pub_editor
         elif the_style == Access_Style.usr_editor:
            g.assurt(real_user)
            group_id = qb.user_group_id
         else:
            g.assurt(the_style == Access_Style.pub_editor)
            group_id = group.Many.public_group_id(qb.db)
         # We've applied the style_change, so forgetaboutit.
         item.style_change = None
      # Never spaghet.
      item.access_style_id = the_style

      # Make just one groups_access record.
      if item.access_level_id != Access_Level.denied:
         item.group_access_add_or_update(qb,
               (group_id, item.access_level_id, session_id,),
               dirty_reason)

   # ***

   #
   def init_access_level_existing(self, qb, item_from_user, item_from_db):
      current_access = item_from_db.access_level_id
      log.verbose1('init_access_level_existing: init. acl: %s / _from_db: %s'
                % (current_access, item_from_db,))
      g.assurt(not item_from_user.is_access_valid())
      g.assurt(item_from_db.is_access_valid())
      # Iterate through the list to determine the user's rights.
      i = 0
      while i < len(self.new_item_policies):
         policy = self.new_item_policies[i]
         log.verbose4(' >> scanning policies: loop no. %d / policy rank: %d'
                      % (i, policy.processing_order,))
         log.verbose5('  >> %s' % (policy.to_string_part_i(),))
         log.verbose5('  >> %s' % (policy.to_string_part_ii(),))
#         if current_access <= Access_Level.editor:
         # If the policy matches the targets, check super_acl, which might 
         # give a user *better* privileges to an item (for now, branch managers
         # can see and edit all users' work items).
         # I don't think it matters if we use item_from_user or item_from_db...
         if policy.matches_targets(item_from_db, qb.item_mgr.item_cache):
            if ((Access_Style.all_denied == policy.access_style_id)
                or (not policy.access_style_id)):
               # The access_style_id should not be not set, but should be
               # all_denied if super_acl is being used.
               g.assurt(policy.access_style_id == Access_Style.all_denied)
               g.assurt(policy.super_acl)
               if policy.super_acl < current_access:
                  current_access = policy.super_acl
            else:
               # No adjustement to access if using access_style.
               g.assurt(Access_Style.is_valid(policy.access_style_id))
               g.assurt(not policy.super_acl)
            if policy.stop_on_match:
               log.verbose4('  short-circuiting!')
               break
         i = i + 1
      log.verbose1(' >>>> new access: %d' % (current_access,))
      # Set the accesses on both items.
      item_from_db.access_level_id = current_access
      item_from_user.access_level_id = current_access
      # All item versions share the same access_style as version 1.
      # NOTE: access_style_id is None if the access_level cannot be changed.
      #       This is for: usr_editor, pub_editor, usr_choice, or all_denied.
      if not Access_Style.is_valid(item_from_db.access_style_id):
         # If an item_stack doesn't have an access_style_id or even if it's
         # all_denied only means we cannot change the permissions on the item.
         # The user can still edit the item, though.
         item_from_db.access_style_id = Access_Style.all_denied
      g.assurt(not Access_Style.is_valid(item_from_user.access_style_id))
      item_from_user.access_style_id = item_from_db.access_style_id

   #
   def prepare_existing_check_errors(self, permitted,
                                           item_from_user, 
                                           item_from_db,
                                           allow_existing=False):
      if permitted:
         # Check if user's item is in conflict (i.e., user needs to update
         # their working copy).
         if id(item_from_user) != id(item_from_db):
            if item_from_user.stack_id == item_from_db.stack_id:
               if (   (item_from_user.branch_id is None)
                   or (item_from_user.branch_id == item_from_db.branch_id)):
                  if item_from_user.version != item_from_db.version:
                     g.assurt(item_from_user.version < item_from_db.version)
                     log.debug(
                        'prep_existg_chk_errs: grac_err-1: usr: %s / db: %s'
                        % (item_from_user, item_from_db,))
                     self.grac_errors_add(item_from_user.client_id, 
                        Grac_Error.revision_conflict, '/item/update')
                     permitted = False
                  # else, same branch, same version.
               else:
                  # Difference branches. This is okay, since we can resolve
                  # conflicts later, more casually than raising a Grac_Error.
                  g.assurt(item_from_user.version <= item_from_db.version)
                  pass
            else:
               # Split-from byway. item_from_db is a reference item, so version
               # cannot be compared.
               g.assurt(item_from_user.version == 0)
         else: # id(item_from_user) == id(item_from_db)
            # This is a new item, so the version is just 0.
            g.assurt((item_from_user.version == 0) or (allow_existing))
         # 2011.05.23 Allow from ccp.py script:
         ## BUG nnnn: We don't allow branch updates from the client yet.
         #if (isinstance(item_from_db, branch.One)):
         #   self.grac_errors_add(item_from_user.client_id, 
         #      Grac_Error.bad_item_type, '/item/update')
         #   permitted = False
         ## else, item is link_value, or derived from attachment or geofeature.
      else:
         if item_from_db.can_view():
            # If the user can see the item, they at least know it exists.
            log.debug(
               'prep_existg_chk_errs: grac_err-2: usr: %s / db: %s'
               % (item_from_user, item_from_db,))
            self.grac_errors_add(item_from_user.client_id, 
               Grac_Error.permission_denied, '/item/update')
         else:
            # If user cannot see the item, don't tip them off that it exists.
            log.debug(
               'prep_existg_chk_errs: grac_err-3: usr: %s / db: %s'
               % (item_from_user, item_from_db,))
            self.grac_errors_add(item_from_user.client_id, 
               Grac_Error.unknown_item, '/item/update')
      return permitted

   # *** Helpers for: verify_access_item_update

   #
   def verify_access_item_update_groups(self, item):
      log.verbose1('verify_access_item_update_groups: item: %s' % (item,))
      g.assurt(len(item.groups_access) > 0) # I.e., user's prvt and/or pub grp
      for grpa in item.groups_access.itervalues():
         # FIXME: Why does trace show grpa without system ID, stack ID, 
         #        version, or branch set?
         log.verbose3(' >> grpa: %s / item.dirty: %s / acl: %d' 
                      % (grpa, grpa.dirty, grpa.access_level_id,))
         # Check that the user is not trying to game the system.
         if (grpa.dirty & (item_base.One.dirty_reason_item_user
                           | item_base.One.dirty_reason_grac_user)):
            g.assurt(item.valid)
            g.assurt(item.access_style_id == Access_Style.permissive)
            # Check user can at least arbiter the item.
            if not item.can_arbit():
               log.warning('GUI failure? Non-arbit user trying to arbit.')
               item.valid = False
            # Check user is not trying to set access better than current access
            if Access_Level.is_more_privileged(grpa.access_level_id,
                                               item.access_level_id):
               log.warning('GUI failure? User trying to cheat access.')
               item.valid = False
            # BUG nnnn: Users can cheat and give any other group the same
            # access the user has to the item. But only arbiters can change
            # access. And the concept of arbiter changes when branch-roles is
            # implemented.
            if not item.valid:
               self.grac_errors_add(item.client_id, 
                                    Grac_Error.permission_denied, 
                                    'item/groups_access', 
                                    grpa.group_id)

   # ***

   #
   # FIXME: Belongs in item_manager?
   @staticmethod
   def ccp_get_gf(gf_many, stack_id, qb, by_network=False):
      log.verbose('ccp_get_gf: gf_type: %s / stack_id: %d' 
                  % (type(gf_many), stack_id,))
      # FIXME: Remove these asserts
      g.assurt(not qb.sql_clauses)
      # Hack:
      if isinstance(gf_many, byway.Many):
         if by_network:
            g.assurt(not qb.filters.only_stack_ids)
            qb.filters.only_stack_ids = str(stack_id)
            gf_many.search_by_network(qb)
            qb.filters.only_stack_ids = ''
         else:
            gf_many.search_by_stack_id(stack_id, qb)
      else:
         gf_many.search_by_stack_id(stack_id, qb)
      g.assurt(not qb.sql_clauses)
      #qb.sql_clauses = None # Bug nnnn: Item class should clean up
      if len(gf_many) == 1:
         gf = gf_many[0]
      else:
         g.assurt((len(gf_many) == 0) and (not qb.revision.allow_deleted))
         gf = None
      #log.verbose(' .. gf: %s' % (gf,))
      # Callers of this fcn. expect an item, so throw if none found.
      if ((gf is None) or (gf.deleted)):
         err_s = 'Found None or deleted: stack_id: %d: %s' % (stack_id, gf,)
         log.error(err_s)
         log.debug('%s' % (traceback.format_exc(),))
         raise Exception(err_s)
      return gf

   # ***

# ***

if (__name__ == '__main__'):
   pass


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# A versioned item is one that follows the valid-start/valid-until
# revisioning model.

import copy
import time

import conf
import g

from grax.user import User
from gwis.query_filters import Query_Filters
from gwis.query_viewport import Query_Viewport
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item.util import revision
from util_ import db_glue
from util_ import mem_usage

__all__ = ['Sql_Clauses', 'Sql_Bi_Clauses', 'Item_Query_Builder',]

log = g.log.getLogger('item_query_b')

class Sql_Clauses(object):

   __slots__ = (
      #'source', # FIXME: Make a magic enum for this?
      'enabled',
      'select',
      'shared',
      'from_table',
      'join',
      'ts_queries',
      'where',
      'where_item_type_id_fcn',
      'group_by_enable',
      'group_by',
      'order_by_enable',
      'order_by',
      'geometry_needed',
      )

   def __init__(self, copy_this=None):
      for mbr in Sql_Clauses.__slots__:
         if copy_this is not None:
            setattr(self, mbr, getattr(copy_this, mbr))
         else:
            setattr(self, mbr, '')
      self.enabled = bool(self.enabled)
      self.group_by_enable = bool(self.group_by_enable)
      self.order_by_enable = bool(self.order_by_enable)
      self.geometry_needed = bool(self.geometry_needed)

   #
   def __eq__(self, other):
      equals = (
             (self.enabled == other.enabled)
         and (self.select == other.select)
         and (self.shared == other.shared)
         and (self.from_table == other.from_table)
         and (self.join == other.join)
         and (self.ts_queries == other.ts_queries)
         and (self.where == other.where)
         and (self.where_item_type_id_fcn == other.where_item_type_id_fcn)
         and (self.group_by_enable == other.group_by_enable)
         and (self.group_by == other.group_by)
         and (self.order_by_enable == other.order_by_enable)
         and (self.order_by == other.order_by)
         and (self.geometry_needed == other.geometry_needed)
         )
      #log.debug('__eq__: equals: %s' % (equals,))
      return equals

   #
   def __ne__(self, other):
      not_equals = not self.__eq__(other)
      #log.debug('__ne__: not equals: %s' % (not_equals,))
      return not_equals

   #
   def __str__(self):
      return (
         'enbl: %s / sel: %s / shr: %s / frm: %s / join: %s / ts_q: %s '
         '/ whr: %s / whr_f: %s / grpb_enbl: %s / grpb: %s '
         '/ ordb_enbl: %s / ordb: %s / geom_n: %s'
         % (self.enabled,
            self.select,
            self.shared,
            self.from_table,
            self.join,
            self.ts_queries,
            self.where,
            self.where_item_type_id_fcn,
            self.group_by_enable,
            self.group_by,
            self.order_by_enable,
            self.order_by,
            self.geometry_needed,))

   #
   def diff_str(self, other):
      return ('%s%s%s%s%s%s%s%s%s%s%s%s%s'
         % (('\n>> enbl:\n   ...self: %s\n   ...other: %s'
             % (self.enabled, other.enabled,))
               if (self.enabled != other.enabled) else '',
            ('\n>> sel:\n   ...self: %s\n   ...other: %s'
             % (self.select, other.select,))
               if (self.select != other.select) else '',
            ('\n>> shr:\n   ...self: %s\n   ...other: %s'
             % (self.shared, other.shared,))
               if (self.shared != other.shared) else '',
            ('\n>> frm:\n   ...self: %s\n   ...other: %s'
             % (self.from_table, other.from_table,))
               if (self.from_table != other.from_table) else '',
            ('\n>> join:\n   ...self: %s\n   ...other: %s'
             % (self.join, other.join,))
               if (self.join != other.join) else '',
            ('\n>> ts_q:\n   ...self: %s\n   ...other: %s'
             % (self.ts_queries, other.ts_queries,))
               if (self.ts_queries != other.ts_queries) else '',
            ('\n>> whr:\n   ...self: %s\n   ...other: %s'
             % (self.where, other.where,))
               if (self.where != other.where) else '',
            ('\n>> whr_f:\n   ...self: %s\n   ...other: %s'
             % (self.where_item_type_id_fcn, other.where_item_type_id_fcn,))
               if (self.where_item_type_id_fcn != other.where_item_type_id_fcn)
               else '',
            ('\n>> grpb_enbl:\n   ...self: %s\n   ...other: %s'
             % (self.group_by_enable, other.group_by_enable,))
               if (self.group_by_enable != other.group_by_enable) else '',
            ('\n>> grpb:\n   ...self: %s\n   ...other: %s'
             % (self.group_by, other.group_by,))
               if (self.group_by != other.group_by) else '',
            ('\n>> ordb_enbl:\n   ...self: %s\n   ...other: %s'
             % (self.order_by_enable, other.order_by_enable,))
               if (self.order_by_enable != other.order_by_enable) else '',
            ('\n>> ordb:\n   ...self: %s\n   ...other: %s'
             % (self.order_by, other.order_by,))
               if (self.order_by != other.order_by) else '',
            ('\n>> geom_n:\n   ...self: %s\n   ...other: %s'
             % (self.geometry_needed, other.geometry_needed,))
               if (self.geometry_needed != other.geometry_needed) else '',))

class Sql_Bi_Clauses(object):

   __slots__ = (
      'inner',
      'outer',
      'is_clone', # True if clauses object is a clone (used for dbggg)
      )

   def __init__(self, copy_this=None):
      self.inner = Sql_Clauses(getattr(copy_this, 'inner', None))
      self.outer = Sql_Clauses(getattr(copy_this, 'outer', None))
      self.is_clone = False

   #
   def __eq__(self, other):
      equals = (    (self.inner == other.inner)
                and (self.outer == other.outer))
                # ignoring: self.is_clone
      #log.debug('__eq__: equals: %s' % (equals,))
      return equals

   #
   def __ne__(self, other):
      not_equals = not self.__eq__(other)
      #log.debug('__ne__: not equals: %s' % (not_equals,))
      return not_equals

   #
   def __str__(self):
      return ('SQL Bi Cl: inner: %s / outer: %s/ clone: %s'
         % (str(self.inner),
            str(self.outer),
            self.is_clone,))

   #
   def diff_str(self, other):
      inner_diff_str = self.inner.diff_str(other.inner)
      outer_diff_str = self.outer.diff_str(other.outer)
      if not inner_diff_str and not outer_diff_str:
         diff_str = ''
      else:
         diff_str = ('SQL Bi Cl Diff: inner: %s / outer: %s%s'
                     % (inner_diff_str if inner_diff_str else 'no-diff',
                        outer_diff_str if outer_diff_str else 'no-diff',
                       (' / clone: %s|%s' % (self.is_clone, other.is_clone,))
                        if (self.is_clone != other.is_clone) else '',))
      return diff_str

   #
   def clone(self):
      the_clone = Sql_Bi_Clauses(self)
      the_clone.is_clone = True
      return the_clone

   # ***

# ***

class Item_Query_Builder(object):

   __slots__ = (
      'db',
      # These values come from the user in the request and are required.
      'username',          #
      'user_id',           #
      'user_group_id',     #
      'branch_hier',       # list of tuples
      'revision',          # revision.Revision descendant (e.g., Historic)
      # These values also come from the user but are optional.
      'viewport',          # Query_Viewport instance
      'filters',           # Query_Filters instance
      # These values are configured and used internally.
      'sql_clauses',       # Sql_Bi_Clauses instance (see above).

      'confirm_leafiness', # True if using (more costly*) stacked branching.
      # BUG nnnn: It might be faster to just copy all parent items to branches.
      #           It wouldn't be too hard to implement (ha!), and then we'd
      #           see if we got better performance, at the cost of more
      #           storage. But storage is cheap!
      #           Anyway, stacked branching is probably more SQL-costly than
      #           it's worth. We should just copy all parent branch items
      #           from the last_merge_rid into the branch that don't already
      #           exist there...
      #           It's actually not bad to support both options: stacked
      #           branching is handy when you're sketching out new ideas.
      #           And we might be able to export the MetC branch and re-import
      #           it into a new basemap branch, and then just manually update
      #           parent.branch_id to re-establish the connection.
      #           FIXME: Make a new branch table column, is_flattened,
      #                  to indicate that a stacked branch contains all
      #                  of the items, so that costly stacked branching
      #                  can be avoided.
      #           Implementation note: When you save to the branch, you
      #           can ignore the items with the old branch ID, but when
      #           you merge or update two branches, you'll not only create
      #           new records in the parent branch, but you'll create new
      #           records with the parent branch ID in the leafier branch.

      # (*) Stack branching means we have to search parent branches for items.
      # Meta-filters, used to filter the filters.
      'use_filters_and_viewport', # Used to ignore (most of) what's in filters
      'use_limit_and_offset', # Used to pageinate results
      'diff_group',        # Set to 'former' or 'latter' when diffing
      'diff_items',        #
      'diff_counterparts', #
      'diff_hier',         #
      # See: these variables are similar to same-named ones in query_client.
      'request_is_local',  # True if developer invoked pyserver from cmd line.
      'request_is_script', # If the request is coming from a local(host) script
      #
      'request_is_a_test', # True if db should be rollback()ed, not commit()ted
      'request_is_secret', #
      'cp_maint_lock_owner', # True for scripts being run during maintenance.
      #
      # For access_style_id = 'restricted', anonymous users can create items,
      # log in, and then claim ownership of the item they created -- we just
      # need to know their session ID. (Note, this is from query_client.)
      'session_id',        #
      # 2014.05.14: Adding some more query_client attributes to the qb,
      #             since not all items saved are saved via a GWIS request
      #             (that is, these, like other qb values, are "redunant",
      #             and can be found in the gwis/query_* classes).
      #             These values are inspired by old route columns:
      #             We've always stored the username and creation date with
      #             each route version. In CcpV1, these two columns were
      #             redundant, since the same information was stored in the
      #             revision table, as all routes were revisioned. So this
      #             was mostly a caching mechanism, to make research and
      #             fetches "easier". In CcpV2, with acl_grouping, we can't
      #             rely on joining against the revision table, because not
      #             all items are revisioned (see: acl_grouping).
      'remote_ip',
      'remote_host',
      'remote_what',
      #
      # Advice on how to lock the database.
      # 2012.08.10: Use of request_lock_for_share is no longer supported.
      # MAYBE: Delete the code for this option.
      'request_lock_for_share',
      # FIXME: 2012.09.25: Row locking for update is experimental. It's used
      #                    branches_prepare.
      'request_lock_for_update',
      #
      'grac_mgr',
      'item_mgr',
      #
      'finalized',         # One must call Query_Overlord.finalize() on each qb
      'leafier_stack_ids', # A list of leafier stack ids than those found
      #
      'branch_hier_limit', # For special item types that want 0 or 1 branches.
      )

   def __init__(self, db, username, branch_hier, rev,
                      viewport=None, filters=None, user_id=None):
      g.assurt(db)
      self.db = db
      g.assurt(isinstance(username, basestring))
      self.username = username
      #
      if user_id:
         self.user_id = user_id
      else:
         if self.username:
            try:
               self.user_id = User.user_id_from_username(db, username)
            except Exception, e:
               log.debug('User ID not found for user %s: %s'
                         % (username, str(e),))
               raise GWIS_Error('User ID not found for user "%s".'
                                % (username,))
         else:
            self.user_id = 0
      # For now, user_group_id must be set explicitly by the caller.
      self.user_group_id = None

      self.branch_hier_set(branch_hier)
      if ((self.branch_hier)
          and (   (isinstance(rev, revision.Current))
               or (isinstance(rev, revision.Historic))
               or (isinstance(rev, revision.Comprehensive)))):
         g.assurt(rev == branch_hier[0][1])
         # Not always the case: g.assurt(id(rev) == id(branch_hier[0][1]))
         # We just set this in branch_hier_set.
         g.assurt(id(self.revision) == id(self.branch_hier[0][1]))
      else:
         # This happens for revision.Updated and for getting branches, when
         # branch_hier is left empty.
         # MAYBE: Make a revision_set() command and move setup_gids to there
         #        from branch_hier_set.
         self.revision = rev
         # This also happens for scripts that accept --branch -1, meaning, all
         # branches. See tilecache_update.py, etc.
         if (not self.branch_hier) and self.username:
            # I.e., --branch -1, but not gia_userless.
            self.revision.setup_gids(self.db, self.username)
         # else: in branch_hier_set, we ran self.branch_hier[0][1].setup_gids
         #       -- is this ok for revision.Updated?

      self.viewport = viewport or Query_Viewport(None)
      self.filters = filters or Query_Filters(None)
      self.sql_clauses = None
      self.confirm_leafiness = False
      # We default using filters and viewports to True which is a little
      # counter-intuitive, since all other variables in this object default
      # to None or False.
      # FIXME: Call this skip_conditions instead?
      self.use_filters_and_viewport = True
      self.use_limit_and_offset = False
      self.diff_group = None
      self.diff_items = {}
      self.diff_counterparts = {}
      self.diff_counterparts['latter'] = []
      self.diff_counterparts['former'] = []
      #self.diff_counterparts['static'] = []
      self.diff_hier = None
      self.request_is_local = False
      self.request_is_script = False
      self.request_is_a_test = False
      self.request_is_secret = False
      self.cp_maint_lock_owner = False
      # Skipping, presumably to signify a Throolean: self.session_id
      self.remote_ip = None
      self.remote_host = None
      self.remote_what = None
      self.request_lock_for_share = False
      self.request_lock_for_update = False
      self.grac_mgr = None
      self.item_mgr = None
      self.finalized = False
      self.leafier_stack_ids = []
      self.branch_hier_limit = None

   # ***

   #
   def __str__(self):
      return (
            '%s(%d:%s) / br. %s / r. %s / v. %s / f. %s / sql. %s%s'
         % (
            #self.db,
            self.username,
            self.user_id,
            self.user_group_id,
            self.branch_hier,
            #self.branch_hier_str,
            self.revision,
            self.viewport,
            self.filters,
            self.sql_clauses,
            #self.confirm_leafiness,
            #self.use_filters_and_viewport,
            #self.use_limit_and_offset,
            #self.diff_group,
            #self.diff_items,
            #self.diff_counterparts,
            #self.diff_hier,
            #self.request_is_local,
            #self.request_is_script,
            #self.request_is_a_test,
            #self.request_is_secret,
            #self.cp_maint_lock_owner,
            (' / sssid %s' % (self.session_id,))
             if getattr(self, 'session_id', '') else '',
            #self.remote_ip,
            #self.remote_host,
            #self.remote_what,
            #self.request_lock_for_share,
            #self.request_lock_for_update,
            #self.grac_mgr,
            #self.item_mgr,
            #self.finalized,
            #self.leafier_stack_ids,
            #self.branch_hier_limit,
            ))

   #
   def branch_hier_set(self, branch_hier):
      # The branch hier is at least one deep and the leaf has no prev last rid.
      #log.verbose('branch_hier_set: %s' % (branch_hier,))
      g.assurt(not branch_hier
               or (isinstance(branch_hier[0], tuple)
                   # tuple is: (branch_stack_id, revision, branch_name,)
                   and isinstance(branch_hier[0][0], int)
                   and isinstance(branch_hier[0][1], revision.Revision_Base)
                   and isinstance(branch_hier[0][2], basestring)))
      # NOTE: We're not copy.copy()ing branch_hier. We used to, but we should
      #       not have to. The branch_hier should be considered immutable, and
      #       this makes it easier to maintain branch_hier[0][1] == revision.
      self.branch_hier = branch_hier
      # 2012.08.07: Probably want to reset revision, too, right?
      # MAYBE: Just delete self.revision and use branch_hier?
      if branch_hier:
         # 2013.04.04: No need to clone, right?
         # self.revision = branch_hier[0][1].clone()
         self.revision = branch_hier[0][1]
      else:
         self.revision = None
      # Is this right? Should we setup revision.gids? Otherwise it seems like
      # we always call it anyway...
      if self.username and self.branch_hier:
         self.branch_hier[0][1].setup_gids(self.db, self.username)
         if not self.revision.gids:
            log.warning('finalize: no group IDs from user: %s'
                        % (self.username,))
            g.assurt(False)

   #
   def branch_hier_where(self, tprefix='gia', include_gids=False,
                               allow_deleted=False):
      branch_query = ''

      if self.branch_hier:
         branch_query = revision.Revision.branch_hier_where_clause(
            self.branch_hier, tprefix, include_gids, allow_deleted)
      # else, self.branch_hier is None or empty, so we're searching for a list
      # of branches for a particular user, so don't restrict by branch ID.

      return branch_query

   #
   # MAYBE: Should db_clone=True should be the default. Hrmm...
   def clone(self, skip_clauses=False, skip_filtport=False,
                   db_get_new=False, db_clone=False):
      sql_clauses = None
      if (self.sql_clauses is not None) and (not skip_clauses):
         # FIXME: I [lb] think this operation is a wash. I think all the times
         # that clone() is called, the caller always sets sql_clauses itself.
         # For we're just wasting string math here. I think.
         sql_clauses = self.sql_clauses.clone()
      if not skip_filtport:
         viewport = self.viewport
         # FIXME: Shouldn't we be cloning filters?
         #filters = self.filters
         # FIXME: copy.copy is not perfect. Should really be out own clone, or
         # maybe a deepcopy. But if this even that important?
         filters = copy.copy(self.filters)
         use_filters_and_viewport = self.use_filters_and_viewport
         use_limit_and_offset = self.use_limit_and_offset
      else:
         viewport = None
         filters = None
         use_filters_and_viewport = False
         use_limit_and_offset = False
      g.assurt(not (db_get_new and db_clone))
      if db_get_new:
         db = db_glue.new()
      elif db_clone:
         db = self.db.clone()
      else:
         db = self.db
      #
      # HMMM: [lb] is not sure if we need to copy or not. But if we do copy,
      #       we need to maintain the relationship between the revision and
      #       branch_hier.
      branch_hier = copy.copy(self.branch_hier)
      if self.revision == self.branch_hier[0][1]:
         # revision.Current, revision.Historic
         g.assurt(self.revision.gids == self.branch_hier[0][1].gids)
         g.assurt(id(self.revision) == id(self.branch_hier[0][1]))
         rev = branch_hier[0][1]
      elif self.revision is not None:
         # revision.Updated
         rev = self.revision.clone()
      else:
         rev = self.revision # I.e., None
      #
      qb = Item_Query_Builder(db,
                              self.username,
                              # This makes a new list but the tuples are shared
                              # (so callers should not, e.g., hier[0][1] = ...)
                              branch_hier,
                              rev,
                              viewport,
                              filters,
                              self.user_id)
      # Already got: qb.username
      # Already got: qb.user_id
      qb.user_group_id = self.user_group_id
      # Already got: qb.branch_hier
      # Already got: qb.revision
      # Already got: qb.viewport
      # Already got: qb.filters
      # Except for gia_userless, which we always copy.
      if ((skip_filtport)
          and (not self.username)
          and (self.filters.gia_userless)):
         qb.filters.gia_userless = True
      qb.sql_clauses = sql_clauses
      # Skipping: qb.confirm_leafiness = self.confirm_leafiness
      qb.use_filters_and_viewport = use_filters_and_viewport
      qb.use_limit_and_offset = use_limit_and_offset
      # FIXME: Really clone diff_group? And diff_hier? Probably if copying
      #        revision.Diff object...
      qb.diff_group = self.diff_group
      # Skipping: qb.diff_items = self.diff_items
      # [mm] has enabled diff_counterparts cloning so that the functions that
      # create temporary tables can name their tables appropriately to avoid
      # the same table being created twice (funny why that happens...)
      #    e.g. item_manager::load_feats_and_attcs_load_stack_ids(..)
      # (2013.05.14)
      qb.diff_counterparts = self.diff_counterparts
      qb.diff_hier = self.diff_hier
      qb.request_is_local = self.request_is_local
      qb.request_is_script = self.request_is_script
      qb.request_is_a_test = self.request_is_a_test
      qb.request_is_secret = self.request_is_secret
      qb.cp_maint_lock_owner = self.cp_maint_lock_owner
      # Copy the session ID since we may have copied filters.gia_use_sessid.
      try:
         qb.session_id = self.session_id
      except AttributeError, e:
         pass
      qb.remote_ip = self.remote_ip
      qb.remote_host = self.remote_host
      qb.remote_what = self.remote_what
      # Skipping: qb.request_lock_for_share = self.request_lock_for_share
      # Skipping: qb.request_lock_for_update = self.request_lock_for_update
      qb.grac_mgr = self.grac_mgr
      qb.item_mgr = self.item_mgr
      # Skipping: qb.leafier_stack_ids = self.leafier_stack_ids
      # Skipping: qb.branch_hier_limit = self.branch_hier_limit
      # Since we copied filters.only_in_multi_geometry and diff_hier, we can
      # set qb.finalized.
      self.finalize_leafiness()
      qb.finalized = self.finalized
      # Skipping: qb.leafier_stack_ids
      # Skipping: qb.branch_hier_limit
      return qb

   #
   def get_userless_qb(self):

      username = '' # I.e., not anonymous.
      userless_qb = Item_Query_Builder(
         self.db, username, self.branch_hier, self.revision)

      # FIXME: request_is_local/request_is_script checks are comprised,
      #        since this fcn. is used by commit.py. Obviously, there
      #        are times that pyserver wants to bypass checking permissions,
      #        e.g., when deleting an attachment or geofeature, all link_values
      #        should be deleted; and when splitting a byway, all link_values
      #        should be cloned, i.e., think private user ratings. So there are
      #        non-script times when a permissionsless request is okay.
      #        But for now, we just lie and say this is a "safe" request.
      userless_qb.request_is_local = True
      userless_qb.request_is_script = True

      userless_qb.filters.gia_userless = True
      g.assurt(not userless_qb.revision.allow_deleted)
      g.assurt(self.item_mgr is not None)
      userless_qb.item_mgr = self.item_mgr
      userless_qb.grac_mgr = self.grac_mgr

      return userless_qb

   #
   def finalize(self):
      if self.username:
         # 2013.04.05: We used to call self.revision.setup_gids,
         #             but now that's called from branch_hier_set.
         try:
            g.assurt(len(self.revision.gids) > 0)
         except TypeError: # i.e., self.revision.gids is None
            pass # This is revision.Updated.
            g.assurt(isinstance(self.revision, revision.Updated))
      self.finalize_leafiness()

   #
   def finalize_leafiness(self):
      self.confirm_leafiness = False
      if (((self.filters is not None)
           and (self.filters.only_in_multi_geometry))
          or ((self.viewport is not None)
              and (self.viewport.include is not None))):
         # FIXME: This misses fcns. like, e.g., search_by_distance, that edit
         # inner. or outer.where and add a geometry filter.
         if len(self.branch_hier) > 1:
            self.confirm_leafiness = True
      # NOTE: See Query_Overlord, which sets self.finalized = True.
      #       We can also set it in clone(). But we can't get the geometry from
      #       this file, so we can't finalize ourselves normally

   #
   # This is just another way to invoke Query_Overlord.finalize_query
   def finalize_query(self):
      g.assurt(self.item_mgr is not None)
      self.item_mgr.finalize_query(self)

   #
   def definalize(self):
      # Resets filters used by SQL but not those that are the real filters, per
      # se. That is, you can call Query_Overlord.finalize_request() and you'll
      # get the same results (save for LIMIT and OFFSET).
      #
      # This call also resets the db cursor, to reclaim system memory.
      self.filters.pagin_count = 0
      self.filters.pagin_offset = 0
      self.filters.filter_by_regions = ''
      self.filters.only_in_multi_geometry = None
      self.db.dont_fetchall = False
      self.db.curs_recycle()
      self.confirm_leafiness = False
      self.diff_items = {}
      self.diff_counterparts = {}
      self.diff_counterparts['latter'] = []
      self.diff_counterparts['former'] = []
      #self.diff_counterparts['static'] = []
      self.diff_hier = None
      self.finalized = False
      self.leafier_stack_ids = []
      self.branch_hier_limit = None

   #
   def is_filled(self):
      # The following should not be None, but other members can be.
      log.verbose('is_filled: %s' % str(self))
      return (    (self.db is not None)
              and (isinstance(self.username, basestring))
              and (isinstance(self.user_id, int))
              # Skipping: user_group_id
              and (isinstance(self.branch_hier, list))
              # Not importing revision, so cannot use revision.Revision_Base
              and (self.revision is not None)
              and (isinstance(self.sql_clauses, Sql_Bi_Clauses))
              and (isinstance(self.filters, Query_Filters))
              and (isinstance(self.viewport, Query_Viewport))
              )

   #
   def prepare_temp_stack_id_table(self, table_name):

      # Make a temporary table for stack_ids.
      #self.db.sql("DROP TABLE IF EXISTS %s" % (table_name,))
      self.db.sql(
      #   CREATE TABLE %s (
         """
         CREATE TEMPORARY TABLE %s (
            stack_id INTEGER NOT NULL,
            branch_id INTEGER
         )
         """ % (table_name,))
      self.db.sql(
         """
         ALTER TABLE %s
            ADD CONSTRAINT %s_pkey
            PRIMARY KEY (stack_id)
         """ % (table_name, table_name,))

   #
   def load_stack_id_lookup(self, table_name, lookup, lhs=False, rhs=False):
      table_name = 'temp_stack_id__%s' % table_name
      self.prepare_temp_stack_id_table(table_name)
      if (not lhs) and (not rhs):
         self.filters.stack_id_table_ref = table_name
      elif lhs:
         g.assurt(not rhs)
         self.filters.stack_id_table_lhs = table_name
      else:
         g.assurt(rhs)
         self.filters.stack_id_table_rhs = table_name
      #
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
         log.verbose2('load_stack_id_lookup: on: %s...' % (table_name,))
      #
      g.assurt(lookup)
      if isinstance(lookup, dict):
         self.db.sql(
            "INSERT INTO %s (stack_id) VALUES %s"
            % (table_name,
               #','.join([('(%s)' % str(x)) for x in lookup.iterkeys()]),))
               ','.join([('(%d)' % int(x)) for x in lookup.iterkeys()]),))
      elif isinstance(lookup, list) or isinstance(lookup, set):
         # Rather than running a bunch of INSERTs, run just one.
         # NO: for stack_id in lookup:
         #        self.db.sql(
         #           "INSERT INTO %s (stack_id) VALUES (%d)"
         #           % (table_name, stack_id,))
         self.db.sql(
            "INSERT INTO %s (stack_id) VALUES %s"
            % (table_name,
               #','.join([('(%s)' % str(x)) for x in lookup]),))
               ','.join([('(%d)' % int(x)) for x in lookup]),))
      else:
         # For now, this fcn. just supports dicts with stack IDs as keys, or
         # lists. Modify as needed to support other collection types.
         g.assurt(False)
      #

      conf.debug_log_mem_usage(log, usage_0, 'iqb.load_stack_id_lookup')

      return table_name

   # ***

# ***

if (__name__ == '__main__'):
   pass


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# A versioned item is one that follows the valid-start/valid-until
# revisioning model.

import os
import re
import sys
import traceback
import uuid

import conf
import g

from grax.library_squelch import Library_Squelch
#from gwis.query_filters import Query_Filters
#from gwis.query_viewport import Query_Viewport
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import item_base
from item import item_stack
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import misc

__all__ = ['One', 'Many',]

log = g.log.getLogger('item_versioned')

class One(item_stack.One):
   '''
   Represents a single database row, sometimes with additional (calculated)
   values of interest to the client. For instance, byway items also include
   interesting ratings values and also indicate if there are attachments 
   associated with the byway.
   '''

   item_type_id = None
   item_type_table = 'item_versioned'
   item_gwis_abbrev = None
   child_item_types = None

   # These columns exist in all of the item type tables.
   shared_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      # 2012.05.04: [lb] asks: what don't we send system_id to flashclient?
      # 2013.03.25: [mm] says: we should send because item-read-event needs it.
      ('system_id',           None,   True,   True,    int,  None, 'syid'),
      ('branch_id',           None,   True,  False,    int,     3, 'brid'),
      ('stack_id',            None,   True,  False,    int,     2, 'stid'),
      ('version',                0,   True,  False,    int,     2,    'v'),
      ]
   # These columns only exist in the item_versioned table.
   local_defns = [
      ('deleted',            False,  False,  False,   bool,     0,  'del'),
      ('reverted',           False,  False,  False,   bool,     0,  'rvt'),
      # 2012.06.28: name used to be mandatory... But work_items and even 
      #             on import: do we need to enforce a naming policy?
      #             It seems that everything *should* be named, but we can
      #             just get it in post, as they say, right?
      # 2012.07.29: Name should be None so that it doesn't get changed to '' 
      # by accident, i.e., if it's not set via client, it needs to be None,
      # otherwise we'll be confused when client wants it to be ''.
      ('name',                None,   True,  False,    str,     0),
      ('valid_start_rid',     None,  False,  False,    int,     3),
      ('valid_until_rid',     None,  False,  False,    int,     3),
      ]
   attr_defns = item_stack.One.attr_defns + shared_defns + local_defns
   psql_defns = item_stack.One.psql_defns + shared_defns
   gwis_defns = item_stack.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   private_defns = item_stack.One.psql_defns + shared_defns + local_defns
   #
   cols_copy_nok = item_stack.One.cols_copy_nok + (
      [
       'system_id',
       'branch_id',
       'stack_id',
       'version',
       'deleted',
       #
       'reverted',
       'valid_start_rid',
       'valid_until_rid',
       ])

   __slots__ = ([
      'client_id',
      ]
      + [attr_defn[0] for attr_defn in shared_defns]
      + [attr_defn[0] for attr_defn in local_defns]
      )

   # *** Constructor

# FIXME: logcheck looks for WARNING, not WARN

   # It seems a little hacky (increases coupling) to have items know about the 
   # request, but it makes things easy....
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      self.client_id = 0
      #log.debug('item_versioned.__init__: row: %s / req: %s' % (row, req, ))
      item_stack.One.__init__(self, qb, row, req, copy_from)
      if (not self.branch_id) and (req is not None):
         # This is the case for GWIS requests for non-grac items.
         self.branch_id = req.branch.branch_id
      # else, if it was set in row, we grabbed it.
      # The stack ID is still the client ID that the client was using;
      # it'll get corrected after all client items are hydrated.
      # FIXME: This is right, right?
      self.client_id = self.stack_id

      # 2013.08.15: Items with client IDs are always fresh, right?
      if (self.stack_id is not None) and (self.stack_id < 0):
         self.fresh = True

      # Not for GrAC: g.assurt(self.branch_id > 0)

   # *** Built-in Function definitions

   #
   def __str__(self):
      return ('"%s" [%s]' 
              % (self.name,
                 self.__str_deets__(),))

   #
   def __str_deets__(self):
      # MAYBE: Add self.valid_start_rid and self.valid_until_rid?
      flags_str = (
         '%s%s%s%s%s' 
         % ('+DEL'            if self.deleted   else  '',
            '+REV'            if self.reverted  else  '',
            '+NEW'            if self.fresh     else  '',
            '+VLD'            if self.valid     else  '',
            '+DTY'            if self.dirty     else  '',))
      return (
         '%s:%s%s.v%s%s/ss%s-b%s' 
         % (misc.module_name_simple(self),
            self.stack_id     if self.stack_id is not None  else 'X', 
            ('(%sc)' % self.client_id) 
                              if self.client_id < 0         else  '',
            self.version      if self.version is not None   else 'X', 
            flags_str,
            self.system_id    if self.system_id is not None else 'X', 
            self.branch_id    if self.branch_id is not None else 'X',))

   #
   def __str_abbrev__(self):
      return ('"%s" | %s [%s]' % (
         self.name,
         #(self.item_type_table or self.__class__),
         self.__class__.__module__,
         self.stack_id,))

   #
   def __str_verbose__(self):
      return self.__str__()

   # *** GML/XML Processing

   #
   def col_to_attr(self, row, attr_defn, copy_from):
      item_stack.One.col_to_attr(self, row, attr_defn, copy_from)

   #
   def from_gml(self, qb, elem):
      item_stack.One.from_gml(self, qb, elem)
      if self.version < 0:
         raise GWIS_Error('The version attr must be non-negative.')
      # 2013.08.15: Items with client IDs are always fresh, right?
      #log.debug('from_gml: before: client_id: %s / stack_id: %s / %s'
      #          % (self.client_id, self.stack_id, self,))
      self.client_id = self.stack_id
      g.assurt(self.stack_id is not None)
      if self.stack_id < 0:
         self.fresh = True
      #log.debug('from_gml: after: client_id: %s / stack_id: %s / %s'
      #          % (self.client_id, self.stack_id, self,))

   # *** Pre-Saving

   #
   def mark_deleted_update_sql(self, db):
      rows = db.sql(
         "UPDATE %s SET deleted = TRUE WHERE system_id = %d"
         % (One.item_type_table, self.system_id,))
      g.assurt(rows is None)

   # 
   def version_finalize_and_increment(self, qb, rid, same_version=False,
                                                     same_revision=False):
      '''Set my metadata appropriately: increment my version number, mark
         myself as beginning life now, and mark end-of-life on the previous
         versioned revision, if one exists.'''

      log.verbose('version_finalize_and_increment: %d' % (rid,))

      g.assurt((rid == 1)
               or (rid == qb.item_mgr.rid_new)
               # This is for, e.g., saving '/item/alert_email' link_values.
               or (same_revision))

      if (self.valid_start_rid is None) or (self.version > 0):
         self.valid_start_rid = rid
      elif ((not qb.request_is_local)
            or (self.valid_start_rid != 1)
            or (not self.version_finalize_preset_is_okay())):
         raise GWIS_Error('The valid_start_rid attr must not be set.')
      # else, ccp.py wants to create a new group_ or group_membership with
      #       valid_start_rid = 1.

      self.valid_until_rid = conf.rid_inf

      # See if this item has been saved before.
      g.assurt(self.stack_id > 0)
      if self.version > 0:
         g.assurt((self.system_id is not None) or (same_version))
         # If we're saving a new leafy (a/k/a branchy) item, we must check if 
         # the item was previously reverted. If it was, we'll want to update
         # the last record's valid_until_rid and use its version number.
         # NOTE: Call this fcn. now, before finalize_last_version_at_revision,
         #       since version_load_reverted may set self.branch_id = ....
         if self.branch_id:
            if self.branch_id != qb.branch_hier[0][0]:
               self.version_load_reverted(qb)
            # If this item has been saved to the leaf branch before, update the
            # last record's valid_until_rid.
            if self.branch_id == qb.branch_hier[0][0]:
               self.finalize_last_version_at_revision(qb, rid, same_version)
            # else, item new to leaf branch; leave parent branch's item alone.
         # else, this is a new, revisionless item, whose system_id is None.
      else:
         # If the item was built with copy_from, its system_id might be set 
         # and its branch_id might be a parent branch id. (I [lb] think
         # copy_from is just used when creating split byways... and copying
         # their link_values.)
         g.assurt((self.system_id is None) 
                  or (self.branch_id != qb.branch_hier[0][0]))

      # Clear the system_id so a new one is drawn and increment the version.
      if not same_version:
         self.system_id = None

      # Set the branch id. If we used copy_from, we might have had a handle to
      # the old'n, or if we're copying to a leafier branch we have a handle to
      # a parent branch.
      # 2012.09.25: We can use the new branch_id fcn. now, can't we?
      #             Old way: self.branch_id = qb.branch_hier[0][0]
      self.branch_id = self.save_core_get_branch_id(qb)

      # Bump the vers. Maybe.
      if not same_version:
         self.version += 1

      # Make sure the item is marked for saving.
      if not self.dirty:
         # New routes follow this path.
         # EXPLAIN: Why isn't the new route marked dirty? Oh, well...
         log.debug('vers_fnlz_n_inc: mean and clean: %s' % (self,))
         if not same_version:
            dirty_reason = item_base.One.dirty_reason_item_auto
         else:
            # If we didn't bump the version, we bumped the acl_grouping, which
            # only applies to group_item_access records (so grac records will
            # be updated but the item won't be touched).
            dirty_reason = item_base.One.dirty_reason_grac_auto
         self.dirty_reason_add(dirty_reason)
      else:
         # 2013.12.19: The 'if not self.dirty' is new, so make sure nothing
         # dumps through here without all the dirties set.
         log.debug('vers_fnlz_n_inc: nice and dirty: %s / %s'
                   % (hex(self.dirty), self,))

   #
   def version_load_reverted(self, qb):
      log.verbose2('version_load_reverted (1): %s' % (str(self),))
      find_reverted_sql = (
         """
         SELECT 
            system_id
            , branch_id
            , version
         FROM 
            item_versioned 
         WHERE 
            stack_id = %d
            AND branch_id = %d
            AND valid_until_rid = %d
            AND reverted IS TRUE
         """ % (self.stack_id,
                qb.branch_hier[0][0],
                conf.rid_inf,))
      rows = qb.db.sql(find_reverted_sql)
      if rows:
         g.assurt(len(rows) == 1)
         self.system_id = rows[0]['system_id']
         g.assurt(rows[0]['branch_id'] > self.branch_id)
         self.branch_id = rows[0]['branch_id']
         g.assurt(rows[0]['version'] > self.version)
         self.version = rows[0]['version']
         log.verbose2('version_load_reverted (2): %s' % (str(self),))

   # "Finalize" the existing item row before saving the new item row.
   # Basically, just change its valid_until_rid from infinity to whatever the
   # current revision is.
   #
   def finalize_last_version_at_revision(self, qb, rid, same_version):

      log.verbose2(
         'version_finalize: typ: %s / r: %s / sys: %s / br: %s / same_v: %s'
         % (One.item_type_table, rid, self.system_id, self.branch_id, 
            same_version,))

      if not same_version:
         # Make sure to use the branch_id: when we load items, we load them at
         # for a specific branch, but the loaded item doesn't indicate to which
         # branch in the hierarchy it belongs. That is, when you call
         # item_mgr.load_feats_and_attcs, all items have the same branch_id
         # as qb.branch_hier[0][0].
         qb.db.sql(
            """
            UPDATE %s SET valid_until_rid = %s
            WHERE (system_id = %s) AND (branch_id = %d)
            """ % (One.item_type_table, rid,
                   self.system_id, qb.branch_hier[0][0],))

   #
   def version_finalize_preset_is_okay(self):
      return False

   # *** Saving to the Database

   #
   def group_ids_add_to(self, group_ids, rid):
      ''''''
      g.assurt(False) # Abstract

   #
   def save_core(self, qb):
      g.assurt(isinstance(qb.revision, revision.Current))
      item_stack.One.save_core(self, qb)
      # For fresh items and items being saved for the first time to a leafy
      # branch, the system ID hasn't been set. For existing items, we're saving
      # a new version, so we want a new system_id.
      # However, depending on if we're making a new revision or not, we might
      # get a new ID directly from the sequence (e.g., for saving new routes),
      # or we might get a new ID from an internal list (e.g., for commit and 
      # import, so we can rollback and return sequence IDs to the pool).
      self.system_id = qb.item_mgr.seq_id_next_system_id(qb)
      # The branch might represent the item from a parent branch, so set it
      # according to the commit context.

      # VERIFY: We updated the branch ID earlier...
      new_branch_id = self.save_core_get_branch_id(qb)
      g.assurt((self.branch_id is None) or (self.branch_id == new_branch_id))
      self.branch_id = self.save_core_get_branch_id(qb)

      # Save the item_versioned row before derived tables save their new rows.
      self.save_insert(qb, One.item_type_table, One.private_defns)

   #
   def save_core_get_branch_id(self, qb):
      # Whenever saving any item that's not a branch, we use the leafiest
      # branch indicated by the branch_hier.
      return qb.branch_hier[0][0]

   #
   def save_related_maybe(self, qb, rid):
      item_stack.One.save_related_maybe(self, qb, rid)

   #
   def save_update(self, qb):
      g.assurt(self.system_id)
      g.assurt(self.branch_id)
      g.assurt(self.stack_id)
      g.assurt(self.version)
      g.assurt(self.valid_start_rid)
      g.assurt(self.valid_until_rid)
      # ??
      g.assurt((self.client_id < 0) or (self.stack_id == self.client_id))
      #
      # ??
      #self.client_id = self.stack_id
      #
      self.save_insert(qb, One.item_type_table, One.private_defns, 
                       do_update=True)

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, item):

      insert_expr = (
         "(%d, %d, %d, %d, %s, %s, %s, %d, %d)"
         % (item.system_id,
            #? qb.branch_hier[0][0],
            # or:
            item.branch_id,
            item.stack_id,
            item.version,
            "TRUE" if item.deleted else "FALSE",
            "TRUE" if item.reverted else "FALSE",
            qb.db.quoted(item.name) if item.name else 'NULL',
            item.valid_start_rid,
            item.valid_until_rid,
            ))

      return insert_expr

   # ***

# ***

class Many(item_stack.Many):
   '''
   Represents multiple item rows from the database, implemented as a list of
   One() objects.
   '''

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      item_stack.Many.__init__(self)

   # *** Query Builder helpers

   #
   # Usage: 
   #   self.query_builderer(qb=qb)
   #   self.query_builderer(qb)
   #   self.query_builderer(db, username, branch_id, rev)
   #   self.query_builderer(db, username, branch_hier, rev)
   #   self.query_builderer(db, username, branch_hier, rev,
   #                        viewport, filters)
   def query_builderer(self, *args, **kwargs):
      g.assurt(not (args and kwargs))
      try:
         qb = kwargs['qb']
      except KeyError:
         argn = len(args)
         if argn == 1:
            qb = args[0]
            g.assurt(isinstance(qb, Item_Query_Builder))
         else:
            g.assurt((argn >= 4) and (argn <= 6))
            db = args[0]
            g.assurt(isinstance(db, db_glue.DB))
            username = args[1]
            g.assurt(isinstance(username, str))
            branch_hier = args[2]
            if isinstance(branch_hier, int):
               # NOTE: Using args[3], which is rev.
               # DEPRECATE: This is so weird not using branch_hier_build...
               #        I really think the qb should be built outside the item
               #        classes, so replace all calls to, e.g., 
               #    search_by_stack_id(db, username, branch... _id/_hier, rev)
               # There shouldn't be any callers left using this.... ....right?
               log.warning('Deprecated: reducing branch_hier to leafiest')
               branch_hier = [(branch_hier, args[3], '',)]
            elif isinstance(branch_hier, tuple):
               g.assurt(isinstance(branch_hier[0], int))
               g.assurt(isinstance(branch_hier[1], revision.Revision_Base))
               g.assurt(isinstance(branch_hier[2], basestring))
               branch_hier = [branch_hier,]
               log.debug('query_builderer: making single-tuple branch_hier: %s'
                         % (branch_hier,))
            else:
               log.debug('query_builderer: leaving branch_hier: %s' 
                         % (branch_hier,))
            g.assurt(isinstance(branch_hier, list) 
                     and isinstance(branch_hier[0], tuple))
            rev = args[3]
            # For Diff or Updated, make the qb and call finalize on it.
            g.assurt(isinstance(rev, revision.Current)
                     or isinstance(rev, revision.Historic))
            try:
               viewport = args[4]
               #g.assurt(isinstance(viewport, Query_Viewport))
            except IndexError:
               viewport = None
            try:
               filters = args[5]
               #g.assurt(isinstance(filters, Query_Filters))
            except IndexError:
               filters = None
            if (viewport is None) and (filters is None):
               # A little hack since this fcn. predates the Query_Overlord, so
               # we don't have to refactor old code.
               finalized = True
            else:
               # Who uses this still?
               g.assurt(False)
               finalized = False
            qb = Item_Query_Builder(db, username, branch_hier, rev,
                                    viewport, filters)
            qb.finalize()
            #qb.finalized = finalized
            qb.finalized = True
            # NOTE: I think we don't have to worry about calling 
            #       Query_Overlord.finalize_query(qb) because the multi 
            #       geometry should already have been computed and 
            #       stored as part of qb.filters.
      return qb

   # *** SQL query_filters helper

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not conjunction) or (conjunction == "AND"))

      # 2013.12.23: Moving item_findability-related filtering from route.py,
      #             so every item can use it.
      #
      # MAYBE: Add client support for more than just routes? Maybe, tracks?
      #        Regions? A list of all recently viewed items, of all types?

      if self.sql_enabled_squelch_circuitry():
         if not qb.filters.use_stealth_secret:
            gwis_errs = [] # Ignored, but oh, well.
            # itype is, e.g., Item_Type.ROUTE, or 'route'.
            itype = self.one_class.item_type_id
            if not qb.filters.get_id_count(itype, gwis_errs):
               where_clause, conjunction = self.sql_apply_squelch_filters(qb,
                                                   where_clause, conjunction)
            # else, searching by stack_id, so ignore item_findability.
         # else, using stealth_secret, so ignore item_findability.
      elif (   (qb.filters.findability_recent)
            or (qb.filters.findability_ignore)):
         raise GWIS_Error('Wrong item type for findability_recent')
      # else, item type doesn't squelch, so don't tune squelch filter.

      return item_stack.Many.sql_apply_query_filters(
                  self, qb, where_clause, conjunction)

   #
   def sql_apply_squelch_filters(self, qb, where_clause="", conjunction=""):

      # See if the user wants their recent history (findability_recent)
      # or if they are searching the route library (else).
      if qb.filters.findability_recent:
         # Routes viewed history.
         where_clause, conjunction = self.sql_apply_squelch_filter_recent(
            qb, where_clause, conjunction)
      else:
         # Route library.
         where_clause, conjunction = self.sql_apply_squelch_filter_library(
            qb, where_clause, conjunction)

      return (where_clause, conjunction,)

   #
   def sql_apply_squelch_filter_recent(self, qb, where_clause="",
                                                 conjunction=""):

      if qb.username == conf.anonymous_username:
         raise GWIS_Error('Anon users have no server-side item_findability')

      qb.sql_clauses.inner.shared += (
         """
         , usrf.last_viewed
         """)

      if qb.filters.gia_use_sessid:
         join_prefix = "LEFT OUTER"
      else:
         join_prefix = ""
      qb.sql_clauses.inner.join += (
         """
         %s JOIN item_findability AS usrf
            ON ((usrf.item_stack_id = gia.stack_id)
                AND (usrf.username = %s))
         """ % (join_prefix,
                qb.db.quoted(qb.username),))

      # 2014.06.30: These two route library features are not fully tested:
      #             ignoring an item's findability, and including deleted.
      if not qb.filters.findability_ignore:
         where_in_history = "(usrf.show_in_history IS TRUE)"
      if qb.filters.findability_ignore_include_deleted:
         qb.revision.allow_deleted = True
      if qb.filters.gia_use_sessid:
         where_in_history = ("((gia.session_id = %s) OR %s)"
                             % (qb.db.quoted(qb.session_id),
                                where_in_history,))
      where_clause += ("%s %s" % (conjunction, where_in_history,))
      conjunction = "AND"

      # NOTE: Order by DESC puts NULLs first. So Session ID matches will
      #       be up top. Makes sense....
      g.assurt(qb.sql_clauses.outer.order_by)
      qb.sql_clauses.outer.order_by = (
         """
         group_item.last_viewed DESC
         """)

      return (where_clause, conjunction,)

   #
   def sql_apply_squelch_filter_library(self, qb, where_clause="",
                                                  conjunction=""):

      if qb.filters.gia_use_sessid:
         # Clients don't currently combine route library lists and session IDs.
         # Not that it won't work. The user will just see a mix of routes
         # requested during their session and routes that are libraried.
         log.warning('sql_apply_squelch_filter_library: unexpected')

      where_squelch = ""

      if not qb.filters.findability_ignore:

         # If the user is using search terms, include items that are findable.
         # Ignoring: qb.filters.filter_by_creator_include/_exclude, which is
         #           used to filter by item creator, i.e., "my routes",
         #           "everyone's routes", etc.
         if (

             False # FIXME: Implement searching routes by specific user.
             #? or qb.filters.filter_by_username

             # FIXME: If you search on an almost empty string... won't you
             #     find everything, anyway? Or maybe we don't allow that...?
             #     Maybe searchability is not as special as it seems... but
             #     how many people search? Maybe it has some value after all.
             or qb.filters.filter_by_names_exact
             or qb.filters.filter_by_text_loose
             or qb.filters.filter_by_text_smart

             ):

            # Look for both libraried routes and routes that are findable.
            sql_library_squelch = (
               "IN (%d, %d)"
               % (Library_Squelch.squelch_show_in_library,
                  Library_Squelch.squelch_searches_only,))
                  # The third squelch is: squelch_always_hide
                  #

         # Otherwise, only find items that are libraried.
         else:
            sql_library_squelch = (
               "= %d" % (Library_Squelch.squelch_show_in_library,))

         # 2014.07.02: Don't include public library items if filtering
         #             by a specific user.
         # 2014.07.21: The item_revisionless class adds a WHERE on edited_user
         #             based on filter_by_creator_include, so it probably
         #             wouldn't matter if we always joined the table.
         if not qb.filters.filter_by_creator_include:

            # The anonymous user records in item_findability indicate
            # an item's findability in the public route library.
            qb.sql_clauses.inner.join += (
               """
               LEFT OUTER JOIN item_findability AS pubf
                  ON (    (pubf.item_stack_id = gia.stack_id)
                      AND (pubf.username = %s))
               """ % (qb.db.quoted(conf.anonymous_username),))

            # When a user gets a new route, the user is made its arbiter.
            #
            # Previously, we didn't create item_findability records for these
            # routes, so, by default, they'll show up in the route list if
            # there's a public-viewer GIA record for the route. But now we
            # create item_findability records for new routes and change the
            # default to not showing the routes in the library once they're
            # made public.
            where_squelch = (
               """(   (pubf.library_squelch IS NULL)
                   OR (pubf.library_squelch %s))
               """ % (sql_library_squelch,))

         if (    (qb.username != conf.anonymous_username)
             and (qb.username != qb.filters.filter_by_creator_exclude)):

            qb.sql_clauses.inner.join += (
               """
               LEFT OUTER JOIN item_findability AS usrf
                  ON (    (usrf.item_stack_id = gia.stack_id)
                      AND (usrf.username = %s))
               """ % (qb.db.quoted(qb.username),))

            user_squelch = "(usrf.library_squelch %s)" % (sql_library_squelch,)

            if where_squelch:
               where_squelch = (
                  """
                  (((usrf.library_squelch IS NULL) AND %s)
                   OR %s)
                  """ % (where_squelch,
                         user_squelch,))
            else:
               where_squelch = user_squelch

      if where_squelch:
         where_clause += ("%s %s" % (conjunction, where_squelch,))
         conjunction = "AND"

      return (where_clause, conjunction,)

   # ***

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):

      where_clause = ""

      conjunction = "AND"

      if qb.viewport.include is not None:
         # FIXME: PERFORMANCE: Would putting this in the JOIN or specifying
         # geofeature before group_item_access (using join_collapse_limit)
         # speed up fetching with a bbox? [lb]'s concern is that the geofeature
         # table should be searched first, then the group_item_access and group
         # and user tables.
         where_clause += (
            " %s %s " 
            % (conjunction,
               qb.viewport.as_sql_where(qb.revision, geo_table_name),))
         conjunction = "AND"
         # Searching by bbox misses items in leafier branches that have been
         # moved (their geometry) outside of the viewport. So we need to
         # check each item and see if a more leafy item exists. (Tricky,
         # isn't it? =) We set this value previously in finalize_query.
         g.assurt((len(qb.branch_hier) == 1) or qb.confirm_leafiness)

      # Note that attachment doesn't call this fcn. but processes
      # only_in_multi_geometry on its own, so we can expect
      # geo_table_name to be set.
      if qb.filters.only_in_multi_geometry:
         #log.debug('sql_apply_query_filters: multi_geom: %s' 
         #          % (qb.filters.only_in_multi_geometry,))
         g.assurt(qb.filters.filter_by_regions
                  or qb.filters.filter_by_watch_geom)
         g.assurt(geo_table_name)
         #where_clause += (
         #   """
         #   %s (ST_Intersects(%s.geometry, '%s'))
         #   """ % (conjunction, 
         #          geo_table_name, 
         #          qb.filters.only_in_multi_geometry,))
         #where_clause += (
         #   """
         #   %s (ST_Intersects(%s.geometry, ST_SetSRID('%s'::GEOMETRY, %d))
         #   """ % (conjunction, 
         #          geo_table_name, 
         #          qb.filters.only_in_multi_geometry,
         #          conf.default_srid,))
         where_clause += (
            """
            %s (ST_Intersects(%s.geometry, '%s'::GEOMETRY))
            """ % (conjunction, 
                   geo_table_name, 
                   qb.filters.only_in_multi_geometry,))
         conjunction = "AND"

      return where_clause

   #
   def sql_enabled_squelch_circuitry(self):
      # By default, when fetching non-specific items (read: all, i.e.,
      # qb.filters is emptyish), the item_findability table is ignored.
      return False

   #
   def sql_inner_where_extra(self, qb, branch_hier, br_allow_deleted, 
                                   min_acl_id):
      return ""

   #
   def sql_outer_select_extra(self, qb):
      return ""

   #
   def sql_outer_where_extra(self, qb, branch_hier, br_allow_deleted, 
                                   min_acl_id):
      return ""

   # ***

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      where_clause = ""
      conjunction = ""
      outer_where = ""
      for table_col in table_cols:
         (where_clause, conjunction, outer_where,
            ) = self.sql_apply_query_filter_by_text_tc(qb,
                  table_col, stop_words, where_clause, conjunction,
                  use_outer, outer_where)
      if outer_where:
         qb.sql_clauses.outer.where += ' AND %s ' % (outer_where,)
      return where_clause

   #
   def sql_apply_query_filter_by_text_tc(self, qb, table_col,
                                                   stop_words,
                                                   where_clause,
                                                   conjunction,
                                                   use_outer,
                                                   outer_where):

      # Only select items whose name matches the user's search query.
      # But if multiple search columns or search filters are specified,
      # just OR them all together (this is so, e.g., search threads
      # looks in both the thread name and the post body).

      # See below for a bunch of comments are the different postgres
      # string comparison operators (=, ~/~*, and @@).

      if qb.filters.filter_by_text_exact:
         filter_by_text_exact_lower = qb.filters.filter_by_text_exact.lower()
         where_clause += (
            """
            %s (LOWER(%s) = %s)
            """ % (conjunction,
                   table_col,
                   # qb.db.quoted(qb.filters.filter_by_text_exact),
                   #    %s (LOWER(%s) = LOWER(%s))
                   qb.db.quoted(filter_by_text_exact_lower),))
         conjunction = "OR"

      # This is like the previous filter but allows the user to specify a list.
      if qb.filters.filter_by_names_exact:
         item_names = [x.strip().lower()
                       for x in qb.filters.filter_by_names_exact.split(',')]
         name_clauses = []
         for item_name in item_names:
            # item_name is the empty string if input contained ,,
            if item_name:
               name_clauses.append("(LOWER(gia.name) = %s)"
                                   % (qb.db.quoted(item_name),))
         name_clauses = " OR ".join(name_clauses)
         where_clause += (
            """
            %s (%s)
            """ % (conjunction,
                   name_clauses,))
         conjunction = "OR"

      if qb.filters.filter_by_text_loose:
         # NOTE: ~* does case-insensitive regex matching. This is slower than
         #       using =, but this is how we get a loose search. Consider
         #         select 'a' ~ 'a b c'; ==> false
         #         select 'a b c' ~ 'a'; ==> true
         #       meaning if the user searches 'lake' they get all the lakes.
         if not use_outer:
            where_clause += (
               """
               %s (%s ~* %s)
               """ % (conjunction, 
                      table_col,
                      qb.db.quoted(qb.filters.filter_by_text_loose),))
            conjunction = "OR"
         else:
            sub_where = (" (%s ~* %s) "
                         % (table_col,
                            qb.db.quoted(qb.filters.filter_by_text_loose),))
            if not outer_where:
               outer_where = sub_where
            else:
               outer_where = (" (%s OR (%s ~* %s)) "
                              % (outer_where,
                                 table_col,
                                 qb.db.quoted(qb.filters.filter_by_text_loose),
                                 ))

      # For filter_by_text_smart and filter_by_text_full:
      tsquery = None

      # Callers should only specify columns that are properly indexed for
      # full text search, since that's the column we really want (if we use
      # the normal-named column, Postgres does an inline index on the text).
      (table, column) = table_col.split('.', 1)
      table_col = '%s.tsvect_%s' % (table, column,)
      # FIXME: l18n. Hard-coding 'english' for now.
      # NOTE: Avoid plainto_tsquery, which applies & and not |.
      #       Or is that what we want??
      #where_clause += (
      #   """
      #   %s (%s @@ plainto_tsquery('english', %s))
      #   """ % (conjunction, 
      #          table_col,
      #          qb.db.quoted(qb.filters.filter_by_text_smart),))

      if qb.filters.filter_by_text_smart:

         # Get a list of "quoted phrases".
         query_text = qb.filters.filter_by_text_smart
         query_terms = re.findall(r'\"[^\"]*\"', query_text)
         # Remove the quotes from each multi-word term.
         raw_terms = [t.strip('"').strip() for t in query_terms]
         # Cull the "quoted phrases" we just extracted from the query string.
         (remainder, num_subs) = re.subn(r'\"[^\"]*\"', r' ', query_text)
         # Add the remaining single-word terms.
         raw_terms.extend(remainder.split())

         # Remove all non-alphanums and search just clean words.
         clean_terms = set()
         for raw_term in raw_terms:
            cleaned = re.sub(r'\W', ' ', raw_term).split()
            for clean_word in cleaned:
               if (not stop_words) or (clean_word not in stop_words.lookup):
                  clean_terms.add(clean_word)
            # Add the original string-term, too.
            if cleaned and ((len(cleaned) > 1) or (cleaned[0] != raw_term)):
               if (not stop_words) or (raw_term not in stop_words.lookup):
                  # 2014.08.19: Watch out for, e.g., "Ruttger's" (as in,
                  # (Ruttger's Resort), which splits on the \W to "Ruttger s"
                  # but whose raw term remains "Ruttger's": the single quote
                  # is special to full text search so remove 'em all.
                  raw_sans_single_quote = re.sub("'", '', raw_term)
                  clean_terms.add(raw_sans_single_quote)

         approved_terms = []
         for clean_term in clean_terms:
            # MAGIC_NUMBER: Short terms are okay when &'ed to another term, but
            # on their own, they're not very meaningful. E.g., searching 'st'
            # would return half the byways. And [lb] cannot think of any one-
            # or two-letter words that would be important to search on their
            # own.
            if len(clean_term) > 2:
               approved_terms.append(clean_term)
         if not approved_terms:
            nothing_to_query = True
         else:
            # Special Case: Check if query is all stop words.
            sql_tsquery = ("SELECT to_tsquery('%s')"
                           % ('|'.join(approved_terms),))
            dont_fetchall = qb.db.dont_fetchall
            qb.db.dont_fetchall = False
            rows = qb.db.sql(sql_tsquery)
            qb.db.dont_fetchall = dont_fetchall
            g.assurt(len(rows) == 1)
            nothing_to_query = not rows[0]['to_tsquery']
         if nothing_to_query:
            approved_terms = []
            log.info(
               'sql_apply_query_filter_by_text_tc: only stop words: %s'
               % (qb.filters.filter_by_text_smart,))
            # Stop processing the request now.
            #raise GWIS_Warning(
            #   'Too vague: Please try using more specific search terms.')

         # Quote each andd everything.
         if raw_terms and (raw_terms.sort() != approved_terms.sort()):
            quoted_terms = ["'%s'" % (' '.join([x for x in raw_terms]),),]
         else:
            quoted_terms = []
         quoted_terms.extend([
            "'%s'" % (qb.db.quoted(term),) for term in approved_terms])
         tsquery = "|".join(quoted_terms)

      if qb.filters.filter_by_text_full:

         # This is only used internally. It's a ready-to-go string, like
         # ''123 main st''|''minneapolis''|''main st''
         tsquery = qb.filters.filter_by_text_full

      if tsquery and (qb.filters.filter_by_text_smart
                   or qb.filters.filter_by_text_full):

         where_clause += (
            """
            %s (%s @@ to_tsquery('english', '%s'))
            """ % (conjunction, table_col, tsquery,))
         conjunction = "OR"
         # Sort the full text results by relevance.
         if True:
            # The ts_rank_cd function returns a number from 0 to whatever,
            # adding 0.1 for every matching word. E.g.,
            #  select ts_rank_cd(
            #    to_tsvector('english', 'route|route|hello|hello'),
            #    to_tsquery('english', 'hello|route'));
            # returns 0.4 and not just 0.2 because the query includes
            # the same words twice... so if the user includes a search
            # term multiple times, any results with that term will be
            # ranked even higher.
            qb.sql_clauses.outer.enabled = True

            # An example of how one might use debuggery_print_next_sql:
            #  conf.debuggery_print_next_sql += 1

            qb.sql_clauses.inner.shared += (
               """
               , %s
               """ % (table_col,))
            qb.sql_clauses.outer.select += (
               """
               , ts_rank_cd(group_item.tsvect_%s,
                            to_tsquery('english', '%s'))
                  AS fts_rank_%s
               """ % (column,
                      tsquery,
                      column,))
            qb.sql_clauses.outer.group_by += (
               """
               , fts_rank_%s
               """ % (column,))
            qb.sql_clauses.outer.order_by_enable = True
            # Route will add edited_date DESC, which we don't want when
            # ranking by test.
            comma_maybe = ', ' if qb.sql_clauses.outer.order_by else ''
            if comma_maybe:
               check_ordering = qb.sql_clauses.outer.order_by.strip()
               if check_ordering == 'edited_date DESC':
                  qb.sql_clauses.outer.order_by = ''
                  comma_maybe = ''
               # When searching multiple columns, we'll order by each of
               # them, e.g., when geocoding, we'll search text in the
               # item name and also look for item comments, so the order-
               # by is a collection of fts_rank_*, e.g.,
               #   ORDER BY fts_rank_name DESC, fts_rank_comments DESC
               # not that ordering by the second column probably does much.
               elif not check_ordering.startswith('fts_rank_'):
                  log.warning(
                     'sql_apply_query_filter_by_text_tc: check_ordering: %s'
                     % (check_ordering,))
                  log.warning(
                     'sql_apply_query_filter_by_text_tc: qb: %s' % (qb,))
                  g.assurt_soft(False)
            qb.sql_clauses.outer.order_by += (
               """
               %s fts_rank_%s DESC
               """ % (comma_maybe,
                      column,))
         if False:
            # We could use levenshtein distance, but that doesn't work well
            # when terms are scrambled, e.g., comparing "my favorite route"
            # to "route favorite my" is same as comparing "my favorite route"
            # to "completely different", i.e., not a good way to rank results
            # (but good for looking for duplicate line segments by name, like
            # how geofeature_io.py works).
            #   sudo apt-get install postgresql-contrib
            #   psql -U postgres ccpv3_lite
            #   ccpv3_lite=# create extension fuzzystrmatch;
            qb.sql_clauses.outer.enabled = True
            qb.sql_clauses.outer.select += (
               """
               , levenshtein(LOWER(group_item.name), %s) AS leven_dist
               """ % (qb.db.quoted(qb.filters.filter_by_text_smart),))
            qb.sql_clauses.outer.group_by += (
               """
               , leven_dist
               """)
            qb.sql_clauses.outer.order_by_enable = True
            comma_maybe = ', ' if qb.sql_clauses.outer.order_by else ''
            qb.sql_clauses.outer.order_by += (
               """
               %s leven_dist ASC
               """ % (comma_maybe,))

      return (where_clause, conjunction, outer_where,)

      # 2013.03.28: Some notes on string matching and execution times.
      #
      # 1. The squiggle is a regex operator.
      #
      #       select 'a' ~ '[abc]'; ==> true
      #       select 'a' ~ 'a b c'; ==> false
      #       select 'a b c' ~ 'a'; ==> true
      #
      #    Consider that if the user sends "Lake" we'll match
      #       "Lake Harriet", "Lake Calhoun", etc...
      #
      #    Rather than using LOWER(), use case-insensitve ~* regex match.
      #
      #    Read more online.
      #
      #       http://www.postgresql.org/docs/8.4/static/functions-matching.html
      #
      # 2. The @@ is the full text search operator.
      #
      #    [lb] notes how much faster it is:
      #
      #       * ccpv3=> select count(*) from group_item_access as gia
      #                 where (gia.name ~* 'lake hARRieT PKWY');
      #         Time: 1239.339 ms
      #
      #       * ccpv3=> select count(*) from group_item_access as gia
      #                 where (gia.tsvect_name @@ plainto_tsquery(
      #                           'english', 'lake hARRieT PKWY'));
      #         Time: 8.214 ms
      #
      #       * ccpv3=> select count(*) from group_item_access as gia
      #                 where (LOWER(gia.name) = 'lake harriet pkwy');
      #         Time: 505.316 ms
      #
      #       * ccpv3=> select count(*) from group_item_access as gia
      #                 where (gia.name = LOWER('Lake Harriet Pkwy'));
      #         Time: 1.228 ms

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, iv_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if iv_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               system_id
               , branch_id
               , stack_id
               , version
               , deleted
               , reverted
               , name
               , valid_start_rid
               , valid_until_rid
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(iv_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***


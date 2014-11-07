# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# A versioned item is one that follows the valid-start/valid-until
# revisioning model.

import hashlib
import os
import re
import sys
import traceback
import uuid

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_style import Access_Style
#from gwis.query_filters import Query_Filters
#from gwis.query_viewport import Query_Viewport
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import item_base
#from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import misc

__all__ = ['One', 'Many',]

log = g.log.getLogger('item_stack')

class One(item_base.One):

   item_type_id = None
   item_type_table = 'item_stack'
   item_gwis_abbrev = None
   child_item_types = None

   # Usually, an item's version number between branches has some relation --
   # when a branch is created or merged, the items between the two will have
   # their versions reconciled. But some items, like node_endpoint, share
   # stack_ids but not versions, i.e., node_endpoints cannot be merged
   # between branches (they are therefore branch-specific).
   item_version_is_branch_specific = False

   # NOTE: There's no branch_id in the item_stack table. Currently, all
   #       items will have the same access_infer_id in all branches,
   #       simply because of how it works: restricted-style items are not
   #       shared across branches (routes and tracks); public and private
   #       items are the same across branches and user cannot change this
   #       (BUG nnnn: implement clone feature in client that copies a
   #       private item to a new item, marks the private item deleted,
   #       and makes the new item public); and the last access style,
   #       permissive, only applies to branches (allowing users access
   #       to a branch), and branches each will have their own item_stack
   #       record.

   # These columns exist in all of the item type tables.
   shared_defns = [
      # NOTE: The only shared column is 'stack_id', but item_versioned has to
      # make its own definition since that column is a primary key here but not
      # in item_versioned.
      ]
   # These columns only exist in the item_stack table.
   local_defns = [
      # py/psql name,      deft,  send?,  pkey?,     pytyp,  reqv, abbrev
      ('stack_id',         None,  False,   True,       int,  None,),
      ('stealth_secret',   None,   True,  False, uuid.UUID,  None, 'stlh',),
      ('cloned_from_id',   None,   True,  False,       int,  None, 'clid',),
      # NOTE: We don't set a default for access_style_id here since we don't
      #       always fetch it (i.e., if !qb.filters.include_item_stack). If we
      #       do fetch it, the SQL defaults it to Access_Style.all_denied.
      ('access_style_id',  None,   True,  False,       int,  None, 'acst',),
      ('access_infer_id',  None,   True,  False,       int,  None, 'acif',),

      ('created_date',     None,   True,   None,       str,  None, 'crat',),
      ('created_user',     None,   True,   None,       str,  None, 'crby',),

      # BUG nnnn: We should-could move three fields from group_item_access to
      #           here. Because these three fields are always the same for each
      #           stack_id's versions and acl_groupings.
      #            item_type_id, link_lhs_type_id, link_rhs_type_id

      ]
   attr_defns = item_base.One.attr_defns + shared_defns + local_defns
   psql_defns = item_base.One.psql_defns + shared_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   private_defns = item_base.One.psql_defns + shared_defns + local_defns
   #
   cols_copy_nok = item_base.One.cols_copy_nok + (
      [
       'stack_id',
       'stealth_secret',
       'cloned_from_id',
       'access_style_id',
       'access_infer_id',
       'created_date',
       'created_user',
       ])
   
   __slots__ = ([
      ]
      + [attr_defn[0] for attr_defn in shared_defns]
      + [attr_defn[0] for attr_defn in local_defns]
      )

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_base.One.__init__(self, qb, row, req, copy_from)

   # ***

   # MAYBE: Implement __str__ and __str_deets__?
   #        or __str_abbrev__ or __str_verbose__?

   # *** GML/XML Processing

   #
   def col_to_attr(self, row, attr_defn, copy_from):
      #stack_id_old = self.stack_id
      item_base.One.col_to_attr(self, row, attr_defn, copy_from)
      attr_name = attr_defn[item_base.One.scol_pyname]
      # Tickly any classes listening on stack_id.
      #if (attr_name == 'stack_id') and (stack_id_old != self.stack_id):
      if (attr_name == 'stack_id') and (self.stack_id is not None):
         self.stack_id_set(self.stack_id)

   #
   def from_gml(self, qb, elem):
      item_base.One.from_gml(self, qb, elem)

      if not self.stack_id:
         # FIXME: 2012.09.25: I think this case is okay for 'analysis' routes.
         #raise GWIS_Error('The stack_id attr must be nonzero.')
         #
         # Sep-20 17:06:17 item_stack # from_gml: no stack ID:
         # "Route via Midtown Greenway" route:0(Nonec).v0/ssX-b2500677-acl:n/a
         #  { beg: ".... Brookside Ave S, Minneapolis, MN 55416" }
         #  { end: ".... E 38th St, Minneapolis, MN 55406" } 
         #  [mode:1|3attr:wgt_rat_8|p3wgt:len|p3rat:8|p3fac:0|p3alg:as*]
         # this is a user's two-year-old deeplink. The beg and fin addrs
         # are set to the qualified values... so why isn't the stack_id set?
         # Apache log says:
         # 20/Sep/2014:17:06:16 rqst=route_get&rt_sid=1578047&source=
         #   android_top&asgpx=0&checkinvalid=1&istk=1&iaux=1
         # Except that's not the right stack ID, the Midtown route is
         # 1578046. But the 1578047 route is the only one with the
         # stealth_secret in item_stack. What is going on here?
         # And the 1578047 route is the only one with an item_findability
         # record, but it's dated most previously 2014-07-22.
         #
         #if not qb.filters.use_stealth_secret: what, only warn???
         #                                   # but why no stack_id?
         #
         log.warning('from_gml: no stack ID: %s' % (str(self),))

      # The stack ID is still the client ID that the client was using;
      # it'll get corrected after all client items are hydrated.
      self.client_id = self.stack_id

   # *** Dirty/Fresh/Valid Routines

   # 
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      item_base.One.validize(self, qb, is_new_item, dirty_reason, 
                                   ref_item)
      g.assurt(self.valid)

   # *** Saving to the Database

   #
   def save_core(self, qb):

      # Defensive programming/programming by contract: Check our contracts.
      g.assurt((self.fresh and (self.version == 1)) 
               or (not self.fresh and (self.version > 1))
               or (not self.fresh and (self.acl_grouping > 1)))
      g.assurt(not (self.fresh and self.deleted))
      g.assurt(self.stack_id > 0)
      g.assurt((self.client_id < 0) or (self.stack_id == self.client_id))

      log.verbose('save_core: updating access_infer_id: %s' % (self,))

      if not self.item_version_is_branch_specific:

         # We used to only save if fresh, and later in save_related_maybe if
         # the stealth_secret was added, but we also have to save if the access
         # infer changed.
         latest_infer_id = self.get_access_infer(qb)
         log.debug('save_core: latest_infer_id: %d (%s)'
                     % (latest_infer_id, qb.username,))

         # But first save to item_stack first if this is a new item.
         if self.fresh or (latest_infer_id != self.access_infer_id):
            if not self.access_style_id:
               # This assumes this is not a fresh item.
               self.access_style_id = self.save_core_pre_save_get_acs(qb)
               g.assurt(Access_Style.is_valid(self.access_style_id))
            self.access_infer_id = latest_infer_id
            # The node_cache_maker.py script can be used to drop tables but
            # it doesn't clean the node IDs from item_stack, so there might
            # already be a row for this stack_id. So use do_update=True and
            # clobber the existing row (which may not even exist).
            # 2013.05.30: Thanks from [lb] to [ft] for noticing that when you
            # edited existing items, the access_style_id was being reset to
            # all_denied and the creator_name (since renamed and now
            # calculated specially, created_user) was being clobbered. Haha,
            # we don't want to clobber the entire record for existing items!
            if self.fresh:
               self.save_insert(qb, One.item_type_table, One.private_defns)
            else:
               log.verbose(
                  'save_core: set dirty_reason_infr / access_infer_id: %d / %s'
                         % (self.access_infer_id, self,))
               self.dirty |= item_base.One.dirty_reason_infr

      if self.dirty & item_base.One.dirty_reason_stlh:
         log.debug('save_core: saved stealth secret')
         g.assurt(self.item_version_is_branch_specific)
         self.dirty &= ~item_base.One.dirty_reason_stlh

   #
   def save_core_pre_save_get_acs(self, qb):
      # This isn't a Bad Thing, really, but [lb] wonders if some callers
      # should use qb.filters.include_item_stack when they fetch.
      #log.warning('save_core_: fetching access_style_id pre-save...')
      g.assurt(self.version > 1) # At least shouldn't happen on new item.
      acs_sql = ("SELECT access_style_id FROM item_stack WHERE stack_id = %d"
                 % (self.stack_id,))
      rows = qb.db.sql(acs_sql)
      g.assurt(len(rows) == 1)
      return rows[0]['access_style_id']

   #
   def save_related_maybe(self, qb, rid):
      # We wait until here to update access_infer_id because the acl_grouping
      # features skips save_core and justs triggers save_related_maybe (since
      # we're not saving any new item version records, just gia records).
      if self.dirty & item_base.One.dirty_reason_infr:
         # Whatever: we might have already called get_access_infer in
         # save_core, but it's a cheap call.
         # The code path followed when an anon user gets a route and then the
         # web_link.
         self.access_infer_id = self.get_access_infer(qb)        
         log.debug(
            'save_related_maybe: dirty_reason_infr: set access_infer_id: %d'
            % (self.access_infer_id,))
         self.save_update_access_infer_id(qb)
         self.dirty &= ~item_base.One.dirty_reason_infr
      # Not calling: item_base.One.save_related_maybe(self, qb, rid)
      if self.dirty & One.dirty_reason_stlh:
         g.assurt(False) # Should not happen
         self.save_insert(qb, One.item_type_table, One.private_defns,
                              do_update=True)

   #
   def save_update_access_infer_id(self, qb):
      update_sql = (
         """
         UPDATE item_stack
         SET access_infer_id = %d
         WHERE stack_id = %d
         """ % (self.access_infer_id, self.stack_id,))
      rows = qb.db.sql(update_sql)

   # *** Client ID Resolution

   #
   def stack_id_correct(self, qb):
      '''If stack_id is a negative client ID, we lookup or make the positive 
         permanent stack ID.'''
      g.assurt(self.stack_id is not None)
      if self.stack_id < 0:
         client_id = self.stack_id
         stack_id = qb.item_mgr.stack_id_translate(qb, client_id)
         self.stack_id_set(stack_id)
         self.fresh = True
         qb.item_mgr.item_cache_add(self, client_id)

   #
   def stack_id_lookup_by_name_sql(self, qb):
      g.assurt(False) # Don't call me.

   #
   def stack_id_set(self, stack_id):
      # EXPLAIN: When is the client ID the same as the stack ID? Are they
      # sometimes both negative client IDs, or are they sometimes both positive
      # real IDs, or are they alwaystimes one or the other?
      g.assurt(stack_id is not None)
      g.assurt(self.client_id is not None)
      if self.client_id == self.stack_id:
         # If the recorded client ID is a real ID, or if the stack ID being
         # assigned is a new client ID, reset the client ID.
         if (self.client_id > 0) or (stack_id < 0):
            self.client_id = stack_id
      else:
         g.assurt(self.client_id <= 0)
         pass
      #try:
      #   log.debug('stack_id_set: stack_id: %s / %s' % (stack_id, self,))
      #except AttributeError:
      #   log.debug('stack_id_set: stack_id: %s / from ctor' % (stack_id,))
      self.stack_id = stack_id

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, item):

      # Generates part of the SQL used by bulk_insert_rows.

      insert_expr = (
         "(%d, %d, %d)"
         % (item.stack_id,
            item.access_style_id,
            item.access_infer_id,
            ))

      return insert_expr

   # ***

# ***

class Many(item_base.Many):

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      item_base.Many.__init__(self)

   # *** SQL clauses

   # NOTE: Skipping: sql_clauses_cols_all and sql_clauses_cols_name.
   #       We use sql_apply_query_filters to inject the table and its columns.

   # ***

   sql_clauses_include_item_stack_join = (
      """
      LEFT OUTER JOIN item_stack AS st
         ON (%s.stack_id = st.stack_id)
      -- Get the first version info:
      LEFT OUTER JOIN item_versioned AS first_iv
         ON (%s.stack_id = first_iv.stack_id
             AND first_iv.version = 1)
      """)

   sql_clauses_include_item_stack_join_revisioned = (
      """
      LEFT OUTER JOIN revision AS first_rev
         ON (first_iv.valid_start_rid = first_rev.id)
      """)

   sql_clauses_include_item_stack_join_revisionless = (
      """
      LEFT OUTER JOIN item_revisionless AS first_ir
         ON (first_iv.system_id = first_ir.system_id
             AND first_ir.acl_grouping = 1)
      """)


   sql_clauses_include_item_stack_select = (
      """
      , st.stealth_secret
      , COALESCE(st.access_style_id, %d) AS access_style_id
      , COALESCE(st.access_infer_id, %d) AS access_infer_id
      --, st.cloned_from_id.
      """ % (Access_Style.all_denied,
             Access_Infer.not_determined,))

   sql_clauses_include_item_stack_select_revisioned = (
      """
      , TO_CHAR(first_rev.timestamp, 'MM/DD/YYYY HH:MI am') AS created_date
      , CASE WHEN ((first_rev.username = '%s')
                   OR (first_rev.username IS NULL))
             THEN first_rev.host
             ELSE first_rev.username END
        AS created_user
      """ % (conf.anonymous_username,))

   sql_clauses_include_item_stack_select_revisionless = (
      """
      , TO_CHAR(first_ir.edited_date, 'MM/DD/YYYY HH:MI am') AS created_date
      , CASE WHEN ((first_ir.edited_user = '%s')
                   OR (first_ir.edited_user IS NULL))
             THEN CASE WHEN first_ir.edited_host IS NULL
                       THEN HOST(first_ir.edited_addr)
                       ELSE first_ir.edited_host
                       END
             ELSE first_ir.edited_user END
        AS created_user
      """ % (conf.anonymous_username,))

   sql_clauses_include_item_stack_group_by = (
      """
      , st.stealth_secret
      , st.access_style_id
      , st.access_infer_id
      """)

   sql_clauses_include_item_stack_group_by_revisioned = (
      """
      , first_rev.timestamp
      , first_rev.host
      , first_rev.username
      """)

   sql_clauses_include_item_stack_group_by_revisionless = (
      """
      , first_ir.edited_date
      , first_ir.edited_addr
      , first_ir.edited_host
      , first_ir.edited_user
      """)

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not conjunction) or (conjunction == "AND"))

      # Don't waste time joining item_stack until it's absolutely needed.
      use_inner_join = False
      # If the user wants to check created_user or stealth_secret, obviously we
      # need the item_stack table.
      if (   qb.filters.filter_by_creator_include
          or qb.filters.filter_by_creator_exclude
          # FIXME: Erm, what's with both filter_by_creator_* and _by_username?
          or qb.filters.filter_by_username
          or qb.filters.use_stealth_secret):
         use_inner_join = True
         qb.filters.include_item_stack = (qb.sql_clauses is not None)

      if qb.filters.include_item_stack:
         # PERFORMANCE: It's costly to join the item_stack table, especially
         # within the inner select, so we try to do it in the outer fetch.
         # Which isn't always possible, e.g., when fetching basic info using
         # item_type=item_user_access.
         # NOTE: The stealth_secret here is just returned to the client to
         #       let the user copy-n-paste it. The stealth_secret is not
         #       fetched here to do a one-SQL-statement-stealth-checkout.
         #       If the user has a stealth secret andh wants an item, we'll
         #       fetch the stack ID directly from the item_stack table and
         #       then _try_ to check out the item with the qb, so that we
         #       honor user permissions.
         qb.sql_clauses.outer.enabled = True
         if use_inner_join:
            qb.sql_clauses.inner.join += (
               Many.sql_clauses_include_item_stack_join
               % ('gia', 'gia',))
            qb.sql_clauses.inner.select += (
               Many.sql_clauses_include_item_stack_select)
            qb.sql_clauses.inner.group_by += (
               Many.sql_clauses_include_item_stack_group_by)
            qb.sql_clauses.outer.shared += (
               """
               , group_item.stealth_secret
               , group_item.access_style_id
               , group_item.access_infer_id
               , group_item.created_date
               , group_item.created_user
               """)
         else:
            qb.sql_clauses.outer.join += (
               Many.sql_clauses_include_item_stack_join
               % ('group_item', 'group_item',))
            qb.sql_clauses.outer.select += (
               Many.sql_clauses_include_item_stack_select)
            qb.sql_clauses.outer.group_by += (
               Many.sql_clauses_include_item_stack_group_by)
         self.sql_apply_query_filters_item_stack_revisiony(qb, use_inner_join)

      if qb.filters.use_stealth_secret:
         # Filter the results by those with the matching secret.
         where_clause += (
            """
            %s (st.stealth_secret = %s)
            """ % (conjunction, 
                   qb.db.quoted(qb.filters.use_stealth_secret),))
         conjunction = "AND"

      # Assemble the text query. We do it here because if two or more
      # descendants have text to search, we want to OR the tests, so
      # that, e.g., search a discussion can hit either the thread.name
      # or the post.body.
      table_cols = []
      stop_words = None
      where_text = self.sql_apply_query_filter_by_text(qb, table_cols,
                                                           stop_words)
      if where_text:
         where_clause += " %s (%s) " % (conjunction, where_text,)
         conjunction = "AND"

      where_clause = "%s %s" % (conjunction, where_clause,)

      # NOTE: Not calling item_base.sql_apply_query_filters; we're the end of
      #       the road.

      return where_clause

   #
   def sql_apply_query_filters_item_stack_revisioned(self, qb, use_inner_join):
      if use_inner_join:
         qb.sql_clauses.inner.join += (
            Many.sql_clauses_include_item_stack_join_revisioned)
         qb.sql_clauses.inner.select += (
            Many.sql_clauses_include_item_stack_select_revisioned)
         qb.sql_clauses.inner.group_by += (
            Many.sql_clauses_include_item_stack_group_by_revisioned)
      else:
         qb.sql_clauses.outer.join += (
            Many.sql_clauses_include_item_stack_join_revisioned)
         qb.sql_clauses.outer.select += (
            Many.sql_clauses_include_item_stack_select_revisioned)
         qb.sql_clauses.outer.group_by += (
            Many.sql_clauses_include_item_stack_group_by_revisioned)

   #
   def sql_apply_query_filters_item_stack_revisionless(self, qb,
                                                             use_inner_join):
      if use_inner_join:
         qb.sql_clauses.inner.join += (
            Many.sql_clauses_include_item_stack_join_revisionless)
         qb.sql_clauses.inner.select += (
            Many.sql_clauses_include_item_stack_select_revisionless)
         qb.sql_clauses.inner.group_by += (
            Many.sql_clauses_include_item_stack_group_by_revisionless)
      else:
         qb.sql_clauses.outer.join += (
            Many.sql_clauses_include_item_stack_join_revisionless)
         qb.sql_clauses.outer.select += (
            Many.sql_clauses_include_item_stack_select_revisionless)
         qb.sql_clauses.outer.group_by += (
            Many.sql_clauses_include_item_stack_group_by_revisionless)

   #
   def sql_apply_query_filters_item_stack_revisiony(self, qb, use_inner_join):
      # By default, items are considered revisioned, not revisionless.
      self.sql_apply_query_filters_item_stack_revisioned(qb, use_inner_join)

   #
   def sql_apply_query_filters_last_editor_revisioned(self, qb, where_clause,
                                                                conjunction):

      if qb.filters.filter_by_creator_include:
         cnames = ','.join(
            [qb.db.quoted(x)
               for x in qb.filters.filter_by_creator_include.split(',')])
         where_clause += (
            """
            %s (first_rev.created_user IN (%s))
            """ % (conjunction, 
                   cnames,))
         conjunction = "AND"

      if qb.filters.filter_by_creator_exclude:
         cnames = ','.join(
            [qb.db.quoted(x)
               for x in qb.filters.filter_by_creator_exclude.split(',')])
         where_clause += (
            """
            %s (first_rev.created_user NOT IN (%s))
            """ % (conjunction, 
                   cnames,))
         conjunction = "AND"

      # FIXME: Erm, what's with both filter_by_creator_* and _by_username?
      #        - filter_by_username is used by Tab_Latest_Activity_Base.
      #        - filter_by_creator_include is used by Panel_Routes_Library.
      if qb.filters.filter_by_username:
         qb.sql_clauses.inner.join += (
            """
            JOIN revision AS rev
               ON (rev.id = gia.valid_start_rid)
            """)
         # FIXME: Do username and host have to be in SELECT?
         # Only select items that we created by the indicated user.
         # FIXME: When searching threads, in addition to posts written by the
         # selected user, this selects the thread and all its posts if the
         # thread was created by the indicated user). (So maybe, for each post,
         # you should save a new revision of the thread and attach it to the
         # latest post....)
         # 2013.03.28: Do we really need to do a regex search? It's slower than
         #             exact match. Also we don't need LOWER(), since
         #             rev.username and rev.host already lowercase (latter is
         #             IP address or machine name (lowercase) or _DUMMY (which
         #             is not lowercase but for which we don't care to expost a
         #             filter).
         # %s (LOWER(COALESCE(rev.username, rev.host)) ~ LOWER(%s))
         filter_by_username = qb.filters.filter_by_username.lower()
         # %s (LOWER(COALESCE(rev.username, rev.host)) ~ %s)
         where_clause += (
            """
            %s (COALESCE(rev.username, rev.host) = %s)
            """ % (conjunction,
                   qb.db.quoted(filter_by_username),))
         conjunction = "AND"

      return (where_clause, conjunction,)

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, is_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if is_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               stack_id
               --, stealth_secret
               --, cloned_from_id
               , access_style_id
               , access_infer_id
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(is_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***


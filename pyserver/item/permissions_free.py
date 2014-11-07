# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_style import Access_Style
from gwis.exception.gwis_error import GWIS_Error
from item import geofeature
from item import item_base
from item import item_versioned
from item import item_user_watching
from item.grac import group
from item.util import item_query_builder
from item.util.item_type import Item_Type
from util_ import geometry

__all__ = ['One', 'Many',]

log = g.log.getLogger('perms_free')

# ***

class One(item_user_watching.One):

   item_type_id = None
   item_type_table = None
   item_gwis_abbrev = None
   child_item_types = None

   local_defns = [
      ]
   attr_defns = item_user_watching.One.attr_defns + local_defns
   psql_defns = item_user_watching.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   # Group Access Not Required. No Dogs Allowed.
   groups_access_not_required = True

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_user_watching.One.__init__(self, qb, row, req, copy_from)
      # Rather than leave the unused access stuff None, set it.
      # This also avoids not-null constraints in item_stack on save_core.
      self.access_infer_id = Access_Infer.not_determined
      self.access_level_id = Access_Level.editor
      self.access_style_id = Access_Style.all_denied

   # ***

   #
   def get_access_infer(self, qb):
      # Not used by this class or its descendants.
      return Access_Infer.not_determined

   #
   def is_dirty(self):
      # NOTE: HACK: Skipping item_user_access's is_dirty, which expects
      #             self.groups_access, and calling the parent's parent
      #             class directly!
      is_dirty = item_versioned.One.is_dirty(self)
      return is_dirty

   #
   def save_core(self, qb):
#      self.access_infer_id = Access_Infer.not_determined
#      self.access_style_id = Access_Style.all_denied

# FIXME_2013_06_11: [lb] did something that breaks the upgrade scripts... here!
# FIXME: node_endpoint calls down to item_stack and we get duplicate key error
#        when making a new branch
      item_user_watching.One.save_core(self, qb)

   #
   def save_core_pre_save_get_acs(self, qb):
      # Not used by this class or its descendants.
      return Access_Style.all_denied

   #
   def save_update(self, qb):
      item_user_watching.One.save_update(self, qb)

   #
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      # FIXME: We don't call the base class, I [lb] think.
      # NO: item_user_watching.One.validize(self, qb, is_new_item, 
      #                                     dirty_reason, ref_item)
      log.warning('validize: FIXME: Just pass, right?')
      pass

# ***

class Many(item_user_watching.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   sql_clauses_cols_all = item_user_watching.Many.sql_clauses_cols_all.clone()

   # We're a Very Special Class. We're Always Public. So skip the GIA table.

   sql_clauses_cols_all = item_query_builder.Sql_Bi_Clauses()

   # This is just formalities. We don't really care about this, since we don't
   # call call item_user_access.search_get_sql.
   sql_clauses_cols_all.inner.enabled = True

   # NOTE: Not using inner.shared, like the item_user_access stack. Though
   #       maybe in the future if we need group by and aggregates.
   # NOTE: Permissions-Free means these types of items are always editor-able.
   # MAGIC_NUMBER: The acl_grouping is 1 since we're faking that there's just 
   #               one group_item_access record.
   sql_clauses_cols_all.inner.select = (
      """
         itmv.stack_id
         , itmv.branch_id
         , itmv.system_id
         , itmv.version
         , itmv.deleted
         , itmv.reverted
         , itmv.name
         , itmv.valid_start_rid
         , itmv.valid_until_rid
         , 1 AS acl_grouping
         , %d AS access_level_id
      """ % (Access_Level.editor,))

   sql_clauses_cols_all.inner.join = (
      """
      JOIN item_versioned AS itmv
         ON (itmv.system_id = item.system_id)
      """)

   # NOTE: Derived classes should set from_table, e.g.,
   #         sql_clauses_cols_all.inner.from_table = (
   #            """
   #            FROM 
   #               node_endpoint AS item
   #            """)

   # *** Constructor

   def __init__(self):
      item_user_watching.Many.__init__(self)

   # ***

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):
      g.assurt(False)

   def search_for_names(self, *args, **kwargs):
      g.assurt(False)

   #
   def search_for_items(self, *args, **kwargs):
      # FIXME: This one maybe should be implemented?
      g.assurt(False)

   # *** Query Builder functions

   #
   def search_by_stack_id(self, stack_id, *args, **kwargs):
      qb = self.query_builderer(*args, **kwargs)
      self.sql_clauses_cols_setup(qb)
      qb.filters.only_stack_ids = stack_id
      self.search_get_items(qb)
      g.assurt((not self) or (len(self) == 1))

   # ***

   #
   def search_get_items(self, qb):

      # Get the search string.
      sql = self.search_get_sql(qb)

      # Fetch items.
      res = qb.db.sql(sql)

      # Hydrate our Many() self if fetchall.
      if res is not None:
         g.assurt(not qb.db.dont_fetchall)
         for row in res:
            item = self.get_one(qb, row)
            self.search_get_items_by_group_consume(qb, item)
         # NOTE: Don't call qb.db.curs_recycle() here; let callers do it.
      # else, since dont_fetchall; called will fetchone-by-one.

      # FIXME: Is this right? Clear the clauses? Since we may have edited them?
      qb.sql_clauses = None

   #
   def search_get_sql(self, qb):

      # MAYBE: Do we need to bulk-load using a lookup/temp table?
      #        Search qb.filters.stack_id_table_ref...

      # This SQL mimics what would otherwise have been setup by
      # item_user_access.Many.sql_clauses_cols_all.outer.select.
      # But we're skipping the group_item_access and grac tables.

      inner_join = qb.sql_clauses.inner.join
      if qb.filters.stack_id_table_ref:
         inner_join += (
            """
            JOIN %s AS stack_ids_ref
               ON (stack_ids_ref.stack_id = item.stack_id)
            """ % (qb.filters.stack_id_table_ref,))

      # The clauses' inner.where is not used for perms-free, at least not now.
      g.assurt(not qb.sql_clauses.inner.where)
      where_clause = ""
      conjunction = "AND"
      if qb.filters.only_stack_ids:
         try:
            stack_id = int(qb.filters.only_stack_ids)
            where_clause += (" %s (item.stack_id = %d)" 
                             % (conjunction, stack_id,))
         except ValueError:
            # It's a string of IDs and not just a single int.
            where_clause += (" %s (item.stack_id IN (%s))"
                             % (conjunction, qb.filters.only_stack_ids,))
         conjunction = "AND"

      # NOTE: permissions_free items are node_endpoint and node_traverse, both
      # of which are flattened branches, so there's one row for every item in
      # the branch (i.e., and parent branches), so we only need to
      # where-against the leafiest branch ID.
      # MAYEB: [lb] Will new permissions_free descendants also be flattened?
      #             I don't really think it should be a requirement... but 
      #             for now, it's the truth.
      sql_inner = (
         """
         SELECT
            %s
         %s
         %s
         WHERE
            item.branch_id = %d
            %s
            AND %s
         """ % (qb.sql_clauses.inner.select,
                qb.sql_clauses.inner.from_table,
                qb.sql_clauses.inner.join,
                qb.branch_hier[0][0],
                where_clause,
                # The revision is usually just Current
                qb.revision.as_sql_where(),))

      return sql_inner

   # ***

# ***


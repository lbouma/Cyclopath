# Copyright (c) 2014-2014 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import datetime
import os
import re
import sys
import traceback
import uuid

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import item_base
from item import item_stack
from item import item_versioned
from item.util import item_query_builder
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import misc

__all__ = ['One', 'Many',]

log = g.log.getLogger('itm_rvsnless')

class One(item_versioned.One):

   item_type_id = None
   item_type_table = 'item_revisionless'
   item_gwis_abbrev = None
   child_item_types = None

   local_defns = [
      # py/psql name,       deft,  send?,  pkey?,  pytyp,  reqv, abbrev

      # In item_versioned: system_id, branch_id, stack_id, version

      # The acl_grouping starts at 1 for every new version and is only used 
      # by 'permissive'-style records. It's similar to version: users cannot
      # set this value, and generally they don't see it, but it's used by the
      # server and client to manage items and their permissions.
      ('acl_grouping',      None,  False,   True,    int,  None),

      # The edited_date date refers to when the latest item version was
      # created and not the last time the item's permissions were changed.
      ('edited_date',       None,   True,  False,    str,     3, 'ed_dat',),
      ('edited_user',       None,   True,  False,    str,     3, 'ed_usr',),
      ('edited_addr',       None,   True,  False,    str,     3, 'ed_adr',),
      ('edited_host',       None,   True,  False,    str,     3, 'ed_hst',),
      # The edited_note is essentially just like revision.changenote.
      ('edited_note',       None,   True,  False,    str,     3, 'ed_not',),
      # The callback_source/edited_what indicates the client and context of
      #   the request, like 'deeplink', 'put_feature', 'android_top', etc.
      #   FIXME: Replace track.source with item_revisionless.edited_what.
      ('edited_what',       None,  False,  False,    str,     3, 'ed_wht',),
      ]
   attr_defns = item_versioned.One.attr_defns + local_defns
   psql_defns = item_versioned.One.psql_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   private_defns = item_versioned.One.psql_defns + local_defns
   #
   cols_copy_nok = item_versioned.One.cols_copy_nok + (
      [
       'acl_grouping',
       'edited_date',
       'edited_user',
       'edited_addr',
       'edited_host',
       'edited_note',
       'edited_what',
      ])

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_versioned.One.__init__(self, qb, row, req, copy_from)
      #
      # Not needed, since we format when we fetch, and we normally
      # let the trigger create edited_date on insert.
      #   if (row is not None) and ('edited_date' in row):
      #      self.edited_date = misc.sql_time_to_datetime(row['edited_date'])
      #   else:
      #      self.edited_date = None

   # ***

   #
   def clear_item_revisionless_defaults(self):
      self.edited_date = None
      self.edited_user = None
      self.edited_addr = None
      self.edited_host = None
      self.edited_what = None
      self.edited_note = None

   #
   def setup_item_revisionless_defaults(self, qb, force=False):
      # Skipping: self.acl_grouping
      if force or (self.acl_grouping > 1):
         self.edited_date = datetime.datetime.now()
         if qb is not None:
            self.edited_user = qb.username
            self.edited_addr = qb.remote_ip
            self.edited_host = qb.remote_host
            self.edited_what = qb.remote_what
         # Skipping: self.edited_note

   # ***

   # 
   def version_finalize_and_increment(self, qb, rid, same_version=False,
                                                     same_revision=False):

      # Reset the GIA grouping (which lets users change permissions without
      # creating new revisions and item versions).

      if not self.version:
         # New item; using same_version doesn't matter.
         # Base class will set version = 1... unless same_version.
         g.assurt(self.version == 0)
         if same_version:
            self.version = 1
         self.acl_grouping = 1
      else:
         g.assurt(self.version >= 1)
         if not same_version:
            # Existing item; user wants new version, so start new ACL Grouping.
            # Base class will set version += 1 (so version will be >= 2).
            self.acl_grouping = 1
         else:
            # User is just updating the GIA of a particular item, so don't bump
            # its version, just increment its ACL Group number.
            # Base class will leave version untouched.
            self.acl_grouping += 1
            if self.acl_grouping > 1:
               self.setup_item_revisionless_defaults(qb)

      item_versioned.One.version_finalize_and_increment(self, qb, rid, 
                                                        same_version,
                                                        same_revision)

   # ***

   #
   def save_core(self, qb):
      item_versioned.One.save_core(self, qb)

   #
   def save_related_maybe(self, qb, rid):

      item_versioned.One.save_related_maybe(self, qb, rid)

      if self.acl_grouping > 1:
         self.setup_item_revisionless_defaults(qb)

      self.save_insert(qb, One.item_type_table, One.private_defns)

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, item):

      insert_expr = (
         "(%d, %d, %d, %d, %d, %s, %s, %s, %s, %s, %s)"
         % (item.system_id,
            item.acl_grouping,
            item.branch_id,
            item.stack_id,
            item.version,
            "'%s'" % (item.edited_date,) if item.edited_date else 'NULL',
            qb.db.quoted(item.edited_user) if item.edited_user else 'NULL',
            "'%s'::INET" % (item.edited_addr,) if item.edited_addr else 'NULL',
            qb.db.quoted(item.edited_host) if item.edited_host else 'NULL',
            qb.db.quoted(item.edited_note) if item.edited_note else 'NULL',
            qb.db.quoted(item.edited_what) if item.edited_what else 'NULL',
            ))

      return insert_expr

   # ***

# ***

class Many(item_versioned.Many):

   one_class = One

   # Skipping: sql_clauses_cols_all
   # Skipping: sql_clauses_cols_name
   # Doinging: sql_clauses_cols_versions
   #           But we're a sham of an intermediate class -- route
   #           is the only true revisionless class (and maybe track
   #           someday, too, and maybe work_items), but all item
   #           classes eventually derive from this class. As such,
   #           we'll define some item_revisionless stuff herein,
   #           but it's an opt-in model: derived item classes that
   #           care need to deliberately include our special things.

   # **** SQL: Item version history query: Revisioned Items

   sql_clauses_cols_versions_revisioned = item_query_builder.Sql_Bi_Clauses()
   sql_clauses_cols_versions_revisioned.inner.shared = (
      """
        iv.system_id
      , iv.branch_id
      , iv.stack_id
      , iv.version
      , iv.deleted
      , iv.reverted
      , iv.name
      , iv.valid_start_rid
      , iv.valid_until_rid
      --, ik.stealth_secret
      --, ik.cloned_from_id
      --, ik.access_style_id
      --, ik.access_infer_id
      , TO_CHAR(rev.timestamp, 'MM/DD/YYYY HH:MI am') AS edited_date
      , rev.username AS edited_user
      , rev.host AS edited_addr
      , rev.host AS edited_host
      , rev.comment AS edited_note
      , '' AS edited_what
      """)
   sql_clauses_cols_versions_revisioned.inner.join = (
      """
      FROM item_versioned AS iv
      --LEFT OUTER JOIN item_stack AS ik
      --   ON (gia.stack_id = ik.stack_id)
      LEFT OUTER JOIN revision AS rev
         ON (iv.valid_start_rid = rev.id)
      """)

   # **** SQL: Item version history query: Revisionless Items

   sql_clauses_cols_versions_revisionless = item_query_builder.Sql_Bi_Clauses()
   sql_clauses_cols_versions_revisionless.inner.shared = (
      """
        iv.system_id
      , iv.branch_id
      , iv.stack_id
      , iv.version
      , iv.deleted
      , iv.reverted
      , iv.name
      , iv.valid_start_rid
      , iv.valid_until_rid
      --, ik.stealth_secret
      --, ik.cloned_from_id
      --, ik.access_style_id
      --, ik.access_infer_id
      --, ir.edited_date
      , TO_CHAR(ir.edited_date, 'MM/DD/YYYY HH:MI am') AS edited_date
      , ir.edited_user
      , ir.edited_addr
      , ir.edited_host
      , ir.edited_note
      , ir.edited_what
      """)
   sql_clauses_cols_versions_revisionless.inner.join = (
      """
      FROM item_versioned AS iv
      --LEFT OUTER JOIN item_stack AS ik
      --   ON (gia.stack_id = ik.stack_id)
      LEFT OUTER JOIN item_revisionless AS ir
         ON (iv.system_id = ir.system_id
             AND ir.acl_grouping = 1)
      """)

   # By default, we do non-revisionless and use the revision table,
   # rather than using the item_revisionless table, because that's
   # how most classes operate.
   sql_clauses_cols_versions = sql_clauses_cols_versions_revisioned
   #sql_clauses_cols_versions e()

   # *** Constructor

   __slots__ = ()

   def __init__(self):
      item_versioned.Many.__init__(self)

   # ***

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not conjunction) or (conjunction == "AND"))

      # Piggyback on include_item_stack, which includes data about the item
      # creator, and include details about the last item editor.
      if qb.filters.include_item_stack:
         # Only one item type, route, is currently revisionless (though track
         # should also be, and something something work_item, too, probably).
         # So callout an overrideable class fcn. that'll either grab the
         # last editor's username and last edited date from the revision
         # table, for revisioned items, or from the item_revisionless table,
         # for revisionless items, like routes.
         (where_clause, conjunction,
          ) = self.sql_apply_query_filters_last_editor(qb,
                                 where_clause, conjunction)

      return item_versioned.Many.sql_apply_query_filters(
                  self, qb, where_clause, conjunction)

   #
   def sql_apply_query_filters_last_editor(self, qb, where_clause,
                                                     conjunction):
      # This is the default handler, for all classes but route (and, eventually
      # hopefully maybe ideally, also track, so that adding a new track doesn't
      # bump revision.id).
      return self.sql_apply_query_filters_last_editor_revisioned(qb,
                                          where_clause, conjunction)

   #
   def sql_apply_query_filters_last_editor_revisioned(self, qb, where_clause,
                                                                conjunction):
      qb.sql_clauses.outer.enabled = True
      qb.sql_clauses.outer.join += (
         """
         JOIN revision AS rev
            ON (group_item.valid_start_rid = rev.id)
         """)
      qb.sql_clauses.outer.shared += (
         """
         --, rev.timestamp AS edited_date
         , TO_CHAR(rev.timestamp, 'MM/DD/YYYY HH:MI am') AS edited_date
         , rev.username AS edited_user
         , '' AS edited_addr
         , rev.host AS edited_host
         , rev.comment AS edited_note
         , '' AS edited_what
         """)

      return (where_clause, conjunction,)

   #
   def sql_apply_query_filters_last_editor_revisionless(self, qb, where_clause,
                                                                  conjunction):

      # CXPX: Parts of the if and the else and basically copies on one another.
      if qb.filters.include_item_stack:
         qb.sql_clauses.inner.join += (
            """
            JOIN item_revisionless AS ir_n
               ON (ir_n.system_id = gia.item_id
                   AND ir_n.acl_grouping = 1)
            """)
         qb.sql_clauses.inner.shared += (
            """
            --, ir_n.edited_date
            , TO_CHAR(ir_n.edited_date, 'MM/DD/YYYY HH:MI am') AS edited_date
            , ir_n.edited_user
            , ir_n.edited_addr
            , ir_n.edited_host
            , ir_n.edited_note
            , ir_n.edited_what
            """)
         qb.sql_clauses.outer.enabled = True
         qb.sql_clauses.outer.shared += (
            """
            , group_item.edited_date
            , group_item.edited_user
            , group_item.edited_addr
            , group_item.edited_host
            , group_item.edited_note
            , group_item.edited_what
            """)
      else:
         qb.sql_clauses.outer.enabled = True
         qb.sql_clauses.outer.join += (
            """
            JOIN item_revisionless AS ir_n
               ON (ir_n.system_id = group_item.system_id
                   AND ir_n.acl_grouping = 1)
            """)
         qb.sql_clauses.outer.shared += (
            """
            --, ir_n.edited_date
            , TO_CHAR(ir_n.edited_date, 'MM/DD/YYYY HH:MI am') AS edited_date
            , ir_n.edited_user
            , ir_n.edited_addr
            , ir_n.edited_host
            , ir_n.edited_note
            , ir_n.edited_what
            """)

      # C.f. item_stack.sql_apply_query_filters_last_editor_revisioned

      if qb.filters.filter_by_creator_include:
         cnames = ','.join(
            [qb.db.quoted(x)
               for x in qb.filters.filter_by_creator_include.split(',')])
         where_clause += (
            """
            %s (ir_n.edited_user IN (%s))
            """ % (conjunction, 
                   cnames,))
         conjunction = "AND"

      if qb.filters.filter_by_creator_exclude:
         cnames = ','.join(
            [qb.db.quoted(x)
               for x in qb.filters.filter_by_creator_exclude.split(',')])
         where_clause += (
            """
            %s (ir_n.edited_user NOT IN (%s))
            """ % (conjunction, 
                   cnames,))
         conjunction = "AND"

      # FIXME: Same as qb.filters.filter_by_creator_include ?
      if qb.filters.filter_by_username:
         # This path probably not used; filter_by_username just used
         # by Tab_Latest_Activity_Base.
         filter_by_username = qb.filters.filter_by_username.lower()
         where_clause += (
            """
            %s (COALESCE(ir_n.edited_user, ir_n.edited_host) = %s)
            """ % (conjunction,
                   qb.db.quoted(filter_by_username),))
         conjunction = "AND"

      return (where_clause, conjunction,)

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, ir_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if ir_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               system_id
               , acl_grouping
               , branch_id
               , stack_id
               , version
               , edited_date
               , edited_user
               , edited_addr
               , edited_host
               , edited_note
               , edited_what
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(ir_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***


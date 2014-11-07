# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import time

import conf
import g

from grax.access_level import Access_Level
from gwis.query_filters import Query_Filters
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_nothing_found import GWIS_Nothing_Found
from item import grac_record
from item import item_base
from item import item_user_watching
from item import item_versioned
#from item import link_value
from item.util.item_type import Item_Type
from util_ import gml
from util_ import misc

__all__ = ['One', 'Many']

log = g.log.getLogger('group_revision')

# CODE_COUSINS: flashclient/items/gracs/New_Item_Policy.py
#               pyserver/item/grac/new_item_policy.py

class One(grac_record.One):

   item_type_id = Item_Type.GROUP_REVISION
   item_type_table = 'group_revision'
   item_gwis_abbrev = 'grev'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('group_id',            None,   True,   True,    int,  None, 'gpid'),
      ('group_ids',           None,   True,   None,    str,  None, 'gids'),
      # Skipping (client does not need): group_name
      # in item_versioned: ('branch_id', None, True, True),
      ('branch_name',         None,   True), # This prob isn't necessary, eithr
      ('revision_id',         None,   True,   True),
      ('visible_items',       None,   True,  False),
      ('is_revertable',       None,   True,  False),
      ('bbox',                None,   True,  False),
      ('geosummary',          None,   True,  False),
      # Skipping: geometry (it's only used by the viewport filter)
      # From revision table:
      ('timestamp',           None,   True),
      ('username',            None,   True),
      ('comment',             None,   True),
      ('reverted_count',      None,   True),
      ('is_revert',           None,   True),
      ('feedback_exists',     None,   True),
      ]
   attr_defns = grac_record.One.attr_defns + local_defns
   psql_defns = grac_record.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor
   
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      grac_record.One.__init__(self, qb, row, req, copy_from)

   # *** Built-in Function definitions

   #
   def __str__(self):
      return (
'%s / grev gid %s | rid %d | #%d | rvt? %s | %s.%s.%s | %s.%s.%s.%s'
         % (grac_record.One.__str__(self), self.group_id, self.revision_id, 
            self.visible_items, self.is_revertable, 
            self.bbox, self.geosummary, '', #self.geometry, 
            self.timestamp, self.username, self.comment, self.reverted_count,))

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
       # This object cannot be manipuled by clients.
      raise GWIS_Error('Illegal operation on group_revision.')

   # *** Saving to the Database

   #
   def save_core(self, qb):
      # Avoid not-null constraints in item_stack by setting unused attrs.
      self.access_style_id = Access_Style.all_denied
      grac_record.One.save_core(self, qb)
      # Save to the 'group_revision' table
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def save_core_pre_save_get_acs(self, qb):
      # This is redundant since we set this is save_core. That is, this fcn. is
      # never called. But we still want to override the base class, to be
      # thorough.
      return Access_Style.all_denied

   # ***

class Many(grac_record.Many):

   one_class = One

   __slots__ = (
      'revision_id_table_ref',
      )

   # *** Constructor

   def __init__(self):
      grac_record.Many.__init__(self)
      #
      self.revision_id_table_ref = None

   # *** SQL query_filters helper

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not where_clause) and (not conjunction))
      g.assurt((not conjunction) or (conjunction == "AND"))

      # We build custom SQL in sql_context_user (and don't use
      # item_user_access's search_get_sql(), so we cannot support
      # filters that edit qb.sql_clauses. We only support filters
      # that only modify the where clause.
      g.assurt(not (   qb.filters.filter_by_creator_include
                    or qb.filters.filter_by_creator_exclude
                    or qb.filters.stack_id_table_ref
                    or qb.filters.use_stealth_secret
                    or qb.filters.include_item_stack
                    # There are lots more filters we don't support...
                    # but there's no reason to list them all.
                    ))

      if qb.filters.filter_by_username:
         # %s (LOWER(rev.username) ~ LOWER(%s))
         # %s (rev.username ~* %s)
         # [lb] is curious why we use regex search when we want exact match.
         # MAYBE: Full Text Search @@ is faster than exact match = which is
         #        faster than LOWER() = LOWER() which is faster than regex ~.
         # NOTE: Do not need to lower username (already lower)
         filter_by_username = qb.filters.filter_by_username.lower()
         where_clause += (
            """
            %s (rev.username = %s)
            """ % (conjunction,
                   qb.db.quoted(filter_by_username),))
         conjunction = "AND"

      # Find items the user is watching and only those items' revisions.
      if (qb.filters.filter_by_watch_item
          or qb.filters.only_stack_ids):
         time_0 = time.time()
         # Clone the qb but keep the db: we want to make a temp table.
         watchers_qb = qb.clone(skip_clauses=True, skip_filtport=True)
         qfs = Query_Filters(req=None)
         qfs.filter_by_watch_item = qb.filters.filter_by_watch_item
         qfs.only_stack_ids = qb.filters.only_stack_ids
         watchers_qb.filters = qfs
         watchers_qb.finalize_query()
         watchers_qb.sql_clauses = (
            item_user_watching.Many.sql_clauses_cols_all.clone())
         watchers_many = item_user_watching.Many()
         inner_sql = watchers_many.search_get_sql(watchers_qb)
         # No: watchers_qb.db.close()
         self.revision_id_table_ref = 'temp__filter_rids'
         # MAYBE: The valid_start_rid and valid_until_rid are the
         #        group_item_access record's. These usually match
         #        the item_versioned rids, right? Whenever an item
         #        is edited, we update the access records... [lb] thinks.
         #        Otherwise, what we'd really want here is item_versioned's
         #        valid_start_rid and valid_until_rid.
         thurrito_sql = (
            """
            SELECT
               valid_start_rid,
               valid_until_rid
            INTO TEMPORARY TABLE
               temp__both_rids
            FROM
               (%s) AS foo_grv_1
            """ % (inner_sql,))
         rows = qb.db.sql(thurrito_sql)
         rid_union_sql = (
            """
            SELECT
               DISTINCT (filter_rid)
            INTO TEMPORARY TABLE
               %s
            FROM
               ((SELECT valid_start_rid AS filter_rid FROM temp__both_rids)
                UNION
                (SELECT valid_until_rid AS filter_rid FROM temp__both_rids))
               AS foo_grv_2
            """ % (self.revision_id_table_ref,))
         rows = qb.db.sql(rid_union_sql)
         log.debug('sql_apply_qry_fltrs: %s in %s'
                   % ('filter_by_watch_item or only_stack_ids',
                      misc.time_format_elapsed(time_0),))

      if qb.filters.filter_by_watch_feat:
         # This filter only makes sense for attachment item types.
         log.warning('group_revision does not support filter_by_watch_feat')
         raise GWIS_Nothing_Found()

      # FIXME: Show only changes to watched items...
      #qfs.filter_by_watch_geom = wr;
      #qfs.filter_by_watch_item = 0 or 1 or 2 ...
# 2013.03.29: To support CcpV1 feature, see search_for_geom and get a bbox.
#             Maybe: in CcpV2, you can watch non-regions, so we could get
#             a list of stack_ids the user is watching and return revisions
#             containing changes to those stack IDs...

      return grac_record.Many.sql_apply_query_filters(
                  self, qb, where_clause, conjunction)

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words=None,
                                                use_outer=False):
      table_cols.insert(0, 'rev.comment')
      return grac_record.Many.sql_apply_query_filter_by_text(
                     self, qb, table_cols, stop_words, use_outer)

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):
      # qb.filter.only_in_multi_geometry is set if either filter_by_regions or
      # filter_by_watch_geom is set. item_versioned.sql_apply_query_viewport
      # will add the ST_Intersects; we just tell it the name of our geom table.
      where_c = grac_record.Many.sql_apply_query_viewport(self, qb, 'grev')
      return where_c

   # ** Public interface

   #
   def sql_context_user(self, qb, *args, **kwargs):

      # FIXME: This fcn. is also called just for count(*), so make a simpler
      #        SQL query that doesn't calculate everything in the select

      # FIXME: Code C.f. new_item_policy and group_item_access, and doesn't use
      # SQL build hierarchy.

      # NOTE: Not getting group_id: it's irrelevant, as user is part of one or
      # more groups. Same reason for not populating item_versioned columns.

      gssql = ""
      where_filters = ""
      where_viewport = ""
      if qb.use_filters_and_viewport:
         # CAVEAT: This fcn. does not use qb.sql_clauses so the filters we use
         #         can only affect the where clause, and not the select, join,
         #         etc.
         where_filters = self.sql_apply_query_filters(qb)
      if qb.filters.include_geosummary:
         gssql = (
            """
            , ST_AsSVG(ST_Scale(ST_Collect(grac_item.geosummary), 
                                1, -1, 1), 0, %d) AS geosummary
            """ % (conf.db_fetch_precision,))
      if qb.viewport is not None:
         where_viewport = self.sql_apply_query_viewport(qb)

      outer_limit_clause = ""
      outer_offset_clause = ""
      #log.debug('search_get_sql: qb.filters: %s / qb.use_limit_and_offset: %s'
      #          % (qb.filters, qb.use_limit_and_offset,))
      if (qb.filters is not None) and qb.use_limit_and_offset:
         outer_limit_clause = qb.filters.limit_clause()
         outer_offset_clause = qb.filters.offset_clause()

      # FIXME: C.f. from thread.py
      sql_select_rev_username = (
         """
         CASE 
            WHEN (grac_item.username = '%s') THEN
               grac_item.host
            ELSE
               COALESCE(grac_item.username, grac_item.host)
            END AS username
         , grac_item.username AS raw_username
         """ % (conf.anonymous_username,)
         )

      # FIXME: Make sql sub-query for feedback exists
      #        and honor: qb.filters.rev_min, qb.filters.rev_max, 
      #                   qb.filters.rev_ids
      #fb_threads = link_post.Many()
      #use_filters_and_viewport = False
      #feedback_exists = fb_threads.search_by_stack_id_rhs(rev_ids???)
      #   feedback_exists = fb_threads.search_get_sql(qb, 
      #                                               use_filters_and_viewport)
      # see complaint in link_value.py: probably want to add l/rhs_stack_id to
      # query_filters
#
# FIXME: Get feedback exists... maybe have to do separate queries?
      feedback_exists = "FALSE AS feedback_exists"

      filter_rids_join = ""
      if self.revision_id_table_ref:
         filter_rids_join = (
            """
            JOIN %s AS filter_rids
               ON (rev.id = filter_rids.filter_rid)
            """ % (self.revision_id_table_ref,))

      # FIXME: Does this find all group_revisions to make each page of the rev
      # history? i think so...

      # FIXME: bbox_text is our fcn.: rename it cp_bbox_text
      sql = (
         """
         SELECT 

            grac_item.branch_id
            , grac_item.branch_name

            , grac_item.revision_id
            , grac_item.visible_items
            , grac_item.is_revertable

            , group_concat(grac_item.group_id::text) AS group_ids

            , bbox_text(ST_Collect(grac_item.bbox)) AS bbox
            %s -- geosummary (if requested; see gssql)

            , TO_CHAR(grac_item.timestamp, 'MM/DD/YYYY HH:MI am') AS timestamp
            , %s -- user friendly name (see sql_select_rev_username)
            , grac_item.comment
            , grac_item.reverted_count

            , grac_item.is_revert

            , %s -- feedback_exists

         FROM

            (SELECT 

               grev.branch_id
               , br_iv.name AS branch_name

               , grev.revision_id
               , grev.group_id
               , grev.visible_items
               , grev.is_revertable
               , grev.bbox
               , grev.geosummary

               , rev.timestamp
               , rev.username
               , rev.host
               , rev.comment
               , rev.reverted_count

               , (re.rid_victim IS NOT NULL) AS is_revert

            FROM

               user_ AS u
               JOIN group_membership AS gm
                  ON (u.id = gm.user_id)
               JOIN group_ AS gr
                  ON (gm.group_id = gr.stack_id)
               JOIN group_revision AS grev
                  ON (gr.stack_id = grev.group_id)
               JOIN revision AS rev
                  ON (grev.revision_id = rev.id)

               %s -- filter_rids_join

               JOIN item_versioned AS br_iv
                  ON (grev.branch_id = br_iv.stack_id)

               LEFT OUTER JOIN revert_event AS re 
                  ON (rev.id = re.rid_victim)

            WHERE

               u.username = %s

               AND gm.access_level_id <= %d

               AND grev.branch_id = %d

               %s -- grev.revision_id restrictions

               AND NOT gm.deleted
               --AND NOT gr.deleted
               --AND NOT br_iv.deleted

               -- check user access over rev range
               AND gm.valid_start_rid <= grev.revision_id
               AND grev.revision_id < gm.valid_until_rid
               -- 
               AND gr.valid_start_rid <= grev.revision_id
               AND grev.revision_id < gr.valid_until_rid

               -- get particular branch from branch stack_id
               AND br_iv.valid_start_rid <= grev.revision_id
               AND grev.revision_id < br_iv.valid_until_rid

               %s -- filters
               %s -- viewport

            ) AS grac_item

         WHERE

            grac_item.revision_id != %d -- rid_inf

         GROUP BY

            grac_item.branch_id
            , grac_item.branch_name

            , grac_item.revision_id
            , grac_item.visible_items
            , grac_item.is_revertable

            , grac_item.timestamp
            , grac_item.username
            , grac_item.host
            , grac_item.comment
            , grac_item.reverted_count

            , grac_item.is_revert

         ORDER BY

            grac_item.revision_id DESC

         %s %s

         """ % (
            # [outer] SELECT
            gssql,
            sql_select_rev_username,
            feedback_exists,
            filter_rids_join,
            # [inner] WHERE
            qb.db.quoted(qb.username),    # Given a certain user...
                                          # ...w/ group mmbrshp at reqv rev
            Access_Level.client,          # ...with at least client access
            # NOTE: The group_revision list is branch-specific: users cannot
            #       see changes made to parent branches 
            qb.branch_hier[0][0],         # get items for a particular branch
            self.sql_where_rev('grev', qb), # grev.revision_id restrictions
            where_filters,
            where_viewport,
            # [outer] WHERE               # ...at the specified revision
            # Don't fetch the special revisions.
            #  MAYBE: Is this necessary?
            conf.rid_inf,
            outer_limit_clause,
            outer_offset_clause,
            ))

# FIXME: route reactions:
# Implement this: maybe: maybe social revisions aren't saved to users' groups'
#                        group_revisions
# this is in CcpV1:
#   where = 'AND NOT is_social_rev(r.id)'

      return sql

   # Constrain by revision ID
   def sql_where_rev(self, tbl, qb):
      g.assurt(not ((qb.filters.rev_min or qb.filters.rev_max)
                  and (qb.filters.rev_ids)))
      where_rev = ""
      where_cjn = "AND"
      if qb.filters.rev_min > 0:
         where_rev += (" %s %s.revision_id >= %d " 
                       % (where_cjn, tbl, qb.filters.rev_min,))
         where_cjn = "AND"
      if qb.filters.rev_max > 0:
         where_rev += (" %s %s.revision_id <= %d " 
                       % (where_cjn, tbl, qb.filters.rev_max,))
         where_cjn = "AND"
      if qb.filters.rev_ids:
         where_rev += (" %s %s.revision_id IN (%s) " 
                       % (where_cjn,
                          tbl,
                          ','.join([str(x) for x in qb.filters.rev_ids]),))
         where_cjn = "AND"
      return where_rev

   # ***

# ***


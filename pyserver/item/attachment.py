# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import copy
import os
import sys

import conf
import g

from grax.access_level import Access_Level
from grax.user import User
from gwis.query_filters import Query_Filters
from gwis.query_viewport import Query_Viewport
from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import item_user_access
from item import item_user_watching
from item import item_versioned
# 2013.03.30: [lb] not sure we should/can import geofeature.
#             If not, move to qb.item_mgr.
from item import geofeature
from item import link_value
from item.feat import branch
from item.util.item_type import Item_Type

log = g.log.getLogger('attachment')

class One(item_user_watching.One):

   item_type_id = Item_Type.ATTACHMENT
   item_type_table = 'attachment'
   item_gwis_abbrev = 'attc'
   # This is a little coupled: all this class's derived classes' item_types.
   child_item_types = (
      Item_Type.ATTACHMENT,
      Item_Type.ANNOTATION,
      Item_Type.ATTRIBUTE,
      Item_Type.POST,
      Item_Type.TAG,
      Item_Type.THREAD,
      )

   item_save_order = 3

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ]
   attr_defns = item_user_watching.One.attr_defns + local_defns
   psql_defns = item_user_watching.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis([])

   # *** Constructor

   __slots__ = ()

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_user_watching.One.__init__(self, qb, row, req, copy_from)

   # *** Saving to the Database

   #
   def load_all_link_values(self, qb):

      # The base class shouldn't import link_value, so send it one.
      links = link_value.Many()

      self.load_all_link_values_(qb, links, lhs=True, rhs=False, heavywt=True)

   #
   def save_core(self, qb):
      item_user_watching.One.save_core(self, qb)
      # Save to the 'attachment' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def save_update(self, qb):
      g.assurt(False) # Not impl. for attachment.
      item_user_watching.One.save_update(self, qb)
      self.save_insert(qb, One.item_type_table, One.psql_defns, 
                           do_update=True)

   #
   def save_verify_creator_arbiter(self, qb):
      # BUG nnnn: This is a hack until posts' and threads' GIA records
      # are fixed. Currently, just one publicly-editable record is created.
      # Ideally, there'd be two records, one public-readable, and one
      # creator-editable/or-arbitable. But we're still left with how
      # to give branch arbiters edit-access to all users' threads and posts,
      # so arbiters can censor threads and posts... would that be controlled
      # by a GIA record for branch arbiters, or would it be controlled by
      # a new_item_policy record? For not, we do it in code: branch arbiters
      # can edit posts and threads.
      if self.version > 1:
         if qb.username == conf.anonymous_username:
            raise GWIS_Error('Must be item creator to edit said item.')
         try:
            branch.Many.branch_enforce_permissions(qb, Access_Level.arbiter)
         except GWIS_Error, e:
            raise GWIS_Error('Not creator or branch arbiter too bad.')

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, item):

      insert_expr = (
         "(%d, %d, %d, %d)"
         % (item.system_id,
            #? qb.branch_hier[0][0],
            # or:
            item.branch_id,
            item.stack_id,
            item.version,
            ))

      return insert_expr

   # ***

# ***

class Many(item_user_watching.Many):

   one_class = One

   # NOTE: Not Joining attachment table. It's got nothing new for us.

   # *** Constructor

   __slots__ = ()

   def __init__(self):
      item_user_watching.Many.__init__(self)

   @staticmethod
   def sql_format_timestamp(col_name_raw):
      return (
         """
         CASE 
            WHEN (%s > (now() - interval '1 day')) THEN
               TO_CHAR(%s::TIMESTAMP, 'HH:MI am')
            WHEN (%s > DATE_TRUNC('YEAR', now())) THEN
               TO_CHAR(%s::TIMESTAMP, 'Mon DD')
            ELSE
               TO_CHAR(%s::TIMESTAMP, 'MM/DD/YYYY')
            END
         """ % (col_name_raw,
                col_name_raw,
                col_name_raw,
                col_name_raw,
                col_name_raw,))

   # *** Public Interface

# Bug nnnn: 20110907: This and the next fcn. should be scrapped and replaced
# with calls to link_value instead. the link_value class checks permissions on
# things we join -- and this fcn. does not. I think we should do a link_value
# search on the attachment type desired, distinct on the lhs stack IDs, and
# then return those items. And besides not respecting permissions or branching,
# this fcn. embeds SQL into inner.join that makes fetching leafier items not
# find anything (that is, it does not respek use_filters_and_viewport).
#
# 2013.03.30: This is the old way of fetching attachments in a bbox.
#             See sql_apply_query_filters for current implementation.
   '''
   def search_for_items(self, *args, **kwargs):
      """
      Overrides the base class implementation (item_user_access). Fetching 
      attachments by viewport is a bit tricky, since attachments themselves 
      do not contain geometry. But if we fetch the link_values in a particular 
      viewport, we can then select the distinct set of attachments linked and
      return those.
      """

      qb = self.query_builderer(*args, **kwargs)

      # The viewport only applies to the links, since attachments don't have
      # geometry, so don't use a bbox for the attachments themselves. But we
      # can use filters, but not all of them, so we'll clone the filters.
      attc_qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      attc_qb.filters = copy.copy(qb.filters)

      self.sql_clauses_cols_setup(attc_qb)

      # If a viewport or geometry is specified, be magical.
      if ((qb.viewport and qb.viewport.include)
          or (qb.filters and (qb.filters.only_in_multi_geometry
                              # The filter used to be used for attachments
                              # but now it's just used for link_values
                              #or qb.filters.only_rhs_stack_ids
                              ))):

         # EXPLAIN: this code path is deprecated.
         #
         # We shouldn't search for attachments by bbox. Flashclient searches 
         # for all tags and attrs, and it searches link_values by rhs_stack_id.
         # But [lb] doesn't think anyone should search for attcs by bbox.
         log.warning('search_for_items: doing (slow?) attc-link_value search.')

         log.verbose('search_for_items: yes vp: %s' % (self,))
         # Make a query to get link_values and their geofeatures to determine 
         # which attachments to get (since attachments do not have geometry in 
         # group_item_access). Use the query as an embedded select and join 
         # against it to get just those attachments linked to items in the 
         # viewport or the filter.
         inner_sql = self.sql_by_viewport_inner_sql(qb)
         attc_qb.sql_clauses.inner.join += (
            """
            JOIN (%s) AS link_items
               ON (gia.stack_id = link_items.lhs_stack_id)
            """ % (inner_sql,))

      g.assurt(not attc_qb.viewport)
      # NOTE: It's probably a better solution to selectively copy from
      # qb.filters than to clone it and clear selectively (since we might add
      # new filter options but forget to include them here).
      #attc_qb.filters.filter_by_regions = ''
      #attc_qb.filters.filter_by_watch_geom = False
      #attc_qb.filters.filter_by_watch_item = 0
      attc_qb.filters.only_in_multi_geometry = None
      #attc_qb.filters.only_rhs_stack_ids = ''

      # NOTE: Normally, the item classes shouldn't call Query_Overlord, but it
      #       doesn't reference the attachment classes, just geofeatures.
      # Call without importing Query_Overlord.finalize_query(attc_qb):
      attc_qb.item_mgr.finalize_query(attc_qb)

      # NOTE: Not calling base class search_for_items.
      log.verbose('search_for_items: attc_qb: %s' % (attc_qb,))
      self.search_get_items(attc_qb)

      attc_qb.db.close()
   '''

   #
   def sql_by_viewport_inner_sql(self, qb):

      # See comments above. Fetching attc-link-feat in one go is a no-go.
      log.warning('sql_by_viewport_inner_sql: deprecated')

      # Copy the qb, but exclude filters.
      links_qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      links_qb.filters = Query_Filters(req=None)
      # Would these help?:
      #  filter_by_username, filter_by_unread, min_access_level
      #links_qb.filters.filter_by_regions = qb.filters.filter_by_regions
      #links_qb.filters.filter_by_watch_geom = qb.filters.filter_by_watch_geom
      #links_qb.filters.filter_by_watch_item = qb.filters.filter_by_watch_item
      links_qb.filters.only_in_multi_geometry = (
                                             qb.filters.only_in_multi_geometry)
      #links_qb.filters.only_rhs_stack_ids = qb.filters.only_rhs_stack_ids
      links_qb.sql_clauses = link_value.Many.sql_clauses_cols_name.clone()
      # NOTE Not doing +=, but replacing the selects
      # EXPLAIN Using distinct so we...
      links_qb.sql_clauses.outer.select = "DISTINCT(group_item.lhs_stack_id)"
      links_qb.sql_clauses.outer.shared = ""
      links_qb.sql_clauses.inner.where_item_type_id_fcn = (
                     self.search_item_type_id_sql_from_link)
      # Do we need to copy the viewport, too?
      g.assurt(not links_qb.viewport)
      if qb.viewport:
         links_qb.viewport = Query_Viewport(req=None)
         links_qb.viewport.include = qb.viewport.include
         links_qb.viewport.exclude = qb.viewport.exclude
      g.assurt(qb.use_filters_and_viewport)
      # EXPLAIN: Not calling links_qb.finalize_query? Not needed or !item_mgr?
      # Make a link_value Many object to make the SQL.
      links = link_value.Many()
      inner_sql = links.search_get_sql(links_qb)
      links_qb.db.close()
      return inner_sql

   #
   def search_item_type_id_sql_from_link(self, qb):
      # NOTE: Not calling parent, which tests gia.item_type_id against
      #       self.one_class.item_type_id. We do it a little different.
      where_clause = (""" (gia.item_type_id = %d 
                           AND gia.link_lhs_type_id = %d) """
                      % (link_value.One.item_type_id,
                         self.one_class.item_type_id,))
      return where_clause

   #
   def search_for_orphan_query(self, qb):
      '''Returns all attachments that aren't marked as deleted but don't have 
         any non-deleted link_values'''
      # See also the note in link_value.search_for_orphan_query. 

      g.assurt(False) # not tested

      # FIXME: remove this:
      #cols_item_versioned = ','.join([("iv.%s" % (attr_defn[0],)) 
      #                     for attr_defn in item_versioned.One.local_defns])

      sql = (
         """
         SELECT 
            iv.stack_id
         FROM 
            item_versioned AS iv
         JOIN
            %s AS at_child
               USING (system_id)
         WHERE
            NOT iv.deleted
            AND iv.valid_until_rid = %d
            AND NOT EXISTS (
               SELECT lv.stack_id 
               FROM link_value AS lv
               JOIN item_versioned AS iv_2
                  USING (system_id)
               WHERE lv.lhs_stack_id = iv.stack_id
                     AND iv_2.valid_until_rid = %d
                     AND NOT iv_2.deleted)
         """ % (self.one_class.item_type_table,
                conf.rid_inf,
                conf.rid_inf))
      self.sql_search(qb, sql)


   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not conjunction) or (conjunction == "AND"))

      # We can only call sql_where_filter_linked once per query. So we can't
      # support about_stack_ids or filter_by_watch_feat and a viewport query.
      sql_where_filter_linked_cnt = 0
      if qb.filters.about_stack_ids:
         sql_where_filter_linked_cnt += 1
      if qb.filters.filter_by_watch_feat:
         sql_where_filter_linked_cnt += 1
      if ((qb.viewport is not None) and (qb.viewport.include)
          or qb.filters.only_in_multi_geometry):
         sql_where_filter_linked_cnt += 1
      if qb.filters.filter_by_nearby_edits:
         sql_where_filter_linked_cnt += 1
      if sql_where_filter_linked_cnt > 1:
         raise GWIS_Error('Please choose just one: '
                          'about_stack_ids, filter_by_watch_feat or viewport.')

      if qb.filters.about_stack_ids:
         linked_items_where = self.sql_where_filter_about(qb)
         g.assurt(linked_items_where)
         where_clause += " %s %s " % (conjunction, linked_items_where,)
         conjunction = "AND"

      if qb.filters.filter_by_watch_feat:
         # FIXME: Debug, then combine handlers for filter_by_watch_feat
         #                                     and only_in_multi_geometry.
         feat_qb = qb.clone(skip_clauses=True, skip_filtport=True)
         feat_qb.filters = Query_Filters(req=None)
         qfs = feat_qb.filters
         # Set filter_by_watch_item=True and search for geofeatures
         # that the user is watching.
         qfs.filter_by_watch_item = qb.filters.filter_by_watch_feat
         g.assurt(not qb.filters.only_in_multi_geometry)
         g.assurt((qb.viewport is None) or (qb.viewport.include is None))
         feat_qb.finalize_query()
         feat_qb.sql_clauses = geofeature.Many.sql_clauses_cols_all.clone()
         feats = geofeature.Many()
         feats_sql = feats.search_get_sql(feat_qb)
         feat_stack_id_table_ref = 'temp_stack_id__watch_feat'
         thurrito_sql = (
            """
            SELECT
               stack_id
            INTO TEMPORARY TABLE
               %s
            FROM
               (%s) AS foo_feat_sid_1
            """ % (feat_stack_id_table_ref,
                   feats_sql,))
         rows = qb.db.sql(thurrito_sql)
         #
         join_on_to_self = self.sql_where_filter_linked_join_on_to_self(qb)
         where_on_other = ""
         join_on_temp = (
            """
            JOIN %s
               ON (flv.rhs_stack_id = %s.stack_id)
            """ % (feat_stack_id_table_ref,
                   feat_stack_id_table_ref,))
         linked_items_where = self.sql_where_filter_linked(qb, join_on_to_self,
                                                               where_on_other,
                                                               join_on_temp)
         #
         where_clause += " %s %s " % (conjunction, linked_items_where,)
         conjunction = "AND"

      # 2013.04.02: Freshly implemented in CcpV2. Not the quickest fcn., but it
      #             works.
      #             MAYBE: Disable this until we can find a better solution?
      #             MEH: [lb] got it under 15 seconds, I think. Good enough.
      if qb.filters.filter_by_nearby_edits:

         '''
         g.assurt(False) # FIXME: This code is broke!

         join = ' JOIN post_geo pg ON (p.id = pg.id)'
         where_clause += (
            """
            %s 
            -- FIXME: Instead of ST_Intersects/ST_Buffer, try: ST_DWithin
               (ST_Intersects(
                  pg.geometry,
                  (SELECT ST_Buffer(collect(rr.geometry), 0)
                   FROM revision rr
                   WHERE
                     rr.username = %s
                     AND NOT is_social_rev(rr.id)))
            """ % (conjunction,
                   qb.db.quoted(qb.username),))
         conjunction = "AND"
         '''

         # FIXME: This was the older SQL snippet used for this filter. It
         #        was waaaaaayyyyy too slow. The one I used instead is also
         #        slow, but it doesn't time out, at least.
         #        [lb] notes that his database is missing geometry indices,
         #        but this didn't quite halve my experience, from 52 secs.
         #        to 29 secs. We need to run db_load_add_constraints.sql on
         #        the db.
         #        
         # sql_or_sids = (
         #    """
         #    SELECT
         #       stack_id
         #    FROM
         #       geofeature AS gf_near
         #    WHERE
         #       ST_Intersects(
         #          gf_near.geometry,
         #          (
         #             SELECT
         #                ST_Buffer(collect(rr.geometry), 0)
         #             FROM
         #                revision rr
         #             WHERE
         #                rr.username = %s
         #                -- AND NOT is_social_rev(rr.id)
         #          )
         #       )
         #    """
         #    ) % (qb.db.quoted(qb.username),)

         # FIXME: Very slow query: ~ 42 sec.
         '''
         sql_or_sids = (
            """
            SELECT
               stack_id
            FROM
               geofeature AS gf_near
               JOIN revision AS rv_near
                  ON ST_Intersects(gf_near.geometry, rv_near.geometry)
            WHERE
               rv_near.username = %s
               -- AND NOT is_social_rev(rv_near.id)
            """
            ) % (qb.db.quoted(qb.username),)
         '''

         # MAYBE: Why isn't setting user_group_id part of finalize_query?
         #g.assurt(not qb.user_group_id)
         if not qb.user_group_id:
            qb.user_group_id = User.private_group_id(qb.db, qb.username)
            g.assurt(qb.user_group_id)

         geometry_table_ref = 'temp_geometry__edited_items'
         geometry_sql = (
            """
            SELECT
               ST_Buffer(ST_Collect(grev.geometry), 0) AS geometry
            INTO TEMPORARY TABLE
               %s
            FROM
               group_revision AS grev
            WHERE
               grev.group_id = %d
            """ % (geometry_table_ref,
                   qb.user_group_id,))
         # 2013.04.02: On [lb]: Time: 405.073 ms
         rows = qb.db.sql(geometry_sql)

         # NOTE: This is a broad query: if a revision contains edits far apart,
         #       we'll find all the geofeatures in between. E.g., for [lb], it
         #       finds hundreds of thousands of byways; not very useful.
         item_stack_id_table_ref = 'temp_stack_id__edited_items'
         about_stack_ids_sql = (
            """
            SELECT
               DISTINCT(stack_id)
            INTO TEMPORARY TABLE
               %s
            FROM
               geofeature AS feat
            JOIN
               %s AS grev
               ON ST_Intersects(feat.geometry, grev.geometry)
            """ % (item_stack_id_table_ref,
                   geometry_table_ref,
                   ))
         # 2013.04.02: On [lb]: Time: 13106.527 ms
         rows = qb.db.sql(about_stack_ids_sql)
         #
         join_on_to_self = self.sql_where_filter_linked_join_on_to_self(qb)
         where_on_other = ""
         join_on_temp = (
            """
            JOIN %s
               ON (flv.rhs_stack_id = %s.stack_id)
            """ % (item_stack_id_table_ref,
                   item_stack_id_table_ref,))
         linked_items_where = self.sql_where_filter_linked(qb, join_on_to_self,
                                                               where_on_other,
                                                               join_on_temp)
         #
         where_clause += " %s %s " % (conjunction, linked_items_where,)
         conjunction = "AND"

      # Only select posts whose name matches the user's search query.
      where_clause = item_user_watching.Many.sql_apply_query_filters(
                                 self, qb, where_clause, conjunction)

      return where_clause

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):

      where_clause = ""

      conjunction = "AND"

      if (((qb.viewport is not None) and (qb.viewport.include))
          or qb.filters.only_in_multi_geometry):

         # FIXME: Debug, then combine handlers for filter_by_watch_feat
         #                                     and only_in_multi_geometry.

         # This is Discussion's "About objects in visible area"
         #   and "Filter by Region (Names)"
         #   and "Filter by Watch Regions"

         # MAYBE: We should probably restrict this query to a maximum size, to
         #        avoid really strenuous database queries.

         feat_qb = qb.clone(skip_clauses=True, skip_filtport=True)
         qfs = Query_Filters(req=None)
         qfs.only_in_multi_geometry = qb.filters.only_in_multi_geometry
         feat_qb.filters = qfs
         feat_qb.viewport = qb.viewport         
         feat_qb.finalize_query()
         feat_qb.sql_clauses = geofeature.Many.sql_clauses_cols_all.clone()
         feats = geofeature.Many()
         feats_sql = feats.search_get_sql(feat_qb)
         # No: feats_sql.db.close()
         feat_stack_id_table_ref = 'temp_stack_id__viewport'
         thurrito_sql = (
            """
            SELECT
               stack_id
            INTO TEMPORARY TABLE
               %s
            FROM
               (%s) AS foo_vport_sid
            """ % (feat_stack_id_table_ref,
                   feats_sql,))
         rows = qb.db.sql(thurrito_sql)
         #
         count_sql = ("SELECT COUNT(*) FROM %s" % (feat_stack_id_table_ref,))
         rows = qb.db.sql(count_sql)
         # 2014.05.04: [lb] sees it faster to WHERE IN (SELECT ... FROM tmp)
         #             rather than to join on the tmp table.
         n_sids = rows[0]['count']
         log.debug('sql_where_filter_linked: tmp tble rows: %d' % (n_sids,))
         # DETERMINE: What's the best cutoff point?
         if n_sids > 2500:
            # Does this path happen?
            log.warning('sql_where_filter_linked: test me: join vs. where')
            join_on_to_self = self.sql_where_filter_linked_join_on_to_self(qb)
            where_on_other = ""
            join_on_temp = (
               """
               JOIN %s
                  ON (flv.rhs_stack_id = %s.stack_id)
               """ % (feat_stack_id_table_ref,
                      feat_stack_id_table_ref,))
            linked_items_where = self.sql_where_filter_linked(
               qb, join_on_to_self, where_on_other, join_on_temp)
         else:
            # Use WHERE rather than JOINing.
            (linked_items_where, sql_tmp_table,
               ) = link_value.Many.prepare_sids_temporary_table(self.qb,
                     'rhs_stack_id',
                     feat_stack_id_table_ref,
                     'lhs_stack_id',
                     'temp_stack_id__feats_attcs')
         #
         log.debug('sql_where_filter_linked: conjunction: %s' % (conjunction,))
         where_clause += " %s %s " % (conjunction, linked_items_where,)
         conjunction = "AND"

      # Not calling item_versioned.Many.sql_apply_query_viewport, since
      # we've processed the viewport.

      return where_clause

   #
   def sql_where_filter_linked_join_on_to_self(self, qb):
      join_on_to_self = "attc.stack_id = flv.lhs_stack_id"
      return join_on_to_self

   #
   def sql_where_filter_linked_where_unto_self(self):
      #where_unto_self = "attc.stack_id IN (SELECT stack_id FROM %)"
      where_unto_self = "flv.lhs_stack_id IN (SELECT stack_id FROM %)"
      return where_unto_self

   #
   def sql_where_filter_about(self, qb):

      # "Filter by what is visible in the map"
      #
      # This is used if the user is at vector zoom level (because then the
      # client has geofeature stack IDs on the items in the viewport). At
      # raster zoom level, the client sends a bbox, so this filter isn't used.
      #
      # PERMS: Unless it's a custom client trying to hack us, we sent the
      # rhs stack IDs to the client earlier, so we can assume the client
      # has at least access_client to the rhs items. But even if the client
      # is trying to hack us, the point is moot; all a client would learn is
      # what random stack IDs it sent represent private geofeatures attached to
      # public threads, which is a case that can't even happen right now.

      join_on_to_self = self.sql_where_filter_linked_join_on_to_self(qb)
      where_on_other = ("(flv.rhs_stack_id IN (%s))"
                        % (qb.filters.about_stack_ids,))
      linked_items_where = self.sql_where_filter_linked(qb, join_on_to_self,
                                                            where_on_other)

      return linked_items_where

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, at_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if at_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               system_id
               , branch_id
               , stack_id
               , version
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(at_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***



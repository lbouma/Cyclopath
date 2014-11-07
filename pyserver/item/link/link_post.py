# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item import item_base
from item import item_versioned
from item.grac import group_revision
from item.link import link_geofeature
from item.util.item_type import Item_Type
from util_ import gml

log = g.log.getLogger('link_post')

class One(link_geofeature.One):

   # There is no link_post table...
   # MAYBE: Should probably make a link_post item type...
   #  item_type_id = Item_Type.LINK_POST
   #  item_type_table = 'link_post'
   #  item_gwis_abbrev = 'lp'

   child_item_types = None

   item_gwis_name = 'link_post'

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ]
   attr_defns = link_geofeature.One.attr_defns + local_defns
   psql_defns = link_geofeature.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      link_geofeature.One.__init__(self, qb, row, req, copy_from)

class Many(link_geofeature.Many):

   one_class = One

   # ***

   sql_clauses_cols_all = link_geofeature.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.join += (
      """
      JOIN post AS post
         ON (lhs_gia.item_id = post.system_id)
      """)

   # ***

   __slots__ = ()

   def __init__(self, feat_type=None):
      link_geofeature.Many.__init__(self, Item_Type.POST, feat_type)

   #
   def search_by_thread_id(self, qb, context_stack_id):

      qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)

      # FIXME: Don't need to worry about qb.diff_group?
      g.assurt(context_stack_id > 0)
      if not self.attr_stack_id:
         # linked byways, regions, and waypoints.
         self.sql_clauses_cols_setup(qb)
      else:
         # linked revisions (by way of /post/revision attribute).
         qb.sql_clauses = self.sql_clauses_cols_rev.clone()
         qb.sql_clauses.inner.join += (
            " JOIN post AS post ON (lhs_gia.item_id = post.system_id) ")
         qb.sql_clauses.inner.where += (
            " AND (link.rhs_stack_id = %d) " % (self.attr_stack_id,))
      qb.sql_clauses.inner.where += (
         " AND (post.thread_stack_id = %d) " % (context_stack_id,))

      self.search_get_items(qb)

      # The SQL we just ran doesn't get geosummaries for post_revisions, so we
      # do that here.
      # MAYBE: This scheme only supports one attribute, which happens to be
      #        /post/revision.
      if self.attr_stack_id:
         # Clear the clauses, since grac_record classes don't use clauses.
         qb.sql_clauses = None
         # Tell group_revision to include the geosummary information.
         qb.filters.include_geosummary = True
         # SPEED: Would it be faster to do one lookup rather than many, using 
         #          qb.filters.rev_ids = [...]?
         qb.use_filters_and_viewport = True
         qb.use_limit_and_offset = False
         log.debug('search_by_thread_id: looking for %d geosummaries.' 
                   % (len(self)))
         for one in self:
            qb.filters.rev_min = one.revision_id
            qb.filters.rev_max = one.revision_id
            grev = group_revision.Many()
            grev_sql = grev.sql_context_user(qb)
            #log.debug('grev_sql: %s' % (grev_sql,))
            res = qb.db.sql(grev_sql)
            if len(res) > 0:
               g.assurt(len(res) == 1)
               for row in res:
                  try:
                     one.line_geometry = row['geosummary']
                  except KeyError:
                     log.warning('search_by_thread_id: no geosummary col')
            else:
               log.warning('search_by_thread_id: no geosummary res')

      qb.db.close()

   # FIXME: Assert on the other search_ fcns, so no one inadvertently uses them

   # ***

# ***


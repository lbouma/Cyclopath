# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item import link_value
#from item.attc import attribute
#from item.attc import post
#from item.grac import group_revision
#from item.util import revision
from item.util.item_type import Item_Type
#from util_ import gml

log = g.log.getLogger('link_tag')

# FIXME: I have reservations about this class! we need to check permissions of 
# attachments and geofeatures, not just link_values, so maybe users of this 
# class need to do three item_user_access queries?
# 20110905: I think I solved this: link_value has to check perms on lhs and rhs
# on each fetched row.

class One(link_value.One):

   item_type_id = Item_Type.LINK_VALUE
   item_type_table = 'link_value'
   item_gwis_abbrev = 'lv'
   child_item_types = None

   __slots__ = ()

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      link_value.One.__init__(self, qb, row, req, copy_from)

   # *** GML/XML Processing

   def from_gml(self, qb, elem):
      g.assurt(False) # Invalid request.
      link_value.One.from_gml(self, qb, elem)

   # *** Saving to the Database

   def save_core(self, qb):
      g.assurt(False) # Invalid request.
      link_value.One.save_core(self, qb)

   # ***

# ***

class Many(link_value.Many):

   one_class = One

   sql_clauses_cols_all = link_value.Many.sql_clauses_cols_all.clone()

   # FIXME: This is somewhat similar to link_post. Make intermediate class, 
   #        link_attachment?

   sql_clauses_cols_all.inner.select += (
      """
      , rhs_gia.name AS gf_name
      , rhs_gia.deleted AS gf_deleted
      """)
   g.assurt(not sql_clauses_cols_all.inner.group_by_enable)
   sql_clauses_cols_all.inner.group_by += (
      """
      , rhs_gia.name
      , rhs_gia.deleted
      """)

   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.gf_name
      , group_item.gf_deleted
      , group_item.geometry
      """)

   # ***

   __slots__ = (
      'tag_name',
      )

   def __init__(self, tag_name, feat_type=None):
      link_value.Many.__init__(self, Item_Type.TAG, feat_type)
      self.tag_name = tag_name

   # Is this cool? We're not being true to the fcn. name, but this works.
   # NOTE: In link_attribute, it overrides search_by_stack_id_rhs and searches 
   #       for the attr stack_id first, and uses that to add to
   #       qb.sql_clauses.inner.where. In this class, we let search_get_sql
   #       call our fcn., search_item_type_id_sql, and we search by tag
   #       name. It's just one end of two different means.
   # NOTE: qb should contain a copy of sql_clauses_cols_all...
   #       'cause that's where tag_iv comes from... but this class is coupled
   #       to search_map, because it needs raw SQL, from search_get_sql. But 
   #       the item hierarchy always manages clauses itself when it returns
   #       Many() items.
   def search_item_type_id_sql(self, qb):
      where_clause = link_value.Many.search_item_type_id_sql(self, qb)
      # SECURITY: tag_name always supplied internally, so no need to db.quoted.
      where_clause += (" AND lhs_gia.name = '%s' " % (self.tag_name,))
      log.verbose('search_item_type_id_sql: where: %s' % (where_clause,))
      return where_clause

   # NOTE: Don't call the above function directly, silly! Instead, call:
   #
   #          tags.search_by_stack_id_rhs(bway.stack_id, qb)

   # ***

# ***


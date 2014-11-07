# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item import link_value
from item.util.item_type import Item_Type

# NOTE This module is the item/type package since it's similar to the other 
#      item types, but it's not really meant to be instantiated by the item 
#      factory.

log = g.log.getLogger('tag_counts')

class One(link_value.One):

   item_type_id = Item_Type.LINK_VALUE
   item_type_table = 'link_value'
   item_gwis_abbrev = 'lv'
   child_item_types = None

   __slots__ = ()

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      link_value.One.__init__(self, qb, row, req, copy_from)
      g.assurt(False) # This class shouldn't be called

   # *** GML/XML Processing

   def from_gml(self, qb, elem):
      g.assurt(False) # Invalid request.
      link_value.One.from_gml(self, qb, elem)

   # *** Saving to the Database

   def save_core(self, qb):
      g.assurt(False) # Invalid request.
      link_value.One.save_core(self, qb)

class Many(link_value.Many):

   one_class = One

   sql_clauses_cols_name = link_value.Many.sql_clauses_cols_name.clone()

   # The other item classes tend to use +=, that is, they add on to the
   # exisiting SQL bits. In contrast, this class just overwrites them. That's
   # because we're fudging the request: we don't want link_value stack IDs, we 
   # want one lhs_stack_id (the tag) and a count of rhs_stack_ids (the number
   # of byways to which that tag is applied).

   # NOTE: This class doesn't account for branches... it counts _all_ tag
   # applications that the user can see in all branches the user can see.

   g.assurt(not sql_clauses_cols_name.outer.enabled)
   sql_clauses_cols_name.outer.enabled = True

# FIXME: Should count_byways be computed in the outer select? I think this
# number might be a little inflated here...
   sql_clauses_cols_name.outer.select = (
      """
      group_item.lhs_stack_id
      , COUNT(DISTINCT group_item.rhs_stack_id) AS count
      """
      )

   sql_clauses_cols_name.outer.shared = ""

   g.assurt(not sql_clauses_cols_name.outer.group_by_enable)
   sql_clauses_cols_name.outer.group_by_enable = True
   sql_clauses_cols_name.outer.group_by = (
      """
      group_item.deleted
      , group_item.lhs_stack_id
      """)

   # *** Constructor

   __slots__ = ()

   def __init__(self, feat_type=None):
      link_value.Many.__init__(self, 'tag', feat_type)


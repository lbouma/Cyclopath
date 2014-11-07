# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item import link_value
from item.attc import annotation
from item.util.item_type import Item_Type

log = g.log.getLogger('link_annot')

class One(link_value.One):

   item_type_id = Item_Type.LINK_VALUE
   item_type_table = 'link_value'
   item_gwis_abbrev = 'lv'
   child_item_types = None

   __slots__ = ()

   def __init__(self, qb=None, row=None, req=None, copy_from=None, 
                      item_type_tuple=None):
      link_value.One.__init__(self, qb, row, req, copy_from, item_type_tuple)

   # ***

# ***

class Many(link_value.Many):

   one_class = One

   __slots__ = ()

   def __init__(self, attc_type=None, feat_type=None):
      link_value.Many.__init__(self, attc_type, feat_type)

   # ***

   #
   @staticmethod
   def lhs_stack_ids_sql(qb, rhs_stack_id):
      lhs_stack_ids_sql = (
         """
         SELECT lhs_stack_id
         FROM %s.%s
         WHERE branch_id = %d
           AND rhs_stack_id = %d
           AND deleted IS FALSE
           AND reverted IS FALSE
           AND link_lhs_type_id = %d
         """ % (conf.instance_name,
                One.item_type_table,
                qb.branch_hier[0][0],
                rhs_stack_id,
                annotation.One.item_type_id,
                ))
      return lhs_stack_ids_sql

   # ***

# ***


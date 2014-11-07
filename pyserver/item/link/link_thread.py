# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item import link_value
from item.util.item_type import Item_Type

log = g.log.getLogger('link_thread')

class One(link_value.One):

   item_type_id = Item_Type.LINK_VALUE
   item_type_table = 'link_value'
   item_gwis_abbrev = 'lv'
   child_item_types = None

   __slots__ = ()

   def __init__(self, qb=None, row=None, req=None, copy_from=None,
                      item_type_tuple=None):
      link_value.One.__init__(self, qb, row, req, copy_from, item_type_tuple)

class Many(link_value.Many):

   one_class = One

   __slots__ = ()

   def __init__(self, attc_type=None, feat_type=None):
      link_value.Many.__init__(self, attc_type, feat_type)


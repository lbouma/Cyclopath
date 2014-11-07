# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import sys

import conf
import g

from item import item_base
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import misc

__all__ = ['One', 'Many']

log = g.log.getLogger('item_helper')

class One(item_base.One):
   '''
   Represents information managed by a versioned item but itself is outside of
   the versioned and revisioned item system.
   '''

   item_type_id = None
   item_type_table = None # 'item_helper'
   item_gwis_abbrev = 'itmh'
   child_item_types = None

   local_defns = [
      ]
   attr_defns = item_base.One.attr_defns + local_defns
   psql_defns = item_base.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_base.One.__init__(self, qb, row, req, copy_from)

   #
   def save_core(self, qb):
      # Don't call base class.
      # Also, we never called validize.
      g.assurt(not self.valid)

class Many(item_base.Many):

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      item_base.Many.__init__(self)

   # ***

# ***


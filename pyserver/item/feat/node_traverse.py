# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

#try:
#   from osgeo import gdal
#   from osgeo import osr
#   from osgeo.gdalconst import GA_ReadOnly
#except ImportError:
#   import gdal
#   import osr
#   from gdalconst import GA_ReadOnly

import os
import sys

import conf
import g

from grax.access_level import Access_Level
from gwis.exception.gwis_error import GWIS_Error
from item import geofeature
from item import item_base
#from item import item_helper
from item import item_versioned
from item import permissions_free
from item.grac import group
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import gml
from util_ import misc

log = g.log.getLogger('node_travers')

class One(permissions_free.One):

   item_type = Item_Type.NODE_TRAVERSE
   item_type_table = 'node_traverse'
   item_gwis_abbrev = 'nt'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('node_stack_id',       None,  False,   True,    int,  None),
      ('exit_stack_id',       None,  False,   True,    int,  None),
      ('into_stack_id',       None,  False,   True,    int,  None),
      # FIXME: Not sure if this is integer or float.
      ('troll_cost',          None,  False,  False,    int,  None),
      # BUG nnnn: Turn Directions Help. Or whatever we call it, but some users
      # (in a user study) said the cue sheet isn't too helpful when it says,
      # e.g., "Turn from unnamed trail to unnamed trail." We could use
      # node_traverse to print additional help text at specific intersections.
      ]
   attr_defns = permissions_free.One.attr_defns + local_defns
   psql_defns = permissions_free.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      permissions_free.One.__init__(self, qb, row, req, copy_from)
      #
      # FIXME: Implement.
      g.assurt(False) # This class isn't fully implemented.

   # *** Init methods

   # *** Built-in Function definitions

   #
   def __str__(self):
      return permissions_free.One.__str__(self)

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      permissions_free.One.from_gml(self, qb, elem)

   #
   def append_gml(self, elem):
      return permissions_free.One.append_gml(self, elem)

   # *** Saving to the Database

class Many(permissions_free.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   sql_clauses_cols_all = permissions_free.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.select += (
      """
      , item.node_stack_id
      , item.exit_stack_id
      , item.into_stack_id
      , item.troll_cost
      """)

   sql_clauses_cols_all.inner.from_table = (
      """
      FROM
         node_traverse AS item
      """)

   # *** Constructor

   def __init__(self):
      permissions_free.Many.__init__(self)
      #
      # FIXME: Implement.
      g.assurt(False) # This class isn't fully implemented.

   # *** Table management

   indexed_cols = ('branch_id',
                   'stack_id',
                   'node_stack_id',
                   'exit_stack_id',
                   'into_stack_id',
                   #'troll_cost',
                   )

   #
   @staticmethod
   def drop_indices(db):
      # FIXME: This loop shared by the node_ classes. Put in some base class.
      for col_name in Many.indexed_cols:
         # E.g., "DROP INDEX IF EXISTS node_traverse_branch_id"
         db.sql("DROP INDEX IF EXISTS node_traverse_%s" % (col_name,))

   #
   @staticmethod
   def make_indices(db):
      # Drop the indices first.
      Many.drop_indices(db)
      #
      for col_name in Many.indexed_cols:
         # E.g., 
         #  "CREATE INDEX node_traverse_branch_id ON node_traverse(branch_id)"
         db.sql("CREATE INDEX node_traverse_%s ON node_traverse(%s)"
                % (col_name, col_name,))

   # ***

# ***


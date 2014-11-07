# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from item import geofeature
from item.util.item_type import Item_Type
from util_ import gml

log = g.log.getLogger('terrain')

class Geofeature_Layer(object):

   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   Open_Space = 101
   Water = 102
   Waterbody = 103
   Flowline = 104

   Z_DEFAULT = 121
   Z_DEFAULT_OPEN_SPACE = 110
   Z_DEFAULT_WATER = 120

class One(geofeature.One):

   item_type_id = Item_Type.TERRAIN
   item_type_table = 'geofeature'
   item_gwis_abbrev = 'ft'
   child_item_types = None
   gfl_types = Geofeature_Layer

   __slots__ = ()

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      # self.geofeature_layer_id = Geofeature_Layer.Default
      geofeature.One.__init__(self, qb, row, req, copy_from)

   # *** GML/XML Processing

   def append_gml_geometry(self, new):
      gml.append_Polygon(new, self.geometry_svg)

   def from_gml(self, qb, elem):
      geofeature.One.from_gml(self, qb, elem)
      self.set_geometry_wkt(gml.wkt_polygon_get(elem))

   # *** Saving to the Database

   def save_core(self, qb):
      g.assurt(False) # Unreachable Code / Not Implemented nor Supported
      geofeature.One.save_core(self, qb)

   # ***

   #
   def ensure_zed(self):
      # Derived classes should override this.
      if not self.z:
         if self.geofeature_layer_id == Geofeature_Layer.Open_Space:
            self.z = Geofeature_Layer.Z_DEFAULT_OPEN_SPACE
         elif self.geofeature_layer_id == Geofeature_Layer.Water:
            self.z = Geofeature_Layer.Z_DEFAULT_WATER
         else:
            self.z = Geofeature_Layer.Z_DEFAULT


   # ***

class Many(geofeature.Many):

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      geofeature.Many.__init__(self)

   # ***

# ***


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from item import geofeature
from item import item_user_watching
from item.util.item_type import Item_Type
from util_ import gml
from util_.streetaddress import ccp_stop_words

log = g.log.getLogger('waypoint')

class Geofeature_Layer(object):

   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   Default = 103

   Z_DEFAULT = 140

class One(geofeature.One):

   item_type_id = Item_Type.WAYPOINT
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

   #
   def append_gml_geometry(self, new):
      g.assurt(self.geometry_wkt)
      gml.append_Point(new, self.geometry_wkt)

   #
   def from_gml(self, qb, elem):
      geofeature.One.from_gml(self, qb, elem)
      self.set_geometry_wkt(gml.wkt_point_get(elem.text))

   # *** Search feature helpers

   #
   @staticmethod
   def search_center_sql(geom=None, table_name=None):
      g.assurt((geom is not None) or (table_name is not None))
      if table_name:
         geom_col_or_text = '%s.geometry' % (table_name,)
      else:
         # A geom, like '010100002023690000AE47E1FA4E3B1D4184EB516056005341'
         geom_col_or_text = "'%s'" % (geom,)
      as_center_sql = (
         """ ST_AsText(%s) """ % (geom_col_or_text,))
      return as_center_sql

   # ***

# ***

class Many(geofeature.Many):

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      geofeature.Many.__init__(self)

   # *** Query Builder routines

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      stop_words = ccp_stop_words.Addy_Stop_Words__Waypoint
      return geofeature.Many.sql_apply_query_filter_by_text(
                  self, qb, table_cols, stop_words, use_outer)

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):
      g.assurt((not where_clause) and (not conjunction))
      g.assurt((not conjunction) or (conjunction == "AND"))
      # Waypoints -- for whatever reason -- are special: we send flashclient
      # their WKT geometry; for all other geofeatures, we send the geometry as
      # SVG instead...
      log.verbose('sql_apply_query_filters: setting skip_geometry_svg')
      return geofeature.Many.sql_apply_query_filters(
               self, qb, where_clause, conjunction)

   # ***

# ***


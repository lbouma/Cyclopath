# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

from item import geofeature
from item.util import revision
from item.util.item_type import Item_Type
from util_ import gml
from util_.streetaddress import ccp_stop_words

log = g.log.getLogger('region')

# ***

class Geofeature_Layer(object):

   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   Default = 104
   Work_Hint = 108

   # SEE: select distinct(z), geofeature_layer_id from geofeature
   #      where geofeature_layer_id > 100 order by geofeature_layer_id asc;
   Z_DEFAULT_OTHER = 152
   Z_DEFAULT_CITY = 151
   Z_DEFAULT_TOWNSHIP = 150
   Z_DEFAULT_COUNTY = 149 # This is the lowest flashclient allows region Z.

# ***

class One(geofeature.One):

   item_type_id = Item_Type.REGION
   item_type_table = 'geofeature'
   item_gwis_abbrev = 'ft'
   child_item_types = None
   gfl_types = Geofeature_Layer

   __slots__ = []

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      #self.geofeature_layer_id = Geofeature_Layer.Default
      geofeature.One.__init__(self, qb, row, req, copy_from)

   # *** GML/XML Processing

   #
   def append_gml_geometry(self, new):
      if not self.geometry_svg:
         log.error('append_gml_geom: geometry_svg not set: %s' % (str(self),))
      gml.append_Polygon(new, self.geometry_svg)

   #
   def from_gml(self, qb, elem):
      geofeature.One.from_gml(self, qb, elem)
      # FIXME: the other geof from_gmls use elem.text here:
      self.set_geometry_wkt(gml.wkt_polygon_get(elem))

   # *** Search feature helpers

   #
   @staticmethod
   def search_center_sql(geom=None, table_name=None):
      g.assurt((geom is not None) or (table_name is not None))
      if table_name:
         geom_col_or_text = '%s.geometry' % (table_name,)
      else:
         # A geom, like '010100002023690000AE47E1FA4E3B1D4184EB516056005341'
         geom_col_or_text = "'%s'::GEOMETRY" % (geom,)

      # BUG nnnn: (Better) MULTIPOLYGON support. For now, using ST_GeometryN,
      # otherwise ST_ExteriorRing fails: 
      # BUG nnnn: Upgrade to PostGIS 2.1.x. (Requires later Psql than on svr.)
      # Also: ST_Line_Locate_Point renamed ST_LineLocatePoint in PostGIS 2.1.0.
      as_center_sql = (
         """  CASE
               WHEN ST_Within(ST_Centroid(%s), %s) THEN
                  ST_AsText(ST_Centroid(%s))
               ELSE
                  ST_AsText(ST_line_interpolate_point(
                              ST_ExteriorRing(ST_GeometryN(%s, 1)),
                              ST_line_locate_point(
                                 ST_ExteriorRing(ST_GeometryN(%s, 1)),
                                 ST_Centroid(%s))))
               END """ % (geom_col_or_text,
                          geom_col_or_text,
                          geom_col_or_text,
                          geom_col_or_text,
                          geom_col_or_text,
                          geom_col_or_text,))
      return as_center_sql

   # ***

   #
   def ensure_zed(self):
      # Derived classes should override this.
      if not self.z:
         if 'city' in self.tagged:
            self.z = Geofeature_Layer.Z_DEFAULT_CITY
         elif 'township' in self.tagged:
            self.z = Geofeature_Layer.Z_DEFAULT_TOWNSHIP
         elif 'county' in self.tagged:
            self.z = Geofeature_Layer.Z_DEFAULT_COUNTY
         else:
            self.z = Geofeature_Layer.Z_DEFAULT_OTHER

   # ***

# ***

class Many(geofeature.Many):

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      geofeature.Many.__init__(self)

   # *** Instance methods

   #
   # 2013.03.29: It's pretty lonely in this file, and search_for_geom has only
   # ever compiled the geometries of regions (either named or watched) so,
   # well, let's make this file its new home.
   def search_for_geom(self, qb, filter_by_regions, filter_by_watch_geom):

      # We don't support filter_by_regions and filter_by_watch_geom because
      # the latter needs to join link_value. If we wanted to support both (in
      # the same SQL statement), we'd have to LEFT OUTER JOIN and then do
      # some fancy WHERE ... OR ... filtering.  Which [lb] thinks would be
      # tedious. And no client currently combines these filters. So nuts to
      # that. Or is it bollocks?
      g.assurt(bool(filter_by_regions) ^ (bool(filter_by_watch_geom)))

      # This is by design. We could get old geometry, but there's no good
      # reason.
      g.assurt(isinstance(qb.revision, revision.Current))

      g.assurt(qb.use_filters_and_viewport)

      # Let sql_apply_query_filters know we're in a special geometry-finding
      # mode. 
      g.assurt(not qb.filters.setting_multi_geometry)
      qb.filters.setting_multi_geometry = True

      # The two filters, filter_by_regions and filter_by_watch_geom, are used
      # to tell us to do this special geometry-finding mode but we can't use
      # these again or we'd end up back here. So translate to other filters.
      qb.filters.filter_by_names_exact = filter_by_regions
      qb.filters.filter_by_watch_item = filter_by_watch_geom

      qb.sql_clauses = self.sql_clauses_cols_geom.clone()

      qb.finalize()

      # Get the search string
      g.assurt(not qb.db.dont_fetchall)
      sql = self.search_get_sql(qb)

      qb.filters.setting_multi_geometry = False

      # NOTE: ST_Union just makes a collection:
      #
      # SELECT ST_AsText(ST_Union(
      #    ST_GeomFromText('POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))'),
      #    ST_GeomFromText('POLYGON((10 10, 10 11, 11 11, 11 10, 10 10))')));
      #                                st_astext                               
      # -----------------------------------------------------------------------
      # MULTIPOLYGON(((0 0,0 1,1 1,1 0,0 0)),((10 10,10 11,11 11,11 10,10 10)))

      # Make a thurrito.
      third_ring_sql = (
         """
         SELECT
            ST_Union(geometry) AS geometry
         FROM
            (%s) AS foo_reg_1
         """ % (sql,))

      # Perform the SQL query and collect the results.
      res = qb.db.sql(third_ring_sql)
      for row in res:
         self.append(self.get_one(qb, row))

   # ***

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      stop_words = ccp_stop_words.Addy_Stop_Words__Region
      return geofeature.Many.sql_apply_query_filter_by_text(
                  self, qb, table_cols, stop_words, use_outer)

   # ***

# ***


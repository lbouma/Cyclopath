# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from lxml import etree

import conf
import g

from item import item_base
from item import item_versioned
from item.grac import group_revision
from item.link import link_uses_attr
from item.util.item_type import Item_Type
from util_ import gml

log = g.log.getLogger('link_geofeature')

class One(link_uses_attr.One):

   # There is no link_geofeature table...
   #  item_type_id = Item_Type.LINK_GEOFEATURE
   #  item_type_table = 'link_geofeature'
   #  item_gwis_abbrev = 'lg'
   # This is a little coupled: all this class's derived classes' item_types.
   # MAYBE: Do we really need this for this class?
   child_item_types = (
      Item_Type.LINK_GEOFEATURE,
      Item_Type.LINK_POST,
      )
   child_item_types = None

   item_gwis_name = 'link_geofeature'

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('gf_name',             None,   True),
      ('line_geometry',       None,  False),
      ('point_geometry',      None,  False),
      ('gf_deleted',          None,   True),
      ('revision_id',         None,  False),
      ]
   attr_defns = link_uses_attr.One.attr_defns + local_defns
   psql_defns = link_uses_attr.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      link_uses_attr.One.__init__(self, qb, row, req, copy_from)

   #
   def append_gml(self, elem, need_digest):
      new = etree.Element(self.item_gwis_name)
      log.debug('link_geofeature: append_gml: rhs type: %s' 
                % (self.link_rhs_type_id,))
      # This is a little hacky (better sol'n is to call item class, but
      # link_values just reference Item Type IDs, so... works for now).
      # NOTE: geometries might be none if user doesn't have access to 'em.
      if self.link_rhs_type_id == Item_Type.WAYPOINT:
         if self.point_geometry:
            gml.append_Point(new, self.point_geometry)
         else:
            log.warning('append_gml: no geometry for link_value-waypoint: %s'
                        % (self,))
      elif self.link_rhs_type_id == Item_Type.BYWAY:
         if self.line_geometry:
            gml.append_LineString(new, self.line_geometry)
         else:
            log.warning('append_gml: no geometry for link_value-byway: %s'
                        % (self,))
      elif self.link_rhs_type_id == Item_Type.REGION:
         if self.line_geometry:
            gml.append_Polygon(new, self.line_geometry)
         else:
            log.warning('append_gml: no geometry for link_value-polygon: %s'
                        % (self,))
      elif self.link_rhs_type_id == Item_Type.ROUTE:
         if self.line_geometry:
            gml.append_Polygon(new, self.line_geometry)
         else:
            log.warning('append_gml: no geometry for link_value-route: %s'
                        % (self,))
      else:
         # This is a post-revision link.
         # MAYBE: We only use the one attribute, /post/revision, but it
         #        couldn't hurt to generalize this in case the future finds us
         #        with more attributes. I.e., check that the linked attribute
         #        is /post/revision... by looking in qb.item_mgr.cache_attrs or
         #        cache_attrnames, probable...
         g.assurt(self.link_rhs_type_id == Item_Type.ATTRIBUTE)
         log.debug('append_gml: line_geo: %s / point_geometry %s' 
                   % (self.line_geometry, self.point_geometry,))
         if self.line_geometry:
            # FIXME: the geo is going in a doc named <external>.
            gml.append_Polygon(new, self.line_geometry)
         else:
            log.warning(
               'append_gml: no geometry for link_geofeature-revision: %s'
               % (self,))
      #log.debug('append_gml: gf_name: %s / gf_deleted: %s' 
      #          % (self.gf_name, self.gf_deleted,))
      return link_uses_attr.One.append_gml(self, elem, need_digest, new,
                                                 extra_attrs=None)

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      # In commit.py, we treat a link_geofeature item as just a link_value, so 
      # this fcn. shouldn't be called.
      g.assurt(False)
      link_uses_attr.One.from_gml(self, qb, elem)

   # *** Saving to the Database

   #
   def save_core(self, qb):
      # Invalid request. Same reason as from_gml: commit uses link_value.
      g.assurt(False)
      link_uses_attr.One.save_core(self, qb)

class Many(link_uses_attr.Many):

   one_class = One

   # ***

   sql_clauses_cols_all = link_uses_attr.Many.sql_clauses_cols_all.clone()

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

   # This seems a little hacky: line line and point geometry is sent 
   # differently to flashclient, but flashclient translates both differently,
   # too. My [lb's] guess is that we can fix this and just return one geom.
   # NOTE ST_AsSVG Converts the binary geometry object to an SVG object,
   #      which is what we put in the GML to return to the client
   # NOTE: line_geometry is SVG, and point_geometry is WKT... why?
   g.assurt(not sql_clauses_cols_all.outer.enabled)
   sql_clauses_cols_all.outer.enabled = True
   sql_clauses_cols_all.outer.select += (
      """
      , group_item.gf_name
      , group_item.gf_deleted
      , ST_AsSVG(ST_Scale(group_item.geometry, 1, -1, 1), 0, %d) 
                                       AS line_geometry
      , ST_AsText(group_item.geometry) AS point_geometry
      """ % (conf.db_fetch_precision))
   g.assurt(not sql_clauses_cols_all.outer.group_by_enable)
   sql_clauses_cols_all.outer.group_by_enable = True
   sql_clauses_cols_all.outer.group_by += (
      """
      , group_item.gf_name
      , group_item.gf_deleted
      , group_item.geometry
      """)

   #

   sql_clauses_cols_rev = sql_clauses_cols_all.clone()
   sql_clauses_cols_rev.inner.select += (
      """
      , rev.id AS revision_id
      """)
   g.assurt(not sql_clauses_cols_rev.inner.group_by_enable)
   #g.assurt(sql_clauses_cols_rev.inner.group_by)
   # sql_clauses_cols_rev.inner.group_by_enable = True
   sql_clauses_cols_rev.inner.group_by += (
      """
      , rev.id
      """)
   sql_clauses_cols_rev.inner.join += (
      # We don't need the attribute, but we could add it:
      #   JOIN attribute AS attr
      #      ON (rhs_gia.item_id = attr.system_id)
      """
      JOIN revision AS rev
         ON (link.value_integer = rev.id)
      """)
   sql_clauses_cols_rev.outer.select += (
      """
      , 'Revision ' || group_item.revision_id AS gf_name
      , FALSE AS gf_deleted
      """)
   sql_clauses_cols_rev.outer.shared += (
      """
      , group_item.revision_id
      """)

   # ***

   __slots__ = ()

   def __init__(self, attc_type, feat_type=None):
      link_uses_attr.Many.__init__(self, attc_type, feat_type)

   #
   def attribute_load(self, qb, attr_name):
      # Our link_lhs_type_ids member is a string of integers. But if it were a 
      # collect'n we'd g.assurt(Item_Type.ATTRIBUTE in self.link_lhs_type_ids).
      link_uses_attr.Many.attribute_load(self, qb, attr_name)

   # FIXME: Assert on the other search_ fcns, so no one inadvertently uses them

   # ***

# ***


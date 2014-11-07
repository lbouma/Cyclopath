# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import lxml.etree as et
import math

import conf
import g

from grax.access_level import Access_Level
from item.feat import byway
from item.grac import group
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import gml
from util_ import misc

log = g.log.getLogger('landmark')

class Landmark(object):

   item_type_id = Item_Type.LANDMARK

   # MAGIC_NUMBER: The April 2014 Landmarks experiment asks the user to
   #               look at and add landmarks to five routes.
   # SYNC_ME: pyserver/item/util/landmark.py::Landmark::experiment_count
   #     flashclient/items/utils/Landmark.as::Landmark::experiment_count
   experiment_count = 15

   max_search_distance = 75

   __slots__ = (
      'name',
      'item_id',
      'type_id',
      'geometry',
      'dist',
      'display',
      'step_number'
      )

   def __init__(self, name=None,
                item_id=None,
                type_id=None,
                geometry=None,
                step=-1,
                dist=-1,
                display=False):
      self.name = name
      self.item_id = item_id
      self.type_id = type_id
      self.geometry = geometry
      self.step_number = step
      self.dist = dist
      self.display = display

   #
   def append_gml(self, elem):
      new = et.Element(Item_Type.id_to_str(self.item_type_id))
      misc.xa_set(new, 'name', self.name)
      misc.xa_set(new, 'item_id', self.item_id)
      misc.xa_set(new, 'type_id', self.type_id)
      misc.xa_set(new, 'step', self.step_number)
      misc.xa_set(new, 'dist', self.dist)
      misc.xa_set(new, 'disp', self.display)
      if self.geometry:
         if self.type_id == Item_Type.WAYPOINT:
            gml.append_Point(new, self.geometry)
         else:
            gml.append_Polygon(new, self.geometry)
      elem.append(new)

#
def landmarks_compute(rsteps, qb):
   for i in xrange(0, len(rsteps)-1):
      this_step = rsteps[i]
      next_step = rsteps[i+1]
      this_step.landmarks = list()
      landmarks_pois(this_step, qb)
      landmarks_tags(this_step, next_step, qb)
      landmarks_big_crossings(this_step, qb)
      #landmarks_regions(this_step, qb)
      #landmarks_polygons(this_step, qb)
      landmarks_byway_geometry(this_step, qb)
      landmarks_graph_properties(this_step, qb)
      landmarks_intersection_props(this_step, qb)

# Retrieve landmarks from a random user for this route
# (This is part of the Landmarks Experiment, Part 2: Validation)
def landmarks_exp_retrieve(route, qb, username, uid):

   # get username whose landmarks we will evaluate
   sql = (
      """
      SELECT route_user
      FROM landmark_exp_route_p2_users AS users
      WHERE users.route_system_id = %s
         AND users.route_user_id = %s
         AND username = '%s'
      """ % (route.system_id, uid, username,))
   rows = qb.db.sql(sql)
   p2_user = rows[0]['route_user']
   
   # Retrieve all landmarks for this user and route
   sql = (
      """
      SELECT *, ST_AsText(landmark_geo) AS geo
      FROM landmark_exp_landmarks
      WHERE current
         AND username LIKE '%%%s%%'
         AND route_system_id=%s
      """ % (p2_user, route.system_id,))
   rows = qb.db.sql(sql)
   
   # Add landmarks to corresponding steps
   for r in rows:
      step_number = r['step_number']
      
      route.rsteps[step_number-1].landmarks.append(
         Landmark(name=r['landmark_name'],
                  item_id=r['landmark_id'],
                  type_id=r['landmark_type_id'],
                  geometry=r['geo'],
                  display=True))

#
def landmarks_pois(step, qb):
   # get geometry for end point of this step
   pts = gml.flat_to_xys(step.geometry)
   node_geo = pts[0]
   if (step.forward):
      node_geo = pts[len(pts) - 1]

   sql_str = (
      """
      SELECT
         DISTINCT ON (gia.stack_id) gia.stack_id,
         gia.acl_grouping,
         gia.name,
         gf.geometry AS geometry,
         ST_AsText(gf.geometry) AS geometry_wkt,
         ST_DISTANCE(gf.geometry, ST_SetSRID(ST_Point(%s, %s), %d)) as dist

      FROM group_item_access AS gia
         JOIN geofeature AS gf ON (gia.item_id = gf.system_id)

      WHERE gia.valid_until_rid = %d
        AND NOT gia.deleted
        AND NOT gia.reverted
        AND gia.branch_id = %d
        AND gia.item_type_id = %d
        AND ST_DISTANCE(gf.geometry, ST_SetSRID(ST_Point(%s, %s), %d)) < %d
        AND gia.group_id = %d
        AND gia.access_level_id <= %d

      ORDER BY gia.stack_id, gia.acl_grouping DESC
      """ % (node_geo[0], node_geo[1], conf.default_srid,
             conf.rid_inf,
             qb.branch_hier[0][0],
             Item_Type.WAYPOINT,
             node_geo[0], node_geo[1], conf.default_srid,
             Landmark.max_search_distance,
             group.Many.public_group_id(qb.db),
             Access_Level.client,))
   #gia.group_id IN (%s) => qb.filters.gia_use_gids?

   rows = qb.db.sql(sql_str)
   for row in rows:
      step.landmarks.append(Landmark(name=row['name'],
                                     item_id=row['stack_id'],
                                     type_id=Item_Type.WAYPOINT,
                                     geometry=row['geometry_wkt'],
                                     dist=row['dist']))

#
def landmarks_tags(step, new_step, qb):
   # idea: get tags that are on new step but not on this one
   node_id = step.beg_node_id
   if (step.forward):
      node_id = step.fin_node_id

   # get the tags of byways connected to end node

   # link value must be current (if it is, everything else should be current
   # too, right?)
   # I just want the byway ids and tag strings
   # link_value lhs_stack_id, rhs_stack_id
   # use node_byway table (byway_stack_id, node_stack_id, branch_id)

   sql_str = """
   SELECT
   node_byway.byway_stack_id,
   gia.stack_id AS lv_stack_id,
   tag.stack_id AS tag_stack_id,
   tgia.name AS tag_name

   FROM group_item_access AS gia
      JOIN link_value AS lv ON (gia.item_id = lv.system_id)
      JOIN node_byway ON (lv.rhs_stack_id = node_byway.byway_stack_id)
      JOIN tag ON (lv.lhs_stack_id = tag.stack_id)
      JOIN group_item_access AS tgia ON (tgia.item_id = tag.system_id)

   WHERE
      gia.valid_until_rid >= %d
      AND NOT gia.deleted
      AND NOT gia.reverted
      AND gia.branch_id = %d
      AND gia.item_type_id = %d
      AND tgia.valid_until_rid >= %d
      AND NOT tgia.deleted
      AND NOT tgia.reverted
      AND tgia.branch_id = %d
      AND tgia.item_type_id = %d
      AND node_byway.node_stack_id = %s
      AND node_byway.branch_id = %d

   """ % (conf.rid_inf,
          qb.branch_hier[0][0],
          Item_Type.LINK_VALUE,
          conf.rid_inf,
          qb.branch_hier[0][0],
          Item_Type.TAG,
          node_id,
          qb.branch_hier[0][0],)

   rows = qb.db.sql(sql_str)
   tags_this = list()
   tags_next = list()
   for row in rows:
      if (row['byway_stack_id'] == step.byway_stack_id):
         tags_this.append((row['tag_stack_id'], row['tag_name'],))
      if (row['byway_stack_id'] == new_step.byway_stack_id):
         tags_next.append((row['tag_stack_id'], row['tag_name'],))
   for tag in tags_next:
      contains = False
      for tag2 in tags_this:
         if (tag[0] == tag2[0]):
            contains = True
      if not contains:
         step.landmarks.append(Landmark(name=tag[1],
                                     item_id=tag[0],
                                     type_id=Item_Type.TAG))
   return

#
def landmarks_big_crossings(step, qb):
   # idea: get road of certain types (e.g. highways) that geometrically cross
   # this step
   # TODO: the intersection logic could be improved

   sql_str = (
      """
      SELECT
         DISTINCT ON (gia.stack_id) gia.stack_id,
         gia.acl_grouping,
         gia.name

      FROM group_item_access AS gia
         JOIN geofeature AS gf ON (gia.item_id = gf.system_id)

      WHERE
         gia.valid_until_rid = %d
         AND NOT gia.deleted
         AND NOT gia.reverted
         AND gia.branch_id = %d
         AND gia.item_type_id = %d
         AND ST_Crosses(gf.geometry, '%s'::GEOMETRY)
         AND gf.geofeature_layer_id IN (%d, %d, %d)
         AND gia.group_id = %d
         AND gia.access_level_id <= %d

      ORDER BY gia.stack_id, gia.acl_grouping DESC
      """ % (conf.rid_inf,
             qb.branch_hier[0][0],
             Item_Type.BYWAY,
             geometry.xy_to_ewkt_line(gml.flat_to_xys(step.geometry)),
             byway.Geofeature_Layer.Highway,
             byway.Geofeature_Layer.Expressway,
             byway.Geofeature_Layer.Major_Trail,
             group.Many.public_group_id(qb.db),
             Access_Level.client,))

   rows = qb.db.sql(sql_str)
   # Checking a set for membership is faster than using a list.
   name_list = set()
   for row in rows:
      try:
         if (len(row['name']) > 0 and not row['name'] in name_list):
            step.landmarks.append(Landmark(name=row['name'],
                                           item_id=row['stack_id'],
                                           type_id=Item_Type.BYWAY))
            name_list.add(row['name'])
      except TypeError:
         # row['name'] is None.
         pass
   return

#
def landmarks_regions(step, qb):
   # idea: get regions where one node of this step is on the region and the
   # other isn't
   return

#
def landmarks_polygons(step, qb):
   # idea: get polygons close to end node
   # Currently kind of useless because we don't have terrain names

   # get geometry for end point of this step
   pts = gml.flat_to_xys(step.geometry)
   node_geo = pts[0]
   if (step.forward):
      node_geo = pts[len(pts) - 1]

   sql_str = (
      """
      SELECT
         DISTINCT ON (gia.stack_id) gia.stack_id,
         gia.acl_grouping,
         gia.name,
         gf.geofeature_layer_id,
         gf.geometry AS geometry,
         ST_AsText(gf.geometry) AS geometry_wkt,
         ST_DISTANCE(gf.geometry, ST_SetSRID(ST_Point(%s, %s), %d)) AS dist,
         ST_AsSVG(ST_Scale(gf.geometry, 1, -1, 1), 0, %d) AS geometry_svg

      FROM group_item_access AS gia
         JOIN geofeature AS gf ON (gia.item_id = gf.system_id)

      WHERE
         gia.valid_until_rid = %d
         AND NOT gia.deleted
         AND NOT gia.reverted
         AND gia.branch_id = %d
         AND gia.item_type_id = %d
         AND ST_DISTANCE(gf.geometry, ST_SetSRID(ST_Point(%s, %s), %d)) < %d
         AND gia.group_id = %d
         AND gia.access_level_id <= %d

      ORDER BY gia.stack_id, gia.acl_grouping DESC
      """ % (node_geo[0], node_geo[1], conf.default_srid,
             conf.db_fetch_precision,
             conf.rid_inf,
              qb.branch_hier[0][0],
              Item_Type.TERRAIN,
              node_geo[0], node_geo[1], conf.default_srid,
              Landmark.max_search_distance,
              group.Many.public_group_id(qb.db),
              Access_Level.client,))

   rows = qb.db.sql(sql_str)
   for row in rows:
      # TODO: If namy is none, get terrain type
      log.debug('terrain geometry: ' + str(row['geometry_svg']))
      step.landmarks.append(Landmark(name=row['name'],
                                     item_id=row['stack_id'],
                                     type_id=Item_Type.TERRAIN,
                                     geometry=row['geometry_svg'],
                                     dist=row['dist']))
   return

#
def landmarks_byway_geometry(step, qb):
   # idea: detect curves?
   return

#
def landmarks_graph_properties(step, qb):
   # idea: detect T intersections

   pts = gml.flat_to_xys(step.geometry)
   step_xys = (pts[0], pts[1])
   node_id = step.beg_node_id
   if (step.forward):
      step_xys = (pts[len(pts)-1], pts[len(pts)-2])
      node_id = step.fin_node_id

   # find byways connected to this node

   sql_str = (
      """
      SELECT
         DISTINCT ON (gia.stack_id) gia.stack_id,
         gia.acl_grouping,
         ST_AsText(gf.geometry) AS geometry_wkt,
         gf.beg_node_id

      FROM group_item_access AS gia
         JOIN geofeature AS gf ON (gia.item_id = gf.system_id)
         JOIN node_byway ON (node_byway.byway_stack_id = gia.stack_id)

      WHERE
         gia.valid_until_rid = %d
         AND NOT gia.deleted
         AND NOT gia.reverted
         AND gia.branch_id = %d
         AND gia.item_type_id = %d
         AND node_byway.branch_id = %d
         AND node_byway.node_stack_id = %d
         AND NOT gia.stack_id = %s
         AND gia.group_id = %d
         AND gia.access_level_id <= %d

      ORDER BY gia.stack_id, gia.acl_grouping DESC
      """ % (conf.rid_inf,
             qb.branch_hier[0][0],
             Item_Type.BYWAY,
             qb.branch_hier[0][0],
             node_id,
             step.byway_stack_id,
             group.Many.public_group_id(qb.db),
             Access_Level.client,))

   rows = qb.db.sql(sql_str)

   # If not two, exit (no T intersection here)
   if not len(rows) == 2:
      return

   # get first two points of each byway
   byways_xys = list()
   for row in rows:
      xys = gml.flat_to_xys(row['geometry_wkt'])
      if (row['beg_node_id'] == node_id):
         byways_xys.append((xys[0], xys[1],))
      else:
         byways_xys.append((xys[len(xys)-1], xys[len(xys)-2],))

   # now we can calculate all angles, if the other two byways are almost
   # straight and they are both at least between 60 and 120 degrees from
   # this one

   angle1 = geometry.v_dir(step_xys[0], step_xys[1]) * 180 / math.pi
   angle2 = geometry.v_dir(byways_xys[0][0], byways_xys[0][1]) * 180 / math.pi
   angle3 = geometry.v_dir(byways_xys[1][0], byways_xys[1][1]) * 180 / math.pi

   # Check that agles are at 90+-30 degrees
   dif1 = angle1 - angle2
   if not ((abs(dif1) > 60 and abs(dif1) < 120)
       or (abs(dif1) > 240 and abs(dif1) < 300)):
      return
   dif2 = angle1 - angle3
   if not ((abs(dif2) > 60 and abs(dif2) < 120)
       or (abs(dif2) > 240 and abs(dif2) < 300)):
      return
   if (abs(dif2 - dif1) < 90):
      # angles are too close, probably perpendicular toward the same side
      return

   # We found a T intersection
   step.landmarks.append(Landmark(name='',
                                  item_id=-1,
                                  type_id=Item_Type.LANDMARK_T))

#
def landmarks_intersection_props(step, qb):
   # idea: in the future, this should return things like traffic light
   return


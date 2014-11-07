# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from item.feat import route_step
from planner.tgraph_base import Trans_Graph_Base
from planner.travel_mode import Travel_Mode
from util_ import geometry

log = g.log.getLogger('tgraph_p1')

__all__ = ('Trans_Graph',)

# *** Route Finder Personality (routed_pers) #1 -- Original Cycling Algorithm

class Trans_Graph(Trans_Graph_Base):
   'Transportation network as a graph.'

   __slots__ = (
      #
      # (x,y) coordinates of each node, e.g.:
      #
      #              { 119456: (-93.87231, 45.87632),
      #                119457: (-93.87201, 45.87660) }
      'node_xys',
      #
      # Dictionaries of route_step.Ones originating at each node, organized as
      # edges[from_id][to_id][byway_segment_id], e.g.:
      #
      #        { 119456: { 119457: { 42872: <route_step.One instance>,
      #                              59821: <route_step.One instance> },
      #                    327612: { 59541: <route_step.One instance> } }
      #          128732: { 119457: { 38171: <route_step.One instance> } }
      'edges',
      )

   # *** Constructor

   def __init__(self, route_daemon):
      Trans_Graph_Base.__init__(self, route_daemon)
      self.node_xys = dict()
      self.edges = dict()

   # *** Loading and Updating

   #
   def load_make_graph_insert_new(self, new_byway):

      # Alias the node IDs just for this fcn.
      bid = new_byway.beg_node_id
      eid = new_byway.fin_node_id

      # Initialize edges data structure with byway's node IDs.
      self.edges.setdefault(bid, dict())
      self.edges[bid].setdefault(eid, dict())
      self.edges.setdefault(eid, dict())
      self.edges[eid].setdefault(bid, dict())

      # Get the points' xs and ys so we can determine direction.
      # FIXME: Does it matter these values do not always match node_endpoint,
      # because of endpoint drift? (There's a bug about endpoints with the same
      # stack ID not sharing the same x,y.) 2012.07.30: Probably not, I think
      # point_beg and point_fin is just used for calculating distances and
      # directions between nodes.
      point_beg = geometry.wkt_point_to_xy(new_byway.beg_point)
      point_beg2 = geometry.wkt_point_to_xy(new_byway.beg2_point)
      point_fin = geometry.wkt_point_to_xy(new_byway.fin_point)
      point_fin2 = geometry.wkt_point_to_xy(new_byway.fin2_point)

      # Cache node x/y locations
      # FIXME: does this leak when node ids are orphaned?
      # BUG nnnn: Byways whose node endpoints have same ids but diff geom will
      # overwrite the value here.
      self.node_xys[bid] = point_beg
      self.node_xys[eid] = point_fin

      # Cache forward and backward edges.
      #
      # MAGIC NUMBER: 1 and -1 indicate the direction of the one way.
      if new_byway.one_way != -1:
         # Cache forward edge
         step = route_step.One()
         step.travel_mode = Travel_Mode.bicycle
         step.init_from_byway(new_byway)
         step.forward = True
         step.dir_entry = geometry.v_dir(point_beg, point_beg2)
         step.dir_exit = geometry.v_dir(point_fin2, point_fin)
         self.edges[bid][eid][step.byway_stack_id] = step
         # Bug 2641: Poor Python Memory Management
         # BUG nnnn: Directional attrs/tags. Maybe self.step_lookup is always a
         #           tuple with two entries, one for each direction?
         self.step_lookup_append(step.byway_stack_id, step)
      #
      if new_byway.one_way != 1:
         # Cache backward edge
         step = route_step.One()
         step.travel_mode = Travel_Mode.bicycle
         step.init_from_byway(new_byway)
         step.forward = False
         step.dir_entry = geometry.v_dir(point_fin, point_fin2)
         step.dir_exit = geometry.v_dir(point_beg2, point_beg)
         self.edges[eid][bid][step.byway_stack_id] = step
         # Bug 2641: Poor Python Memory Management
         self.step_lookup_append(step.byway_stack_id, step)

   #
   def load_make_graph_remove_old(self, old_byway):
      try:
         old_steps = self.step_lookup[old_byway.stack_id]
         self.load_make_graph_remove_old_steps(old_byway, old_steps)
      except KeyError:
         # This fcn. is called during update, so this means a user saved a new
         # byway to the database.
         log.verbose('_graph_remove_old: skipping new byway: %d' 
                     % (old_byway.stack_id,))
         pass

   #
   def load_make_graph_remove_old_steps(self, old_byway, old_steps):
      # FIXME: verbose
      log.debug('_graph_remove_old: old_steps: %s' % (old_steps,))
      for old_step in old_steps:
         not_found = False
         old_bid = old_step.beg_node_id
         old_eid = old_step.fin_node_id
         try:
            self.edges[old_bid][old_eid].pop(old_byway.stack_id, None)
         except KeyError:
            log.warning('failed to remove old byway from graph: no [bid][eid]')
            not_found = True
         try:
            self.edges[old_eid][old_bid].pop(old_byway.stack_id, None)
         except KeyError:
            log.warning('failed to remove old byway from graph: no [eid][bid]')
            not_found = True
         if not_found:
            log.warning(' >> old_byway.stack_id: %d / bid: %d / eid: %d'
                        % (old_byway.stack_id, old_bid, old_eid))
         else:
            log.verbose('_graph_remove_old: sid: %d / beg: %d / end: %d'
                        % (old_byway.stack_id, old_bid, old_eid,))
      del self.step_lookup[old_byway.stack_id]
      # FIXME: What about self.node_xys? I guess it just contains info of
      # deleted byways, since we cannot cleanup without using reference_n.

   # ***

# ***


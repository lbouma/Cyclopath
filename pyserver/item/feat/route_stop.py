# Copyright (c) 2006-2010 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# The route_stop class represents points on the map that a route must pass
# through. They can be addressable locations where a user intends to stop,
# intermediate control points to change the route, or transit stops.

from lxml import etree
import os
import sys

import conf
import g

from item import geofeature
from item import item_base
from item import item_helper
from item.feat import node_byway
from item.util.item_type import Item_Type
from util_ import gml
from util_ import misc

log = g.log.getLogger('route_stop')

# ***

# FIXME: The route_stop and node_endpoint tables are very similar...
#        should their be more collaboration between the two? (In CcpV1,
#        the node IDs and their geometry are stored in and calculated
#        from byway_segment; i.e., node_endpoint is new to CcpV2.)
#        I.e., if not is_transit_stop, then x,y should be node_id's
#        x,y (so we can nix the x,y columns, maybe, and just grab
#        from node_enpoint). And, i.e., if is_transit_stop, x,y are in
#        the gtfsdb cache (maybe; I can't remember; but we should
#        have an x,y cache of transit nodes like we do byway nodes).

class One(item_helper.One):
   """A stop along a route, that the path will pass through"""

   item_type = Item_Type.ROUTE_STOP
   item_type_table = 'route_stop'
   # The 'rs' abbrev is taken so use 'rw' for its former name, route waypoint.
   item_gwis_abbrev = 'rw'
   child_item_types = None

   local_defns = [
      # py/psql name,          deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      # NOTE: All of these values should at least be reqv=inreqd_local_only,
      #       otherwise mr_do fails to load routes for route analysis.
      ('route_id',             None,  False,   True,    int,     3),
      ('stop_number',          None,  False,   True,    int,     3),
      ('route_stack_id',       None,  False,  False,    int,     3),
      ('route_version',        None,  False,  False,    int,     3),
      # An address, point name, or transit station name.
      ('name',                 None,   True,  False,    str,     3),
      # FIXME: 2012.09.24: Like node_endpoint, shouldn't this be a point WKT?
      ('x',                    None,   True,  False,  float,     3),
      ('y',                    None,   True,  False,  float,     3),
      # Node ID might be NULL for transit (is_transit_stop) stops.
      ('node_id',              None,   True,  False,    int,     3),
      # If is_pass_through, means the user dragged the route in flashclient to
      # suggest a better route subsegment, i.e., the route finder will route
      # to/from this stop but it's not a place the user wants to visit (except
      # to pass through along their route). The user can also make pass
      # through stops by clicking Add Destionation, clicking the map, and
      # then leaving the route stop name blank in the route stop list.
      # 2014.04.28: Some routes (e.g., 1582594) exist where user added point
      # after last point, so, e.g., step 1 is not pass_thru but last step is.
      #  SELECT * FROM _rt_stop WHERE rt_stk_id = 1582594 AND rt_v = 2;
      # Skipping (like server has): 'is_endpoint' (can be deduced).
      ('is_pass_through',     False,   True,  False,   bool,     3),
      # For transit: if a transit board/alight stop, then is_transit_stop.
      ('is_transit_stop',     False,   True,  False,   bool,     3),
      # BUG nnnn: Finish implementing/test: internal_system_id/external_result.
      # internal_system_id is set to matching Cyclopath item if internally
      # geocoded. external_result is True if address or other external geocoder
      # was source of route stop's x,y and name.
      ('internal_system_id',      0,   True,  False,    int,     3, 'int_sid'),
      ('external_result',     False,   True,  False,   bool,     3, 'ext_res'),
      # NOTE: If !internal_system_id and !external_result, than user
      #       clicked on map or otherwise submitted x,y deliberately.
      ]
   attr_defns = item_helper.One.attr_defns + local_defns
   psql_defns = item_helper.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(psql_defns)

   __slots__ = [
      # The starting route_step number.
      'stop_step_number',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      item_helper.One.__init__(self, qb, row, req, copy_from)

   # ***

   #
   def __str__(self):
      s = ('stop: rte%s #%s / "%s" / nid: %s'
           % (self.route_id,
              self.stop_number,
              self.name,
              self.node_id,))
      return s

   # ***

   #
   def append_gml(self, elem):

      # MAYBE: This should be renamed 'rstop' but android still uses this name.
      new = etree.Element('waypoint')

      item_helper.One.append_gml(self, elem, need_digest=False,
                                       new=new, extra_attrs=None,
                                       include_input_only_attrs=False)

      return new

   #
   def from_gml(self, qb, elem):
      item_helper.One.from_gml(self, qb, elem)

   #
   def fit_route_step(self, step, at_start):

      # Get the node ID and node x,y from the byway for this route step. That
      # is, instead of using the geocoded xy, use Cyclopath's byway's xy.
      # FIXME: If you request a route from an address in the middle of the
      #        street, doesn't think move the point to the nearest
      #        intersection?? (TEST: 5038 dupont ave s)

      # FIXED?: Was: geom = gml.flat_to_xys(step.geometry[2:])
      geom = gml.flat_to_xys(step.geometry)

      if at_start:
         if step.forward:
            self.node_id = step.beg_node_id
            self.x = geom[0][0]
            self.y = geom[0][1]
         else:
            self.node_id = step.fin_node_id
            self.x = geom[-1][0]
            self.y = geom[-1][1]
      else:
         if step.forward:
            self.node_id = step.fin_node_id
            self.x = geom[-1][0]
            self.y = geom[-1][1]
         else:
            self.node_id = step.beg_node_id
            self.x = geom[0][0]
            self.y = geom[0][1]

#   #
#   def save(self, db, route_id, route_version, seq_num):
#      # (Don't call geofeature.One.save() because we don't use that ID pool.)
#      db.insert('route_stop',
#                {'route_id': route_id,
#                 'route_version': route_version,
#                 'stop_number': seq_num,},
#                {'name': self.name,
#                 'node_id': self.node_id,
#                 'is_pass_through': self.is_pass_through,
#                 'is_transit_stop': self.is_transit_stop,
#                 'internal_system_id': self.internal_system_id,
#                 'external_result': self.external_result,
#                 'x': self.x,
#                 'y': self.y,})
   #
   def save_rstop(self, qb, route, stop_number):

      log.debug('save_rstop: route: %s / stop_number: %s'
                % (route, stop_number,))

      #item_helper.One.save_core(self, qb)
      self.route_id = route.system_id
      self.stop_number = stop_number
      # FIXME: 2012.09.24: Drop the stack_id and version, eh?
      self.route_stack_id = route.stack_id
      self.route_version = route.version

      # 2014.09.13: There's been a bug until now wherein the user drags a new
      # route in the client, and when the route is saved, the client does not
      # send the intermediate stops' node IDs.
      if not self.node_id:

         pt_xy = (self.x, self.y,)
         nodes_byway = node_byway.Many()
         nodes_byway.search_by_endpoint_xy(qb, pt_xy, internals_ok=False,
                                                      limit_one=True)
         if len(nodes_byway) == 1:
            self.node_id = nodes_byway[0].node_stack_id
         else:
            g.assurt_soft(len(nodes_byway) == 0)
            log.warning('save_rstop: endpoint no found: %s' % (pt_xy,))
            g.assurt_soft(False)

      self.save_insert(qb, One.item_type_table, One.psql_defns)

   # ***

class Many(item_helper.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   # *** Constructor

   def __init__(self):
      item_helper.Many.__init__(self)

   # ***

   # ***

# ***


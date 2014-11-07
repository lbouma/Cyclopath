# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# BUG nnnn: 2012.09.26: Search for a route from DT Mpls to DT St Paul (i.e.,
#           the 94) at 9 AM and you may have to bike to a slow bus -- why
#           isn't the express bus suggested?

import os
# FIXME: Bug NNNN: Replace sqlite3 table with postgres table, and just keep a
# copy of the transit db alongside the other cyclopath tables, but in a
# different schema.
# ^^^ Maybe this doesn't matter. Is the sqlite3 db closed once the route finder
# is loaded? Is the load time so slow that we should bother importing into
# Postgres? Is there an easy way to import a sqlite3 file into Postgres?
import sqlite3
import time
import traceback

# 2013.11.18: This is new:
# /ccp/dev/cp/pyserver/planner/routed_p2/route_finder.py:24: UserWarning:
#  "Module osgeo was already imported from
#   /ccp/opt/usr/lib/python2.7/site-packages/GDAL-1.10.1-py2.7-linux-x86_64.egg
#   /osgeo/__init__.py, but /usr/lib64/python2.7/site-packages is being added
#   to sys.path"
from pkg_resources import require
require("Graphserver>=1.0.0")
from graphserver.core import Crossing
from graphserver.core import GenericPyPayload
from graphserver.core import Link
from graphserver.core import State
from graphserver.core import TripAlight
from graphserver.core import TripBoard
from graphserver.core import WalkOptions
from graphserver.ext.gtfs.gtfsdb import GTFSDatabase

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item.feat import byway
from item.feat import node_endpoint
from item.feat import route_step
from item.feat import route_stop
from item.util.item_query_builder import Item_Query_Builder
from planner.problem_base import Problem_Base
from planner.travel_mode import Travel_Mode
from planner.routed_p2.payload_byway import Payload_Byway
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc

__all__ = ['Problem']

log = g.log.getLogger('route_finder/p2')

class Problem(Problem_Base):

   __slots__ = (
      'req',
      'gserver',
      'beg_addr',
      'fin_addr',
      'beg_vertex_id',
      'fin_vertex_id',
      'beg_xy',
      'fin_xy',
      'rating_func',
      'rating_min',
      'p1_priority',
      'xy_crow_flies',
      'p2_depart_at',
      'p2_transit_pref',
      'is_reverse', # FIXME: Not implemented.
      'depart_time',
      'walk_opts',
      'phase_change_grade',
      'phase_change_velocity_factor',
      'spt_vertex_id',
      'db_gtfs',
      'qb',
      )

   # *** Constructor

   #
   def __init__(self, req, graph, rt,
                beg_vertex_id, fin_vertex_id, rating_func, rating_min,
                beg_xy, fin_xy, is_reverse=False):
      '''Finds a bike/transit route between the start and end vertices using
         the given graph. Uses the departure time and transit preference to
         determine when to route using transit, and when to route using
         bicycling.'''
      self.req = req # FIXME: Use to check branch, rev, and username?
      self.gserver = graph.gserver
      self.beg_vertex_id = str(beg_vertex_id)
      self.fin_vertex_id = str(fin_vertex_id)
      self.rating_func = rating_func
      self.rating_min = rating_min # FIXME: Not used?
      self.p1_priority = rt.p1_priority
      self.beg_xy = beg_xy
      self.beg_addr = rt.beg_addr
      self.fin_xy = fin_xy
      self.fin_addr = rt.fin_addr
      self.xy_crow_flies = 0.0
      self.p2_depart_at = rt.p2_depart_at
      if not self.p2_depart_at:
         raise GWIS_Error('Please specify p2_depart_at')
      self.p2_transit_pref = rt.p2_transit_pref
      self.depart_time = None
      self.walk_opts = None
      self.phase_change_grade = None
      self.phase_change_velocity_factor = None
      # FIXME: Carol has this coded but it's never True
      g.assurt(not is_reverse) # FIXME: Not implemented
      self.is_reverse = is_reverse
      # Internal members
      self.spt_vertex_id = None
      self.db_gtfs = None
      #
      self.qb = None

   # *** Public interface

   #
   def solve(self, qb):
      '''Solves the problem of getting from point A to point B.'''

      time_0 = time.time()

      log.debug('solve: solving...')

# FIXME_2013_06_14:
# FIXME/EXPLAIN: Why is qb passed to fcns. when also set as instance var?
# oh, also: up until 2013.06.14 no one noticed solve(qb) for p2 but solve() p1
      self.qb = qb

      # Get handles to the two databases
      self.db_gtfs = GTFSDatabase(conf.transitdb_filename)

      # Get the walk options used to calculate costs.
      # FIXME: Most walk options are currently hard-coded.
      self.walk_opts = self.get_walk_options()
      # The walk opts members are immutable, so save a ref to us for the Edge
      Payload_Byway.outstanding_problems[self.walk_opts.soul] = self

      # Convert the departure time string into seconds-since-epoch.
      depart_time = Problem.date_flashclient_mktime(self.p2_depart_at)
      # FIXME: Make this adjustment settable.
      slack = 5 * 60 # Number of seconds to wait at the first transit stop.
      self.depart_time = depart_time + slack

      # Ask Graphserver for the shortest path tree.
      spt = self.graphserver_get_spt()
      # Ask Graphserver for the lists of vertices and edges.
      (vertices, edges) = self.graphserver_get_path(spt)

      rsteps = route_step.Many()
      rstops = route_stop.Many()

      path_len = 0.0
      if len(vertices) > 0:
         # Convert the path into route steps we can send back to the client.
         (rsteps, rstops, path_len,) = self.path_convert(qb, vertices, edges)
         # Adjust bicycle route steps' times according to transit edges.
         # (That is, don't have the user get to the transit stop 30 mins.
         #  early.)
         self.steps_adjust_jit_arrival(rsteps, slack)
      # else, we'll raise in a moment, after cleaning up.

      del Payload_Byway.outstanding_problems[self.walk_opts.soul]

      # Destroy Graphserver C-objects
      spt.destroy()
      self.walk_opts.destroy()
      self.walk_opts = None

      log.debug('solve: route of %d steps found in %s'
         % (len(rsteps), misc.time_format_elapsed(time_0),))

      if not rsteps:
         log.error('solve: route not found?: %s' % (self,))
         # FIXME: This error message is not really "Help"ful. Why did the
         # request fail? What specifically can the user do to fix the problem?
         # SYNC_ME: This error message shared with routed_p1/route_finder.py.
         #raise GWIS_Error(
         #   'No route exists. Click "Help" for ideas on what to do next.')
         raise GWIS_Error(Problem_Base.error_msg_basic)

      # The path cost returned here is just for debugging. We'll compute it
      # later, anyway, so just toss back a negative.
      path_cost = -1.0

      return (rsteps, rstops, path_cost, path_len,)

   # *** First tier solve() helpers

   #
   def get_walk_options(self):
      # FIXME: WalkOptions is immutable and not completed wired into Python.
      #        We have to set some options that Graphserver uses (FIXME:
      #        Enumerate those options), but some of the options are only used
      #        by core/edgetypes/street.c, which we don't use. So I [lb] think
      #        we should probably make our own object and not worry about this
      #        one.
      # See graphserver/core.py, where all these options are defined.
      # See also graphserver/core/walkoption.c for the defaults:
      # FIXME: Magic Numbers. These should be user-choosable. See Cycloplan 2.
      walkoptions = WalkOptions()
      # The transfer_penalty is the no. of seconds penalty for each boarding.
      # Increase if routes contain frivolous transfers, or decrease if routes
      # avoiding all buses/trains/transit.
      walkoptions.transfer_penalty = 5000
      # NOTE: We don't care about turn_penalty; we have our own alg.
      walkoptions.turn_penalty = 120
      walkoptions.walking_speed = 4.5 # in meters per sec; approx 10 mph
      walkoptions.uphill_slowness = 0.05
      walkoptions.downhill_fastness = -12.1
      #walkoptions.phase_change_grade = 0.045;
      walkoptions.hill_reluctance = 0.0
      walkoptions.max_walk = 10000 # meters
      walkoptions.walking_overage = 0.1
      log.debug('get_walk_options: walk_ops.soul: %s' % (walkoptions.soul))
      # Graphserver defines these in walkoptions.c, but not in core.py. Hrm.
      # And we can't attach them to walkoptions because that's a C object.
      # And I [lb] quote: "Grade. An interesting thing thing happens at a
      #               particular grade, when they settle in for a long slog."
      self.phase_change_grade = 0.045;
      # From graphserver: "velocity between 0 grade and the phase change grade
      # is Ax^2+Bx+C, where A is the phase_change_velocity_factor, B is the
      # downhill fastness, and C is the average speed"
      # FIXME: See speed_from_grade: this is almost the same calculation,
      # expect speed_from_grade uses whatever the grade really is, and this
      # uses a static value for the grade....
      phase_change_speed = ((walkoptions.uphill_slowness
                             * walkoptions.walking_speed)
                            / (walkoptions.uphill_slowness
                               + self.phase_change_grade))
      self.phase_change_velocity_factor = (
         (phase_change_speed
          - (walkoptions.downhill_fastness * self.phase_change_grade)
          - walkoptions.walking_speed)
         / (self.phase_change_grade * self.phase_change_grade))
      log.debug('get_walk_options: phase_change_grade: %s'
                % (self.phase_change_grade,))
      log.debug('get_walk_options: phase_change_velocity_factor: %s'
                % (self.phase_change_velocity_factor,))
      # FIXME: Why waste time with SQL? If crow_flies_sql and crow_flies_raw
      #        return same results, use latter (_raw) (or maybe timeit first).
      crow_flies_sql = self.get_straightline_geom_len_sql(self.beg_xy,
                                                          self.fin_xy)
      crow_flies_raw = self.get_straightline_geom_len_raw(self.beg_xy,
                                                          self.fin_xy)
      if abs(crow_flies_raw - crow_flies_sql) > 0.01:
         log.warning(
            'Unexpectd diffr: xy: beg: %s / fin: %s // crow: sql: %s / raw: %s'
            % (self.beg_xy, self.fin_xy, crow_flies_sql, crow_flies_raw,))
      self.xy_crow_flies = crow_flies_raw

      log.debug('get_walk_options: xy_crow_flies: %s' % (self.xy_crow_flies,))
      if self.p2_transit_pref == -4:
         walkoptions.walking_reluctance = 0.5
         walkoptions.max_walk = Payload_Byway.ABSOLUTE_MAX_WALK
         # Don't go negative, unless you want a century spaghetti ride. It
         # means the further from the start you are, the more favored the edge.
         #walkoptions.walking_overage = -0.1 # favors walking
         walkoptions.walking_overage = 0.0
      elif self.p2_transit_pref == -2:
         walkoptions.walking_reluctance = 0.75
         walkoptions.max_walk = Payload_Byway.ABSOLUTE_MAX_WALK
         walkoptions.walking_overage = 0.0
      elif self.p2_transit_pref == 0:
         # Default value. Don't pref. either transit or biking.
         walkoptions.walking_reluctance = 1.0
         walkoptions.max_walk = Payload_Byway.ABSOLUTE_MAX_WALK # 1,000 km
         walkoptions.walking_overage = 0.0
      elif self.p2_transit_pref == 2:
         walkoptions.walking_reluctance = 1.0
         walkoptions.max_walk = int(self.xy_crow_flies * 1.33)
         walkoptions.walking_overage = 0.1
      elif self.p2_transit_pref == 4:
         walkoptions.walking_reluctance = 2.0
         walkoptions.max_walk = int(self.xy_crow_flies * 0.66)
         walkoptions.walking_overage = 0.1
      elif self.p2_transit_pref == 6:
         walkoptions.walking_reluctance = 2.0
         walkoptions.max_walk = 0
         walkoptions.walking_overage = 0.1
      else:
         g.assurt(False)
      log.debug('get_walk_options: relucance: %s / max_bike: %s / overage: %s'
                % (walkoptions.walking_reluctance, walkoptions.max_walk,
                   walkoptions.walking_overage,))
      return walkoptions

   #
   def graphserver_get_spt(self):
      time_0 = time.time()
      if not self.is_reverse:
         log.debug('graphserver_get_spt: forward / shortest_path_tree')
         spt_fcn = self.gserver.shortest_path_tree
         self.spt_vertex_id = self.fin_vertex_id
      else:
         log.debug('graphserver_get_spt: reverse / shortest_path_tree_retro')
         spt_fcn = self.gserver.shortest_path_tree_retro
         self.spt_vertex_id = self.beg_vertex_id
      spt = spt_fcn(self.beg_vertex_id, self.fin_vertex_id,
                    State(1, self.depart_time), self.walk_opts)
      log.debug('graphserver_get_spt: %s / spt: %s'
                % (misc.time_format_elapsed(time_0),
                   spt,))
      return spt

   #
   def graphserver_get_path(self, spt):
      time_0 = time.time()
      log.debug('graphserver_get_path: calling spt.path...')
      vertices = []
      edges = []
      try:
         (vertices, edges) = spt.path(self.spt_vertex_id)
         #for vertex in vertices:
         #   log.debug('graphserver_get_path: vertex.label: %s' % vertex.label)
         #for edge in edges:
         #   log.debug('graphserver_get_path: edge: %s' % (edge,))
      except Exception, e:
         # BUG 2286: If Graphserver cannot find a path, e.g., to "Ridgedale
         # Mall", it raises, e.g., "Exception: A path to 1302090 could not be
         # found".
         log.error('Unable to find a route: "%s" / %s'
                   % (str(e), traceback.format_exc(),))
         #raise GWIS_Error('Unable to find a route: %s' % (str(e),))
         raise GWIS_Error(Problem_Base.error_msg_basic)
      finally:
         log.debug('graphserver_get_path: %s / v. cnt: %d / e. cnt: %d'
                   % (misc.time_format_elapsed(time_0),
                      len(vertices), len(edges),))
      return (vertices, edges,)

   #
   # FIXME: This fcn. is obnoxiously long: split into into multiple fcns.
   def path_convert(self, qb, vertices, edges):

      # FIXME: should these be route_step.Many() and route_stop.Many()?
      route_steps = []
      route_stops = []

      last_alight = None
      last_board = None

      path_len = 0.0

      time_0 = time.time()

      log.debug('path_convert: making route steps...')

      for i in xrange(0, len(edges)):

         # NOTE: See class Edge in graphserver/core.py.
         edge = edges[i]

         beg_node = vertices[i]
         fin_node = vertices[i+1]

         # Handle byway.
         if isinstance(edge.payload, Payload_Byway):

            # FIXME: 2012.09.26: Is this still true?
            # Should not get a byway after a board edge without another edge.
            g.assurt(last_board is None)

            byway_step = self.make_route_step_bicycle(
                     edge.payload, beg_node, fin_node)

            log.debug('path_convert: Byway step: beg_nid: %d / fin_nid: %d'
                      % (byway_step.beg_node_id, byway_step.fin_node_id,))

            if i == 0:
               # For the first step, create a beginning stop.
               log.debug('path_convert: Adding first stop for byway step.')
               stop = route_stop.One(
                        qb, row={'name': self.beg_addr,
                                 'is_pass_through': False,
                                 'is_transit_stop': False,})
               stop.fit_route_step(byway_step, True)
               route_stops.append(stop)
            else:
               g.assurt(len(route_stops) > 0) # must have at least 1 by now

            if last_alight is not None:
               log.debug('Adding stop between TripAlight and Payload_Byway.')
               # Handle the case where we have a TripAlight and then
               # BywayPayload: we have to create the missing link (route stop).
               stop = route_stop.One(
                        qb, row={'name': last_alight.fin_sta_name,
                                 'is_pass_through': False,
                                 'is_transit_stop': True,})
               stop.fit_route_step(byway_step, True)
               route_stops.append(stop)
               last_alight = None
            # else: the last step was not an alight, so no stop missing.

            # Make any previous transit step's node id match up with this step
            # and repair the node_id of the last transit stop.
            if ((len(route_steps) > 0)
                and (route_steps[-1].travel_mode == Travel_Mode.transit)):
               node_id = (byway_step.beg_node_id if byway_step.forward else
                          byway_step.fin_node_id)

               if route_steps[-1].forward:
                  route_steps[-1].fin_node_id = node_id
               else:
                  route_steps[-1].beg_node_id = node_id

               if ((route_stops[-1].is_transit_stop)
                   and (route_stops[-1].node_id is None)):
                  route_stops[-1].node_id = node_id

            path_len += byway_step.edge_length

            # Push the byway step onto the list of steps.
            route_steps.append(byway_step)

         # Handle link (which links a transit edge and a Cyclopath edge, i.e.,
         # byway->transit and transit->byway transitions).
         elif isinstance(edge.payload, Link):

            # FIXME: 2012.09.26: Is this still true?
            # We should not get a link after a board edge without a transit
            # edge in between.
            g.assurt(last_board is None)

            link_step = self.make_route_step_link(qb, edge, beg_node, fin_node)

            log.debug('Encountered link step')

            if last_alight is not None:
               # We are a link after the alight, so steal its metadata.
               # EXPLAIN: When does Link follow TripAlight
               #      vs. when does Payload_Byway follow TripAlight?
               link_step.step_name = last_alight.step_name

               # Create a stop for the previous alight.
               stop = route_stop.One(
                        qb, row={'name': last_alight.step_name,
                                 'is_pass_through': False,
                                 'is_transit_stop': True,})
               log.debug('Adding stop after last TripAlight.')
               if ((i < (len(edges) - 1))
                   and (isinstance(edges[i + 1].payload, TripBoard))):
                  # Put stop at the start of the link.
                  stop.fit_route_step(link_step, True)
               else:
                  # Put stop at the end of the link.
                  stop.fit_route_step(link_step, False)
               route_stops.append(stop)
               last_alight = None

            # repair node_ids of the step if possible
            if ((len(route_steps) > 0)
                and (route_steps[-1].travel_mode == Travel_Mode.bicycle)):
               # grab a node id from the previous bike step
               if route_steps[-1].forward:
                  node_id = route_steps[-1].fin_node_id
               else:
                  node_id = route_steps[-1].beg_node_id
               if link_step.forward:
                  link_step.beg_node_id = node_id
               else:
                  link_step.fin_node_id = node_id

            # Push the link step onto the list of steps.
            route_steps.append(link_step)

         # Handle non-Link transit: TripAlight, TripBoard, and Crossing.
         else:

            tstep = self.make_route_step_transit(qb, edge, beg_node, fin_node)

            # Handle TripAlights.
            if isinstance(edge.payload, TripAlight):

               log.debug('Encountered TripAlight, storing for later')

               # Just store the alight in last_alight. A stop will be created
               # at the end of the loop or at the next byway/link encountered.
               last_alight = tstep

            # Handle TripBoards.
            elif isinstance(edge.payload, TripBoard):

               log.debug('Encountered TripBoard step')

               # Create a stop at the end of the previous step's geometry,
               # or at the start of the next if this is the first edge.
               stop = route_stop.One(
                        qb, row={'name': tstep.step_name,
                                 'is_pass_through': False,
                                 'is_transit_stop': True,})

               if len(route_steps) > 0:
                  log.debug('Creating stop for TripBoard.')
                  # If the previous step is a bicycle step, place at the end.
                  # If the previous step is a link, it's a weird situation
                  # where (Alight - Link - Board) so place at the end.
                  # And node_id is only set if the last step was a bike step.
                  # FIXME: Are we showing transit boardings at the Cyclopath
                  # node_endpoint or at the transit stop's actual x,y
                  # coordinates?
                  stop.fit_route_step(route_steps[-1], False)
                  route_stops.append(stop)
                  # Push metadata onto previous link.
                  if ((route_steps[-1].step_name is None)
                      and (route_steps[-1].travel_mode
                           == Travel_Mode.transit)):
                     route_steps[-1].step_name = tstep.step_name
               else:
                  # Store the TripBoard to be processed by the next Crossing
                  # step.
                  # FIXME: Make this verbose...
                  log.debug('Storing tripBoard for later use.')
                  last_board = tstep

            # Handle Crossings.
            elif isinstance(edge.payload, Crossing):

               # FIXME: log.verbose
               log.debug('Encountered Crossing edge')

               if last_board is not None:
                  # Add the stop.
                  # FIXME: log.verbose
                  log.debug('Adding stop from previously stored TripBoard.')
                  stop = route_stop.One(
                           qb, row={'name': last_board.step_name,
                                    'is_pass_through': False,
                                    'is_transit_stop': True,})
                  stop.fit_route_step(tstep, True)
                  route_stops.append(stop)
                  last_board = None

               # Repair the node_ids of the step if possible.
               if ((len(route_steps) > 0)
                   and (route_steps[-1].travel_mode == Travel_Mode.bicycle)):
                  # Grab a node id from the previous bike step.
                  if route_steps[-1].forward:
                     node_id = route_steps[-1].fin_node_id
                  else:
                     node_id = route_steps[-1].beg_node_id
                  if link_step.forward:
                     link_step.beg_node_id = node_id
                  else:
                     link_step.fin_node_id = node_id

               route_steps.append(tstep)

            # No other edge types.
            else:
               # This code should be unreachable.
               g.assurt(False)

      # We're done processing edges. See if we're missing the fininshing stop.
      if route_steps[-1].travel_mode == Travel_Mode.bicycle:
         log.debug('Adding last stop: after a bicycle step.')
         # Add a last stop for the path.
         stop = route_stop.One(
                  qb, row={'name': self.fin_addr,
                           'is_pass_through': False,
                           'is_transit_stop': False,})
         stop.fit_route_step(route_steps[-1], False)
         route_stops.append(stop)
      else:
         g.assurt(route_steps[-1].travel_mode == Travel_Mode.transit)
         if last_alight is not None:
            log.debug('Adding last stop: after a transit stop.')
            # We had a transit stop at the very end but no ending link to
            # process it, so add a transit stop.
            stop = route_stop.One(
                     qb, row={'name': last_alight.step_name,
                              'is_pass_through': False,
                              'is_transit_stop': True,})
            stop.fit_route_step(route_steps[-1], False)
            route_stops.append(stop)
         else:
            # EXPLAIN: We're all good?
            log.warning('Not adding last stop for after a transit stop?')

      # Fix route steps with null node IDs. I.e., transit stops should be
      # aligned with their byway neighbors so that we have a connected path.
      self.repair_node_ids(route_steps, route_stops)

      log.debug('Path conversion completed')

      # DEVS: Uncomment this if you want a lot of output...
      #for rs in route_steps:
      #   log.debug(' >> step: %s %s to %s %s'
      #             % (rs.transit_type,
      #                str(rs.beg_time),
      #                str(rs.fin_time),
      #                str(rs.transit_name)))
      log.debug('path_convert: %.2f secs / rs. cnt: %d'
                % ((time.time() - time_0), len(route_steps),))

      return (route_steps, route_stops, path_len,)

   # Replace null node_ids and beg_node_id/fin_node_id with unique negative
   # IDs, so that it's still possible to identify where a stop exists in a
   # route, even if the steps aren't part of the byway graph (since we don't
   # support editing multimodal routes... yet).
   # BUG nnnn: Routed p2: Editable routes.
   def repair_node_ids(self, route_steps, route_stops):

      # Repair any null step node ids.
      route_step.Many.repair_node_ids(self.qb, route_steps)

      # Iterate through the stops.
      last_found_step = -1
      for stop in route_stops:
         if not stop.node_id:
            # must find a route_step that fits this geometry and assign
            # the appropriate node id
            step_i = last_found_step + 1
            while step_i < len(route_steps):
               step = route_steps[step_i]
               # FIXED?: Was: geom = gml.flat_to_xys(step.geometry[2:])
               geom = gml.flat_to_xys(step.geometry)

# FIXME: MAGIC NUMBERS. FIXME: Use Ccp precision of 0.01?
#fixme: do something like this?
#existing_xy = geometry.wkt_point_to_xy(rows[0]['existing_xy_wkt'],
#                                    precision=conf.node_precision)
#proposed_xy = geometry.wkt_point_to_xy(self.endpoint_wkt,
#                                    precision=conf.node_precision)
#
# FIXME: How does these node IDs relate to node_endpoint, etc.?

               if ((abs(stop.x - geom[0][0]) < .0001)
                   and (abs(stop.y - geom[0][1]) < .0001)):
                  # matches start of the step
                  stop.node_id = step.beg_node_id
                  last_found_step = step_i
                  break
               elif ((abs(stop.x - geom[-1][0]) < .0001)
                     and (abs(stop.y - geom[-1][1]) < .0001)):
                  # matches end of the step
                  stop.node_id = step.fin_node_id
                  last_found_step = step_i
                  break
               step_i = step_i + 1
            # end while.

            # Since we moved transit edges' endpoints to match Cyclopath
            # node_endpoints, we should have found a matching step by now.
            g.assurt(stop.node_id)

         # else, stop.node_id is nonzero, so nothing to do.

   # Graphserver returns a route that leaves at the start time and will wait
   # at the transit stop for however long is necessary. Working back from the
   # first transit stop's departure, adjust start time of cycling steps to
   # minimize wait.
   def steps_adjust_jit_arrival(self, route_steps, slack):

      time_0 = time.time()
      log.debug('steps_adjust_jit_arrival: len(route_steps): %d'
                % (len(route_steps),))

      first_transit_step = None
      prev_transit_step = None
      steps_to_adjust = []

      # Look for the first transit edge.
      for step in route_steps:
         # NOTE: In Pre-Route Sharing, travel_mode was called transit_type
         # and in this fcn., we checked that it was 'board_bus' or
         # 'board_train'. Now, Travel_Mode.transit also includes the Crossing
         # and Link types (see also TripAlight and TripBoard), but Crossing
         # not Link should be the first step...
         if step.travel_mode == Travel_Mode.transit:
            # FIXME: g.assurt this is TripBoard?
            if first_transit_step is None:
               first_transit_step = step
            prev_transit_step = step
         else:
            # We trace back from the first transit stop, so assemble a list of
            # bicycle edges in reverse order.
            # FIXME: Only applies to init. bike edges? I.e., not after alight?
            #        What about transfers?
            if first_transit_step is None:
               steps_to_adjust.insert(0, step)
            if prev_transit_step is not None:
               # BUG 2296 Correct the board edges' end times: set to the
               # Crossing edge's start time and subtract a minute.
               prev_transit_step.fin_time = step.beg_time - 60
               prev_transit_step = None

      log.debug('steps_adjust_jit_arrival: found: %s (%d edges)'
                % (first_transit_step, len(steps_to_adjust),))

      # Bug 2293: If the first step is a transit edge, it's a Board edge, and
      # it's start time is the time for which the user requested the route
      # and for which we configured the State() object when we submitted the
      # problem to Graphserver. Correct the Board edge here, otherwise you get
      # wonky results -- e.g., if you request a route at 4 AM but the first bus
      # isn't until 6 AM, you'll get told to board the bus at 6 AM.

      # If there are no transit edges, this is an all-cycling route, so the
      # route steps do not need adjustment. Otherwise, go through route steps
      # and adjust the cycling edges' start and end times.
      if first_transit_step is not None:

         transit_departs = first_transit_step.fin_time
         total_duration = slack # No. seconds to wait at first transit stop
         first_transit_step.beg_time = transit_departs - total_duration

         for step in steps_to_adjust:
            duration = step.fin_time - step.beg_time
            step.fin_time = transit_departs - total_duration
            total_duration += duration
            step.beg_time = transit_departs - total_duration

      log.debug('steps_adjust_jit_arrival: %s / adjust cnt: %d'
                % (misc.time_format_elapsed(time_0),
                   len(steps_to_adjust),))

   # *** Route Step support routines

   #
   def make_route_step_bicycle(self, payload, beg_node, fin_node):
      # FIXME: Does route_step.forward and payload.reverse match up?
      #        Does it affect beg_node_id and fin_node_id?
      rs = route_step.One()
      rs.travel_mode = Travel_Mode.bicycle
      rs.init_from_byway(payload.byway)
      rs.forward = payload.forward
      # The rating is the generic rating; the caller, route.py, will
      # overwrite this with the logged-in user's rating, if the user is
      # logged in. Note that we can't use byway.user_rating, since the
      # Transit_Graph's byways is a collection on anon. user byways.
      rs.rating = payload.byway.generic_rating
      # Transit attrs.
      # Not applicable to bicycle edges: beg_sta_name, fin_sta_name,
      #                                  duration, transit_name
      # FIXME: Return 'duration'? It wouldn't be that hard to calculate
      # (we already do so in Payload_Cyclopath.cost_graphserver_passable)
      # (And I think flashclient caculates this value, too, but it's
      #  probably not the same as what we calculate... and then you have
      #  to maintain twice as much code, too. =)
      # Shared attrs.
      rs.beg_time = beg_node.state.time
      rs.fin_time = fin_node.state.time
      return rs

   #
   def make_route_step_link(self, qb, edge, beg_node, fin_node):

      # In old CcpV1, there was no travel_mode but instead here we used:
      #                'transit_type': 'link',
      rs = route_step.One(
               qb, row={'travel_mode': Travel_Mode.transit,
                        'forward': True,
                        'beg_time': beg_node.state.time,
                        'fin_time': fin_node.state.time,})

      # Get start and end points
      if beg_node.label.startswith('sta'):
         sql_beg_pt_wkt = self.get_xy_wkt_from_station_node(beg_node)
         sql_fin_pt_wkt = self.get_xy_wkt_from_network_node(fin_node)
      else:
         g.assurt(fin_node.label.startswith('sta')) # Is this right?
         sql_beg_pt_wkt = self.get_xy_wkt_from_network_node(beg_node)
         sql_fin_pt_wkt = self.get_xy_wkt_from_station_node(fin_node)

      # Get straightline geometry
      # FIXME: Can graph calculate this when it loads? (a) So we don't waste
      # time calculating it now, and (b) so we don't waste time re-calculating
      # every time someone makes a route request.
      # EXPLAIN: Why are we using SVG here? We usually use E/WKT and xy...
      rs.geometry_svg = self.get_straightline_geom(sql_beg_pt_wkt,
                                                   sql_fin_pt_wkt)

      return rs

   # A note about the difference between PSV and STA nodes. I'm still not quite
   # sure I get it. =)
   #
   # From Brandon Martin-Anderson (Graphserver Hero Extraordinaire):
   #
   #    "sta-" vertices are "station" vertices and correspond to physical
   #    transit stops. "psv-" are Pattern-Stop Vertices, or PSVs. These
   #    vertices represent the state of being on a transit vehicle traveling
   #    on a particular pattern at a particular stop. For example, a class of
   #    edges called "TripBoard" edges model moving between station vertices
   #    which model being at a station and _off_ a vehicle to pattern-stop
   #    vertices which model being at a station _on_ a vehicle. Then a class
   #    of edges called "Crossing" edges model going between to PSVs. It's
   #    a little contrived, but it's necessary to work around the dreaded
   #    Pro-Active Transferring Bug.
   #
   # Reference:
   #
   #   https://groups.google.com/group/graphserver/msg/7a18e62fdccf0722
   #   https://github.com/bmander/graphserver/wiki/Board---Alight---Crossing-Transit-Graphs
   #
   # Definition:
   #
   #   alighting: Descend from a train, bus, or other form of transportation.
   #
   def make_route_step_transit(self, qb, edge, beg_node, fin_node):

      rs = route_step.One(
               qb, row={'travel_mode': Travel_Mode.transit,
                        'forward': True,
                        'beg_time': beg_node.state.time,
                        'fin_time': fin_node.state.time,})

      transit_name = None
      beg_sta_name = None
      fin_sta_name = None
      beg_sta_node = None
      fin_sta_node = None

      # NOTE: Graphserver hard-codes the node labels with 'sta-' and 'psv-'
      #       prefixes. There's no other mechanism to determine the type of
      #       vertex other than doing a string compare on its label.
      if beg_node.label.startswith('psv'):

         # Get beg_sta_name and beg_sta_node.
         transit_name = self.get_transit_route_name(beg_node)
         beg_sta_node = self.transit_get_station_vertex(beg_node.label,
                                                        True)

         # BUG 2287: See below
         if beg_sta_node is None:
            log.info(
               'make_route_step_transit: no beg_sta_node: %s (%s / %s)'
               % (edge.payload, beg_node, fin_node,))
            # Well, if we go the other way, we should find a transit station.
            beg_sta_node = self.transit_get_station_vertex(beg_node.label,
                                                             False)
         if beg_sta_node is not None:
            beg_sta_name = self.get_stop_name(beg_sta_node)
         else:
            # BUG nnnn: l10n
            beg_sta_name = 'Start Here'
            log.warning('...step_transit: no beg_sta_node: beg_node: %s'
                        % (beg_node,))

      # MAGIC_NUMBER: 'psv': ...
      if fin_node.label.startswith('psv'):

         transit_name = self.get_transit_route_name(fin_node)
         fin_sta_node = self.transit_get_station_vertex(fin_node.label,
                                                        False)

         # BUG 2287: Some transit stops' PSV nodes only have incoming or
         #           outgoing Crossing edges, but do not have incoming or
         #           outgoing Alight or Board edges.
         #
         #           E.g. search for a multimodal route from 'cs building' to
         #           'moa' with Minimize Biking and More Busing, 6/29/2011 at
         #           8:45 AM. The last edge, before the Alight, is a Crossing
         #           whose vertices are both PSVs, but one of the PSVs is only
         #           attached to a Crossing edge, and not to an Alight or
         #           Board.
         #
         #           For now, this seems to do the trick: just look at the
         #           other direction (so, if the incoming edges is just a
         #           Crossing edge, look at the outgoing edges).
         #
         #           I'm not [lb isn't] 100% sure this is the proper solution,
         #           but it works for now....
         if fin_sta_node is None:
            log.info(
               'make_route_step_transit: no fin_sta_node: %s (%s / %s)'
               % (edge.payload, beg_node, fin_node,))
            fin_sta_node = self.transit_get_station_vertex(fin_node.label,
                                                           True)
         if fin_sta_node is not None:
            fin_sta_name = self.get_stop_name(fin_sta_node)
         else:
            # BUG nnnn: l10n
            fin_sta_name = 'End Here'
            log.warning('...step_transit: no fin_sta_node: fin_node: %s'
                        % (fin_node,))

      # FIXME: MAGIC_NUMBER: hack to identify light rail...
      # FIXME: What's the long term solution here? Is this data indicated in
      #        the GTFSDB?
      transit_type_name = 'Bus'
      if transit_name == '55':
         transit_type_name = 'Train'

      # MAYBE: Do we (in route_step) or does flashclient care about board v.
      #        alight?
      if isinstance(edge.payload, TripBoard):
         # TripBoard only needs station name and route name
         rs.step_name = '%s %s at %s' % (transit_type_name,
                                         transit_name,
                                         beg_sta_name or fin_sta_name,)
      elif isinstance(edge.payload, TripAlight):
         # TripAlight only needs station name and route name
         rs.step_name = '%s %s at %s' % (transit_type_name,
                                         transit_name,
                                         fin_sta_name or beg_sta_name,)
      elif isinstance(edge.payload, Crossing):
         # Crossing only needs route name
         rs.step_name = '%s %s' % (transit_type_name, transit_name,)

         # If Crossing, get straightline geometry from start to end station.
         if (beg_sta_node is not None) and (fin_sta_node is not None):
            sql_beg_pt_wkt = self.get_xy_wkt_from_station_node(beg_sta_node)
            sql_fin_pt_wkt = self.get_xy_wkt_from_station_node(fin_sta_node)
            rs.geometry_svg = self.get_straightline_geom(sql_beg_pt_wkt,
                                                         sql_fin_pt_wkt)
         else:
            # Crossing should have PSV endpoints, but not always...
            log.warning('...step_transit: messed up Crossing?: %s / %s / %s'
                        % (edge, beg_sta_node, fin_sta_node,))
      else:
         log.warning('EXPLAIN: Why no geometry for this transit step?')
         rs.geometry_svg = None

      return rs

   # ***

# FIXME: This works for now, but it needs cleaning up
   #
   def transit_get_station_vertex(self, psv_label, is_outgoing):
      '''Search for a station vertex (i.e. its label starts with sta-)
         so that we can use its id to look up stop information.  PSV vertices
         do not contain the stop id unfortunately, so we can't use them.

         NOTE: It appears that some stops cannot be found when using certain
         values for is_outgoing, so if one value doesn't work, the other
         should be used as a fallback.'''
      if is_outgoing:
         edges = self.gserver.get_vertex(psv_label).outgoing
      else:
         edges = self.gserver.get_vertex(psv_label).incoming
      for edge in edges:
         if (isinstance(edge.payload, TripAlight)):
            # This is the last route step when routing to a transit stop as the
            # final destination.
            g.assurt(is_outgoing)
            return edge.to_v
         elif (isinstance(edge.payload, TripBoard)):
            # If you route from a transit stop, look at incoming edges... I
            # guess.
            g.assurt(not is_outgoing)
            return edge.from_v
         # else, it's a Crossing; if there's a next edge in the list, it's an
         #                        Alight or Board edge.
      return None

   # *** Static Support Routines

# FIXME: BUG 2291: This fcn. does not respek daylight savings time
# FIXME: If date outside (before or after) GTFSDB calendar, warn user
   #
   @staticmethod
   def date_flashclient_mktime(date_str):
      log.debug('date_flashclient_mktime: date_str (1): %s' % (date_str,))
      # If daylight savings, remove Mpls' GMT
      if (date_str.find('GMT-0500') != -1):
         date_str = date_str.replace('GMT-0500', '')
         log.debug('date_flashclient_mktime: Stripped GMT-0500')
      elif (date_str.find('GMT-0600') != -1):
         # If winter, remove Mpls' non-CDT GMT
         date_str = date_str.replace('GMT-0600', '')
         log.debug('date_flashclient_mktime: Stripped GMT-0600')
      else:
         g.assurt(False)
      log.debug('date_flashclient_mktime: date_str: %s' % (date_str,))
      secs_since_epoch = time.mktime(time.strptime(date_str,
                                                   '%a %b %d %H:%M:%S %Y'))
      log.debug('date_flashclient_mktime: secs_since_epoch: %s'
                % (secs_since_epoch,))
      return secs_since_epoch

   # *** SQL Support Routines

   #
   def get_xy_wkt_from_network_node(self, node_endpoint):
      node_id = node_endpoint.label
      ndpt = node_endpoint.Many.node_endpoint_get(self.qb, node_id, pt_xy=None)
      g.assurt(ndpt is not None)
      try:
         if ndpt.endpoint_wkt:
            geom = ndpt.endpoint_wkt
         else:
            g.assurt(False) # 2012.08.02: Deprecated. See ndpt.endpoint_wkt.
            # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
            point_sql = geometry.xy_to_raw_point_lossless(ndpt.endpoint_xy)
            sql_points = self.qb.db.sql("SELECT %s" % (point_sql,))
            log.debug('get_xy_wkt_from_network_node: rows: %s'
                      % (sql_points,))
            geom = sql_points[0]['st_asewkt']
      except IndexError:
         log.warning(
            'get_xy_wkt_from_network_node: missing geom: node_endpoint: %s'
            % (node_endpoint, node_id,))
         # I'm [lb's] not sure how best to propagate this error, so let's
         # just assume it'll never happen, cool beans?
         g.assurt(False)
         geom = None
      return geom

   #
   def get_straightline_geom(self, beg_pt_wkt, fin_pt_wkt):
      rows = self.qb.db.sql(
         """
         SELECT
            ST_AsSVG(ST_Scale(ST_MakeLine(('%s'), ('%s')), 1, -1, 1), 0, %d)
               AS geometry
         """ % (beg_pt_wkt, fin_pt_wkt, conf.db_fetch_precision,))
      return rows[0]['geometry']

   #
   # MAYBE: Rename from_ and to_ to beg_ and fin_.
   def get_straightline_geom_len_sql(self, beg_xy, fin_xy):
      # FIXME: Why not use wkt_point_to_xy, et al.?
      # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
      point_lhs = geometry.xy_to_raw_point_lossless(beg_xy)
      point_rhs = geometry.xy_to_raw_point_lossless(fin_xy)
      rows = self.qb.db.sql(
         "SELECT ST_Length(ST_MakeLine(ST_AsEWKT(%s), ST_AsEWKT(%s)))"
         % (point_lhs, point_rhs,))
      return rows[0]['st_length']

   #
   def get_straightline_geom_len_raw(self, beg_xy, fin_xy):
      return geometry.distance(beg_xy, fin_xy)

   # TRANSITDB

   #
   def get_stop_xy(self, station_node):
      cursor = self.db_gtfs.conn.cursor()
      station_id = station_node.label[4:]
      cursor.execute(
         "SELECT stop_lat, stop_lon FROM stops WHERE stop_id = %s"
         % (station_id,))
      row = cursor.fetchone()
      return row

   #
   def get_stop_map_xy(self, station_node):
      stop_xy = self.get_stop_xy(station_node)
      log.debug('get_stop_map_xy: stop_xy: %s' % (stop_xy,))
      # Convert to map coordinates.
      # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
      point_sql = geometry.xy_to_raw_point_lossless((stop_xy[1], stop_xy[0],),
                                                    srid=conf.srid_latlon)
      rows = self.qb.db.sql(
         """
         SELECT
            ST_X(ST_Transform(%s, %d))
               AS xcoord,
            ST_Y(ST_Transform(%s, %d))
               AS ycoord
         """ % (point_sql, conf.default_srid,
                point_sql, conf.default_srid,))
      log.debug('get_stop_map_xy: %s' % (rows[0],))
      return [rows[0]['xcoord'], rows[0]['ycoord']]

   #
   def get_xy_wkt_from_station_node(self, station_node):
      stop_xy = self.get_stop_xy(station_node)
      # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
      point_sql = geometry.xy_to_raw_point_lossless((stop_xy[1], stop_xy[0],),
                                                    srid=conf.srid_latlon)
      rows = self.qb.db.sql("SELECT ST_AsEWKT(ST_Transform(%s, %d))"
                            % (point_sql, conf.default_srid,))
      log.debug('get_xy_wkt_from_station_node: rows: %s' % (rows,))
      return rows[0]['st_asewkt']

   #
   def get_stop_name(self, station_node):
      cursor = self.db_gtfs.conn.cursor()
      station_id = station_node.label[4:]
      cursor.execute(
         "SELECT stop_name FROM stops WHERE stop_id = %s"
         % (station_id,))
      row = cursor.fetchone()
      # EXPLAIN: When is the value not a string?
      stop_name = str(row[0])
      return stop_name
   #
   def get_transit_route_name(self, psv_node):

      # Fetch route_short_name from the transit database.

      cursor = self.db_gtfs.conn.cursor()

      cursor.execute(
         "SELECT route_id FROM trips WHERE trip_id = '%s'"
         % (psv_node.state.trip_id,))
      row = cursor.fetchone()
      rte_id = row[0]

      # NOTE: This is a transit route, not a Cyclopath route.
      cursor.execute(
         "SELECT route_short_name FROM routes WHERE route_id = '%s'"
         % (rte_id,))
      row = cursor.fetchone()
      # EXPLAIN: When is the value not a string?
      route_name = str(row[0])

      return route_name

   # ***

# *** Unit tests

def unit_test_01():
   dateStr = "Fri Mar 25 03:30:00 GMT-0500 2011"
   Problem.date_flashclient_mktime(dateStr)

if (__name__ == '__main__'):
   unit_test_01()


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import copy
import math
import networkx
import os
import sys
import time
import traceback

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item.feat import route_step
from item.feat import route_stop
from planner.problem_base import Problem_Base
from planner.travel_mode import Travel_Mode
from util_ import geometry
from util_ import gml
from util_ import misc

log = g.log.getLogger('rte_findr_p3')

# DEVS: Look in planner_tester.sh for easy-to-use copy-n-paste test commands.

# ***

# NOTE: pyserver/planner/routed_p1/route_finder
#                    and routed_p2/route_finder
#                    and routed_p3/route_finder
#       share a similarly identical interface (like the name
#       of the class, Problem, and the function, solve()) but
#       they don't share a common base class nor accept the
#       same __init__ args.
class Problem(Problem_Base):

   __slots__ = (
      'req', 
      'tgraph',
      'route',
      'rating_func',
      )

   def __init__(self, req, tgraph, route):
      Problem_Base.__init__(self)
      self.req = req
      self.tgraph = tgraph
      self.route = route

      if not self.route.p3_weight_type:
         # Default to basic shortest length search.
         self.route.p3_weight_type = 'len'

      if self.route.p3_weight_type not in tgraph.weight_types:
         log.error('Unknown edge weight type specified: route: %s'
                   % (route,))
         raise GWIS_Error('%s: %s. Hint: try one of: %s'
            % ('Unknown edge weight type specified',
               self.route.p3_weight_type,
               ', '.join(tgraph.weight_types),))

      if self.route.p3_weight_type not in tgraph.weights_enabled:
         log.error('Disabled edge weight type specified: route: %s'
                   % (route,))
         raise GWIS_Error('%s: %s. Hint: try one of: %s'
            % ('Disabled edge weight type specified',
               self.route.p3_weight_type,
               ', '.join(tgraph.weights_enabled),))

      if ((self.route.p3_rating_pump)
          and (self.route.p3_rating_pump not in tgraph.rating_pows)):
         log.error('Unknown Bikeability rating spread: route: %s'
                   % (route,))
         raise GWIS_Error('%s: %s. Hint: try a rating spread of: %s'
            % ('Unknown Bikeability rating spread',
               self.route.p3_rating_pump,
               ', '.join([str(x) for x in tgraph.rating_pows]),))

      if ((self.route.p3_burden_pump)
          and (self.route.p3_burden_pump not in tgraph.burden_vals)):
         log.error('Unknown travel-to-facility burden: route: %s'
                   % (route,))
         raise GWIS_Error('%s: %s. Hint: try a facility burden of: %s'
            % ('Unknown travel-to-facility burden',
               self.route.p3_burden_pump,
               ', '.join([str(x) for x in tgraph.burden_vals]),))

      if not self.route.p3_spalgorithm:
         # Default to astar search.
         self.route.p3_spalgorithm = 'as*'
      if self.route.p3_spalgorithm not in tgraph.algorithms:
         log.error('Unknown shortest paths algorithm specified: route: %s'
                   % (route,))
         raise GWIS_Error('%s: %s. Hint: try one of: %s'
            % ('Unknown shortest paths algorithm specified',
               self.route.p3_spalgorithm,
               ', '.join(tgraph.algorithms),))

   #
   def __str__(self):
      selfie = (
         'route_finder: rq: %s / beg: %s: %d / fin: %s: %d / %s / p3: %s/%s/%s'
         % (self.req,
            #self.tgraph,
            self.route.beg_addr,
            self.route.beg_nid,
            self.route.fin_addr,
            self.route.fin_nid,
            Travel_Mode.get_travel_mode_name(self.route.travel_mode),
            self.route.p3_weight_type,
            self.route.p3_rating_pump,
            self.route.p3_burden_pump,
            self.route.p3_spalgorithm,))
      return selfie

   # ***

   #
   def solve(self, qb):
      """
      Return list of byway stack IDs satisfying route request.
      """
      try:
         (rsteps, rstops, path_cost, path_len,) = self.solve_problem(qb)
      except networkx.NetworkXNoPath, e:
         log.error('cannot solve: NetworkXNoPath: %s / route: %s'
                   % (str(e), self.route))
         # BUG nnnn/2014.09.17: Fix connectivity. This route only works in
         # one direction:
         #  Sep-16 18:41:10 ERRR rte_findr_p3 # cannot solve: NetworkXNoPath:
         #   Node 2786225 not reachable from 1298046 / route: "Untitled" [r...]
         #   { beg: "Naples Circle NE @ Petersburg St, Blaine" }
         #   { end: "Sandburg Rd @ Douglas Drive, Golden Valley" }
         # except I fixed the problem by fixing the connectivity between a
         # neighborhood street and the two oneway couplets and bike trail
         # (at S Lake Blvd NE and 117th La NE).
         # (Just be patient: it takes ten minutes for routed to update
         #  its graphs.)
         #
         # DEV: If you see this error in logcheck, sometimes you can fix
         #      the problem by fixing connectivity in the road network.
         #      Look for streets that might just connect to a oneway and
         #      end up blocking a whole section of roads from the other
         #      direction.
         error_msg_complicated = (
            "Our apologies, but we were unable to find a route for you!\n\n"
            + "This is our fault and we will try to fix the problem soon.\n\n"
            + "You can also try swapping the from and the to addresses, "
            + "to see if maybe one-way roads are causing the problem.\n\n"
            + "And feel free to email us at %s. "
              % (conf.mail_from_addr,)
            + "Sorry for the inconvenience!\n\n")
         #raise GWIS_Error(Problem_Base.error_msg_basic)
         raise GWIS_Error(error_msg_complicated)
      except KeyError, e:
         log.error('cannot solve: endpoint missing from graph: %s / route: %s'
                   % (str(e), self.route,))
         # BUG nnnn: Endpoint not in graph problem.
         # 2014.09.17: This is weird: endpoint missing from graph but the roads
         # using that endpoint haven't been edited recently (I thought maybe it
         # was a problem with routed updating after a revision commit). E.g.,
         # Sep-16 18:28:56 WARN  ratings # Byway ID 1055861 not found in graph!
         # Sep-16 18:28:56 WARN  ratings # Byway ID 1035280 not found in graph!
         # Sep-16 18:28:57 ERRR rte_findr_p3 # cannot solve: endpoint missing
         #  from graph: 1303666 / route: "Untitled" [route:X(Nonec)...]
         #  (78 10th St E, St Paul)
         # Sep-16 18:28:57 WARN  ratings # Byway ID 1484642 not found in graph!
         # but when [lb] started up a test route daemon, that node is in the
         # graph. So I'm not sure what's up. Happened just once so far, though.
         error_msg_complicated = (
            "Our apologies, but we were unable to find a route for you!\n\n"
            + "One of the destinations we found is not part of our "
            + "route finder's road network.\n\n"
            + "This is our fault and we will try to fix the problem soon.\n\n"
            + "In the meantime, please try a different from or to address.\n\n"
            + "You can also email us at %s. "
              % (conf.mail_from_addr,)
            + "Sorry for the inconvenience!\n\n")
         # MAYBE: Show this if you know for sure --regions is used:
         #   + "Solution: Try using destinations within '%s'.\n\n"
         #     % (self.tgraph.route_daemon.cli_opts.regions,)
         #raise GWIS_Error(Problem_Base.error_msg_basic)
         raise GWIS_Error(error_msg_complicated)
      except Exception, e:
         log.error('cannot solve: unknown problem: %s / route: %s'
                   % (str(e), self.route,))
         stack_trace = traceback.format_exc()
         log.warning('Warning: Unexpected exception: %s' % (stack_trace,))
         raise GWIS_Error(Problem_Base.error_msg_basic)
      return (rsteps, rstops, path_cost, path_len,)

   #
   def solve_problem(self, qb):

      wgt_attr = self.resolve_weight_attr(qb)

      solution = self.execute_problem_solver(qb, wgt_attr)

      results = self.stepify_walk_path(qb, solution, wgt_attr)

      return results

   #
   def resolve_weight_attr(self, qb):

      weight_type = self.route.p3_weight_type

      # This class normally ignores the p1_bike_priority, unless an old
      # client is still contacting us, in which case we need to translate
      # the p1 bike priority value to the p3 rating spread, and then we
      # give a fast, static route and not a personalized route.
      if self.route.travel_mode == Travel_Mode.bicycle:
         # This is android. Flashclient sends wayward only to p3 (classic to
         # p1 finder; but bicycle can be processed by either p1 or p3.)
         # BUG nnnn: Update android to use p3 planner...
         # Because of how route_get parses attributes, these should not be set.
         g.assurt((not weight_type) or (weight_type == 'len'))
         g.assurt(not self.route.p3_rating_pump)
         # Note that we're not giving a personalized route:
         weight_type = 'rat'
         if not self.route.p1_priority:
            log.debug('solve_prob: simplifying tm.bicycle to length wgt')
            weight_type = 'len'
         else:
            # Map the 0.0 to 1.0 slider to a comparable rating power.
            # HACK/SYNC_ME: We use our insider knowledge of rating_pows
            # to just hardcode the conversion. The old priority slider
            # ranges from 0 to 1 using tick marks spaced 0.125 apart,
            # for 9 positions. In p3, it's 5 positions mapped 2 to 32.
            if self.route.p1_priority <= 0.125:
               self.route.p3_rating_pump = 2
            elif self.route.p1_priority <= 0.375:
               self.route.p3_rating_pump = 4
            elif self.route.p1_priority <= 0.625:
               self.route.p3_rating_pump = 8
            elif self.route.p1_priority <= 0.875:
               self.route.p3_rating_pump = 16
            else:
               self.route.p3_rating_pump = 32

      # The personalized fcn. need more preprocessing that the static weights.
      if weight_type in set(['prat', 'pfac', 'prac',]):

         # The personalized finder uses whatever options we leave nonzero, so
         # make sure to zero out whatever's set but that we don't want to use.
         if weight_type == 'prat':
            self.route.p3_burden_pump = 0
         elif weight_type == 'pfac':
            self.route.p3_rating_pump = 0

         # If no tagprefs, we might be able to use a static weight instead.
         if not self.route.tagprefs:
            if self.req.client.username == conf.anonymous_username:
               # There's nothing to personalize w/out user or tagprefs.
               log.debug('resolve_weight_attr: no need to personalize: %s / %s'
                         % (weight_type, self.route,))
               if weight_type == 'prat':
                  weight_type = 'rat'
               elif weight_type == 'pfac':
                  weight_type = 'fac'
               else:
                  g.assurt(weight_type == 'prac')
                  weight_type = 'rac'
            elif (weight_type == 'prat') and (not self.route.p3_rating_pump):
               log.warning('resolve_weight_attr: no prat: using length wgt')
               weight_type = 'len'
            elif (weight_type == 'pfac') and (not self.route.p3_burden_pump):
               log.warning('resolve_weight_attr: no pfac: using length wgt')
               weight_type = 'len'
            elif ((weight_type == 'prac')
                  and (not self.route.p3_rating_pump)
                  and (not self.route.p3_burden_pump)):
               log.warning('resolve_weight_attr: no prac: using length wgt')
               weight_type = 'len'

      if (weight_type == 'rat') and (not self.route.p3_rating_pump):
         log.warning('resolve_weight_attr: no rat: using length wgt')
         weight_type = 'len'
      elif (weight_type == 'fac') and (not self.route.p3_burden_pump):
         log.warning('resolve_weight_attr: no fac: using length wgt')
         weight_type = 'len'
      elif weight_type == 'rac':
         if not self.route.p3_rating_pump:
            # Rating spread not specied, so just use facility willingness.
            if not self.route.p3_burden_pump:
               log.warning(
                  'resolve_weight_attr: no spread for "rac": default "len"')
               weight_type = 'len'
            else:
               weight_type = 'fac'
         elif not self.route.p3_burden_pump:
            # The opposite.
            weight_type = 'rat'

      edge_weight_attr = None

      if weight_type in set(['prat', 'pfac', 'prac',]):
         # Personalized routing, just like mom used to bake.
         self.rating_func = self.tgraph.ratings.rating_func(
            self.req.client.username, self.route.tagprefs, self.tgraph)
         # This name is writ to route_parameters.p3_weight_attr.
         edge_weight_attr = 'wgt_pers_f'
         # [lb] hacked network's astar algorithm to support
         # payloads and runtime edge weights. But not t'others.
         if self.route.p3_spalgorithm != 'as*':
            raise GWIS_Error('%s: %s. Hint: try one of: "as*"'
               % ('Incompatible graph search algorithm specified',
                  self.route.p3_spalgorithm,))

      if not edge_weight_attr:
         if weight_type == 'len':
            edge_weight_attr = 'wgt_len'
         elif weight_type == 'rat':
            edge_weight_attr = 'wgt_rat_%d' % (self.route.p3_rating_pump,)
         elif weight_type == 'fac':
            edge_weight_attr = 'wgt_fac_%d' % (self.route.p3_burden_pump,)
         elif weight_type == 'rac':
            edge_weight_attr = ('wgt_rat_%d_fac_%d'
                                % (self.route.p3_rating_pump,
                                   self.route.p3_burden_pump,))
         else:
            g.assurt(False) # Unreachable.

      # EXPLAIN: Does this value get saved to the route table?
      #          This is the only place it's set in code.
      self.route.p3_weight_attr = edge_weight_attr

      return edge_weight_attr

   #
   def execute_problem_solver(self, qb, edge_weight_attr):

      walk_path = None

      log.debug(
         'exec_prob_slvr: wattr: %s / rat sprd: %s / fac brdn: %s / spalg: %s'
         % (edge_weight_attr,
            self.route.p3_rating_pump,
            self.route.p3_burden_pump,
            self.route.p3_spalgorithm,))

      # ***

      if self.route.p3_spalgorithm == 'as*':

         time_0 = time.time()

         # Calculate path using A* search.
         # MAYBE: We don't need a heuristic, do we??
         #        Would it speed up the search?
         #        The h fcn. would just be the dist from the curnode to the
         #        finish? Or does [lb] still not know how graph search works...
         ast_path = networkx.astar_path(
            self.tgraph.graph_di, self.route.beg_nid, self.route.fin_nid,
            # MAYBE: Send pload... networkx hack
            #heuristic=None, weight=edge_weight_attr)
            heuristic=None, weight=edge_weight_attr, pload=self)

         log.debug('exec_prob_slvr: astar_path: no. edges: %d / in %s'
                   % (len(ast_path),
                      misc.time_format_elapsed(time_0),))

         walk_path = ast_path

      # ***

      elif self.route.p3_spalgorithm == 'asp':

         time_0 = time.time()

         # MAYBE: Hack networkx and add pload param to support edge wght fcns.
         all_paths = networkx.all_shortest_paths(
            self.tgraph.graph_di, self.route.beg_nid, self.route.fin_nid,
            weight=edge_weight_attr)

         log.debug(
            'exec_prob_slvr: all_shortest_paths: returned generator in %s'
            % (misc.time_format_elapsed(time_0),))

         time_0 = time.time()

         path_num = 1
         for a_path in all_paths:

            log.debug('solve_pb: all_shortest_paths: path #%d: len: %d / in %s'
                      % (path_num, len(a_path),
                         misc.time_format_elapsed(time_0),))
            path_num += 1
            time_0 = time.time()

            if walk_path is None:
               walk_path = a_path
               #break

            # FIXME/EXPLAIN: Find an O/D pair that results in multiple paths...
            # or would the cost have to be equal? That doesn't sound very
            # likey -- in practicality, all_shortest_paths would probably
            # always just return one result for Cyclopath.

      # ***

      elif self.route.p3_spalgorithm == 'dij':

         time_0 = time.time()

         # Calculate path using Dijkstra's algorithm.
         # MAYBE: Hack networkx and add pload param to support edge wght fcns.
         dij_path = networkx.dijkstra_path(
            self.tgraph.graph_di, self.route.beg_nid, self.route.fin_nid,
            weight=edge_weight_attr)

         log.debug('exec_prob_slvr: dijkstra_path: no. edges: %d / in %s'
                   % (len(dij_path),
                      misc.time_format_elapsed(time_0),))

         walk_path = dij_path

      # ***

      elif self.route.p3_spalgorithm == 'sho':

         time_0 = time.time()

         # Calculate path using generic NetworkX shortest path search.
         # MAYBE: Hack networkx and add pload param to support edge wght fcns.
         asp_path = networkx.shortest_path(
            self.tgraph.graph_di, self.route.beg_nid, self.route.fin_nid,
            weight=edge_weight_attr)

         log.debug('exec_prob_slvr: shortest_path: no. edges: %d / in %s'
                   % (len(asp_path),
                      misc.time_format_elapsed(time_0),))

         walk_path = asp_path

      # ***

      elif self.route.p3_spalgorithm == 'ssd':

         time_0 = time.time()

         # This Dijkstra fcn. "returns a tuple of two dictionaries
         # keyed by node. The first dictionary stores distance from
         # the source. The second stores the path from the source to
         # that node."
         # So... this isn't an ideal fcn. to use, since the second
         # dictionary contains paths for every pair of nodes.
         # MAYBE: Hack networkx and add pload param to support edge wght fcns.
         dij_distance2, dij_path2 = networkx.single_source_dijkstra(
            self.tgraph.graph_di, self.route.beg_nid, self.route.fin_nid,
            weight=edge_weight_attr)

         log.debug(
            'exec_prob_slvr: single_source_dijkstra: no. edges: %d / in %s'
            % (len(dij_path2),
               misc.time_format_elapsed(time_0),))

         walk_path = dij_path2[self.route.fin_nid]

      # ***

      else:

         # This code should be unreachable, as we would've raised by now.
         g.assurt(False)

      # ***

      if not walk_path:
         # NOTE: This code is probably unreachable. With the new
         #       is_disconnected attribute, there should no longer
         #       be a possibility that we won't find a route, since
         #       we guarantee that the origin and destination are
         #       on nodes that are well-connected.
         log.error('exec_prob_slvr: no route?: %s' % (self,))
         raise GWIS_Error(Problem_Base.error_msg_basic)

      # ***

      return walk_path

   #
   def stepify_walk_path(self, qb, walk_path, edge_weight_attr):

      time_0 = time.time()

      path_cost = 0.0
      path_len = 0.0
      last_node = None
      rsteps = route_step.Many()
      for curr_node in walk_path:
         if last_node is not None:
            rstep_wrapper = self.tgraph.graph_di[last_node][curr_node]['rstep']
            rt_step = copy.copy(rstep_wrapper.rstep)
            g.assurt(rt_step.byway_stack_id > 0)
            rt_step.forward = rstep_wrapper.forward
            rt_step.dir_entry = rstep_wrapper.dir_entry
            rt_step.dir_exit = rstep_wrapper.dir_exit
            if rt_step.forward:
               lhs_nid = rt_step.beg_node_id
               rhs_nid = rt_step.fin_node_id
            else:
               lhs_nid = rt_step.fin_node_id
               rhs_nid = rt_step.beg_node_id
            try:
               network_edge = self.tgraph.graph_di[lhs_nid][rhs_nid]
               rt_step.edge_weight = network_edge[edge_weight_attr]
               # Assume an int so the exception cost is on personalized.
               try:
                  path_cost += rt_step.edge_weight
               except TypeError:
                  rt_step.edge_weight = rt_step.edge_weight(network_edge, self)
                  path_cost += rt_step.edge_weight
            except KeyError, e:
               log.warning(
                  'stepify_walk_path: edge not found: attr: "%s" / %s -> %s'
                  % (edge_weight_attr, lhs_nid, rhs_nid,))
               rt_step.edge_weight = sys.maxint / 100000000.0 # 92233720368.547
               path_cost = float('inf')
            path_len += rt_step.edge_length
            rsteps.append(rt_step)
         # end: if last_node is not None
         last_node = curr_node
      # end: for curr_node in walk_path

      log.debug('stepify_walk_path: assembled: no. rsteps: %d / in %s'
                % (len(rsteps),
                   misc.time_format_elapsed(time_0),))

      #log.debug('goal test count: %d' % (self.goal_test_ct,))

      rstops = route_stop.Many()
      rstops.append(
         route_stop.One(
            qb=None,
            row={'name': self.route.beg_addr,
                 'is_pass_through': False,}))
      rstops.append(
         route_stop.One(
            qb=None,
            row={'name': self.route.fin_addr,
                 'is_pass_through': False,}))
      rstops[0].fit_route_step(rsteps[0], True)
      rstops[1].fit_route_step(rsteps[-1], False)

      log.debug('stepify_walk_path: rstops %s %s'
                % (rstops[0].name, rstops[1].name,))

      return (rsteps, rstops, path_cost, path_len,)

   # ***

# ***


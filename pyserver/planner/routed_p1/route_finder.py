# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import copy
import math
import os
import sys

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item.feat import route_step
from item.feat import route_stop
from planner.problem_base import Problem_Base
from util_ import geometry
from util_ import gml
from util_.norvig import search

log = g.log.getLogger('route_finder')

# ***

class Action(object):

   def __init__(self):
      pass

   #
   def cost(self):
      __abstract__

# ***

class Action_Null(Action):

   def __init__(self):
      pass

   #
   def cost(self):
      return 0

# ***

class Action_Node_Trav(Action):

   __slots__ = (
      'beg_rt_step',
      'fin_rt_step',
      )

   def __init__(self, beg_rt_step, fin_rt_step):
      self.beg_rt_step = beg_rt_step
      self.fin_rt_step = fin_rt_step

   #
   def cost(self):
      a = geometry.rotation_ccw(self.beg_rt_step.dir_exit,
                                self.fin_rt_step.dir_entry)
      if (a > math.pi/8):
         return conf.routing_penalty_left
      elif (a > -math.pi/8):
         return conf.routing_penalty_straight
      else:
         g.assurt(a >= -math.pi)
         return conf.routing_penalty_right

   # ***

# ***

class State(object):

   '''WARNING: States _must_ implement a __hash__() method in order for them
      to work properly as members of sets.'''

   __slots__ = ('node_id')

   #
   def cost(self, priorities, rating_func):
      '''Return the cost of traversing this state.'''
      # FIXME: Replace all "g.assurt(False) # abstract" with this?:
      __abstract__

   #
   def successors(self, edges, rating_func, rating_min):
      'Return a list of (action, successor) pairs.'
      __abstract__

   #
   def node_successors(self, edges, rating_func, rating_min, node_id):
      'Return a list of route_step.One()s reachable from node node_id.'
      # FIXME: speed this up with list comprehensions?
      sucs = list()
      for eid in edges[node_id]:
         for bid in edges[node_id][eid]:
            # This is what omits impassable byways (ratings.t_avoid)
            if (rating_func(bid) >= rating_min):
               sucs.append(edges[node_id][eid][bid])
      return sucs

   # ***

# ***

class State_Start_End(State):

   'The state of being "at" the start or end node of a graph traversal.'

   def __init__(self, node_id):
      self.node_id = node_id

   #
   def __eq__(self, other):
      return (isinstance(other, State_Start_End)
              and self.node_id == other.node_id)

   #
   def __ne__(self, other):
      return not self.__eq__(other)

   #
   def __hash__(self):
      # This is also unique against State_Byway instances because the nodes
      # are numbered from the same sequence as byways.
      return self.node_id

   #
   def __str__(self):
      return 'at %d' % (self.node_id)

   #
   def cost(self, priorites, rating_func):
      return 0

   #
   def successors(self, edges, rating_func, rating_min):
      sucs = [(Action_Null(), State_Byway(rs))
              for rs in self.node_successors(edges, rating_func, rating_min,
                                             self.node_id)]
      return sucs

   # ***

# ***

class State_Byway(State):

   'The state of having traversed a byway.'

   __slots__ = ('route_step')

   def __init__(self, rt_step):
      self.route_step = rt_step
      if (self.route_step.forward):
         self.node_id = self.route_step.fin_node_id
      else:
         self.node_id = self.route_step.beg_node_id

   #
   def __eq__(self, other):
      return (isinstance(other, State_Byway)
              and self.route_step == other.route_step)

   #
   def __ne__(self, other):
      return not self.__eq__(other)

   #
   def __hash__(self):
      return self.route_step.__hash__()

   # FIXME: Who uses this? a repr is supposed to return an executable Python
   #        string that could be used to recreated this object.
   def __repr__(self):
      return self.__str__()

   #
   def __str__(self):
      return ':: ' + str(self.route_step)

   #
   def cost(self, priorities, rating_func):
      # FIXME: [ml] This cost is a weighted sum of priorities, but the
      # cost_dist function has significantly larger values compared to the
      # others, which are on an ~5 point scale.
      # - Are priorities balanced to compensate this?
      # - If not, is it okay that distance plays a much larger role?
      c = 0.0
      # NOTE: func_name is one of 'dist' and 'bike'.
      for func_name in priorities:
         try:
            # Don't calculate the cost unless the cost counts.
            if priorities[func_name]:
               c += (priorities[func_name]
                     * cost_funcs[func_name](self.route_step, rating_func))
         except TypeError:
            g.assurt(False)
      return c

   #
   def successors(self, edges, rating_func, rating_min):
      sucs = [(Action_Node_Trav(self.route_step, rs),
               State_Byway(rs))
              for rs in self.node_successors(edges, rating_func, rating_min,
                                             self.node_id)
              if rs.byway_stack_id != self.route_step.byway_stack_id]
      return sucs

   # ***

# ***

# NOTE: pyserver/planner/routed_p1/route_finder and routed_p2/route_finder
#       share a similarly identical interface (like def solve()) but don't
#       share the same intermediate base class because of norvig.
# NOTE: This class derives from util_.norvig.search, not Cyclopath's search.
class Problem(search.Problem):
   '''Formal problem for transportation network route-finding problem.

   Documentation (good): <http://aima.cs.berkeley.edu/python/search.html>'''

   __slots__ = (
      'req', 
      'edges',
      'node_xys',
      'beg_addr',
      'fin_addr',
      'rating_func',
      'rating_min',
      'priorities',
      'ideal',
      'goal_test_ct',
      )

   def __init__(self, req,
                      graph,
                      rt,
                      beg_vertex_id, # Huh. beg_node_id
                      fin_vertex_id, # Funny name for fin_node_id
                      rating_func,
                      rating_min):
      search.Problem.__init__(self, 
                              State_Start_End(beg_vertex_id),
                              State_Start_End(fin_vertex_id))
      self.req = req # FIXME: Use to check branch, rev, and username?
      self.edges = graph.edges
      self.node_xys = graph.node_xys
      self.beg_addr = rt.beg_addr
      self.fin_addr = rt.fin_addr
      self.rating_func = rating_func
      self.rating_min = rating_min
      self.priorities = {}
      self.priorities['bike'] = rt.p1_priority
      self.priorities['dist'] = 1.0 - rt.p1_priority
      # The ideal route step, all of whose attributes are the best possible.
      # This is used in the heuristic estimation of remaining cost.
      self.ideal = State_Byway(route_step.One())
      self.goal_test_ct = 0

   # 
   def goal_test(self, state):
      self.goal_test_ct += 1
      return (self.goal.node_id == state.node_id)

   # 
   def h(self, pnode):
      '''Return the heuristic cost of traveling from Node pnode to the goal.'''

      try:
         d = geometry.distance(self.node_xys[pnode.state.node_id],
                               self.node_xys[self.goal.node_id])
      except KeyError, e:
         log.error('h: KeyError: %s' % (str(e),))
         #g.assurt(False)
         # BUG nnnn: Find a nearby node, instead.
         # Ug, this error message I [lb] just wrote is terrible... but it's
         # better than an assert, which has an even worse error message, but
         # for different reasons (because the latter suggests that the server
         # crashed; at least this error message tries to explain what's up).
         # NOTE: It could be that routed update failed; we don't actually
         #       check that it's updating (we just assume, since the key
         #       was found in the database but unknown to the finder).
         #raise GWIS_Error('%s%s'
         #  % ('Our apologies! Please wait to route using this destination: ',
         #     'the route finder is updating itself since the last map save',))
         raise GWIS_Error(Problem_Base.error_msg_basic)

      self.ideal.route_step.edge_length = d
      return self.ideal.cost(self.priorities, lambda rs: 5)

   # 
   def path_cost(self, c, state1, action, state2):
      return (c + action.cost() + state2.cost(self.priorities,
                                              self.rating_func))

   #
   # NOTE: qb is ignored here, but it's used by routed_p2.routed_finder's
   #       solve; we're just maintaining consistency sans base class
   #       commonality.
   def solve(self, qb):

      # Calculate path using A* search.
      node = search.astar_search(self)

      if node is None:

         # We return an error to the client, which is logged as an error to the
         # server log file. By default, logcheck will see the error and send an
         # email. We could filter these errors, but we don't get many of them.
         # And if we print the O/D requested, it will make the logcheck email
         # easier to decide if ignore/persue.
         log.warning('No route: beg_addr: %s' % (self.beg_addr,))
         log.warning('No route: fin_addr: %s' % (self.fin_addr,))

         # SYNC_ME: FIXME: This text is a copy of routed_p2.route_finder's.
         #raise GWIS_Error(
         #   'No route exists. Click "Help" for ideas on what to do next.')
         raise GWIS_Error(Problem_Base.error_msg_basic)

      path_cost = node.path_cost
      path_len = 0.0

      # Make a list of route_steps.
      # Old way: rsteps = list()
      rsteps = route_step.Many()
      walker = node
      while walker.parent is not None:
         rt_step = copy.copy(walker.state.route_step)
         state2 = State_Byway(rt_step)
         rt_step.edge_weight = (
            state2.cost(self.priorities, self.rating_func)
            * route_step.One.weight_multiplier)
         rsteps.insert(0, rt_step)
         path_len += rt_step.edge_length
         walker = walker.parent

      log.debug('goal test count: %d' % (self.goal_test_ct,))

      # Make a list of route_stops. Extract the xys from the path instead
      # of using the geocoded points so that each route_stop lines up on the
      # actual byway.
      #
      # FIXME: Above comment suggests change in behavior: pre-route sharing,
      # the origin or destination that the users specifies and that we geocode
      # shows up on the map as the geocoded point. E.g., if you search for
      # 5038 Dupont Ave S, Mpls, MN, you'll see a point in the middle of the
      # block. The above comment suggests that now route_stops are placed at
      # the nearest Cyclopath node_endpoint...
      #
      # Old way: rstops = list()
      rstops = route_stop.Many()
      rstops.append(
         route_stop.One(
            qb=None, row={'name': self.beg_addr, 'is_pass_through': False,}))
      rstops.append(
         route_stop.One(
            qb=None, row={'name': self.fin_addr, 'is_pass_through': False,}))
      rstops[0].fit_route_step(rsteps[0], True)
      rstops[1].fit_route_step(rsteps[-1], False)

      log.debug('rstops: 0: %s / 1: %s' % (rstops[0].name, rstops[1].name,))

      return (rsteps, rstops, path_cost, path_len,)

   # 
   def successor(self, state):
      return state.successors(self.edges, self.rating_func, self.rating_min)

   # ***

# ***

class Cost_Functions(object):

   def __init__(self):
      pass

   # The following functions calculate edge costs. If you add a new one, be
   # sure to update the lookup, cost_funcs.

   #
   @staticmethod
   def cost_dist(rs, rating_func):
      # FIXME: In CcpV2, might you get routed down freeways? We need rating to
      #        know if impassable, right?
      return rs.edge_length

   #
   @staticmethod
   def cost_bike(rs, rating_func):

      # 2014.04.11: [lb] always gets confused when he visits this fcn.,
      # so I did a little digging and maths to help explain it to myself.
      #
      # For some background, let's investigate the evolution of this fcn.
      #
      # Here's the origin fcn. and comment, from Release 1, 2008-05-06.
      #
      #  def cost_ratg(rs):
      #     # Ratings vary 0-4 where bigger is better, but cost is a _penalty_,
      #     # so normalize the rating to 0-1 where smaller is better.
      #
      #     # This is scaled roughly as follows: if rating and distance are
      #     # given equal weight, then traveling two miles on Excellent streets
      #     # is the same cost as one mile on Unrideable streets.
      #     return rs.edge_length * (1 - (rs.rating_generic / 4.0))
      # 
      # Between Release 1 and 29, two changes occurred: "Unrideable" was
      # changed to "Impassable", and the fcn. was renamed as cost_bike.
      #
      # At Release 29, the fcn. and comment evolved to the current state
      # that's been unchanged since -- well, the code has remaining unchanged
      # in CcpV2, but [lb] keeps reworking (this) comment.
      #
      # Here's the fcn. and comment in Release 29, 2009-04-30:
      #
      #  def cost_bike(rs, rating_func):
      #     # Ratings vary 0-5 where bigger is better, but cost is a _penalty_,
      #     # so normalize the rating to 0-3 where smaller is better.
      #     #
      #     # (Note: 4 is Excellent, so ratings >4 are only possible when a tag
      #     # bonus has been applied.)
      #     #
      #     # This is scaled roughly as follows: if cost_dist and cost_bike are
      #     # given equal priority, then traveling four miles on highly Bonused
      #     # streets is the same cost as one mile on Impassable streets.
      #     return 3 * rs.edge_length * (1 - (rating_func(rs.byway_id) / 5.0))
      #
      # You'll see a number of changes.
      # 1) The personalized rating fcn. was implemented, so now rating_func is
      #    used instead of the generic rating. This causes the rating scalar to
      #    increase, from 4 to 5: the best you can rate a road -- excellent --
      #    is value 4, but with tag preferences, the calculated rating now
      #    converges on 5.
      # 2) A new, constant scalar -- 3 -- was added to the cost.
      # 3) The comment about what the cost really means changed to
      #    "4 miles on highly bonused == 1 mile on impassable". Before, the
      #    comment read that "2 miles excellent == 1 mile unrideable".
      #
      # First, about the newer comment about relative cost, let's do the math.
      #  The rating of an impassable road is 0.
      #  The calculated rating of a highly bonsed road is 4 for the excellent
      #   generic rating + no. tag matches * 5.0. If we assume a whopping 4
      #   tag matches, the calculated rating is (4+4*5)/5 = 4.8.
      #  The cost of a 1 mile impassable road = 3 * 1.0 * (1 -   0/5) = 3.0
      #  The cost of 4 miles of the nice road = 3 * 4.0 * (1 - 4.8/5) = 0.48
      #  So the comment is wrong, since 3.0 != 0.48.
      #  If we take the cost of the 1 mile impassable road and solve for the
      #  length of the nice road at the same cost,
      #   3.0 = 3 * some_length * (1 - 4.8/5), we find that some_length = 25.
      #  Meaning, if the route finder has to choose btw. a 1 mile impassable
      #   road and 24 miles of highly bonused nice road, it'll choose the
      #   24 times longer bonused road.
      #
      #  More realistically, at least, the route finder will be choosing
      #   between roads with ratings more close to one another, e.g.,
      #   a fair (2) or good (3) vs. excellent (4). Here, we want the 
      #   excellent road to win, but not by so much that we produce a
      #   route that's ten times longer than the shortest route.
      #  Using the same CcpV1 algorithm, 3.0*1.0*(1.0-2.0/5.0) = 1.8 cost
      #   for 1 miles of fair-rated (2) road. Solving for excellent (4),
      #   1.8 = 3.0*some_length*(1.0-4.0/5.0), and some_length = 3 miles.
      #   So a route that's three times as long but nice is the same cost
      #   as a one mile fair route.
      #  Looking at good vs. excellent, 3.0*1.0*(1.0-3.0/5.0) = 1.2 cost
      #   for 1 mile of good-rated (3) road. Solving for excellent (4),
      #   1.2 = 3.0*some_length*(1.0-4.0/5.0), some_length = 2 miles,
      #   or a route that's excellent is the same cost as a route that's
      #   half as long but only rated good.
      #
      #  From the last example, you'll see that scaling between successive
      #  ratings isn't constant.
      #   E.g., 1 mile fair = 3 miles excellent, but in terms of good,
      #    1.8 = 3.0*some_length*(1.0-3.0/5.0), and some_length = 1.5 miles.
      #  These are the same cost: 1 mile fair, 1.5 miles good, 3 excellent.
      #  You'll see that a route of good has to less than 50% longer than
      #  a route of fair to be less cost, but a route of excellent can be
      #  up to 100% longer than a route of good to be less cost!
      #
      #  The reason for this is that we calculate a scalar from 0 to some
      #  number, but the successive steps are an arithmetic progression. So the
      #  difference between, e.g., 1 and 2 is 2/1 = 2, but the difference
      #  between 2 and 3 is 3/2. As the terms increase, the relative difference
      #  between successive terms _decreases_.
      #
      #  The problem this causes is that a +1 bump to a rating has a different
      #  effect depending on the initial value. E.g., changing a road from
      #  "fair" to "good" has less effect on the cost than changing a road
      #  from "good" to "excellent".
      #
      #  .. and buefore I get way too far ahead of myself (too late), I want
      #  to comment on the other two changes I noted. I think I've explained
      #  why the original comment about relative cost is wrong and how the
      #  arithmetic mapping produces uneven relative costs.
      #
      #  Regarding the cost being scaled by 3.0 starting in Release 29, this
      #  has no effect for an all-bike cost. I.e., the difference in cost
      #  when comparing 3 * rating1 vs 3 * rating2 is the same as comparing the
      #  cost of 10 * rating1 vs 10 * rating2. Another way to view this is
      #  that, consider the cost of a 1 mile excellent (4) rated road with
      #  no scaling: 1-4/5 = 1/5. Now consider a the same for a good-rated (3)
      #  road: 1-3/5 = 2/5. The good cost is x2 the excellent cost, and scaling
      #  both values won't change that, e.g., 3*1/5 vs. 3*2/5 is still a factor
      #  of 2.
      #
      #  So what's the 3.0 do? It affects the influence of the rating cost
      #  when splitting the cost between rating and distance.
      #
      #  Consider a 50-50 split without the scaling. The rating cost of
      #   1 mile of poor road is 1-1/5 = 4/5, and 1 miles of excellent road is
      #   1-4/5 = 1/5. Now, combining half the rating with half the distance,
      #   the poor road costs 1/2 + (1/2)*(4/5) = 9/10, and the excellent cost
      #   is 1/2 + (1/2)*(1/5) = 6/10. So 1 mile of poor has the same cost as
      #   1-1/2 miles of excellent.
      #  Now consider the same split but with scaling.
      #   The poor cost is 1/2 + (1/2)*3*(4/5) = 17/10, and the
      #   excellent cost is 1/2 + (1/2)*3*(1/5) = 8/10.
      #   This changes the cost ratio: a one mile poor road now has the same
      #   cost as a little over two miles of excellent road.
      #
      # Since our scale ranges from 0 to 5, after inverting the rating
      #  (diving rating by 5.0), I'm surprised the original code doesn't
      #  normalize back to 0 to 5. Instead, it normalizes to 0 to 3.
      # By using 3, it means a road that's rated 10/3 has the same
      #  distance cost as rating cost: 3*(1-(10/3)/5)=3*(1-2/3)=3*(1/3)=1.
      # Also by using 3, it means that when combining costs, the spectrum isn't
      #  weighted to much towards distance, i.e., if we didn't scale but kept
      #  the inverted rating value (of 0 to 1), then a 50-50 distance-rating
      #  cost split is more heavily weighted towards distance:
      #   1/2 * dist + 1/2 * dist * some_scalar_less_than_one = cost,
      #   and 1/2 * dist * some_scalar_less_than_one is always < 1/2 * dist,
      #   so the "50-50" priority split isn't really 50-50.
      #  By using a value of 3, it's saying that a 3-1/3 rating is considered
      #   "average", and the rating<->distance priority slider more accurately
      #   represents what impact it has on the cost.
      #  One last thing about the slider value: a 100% bike cost using the
      #   scale we've been discussing (from 0 to some number, with successive
      #   ratings equally spaced), always means that an excellent road (4) is
      #   one-quarter the cost of a poorly- rated road (1). Or, 3.999 miles of
      #   excellent road is less cost than 1 mile of poorly-rated road. So,
      #   when combing rating cost and distance cost, if we didn't scale up
      #   from 0 to 1, the difference between fair and excellent is scaled
      #   again. Consider 25% distance cost and 75% rating cost,
      #    1/4 + (3/4)*(4/5) = 17/20 for 1 mile of poor.
      #    Then, for the same cost of excellent,
      #     (1/4)*some_length + (3/4)*some_length*(1/5) = 17/20,
      #     and some_length=(17.0/20.0)*(20.0/8.0) = 2.125
      #    So at 75% rating weight, 1 mile poor = 2.125 excellent, but
      #     at 100% rating, it was 1 mile poor = 4 mile excellent. Now, using
      #     the 3 scaler, 1/4 + 3*(3/4)*(4/5) = 41/20 for 1 mile of poor.
      #     Then, for the same cost of excellent,
      #      (1/4)*some_length + 3*(3/4)*some_length*(1/5) = 41/20,
      #      and some_length=(41.0/20.0)*(20.0/14.0) = 2.92.
      #    So at 75% rating priority, almost 3 miles of excellent is equal
      #    to 1 mile of poor, which feels more natural for the scale,
      #    considering that at 100% rating, 4 miles of excellent is equal
      #    to 1 mile of poor (and you could extrapolate and assume that at
      #    50% rating priority, 2 miles or so of excellent is equal to
      #    1 mile of poor, and then at 25% rating priority, it's around
      #    1.2 to 1.4 or 1.5 -- the idea being, if the ends of the spectrum
      #    are 1:1 and 4:1, that slider should try its best to slide across
      #    that range).
      #
      # Now, on to some more math.
      #
      # Let's write some equations to help us understand the current
      # relationships between ratings.
      #
      # At 100% rating cost, where r1 and r2 are the inverted ratings (e.g.,
      #   if r1 is excellent (4), then r1 = 1-4/5 = 1/5).
      #  The relationship is r1/r2.
      #   E.g., if r1 = 1/5 (excellent), and r2 = 2/5 (good), r1/r2 = 2.
      #         if r1 = 1/5 (excellent), and r2 = 3/5 (fair), r1/r2 = 3.
      #         if r1 = 1/5 (excellent), and r2 = 4/5 (poor), r1/r2 = 4.
      #   The last examples seem natural, unless you look at them in reverse:
      #         if r1 = 2/5 (good), and r2 = 1/5 (excellent), r1/r2 = 2.
      #         if r1 = 2/5 (good),      and r2 = 3/5 (fair), r1/r2 = 2/3.
      #         if r1 = 2/5 (good),      and r2 = 4/5 (poor), r1/r2 = 1/2.
      #    I.e., excellent is half the cost of good, but fair isn't twice
      #    the cost of good, it's just 3/2 the cost.
      #
      # At 50% rating and 50% distance, where x is the length of the inferior-
      # rated road, and y is the length of the better-rated  road, and y = mx
      # where m > 1 (since y is longer since it's better rated), and c is the
      # range scalar, and r1 is the worse cost and r2 the better cost,
      #  (1/2)*x + (1/2)*x*c*r1 = (1/2)*y+(1/2)*y*c*r2
      #  (1/2)*x + (1/2)*x*c*r1 = (1/2)*m*x+(1/2)*m*x*c*r2
      #  Dividing out the 1/2 and the x,
      #  1 + c*r1 = m(1 + c*r2), so, m = (1 + c*r1)/(1 + c*r2).
      #
      # At 12.5% rat and 87.5% distnce, m = (7 +   c*r1)/(7 +   c*r2)
      # At 25% rating and 75% distance, m = (3 +   c*r1)/(3 +   c*r2)
      # At 50% rating and 50% distance, m = (1 +   c*r1)/(1 +   c*r2)
      # At 75% rating and 25% distance, m = (1 + 3*c*r1)/(1 + 3*c*r2)
      # At 87.5% rat and 12.5% distnce, m = (1 + 7*c*r1)/(1 + 7*c*r2)
      #
      # E.g., at 50/50, if c = 1, r1 = 1/5, and r2 = 2/5, then m = 6/9.
      #            But, if c = 3, r1 = 1/5, and r2 = 2/5, then m = 8/17.
      #   This example was discussed above. At c=1 and 50/50 an excellent
      #   road that's 1-1/2 times longer than a good road is the same cost,
      #   but at c=3, the excellent road can be a little over twice as long
      #   and be the same cost.
      #
      # Okay, enough math. I think we get the point.
      #
      # So, Finally, what's the endgame?
      #
      # There are three obvious ways to scale the rating:
      #
      #  1. From 0 to some number.
      #
      #     The latter number doesn't matter if the ratings are all equally
      #     spaced. E.g., 0-1-2-3-4 will produce comparatively equivalent costs
      #     as will 0-10-20-30-40. We only need to scale if we're normalizing
      #     the cost so it can be combined with the distance cost (as we do for
      #     all cases).
      #
      #  2. By adding a constant.
      #
      #     E.g., Instead of 0 to 5, scale from 2 to 7.
      #     This doesn't really change the problem, it just starts the
      #     converging process quicker, e.g., in a scale of 0 to 5, if
      #     excellent maps to 1, good to 2, and fair to 3, than excellent is
      #     half the cost of good, but good is only 2/3 the cost of 3. Now
      #     consider mapping excellent to 3, good to 4, and fair to 5:
      #     excellent is 75% the cost of good, and good is 80% the cost
      #     of fair. So we still have the problem with ratings scaling
      #     unevenly, but it's a little less prounced since we're not
      #     scaling from 0.
      #
      #  3. By using a geometric progression.
      #
      #     For instance, consider the progression 2 * pow(1.5, n) for n >= 0:
      #      2, 3, 4.5, 6.75, 10.125.
      #      If excellent maps to 2, and good to 3, fair to 4.5, etc.
      #      excellent is half the cost of good, and good is half the cost of
      #      fair, and fair is half the cost of poor, etc.
      #      (We could also not scale the power by 2 and get the same results,
      #      e.g., 1, 1.5, 2.25, 3.375, 5.0625 are each related by 3/2 or 2/3.)
      #
      # Looking further into the geometric progression, consider the simple
      #  scale, excellent = 1, 2, 3, 4 = poor. One mile of poor == 4 miles exc,
      #  or 2 miles good, or 1-1/3 miles fair. With the geometric scale, where
      #  excellent = 2, 3, 4.5, 6.75 = poor,
      #  1 mile of poor = (6.75/2.0) = 3.375 miles of excellent, or
      #  (6.75/3.0) = 2.25 miles good, or 6.75/4.5 = 1.5 miles fair.
      # Each rating step is 3/2 or 2/3 that of its neighor, and we'll
      #  distinguish between pairs of ratings just the same, e.g.,
      #  if 1 mile good = 1.5 mile excellent,
      #  then so should 1 mile fair = 1.5 mile good.
      #
      # There are other scales we could use.
      #
      # We could use a geometric pregression where we bind the bounds
      # between excellent and impassable. Perhaps from 2 to 3, if we
      # wanted, for ratings 0=impass through 4=exc, then:
      #    0      1/4       1/2       3/4       1    || (4-rating)/4
      #   2.0 -- 2.2133 -- 2.4494 -- 2.7108 -- 3.0   || 2*pow(1.5,4-rating/4)
      #   excellent                     impassable
      # Going right, each term is * 1.10665 the previous term,
      #  and going left, it's 0.9036.
      #
      #    0      1/4       1/2       3/4       1    || (4-rating)/4
      #   2.0 -- 2.5149 -- 3.1622 -- 3.9763 -- 5.0   || 2*pow(2.5,4-rating/4)
      # The ratios between terms is * 1.257 and * 0.7955.
      #
      #    0      1/4       1/2       3/4       1    || (4-rating)/4
      #   4.0 -- 5.0297 -- 6.3246 -- 7.9527 -- 10.0  || 4*pow(2.5,4-rating/4)
      # The ratios between terms is * 1.257 and * 0.7955. The same. Duh.
      # Argh: the 4* doesn't matter. It's the 2.5 that matters.
      #
      #    0      1/4       1/2       3/4       1    || (4-rating)/4
      #   4.0 -- 4.1892 -- 4.4142 -- 4.6818 -- 5.0   || 3 + pow(2.0,4-rating/4)
      # The ratios differ... so addition again never solved anything, mon.
      #
      #    0      1/4       1/2       3/4       1    || (4-rating)/4
      #   1.0 -- 1.4142 -- 2.0000 -- 2.8284 -- 4.0   || pow(4.0,4-rating/4)
      # The ratios between terms is * 1.4142 and * 0.7071.
      # The ration are: pow(4.0,0.25) and pow(4.0,-0.25), i.e.,
      # one of our units is 1/4 so +/- pow(4,1/4) are the multipliers.
      #
      #    0      1/2       1       3/2       2      || (4-rating)/2
      #   1.0 --  2.0  --  4.0  --  8.0  --  16.0    || pow(4.0,4-rating/2)
      #                                      same as :: pow(16.0,4-rating/4)
      #   So *2 or *1/2.
      #
      # Basically, define the range you want.
      #  pow(1.0, (4-rat)/4) is 1 for every rating.
      #   I.e., no rating influence, or 100% distance cost.
      #  pow(16.0, (4-rat)/4) ranges from 1 (excellent) to 16 (impassable).
      #   The difference btw. ratings is calculated: pow(16, -.25) : 0.5
      #                                              pow(16, 0.25) : 2.0.
      #   Stated elsewise, you're willing to bike twice as far for each
      #   successively-better-rated route. E.g.,
      #    1 mile excellent = 2 miles good = 4 miles fair = 8 poor.
      #  pow(8.0, (4-rat)/4) ranges from 1 (excellent) to 8 (impassable).
      #   The ratio is pow(8, -.25) : 0.59 / pow(8, 0.25) : 1.68, i.e.,
      #   you're willing to bike 1.7 times longer for each better rated
      #   route: 1 mile excellent = 1.68 miles good = 2.82 miles poor,
      #   = 4.74 miles impassable.
      #  pow(4.0, (4-rat)/4) ranges from 1 (excellent) to 4 (impassable),
      #   which ratios 1.4142 and 0.707, and range 1, 1.414, 2, 2.82, 4.
      #   1 mile excellent = 1.414 good = 2 fair = 2.82 poor = 4 impass.
      #  pow(2.0, (4-rat)/4) ranges from 1 (excellent) to 2 (impassable),
      #   which ratios 1.189 and 0.841:
      #   1 mile excellent = 1.189 good = 1.414 fair = 1.682 poor = 2 impass.
      #
      # For the static planner, consider 6 options: pows: 1, 2, 4, 8, 16, 32
      #  Where pow=1 is all-distance cost, and pow=32 is insane all-excellent.
      #
      # One way to sum all of this up is that, in the p1 planner, you're likely
      # to only ever get two routes: either a route that uses well-rated roads,
      # or a route that's the shortest distance. Because of the jump from
      # excellent to good, and the decreasing size of the jumps after that,
      # and because the rating algorithm only ever uses the one range (0 to n),
      # it'll be greedy and choose very well rated roads, and as soon as
      # you move the priority slider far enough toward shortest distance to
      # actually get a different route, you'll end up with the shortest
      # distance route. With the p1 planner, you'll always get the shortest
      # route, or the route with the absolute best-rated roads that might be
      # considerably longer, but you won't be able to generate an in-between
      # route. E.g., you can find a 10 mile crappy road route, and you can
      # find a 20 to 30 mile excellent road route, but you won't be able to
      # find a 15 mile mediocre road route.
      #
      # I've only just recently tossed together the new p3 planner, but testing
      # Gateway Fountain to W 50th St and Dupont Ave S, Mpls, I was able
      # to get four different results using the willingness slider -- one
      # route followed the lake paths and Kenilworth trail; another followed
      # the bike lanes on Blaisdell; another went down Lyndale; and the
      # least influenced by facilities, and also the shortest route, was via
      # Colfax/Bryant. Using the p1 planner, with the slider at shortest
      # distance, I got a route down Colfax; moving the slider one toward
      # rating influence, I got a route down Bryant; next, a route down
      # Aldrich. It wasn't until the last couple of ticks on the rating end
      # of the scale that I got a route down Chicago, and that's a road I've
      # rated excellent. With nine different priorities, I basically got two
      # different routes. With the six different burdens I've defined for p3,
      # I got four different routes for the same origin and destination. Albeit
      # the p3 planner didn't generate a route down Chicago Ave... but it's
      # out of the way, so even with bike lanes, it would always lose to
      # Blaisdell. I guess that makes sense. Anyway, I've defined a new
      # set of rating power weight, so maybe the new static rating weights will
      # find that route down Chicago...
      # TESTME: New rat wgts on: Gateway Fountain
      #                          to W 50th St and Dupont Ave S, Mpls
      #
      #  Some reference:
      #   https://en.wikipedia.org/wiki/Arithmetic_progression
      #   https://en.wikipedia.org/wiki/Geometric_progression
      #
      # The following comments are from [lb] from different times before 2014.
      # This ends the spew from 2014.04.11.

      # (Note: 4 is Excellent, so ratings >4 are only possible when a tag bonus
      #  is applied. In item.util.ratings.rating_func, the rating is
      #  calculated as the average of a master rating value and zero or more
      #  tag preference bonuses (+5 for each matching tag) and penalities (+0.5
      #  for each matching tag); the master rating is either the user's rating
      #  (if one exists), or the average user rating (if one exists), or a
      #  rating calculated from byway attributes. E.g., if a road is rated
      #  good (+3) and there's one tag bonus (+5) and one tag penalty (+0.5),
      #  the rating is (3+5+.5)/3 = 8.5/3 = 2.83. You can see that even with
      #  a lot of bonuses, it's hard to get above a 4.9, e.g., the highest
      #  rating is 4, and with 5 bonuses, (4.0+5.0*5.0)/6.0 = 4.83. As such,
      #  the smallest realistic scale value on the scale of 0 to 3 is 0.10
      #  (if we use the example of 5 bonuses); the highest realistic value
      #  is still 3, though, since ratings of 0 happen readily.)

      # [lb] Here's a look at what usually happens, considering a byway that
      # matches zero or one tag prefs.
      #
      # thumbs down, 'fair', (0.5+2)/2 = 1.25, 3*(1-1.25/5) = 2.25      > 1.50
      # thumbs down, 'good', (0.5+3)/2 = 1.75, 3*(1-1.75/5) = 1.95      >
      # thumbs down, 'excl', (0.5+4)/2 = 2.25, 3*(1-2.25/5) = 1.65      >
      # thumbs   up, 'fair', (5.0+2)/2 = 3.50, 3*(1-3.50/5) = 0.90   < 1.50
      # thumbs   up, 'good', (5.0+3)/2 = 4.00, 3*(1-4.00/5) = 0.60   <   
      # thumbs   up, 'excl', (5.0+4)/2 = 4.50, 3*(1-4.50/5) = 0.30   <   
      #       avoid, 'fair', (0.0+2)/2 = 1.00, 3*(1-1.00/5) = 2.40      >
      #       avoid, 'good', (0.0+3)/2 = 1.50, 3*(1-1.50/5) = 2.10      >
      #       avoid, 'excl', (0.0+4)/2 = 2.00, 3*(1-2.00/5) = 1.80      >
      # no tag pref, 'poor',     (1)/1 = 1.00, 3*(1-1.00/5) = 2.40      >
      # no tag pref, 'fair',     (2)/1 = 2.00, 3*(1-2.00/5) = 1.80      >
      # no tag pref, 'good',     (3)/1 = 3.00, 3*(1-3.00/5) = 1.20   <   
      # no tag pref, 'excl',     (4)/1 = 4.00, 3*(1-4.00/5) = 0.60   <   

      # And finally, the cost function as it's been writ since Release 29.

      c = 3.0 * rs.edge_length * (1.0 - (rating_func(rs.byway_stack_id) / 5.0))
      return c

   # ***

   # To find the facil. definitions, search: skin_bikeways.assign_attr_pen.
   # MAYBE: Make a bike facility pyserver utility/enum class... currently,
   #        bike facility names are defined in mapserver.skins.skin_bikeways.py
   #        and in pyserver.planner.routed_p1.route_finder.
   # SYNC_ME: Search: bike_facil values.
   #          See, e.g., mapserver/skins/skin_bikeways.py
   #          Some values: paved_trail, loose_trail, bike_lane, etc.
   bike_facils_positive_benefit = [
      # Skipping: 'no_facils'
      'paved_trail',
      'loose_trail', # MAYBE: Don't include unpaved?
      'protect_ln',
      'bike_lane',
      'rdway_shrrws',
      'bike_blvd',
      'rdway_shared',
      'shld_lovol',
      'shld_hivol', # FIXME: Can we rate this a little lower than shld_lovol
                    # but still above roads without any facilities?
      # Skipping:
      #  'hway_lovol'
      #  'hway_hivol'
      #  'gravel_road'
      ##  'major_street'
      'bk_rte_u_s',
      'bkway_state',
      # Skipping: The cautions:
      #  'no_cautys'
      #  'poor_visib'
      #  'extra_cautn'
      #  'diffi_conn'
      ##  'cntrld_acs'
      ##  'climb'
      ]

   #
   @staticmethod
   def cost_bike_facils(rs, rating_func):

      g.assurt(False) # See the p3 planner for facility weights.

      # Return a high rating if the route step has an attribute associated
      # with the metro council bikeways branch.

      # FIXME: This fcn. isn't quite right... I [lb] don't think just
      #        multiplying the length by 150.0 really makes much sense...

      # SYNC_ME: metc bikeways definition
      # FIXME: At the moment, route_step does not store branch_id. We can
      # consolidate byway_system_id and byway_stack_id into just byway, and
      # then we'd get access to the branch_id, and can do a simple comparison
      # to the MetC branch id (or add a branch_id col to route_step if a full
      # byway is too heavyweight).

      base_bike_facil = '/byway/cycle_facil'
      metc_bike_facil = '/metc_bikeways/bike_facil'

      bike_facil = None
      try:
         bike_facil = rs.attrs[base_bike_facil]
      except KeyError:
         try:
            bike_facil = rs.attrs[metc_bike_facil]
         except KeyError:
            pass

      # See if this facility is a "happy" one.

      if bike_facil in Cost_Functions.bike_facils_positive_benefit:
         # There's no penalty for bikeways steps.
         # NOTE: Returning a zero cost, which means free, but this value
         #       should get added to the 'dist' and 'bike' costs... so this
         #       does not represent the final cost of an edge but just a
         #       penalty.
         return 0.0
      else:
         # Penalize non-bikeways steps with added cost.
         # FIXME/EXPLAIN: 2012.09.17: [lb] asks, Why 150?
         return 150.0 * rs.edge_length

   # ***

# ***

# Now that the cost fcns. are defined, make the lookup table.

cost_funcs = {
   'dist': Cost_Functions.cost_dist,
   'bike': Cost_Functions.cost_bike,
   }

# ***


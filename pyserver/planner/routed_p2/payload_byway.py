# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

'''This file is the main script for building a multimodal graph. '''

import math
import sys
import time
import traceback

from pkg_resources import require
require("Graphserver>=1.0.0")
from graphserver.core import GenericPyPayload
from graphserver.core import Street
from graphserver.gsdll import LGSTypes
from graphserver.gsdll import lgs

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from util_ import geometry

__all__ = ['Payload_Byway']

# NOTE: If you uncomment or put a lot of trace messages herein, you'll want to 
#       relax flashclient/Conf.as's network timeout to a couple minutes, since
#       tracing the edge weight functions slows down route finding a lot.
log = g.log.getLogger('transit_graph')

# Some notes from Graphserver...
#
# The State class has the following members:
#
#    time, weight, dist_walked, num_transfers, prev_edge, num_agencies, 
#    trip_id, stop_sequence 
#
# NOTE: num_agencies is n_agencies in the Graphserver C code
# 
# The GenericPyPayload class derives from EdgePayload, which is part Walkable:
#
#   class Walkable:
#      def walk(self, state, walk_options):
#         return State.from_pointer(self._cwalk(self.soul, state.soul, 
#                                               walk_options.soul))
#      def walk_back(self, state, walk_options):
#          return State.from_pointer(self._cwalk_back(self.soul, state.soul, 
#                                                     walk_options.soul))
# 
# Developers can poke around with Graphserver's built-in Street edge type using
# the lgs dll to get at the cost fcns:
#
#   Street._cwalk = lgs.streetWalk
#   Street._cwalk_back = lgs.streetWalkBack
#
# but we use our own cost function, Payload_Byway.cost.
#
# NOTE: It's a pain in the butt to debug this class. It takes a few minutes to
#       boot the server, and certain errors will causes my [lb's] linux cpu to 
#       max out, and it takes a minute to get control back of my OS. 
#
#       For one thing, don't override base class methods defined in 
#       graphserver/core.py.
#
#       FIXME: Just load a subset of the road network, silly! Maybe just Mpls?
#              Or just a neighborhood within Mpls?

class Payload_Byway(GenericPyPayload):

   outstanding_problems = {}

   PI_EIGHTH_POSITIVE = math.pi / 8.0
   PI_EIGHTH_NEGATIVE = math.pi / -8.0
   PI_NEGATIVE = -1.0 * math.pi

   # C.f. graphserver/core/graphserver.h
   ABSOLUTE_MAX_WALK = 1000000 # graphserver.h says, "meters. 100 km. prevents 
                               # overflow", but 1 million meters is 1 thousand 
                               # kilometers. Is the comment wrong, or the num?
   # FIXME: This is the max value a C long can hold. Does it apply to
   #        Python? If so, is it the same, or more or less?
   # FIXME: Is the 'cannot find a route to...' error that Graphserver returns 
   #        because of this value? I saw that mentioned in a Google group post.
   # MAX_LONG = 2147483647 # From graphserver/core/graphserver.h
   MAX_LONG = 1999999999

   __slots__ = (
      # C.f. core/edgetypes/street.c/h
      'type', # required by Graphserver
      'reverse_of_source',
      # C.f. graphserver/core.py :: Street()
# FIXME: Remove these
      'rise',
      #'fall',
      'slog',
      # Pointer to the Cyclopath byway object

# BUG 2641: Poor Python Memory Management
# FIXME: copy from byway instead and make a lighter-weight object.
#        do not keep references to byways.
'byway',

      'forward',
      'dir_entry',
      'dir_exit',
      'average_grade',
      )

   def __init__(self, byway, forward):
      GenericPyPayload.__init__(self)
      # NOTE: graphserver.core crashes if you don't set self.type
      self.type = LGSTypes.ENUM_edgepayload_t.PL_EXTERNVALUE
      self.rise = 0.0
      #self.fall = 0.0
      self.slog = 1.0
      self.byway = byway
      self.forward = forward
      # Calculate the slope of the street.
      # Graphserver's Street defines a rise and a fall. The rise is the number
      # of meters of elevation as you travel the line segment, and the fall is
      # the number of meters of descending. Since Cyclopath only stores the
      # elevation at the endpoints, we can only supply one of those values, and
      # it might be less than its true value.
      if byway.geometry_len > 0.0:
         try:
            if forward:
               elevation_delta = (float(byway.node_rhs_elevation_m) 
                                  - float(byway.node_lhs_elevation_m))
            else:
               elevation_delta = (float(byway.node_lhs_elevation_m) 
                                  - float(byway.node_rhs_elevation_m))
            self.average_grade = elevation_delta / byway.geometry_len
            if elevation_delta > 0.0:
               self.rise = elevation_delta
         except TypeError, e:
            log.error('TypeError: %s' % (str(e),))
            log.error('byway: %s' % (str(byway),))
            log.error('beg_node_id: %s' % (byway.beg_node_id,))
            log.error('fin_node_id: %s' % (byway.fin_node_id,))
            log.error('node_lhs_elevation_m: %s'
                      % (byway.node_lhs_elevation_m,))
            log.error('node_rhs_elevation_m: %s'
                      % (byway.node_rhs_elevation_m,))
            self.average_grade = 0.0
            #self.rise = 0.0
            # Don't raise, so that we keep loading, even if we can't figure
            # out the elevation.
            # Nope: raise
            g.assurt_soft(False)
      else:
         self.average_grade = 0.0
         #self.rise = 0.0
      #log.debug('Payload_Byway: byway: %s / avg_grade: %.5f / fwd: %s' 
      #          % (self.byway.name, self.average_grade, self.forward))

   # *** Base class overrides

   # 
   def walk_general(self, state, walkoptions, is_forward):
      # If Walk_Options had a generic payload for us, we could use it to store
      # a pointer to the Problem object, but it doesn't, so have maintain a
      # static lookup in the Problem class.
      #log.debug('walk_general: walk_ops.soul: %s' % (walkoptions.soul))
      try:
         problem = Payload_Byway.outstanding_problems[walkoptions.soul]
      except KeyError:
         raise GWIS_Error('The Edge cannot find its Problem!')
      try:
         state = self.cost(problem, state, walkoptions, is_forward)
      except Exception, e:
         # NOTE: Some errors -- if they're thrown in the Graphserver C code --
         # can cause your system to stall and it processes all the errors
         # (stall for a few minutes). In VirtualBox, I [lb] "disconnect the
         # cable".  I also hover over a command line, poised to execute my
         # 'killrd2' command, which kills the routed_p2 route finder, if I see
         # any errors in the log trace, because you sometimes have a second
         # between seeing the error and the system freezing. (The freeze
         # might not happen on dev. machines, as I've only got one processor
         # allocated to VirtualBox.)
         # FIXME: I'm not sure that sys.exit() really prevents the system from
         # freezing.
         # NOTE: We can't call GWIS_Error because we're running in the context
         # of the Graphserver C library. Also, I don't think sys.exit() stops
         # the system from freezing, because Graphserver always regains
         # control.
         log.error('Programming Error! "%s" / %s' 
                   % (str(e), traceback.format_exc(),))
         sys.exit()
      return state

   # 
   def walk_impl(self, state, walkoptions):
      return self.walk_general(state, walkoptions, True)

   # 
   def walk_back_impl(self, state, walkoptions):
      g.assurt(False) # I think this is for arrive-by problems.
      return self.walk_general(state, walkoptions, False)

   # *** The Cyclopath cost calculation

   #
   def cost(self, problem, state, walk_opts, is_forward):
      # Get the Bikeability weight. In flashclient, this is a slider, and we
      # use it to scale the edge weight based on user ratings and tag prefs.
      bikeability_weight = problem.p1_priority
      # Get the rating. The fcn., problem.rating_func, is generally (always?)
      # ratings.rating_func. The rating is an average of the user's rating
      # (0-4) and all the tag prefs that match the byway's tag (5 for each
      # thumbs up, 0.5 for each thumbs down, and 0 for each avoid).
      byway_rating = problem.rating_func(self.byway.stack_id)
      # Calculate the edge weight
      ret = self.byway_cost(problem, state, walk_opts, is_forward, 
                            byway_rating, bikeability_weight)
      #log.debug('cost: byway_cost: w %s / t %d / d %s' 
      #          % (ret.weight, ret.time, ret.dist_walked))
      return ret

# FIXME: Does v2 A* use dist-to-goal?

   # C.f. graphserver/core/edgetypes/street.c :: streetWalkGeneral
   def byway_cost(self, problem, state, walk_opts, is_forward, 
                  byway_rating, bikeability_weight):

      # NOTE: You gotta be careful about types, lest C barf on you! If it's an
      # int or a long in C, it must be an in in Python. Same for doubles:
      # they must be Python floats, otherwise you'll get a type error.

      # In Graphserver, Street's walk fcn. makes a copy of the State, and then 
      # modifies and returns that. In core.py, however, Graphserver clones
      # the State first and passes us the clone.
      ret = state

      # If the byway is already rated super low, don't bother with the real
      # cost function.
      if byway_rating < problem.rating_min:
         # Impassable; set weight super heavy
         new_weight = float(Payload_Byway.MAX_LONG)
         end_dist = state.dist_walked + self.byway.geometry_len
# FIXME: Else check that byway matches branch. If you load multiple revision,
# check revision matches, too. If you load private byways, check permissions,
# too.
# See: problem.req for branch and revision, right? at least br and rev of
# loaded map. See: ??? for current route request branch and revision.
      else:
         # Otherwise, get the new values for the state object.
         (new_weight, delta_t, end_dist) = self.byway_cost_passable(
               ret, problem, state, walk_opts, is_forward, byway_rating, 
               bikeability_weight)
         ret.dist_walked = end_dist
         # EXPLAIN: What's this do?
         # FIXME: Should we apply this to the MAX_LONG case above, too?
         if is_forward:
            lgs.elapse_time_and_service_period_forward(ret.soul, state.soul, 
                                                       int(delta_t))
         else:
            lgs.elapse_time_and_service_period_backward(ret.soul, state.soul, 
                                                        int(delta_t))

      if (new_weight < Payload_Byway.MAX_LONG):
         ret.weight = int(new_weight)
      else:
         ret.weight = Payload_Byway.MAX_LONG
      ret.dist_walked = end_dist
      # Set the previous edge to us. We don't need to do self.soul, as the
      # Graphserver wrapper will do that for us.
      ret.prev_edge = self

      return ret

   def byway_cost_passable(self, ret, problem, state, walk_opts, 
                           is_forward, byway_rating, bikeability_weight):

      # BUG nnnn: Let the user specify more of the walk_opts and other
      # variables we use.

      # Calculate the anticipated biking speed along this street for an
      # "average rider".
      # FIXME: Let user specify if they are an A-, B-, or C-type rider.
      average_speed = self.speed_from_grade(problem, walk_opts)
      #log.verbose(' >> geometry_len: %.2f' % (self.byway.geometry_len,))
      #log.verbose(' >> average_speed: %.2f' % (average_speed,))
      #log.verbose(' >> byway: %s (%d) / fwd: %s' 
      #            % (self.byway.name, self.byway.id, self.forward))

      # Calculate the time it takes to ride this edge.
      delta_t = (self.byway.geometry_len / average_speed)
      #log.verbose(' >> delta_t (travel): %.2f' % (delta_t,))

      # Penalize the rider for turning or crossing an intersection.
      if ((state.prev_edge)
          and (isinstance(state.prev_edge, Payload_Byway))):
         delta_t += self.byway_transition_cost(state)
         #log.verbose(' >> delta_t (turning): %.2f' % (delta_t,))

      # Plug in the Bikeability rating. The byway rating is a number from 0
      # to 5, where 2.5 is an 'average' rating that has no effect, 0 means
      # to avoid the byway, and 5 means the byway is really cool. Note that
      # byway_rating isn't less than problem.rating_min (usually 1), since the
      # caller wouldn't have called us otherwise.
      #
      # Bikeability weight is 0.0 to 1.0, depending on the slider in
      # flashclient. A 0.0 means the bikeability has no effect, and a 1.0 means
      # the bikeability should have a large effect.
      delta_w = delta_t
      if bikeability_weight > 0.0:
         bikeability = (1.0 - (byway_rating / 5.0)) # 0.0 to 1.0
         # 0.9 to 1.2, 2.5 being 1.0?
         if byway_rating > 2.5:
            # Scale to 0.9 to 1.0
            # bikeability is 0.0 to 0.5
            bikeability_scale = (0.9 + (0.1 * (bikeability * 2.0)))
         else:
            # Scale to 1.0 to 1.2
            # bikeability is 0.5 to 1.0
            bikeability_scale = (1.0 + (0.2 * ((bikeability - 0.5) * (2.0))))
# BUG nnnn: This is soooooo wrong! The weight is 0.0 to 1.0! and scale 0.9 to 
# 1.2. So result is not 0.9 to 1.2 but 0.0 to 1.2, silly!
         delta_w *= bikeability_weight * bikeability_scale

      # Scale the time with the walking reluctance.
      delta_w *= walk_opts.walking_reluctance

      # Add the hill reluctance penalty.
      # (NOTE: 2011.06.28: hill_reluctance is 0.0, so this adds nothing.)
      delta_w += (self.rise * walk_opts.hill_reluctance)

      #log.verbose(' >> delta_w (reluctance): %.2f' % (delta_w,))
      # FIXME: This is from the graphserver Street.c cost fcn. Why would this
      # value ever be negative?
      if (delta_w < 0.0):
         delta_w = 0.0
         #log.verbose(' >> delta_w (corrected): %.2f' % (delta_w,))

      # Penalize the edge by the amount we've exceeded the max bike distance.
      end_dist = state.dist_walked + self.byway.geometry_len
      #log.verbose(' >> end_dist (dist_walked): %.2f' % (end_dist,))
      if ((walk_opts.max_walk < Payload_Byway.ABSOLUTE_MAX_WALK) 
          and (end_dist > walk_opts.max_walk)):
         # NOTE: You penalize more the more you are over?
         delta_w += ((end_dist - float(walk_opts.max_walk)) # excess meters
                     * walk_opts.walking_overage            # 0.1
                     * delta_t)                             # secs to trav edge
         #log.verbose(' >> delta_w (overage): %.2f' % (delta_w,))
      if (delta_w < 0.0):
         # This is necessary if walking_overage is allowed to be negative
         delta_w = 0.0
         #log.verbose(' >> delta_w (corrected): %.2f' % (delta_w,))

      # //TODO profile this to see if it's worth it
      # In C, ret.weight is a long
      the_weight = ret.weight
      if (end_dist > Payload_Byway.ABSOLUTE_MAX_WALK):
         the_weight = Payload_Byway.MAX_LONG
      else:
         #log.verbose(' >> ret.weight (before slog): %.2f' % (ret.weight,))
         # path cost (cumulative edge weights)
         the_weight += self.slog * delta_w
      #ret.weight = int(the_weight)
      #log.verbose(' ========== >> the_weight (final): %.2f' % (the_weight,))

      return (the_weight, delta_t, end_dist)

   # FIXME: This cost seems weird, since not all intersections are the same,
   #        and not all byway connections are intersections.
   def byway_transition_cost(self, state):
      a = geometry.rotation_ccw(state.prev_edge.dir_exit, self.dir_entry)
      # FIXME: Change routing_penalty_* in CONFIG: was meters, now seconds
      # FIXME: These seem too costly? Maybe don't apply to short byways? Or 
      #        devise a mechanism to know if the vertex is really an
      #        intersection, and what kind of traffic controls exist.
      if (a > Payload_Byway.PI_EIGHTH_POSITIVE):
         return 22.2 # secs. # conf.routing_penalty_left # 100 (meters) / 4.5 m/s (10mph)
      elif (a > Payload_Byway.PI_EIGHTH_NEGATIVE):
         return 4.44 # secs. # conf.routing_penalty_straight # 20 (meters)
      else:
         g.assurt(a >= Payload_Byway.PI_NEGATIVE)
         # FIXME: Why is a right more costly than forward? Because you slow
         # down?
         return 8.88 # secs. # conf.routing_penalty_right # 40 (meters)

   # C.f. graphserver/core/edgetypes/street.c::speed_from_grade
   def speed_from_grade(self, problem, walk_opts):
      speed = 0.0
      grade = self.average_grade
      if grade <= 0.0:
         #log.verbose(' << downhill')
         speed = walk_opts.downhill_fastness * grade + walk_opts.walking_speed
      elif grade <= problem.phase_change_grade: # 0.045
         #log.verbose(' << slight incline')
         speed = (problem.phase_change_velocity_factor * grade * grade 
                  + walk_opts.downhill_fastness * grade 
                  + walk_opts.walking_speed)
      else:
         #log.verbose(' << uphill')
         speed = ((walk_opts.uphill_slowness * walk_opts.walking_speed)
                  / (walk_opts.uphill_slowness + grade))
      # E.g., grade: 0, speed: 4.5
      #log.verbose('speed_from_grade: gr.: %.2f / speed: %.2f' 
      #            % (grade, speed,))
      return speed

# *** Unit testing

if (__name__ == '__main__'):
   pass


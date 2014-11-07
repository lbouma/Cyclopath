# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('travel_mode')

class Travel_Mode(object):

   # NOTE: See the long discussion about this class in flashclient's package of
   #       the same name.

   # SYNC_ME: Search: Travel Mode IDs.
   undefined = 0
   bicycle = 1 # To route, personalized alg.; to step, is byway segment.
   transit = 2 # To route, multimodal planner; to step, a transit edge.
   walking = 3 # Reserved; currently not used.
   autocar = 4 # Reserved; should be called automobile? [ml]
               #           No, because then the word width of each of 
               #           the four options is no longer the same. =) [lb]
   wayward = 5 # Uses NetworkX and pre-calculated weights; *fast* p3 planner.
   classic = 6 # Use the original p1 planner.
   invalid = 7 # SYNC_ME: Keep this value 1+ the last value.

   # Which planners handle which travel modes.
   p1_modes = set([classic,])
   p2_modes = set([transit,])
   p3_modes = set([wayward, bicycle,])
   # 2014.04.25: flashclient sends all but bicycle;
   #          Bug nnnn: android still sends bicycle.
   px_modes = set([wayward, transit, classic, bicycle,])

   lookup = {
      # SYNC_ME: Search: Travel Mode IDs.
      # NOTE: Cannot use, e.g., Travel_Mode.undefined (not defined yet)
      'undefined':      undefined,
      'bicycle':        bicycle,
      'transit':        transit,
      'walking':        walking,
      'autocar':        autocar,
      'wayward':        wayward,
      'classic':        classic,
      }

   lookup_by_str = lookup

   lookup_by_id = {}
   for k,v in lookup_by_str.iteritems():
      lookup_by_id[v] = k

   #
   def __init__(self):
      raise # do not instantiate an object of this class

   #
   @staticmethod
   def get_travel_mode_id(travel_mode_name):
      g.assurt(travel_mode_name in Travel_Mode.lookup_by_str)
      return Travel_Mode.lookup_by_str[travel_mode_name]

   #
   @staticmethod
   def get_travel_mode_name(travel_mode_id):
      g.assurt(Travel_Mode.is_valid(travel_mode_id))
      return Travel_Mode.lookup_by_id[travel_mode_id]

   #
   @staticmethod
   def is_valid(mode):
      # SYNC_ME: Search: Travel Mode IDs.
      # FIXME: 2012.09.24: This fcn. used to not catch ValueError. So search
      #        other is_valid-like fcns. and make sure you try/except.
      try:
         # See that it's an int. We don't want no non-ints.
         is_valid = ((mode > Travel_Mode.undefined) 
                     and (mode < Travel_Mode.invalid))
      except ValueError:
         is_valid = False
      return is_valid

   # *** Convenience methods

   # SIMILAR_TO: Item_User_Access.can_*()

   #
   @staticmethod
   def is_bicycle(mode):
      return (mode == Travel_Mode.bicycle)

   #
   @staticmethod
   def is_transit(mode):
      return (mode == Travel_Mode.transit)

   #
   @staticmethod
   def is_walking(mode):
      return (mode == Travel_Mode.walking)

   #
   @staticmethod
   def is_autocar(mode):
      return (mode == Travel_Mode.autocar)

   #
   @staticmethod
   def is_wayward(mode):
      return (mode == Travel_Mode.wayward)

   #
   @staticmethod
   def is_classic(mode):
      return (mode == Travel_Mode.classic)

   # ***

# ***


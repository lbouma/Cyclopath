# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This class acts as an enum, representing the values found in the 
# enum_definition database table, under the family: 'digest_frequency'.

import conf
import g

log = g.log.getLogger('watcher_freq')

class Watcher_Frequency(object):

   # SYNC_ME: Search: Watcher_Frequency IDs.
   never       = 0
   immediately = 1
   daily       = 2
   weekly      = 3
   nightly     = 4
   morningly   = 5
   ripens_at   = 6

   lookup = {
      # NOTE: Cannot use Watcher_Frequency.* (not defined yet)
      'never':       never,
      'immediately': immediately,
      'daily':       daily,
      'weekly':      weekly,
      'nightly':     nightly,
      'morningly':   morningly,
      'ripens_at':   ripens_at,
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
   def get_watcher_frequency_id(watcher_frequency_name):
      g.assurt(watcher_frequency_name in Watcher_Frequency.lookup_by_str)
      return Watcher_Frequency.lookup_by_str[watcher_frequency_name]

   #
   @staticmethod
   def get_watcher_frequency_name(watcher_frequency_id):
      g.assurt(Watcher_Frequency.is_valid(watcher_frequency_id))
      return Watcher_Frequency.lookup_by_id[watcher_frequency_id]

   #
   @staticmethod
   def is_valid(frequency):
      return ((frequency >= Watcher_Frequency.never) 
              and (frequency <= Watcher_Frequency.ripens_at))

   # *** Convenience methods

   # SIMILAR_TO: Item_User_Access.can_*()

   #
   @staticmethod
   def is_never(frequency):
      return (frequency == Watcher_Frequency.never)

   #
   @staticmethod
   def is_immediately(frequency):
      return (frequency == Watcher_Frequency.immediately)

   #
   @staticmethod
   def is_daily(frequency):
      # MAYBE: Remove this. No one uses it.
      #        Or else daily == (nightly or morningly)
      return (frequency == Watcher_Frequency.daily)

   #
   @staticmethod
   def is_weekly(frequency):
      return (frequency == Watcher_Frequency.weekly)

   #
   @staticmethod
   def is_nightly(frequency):
      return (frequency == Watcher_Frequency.nightly)

   #
   @staticmethod
   def is_morningly(frequency):
      return (frequency == Watcher_Frequency.morningly)


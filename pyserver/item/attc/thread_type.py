# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('thread_type')

class Thread_Type(object):

   # SYNC_ME: Search: Thread Type IDs.

   default = 0
   general = 1
   reaction = 2

   # ***

   lookup = {
      # NOTE: Cannot use Thread_Type.* (not defined yet).
      'default': default,
      'general': general,
      'reaction': reaction,
      }

   lookup_by_str = lookup

   lookup_by_id = {}
   for k,v in lookup_by_str.iteritems():
      lookup_by_id[v] = k

   #
   def __init__(self):
      raise # do not instantiate.

   #
   @staticmethod
   def get_thread_type_id(as_name_or_id):
      try:
         asid = int(as_name_or_id)
      except ValueError:
         g.assurt(as_name_or_id in Thread_Type.lookup_by_str)
         #g.assurt(as_name_or_id != 'default') # No reason.
         asid = Thread_Type.lookup_by_str[as_name_or_id]
      g.assurt(Thread_Type.is_valid(asid))
      return asid

   #
   @staticmethod
   def get_thread_type_name(thread_type_id):
      g.assurt(Thread_Type.is_valid(thread_type_id))
      return Thread_Type.lookup_by_id[thread_type_id]

   #
   @staticmethod
   def is_valid(thread_type_id):
      valid = ((thread_type_id in Thread_Type.lookup_by_id)
               and (thread_type_id != Thread_Type.default))
      return valid

# ***


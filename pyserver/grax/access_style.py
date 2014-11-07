# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('access_style')

class Access_Style(object):

   # SYNC_ME: Search: Access Style IDs.

   nothingset = 0
   all_access = 1 # Not implemented... maybe same as permissive.
   permissive = 2 # For branches, generally (unlimited GIA control).
   restricted = 3 # For routes and tracks, mostly (session ID).
   _reserved1 = 4 # Not implemented.
   pub_choice = 5 # on create, user can keep item public or make private.
   usr_choice = 6 # on create, user can keep item private or make public.
   usr_editor = 7 # style_change not allowed.
   pub_editor = 8 # style_change not allowed.
   all_denied = 9

   # ***

   lookup = {
      # NOTE: Cannot use Access_Style.* (not defined yet).
      'nothingset': nothingset,
      'all_access': all_access,
      'permissive': permissive,
      'restricted': restricted,
      # '_reserved1': _reserved1,
      'pub_choice': pub_choice,
      'usr_choice': usr_choice,
      'usr_editor': usr_editor,
      'pub_editor': pub_editor,
      'all_denied': all_denied,
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
   def get_access_style_id(as_name_or_id):
      try:
         asid = int(as_name_or_id)
      except ValueError:
         g.assurt(as_name_or_id in Access_Style.lookup_by_str)
         g.assurt(as_name_or_id != 'nothingset')
         asid = Access_Style.lookup_by_str[as_name_or_id]
      g.assurt(Access_Style.is_valid(asid))
      return asid

   #
   @staticmethod
   def get_access_style_name(access_style_id):
      g.assurt(Access_Style.is_valid(access_style_id))
      return Access_Style.lookup_by_id[access_style_id]

   #
   @staticmethod
   def is_valid(access_style_id):
      valid = ((access_style_id in Access_Style.lookup_by_id)
               and (access_style_id != Access_Style.nothingset))
      return valid

# ***


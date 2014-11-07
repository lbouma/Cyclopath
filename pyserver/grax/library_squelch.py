# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

log = g.log.getLogger('libr_squelch')

class Library_Squelch(object):

   # SYNC_ME: Search: Library Squelch IDs.
   # MAYBE: Load these values from the database.
   #        Also the other enum classes.

   squelch_undefined = 0

   squelch_show_in_library = 1
   squelch_searches_only   = 2
   squelch_always_hide     = 3

   lookup = {
      # NOTE: Cannot use Access_Scope.* (not defined yet)
      'undefined':      squelch_undefined,
      'always_show':    squelch_show_in_library,
      'searches_only':  squelch_searches_only,
      'never_show':     squelch_always_hide,
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
   def is_valid(squelch):
      return ((squelch >= Library_Squelch.squelch_show_in_library) 
              and (squelch <= Library_Squelch.squelch_always_hide))

   # ***

# ***


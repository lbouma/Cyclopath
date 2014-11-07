# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This class acts as an enum, representing the values found in the 
# access_scope database table. See the wiki for detailed information:
#
#    http://wiki.grouplens.org/index.php/Cyclopath/Database_Model
#

# Access Scope is only used by the group_ table now.
# What was access scope -- an indication of the totality of all users access
# levels to items -- is now access infer... which also consume style change.

import conf
import g

log = g.log.getLogger('access_scope')

class Access_Scope(object):

   # SYNC_ME: Search: Access Scope IDs.
   # MAYBE: Load these values from the database.
   #        Also the other enum classes.

   undefined = 0

   private = 1
   shared  = 2
   public  = 3

   lookup = {
      # NOTE: Cannot use Access_Scope.* (not defined yet)
      'undefined': undefined,
      'private':   private,
      'shared':    shared,
      'public':    public,
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
   def get_access_scope_id(access_scope_name):
      g.assurt(access_scope_name in Access_Scope.lookup_by_str)
      g.assurt(access_scope_name != 'undefined')
      return Access_Scope.lookup_by_str[access_scope_name]

   #
   @staticmethod
   def get_access_scope_name(access_scope_id):
      g.assurt(Access_Scope.is_valid(access_scope_id))
      return Access_Scope.lookup_by_id[access_scope_id]

   #
   @staticmethod
   def is_valid(scope):
      return ((scope >= Access_Scope.private) 
              and (scope <= Access_Scope.public))

   # *** Convenience methods

   # SIMILAR_TO: Item_User_Access.can_*()

   #
   @staticmethod
   def is_private(scope):
      return (scope == Access_Scope.private)

   #
   @staticmethod
   def is_shared(scope):
      return (scope == Access_Scope.shared)

   #
   @staticmethod
   def is_public(scope):
      return (scope == Access_Scope.public)

   # ***

# ***


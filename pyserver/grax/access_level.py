# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# This class acts as an enum, representing the values found in the 
# access_level database table. See the wiki for detailed information:
#
#    http://wiki.grouplens.org/index.php/Cyclopath/Database_Model
#
# The access levels are loosely ordered from more rights to fewer rights.
#
#    owner  -- can modify item properties and permissions
#    arbiter -- similar to owner, but cannot modify owners' permissions
#    editor -- can edit items
#    viewer -- can view items
#    client -- similar to viewer, but suggestion that item is internal to the
#              geowiki and not a map item, i.e., used by application only
#    denied -- explicit hands off! usually the absense of a GIA record serves
#              this purpose, but if a group loses all their access to an item,
#              it's nice to add a denied GIA record.
#
# You'll notice that you can group the accesses:
#   owner/arbiter/session (change permissions)
#   editor (edit items)
#   viewer/client (view items)
#
#   session (set access to one of the above three, depending on access_style)

# MAYBE: Should this be an enum or dictionary lookup?
# MAYBE: Should this values be auto-loaded from the database?

# CODE_FOLLOWS: flashclient/grax/Access_Level.as

import conf
import g

log = g.log.getLogger('access_level')

class Access_Level(object):

   # SYNC_ME: Search: Access Level IDs.

   invalid = -1

   owner   = 1
   arbiter = 2
   editor  = 3
   viewer  = 4
   client  = 5
   denied  = 6

   lookup = {
      # NOTE: Cannot use Access_Level.* (not defined yet)
      'invalid': invalid,
      'owner'  :   owner,
      'arbiter': arbiter,
      'editor' :  editor,
      'viewer' :  viewer,
      'client' :  client,
      'denied' :  denied,
      }

   lookup_by_str = lookup

   lookup_by_id = {}
   for k,v in lookup_by_str.iteritems():
      lookup_by_id[v] = k

   lookup_by_id_tuples = {
      # NOTE: Cannot use Access_Level.* (not defined yet)
      invalid: ('invalid',  'invalidate', ),
      owner:   ('owner'  ,  'own', ),
      arbiter: ('arbiter',  'arbit', ),
      editor:  ('editor' ,  'edit', ),
      viewer:  ('viewer' ,  'view', ),
      client:  ('client' ,  'client', ),
      denied:  ('denied' ,  'deny', ),
      }

   #
   def __init__(self):
      raise # do not instantiate an object of this class

   #
   @staticmethod
   def get_access_level_id(access_level_name):
      g.assurt(access_level_name in Access_Level.lookup_by_str)
      return Access_Level.lookup_by_str[access_level_name]

   #
   @staticmethod
   def get_access_level_name(access_level_id):
      g.assurt(Access_Level.is_valid(access_level_id))
      return Access_Level.lookup_by_id[access_level_id]

   #
   @staticmethod
   def access_level_id_get(access_level_name_or_id):
      try:
         access_level_id = int(access_level_name_or_id)
      except ValueError:
         try:
            g.assurt(isinstance(access_level_name_or_id, basestring))
            access_level_id = Access_Level.get_access_level_id(
                                       access_level_name_or_id)
         except KeyError:
            # This is a programmer's problem.
            g.assurt(False)
      return access_level_id

   # ***

   #
   @staticmethod
   def best_of(levels):
      level = Access_Level.denied
      for walker in levels:
         if (Access_Level.is_same_or_more_privileged(walker, level)):
            level = walker
            if (level == Access_Level.owner):
               break
      return level

   #
   @staticmethod
   def least_of(levels):
      level = Access_Level.invalid
      for walker in levels:
         if (level == Access_Level.invalid):
            g.assurt(Access_Level.is_valid(walker))
            level = walker
         elif (Access_Level.is_same_or_less_privileged(walker, level)):
            level = walker
            if (level == Access_Level.denied):
               break
      if (level == Access_Level.invalid):
         level = Access_Level.denied
      g.assurt(Access_Level.is_valid(level))
      return level

   #
   @staticmethod
   def is_denied(level):
      g.assurt(Access_Level.is_valid(level))
      return (level == Access_Level.denied)

   ## 

   #
   @staticmethod
   def is_same_or_less_privileged(candidate, subject):
      g.assurt(Access_Level.is_valid(candidate))
      g.assurt(Access_Level.is_valid(subject))
      return (candidate >= subject)

   #
   @staticmethod
   def is_same_or_more_privileged(candidate, subject):
      g.assurt(Access_Level.is_valid(candidate))
      g.assurt(Access_Level.is_valid(subject))
      return (candidate <= subject)

   ##

   #
   @staticmethod
   def is_less_privileged(candidate, subject):
      g.assurt(Access_Level.is_valid(candidate))
      g.assurt(Access_Level.is_valid(subject))
      return (candidate > subject)

   #
   @staticmethod
   def is_more_privileged(candidate, subject):
      g.assurt(Access_Level.is_valid(candidate))
      g.assurt(Access_Level.is_valid(subject))
      return (candidate < subject)

   ##

   #
   @staticmethod
   def is_valid(level):
      return ((level >= Access_Level.owner) 
              and (level <= Access_Level.denied))

   # *** Convenience methods

   # SIMILAR_TO: Item_User_Access.can_*()

   #
   @staticmethod
   def can_own(level):
      # NOTE: Owner is the top level, so no <=, just straight-up ==
      return (level == Access_Level.owner)

   #
   @staticmethod
   def can_arbit(level):
      return ((Access_Level.is_valid(level))
              and (level <= Access_Level.arbiter))

   #
   @staticmethod
   def can_edit(level):
      return ((Access_Level.is_valid(level))
              and (level <= Access_Level.editor))

   #
   @staticmethod
   def can_view(level):
      return ((Access_Level.is_valid(level))
              and (level <= Access_Level.viewer))

   #
   @staticmethod
   def can_client(level):
      return ((Access_Level.is_valid(level))
              and (level <= Access_Level.client))

   #
   # An alias for can_client...
   @staticmethod
   def can_know(level):
      return ((Access_Level.is_valid(level))
              and (level <= Access_Level.client))

   # ***

# ***


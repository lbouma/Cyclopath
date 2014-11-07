# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from grax.access_level import Access_Level
from item import item_base
from item.util import item_factory
from item.util.item_type import Item_Type

log = g.log.getLogger('new_item_pro')

class New_Item_Profile(object):

   #item_type_id = Item_Type.NEW_ITEM_PROFILE
   #item_type_table = 'new_item_profile'
   #item_gwis_abbrev = None
   #child_item_types = None

   __slots__ = (
      'item_class',
      'item_type_id',
      'item_layer',
      'item_stack_id',
      'min_access_id',)

   # *** Constructor

   #
   def __init__(self):
      self.item_class = None
      self.item_type_id = -1
      self.item_layer = None
      self.item_stack_id = 0
      self.min_access_id = Access_Level.invalid

   #
   #def __init__(self, item_class=None, item_type_id=-1, item_layer=None,
   #             item_stack_id=0, min_access_id=Access_Level.invalid):
   #   self.item_class = item_class
   #   self.item_type_id = item_type_id
   #   self.item_layer = item_layer
   #   self.item_stack_id = item_stack_id
   #   self.min_access_id = min_access_id

   # *** Built-in Function definitions

   def __str__(self):
      return ('type: %-17s / stack_id: %-8s / min_acl: %-4s' % (
         (Item_Type.id_to_str(self.item_type_id) 
            if Item_Type.is_id_valid(self.item_type_id) else 'None'),
         self.item_stack_id,
         self.min_access_id,))

   # *** Instance methods

   #
   def item_class_set(self, item_class):
      g.assurt(False) # Is this fcn. used?
      log.verbose3('item_class_set: %s', (type(item_class),))
      self.item_class = item_class
      if (self.item_class is not None):
         g.assurt(isinstance(self.item_class, item_base.One))
         self.item_type_id = self.item_class.item_type_id
         g.assurt(Item_Type.is_id_valid(self.item_type_id))
      else:
         self.item_type_id = 0

   #
   def item_type_id_set(self, item_type_id):
      #log.verbose3('item_type_id_set: item_type_id_set: %s' % (item_type_id,))
      self.item_type_id = item_type_id
      if self.item_type_id:
         item_class_name = Item_Type.id_to_str(self.item_type_id)
         #log.verbose3('item_type_id_set: class_name: %s' % (item_class_name,))
         item_module = item_factory.get_item_module(item_class_name)
         self.item_class = item_module.One
         g.assurt(self.item_class is not None)
      else:
         self.item_class = None

   # *** Public instance methods

   #
   def is_valid(self):
      return (self.item_class is not None)

   #
   def matches(self, item):

      matches = False

      g.assurt(item is not None)
      g.assurt(self.item_class is not None)
      g.assurt(not self.item_layer) # Not implemented

      log.verbose('matches: profile targets: %12s / stack_id: %s / class: %s' 
                  % (Item_Type.id_to_str(self.item_type_id), 
                      self.item_stack_id, self.item_class,))
      log.verbose('matches: looking at type: %12s / stack_id: %s' 
                  % (item.item_type_str(), item.stack_id,))
      #log.verbose3('item.__class__: %s' % item.__class__)
      #log.verbose3('isinstance: %s' % isinstance(item, self.item_class))

      # Check that item type matches and stack ID (if exists) matches.
      # 2013.04.26: We now support hydrating intermediate classes, in which
      #             case check the "real" item type ID.
      if ((((item.real_item_type_id)
             and ((item.real_item_type_id == self.item_type_id)
                  or ((self.item_class.child_item_types)
                      and (item.real_item_type_id
                           in self.item_class.child_item_types))))
            or (isinstance(item, self.item_class)))
          and ((not self.item_stack_id)
               or (item.stack_id == self.item_stack_id))):
         # The item class and maybe the stack ID match. If the policy
         # specifies an access control level limit, check the user
         # passes.
         # NOTE: The access level check only applies to the attc and/or
         #       feat of an item being linked (so item is an attc or feat
         #       that already exists, and we're checking that the user has
         #       rights to create a link on self item).
         if (Access_Level.is_valid(self.min_access_id)):
            if (Access_Level.is_same_or_more_privileged(
                  item.access_level_id, self.min_access_id)):
               log.verbose('matches: passed: linked attc or feat ok')
               matches = True
            else:
               log.verbose('matches: denied: innapropriate access level')
               log.verbose('  >> item.access_level_id:' 
                           % (item.access_level_id,))
               log.verbose('  >> self.min_access_id:' % (self.min_access_id,))
         else:
            log.verbose3('matches: passed: item ok')
            matches = True
      else:
         log.verbose('matches: ignored: profile does not apply to item')

      return matches


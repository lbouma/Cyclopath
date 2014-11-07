# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# FIXME?: CODE_FOLLOWS: flashclient/grax/Grac_Error.as

import conf
import g

from item import item_base
from item.util.item_type import Item_Type

__all__ = ['Grac_Error']

log = g.log.getLogger('grac_error')

class Grac_Error(item_base.One):

   # Base class overrides

   item_type_id = Item_Type.GRAC_ERROR
   item_type_table = 'grac_error'
   item_gwis_abbrev = 'gerr'
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv
      ('client_id',           None,   True),
      ('error_id',            None,   True),
      ('error_name',          None,   True),
      ('err_count',           None,   True),
      ('err_hints',           None,   True),
      ]
   attr_defns = item_base.One.attr_defns + local_defns
   psql_defns = attr_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(psql_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # SYNC_ME: Search: Grac Error IDs.

   no_error          =  0

   semi_protected    =  1
   fully_banned      =  2
   user_is_banned    =  3
   permission_denied =  4
   revision_conflict =  5
   unknown_item      =  6
   bad_item_type     =  7
   invalid_item      =  8
   duplicate_item    =  9

   lookup = {
      # NOTE: Cannot use Grac_Error.* (not defined yet)
      'no_error':          no_error,
      'semi_protected':    semi_protected,
      'fully_banned':      fully_banned,
      'user_is_banned':    user_is_banned,
      'permission_denied': permission_denied,
      'revision_conflict': revision_conflict,
      'unknown_item':      unknown_item,
      'bad_item_type':     bad_item_type,
      'invalid_item':      invalid_item,
      'duplicate_item':    duplicate_item,
      }

   lookup_by_str = lookup

   lookup_by_id = {}
   for k,v in lookup_by_str.iteritems():
      lookup_by_id[v] = k

   lookup_by_id_tuples = {
      # NOTE: Cannot use Grac_Error.* (not defined yet)
      no_error:          ('no_error',           'no error', ),
      semi_protected:    ('semi_protected',     'semi protected', ),
      fully_banned:      ('fully_banned',       'fully banned', ),
      user_is_banned:    ('user_is_banned',     'user is banned', ),
      permission_denied: ('permission_denied',  'permission denied', ),
      revision_conflict: ('revision_conflict',  'revision conflict', ),
      unknown_item:      ('unknown_item',       'unknown item', ),
      bad_item_type:     ('bad_item_type',      'bad item type', ),
      invalid_item:      ('invalid_item',       'invalid item', ),
      duplicate_item:    ('duplicate_item',     'duplicate item', ),
      }

   #
   def __init__(self, client_id, error_id):
      item_base.One.__init__(self)
      if client_id is None:
         # EXPLAIN: When is client_id None?
         self.client_id = 0
      else:
         self.client_id = client_id
      self.error_set(error_id)
      self.err_count = 0
      self.err_hints = dict()

   # 
   def __str__(self):
      return (
         'Grac Error / Client ID: %d / Error: %s (%d) / Count: %d / Hints: %s'
         % (self.client_id, Grac_Error.get_grac_error_name(self.error_id), 
            self.error_id, self.err_count, self.err_hints,))

   #
   def error_set(self, error_id):
      self.error_id = error_id
      self.error_name = Grac_Error.get_grac_error_name(error_id)

   #
   def from_gml(self, qb, elem):
      g.assurt(False) # Not applicable

   #
   def hints_add(self, hint_key, hint_value=None):
      self.err_count = self.err_count + 1
      if not hint_key in self.err_hints:
         self.err_hints[hint_key] = set()
      if hint_value is not None:
         self.err_hints[hint_key].add(hint_value)

   #
   def save_core(self, qb):
      g.assurt(False) # Not applicable

   #
   def save_insert(self, qb):
      g.assurt(False) # Not applicable

   #
   @staticmethod
   def get_grac_error_id(grac_error_name):
      g.assurt(grac_error_name in Grac_Error.lookup_by_str)
      return Grac_Error.lookup_by_str[grac_error_name]

   #
   @staticmethod
   def get_grac_error_name(grac_error_id):
      #g.assurt(Grac_Error.is_valid(grac_error_id))
      g.assurt(grac_error_id in Grac_Error.lookup_by_id)
      return Grac_Error.lookup_by_id[grac_error_id]

   # ***

# ***


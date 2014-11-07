# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# CODE_COUSINS: flashclient/items/gracs/Group.py
#               pyserver/item/grac/group.py

# BUG 2077: Implement client-side group management

import conf
import g

import psycopg2

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import grac_record
from item import item_base
from item import item_versioned
from item.grac import groupy_base
from item.util.item_type import Item_Type

__all__ = ['One', 'Many']

log = g.log.getLogger('group')

class One(groupy_base.One):

   item_type_id = Item_Type.GROUP
   item_type_table = 'group_'
   item_gwis_abbrev = 'gp'
   child_item_types = None

# BUG nnnn: Where do private groups get created for new users??????

   local_defns = [
      # py/psql name,         deft, send?,  pkey?,  pytyp,  reqv
      # FIXME: 2012.05.11: Now deriving from groupy_base, which means group_id
      # and group_name are accepted... we could use them to set stack_id...
      ('description',         None,  True,  False,    str,     2),
      ('access_scope_id',     None, False,  False,    int,     2),
      ]
   attr_defns = groupy_base.One.attr_defns + local_defns
   psql_defns = groupy_base.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      groupy_base.One.__init__(self, qb, row, req, copy_from)

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      groupy_base.One.from_gml(self, qb, elem)
      # Resolve the stack_id from a group_name
      self.from_gml_group_id(qb, required=False)

   # *** Saving to the Database

   #
   def group_ids_add_to(self, group_ids, rid):
      # FIXME: Care about rid?
      # See note in group_membership: if admin doing lots of work, changenote
      # might not be meaningful, and may convey more info. than group should
      # see... though probably not a big deal: changenotes should probably be
      # written like public can see them.
      group_ids.add(self.stack_id)

   #
   def save_core(self, qb):
      groupy_base.One.save_core(self, qb)
      # Save to the 'group' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def version_finalize_preset_is_okay(self):
      return True

   # ***

class Many(groupy_base.Many):

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      groupy_base.Many.__init__(self)

   # *** Convenience routines

   #
   @staticmethod
   def public_group_id(db):
      return groupy_base.Many.public_group_id(db)

   #
   @staticmethod
   def session_group_id(db):
      return groupy_base.Many.session_group_id(db)

   #
   @staticmethod
   def stealth_group_id(db):
      return groupy_base.Many.stealth_group_id(db)

   #
   @staticmethod
   def cp_group_private_id(db, username):
      return groupy_base.Many.cp_group_private_id(db, username)

   #
   @staticmethod
   def cp_group_shared_id(db, group_name):
      return groupy_base.Many.cp_group_shared_id(db, group_name)

   #
   @staticmethod
   def group_id_from_group_name(db, group_name, restrict_scope=None):
      return groupy_base.Many.group_id_from_group_name(db, group_name, 
                                                       restrict_scope)

   # *** Public interface

   #
   @staticmethod
   def group_resolve(db, group_name_or_id, restrict_scope=None):
      group_id = None
      group_name = None
      if group_name_or_id is not None:
         try:
            group_id = int(group_name_or_id)
            if group_id == 0:
               group_id = Many.public_group_id(db)
            g.assurt(group_id > 0)
            try:
               group_name = Many.group_name_from_group_id(db, group_id, 
                                                          restrict_scope)
            except GWIS_Error, e:
               g.assurt(False)
               pass
            except GWIS_Warning, e:
               pass
         except ValueError:
            if ((isinstance(group_name_or_id, basestring)) 
                and (group_name_or_id != '')):
               group_name = group_name_or_id
               try:
                  # raises on not matched, or > 1 match
                  group_id = Many.group_id_from_group_name(db, 
                                    group_name, restrict_scope)
               except GWIS_Error, e:
                  g.assurt(False)
                  pass
               except GWIS_Warning, e:
                  # Not found or not permitted.
                  group_name = None
                  pass
            else:
               log.error('group_resolve: group not int or string: %s'
                         % (group_name_or_id,))
               g.assurt(False)
      return group_id, group_name

   #
   @staticmethod
   def group_name_from_group_id(db, group_id, restrict_scope=None):
      group_name = ''
      try:
         where_scope = ""
         if restrict_scope is not None:
            where_scope = (
               "AND access_scope_id = %d"
               % Access_Scope.get_access_scope_id(restrict_scope),)
         group_name = db.sql(
            """
            SELECT 
               grp.name AS group_name
            FROM 
               group_ AS grp
            WHERE 
               grp.stack_id = %d
               %s
            """ % (group_id, where_scope,))[0]['group_name']
         if not group_name:
            g.assurt(False) # All groups have names, so IndexError is raised.
            raise GWIS_Warning('Group ID "%d" not recognized.' % (group_id,))
      except IndexError:
         raise GWIS_Warning('Group ID "%d" is not recognized.' % (group_id,))
      except KeyError:
         g.assurt(False) # I [lb] think the error will be IndexError
         raise GWIS_Warning('Group ID "%d" is not recognized.' % (group_id,))
      except psycopg2.ProgrammingError, e:
         g.assurt(False) # Should not occur
      return group_name

   # *** Query Builder routines

   # FIXME: Implement search_by_context?

   # ***

# ***


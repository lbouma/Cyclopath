# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_style import Access_Style
from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from item import grac_record
from item import item_base
from item import item_versioned
from util_ import misc

__all__ = ['One', 'Many']

log = g.log.getLogger('groupy_base')

class One(grac_record.One):

   item_type_id = None # Abstract
   item_type_table = None
   item_gwis_abbrev = None
   child_item_types = None

   local_defns = [
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      # These are technically required for gm and gia, but we don't check 
      # until from_gml_group_id is called.
      ('group_id',            None,   True,   True,    int,     0, 'gpid',),
      ('group_name',          None,   True,   None,    str,     0,),
      ]
   attr_defns = grac_record.One.attr_defns + local_defns
   psql_defns = grac_record.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      grac_record.One.__init__(self, qb, row, req, copy_from)

   # ***

   #
   def from_gml_group_id(self, qb, required=True):
      self.group_id = Many.from_gml_group_id_(qb.db,
                                              self.group_id, 
                                              self.group_name,
                                              required)
      g.assurt((not required) or (self.group_id > 0))

   #
   def save_core(self, qb):
      # Avoid not-null constraints in item_stack by setting unused attrs.
      self.access_style_id = Access_Style.all_denied
      item_versioned.One.save_core(self, qb)

   #
   def save_core_pre_save_get_acs(self, qb):
      # This is redundant since we set this is save_core. That is, this fcn. is
      # never called. But we still want to override the base class, to be
      # thorough.
      return Access_Style.all_denied

   # ***

class Many(grac_record.Many):

   one_class = One

   __slots__ = ()

   public_group_id_ = None
   session_group_id_ = None
   stealth_group_id_ = None

   # *** Constructor

   def __init__(self):
      grac_record.Many.__init__(self)

   # *** Public interface

   # Get the public group ID.
   # EXPLAIN: How is this different than the private _user_anon_instance group?
   @staticmethod
   def public_group_id(db):
      if (Many.public_group_id_ is None):
         # Get the group ID of the public group.
         Many.public_group_id_ = int(db.sql(
            "SELECT cp_group_public_id() AS grp_id")[0]['grp_id'])
         #log.debug('Many.public_group_id_ = %d' % (Many.public_group_id_,))
         g.assurt(Many.public_group_id_ > 0)
      return Many.public_group_id_


   #
   @staticmethod
   def session_group_id(db):
      if (Many.session_group_id_ is None):
         # Get the group ID of the stealth group.
         was_dont_fetchall = db.dont_fetchall
         db.dont_fetchall = False
         rows = db.sql("SELECT cp_group_session_id() AS grp_id")
         g.assurt(len(rows) == 1)
         Many.session_group_id_ = int(rows[0]['grp_id'])
         #log.debug('Many.session_group_id_ = %d' % (Many.session_group_id_,))
         g.assurt(Many.session_group_id_ > 0)
         db.dont_fetchall = was_dont_fetchall
      return Many.session_group_id_

   #
   # This gets the stack ID of the 'Stealth-Secret Group'.
   @staticmethod
   def stealth_group_id(db):
      if (Many.stealth_group_id_ is None):
         # Get the group ID of the stealth group.
         was_dont_fetchall = db.dont_fetchall
         db.dont_fetchall = False
         rows = db.sql("SELECT cp_group_stealth_id() AS grp_id")
         g.assurt(len(rows) == 1)
         Many.stealth_group_id_ = int(rows[0]['grp_id'])
         #log.debug('Many.stealth_group_id_ = %d' % (Many.stealth_group_id_,))
         g.assurt(Many.stealth_group_id_ > 0)
         db.dont_fetchall = was_dont_fetchall
      return Many.stealth_group_id_

   #
   @staticmethod
   def cp_group_private_id(db, username):
      rows = db.sql(
         """
         SELECT 
            grp.stack_id AS group_id
         FROM 
            user_ AS usr
         JOIN 
            group_membership AS gmp
               ON gmp.user_id = usr.id
         JOIN 
            group_ AS grp
               ON grp.stack_id = gmp.group_id
         WHERE
                usr.username = %s 
            AND grp.access_scope_id = %s
            AND gmp.access_level_id < %s
            AND gmp.valid_until_rid = %s
            AND gmp.deleted IS FALSE
         """, (username,
               Access_Scope.private,
               Access_Level.denied,
               conf.rid_inf,))
      if rows:
         g.assurt(len(rows) == 1)
         group_id = int(rows[0]['group_id'])
         g.assurt(group_id > 0)
      else:
         group_id = None
      return group_id

   #
   @staticmethod
   def cp_group_shared_id(db, group_name):
      rows = db.sql(
         """
         SELECT 
            grp.stack_id AS group_id 
         FROM 
            group_ AS grp
         WHERE 
                grp.name = %s
            AND grp.access_scope_id = %s
            AND grp.valid_until_rid = %s
            AND grp.deleted IS FALSE
         """, (group_name,
               Access_Scope.shared,
               conf.rid_inf,))
      if rows:
         if len(rows) != 1:
            log.error('cp_group_shared_id: found %d rows for "%s"'
                      % (len(rows), group_name,))
            g.assurt(False)
         group_id = int(rows[0]['group_id'])
         g.assurt(group_id > 0)
      else:
         group_id = None
      return group_id

   #
   @staticmethod
   def from_gml_group_id_(db, grp_id, grp_nm, required=True):
      group_id = None
      if bool(grp_id and grp_nm):
         raise GWIS_Error(
            'Attr. confusions: Please specify just "group_id" or "group_name"')
      elif (not grp_id) and (not grp_nm):
         if required:
            raise GWIS_Error(
               'Missing mandatory attr: "group_id" or "group_name"')
      elif not grp_id:
         group_id = Many.group_id_from_group_name(db, grp_nm)
         log.debug('from_gml: resolved group_id %d from group_name "%s".' 
                   % (group_id, grp_nm,))
      return group_id

   #
   @staticmethod
   def group_id_from_group_name(db, group_name, restrict_scope=None):
      group_id = None
      #
      if (((restrict_scope is None) or (restrict_scope == Access_Scope.shared))
          and (group_id is None)):
         group_id = Many.cp_group_shared_id(db, group_name)
         if group_id is None:
            # Well, it's not a shared group. If the user asked for it, complain
            if restrict_scope == Access_Scope.shared:
               raise GWIS_Warning('No shared group for "%s"' % (group_name,))
      #
      if (((restrict_scope is None) 
           or (restrict_scope == Access_Scope.private))
          and (group_id is None)):
         group_id = Many.cp_group_private_id(db, group_name)
         if group_id is None:
            if restrict_scope == Access_Scope.private:
               raise GWIS_Warning('No private group for "%s"' % (username,))
      #
      if (((restrict_scope is None) 
           or (restrict_scope == Access_Scope.public))
          and (group_id is None)
          # MAYBE: Is this okay? MAGIC_NAME: 'Public' user group.
          and (group_name == 'Public')):
         group_id = Many.public_group_id(db)
      #
      # MAYBE: Do we care about Many.stealth_group_id(db)?
      #
      if not group_id:
         raise GWIS_Warning('Named group not found or not permitted: "%s"' 
                            % (group_name,))
      return group_id

   # ***

# ***


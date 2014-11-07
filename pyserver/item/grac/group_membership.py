# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from grax.access_level import Access_Level
from grax.user import User
from gwis.exception.gwis_error import GWIS_Error
from item import grac_record
from item import item_base
from item import item_versioned
from item.grac import group
from item.grac import groupy_base
from item.util import revision
from item.util.item_type import Item_Type
from util_ import gml

__all__ = ['One', 'Many']

log = g.log.getLogger('group_membership')

class One(groupy_base.One):

   item_type_id = Item_Type.GROUP_MEMBERSHIP
   item_type_table = 'group_membership'
   item_gwis_abbrev = 'gmp'
   child_item_types = None

   local_defns = [
      # FIXME: I think pkey? is really notnull?
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      # Group Membership details
      ('access_level_id',     None,   True,   True,    int,     2, 'alid'),
      ('opt_out',             None,   True,  False,   bool,     1),
      # User details
      # FIXME:  User ID or name? Is using ID bad? Group ID or, is group name
      #         unique, too? I don't know... maybe Group Description is really
      #         Group Friendly Name?
      ('user_id',             None,  False,   True,    int,     0),
      ('username',            None,   True,   True,    str,     0),
      # Group details
      # NOTE: 'group_desc' is at group_.description.
      ('group_desc',          None,   True),
      # NOTE: 'group_scope' is at group_.access_scope_id.
      ('group_scope',         None,   True),
      ]
   attr_defns = groupy_base.One.attr_defns + local_defns
   psql_defns = groupy_base.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      groupy_base.One.__init__(self, qb, row, req, copy_from)

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      groupy_base.One.from_gml(self, qb, elem)
      # Resolve the user_id
      if self.user_id and self.username:
         raise GWIS_Error(
            'Attr. confusions: Please specify just "user_id" or "username".')
      elif (not self.user_id) and (not self.username):
         raise GWIS_Error('Missing mandatory attr: "user_id" or "username".')
      elif not self.user_id:
         # FIXME: Should we have a qb passed in, e.g., qb.db and qb.username?
         self.user_id = User.user_id_from_username(self.req.db, 
                                                   self.username)
         log.debug('from_gml: resolved user_id %d from username "%s".' 
                   % (self.user_id, self.username,))
      # Resolve the group_id
      self.from_gml_group_id(qb)

   # *** Saving to the Database

   #
   def group_ids_add_to(self, group_ids, rid):
      # FIXME: Care about rid?
      # I'm [lb isn't] convinced this is cool... mostly, if admin is doing lots
      # of changes, then admin should know changenote is readable by all
      # affected.
      group_ids.add(self.group_id)

   #
   # BUG nnnn: This adds duplicates records...
   # FIXME: Add group_name to group_membership table, for human benefit.
   #        But that means you gotta UPDATE gm when group_ changes.
   def save_core(self, qb):
      groupy_base.One.save_core(self, qb)
      # Save to the 'group_membership' table
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

   # *** Query Builder routines

   # This is the first call that flashclient makes. If the user is not logged
   # in, it simply returns the group ID of the public group. Otherwise, it
   # returns all of the groups IDs (and associated info) of the groups to which
   # the user belongs.
   def sql_context_user(self, qb, *args, **kwargs):

      g.assurt(isinstance(qb.revision, revision.Current)
            or isinstance(qb.revision, revision.Historic))

      sql_user = (
         """
         SELECT

            gmp.stack_id
            , gmp.version
            , gmp.access_level_id
            , gmp.opt_out AS opt_out

            , grp.stack_id AS group_id
            , grp.version
            , grp.name AS group_name
            , grp.description AS group_desc
            , grp.access_scope_id AS group_scope
            , GREATEST(gmp.valid_start_rid, grp.valid_start_rid) 
                 AS valid_start_rid
            , LEAST(gmp.valid_until_rid, grp.valid_until_rid) 
                 AS valid_until_rid

         FROM

            user_ AS u
            JOIN group_membership AS gmp
               ON (u.id = gmp.user_id)
            JOIN group_ AS grp
               ON (gmp.group_id = grp.stack_id)

         WHERE

            u.username = %s
            AND %s -- group_membership revision
            AND %s -- group revision
            AND gmp.access_level_id <= %d

         GROUP BY

            gmp.stack_id
            , gmp.version
            , gmp.access_level_id
            , gmp.opt_out

            , grp.stack_id
            , grp.version
            , grp.name
            , grp.description
            , grp.access_scope_id

            , gmp.valid_start_rid
            , grp.valid_start_rid
            , gmp.valid_until_rid
            , grp.valid_until_rid

         """ % (
            # WHERE
            qb.db.quoted(qb.username),    # Given a certain user...
            qb.revision.as_sql_where_strict('gmp'),
            qb.revision.as_sql_where_strict('grp'),
            Access_Level.client,          # ...with at least client access
            ))

      # The flashclient needs to know the stealth secret stack ID, so it can
      # locate the corresponding group_item_access records.
      # 2013.12.20: Also add the Session ID Group.

      # NOTE: The Stealth-Secret Group and Session ID Group do not have
      #       group_membership records, since the server uses these
      #       group IDs specially. (And if we wired a group_membership
      #       to, e.g., the anon group, then we'd wrongfully give everyone
      #       defacto access to these groups' permissions, rather than
      #       verifying the session ID or stealth secret to give access).
      #       As such, we return NULL values for the group_membership
      #       attributes, like stack_id, version, access_level_id, and
      #       opt_out. The client will remember the group IDs for these
      #       special groups, but it won't create group_membership objects.

      sql_stealth = (
         """
         SELECT
            -- The first parms. are for the non-existant group_membership.
            NULL AS stack_id
            , NULL AS version
            , NULL AS access_level_id
            , NULL AS opt_out
            -- The group_ record values.
            , grp.stack_id AS group_id
            , grp.version
            , grp.name AS group_name
            , grp.description AS group_desc
            , grp.access_scope_id AS group_scope
            -- Here again we fake like there's a group_membership record.
            , 1 AS valid_start_rid
            , %d AS valid_until_rid
         FROM
            group_ AS grp
         WHERE
            grp.stack_id IN (%d, %d)
         """ % (
            conf.rid_inf,
            # In sql, see: cp_group_stealth_id()
            # MEH: We could just return all group_ records
            #      where access_scope_id = cp_access_scope_id('public')
            #      but we don't plan on making more of these records.
            group.Many.session_group_id(qb.db),
            group.Many.stealth_group_id(qb.db),
            ))

      sql = ("%s UNION (%s)" % (sql_user, sql_stealth,))

      return sql

   #
   def search_by_group_id(self, qb, group_stack_id):

      # Note that the group classes don't use local_defns and have a common
      # SQL fcn like item_user_access provides. Most of the group class SQL
      # fetches are pretty custom, though.

      group_memberships_sql = (
         """
         SELECT
              gmp.stack_id
            , gmp.version
            , gmp.deleted
            , gmp.access_level_id
            , gmp.opt_out AS opt_out
            , gmp.username
            , gmp.user_id
            , grp.stack_id AS group_id
            , grp.name AS group_name
            , grp.description AS group_desc
            , grp.access_scope_id AS group_scope
            , GREATEST(gmp.valid_start_rid, grp.valid_start_rid) 
                 AS valid_start_rid
            , LEAST(gmp.valid_until_rid, grp.valid_until_rid) 
                 AS valid_until_rid
         FROM
            group_membership AS gmp
            JOIN group_ AS grp
               ON (grp.stack_id = gmp.group_id)
            JOIN user_ AS u
               ON (u.id = gmp.user_id)
         WHERE
            grp.stack_id = %d
            AND %s -- group_membership revision
            AND %s -- group revision
         /*
         GROUP BY
            gmp.stack_id
            , gmp.version
            , gmp.access_level_id
            , gmp.opt_out
            --
            , grp.stack_id
            , grp.version
            , grp.name
            , grp.description
            , grp.access_scope_id
            --
            , gmp.valid_start_rid
            , grp.valid_start_rid
            , gmp.valid_until_rid
            , grp.valid_until_rid
         */
         """ % (group_stack_id,
                qb.revision.as_sql_where_strict('gmp'),
                qb.revision.as_sql_where_strict('grp'),))

      self.sql_search(qb, group_memberships_sql)

   # ***

# ***


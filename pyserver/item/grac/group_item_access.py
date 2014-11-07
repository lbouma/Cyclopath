# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from lxml import etree
import uuid

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from item import grac_record
from item import item_base
from item import item_versioned
from item.grac import groupy_base
from item.util.item_type import Item_Type
from util_ import gml

__all__ = ['One', 'Many']

log = g.log.getLogger('group_item_access')

class One(groupy_base.One):

   # append_gml needs this set:
   item_type_id = Item_Type.GROUP_ITEM_ACCESS
   # and we're not used to save data, so leave the table None.
   item_type_table = 'group_item_access'
   # the abbrev. says how we can name the outgoing XML elements.
   item_gwis_abbrev = 'gia'
   child_item_types = None

   local_defns = [

      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev

      # SYNC_ME: If you add items to this list, you have to edit
      # item_user_access.save_related_save_groups_access's qb.db.insert
      # to make sure your new columns get saved.

      # NOTE: group_id is in the base class, groupy_base.
      ('item_id',             None,  False,   True,       int, None),
      # NOTE: valid_start_id is in the base class, item_versioned, but
      #       in group_item_access it's part of the primary key.
      ('valid_start_rid',     None,  False,   True,       int,    3),
      # Skipping: acl_grouping isn't needed; it's just in item_user_access.
      # 2014.03.18: acl_grouping is needed for hausdorff_import.
      ('acl_grouping',        None,  False,   True,       int,    2, 'aclg'),

      ('access_level_id',     None,   True,  False,       int,    2, 'alid'),

      # FIXME: Implement session_id. Use self.req.client.session_id, after
      #        verifying the session_id and client IP.
      # If session ID is set, then access_level_id reflects the access level
      # only if the client provides a matching session ID.
      # FIXME: The route table still has a session_id TEXT param.
      ('session_id',          None,  False,  False, uuid.UUID, None, ),

      # Override item_versioned's defn of branch_id.
      ('branch_id',           None,  False,  False,       int, None, 'brid'),

      # We don't care about the other values in group_item_access, which are
      # filled in by item_user_access when it saves group_item_access items.
      # We just care about a group's access to an item.
      # NOTE: valid_start_rid and valid_until_rid are in item_versioned.
      #       item_user_access uses them to see if the GIA record was loaded
      #       from the database or is new from the user.
      # Oops. This name conflicts with the item class static member of same
      # name. But I don't think we really care about the following, anyway.
      # Really we just care about the group ID, item ID, and access level.
      ##('item_type_id',        None,  False, False),
      #('item_type_id_',       None,  False, False),
      ##('item_layer_id',       None,  False, False), # deprecated
      ('link_lhs_type_id',    None,  False, False),
      ('link_rhs_type_id',    None,  False, False),
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
   def append_gml(self, elem, need_digest, new=None, extra_attrs=None, 
                        include_input_only_attrs=False):
      g.assurt(new is None)
      new = etree.Element(One.item_gwis_abbrev)
      return groupy_base.One.append_gml(self, elem, need_digest, new,
                                              extra_attrs,
                                              include_input_only_attrs)

   #
   def from_gml(self, qb, elem, valid_group_required=True):
      groupy_base.One.from_gml(self, qb, elem)
      # Resolve the group_id.
      self.from_gml_group_id(qb, required=valid_group_required)

   # *** Saving to the Database

   #
   def group_ids_add_to(self, group_ids, rid):
      # FIXME: Care about rid?
      g.assurt(False) # Used?
      group_ids.add(self.group_id)

   #
   def save_core(self, qb):
      # NOTE: GIA records do not save themselves; see
      #       item_user_access.One.save_related_save_groups_access
      g.assurt(False)
      groupy_base.One.save_core(self, qb)

   # *** Developer interface

   def __str__(self):
      return self.to_string()

   #
   def to_string(self):
      return (
         'gia: %s.%s / itm id: %s / grp sid: %s / acl: %s / sssd: %s / r:%s:%s'
         % (self.stack_id,
            self.version,
            self.item_id,
            self.group_id,
            self.access_level_id,
            self.session_id,
            self.valid_start_rid,
            self.valid_until_rid,))

   # ***

   #
   def validate_access_loose(self, qb, the_item):

      # COUPLING: Does this fcn. belong here or in grac_mgr?
      #           [lb] feels like he could go either way....
      #           And this fcn. is only used by items with
      #           'permissive' rights, which is just branches.

      # 2012.10.05: This type of access change is only supported for branches,
      #             though this could change in the future.
      # Cannot import branch (circular import loop):
      #  g.assurt(isinstance(the_item, branch.One))

      access_ok = False

      log.debug('validate_access_loose: grp_id: %d / acl_id: %d'
                % (self.group_id, self.access_level_id,))

      if ((not the_item.can_arbit())
          or (self.access_level_id < the_item.access_level_id)):
         # The user must have arbit/owner access and cannot set access 
         # better than their own.
         # MAYBE: The grac error specifies the item's stack ID but doesn't
         # specify which GIA record is being rejected.
         log.warning('validate_access_loose: !arb or <acl: %s:%s:%s / %s'
            % (self.group_id, grp_nm, self.access_level_id, str(the_item),))
         qb.grac_mgr.grac_errors_add(the_item.stack_id, 
                                     Grac_Error.permission_denied,
                                     '/item/groups_access')
      elif ((not the_item.can_own())
            and (self.access_level_id <= the_item.access_level_id)):
      # ct: elif ((not the_item.can_own())
      #           and (self.access_level_id <= Access_Level.arbiter)):
         # Arbiters can only change editor access (i.e., to denied, or 
         # vice versa); they cannot make other arbiters.
         # BUG nnnn: This check should be replaced by branch_roles, i.e., 
         #           owner/arbiter is silly, too constrictive, and should 
         #           be replaced by a roles-driven implementation. (The 
         #           arbiter and owner permissions were originally
         #           meant for managing access to individual items (i.e.,
         #           not branches), but during development it because
         #           obvious that changing item permissions should be
         #           restricted to the donate/clone approach and we should
         #           use branch_roles to define "owner" and "arbiter" (or
         #           "moderator") roles, i.e., roles specify what actions a
         #           user can perform to types of items.)
         log.warning('validate_access_loose: !owner and acl-arb: %s:%s:%s / %s'
            % (self.group_id, grp_nm, self.access_level_id, str(the_item),))
         qb.grac_mgr.grac_errors_add(the_item.stack_id, 
                                     Grac_Error.permission_denied,
                                     '/item/groups_access')
      elif self.group_id == qb.user_group_id:
         # Users cannot modify their private permissions. That is, if a user
         # wants to make something private public, or wants to make
         # something public private, they should use the donate or cloner
         # features, respectively.
         log.warning(
            'validate_access_loose: not not private group: %s:%s:%s / %s'
            % (self.group_id, grp_nm, self.access_level_id, str(the_item),))
         qb.grac_mgr.grac_errors_add(the_item.stack_id, 
                                     Grac_Error.permission_denied,
                                     '/item/groups_access')
      else:
         access_ok = True

      return access_ok

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, grac, item_type_id):

      g.assurt(grac.group_id > 0)
      g.assurt(grac.item_id > 0)
      g.assurt(grac.branch_id > 0)
      g.assurt(grac.stack_id > 0)
      g.assurt(grac.version > 0)
      g.assurt(grac.acl_grouping > 0)
      g.assurt(grac.valid_start_rid > 0)
      g.assurt(grac.valid_until_rid > 0)
      g.assurt(Access_Level.is_valid(grac.access_level_id))
      g.assurt(Item_Type.is_id_valid(item_type_id))

      insert_expr = (
         """(%d, %d, %d, %d, %d,
             %d, %d, %d, %s, %s,
             %d, %d, %s, %s, %s)
         """
         % (
            # Interpolations 1-5
            grac.group_id,
            grac.item_id,
            grac.branch_id,
            grac.stack_id,
            grac.version,

            # Interpolations 6-10
            grac.acl_grouping,
            grac.valid_start_rid,
            grac.valid_until_rid,
            "TRUE" if grac.deleted else "FALSE",
            "TRUE" if grac.reverted else "FALSE",

            # Interpolations 11-15
            grac.access_level_id,
            item_type_id,
            grac.link_lhs_type_id or "NULL",
            grac.link_rhs_type_id or "NULL",
            qb.db.quoted(grac.name),

            # Skipping: grac.session_id,
            ))

      return insert_expr

   # ***

# ***

class Many(groupy_base.Many):

   one_class = One

   __slots__ = ()

   # *** Constructor

   def __init__(self):
      groupy_base.Many.__init__(self)

   # *** Query Builder routines

# FIXME: When user activates group tab in client, lazy load this:
   #
   def sql_context_group(self, qb, *args, **kwargs):
# FIXME: Make sure user is item owner.
      # We could restrict groups user sees to just groups to which user is
      # member, but if user owns the item, they should be able to see all
      # group_item_access records. Rights?
      # Well, in the least, we only return group IDs, so even if we return all
      # GIAs for an item and user is not part of all the groups, is sending
      # them the group ID really that bad?
      return self.sql_context_item(qb, args, kwargs)

   #
   def sql_context_item(self, qb, *args, **kwargs):
      log.verbose4('sql_context_item: qb.filters: %s', (str(qb.filters),))
      stack_id = int(qb.filters.only_stack_ids)
      # The item may be in a parent branch, so we need the hierarchy, but we
      # only want the set of records for the leafiest branch in which we can
      # find the item. But because of the way this is called, we just order by
      # and leave it up to the client to filter the results.
      #
      # This fcn is called by item_user_access to load an item's groups_access.
      #
      # The branch_hier_where will narrow the fetch to the branch and revision
      # we want, but some items are revisionless and others use acl_grouping,
      # so we order by, which just gets the latest record for a revision.
      #
      # MAYBE: Support fetching a particular version and maybe acl_grouping
      #        for a particular revision?
      # Argh, I broke this!
      # r30983 | landonb | 2013-12-27 21:01:23 -0600 (Fri, 27 Dec 2013)
      # Repaired: r31671 | 2014-04-27... oops! Do not DISTINCT ON, 'cause
      # then you're only fetching one record, dummy!
      sql = (
         """
         SELECT
              gia.stack_id
            , gia.version
            , gia.acl_grouping
            , gia.item_id
            , gia.group_id
            , gia.branch_id
            , gia.access_level_id
            , gia.session_id
            , gia.valid_start_rid
            , gia.valid_until_rid
            , gia.deleted
            , gia.reverted
            , gia.item_type_id
            , gia.link_lhs_type_id
            , gia.link_rhs_type_id
            , gia.name
            --, gia.tsvect_name
         FROM 
            group_item_access AS gia
         WHERE
            gia.stack_id = %d
            AND %s
         ORDER BY 
            gia.stack_id ASC
            , gia.version DESC
            , gia.acl_grouping DESC
         """ % (stack_id,
                qb.branch_hier_where('gia'),))
      return sql

   # 
   # The client calls this to determine a user's access to an item.
   def sql_context_user(self, qb, *args, **kwargs):

      # 2012.09.25: This fcn. is not called by flashclient.

      # 2013.09.11: This command will call this fcn:
      #
      #   ./ccp.py -U landonb --no-password \
      #     -r -t group_item_access -x user -I 2538545
      #
      # But flashclient uses the 'item' context, not the user's. Hrm?
      #
      # Using the 'user' context:
      #
      # item id: None / grp sid: None / acl: 2 / sssd: None / r:None:None
      #
      # Using the 'item' context:
      #
      # item id: 1253469 / grp sid: 2511827 / acl: 2 / sssd: None / r:None:None
      #
      # So maybe the 'user' context is... not well defined.

      stack_id = int(qb.filters.only_stack_ids)

      # MAYBE: The caller does not pass args or kwargs.
      #        See item/grac_record.py::search_get_sql_grac
      #        And none of the other sql_context_user fcns.
      #        use args or kwargs. Maybe nix the two params?
      # WRONG: gids_where = self.sql_group_ids(kwargs['gids'])
      gids_where = self.sql_group_ids(qb.revision.gids)

# FIXME: This is so weird. What's up will all the FIRSTs?
#        thankfully, no one calls this fcn. Can we delete it? Please?
# FIXME: Do we need an ORDER BY? How 'bout the FIRST(gia.acl_grouping)?
      g.assurt(False) # Deprecated.

      sql = (
         """
         SELECT
            FIRST(gia.stack_id)
            , FIRST(gia.version)
            , FIRST(gia.item_id)
            , FIRST(gia.branch_id)
            -- ?: , FIRST(gia.acl_grouping)
            , MIN(gia.access_level_id) AS access_level_id
            -- ?: , gia.session_id
            , (%s) AS access_scope_id
         FROM 
            group_item_access AS gia
         WHERE
            gia.stack_id = %d
            AND %s
            AND %s
         """ % (self.sql_access_scope(qb, stack_id),
                stack_id,
                # FIXME: should just be leaf?
                qb.branch_hier_where('gia'),
                gids_where,))

      return sql

   #
   def sql_access_scope(self, qb, stack_id):
      sql = (
         """
         SELECT
            MAX(grp.access_scope_id) AS access_scope_id
         FROM 
            group_item_access AS gia
         JOIN
            group_ AS grp
               ON (gia.group_id = grp.stack_id)
         WHERE
            gia.stack_id = %d
            AND %s
            AND %s
         """ % (stack_id,
                # FIXME: should just be leaf?
                qb.branch_hier_where('gia'),
                qb.revision.as_sql_where_strict('grp'),))
      return sql

   #
   def sql_group_ids(self, gids):
      sql = " gia.group_id IN (%s) " % ",".join([str(x) for x in gids])
      return sql

   # ***

   #
   def from_gml(self, qb, the_item, item_elem):

      log.debug('from_gml')

      # Examine the GML children with our tag name.
      # MAGIC NUMBER: 'gia' must match the tag name.
      # NOTE: If you call iter() without the tag name, you'll get the root
      #       element, too, i.e., you'll get item_elem as the first iter.
      # E.g., item_gwis_abbrev: 'gia' 
      for gia_elem in item_elem.iter(One.item_gwis_abbrev):

         log.debug('from_gml: e: %s / tag: %s / text: %s' 
                   % (gia_elem, gia_elem.tag, gia_elem.text,))

         # Passing the req shouldn't be necessary... "but he's a decent man,
         # and thorough."
         the_gia = One(qb, req=the_item.req)
         # MAYBE: This raises GWIS_Error if any XML is missing, and it raises
         #        GWIS_Warning if the group cannot be found... do we catch it?
         the_gia.from_gml(qb, gia_elem)
         # from_gml loads the group ID or name, and hopefully the item_id
         # and access_level_id.

         access_ok = the_gia.validate_access_loose(qb, the_item)

         if access_ok:
            # Success! User and item are cleared for the permissions change.
            self.append(the_gia)

      # end for

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, gia_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if gia_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               group_id
               , item_id
               , branch_id
               , stack_id
               , version
               , acl_grouping
               , valid_start_rid
               , valid_until_rid
               , deleted
               , reverted
               , access_level_id
               , item_type_id
               , link_lhs_type_id
               , link_rhs_type_id
               , name
               --, session_id
               --, tsvect_name
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(gia_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_style import Access_Style
from grax.new_item_profile import New_Item_Profile
from item import grac_record
from item import item_base
from item import item_versioned
from item import link_value
from item.attc import attribute
from item.grac import group
from item.util.item_type import Item_Type
from util_ import gml
from item.util import revision

__all__ = ['One', 'Many']

log = g.log.getLogger('new_item_policy')

# CODE_COUSINS: flashclient/items/gracs/New_Item_Policy.py
#               pyserver/item/grac/new_item_policy.py

class One(grac_record.One):

   item_type_id = Item_Type.NEW_ITEM_POLICY
   item_type_table = 'new_item_policy'
   item_gwis_abbrev = 'nip'
   child_item_types = None

   local_defns = [
      # NOTE: item_versioned provides: system_id, stack_id, version, deleted,
      #                                name, valid_*_rid, branch_id.
      # NOTE: Using reqv=3 (inreqd_local_only), since we don't except client to
      #       send this.
      # BUG nnnn: How can people change branch NIP, i.e., to make a branch
      #           public but not allow public to edit? And then maybe choose
      #           to let public edit specific item types...
      # py/psql name,             deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('group_id',                None,   True,  False,    int,     3, 'gpid'),
      #('group_name',              None,   True),
      ('target_item_type_id',     None,   True,  False,    int,     3),
      # NOTE: target_item_layer is not used. The policy for an item type
      #       applies to all of its layer types.
      ('target_item_layer',       None,   True,  False,    str,     3),
      ('link_left_type_id',       None,   True,  False,    int,     3),
      ('link_left_stack_id',      None,   True,  False,    int,     3),
      ('link_left_min_access_id', None,   True,  False,    int,     3),
      ('link_right_type_id',      None,   True,  False,    int,     3),
      ('link_right_stack_id',     None,   True,  False,    int,     3),
      ('link_right_min_access_id', None,  True,  False,    int,     3),
      ('processing_order',        None,   True,  False,    int,     3),
      ('stop_on_match',           None,   True,  False,   bool,     3),
      ('access_style_id',         None,   True,  False,    int,     3),
      ('super_acl',               None,   True,  False,    int,     3),
      ]
   attr_defns = grac_record.One.attr_defns + local_defns
   psql_defns = grac_record.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   # NOTE: This is a little hacky; we duplicate some of the column data as
   #       independent, specialized objects. This matches what flashclient 
   #       does, and it makes some Grac opertions easier.
   __slots__ = [
      'target_item',
      'target_left',
      'target_right',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor
   
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      g.assurt(copy_from is None) # Not supported for this class.
      self.target_item = None
      self.target_left = None
      self.target_right = None
      grac_record.One.__init__(self, qb, row, req, copy_from)

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      grac_record.One.from_gml(self, qb, elem)
      g.assurt(False) # BUG 2510: Support GrAC CRUD GWIS.

   # *** Saving to the Database

   #
   def group_ids_add_to(self, group_ids, rid):
      # FIXME: Care about rid?
      # It doesn't seem right to let a group know its new item policy
      # changed... or that it even matters, right?
      #group_ids.add(self.group_id)
      pass

   #
   def save_core(self, qb):
      grac_record.One.save_core(self, qb)
      # Save to the 'new_item_policy' table.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   # *** Instance methods

   #
   def prepare_policy(self):
      #
      self.target_item = New_Item_Profile()
      self.target_item.item_type_id_set(self.target_item_type_id)
      self.target_item.item_layer = self.target_item_layer
      #
      self.target_left = New_Item_Profile()
      self.target_left.item_type_id_set(self.link_left_type_id)
      self.target_left.item_stack_id = self.link_left_stack_id
      self.target_left.min_access_id = self.link_left_min_access_id
      #
      self.target_right = New_Item_Profile()
      self.target_right.item_type_id_set(self.link_right_type_id)
      self.target_right.item_stack_id = self.link_right_stack_id
      self.target_right.min_access_id = self.link_right_min_access_id

   #
   def matches_targets(self, new_item, item_cache):
      log.verbose('matches_targets: checking policy: %s' % (self,))
      log.verbose('  >> %s' % (self.to_string_part_i(),))
      log.verbose('  >> %s' % (self.to_string_part_ii(),))
      does_match = False
      # The item should have been hydrated and cached by the caller, in
      # commit.py.
      g.assurt(new_item.stack_id in item_cache)
      if (self.target_item.matches(new_item)):
         # There's not a strict rule that left is attc and right is feat
         # -- in fact, you could specify a policy for linking two attcs
         # (though the client only supports links btw. attcs and feats).
         if (not isinstance(new_item, link_value.One)):
            # This policy does not apply to links.
            g.assurt(not self.target_left.is_valid())
            g.assurt(not self.target_right.is_valid())
            log.verbose('matches_targets: OK: non-link item and user creds ok')
            does_match = True
         else:
            # This policy applies to links.
            link = new_item
            # Get the items being linked, so we can check the user's
            # permissions. These must already be populated in the cache.
            lhs_item = item_cache[link.lhs_stack_id]
            rhs_item = item_cache[link.rhs_stack_id]
            #
            if ((self.target_left.is_valid()) 
                and (self.target_right.is_valid())):
               if ( ( (self.target_left.matches(lhs_item))
                     and (self.target_right.matches(rhs_item)) )
                   or ( (self.target_left.matches(rhs_item))
                       and (self.target_right.matches(lhs_item)) ) ):
                  log.verbose('matches_targets: OK: both targets match')
                  does_match = True
               else:
                  log.verbose('matches_targets: NO: neither left nor right')
            elif (self.target_left.is_valid()):
               if ( (self.target_left.matches(lhs_item))
                   or (self.target_left.matches(rhs_item)) ):
                  log.verbose('matches_targets: OK: left target matches')
                  does_match = True
               else:
                  log.verbose('matches_targets: NO: not left')
            elif (self.target_right.is_valid()):
               if ( (self.target_right.matches(lhs_item))
                   or (self.target_right.matches(rhs_item)) ):
                  log.verbose('matches_targets: OK: right target matches')
                  does_match = True
               else:
                  log.verbose('matches_targets: NO: not right')
            else:
               # Both target_left and target_right are null
               log.verbose('matches_targets: link: targets are both null')
               does_match = True
      return does_match

   # *** Developer methods

   # Both AutoComplete logs and Logging.debug use this fcn. to produce a
   # friendly name for the item
   #def __str__(self):
   #   return ('%s: grp %s po %s st %s as %s sp %s tgt %s lhs %s rhs %s'
   #           % (grac_record.One.__str__(self),
   #              self.group_id,
   #              self.processing_order,
   #              self.stop_on_match,
   #              self.access_style_id,
   #              self.super_acl,
   #              self.target_item,
   #              self.target_left,
   #              self.target_right,))
   #def __str__():
   #   return ('' # grac_record.One.__str__(self, 'nip')
   #           + self.to_string_part_i()
   #           + ', '
   #           + self.to_string_part_ii()
   #      )

   #
   def to_string_part_i(self):
      return (
         'gid %d, typ %d (%s), lyr (%s), ord %d, stop %s, styl %s, supr %s'
         % (self.group_id,
            self.target_item.item_type_id,
            (Item_Type.id_to_str(self.target_item.item_type_id) 
               if Item_Type.is_id_valid(self.target_item.item_type_id) 
               else '-'),
            (self.target_item.item_layer 
               if self.target_item.item_layer 
               else '-'),
            self.processing_order,
            ('t' if self.stop_on_match else 'f'),
            self.access_style_id,
            self.super_acl,))

   #
   def to_string_part_ii(self):
      # NOTE: Using %s instead of %d because some or all of these could be None
      return ('ltd %s, lsd %s, lad %s, rtd %s, rsd %s, rad %s' % 
              (self.target_left.item_type_id,
               self.target_left.item_stack_id,
               self.target_left.min_access_id,
               self.target_right.item_type_id,
               self.target_right.item_stack_id,
               self.target_right.min_access_id,))

   # ***

# ***

class Many(grac_record.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   sql_shared_nip_cols = (
      """
      , nip.group_id
      , nip.target_item_type_id
      , nip.target_item_layer
      , nip.link_left_type_id
      , nip.link_left_stack_id
      , nip.link_left_min_access_id
      , nip.link_right_type_id
      , nip.link_right_stack_id
      , nip.link_right_min_access_id
      , nip.processing_order
      , nip.stop_on_match
      , nip.access_style_id
      , nip.super_acl
      """)

   # *** Constructor

   def __init__(self):
      grac_record.Many.__init__(self)

   # *** Public interface

   # *** Query Builder routines

   #
   def sql_context_branch(self, qb, *args, **kwargs):
      # FIXME This fcn. is new/untested
      # NOTE: Ordering by target_item_type_id is unnecessary? arbitrary?
      g.assurt(False) # Who calls this fcn?
      sql = (
         """
         SELECT 
            %s -- i_v columns
            %s -- nip columns
         FROM 
            new_item_policy AS nip
         WHERE
            nip.branch_id = %d
            AND %s -- nip rev
         ORDER BY
            nip.processing_order ASC
            , nip.target_item_type_id ASC 
         """ % (
            grac_record.Many.sql_shared_basic_iv('nip'),
            Many.sql_shared_nip_cols,
            qb.branch_hier[0][0], # NOTE: Just returning leaf branch's policies
            qb.revision.as_sql_where_strict('nip'), 
            ))

      return sql

   #
   def sql_context_user(self, qb, *args, **kwargs):

      g.assurt(isinstance(qb.revision, revision.Current)
            or isinstance(qb.revision, revision.Historic))

      # NOTE User can belong to more than one group, so each user might have
      #      multiple policies applying to the same item type. If not for the
      #      stop_on_match feature, we could ORDER BY processing_order, GROUP
      #      BY target_item_type_id and also all the link IDs, and do MIN()
      #      on the access_levels, so that we only send the client one policy
      #      for each unique item class. But because of stop_on_match, I don't
      #      think we can do this in SQL (maybe plpgsql, or definitely python
      #      or flex).

      # FIXME: We only send NIPs for groups to which the user belongs, but this
      #        means that when the user creates new items, they might
      #        incorrectly be marked 'private' but after saving they'll appear
      #        'shared' if other groups to which user doesn't belong are
      #        assigned rights. So send _all_ groups' NIPs?

      log.verbose('qb.branch_hier: %s' % (qb.branch_hier,))

      # "Ensure these policies are valid 'til we're done."
      row_lock = ""
      if qb.request_lock_for_share:
         # 2012.09.25: Using request_lock_for_share is no longer supported.
         g.assurt(not qb.request_lock_for_share)
         # I'm not sure commit needs to lock the NIP table. Seems appropriate,
         # though.
         # Haha, no: row_lock = "FOR SHARE OF new_item_policy". Yes:
         # NOTE: We're using FOR SHARE OF, so we don't have to worry about 
         #       deadlock. If someone wants to edit new_item_policy, they
         #       will grab the table lock.
         row_lock = "FOR SHARE OF nip"

      sql = (
         """
         SELECT 
            %s -- i_v columns
            %s -- nip columns
         FROM 
            user_ AS u
            JOIN group_membership AS gm
               ON (u.id = gm.user_id)
            JOIN group_ AS gr
               ON (gm.group_id = gr.stack_id)
            JOIN new_item_policy AS nip
               ON (gr.stack_id = nip.group_id)
         WHERE
            u.username = %s
            AND %s -- group_membership revision
            AND %s -- group_ revision
            AND %s -- new_item_policy revision
            AND gm.access_level_id <= %d
            AND nip.branch_id = %d
         ORDER BY
            nip.processing_order ASC
         %s
         """ % (
            grac_record.Many.sql_shared_basic_iv('nip'),
            Many.sql_shared_nip_cols,
            qb.db.quoted(qb.username),
            qb.revision.as_sql_where_strict('gm'), 
            qb.revision.as_sql_where_strict('gr'), 
            qb.revision.as_sql_where_strict('nip'), 
            Access_Level.client,
            qb.branch_hier[0][0], # specific branch, and not the hierarchy
            row_lock,
            ))

      return sql

   # ***

   #
   @staticmethod
   def purge_from_branch(qb):

      from_and_where = ("FROM new_item_policy WHERE branch_id = %d"
                        % (qb.branch_hier[0][0],))

      # 2013.04.02: D'oh! [lb] totally forgot the other silly tables...
      qb.db.sql(
         """
         DELETE FROM item_versioned WHERE system_id IN (SELECT system_id %s)
         """
         % (from_and_where,))
      qb.db.sql(
         """
         DELETE FROM item_stack WHERE stack_id
            IN (SELECT DISTINCT(stack_id) %s)
         """
         % (from_and_where,)) 

      qb.db.sql("DELETE FROM new_item_policy WHERE branch_id = %d"
                % (qb.branch_hier[0][0],))

   # ***

   #
   @staticmethod
   def processing_order_peek_next(qb):
      rows = qb.db.sql(
         """
         SELECT 
            MAX(processing_order) AS next_po
         FROM 
            %s 
         WHERE 
            branch_id = %d
         """ % (One.item_type_table,
                qb.branch_hier[0][0],))
      # If this is a new branch, there won't be any hits.
      next_po = rows[0]['next_po'] or 0
      next_po += 1
      return next_po

   # ***

   #
   @staticmethod
   def install_nips(qb, profile_tuples, group_id, force_style=None):

      processing_order = Many.processing_order_peek_next(qb)

      for nip_tup in profile_tuples:

         # See if the tuple includes link_value specifics. The format is, e.g.,
         #   ('Branch arbiters can access all branch work items',
         #      'work_item', None, Access_Level.editor,),
         #  and
         #   ('Attach Note to Viewable Geofeature', 
         #      'link_value', 'pub_editor',
         #         'geofeature', 'viewer', 
         #         'annotation', 'client',
         #       None,),
         last_index = 2
         try:
            # This is a link_value policy.
            lhs_type = nip_tup[3]
            lhs_acl = nip_tup[4]
            rhs_type = nip_tup[5]
            rhs_acl = nip_tup[6]
            last_index = 6
            try:
               lhs_name_or_id = nip_tup[7]
               rhs_name_or_id = nip_tup[8]
               stop_on_match = nip_tup[9]
               last_index = 9
            except IndexError:
               lhs_name_or_id = None
               rhs_name_or_id = None
               stop_on_match = False
            super_acl = None
         except IndexError:
            lhs_type = None
            lhs_acl = None
            rhs_type = None
            rhs_acl = None
            lhs_name_or_id = None
            rhs_name_or_id = None
            stop_on_match = False
            # Some non-link_value policies specify super_acl.
            try:
               super_acl = nip_tup[3]
               last_index = 3
            except IndexError:
               super_acl = None
         # Dev-check
         try:
            ignored = nip_tup[last_index + 1]
            g.assurt(False) # Unexpected input.
         except IndexError:
            pass

         style_id = None
         style_name = force_style or nip_tup[2]
         if style_name:
            style_id = Access_Style.get_access_style_id(style_name)
         else:
            # The access_style_id is required.
            g.assurt(False)

         Many.insert_new_policy(qb,
                                policy_name=nip_tup[0],
                                group_name_or_id=group_id,
                                item_type_name_or_id=nip_tup[1],
                                access_style_id=style_id,
                                processing_order=processing_order,
                                lhs_type=lhs_type,
                                lhs_acl=lhs_acl,
                                lhs_name_or_id=lhs_name_or_id,
                                rhs_type=rhs_type,
                                rhs_acl=rhs_acl,
                                rhs_name_or_id=rhs_name_or_id,
                                super_acl=super_acl,
                                stop_on_match=stop_on_match
                                )

         processing_order += 1

      next_po = Many.processing_order_peek_next(qb)
      g.assurt(next_po == processing_order)

   # ***

   #
   @staticmethod
   def insert_new_policy(qb,
                         policy_name,
                         group_name_or_id,
                         item_type_name_or_id,
                         access_style_id,
                         processing_order,
                         lhs_type=None,
                         lhs_acl=None,
                         lhs_name_or_id=None,
                         rhs_type=None,
                         rhs_acl=None,
                         rhs_name_or_id=None,
                         super_acl=None,
                         stop_on_match=None
                         # Skipping:
                         #  target_item_layer
                         ):

      g.assurt(policy_name)
      g.assurt(qb.item_mgr.rid_new)

      group_id, group_name = group.Many.group_resolve(qb.db, group_name_or_id)
      g.assurt(group_id)

      target_item_type_id = Item_Type.item_type_id_get(item_type_name_or_id)
      g.assurt(target_item_type_id)

      if lhs_type and lhs_acl and rhs_type and rhs_acl:
         link_left_type_id = Item_Type.item_type_id_get(lhs_type)
         link_left_min_access = Access_Level.access_level_id_get(lhs_acl)
         link_right_type_id = Item_Type.item_type_id_get(rhs_type)
         link_right_min_access = Access_Level.access_level_id_get(rhs_acl)
      else:
         link_left_type_id = None
         link_left_min_access = None
         link_right_type_id = None
         link_right_min_access = None

      link_left_stack_id = Many.resolve_item_sid(qb, lhs_name_or_id, lhs_type)
      link_right_stack_id = Many.resolve_item_sid(qb, rhs_name_or_id, rhs_type)

      g.assurt(processing_order)
      g.assurt(access_style_id or super_acl)

      client_id = qb.item_mgr.get_next_client_id()

      new_nip = One(
         qb=qb,
         row={
            # From item_versioned
            'system_id'                : None, # assigned later,
            'branch_id'                : qb.branch_hier[0][0],
            'stack_id'                 : client_id,
            'version'                  : 0,
            'deleted'                  : False,
            'reverted'                 : False,
            'name'                     : policy_name,
            'valid_start_rid'          : None, # qb.item_mgr.rid_new,
            'valid_until_rid'          : conf.rid_inf,
            'group_id'                 : group_id,
            'target_item_type_id'      : target_item_type_id,
            'target_item_layer'        : None, # target_item_layer,
            'link_left_type_id'        : link_left_type_id,
            'link_left_stack_id'       : link_left_stack_id,
            'link_left_min_access_id'  : link_left_min_access,
            'link_right_type_id'       : link_right_type_id,
            'link_right_stack_id'      : link_right_stack_id,
            'link_right_min_access_id' : link_right_min_access,
            'processing_order'         : processing_order,
            'stop_on_match'            : stop_on_match,
            'access_style_id'          : access_style_id,
            'super_acl'                : super_acl,
            #
            })

      new_nip.stack_id_correct(qb)
      g.assurt(new_nip.fresh)
      log.verbose('insert_new_policy: not clearing item_cache')
      # NO: qb.item_mgr.item_cache_reset()
      qb.item_mgr.item_cache_add(new_nip, client_id)
      prepared = qb.grac_mgr.prepare_item(qb,
         new_nip, Access_Level.editor, ref_item=None)
      g.assurt(prepared)
      new_nip.version_finalize_and_increment(qb, qb.item_mgr.rid_new)
      new_nip.save(qb, qb.item_mgr.rid_new)

   #
   @staticmethod
   def resolve_item_sid(qb, item_name_or_id, item_type):

      item_stack_id = None

      if item_name_or_id:

         # For now, we only resolve attributes by their special name.
         # MAYBE: Use stack ID or name to find item of any item type.
         g.assurt(item_type == attribute.One.item_type_table)
         g.assurt(isinstance(item_name_or_id, basestring))

         attrs = attribute.Many()
         attrs.search_by_internal_name(item_name_or_id, qb)
         if (len(attrs) == 1):
            log.verbose('resolve_item_sid: found attribute: %s' % (attrs[0],))
            attr = attrs[0]
            item_stack_id = attr.stack_id
         else:
            g.assurt(len(attrs) == 0)
            log.error('resolve_item_sid: unknown attribute: %s'
                      % (item_name_or_id,))
            # We can assert because we're only run via a dev script.
            g.assurt(False)

      return item_stack_id

   # ***

# ***


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import psycopg2
import traceback
import uuid

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from grax.grac_error import Grac_Error
from grax.user import User
from gwis.query_filters import Query_Filters
from gwis.query_viewport import Query_Viewport
from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import item_versioned
from item import item_revisionless
# Coupling: Be careful, we're importing group modules, so those modules cannot
#           import us, i.e., the group classes cannot import attc or feat
#           classes.
from item.grac import group
from item.grac import groupy_base
from item.grac import group_item_access
from item.util import item_query_builder
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import misc

__all__ = ['One', 'Many',]

log = g.log.getLogger('item_user_access')

# This is a Statewide Flashclient bug:
# BUG nnnn: Rather that making a new revision when, e.g., a branch is made
# public, we can make an entry in the Recent Changes list that says,
# Hey, this branch is public!
# Search: activity_stream.

class One(item_revisionless.One):

   item_type_id = Item_Type.ITEM_USER_ACCESS
   item_type_table = 'group_item_access'
   item_gwis_abbrev = 'gia'
   # If a caller fetches items of type item_user_access.One, we'll just
   # get basic information of the item and nothing else, and we won't
   # care about the item type.
   # NOTE: Using an empty collection, which means something other than None.
   child_item_types = ()

   local_defns = [
      # py/psql name,       deft,  send?,  pkey?,  pytyp,  reqv, abbrev

      # This access_level_id is a computed value, and is an aggregate of the 
      # real access_level_id values stored in group_item_access.
      # MAYBE: Because this defaults to -1 and not None, ccp.py sends it for
      # items being updated, but it's probably not a big deal.
      ('access_level_id',   Access_Level.invalid, 
                                   True,   False,    int,     3, 'alid', ),

      # Skipping: session_id. It's just set in group_item_access.

      # The diff_group value is used by diffs to indicate old, new or static.
      # FIXME: These doesn't seem to be used in flashclient! Maybe it just uses
      #        the hash?
      #        2012.05.26: I [lb] think we the way CcpV2 uses this var that if
      #        would make it easier for flashclient to use it, too, and for us
      #        to get rid of the "difference hash".
      # FIXME: Is diff_group used? Is this where it belongs?
#
# FIXME_2013_06_11: 2013.05.28: [mm] says this is not being set for link_value
      ('diff_group',        None,   True,   None,    str,  None, 'dgrp', ),

      # 2012.10.05: Permissions State Change Request.
      ('style_change',      None,  False,   None,    int,     0, 'schg', ),

      # The user can ask for items by stack ID without knowing the item type
      # (and by using an intermediate class, like this one, or Attachment or
      # Geofeature). To help the caller know what data we're sending back, we
      # can include the 'real' item_type_id, abbreviated 'rtyp' because the
      # GWIS checkout command uses the abbreviation 'ityp'. (This feature
      # was originally introduced for link_attributes_populate.py, circa Winter
      # 2013... ug, [lb] is _still_ refining the V1->V2 import scripts....)
      ('real_item_type_id', None,   True,  False,    int,  None, 'rtyp', ),
      ]
   attr_defns = item_revisionless.One.attr_defns + local_defns
   psql_defns = item_revisionless.One.psql_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   cols_copy_nok = item_revisionless.One.cols_copy_nok + (
      [
       'access_level_id',
       # ?: 'diff_group',
       'style_change',
      ])

   # Some classes (routes and tracks) can be used to save items without any
   # group_item_access records. (Their presence in the database will only be
   # used by our scripts to analyze them, so no need for GIA records; this only
   # happens when anonymous users are routing or tracking.)
   groups_access_not_required = False

   __slots__ = [
      'groups_access',
      # Deprecated: 'access_scope_id',
      'latest_infer_id',
      'latest_infer_username',
      ] + [attr_defn[0] for attr_defn in local_defns]

   # *** Constructor

   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      item_revisionless.One.__init__(self, qb, row, req, copy_from)
      self.groups_access = None
      self.latest_infer_id = None
      self.latest_infer_username = None
      if copy_from is not None:
         # FIXME Copy group accesses? 
         #       For work item, copy latest step?
         pass

   # *** Built-in Function definitions

   acl_abbrev = {
      Access_Level.invalid: 'x',
      Access_Level.owner:   'o',
      Access_Level.arbiter: 'a',
      Access_Level.editor:  'e',
      Access_Level.viewer:  'v',
      Access_Level.client:  'c',
      Access_Level.denied:  'd',
      }

   acl_nickname = {
      Access_Level.invalid: 'n/a',
      Access_Level.owner:   'own',
      Access_Level.arbiter: 'arb',
      Access_Level.editor:  'edt',
      Access_Level.viewer:  'vwr',
      Access_Level.client:  'cli',
      Access_Level.denied:  'den',
      }

   #
   def __str__(self):
      return ('"%s" [%s]'
              % (self.name,
                 self.__str_deets__(),))

   #
   def __str_abbrev__(self):
      return ('"%s" | %s [%s|%s]' 
              % (self.name,
                 #(self.item_type_table or self.__class__),
                 self.__class__.__module__,
                 self.stack_id,
                 One.acl_abbrev[self.access_level_id],))

   #
   def __str_deets__(self):
      return ('%s-acl:%s%s'
              % (item_revisionless.One.__str_deets__(self),
                 #self.access_level_id,
                 One.acl_nickname[self.access_level_id],
                 # diff_group is 'latter' or 'former'
                 ('-%s' % self.diff_group) if self.diff_group else '',))

   # *** Dirty/Fresh/Valid Routines

   # 
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      item_revisionless.One.validize(self, qb, is_new_item, dirty_reason, 
                                  ref_item)
      g.assurt(self.valid)
      copy_gia_from = None
      if not is_new_item:
         if ref_item is not None:
            copy_gia_from = ref_item
         else:
            copy_gia_from = self
      elif (ref_item is not None) and (id(self) != id(ref_item)):
         # This is a new item, but it wants to use the GIA of the ref_item.
         # This should be a new link_value for a new split-from byway. The 
         # ref_item is the old link for the old byway.
         copy_gia_from = ref_item
      # else, 
      #   this is a new item, and there's not ref_item or it's the same as us.
      #   so grac_mgr should've created gia records for us based the user's
      #   new item policies.
      if copy_gia_from:
         #log.verbose('validize: loading groups_access')
         if self.groups_access is not None:
            log.verbose('validize: groups_access already set: clearing: %s' 
                        % (self,))
            self.groups_access = {}
            self.latest_infer_id = None
            self.latest_infer_username = None
         # This happens when the user is saving a new version of an existing
         # item. Get the group access permissions of the existing item, which
         # we'll use to save new group access permissions for the updated item.
         # NOTE: This is the second place the code loads accesses: the other 
         #       is in grac_mgr, which sets up access if the item is new and 
         #       not split-from. The code here is for items being updated or
         #       split-froms.
         self.groups_access_load_from_db(qb, copy_gia_from)
         for grpa in self.groups_access.itervalues():
            grpa.valid_start_rid = None
            grpa.valid_until_rid = None
         g.assurt(not self.groups_access_not_required) # No routes or tracks
         g.assurt(len(self.groups_access) > 0)
      else:
         # New item from client. Commit should have applied the new item policy
         # and built the groups_access list.
         # MAYBE: What to do about anon routes? They don't have
         # groups_access... and probably shouldn't, unless we made a special
         # user. But we only analyze routes with our scripts, so probably no
         # needs to worry about GIA records for them.
         if not self.groups_access_not_required:
            # At least 1 grp (user's or pub). Though routes and tracks can be
            # saved without any.
            g.assurt(len(self.groups_access) > 0)
      g.assurt(self.is_access_valid())

   # NOTE: We could override validize_compare and compare groups_access,
   #       but, hrmm... I'm [lb] not sure we need to....

   # *** Pre-Saving

   #
   def mark_deleted_update_sql(self, db):
      item_revisionless.One.mark_deleted_update_sql(self, db)
      rows = db.sql("UPDATE %s SET deleted = TRUE WHERE item_id = %s"
             % (One.item_type_table, self.system_id,))
      g.assurt(rows is None)

   #
   def finalize_last_version_at_revision(self, qb, rid, same_version):

      # This fcn. is called when a new version of the item is about to be saved
      item_revisionless.One.finalize_last_version_at_revision(
         self, qb, rid, same_version)

      qb.db.sql(
         """
         UPDATE %s SET valid_until_rid = %d
         WHERE (item_id = %d) AND (valid_until_rid = %d) AND (branch_id = %d)
         """ % (One.item_type_table, rid,
                self.system_id, conf.rid_inf, qb.branch_hier[0][0],))

   # *** Saving to the Database

   # This is used by commit.py to figure out what group_revisions to create.
   def group_ids_add_to(self, group_ids, rid):
      # FIXME: Care about rid?
      for grpa in self.groups_access.itervalues():
         group_ids.add(grpa.group_id)

   #
   def save_related_get_cols(self, qb):

      id_cols = {
         # Skipping: group_id, set in the loop
         # Skipping: access_level_id, set in the loop
         'item_id': self.system_id,
         'acl_grouping': self.acl_grouping,
         }

      # FIXME: Just curious: are these always cur and inf?
      #g.assurt(self.valid_start_rid == revision.Revision.revision_last())
      g.assurt(self.valid_until_rid == conf.rid_inf)

      # This is a simply check to make sure the item type is set, so that
      # commit can make acl_grouping changes with an item_user_access object
      # and not hydrate the complete item. So this isn't the same as
      # checking g.assurt(self(type) != item.item_user_access.One).
      g.assurt(self.item_type_id != One.item_type_id)
      # On second thought... maybe callers should always get real objects.
      g.assurt(type(self) != One) # since instance(self, One) is True.

      nonid_cols = {
         'branch_id': self.branch_id,
         'stack_id': self.stack_id,
         'version': self.version,
         'deleted': self.deleted,
         'reverted': self.reverted,
         'name': self.name,
         # gia's revision IDs don't have to match the items, but they do when
         # a new item version is saved
         'valid_start_rid': self.valid_start_rid,
         'valid_until_rid': self.valid_until_rid,
         # Weird. These are just set here but are not defined in
         # local_defns... and item_type_id is a class variable.
         'item_type_id': self.item_type_id,
         # Skipping: item_layer_id (deprecated)
         # Skipping: link_name (not implemented)
         # This is kludgy: only link_values set these two attrs.
         'link_lhs_type_id': getattr(self, 'link_lhs_type_id', None),
         'link_rhs_type_id': getattr(self, 'link_rhs_type_id', None),
         # Skipping: 'session_id' (set in loop)
         }

      return (id_cols, nonid_cols,)

   #
   def save_related_maybe(self, qb, rid):

      if self.groups_access and (len(self.groups_access) > 0):
         log.verbose('save_related_maybe: set dirty_reason_infr: %s' % (self,))
         # The item_stack class is below us and it'll analyze
         # groups_access to determine and update the access_infer_id.
         # Note that item_stack.save_core may already have set this
         # flag, but if acl_grouping > 1, then it's not set yet.
         self.dirty |= item_base.One.dirty_reason_infr

      item_revisionless.One.save_related_maybe(self, qb, rid)

      g.assurt(self.item_type_id > 0)
      # When bumping an item's version, create new group_item_access rows.
      # But routes and tracks may be saved anonymously, sans groups_access.
      if self.groups_access:
         if len(self.groups_access) > 0:
            (id_cols, nonid_cols,) = self.save_related_get_cols(qb)
            self.save_related_save_groups_access(qb, id_cols, nonid_cols, rid)
         else:
            g.assurt(self.groups_access_not_required)
         for gia in self.groups_access.itervalues():
            gia.dirty = item_base.One.dirty_reason_none
      else:
         # I.e., node_endpoint, node_byway, permissions_free.
         g.assurt(self.groups_access_not_required)
      # MAYBE: Would we want to consume some of the stuff commit.py currently 
      #        does? Like, e.g.,
      #          self.save_related_save_ratings(qb)
      #          self.save_related_save_tagprefs(qb)
      #          self.save_related_save_thumbers(qb)
      #          self.save_related_save_watchers(qb)

   #
   def is_dirty(self):
      is_dirty = item_revisionless.One.is_dirty(self)
      # self.groups_access is empty for permissions_free items.
      # But it's always set.
      g.assurt(self.groups_access is not None)
      if not is_dirty:
         for gia in self.groups_access.itervalues():
            if gia.dirty != item_base.One.dirty_reason_none:
               is_dirty = True
               break
      return is_dirty

   #
   def save_related_save_groups_access(self, qb, id_cols, nonid_cols, rid):

      # Save all the dirty group access items.

      log.verbose('save_related_save_groups_access: %s' % (self,))
      log.verbose(' >> groups_access: %s' % (self.groups_access,))
      log.verbose(' >> id_cols: %s / nonid_cols: %s' % (id_cols, nonid_cols,))

      g.assurt(self.system_id)
      g.assurt(self.valid_until_rid == conf.rid_inf)

      # MAYBE: PERF. Cache revision_max, or have it passed in.
      rev_max = revision.Revision.revision_max(qb.db)

      for gia in self.groups_access.itervalues():

         # DEVs: Uncomment to stop here on stealth group id.
         # MAGIC_NUMBER: 'minnesota' database. See:
         #  SELECT value FROM key_value_pair where key = 'cp_group_stealth_id';
         # if gia.group_id == 2506583:
         #    import rpdb2;
         #    rpdb2.start_embedded_debugger('password',fAllowRemote=True)

         do_insert = False

         if self.dirty != item_base.One.dirty_reason_none:
            # We were just saved w/ a new version ID, so we got a new system
            # ID. For new items, gia.item_id is None.
            g.assurt((gia.item_id != self.system_id)
                     or (self.acl_grouping > 1))
            is_new_item = False
            if (self.version == 1) and (self.acl_grouping == 1):
               g.assurt(gia.item_id is None)
               is_new_item = True
               g.assurt(gia.valid_start_rid is None)
               g.assurt(gia.valid_until_rid is None)
            else:
               g.assurt(gia.item_id is not None)
               # The gia's valid_start_rid and gia.valid_until_rid may or may
               # not be set; even if the item is a versiony version, the gia 
               # record still might be new.
            g.assurt((self.valid_start_rid == 1) 
                     or (self.valid_start_rid > rev_max)
                     or ((qb.item_mgr.rid_latest_really)
                         and (self.valid_start_rid == rev_max)))

            # Non-wiki items have valid_start_rid of 1.
            # g.assurt(self.valid_start_rid == rid)
            self.verify_revision_id(rid)

            # If this is a new item, the item_id is None. If the item was just 
            # saved, then the gia's item_id is for the old item.
            gia.item_id = self.system_id
            gia.valid_start_rid = self.valid_start_rid
            gia.valid_until_rid = conf.rid_inf

            # 2013.12.21: The commit and stealth_create commands now
            #  return GIA data, so make sure stack_id is set (which
            #  flashclient uses to lookup the item reference).
            #
            # Also, MAYBE: Instead of GML response like:
            #
            #    <id_map cli_id="-1" new_id="1" acif="66048">
            #     <access_control control_type="group_item_access">
            #       <gia stid="4047801" alid="2" v="1" gpid="2506584"/>
            #       <gia stid="4047801" alid="3" v="1" gpid="2506583"/>
            #     </access_control></id_map>
            #
            #  We could make tags out of the stack ID and version.
            #
            #    <id_map cli_id="-1" new_id="1" acif="66048">
            #     <access_control control_type="group_item_access"
            #         stid="4047801" v="1">
            #       <gia alid="2" gpid="2506584"/>
            #       <gia alid="3" gpid="2506583"/>
            #     </access_control></id_map>
            #
            #  But until then:
            gia.stack_id = self.stack_id
            gia.version = self.version

            # Don't bother saving new GIA record if access is simply denied
            # and item is new.
            if self.version != 1:
               do_insert = True
               # MAYBE: Do make keep making records for deleted items? Prob. 
               # not necessary, but probably not a big problem.
               if Access_Level.is_denied(gia.access_level_id):

                  # [lb] is curious why this would happen.
                  #
                  # 2014.09.09: [lb] saw this... but it might have been because
                  # of issues getting route saving/changing permissions to
                  # work. I thought maybe this had to do with a route save that
                  # timed out in the client but completed on the server (I was
                  # debugging), such that the client's version number was one
                  # off, but it might be because of something else.
                  #  Sep-09 00:37:41 WARN item_user_access _save_groups_access:
                  #  was already denied: "test2 Route via Midtown Greenway"
                  #  [route:2539274.v2+VLD+DTY/ss3869404-b2500677-acl:arb]
                  #  { beg: "Kenneth H. Keller Hall" }
                  #  { end: "W 50th St & S Dupont Ave, Minneapolis, MN 55419" }
                  #  [mode:1|3attr:|p3wgt:|p3rat:0|p3fac:0|p3alg:]
                  # 
                  log.warning('_save_groups_access: was already denied: %s'
                              % (str(self),))
            else:
               do_insert = True
               # 2012.08.08: It maybe might matter if someone is creating a
               # 'denied' GIA record on new item creation, but this is useful
               # for new branches: We can set the 'Public' as denied so that 
               # the Public group shows up in the client GIA list (which makes
               # it easy for the user to give the Public access to the branch).
               if Access_Level.is_denied(gia.access_level_id):
                  log.verbose(
                     '_save_groups_access: skipping denied on new: %s'
                     % (str(self),))

         elif gia.dirty != item_base.One.dirty_reason_none:
            # This only happens if we're changing the GIA of an item that
            # isn't changing -- meaning, the GIA records were loaded from the
            # database.
            g.assurt(gia.item_id == self.system_id)
            g.assurt(self.valid_start_rid < rid)
            g.assurt(gia.valid_start_rid < rid)
            g.assurt(gia.valid_until_rid == conf.rid_inf)
            # If the item would have been dirty (the preceeding 'if'-clause),
            # we would have finalized all of the old GIA records and here we'd
            # create new ones. But the item is not marked dirty, so we're not
            # saving a new version of it, so we have to finalize the old GIA
            # records here. See also version_finalize_and_increment and esp.
            # finalize_last_version_at_revision.
            qb.db.sql(
               """
               UPDATE
                  %s
               SET
                  valid_until_rid = %d
               WHERE
                  group_id = %d
                  AND item_id = %d
                  AND valid_until_rid = %d
               """ % (One.item_type_table, 
                      rid,
                      gia.group_id,
                      gia.item_id, 
                      conf.rid_inf,))
            # Update the GIA object and save a new GIA record.
         # else, neither the item nor its GIA are dirty.

# FIXME: Verify this is right
#            gia.valid_start_rid = rid
            do_insert = True
         # else, the GIA is not marked dirty, and do_insert is still False.

         log.verbose(' >> do_insert: %s / %s' % (do_insert, gia,))
         if do_insert:
            # We setup most of the columns' values in save_related_get_cols().
            # Here we just set the group ID and access level.
            # SYNC_ME: See grac.group_item_access.local_defns.
            log.verbose('save_related_save_groups_access: session_id: %s'
                        % (gia.session_id,))
            id_cols.update({
               'group_id'        : gia.group_id,
               'access_level_id' : gia.access_level_id,
               'session_id'      : gia.session_id,
               # Skipping: item_id, branch_id.
               })
            # Not calling save_insert, but calling insert directly.
            # NOTE: Even if access denied, we still save all of the columns.
            qb.db.insert(One.item_type_table, id_cols, nonid_cols)

      # end: for gia in self.groups_access.itervalues

   #
   def verify_revision_id(self, rid):
      g.assurt(self.valid_start_rid == rid)

   # *** Groups Access routines

   # CODE_COUSINS: group_access_add/group_access_add
   #               in: pyserver/item/item_user_access.py
   #               in: flashclient/item/Item_User_Access.as

   # 
   def group_access_add_or_update(self, qb, obj, dirty_reason):
      # Callers need to make sure to set groups_access to dict() before first
      # calling this function.
      g.assurt(self.groups_access is not None)
      # Is the dirty_reason ever _not_ a grac reason?
      g.assurt(dirty_reason in (item_base.One.dirty_reason_grac_user,
                                item_base.One.dirty_reason_grac_auto,))
      # The caller can pass a tuple or a real gia instance.
      if isinstance(obj, tuple):
         (group_id, access_level_id, session_id,) = obj
         new_gia = group_item_access.One(
            qb=qb, 
            row={
             'item_id'         : self.system_id,
             'group_id'        : group_id,
             'access_level_id' : access_level_id,
             'session_id'      : session_id,
            })
      else:
         g.assurt(isinstance(obj, group_item_access.One))
         new_gia = obj
      g.assurt(new_gia.item_id == self.system_id)
      g.assurt(new_gia.group_id != 0)
      g.assurt(Access_Level.is_valid(new_gia.access_level_id))
      log.verbose(
         'grp_access_add_or_upd: gpid %d / acl %d / ssid %s / dty %d'
         % (new_gia.group_id, new_gia.access_level_id, new_gia.session_id,
            dirty_reason,))
      log.verbose('  >> %s' % (self,))

      try:
         # Set the access level and update the dirty reason. This throws
         # (caught below) if the group access isn't part of the lookup yet.
         real_gia = self.groups_access[new_gia.group_id]
         if real_gia.access_level_id != new_gia.access_level_id:
            real_gia.access_level_id = new_gia.access_level_id
            real_gia.dirty_reason_add(dirty_reason)
         g.assurt(real_gia.group_id == new_gia.group_id)
         g.assurt(real_gia.item_id == new_gia.item_id)
         log.verbose('  >> updated existing: %s' % (real_gia.to_string(),))
      except KeyError:
         new_gia.dirty_reason_add(dirty_reason)
         self.groups_access[new_gia.group_id] = new_gia
         log.verbose('  >> added new: %s' % (new_gia.to_string(),))

      self.access_level_id = Access_Level.denied
      for gia in self.groups_access.values():
         self.access_level_id = min(self.access_level_id,
                                    gia.access_level_id)
      g.assurt(Access_Level.is_valid(self.access_level_id))

      self.latest_infer_id = None
      self.latest_infer_username = None

      return new_gia

   #
   def groups_access_load_from_db(self, qb, copy_gia_from=None):
      '''Loads all the group accesses for an item, i.e., context: item. '''
      g.assurt(not self.groups_access)
      self.groups_access = {}
      self.latest_infer_id = None
      self.latest_infer_username = None
      #
      tmp_qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      # FIXME/MAYBE: db_glue.clone() copies qb.db.dont_fetchall, which seems
      #              odd, but a lot of places already use db_clone=True, so...
      tmp_qb.db.dont_fetchall = False

      if copy_gia_from is None:
         copy_gia_from = self

      g.assurt(copy_gia_from.valid_start_rid)
      tmp_qb.revision = revision.Historic(copy_gia_from.valid_start_rid)

      g.assurt(not tmp_qb.filters.only_stack_ids)
      tmp_qb.filters.only_stack_ids = str(copy_gia_from.stack_id)
      grpa_many = group_item_access.Many()
      grpa_sql = grpa_many.sql_context_item(tmp_qb)
      grpa_rows = tmp_qb.db.sql(grpa_sql)

      if len(grpa_rows) == 0:
         log.warning('groups_access_load_from_db: no rows: stack_id: %s' 
                     % (copy_gia_from.stack_id,))
         g.assurt(False)
      else:
         latest_branch_id = None
         for grpa_row in grpa_rows:
            grpa = group_item_access.One(qb=tmp_qb, row=grpa_row)
            if not latest_branch_id:
               latest_branch_id = grpa.branch_id
            elif latest_branch_id != grpa.branch_id:
               # sql_context_item gets GIA records for all branches, but we
               # just want the latest set of records.
               break
            # If we copied another item's group accesses, we need to tell 'em.
            grpa.item_id = self.system_id
            g.assurt(grpa.group_id > 0)
            g.assurt(Access_Level.is_valid(grpa.access_level_id))
            # Mark these dirty so if the item is saved, so are the gias.
            #grpa.dirty |= item_base.One.dirty_reason_item_auto
            grpa.dirty |= item_base.One.dirty_reason_grac_auto
            #self.group_access_add_or_update(grpa, mark_dirty)
            g.assurt(grpa.group_id not in self.groups_access)
            self.groups_access[grpa.group_id] = grpa
            self.latest_infer_id = None
            self.latest_infer_username = None

      tmp_qb.db.close()

   #
   def groups_access_load_from_gml(self, qb, accesses_elem):

      # FIXME: Test this fcn! This is for permissive GIA changes.
      # at least, I think it is...
      log.warning('FIXME: test this fcn., groups_access_load_from_gml')

      loaded_ok = True

      log.verbose('groups_access_load_from_gml')

      # This fcn. only applies to the 'permissive' style.
      g.assurt(self.access_style_id == Access_Style.permissive)

      # Check that the user is an arbiter of the item, else they can't change
      # its GIA records.
      if not self.can_arbit():
         log.error('gia_load_from_gml: cannot arbit: %s' % (str(self),))
         loaded_ok = False
      else:
         # Make children from the GML.
         gias = group_item_access.Many()
         gias.from_gml(qb, accesses_elem)
         # At this point, qb.grac_mgr may have zero or more errors, and gias
         # may contain zero or more objects.
         for the_gia in gias:
            self.group_access_add_or_update(qb, the_gia,
                        #item_base.One.dirty_reason_item_user
                        item_base.One.dirty_reason_grac_user)
         # Now that we've consumed the user's desired access changes,
         # double-check that the user isn't changing their own permissions,
         # since users can neither demote nor promote their own access.
         g.assurt(qb.username != conf.anonymous_username)
         # There are at least two group IDs for this user: anon and private.
         g.assurt(len(qb.revision.gids) >= 2)
         new_acl_id = self.calculate_access_level(qb.revision.gids)
         if new_acl_id != self.access_level_id:
            log.error('gia_load_from_gml: acl changed: %s / %s:%s:%s / %s'
                      % (new_acl_id, grp_id, grp_nm, acl_id, str(self),))
            loaded_ok = False
      if not loaded_ok:
         qb.grac_mgr.grac_errors_add(self.stack_id,
                                     Grac_Error.permission_denied,
                                     '/item/groups_access')
         item.valid = False

      return loaded_ok

   #
   def groups_access_style_change(self, qb):

      log.verbose('groups_access_style_change: %s' % (str(self),))

      # This only works on 'restricted' access style. 'acl_choice'
      # ('usr_choice' and 'pub_choice') is handled by grac_manager
      # when new item is created. And 'permissive' should be implemented
      # using straightup GIA records.

      changed_ok = True

      if not self.can_arbit():

         log.error('_style_change: cannot arbit: %s' % (str(self),))
         qb.grac_mgr.grac_errors_add(self.stack_id,
                                     Grac_Error.permission_denied,
                                     '/item/groups_access')
         changed_ok = False

      elif self.access_style_id != Access_Style.restricted:

         log.error('_style_change: Unexpected: !Access_Style.restricted: %s'
                   % (hex(self.access_style_id),))

         qb.grac_mgr.grac_errors_add(self.stack_id,
                                     Grac_Error.bad_item_type,
                                     '/item/groups_access')
         changed_ok = False

      elif self.style_change & ~Access_Infer.restricted_mask:

         log.error('_style_change: Unexpected: ~restricted_mask: %s'
                   % (hex(self.style_change),))
         qb.grac_mgr.grac_errors_add(self.stack_id,
                                     Grac_Error.invalid_item,
                                     '/item/groups_access')
         changed_ok = False

      elif self.style_change == Access_Infer.not_determined:

         log.error('_style_change: Unexpected: not_determined: %s'
                   % (hex(self.style_change),))
         qb.grac_mgr.grac_errors_add(self.stack_id,
                                     Grac_Error.invalid_item,
                                     '/item/groups_access')
         changed_ok = False

      else:

         #private_group_id = qb.user_group_id
         public_group_id = group.Many.public_group_id(qb.db)
         stealth_group_id = group.Many.stealth_group_id(qb.db)
         session_group_id = group.Many.session_group_id(qb.db)

         if self.style_change & Access_Infer.usr_denied:

            # This is the code path when, e.g., making a private arbiter
            # route into a public route: we make an editor record for the
            # public, and we set the user's access to denied (so their
            # access is now derived from the public record).

            g.assurt(not ((self.style_change & ~Access_Infer.usr_denied)
                          & Access_Infer.usr_mask))
            g.assurt((self.style_change & Access_Infer.pub_mask)
                     == Access_Infer.pub_editor)
            # Ignoring stealth_*, and others_*.
            public_acl = Access_Level.editor
            # It doesn't matter if we set editor or denied for private and
            # stealth since public is editor...
            #private_acl = Access_Level.editor
            #stealth_acl = Access_Level.editor
            # Use denied so we don't make unnecessary records... and it makes
            # more sense, in a sense, though it might not seem so.
            private_acl = Access_Level.denied
            stealth_acl = Access_Level.denied
            session_acl = Access_Level.denied

         else:

            # Don't enforce; allow user not to specify usr_* option (we'll just
            # infer usr_arbiter):
            # No: g.assurt(self.style_change & Access_Infer.usr_arbiter)
            # But user should not specify any other usr_* options.
            g.assurt(not ((self.style_change & ~Access_Infer.usr_arbiter)
                          & Access_Infer.usr_mask))

            if self.style_change & Access_Infer.usr_denied:
               private_acl = Access_Level.denied
            #elif self.style_change & Access_Infer.usr_viewer:
            #   private_acl = Access_Level.viewer
            #elif self.style_change & Access_Infer.usr_editor:
            #   private_acl = Access_Level.editor
            elif self.style_change & Access_Infer.usr_arbiter:
               private_acl = Access_Level.arbiter
            else:
               # No: private_acl = Access_Level.denied
               # If caller leaves the byte 0, then it means ignore.
               g.assurt(not (self.style_change & Access_Infer.usr_mask))
               private_acl = None

            if self.style_change & Access_Infer.pub_denied:
               public_acl = Access_Level.denied
            elif self.style_change & Access_Infer.pub_viewer:
               public_acl = Access_Level.viewer
            elif self.style_change & Access_Infer.pub_editor:
               public_acl = Access_Level.editor
            else:
               g.assurt(not (self.style_change & Access_Infer.pub_mask))
               public_acl = None

            if self.style_change & Access_Infer.stealth_denied:
               stealth_acl = Access_Level.denied
            elif self.style_change & Access_Infer.stealth_viewer:
               stealth_acl = Access_Level.viewer
            elif self.style_change & Access_Infer.stealth_editor:
               stealth_acl = Access_Level.editor
            else:
               g.assurt(not (self.style_change & Access_Infer.stealth_mask))
               stealth_acl = None

            if self.style_change & Access_Infer.sessid_denied:
               session_acl = Access_Level.denied
            #elif self.style_change & Access_Infer.sessid_viewer:
            #   session_acl = Access_Level.viewer
            #elif self.style_change & Access_Infer.sessid_editor:
            #   session_acl = Access_Level.editor
            elif self.style_change & Access_Infer.sessid_arbiter:
               session_acl = Access_Level.arbiter
            else:
               g.assurt(not (self.style_change & Access_Infer.sessid_mask))
               session_acl = None

         if ((private_acl is not None) and (session_acl is not None)):
            # This is okay if the user is making a private item (like a route)
            # into a public item (so we set the user's access denied and make
            # a new, public-group editable GIA record).
            if (   (private_acl != Access_Level.denied)
                or (session_acl != Access_Level.denied)
                or (self.style_change != (  Access_Infer.usr_denied
                                          | Access_Infer.pub_editor))):
               log.warning(
                  '%s private_acl: %s / session_acl: %s / style_change: %s'
                  % ('groups_access_style_change:',
                     private_acl,
                     session_acl,
                     self.style_change,))
               g.assurt(private_acl == Access_Level.arbiter)
               session_acl = Access_Level.denied

            # BUG nnnn/MAYBE: We'll keep making denied session ID records
            # everytime we update group_item_access. Let's stop correct
            # the valid_until_rid of the first record and than not make
            # any new ones.

         #dirty_reason_auto = item_base.One.dirty_reason_item_auto
         dirty_reason_auto = item_base.One.dirty_reason_grac_auto

         updated_private = False
         updated_public = False
         updated_stealth = False
         updated_session = False

         #g.assurt(len(self.groups_access) in (1, 2,)) ??
         g.assurt(len(self.groups_access) in (1, 2, 3,))
         for grpa in self.groups_access.itervalues():
            if grpa.group_id == qb.user_group_id:
               g.assurt(grpa.access_level_id == Access_Level.arbiter)
               if ((private_acl is not None)
                   and (grpa.access_level_id != private_acl)):
                  grpa.access_level_id = private_acl
                  grpa.dirty |= dirty_reason_auto
               updated_private = True
            elif grpa.group_id == public_group_id:
               if ((public_acl is not None)
                   and (grpa.access_level_id != public_acl)):
                  grpa.access_level_id = public_acl
                  grpa.dirty |= dirty_reason_auto
               updated_public = True
            elif grpa.group_id == stealth_group_id:
               if ((stealth_acl is not None)
                   and (grpa.access_level_id != stealth_acl)):
                  grpa.access_level_id = stealth_acl
                  grpa.dirty |= dirty_reason_auto
               updated_stealth = True
            elif grpa.group_id == session_group_id:
               # The grpa.session_id is not retrieved from the db, so set it.
               if ((session_acl is not None)
                   and ((grpa.access_level_id != session_acl)
                        or (not grpa.session_id))):
                  grpa.access_level_id = session_acl
                  grpa.dirty |= dirty_reason_auto
                  grpa.session_id = qb.session_id
                  log.debug('groups_access_style_change: session_id: %s'
                            % (grpa.session_id,))
               updated_session = True
            # else... what now?

         #
         session_id = None
         g.assurt(updated_private or updated_session)
         if ((private_acl is not None)
             and (not updated_private)
             and (private_acl != Access_Level.denied)):
            self.group_access_add_or_update(qb,
               (qb.user_group_id, private_acl, session_id,),
               dirty_reason_auto)
         if ((public_acl is not None)
             and (not updated_public)
             and (public_acl != Access_Level.denied)):
            self.group_access_add_or_update(qb,
               (public_group_id, public_acl, session_id,),
               dirty_reason_auto)
         if ((public_acl is not None)
             and (not updated_public)
             and (public_acl != Access_Level.denied)):
            self.group_access_add_or_update(qb,
               (public_group_id, public_acl, session_id,),
               dirty_reason_auto)
         if ((stealth_acl is not None)
             and (not updated_stealth)
             and (stealth_acl != Access_Level.denied)):
            self.group_access_add_or_update(qb,
               (stealth_group_id, stealth_acl, session_id,),
               dirty_reason_auto)
         if ((session_acl is not None)
             and (not updated_session)
             and (session_acl != Access_Level.denied)):
            g.assurt(qb.session_id)
            session_id = qb.session_id
            self.group_access_add_or_update(qb,
               (session_group_id, session_acl, session_id,),
               dirty_reason_auto)

      if not changed_ok:
         self.valid = False

      # NOTE: The caller must make sure to version_finalize_and_increment and
      #       to set save_version=True to increment acl_grouping.

      return changed_ok

   # *** Permissions convenience methods

   # CODE_COUSINS: pyserver/item/gitem_user_access.py
   #               flashclient/item/Item_User_Access.as

   #
   def is_access_valid(self):
      return Access_Level.is_valid(self.access_level_id)

   #
   def can_own(self):
      return Access_Level.can_own(self.access_level_id)

   #
   def can_arbit(self):
      return Access_Level.can_arbit(self.access_level_id)

   #
   def can_edit(self):
      return Access_Level.can_edit(self.access_level_id)

   #
   def can_view(self):
      return Access_Level.can_view(self.access_level_id)

   #
   def can_know(self):
      return Access_Level.can_know(self.access_level_id)

   # *** Scope convenience methods

   #
   def get_access_infer(self, qb):
      if ((self.latest_infer_id is None)
          or (self.latest_infer_username != qb.username)):
         # For some items, like node_endpoints, we won't have a user... and
         # access scope is kind of meaningless.
         self.latest_infer_id = Access_Infer.not_determined
         self.latest_infer_username = qb.username
         if not qb.username:
            # Happens when splitting byways and recreating link_values.
            g.assurt(qb.request_is_local)
            g.assurt(qb.request_is_script)
            g.assurt(qb.filters.gia_userless)
         #elif self.groups_access is not None:
         if self.groups_access is not None:
            self.latest_infer_id = self.get_access_infer_impl(qb)
         # else, node_endpoint, etc.; items without GIA records.
      return self.latest_infer_id

   # See flashclient's get_access_infer / pyserver's get_access_infer.
   #
   def get_access_infer_impl(self, qb):

      public_group_id = group.Many.public_group_id(qb.db)
      stealth_group_id = group.Many.stealth_group_id(qb.db)
      session_group_id = group.Many.session_group_id(qb.db)

      latest_infer_id = Access_Infer.not_determined # I.e., 0.
      num_user_records = 0
      for grpa in self.groups_access.itervalues():
         if grpa.group_id == public_group_id:
            if Access_Level.can_edit(grpa.access_level_id):
               g.assurt(not Access_Level.can_arbit(grpa.access_level_id))
               latest_infer_id |= Access_Infer.pub_editor
            elif Access_Level.can_client(grpa.access_level_id):
               # NOTE: Using can_client and not just can_view.
               latest_infer_id |= Access_Infer.pub_viewer
            else:
               g.assurt(grpa.access_level_id == Access_Level.denied)
         elif grpa.group_id == stealth_group_id:
            if Access_Level.can_edit(grpa.access_level_id):
               g.assurt(not Access_Level.can_arbit(grpa.access_level_id))
               latest_infer_id |= Access_Infer.stealth_editor
            elif Access_Level.can_client(grpa.access_level_id):
               # NOTE: Using can_client and not just can_view.
               latest_infer_id |= Access_Infer.stealth_viewer
            else:
               g.assurt(grpa.access_level_id == Access_Level.denied)
         elif grpa.group_id == session_group_id:
            if Access_Level.can_arbit(grpa.access_level_id):
               latest_infer_id |= Access_Infer.sessid_arbiter
            else:
               # We only ever use sessid_arbiter. 
               g.assurt(grpa.access_level_id == Access_Level.denied)
         elif grpa.access_level_id != Access_Level.denied:
            # A 'restricted'-style item has one arbiter, which is the user;
            #  there may be public, stealth, and session records, but there
            #  shouldn't be other user records.
            # A usr_editor will only have one user record, and pub_editor none.
            # A permissive-style item should probably not set usr_arbiter or
            #  usr_editor?
            num_user_records += 1
            if self.access_style_id == Access_Style.restricted:
               g.assurt(grpa.access_level_id == Access_Level.arbiter)
               g.assurt(num_user_records == 1)
               latest_infer_id |= Access_Infer.usr_arbiter
            elif self.access_style_id == Access_Style.usr_editor:
               g.assurt(grpa.access_level_id == Access_Level.editor)
               g.assurt(num_user_records == 1)
               latest_infer_id |= Access_Infer.usr_editor
            elif self.access_style_id == Access_Style.permissive:
               if Access_Level.can_arbit(grpa.access_level_id):
                  latest_infer_id |= Access_Infer.others_arbiter
               elif Access_Level.can_edit(grpa.access_level_id):
                  latest_infer_id |= Access_Infer.others_editor
               elif Access_Level.can_client(grpa.access_level_id):
                  latest_infer_id |= Access_Infer.others_viewer
               else:
                  g.assurt(grpa.access_level_id == Access_Level.denied)
            else:
               g.assurt(False)

      return latest_infer_id

   # Calculate a specific user's access level to an item.
   def calculate_access_level(self, users_group_ids):
      acl_id = Access_Level.denied
      for grpa in self.groups_access.itervalues():
         # Filter by user's group IDs since we load GIA records for all users.
         if grpa.group_id in users_group_ids:
            if Access_Level.is_more_privileged(grpa.access_level_id, acl_id):
               # E.g., if grpa.access_level_id < acl_id:
               acl_id = grpa.access_level_id
      g.assurt(Access_Level.is_valid(acl_id))
      return acl_id

   # ***

   #
   def prepare_and_save_item(self, qb, target_groups, rid_new, ref_item):

      g.assurt((rid_new == 1) or (rid_new == qb.item_mgr.rid_new))

      # This fcn. expects the object and its ref_item to be disparate.
      g.assurt(id(self) != id(ref_item))

      # New items may or may not be fresh, since this fcn. handles new and 
      # existing items.

      # New items objects are considered invalid until user perms are checked.
      g.assurt(not self.valid)

      # Correct the stack ID, if it needs correcting.
      g.assurt(self.stack_id) # Plus ou moins.
      self.stack_id_correct(qb)
      g.assurt(self.stack_id > 0)
      g.assurt((not self.fresh) or (self.version == 0))

      if self.client_id:
         qb.item_mgr.item_cache_del(self.client_id)
      #log.debug('prepare_and_save_item: item_cache: self: %s' % (self,))
      qb.item_mgr.item_cache_add(self, self.client_id)
      # Only add the ref_item to the item_cache if it's its own stack_id, i.e.,
      # add the split-from byway when adding the split-into byway, but if
      # you're copying an item from a parent branch and saving it to a leafier
      # branch, than ref_item is the same stack_id from a different branch.
      if (ref_item is not None) and (ref_item.stack_id != self.stack_id):
         log.verbose('prepare_and_save_item: item_cache: ref_item: %s'
                     % (ref_item,))
         qb.item_mgr.item_cache_add(ref_item, ref_item.client_id)

      # self.access_level_id may or may not be set. If the One() was
      # created using copy_from, self.access_level_id is the same as
      # ref_item. But sometimes it's None.
      g.assurt((self.access_level_id == Access_Level.invalid)
               or (self.version >= 1)
               or ((ref_item is not None) 
                   and (self.access_level_id == ref_item.access_level_id)))
      self.access_level_id = Access_Level.invalid

      if target_groups:
         # We're skipping Grac_Manager.prepare_item(). This path is used by
         # merge_job_import to skip the new item policies. It's possible for
         # the new item policies to default items as private to the user, so we
         # let the import code specify a different set of group accesses.
         # [1] You can also think of these as a Feature Class template, like 
         #     used in ArcGIS. I.e., the new item policies are one template, 
         #     and using the taml during import is another template.
         # NOTE: It is assumed the caller has verifed that the user is allowed 
         #       to create the group access permissions specified herein.

         # FIXME: 2013.04.25: This path should maybe be deprecated. We at least
         #        need access_style_id... which is what for these special
         #        items? So we should let user treat all items as 'permissive'
         #        by using the import featuer.
         #g.assurt(False) # Deprecated... okay, maybe later
         # What about?:
         #  g.assurt(self.access_style_id == Access_Style.permissive)
         # No, wait, there's no reason we can't call prepare_item and also
         # check against target_groups! Haha, that sounds like just the thing.

         groups_rights = qb.grac_mgr.create_rights_get(qb, self)
         g.assurt(groups_rights)
         the_style = qb.grac_mgr.get_style_from_rights(groups_rights)

         # NOTE: Skipping prepare_item, since we want to set groups_access
         #       ourselves. But we still do some grac_mgr-ish things here,
         #       like verifying the target_groups and setting access_style_id.
         self.access_style_id = the_style
         #self.style_change = style_change ??
         #g.assurt(ref_item is None)
         #prepared = grac_mgr.prepare_item(qb,
         #   self, Access_Level.editor, ref_item)
         #g.assurt(not grac_mgr.grac_errors)
         #g.assurt(prepared)
         self.style_change = None

         # MAYBE: This control block is very strict and fails on any
         # infraction. We might want to loosen it up -- like, if an item is
         # pub_editor and user sent us private target_groups, just record a
         # warning to the import output file and save the name item according
         # to its access_style_id (i.e., and ignore target_groups for this
         # item).

         # The target_groups dict is: gm/sid (key) => access level (val).
         grp_mship_or_id = target_groups.keys()[0]
         gp_sid = self.grp_mship_or_id_resolve(grp_mship_or_id)
         gm_acl = target_groups[grp_mship_or_id]

         access_granted = False
         # *** All-access and Permissive
         if self.access_style_id in (Access_Style.all_access,
                                     Access_Style.permissive,):
            access_granted = True
         # *** Restricted
         elif self.access_style_id == Access_Style.restricted:
            # User is allowed to twiddle user, pub, and stealth.
            for grp_mship_or_id, acl_id in target_groups.iteritems():
               gp_sid = self.grp_mship_or_id_resolve(grp_mship_or_id)
               if gp_sid in (group.Many.public_group_id(qb.db),
                             group.Many.stealth_group_id(qb.db),):
                  # User can set one of: denied, viewer, editor.
                  if not (acl_id in (Access_Level.editor,
                                     Access_Level.viewer,
                                     Access_Level.denied,)):
                     msg = ('prep_n_save_itm: %s: %s: acl_id %s / %s / %s'
                        % ('restricted-style access_style violation',
                           'unexpected: pub/stealth not editor/viewer/denied',
                           acl_id, str(self), gp_sid,))
                     log.warning(msg)
                     raise GWIS_Error(msg)
                  else:
                     access_granted = True
               elif ((qb.username != conf.anonymous_username)
                     and (gp_sid == group.Many.cp_group_private_id(
                                                qb.db, qb.username))):
                  if not (acl_id in (Access_Level.arbiter,
                                     Access_Level.denied,)):
                     msg = ('prep_n_save_itm: %s: %s: acl_id %s / %s / %s'
                        % ('restricted-style access_style violation',
                           'unexpected: private perms not arbiter/denied',
                           acl_id, str(self), gp_sid,))
                     log.warning(msg)
                     raise GWIS_Error(msg)
                  else:
                     access_granted = True
               else:
                  msg = ('prep_n_save_itm: %s: %s: %s / %s'
                     % ('restricted-style access_style violation',
                        'unexpected: user cannot add perms for group',
                        str(self), gp_sid,))
                  log.warning(msg)
                  raise GWIS_Error(msg)
            # end elif: self.access_style_id == Access_Style.restricted
         # *** Pub-Choice and Usr-Choice
         elif self.access_style_id in (Access_Style.pub_choice,
                                       Access_Style.usr_choice,):
            if len(target_groups) == 1:
               if ((gp_sid == group.Many.public_group_id(qb.db))
                   or ((qb.username != conf.anonymous_username)
                       and (gp_sid == group.Many.cp_group_private_id(
                                                   qb.db, qb.username)))):
                  if gm_acl != Access_Level.editor:
                     # BUG nnnn: Log warnings to the shapefile import job log
                     #           file and include in the download zip.
                     msg = ('prep_n_save_itm: %s: %s: acl_id %s / %s / %s'
                        % ('restricted-style access_style violation',
                           'unexpected: perms should be editor',
                           gm_acl, str(self), gp_sid,))
                     log.warning(msg)
                     # MAYBE: Rather than raise we could just change
                     #        permissions to editor... but what if
                     #        target_groups says viewer or denied? We
                     #        don't want to accidentally give better
                     #        permissions.
                     raise GWIS_Error(msg)
                  else:
                     access_granted = True
               else:
                  msg = ('prep_n_save_itm: %s: %s: %s / %s'
                     % ('itm_choice-style access_style violation',
                        'unexpected: user cannot add perms for group',
                        str(self), gp_sid,))
                  log.warning(msg)
                  raise GWIS_Error(msg)
            else:
               msg = ('prep_n_save_itm: %s: %s: %s / %s'
                  % ('itm_choice-style access_style violation',
                     'unexpected: user cannot add perms for groups',
                     str(self), len(target_groups),))
               log.warning(msg)
               raise GWIS_Error(msg)
         # *** Pub-Editor and Usr-Editor
         elif self.access_style_id == Access_Style.usr_editor:
            if ((len(target_groups) != 1)
                or (qb.username == conf.anonymous_username)
                or (gp_sid != group.Many.cp_group_private_id(qb.db,
                                                      qb.username))
                or (gm_acl != Access_Level.editor)):
               msg = ('prep_n_save_itm: %s: %s: %s / %s / %s'
                  % ('usr_editor-style access_style violation',
                     'unexpected: user cannot add perms for group(s)',
                     str(self), len(target_groups), gp_sid,))
               log.warning(msg)
               raise GWIS_Error(msg)
            else:
               access_granted = True
         elif self.access_style_id == Access_Style.pub_editor:
            if ((len(target_groups) != 1)
                or (gp_sid != group.Many.public_group_id(qb.db))
                or (gm_acl != Access_Level.editor)):
               msg = ('prep_n_save_itm: %s: %s: %s / %s / %s'
                  % ('pub_editor-style access_style violation',
                     'unexpected: user cannot add perms for group(s)',
                     str(self), len(target_groups), gp_sid,))
               log.warning(msg)
               raise GWIS_Error(msg)
            else:
               access_granted = True
         # *** Nothingset and All-Denied
         else:
            g.assurt(self.access_style_id == Access_Style.all_denied)
            msg = ('prep_n_save_itm: %s: %s: %s / %s / %s'
               % ('restricted-style access_style violation',
                  'unexpected: group cannot create item',
                  str(self), len(target_groups), gp_sid,))
            log.warning(msg)
            raise GWIS_Error(msg)

         # Currently, it's all or nothing. We don't correct any mistakes the
         # caller may have made. So we either raised an exception already or
         # we've approved the user's target_groups.
         g.assurt(access_granted)

         #if self.groups_access:
         #   log.debug('prepare_and_save_item: resetting groups_access: %s'
         #             % (self,))
         #g.assurt(self.groups_access is None)
         self.groups_access = {}
         self.latest_infer_id = None
         self.latest_infer_username = None
         session_id = None
         for grp_mship_or_id, acl_id in target_groups.iteritems():
            group_id = self.grp_mship_or_id_resolve(grp_mship_or_id)
            self.group_access_add_or_update(qb,
               (group_id, acl_id, session_id,),
               #item_base.One.dirty_reason_item_user
               item_base.One.dirty_reason_grac_user)
         # Keep validize happy; set the access level to editor or better.
         self.access_level_id = Access_Level.editor
         # If specifying target_groups, item must be new. Else, we'd ref_item.
         is_new_item = (self.version == 0)
         log.verbose2('prepare_and_save_item: validize: is_new_item: %s / %s'
                      % (is_new_item, self,))
         self.validize(
            qb, is_new_item, item_base.One.dirty_reason_item_user, None)
      # end if: target_groups
      else: # not target_groups:
         g.assurt((ref_item is not None) and ref_item.groups_access)
         # Prepare the group_item_access records using the GrAC manager. This 
         # copies the reference item's group_item_access records and is
         # generally used when splitting byways (since the split byways should
         # inherit those GIAs of the split-from byway). Using the grac_mgr
         # object here couples the item class to grac_mgr, but those two
         # classes are already pretty intimate.

         log.verbose2('prepare_and_save_item: prepare_item: %s' % (self,))

         prepared = qb.grac_mgr.prepare_item(qb,
            self, Access_Level.editor, ref_item)
         g.assurt(not qb.grac_mgr.grac_errors)

         g.assurt(prepared)

      g.assurt(self.valid)
      g.assurt(self.access_level_id <= Access_Level.editor)
      g.assurt(not self.groups_access_not_required) # No routes or tracks
      g.assurt(len(self.groups_access) > 0)

      self.version_finalize_and_increment(qb, rid_new)

      log.verbose1('prepare_and_save_item: saving item: %s' % (self,))

      # NOTE: qb.db.integrity_errs_okay isn't set, so a duplicate key violation
      #       -- psycopg2.IntegrityError -- will be raised if we're trying to
      #       save a duplicate row.
      try:
         self.save(qb, rid_new)
      except psycopg2.IntegrityError, e:
         log.error('prepare_and_save_item: failed: %s / %s' % (str(e), self,))
         #conf.break_here('ccpv3')
         # EXPLAIN: Are we specifically not raising our own exception so
         #          that the IntegrityError propagates upwards?
         #raise GWIS_Error('Problem saving item to db: %s' % (str(self),))
         raise

      log.verbose('prepare_and_save_item: saved: %s' % (self,))

   #
   def grp_mship_or_id_resolve(self, grp_mship_or_id):
      try:
         group_id = int(grp_mship_or_id)
      except TypeError:
         g.assurt(isinstance(grp_mship_or_id, groupy_base.One))
         group_id = grp_mship_or_id.group_id
      return group_id

   # ***

   #
   # If the item ID is different, then the item has changed. If the 
   # branch ID is different, then the user's access has changed (but 
   # see below: we don't currently detect all user access changes).
   def diff_compare(self, other):
      different = ((self.system_id != other.system_id)
                   or (self.branch_id != other.branch_id))
      # MAYBE: Check other attributes, too?
      return different

   # ***

# ***

class Many(item_revisionless.Many):
   '''
   The hierarchy of Many classes is used to fetch items on behalf of a
   particular user, ensuring that only those items the user has access to
   are fetched.
   '''

   one_class = One

   # *** SQL Clauses setup

   # Since our repository uses stacked branching, we can't exclude deleted
   # items in the where-clause when searching for items, like Ccpv1 does. E.g.,
   # if an item is deleted in a leaf branch but not in a parent, if we search
   # "where not deleted", we'll find the parent item but not the child item. 
   # Since we don't always want to send information about deleted items to the
   # client, we either have to wrap the SQL query in an outer select that
   # removes the uninteresting rows, or we have to go through the rows in
   # Python and extract those we find boring. Since using a wrapped-select 
   # is cool -- and not to mention useful for doing other things -- the sql
   # clauses object that this class seeds and the descendant classes clone and
   # further populate is composed of two sets of clauses: one for the inner
   # select and one for the outer select. In most cases, classes only care
   # about the inner select; the outer select is mostly used to duplicate the
   # columns selected by the inner select.

   # **** SQL: Normal item query

   # NOTE: Not cloning parent's clauses, but creating anew. Derived classes
   #       should do the same -- that is, copy, don't overwrite.
   sql_clauses_cols_all = item_query_builder.Sql_Bi_Clauses()
   #sql_clauses_cols_all.source = 'iua/all'

   # NOTE: In the basic select, MAX(gr.access_scope_id) misses groups the user 
   #       does not belong to, so access_scope could be under-scoped. E.g., 
   #       a user has a private item that is also part of a shared group the
   #       user is not part of.  This case seems strange and unlikely, and
   #       also the user is not part of the groups missed, so it's technically
   #       correct that the user would not know the item's true scope ('cause 
   #       that's just the nature of the beast). 
   # BUG nnnn: Maybe auditor.sql should check for this weird case.
   # DOCUMENT: Access Scope is relative to user's groups. E.g., if user has a
   #           private item and shares it with a group to which they are not a 
   #           member, the item's access scope will still be private.
   # Taking the maximum access scope gives the item's most exposure to users.
   # NOTE: We use distinct to elimate duplicate rows, since the user may have 
   #       access to the same item through more than one group_membership.
   #       See more about distinct in the SQL docs:
   #     http://www.postgresql.org/docs/8.3/static/sql-select.html#SQL-DISTINCT

   # CAVEAT: Because of the DISTINCT ON, please do not add aggregate functions
   # to the inner select list: all you'll do is aggregate the first row that
   # matches the distinct.
   #
   # SELECT DISTINCT ON (eggs) eggs, addme
   #    FROM (      SELECT 'spam' AS eggs, 2 AS addme
   #          UNION SELECT 'maps' AS eggs, 3 AS addme) AS bacon
   #    ORDER BY eggs;
   #
   # SELECT DISTINCT ON (eggs) eggs, MIN(addme), MAX(addme), COUNT(*), butter
   #    FROM (      SELECT 'spam' AS eggs,  2 AS addme, 'a' AS butter
   #          UNION SELECT 'spam' AS eggs,  3 AS addme, 'b' AS butter
   #          UNION SELECT 'maps' AS eggs, -1 AS addme, 'c' AS butter
   #          UNION SELECT 'maps' AS eggs,  1 AS addme, 'd' AS butter
   #             ) AS bacon
   #    GROUP BY eggs, addme, butter
   #    ORDER BY eggs, addme ASC;
   # 
   #    GROUP BY eggs
   #    ORDER BY eggs;

   sql_clauses_cols_all.inner.enabled = True

   # NOTE: DISTINCT ON () is possibly discouraged, since it's not standard SQL:
   #        http://www.postgresql.org/docs/8.4/static/
   #           queries-select-lists.html#QUERIES-DISTINCT
   #       "With judicious use of GROUP BY and subqueries in FROM, this
   #        construct can be avoided, but it is often the most convenient
   #        alternative." Ya betcha! If we were to replace DISTINCT ON (),
   #        we'd have to move the columns being distincted on to the GROUP BY
   #        clause (and we're pretty good about grouping-by, by-the-way), and
   #        then we'd have to either do a smaller select within a larger
   #        select, or we'd have to wrap all the non-distinct-on columns with
   #        the FIRST() aggregate, with is a nasty beast.
   sql_clauses_cols_all.inner.select = (
      """
        DISTINCT ON (gia.stack_id)
        gia.stack_id
      , gia.branch_id
      , gia.acl_grouping
      , gia.access_level_id
      , gia.item_id AS system_id
      , gia.version
      , gia.deleted
      , gia.reverted
      , gia.name
      , gia.valid_start_rid
      , gia.valid_until_rid
      """)

   g.assurt(not sql_clauses_cols_all.inner.shared)

   # Group-by is needed to figure out the access scope. It's also used by sub-
   # classes and others that add aggregate fcns. to the select.
   # NOTE: Group-by is expensive in the inner select when paginating.
   # We used to always enable the group-by but not it's as-needed.
   # Not here: sql_clauses_cols_all.inner.group_by_enable = True
   g.assurt(not sql_clauses_cols_all.inner.group_by_enable)
   sql_clauses_cols_all.inner.group_by = (
      """
        gia.stack_id
      , gia.branch_id
      , gia.acl_grouping
      , gia.access_level_id
      , gia.item_id
      , gia.version
      , gia.deleted
      , gia.reverted
      , gia.name
      , gia.valid_start_rid
      , gia.valid_until_rid
      """)

   # To use distinct-on item_id, it's gotta be left-most in the order-by,
   # followed by the other columns we use for ordering.
   # 1. Since our item respository uses stacked branching, we have to order by 
   #    stack_id, not system_id.
   # 2. Since we enforce the policy that a child branch ID is always less than
   #    any of its parents' branch IDs, if we sort by descending branch ID, the
   #    first item(s) in the list will be the leafiest items in the results.
   # BUG nnnn: Add (2.) to auditor.
   # 3. Since the best access level is owner -- or 1 -- we can order by
   #    ascending access level ID to get the user's best access to each item.
   # 4. For nice ordering when paginating, order by stack_id DESC, so latest 
   #    items are shown first. This is useful for classes that don't do thei
   #    own ordering.
   # BUG nnnn: Auditor.sql: check all access level IDs are 1 <= n <= denied

   # SYNC_ME: add_constraints/sql_clauses_cols_all.inner.order_by
   sql_clauses_cols_all.inner.order_by_enable = True

   # 2013.03.27: Is order by version even relevant? Since we always use a
   #             valid_*_rid filter, you'd think version is always the same
   #             for each gia record. Unless item is edited and a new GIA
   #             record is created but old ones aren't updated, which is a dev
   #             failure. So, yeah, version is probably always the same...
   sql_clauses_cols_all.inner.order_by = (
      """
        gia.stack_id ASC
      , gia.branch_id DESC
      , gia.version DESC
      , gia.acl_grouping DESC
      , gia.access_level_id ASC
      """)

   # Welcome to the Outer Limits.
   # Welcome to the Scary Door.
   # Welcome to the Outer Select.

   g.assurt(not sql_clauses_cols_all.outer.enabled)

   sql_clauses_cols_all.outer.select = (
      """
        group_item.stack_id
      , group_item.branch_id
      , group_item.acl_grouping
      , group_item.access_level_id
      , group_item.system_id
      , group_item.version
      , group_item.deleted
      , group_item.reverted
      , group_item.name
      , group_item.valid_start_rid
      , group_item.valid_until_rid
      """)

   g.assurt(not sql_clauses_cols_all.outer.shared)
   #sql_clauses_cols_all.outer.shared = (
   #   """
   #   , group_item.name
   #   """)

   g.assurt(not sql_clauses_cols_all.outer.where)

   # NOTE: Not setting sql_clauses_cols_all.outer.group_by_enable
   sql_clauses_cols_all.outer.group_by = (
      """
        group_item.stack_id
      , group_item.branch_id
      , group_item.acl_grouping
      , group_item.access_level_id
      , group_item.system_id
      , group_item.version
      , group_item.deleted
      , group_item.reverted
      , group_item.name
      , group_item.valid_start_rid
      , group_item.valid_until_rid
      """)

   # NOTE: Not setting sql_clauses_cols_all.outer.order_by_enable
   # 2012.05.15: I [lb] think this isn't actually necessary. [mm] figured out 
   #             the problem with geocoding returning funny node_endpoints, and
   #             while I investigated, well, what outer.order_by used to be
   #             used for, it no longer is. The inner order by does the exact
   #             same thing, so this is redundant, yes?
   #sql_clauses_cols_all.outer.order_by = (
   #   """
   #   group_item.stack_id ASC
   #   , group_item.branch_id DESC
   #   , group_item.version DESC
   #   , group_item.acl_grouping DESC
   #   , group_item.access_level_id ASC
   #   """)
   g.assurt(not sql_clauses_cols_all.outer.order_by)

   # **** SQL: Lightweight item query

   sql_clauses_cols_name = item_query_builder.Sql_Bi_Clauses()

   sql_clauses_cols_name.inner.select = (
      """
        DISTINCT ON (gia.stack_id)
        gia.stack_id
      , gia.branch_id
      , gia.acl_grouping
      , gia.access_level_id
      , gia.version
      , gia.deleted
      , gia.reverted
      , gia.name
      """)

   g.assurt(not sql_clauses_cols_name.inner.shared)

   g.assurt(not sql_clauses_cols_name.inner.group_by_enable)
   g.assurt(not sql_clauses_cols_name.inner.group_by)
   # Can we not use group by?
   # sql_clauses_cols_name.inner.group_by_enable = True
   sql_clauses_cols_name.inner.group_by = (
      """
        gia.stack_id
      , gia.branch_id
      , gia.acl_grouping
      , gia.access_level_id
      , gia.version
      , gia.deleted
      , gia.reverted
      , gia.name
      """)

   g.assurt(not sql_clauses_cols_name.inner.order_by_enable)
   g.assurt(not sql_clauses_cols_name.inner.order_by)
   sql_clauses_cols_name.inner.order_by_enable = True
   sql_clauses_cols_name.inner.order_by = (
      """
        gia.stack_id ASC
      , gia.branch_id DESC
      , gia.acl_grouping DESC
      , gia.access_level_id ASC
      """)

   # The outer clauseses.

   sql_clauses_cols_name.outer.select = (
      """
        group_item.stack_id
      , group_item.acl_grouping
      , group_item.access_level_id
      , group_item.name
      """)

   g.assurt(not sql_clauses_cols_name.outer.shared)

   g.assurt(not sql_clauses_cols_name.outer.where)

   g.assurt(not sql_clauses_cols_name.outer.group_by_enable)
   g.assurt(not sql_clauses_cols_name.outer.group_by)
   # NOTE: Not setting sql_clauses_cols_name.outer.group_by_enable
   sql_clauses_cols_name.outer.group_by = (
      """
        group_item.stack_id
      , group_item.acl_grouping
      , group_item.access_level_id
      , group_item.name
      """)

   g.assurt(not sql_clauses_cols_name.outer.order_by_enable)
   g.assurt(not sql_clauses_cols_name.outer.order_by)
   # NOTE: Not setting sql_clauses_cols_name.outer.order_by_enable
   # FIXME: Not sure this order by might not be always necessary... maybe just
   #        for pagination
   sql_clauses_cols_name.outer.order_by = (
      """
        group_item.stack_id ASC
      , group_item.branch_id DESC
      , group_item.acl_grouping DESC
      , group_item.access_level_id ASC
      """)

   # *** Constructor

   __slots__ = ()

   def __init__(self):
      item_revisionless.Many.__init__(self)

   # *** SQL statement maker helpers // phrase makers and whatnot

   #
   def search_item_type_id_sql(self, qb):

      where_clause = ""

      # We used to require that callers always fetched specific item types
      # (i.e., homogeneous fetches). But sometimes this is limiting, as in
      # the case of work items, in which case we don't filter by item type.
      # And in other cases, it's nice to let the client fetch basic item
      # details without having to fetch the whole item, as in the case of
      # determining an item's access_style_id (which lives in the item_stack
      # table which isn't joined except when requested).

      resolve_item_type = False

      if qb.filters.force_resolve_item_type:
         resolve_item_type = True

      # In most cases, the caller specifies a leafy item type.
      if ((self.one_class.child_item_types is None)
          and (self.one_class.item_type_id is not None)):
         try:
            where_clause = (" (gia.item_type_id = %d) "
                            % (self.one_class.item_type_id,))
         except TypeError, e:
            raise
      elif self.one_class.child_item_types:
         # This is an intermediate class, e.g., Attachment or Geofeature.
         # Filter by the item types of its children.
         where_clause = (" (gia.item_type_id IN (%s)) " 
                         % (','.join([str(x) for x in
                            self.one_class.child_item_types]),))
         resolve_item_type = True
      else:
         # This is an intermediate class that support all item types.
         # Presently, this'un is the only class to not define
         # child_item_types.
         # 2013.04.04: This assert isn't necessary but it verifies this new
         # feature (child_item_types) is only used as intended. Which is
         # currently to ask for a specific item(s)'(s) access_style_id(s).
         # 2013.04.18: We'll get here from search_by_stack_id, so this fails:
         # Skip: g.assurt(qb.filters.only_stack_ids)
         # DEVS: Here's a good test:
         # ./ccp.py -r -t item_user_access -I 983982 -f include_item_stack 1
         resolve_item_type = True

      if resolve_item_type:
         # Include the item type ID so the caller can resolve stack IDs to
         # types. Note that item_type_id is a class attribute, so use a
         # different name.
         qb.sql_clauses.inner.select += (
            " , gia.item_type_id AS real_item_type_id")
         qb.sql_clauses.inner.group_by += (
            " , gia.item_type_id ")
         qb.sql_clauses.outer.select += (
            " , group_item.real_item_type_id ")
         qb.sql_clauses.outer.group_by += (
            " , group_item.real_item_type_id ")

      return where_clause

   # *** SQL query_filters helper

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      g.assurt((not conjunction) or (conjunction == "AND"))

      # Double-check that the programmer called Query_Overlord.
      if ((not qb.filters.setting_multi_geometry)
          and (qb.filters.filter_by_regions 
               or qb.filters.filter_by_watch_geom)):
         if not qb.filters.only_in_multi_geometry:
            # FIXME: This might also happen if user filters by region (a) with
            # nothing in it or (b) that doesn't exist. In either case, the
            # query should not make it this far, right?
            log.error('sql_apply_query_filters: programmer error')
            g.assurt(False)

      if qb.filters.stack_id_table_ref:
         qb.sql_clauses.inner.join += (
            """
            JOIN %s AS stack_ids_ref
               ON (stack_ids_ref.stack_id = gia.stack_id)
            """ % (qb.filters.stack_id_table_ref,))

      # NOTE: If you have hundreds or thousands of stack_ids, consider using 
      # the temporary join table instead (see stack_id_table_ref).
      #
      if qb.filters.only_stack_ids:
         where_clause += (" %s (gia.stack_id IN (%s))"
                          % (conjunction, qb.filters.only_stack_ids,))
         conjunction = "AND"

      # The only_system_id filter is used to get an historic version of a
      # single item. With this filter, the client would need to have got an
      # item's history first, or the client must really just care about a
      # specific item version (e.g., Landmarks exp., where they're hardcoded).
      if qb.filters.only_system_id:
         where_clause += (" %s (gia.item_id = %d)"
                          % (conjunction, qb.filters.only_system_id,))
         conjunction = "AND"

      # FIXME: Revisit this filter- who uses it?
      # FIXME: See also search_item_type_id_sql, 
      #        which does gia.item_type_id == ....
      #        But note that we OR here, and the other one ANDs.
      if qb.filters.only_item_type_ids:
         where_clause += (" %s (gia.item_type_id IN (%s)) "
                          % (conjunction, qb.filters.only_item_type_ids,))
         conjunction = "AND"

      return item_revisionless.Many.sql_apply_query_filters(
                     self, qb, where_clause, conjunction)

   #
   def sql_apply_query_filter_by_text(self, qb, table_cols, stop_words,
                                                use_outer=False):
      # Note that we insert at 0 rather than appending, so that name is
      # first in the ORDER BY list.
      if not use_outer:
         table_cols.insert(0, 'gia.name')
      else:
         table_cols.insert(0, 'group_item.name')
      return item_revisionless.Many.sql_apply_query_filter_by_text(
                        self, qb, table_cols, stop_words, use_outer)
      
   # *** Query Builder functions

   #
   # MAYBE: The new convention is that qb comes first in the parms list. 
   #        So these parms are backwards. We will have to get rid of 
   #        query_builderer.
   def search_by_stack_id(self, stack_id, *args, **kwargs):
      '''
      Searches for the item specified by stack_id at the specified revision.
      Appends the item, if found, to the Many instance (which derives from 
      list).
      '''
      # This fcn. is mutually excl. of using some filters. It's used to find 
      # zero or one records by stack ID, so generally using filters to restrict
      # the query would be odd. But some of the filters affect the results,
      # like using skip_geometry_svg, which MetC import does.
      # NOTE: There's a filter options,
      #         qb.filters.only_stack_ids = str(stack_id)
      #       that has the same effect as calling this fcn. But the filter
      #       option also accepts a list of stack IDs.
      qb = self.query_builderer(*args, **kwargs)
      # MAYBE: We probably don't need to clone, do we? qb.sql_clauses always
      # gets fiddled with... so callers never expect it to be the same after
      # SQLing...? Ug... wish I [lb] knew. Cloning just to be safe, since this
      # is the original code.
      self.sql_clauses_cols_setup(qb)
      # 2013.09.06: This prevents qb.filters.get_id_count from working.
      # qb.sql_clauses.inner.where += (" AND gia.stack_id = %d " % (stack_id,))
      # So use qb.filters.only_stack_ids instead of injecting SQL directly.
      g.assurt(qb.filters.only_stack_ids == '')
      qb.filters.only_stack_ids = str(stack_id)
      # Get the item, or nothing.
      self.search_get_items(qb)
      g.assurt((not self) or (len(self) == 1))
      # Maybe lock the corresponding item_versioned row for the caller. 
      if qb.request_lock_for_update:
         self.searched_lock_items(qb)
      # 2013.09.25: D'oh!n't forget to cleanup...
      qb.filters.only_stack_ids = ''

   #
   # This fcn. locks the rows of items in the item_versioned table using
   # system_id. It's currently just used by search_by_stack_id when
   # qb.request_lock_for_update is set. Locking rows is useful for, e.g.,
   # working with work items, to prevent other threads from working with the
   # same work item, since work items are Nonwiki items (whose version, and
   # system_id, never changes).
   def searched_lock_items(self, qb):
      # NOTE: It we wanted to lock multiple items, we'd have to make sure our
      # threads always lock them in order. If we didn't, e.g., if one thread
      # locked ID 2 and then wanted to lock ID 1, but another thread locked ID
      # 1 and then tried to lock ID 2, we'd have a deadlock. Which,
      # surprisingly (at least to [lb]), Postgres will actually detect,
      # "ERROR:  deadlock detected". (Note also that this doesn't matter for
      # FOR SHARE OF, but just for FOR UPDATE OF and getting table locks.)
      system_ids = [ an_item.system_id for an_item in self ]
      if len(system_ids) > 1:
         log.warning(
            'searched_lock_items: locking multiple rows is experimental.')
         system_ids.sort()
      for system_id in system_ids:
         self.searched_lock_item_system_id(qb, system_id)

   #
   def searched_lock_item_system_id(self, qb, system_id):
      # Get a row-lock now. If we had tried earlier in the original query
      # we'd be griped. "NotSupportedError:  SELECT FOR UPDATE/SHARE 
      #                          is not allowed with DISTINCT clause"
      #stack_trace = traceback.format_exc()
      #log.warning('search_by_stack_id: stack: %s' % (stack_trace,))
      log.verbose('search_by_stack_id: row-locking item: system_id: %d' 
                  % (system_id,))

      rows = qb.db.sql(
         """
         SELECT 
            system_id 
         FROM 
            item_versioned 
         WHERE 
             system_id = %s
         FOR UPDATE OF 
            item_versioned
         """, (system_id,))
      g.assurt(len(rows) == 1)

   # ***

   #
   def search_for_names(self, *args, **kwargs):
      # This is called by gwis.command_.item_names_get.
      qb = self.query_builderer(*args, **kwargs)
      qb.filters.results_style = 'rezs_names'
      self.search_for_items(qb)

   # ***

   #
   def sql_clauses_cols_setup(self, qb):
      if ((not qb.filters.results_style)
          or (qb.filters.results_style == 'rezs_all')):
         sql_clauses = self.sql_clauses_cols_all.clone()
      elif qb.filters.results_style == 'rezs_names':
         sql_clauses = self.sql_clauses_cols_name.clone()
      else:
         raise GWIS_Error('Unknown results_style: %s'
                          % (qb.filters.results_style,))
      qb.sql_clauses = sql_clauses

   #
   def search_for_items(self, *args, **kwargs):
      ''' '''
      # NOTE: This fcn. is called by geofeature.Many and link_value.Many, but 
      #       not by attachment.Many, which implements it a bit differently.
      qb = self.query_builderer(*args, **kwargs)
      self.sql_clauses_cols_setup(qb)
      self.search_get_items(qb)

   #
   def search_for_items_clever(self, *args, **kwargs):
      self.search_for_items_simple(*args, **kwargs)

   #
   def search_for_items_simple(self, *args, **kwargs):

      qb = self.query_builderer(*args, **kwargs)

      # This fcn. is used by ccp.py and the checkout command. Usually, it just
      # calls the normal search_for_items. But for diff, we perform multiple
      # search_for_items. Also, the geofeature derived class overrides this
      # fcn. so it can load geofeatures and link_values.

      # Neither ccp.py nor the checkout command use the dont_fetchall option;
      # they expect the Many() object to be hydrated when this call returns.
      g.assurt(not qb.db.dont_fetchall)

      # We'll probably create a temporary table, so start a r/w op.
      if qb.db.locked_tables is None:
         qb.db.transaction_begin_rw()

      if not isinstance(qb.revision, revision.Diff):

         self.search_for_items_load(qb, diff_group=None)

      else:

         self.search_for_items_diff(qb)

      qb.db.curs_recycle()

   # 
   def search_for_items_diff(self, qb):

      rev = qb.revision

      rev_new = revision.Historic(rev.rid_new, rev.gids)
      rev_old = revision.Historic(rev.rid_old, rev.gids)

      g.assurt(qb.branch_hier[0][1] == rev_new)

      hier_new = qb.branch_hier
      hier_new[0] = (qb.branch_hier[0][0], rev_new, qb.branch_hier[0][2])
      hier_old = qb.diff_hier
      hier_old[0] = (qb.diff_hier[0][0], rev_old, qb.diff_hier[0][2])

      qb.revision = rev_new
      # I know we haven't changed qb.branch_hier but this is for parallelism
      # with the next bit of code.
      # Also, skipping: branch_hier_set, since we've already done what it does.
      qb.branch_hier = hier_new
      qb.item_mgr.clear_cache()
      #
      self.search_for_items_diff_search(qb, diff_group='latter')

      #log.debug('search_for_items_diff: cparts: %s' % (qb.diff_counterparts,))
      #log.debug('search_for_items_diff: ditems: %s' % (qb.diff_items,))

      qb.revision = rev_old
      qb.branch_hier = hier_old
      # Clear the Item_Manager so it refreshes the attc cache to earlier.
      qb.item_mgr.clear_cache()
      #
      if qb.revision.rid > hier_old[0][1].rid:
         # If the first revision in the branch_hier is less than the former 
         # revision, it means the branch did not exist at the former revision.
         # So we don't need to bother with the query.
         log.debug('search_for_items_diff: skipping former')
         pass
      else:
         self.search_for_items_diff_search(qb, diff_group='former')

      #log.debug('search_for_items_diff: cparts: %s' % (qb.diff_counterparts,))
      #log.debug('search_for_items_diff: ditems: %s' % (qb.diff_items,))

      # If there are items still in diff_items, it means we found them in the
      # latter revision but not the former. So make a counterpart search for
      # former.
      for an_item in qb.diff_items.itervalues():
         self.search_get_items_add_item(qb, an_item, 'latter', 'former')

      #log.debug('search_for_items_diff: cparts: %s' % (qb.diff_counterparts,))
      #log.debug('search_for_items_diff: ditems: %s' % (qb.diff_items,))

      qb.revision = rev
      qb.branch_hier = hier_new

      # For items found only in 'latter' or only in 'former', double check
      # that the other item doesn't really exist.
      # MAYBE: Use generator to collect items. Probably not necessary.
      self.search_get_item_counterparts(qb, rev_new, rev_old)

      #log.debug('search_for_items_diff: cparts: %s' % (qb.diff_counterparts,))
      #log.debug('search_for_items_diff: ditems: %s' % (qb.diff_items,))

   #
   def search_get_item_counterparts(self, qb, rev_new, rev_old):

      # If we're using a viewport filter, we might not have found counterpart
      # items because they were moved outside the bbox. But even if we're not
      # using a viewport filter, we might not see the counterpart item because
      # it's deleted or restricted, which we can at least tell the user about.

      rev = qb.revision
      hier_new = qb.branch_hier
      hier_old = qb.diff_hier

      for diff_group in ['latter', 'former',]:

         # qb.diff_items
         if qb.diff_counterparts[diff_group]:

            qb_c = qb.clone(skip_clauses=True, skip_filtport=True, 
                            db_clone=True)
            g.assurt((not qb_c.filters.results_style)
                     or (qb_c.filters.results_style == 'rezs_all'))
            qb_c.sql_clauses = self.sql_clauses_cols_all.clone()

#         qb_c.diff_group = diff_group

            if diff_group == 'latter':
               qb_c.revision = rev_new
               qb_c.branch_hier = hier_new
            else:
               qb_c.revision = rev_old
               qb_c.branch_hier = hier_old

            g.assurt(not qb_c.revision.allow_deleted)
            g.assurt(not qb_c.filters.min_access_level)
            qb_c.revision.allow_deleted = True
            qb_c.filters.min_access_level = Access_Level.denied

            # MAYBE: Use temporary table and JOIN instead of using 
            #        WHERE ... IN ()
            qb_c.filters.only_stack_ids = ','.join([
               # qb.diff_items
               str(sid) for sid in qb.diff_counterparts[diff_group]])

#         sql = self.search_get_sql(qb)
#
#         # MAYBE: Use fetchone...
#         rows = qb.db.sql(sql)
#
#         log.debug('search_get_item_counterparts: found %d items.'
#                   % (len(rows),))

#         for row in rows:
#            new_item = self.get_one(qb, row)
#            self.search_get_items_add_item(qb, new_item)

            qb_c.revision.allow_deleted = False
            qb_c.filters.min_access_level = None

            self.search_get_item_counterparts_search(qb_c, diff_group)

            qb_c.db.close()

      qb.revision = rev
      qb.branch_hier = hier_new

   clever_fetchone = True
   #clever_fetchone = False

   #
   def search_for_items_load(self, qb, diff_group):
      if qb.filters.pagin_total:
         g.assurt(diff_group is None)
         self.search_for_items(qb)
      elif Many.clever_fetchone:
         # In lieu of calling self.search_for_items(qb), which calls 
         # psycopg2's fetchall, hydrate using fetchone.
         qb.item_mgr.load_items_quick(qb, self, 
            item_search_fcn='search_for_items', 
            processing_fcn=self.search_get_items_by_group_consume, 
            prog_log=None, keep_running=None, diff_group=diff_group)
      else:
         # This is similar to just calling search_for_items but with some
         # additional trace output.
         qb.item_mgr.search_for_wrap(qb, self, 'search_for_items', 
                                         keep_running=None)

   #
   def search_for_items_diff_search(self, qb, diff_group):
      self.search_for_items_load(qb, diff_group=diff_group)

   #
   def search_get_item_counterparts_search(self, qb, diff_group):
      qb.item_mgr.load_items_quick(qb, self, 'search_for_items', 
         self.search_get_item_counterparts_consume,
         prog_log=None, keep_running=None, diff_group=diff_group)

   #
   def search_get_item_counterparts_consume(self, qb, an_item, prog_log=None):
      g.assurt(qb.diff_group is not None)
      self.search_get_items_add_item(qb, an_item, qb.diff_group, None)

   # *** SQL statement makers

   #
   def search_get_items(self, qb):
      '''
      Uses the query builder to make an SQL SELECT statement and execute it.
      May or may not immediately hydrate the results and append to self,
      according to qb.db.dont_fetchall. Makes sure to check for leafier items
      if there's a geometric query or full text search, since leafy items might
      otherwise be missed by those query types.
      '''

      # FIXME: This assurt checks that qb.finalized has been called if
      # necessary. But it doesn't check for instances when a WHERE clause has
      # been changed to filter by geometry. E.g., search_by_distance changes
      # the WHERE to do a closest-to search, which means we need to
      # confirm_leafiness (so it sets it explicitly). We need to make sure
      # other places that edit inner. or outer.where also set
      # confirm_leafiness.
      g.assurt(qb.finalized or 
               (not (qb.filters.filter_by_regions
                     or qb.filters.filter_by_watch_geom
                     or qb.filters.only_in_multi_geometry
                     or (qb.viewport.include is not None)
                     or (isinstance(qb.revision, revision.Diff)))))
      g.assurt((qb.diff_group is None)
         or ((qb.diff_group == 'latter') 
             and (not qb.diff_items)
             and (not qb.diff_counterparts['latter'])
             and (not qb.diff_counterparts['former']))
         or (qb.diff_group == 'former'))

      # Prepare the meta-filters.
      qb.use_filters_and_viewport = True
      qb.use_limit_and_offset = not qb.filters.pagin_total

      # Get the search string.
      sql = self.search_get_sql(qb)

      #import rpdb2;rpdb2.start_embedded_debugger('password',fAllowRemote=True)
      #log.debug('sql %s' % sql)

      # Perform the query.
      if qb.filters.pagin_total:
         # Don't fetchall when just getting a count.
         if qb.db.dont_fetchall:
            log.warning('search_get_items: disabling dont_fetchall')
            qb.db.dont_fetchall = False
         # NOTE: The table_name 'item_count' is just the name of the XML
         # element.
         res = qb.db.table_to_dom('item_count', sql)
         log.verbose1('search_get_items: pagin_total: %s' % (res,))
         # Attach the XML doc. See item_base.Many.append_gml. The Many() 
         # object is derived from list; we're appending to ourselves.
         self.append(res)
      else:
         # Fetch items.
         #log.debug('search_get_items: sql: %s' % (sql,))
         res = qb.db.sql(sql)
         #log.debug('search_get_items: sql: done')
         # If fetching by geometric query and branchy, check for leafier items.
         if qb.confirm_leafiness:
            # Clone the qb but get a new db handle -- we're creating a
            # temporary table, and we don't want the other db cursors 
            # to see it, and we don't want to have to use a unique name.
            qb_leafy = qb.clone(skip_clauses=True, skip_filtport=True,
                                db_get_new=True)
            # Start a r/w transaction since we're creating a table.
            qb_leafy.db.transaction_begin_rw()
            table_name = 'temp_stack_id__iua'
            qb_leafy.prepare_temp_stack_id_table(table_name)
            g.assurt(not qb_leafy.leafier_stack_ids)
         if res is None:
            # The caller wants to fetch items one by one, most likely to
            # prevent Python from gobbling up memory that it won't later 
            # release (since Python doesn't give pages back to the OS).
            g.assurt(qb.db.dont_fetchall)
            g.assurt(not qb.diff_items)

            # [mm] has enabled diff_counterparts cloning as a part of qb 
            # cloning, so the assumptions behind these asserts are no longer
            # valid. (2013.05.14)
            # g.assurt(not qb.diff_counterparts['latter'])
            # g.assurt(not qb.diff_counterparts['former'])

            # But we still want to confirm_leafiness, maybe.
            if qb.confirm_leafiness:
               generator = qb.db.get_row_iter()
               self.leafier_check_rows(qb_leafy, generator, table_name)
               generator.close()
         else:
            if qb.confirm_leafiness:
               self.leafier_check_rows(qb_leafy, res, table_name)

         if qb.confirm_leafiness:
            self.leafier_search_items(qb, qb_leafy, table_name)
            # If we had cloned the db, we'd want to drop the temporary table
            # now. But we created a new connection, so we can just close it.
            qb_leafy.db.close()

         # If not dont_fetchall, hydrate the items now.
         if res is not None:
            g.assurt(not qb.db.dont_fetchall)
            for row in res:
               if ((not qb.confirm_leafiness) 
                     or (row['stack_id'] not in qb.leafier_stack_ids)):
                  item = self.get_one(qb, row)
                  self.search_get_items_by_group_consume(qb, item)
            # Add the 'latter' items, for which we didn't find a former 
            # counterpart. But there might be a counterpart- if searching by 
            # viewport, the counterpart may be outside the bbox.
            if qb.diff_group == 'former':
               for item_sid in qb.diff_items:
                  an_item = qb.diff_items[item_sid]
                  self.search_get_items_add_item(qb, an_item,
                                                 'latter', 'former')
            # NOTE: Don't call qb.db.curs_recycle() here; let callers do it.
         # else, since dont_fetchall, don't definalize yet.

      # FIXME: Is this right? Clear the clauses?
      #        If so, we really don't need to clone() in search_by_stack_id
      qb.sql_clauses = None

   #
   def leafier_check_rows(self, qb_leafy, rows, table_name):

      insert_rows = []
      for row in rows:
         if row['branch_id'] < qb_leafy.branch_hier[0][0]:
            insert_rows.append(
               '(%s, %s)' % (row['stack_id'], row['branch_id'],))
      if insert_rows:
         qb_leafy.db.sql(
            "INSERT INTO %s (stack_id, branch_id) VALUES %s"
            % (table_name, ','.join(insert_rows),))

   #
   def leafier_search_items(self, qb, qb_leafy, table_name):
      # NOTE: Not doing dont_fetchall here. Maybe not necessary?
      res = qb_leafy.db.sql(
         """
         SELECT
            DISTINCT (gia.stack_id) AS stack_id,
            gia.branch_id
         FROM
            group_item_access AS gia
         JOIN
            %s AS stack_ids_ref
               ON ((gia.stack_id = stack_ids_ref.stack_id)
                   AND (gia.branch_id > stack_ids_ref.branch_id))
         ORDER BY
            gia.stack_id ASC,
            gia.branch_id DESC
         """ % (table_name,), 
         force_fetchall=True)
      for row in res:
         qb.leafier_stack_ids.append(row['stack_id'])

   #
   def search_get_items_by_group_consume(self, qb, an_item, prog_log=None):
      if qb.diff_group is None:
         # Append each result item to this object (which is derived from list).
         self.search_get_items_add_item(qb, an_item)
      elif qb.diff_group == 'latter':
         # This is the first query, so we're populating the lookup.
         qb.diff_items[an_item.stack_id] = an_item
      else:
         # This is the second query, so see if the item is already in the
         # lookup.
         g.assurt(qb.diff_group == 'former')
         try:
            former = an_item
            latter = qb.diff_items[an_item.stack_id]
            # Delete the item from the lookup so we don't process it twice.
            del qb.diff_items[an_item.stack_id]
            # See if the item is the same or not.
            if former.diff_compare(latter):
               # Add the items as former and latter counterparts
               self.search_get_items_add_item(qb, latter, 'latter', None)
               self.search_get_items_add_item(qb, former, 'former', None)
            else:
               self.search_get_items_add_item(qb, latter, 'static', None)
         except KeyError:
            # The latter may not exist -- if not searching by viewport, then it
            # definitely does not exist; if searching by viewport, the item may
            # have just been moved outside the bbox.
            self.search_get_items_add_item(qb, former, 'former', 'latter')

   #
   def search_get_items_add_item_cb(self, qb, new_item, prog_log):
      self.search_get_items_add_item(qb, new_item)
      
   #
   def search_get_items_add_item(self, qb, new_item, 
                                       diff_group=None, 
                                       counterpart=None):
      # With Diff counterpart items, we don't check the access level or 
      # deleted until now, so that we can report as much to the user.
      min_acl_id = qb.filters.min_access_level or Access_Level.client
      log.verbose('adding item: acl: %d / min: %d / diff_group: %s' 
                  % (new_item.access_level_id, min_acl_id, diff_group,))
      if diff_group is None:
         diff_group = qb.diff_group
      else:
         g.assurt(isinstance(diff_group, basestring))
# item_names for region... no access_level_id...
      if new_item.access_level_id <= min_acl_id:
         if new_item.deleted or new_item.reverted:
            # 2013.03.26: What's the point of the simlified representation? It
            #             can't be a permissions problem. Is this just to save
            #             bandwidth? Anyway, [lb] wants additional item details
            #             for link_attributes_populate.py... I could just add
            #             them to the geo_one row, or I could just say, hey,
            #             why not return the complete item?
            # # Add a simplified representation of the item.
            # append_item = self.get_one(qb, 
            #    row={'stack_id': new_item.stack_id,
            #         'deleted': new_item.deleted,
            #         'reverted': new_item.reverted,})
            # [lb] thinks we can return the whole item. Even though it's
            #      deleted, its data is still interesting, right?
            append_item = new_item
         else:
            # Add the found item.
            append_item = new_item
      else:
         # Add a simplified version of the item.
         # NOTE: Usually, we don't reveal access denied, we just don't return
         # an item. But I [lb] think this is just used by revision.Updated,
         # which a client is not allowed to request.
         append_item = self.get_one(qb, 
            row={'stack_id': new_item.stack_id,
                 'access_level_id': Access_Level.denied,})
      append_item.diff_group = diff_group
      # Don't indicate deleted or access-denied unless former or latter.
      if (id(append_item) == id(new_item)) or (diff_group != 'static'):
         self.append(append_item)
      # See if we need to look later for the counterpart item. Counterpart is
      # set if we only found a 'latter' or a 'former' but not both.
      #if diff_group is not None:
      if (counterpart 
          and qb.use_filters_and_viewport 
          # FIXME: I [lb] don't like (am uncomfortable with) this check: are
          # there other reasons than just searching viewport that we'd want to
          # look for a counterpart item? (Or maybe this check is okay....)
          and qb.viewport 
          and qb.viewport.include is not None):
         g.assurt( ((diff_group == 'former') and (counterpart == 'latter'))
                or ((diff_group == 'latter') and (counterpart == 'former')))
         qb.diff_counterparts[diff_group].append(new_item.stack_id)

   # ***

   #
   # This fcn. returns a generator, which can be iterated over. E.g.,
   #    generator = items.results_get_iter(qb)
   #    for i in generator:
   #       pass # do something
   #    generator.close()
   # Alternatively, you can use generator.next(), but you'll need to catch the
   # StopIteration exception, which is thrown when there are no more items.
   def results_get_iter(self, qb):
      # Caller should not have qb.definalize()d.
      #log.verbose('results_get_iter: dont_fetchall: %s'
      #            % (qb.db.dont_fetchall,))
      g.assurt(qb.db.dont_fetchall)
      # Get the generator and loop.
      generator = qb.db.get_row_iter()
      for row in generator:
         if qb.confirm_leafiness and (row['stack_id'] in qb.leafier_stack_ids):
            log.debug('results_get_iter: skipping not-so-leafy result.')
            row = None
         if row is not None:
            # FIXME: Check access level? And what about deleted?
            min_acl_id = qb.filters.min_access_level or Access_Level.client
            #log.debug('results_get_iter: row: %s' % (str(row),))
            if not row.get('access_level_id', None):
               log.error('results_get_iter error: row: %s' % (str(row),))
            if row['access_level_id'] <= min_acl_id:
               # The item is okay for hydration.
               next_item = self.get_one(qb, row)
               #log.verbose('results_get_iter: dont_fetchall after get_one: %s'
               #            % (qb.db.dont_fetchall,))
               #next_item.diff_group = None
               yield next_item
            else:
               # EXPLAIN: Why would this happen? I.e., who searches for items
               # the user cannot access?
               log.warning('results_get_iter: user cannot access item')
         # else, we'll go through loop again, so caller never sees None.
      generator.close()

   # ***

   #
   def search_get_sql(self, qb):
      '''
      Creates an SQL query to retrieve access-controlled items for the given
      user at the given branch and revision. Uses SQL fragments in sql_clauses
      to construct the statement.
      '''

      g.assurt(qb.is_filled())
      g.assurt(qb.sql_clauses.is_clone)
      # FIXME: Doing this until confidence builds: compare sqlc before n' after
      dbg_sql_clauses_0 = qb.sql_clauses.clone()

      g.assurt(not isinstance(qb.revision, revision.Diff))
      # 2013.05.28: revision.Updated is okay w/ qb.filters.stack_id_table_ref.

      # Inner query

      iinterp = {}

      # From and Where clauses

      where_conj = ""

      # If the caller wants 0, 1, or all branches in the hierarchy.

      if qb.branch_hier:
         if qb.branch_hier_limit is None:
            # Use all branches.
            branch_hier = qb.branch_hier
         elif qb.branch_hier_limit == 1:
            # Use the leafiest branch.
            branch_hier = [qb.branch_hier[0],]
         elif qb.branch_hier_limit == -1:
            # Use the basemap branch. But fake it and use the leafiest revision
            # This is a hack for tags, which are only saved to the mainline.
            #   NO: branch_hier = [qb.branch_hier[-1],]
            br_base = qb.branch_hier[-1]
            branch_hier = [(br_base[0], qb.branch_hier[0][1], br_base[2],)]
         elif qb.branch_hier_limit == 0:
            # Use no branches.
            branch_hier = []
         else:
            g.assurt(False)
      else:
         branch_hier = []

      # We have to filter results according to which groups the user belongs.
      # There are two obvious ways to figure this out: join the user_ and
      # group_membership table, or throw a "group_id IN (...)" in the where 
      # clause. I [lb] added the latter for Diff, but I think either method is 
      # appropriate, so we'll leave this for now and maybe test the difference
      # in performance later (I bet you it's not noticeable).
      # 2013.02.04: Actually, it is noticeable. Using "group_id in" rather than
      # joining the user_, group_membship, and group_ tables is noticeably
      # faster. So this is new: always use gia_use_gids.
      gia_force_gids = True # Easy disable for DEVs.
      orig_gia_use_gids = qb.filters.gia_use_gids
      if ((gia_force_gids)
          and (qb.username)
          and (not qb.filters.gia_use_gids)):
         g.assurt(qb.user_id)
         g.assurt(not qb.filters.gia_userless)
         # If this next assert fires and you're using revision.Updated, you
         # probably forget to set qb.username='' and qb.gia_userless=True.
         g.assurt(qb.revision.gids)
         # NOTE: qb.revision.gids can be used in Historic mode for a user to
         #       see items to a group to which they used to belong. Is this a
         #       problem? If a user loses access to a group, do they lose
         #       Historic access? What about items someone accidentally makes
         #       public for one revision? Maybe it doesn't matter.
         # NOTE: We're using the user's GIDs at the revision of the topmost
         #       branch, but we don't use GIDs the user had at the parent
         #       branches' last_merge_rids. This is because, if the user is
         #       added to a group after the last_merge_rid of a branch, that
         #       user would not see items from the parent branch that haven't
         #       been edited.
         qb.filters.gia_use_gids = ','.join([str(x) for x in qb.revision.gids])
      # Note that use_filters_and_viewport has no influence on gia_use_gids.
      gids_where = []
      iinterp['gids_where'] = ""
      include_gids = False
      if ((not qb.username)
          or (qb.filters.gia_use_gids)
          or (qb.filters.gia_userless)
          or (isinstance(qb.revision, revision.Updated))):
         # These assurts make sure we don't let a client get around permissions
         g.assurt(qb.filters.gia_use_gids or qb.request_is_local)
         g.assurt(qb.filters.gia_use_gids or qb.request_is_script)
         g.assurt((not isinstance(qb.revision, revision.Updated)) 
                  or branch_hier)
         #
         iinterp['gia_from_clause'] = (
            """
            FROM group_item_access AS gia
            """)
         if qb.filters.gia_use_gids:
            if isinstance(qb.revision, revision.Updated):
               log.warning('Ignoring: gia_use_gids does not apply to Updated.')
            else:
               # [lb] is curious about the relationship btw. these two lists of
               #      group IDs:
               # log.debug('search_get_sql: qb.revision.gids:        %s'
               #           % (qb.revision.gids,))        # a list
               # log.debug('search_get_sql: qb.filters.gia_use_gids: %s'
               #           % (qb.filters.gia_use_gids,)) # a str
               gids_where.append(
                  """
                  gia.group_id IN (%s)
                  """ % (qb.filters.gia_use_gids,))
               # MAYBE/EXPLAIN: How does qb.filters.gia_use_gids compare to
               # qb.branch_hier's revisions which might have their own lists of
               # gids?
               # NO: It seems wrong to use GIDs in branch_hier_where_clause
               #        include_gids = True
               #     If you added a person to a group after last_merge_rid,
               #     they wouldn't see usedited items in the parent.
         # else: this is revision.Update, and we want items changed between two
         # revisions, or this is qb.filters.gia_userless, so leave gids_where
         # empty and don't filter by group IDs.
      else:
         # BUG 2652: We rely on a liberal join_collapse_limit to let the
         # postgres planner determine a good join order. But if you have a good
         # join order and set join_collapse_limit to 1, you'll see that you can
         # improve a 0.20 sec. search to 0.02 sec. So well worth the investment
         # of doing explicit join ordering.
         iinterp['gia_from_clause'] = (
            """
            FROM user_ AS u
            JOIN group_membership AS gm
               ON (u.id = gm.user_id)
            JOIN group_ AS gr
               ON (gm.group_id = gr.stack_id)
            JOIN group_item_access AS gia
               ON (gr.stack_id = gia.group_id)
            """)
         #
         # The group_membership query always excludes deleted, and it should
         # only check one revision (e.g., for Updated, this has the same effect
         # as Current, since Updated checks rid_inf).
         where_gm_rev = qb.revision.as_sql_where_strict('gm')
         where_gr_rev = qb.revision.as_sql_where_strict('gr')
         #
         first_gids_where = (
            """
            u.id = %d
            AND gm.access_level_id <= %d
            AND %s
            AND %s
            """ % (qb.user_id,
            # FIXME: If user lost access privileges, during Revision.Updated
            #        operation, client will not learn about lost privileges.
                   Access_Level.client,
                   where_gm_rev,
                   where_gr_rev,))
         #
         gids_where.append(first_gids_where)

      #
      if qb.filters.gia_use_sessid:
         # Using session ID with stealth secret doesn't work: the session ID
         # records will get filtered out. But maybe the user made a Web link
         # to an item they haven't saved to their item library? Ha.
         if qb.filters.use_stealth_secret:
            # Is this a problem? Or does it ever happen?
            log.warning(
               'search_get_sql: gia_use_sessid and use_stealth_secret?')
         #g.assurt(qb.session_id)
         g.assurt(gids_where) # Not expected for gia_userless or Updated.
         # Don't be too strict. If there's no session ID, don't sweat it.
         # Think ccp.py, right? or we should always expect a session ID...?
         if qb.session_id:
         #if (self.req is not None) and (self.req.client.session_id):
            # MAYBE: If we return these, how does application know which
            #        results are explicit to user and which are via session
            #        ID?
            or_where_session_id = (
               """
                   gia.group_id = %d
               AND gia.session_id = %s
               """ % (group.Many.session_group_id(qb.db),
                      qb.db.quoted(qb.session_id),))
            # Make sure finding by session ID doesn't trump unlibrariedness.
            if ((qb.filters.findability_recent)
                and (not qb.filters.findability_ignore)):
               or_where_session_id = (
                  """
                  %s
                  AND (   (usrf.show_in_history IS NULL)
                       OR (usrf.show_in_history IS TRUE))
                  """
                  % (or_where_session_id,))
            gids_where.append(or_where_session_id)

         else:
            log.warning('search_get_sql: missing: qb.session_id')

      #
      if qb.filters.use_stealth_secret:
         # We're not expecting to be called for gia_userless or Updated.
         g.assurt(gids_where)
         # We are expecting that gia_use_gids was specified, so we joined just
         # against the group_item_access table.
         g.assurt(qb.filters.gia_use_gids)
         # NOTE: It's costly to join item_stack in the inner clause, but
         #       it's more complicated if we don't, at least for
         #       stealth_secret. That's because the access level is computed
         #       based on the inner clause, so either we find all of the user's
         #       GIA records now, or we require the client to send two item
         #       requests (one with the stealth ID, and a second with the stack
         #       ID). But requiring the client to send two requests seems...
         #       weird. So we'll move the item_stack join inside the inner
         #       clause if a stealth secret is provided.
         gids_where.append(
            # Need this?: It's in the inner.where now:
            #  AND item_stack.stealth_secret = %s
            """
            gia.group_id = %d
            """ % (group.Many.stealth_group_id(qb.db),
                   #qb.db.quoted(qb.filters.use_stealth_secret),
                   ))
         # Per the last comment, find all records that match, and not just the
         # stealth group's record -- i.e., the user might have better
         # permissions through a private gia record.

      # There are zero, one, two, or three gids sub-clauses that we OR.
      if gids_where:
         iinterp['gids_where'] = " OR ".join(["(%s)" % x for x in gids_where])
         iinterp['gids_where'] = "(%s)" % (iinterp['gids_where'],)
         where_conj = "AND"
      else:
          g.assurt(qb.filters.gia_userless
                   or isinstance(qb.revision, revision.Updated))

      # If this is a leafy branch, we always use an outer select to reduce.
      if len(branch_hier) > 1:
         br_allow_deleted = True
      else:
         br_allow_deleted = qb.revision.allow_deleted

      iinterp['branch_where'] = ''
      iinterp['rev_where_gia'] = ''
      # We used to sometimes use the GIDs in the branch_hier, but we shouldn't.
      # We to supply our own GIDs filter using just the leafiest branch GIDs.
      g.assurt(not include_gids)
      # The revision is specified via the branch_hier. Unless there is no hier.
      if branch_hier:
         # DEV_CODE BEG
         if qb.revision != branch_hier[0][1]:
            # This happens when routed or tilecache wants an update of just
            # items changed between two revisions.
            g.assurt(isinstance(qb.revision, revision.Updated)) # tc: Historic
            g.assurt(isinstance(branch_hier[0][1], revision.Historic)) # tc Cur
         else:
            # 2013.04.04: Is this ever not the case?
            # [lb] is curious because revision.gids may differ
            g.assurt(qb.revision.gids == qb.branch_hier[0][1].gids)
            #
            g.assurt(id(qb.revision) == id(qb.branch_hier[0][1]))
            #
         # DEV_CODE EOL
         if (isinstance(qb.revision, revision.Current)
             or isinstance(qb.revision, revision.Historic)):
            # Restrict to branches at their proper parent last_merge_rid.
            iinterp['branch_where'] = ("%s %s"
               % (where_conj,
                  revision.Revision.branch_hier_where_clause(
                     branch_hier, 'gia', include_gids, br_allow_deleted),))
            where_conj = "AND"
         elif isinstance(qb.revision, revision.Updated):
            # Get items updated in any branch of the hierarchy, deleted or not.
            # This is only called from ccp.py.
            # 2014.05.10: Also called by tilecache and routed on hup, right?
            g.assurt(qb.request_is_local and qb.request_is_script)
            # The caller should have fetched all the IDs first -- currently, we
            # compile the list of geofeature stack IDs by looking at both
            # geofeatures that changed and also link_values that changed (and
            # grabbing their rhs_stack_id). If the caller did not specify this
            # table, we would end up fetching everything -- which is why we
            # don't call the class revision.Everything.
            g.assurt(qb.filters.stack_id_table_ref)
            # We're only interested in things that changed in the one branch.
            iinterp['branch_where'] = ("%s (gia.branch_id = %s)" 
                                       % (where_conj, branch_hier[0][0],))
            where_conj = "AND"
         else:
            # This is fetch-by-system-id.
            g.assurt(isinstance(qb.revision, revision.Comprehensive))
            # 2014.05.10: This is a new revision type. The client has a system
            # ID, which it got using the GWIS command, item_history_get, or
            # obtained by way of an experiment, like the landmarks experiment.
            # Note that the only difference between using a stack ID and using
            # a system ID is the latter doesn't check revision IDs and branch
            # IDs, but that both commands still check permissions.
            g.assurt(qb.revision.gids and qb.filters.gia_use_gids)
            # So, nothing to do.
            pass
      else:
         g.assurt(not isinstance(qb.revision, revision.Updated))
         iinterp['rev_where_gia'] = qb.revision.as_sql_where('gia', 
                                     include_gids, qb.revision.allow_deleted)
         iinterp['rev_where_gia'] = ("%s %s" 
                                     % (where_conj, iinterp['rev_where_gia'],))
         where_conj = "AND"

      # There are two ways derived classes can influence the where clause: by
      # overriding search_item_type_id_sql() (if they're the item type being
      # searched for) or by specifying where_item_type_id_fcn (if
      # they're not the item type being searched for).
      if qb.sql_clauses.inner.where_item_type_id_fcn:
         iinterp['where_type'] = qb.sql_clauses.inner.where_item_type_id_fcn(
                                                                           qb)
      else:
         iinterp['where_type'] = self.search_item_type_id_sql(qb)
      #
      if iinterp['where_type']:
         iinterp['where_type'] = "%s %s" % (where_conj, iinterp['where_type'],)
         where_conj = "AND"

      # If we're not checking out a leafy branch, we can omit records whose 
      # access level is worse than client (i.e., denied). Otherwise, we need to
      # make sure the select grabs the leafiest item, in case the user's access
      # is different in the branch.
      iinterp['access_level_where'] = ""
      # NOTE: Use <= in case branch_hier is empty, meaning user wants a list of
      #       branches.
      min_acl_id = qb.filters.min_access_level or Access_Level.client
      if ((len(branch_hier) <= 1) and (qb.diff_group is None)):
         iinterp['access_level_where'] = (
            """
            gia.access_level_id <= %d
            """ % (min_acl_id,))
      # No matter what, if the branch_hier is greater than 1, we have to use an
      # outer query. This is because, if the leafy item is denied or deleted,
      # the query would otherwise select any parent item that is neither.
      elif ((len(branch_hier) > 1)
            and ((not qb.revision.allow_deleted)
                 or (qb.diff_group is None))):
         qb.sql_clauses.outer.enabled = True
      #
      if iinterp['access_level_where']:
         iinterp['access_level_where'] = (
               "%s %s" % (where_conj, iinterp['access_level_where'],))
         where_conj = "AND"

      iinterp['extra_where'] = self.sql_inner_where_extra(qb, 
                     branch_hier, br_allow_deleted, min_acl_id)

      # Query filters and viewport restrictions.
      iinterp['where_filters'] = ""
      iinterp['where_viewport'] = ""
      if qb.use_filters_and_viewport:
         iinterp['where_filters'] = self.sql_apply_query_filters(qb)
         tprefix = None
         iinterp['where_viewport'] = self.sql_apply_query_viewport(qb, tprefix)
      # MAYBE: Warn if filters or viewport set but not being used?

      # *** Group by

      # If the query includes aggregate fcns., we need to use a group-by.
      iinterp['inner_group_by'] = ""
      if (qb.sql_clauses.inner.group_by_enable):
         iinterp['inner_group_by'] = ("GROUP BY %s %s" 
                                     % (qb.sql_clauses.inner.group_by,
                                        qb.sql_clauses.inner.shared,))

      # *** Order by (always hot)

      g.assurt(qb.sql_clauses.inner.order_by_enable)

      # ** Outer query

      # The outer query is used by geofeatures (to output geometry in the
      # correct format), by byways (to output the length of the line segment),
      # and by search_map, tag_counts, and tilecache_update.

      ointerp = {}

      # *** Select list

      ointerp['extra_outer_select'] = ""
      if qb.sql_clauses.outer.enabled:
         ointerp['extra_outer_select'] = self.sql_outer_select_extra(qb)

      # *** Where clause

      # If we're checking out a leafy branch, the inner clause always allows
      # deleted items. In the outer clause, we filter out the deleted items. If
      # we didn't allow deleted items in the inner clause, we'd end up fetching
      # the non-deleted parent branch items of leafier deleted items.
      ointerp['outer_where'] = ""
      ointerp['extra_outer_where'] = self.sql_outer_where_extra(qb, 
                        branch_hier, br_allow_deleted, min_acl_id)
      if qb.sql_clauses.outer.enabled:
         if len(branch_hier) > 1:
            if not qb.revision.allow_deleted:
               ointerp['outer_where'] = (
                  """
                     AND NOT group_item.deleted
                     %s
                  """ % (ointerp['outer_where'],))
            if qb.diff_group is None:
               ointerp['outer_where'] = (
                  """
                     AND group_item.access_level_id <= %d
                     %s
                  """ % (min_acl_id, 
                         ointerp['outer_where'],))
         ointerp['outer_where'] = (
            """
            WHERE TRUE
               %s
               %s
               %s
            """ % (ointerp['outer_where'], 
                   qb.sql_clauses.outer.where,
                   ointerp['extra_outer_where'],))

      # *** Group by

      # The outer group-by is only needed if there's an outer aggregate.
      ointerp['outer_group_by'] = ""
      if (qb.sql_clauses.outer.enabled
          and qb.sql_clauses.outer.group_by_enable):
         ointerp['outer_group_by'] = (
            "GROUP BY %s %s" 
            % (qb.sql_clauses.outer.group_by,
               qb.sql_clauses.outer.shared,))

      # *** Full Text Search (ignored in outer)

      g.assurt(not qb.sql_clauses.outer.ts_queries) # Put in inner instead

      # *** Limit/Offset

      outer_order_by_enable = qb.sql_clauses.outer.order_by_enable

      #
      sql_limit = ""
      sql_offset = ""
      #log.debug('search_get_sql: qb.filters: %s / qb.use_limit_and_offset: %s'
      #          % (qb.filters, qb.use_limit_and_offset,))
      if (qb.filters is not None) and qb.use_limit_and_offset:
         if not qb.filters.pagin_total:
            sql_limit = qb.filters.limit_clause()
            sql_offset = qb.filters.offset_clause()
            if sql_limit or sql_offset:
               # When using limit and offset, be sure to always use order by
               # to ensure that pagination always works the same for the same
               # request.
               if not qb.sql_clauses.outer.enabled:
                  g.assurt(qb.sql_clauses.inner.order_by_enable)
               else:
                  # The outer select is enabled; always enable its order-by.
                  outer_order_by_enable = True

      if not qb.sql_clauses.outer.enabled:
         iinterp['inner_sql_limit'] = sql_limit
         iinterp['inner_sql_offset'] = sql_offset
         ointerp['outer_sql_limit'] = ""
         ointerp['outer_sql_offset'] = ""
      else:
         iinterp['inner_sql_limit'] = ""
         iinterp['inner_sql_offset'] = ""
         ointerp['outer_sql_limit'] = sql_limit
         ointerp['outer_sql_offset'] = sql_offset

      # *** Order by

      ointerp['outer_order_by'] = ""
      if (qb.sql_clauses.outer.enabled 
          and outer_order_by_enable
          and qb.sql_clauses.outer.order_by):
         ointerp['outer_order_by'] = ("ORDER BY %s" 
                                      % (qb.sql_clauses.outer.order_by,))

      # *** Build the SQL query string

      sql_inner = self.search_get_sql_inner(qb, iinterp)
      sql_outer = self.search_get_sql_outer(qb, ointerp, sql_inner)

      # If you want to see the difference in clauses...
      #diff_str = qb.sql_clauses.diff_str(dbg_sql_clauses_0)
      #if diff_str:
      #   log.debug('search_get_sql: diff_str: %s' % diff_str)

#      # FIXME: Reset the clauses?
#      if qb.sql_clauses != dbg_sql_clauses_0:
#         qb.sql_clauses = dbg_sql_clauses_0

      # 
      if qb.filters.pagin_total:
         sql_outer = 'SELECT COUNT(*) FROM (%s) AS foo_iua' % (sql_outer,)

      # Reset little hack we did...
      qb.filters.gia_use_gids = orig_gia_use_gids

      if conf.debuggery_print_next_sql:
         log.debug('search_get_sql: %s' % (sql_outer,))
         debuggery_print_next_sql = 0

      return sql_outer

   def search_get_sql_inner(self, qb, interp):
      interp['inner_select']   = qb.sql_clauses.inner.select
      interp['inner_shared']   = qb.sql_clauses.inner.shared
      interp['inner_join']     = qb.sql_clauses.inner.join
      interp['ts_queries']     = qb.sql_clauses.inner.ts_queries
      interp['inner_where']    = qb.sql_clauses.inner.where
      interp['inner_order_by'] = qb.sql_clauses.inner.order_by
      # NOTE: We never find reverted items, e.g., AND NOT item.reverted.
      # The only caller that finds reverts is version_finalize_and_increment.
      sql_inner = (
         """
         SELECT 
            %(inner_select)s 
            %(inner_shared)s
         %(gia_from_clause)s
         %(inner_join)s
         %(ts_queries)s
         WHERE
            %(gids_where)s
            %(branch_where)s
            %(rev_where_gia)s
            %(where_type)s
            %(access_level_where)s
            %(extra_where)s
            %(where_filters)s
            %(where_viewport)s
            %(inner_where)s
         %(inner_group_by)s
         ORDER BY
            %(inner_order_by)s
         %(inner_sql_limit)s
         %(inner_sql_offset)s
         """ % interp)
      return sql_inner

   def search_get_sql_outer(self, qb, interp, sql_inner):
      sql_outer = sql_inner
      if qb.sql_clauses.outer.enabled:
         interp['sql_inner'] = sql_inner
         interp['outer_select'] = qb.sql_clauses.outer.select
         interp['outer_shared'] = qb.sql_clauses.outer.shared
         interp['outer_join']   = qb.sql_clauses.outer.join
         sql_outer = (
            """
            SELECT
               %(outer_select)s
               %(outer_shared)s
               %(extra_outer_select)s
            FROM (
               %(sql_inner)s
               ) AS group_item
            %(outer_join)s
            %(outer_where)s
            %(outer_group_by)s
            %(outer_order_by)s
            %(outer_sql_limit)s
            %(outer_sql_offset)s
            """ % interp)
      return sql_outer

   # ***

# ***


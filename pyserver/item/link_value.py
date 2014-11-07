# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

from grax.access_level import Access_Level
from gwis.exception.gwis_error import GWIS_Error
from item import item_base
from item import item_user_access
from item import item_user_watching
from item import item_versioned
from item.util import revision
from item.util.item_type import Item_Type

log = g.log.getLogger('link_value')

class One(item_user_watching.One):

   item_type_id = Item_Type.LINK_VALUE
   item_type_table = 'link_value'
   item_gwis_abbrev = 'lv'
   child_item_types = None

   item_save_order = 4

   local_defns = [
      # MAYBE: Save network bandwidth and uses abbrev(iation)s.
      # py/psql name,         deft,  send?,  pkey?,  pytyp,  reqv, abbrev
      ('lhs_stack_id',        None,   True,  False,    int,     2,),
      ('rhs_stack_id',        None,   True,  False,    int,     2,),
      # We require the client to specify the linked item type IDs so we know
      # which item.Many() to create; otherwise, we'd have to look in
      # group_item_access and deduce the item type ID.
      ('link_lhs_type_id',    None,   True,   None,    int,     2,),
      ('link_rhs_type_id',    None,   True,   None,    int,     2,),
      # Without regard for storage space, we define six value_ columns,
      # though each link_value uses only zero or one of these.
      ('value_boolean',       None,   True,  False,   bool,     0,),
      ('value_integer',       None,   True,  False,    int,     0,),
      ('value_real',          None,   True,  False,  float,     0,),
      ('value_text',          None,   True,  False,    str,     0,),
      ('value_binary',        None,   True,  False,    str,     0,), # Bug nnnn
      ('value_date',          None,   True,  False,    str,     0,), # Bug nnnn
      # Skipping: We get some columns from the database that we don't add to 
      # the object, including lhs_gia_branch_id and lhs_min_acl and their rhs
      # doppelgangers. They're only used to decide if we should hydrate the row
      # into an item.
      # 
      # Don't send the 'name' column to the client, or expect it.
      # NOTE: This overrides item_versioned.One.schema_names.
      ('name',                None,  False,   None,    str,  None,),
      # 2013.03.27: For item watchers, it's nice to be able to display
      #             a name, even if we don't have any other details about
      #             the linked item.
      ('lhs_name',            None,   True,   None,    str,  None,),
      ('rhs_name',            None,   True,   None,    str,  None,),
      # The split-from stack ID is used to track ancestry. It's not really
      # used; we could use it to show more item history in the client.
      ('split_from_stack_id', None,  False,   None,    int,  None,),
      ]
   # 2012.09.25: We used to just add the lists of defns together, e.g.,
   #               attr_defns = item_user_watching.One.attr_defns + local_defns
   #             but then we might end up with multiple listings for the
   #             same-named attribute. Now we smartly combine the two lists so
   #             that attrs defined in leafier classes override their parents'.
   #             This fcn. was defined for this class, because of the 'name'
   #             attr (which we don't want sent to the client).
   # MAYBE: Update all 'attr_defns =' to use attr_defns_assemble.
   attr_defns = item_base.One.attr_defns_assemble(
                     item_user_watching, local_defns)
   psql_defns = item_user_watching.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)
   #
   cols_copy_nok = item_user_watching.One.cols_copy_nok + []

   __slots__ = [] + [attr_defn[0] for attr_defn in local_defns]

   value_cols = (
      'value_boolean',
      'value_integer',
      'value_real',
      'value_text',
      'value_binary',
      'value_date',
      )

   # *** Constructor

   # FIXME: get rid of item_type_tuple.
   def __init__(self, qb=None, row=None, req=None, copy_from=None,
                      item_type_tuple=None):
      item_user_watching.One.__init__(self, qb, row, req, copy_from)
      # Only zero or one of item_type, row or req should be set
      # WRONG, row and tuple sometimes set:
      #       g.assurt(len([x for x in (row, req, item_type_tuple) if x]) <= 1)
      # Load the database columns (or defaults)
      # First, figure out the attachment and geofeature types. This is a
      # somewhat special operation. Though we're not quite a factory class, 
      # we sort'uv are
      #if item_type_tuple:
      #   (self.attc_type, self.feat_type) = item_type_tuple
      if copy_from is not None:
         self.link_lhs_type_id = copy_from.link_lhs_type_id
         self.link_rhs_type_id = copy_from.link_rhs_type_id

   #
   def __str__(self):
      value_value = '%s%s%s%s%s%s' % (
            '' if self.value_boolean  is None else str(self.value_boolean),
            '' if self.value_integer  is None else str(self.value_integer),
            '' if self.value_real     is None else str(self.value_real),
            '' if self.value_text     is None else str(self.value_text),
            '' if self.value_binary   is None else str(self.value_binary),
            '' if self.value_date     is None else str(self.value_date),
            )
      return ('%s | lhs:%7d / rhs:%7d | val:%s' % (
         item_user_watching.One.__str__(self),
         # MAGIC_NUMBER: -99999 so we can %7d but still indicate None, sorta.
         -99999 if self.lhs_stack_id is None else self.lhs_stack_id,
         -99999 if self.rhs_stack_id is None else self.rhs_stack_id,
         value_value,
         ))

   #
   def __str_abbrev__(self):
      return ('%s | %7d-%7d' % (
         item_user_watching.One.__str_abbrev__(self),
         self.lhs_stack_id,
         self.rhs_stack_id,))

   # *** GML/XML Processing

   #
   def from_gml(self, qb, elem):
      item_user_watching.One.from_gml(self, qb, elem)
      # MAYBE Bug nnnn self.value_binary = foo(elem.get('value_binary'))
      # FIXME Bug nnnn self.value_date = FIXME(elem.get('value_date'))
      # MAYBE value_binary is so far undefined; it's meant to contain, 
      #       e.g., an avatar image (i.e., png or jpg), though it should 
      #       probably be a URL of a file, instead, so that we're not storing
      #       binary blobs in the database -- Should probably rename to
      #       value_binary_URL or similar (and figure out where to store
      #       user-uploaded binary data). Could also be used to add images to
      #       notes, e.g., user enters URL of their Flickr photo.

      if not self.lhs_stack_id:
         raise GWIS_Error('The lhs_stack_id attr must be nonzero.')
      if not self.rhs_stack_id:
         raise GWIS_Error('The rhs_stack_id attr must be nonzero.')
      #
      if ((not self.link_lhs_type_id) 
          or (not Item_Type.is_id_valid(self.link_lhs_type_id))):
         raise GWIS_Error('Missing or Unknown Value: link_lhs_type_id: %s'
                          % (self.link_lhs_type_id,))
      if ((not self.link_rhs_type_id) 
          or (not Item_Type.is_id_valid(self.link_rhs_type_id))):
         raise GWIS_Error('Missing or Unknown Value: link_rhs_type_id: %s'
                          % (self.link_rhs_type_id,))

      # Currently, we support just one of these set (and not zero, and not two
      # or more). In the future, however... maybe value_date can be set
      # alongside one of the other values... and maybe we'll add a value_set or
      # value_collection to handle "multiple_allowed". What's the Bug nnnn?
      value_value_cnt = (0
         + (0 if self.value_boolean  is None else  1)
         + (0 if self.value_integer  is None else  1)
         + (0 if self.value_real     is None else  1)
         + (0 if self.value_text     is None else  1)
         + (0 if self.value_binary   is None else  1)
         + (0 if self.value_date     is None else  1))
      value__text = 'value_[boolean|integer|real|text|binary|date]'
      if ((self.link_lhs_type_id == Item_Type.ATTRIBUTE)
          or (self.link_lhs_type_id == Item_Type.POST)):
         # For POST, value_integer is the revision ID.
         if value_value_cnt < 1:
            if self.link_lhs_type_id != Item_Type.POST:
               raise GWIS_Error('Missing mandatory attr: %s' % (value__text,))
            # else, a geofeature attached to a post.
         elif value_value_cnt > 1:
            raise GWIS_Error('Too many value attrs: %s' % (value__text,))
      elif value_value_cnt != 0:
         # NOTE: We could just ignore this value but it's better to let
         #       the programmer know their assumptions are wrong.
         #       This happens if the client sends a link_value with a value_*
         #       column set but the lhs item is not an attribute.
         raise GWIS_Error('Unexpected value attr(s): %s' % (value__text,))
      if self.name:
         raise GWIS_Error('Please do not set the name attribute for links.')
      # MAYBE: The name is actually the value_* thingy that's set... weird.
      self.name = self.save_core_get_name()
      # FIXME: item_versioned.name is empty but group_item_access.name is
      #        set to the value_* value for items since CcpV2 upgrade.

#   #
#   def attrs_to_xml_confirm(self, col_tuple):
#      # Don't send the 'name' attribute to the client. That's all this
#      # override does....
#      return (col_tuple[item_base.One.scol_pyname] != 'name')

   # *** Saving to the Database

   #
   def finalize_last_version_at_revision(self, qb, rid, same_version):

      item_user_watching.One.finalize_last_version_at_revision(
         self, qb, rid, same_version)

   #
   def save_core(self, qb):
      g.assurt(self.lhs_stack_id > 0)
      g.assurt(self.rhs_stack_id > 0)
      # BUG nnnn: See discussion about saving name for link in gia.
      self.name = self.save_core_get_name()
      log.verbose('save_core: naming as: %s' % (self.name,))
      # Check if another link_value already exists linking the lhs and rhs
      # items. For attributes marked allowed_deleted, this is okay; for all
      # other lhs items, it's not okay.
      # Not using try/except KeyError because the links are loaded prior to
      # saving.
      #lhs_item = qb.item_mgr.item_cache[self.lhs_stack_id]
      lhs_item = qb.item_mgr.item_cache_get(self.lhs_stack_id)
      try:
         multiple_allowed = lhs_item.multiple_allowed
      except AttributeError:
         # Annotations, Tags, Posts, etc., are all 1-to-1.
         multiple_allowed = False
      if not multiple_allowed:
         # FIXME: Do we need to include iv.reverted in where clause?
         sql_existing_links = (
            """SELECT lv.stack_id FROM link_value AS lv
               JOIN item_versioned AS iv USING (system_id)
               WHERE lv.lhs_stack_id = %d
                 AND lv.rhs_stack_id = %d
                 AND lv.branch_id = %d
                 AND iv.deleted IS FALSE
            """ % (qb.branch_hier[0][0],
                   self.lhs_stack_id,
                   self.rhs_stack_id,))
         rows = qb.db.sql(sql_existing_links)
         for row in rows:
            if row['stack_id'] != self.stack_id:
               log.error('save_core: unexpected: already a link_value: %d / %s'
                         % (row['stack_id'], self,))
               raise GWIS_Error('link_value already exists- stack id: %d / %d' 
                                % (row['stack_id'], self.stack_id,))
            else:
               # We're just saving a new version of the exising link.
               #g.assurt(len(rows) == 1)
               if len(rows) != 1:
                  log.error('save_core: unexpected: mult. lvals in db: %s / %s'
                            % (rows, self,))
               log.debug('save_core: saving new link_value version: %s'
                         % (self,))
      # Get a new System ID and save the item_stack and item_versioned rows.
      item_user_watching.One.save_core(self, qb)
      # NOTE: Use One. and not self. since we want this class's
      # table name and schema_columns, not a descendant class's.
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def save_core_get_name(self):
      link_name = ''
      for val_name in One.value_cols:
         value_val = getattr(self, val_name, None)
         if value_val is not None:
            link_name = str(value_val)
            break
      log.verbose('save_core_get_name: link_name: %s' % (link_name,))
      return link_name

   #
   def save_related_maybe(self, qb, rid):
      item_user_watching.One.save_related_maybe(self, qb, rid)

   #
   def save_update(self, qb):
      # Update the name of the link, based on whichever value is set.
      self.name = self.save_core_get_name()
      # Call the base class to trigger the update.
      item_user_watching.One.save_update(self, qb)

   # 
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      item_user_watching.One.validize(self, qb, is_new_item, dirty_reason,
                                            ref_item)

   # ***

   #
   def update_if_split_into(self, qb, split_into_lvals):

      # Only do this if client_id.
      g.assurt(self.fresh)

      updated = None

      # See if we've already processed the geofeature. This happens for
      # split-into byways, whose link_values were copied and saved already.
      # But the link_value from the client uses client IDs.
      log.debug('update_if_split_into: looking for processed lval links: %s'
                % (self,))

      # Not using qb.item_mgr.stack_id_translate, which gets a new ID if
      # necessary, or raises. We don't want either reaction.
      try:
         self.lhs_stack_id = qb.item_mgr.client_id_map[self.lhs_stack_id]
      except KeyError:
         pass

      try:
         self.rhs_stack_id = qb.item_mgr.client_id_map[self.rhs_stack_id]
      except KeyError:
         pass

      try:

         lval = split_into_lvals[self.rhs_stack_id][self.lhs_stack_id]

         log.debug('update_if_split_into: matched self: %s'
                   % (self,))
         log.debug('                           to lval: %s'
                   % (lval,))

         client_id = self.stack_id
         g.assurt(client_id < 0)

         # This call sets self.stack_id = lval.stack_id, basically.
         (suc, multiple_allowed,) = qb.item_mgr.lval_resolve_overlapping(
                                                qb, self, lval, force=True)
         # Becaues of force=True, when would this not be True?
         g.assurt(suc)

         # The lval_resolve_overlapping updates lval according to self.
         # And since lval has been processed and saved, but self has not,
         # we can check lval for permissions.
         user_acl_id = lval.calculate_access_level(qb.revision.gids)
         if not Access_Level.can_edit(user_acl_id):
            qb.grac_mgr.grac_errors_add(client_id, 
               Grac_Error.permission_denied,
               '/byway/split_into-link_value')
         else:
            # Do it. Update the database record.
            lval.update_values_force(qb)
            log.debug('update_if_split_into: client_id_map: %d ==> %d'
                        % (client_id, lval.stack_id,))
            qb.item_mgr.item_cache_add(lval, client_id)

         updated = lval

      except KeyError, e:
         # This is not a split-into link_value.
         pass

      # 2014.07.21: We used to check to see if a link_value already exists,
      # e.g., to prevent a user/client from making more than one item watcher
      # link-attribute. We no longer do that, because, well [lb] doesn't
      # quite remember why, which is why I'm preserving this dead code
      # (I think it was because this code pre-dates item_revisionless, that is,
      # we UPDATEd the existing link_value row rather than creating a new
      # version, but nowadays we can just create a new link_value version
      # without creating a new revision).
      # Naw: self.multiple_allowed_verify_stack_id()

      return updated

   #
   def multiple_allowed_verify_stack_id(self):

      g.assurt(False) # Not called.

      # For multiple_allowed, we want to verify against existing
      # link_value for user.

      #lhs_item = qb.item_mgr.item_cache[self.lhs_stack_id]
      lhs_item = qb.item_mgr.item_cache_get(self.lhs_stack_id)
      try:
         multiple_allowed = lhs_item.multiple_allowed
      except AttributeError:
         multiple_allowed = False

      if multiple_allowed:
         # It is assumed that link_values between the same two items only
         # makes sense if each link_value is private to an individual user.
         if qb.username == conf.anonymous_username:
            raise GWIS_Error(
               'Unexpected: anon user cannot commit personal links (2)')
         sql_existing_stack_id = (
            """SELECT DISTINCT ON (gia.stack_id) 
                      gia.stack_id,
                      gia.version,
                      gia.acl_grouping
                 FROM group_item_access AS gia
                 JOIN link_value AS lval ON (lval.system_id = gia.item_id)
                WHERE lval.lhs_stack_id = %d
                  AND lval.rhs_stack_id = %d
              --? AND gia.branch_id = %d
                  AND gia.group_id = %d
                  AND gia.deleted IS FALSE
                  AND gia.valid_until_rid = %d
                --AND gia.access_level_id = %d

             ORDER BY version DESC,
                      acl_grouping DESC

            """ % (self.lhs_stack_id,
                   self.rhs_stack_id,
                   qb.branch_hier[0][0],
                   qb.user_group_id,
                   conf.rid_inf,
                   # This is always editor, but by commenting out in the
                   # SQL, we'll catch more errors (e.g., link_values with
                   # other gia access_level_ids).
                   Access_Level.editor,))
         rows = qb.db.sql(sql_existing_stack_id)

         if rows:
            if len(rows) != 1:
               log.error('update_if_split_into: unexpected row cnt: %s'
                         % (sql_existing_stack_id,))
            for row in rows:
               existing_stack_id = row['stack_id']
               if existing_stack_id != self.stack_id:
                  log.warning(
                     'update_if_split_into: bad stk_id: %s / self: %s'
                     % (existing_stack_id, self,))
                  self.stack_id = existing_stack_id
            log.debug('update_if_split_into: lval-self ready: %s'
                      % (self,))
         else:
            # len(rows) == 0, so this is a new link_value.
            log.debug('update_if_split_into: new lval-self ok: %s'
                      % (self,))

      else:
         # not multiple_allowed
         # On save_core, link_value will check that link_values don't
         # already exist if not multiple_allowed, and it will throw an
         # error is so. So we could check here, but it's easier to just
         # let link_value raise.
         log.debug('update_if_split_into: lval-self seemingly ok: %s'
                   % (self,))

   #
   def update_values_force(self, qb, lhs_item=None):

      if lhs_item is None:
         #lhs_item = qb.item_mgr.item_cache[self.lhs_stack_id]         
         lhs_item = qb.item_mgr.item_cache_get(self.lhs_stack_id)

      # HACKTIMEFUNTIME
      update_sql = (
         """
         UPDATE link_value
         SET 
            value_boolean = %s
            , value_integer = %s
            , value_real = %s
            , value_text = %s
            , value_binary = %s
            , value_date = %s
            --, direction_id
            --, line_evt_mval_a
            --, line_evt_mval_b
            --, line_evt_dir_id
         WHERE system_id = %s
         """)

      qb.db.sql(update_sql,
                (self.value_boolean,
                 self.value_integer,
                 self.value_real,
                 self.value_text,
                 self.value_binary,
                 self.value_date,
                 self.system_id,))

      # BUG nnnn: link_values should not have name set in item_versioned or
      #           group_item_access. Clear link_value's item_versioned.name
      #           and group_item_access.name in the database and remove code
      #           that saves those rows.
      # lval_val = self.get_value(lhs_item)
      # if lval_val is None:
      #    # MAYBE: This names the link_value after the tag
      #    lval_val = lhs_item.name
      # update_sql = (
      #    "UPDATE item_versioned SET name = %s WHERE system_id = %s")
      # qb.db.sql(update_sql, (lval_val, self.system_id,))
      # update_sql = (
      #    "UPDATE group_item_access SET name = %s WHERE item_id = %s")
      # qb.db.sql(update_sql, (lval_val, self.system_id,))

   # ***

   #
   def load_all_link_values(self, qb):
      pass # Since Link_Values do not have... link_values.

   #
   def mark_deleted_link_values(self, qb, f_process_item_hydrated):
      pass # Link_Values do not have... link_values.

   # *** Client ID Resolution

   #
   def stack_id_correct(self, qb):
      '''When the client sends new items, it IDs the new items with negative 
         numbers; here, we convert those temporary IDs to permanent IDs'''
      # Since this is a link value, first translate the link IDs.
      self.lhs_stack_id = qb.item_mgr.stack_id_translate(
                  qb, self.lhs_stack_id, must_exist=True)
      self.rhs_stack_id = qb.item_mgr.stack_id_translate(
                  qb, self.rhs_stack_id, must_exist=True)
      # Next, try to find an existing link between those two IDs. If one is not
      # found, use a new stack ID.
      # FIXME: Implement stack_id_lookup_by_name for link_value? It's just
      #        implemented for link_tag at the moment...
      #self.stack_id_lookup_by_name(qb)
#Items have not been committed. (so searching w/ sql isn't complete)
#Multiple Link Values okay? (if so, don't care to lookup existing...)
#Check if attr and if multiple_allowed or use existing ID?
#which branches and groups apply?
#if i change speed limit in a branch, it only applies to that branch.
#but the item version still matters!

# FIXME: Since lhs and/or rhs may be fresh, we either need a lookup we can use,
# or, after saving, we have to go through gia and look for duplicates.

# FIXME: 20110829: Not worrying about duplicate links for now...
#
# BUG nnnn: Unless attribute multiple_allowed (probably all personalia
# attributes, like alert_email?), then we should check for duplicate
# links. E.g., when resolving branch_conflicts, it's easy to see if something
# was edited, but we don't check if someone created a link_value we also
# created, e.g., say I set shoulder_width for the first time and so did someone
# else, so each of our working copies submits two different new link_values.
# This is Bug nnnn: Duplicate link_values possible (attribute.multiple_allowed)
      if True:
         item_user_watching.One.stack_id_correct(self, qb)

   # ***

   # This fcn. applies just to attributes, but it's not in link_attribute
   # because some callees use link_value.Many() to load a heterogeneous 
   # mix of link_values.
   def get_value(self, attr):
      # I.e., value_boolean, value_integer, value_real, value_text, 
      # value_binary, value_date.
      try:
         obj_attr = 'value_%s' % (attr.value_type,)
         # This shouldn't fail, so no need for default value.
         value = getattr(self, obj_attr)
      except AttributeError, e:
         # Not an attribute. Called via update_values_force.
         # Hrmm... use the tag name, or thread name; the names of posts and
         # annotations is empty.
         #value = attr.name
         value = None
         log.error('get_value: unexpected: not an attr: %s' % (attr,))
      return value

   # ***

   #
   @staticmethod
   def as_insert_expression(qb, item):

      # Generates part of the SQL used by bulk_insert_rows.

      insert_expr = (
         "(%d, %d, %d, %d, %d, %d, %s, %s)"
         % (item.system_id,
            #? qb.branch_hier[0][0],
            # or:
            item.branch_id,
            item.stack_id,
            item.version,
            item.lhs_stack_id,
            item.rhs_stack_id,
            #item.value_boolean,
            item.value_integer if item.value_integer is not None else "NULL",
            #item.value_real,
            qb.db.quoted(item.value_text) if item.value_text else "NULL",
            #item.value_binary,
            #item.value_date,
            ))

      return insert_expr

   # ***

# ***

#
class Many(item_user_watching.Many):

   __slots__ = (
      'link_lhs_type_ids',
      'link_rhs_type_ids',
      'attr_stack_id',
      )

   one_class = One

   # ***

   sql_clauses_cols_all = item_user_watching.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_all.inner.select += (
      """
      , lhs_gia.branch_id AS lhs_gia_branch_id
      , lhs_gia.acl_grouping AS lhs_acl_gpg
      , lhs_gia.access_level_id AS lhs_min_acl
      , rhs_gia.branch_id AS rhs_gia_branch_id
      , rhs_gia.acl_grouping AS rhs_acl_gpg
      , rhs_gia.access_level_id AS rhs_min_acl
      """)

   # FIXME: Do not always get geometry? Would that save on execution or memory?
   sql_clauses_cols_all.inner.shared += (
      """
      , gia.link_lhs_type_id
      , gia.link_rhs_type_id
      , link.lhs_stack_id
      , link.rhs_stack_id
      , link.value_boolean
      , link.value_integer
      , link.value_real
      , link.value_text
      , link.value_binary
      , link.value_date
      , gf.geometry
      """)

   g.assurt(not sql_clauses_cols_all.inner.geometry_needed)

   sql_clauses_cols_all.inner.join += (
   # BUG nnnn: Use explicit join order (see join_collapse_limit).
   # See inner_where_sql_extra: we'll check the user's GrAC in the where.
      """
      JOIN link_value AS link
         ON (gia.item_id = link.system_id)
      JOIN group_item_access AS lhs_gia
         ON (link.lhs_stack_id = lhs_gia.stack_id)
      JOIN group_item_access AS rhs_gia
         ON (link.rhs_stack_id = rhs_gia.stack_id)
      LEFT OUTER JOIN geofeature AS gf
         ON (rhs_gia.item_id = gf.system_id)
      LEFT OUTER JOIN attribute AS lhs_attr
         ON (lhs_gia.item_id = lhs_attr.system_id)
      """)

   sql_clauses_cols_all.inner.group_by += (
      """
      , lhs_gia.branch_id
      , lhs_gia.acl_grouping
      , lhs_gia.access_level_id
      , rhs_gia.branch_id
      , rhs_gia.acl_grouping
      , rhs_gia.access_level_id
      """)

   # Parent sets:
   #   gia.stack_id ASC
   #   , gia.branch_id DESC
   #   , gia.version DESC
   #   , gia.acl_grouping DESC
   #   , gia.access_level_id ASC
   # Make sure you use the leafiest linked items. The two joins against the
   # attachment and the geofeature tables resulted in results for every
   # combination, so just order by one and then the other.
   sql_clauses_cols_all.inner.order_by += (
      """
      , lhs_gia.branch_id DESC
      , lhs_gia.acl_grouping DESC
      , lhs_gia.access_level_id ASC
      , rhs_gia.branch_id DESC
      , rhs_gia.acl_grouping DESC
      , rhs_gia.access_level_id ASC
      """)

   # FIXME/EXPLAIN: lhs_min_acl/rhs_min_acl never used.
   #                Do we need to check acl on linked items?
   #                Or is the link_value deleted when one or the other item is?
   sql_clauses_cols_all.outer.shared += (
      """
      , group_item.link_lhs_type_id
      , group_item.link_rhs_type_id
      , group_item.lhs_stack_id
      , group_item.rhs_stack_id
      , group_item.lhs_gia_branch_id
      , group_item.lhs_acl_gpg
      , group_item.lhs_min_acl
      , group_item.rhs_gia_branch_id
      , group_item.rhs_acl_gpg
      , group_item.rhs_min_acl
      , group_item.value_boolean
      , group_item.value_integer
      , group_item.value_real
      , group_item.value_text
      , group_item.value_binary
      , group_item.value_date
      """)

   # 

   sql_clauses_cols_name = sql_clauses_cols_all.clone()

   #

   sql_clauses_cols_lite = item_user_watching.Many.sql_clauses_cols_all.clone()

   sql_clauses_cols_lite.inner.shared += (
      """
      , gia.link_lhs_type_id
      , gia.link_rhs_type_id
      , link.lhs_stack_id
      , link.rhs_stack_id
      , link.value_boolean
      , link.value_integer
      , link.value_real
      , link.value_text
      , link.value_binary
      , link.value_date
      """)

   g.assurt(not sql_clauses_cols_lite.inner.geometry_needed)

   sql_clauses_cols_lite.inner.join += (
      """
      JOIN link_value AS link
         ON (gia.item_id = link.system_id)
      """)

   sql_clauses_cols_lite.outer.shared += (
      """
      , group_item.link_lhs_type_id
      , group_item.link_rhs_type_id
      , group_item.lhs_stack_id
      , group_item.rhs_stack_id
      , group_item.value_boolean
      , group_item.value_integer
      , group_item.value_real
      , group_item.value_text
      , group_item.value_binary
      , group_item.value_date
      """)

   #

   # *** Constructor

   def __init__(self, attc_types=None, feat_types=None):
      '''Creates a list of link_value items. Pass in the two items being 
         linked -- the attachment and the geofeature -- specified as either 
         strings or classes. The GML specifies the link item types as strings;
         the python code should always opt to use classes, so the runtime can
         catch any errors.'''
      item_user_watching.Many.__init__(self)
      self.link_lhs_type_ids = None
      if attc_types:
         self.link_type_set_ids('link_lhs_type_ids', attc_types)
      self.link_rhs_type_ids = None
      if feat_types:
         self.link_type_set_ids('link_rhs_type_ids', feat_types)

   # *** Query Builder routines

   #
   def sql_apply_query_filters(self, qb, where_clause="", conjunction=""):

      # link_attribute is now implemented, so no longer true:
      #  nope: g.assurt((not where_clause) and (not conjunction))
      g.assurt((not conjunction) or (conjunction == "AND"))

      if (qb.filters.filter_by_regions
          or qb.filters.filter_by_watch_geom):
         # You can't watch link_values. You watch the rhs item whose
         # link_values change.
         # MAYBE: Though it doesn't not make sense to support watching links,
         #        like, alert me when the speed limit of this road changes...?
         raise GWIS_Error('Link_Value does not support filtering by geom.')

      # NOTE: If you have hundreds or thousands of stack_ids, consider using 
      # these temporary join table(s) rather than filters.only_xhs_stack_id(s).
      if qb.filters.stack_id_table_lhs:
         qb.sql_clauses.inner.join += (
            """
            JOIN %s AS stack_ids_lhs
               ON (stack_ids_lhs.stack_id = link.lhs_stack_id)
            """ % (qb.filters.stack_id_table_lhs,))
      #
      if qb.filters.stack_id_table_rhs:
         qb.sql_clauses.inner.join += (
            """
            JOIN %s AS stack_ids_rhs
               ON (stack_ids_rhs.stack_id = link.rhs_stack_id)
            """ % (qb.filters.stack_id_table_rhs,))
         # BUG nnnn: Explicit join order. 2012.04.24: This is the ninth join 
         # in the SQL to get link_values for the byways that were just fetched.

      # NOTE: Unlike most other sql_apply_query_filters implementations, here
      # we AND everything together, rather than ORing them.

      # MAYBE: Use a where-and list and "AND".join() in the other 
      # implementations of this fcn. (sql_apply_query_filters). 
      # The other fcns. do tedious string arithmetic.

      where_ands = []

      if qb.filters.only_lhs_stack_id:
         where_ands.append("(link.lhs_stack_id = %d)" 
                           % (qb.filters.only_lhs_stack_id,))
      if qb.filters.only_lhs_stack_ids:
         where_ands.append("(link.lhs_stack_id IN (%s))"
                           % (qb.filters.only_lhs_stack_ids,))
      #
      if qb.filters.only_rhs_stack_id:
         where_ands.append("(link.rhs_stack_id = %d)" 
                           % (qb.filters.only_rhs_stack_id,))
      if qb.filters.only_rhs_stack_ids:
         where_ands.append("(link.rhs_stack_id IN (%s))"
                           % (qb.filters.only_rhs_stack_ids,))

      #
      if qb.filters.filter_by_value_text:
         where_ands.append("(LOWER(%s) = LOWER(link.value_text))"
                           % (qb.db.quoted(qb.filters.filter_by_value_text),))
      # FIXME: Implement other value_* filters.

      #
      # FIXME: The link_value class already takes lhs/rhs types. 
      #        See self.link_lhs_type_ids / search_item_type_id_sql().
      if qb.filters.only_lhs_item_types:
         where_ands.append("(gia.link_lhs_type_id IN (%s))"
                           % (qb.filters.only_lhs_item_types,))
      #
      if qb.filters.only_rhs_item_types:
         where_ands.append("(gia.link_rhs_type_id IN (%s))"
                           % (qb.filters.only_rhs_item_types,))

      # FIXED: conjunction is silly. Should probably always be AND?
      # 2013.03.27: The previous comment is old and incorrent. Each class'
      #             sql_apply_query_filters is ORed with the others in the
      #             class hierarchy. Only within a class is a subset of
      #             query_filters ever ANDed. So using query_filters is
      #             cumulative, in a sense: generally, the more filters you
      #             specify, the more results you'll get.
      if where_ands:
         addit_where = " AND ".join(where_ands)
         where_clause = "%s %s %s" % (where_clause, conjunction, addit_where,)
         conjunction = "AND"
      else:
         conjunction = ""

      # 2013.03.27: Return the linked items' names so the user can get some
      # idea what the linked item is (the client will know its item type and
      # name) without the client needing to checkout the linked items.
      if qb.filters.include_lhs_name and qb.filters.include_rhs_name:
         raise GWIS_Error(
            'Choose include_lhs_name or include_rhs_name, not both.')
      if qb.filters.include_lhs_name:
         qb.sql_clauses.inner.select += (
            """
            , lhs_gia.name AS lhs_name
            """)
         qb.sql_clauses.inner.group_by += (
            """
            , lhs_gia.name
            """)
         qb.sql_clauses.outer.shared += (
            """
            , group_item.lhs_name
            """)


# FIXME: Do you also need to branch_hier_where_clause on lhs and rhs??
#
         # FIXME: Is this right?:
# FIXME: see comments below, this should always be the case. also check
#        deleted...
         qb.sql_clauses.outer.where += (
            """
            AND (group_item.lhs_min_acl <= %d)
            """ % (Access_Level.client,))
      if qb.filters.include_rhs_name:
         qb.sql_clauses.inner.select += (
            """
            , rhs_gia.name AS rhs_name
            """)
         qb.sql_clauses.inner.group_by += (
            """
            , rhs_gia.name
            """)
         qb.sql_clauses.outer.shared += (
            """
            , group_item.rhs_name
            """)
         # FIXME: Is this right?:
         qb.sql_clauses.outer.where += (
            """
            AND (group_item.rhs_min_acl <= %d)
            """ % (Access_Level.client,))

      return item_user_watching.Many.sql_apply_query_filters(
                           self, qb, where_clause, conjunction)

   #
   def sql_apply_query_viewport(self, qb, geo_table_name=None):
      # NOTE: By design, this only ever applies to inner gia query
      apply_viewport_filter = False
      if not self.link_rhs_type_ids:
         apply_viewport_filter = True
      else:
         for rhs_type_id in self.link_rhs_type_ids:
            if int(rhs_type_id) in Item_Type.all_geofeatures():
               apply_viewport_filter = True
               break
      if apply_viewport_filter:
         where_c = item_user_watching.Many.sql_apply_query_viewport(
                                                      self, qb, 'gf')
      else:
         # EXPLAIN: When/how does this code path get followed?
         log.debug('sql_apply_query_viewport: Skipping non-geom rhs types: %s'
                   % (self.link_rhs_type_ids,))
         where_c = ""
      return where_c

   #
   def search_for_orphan_query(self, qb):
      '''Called by commit to clean up the GML sent from the
         client. Returns a list of link_values that aren't marked deleted, but
         that are linked to one or more non-existent items or deleted.'''
      # EXPLAIN: Is the client sending GML that's messed up, or is something
      #          else going on. Per the former, does that mean the user created
      #          and deleted something in their working copy, and the gml on
      #          commit included one but not the other item?
      # NOTE: Ignoring group_item_access. We're cleaning up the item_versioned 
      #       hierarchy, and we don't care about user permissions right now.
      sql = (
         """
         SELECT
            iv.stack_id
         FROM
            item_versioned AS iv
         JOIN
            link_value AS lv
               USING (system_id)
         WHERE
            NOT iv.deleted
            AND iv.valid_until_rid = %d
            AND (NOT EXISTS (
                        SELECT gf.stack_id
                        FROM geofeature AS gf
                        JOIN item_versioned AS iv_2
                           USING (system_id)
                        WHERE gf.stack_id = lv.rhs_stack_id
                              AND iv_2.valid_until_rid = %d
                              AND NOT iv_2.deleted)
                 OR NOT EXISTS (
                        SELECT at.stack_id 
                        FROM attachment AS at
                        JOIN item_versioned AS iv_2
                           USING (system_id)
                        WHERE at.stack_id = lv.lhs_stack_id
                              AND iv_2.valid_until_rid = %d
                              AND NOT iv_2.deleted))
         """ % (conf.rid_inf,
                conf.rid_inf,
                conf.rid_inf,))
      self.sql_search(qb, sql)

   ##
   #def search_get_items(self, qb):
   #   # FIXME: This class used to go out of its way to include deleted tags
   #   # when diffing, but I think this is fixed. But still: test deleting
   #   # tags and doing a diff.
   #   item_user_watching.Many.search_get_items(self, qb)

   #
   def search_item_type_id_sql(self, qb):
      '''Adds to the where clause. Restricts group_item_access rows to
         link_values, and the link_values to link_values of specific lhs and
         rhs types, if specified.'''
      where_clause = ("gia.item_type_id = %d" 
                      % (self.one_class.item_type_id,))
      if self.link_lhs_type_ids:
         where_clause += (
            " AND gia.link_lhs_type_id IN (%s)" % (self.link_lhs_type_ids,))
      if self.link_rhs_type_ids:
         where_clause += (
            " AND gia.link_rhs_type_id IN (%s)" % (self.link_rhs_type_ids,))
      log.verbose('search_item_type_id_sql: where: %s' % (where_clause,))
      return where_clause

   # *** Protected Interface

   #
   def link_type_set_ids(self, attr_name, item_types):

      if isinstance(item_types, int):
         item_types = [item_types,]
      elif isinstance(item_types, basestring):
         item_types = item_types.split(',')
      else:
         g.assurt(isinstance(item_types, list))

      setattr(self, attr_name, '')

      item_type_ids = set()
      for item_type in item_types:
         ittid = self.link_type_get_id(attr_name, item_type)
         if ittid is not None:
            item_type_ids.add(ittid)

      ittids_str = ','.join([str(x) for x in item_type_ids])
      # E.g., attr_name is link_lhs_type_ids or link_rhs_type_ids.
      setattr(self, attr_name, ittids_str)

   #
   def link_type_get_id(self, attr_name, item_type):
      # Get the item type; may be a string or a watcher 
      #                    <type 'classobj'>, e.g., item_user_watching.byway
      try:
         if issubclass(item_type, item_base.One):
            # NOTE: item_type.__name__ == 'One'
            #       item_type.__module__ == 'item.xxxx.xxxx.One'
            g.assurt(item_type.__module__.startswith('item.'))
            str_index = item_type.__module__.rfind('.')
            item_type_str = item_type.__module__[str_index+1:]
            item_type_id = Item_Type.str_to_id(item_type_str)
         else:
            # This code should be unreachable: if item_type is a class,
            # item_type should be dervied from item_base.One; if item_type is
            # not a class, issubclass throws TypeError.
            g.assurt(False)
      except TypeError:
         # The callee passed a string or an integer
         g.assurt((item_type is None) 
                or isinstance(item_type, basestring)
                or isinstance(item_type, int))
         item_type_id = None
         try:
            item_type = int(item_type)
            item_type_id = Item_Type.id_validate(item_type)
         except ValueError:
            if isinstance(item_type, basestring):
               # NOTE item_type must be lowercase. And if this doesn't hit, a
               #      KeyError is thrown.
               item_type_id = Item_Type.str_to_id(item_type)
      # all other exceptions thrown
      return item_type_id

   #
   def search_by_stack_id_both(self, lhs_stack_id, rhs_stack_id, 
                               *args, **kwargs):
      # FIXME: I can delete the old way, right?
      #qb.sql_clauses = self.sql_clauses_cols_all.clone()
      #if (lhs_stack_id is not None):
      #   qb.sql_clauses.inner.where += (
      #      " AND link.lhs_stack_id = %d" % (lhs_stack_id,))
      #if (rhs_stack_id is not None):
      #   qb.sql_clauses.inner.where += (
      #      " AND link.rhs_stack_id = %d" % (rhs_stack_id,))

      # FIXME: Unlike other search_by_* fcns., this one is passed a qb that it
      # doesn't own, so we gotta make ourselves a copy.
      qb = self.query_builderer(*args, **kwargs)
      qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      self.sql_clauses_cols_setup(qb)
      qb.filters.only_lhs_stack_id = lhs_stack_id
      qb.filters.only_rhs_stack_id = rhs_stack_id
      qb.filters.include_item_stack = True
      self.search_get_items(qb)
      qb.db.close()

   #
   def search_by_stack_id_lhs(self, lhs_stack_id, *args, **kwargs):
      # NOTE: This fcn. is not called...
      log.warning('search_by_stack_id_lhs: not tested/used')
      self.search_by_stack_id_both(lhs_stack_id, 0, *args, **kwargs)

   #
   def search_by_stack_id_rhs(self, rhs_stack_id, *args, **kwargs):
      self.search_by_stack_id_both(0, rhs_stack_id, *args, **kwargs)

   #
   def sql_inner_where_extra(self, qb, branch_hier, br_allow_deleted, 
                                       min_acl_id):

      # 2012.08.14: Is this always the case? If not, examine usage below...
      # 2013.05.01: Won't this fire if branch_hier_limit is in play, since
      # item_user_access.search_get_sql doesn't change qb.branch_hier but
      # instead uses the local copy sent herein? Or maybe branch_hier_limit is
      # never used on link_value... but what about, e.g., the item watcher
      # attribute? aren't those singly-branchy?
      g.assurt(branch_hier == qb.branch_hier)

      where_extra = item_user_watching.Many.sql_inner_where_extra(self, qb, 
                                 branch_hier, br_allow_deleted, min_acl_id)

      if (qb.filters.stack_id_table_lhs) or (qb.filters.stack_id_table_rhs):
         # If we have a table of stack IDs, the caller must guarantee that
         # they have been vetted for permissions.
         g.assurt(qb.request_is_local)

      # Always add the revision filters on the linked items, which also
      # checks user access to the link items via the group. We'll order by
      # access_level_id to make sure the user still has appropriate perms.
      include_gids = (not qb.filters.gia_userless)
      # MAYBE: I [lb] think allow_deleted should be False, since a
      # link_value to a deleted attachment or a deleted geofeature doesn't
      # make sense. But I'm not 100% confident.
# FIXME: For update or diff, you want to allow_deleted and ignore perms.
#      allow_deleted = False
# FIXME: tags and attrs for byways are fetched differently now with item_mgr:
#        so maybe this path isn't used for Update or Diff

# FIXME: 2012.07.25: I think this is deletable:
#        For whatever reason I used to not use 
#        the branch_hier_where and where_extra 
#        if qb.filters.stack_id_table_lhs or qb.filters.only_lhs_stack_id
#        which seems odd, since we still want to restrict the links that match,
#        even if we have their IDs...

      # FIXME: Okay to use qb.branch_hier and not branch_hier??
# 2013.03.27: see comments below. we should always allow deleted in the inner
# where, and then exclude if deleted in the outer...
      where_lhs_gia = qb.branch_hier_where('lhs_gia', include_gids, 
                                                      br_allow_deleted)
      g.assurt(where_lhs_gia)

      # BUG nnnn: FIXED?: For tags, we shouldn't use branch_hier_where,
      # since tags are saved to the basemap only (they're a bit like
      # node_endpoints, in the sense that they transcend branches).
      # COUPLING: This makes link_value know too much about tag (things
      # link_value shouldn't care about) but c'est la vie, get over it.
      # 
      # NOTE: We could do, e.g., branch_id = qb.branch_hier[-1][0] 
      #       to check that the tag is from the basemap branch, but
      #       tags are not saved to any other branch, so no need.
      if len(branch_hier) > 1:

         where_lhs_tag = revision.Current().as_sql_where('lhs_gia', 
                                    include_gids, br_allow_deleted,
                                    basemap_stack_id=qb.branch_hier[-1][0])

         # NOTE: Using gia and not lhs_gia for the link_lhs_type_id, since gia
         # is the link_value and lhs_gia is the attachment (so link_lhs_type_id
         # isn't set).
         where_extra += (
            """
            AND (   ((gia.link_lhs_type_id  = %d) AND %s)
                 OR ((gia.link_lhs_type_id != %d) AND %s))
            AND (    (gia.link_lhs_type_id != %d)
                 OR (NOT lhs_attr.multiple_allowed)
                 OR (gia.branch_id = %d))
            """ % (Item_Type.TAG, where_lhs_tag,
                   Item_Type.TAG, where_lhs_gia,
                   Item_Type.ATTRIBUTE,
                   qb.branch_hier[0][0],))

      else:
         g.assurt(len(branch_hier) == 1)
         where_extra += (
            """
            AND (%s)
            """ % (where_lhs_gia,))

# BUG nnnn: Search for link_values not working. E.g., 
#   ./ccp.py -s -q "bikelane" 
# should find byways tagged with bikelane... but it doesn't find anything!
# Also FIXME: Make sure finding neighborhoods and cities works, too.   


#      if not qb.filters.stack_id_table_rhs:
#         g.assurt(not qb.filters.only_rhs_stack_id)
# 2013.03.27: Don't you think we should allow deleted here
# and then, in the outer where, exclude links that have a
# deleted lhs or rhs item? If we exclude deleted in the inner,
# don't we end up selecting an earlier version of the link?
      where_rhs_gia = qb.branch_hier_where('rhs_gia', include_gids, 
                                                      br_allow_deleted)
      g.assurt(where_rhs_gia)
      where_extra += (" AND %s " % (where_rhs_gia,))

      return where_extra

   # ***

   #
   @staticmethod
   def prepare_sids_temporary_table(qb, xhs_stack_id_column,
                                        stack_id_table_ref,
                                        ohs_stack_id_column,
                                        target_table_ref):

      lval_qb = qb.clone(skip_clauses=True, skip_filtport=True)
      # Not using link_value's sql_clauses_cols_all/_name: lots of joins.
      lval_sqlc = Many.sql_clauses_cols_lite.clone()
      lval_qb.sql_clauses = lval_sqlc

      # NOTE: Not JOINing, but WHERE stack_id IN (...) instead.
      # Also: filters.only_lhs_stack_ids expects comma separated list,
      #       so just updating lval_sqlc instead.
      # lval_qb.filters.only_lhs_stack_ids = (
      #    "SELECT stack_id FROM %s" % (attc_stack_id_table_ref,))
      lval_sqlc.inner.where += (
         """
         AND (link.%s IN (SELECT stack_id FROM %s))
         """ % (xhs_stack_id_column, # lhs_stack_id or rhs_stack_id
                stack_id_table_ref,))

      #lvals_sql = Many().search_get_sql(lval_qb)
      #lvals_sql = item_user_watching.Many().search_get_sql(lval_qb)
      lvals_sql = item_user_access.Many().search_get_sql(lval_qb)

      sql_tmp_table = (
         """
         SELECT
            %s AS stack_id
         INTO TEMPORARY TABLE
            %s
         FROM
            (%s) AS foo_tagged_feats
         """ % (ohs_stack_id_column, # rhs_stack_id or lhs_stack_id
                target_table_ref,
                lvals_sql,))

      rows = lval_qb.db.sql(sql_tmp_table)

      lval_count_sql = ("SELECT COUNT(*) FROM %s" % (target_table_ref,))
      rows = lval_qb.db.sql(lval_count_sql)
      feat_count = rows[0]['count']
      log.debug('prepare_sids_temporary_table: feat_count: %d'
                % (feat_count,))

      where_clause = ("(gia.stack_id IN (SELECT stack_id FROM %s))"
                      % (target_table_ref,))

      return (where_clause, sql_tmp_table,)

   # ***

   #
   @staticmethod
   def bulk_insert_rows(qb, lv_rows_to_insert):

      g.assurt(qb.request_is_local)
      g.assurt(qb.request_is_script)
      g.assurt(qb.cp_maint_lock_owner or ('revision' in qb.db.locked_tables))

      if lv_rows_to_insert:

         insert_sql = (
            """
            INSERT INTO %s.%s (
               system_id
               , branch_id
               , stack_id
               , version
               , lhs_stack_id
               , rhs_stack_id
               --, value_boolean
               , value_integer
               --, value_real
               , value_text
               --, value_binary
               --, value_date
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   One.item_type_table,
                   ','.join(lv_rows_to_insert),))

         qb.db.sql(insert_sql)

   # ***

# ***


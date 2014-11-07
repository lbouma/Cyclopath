# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import os
import sys
import time
import traceback

from grax.access_level import Access_Level
from gwis.exception.gwis_error import GWIS_Error
from gwis.query_filters import Query_Filters
from gwis.query_overlord import Query_Overlord
from item import geofeature
from item import item_versioned
from item import link_value
from item.attc import attribute
from item.attc import tag
from item.feat import byway
#from item.feat import region
from item.feat import terrain
from item.jobsq import work_item_step
from item.link import link_post
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from item.util.watcher_watcher import Watcher_Watcher
from util_ import mem_usage
from util_ import misc
from util_.log_progger import Debug_Progress_Logger

log = g.log.getLogger('grax.item_mgr')

class Item_Manager(object):
   '''The Item_Manager in pyserver is not quite complementary to the same-named
      package in flashclient. In flashclient, the item_manager is used to
      maintain collections of items checked out from the server (i.e., it
      maintains the user's working copy). In pyserver, this file is used to
      manage collections of items temporarily during certain processes.

      Using an item manager allows, for instance, our commit code and our item
      code to share the same class without causing circular import problems.'''

   __slots__ = (
      'please_kick_mr_do',    # Items being saved set this for later processing
      'cache_attrs',          # A lookup of attr stack IDs to attribute items.
      'cache_attrnames',      # A lookup of attr internal names to attr items.
      'cache_tags',           # A lookup of tag stack IDs to tag items.
      'cache_tagnames',       # A lookup of tag names to tag items.
      'attr_and_tag_ids',     # Lookup for link_value search
      'loaded_cache',         # Set once load_cache_attachments has been called
      'cache_node_endpoints', # node_endpoint lookup.
      # Helper attributes for processing fcns. Note that the usage of these
      # means the Item_Manager is not reentrant.
      'prog_log',             #
      'heavyweight',          #
      'keep_running',         #
      'use_stack_id_table',   #
      'geofeat_many',         #
      'geofeats_cnt',         #
      'cache_items_attrs',    #
      'cache_items_tagged',   #
      'cache_link_values',    #
      'cache_n_notes',        #
      'cache_n_posts',        #
      'load_groups_access',   #
      #
      'rid_new',              #
      'rid_latest_really',    # Set to true if committing same revision
                              # (using acl_grouping).
      #
      'next_client_id',       # For callers that want to create new items.
      'client_id_map',        # The client-to-server ID map.
      'tag_id_map',           # Tags are special and live in the basemap.
      #
      # DEVs: If you're worried or OCD about blowing a lot of sequence IDs
      #       while testing, you can choose to peek at system IDs and only
      #       consume them if your code eventually commits -- because SQL's
      #       NEXTVAL('sequence_name') is atomic, once you call it, you've
      #       burned a sequence ID, which might bother or concern you if
      #       you're just testing or developing.
      'use_sequence_peeker',  # True to try to prevent sequence ID gaps
      'fst_stack_id',         # Only used to make str(item_mgr)
      'seq_stack_id',         #
      'fst_system_id',        #
      'seq_system_id',        #
      #
      'gfl_layer_id_lookup',  #
      'gfl_layer_name_lookup',#
      #
      'temp_tables',          #
      #
      'item_cache',           # For making new items, so we don't needlessly
                              # re-fetch, or so we don't not find new items.
      )

   # ***

   # 2014.03.17: For Shapefile import, we finally need a sane gfl lookup.

   # MAYBE: In Item_Manager might not be the best place for the lookup.
   #        But there aren't many classes that implement all geofeatures.

   # HINT: To help make this table, try:
   #  SELECT
   #     '''' || LOWER(layer_name) || ''': '
   #     || feat_type || '.Geofeature_Layer.'
   #     || REPLACE(layer_name, ' ', '_') || ','
   #     FROM geofeature_layer WHERE layer_name != 'default'
   #     ORDER BY feat_type, layer_name;
   gfid_lookup = {
      #'alley': byway.Geofeature_Layer.Alley,
      'alley': byway.Geofeature_Layer.Byway_Alley,
      #'bicycle path': byway.Geofeature_Layer.Bicycle_Path,
      'bicycle path': byway.Geofeature_Layer.Bike_Trail,
      'bike trail': byway.Geofeature_Layer.Bike_Trail,
      'bicycle trail': byway.Geofeature_Layer.Bike_Trail,
      'doubletrack': byway.Geofeature_Layer.Doubletrack,
      'expressway': byway.Geofeature_Layer.Expressway,
      'expressway ramp': byway.Geofeature_Layer.Expressway_Ramp,
      'highway': byway.Geofeature_Layer.Highway,
      'local road': byway.Geofeature_Layer.Local_Road,
      'major road': byway.Geofeature_Layer.Major_Road,
      'major trail': byway.Geofeature_Layer.Major_Trail,
      'other': byway.Geofeature_Layer.Other,
      'railway': byway.Geofeature_Layer.Railway,
      'private road': byway.Geofeature_Layer.Private_Road,
      'other ramp': byway.Geofeature_Layer.Other_Ramp,
      'parking lot': byway.Geofeature_Layer.Parking_Lot,
      'sidewalk': byway.Geofeature_Layer.Sidewalk,
      'singletrack': byway.Geofeature_Layer.Singletrack,
      'unknown': byway.Geofeature_Layer.Unknown,
      #'work_hint': region.Geofeature_Layer.work_hint,
      'flowline': terrain.Geofeature_Layer.Flowline,
      #'openspace': terrain.Geofeature_Layer.openspace,
      'openspace': terrain.Geofeature_Layer.Open_Space,
      'open space': terrain.Geofeature_Layer.Open_Space,
      #'water': terrain.Geofeature_Layer.water,
      'water': terrain.Geofeature_Layer.Water,
      'waterbody': terrain.Geofeature_Layer.Waterbody,
   }

   # *** Constructor

   def __init__(self):
      self.please_kick_mr_do = False
      self.cache_attrs = None
      self.cache_attrnames = None
      self.cache_tags = None
      self.cache_tagnames = None
      self.attr_and_tag_ids = None
      self.loaded_cache = False
      self.cache_node_endpoints = {}
      #
      self.load_feats_and_attcs_reset()
      #
      # The "client IDs" start at negative one and ascend descendingly.
      self.rid_new = None
      #self.rid_latest_really
      self.next_client_id = -1
      self.client_id_map = {}
      self.tag_id_map = {}

# FIXME: Make True on the server after running mndot import.
      self.use_sequence_peeker = True
      self.use_sequence_peeker = False

      self.fst_stack_id = None
      self.seq_stack_id = None
      self.fst_system_id = None
      self.seq_system_id = None
      #
      self.gfl_layer_id_lookup = {}
      self.gfl_layer_name_lookup = {}
      #
      self.temp_tables = []
      #
      #self.item_cache = None
      self.item_cache = {}

   #
   def __str__(self):
      preamble = (
         'item_manager: / seq_sid: %s%s / seq_sys: %s%s'
         % (self.seq_stack_id,
            '' if ((not self.fst_stack_id)
                   or (not self.seq_stack_id)
                   or (not self.fst_stack_id)) else
               ' [+%d]' % (self.seq_stack_id - self.fst_stack_id),
            self.seq_system_id,
            '' if (not self.seq_system_id or not self.fst_system_id) else
               ' [+%d]' % (self.seq_system_id - self.fst_system_id),))
      if self.cache_attrs is not None:
         self_str = ('%s%s%s%s'
               % ('%s' % preamble,
                  '\n/ tags: %4d of them' % len(self.cache_tags),
                  '\n/ attrs: %4d of them: \n' % len(self.cache_attrnames),
                  '\n'.join(['%s (%s)'
                               % (attr.value_internal_name or attr.name,
                                  attr.stack_id,)
                             for attr in self.cache_attrnames.itervalues()]),))
      else:
         self_str = '%s / cache not loaded' % (preamble,)
      return self_str

   #
   def log_self(self, logf=log.debug):
      preamble = (
         'item_manager: / seq_sid: %s%s / seq_sys: %s%s'
         % (self.seq_stack_id,
            '' if ((not self.fst_stack_id)
                   or (not self.seq_stack_id)
                   or (not self.fst_stack_id)) else
               ' [+%d]' % (self.seq_stack_id - self.fst_stack_id),
            self.seq_system_id,
            '' if (not self.seq_system_id or not self.fst_system_id) else
               ' [+%d]' % (self.seq_system_id - self.fst_system_id),))
      if self.cache_attrs is not None:
         logf(preamble)
         logf(' ..  tags: %4d of them' % (len(self.cache_tags),))
         logf(' .. attrs: %4d of them:' % (len(self.cache_attrnames),))
         for attr in self.cache_attrnames.itervalues():
            logf('           %s (%s)'
                 % (attr.friendly_name(),
                    attr.stack_id,))
      else:
         logf('%s / cache not loaded' % (preamble,))

   # *** Commit/Import Helpers: Manage Sequence Numbers

   #
   def finalize_seq_vals(self, db):
      if self.use_sequence_peeker:
         if self.seq_stack_id:
            g.assurt((qb.db.locked_tables == ['revision',])
                     or (qb.cp_maint_lock_owner))
            log.debug('finalize_seq_vals: stack_id: %d'
                      % (self.seq_stack_id,))
            db.sequence_set_value('item_stack_stack_id_seq',
                                  self.seq_stack_id)
         if self.seq_system_id:
            g.assurt((qb.db.locked_tables == ['revision',])
                     or (qb.cp_maint_lock_owner))
            log.debug('finalize_seq_vals: system_id: %d'
                      % (self.seq_system_id,))
            db.sequence_set_value('item_versioned_system_id_seq',
                                  self.seq_system_id)
      self.fst_stack_id = None
      self.seq_stack_id = None
      self.fst_system_id = None
      self.seq_system_id = None

   # Client Stack ID generator.
   def get_next_client_id(self):
      # This fcn. is called to prepare new items with client IDs. It's used
      # during the import process to setup items before finally calling
      # validize, which transforms the (negative) client ID into a (positive)
      # real stack ID. (This is new to CcpV2 because in CcpV1 items were only
      # created on the commit (PutFeature) command, whereby client IDs are
      # created by -- aha! -- the client. In CcpV2, we need this fcn. because
      # sometimes we're our own client, i.e., for import.
      next_client_id = self.next_client_id
      self.next_client_id -= 1
      log.verbose('get_next_client_id: returning: %d' % (next_client_id,))
      return next_client_id

   #
   def item_cache_add(self, item, client_id=None, force_add=False):

      log.verbose('item_cache_add: add: %s (%s): %s%s'
         % (item.stack_id, client_id, 'force:' if force_add else '', item,))

      # Add to the client ID map, maybe.
      if client_id:
         # When updating a split-into link_value during a commit, it's first
         # saved by the byway, and then commit overwrites the link_value values
         # if the user specified new values. So this might not be true:
         # No: g.assurt((item.client_id > 0) or (item.client_id == client_id))
         try:
            # Check that we're not overwriting an existing key with a different
            # value.
            g.assurt(self.client_id_map[client_id] == item.stack_id)
         except KeyError:
            pass
         self.client_id_map[client_id] = item.stack_id
      elif item.client_id and (item.client_id < 0):
         log.verbose('item_cache_add: auto-adding item.client_id: %d: %s'
                     % (item.client_id, item,))
         try:
            g.assurt(self.client_id_map[item.client_id] == item.stack_id)
         except KeyError:
            pass
         self.client_id_map[item.client_id] = item.stack_id

      # Cache the new item.
      if item.stack_id not in self.item_cache:
         log.verbose('item_cache_add: item_cache: new: %s' % (item,))
         self.item_cache[item.stack_id] = item
      else:
         # If the item was already added to the cache, it should be the same.
         # Otherwise, we risk processing the item in two different ways.
         log.verbose('item_cache_add: item_cache: cur: %s' % (item,))
         log.verbose('item_cache_add: item_cache: old: %s'
                     % (self.item_cache[item.stack_id],))
         # 2013.08.05: When you delete an item, you first delete its
         # link_values, which means you hydrate the item then, too.
         if id(item) != id(self.item_cache[item.stack_id]):
            if force_add:
               # NOTE: No callers use force_add.
               log.verbose('item_cache_add: overwriting existing item')
               self.item_cache[item.stack_id] = item
            else:
               g.assurt(id(item) == id(self.item_cache[item.stack_id]))

         # 2013.10.06: What about the other item caches?
         # FIXME: Test editing existing attribute... any other tests?
         if ((self.cache_attrs is not None)
             and (item.stack_id in self.cache_attrs)):
            if id(self.cache_attrs[item.stack_id]) != id(item):
               log.error('FIXME: what about cache_attrs?: %s' % (item,))
            # FIXME: Overwrite entries in self.cache_attrs, cache_attrnames,
            #        and attr_and_tag_ids?
         if ((self.cache_tags is not None)
             and (item.stack_id in self.cache_tags)):
            if id(self.cache_tags[item.stack_id]) != id(item):
               log.error('FIXME: what about cache_tags?: %s' % (item,))
            # FIXME: Overwrite entries in self.cache_tags and attr_and_tag_ids?

   #
   def item_cache_del(self, item_stack_id):
      try:
         stack_id = item_stack_id.stack_id
      except AttributeError:
         stack_id = int(item_stack_id)
      log.verbose('item_cache_del: item_cache (%d): del stack_id: %s'
                  % (id(self.item_cache), stack_id,))
      try:
         del self.item_cache[stack_id]
      except KeyError:
         pass

   #
   def item_cache_get(self, stack_id):
      try:
         item = self.item_cache[stack_id]
      except KeyError:
         try:
            item = self.cache_attrs[stack_id]
         except KeyError:
            try:
               item = self.cache_tags[stack_id]
            except KeyError:
               item = None
      return item

   #
   def item_cache_reset(self):
      log.debug('item_cache_reset: clearing item_cache')
      self.item_cache = {}

   #
   def seq_id_next_stack_id(self, qb):
      # See usages of stack_id_translate and stack_id_correct.
      if qb.db.locked_tables:
         g.assurt((qb.db.locked_tables == ['revision',])
                  or (qb.cp_maint_lock_owner))
         if self.use_sequence_peeker:
            if not self.seq_stack_id:
               self.seq_stack_id = qb.db.sequence_peek_next(
                                    'item_stack_stack_id_seq')
               what = 'new'
               self.fst_stack_id = self.seq_stack_id - 1
            else:
               what = 'inc'
               self.seq_stack_id += 1
         else:
            what = 'get'
            self.seq_stack_id = qb.db.sequence_get_next(
                                 'item_stack_stack_id_seq')
            self.fst_stack_id = self.seq_stack_id - 1
      else:
         g.assurt(self.rid_latest_really)
         what = 'steal'
         self.seq_stack_id = None
         self.seq_stack_id = self.seq_id_steal_stack_id(qb.db)
         self.fst_stack_id = self.seq_stack_id - 1
      log.verbose('_next_stack_id: %s: %d / item_mgr: %d'
                  % (what, self.seq_stack_id, id(self),))
      return self.seq_stack_id

   #
   def seq_id_next_system_id(self, qb):
      if qb.db.locked_tables:
         # This check is valid but seems silly...
         #g.assurt((set(qb.db.locked_tables)
         #          .intersection(set(['revision','tag',])))
         #         or (qb.cp_maint_lock_owner))
         g.assurt(qb.db.locked_tables or qb.cp_maint_lock_owner)
         if self.use_sequence_peeker:
            if not self.seq_system_id:
               self.seq_system_id = qb.db.sequence_peek_next(
                              'item_versioned_system_id_seq')
               # This is just for DEVs to track the number
               # of system_ids that we generate.
               self.fst_system_id = self.seq_system_id - 1
            else:
               self.seq_system_id += 1
         else:
            self.seq_system_id = qb.db.sequence_get_next(
                           'item_versioned_system_id_seq')
            self.fst_system_id = self.seq_system_id - 1
      else:
         g.assurt(self.rid_latest_really)
         self.seq_system_id = None
         self.seq_system_id = self.seq_id_steal_system_id(qb.db)
      return self.seq_system_id

   #
   def seq_id_steal_stack_id(self, db):
      # This is used by operations that are not creating a new revision but
      # still need new stack IDs, e.g., saving routes.
      # NOTE: Try not to use this fcn. until you know your commit be really be
      #       done, otherwise you'll waste sequence IDs (which wouldn't really
      #       matter if we used GUIDs instead...).
      g.assurt(not db.locked_tables)
      g.assurt(self.seq_stack_id is None)
      next_stack_id = db.sequence_get_next('item_stack_stack_id_seq')
      return next_stack_id

   #
   def seq_id_steal_system_id(self, db):
      # This is used by operations that are not creating a new revision but
      # still need new stack IDs, e.g., saving routes.
      g.assurt(not db.locked_tables)
      g.assurt(self.seq_system_id is None)
      next_system_id = db.sequence_get_next('item_versioned_system_id_seq')
      return next_system_id

   # Return the permanent ID appropriate for the given client ID. For some
   # items, like tags, we check the name, too, to make sure we don't create a
   # duplicate where duplicates are not allowed.
   def stack_id_lookup_by_name(self, qb, item):
      # This is called by tag.One.stack_id_correct(), since tags are only saved
      # to the baseline; we don't want to create multiple tag names.
      g.assurt(item.stack_id != 0)
      try:
         # See if we've seen this tag before during this save. By using this
         # lookup we prevent against the case where a client sends two tags
         # with the same name but different client IDs.
         stack_id_from_map = self.tag_id_map[item.name]
         g.assurt(stack_id_from_map is not None)
         item.stack_id_set(stack_id_from_map)
      except KeyError:
         # If this is a client ID, maybe we've seen it before.
         g.assurt(item.stack_id is not None)
         if item.stack_id < 0:
            # 2013.08.15: Items with client IDs are always fresh, right?
            item.fresh = True
            try:
               stack_id_from_map = self.client_id_map[item.stack_id]
               g.assurt(stack_id_from_map is not None)
               item.stack_id_set(stack_id_from_map)
            except KeyError:
               # Try to find the named item in the database.
               # NOTE: This asserts unless item is a tag... which is the only
               #       class that uses stack_id_lookup_by_name.
               sql = item.stack_id_lookup_by_name_sql(qb)
               rows = qb.db.sql(sql)
               if len(rows) == 1:
                  # Success; cache and set.
                  stack_id = rows[0]['stack_id']
                  g.assurt(stack_id is not None)
                  client_id = item.stack_id
                  item.stack_id_set(stack_id)
                  log.debug('stack_id_lookup_by_name: client_id_map: %d ==> %d'
                              % (item.stack_id, stack_id,))
                  qb.item_mgr.item_cache_add(item, client_id)
               else:
                  g.assurt(not rows)
                  # Not found; get new id.
                  stack_id = self.stack_id_translate(qb, item.stack_id)
                  item.stack_id_set(stack_id)
                  # 2013.08.15: Shouldn't we always set item.fresh, and not
                  # just when we get a new ID (i.e., what if we already put the
                  # client ID in the cliend_id_map: that doesn't mean this item
                  # isn't fresh, right?). In any case, the item_base ctor
                  # should probably just set fresh when stack_id < 0....
                  # 2013.10.07: Didn't we set this above? If so, remove these
                  # comments and codes.
                  g.assurt(item.fresh)
                  item.fresh = True
         # Remember the named tag for later.
         self.tag_id_map[item.name] = item.stack_id

   # Return the permanent ID appropriate for the given client ID, which might
   # already be permanent. The purpose here is to map temporary IDs assigned
   # by the client to permanent IDs assigned by the server. Client IDs are
   # negative, and permanent IDs are positive. No ID is zero.
   #
   def stack_id_translate(self, qb, client_id, must_exist=False):
      g.assurt(client_id)
      g.assurt((must_exist)
               or (qb.db.locked_tables == ['revision',])
               or (qb.cp_maint_lock_owner))
      if client_id > 0:
         # NOTE: We're taking them at their word and not checking that the item
         #       actually exists or that the user has view access or better to
         #       it. We'll find these things out later....
         permanent_id = client_id
         log.verbose('stack_id_translate: already permanent: %d ==> %d'
                     % (client_id, permanent_id,))
      else:
         # If we haven't already seen this item, add it to our lookup,
         # so we can recognize the same negative IDs from the client.
         try:
            permanent_id = self.client_id_map[client_id]
            log.verbose('stack_id_translate: found permanent: %d ==> %d'
                        % (client_id, permanent_id,))
         except KeyError:
            if not must_exist:
               permanent_id = self.seq_id_next_stack_id(qb)
               log.verbose('stack_id_translate: client_id_map: %d ==> %d'
                           % (client_id, permanent_id,))
               # Cannot call: qb.item_mgr.item_cache_add(???, client_id)
               self.client_id_map[client_id] = permanent_id
            else:
               # This should only happen if the user's GML is malformed
               #g.assurt(False)
               raise GWIS_Error('Cannot resolve client ID: %d' % (client_id,))
      g.assurt(permanent_id > 0)
      return permanent_id

   #
   def start_new_revision(self, db, use_latest_rid=False):
      if not use_latest_rid:
         # This is, e.g., rid_new.
         rid_new_maybe = revision.Revision.revision_peek(db)
         self.rid_latest_really = False
      else:
         # This is, e.g., rid_latest.
         rid_new_maybe = revision.Revision.revision_max(db)
         self.rid_latest_really = True
      self.rid_new = rid_new_maybe
      g.assurt(self.rid_new)

   # *** Commit/Import Helpers: After Committing Revision

   #
   def do_post_commit(self, qb):

      log.debug('do_post_commit: kick Mr. Do!?: %s'
                % (self.please_kick_mr_do,))

      # Kick Mr. Do! if called from work_item_step (we can't kick the Do!
      # until # after we've committed the database transaction).

      if self.please_kick_mr_do:
         work_item_step.One.kick_mr_do(qb)
         self.please_kick_mr_do = False

   # *** Deprecated bulk item loading

   # These load fcns. should be avoided in favor of bulk-loading.
   # Also, these could just as well be staticmethod, except they're
   # called from byway, which cannot import item_manager (lest we form an
   # infinite import loop).

   load_links_slow_warned = False

   #
   def load_links_slow(self, qb, the_item, heavyweight=False):
      if not Item_Manager.load_links_slow_warned:
         log.warning(
            'load_links_slow: This fcn. is deprecated because it is slow.')
         Item_Manager.load_links_slow_warned = True
      self.load_attrs_for_item(qb, the_item, heavyweight)
      self.load_tags_for_item(qb, the_item, heavyweight)
      # FIXME/EXPLAIN: What about annotations and other attc types?
      #                At least this fcn. is deprecated...
      the_item.lvals_wired_ = True

   load_attrs_slow_warned = False

   #
   def load_attrs_for_item(self, qb, the_item, heavyweight=False):
      if not Item_Manager.load_attrs_slow_warned:
         log.warning(
            'load_attrs_for_item: This fcn. is deprecated because it is slow.')
         Item_Manager.load_attrs_slow_warned = True
      g.assurt(self.cache_attrs is not None)
      g.assurt(self.cache_attrnames is not None)
      lvals_attrs = link_value.Many(attc_types=Item_Type.ATTRIBUTE,
                                    feat_types=None)
      # Search for links using our ID; this fcn. clones qb.
      lvals_attrs.search_by_stack_id_rhs(the_item.stack_id, qb)
      log.verbose('load_attrs_for_item: found %d attrs for: %s (%d)'
                  % (len(lvals_attrs), the_item.name, the_item.stack_id,))
      # Add to the lightweight lookup.
      # Note that we don't expect the lookup to have been populated yet.
      g.assurt(not the_item.attrs)
      for lval_attr in lvals_attrs:
         # FIXME: APRIL2014: What about /item/alert_email, /item/reminder_email
         #        Do we need to worry about the private, multi-user link-attrs?
         the_item.wire_link_attribute(qb, lval_attr)

      # Add to the heavyweight lookup.
      if heavyweight:
         if not hasattr(the_item, 'link_values'):
            the_item.link_values_reset(qb)
            # We'll set "the_item.lvals_wired_ = True" separately.
         for lval_attr in lvals_attrs:
            g.assurt(lval_attr.lhs_stack_id not in the_item.link_values)
            the_item.link_values[lval_attr.lhs_stack_id] = lval_attr
            log.verbose('load_attrs_for_item: added lval: %s'
                        % (lval_attr,))
         # We'll set this later: the_item.lvals_wired_ = True

   load_tags_slow_warned = False

   #
   def load_tags_for_item(self, qb, the_item, heavyweight=False):
      if not Item_Manager.load_tags_slow_warned:
         log.warning(
            'load_tags_for_item: This fcn. is deprecated because it is slow.')
         Item_Manager.load_tags_slow_warned = True
      g.assurt(qb.item_mgr.cache_tags is not None)
      lvals_tag = link_value.Many(attc_types=Item_Type.TAG, feat_types=None)
      # Search for links using our ID; this fcn. clones qb.
      lvals_tag.search_by_stack_id_rhs(the_item.stack_id, qb)
      log.verbose('load_tags_for_item: found %d tags for: %s (%d)'
                   % (len(lvals_tag), the_item.name, the_item.stack_id,))
      # Add to the lightweight lookup.
      # Note that we don't expect the lookup to have been populated yet.
      g.assurt(not the_item.tagged)
      for lval_tag in lvals_tag:
         the_item.wire_link_tag(qb, lval_tag)
      # Add to the heavyweight lookup.
      if heavyweight:
         if not hasattr(the_item, 'link_values'):
            the_item.link_values_reset(qb)
            # We'll set "the_item.lvals_wired_ = True" separately.
         for lval_tag in lvals_tag:
            g.assurt(lval_tag.lhs_stack_id not in the_item.link_values)
            the_item.link_values[lval_tag.lhs_stack_id] = lval_tag
            log.verbose('load_tags_for_item: added lval: %s' % (lval_tag,))
         # We'll set this later: the_item.lvals_wired_ = True

   # *** Attachment Cache Management

   #
   def clear_cache(self):
      #log.debug('clear_cache: cache_attrs')
      self.loaded_cache = False
      self.cache_attrs = None
      self.cache_attrnames = None
      self.cache_tags = None
      self.cache_tagnames = None
      self.attr_and_tag_ids = None

   #
   def load_cache_attachments(self, qb):
      #log.debug('load_cache_attachments')
      if not self.loaded_cache:
         g.assurt((self.cache_attrs is None)
                  and (self.cache_attrnames is None)
                  and (self.cache_tags is None)
                  and (self.cache_tagnames is None))
         # For checkouts, the revision is Historic. For commit, we use Current.
         g.assurt((isinstance(qb.revision, revision.Current))
                  or (isinstance(qb.revision, revision.Historic)))
         self.attr_and_tag_ids = set()
         self.load_cache_attc_attributes(qb)
         self.load_cache_attc_tags(qb)
         self.loaded_cache = True
      else:
         g.assurt((self.cache_attrs is not None)
                  and (self.cache_attrnames is not None)
                  and (self.cache_tags is not None)
                  #and (self.cache_tagnames is not None)
                  )

   #
   def load_cache_attc_attributes(self, qb):
      if self.cache_attrs is None:
         g.assurt(self.cache_attrnames is None)
         log.verbose2('load_cache_attc_attrs: loading all attrs...')
         time_0 = time.time()
         self.cache_attrs = {}
         self.cache_attrnames = {}
         qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
         qb.diff_group = None
         Query_Overlord.finalize_query(qb)
         attc_attrs = attribute.Many()
         attc_attrs.search_for_items(qb)
         if not attc_attrs:
            log.warning('load_cache_attc_attributes: Branch has no attrs?!')
         qb.db.close()
         for attc_attr in attc_attrs:
            g.assurt(attc_attr.stack_id not in self.cache_attrs)
            self.cache_attrs[attc_attr.stack_id] = attc_attr
            # If this fires, you've got two attributes with the same name,
            # possibly in different branches. You should ask yourself why.
            # 2013.09.25: What happened to the import scripts that this is
            # happening now when trying to populate the MetC branch??
            g.assurt(attc_attr.value_internal_name not in self.cache_attrnames)
            self.cache_attrnames[attc_attr.value_internal_name] = attc_attr
            self.attr_and_tag_ids.add(attc_attr.stack_id)
         log.debug('load_cache_attc_attrs: found %d attrs in %s'
                   % (len(self.cache_attrs),
                      misc.time_format_elapsed(time_0),))
      else:
         log.warning('load_cache_attc_attributes: already loaded attrs')

   #
   def load_cache_attc_tags(self, qb):
      if self.cache_tags is None:
         log.verbose2('load_cache_attc_tags: loading all tags...')
         time_0 = time.time()
         self.cache_tags = {}
         qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
         qb.diff_group = None
         # Don't load the tag counts, which takes a number of seconds.
         # BUG nnnn: Don't load tag counts in flashclient until route dialog
         #   displayed, or cache the tag counts after every revision update.
         #   [lb] thinks we should speed up the initial load time, and lazy
         #        load minor things, like tag counts and discussions (and
         #        maybe not throb, so user thinks map loaded quickly).
         qb.filters.skip_tag_counts = True
         Query_Overlord.finalize_query(qb)
         # NOTE: tag.Many() will search just the basemap branch at qb.rev'n.
         attc_tags = tag.Many()
         attc_tags.search_for_items(qb)
         g.assurt(len(attc_tags) > 0)
         qb.db.close()
         for attc_tag in attc_tags:
            g.assurt(attc_tag.stack_id not in self.cache_tags)
            if attc_tag.name:
               self.cache_tags[attc_tag.stack_id] = attc_tag
               self.attr_and_tag_ids.add(attc_tag.stack_id)
            else:
               log.warning('load_cache_attc_tags: nameless tag: %s'
                           % (attc_tag,))
         log.verbose1('load_cache_attc_tags: found %d tags in %s'
                      % (len(self.cache_tags),
                         misc.time_format_elapsed(time_0),))
      else:
         log.warning('load_cache_attc_tags: already loaded tags')

   # BUG nnnn: flashclient/checkout should use this instead of getting byways
   # and then sending a bunch of stack_ids. Also make lighter-weight response
   # for flashclient. Maybe some filters to say if tags and attrs are wanted?

   #
   def load_feats_and_attcs_reset(self):
      #log.debug('load_feats_and_attcs_reset')
      self.prog_log = None
      self.heavyweight = None
      self.keep_running = None
      self.use_stack_id_table = False
      self.geofeat_many = None
      self.geofeats_cnt = 0
      self.cache_items_attrs = {}
      self.cache_items_tagged = {}
      if self.heavyweight:
         g.assurt(False) # We just set heavyweight to None, silly.
         self.cache_link_values = {}
      else:
         self.cache_link_values = None
      self.cache_n_notes = {}
      self.cache_n_posts = {}
      self.load_groups_access = False

   # *** Bulk Item Loaders

   #
   # feat_search_fcn is, i.e., 'search_for_items' or 'search_by_network'
   def load_feats_and_attcs(self, ref_qb,
                                  feat_class,
                                  feat_search_fcn,
                                  processing_fcn,
                                  prog_log=None,
                                  heavyweight=False,
                                  fetch_size=0,
                                  keep_running=None,
                                  diff_group=None,
                                  load_groups_access=False,
                                  max_iters=0):

      # FIXME: For import/export, implement keep_running.

      t0_all = time.time()

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
         log.info('load_feats_and_attcs: mem_usage: beg: %.2f Mb'
                  % (usage_0,))

      log.verbose1('load_feats_and_attcs: loading/hydrating geofeatures...')

      # *** Load Attribute and Tag Caches

      # If not already loaded, load the tags and attrs now.
      self.load_cache_attachments(ref_qb)

      # *** Prepare the query builder

      g.assurt(not ref_qb.filters.pagin_total)

      # CcpV2 originally cloned the qb and the db and started with fresh
      # filters. But we want to let the client send us whatever filters they
      # want, so they have more control over the bulk checkout. And anyway,
      # all we really care about is that we clone the db, because we iterate
      # through results and the user won't be able to use the cursor otherwise.
      #qb = ref_qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      qb = ref_qb.clone(skip_clauses=True, skip_filtport=False, db_clone=True)
      Query_Overlord.finalize_query(qb)

      try:
         # Prepare the processing attrs.
         self.load_feats_and_attcs_reset()
         self.prog_log = prog_log
         self.heavyweight = heavyweight
         self.keep_running = keep_running
         self.load_groups_access = load_groups_access
         #
         self.load_feats_and_attcs_(qb, ref_qb,
                                    feat_class, feat_search_fcn,
                                    fetch_size, processing_fcn,
                                    diff_group, max_iters)
      finally:
         self.load_feats_and_attcs_reset()
         # Close our copy of the cursor.
         qb.db.close()

      conf.debug_log_mem_usage(log, usage_0, 'item_mgr.load_feats_and_attcs')

      # *** All done

   def load_feats_and_attcs_(self, qb, ref_qb, feat_class, feat_search_fcn,
                                       fetch_size, processing_fcn, diff_group,
                                       max_iters):

      qb.db.dont_fetchall = True

      if fetch_size:
         qb.filters.pagin_count = fetch_size
         if not max_iters:
            pagin_offset = 0
         else:
            pagin_offset = qb.filters.pagin_offset
      else:
         pagin_offset = None

      if isinstance(feat_class, geofeature.Many):
         geofeats = feat_class
      else:
         # Else, a module.
         geofeats = feat_class.Many()
      # Generally, geofeats is a derived class (like byway.Many), but it could
      # also be an intermeditate class (like geofeature.Many, as in,
      #   ./ccp.py -r -t geofeature -I 983982).
      #  NO: g.assurt(type(geofeats) is not geofeature.Many)

      self.geofeat_many = geofeats

      fetch_iter = 1
      while fetch_iter > 0:

         log.verbose1('load_feats_and_attcs_: fetch_iter: %d / fetchall: %s'
                      % (fetch_iter, qb.db.dont_fetchall,))

         if pagin_offset is not None:
            qb.filters.pagin_offset = (
               pagin_offset + qb.filters.pagin_count * (fetch_iter - 1))

         self.temp_tables = []

         # *** Get Geofeatures

         Item_Manager.search_for_wrap(qb, self.geofeat_many,
                                          feat_search_fcn,
                                          self.keep_running)

         log.verbose('load_feats_and_attcs_: fetchall (2): %s'
                     % (qb.db.dont_fetchall,))

         self.geofeats_cnt = qb.db.curs.rowcount

         if not self.geofeats_cnt:
            # This happens if, e.g., you zoom way in and get no waypoints.
            # 2014.07.22: This also happens for Terrain since we don't
            #             have Terrain outside the metro.
            log.debug('load_feats_and_attcs: zero gfs: %s / %s / %s'
                      % (qb, feat_class, feat_search_fcn,))
            fetch_iter = 0
            break

         qb.filters.min_access_level = None
         qb.revision.allow_deleted = False

         # *** Load Link_Values, maybe

         if ((not ref_qb.filters.dont_load_feat_attcs)
             or (ref_qb.filters.do_load_lval_counts)):

            # Before we can get link_values, we need to know if we want them
            # all, or just those associated with particular IDs. Also, it
            # seems silly to pass a big WHERE stack_id IN (..., ..., ). Some
            # docs suggest the limit is 1,000 items (though I swear I've seen
            # more) but it seems like, rather than having SQL process a big IF
            # clause, we should make a temporary table to join against. I [lb]
            # don't know if this saves memory or processing time....

            qb_lvals = qb.clone(skip_clauses=True,
                                skip_filtport=True,
                                db_clone=True)

            log.verbose(
               'load_feats_and_attcs_: fetchall (3): %s (qb_lvals: %s)'
               % (qb.db.dont_fetchall, qb_lvals.db.dont_fetchall,))

            qb_lvals.request_is_local = True

            # Start a r/w op since we might make a lookup table.
            qb_lvals.db.transaction_begin_rw()

            # If we throw because of keep_running or an error, be sure to clean
            # up.

            try:

               Query_Overlord.finalize_query(qb_lvals)

               log.verbose('load_feats_and_attcs_: fetchall (4): %s'
                           % (qb.db.dont_fetchall,))

               # Load a temporary table of stack IDs.
               self.load_feats_and_attcs_load_stack_ids(qb, qb_lvals,
                                                        diff_group)

               # *** Get Attribute and Tag Link_Values

               # Normally, we load these .:. Normally, dont_... is False.
               if not ref_qb.filters.dont_load_feat_attcs:
                  self.load_feats_and_attcs_load_attcs(qb, qb_lvals,
                                                       diff_group)

               # *** Get Annotation and Post Link_Value Counts

               # Flashclient only gets counts when the user wants to highlight
               # features with tags and annotations.
               if ref_qb.filters.do_load_lval_counts:
                  self.load_feats_and_attcs_load_lcnts(qb, qb_lvals)

               # *** Free the Link_Value db objects

            finally:

               if qb_lvals.filters.stack_id_table_rhs:
                  qb_lvals.db.sql(
                     "DROP TABLE %s" % (qb_lvals.filters.stack_id_table_rhs,))
                  qb_lvals.filters.stack_id_table_rhs = ''

               # Relinquish the db connection.
               qb_lvals.db.close()

         # *** Process the Completed Geofeatures

         self.load_feats_and_attcs_load_feats(qb, ref_qb, diff_group,
                                                  processing_fcn)

         # *** Cleanup the temp table(s).

         # 2013.05.01: Why is [lb] just now seeing a problem with this?
         #             Dropping a temp table raises psycopg2.OperationalError.
         #   for tmp_table in self.temp_tables:
         #      sql_drop_table = "DROP TABLE %s" % (tmp_table,)
         #      qb_lvals.db.sql(sql_drop_table)
         # Don't try dropping temp tables; just clear our references to them.
         self.temp_tables = []

         # *** Loop again for more results, maybe

         # See if we should keep looping.
         if fetch_size:
            g.assurt(qb.filters.pagin_count)
            if not max_iters:
               if qb.db.curs.rowcount < qb.filters.pagin_count:
                  fetch_iter = 0
               else:
                  g.assurt(qb.db.curs.rowcount == qb.filters.pagin_count)
                  fetch_iter += 1
                  # Keep going until we've found everything.
            else:
               if fetch_iter < max_iters:
                  fetch_iter += 1
               else:
                  fetch_iter = 0
         else:
            fetch_iter = 0

      # end while

   #
   def load_feats_and_attcs_load_stack_ids(self, qb, qb_lvals, diff_group):

      self.use_stack_id_table = False

      if (qb.filters.pagin_count
          or (qb.filters.filter_by_regions)
          or (qb.viewport and qb.viewport.include)
          or (qb.filters.only_stack_ids)
          or (qb.filters.stack_id_table_ref)
          # If we're fetching more geofeatures than this,
          # we'll just get all link_values.
          # MAYBE: What's a good number here?
          #or (self.geofeats_cnt < 50000)):
          or (self.geofeats_cnt < 100000)):
          #or (self.geofeats_cnt < 250000)):

         self.use_stack_id_table = True

         stack_id_list = []
         generator = self.geofeat_many.results_get_iter(qb)
         for feat in generator:
            stack_id_list.append(feat.stack_id)
         generator.close()

         # Suffix to indicate this is a counterpart search.
         cp_suffix = ''
         if diff_group is not None:
            cp_suffix = '_%s' % (diff_group,)
         temp_table_name = 'item_mgr_rhs%s' % (cp_suffix,)
         log.debug('_load_stack_ids: creating "temp_stack_id__%s"'
                   % (temp_table_name,))
         self.temp_tables.append(
            qb_lvals.load_stack_id_lookup(
               temp_table_name,
               stack_id_list,
               rhs=True))

   #
   def load_feats_and_attcs_load_attcs(self, qb, qb_lvals, diff_group):

      # Get some or all of the link_values.

      time_0 = time.time()
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
      log.debug(
         "load_fts_n_ats_load_attcs: searching for %s features' link_values..."
         % (("%d items'" % self.geofeats_cnt) if self.use_stack_id_table
             else 'all',))

      # NOTE: If you find this search being slow, check postgresql.conf's
      #       join_collapse_limit and/or reorder the FROM/JOIN clause to be
      #       more efficient. This could mean the different between hundreths
      #       of a second and seconds of a second.

      # This is wrong: If you search for link_values, the search follows the
      # branch_hier, which is wrong for tags, since tags are only saved to the
      # basemap. So if someone tags a byway in a branch with a tag that was
      # added to the basemap after last_merge_rid, then the tag link_value is
      # hidden, because it looks like the user cannot access the tag.
      # Also, we've already searched for attributes and tags this user
      # can access, so we can save time (hopefully) by joining against a temp
      # stack ID table than by doing an inner select on the gia for the links.
      #   lvals = link_value.Many(
      #               attc_types=[Item_Type.ATTRIBUTE,
      #                           Item_Type.TAG,],
      #               feat_types=self.geofeat_many.one_class.item_type_id)

      g.assurt(not qb_lvals.filters.stack_id_table_lhs)

      if qb_lvals.filters.stack_id_table_rhs:
         # Get just the rhs items specified by the stack ID temp table.
         lvals = link_value.Many()
      else:
         # Get all rhs items of the specified geofeature type.
         # NOTE: We don't mark-deleted link_values of deleted byways, and
         # link_value is smart enough not to fetch them. (Otherwise, if we
         # split a byway in a branch that wasn't already split in that branch,
         # we'd have to copy all the link values to the branch and then mark
         # them all deleted; so if you delete (maybe because of a split) a
         # byway in a branch, we'll just copy the byway and mark it deleted but
         # we won't touch the deleted byway's link_values.)
         lvals = link_value.Many(
                     attc_types=None,
                     feat_types=self.geofeat_many.one_class.item_type_id)

      # Suffix to indicate this is a counterpart search.
      cp_suffix = ''
      if diff_group is not None:
         cp_suffix = '_%s' % (diff_group,)
      temp_table_name = 'item_mgr_lhs%s' % (cp_suffix,)
      log.debug('load_feats_and_attcs_load_attcs: creating "temp_stack_id__%s"'
                % (temp_table_name,))
      self.temp_tables.append(
         qb_lvals.load_stack_id_lookup(
            temp_table_name,
            self.attr_and_tag_ids,
            lhs=True))

      qb_lvals.db.dont_fetchall = True

      # 2012.04.24: This query has lots of joins. To make sure it runs fast,
      #        make sure you've SET LOCAL join_collapse_limit = high enough;

      g.assurt(qb_lvals.sql_clauses is None)

      lvals.search_for_items(qb_lvals)

      log.info('load_feats_and_attcs: read %d link_vals at %s in %s'
               % (qb_lvals.db.curs.rowcount,
                  qb_lvals.revision.short_name(),
                  misc.time_format_elapsed(time_0),))
      conf.debug_log_mem_usage(
         log, usage_0, 'item_mgr.load_feats_and_attcs / search_for_items')

      g.check_keep_running(self.keep_running)

      # Make lookups for the attachments.

      time_0 = time.time()
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()

      self.cache_items_attrs = {}
      self.cache_items_tagged = {}
      if self.heavyweight:
         self.cache_link_values = {}

      log.debug('load_feats_and_attcs: heavyweight %s / load_groups_access %s'
                % (self.heavyweight, self.load_groups_access,))
      #log.debug(' .. : %s' % (str(self),))
      self.log_self()

      # FIXME/BUG nnnn: log_progger could just time.time() and report
      #                 every x seconds, rather than every x iterations.
      #log_freq = 1000
      #log_freq = 10000
      #log_freq = 25000
      log_freq = 12500
      prog_log_lvals = Debug_Progress_Logger(log_freq=log_freq,
                           loop_max=qb_lvals.db.curs.rowcount)
      prog_log_lvals.info_print_speed_enable = True

      log.debug('load_feats_and_attcs: Making link_value cache...')

      generator = lvals.results_get_iter(qb_lvals)
      for lval in generator:
         # C.f. item_base
         if lval.link_lhs_type_id == Item_Type.ATTRIBUTE:
            self.cache_link_attribute(lval, self.cache_items_attrs)
         elif lval.link_lhs_type_id == Item_Type.TAG:
            self.cache_link_tag(lval, self.cache_items_tagged)
         else:
            # 2014.04.06: link_lhs_type_id None b/c bulk insert left it null.
            g.assurt(lval.link_lhs_type_id is not None)
            g.assurt(False)
            log.debug(
               'load_feats_and_attcs: skipping link to unknown type: %s'
               % (lval.link_lhs_type_id,))
         if self.heavyweight:
            if self.load_groups_access:
               lval.groups_access_load_from_db(qb)
            misc.dict_dict_update(self.cache_link_values,
                                  lval.rhs_stack_id,
                                  lval.lhs_stack_id,
                                  lval,
                                  # We should add each lhs/rhs combo once.
                                  strict=True)
         if prog_log_lvals.loops_inc():
            pass # Don't short-circuit; it takes < 1 min. to load 500K links
         g.check_keep_running(self.keep_running)
      generator.close()

      # Clean the qb.
      if qb_lvals.filters.stack_id_table_lhs:
         qb_lvals.db.sql(
            "DROP TABLE %s" % (qb_lvals.filters.stack_id_table_lhs,))
         qb_lvals.filters.stack_id_table_lhs = ''

      prog_log_lvals.loops_fin('load_feats_and_attcs-link_vals')

      time_delta = time.time() - time_0
      if time_delta > conf.db_glue_sql_time_limit:
         log.info('load_feats_and_attcs: made link_vals caches in %s'
                  % (misc.time_format_scaled(time_delta)[0],))
      conf.debug_log_mem_usage(
         log, usage_0, 'item_mgr.load_feats_and_attcs / final')

   #
   def load_feats_and_attcs_load_lcnts(self, qb, qb_lvals):

      time_0 = time.time()
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
      log.debug(
         "load_fts_n_ats_load_lcnts: searching for %s features' lval counts..."
          % (("%d items'" % self.geofeats_cnt) if self.use_stack_id_table
              else 'all',))

# BUG nnnn: link_value does a gia search using the branch and revs, which for
# post is wrong, since we want just posts for the leafiest branch.
# Maybe we can cheat and say that notes are branch-specific, too....

      g.assurt(not qb_lvals.filters.stack_id_table_lhs)

      if qb_lvals.filters.stack_id_table_rhs:
         # Get just the rhs items specified by the stack ID temp table.
         # Compare to the similar construct in
         # load_feats_and_attcs_load_attcs
         lvals = link_value.Many(
                     attc_types=[Item_Type.ANNOTATION,
                                 Item_Type.POST,],
                     feat_types=None)
      else:
         # Get all rhs items of the specified geofeature type.
         lvals = link_value.Many(
                     attc_types=[Item_Type.ANNOTATION,
                                 Item_Type.POST,],
                     feat_types=self.geofeat_many.one_class.item_type_id)

      # Set sql_clauses for search_get_sql.
      # Not using: sql_clauses_cols_setup().
      qb_lvals.sql_clauses = lvals.sql_clauses_cols_all.clone()

      inner_sql = lvals.search_get_sql(qb_lvals)

      # We have a query that will fetch link_values, so make an outer select
      # that reduces these to counts of link_values per geofeature per
      # attachment.

      counts_sql = (
         """
         SELECT
            rhs_stack_id,
            link_lhs_type_id,
            COUNT(rhs_stack_id) AS n_lvals
         FROM
            (%s) AS group_item
         GROUP BY
            rhs_stack_id,
            link_lhs_type_id
         ORDER BY
            rhs_stack_id
         """ % (inner_sql,))

      log.verbose('load_fts_n_ats_load_lcnts: enabling dont_fetchall')
      qb_lvals.db.dont_fetchall = True
      res = qb_lvals.db.sql(counts_sql)

      generator = qb_lvals.db.get_row_iter()
      for row in generator:
         #log.debug('load_cnts: stid: %d / itid: %d / cnts: %d'
         #   % (row['rhs_stack_id'], row['link_lhs_type_id'], row['n_lvals'],))
         if row['link_lhs_type_id'] == Item_Type.ANNOTATION:
            self.cache_n_notes[row['rhs_stack_id']] = row['n_lvals']
         elif row['link_lhs_type_id'] == Item_Type.POST:
            self.cache_n_posts[row['rhs_stack_id']] = row['n_lvals']
         else:
            g.assurt(False)
      generator.close()

      log.verbose('load_fts_n_ats_load_lcnts: disabling dont_fetchall')
      qb_lvals.db.dont_fetchall = False

      log.info('load_fts_n_ats_load_lcnts: read link_val counts in %s'
               % (misc.time_format_elapsed(time_0),))
      conf.debug_log_mem_usage(
         log, usage_0, 'load_fts_n_ats_load_lcnts / counts_sql')

      g.check_keep_running(self.keep_running)

   #
   def load_feats_and_attcs_load_feats(self, qb, ref_qb, diff_group,
                                             processing_fcn):

      # Pass the completed geofeatures back to the processing function.

      time_0 = time.time()
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
      log.debug('load_fts_n_ats_load_fts: processing %d geofeatures...'
                % (self.geofeats_cnt,))

      if self.prog_log is None:
         self.prog_log = Debug_Progress_Logger()
         self.prog_log.log_freq = (self.geofeats_cnt / 5) or 1
      else:
         self.prog_log.loops_reset()
      self.prog_log.loop_max = self.geofeats_cnt

      #qb.diff_group = diff_group
      ref_qb.diff_group = diff_group

      # Wire the feature using the caches.
      generator = self.geofeat_many.results_get_iter(qb)
      for feat in generator:

         if not ref_qb.filters.dont_load_feat_attcs:

            # Wire attributes
            try:
               feat.attrs = self.cache_items_attrs[feat.stack_id]
               del self.cache_items_attrs[feat.stack_id]
            except KeyError:
               # FIXME: Is this necessary?:
               #feat.attrs = {}
               pass

            # Wire tags
            try:
               feat.tagged = self.cache_items_tagged[feat.stack_id]
               del self.cache_items_tagged[feat.stack_id]
            except KeyError:
               # FIXME: Is this necessary?:
               #feat.tagged = set()
               pass

            # Wire heavyweight link_values
            if self.heavyweight:
               try:
                  feat.link_values = self.cache_link_values[feat.stack_id]
                  # Since we set feat.attrs, feat.tagger, and feat.link_values,
                  # we don't need to call wire_lval.
                  #log.debug('load_fts_n_ats_load_fts: set all lval: %s'
                  #          % (feat.link_values,))
                  del self.cache_link_values[feat.stack_id]
               except KeyError, e:
                  # I.e., feat.stack_id didn't hit, so no link vals.
                  #
                  # On error, set the link_values to the empty dict so code
                  # doesn't think we didn't try to load 'em (and then do a
                  # slowload, i.e., with load_links_slow).
                  feat.link_values = {}

            # Say it is so. (Note that lvals_wired_ refers to attrs and tagged;
            # it does not imply heavyweight, or that link_values is set up.)
            feat.lvals_wired_ = True

         if ref_qb.filters.do_load_lval_counts:
            # Wire annotation counts
            try:
               feat.annotation_cnt = self.cache_n_notes[feat.stack_id]
               del self.cache_n_notes[feat.stack_id]
            except:
               pass
            # Wire post counts
            try:
               feat.discussion_cnt = self.cache_n_posts[feat.stack_id]
               del self.cache_n_posts[feat.stack_id]
            except:
               pass

         # Load the reference byway's groups_access.
         # FIXME: Can we bulk-load groups_access records?
         g.assurt(feat.groups_access is None)
         if self.load_groups_access:
            feat.groups_access_load_from_db(ref_qb)

         # Call the caller's callback.
         # FIXME: I think you need the ref_qb, for diff_counterparts.
         #processing_fcn(qb, feat)
         try:
            processing_fcn(ref_qb, feat, self.prog_log)
         except Exception, e:
            log.error('processing_fcn: failed on feat: %s' % (feat,))
            log.error(e)
            raise

         #processed_cnt += 1
         g.check_keep_running(self.keep_running)
         if self.prog_log.loops_inc():
            break

      generator.close()

      self.prog_log.loops_fin()

      log.info('load_fts_n_ats_load_fts: processed %d geofeats in %s'
               #% (processed_cnt,
               % (self.prog_log.progress,
                  misc.time_format_elapsed(time_0),))
      conf.debug_log_mem_usage(
         log, usage_0, 'load_fts_n_ats_load_fts / geofeats')

   # ***

   #
   # feat_search_fcn is, i.e., 'search_for_items'.
   def load_items_quick(self, qb, item_class, item_search_fcn,
                              processing_fcn, prog_log=None,
                              keep_running=None, diff_group=None):

      t0_all = time.time()

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()

      g.assurt(not qb.db.dont_fetchall)

      Query_Overlord.finalize_query(qb)

      if isinstance(item_class, item_versioned.Many):
         items = item_class
      else:
         # Else, a module.
         items = item_class.Many()

      log.debug('load_items_quick: searching for items...')

      qb.diff_group = diff_group

      Item_Manager.search_for_wrap(qb, items, item_search_fcn,
                                   keep_running)

      if not qb.db.dont_fetchall:
         item_cnt = len(items)
      else:
         item_cnt = qb.db.curs.rowcount

      if item_cnt and qb.db.dont_fetchall:

         # Pass the items back to the processing function.

         time_0 = time.time()
         usage_inner_0 = None
         if conf.debug_mem_usage:
            usage_inner_0 = mem_usage.get_usage_mb()
         log.debug('load_items_quick: processing %d items...' % (item_cnt,))

         if prog_log is None:
            prog_log = Debug_Progress_Logger()
            prog_log.log_freq = (item_cnt / 5) or 1
         else:
            prog_log.loops_reset()
         prog_log.loop_max = item_cnt

         qb.diff_group = diff_group

         generator = items.results_get_iter(qb)
         for an_item in generator:
            # Call the caller's callback.
            processing_fcn(qb, an_item)
            #processed_cnt += 1
            g.check_keep_running(keep_running)
            if prog_log.loops_inc():
               break
         generator.close()

         prog_log.loops_fin()

         log.info('load_items_quick: processed %d items in %s'
                  % (prog_log.progress,
                     misc.time_format_elapsed(time_0),))
         conf.debug_log_mem_usage(
            log, usage_inner_0, 'load_items_quick / inner')

      conf.debug_log_mem_usage(
         log, usage_0, 'load_items_quick / outer')

      # Reset calculated and SQL-related filters, and reset the db cursor.
      qb.db.curs_recycle()
      #qb.definalize()

      log.verbose('load_items_quick: disabling dont_fetchall')
      qb.db.dont_fetchall = False

   #
   @staticmethod
   def search_for_wrap(qb, items, item_search_fcn, keep_running=None):

      time_0 = time.time()
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()

      adj = qb.filters.get_fetch_size_adj()
      item_type_str = Item_Type.id_to_str(items.one_class.item_type_id)
      # MAYBE: What are branchs [sic]? Implement Inflector.as in python.
      log.debug('search_for_wrap: seeking %s %ss using %s...'
                % (adj, item_type_str, item_search_fcn,))

      search_fcn = getattr(items, item_search_fcn)
      search_fcn(qb)

      log.verbose('search_for_wrap: dont_fetchall: %s'
                  % (qb.db.dont_fetchall,))
      if not qb.db.dont_fetchall:
         item_cnt = len(items)
      else:
         item_cnt = qb.db.curs.rowcount

      log.debug('search_for_wrap: read %d %ss at %s in %s'
                % (item_cnt, item_type_str, qb.revision.short_name(),
                   misc.time_format_elapsed(time_0),))
      conf.debug_log_mem_usage(log, usage_0, 'search_for_wrap')

      g.check_keep_running(keep_running)

   # ***

   #
   # C.f. item_base.py
   def cache_link_attribute(self, lval_attr, cache_items_attrs):
      # RESOURCES: Keeping refs of the link_values (all 500,000 of them)
      # bloats the MSP v1 route finder to 3 GB memory usage.
      # NO: self.link_values[lval_attr.lhs_stack_id] = lval_attr
      g.assurt(self.cache_attrs is not None)
      cache_items_attrs.setdefault(lval_attr.rhs_stack_id, dict())
      try:
         stack_id = lval_attr.rhs_stack_id
         the_attr = self.cache_attrs[lval_attr.lhs_stack_id]
         attr_name = the_attr.value_internal_name
         if not lval_attr.deleted:
            cache_items_attrs[stack_id][attr_name] = (
                           lval_attr.get_value(the_attr))
         else:
            del cache_items_attrs[stack_id][attr_name]
      except KeyError:
         log.warning(
            'wire_link_attr: missing attr: item_mgr: %s / lhs_stack_id: %d'
            % (self, lval_attr.lhs_stack_id,))

   #
   # C.f. item_base.py
   def cache_link_tag(self, lval_tag, cache_items_tagged):
      g.assurt(self.cache_tags is not None)
      # Hahaha, this probably doesn't need to be a set: the database should
      # guarantee no duplicates.
      # cache_items_tagged is temporary; it'll become feat.tagged.
      cache_items_tagged.setdefault(lval_tag.rhs_stack_id, set())
      try:
         stack_id = lval_tag.rhs_stack_id
         the_tag = self.cache_tags[lval_tag.lhs_stack_id]
         g.assurt(the_tag.name)
         if not lval_tag.deleted:
            cache_items_tagged[stack_id].add(the_tag.name)
         else:
            try:
               cache_items_tagged[stack_id].remove(the_tag.name)
            except KeyError:
               pass
      except KeyError:
         log.warning('wire_link_tag: missing tag! item_mgr: %s / stack_id: %d'
                     % (self, lval_tag.lhs_stack_id,))

   # ***

   #
   def cache_tag_lookup_by_name(self, tag_name):
      g.assurt(self.cache_tags is not None)
      self.cache_tag_ensure_by_name()
      try:
         the_tag = self.cache_tagnames[tag_name.lower()]
      except KeyError:
         the_tag = None
      return the_tag

   #
   def cache_tag_ensure_by_name(self):
      # Build the tags-by-tag_name cache if not built.
      if self.cache_tagnames is None:
         self.cache_tagnames = {}
         for some_tag in self.cache_tags.itervalues():
            if some_tag.name:
               self.cache_tagnames[some_tag.name.lower()] = some_tag
            else:
               # This happens if you somehow save a tag with no name.
               log.warning('cache_tag_ensure_by_name: nameless tag: %s'
                           % (some_tag,))

   #
   def cache_tag_insert(self, the_tag):
      # Build the tags-by-tag_name cache if not built.
      if the_tag.name:
         self.cache_tags[the_tag.stack_id] = the_tag
         try:
            self.cache_tagnames[the_tag.name.lower()] = the_tag
         except TypeError:
            # If cache_tagnames is None.
            pass
      else:
         log.warning('cache_tag_insert: nameless tag: %s'
                     % (the_tag,))

   #
   # Skipping: the fcn. Mark the item deleted; do not remove from cache.
   #  def cache_tag_delete(self, the_tag):
   #     try:
   #        del self.cache_tags[the_tag.stack_id]
   #     except KeyError:
   #        pass
   #     try:
   #        del self.cache_tagnames[the_tag.name.lower()]
   #     except KeyError:
   #        # If the named tag doesn't exist.
   #        pass
   #     except TypeError:
   #        # If cache_tagnames is None.
   #        pass

   # ***

   temp_table_update_sids = 'temp_stack_id__item_mgr_b'
   temp_table_update_sids_cnt = 0

   #
   def update_feats_and_attcs(self, ref_qb, feat_class, feat_search_fcn,
                                    processing_fcn, prog_log=None,
                                    heavyweight=False, fetch_size=0,
                                    keep_running=None):

      g.assurt(isinstance(ref_qb.revision, revision.Updated))

      # This fcn. only triggered locally.
      g.assurt(ref_qb.request_is_local)

      # We're going to create a temporary table, so start a r/w op.
      #g.assurt(not ref_qb.db.transaction_in_progress())
      if not ref_qb.db.transaction_in_progress():
         cleanup_transaction = True
         ref_qb.db.transaction_begin_rw()
      else:
         cleanup_transaction = False
         #stack_trace = traceback.format_exc()
         #log.warning(
         #   'update_feats_and_attcs: unexpected transaction_in_progress: %s'
         #   % (stack_trace,))

      sid_count = Item_Manager.create_update_rev_tmp_table(ref_qb)

      if sid_count == 0:

         log.debug('update_feats_and_attcs: nothing found for %s at rev: %s'
                   % (str(feat_class), str(ref_qb.revision),))

      else:

         # Make sure you find denied items. load_feats_and_attcs will reset
         # this after doing the initial search for geofeatures, but before
         # grabbing lvals.
         g.assurt(ref_qb.filters.min_access_level is None)
         ref_qb.filters.min_access_level = Access_Level.denied

         # The Updated revision always allows deleted.
         g.assurt(ref_qb.revision.allow_deleted)
         # But we don't want to pass Updated to the load fcn.
         # item_user_access.search_get_sql() only accepts Updated from ccp.py,
         # and then it returns everything that's changed from all branches.
         # Which is why we explicitly searched for items above (via the helper,
         # create_update_rev_tmp_table), so we can now just search for items
         # with specific IDs and get the appropriately leafy item.
         rev = ref_qb.revision
         ref_qb.revision = revision.Historic(ref_qb.revision.rid_max)
         g.assurt(ref_qb.username)
         ref_qb.revision.setup_gids(ref_qb.db, ref_qb.username)
         # Ug. We're cheating.
         ref_qb.branch_hier[0] = (ref_qb.branch_hier[0][0],
                                  ref_qb.revision,
                                  ref_qb.branch_hier[0][2],)
         # Since we called setup_gids, we don't need to ref_qb.branch_hier_set.

         self.load_feats_and_attcs(ref_qb, feat_class, feat_search_fcn,
                                   processing_fcn, prog_log,
                                   heavyweight, fetch_size,
                                   keep_running)

         ref_qb.revision = rev
         ref_qb.branch_hier[0] = (ref_qb.branch_hier[0][0],
                                  ref_qb.revision,
                                  ref_qb.branch_hier[0][2],)
         # Since we called setup_gids, we don't need to ref_qb.branch_hier_set.

      ref_qb.db.sql("DROP TABLE %s" % (Item_Manager.temp_table_update_sids,))
      Item_Manager.temp_table_update_sids_cnt = None

      if cleanup_transaction:
         ref_qb.db.transaction_rollback()

   #
   @staticmethod
   def create_update_rev_tmp_table(qb):

      # Grab the stack IDs of all changed byways, regardless of branch_id,
      # geometric query, etc.
      #
      # This is a similar to prepare_temp_stack_id_table(table_name):
      # create a temporary table for us that specifies the stack_ids
      # to look for.

      g.assurt(isinstance(qb.revision, revision.Updated))

      # Do a basic revision filter; don't include branch IDs.

      # FIXME_2013_06_11: [lb] added WHERE check for branch_id.
      # I think this is right, but how often does this code get
      # excerised? Only on revision save from commit, which
      # hups routed, and also when apache cron sees a new revision
      # and checks which items changed. So, not very often.

      where_clause = qb.revision.as_sql_where()

      tmp_table_sql = (
         """
         CREATE TEMPORARY TABLE %s AS

         SELECT
             geofeature.stack_id AS stack_id
         FROM
            geofeature
         JOIN
            item_versioned
               USING (system_id)
         WHERE
            (%s AND geofeature.branch_id = %d)

         UNION(
            SELECT
               link_value.rhs_stack_id AS stack_id
            FROM
               link_value
            JOIN
               item_versioned
                  USING (system_id)
            WHERE
               (%s AND link_value.branch_id = %d)
         )
      """ % (Item_Manager.temp_table_update_sids,
             where_clause,
             qb.branch_hier[0][0],
             where_clause,
             qb.branch_hier[0][0],
             ))

      qb.db.sql(tmp_table_sql)

      # Use the temp table of stack_ids when looking up features.
      g.assurt(not qb.filters.stack_id_table_ref)
      # Set the reference table even if no results were found -- otherwise, if
      # a caller forgets to check the number of results, at least a query will
      # return 0 results, as opposed to returing all results.
      qb.filters.stack_id_table_ref = Item_Manager.temp_table_update_sids

      sql_sid_count = (
         "SELECT COUNT(*) FROM %s" % (Item_Manager.temp_table_update_sids,))
      rows = qb.db.sql(sql_sid_count)
      g.assurt(len(rows) == 1)
      Item_Manager.temp_table_update_sids_cnt = rows[0]['count']

      return Item_Manager.temp_table_update_sids_cnt

   # ***

   #
   def geofeature_layer_resolve(self, db, layer_name_or_id):
      try:
         layer_id = self.gfl_layer_id_lookup[layer_name_or_id]
         if layer_id is None:
            # We've already determined this is an unknown name or id.
            raise Exception('Unexpected geofeature type name or id: %s'
                            % (layer_name_or_id,))
         layer_name = self.gfl_layer_name_lookup[layer_id]
      except KeyError:
         try:
            layer_id = int(layer_name_or_id)
            rows = db.sql(
               """
               SELECT
                  layer_name, feat_type
               FROM
                  geofeature_layer
               WHERE
                  id = %s
               """,
               (layer_id,))
            if len(rows) > 0:
               g.assurt(len(rows) == 1)
               layer_name = rows[0]['layer_name']
            else:
               self.gfl_layer_id_lookup[layer_id] = None
               raise Exception('Unknown geofeature type id: %s'
                               % (layer_id,))
         except ValueError:
            layer_name = layer_name_or_id.lower().replace('_', ' ')
            if True:
               try:
                  layer_id = Item_Manager.gfid_lookup[layer_name]
               except KeyError:
                  self.gfl_layer_id_lookup[layer_name] = None
                  raise Exception('Unknown geofeature type name: %s'
                                  % (layer_name,))
            if False:
               rows = db.sql(
                  """
                  SELECT
                     id, feat_type
                  FROM
                     geofeature_layer
                  WHERE
                     layer_name = %s
                  """,
                  (layer_name,))
               if len(rows) > 0:
                  g.assurt(len(rows) == 1)
                  layer_id = rows[0]['layer_id']
               else:
                  self.gfl_layer_id_lookup[layer_name] = None
                  raise Exception('Unknown geofeature type name: %s'
                                  % (layer_name,))
         self.gfl_layer_id_lookup[layer_id] = layer_id
         self.gfl_layer_id_lookup[layer_name] = layer_id
         self.gfl_layer_name_lookup[layer_id] = layer_name
      return layer_id, layer_name

   # ***

   #
   @staticmethod
   def revision_save(qb,
                     rid,
                     branch_hier,
                     host,
                     username,
                     comment,
                     group_ids,
                     activate_alerts=False,
                     processed_items=None,
                     reverted_revs=None,
                     skip_geometry_calc=False,
                     skip_item_alerts=False):

      revision.Revision.revision_save(
            qb, rid, branch_hier, host, username, comment,
            group_ids, activate_alerts, processed_items,
            reverted_revs, skip_geometry_calc, skip_item_alerts)

# BUG_FALL_2013: Make sure gen_tilecache_cfg.py is running...!
      # 2013.01.13: This takes 0.19 mins. on Mpls-St. Paul, so don't block the
      # user's GWIS request; take this offline... so to speak. For now, see
      # gen_tilecache_cfg.py. Maybe later we'll move this to Mr. Do!
      # NO:
      #     time_0 = time.time()
      #     byway.Many.branch_coverage_area_update(db, rid, branch_hier)
      #     misc.time_complain('geosummary_update', time_0, 0.25)

   # *** Helper shims to avoid runtime import loops.

   #
   def finalize_query(self, qb):
      Query_Overlord.finalize_query(qb)

   #
   def get_system_attr(self, qb, internal_name):
      # MAYBE: Should we cache the attribute?
      system_attr = attribute.Many.get_system_attr(qb, internal_name)
      return system_attr

   # ***

   #
   def lval_resolve_overlapping(self, qb, new_lval, old_lval, force=False):
      suc = True
      multiple_allowed = False
      merge_the_two = False
      if (    (new_lval.lhs_stack_id == old_lval.lhs_stack_id)
          and (new_lval.rhs_stack_id == old_lval.rhs_stack_id)):
         # Only some attributes can be linked to the same items more than once.
         # But most attributes and all other attachment types maintain a 1-to-1
         # relationship with rhs items.
         # Also, it's expected that our item cache contains the linked items.
         try:
            lhs_item = self.item_cache[new_lval.lhs_stack_id]
            rhs_item = self.item_cache[new_lval.rhs_stack_id]
         except KeyError, e:
            log.error('lv_rslv_ovrlppg: missing lhs and rhs: %s / %s'
                      % (new_lval, old_lval,))
            suc = False
         if suc:
            try:
               multiple_allowed = lhs_item.multiple_allowed
            except AttributeError:
               pass
            if not multiple_allowed:
               if force:
                  merge_the_two = True
                  #
                  log.debug('lv_rslv_ovrlppg: force: new: %s' % (new_lval,))
                  log.debug('lv_rslv_ovrlppg: force: old: %s' % (old_lval,))
               else:
                  suc = False
                  #
                  log.warning(
                     'lv_rslv_ovrlppg: not multiple_allowed: new: %s / old: %s'
                      % (new_lval, old_lval,))
            else:
               # The attribute is multiple_allowed... for now, multiple_allowed
               # is used by privateish link_values, like item_watchers, so we
               # should look for existing privatish link_values.
               if qb.username == conf.anonymous_username:
                  raise GWIS_Error(
                     'Unexpected: anon user cannot commit personal links (1)')
               # The groups_access should be loaded and there's one record, for
               # the user whose link this is.
               g.assurt(len(old_lval.groups_access) == 1)
               try:
                  gia = old_lval.groups_access[qb.user_group_id]
                  # So, this is the user's link!
                  log.info(
                     'lv_rslv_ovrlppg: mult_allwd: for user: new: %s / old: %s'
                      % (new_lval, old_lval,))
                  if new_lval.stack_id != old_lval.stack_id:
                     log.warning(
                        'lv_rslv_ovrlppg: client sent bad: new: %s / old: %s'
                        % (new_lval, old_lval,))
                     merge_the_two = True
               except KeyError:
                  # Not this user's link.
                  log.debug(
                     'lv_rslv_ovrlppg: mult_allwd: not user: new: %s / old: %s'
                      % (new_lval, old_lval,))
      else:
         log.info('lv_rslv_ovrlppg: ignoring disparate links: %s / %s'
                  % (new_lval, old_lval,))
      if merge_the_two:
         # We could just use the existing link_value's stack_id, e.g.,
         #   new_lval.stack_id = old_lval.stack_id
         # but the link_value was already saved, and the new link_value
         # is still marked fresh... so copy in the other direction.
         old_lval.value_boolean = new_lval.value_boolean
         old_lval.value_integer = new_lval.value_integer
         old_lval.value_real = new_lval.value_real
         old_lval.value_text = new_lval.value_text
         old_lval.value_binary = new_lval.value_binary
         old_lval.value_date = new_lval.value_date
         #old_lval.direction_id = new_lval.direction_id
         #old_lval.line_evt_mval_a = new_lval.line_evt_mval_a
         #old_lval.line_evt_mval_b = new_lval.line_evt_mval_b
         #old_lval.line_evt_dir_id = new_lval.line_evt_dir_id

      return (suc, multiple_allowed,)

   # ***

   #
   def watcher_add_alerts(self, qb, rid, processed_items, reverted_revs):

      if not isinstance(qb.revision, revision.Current):
         qb = qb.clone()
         qb.revision = revision.Current()
         qb.branch_hier[0] = (qb.branch_hier[0][0],
                              qb.revision,
                              qb.branch_hier[0][2],)
         # MAYBE: Should we call either qb.branch_hier_set,
         # or qb.revision.setup_gids(qb.db, qb.username),
         # to setup qb.revision.gids? watchers isn't all
         # the way implemented so [lb] isn't sure...

      watcher = Watcher_Watcher(qb)
      watcher.add_alerts(rid, processed_items, reverted_revs)

   # ***

   #
   @staticmethod
   def item_type_from_stack_id(qb, stk_id_maybe):
      itype_id = None
      lhs_type_id = None
      rhs_type_id = None
      item_type_sql = (
         """
         SELECT item_type_id, link_lhs_type_id, link_rhs_type_id
         FROM group_item_access
         WHERE stack_id = %d
           AND valid_until_rid = %d
         ORDER BY version DESC, acl_grouping DESC
         LIMIT 1
         """ % (stk_id_maybe, conf.rid_inf,)) 
      rows = qb.db.sql(item_type_sql)
      if len(rows) > 0:
         g.assurt(len(rows) == 1)
         itype_id = rows[0]['item_type_id']
         if rows[0]['link_lhs_type_id']:
            lhs_type_id = rows[0]['link_lhs_type_id']
         if rows[0]['link_rhs_type_id']:
            rhs_type_id = rows[0]['link_rhs_type_id']
      return (itype_id, lhs_type_id, rhs_type_id,)

   # ***

# ***


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import gc
import os
import sys
import time

import conf
import g

from grax.access_level import Access_Level
from grax.item_manager import Item_Manager
from gwis.query_overlord import Query_Overlord
from item import link_value
from item.feat import branch
from item.feat import byway
from item.util import ratings
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from util_.log_progger import Debug_Progress_Logger
from util_ import db_glue
from util_ import mem_usage
from util_ import misc

log = g.log.getLogger('tgraph_base')

__all__ = ('Trans_Graph_Base',)

class Trans_Graph_Base(object):
   'Transportation network as a graph.'

   __slots__ = (
      'route_daemon',
      #
      # The user on behalf of whom we're loading the map. Usually, this is the
      # anonymous public user.
      'username',
      #
      # The branch hierarchy of the road network being loaded.
      'branch_hier',
      #
      # Either revision.Current to follow the head, or revision.Historic to
      # just load a static graph at the specified revision.
      'revision',
      #
      # Maximum revision ID represented in the current graph.  Used to
      # incrementally update the street network when a new revision is saved.
      'rid_max',
      #
      # In CcpV1, the ratings model is managed by the callers that make the
      # transit graphs. But we only ever use the same ratings.Predictor()
      # class, and we always have one Predictor per Trans_Graph. It makes
      # things a little easier to just have the graph also manage the model.
      'ratings',
      #
      # Rather than keeping a collection of heavyweight byways, we use a
      # somewhat-lighterweight collection of route_steps.
      'step_lookup',
      #
      # We keep a handle to the db connection while updating so that we can be
      # canceled.
      'update_db',
      )

   # *** Constructor

   def __init__(self, route_daemon,
                      username=None, branch_hier=None, revision_=None):
      self.route_daemon = route_daemon
      self.username = username or route_daemon.cli_opts.username
      self.branch_hier = branch_hier or route_daemon.cli_args.branch_hier
      self.revision = revision_ or route_daemon.cli_args.revision
      g.assurt(self.username and self.branch_hier and self.revision)
      g.assurt(isinstance(self.revision, revision.Current)
               or isinstance(self.revision, revision.Historic))
      self.update_db = None
      self.destroy()

   # *** Memory management

   # Cleanup any memory that the garbage collector won't. This is a no-op for
   # the p1 route finder, since it uses only Pure Python Objects. But for the
   # p2 route finder, we need to actively destroy C-objects.
   def destroy(self):
      self.rid_max = 0
      self.ratings = None
      self.step_lookup = dict()
      if self.update_db is not None:
         self.update_db.close()
         self.update_db = None

   # *** Public interface: load (or update) the transportation network.

   #
   def load(self, keep_running=None):

      # Get a handle to the db. We'll get a fresh handle if updating again.
      # Bug 2688: ERROR: could not serialize access due to concurrent update
      #           This used to happen because we used a serializable trans-
      #           action, which we no longer do. Serializable transactions
      #           are an annoyance; it's better to do assertive locking.
      #           NO: self.update_db = db_glue.new(trans_serializable=True)
      # Just get a new db handle, which sets up the transaction as read
      # committed, so we only see data from whence the db handle is created. So
      # once we call new(), our view of the data won't change. And since we're
      # updating a specific revision to Current(), we'll be a-okay, since the
      # data view doesn't change. But once it's done, we'll want to re-check
      # the latest revision ID and see if we have to update again. Which we do,
      # in load_wrap, by recycling the cursor...
      self.update_db = db_glue.new()
      try:
         self.load_wrap(keep_running=None)
      finally:
         self.update_db.close()
         self.update_db = None

   #
   def load_wrap(self, keep_running=None):
      # If there's a save while we're updating, we'll want to update again.
      update_again = True
      while update_again:
         update_again = False
         # Check the last revision, or just load for the first time.
         load_graph = False
         if isinstance(self.revision, revision.Current):
            rid_latest = revision.Revision.revision_max(self.update_db)
            if self.rid_max != rid_latest:
               g.assurt(rid_latest > self.rid_max)
               load_graph = True
         else:
            g.assurt(isinstance(self.revision, revision.Historic))
            rid_latest = self.revision.rid
            if self.rid_max == 0:
               # Fist time loading.
               load_graph = True
            else:
               # We've already loaded, and since it's Historic, nothing to do.
               g.assurt(rid_latest == self.rid_max)
         if load_graph:
            try:
               qb_curr = self.load_make_qb_new(rid_latest)
               if qb_curr is not None:
                  self.load_really(qb_curr, keep_running)
               else:
                  # qb_curr is only None if there's nothing
                  # to do, which we've already checked for.
                  g.assurt(False)
            except g.Ccp_Shutdown, e:
               raise
            except Exception, e:
               log.error('load: Unexpected error: %s' % (str(e),))
               raise
            # See if the map was saved while we were updating.
            if isinstance(self.revision, revision.Current):
               # Recycle the cursor, so we can see if the revision changed.
               # (This is a trick; rollback the cursor and get a fresh one,
               #  since the old cursor only shows data from when our
               #  transaction began.)
               self.update_db.transaction_rollback()
               # Check the latest revision ID.
               rid_latest = revision.Revision.revision_max(self.update_db)
               # Update again if different.
               if self.rid_max != rid_latest:
                  g.assurt(rid_latest > self.rid_max)
                  update_again = True
         else:
            log.debug('state_update: skipping update.')
            g.assurt(not update_again)

   #
   def load_really(self, qb_curr, keep_running=None):
      '''Load the transport network from the database.'''

      g.check_keep_running(keep_running)

      t0_all = time.time()

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
         log.info('load: mem_usage: beg: %.2f Mb' % (usage_0,))

      # Load ratings.

      # NOTE: To find its usage, search graph.ratings.
      if self.ratings is None:
         g.assurt(isinstance(qb_curr.revision, revision.Historic))
         self.ratings = ratings.Predictor(self)
      # Load all ratings or just update what's changed since we last checked.
      self.ratings.load(qb_curr.db, keep_running=keep_running)

      # Load byways, and attrs and tags.

      try:
         if self.route_daemon.cli_opts.regions:
            qb_curr.filters.filter_by_regions = (
                  self.route_daemon.cli_opts.regions)
      except AttributeError:
         pass

      log.debug('load: calling load_feats_and_attcs...')
      prog_log = Debug_Progress_Logger(log_freq=25000)

      if isinstance(qb_curr.revision, revision.Historic):
         qb_curr.item_mgr.load_feats_and_attcs(qb_curr, byway,
            'search_by_network', self.add_byway_loaded, prog_log,
            heavyweight=False, fetch_size=0, keep_running=keep_running)
      else:
         g.assurt(isinstance(qb_curr.revision, revision.Updated))
         qb_curr.item_mgr.update_feats_and_attcs(qb_curr, byway,
            'search_by_network', self.add_byway_updated, prog_log,
            heavyweight=False, fetch_size=0, keep_running=keep_running)

      # Add transit.

      self.load_make_graph_add_transit(qb_curr)

      # All done loading.

      conf.debug_log_mem_usage(log, usage_0, 'tgraph_base.load_really')

      log.info(
   '/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\')
      log.info('load: complete: for %s in %s'
               % (qb_curr.revision.short_name(),
                  misc.time_format_elapsed(t0_all),))
      log.info(
   '/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\')

      qb_curr.definalize()
      qb_curr = None

   #
   def add_byway_loaded(self, qb, bway, prog_log):
      # For the initial load, we won't fetch deleted or restricted items,
      # but we will while updating.
      if (    (not bway.deleted)
          and (not bway.is_disconnected)
          and (bway.access_level_id <= Access_Level.client)
          and (not bway.tagged.intersection(
               byway.Geofeature_Layer.controlled_access_tags))
          and (bway.geofeature_layer_id
               not in byway.Geofeature_Layer.controlled_access_gfids)
          # FIXME/BUG nnnn: See also geofeature.control_of_access.
          ):
         # MEMORY MANAGEMENT: Maybe only fetch geometry once the route is
         # computed? For now the route finder bloats itself by loading all the
         # geometry for everything into memory.
         # BUG nnnn: Reduce memory usage, leave geometry in the database?
         #           ?? bway.geometry_svg = None
         self.load_make_graph_insert_new(bway)

   #
   def add_byway_updated(self, qb, bway, prog_log):
      # If we've loaded the map at least once, remove the old version of this
      # byway before inserting the new one. For help debugging, we emit a
      # warning on removal if the byway doesn't exist.
      log.verbose('add_byway_updated: bid: %d / eid: %d / %s'
                  % (bway.beg_node_id, bway.fin_node_id, str(bway)))
      g.assurt((bway.version > 1) or (not bway.deleted))
      self.load_make_graph_remove_old(bway)
      self.add_byway_loaded(qb, bway, prog_log)

   # *** Helper functions: make the Item_Query_Builder object.

   #
   def load_make_qb_new(self, rid_latest):

      g.assurt(rid_latest > 0)

      rid_min = self.rid_max
      self.rid_max = rid_latest
      if isinstance(self.revision, revision.Current):
         if rid_min > 0:
            update_only = True
      else:
         g.assurt(isinstance(self.revision, revision.Historic))
         self.rid_max = self.revision.rid

      rev = None
      branch_hier = None
      if rid_min == self.rid_max:
         # The caller should already have checked that we have work to do.
         log.error('load_make_qb_new: rid_min == self.rid_max')
         rev_hist = None
      else:
         # We always need a historic revision, since we always update the attr
         # and tag cache.
         rev_hist = revision.Historic(self.rid_max)
         # If rid_min is already set, do an Update.
         if rid_min > 0:
            log.debug('load_make_qb_new: fr. %d to %d'
                      % (rid_min, self.rid_max,))
            g.assurt(isinstance(self.revision, revision.Current))
            # If we've already loaded byways, we're updating the map,
            # and we want to fetch changed byways, including deleted or
            # restricted-access byways, so we can remove those edges from the
            # transportation graph.
            rev_fetch = revision.Updated(rid_min, self.rid_max)
         else:
            # We're loading the map for the first time.
            rev_fetch = rev_hist

      qb_fetch = None
      if rev_hist is not None:
         branch_hier = branch.Many.branch_hier_build(self.update_db,
                                    self.branch_hier[0][0], rev_hist)
         qb_fetch = Item_Query_Builder(self.update_db, self.username,
                                       branch_hier, rev_fetch)

         # The Item_Manager class will make a table of all changed items by
         # stack_id, and it'll join that against a normal Historic query, so
         # we need to keep the username for the Historic query.
         # NO:
         #     if isinstance(rev_fetch, revision.Updated):
         #        qb_fetch.username = None
         #        qb_fetch.filters.gia_userless = True

         # Because we're using revision.Updated, we need to tell search_get_sql
         # not to worry.
         qb_fetch.request_is_local = True
         qb_fetch.request_is_script = False # True if user running it.
         # This populates the user gids and sets up geometry queries. Neither
         # or which should be necessary.
         Query_Overlord.finalize_query(qb_fetch)
         if rev_fetch != rev_hist:
            qb_hist = Item_Query_Builder(self.update_db, self.username,
                                         branch_hier, rev_hist)
            Query_Overlord.finalize_query(qb_hist)
         else:
            qb_hist = qb_fetch
         # Load the link_value caches for the byways, since we need tags and
         # attributes for the cost function.
         qb_fetch.item_mgr = Item_Manager()
         # NOTE: Whether rev is Historic or Updated, we'll load attrs and tags
         # for a specific revision ID. For Historic, we'll load them for the
         # historic rev ID, and for Updated, we'll load 'em for rid_max.
         # BUG nnnn: With too many tags... we'll want to have a service
         #   running to handle web requests (so they can always be resident)?
         #   bahh...
         qb_fetch.item_mgr.load_cache_attachments(qb_hist)

      return qb_fetch

   # *** Helper functions: add and remove byways from the transportation graph.

   #
   def load_make_graph_insert_new(self, new_byway):
      g.assurt(False) # Abstract

   #
   def load_make_graph_remove_old(self, old_byway):
      g.assurt(False) # Abstract

   #
   def load_make_graph_add_transit(self, qb):
      log.debug('load: transit not enabled for this finder.')
      pass

   n_steps_already_in_lookup = 0

   #
   def step_lookup_append(self, byway_stack_id, rt_step):
      #if byway_stack_id not in self.step_lookup:
      #   self.step_lookup[byway_stack_id] = list()
      self.step_lookup.setdefault(byway_stack_id, list())

      if rt_step not in self.step_lookup[byway_stack_id]:
         self.step_lookup[byway_stack_id].append(rt_step)
      else:
         log.warning('step_lookup_append: already in lookup: stk: %s / %s'
                     % (byway_stack_id, rt_step,))
         Trans_Graph_Base.n_steps_already_in_lookup += 1
         if Trans_Graph_Base.n_steps_already_in_lookup < 3:
            pass

   #
   def byway_has_tags(self, b, tags):
      try:
         byway_stack_id = b.stack_id
      except AttributeError:
         byway_stack_id = int(b)
      try:
         byway_tags = self.step_lookup_get(byway_stack_id).tagged
         has_tags = (len(set(tags).intersection(byway_tags)) > 0)
      except KeyError:
         has_tags = False
      return has_tags

   #
   def step_lookup_get(self, byway_stack_id):
      return self.step_lookup[byway_stack_id][0]

   # ***

# ***


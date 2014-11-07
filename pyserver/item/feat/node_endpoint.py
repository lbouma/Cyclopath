# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# See: https://github.com/Toblerity/Fiona/issues/92
# Avoid a bug on fiona.open: "ValueError: No data available at path '....shp'
#  because something about fiona drivers being unloaded by gdal.
#  The node_endpoint class imports gdal and osr so it can read the DEM file
#  (though maybe fiona can read the DEM file...).
# This is a work-around:
#   import fiona
#   from osgeo import ogr, gdal
try:
   from osgeo import ogr # Comes first, for fiona's sake (generally this
                         # import is not needed, since we don't ref ogr).
   from osgeo import gdal
   from osgeo import osr
   from osgeo.gdalconst import GA_ReadOnly
except ImportError:
   import ogr
   import gdal
   import osr
   from gdalconst import GA_ReadOnly

import os
import struct
import sys

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from gwis.exception.gwis_error import GWIS_Error
from item import geofeature
from item import item_base
from item import item_versioned
from item import permissions_free
from item.feat import node_byway
from item.grac import group
from item.util.item_type import Item_Type
from util_ import geometry
from util_ import misc

__all__ = ['One', 'Many',]

log = g.log.getLogger('node_endpoint')

# ***

class One(permissions_free.One):

   # Base class overrides

   # NOTE: Before NODE_ENDPOINT, the item type/table was BYWAY_NODE.
   item_type_id = Item_Type.NODE_ENDPOINT
   item_type_table = 'node_endpoint'
   item_gwis_abbrev = 'ndpt'
   child_item_types = None

   # 
   item_version_is_branch_specific = True

   # SYNC_ME: See the node_endpoint script, which makes this table.
   local_defns = [
      # py/psql name, deft, send?, pkey?, pytyp, reqv, abbrev, precision
      # MAYBE: move item_versioned columns to node_endpoint table
      # *** Calculated values.
      # The is the node endpoint's x,y geometry. It's stored in the
      # node_endpt_xy table, because an endpoint's geometry never changes.
      # The vertex is stored losslessly (i.e., %.6f) as opposed to node_byway 
      # which stores just, e.g., a decimeter's worth.
      # NOTE: This is really an EWKT, i.e., endpoint_ewkt.
      ('endpoint_wkt',        None,  False,   None,    str,  None),
      # This is the number of byways that use this endpoint.
      ('reference_n',         None,  False,  False,    int,  None),
      # This is a list of stack IDs of the byways that use this endpoint.
      # MAYBE: referencers is not implemented.
      ('referencers',         None,  False,  False,    str,  None),
      # *** User-editable values.
      #
      # BUG nnnn: How do we get this sent to the client?
      # This is the elevations in meters from the Digital Elevation Model.
      ('elevation_m',          0.0,  False,  False,  float, 0, None, 1),
      #
      # A dangle is an endpoint that's all alone.
      ('dangle_okay',         None,  False,  False,   bool,     0),
      # "A duex rues" means "Has two streets." It's an endpoint that connects
      # just two byways. (And we might be able to join the two byways.)
      ('a_duex_rues',         None,  False,  False,   bool,     0),
      ]
   attr_defns = permissions_free.One.attr_defns + local_defns
   psql_defns = permissions_free.One.psql_defns + local_defns
   gwis_defns = item_base.One.attr_defns_reduce_for_gwis(attr_defns)

   __slots__ = [
      ] + [attr_defn[0] for attr_defn in local_defns]

   #
   def __init__(self, qb=None, row=None, req=None, copy_from=None):
      permissions_free.One.__init__(self, qb, row, req, copy_from)

   # 
   def __str__(self):
      return (
            ('%s | reference_n: %s / dangle_okay: %s / a_duex_rues: %s')
         % (permissions_free.One.__str__(self),
            self.reference_n,
            self.dangle_okay,
            self.a_duex_rues,
            ))

   #
   def from_gml(self, qb, elem):
      permissions_free.One.from_gml(self, qb, elem)

   # ***

   # 
   # MAYBE: If we make another class like node_endpoint (which is always 
   #        public so the user doesn't specify GIA records), this fcn. 
   #        should be moved to a new base class.
   def validize(self, qb, is_new_item, dirty_reason, ref_item):
      # At one time, in the beginning, we made Public GIA records for each
      # node_endpoint. But then it was decided that all endpoints are Public.
      g.assurt(self.groups_access is None)
      if is_new_item:
         g.assurt(ref_item is None)
      else:
         g.assurt(id(self) == id(ref_item))
      permissions_free.One.validize(self, qb, is_new_item, dirty_reason, 
                                              ref_item)

   #
   def save_core(self, qb):
      permissions_free.One.save_core(self, qb)
      self.save_insert(qb, One.item_type_table, One.psql_defns)

   #
   def save_update(self, qb):
      # This is used for updating a newly-created node_endpoint that was saved
      # but we want to change it before committing the new revision.
      permissions_free.One.save_update(self, qb)
      # NOTE: Not updating, but clobbering and re-inserting.
      self.save_insert(qb, One.item_type_table, One.psql_defns, 
                       do_update=True)

   #
   def save_related_maybe(self, qb, rid):
      permissions_free.One.save_related_maybe(self, qb, rid)
      # If this is a new node_endpoint, we may have to create the node_endpt_xy
      # entry.
      if self.version == 1:
         g.assurt(self.endpoint_wkt)
         # For the public basemap, a new node_endpoint means a new
         # node_endpt_xy. But for branches, a new node_endpoint does not
         # necessarily mean a new node_endpt_xy: if another branch uses the
         # same node_endpoint, the node_endpt_xy should already exist.
         endpt_sql = (
            """
            SELECT 
               ST_AsText(endpoint_xy) AS existing_xy_wkt
            FROM 
               node_endpt_xy
            WHERE 
               node_stack_id = %d
            """
            % (self.stack_id,))
         rows = qb.db.sql(endpt_sql)
         if not rows:
            # This endpoint truly is new.
            sql_endpt_xy = (
               """
               INSERT INTO node_endpt_xy
                  (node_stack_id, endpoint_xy)
               VALUES
                  (%d, '%s')
               """ % (self.stack_id, 
                      self.endpoint_wkt,))
            qb.db.sql(sql_endpt_xy)
         else:
            # The endpoint is being used or has been previously used by another
            # branch. Just see if the geometry is the same or not.
            g.assurt(len(rows) == 1)
            existing_xy = geometry.wkt_point_to_xy(rows[0]['existing_xy_wkt'],
                                                precision=conf.node_precision)
            proposed_xy = geometry.wkt_point_to_xy(self.endpoint_wkt,
                                                precision=conf.node_precision)
            if existing_xy != proposed_xy:
               log.warning(
                  'save_related_maybe: endpt_xy unequal: theirs: %s / ours: %s'
                  % (existing_xy, proposed_xy,))

   # ***

   n_node_id_matches = {}


# BUG_FALL_2013: BUG nnnn: This probably doesn't decrement on byway delete?
   #
   def save_new_connection(self, qb, for_byway, rid_new, old_node_id=None):

      g.assurt(rid_new > 0)
      g.assurt((old_node_id is None) or (old_node_id > 0))
      g.assurt(self.stack_id > 0)

      # We expect that node_byway is up to date. Though we don't use it to make
      # the reference_n, since we can figure that out easily enough. Enable
      # this if you'd like to double-check the logic.
      # FIXME: Disable this.
      debug_curious = False
      debug_curious = True

      reference_n = self.reference_n

      # The reference count should only not exist for new nodes.
      if self.version == 0:
         # When the stack ID was assigned, fresh was set.
         g.assurt(self.fresh)
         # 
         g.assurt(rid_new != self.valid_start_rid)
         g.assurt(self.valid_start_rid is None)
         # Permissions-free items have no grac records.
         self.groups_access = {}
         self.latest_infer_id = None
         self.latest_infer_username = None
         # A byway this is deleted or reverted should not save new nodes.
         g.assurt((for_byway is None) 
                  or (not (for_byway.deleted or for_byway.reverted)))
         # If we're called from node_cache_maker, the reference count is set,
         # otherwise, this is a commit of a new node, so the count is just one.
         if reference_n is None:
            reference_n = 1
         else:
            # The count is 0 for orphans, but it's usually at least one, or
            # hopefully at least 2.
            g.assurt(reference_n >= 0)
         if debug_curious:
            # Just lie so we don't warn. We believe the caller.
            expected_n = reference_n
         #log.debug('save_new_connection: new node: %s' % (self,))
      else:
         # The node was loaded from the database so its reference count should
         # be nonnegative.
         g.assurt(reference_n >= 0)
         if debug_curious:
            expected_n = node_byway.Many.search_get_stats(
               qb, self.stack_id, internals_ok=False)
         # The node had an existing stack ID, so it's not considered fresh.
         g.assurt(not self.fresh)
         #log.debug('save_new_connection: existing: %s' % (self,))

         # Since we loaded reference_n from the database, only bump the
         # reference count if this byway is coming or going.
         if for_byway is not None:
            if for_byway.fresh:
               reference_n += 1
            if for_byway.deleted:
               reference_n -= 1

      # If we've moved from an old node, decrement its reference_n.
      if old_node_id is not None:
         # We expect that we're saving a new version of an existing byway.
         g.assurt((for_byway is not None) and (for_byway.version > 1))
         # Update the old node endpoint, from whence for_byway is being 
         # moved. Finalizes the old version, decrements reference_n, and 
         # creates a new version.
         old_ndpt = Many.node_endpoint_get(qb, old_node_id, pt_xy=None, 
                                               skip_cache=False)
         #log.debug('save_new_connection: decrementing old: %s' % (old_ndpt,))
         g.assurt(old_ndpt.version > 0)

         # save_new_connection is also called without a for_byway or
         # old_node_id from node_cache_maker.py, so cheat and decrement the
         # reference_n here. The save_new_connection fcn. queries the database
         # for the reference_n, and it complains if the object's value differs.
         old_ndpt.reference_n -= 1
         old_ndpt.save_new_connection(qb, for_byway=None,
                                          rid_new=rid_new, 
                                          old_node_id=None)
         # We shouldn't be called unless the geometry changes, which doesn't
         # technically happen when deleting or reverting (it does
         # conceptually, i.e., the next time you checkout items).
         g.assurt(not (for_byway.deleted or for_byway.reverted))
         # BUG nnnn: Remove node_endpoints that no longer have users?
         #           Search for cmnts re changing from int stack id to GUID.
         #           But note: When splitting a byway, you might temporarily
         #           orphan endpoints, so you'd want to cleanup node IDs as
         #           a separate operation, i.e., after committing.

         # Increment or decrement the count, depending.
         if for_byway is not None:
            reference_n += (
               +1 if (not (for_byway.deleted or for_byway.reverted)) else -1)
            #log.debug('save_new_connection: incremented old: %s' % (self,))
         else:
            # The byway's node endpoint is moving to a new node, so decrement.
            reference_n -= 1
            #log.debug('save_new_connection: decremented old: %s' % (self,))

      g.assurt(self.endpoint_wkt)
      g.assurt(reference_n >= 0)
      g.assurt(not self.referencers) # Not currently used.
      g.assurt(self.elevation_m is not None)
      #? g.assurt(self.dangle_okay is not None)
      #? g.assurt(self.a_duex_rues is not None)

   # FIXME: If you edit the same node_endpoint via two different byways --
   # because node_endpoints piggy-back on byways -- each byway will have a
   # different state of node_endpoint. You may need a node_endpoint cache
   # while working in pyserver. Definitely in flashclient you'll need 
   # to use a cache. But in pyserver, you might just have to know when 
   # node_endpoints referenced by a byway become stale... it almost seems
   # easier to do like the attribute and tag cache and just keep 'em in
   # memory...
   # Here's an older comment:
      #
      # FIXME: Let user edit elevation, etc., of node_endpoint. Also update
      # node_endpoint when byway changing. But two byways connecting to same
      # node would load different node_endpoint objects! So we need to use a
      # node_endpoint cache. If the user is editing the node_endpoint, commit
      # will have prepared the item. If the user is just editing byways, the
      # node_endpoint has not been prepared.  Argh, this seems so tedious.....

      g.assurt(self.branch_id == qb.branch_hier[0][0])

      # MAYBE: debug_curious should always be True, maybe? Or maybe not...
      if debug_curious:
         #log.debug('save_new_connection: saved: %s' % (str(self),))
         #
         # [lb] can't quite remember but this just counts how 'off' our code
         # is... ideally, the difference should be zero, eh.
         stat_count_diff = (expected_n - reference_n)
         misc.dict_count_inc(One.n_node_id_matches, stat_count_diff)
         #
         if reference_n != expected_n:
            if not qb.cp_maint_lock_owner:
               # 2014.09.16: Reducing from warning to just info until fixed.
               # FIXME/BUG nnnn: The node_endpoint.reference_n value is not
               #                 correct.
               #  E.g.,
               #     select * from _nby where nd_stk_id = 1320559
               #        and brn_id = 2500677;
               #  returns four rows, and
               #     select * from (select distinct on (stk_id) stk_id, *
               #        from _by where brn_id = 2500677 and (beg_nd = 1320559
               #        or fin_nd = 1320559) order by stk_id desc) as foo
               #        where d is false and until = 'inf';
               #  also returns four rows, but
               #     select ref_n, start, until from _nde
               #        where stk_id = 1320559 and brn_id = 2500677 limit 1;
               #  says 
               #      ref_n | start | until 
               #     -------+-------+-------
               #          5 | 22626 | inf
               # So, yeah, fix the problem and run node_cache_maker.py again.
               # But this is low priority: reference_n is destined for use to
               # help find dangles and fix map problems, but it's only so far
               # used as output in the Shapefiles. But the new p3 route planner
               # instead uses networkx to find roads that are not connected to
               # the main road network. The reference_n value only helps with
               # dangles and cannot identify disconnected sub-trees of byways.
               # tl;dr The node_endpoint.reference_n value is not always
               # maintained properly (possibly due to deleted byways, such as
               # when splitting byways) but it's doesn't really matter.
               # One solution: after committing the new revision, get a new
               # db cursor and, using a list of byways just saved, recompute
               # reference_n and maybe check the node_byway rows, too.
               #
               #log.warning(
               log.info(
                  'unexpected ref_n: nd: %d / by: %s / ref_n: %d / calcd: %d'
                  % (self.stack_id,
                     'n/a' if for_byway is None else for_byway.stack_id,
                     reference_n,
                     expected_n,))
            # else, this is a bulk operation, so not to worry...? =)
            # 2012.07.30: The old node_cache_maker calculated reference_n
            # incorrectly; the one we calculated is the one to believe.
            reference_n = expected_n
         #else:
         #   log.debug(
         #      'peachy ref_n: stack_id: %9s / ref_n: %d / expected_n: %d' 
         #      % ('      n/a' if for_byway is None else for_byway.stack_id,
         #         reference_n, expected_n,))

      self.reference_n = reference_n

      if rid_new != self.valid_start_rid:
         # We're creating a new version (and maybe finalizing the old version,
         # or we're creating a new node_endpoint).
         if self.valid_start_rid is None:
            g.assurt(self.system_id is None)
            g.assurt(self.valid_until_rid is None)
         else:
            g.assurt(self.system_id > 0) # We loaded it from the db.
            # Finalize the last version's revisions.
            item_versioned.One.finalize_last_version_at_revision(
                        self, qb, rid_new, same_version=False)
            self.system_id = None
            g.assurt(self.valid_start_rid < rid_new)
            g.assurt(self.valid_until_rid == conf.rid_inf)
         # Since we're not calling version_finalize_and_increment().
         self.valid_start_rid = rid_new
         self.valid_until_rid = conf.rid_inf
         self.version += 1
         self.acl_grouping = 1
         # We haven't called save() yet, and this class doesn't use validize().
         g.assurt(not self.is_dirty())
         self.dirty_reason_add(item_base.One.dirty_reason_item_auto)
         # Since we're not using validize().
         g.assurt(not self.valid)
         self.valid = True
         #
         self.save(qb, rid_new)
      else:
         g.assurt(self.system_id > 0)
         # This node_endpoint was just saved during the making of a
         # revision, so just update what we haven't committed yet.
         g.assurt(self.valid_start_rid == rid_new)
         g.assurt(self.valid_until_rid == conf.rid_inf)
         #
         self.save_update(qb)

   # ***

class Many(permissions_free.Many):

   one_class = One

   __slots__ = ()

   # *** SQL clauseses

   sql_clauses_cols_all = permissions_free.Many.sql_clauses_cols_all.clone()

   # NOTE: Using ST_AsEWKT instead of ST_AsText, e.g.,
   #         ST_AsText: 'POINT(473657.6 4977266)'
   #         ST_AsEWKT: 'SRID=26915;POINT(473657.6 4977266)'
   #       So SRID is included (since that's what geometry.py's
   #       xy_to_ewkt_point_restrict does).
   sql_clauses_cols_all.inner.select += (
      """
         , item.reference_n
         , item.referencers
         , item.dangle_okay
         , item.a_duex_rues
         , item.elevation_m
         , ST_AsEWKT(ptxy.endpoint_xy) AS endpoint_wkt
      """)

   sql_clauses_cols_all.inner.from_table = (
      """
      FROM
         node_endpoint AS item
      JOIN
         node_endpt_xy AS ptxy
         ON (ptxy.node_stack_id = item.stack_id)
      """)

   # *** Constructor

   def __init__(self):
      permissions_free.Many.__init__(self)

   # *** Finding Node Endpoints

   #
   @staticmethod
   def node_endpoints_get(qb, bway,
                          preferred_beg_node_id,
                          preferred_fin_node_id,
                          skip_cache=False):
      g.assurt((not bway.beg_node_id) and (not bway.fin_node_id))
      (beg_ndpt, fin_ndpt,) = (None, None,)
      (beg_pt, fin_pt,) = Many.node_endpts_get(bway)
      if (beg_pt is not None) and (fin_pt is not None):
         # Either node ID might be None if we need to make a new endpoint.
         log.verbose1('node_endpoints_get: looking for byway nodes: %s and %s'
                      % (bway.beg_node_id, bway.fin_node_id,))
         beg_ndpt = Many.node_endpoint_get(qb, bway.beg_node_id,
                        beg_pt, preferred_beg_node_id, skip_cache)
         fin_ndpt = Many.node_endpoint_get(qb, bway.fin_node_id,
                        fin_pt, preferred_fin_node_id, skip_cache)
      else:
         g.assurt((beg_pt is None) and (fin_pt is None))
      return (beg_ndpt, fin_ndpt,)

   # 
   @staticmethod
   def node_endpts_get(bway):
      if bway.geometry_wkt:
         locs = geometry.wkt_line_to_xy(bway.geometry_wkt)
      elif bway.geometry_svg:
         # EXPLAIN: I [lb] always forget: Who uses SVG?
         locs = geometry.svg_line_to_xy(bway.geometry_svg)
      elif bway.geometry:
         # This is for an item loaded from the database. E.g., a split-from
         # byway being copied to a branch so it can be marked deleted: we just 
         # use the raw geometry of the item we loaded from the db.
         log.warning('node_endpts_get: use not qb.filters.skip_geometry_wkt')
         g.assurt(False)
      else:
         # Programmer error. This should never happen.
         g.assurt(False)
         locs = (None, None,)
         log.error('elevation_update: no link segment?: %s' % (bway,))
      return (locs[0], locs[-1],)

   #
   @staticmethod
   def node_endpoint_get(qb, stack_id,
                             pt_xy,
                             preferred_node_id=None,
                             skip_cache=False):

      log.verbose1('node_endpoint_get: looking for: %s' % (stack_id,))

      node_endpt = None

      # The stack_id may or may not be set, but it should never be a client id.
      # If it's nonzero, the node exists in the database. If it's not set, the 
      # byway doesn't know if the pt_xy has a node yet or not.
      g.assurt((not stack_id) or (stack_id > 0))
      g.assurt(stack_id or pt_xy)

      if (not preferred_node_id) and stack_id:
         preferred_node_id = stack_id

      # 2012.07.10: Thoughts re cache: Each byway has its own reference to a 
      #             node in memory, so right now we need the cache like we need
      #             one for tags and attributes. 
      #             FIXME: In byway.py, (see call to save_new_connection), 
      #                    can we hydrate nodes on demand? probably...
      #             FIXME: Is memory usage a problem? For either routed or 
      #                    the connectivity scripts, or import?
      if stack_id and (not skip_cache):
         try:
            g.assurt(qb.item_mgr is not None)
            node_endpt = qb.item_mgr.cache_node_endpoints[stack_id]
         except KeyError:
            pass

      if stack_id and (node_endpt is None):
         node_endpoints = Many()
         node_endpoints.search_by_stack_id(stack_id, qb)
         if len(node_endpoints) == 1:
            node_endpt = node_endpoints[0]
            log.verbose1('node_endpt_get: found by ID: %s' % (node_endpt,))
         else:
            g.assurt(len(node_endpoints) == 0)
            # This never happens, I assume.
            g.assurt(False)

      if node_endpt is None:

# BUG nnnn/FIXME_2013_06_11:
# FIXME: What about node_endpt_xy???????????
#        Why bother w/ node_byway????
# search node_endpt_xy and use same stack_id but make node_endpoint version=1
# or maybe client will find parent branch node and use its stack ID...
# still, we should make sure we're not making a new node_endpt_xy or
# creating a new stack ID for a node whose xy is already in the system!
# also double check that node_endpt_xy is otherwise maintained correctly.

         node_byways = node_byway.Many()
         # This search is exact, down to conf.node_tolerance. And we don't care
         # if there are multiple byways but they don't all use the same
         # node_endpoint: that's for the audit script to complain about.
         g.assurt(pt_xy is not None)
         node_byways.search_by_endpoint_xy(
            qb, pt_xy, internals_ok=False, limit_one=False)

         if node_byways:
            if len(node_byways) == 1:
               stack_id = node_byways[0].node_stack_id
            else:
               ref_counter = {}
               for node_bway in node_byways:
                  stack_id = node_bway.node_stack_id
                  misc.dict_count_inc(ref_counter, stack_id)
                  if stack_id == preferred_node_id:
                     break
               if ((stack_id != preferred_node_id)
                   and (len(ref_counter) > 1)):
                  # Use the node with the most byways.
                  largest = -1
                  for sid, count in ref_counter.iteritems():
                     if count > largest:
                        largest = count
                        stack_id = sid
                  log.debug('%s sid: %d (ref_n: %d of %d) / e.g. nds[0]: %s'
                     % ('Found two+ node endpts: not confident:',
                        stack_id, largest, len(node_byways), node_byways[0],))
            g.assurt(stack_id > 0)
            node_endpoints = Many()
            node_endpoints.search_by_stack_id(stack_id, qb)
            if len(node_endpoints) == 1:
               node_endpt = node_endpoints[0]
               log.verbose1('node_endpt_get: found by xy: %s' % (node_endpt,))
            else:
# FIXME_2013_06_11:
# FIXME: 2013.06.14: What about a leafy branch: won't search_by_endpoint_xy
#                    find the stack_id and then
#                    node_endpoints.search_by_stack_id fails because != brid ?
#   though [lb] notes that node_byway searches by branch_id, as does
#   node_endpoint... but maybe that's the best way...
#
               g.assurt(len(node_endpoints) == 0)
               log.warning('node_endpt_get: missing stack ID: %d' 
                           % (stack_id,))

      if node_endpt is None:

         # NOTE: ST_GeomFromEWKT is implicit on INSERT.
         # E.g., "SRID=%s;POINT(%.6f %.6f)"
         endpoint_wkt = geometry.xy_to_ewkt_point_restrict(pt_xy)

         elevation_m = Many.elevation_get_for_pt(pt_xy)

         # We want a permanent ID right away, since we're being managed by a
         # new byway (so there's no need for a client ID, but we still get one
         # for a moment just to be proper, i.e., instead of calling item_mgr's
         # seq_id_next_stack_id directly).
         g.assurt(not stack_id)
         client_id = qb.item_mgr.get_next_client_id()
         permanent_id = qb.item_mgr.stack_id_translate(qb, client_id)
         stack_id = permanent_id

         # I.e., node_endpoint.One(). See also node_cache_maker.
         node_endpt = One(
            qb=qb, 
            row={
               # From item_versioned
               'system_id'    : None, # assigned later,
               'branch_id'    : qb.branch_hier[0][0],
               'stack_id'     : stack_id,
               'version'      : 0,
               # From node_endpoint
               # SYNC_ME: See node_cache_maker, which makes this table.
               # Calculated values.
               'endpoint_wkt' : endpoint_wkt,
               'reference_n'  : 1,
               # MAYBE: 'referencers'  : '%d' % (stack_id,),
               # User-editable values.
               'elevation_m'  : elevation_m,
               'dangle_okay'  : None,
               'a_duex_rues'  : None,
               })

         # Fake that we're fresh (the base class only sets it if stack_id less
         # than 0, but we skipped that step and made our own permanent ID).
         node_endpt.fresh = True

         # 2013.10.07: Does this make sense?
         qb.item_mgr.item_cache_add(node_endpt, client_id)

         log.verbose1('node_endpoint_get: created: %s' % (str(node_endpt),))

         # NOTE: It's up to the caller to save this new node_endpoint.

      if not skip_cache:
         try:
            existing = qb.item_mgr.cache_node_endpoints[stack_id]
            g.assurt(existing == node_endpt)
            # Don't save the new node; this happens on delete when
            # we're double-checking that an x,y matches the expected
            # endpoint.
            node_endpt = existing
         except KeyError:
            qb.item_mgr.cache_node_endpoints[stack_id] = node_endpt

      g.assurt(node_endpt.endpoint_wkt)
      g.assurt(node_endpt.reference_n >= 0)
      g.assurt(not node_endpt.referencers) # Not currently used.
      g.assurt(node_endpt.elevation_m is not None)

      return node_endpt

   # *** Table management

   indexed_cols = ('branch_id',
                   'stack_id',
                   'reference_n',
                   #'referencers',
                   #'elevation_m',
                   #'dangle_okay',
                   #'a_duex_rues',
                   )

   #
   @staticmethod
   def drop_indices(db): # ..................//.mind the gap.//..........
      # NOTE: If we call ALTER TABLE ... DROP CONSTRAINT ourselves and the
      # constraint does not exist, the db handle becomes invalid (and you get
      # the "psycopg2.InternalError: current transaction is aborted, commands 
      # ignored until end of transaction block" error if you try to use it).
      # I'm not sure how to test if a constraint exists, so that leaves two
      # options: create a new db handle here, or use the convenience function
      # we wrote in db_load_add_constraints.sql.
      db.sql(
         """
         SELECT 
            cp_constraint_drop_safe('node_endpoint', 'enforce_valid_geometry')
         """)
      db.sql("DROP INDEX IF EXISTS node_endpoint_endpoint_xy")
      # From the route table.
      # MAYBE: See comments in make_indices.
      #db.sql("SELECT cp_constraint_drop_safe('route', 'route_beg_nid_fkey')")
      #db.sql("SELECT cp_constraint_drop_safe('route', 'route_fin_nid_fkey')")
      # FIXME: Missing any other tables?

      for col_name in Many.indexed_cols:
         # E.g., "DROP INDEX IF EXISTS node_endpoint_branch_id"
         db.sql("DROP INDEX IF EXISTS node_endpoint_%s" % (col_name,))

      # MAYBE: Move to its own file, i.e., item/feat/node_endpt_xy.py ?
      db.sql(
         """
         SELECT 
            cp_constraint_drop_safe('node_endpt_xy', 'enforce_valid_geometry')
         """)
      db.sql("DROP INDEX IF EXISTS node_endpt_xy_endpoint_xy")

   #
   @staticmethod
   def make_indices(db):
      # Drop the indices, lest you have to catch: psycopg2.ProgrammingError:
      # constraint "enforce_valid_geometry" for relation "node_endpoint"
      # already exists.
      Many.drop_indices(db)
      # To the route table.
      # MAYBE: The node ID in route is a stack ID, but node_endpoint is keyed
      # by the system ID. So we don't need (or can't use?) a foreign key
      # constraint.
      #db.sql(
      #   """
      #   ALTER TABLE route 
      #      ADD CONSTRAINT route_beg_nid_fkey
      #         FOREIGN KEY (beg_nid) REFERENCES node_endpoint (stack_id) 
      #            DEFERRABLE
      #   """)
      #db.sql(
      #   """
      #   ALTER TABLE route 
      #      ADD CONSTRAINT route_fin_nid_fkey
      #         FOREIGN KEY (fin_nid) REFERENCES node_endpoint (stack_id) 
      #            DEFERRABLE
      #   """)

      for col_name in Many.indexed_cols:
         # E.g., 
         #  "CREATE INDEX node_endpoint_branch_id ON node_endpoint(branch_id)"
         db.sql("CREATE INDEX node_endpoint_%s ON node_endpoint(%s)"
                % (col_name, col_name,))

      # MAYBE: Move to its own file, i.e., item/feat/node_endpt_xy.py ?
      sql_add_constraint = (
         """
         ALTER TABLE node_endpt_xy 
            ADD CONSTRAINT enforce_valid_geometry
               CHECK (IsValid(endpoint_xy))
         """)
      db.sql(sql_add_constraint)
      #
      # This is the PostGIS 1.x way: USING GIST (... GIST_GEOMETRY_OPS)
      sql_add_index = (
         """
         CREATE INDEX node_endpt_xy_endpoint_xy ON node_endpt_xy 
            USING GIST (endpoint_xy)
         """)
      db.sql(sql_add_index)

   # *** Find Nearby Nodes

   # Says PostGIS, 
   #    Prior to 1.3, ST_Expand was commonly used in conjunction with && and
   #    ST_Distance to achieve the same effect and in pre-1.3.4 this function
   #    was basically short-hand for that construct. From 1.3.4, ST_DWithin
   #    uses a more short-circuit distance function which should make it more
   #    efficient than prior versions for larger buffer regions.
   # 2012.01.11: We let the programmer choose which method to always use; 
   #             see dbg_find_nbor.

   #
   @staticmethod
   def find_nearby(qb, xy_pt, radius, dbg_find_nbor='st_dwithin'):
      if dbg_find_nbor == 'st_expand':
         node_ids, nid_details = Many.find_nearby_v1(qb, xy_pt, radius)
      else:
         g.assurt(dbg_find_nbor == 'st_dwithin')
         node_ids, nid_details = Many.find_nearby_v2(qb, xy_pt, radius)
      return node_ids, nid_details

   #
   @staticmethod
   def find_nearby_v1(qb, xy_pt, radius):

      # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
      point_sql = geometry.xy_to_raw_point_lossless(xy_pt)

      radius = ('%%.%df' % conf.geom_precision) % radius

      results = qb.db.sql(
         """
         SELECT 
              ndpt.stack_id
            , ndpt.reference_n
            , ptxy.endpoint_xy
            , ST_Distance(ptxy.endpoint_xy, %s) AS pt_dist
         FROM 
            node_endpoint AS ndpt
         JOIN 
            item_versioned AS neiv
            ON (neiv.system_id = ndpt.system_id)
         JOIN
            node_endpt_xy AS ptxy
            ON (ptxy.node_stack_id = ndpt.stack_id)
         WHERE
            ndpt.branch_id = %d
            AND neiv.valid_until_rid = %d
            AND ptxy.endpoint_xy && ST_EXPAND(%s, %s)
         ORDER BY
            ST_Distance(ptxy.endpoint_xy, %s) ASC
         """ % (point_sql,
                qb.branch_hier[0][0],
                conf.rid_inf,
                point_sql,
                radius,
                point_sql,))
      # BUG nnnn: "Groveland Rec Center" has this problem: very big 
      # intersection, but the six byways that connect use two different 
      # node IDs (so there's logically two intersections where there should
      # just be one). Which means the SQL above returns more than one row.
      node_ids = []
      nid_details = {}
      for row in results:
         log.verbose(
            'find_nearby: xy_pt: %s / rad: %s | nid: %d / xy: %s / dist: %f'
            % (xy_pt, radius, row['stack_id'], row['endpoint_xy'], 
               row['pt_dist']))
         node_ids.append(row['stack_id'])
         g.assurt(row['stack_id'] not in nid_details)
         nid_details[row['stack_id']] = (row['endpoint_xy'], row['pt_dist'],)
      return node_ids, nid_details

# MAYBE: Assign confidence to what's found nearby?

   #
   @staticmethod
   def find_nearby_v2(qb, xy_pt, radius):

      # "[D]o an ST_DWithin search to utilize indexes to limit [the] search 
      #  list that the non-indexable ST_Distance needs to process."

      # E.g., "ST_GeomFromEWKT('SRID=%d;POINT(%.6f %.6f)')"
      point_sql = geometry.xy_to_raw_point_lossless(xy_pt)

      radius = ('%%.%df' % conf.geom_precision) % radius

      # The node_endpoint table doesn't do branch_hier. It's a
      # flattened-branch, not a stacked-branch, table.

      # MAYBE: Use a revision? node_endpoint is wiki'ed nowadays...
      #        but this is just used for route-finding at Current
      #        (route_analysis does not need this for Historic route 
      #        finding).

      results = qb.db.sql(
         """
         SELECT 
              stack_id
            , reference_n
            , endpoint_xy
            , pt_dist
         FROM (
            SELECT 
                 ndpt.stack_id
               , ndpt.reference_n
               , ptxy.endpoint_xy
               , ST_Distance(ptxy.endpoint_xy, %s) AS pt_dist
            FROM 
               node_endpoint AS ndpt
            JOIN 
               item_versioned AS neiv
               ON (neiv.system_id = ndpt.system_id)
            JOIN
               node_endpt_xy AS ptxy
               ON (ptxy.node_stack_id = ndpt.stack_id)
            WHERE
               ndpt.branch_id = %d
               AND neiv.valid_until_rid = %d
               AND ST_DWithin(ptxy.endpoint_xy, %s, %s)
         ) AS foo_nde_1
         ORDER BY
            pt_dist ASC
         """ % (point_sql,
                qb.branch_hier[0][0],
                conf.rid_inf,
                point_sql,
                radius,))

      # BUG nnnn: "Groveland Rec Center" has this problem: very big 
      # intersection, but the six byways that connect use two different 
      # node IDs (so there's logically two intersections where there should
      # just be one). Which means the SQL above returns more than one row.

      node_ids = []
      nid_details = {}
      for row in results:
         log.verbose(
               'find_nearby: xy_pt: %s / rad: %s | nid: %d / xy: %s / dist: %f'
            % (xy_pt, radius, row['stack_id'], row['endpoint_xy'], 
               row['pt_dist']))
         node_ids.append(row['stack_id'])
         g.assurt(row['stack_id'] not in nid_details)
         nid_details[row['stack_id']] = (row['endpoint_xy'], row['pt_dist'],)

      return node_ids, nid_details

   # *** Global DEM handle.

   # Since we're using a C module, elevdata must be global, as raster is simply
   # a pointer to elevdata. If elevdata is not global, it can cause a segfault.
   # FIXME: [lb] wants to not always load DEM for all pyserver calls, since
   # they don't use them. So is class-scope okay?

   elevdata = None
   raster = None
   xform_coord = None
   xform_pixel = None

   #
   @staticmethod
   def node_endpoints_cache_ensure():
      # Set up the elevation data file for the elevation module.
      if (Many.elevdata is None) and (conf.elevation_tiff):
         log.debug('Opening DEM...')
         Many.elevdata = gdal.Open(conf.elevation_tiff, GA_ReadOnly)
         if Many.elevdata is None:
            log.error('Error reading elevation source file: %s.'
                      % (conf.elevation_tiff,))
            raise GWIS_Error('Error reading elevation source file.')
         log.debug(' opened DEM.')
         proj = Many.elevdata.GetProjection()
         dest_srs = geometry.spatial_reference_from_wkt(proj)
         src_srs = geometry.spatial_reference_from_srid(conf.default_srid)
         Many.xform_coord = osr.CoordinateTransformation(src_srs, dest_srs)
         Many.xform_pixel = geometry.Geo_Transform(
                        Many.elevdata.GetGeoTransform())
         Many.raster = Many.elevdata.GetRasterBand(1)    
         # NOTE: The dest_srs might be lon/lat or it might be bbox_x/_y.
         #       I.e., we'll transform points to, e.g., UTM 15, or to latlon.
         #  Many.raster.ComputeRasterMinMax(1): (646.0, 2011.0)

   # ***

   feet_to_meters = 0.3048

   #
   @staticmethod
   def elevation_get_for_pt(pt_xy):
      Many.node_endpoints_cache_ensure()
      if Many.raster is not None:
         elevation_m = Many.elevation_get_for_pt_(pt_xy)
      else:
         elevation_m = conf.elevation_mean
      return elevation_m

   #
   @staticmethod
   def elevation_get_for_pt_(pt_xy):
      '''Take a point in the default srs and return its elevation in meters.'''
      pt_x, pt_y = float(pt_xy[0]), float(pt_xy[1])
      (lon_or_bbox_x, lat_or_bbox_y, pt_z
         ) = Many.xform_coord.TransformPoint(pt_x, pt_y)
      (pixel_x, pixel_y
         ) = Many.xform_pixel.transform_point(lon_or_bbox_x, lat_or_bbox_y)
      try:
         # Check the size of the raster. If the lat/lon or bbox_x/_y is
         # elsewhere (e.g., Wisconsin), OGR prints to stderr:
         #   ERROR 5: Access window out of range in RasterIO(). Requested
         #            (15675,6926) of size 1x1 on raster of 15638x11844.
         if ((pixel_x < Many.elevdata.RasterXSize) 
             and (pixel_y < Many.elevdata.RasterYSize)):
            elevation_struct = Many.raster.ReadRaster(pixel_x, pixel_y, 1, 1)
            try:
               if len(elevation_struct) == 4:
                  # A four-byte number.
                  elevation_m = struct.unpack('f'*1, elevation_struct)[0]
                  g.assurt(isinstance(elevation_m, float))
               elif len(elevation_struct) == 2:
                  # A two-byte number... no wonder the state DEM
                  # is only 100 MB larger than the metro DEM.
                  elevation_m = struct.unpack('h', elevation_struct)[0]
                  g.assurt(isinstance(elevation_m, int))
                  elevation_m = float(elevation_m)
               else:
                  log.error('Unexpected elevation packed length: %s (%s)'
                            % (elevation_struct, len(elevation_struct),))
                  g.assurt(False)
               if conf.elevation_units == 'feet':
                  elevation_m *= Many.feet_to_meters
            except struct.error, e:
               g.assurt(False) # Should be caught by RasterX/YSize check.
               pass
         else:
            # BUG nnnn: Better DEM coverage (maybe multiple dems, with a bbox
            # lookup to figure out which one to use?).
            # 2012.02.10: There are dozens of these pts in Ccp. I [lb] sampled 
            #             two of them and they were both River Falls, 'sconi.
            # MAYBE: Using %s on tuple means lots of precision, e.g., 
            #        530160.95999999996. Make a wrapper for printing tuple-pts.
            log.warning(
               'nd_elev_ins: outside DEM: ptxy %s,%s / bbox %s,%s / pxel %s,%s'
               % (pt_x, pt_y, lon_or_bbox_x, lat_or_bbox_y, pixel_x, pixel_y,))
            # BUG nnnn: The profile in the client is going to be inaccurate.
            elevation_m = conf.elevation_mean
      except TypeError:
         if elevation_m is None:
            # This is probably outside MN, right?
            log.warning('node_elevation_insert: no elev for pt: %s' % (pt_xy,))
            # BUG nnnn: The profile in the client is going to be inaccurate.
            elevation_m = conf.elevation_mean
      g.assurt(elevation_m is not None)
      elevation_m = round(float(elevation_m), conf.elev_precision + 1)
      return elevation_m

   # ***

# ***


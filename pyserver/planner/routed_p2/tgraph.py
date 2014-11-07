# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

'''This file is the main script for building a multimodal graph. '''

import math
import sys
import time
import traceback

from pkg_resources import require
require("Graphserver>=1.0.0")
from graphserver.compiler.gdb_import_gtfs import GTFSGraphCompiler
import graphserver.core
from graphserver.core import EdgePayload
from graphserver.core import Link
from graphserver.core import VertexNotFoundError
from graphserver.ext.gtfs.gtfsdb import GTFSDatabase

import conf
import g

from gwis.exception.gwis_error import GWIS_Error
from item.feat import byway
from item.feat import route
from item.util import ratings
from item.util.item_query_builder import Item_Query_Builder
from item.util.revision import Revision
from planner.tgraph_base import Trans_Graph_Base
from planner.routed_p2.payload_byway import Payload_Byway
from util_ import db_glue
from util_ import geometry
from util_ import mem_usage
from util_ import misc

__all__ = ['Trans_Graph']

log = g.log.getLogger('tgraph_p2')

# *** Route Finder Personality (routed_pers) #2 -- Multimodal

class Trans_Graph(Trans_Graph_Base):

   __slots__ = (
      'gserver',
      'cache_reg',
      )

   # *** Constructor

   #
   def __init__(self, route_daemon,
                      username=None, branch_hier=None, revision_=None):
      Trans_Graph_Base.__init__(self, route_daemon,
                                      username, branch_hier, revision_)
      self.gserver = graphserver.core.Graph()
      self.cache_reg = None

   # *** Memory management

   #
   def destroy(self):
      try:
         self.gserver.destroy()
         self.gserver = None
      except AttributeError:
         pass
      Trans_Graph_Base.destroy(self)

   # *** Load (or update) the graph.

   #
   def load(self, keep_running=None):
      '''Load the transport network from the database.'''

      # FIXME: Implement: if updating, detect if we should reload graphserver
      # (start new routed) or if we can just update the one we got.
      # For first implementation: just start new routed, and have it set itself
      # up in routed_ports when its ready.
      # FIXME: wow, w/ this & gtfsdb script, p2 finder will finally be robust!

      #if not self.loaded:

      Trans_Graph_Base.load(self, keep_running)

      #else:

      #   start a new routed if one is not already starting
      #     (check routed ports -- there should be at most
      #      two claimed, one ready and one not).

   #
   def load_make_graph_insert_new(self, new_byway):

      g.assurt(new_byway is not None)

      # Get the points' xs and ys so we can determine direction.
      # (C.f. planner.routed_p1.tgraph.load_make_graph_insert_new)
      point_beg = geometry.wkt_point_to_xy(new_byway.beg_point)
      point_beg2 = geometry.wkt_point_to_xy(new_byway.beg2_point)
      point_fin = geometry.wkt_point_to_xy(new_byway.fin_point)
      point_fin2 = geometry.wkt_point_to_xy(new_byway.fin2_point)

      beg_id = str(new_byway.beg_node_id)
      fin_id = str(new_byway.fin_node_id)
# FIXME: Byways share vertices, so make sure add_vertex is add_vertex_maybe?
#        Or maybe the graph handles that?
      self.gserver.add_vertex(beg_id)
      self.gserver.add_vertex(fin_id)
# FIXME: Use remove_vertex when byway is deleted
#        or maybe not: there's no remove_edge -- or is remove_edge implied?

# FIXME: Guarantee that node IDs are unique to revision and branch? Are they
# already (at least, are node IDs unique across revision changes)?

      # Cache forward and backward edges.
      #
      # MAGIC NUMBER: 1 and -1 indicate the direction of the one way.
      if (new_byway.one_way != -1):
         # Cache forward edge
         pload = Payload_Byway(new_byway, True)
         pload.dir_entry = geometry.v_dir(point_beg, point_beg2)
         pload.dir_exit = geometry.v_dir(point_fin2, point_fin)
         self.gserver.add_edge(beg_id, fin_id, pload)
         self.step_lookup_append(new_byway.stack_id, pload)
      #
      if (new_byway.one_way != 1):
         # Cache backward edge
         pload = Payload_Byway(new_byway, False)
         pload.dir_entry = geometry.v_dir(point_fin, point_fin2)
         pload.dir_exit = geometry.v_dir(point_beg2, point_beg)
         self.gserver.add_edge(fin_id, beg_id, pload)
         self.step_lookup_append(new_byway.stack_id, pload)

   #
   def step_lookup_get(self, byway_stack_id):
      # FIXME: This is why p2 is so memory-hungry: We store the complete byway.
      # I wonder if we could install the route_step, or derive from it?
      return self.step_lookup[byway_stack_id][0].byway

   #
   def load_make_graph_remove_old(self, old_byway):
# BUG 2295: routed_p2 does not update on map save
# FIXME: Maybe just start a new instance of the server and then switch
# routed_ports when it's available? weird...
      # self.gserver.????? remove_edge ??
      # FIXME: need (Cyclopath's) node_id and (transit's) stop_id
      pass

   #
   def load_make_graph_add_transit(self, qb):
      # Not calling base class fcn.

# FIXME: What happens here on update? We reload all, don't we?
# FIXME: For p2, only do this on load, not on update.
# BUG nnnn: For p2, start new instance of route finder and then
#           just change routed_ports to use that one, then kill
#           the existing one.

      time_0 = time.time()
      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
      log.debug('load: adding transit...')

      loaded = False

      # Load the transit network, maybe (if we have data for it).
      if conf.transitdb_filename:
         self.cache_reg = self.links_get_cache_reg(qb)
         log.debug('load: loading the transit database')
         db_transit = GTFSDatabase(conf.transitdb_filename)
         log.debug('load: making the transit graph')
         self.load_transit(qb, db_transit)
         # Link the two graphs
         log.debug('load: linking the two graphs')
         self.link_graphs(qb, db_transit)
         loaded = True
      # else, using Graphserver, but no public transit data to load.

      if loaded:
         log.info('load: added transit: in %s'
                  % (misc.time_format_elapsed(time_0),))
      else:
         # MAYBE: Let devs test without loading transit.
         raise GWIS_Error(
            'Unable to load route finder: no transit info found.')

      conf.debug_log_mem_usage(log, usage_0, 'tgraph.load / transit')

      return loaded

   # *** Helper functions: load the transit data and link with Cyclopath data.

   # Similar to: scripts.daily.gtfsdb_build_cache.cache_edges()
   def load_transit(self, qb, db_transit):

      # load the transit info
      agency_id = None
      reporter = None # sys.stdout # FIXME: Can we pass in log.debug somehow?
                                   #    I think we just need to support write()
      maxtrips = None
      g.assurt(self.gserver is not None)

      # C.f. graphserver/pygs/build/lib/graphserver/compiler.py
      #         ::graph_load_gtfsdb
      log.debug('load_transit: loading compiler')
      compiler = GTFSGraphCompiler(db_transit, conf.transitdb_agency_name,
                                   agency_id, reporter)

      nedges = 0
      if self.cache_reg is not None:
         from_and_where = self.links_cache_from_and_where(
                                       'gtfsdb_cache_register', qb)
         nedges = qb.db.sql("SELECT transit_nedges AS nedges %s"
                            % (from_and_where))[0]['nedges']
      if nedges > 0:
         nedges_str = str(nedges)
      else:
         nedges_str = 'unknown'

      time_0 = time.time()
      log.debug('load_transit: loading vertices and edges')
     #for (fromv_label, tov_label, edge) in compiler.gtfsdb_to_edges(maxtrips):
      for i, (fromv_label, tov_label, edge) in enumerate(
                                          compiler.gtfsdb_to_edges(maxtrips)):
         if (i % 25000) == 0:
            log.debug('load_transit: progress: on edge # %d of %s...'
                      % (i, nedges_str,))
            #log.debug(' >> fromv_label: %s / tov_label: %s / edge: %s'
            #          % (fromv_label, tov_label, edge,))
            # NOTE: fromv_label is unicode, tov_label str, and edge
            #       graphserver.core.TripBoard/TripAlight/Etc.
            # FIXME: Why is fromv_label unicode?
         fromv_label = str(fromv_label)
         tov_label = str(tov_label)
         g.assurt(isinstance(edge, EdgePayload))
         self.gserver.add_vertex(fromv_label)
         self.gserver.add_vertex(tov_label)
         self.gserver.add_edge(fromv_label, tov_label, edge)
      # 2011.08.08: 49 seconds
      # 2011.08.09: 36 seconds with less log.debug
      log.debug('load_transit: loaded %d edges in %s'
                % (i + 1,
                   misc.time_format_elapsed(time_0),))
      # 2013.12.05: This is firing. It looks like the count of transit_nedges
      # from gtfsdb_cache_register is less than what we've loaded...
      #g.assurt((nedges == 0) or (nedges == (i + 1)))
      if not ((nedges == 0) or (nedges == (i + 1))):
         log.error('load_transit: nedges: %d / i: %d' % (nedges, i,))

   # FIXME: [cd] observed: for some reason, the following stops are in the
   #        transit database but have not been added to the graph itself:
   #           sta-52709
   #           sta-53427
   #           sta-53440
   # 2011.08.09: I [lb] see the following when loading the cache table:
   #        link_graphs: no vertex?!: node_id: 1245193 / stop_id: sta-52709
   #        link_graphs: no vertex?!: node_id: 1248919 / stop_id: sta-53427
   #        link_graphs: no vertex?!: node_id: 1240707 / stop_id: sta-53440
   #        link_graphs: no vertex?!: node_id: 1273775 / stop_id: sta-53598
   # FIXME: So self.gserver.add_vertex isn't being called on the stop_id?
   #        Does that mean the stop id isn't in gtfsdb_to_edges?
   #        Or maybe this is a problem with unicode/str?

   def link_graphs(self, qb, db_transit):
      log.debug('link_graphs: linking Cyclopath and Transit networks')
      time_0 = time.time()
      # 2011.08.08: Slow method taking 1570.29 secs (26 minutes).
      # 2011.08.09: Made fast method and it took 36 seconds.
      if not self.link_graphs_fast(qb, db_transit):
         # 2011.08.08: 1570.29 secs (26 minutes)
         # NOTE: If you're here, consider running gtfsdb_build_cache.py.
         log.warning('link_graphs: using slow method!')
         self.link_graphs_slow(qb, db_transit)
      log.debug('link_graphs: complete: in %s'
                % (misc.time_format_elapsed(time_0),))

   #
   def link_graphs_fast(self, qb, db_transit):
      linked = False
      if self.cache_reg is not None:
         self.links_process_cache(qb)
         linked = True
      return linked

   #
   def links_get_cache_reg(self, qb):
# FIXME: qb.revision.rid? always Historic??
# FIXME: For now, just grabbing latest revision and caldate
      cache_reg = None
      cache_regs_sql = (
         """
         SELECT
            username
            , branch_id
            , revision_id
            , gtfs_caldate
         FROM
            gtfsdb_cache_register
         WHERE
            username = '%s'
            AND branch_id = %d
         ORDER BY
            revision_id DESC
            --gtfs_caldate DESC
         LIMIT 1
         """ % (qb.username,
                qb.branch_hier[0][0],))
      cache_regs = qb.db.sql(cache_regs_sql)
      if len(cache_regs):
         cache_reg = cache_regs[0]
      return cache_reg

   def links_process_cache(self, qb):
      from_and_where = self.links_cache_from_and_where(
                              'gtfsdb_cache_links', qb)
      count_links_sql = "SELECT COUNT(*) %s" % (from_and_where,)
      nlinks = qb.db.sql(count_links_sql)[0]['count']
      cache_links_sql = (
         """
         SELECT
            node_stack_id
            , transit_stop_id
         %s
         """ % (from_and_where,))
      cache_links = qb.db.sql(cache_links_sql)
      for i, (cache_link) in enumerate(cache_links):
         node_id = cache_link['node_stack_id']
         stop_id = cache_link['transit_stop_id']
         # Every once in a while, print a debug message
         if (i % 1000) == 0:
            log.debug('links_process_cache: progress: on stop # %d of %d...'
                      % (i, nlinks,))
            #log.debug(' >> node_id: %s / stop_id: %s' % (node_id, stop_id,))
         try:
            self.gserver.add_edge(stop_id, node_id, Link())
            self.gserver.add_edge(node_id, stop_id, Link())
         except VertexNotFoundError:
            # 2014.09.19/BUG nnnn: Planner p2 very much broken (only returns
            # bike-only routes; never includes transit), so make this an info
            # so logcheck stops complaining when cron runs gtfsdb_build_cache.
            log.info(
               'link_graphs: no vertex?!.1: node_id: %s / stop_id: %s'
               % (node_id, stop_id,))

   def links_cache_from_and_where(self, table_name, qb):
      revision_id = self.cache_reg['revision_id']
      gtfs_caldate = self.cache_reg['gtfs_caldate']
      from_and_where = (
         """
         FROM
            %s
         WHERE
            username = %s
            AND branch_id = %d
            AND revision_id = %d
            AND gtfs_caldate = %s
         """ % (table_name,
                qb.db.quoted(qb.username),
                qb.branch_hier[0][0],
                revision_id,
                qb.db.quoted(gtfs_caldate),))
      return from_and_where

   # C.f. graphserver/pygs/build/lib/graphserver/compiler/gdb_link_osm_gtfs
   def link_graphs_slow(self, qb, db_transit):

      log.debug('link_graphs: linking Cyclopath and Transit networks')

      # NOTE: We load all byways into the graph, including those tagged
      # 'prohibited' and 'closed', but we only ever link those not tagged as
      # such with transit stops.

      qb = qb.clone(skip_clauses=True, skip_filtport=True, db_clone=True)
      g.assurt(qb.finalized)

      # MAGIC HACK ALERT
      tagprefs = {}
      tagprefs['prohibited'] = ratings.t_avoid
      tagprefs['closed'] = ratings.t_avoid
      #
      rating_func = self.ratings.rating_func(qb.username, tagprefs, self)
      # MAGIC NUMBER: Min rating.
      rating_min = 0.5
      # The transit data is lat,lon, as opposed to SRID-encoded x,y.
      is_latlon = True

      n_stops = db_transit.count_stops()
      # NOTE: 2011.06.26: This loops takes a while. For me [lb], 55 secs.
      # NOTE: 2011.08.08: Find nearest node using GRAC SQL is time consuming!
      #                   On the order of minutes and minutes...

      for i, (stop_id, stop_name, stop_lat, stop_lon,) \
          in enumerate(db_transit.stops()):
         # Every once in a while, print a debug message.
         if (i % 150) == 0:
            log.debug('link_graphs: progress: on stop # %d of %d...'
                      % (i, n_stops,))
            log.debug(' >> id: %s / name: %s / lat: %s / lon: %s'
                      % (stop_id, stop_name, stop_lat, stop_lon,))
         # NOTE: The (x,y) point is lon first, then lat.
         stop_xy = (stop_lon, stop_lat,)
         nearest_byway = route.One.byway_closest_xy(
            qb, stop_name, stop_xy, rating_func, rating_min, is_latlon)
         nearest_node = nearest_byway.nearest_node_id()
# FIXME: What if the node is on a one-way? What if the node is tagged with
# something that the user marks 'avoid'? In both cases, transit stop might be
# Unreachable.
         if nearest_node is not None:
            node_id = str(nearest_node)
            # NOTE: If we don't cast to string, it's unicode, and db.insert
            # doesn't quote it.
            stop_id = 'sta-%s' % (str(stop_id),)
            if node_id != '':
               try:
                  self.gserver.add_edge(stop_id, node_id, Link())
                  self.gserver.add_edge(node_id, stop_id, Link())
               except VertexNotFoundError:
                  # 2014.09.19/BUG nnnn: Planner p2 very much broken, so make
                  # this info instead of warning and add to list of p2 bugs.
                  log.info(
                     'link_graphs: no vertex?!.2: node_id: %s / stop_id: %s'
                     % (node_id, stop_id,))
            else:
               log.warning(
                  'link_graphs: no node name?!: node_id: %s / stop_id: %s'
                  % (node_id, stop_id,))
         else:
            log.warning(
               'link_graphs: no nearest node?!: node_id: %s / stop_id: %s'
               % (node_id, stop_id,))
            log.warning(' >> lat, lon: (%s, %s)' % (stop_lat, stop_lon))

      qb.db.close()

# *** Unit testing

def test_load_graph():
   db_cyclopath = db_glue.new()
   db_cyclopath.sql('set transaction isolation level serializable')
   tgraph = Trans_Graph()
   tgraph.load(db_cyclopath)
   log.debug('tgraph.size: %d' % (tgraph.size,))
   log.debug('tgraph.get_vertex: 1301221: %s', (tgraph.get_vertex("1301221"),))
   log.debug('tgraph.get_vertex: 1240905: %s', (tgraph.get_vertex("1240905"),))
   tgraph.destroy()
   db_cyclopath.close()

if (__name__ == '__main__'):
   test_load_graph()


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import conf
import g

import fiona
import math
import networkx
import os
import random
import shutil
import sys
import time
import traceback
import zipfile

from grax.access_level import Access_Level
from gwis.exception.gwis_error import GWIS_Error
from gwis.query_overlord import Query_Overlord
from item.feat import route_step
from planner.tgraph_base import Trans_Graph_Base
from planner.travel_mode import Travel_Mode
from util_ import geometry
from util_ import mem_usage
from util_ import misc
from item.feat import branch
from item.feat import byway
from item.feat import route
from item.feat import route_step
from item.grac import group
from item.util import ratings
from item.util import revision
from item.util.item_type import Item_Type
from util_.log_progger import Debug_Progress_Logger
from util_.shapefile_wrapper import ojint
from util_.shapefile_wrapper import ojints

log = g.log.getLogger('tgraph_p3')

__all__ = ('Trans_Graph',)

# *** Route Finder Personality (routed_pers) #3 -- Shapefile-based generic
# Statewide quickie routie findie

TEST_IS_DISCONNECTED = False
#TEST_IS_DISCONNECTED = True

__reset_is_disconnected__=("""

DEVs: If you want, before starting route daemon, clear all is_disconnected!
      This'll make sure we inspect all byways on routed boot.

-- UPDATE geofeature SET is_disconnected = FALSE;
-- -- UPDATE 808841
-- -- Time: 202.493501 ms

UPDATE geofeature SET is_disconnected = FALSE WHERE is_disconnected;

FIXME/BUG_2014_JULY: Fix the map data...
I screwed up s snelling ave @ w sargent ave
#     W Sargent Ave: it should connect to S Snelling Ave but does not.
#     The node is a dangle.
#     fortunately, the route finder should be smart enough not to use it.

# This route was broken: the endpoints were on disconnected trees.
# The new planner should be able to route between these:
#
# 3960 Arrowood Ln N, Plymouth, MN, 55441-1469
# 11001 Bren Rd E, Minnetonka, MN, 55343-4410

# FIXME/TEST AGAIN:
# Stack ID 1579364: mjensen's I-94, completely disconnected from the network...
# (its own island). It was loaded from Shapefile, then discarded?
#                   But then identified as missing, and reloaded?
#Jul-10 15:00:33  ERRR     grax.item_mgr  #  139962809995584: processing_fcn:
# failed on feat: "I-94 / US Hwy 52" [byway:983985.v3/3514817-b2500677-acl:edt]

""")

# ***

class Trans_Graph(Trans_Graph_Base):

   # The different cost functions we define.
   #  'len'  -- Cost is simply line length of the edge.
   #  'rat'  -- Cost is the byway rating, scaled to make differences in
   #            ratings more or less perceptible (e.g., how much further
   #            are you will to bike to use better-rated roads).
   #  'fac'  -- Cost is lower for roads and trails with bicycle facilities.
   #            A willingness factor is used to adjust the penalty influence,
   #            much like the way the rating is scaled to make it more or less
   #            perceptible.
   #  'rac'  -- The average of the 'rat' and 'fac' costs.
   #  'p***' -- 'prat', 'pfac', and 'prac' are personalized versions of same.
   weight_types = set(['len', 'rat', 'fac', 'rac', 'prat', 'pfac', 'prac',])
   weight_type_lookup = {'length': 'len',
                         'rating': 'rat',
                         'facility': 'fac',
                         'rat-fac': 'rac',
                         'prating': 'prat',
                         'pfacility': 'pfac',
                         'prat-fac': 'prac',
                         }
   # These are the weights we'll compute and load for the network.
   # On runic.cs, MN takes 3 Gb of RAM for the first three weights.
   # If you add the 'rac' weights, it takes 7 Gb of RAM.
   #weights_enabled=set(['len', 'rat', 'fac',])
   weights_enabled=set(['len', 'rat', 'fac', 'rac', 'prat', 'pfac', 'prac',])
   # Without 'rac' (requires a lot of memory):
   #weights_enabled=set(['len', 'rat', 'fac', 'prat', 'pfac', 'prac',])

   weights_personal = set(['prat', 'pfac', 'prac',])

   # The rating powers define a geometric sequence for the rating values, so
   # that the difference between any two neighbor ratings is always the same
   # ratio. E.g., consider the arithmetic sequence, 1, 2, 3. Comparing 1 and 2,
   # obviously, 2 is twice 1, but comparing 3 and 2, 3 is only 3/2 that of 2.
   # If we're mapping whole-number rating values to an arithmetic sequence,
   # the differences between successive ratings is uneven -- i.e., if
   # excellent is 1, good 2, and fair is 3, 1 mile of a fair road = 1.5 miles
   # of a good road, so a trip that's 50% further on good roads is the same
   # cost. But 1 mile of good road = 2 miles of excellent road, or, a trip
   # that's on good road is the same cost as one on excellent road that's
   # twice as long. This really skews the scale toward whatever values map
   # to the lower numbers: in this case, excellent is weighted twice that
   # of good, but good is only 3/2 of fair, and fair is 4/3 of good, etc.
   # So the difference between a poor road and a fair road is imperceivable
   # when compared to a the difference between a good road and an excellent
   # road. In practice, this could mean that we produce routes on excellent
   # roads that are twice as long as a route we could've just picked on a good
   # road. So, how to solve this? Use a geometric sequence, so the differences
   # between successive ratings is constant. E.g., consider powers of 2 between
   # 0 and 1: pow(2, 0), pow(2, 0.25), ..., pow(2, 1): 1, 1.18, 1.41, 1.68, 2,
   # where each rating is *1.18 the one to its left, or *0.841 that of its
   # right. Note that pow(1,n) is always 1, so that's a distance-only cost.
   # With pow(2,n), the ratios are 1.18/0.84 and the spread is twice the dist.
   # With pow(4,n), the ratios are 1.41/0.70 and the spread is four times.
   # With pow(8,n), the ratios are 1.68/0.59 and spread of eight times dist.
   # With pow(16,n), the ratios are 2.0/0.5, and spread of 16, i.e., 1 mile
   # impassable is the same cost as 16 miles excellent. Also, 2 miles excellent
   # is same as 1 mile good, or 2 miles good is the same cost as 1 mile fair.
   # "You're willing to bike twice as far for each route rated one-star better"
   #
   # For a more exhausting diatribe, see my [lb's] excruciating analysis at the
   # top of the one-line cost_bike fcn. in planner/routed_p1/route_finder.py.
   #
   # SYNC_ME: pyserver.planner.routed_p3.tgraph::Trans_Graph.rating_pows
   #          services.route_analysis.rider_profiles.yml
   #          flashclient.views.panel_branch.Widget_Analysis.mxml
   #rating_pows = set([2, 4, 8, 16, 32,])
   rating_pows = set([2, 4, 8, 16, 32, 64, 128,])
   # The 'rac' weights add a lot of extra memory, so trying just a few...
   #weights_enabled_rac_rating = set([2, 4, 8, 16, 32, 64, 128,])
   weights_enabled_rac_rating = set([2, 128,])

   # The burden is how far out of the way you're willing to bike
   # to access trails, better rated roads, and roads with bike
   # facilities. The burden is the percentage longer of a route
   # you're willing to suffer. The route finder has to load all
   # of these weights on boot, so we only support a handful of
   # burdens.
   # SYNC_ME: pyserver.planner.routed_p3.tgraph::Trans_Graph.burden_vals
   #          services.route_analysis.rider_profiles.yml
   #          flashclient.views.panel_branch.Widget_Analysis.mxml
# 2014.08.25/BUG nnnn: A user is trying to rate roads low but is still
#                      routed on them. If only one person rates a road,
#                      and they rate it low, the average rating is low,
#                      so we should avoid that segment, right? Test/fix.
   burden_vals = set([10, 20, 40, 65, 90, 95, 98,])
   # The 'rac' weights add a lot of extra memory, so trying just a few...
   #weights_enabled_rac_burden = set([10, 20, 40, 65, 90, 95, 98,])
   weights_enabled_rac_burden = set([10, 98,])

   # We don't have to distinguish between types of bike facilities -- we could
   # just say that a route segment has a facility or it doesn't. But we could
   # also say that one type of facility is better than another. This might come
   # in handy, for example, if there's a street with a bike lane or other type
   # of facility, but a block away is a parallel trail: the trail might make
   # the trip longer, but a bike trail is probable a "better" facility to use
   # than a bike lane. Ideally, if our willingness slider works as intended,
   # users will be able to fine-tune their search so that this little facility
   # weight actually has does something useful/meaningful/noticeable.
   #
   # As discussed ad nauseum already, we use a geometric progression. We start
   # at 1 and progress towards the non-facility burden multiplier, but keep
   # the max multiplier less than half of the non-facility burden, or so, such
   # that "lesser-valued" facilities don't have too negative an impact on a
   # feature's cost, but enough so that the finder will be able to distinguish
   # slightly between varying types of and levels of facilities (i.e., trail is
   # preferable to bike boulevard is preferable to bike lanes is preferable to
   # sharrows).
   #
   # To see how the progression works, consider the cost formula:
   #
   #    pow(burden_multiplier, n / magic_denominator)
   #
   # The burden_multiplier is the value computed using burden_vals, n is the
   # sequence position (where n=0 is the best facility, e.g., bike trail, and
   # n=1 and n=2 are assigned to not-the-best facilities), and the
   # magic_denominator is some value we choose. Note that n should be greater
   # than denominator, otherwise the facility adjustment will be worse than if
   # we had just used the burden_multiplier. Also note that we don't want the
   # largest n value to be too close to the burden multiplier for similar
   # reasoning: we don't want the facility adjustment to be as bad, or even
   # as close to as bad, as the burden multipler.
   #
   # For example, consider a denominator of 9 for the smallest burden
   # multiplier. The multiplier for a 10 burden is 10/9, and the facility
   # adjustment for the first few values of n is:
   # 
   # Using denom=9 / 10 Burden
   # >>> pow((10.0/9.0), 1.0/9.0)
   #     1.0117755158353465
   # >>> pow((10.0/9.0), 2.0/9.0)
   #     1.0236896944438814
   # >>> pow((10.0/9.0), 3.0/9.0)
   #     1.0357441686512863
   # (Note that 10.0/9.0 = 1.1111)
   #
   # Considering the middle burden, 50, whose multiplier is 2,
   # 
   # Using denom=9 / 50 Burden
   # >>> pow(2.0, 1.0/9.0)
   #     1.080059738892306
   # >>> pow(2.0, 2.0/9.0)
   #     1.1665290395761165
   # >>> pow(2.0, 3.0/9.0)
   #     1.2599210498948732
   #
   # Finally, on the other side of the burden scale, 90, with a 9 multiplier,
   #
   # Using denom=9 / 90 Burden
   # >>> pow(9.0, 1.0/9.0)
   #     1.2765180070092417
   # >>> pow(9.0, 2.0/9.0)
   #     1.6294982222188463
   # >>> pow(9.0, 3.0/9.0)
   #     2.080083823051904
   #     
   # The last examples used a denominator of nine. Since we only need values
   # for the first few values of n, dividing our raised number by 9 means the
   # first few sequence values are pretty close to one another, and much
   # closer to the starting value of 1 than to the burden multiplier.
   #
   # Indeed, if we decrease the denominator, we increase the cost between
   # steps, and then the largest step sequence value we'll use is closer to
   # the burden multiplier. E.g., consider using a denominator of 6:
   #
   # Using denom=6 / 10 Burden
   # >>> pow((10.0/9.0), 1.0/6.0)
   #     1.0177151706893666
   # >>> pow((10.0/9.0), 2.0/6.0)
   #     1.0357441686512863
   # >>> pow((10.0/9.0), 3.0/6.0)
   #     1.0540925533894598
   #     
   # Using denom=6 / 90 Burden
   # >>> pow(9.0, 1.0/6.0)
   #     1.4422495703074083
   # >>> pow(9.0, 2.0/6.0)
   #     2.080083823051904
   # >>> pow(9.0, 3.0/6.0)
   #     3.0
   #
   # As stated, the lower denominator, the more the spread, until the
   # denominator is smaller than n, at which point the facility scalar
   # exceeds the non-facility multiplier, and then we'd be penalizing
   # the facility too much (more than if it didn't exist)..
   #
   # For now, since we only use n=0, n=1, and n=2, we'll start by
   # testing/implementing a denominator of 6.
   # 2014.04.12: FIXME/MAYBE: Revisit this value and tweak as appropriate.
   facil_magic_denominator = 6.0
   #
   # This lookup tries to qualify different facilty levels of service.
   # A rank of 0 means that an edge with the indicated facility will
   # not be penalized (think: pow(n, 0) = 1, and edge_len *= 1 == edge_len).
   #
   # BUG nnnn: NEW nnnn: Include AADT when considering edge weights...
   #           currently, we use a general notion of traffic,
   #           i.e., high traffic vs. low traffic, but we should
   #           really account for the actual AADT... if it's not
   #           too hard to determine (we have data from MnDOT, but
   #           does it conflate??).
   facil_type_rankweight = {
      #'no_facils': 0.0,
      'paved_trail': 0.0,
      'loose_trail': 2.0,
      'protect_ln': 0.5,
      'bike_lane': 1.0,
      'rdway_shrrws': 1.5,
      'bike_blvd': 0.5,
      'rdway_shared': 1.75,
      'shld_lovol': 1.0,
      # Penalize shld_hivol even more...
      # NO: 'shld_hivol': 2.0,
      'shld_hivol': 5.0, # Out of 6.0
      #'hway_hivol': ,
      'hway_lovol': 4.0,
      #'gravel_road': ,
      'bk_rte_u_s': 0.5,
      'bkway_state': 0.5,
      ##'major_street': ,
      #'facil_vary': ,
      # Skipping: cautionaries: 
      #   no_cautys, constr_open, constr_closed, poor_visib, facil_vary
      }

   # The networkx library provides a handful of different graph search
   # algorithms. It doesn't recommend which ones are faster, though. [lb]
   # wonders if maybe that depends on the dataset, but my experimentation
   # shows that A*-Star and all_shortest_paths are fairly comparable
   # and perform an two or three times faster than Dijkstra's. In practice,
   # I can't see clients wanting to set this value away from the default,
   # but it's possible nonethelesss..
   #
   # 2014.04.04: Some run times:
   #
   #   ./ccp.py --route --p3 --from 'Two Harbors, MN' --to 'Pipestone, MN'
   #
   # networkx.all_shortest_paths    path #1: len: 938 / in 12.01 secs.
   # networkx.shortest_path            no. edges: 938 / in 26.22 secs.
   # EXPLAIN: What does the latter run so much quicker?
   # networkx.astar_path               no. edges: 938 / in 10.79 secs.
   # networkx.dijkstra_path            no. edges: 938 / in 25.50 secs.
   # networkx.single_source_dijkstra   no. edges: 332406 / in 26.61 secs.
   # ... and you don't even want to know how long the p1 finder takes!
   algorithms = set(['as*', 'asp', 'dij', 'sho',])
   algorithm_lookup = {'astar_path': 'as*',
                       'all_shortest_paths': 'asp',
                       'dijkstra_path': 'dij',
                       'shortest_path': 'sho',}

   # If the Shapefile you're loading is missing any attributes, we'll complain.
   # But if you're using the Shapefile made by ccp_export_branches.sh (which
   # makes an export work_item and uses the services/merge/* export scripts),
   # your Shapefile should contain all the right stuff.
   warned_is_disconnected_missing = False
   warned_is_disconnected_invalid = False

   __slots__ = (
      # The multiple-same-nodes-okay directed graph, which contains zero, one,
      # or many directed edges between the any two nodes.
      'graph',
      # A directed graph with only zero or one same-directed edge
      # between sets of nodes.
      'graph_di',
      # An undirected graph, to check for connectednesses.
      'graph_undi',
      'shp_cache_dir',
      'source_shp',
      'source_zip',
      'keep_running',
      # A collection of the favorite subtree node IDs.
      'favtree_members',
      'missing_from_graph_sys',
      'missing_from_graph_stk',
      'removed_from_graph',
      'marked_disconnected_but_not',
      )

   # *** Constructor

   def __init__(self, route_daemon):
      Trans_Graph_Base.__init__(self, route_daemon)
      self.graph = networkx.MultiDiGraph() # Directed graph with multiedges.
      self.graph_di = None
      self.graph_undi = networkx.MultiGraph() # Undirected graph; connectedness
      self.shp_cache_dir = route_daemon.cli_opts.shp_cache_dir
      self.source_shp = route_daemon.cli_opts.source_shp
      self.source_zip = route_daemon.cli_opts.source_zip
      self.favtree_members = None
      if not self.shp_cache_dir:
         self.shp_cache_dir = os.getenv('SHP_CACHE_DIR')
         log.debug('Trans_Graph: using SHP_CACHE_DIR: %s'
                   % (self.shp_cache_dir,))
      if not self.source_shp:
         self.source_shp = os.getenv('SOURCE_SHP')
         log.debug('Trans_Graph: using SOURCE_SHP: %s'
                   % (self.source_shp,))
      if not self.source_zip:
         self.source_zip = os.getenv('SOURCE_ZIP')
         log.debug('Trans_Graph: using SOURCE_ZIP: %s'
                   % (self.source_zip,))
      if bool(self.source_zip) ^ bool(self.shp_cache_dir):
         err_s = ('Specify neither or both --source_zip and --shp_cache_dir.')
         log.warning(err_s)
         raise GWIS_Error(err_s)

   # *** Loading and Updating

   #
   def load_really(self, qb_curr, keep_running=None):

      # Not calling: Trans_Graph_Base.load_really.

      # After someone saves the map, the route planners each update themselves.
      # This can take a number of minutes, during which time users cannot find
      # routes! This planner therefore releases the lock while it updates the
      # copies of the road network that aren't needed to plan routes; when the
      # update is almost complete, it'll re-acquire the lock before changing
      # any variables used for route planning, so we should not cause a service
      # outage just because someone saved map changes.
      self.route_daemon.processing_cnt += 1
      log.debug('load_really: lock_updates.release')
      self.route_daemon.lock_updates.notify()
      self.route_daemon.lock_updates.release()

      self.keep_running = keep_running

      g.check_keep_running(self.keep_running)

      t0_all = time.time()

      usage_0 = None
      if conf.debug_mem_usage:
         usage_0 = mem_usage.get_usage_mb()
         log.info('load: mem_usage: beg: %.2f Mb' % (usage_0,))

      # We load byways from a Shapefile or from the database; if from a
      # Shapefile, we check the database for recent changes.

      qb_update = None
      if (isinstance(qb_curr.revision, revision.Historic)
          and (self.source_shp or self.source_zip)):
         if self.source_zip and self.shp_cache_dir:
            self.cache_shapefiles_setup()
         qb_update = self.load_from_shapefile(qb_curr)
         g.check_keep_running(self.keep_running)
         if qb_update is not None:
            self.load_from_database(qb_update)
      else:
         # qb_curr is revision.Historic or revision.Updated.
         self.load_from_database(qb_curr)

      log.debug('load: self.graph: number_of_nodes: %d'
                % (self.graph.number_of_nodes(),))

      # See that we got nodes. Note that len(self.graph) also works.
      if not self.graph.number_of_nodes():
         raise GWIS_Error('tgraph load failed: nothing loaded?')

      g.check_keep_running(self.keep_running)

      if isinstance(qb_curr.revision, revision.Historic):

         # Make an undirected graph so we can discard disconnected edges.
         self.connected_subtree_enforce(qb_curr, qb_update)

         # We don't need favtree_members any more.
         self.favtree_members = None

         g.check_keep_running(self.keep_running)

      # else, revision.Updated, and our update byway code should manage
      #       removing and adding edges to the graph... hopefully. =)

      # Make a DiGraph ("astar_path() not implemented for Multi(Di)Graphs").
      #
      # FIXME/BUG nnnn: The DiGraph constructor only uses the first edge it
      # finds of any multi-edge. E.g., think of two parallel byways, one road
      # and one bikepath, that are connected at the same node endpoints; it's
      # arbitrary whether the bikepath or road is used (its stack_id attribute
      # is copied) when the DiGraph is constructed.
      #  SOLUTIONs: 1. Make psuedo-nodes between parallels with a 0 edge cost?
      #             2. Build graph_di alongside self.graph and always choose
      #                the bike path/more friendly geofeature layer id?
      #             3. Write our own MultiDiGraph->DiGraph function?
      #             I like (1.) the best (so that both roads still compete,
      #             i.e., the road is likely to be shorter in length, but
      #             the path is friendlier, so depending on the user's bike
      #             preferences, we'll want to be able to choose either).
      #             But how easy is it to make pseudo-nodes....???????
      #             4. Make a psuedo byway stack ID? but then the edge
      #                weight cannot represent all the multi-parallels.
      #             4b. Use a DiGraph to boot, and when an edge already
      #                 exists, complain, so we can manually fix?
      #                 Or make sure the edge is always the bike facil?
      #  FIXME/FOR NOW: On boot, complain when making secondary edges.
      #                 At least then we can understand the scope of the
      #                 problem.
      #
      # 2014.07.21: 4.13 minutes...
      log.debug('load: self.graph: reducing to directed graph...')
      t0 = time.time()

      # The NetworkX DiGraph ctor blocks our thread, so we cannot complete
      # route requests while this is chugging away. So make the graph clone
      # ourselves.
      # Blocks for minutes: new_graph_di = networkx.DiGraph(self.graph)
      new_graph_di = networkx.DiGraph()
      graph_edges = self.graph.edges_iter(data=True, keys=False)
# FIXME: Test different values here... and compare against runtimes.
      edge_count = 0
      for edge_tup in graph_edges:
         # BUG nnnn: For multiple, parallel edges, we only consume first edge.
         new_graph_di.add_edges_from([edge_tup,])
         # This tight loop prevents other threads from running -- namely,
         # we compete with Apache get route requests, because they send them
         # to our handler thread. So we have to make sure Python switches
         # threads, otherwise the get-route requests won't run until we're
         # done with this loop!
         #
   # FIXME/BUG nnnn: When a get route request is received, increment a
   #                 mutex, and here, check that mutex every iteration
   #                 and block if we detect that it's positive.
         #
         # There's a system-wide value,
         #   sys.setcheckinterval(n)
         # that affects thread context switching,
         # otherwise [lb] knows of another trick:
# MAYBE: Only do his every n iterations, to reduce context switches.
         #time.sleep(0.001)
         if (edge_count % 5) == 0:
            time.sleep(0.001)
         edge_count += 1

      log.debug('load: make directed graph in %s'
                % (misc.time_format_elapsed(t0),))

      # Load ratings.

      new_ratings = None
      if set(['prat', 'pfac', 'prac',]).intersection(
                                          Trans_Graph.weights_enabled):
         log.debug('load: loading ratings...')
         if self.ratings is None:
            g.assurt_soft(isinstance(qb_curr.revision, revision.Historic))
         new_ratings = ratings.Predictor(self)
         # Loads ratings or updates what's changed since last checked.
         new_ratings.load(qb_curr.db, keep_running=self.keep_running)

      # The remaining tasks should hopefully run quickly! (Reacquire the lock.)

      log.debug('load_really: lock_updates.acquire...')
      self.route_daemon.lock_updates.acquire()
      self.route_daemon.processing_cnt -= 1
      while self.route_daemon.processing_cnt > 0:
         log.debug('load_really: waiting on processing_cnt (%d)...'
                   % (self.route_daemon.processing_cnt,))
         self.route_daemon.lock_updates.wait()

      self.graph_di = new_graph_di

      if new_ratings is not None:
         self.ratings = new_ratings

      # All done loading.

      conf.debug_log_mem_usage(log, usage_0, 'tgraph_base.load_really')

      log.debug('load: no. graph    nodes: %d' % (len(self.graph),))
      log.debug('load: no. graph_di nodes: %d' % (len(self.graph_di),))

      log.info(
   '/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\')
      log.info('load: complete: for %s in %s'
               % (qb_curr.revision.short_name(),
                  misc.time_format_elapsed(t0_all),))
      log.info(
   '/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\/*\\')

      qb_curr.definalize()
      qb_curr = None

      self.keep_running = None

   #
   def cache_shapefiles_setup(self):

      try:
         source_zip_stats = os.stat(self.source_zip)
      except OSError, e:
         err_s = ('Unexpected: Shapefile archive not found or inaccessible: %s'
                  % (str(self.source_zip),))
         log.warning(err_s)
         raise GWIS_Error(err_s)

      touch_zip = os.path.join(self.shp_cache_dir,
                               '%s.touch' % (os.path.basename(
                                             self.source_zip),))

      unpack_archive = True
      if not os.path.exists(self.shp_cache_dir):
         log.info('Creating shapefiles directory: %s' % (self.shp_cache_dir,))
         try:
            os.mkdir(self.shp_cache_dir, 02777)
            os.chmod(self.shp_cache_dir, 02777)
         except OSError, e:
            err_s = ('Unexpected: Could not make shapefiles directory: %s'
                     % (str(self.shp_cache_dir),))
            log.warning(err_s)
            raise GWIS_Error(err_s)
      else:
         try:
            touch_zip_stats = os.stat(touch_zip)
            if source_zip_stats.st_mtime > touch_zip_stats.st_mtime:
               log.debug('cache_shapefiles_setup: zip file newer')
            else:
               log.debug('cache_shapefiles_setup: zip file unchanged')
               unpack_archive = False
         except OSError, e:
            log.debug('cache_shapefiles_setup: no touch file')

      zfile = None
      try:
         if unpack_archive or (not self.source_shp):
            zfile = zipfile.ZipFile(self.source_zip, 'r')
            (shpf_path, self.source_shp,) = self.deduce_source_shp_path(zfile)
         if unpack_archive:
            # See if we should delete an existing cache directory.
            # The zip file path is relative; find its root.
            unpack_dir = os.path.dirname(shpf_path)
            while os.path.dirname(unpack_dir):
               unpack_dir = os.path.dirname(unpack_dir)
            unpack_dir = os.path.join(self.shp_cache_dir, unpack_dir)
            if os.path.exists(unpack_dir):
               log.debug('cache_shapefiles_setup: removing old shpf cache...')
               shutil.rmtree(unpack_dir)
            log.debug('cache_shapefiles_setup: extracting Shapefile to: %s'
                      % (self.shp_cache_dir,))
            # Extract the archive.
            t0 = time.time()
            zfile.extractall(self.shp_cache_dir)
            log.debug('cache_shapefiles_setup: extracted Shapefile in %s'
                      % (misc.time_format_elapsed(t0),))
            # Make a touch file to remember the last time we unpacked the zip.
            misc.file_touch(touch_zip)
         # Double-check that things worked out okay.
         if not os.path.exists(self.source_shp):
            err_s = ('Unexpected: Shapefile not found after unpacking: %s'
                     % (str(self.source_shp),))
            log.warning(err_s)
            raise GWIS_Error(err_s)
      except IOError, e:
         err_s = ('Could not open and extract zipfile: %s: %s'
                  % (self.source_zip, str(e),))
         log.warning(err_s)
         raise GWIS_Error(err_s)
      finally:
         if zfile is not None:
            zfile.close()

   #
   def deduce_source_shp_path(self, zfile):
      # Look for the one and only Shapefile in the archive.
      shpf_path = None
      for zinfo in zfile.filelist:
         if zinfo.filename.endswith('.shp'):
            if shpf_path:
               err_s = (
                  'Unexpected: More than 1 .shp in .zip: %s and %s in %s'
                  % (shpf_path, zinfo.filename, self.source_zip,))
               log.warning(err_s)
               raise GWIS_Error(err_s)
            shpf_path = zinfo.filename
      if not shpf_path:
         err_s = ('Unexpected: No .shp in .zip: %s' % (self.source_zip,))
         log.warning(err_s)
         raise GWIS_Error(err_s)
      # Complain if the user's path is not what it really is.
      actual_path = os.path.join(self.shp_cache_dir, shpf_path)
      if self.source_shp and (actual_path != self.source_shp):
         log.warning('Unexpected: --source_shp != deduced: %s / %s'
                     % (self.source_shp, actual_path,))
      return (shpf_path, actual_path,)

   #
   def load_from_shapefile(self, qb_curr):

      # Load byways, attrs, tags, ratings, etc.

      num_loaded = 0
      num_disconnected = 0

      latest_revision = -1

      try:

         with fiona.open(self.source_shp, 'r') as source_data:

            log.debug('Found %d fields in Shapefile: %s'
                      % (len(source_data.schema['properties']),
                         os.path.basename(self.source_shp),))
            log.debug(' .. the fields: %s'
                      % (source_data.schema['properties'].keys(),))
            log.debug('Loading %d features...' % (len(source_data),))

            prog_log = Debug_Progress_Logger()
            #prog_log.setup(prog_log, 10000, len(source_data))
            prog_log.setup(prog_log, 25000, len(source_data))

            for shpfeat in source_data:

               if ((ojint(shpfeat['properties']['CCP_ID']) > 0)
                   and (shpfeat['geometry'])):

                  try:
                     latest_revision = shpfeat['properties']['latest_rid']
                  except:
                     pass

                  try:
                     is_disconnected = not int(
                        shpfeat['properties']['wconnected'])
                  except KeyError:
                     is_disconnected = False
                     if not Trans_Graph.warned_is_disconnected_missing:
                        log.warning('Shapefile missing field: wconnected')
                        Trans_Graph.warned_is_disconnected_missing = True
                  except ValueError:
                     is_disconnected = False
                     if not Trans_Graph.warned_is_disconnected_invalid:
                        log.warning('Invalid "wconnected": "%s"'
                           % (shpfeat['properties']['wconnected'],))
                        Trans_Graph.warned_is_disconnected_invalid = True
                  except TypeError:
                     # shpfeat['properties']['wconnected'] in None
                     is_disconnected = False

                  if not is_disconnected:

                     #log.debug('On: %s' % (shpfeat,))

                     self.load_make_graph_insert_shpfeat(qb_curr, shpfeat)
                     num_loaded += 1
                  else:
                     num_disconnected += 1

               if prog_log.loops_inc():
                  break

            prog_log.loops_fin()

      except IOError, e:

         log.error('load: problem opening Shapefile: %s / %s'
                   % (os.path.basename(self.source_shp), str(e),))

      except Exception, e:

         log.error('load: problem processing shapefile: %s' % (str(e),))
         stack_trace = traceback.format_exc()
         log.warning('Warning: Unexpected exception: %s' % stack_trace)

      log.debug('load: num_loaded: %d / num_disconnected: %d'
                % (num_loaded, num_disconnected,))

      # Since qb_curr.revision.rid == Revision.revision_max(qb_curr.db),
      # check in the latest db revision is greater than what we saw in the
      # Shapefile. If so, check the database for updated items.
      if ((latest_revision > -1)
          and (latest_revision < qb_curr.revision.rid)):
         log.debug('load: latest_revision < qb_curr.revision.rid: %s < %s'
                   % (latest_revision, qb_curr.revision.rid,))
         qb_update = qb_curr.clone()
         qb_update.revision = revision.Updated(latest_revision,
                                               qb_curr.revision.rid)
         if self.route_daemon.cli_opts.regions:
            log.debug('load: restrict to region(s): %s'
                      % (self.route_daemon.cli_opts.regions,))
            qb_update.filters.filter_by_regions = (
               self.route_daemon.cli_opts.regions)
         Query_Overlord.finalize_query(qb_update)
      else:
         # Already at latest revision, or so it seems.
         log.debug('load: latest_revision: %s / qb_curr.revision.rid: %s'
                   % (latest_revision, qb_curr.revision.rid,))
         qb_update = None

      return qb_update

   #
   def load_from_database(self, qb_curr):

      if self.route_daemon.cli_opts.regions:
         log.debug('load_from_database: restrict to region(s): %s'
                   % (self.route_daemon.cli_opts.regions,))
         qb_curr.filters.filter_by_regions = self.route_daemon.cli_opts.regions
         Query_Overlord.finalize_query(qb_curr)

      log.debug('load_from_database: calling load_feats_and_attcs...')
      prog_log = Debug_Progress_Logger(log_freq=25000)

      # If we loaded an old Shapefile, or if a user just saved map changes and
      # we got hupped, or if we're starting a finder for route analysis, poke
      # around in the database for changes.
      if isinstance(qb_curr.revision, revision.Historic):
         qb_curr.item_mgr.load_feats_and_attcs(qb_curr, byway,
            'search_by_network', self.add_byway_loaded, prog_log,
            heavyweight=False, fetch_size=0, keep_running=self.keep_running)
      else:
         # EXPLAIN: Does regions option have any effect on revision.Updated
         #          checkout? We only use regions for testing, so not too
         #          big a deal, but that might mean we load byways outside
         #          of the region when processing revision updates.
         g.assurt(isinstance(qb_curr.revision, revision.Updated))
         log.debug('load: loading changes from database...')
         #qb_curr.filters.include_item_stack = True
         prog_log = Debug_Progress_Logger(log_freq=25000)
         qb_curr.item_mgr.update_feats_and_attcs(qb_curr, byway,
            'search_by_network', self.add_byway_updated, prog_log,
            heavyweight=False, fetch_size=0, keep_running=self.keep_running)

   # ***

   #
   def connected_subtree_enforce(self, qb_curr, qb_update):

      # Find a node near a known point.
      # CAVEAT: It's up to the developer to make sure this part of the
      #         road network doesn't get messed up!

      node_list = None

      # During development of this code, [lb] coded two ways to make the
      # undirected graph: derive it from the MultiDiGraph, and also maintain
      # a separate undirected graph. Testing shows that both undirected graphs
      # are always that same. We can save time by using the graph we maintain,
      # since the to_undirected() fcn. takes a very long time compared to the
      # rest of the planner bootstrap.
      if False:

         log.debug('cx_subtree_enforce: graph.to_undirected: %d nodes...'
                   % (len(self.graph),))

         t0 = time.time()

         # 2014.07.10: 343809 nodes: 12.37 mins.
         graph_undi = self.graph.to_undirected()

         log.debug('cx_subtree_enforce: created undirected graph after %s'
                   % (misc.time_format_elapsed(t0),))

         if len(graph_undi) != len(self.graph_undi):
            log.warning('different lens: to_undirected: %d / graph_undi: %d'
                        % (len(graph_undi), len(self.graph_undi),))

      else:

         graph_undi = self.graph_undi

      pt_xy = (conf.known_node_pt_x, conf.known_node_pt_y,)

      if pt_xy[0] and pt_xy[1]:
         log.debug('connected_subtree_enforce: looking for node nearest: %s'
                   % (pt_xy,))
         # Funny. byway_closest_xy returns a byway, always, even for pt. (0,0).
         nearest_byway = route.One.byway_closest_xy(
            qb_curr,
            addr_name='identify_subtree',
            pt_xy=pt_xy,
            rating_func=None,
            rating_min=0.5, # MAGIC_NUMBER: rating_min always 0.5 on scale 0-5.
            is_latlon=False,
            radius=None)
         if nearest_byway is not None:
            log.debug('connected_subtree_enforce: nearest_byway: %s'
                      % (nearest_byway,))
            try:
               node_list = networkx.node_connected_component(graph_undi,
                                             nearest_byway.beg_node_id)
            except KeyError, e:
               g.assurt_soft(self.route_daemon.cli_opts.regions)
         else:
            log.error('could not find node on known network: %s' % (self,))

      if not node_list:
         log.error("DEV: Please set CONFIG's known_node_pt_x/_y.")
         # Without a known node... what can we just guess?
         n_nodes = len(self.graph)
         n_guesses = 10
         while n_guesses > 0:
            guessed_node = self.graph.node.keys()[
               int(math.floor(n_nodes * random.random()))]
            node_list = networkx.node_connected_component(graph_undi,
                                                          guessed_node)
            if len(node_list) > (len(self.graph) * 0.5):
               log.debug('connected_subtree_: guessed right: %d of %d in tree'
                         % (len(node_list), len(self.graph),))
               break
            n_guesses -= 1
            if not n_guesses:
               log.error('connected_subtree_: guessing fail; using last tree')

      if node_list:

         # Checking membership in a set is lots faster than checking an array.
         self.favtree_members = set(node_list)

         if self.graph.number_of_nodes() != len(self.favtree_members):

            if len(self.favtree_members) < (len(self.graph) * 0.5):
               log.warning('%s: %s: graph: %d / subtree: %d'
                           % ('nodes_prep_conn_subtree',
                              'less than half in subtree',
                              len(self.graph),
                              len(self.favtree_members),))
            else:
               log.debug('nodes_prep_conn_subtree: number nodes in favtree: %d'
                         % (len(self.favtree_members),))

            if len(self.favtree_members):
               self.connected_subtree_cull_disconnected(qb_curr, qb_update)
            else:
               log.error('nothing in the connected subtree?')

      else:

         g.assurt_soft(False) # Shouldn't come through here.

   # ***

   broke_once_beg = False
   broke_once_fin = False

   #
   def connected_subtree_cull_disconnected(self, qb_curr, qb_update):

      if self.route_daemon.cli_opts.regions:
         log.debug('connected_subtree_cull_: restrict to region(s): %s'
                   % (self.route_daemon.cli_opts.regions,))
         # If we loaded from a shapefile, qb_update's regions geometry is set.
         if not qb_curr.filters.filter_by_regions:
            g.assurt(self.route_daemon.cli_opts.regions
                     == qb_update.filters.filter_by_regions)
            qb_curr.filters.filter_by_regions = (
               qb_update.filters.filter_by_regions)
         else:
            g.assurt(self.route_daemon.cli_opts.regions
                     == qb_curr.filters.filter_by_regions)

      self.cull_disconnected_via_item_mgr(qb_curr)

      self.missing_from_graph_cleanup(qb_curr)

      self.removed_from_graph_cleanup(qb_curr)

      if self.marked_disconnected_but_not:
         log.error('connected_subtree_cull_: %d marked_disconnected_but_not'
                   % (self.marked_disconnected_but_not,))

   #
   def cull_disconnected_via_item_mgr(self, qb_curr):

      self.missing_from_graph_sys = set()
      self.missing_from_graph_stk = set()
      self.removed_from_graph = set()
      self.marked_disconnected_but_not = 0

      time_0 = time.time()

      log.debug('cull_discx_via_item_mgr: calling load_feats_and_attcs...')
      prog_log = Debug_Progress_Logger(log_freq=25000)

      qb_curr.item_mgr.load_feats_and_attcs(qb_curr, byway,
         'search_by_network', self.check_byway_from_db, prog_log,
         heavyweight=False, fetch_size=0, keep_running=self.keep_running)

      log.debug('cull_discx_via_item_mgr: processed %d byways in %s'
                % (prog_log.progress,
                   misc.time_format_elapsed(time_0),))

   #
   def check_byway_from_db(self, qb, bway, prog_log):

      # Determine if the byway is considered well-connected.

      g.assurt_soft(not bway.deleted)
      if (   (bway.tagged.intersection(
               byway.Geofeature_Layer.controlled_access_tags))
          or (bway.geofeature_layer_id
               in byway.Geofeature_Layer.controlled_access_gfids)
          # NOTE: Ignoring: byway.is_disconnected
          # NOTE: Ignoring: bway.access_level_id > Access_Level.client
          # FIXME/BUG nnnn: See also geofeature.control_of_access.
         ):
         # Controlled-access means never well-connected.
         well_connected = False
      else:
         # Check that one or both node endpoints is well-connected.
         #
         # NOTE: node_connected_component
         if bway.beg_node_id in self.favtree_members:
            if bway.fin_node_id not in self.favtree_members:
               # If one byway node endpoint is in the well-connected
               # graph but the other endpoint is not, it probably
               # means you loaded a Shapefile from the live site
               # but booted it into the test site, and the live
               # site has since been edited. I.e., some byway has
               # a new version indicated in the Shapefile from the
               # live database, but in the test database itself, that
               # new version does not exist.
               if not Trans_Graph.broke_once_beg:
                  Trans_Graph.broke_once_beg = True
                  pass
               log.warning(
                  'check_byway_from_db: beg node is connected but not fin: %s'
                  % (bway,))
            well_connected = True
         else:
            if bway.fin_node_id in self.favtree_members:
               # See comments in if-block. This path probably means that
               # your Shapefile from whence did not come the same database.
               if not Trans_Graph.broke_once_fin:
                  Trans_Graph.broke_once_fin = True
                  pass
               log.warning(
                  'check_byway_from_db: beg node not connected but fin is: %s'
                  % (bway,))

            well_connected = False

      # Process depending on well-connectedness.

      if well_connected:
         # Check that the byway is part of the road network.
         byway_missing = False
         try:
            self.graph.node[bway.beg_node_id]
         except KeyError, e:
            byway_missing = True
            self.missing_from_graph_sys.add(bway.system_id)
            self.missing_from_graph_stk.add(bway.stack_id)
         try:
            self.graph.node[bway.fin_node_id]
         except KeyError, e:
            byway_missing = True
            self.missing_from_graph_sys.add(bway.system_id)
            self.missing_from_graph_stk.add(bway.stack_id)
         # Check that the byway is not marked is_disconnected.
         if bway.is_disconnected:
            # If the byway is marked is_disconnected, it probably wasn't
            # loaded into the graph.
            if not byway_missing:
               self.missing_from_graph_sys.add(bway.system_id)
               self.missing_from_graph_stk.add(bway.stack_id)
               self.marked_disconnected_but_not += 1
         elif byway_missing:
            # The byway is not marked is_disconnected, but it's missing
            # from the graph. Now, why would that be?
            #g.assurt_soft(False)
            log.error(
               'check_byway_from_db: !is_disconnected but missing: %s'
               % (bway,))
         # else, not marked is_disconnected and not missing from the graph.
      else:
         # This byway is not well_connected. Check that it's not loaded.
         byway_loaded = False
         try:
            self.graph.node[bway.beg_node_id]
            byway_loaded = True
         except KeyError, e:
            pass
         try:
            self.graph.node[bway.fin_node_id]
            byway_loaded = True
         except KeyError, e:
            pass
         if byway_loaded:
            self.removed_from_graph.add(bway.system_id)

            try:
               self.graph.remove_edge(
                  bway.beg_node_id, bway.fin_node_id, key=bway.stack_id)
            except networkx.NetworkXError, e:
               pass
            try:
               self.graph.remove_edge(
                  bway.fin_node_id, bway.beg_node_id, key=bway.stack_id)
            except networkx.NetworkXError, e:
               pass
            try:
               self.graph_undi.remove_edge(
                  bway.beg_node_id, bway.fin_node_id, key=bway.stack_id)
            except networkx.NetworkXError, e:
               pass
            try:
               del self.step_lookup[bway.stack_id]
            except KeyError:
               pass

   #
   def missing_from_graph_cleanup(self, qb_curr):

      if self.missing_from_graph_sys:

         log.debug('missing_from_graph_cleanup: found %d missing byways'
                   % (len(self.missing_from_graph_sys),))

         if (not self.route_daemon.cli_opts.regions) or TEST_IS_DISCONNECTED:

            # NOTE: We block indefinitely here; this shouldn't be a problem,
            #       unless your code is stuck.
            qb_curr.db.transaction_begin_rw('revision')

            log.error('The network graph is missing some connected byways.')
            #log.error('=====================================================')
            #log.error('RESTART THE ROUTE DAEMON: You might fix this problem.')
            #log.error('=====================================================')

            update_sql = (
               """
               UPDATE geofeature
                  SET is_disconnected = FALSE
                WHERE system_id IN (%s)
               """
               % (','.join([str(x) for x in self.missing_from_graph_sys]),))

            rows = qb_curr.db.sql(update_sql)
            g.assurt(rows is None)

            log.error('Set is_disconnected FALSE on %d byways'
                      % (qb_curr.db.curs.rowcount,))

            qb_curr.db.transaction_commit()

            log.debug('missing_from_graph_cleanup: loading %d missing byways'
                      % (len(self.missing_from_graph_stk),))
            g.assurt(len(self.missing_from_graph_sys)
                     == len(self.missing_from_graph_stk))

            time_0 = time.time()

            prog_log = Debug_Progress_Logger()
            prog_log.setup(prog_log, 1000, len(self.missing_from_graph_stk))

            load_qb = qb_curr.clone(db_get_new=True)

            load_qb.load_stack_id_lookup('missing_from_graph_stk',
                                         self.missing_from_graph_stk)

            load_qb.item_mgr.load_feats_and_attcs(load_qb, byway,
               'search_by_network', self.add_byway_loaded, prog_log,
               heavyweight=False, fetch_size=0, keep_running=self.keep_running)

            # self.qb.filters.only_stack_ids = ''
            load_qb.filters.stack_id_table_ref = ''
            load_qb.db.close()

            log.debug(
               'missing_from_graph_cleanup: loaded %d missing byways in %s'
               % (prog_log.progress,
                  misc.time_format_elapsed(time_0),))

   #
   def removed_from_graph_cleanup(self, qb_curr):

      if self.removed_from_graph:

         log.debug('removed_from_graph_cleanup: removed %d misconnected byways'
                   % (len(self.removed_from_graph),))

         if (not self.route_daemon.cli_opts.regions) or TEST_IS_DISCONNECTED:

            log.warning('The network graph included disconnected byways.')
            log.warning('We will update is_disconnected now to fix this.')

            # NOTE: We block indefinitely here; this shouldn't be a problem,
            #       unless your code is stuck.
            qb_curr.db.transaction_begin_rw('revision')

            update_sql = (
               """
               UPDATE geofeature
                  SET is_disconnected = TRUE
                WHERE system_id IN (%s)
               """ % (','.join([str(x) for x in self.removed_from_graph]),))

            rows = qb_curr.db.sql(update_sql)
            g.assurt(rows is None)

            log.warning('Set is_disconnected TRUE on %d byways'
                        % (qb_curr.db.curs.rowcount,))

            qb_curr.db.transaction_commit()

   # ***

   #
   def load_make_graph_insert_new(self, new_byway):

      rstep = route_step.One()

      rstep.init_from_byway(new_byway)

      rstep.travel_mode = Travel_Mode.bicycle

      self.step_lookup_append(rstep.byway_stack_id, rstep)

      point_beg = geometry.wkt_point_to_xy(new_byway.beg_point)
      point_beg2 = geometry.wkt_point_to_xy(new_byway.beg2_point)
      point_fin = geometry.wkt_point_to_xy(new_byway.fin_point)
      point_fin2 = geometry.wkt_point_to_xy(new_byway.fin2_point)

      fakeshp = {}
      fakeshp['properties'] = {}
      fakeshp['properties']['geom_len'] = new_byway.geometry_len
      fakeshp['properties']['rtng_gnric'] = new_byway.generic_rating
      attr_bike_facil = new_byway.attr_val(byway.One.attr_bike_facil_base)
      if attr_bike_facil is None:
         attr_bike_facil = new_byway.attr_val(byway.One.attr_bike_facil_metc)
      fakeshp['properties']['bike_facil'] = attr_bike_facil

      edge_weights = Trans_Graph.get_weights(rstep, fakeshp)

      if edge_weights:

         edge_weights['byway_stack_id'] = rstep.byway_stack_id

         # MAGIC NUMBER: If != -1, either two-way, or one-way == 1.
         if new_byway.one_way != -1:
            # Cache forward edge.
            dstep = route_step.Wrap(rstep)
            #
            dstep.forward = True
            dstep.dir_entry = geometry.v_dir(point_beg, point_beg2)
            dstep.dir_exit = geometry.v_dir(point_fin2, point_fin)
            #
            self.graph_add_weighted_edge(dstep,
                                         rstep.beg_node_id,
                                         rstep.fin_node_id,
                                         **edge_weights)

         # MAGIC NUMBER: If != 1, either two-way, or one-way == -1.
         if new_byway.one_way != 1:
            # Cache backward edge
            dstep = route_step.Wrap(rstep)
            #
            dstep.forward = False
            dstep.dir_entry = geometry.v_dir(point_fin, point_fin2)
            dstep.dir_exit = geometry.v_dir(point_beg2, point_beg)
            #
            self.graph_add_weighted_edge(dstep,
                                         rstep.fin_node_id,
                                         rstep.beg_node_id,
                                         **edge_weights)

         self.graph_undi.add_edge(rstep.beg_node_id,
                                  rstep.fin_node_id,
                                  key=rstep.byway_stack_id)

         # MAYBE: Also maintain self.favtree_members?
         #        But how easy is that?

      # else, edge_weights is empty, meaning this edge is impassable
      #       in both directions.

   #
   def load_make_graph_insert_shpfeat(self, qb_curr, shpfeat):

      rstep = route_step.One()

      rstep.init_from_shpfeat(qb_curr, shpfeat)

      # Note: Travel_Mode is overloaded. It specified what route finder to use,
      # i.e., Travel_Mode.wayward is this route finder. But it's not the same
      # value used for the route_step.
      # Nope: rstep.travel_mode = Travel_Mode.wayward
      rstep.travel_mode = Travel_Mode.bicycle

      # Bug 2641: Poor Python Memory Management
      # BUG nnnn: Directional attrs/tags. Maybe self.step_lookup is always a
      #           tuple with two entries, one for each direction?
      self.step_lookup_append(rstep.byway_stack_id, rstep)

      point_beg = shpfeat['geometry']['coordinates'][0]
      point_beg2 = shpfeat['geometry']['coordinates'][1]
      point_fin = shpfeat['geometry']['coordinates'][-1]
      point_fin2 = shpfeat['geometry']['coordinates'][-2]

      edge_weights = Trans_Graph.get_weights(rstep, shpfeat)

      if edge_weights:

         edge_weights['byway_stack_id'] = rstep.byway_stack_id

         # MAGIC NUMBER: If != -1, either two-way, or one-way == 1.
         if ojint(shpfeat['properties']['one_way']) != -1:
            # Cache forward edge.
            dstep = route_step.Wrap(rstep)
            #
            dstep.forward = True
            dstep.dir_entry = geometry.v_dir(point_beg, point_beg2)
            dstep.dir_exit = geometry.v_dir(point_fin2, point_fin)
            #
            self.graph_add_weighted_edge(dstep,
                                         rstep.beg_node_id,
                                         rstep.fin_node_id,
                                         **edge_weights)

         # MAGIC NUMBER: If != 1, either two-way, or one-way == -1.
         if ojint(shpfeat['properties']['one_way']) != 1:
            # Cache backward edge
            dstep = route_step.Wrap(rstep)
            #
            dstep.forward = False
            dstep.dir_entry = geometry.v_dir(point_fin, point_fin2)
            dstep.dir_exit = geometry.v_dir(point_beg2, point_beg)
            #
            self.graph_add_weighted_edge(dstep,
                                         rstep.fin_node_id,
                                         rstep.beg_node_id,
                                         **edge_weights)

         self.graph_undi.add_edge(rstep.beg_node_id,
                                  rstep.fin_node_id,
                                  key=rstep.byway_stack_id)

      # else, edge_weights is empty, meaning this edge is impassable
      #       in both directions.

   # ***

   #
   def load_make_graph_remove_old(self, old_byway):

      # This fcn. called by add_byway_updated, when we're adding and removing
      # nodes between two revisions.

      try:
         old_steps = self.step_lookup[old_byway.stack_id]
         self.load_make_graph_remove_old_steps(old_byway, old_steps)

         # YOU'VE BEEN WARNED: Since Python does not release memory, if you
         # let the route finder run for a long, long time, you might want to
         # consider seeing if its memory consumption just grows and grows.
         # See: check_services_memory_usages, in the daily.runic.sh cronjob.
         #      (for now, cron merely complains when memory usage climbs).
         del self.step_lookup[old_byway.stack_id]

      except KeyError:
         # This fcn. is called during update, so this means a user saved a new
         # byway to the database.
         log.verbose('_graph_remove_old: no old byway: %s' % (old_byway,))
         pass

   #
   def load_make_graph_remove_old_steps(self, old_byway, old_steps):
      #log.debug('_graph_remove_old: old_steps: %s' % (old_steps,))
      for old_step in old_steps:
         try:
            old_bid = old_step.beg_node_id
            old_eid = old_step.fin_node_id
            try:
               self.graph.remove_edge(old_bid, old_eid, key=old_byway.stack_id)
            except networkx.NetworkXError, e:
               # E.g., "The edge 1237961-1237962 not in graph."
               # Should be a one-way.
               #log.debug('remove_old_stps: no fwd edge: %d / %d -> %d / %s'
               #          % (old_byway.stack_id, old_bid, old_eid, old_step,))
               pass
            try:
               self.graph.remove_edge(old_eid, old_bid, key=old_byway.stack_id)
            except networkx.NetworkXError, e:
               # Should be a one-way.
               #log.debug('remove_old_stps: no rwd edge: %d / %d -> %d / %s'
               #          % (old_byway.stack_id, old_eid, old_bid, old_step,))
               pass
            #
            try:
               self.graph_undi.remove_edge(old_bid, old_eid,
                                           key=old_byway.stack_id)
            except networkx.NetworkXError, e:
               pass

            # MAYBE: Also maintain self.favtree_members?
            #        But how easy is that?

         except Exception, e:
            log.warning('_graph_remove_old: failed: old_step: %s / e: %s'
                        % (old_step, str(e),))
            pass

   # ***

   #
   def graph_add_weighted_edge(self, dstep, beg_node_id, fin_node_id,
                                     **edge_weights):

      # If we always wanted to use the same type of edge weight, we could
      # call, e.g.,
      #   self.graph.add_weighted_edges_from(
      #      [(beg_node_id, fin_node_id, edge_weight,),],
      #      rstep=dstep)
      # But we want to support a few different types of weights without
      # instead having to build a separate graph for each weight type.
      # Fortunately, networkx lets us add attributes to each edge, and
      # when we compute the shortest path, we can specify with attribute
      # to use as the edge weight.

      # The add_weighted_edges_from assigns key values 0, 1, 2, ..., etc.,
      # as you add edges; you cannot specify a key like you can with the
      # other add-edge(s) functions.
      #
      #   self.graph.add_weighted_edges_from(
      #      [(beg_node_id, fin_node_id, edge_weights['wgt_len'],),],
      #      key=edge_weights['byway_stack_id'], rstep=dstep, **edge_weights)
      #
      edge_weights['rstep'] = dstep
      self.graph.add_edges_from(
         [(beg_node_id,                    # Networkx's "node u"
           fin_node_id,                    # Networkx's "node v"
           edge_weights['byway_stack_id'], # The key (byway stack_id)
           edge_weights),])                # Attributes dictionary

   #
   @staticmethod
   def get_weights(rstep, shpfeat):

      # If the edge is impassable, don't add it to the network.
      # (We could instead choose a Really Big edge weight, but
      # it makes more sense just not to include the edge.)
#      if (   ('closed'          in rstep.tagged)
#          or ('prohibited'      in rstep.tagged)
#          or ('is_disconnected' in rstep.tagged)
      if (   (rstep.tagged.intersection(
               byway.Geofeature_Layer.controlled_access_tags))
          or (rstep.byway_geofeature_layer_id
               in byway.Geofeature_Layer.controlled_access_gfids)):
         # The edge is impassable.
         edge_weights = None
      else:
         edge_weights = Trans_Graph.get_weights_passable(rstep, shpfeat)

      return edge_weights

   #
   @staticmethod
   def get_weights_passable(rstep, shpfeat):

      edge_weights = {}

      try:
         wgt_len = float(shpfeat['properties']['geom_len'])
      except KeyError:
         wgt_len = geometry.xy_line_len(shpfeat['geometry']['coordinates'])
      # Some of the NetworkX graph search algorithms prefer whole numbers,
      # rather than floats, so we'll round all of our results. We could
      # also scaling the length weight, say, by multiplying it by 100,
      # or we could just make sure not to multiply this initial weight by
      # anything less than 1, so that our granularity is at least as good
      # as a meter. That is, you can't really compare two 0.4 meter long
      # line segments, or maybe you can: suppose one is rated a 4, so it's
      # weight is round(0.4 * 1, 0) ==> 0, and the other segment is rated
      # a 3, so it's weight is round(0.4 * 2.0) ==> 1. Anyway... no need
      # to scale up.

      # The most basic edge weight: the length of the road segment.
      if 'len' in Trans_Graph.weights_enabled:
         # NOTE: We don't need this in the lookup, since it's the default...
         edge_weights['wgt_len'] = wgt_len

      # The classic edge weight: average user rating or calculated bikeability.
      if 'rat' in Trans_Graph.weights_enabled:
         try:
            # There are lots of user ratings fields.
            #  'rtng_gnric'   Either 'rtng_mean' or 'rtng_ccpx'
            #  'rtng_mean'    Avg. user rating; rtng_gnric is this
            #                  unless byway not rated by any users
            #  'rtng_bsir'    Bicycle Safety Index Rating
            #                  values: 1 (poor), 2, 3, 4 (good)
            #  'rtng_cbf7'    Chicago Bikeland Federation Alg #7
            #                  values: nr (0), red (1), yel (2), gr (3))
            #  'rtng_ccpx'    Some Scaled Cyclopath Rating...
            #                  values: 0.0 to 4.0.
            #  'user_rating'  N/a: for user who made Shapefile
            # The generic rating is the average user rating (0 to 4),
            # if one exists, or one of the calculated ratings (0 to 4).
            rtng_gnric = (
               max(0.0, min(float(shpfeat['properties']['rtng_gnric']), 4.0)))
         except KeyError:
            # In init_from_shpfeat, we warned the user that this field is
            # missing from the Shapefile. Here, just use an average rating.
            #
            # In CcpV1, an "average" rating, for which the rating cost is
            # equal to the distance cost (a penalty multiplier of 1.0) is
            # 10/3. With the static finder, the highest rating you'll find
            # is 4 (excellent), so maybe the average is just 2 (fair). But
            # it shouldn't matter; if the rating is missing for one feature,
            # it's probably missing for all features, all costs will simply
            # devolve to the line length, anyway.
            rtng_gnric = 2.0 # "Meh."
         # As discussed in a comment above, where rating_pows is defined, we
         # don't use a arithmetic sequence because then the differences between
         # successive ratings is uneven, e.g., excellent is half the cost of
         # good, but good is just 2/3 the cost of fair- so the scale tips more
         # in favor of better ratings, i.e., four excellents equals two goods,
         # but only three goods equals two fairs.
         #
         # Anyway, here's how to calculate the nasty arithmetic sequence:
         #  Generate a number btw. 1 and 5.
         #   rtng_scaler = (1.0 + (4.0 - rtng_gnric))
         #   rtng_gnric = wgt_len * rtng_scaler
         #   edge_weights['wgt_rat'] = rtng_gnric
         #
         # But we'll compute a range of powers instead, so that jumping between
         # two successive ratings always uses the same multipler.
         for pwr in Trans_Graph.rating_pows:
            # The 4-(rat/4) makes a number from 0 to 1, so the multiplier
            # ranges from 1 to pwr. Which can be stated, 1 mile of impassable
            # is the same cost as pwr miles of excellent, and the differences
            # between successive pairs of rating values is constant.
            multiplier = pow(pwr, ((4.0 - rtng_gnric) / 4.0))
            edge_weights['wgt_rat_%d' % (pwr,)] = wgt_len * multiplier

      # A new edge weight!
      #  "Willingness to travel further to use preferred segments."
      # (Well, new as of April, 2014, and maybe just newish, since [lb] added
      # a prefer-facilities option to the original finder, but it doesn't work
      # as well as this algorithm does, so we'll just call this edge weight
      # new. Also, you'd think we'd have figured this out long ago, right, I
      # mean, we're Cyclopath, our whole deal is finding routes, yet our legacy
      # route finder doesn't even implement edge weighting correctly (see notes
      # in routed_p1/route_finder.py about that), and only now has [lb] cracked
      # the nut on getting the prefer-facilities algorithm to work well. So,
      # yeah, Cyclopath is seven years old, and we finally figured out how best
      # to find routes!)
      if 'fac' in Trans_Graph.weights_enabled:
         try:
            frank = Trans_Graph.facil_type_rankweight[
                  shpfeat['properties']['bike_facil']]
         except KeyError:
            # Either: the 'bike_facil' field is missing (and we've warned the
            # developer when the transit graph was loaded), or the facil_type
            # isn't applied to this feature so it's not ranked.
            frank = None
         # The geofeature_layer_id can trump the bike facility value.
         if (rstep.byway_geofeature_layer_id
             # Nope: in byway.Geofeature_Layer.non_motorized_facils
             in byway.Geofeature_Layer.non_motorized_facils):
            frank = 0.0 # 0 is the value for trails, since pow(n, 0) = 1.
         if frank is not None:
            # This segment has a bike facility, or it is a bike facility.
            # We don't penalize the weight whatsoever for trails, and just
            # a teeny weeny amount for the "lesser" facilties.
            for val in Trans_Graph.burden_vals:
               g.assurt((val > 0) and (val < 100))
               penalty = 1.0 / (1.0 - (val / 100.0))
               # "Everybody take a Franklenator" -- Futurama
               #    https://www.youtube.com/watch?v=vy43iZCPeLI
               # "Noun: A weapon consisting of a stick or club with a
               # dangerous animal, most commonly a badger, tied to the
               # hitting end."
               #    www.urbandictionary.com/define.php?term=Franklinator
               franklinator = pow(penalty,
                   frank / Trans_Graph.facil_magic_denominator)
               edge_weights['wgt_fac_%d' % (val,)] = wgt_len * franklinator
         else:
            # This segment does not have a bike facility. Penalize it.
            # Burden modifier: the burden is percentage more you're willing the
            # route to be to include certain features. E.g., if the shortest
            # route is 20 miles and you're willing to bike 20% more, then the
            # route we figure out might be 4 miles of road and 20 miles of
            # trail. To figure out the multiplier to get this to work, consider
            #     short_road_length_segment * penalty + trail_length
            #       = all_road_length * penalty,
            #   and that
            #     short_road_length_segment + trail_length
            #       <= all_road_length * max_extra_biking_percentage
            # Where penalty = (1.0 / (1.0 - max_extra_biking_percentage))
            # E.g., If user willing to bike 90% further, penalty = 10
            #       because (penalty = 1/(1-.9) = 1/.1 = 10).
            # Also e.g., if user willing to bike 50% further, penalty = 2.
            for val in Trans_Graph.burden_vals:
               g.assurt((val > 0) and (val < 100))
               penalty = 1.0 / (1.0 - (val / 100.0))
               edge_weights['wgt_fac_%d' % (val,)] = wgt_len * penalty

      # A third edge weight type that combines ratings and facilities.
      # 2014.04.12: This is experimental. [lb] really has no idea what
      #             tripes this finder'll dream up.
      #             TEST: w 50th st and dupont ave s, mpls to gateway fountain
      #                   with the facility weight alone, I can get a number
      #                   of routes, so see how it works when combined with
      #                   the rating weight. At least four routes: lakes to
      #                   kenilworth for 65 and 90 burden, then blaisdell, then
      #                   lydale, and then colfax for the 10 burden and also
      #                   for fastest (shortest) route. I get chicago avenue
      #                   using the most bikeable setting and the p1 planner
      #                   because I've down-rated park and portland.
      if 'rac' in Trans_Graph.weights_enabled:
         # Crazy rating_x_facility weights.
         # 2014.04.17: For MN, memory consumption increases to 7 Gb from 3 Gb.
         for pwr in Trans_Graph.rating_pows:
            if pwr in Trans_Graph.weights_enabled_rac_rating:
               for val in Trans_Graph.burden_vals:
                  if val in Trans_Graph.weights_enabled_rac_burden:
                     # The two edge weights we're curious about are already
                     # scaled, so we can just average the two values. For,
                     # e.g., a 4-rated bike trail, (1 + 1) / 2 = 1. There
                     # might be a better algorithm to use, but this is [lb]'s
                     # first crack.
                     if pwr and val:
                        edge_weights['wgt_rat_%d_fac_%d' % (pwr, val,)] = (
                           edge_weights['wgt_rat_%d' % (pwr,)]
                           + edge_weights['wgt_fac_%d' % (val,)]) / 2.0

      rounded_weights = {}
      for alg_name, edge_weight in edge_weights.iteritems():
         edge_weight *= route_step.One.weight_multiplier
         rounded_weights[alg_name] = int(round(edge_weight, 0))

      # Implement personalized edge weights, a la the p1 planner.
      if set(['prat', 'pfac', 'prac',]).intersection(
                                          Trans_Graph.weights_enabled):
         # This is... silly? Set the weight as a callback fcn., not a number.
         # Also, this name is writ to route_parameters.p3_weight_attr.
         rounded_weights['wgt_pers_f'] = Trans_Graph.wgt_personalized_f

      return rounded_weights

   # ***

   rating_min = 0.5 # This is what CcpV1 always used...

   #
   @staticmethod
   def wgt_personalized_f(edge, pload):

      # edge is a dict, e.g., edge['wgt_*'] and edge['rstep'], the Wrap object.
      # The pload is our Problem object.
      usr_rating = pload.rating_func(edge['rstep'].rstep.byway_stack_id)
      if usr_rating < Trans_Graph.rating_min:
         # MAYBE: Use something other than maxint? Can we return a value
         # that tells the graph search to give up on this edge and anything
         # beyond?
         # What's a good value here? Probably not maxint? Above that, and
         # python converts to long, and [lb] wonders who networkx might react.
         #edge_weight = sys.maxint
         edge_weight = sys.maxint / 100000000.0 # 92233720368.54776
      else:
         # Scale the value like we do for 'rat' weight, but use 5.0 not 4.0.
         multiplier = 0.0
         if pload.route.p3_rating_pump:
            # MAGIC_NUMBER: Use a static var instead to indicate rating max+1?
            #               ... which handles tag bonuses, so now rating
            #               approacheth 5.
            multiplier += pow(pload.route.p3_rating_pump,
                              ((5.0 - usr_rating) / 5.0))
         if pload.route.p3_burden_pump:
            multiplier += 1.0 / (1.0 - (pload.route.p3_burden_pump / 100.0))
         if pload.route.p3_rating_pump and pload.route.p3_burden_pump:
            multiplier /= 2.0
         # The edge['wgt_len'] weight is already round and a factor of
         # route_step.One.weight_multiplier.
         edge_weight = edge['wgt_len'] * multiplier

      return int(round(edge_weight, 0))

   # ***

# ***


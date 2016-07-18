#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

"""

What say you, @alleyoopcat?

Where would you like to go today, @p6a?

@alleyoopcat Please take me to The Moon.
@alleyoopcat I'm leaving from Bike Polo.
@alleyoopcat But I'd also like to visit Hobo Camp and to see
@alleyoopcat What's the fastest route?
(Keywords: to and from and ?).

@p6a I've never heard of The Moon.
@alleyoopcat Have you heard of Pluto?

@p6a Okay, I know where you want to go.

@alleyoopcat I got bored waiting for you and decided to also go to the Big Oak Tree. Can we go?
(note that on error i have to ask the question again,
but I can amend my route and also combine to and ?).

(if the first to is obvious, it is the final destination,
otherwise ask?)

@p6a I'm working on it...
@p6a Bike Polo => Big Oak Tree => Hobo Camp => Pluto (~26 miles).

@alleyoopcat You're the best!
@p6a Shut up I know it baby!
(keywork: exclamation mark)

See: Natural Language Toolkit for Python.
http://nltk.googlecode.com/svn/trunk/doc/book/book.html

# ***

# Running Concorde and QSopt

# Note: We're solving an asymmetrical traveling salesperson problem.
#       [lb] is using the matrix format found in the TSLLIB examples.
#       I guess matrix is not the default, because without telling
#       Concorde the format, Concorde complains:
#         Problem Type: ATSP
#         Not a TSP problem
#         CCutil_gettsplib failed
# See ./concorde --help:
#   -N #  norm (must specify if dat file is not a TSPLIB file)
#         0=MAX, 1=L1, 2=L2, 3=3D, 4=USER, 5=ATT, 6=GEO, 7=MATRIX,
#         8=DSJRAND, 9=CRYSTAL, 10=SPARSE, 11-15=RH-norm 1-5, 16=TOROIDAL
#         17=GEOM, 18=JOHNSON
# Here, we use the MATRIX option.

cd /ccp/dev/cp/services/alleyoop
/ccp/opt/.downloads/concorde-tsp-co031219/TSP/concorde -N 7 atsp-easyfour.atsp

# ***

# Using ./ccp.py to get a route:

./ccp.py --py_host cycloplan.cyclopath.org --route --from 'gateway fountain' --to 'eagan, mn'

FIXME: Save route XML to file or somehow pass back here...

# ***

# Install MongoDB

# The mongodb docs say to import the public key used by the pkg mgmt sys,
# but I didn't do this:
#
# sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
# echo \
#   'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' \
#   | sudo tee /etc/apt/sources.list.d/mongodb.list
# sudo apt-get update
# sudo apt-get install mongodb-org

sudo apt-get install mongodb-server
sudo apt-get install python-pymongo python-pymongo-doc

# Either/or:
#sudo /etc/init.d/mongodb start
sudo service mongodb start

tail -n +0 -F /var/log/mongodb/mongodb.log


import pymongo
from pymongo import MongoClient
client = MongoClient('localhost', 27017)
# Same as:
#  client = MongoClient('mongodb://localhost:27017/')

db = client.alleyoopcat


"""

# This daemon runs the Alleyooooop*Cat service.
#
# USAGE: You probably want to start and stop this script with alleyoopctl.
#
# Alleyoopcat solves a simplified travelling salesperson problem (TSP).
#
# This scripts first solves handshake problem, which is a much simpler version
# of the travelling salesperson problem (tsp) -- we want to determine the best
# route between multiple destinations, or stops, but we want to solve the
# problem quicker than the tsp problem. The laziest form of tsp takes
# polynomial factorial time, or O(n!), whereas the handshake problem is
# essentially N-squared, or O(n^2), time (albeit it's n*(n+1)/2, so it's not
# quite so bad for small n).
#
# Basically, we compute the route (and distance) between each un-ordered pair
# of stops (handshake problem), and then we use the computed distances to find
# the best overall route (travelling salesperson problem). The latter is
# obviously a slow calculation but since we're just comparing single values,
# hopefully it won't be too slow. E.g., for 20 routes, there are 210 routes to
# compute (handshake) but there are 2432902008176640000 combinations of stops.
# However, if we use inclusion-exclusion or branch-and-bound, the latter can be
# reduced to 0(2^n) time, or 1048576 computations for 20 stops.
#
# The Cyclopath flashclient currently lets users enter multiple stops
# while planning a trip, but the application uses the order that the
# user specifies.
#
# So, for a route with 10 stops, flashclient computes nine routes.
#
# This is a lot simpler than the TSP problem -- for 10 stops, for example,
# we need to compute 45 routes (assuming we don't need to compute routes in
# opposing directions (i.e., assuming the graph is undirected)).
#
# The total number of distinct pairs that can be selected from n + 1 objects
# is known as "n plus one choose two" (the handshake problem), and is
# represented by the binomial coefficient,
#    (n + 1)
#    (  2  )
# which can be calculated (n(n+1))/2) (which is the sum of natural numbers from
# 1 to n). Each such number in the sequence produced by this algorithm is known
# as a triangular number.
#
# E.g., for 20 routes, there are 20*21/2 or 210 routes to compute.
#
# References:
#   https://en.wikipedia.org/wiki/Triangular_number
#   https://en.wikipedia.org/wiki/Travelling_salesman_problem
#   https://en.wikipedia.org/wiki/Branch_and_bound
#   https://en.wikipedia.org/wiki/Inclusion%E2%80%93exclusion
#
# Implementations:
#   You'll find a handful of TSP algorithms, such as http://openopt.org/TSP
#   and Concorde TSP Solver (a C library) but they're all quite complex (and
#   [lb] tried TSP and it seemed to give bad answers; see extensive notes in
#   auto_install/gis_compile.sh). The easiest TSP is a mashup using networkx:
#   while networkx doesn't do TSP (like, there's no tsp() call), it does enough
#   of the heavy lifting to make our part of the algorithm super simple.
#   (Though [lb] wonders if the time spent writing all these comments could
#   have been spent just writing his own algorithm and being done with it.)
#

script_name = 'Alleyoopcat Multiple-stop Route Finder'
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'

# ***

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../pyserver'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# *** Module globals
# FIXME: Make sure this always comes before other Ccp imports
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.WARNING
# FIXME: Make DEBUG the default on this and all services and make logcheck not
# look for 'em. I think it's more important to have a good trace when we
# release all this new code.
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
#conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)
# NOTE: Must manually configure the logger
# FIXME: It took me a few minutes to remember this... how to remind self when
# files need it? Like: ccp.py, routed, gwis_mod_python.
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('__alleyoop__')

# ***

import copy
import errno
import itertools
import networkx
try:
   import numpy
except ImportError:
   # This is only for testing so don't care.
   pass
import re
import select
import signal
import simplejson
import socket
import threading
import time
import traceback
import twitter
import urllib

# /export/scratch/ccp/opt/.downloads/python-twitter/twitter_test.py

from grax.item_manager import Item_Manager
from gwis.exception.gwis_error import GWIS_Error
from gwis.exception.gwis_warning import GWIS_Warning
from gwis.query_overlord import Query_Overlord
from item.feat import branch
from item.jobsq import work_item
from item.jobsq import work_item_step
from item.jobsq.job_action import Job_Action
from item.jobsq.job_status import Job_Status
from item.util import item_factory
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.mod_loader import Mod_Loader
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base
from util_.task_queue import Task_Queue
from util_.task_queue import Task_Queue_At_Capacity_Error
from util_.task_queue import Task_Queue_Complete_Error
import VERSION

# *** Debug switches

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 3
##debug_prog_log.debug_break_loop_cnt = 10

debug_skip_commit = False
#debug_skip_commit = True

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     )

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):
      Ccp_Script_Args.prepare(self)

   #
   def verify(self):
      verified = Ccp_Script_Args.verify(self)

# *** The Alleyoop Daemon

class Alleyoop(Ccp_Script_Base):

   #
   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # *** The 'go' method

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):
      time_0 = time.time()
      try:
         self.go_go()
      except Exception, e:
         log.error('Fatal error. Please debug!: %s' % (str(e),))
         raise
      finally:
         pass
      log.info('Service complete! Ran in %s'
               % (misc.time_format_elapsed(time_0),))

   #
   def go_go(self):

      pass

   # ***

   # *** Not used: brute_force_itertools. It's not any simpler than networkx to
   #               start looping, but once you're looping, it's more work for
   #               us to calculate path costs, and we end up short-circuiting
   #               more loops than not just to avoid paths with duplicate
   #               nodes.

   #
   @staticmethod
   def brute_force_itertools():

      min_path = []
      min_dist = 0.0

      # E.g., if we had five nodes, pass five arguments to itertools.
      # It'll return (1,1,1,1,1), (1,1,1,1,2), ..., (5,5,5,5,5).
      a = [1,2,3,4,5,]
      args = []
      for i in xrange(len(a)):
        args.append(a)
      num_paths = 0
      for element in itertools.product(*args):
         #print element
         num_paths += 1
         # The problem is: we still need a lookup of edge costs, and
         # itertools.product repeats nodes in each path... so it looks
         # like networkx is a better solution. Even though networkx
         # visits paths that don't visit all nodes, at least it doesn't visit
         # duplicates, and at least it can tell us the path and the edge costs.

      log.debug('brute_force_itertools: %d paths from %d nodes permutated'
                % (num_paths, len(a),))

   # ***

   # This algorithm computes the "almost" shortest hamiltonian path: we're not
   # dealing with a true hamiltonian cycle because we're not returning to the
   # start node. This algorithm uses networkx.all_simple_paths, which isn't
   # perfect but it's simple, clean, and gives us a nice loop to do our work
   # within.
   #
   # And thanks to Allison and The Muse Garden for this simple solution.
   #   http://themusegarden.wordpress.com/tag/networkx/
   # https://github.com/nelsonam/traveling_santa/blob/master/traveling_santa.py

   # Oh, blarney, we can do better yet! See the next section where [lb] tries
   # a third approach, using a custom-built generator.

   #
   @staticmethod
   def shortest_almost_hamiltonian(dir_graph, node_first, node_final):

      num_paths = 0

      distances = []

      # The networkx class is well writ: it returns a generator instead of a
      # collection of paths, meaning we won't do a big memory grab here.
      #
      # Set the cutoff to the number of nodes "to make sure we get out to the
      # ham. cycle". Mmmmm hammm.
      generator = networkx.all_simple_paths(
            dir_graph,
            source=node_first,
            target=node_final,
            cutoff=len(dir_graph))

      for path in generator:

         # Only looks at paths that visit all the nodes.
         if len(path) == len(dir_graph):
            distance = 0.0
            # Add up the edge weights.
            for i in range(0, (len(dir_graph)-1)):
               distance = distance + dir_graph[path[i]][path[i+1]]['weight']
            # Append to the list of all-node hamiltonians.
            distances.append((distance, path,))

         num_paths += 1

      # Find the path with the lowest distance/weight.
      min_path = []
      try:
         min_dist = distances[0]
      except IndexError:
         # No paths found.
         min_dist = -1.0

      for dist in distances:
          if dist[0] <= min_dist:
              min_dist = dist[0]
              min_path = dist[1]

      log.debug('%s has a distance of %s' % (min_path, min_dist,))

      log.debug('shortest_almost_hamiltonian: %d paths from %d nodes graphed'
                % (num_paths, len(dir_graph),))

   # ***

   # The generator code is awesomely thanks to Luka Rahne, via Stack Overflow:
   # http://stackoverflow.com/questions/6284396/permutations-with-unique-values

   #
   class Unique_Element:
      #
      def __init__(self, value, occurrences):
         self.value = value
         self.occurrences = occurrences

   #
   @staticmethod
   def perm_unique(elements):
      eset = set(elements)
      listunique = [
         Alleyoop.Unique_Element(i, elements.count(i)) for i in eset]
      u = len(elements)
      return Alleyoop.perm_unique_helper(listunique, [0] * u, u - 1)

   #
   @staticmethod
   def perm_unique_helper(listunique, result_list, d):

      if d < 0:
         yield tuple(result_list)
      else:
         for i in listunique:
            if i.occurrences > 0:
               result_list[d] = i.value
               i.occurrences -= 1
               for g in Alleyoop.perm_unique_helper(
                     listunique, result_list, d - 1):
                  yield g
               i.occurrences += 1

   #
   def shortest_hamiltonian_orig(self, dir_graph, node_first, node_final):

      num_calcs = 0
      num_paths = 0

# FIXME: MAGIC_NUMBER: How should we determine the best value here?
      #self.cheapest_limit = 6
      #self.cheapest_limit = 66
      self.cheapest_limit = 1
      # Make an array of the size we'll need.
      self.cheapest_paths = [None,] * self.cheapest_limit

      # Remove the endpoints from the hamiltonian calculation since we'll
      # always need to consider the edge cost between the first and second
      # nodes and between the final and second to last nodes.

      nodes = list(set(dir_graph.nodes()))
      nodes.remove(node_first)
      nodes.remove(node_final)

      sub_graph = dir_graph.subgraph(nodes)
      g.assurt(len(sub_graph) == (len(dir_graph) - 2))
      g.assurt(sub_graph.nodes() == nodes)

      generator = Alleyoop.perm_unique(nodes)

      for path in generator:

         # The generator generates reverse-ordered paths, e.g., we'd
         # get both (2,3,4,) and (4,3,2,) on the (2,3,4,) graph. But
         # since we're hogging the start and end node, we have to test
         # the start and end nodes both ways.
         #
         # And we have two choices:
         #
         #   Swap the first and final nodes. For (2,3,4,), if 1 and 5
         #   are the end nodes, we could first do 1-2-3-4-5 and then
         #   try 5-2-3-4-1, and then when we get (4,3,2,) we'd try
         #   1-4-3-2-5 and 5-4-3-2-1.
         #
         #   Or, we could try 1-2-3-4-5 and 5-4-3-2-1 for (2,3,4,)
         #   and 1-4-3-2-5 and 5-2-3-4-1 for (4,3,2,).

         valid = self.hamilton_len(dir_graph, node_first, node_final, path)
         num_paths += 1 if valid else 0

         # Reverse the path, including switching end nodes. The is the second
         # of the two options listed in the comment above. And perm_unique sent
         # us a tuple, so we have to convert it. And note that we don't bother
         # converting it back because hamilton_len doesn't care.
         path = list(path)
         path.reverse()
         valid = self.hamilton_len(dir_graph, node_final, node_first, path)
         num_paths += 1 if valid else 0

         num_calcs += 2

      num_found = 0
      for path in self.cheapest_paths:
         if path is not None:
            num_found += 1
      log.debug('shortest_hamiltonian: %d winners from %s paths from %d tries'
                % (num_found, num_paths, num_calcs,))

      # Rank the collection of lowest cost paths.
      # The paths are tuples: (distance, path,)
      self.cheapest_paths.sort(self.path_tuple_cmp)

      self.print_paths()

      return self.cheapest_paths

   #
   def hamilton_len(self, dir_graph, node_first, node_final, path):

      valid = None

      distance = None
      prev_node = None
      for this_node in path:
         if prev_node is None:
            g.assurt(not distance)
            from_node = node_first
            distance = 0
         else:
            from_node = prev_node
         try:
            distance += dir_graph[from_node][this_node]['weight']
# FIXME: This supercedes self.cheapest_limit
            if ((self.cheapest_paths[0] is not None)
                and (distance > self.cheapest_paths[0])):
               return None # Though might be False
         except KeyError, e:
            # This shouldn't happen, at least not for real Cyclopath routes.
            # Otherwise this happens when there's no edge between two nodes.
            # BREAKING MY RULE: [lb] is short-circuiting here just to maybe
            # possibly make things faster... but given O(n^2), fat chance!
            return None
         prev_node = this_node
      # Done with the first node and the nodes in the path; now do the final
      # node.
      if path is not None:
         try:
            distance += dir_graph[prev_node][node_final]['weight']
            if ((self.cheapest_paths[0] is not None)
                and (distance > self.cheapest_paths[0])):
               return False
         except KeyError, e:
            # There is no edge connecting these two nodes, so this path cannot
            # be travelled (though for Cyclopath this seems improbable).
            return None

# FIXME: If you've short-circuited, there are more permutations you can skip...

      for i in xrange(self.cheapest_limit):
         if ((self.cheapest_paths[i] is None)
             or (distance < self.cheapest_paths[i][0])):
            # Add this finalist to the collection of possible shortest paths.
            # Copy the path since the caller might reverse it and reuse it.
            # Note that list addition implicitly copy.copys other lists. Also
            # note that the caller sent us a tuple... so list() copies it, too.
            finalist = (distance, [node_first,] + list(path) + [node_final,],)
            self.cheapest_paths[i] = finalist
            return True

      return False

   # ***

   #
   def shortest_hamiltonian(self, dir_graph, node_first, node_final):

      num_calcs = 0
      num_paths = 0

# FIXME: MAGIC_NUMBER: How should we determine the best value here?
      #self.cheapest_limit = 6
      #self.cheapest_limit = 66
      #self.cheapest_limit = 1
      # Make an array of the size we'll need.
      #self.cheapest_paths = [None,] * self.cheapest_limit
      self.cheapest_limit = 16
      self.cheapest_paths = []
      self.cutoff_cost = None

      # Remove the endpoints from the hamiltonian calculation since we'll
      # always need to consider the edge cost between the first and second
      # nodes and between the final and second to last nodes.

      inner_nodes = list(set(dir_graph.nodes()))
      inner_nodes.remove(node_first)
      inner_nodes.remove(node_final)

      sub_graph = dir_graph.subgraph(inner_nodes)
      g.assurt(len(sub_graph) == (len(dir_graph) - 2))
      g.assurt(sub_graph.nodes() == inner_nodes)

      g.assurt(len(inner_nodes) > 1)
      # TODO: Gracefully fail otherwise.

      self.dir_graph = dir_graph
      self.node_first = node_first
      self.node_final = node_final
      self.inner_nodes = inner_nodes
      self.stats_endpaths = 0

#      import pdb;pdb.set_trace()

      running_path = [[0.0, node_first,],]
      self.iterate_hamiltonian(node_first, inner_nodes, running_path)

      num_found = 0
      for path in self.cheapest_paths:
         if path is not None:
            num_found += 1
      log.debug('shortest_hamiltonian: %d winners from %d tries'
                % (num_found, self.stats_endpaths,))

      # Rank the collection of lowest cost paths.
      # The paths are tuples: (distance, path,)
      self.cheapest_paths.sort(self.path_tuple_cmp)

      self.print_paths()

      return self.cheapest_paths

   #
   def iterate_hamiltonian(self, curr_node, remaining_nodes, running_path):

      for next_node in remaining_nodes:
         running_cost = (running_path[-1][0] + self.dir_graph[curr_node]
                                                   [next_node]['weight'])
         if ((self.cutoff_cost is not None)
             and (running_cost > self.cutoff_cost)):
            self.stats_endpaths += 1
            return
         running_path.append([running_cost, next_node,])
         if len(remaining_nodes) > 1:
            remaining = []
            for node in remaining_nodes:
               if next_node != node:
                  remaining.append(node)
            self.iterate_hamiltonian(next_node, remaining, running_path)
         else:
            # I.e., g.assurt(remaining_nodes[0] == next_node)
            self.stats_endpaths += 1
            # Last node of inner nodes. Second-to-last node overall.
            running_cost = (running_path[-1][0] + self.dir_graph[next_node]
                                                [self.node_final]['weight'])
            cnt_finalists = len(self.cheapest_paths)
            if ((self.cutoff_cost is None)
                or (cnt_finalists < self.cheapest_limit)
                or (running_cost <= self.cutoff_cost)):
               # Success!
               complete_path = ([x[1] for x in running_path]
                                + [self.node_final,])
               finalist = [running_cost, complete_path,]
               for i in xrange(cnt_finalists):
                  if running_cost <= self.cheapest_paths[i][0]:
                     self.cheapest_paths = (
                        self.cheapest_paths[:i]
                        + [finalist,]
                        + self.cheapest_paths[i+1:])
                     finalist = None
                     break
               if finalist is not None:
                  self.cheapest_paths.append(finalist)
               self.cutoff_cost = self.cheapest_paths[-1][0]

         running_path.pop()

   # ***

   #
   def path_tuple_cmp(self, x, y):
      if y is None:
         return True
      elif x is None:
         return False
      else:
         return x[0] < y[0]

   #
   def print_paths(self):
      print_limit = 16
      for path in self.cheapest_paths:
         if path is not None:
            log.debug('shortest_hamiltonian: dist. %s / %s'
                      % (path[0], path[1],))
         if not print_limit:
            break
         else:
            print_limit -= 1

# *** Test code / Making Fake Network Graphs

#
def __test_get_graph_01__():

   net_graph = [
      #
      (3, 0, .13,),
      (3, 1, .12,),
      (3, 2, .11,),
      #(3, 3, .01,), # node_first
      (3, 4, .01,),
      #
      (2, 0, .01,),
      (2, 1, .01,),
      #(2, 2, 999999999,),
      #(2, 3, 999999999,),
      (2, 4, .01,),
      #
      #(0, 0, 999999999,),
      (0, 1, .01,),
      (0, 2, .01,),
      #(0, 3, 999999999,),
      (0, 4, .01,),
      #
      (4, 0, .01,),
      (4, 1, .01,),
      (4, 2, .01,),
      #(4, 3, 999999999,),
      #(4, 4, 999999999,),
      #
      #(1, 0, 999999999,),
      #(1, 1, 999999999,), # node_final
      #(1, 2, 999999999,),
      #(1, 3, 999999999,),
      #(1, 4, 999999999,),
      ]
   node_first = 3
   node_final = 1

   dir_graph = networkx.DiGraph()

   # Add the first node. Even though other nodes can travel to it, since you
   # cannot travel away from it, networkx doesn't add it as a node like it does
   # the others.
   dir_graph.add_node(node_first)

   dir_graph.add_weighted_edges_from(net_graph)

   return dir_graph, node_first, node_final

#
def __test_get_graph_02__():

   net_graph = [
                    (0, 1, .01,), (0, 2, .01,), (0, 4, .01,), (0, 5, .01,), (0, 6, .01,),
      # 1 is the final node so it doesn't go anywhere.
      (2, 0, .01,), (2, 1, .01,),               (2, 4, .01,), (2, 5, .01,), (2, 6, .01,),
      (3, 0, .13,), (3, 1, .12,), (3, 2, .11,), (3, 4, .01,), (3, 5, .01,), (3, 6, .01,),
      (4, 0, .01,), (4, 1, .01,), (4, 2, .01,),               (4, 5, .01,), (4, 6, .01,),
      (5, 0, .08,), (5, 1, .07,), (5, 2, .06,), (5, 4, .21,),               (5, 6, .21,),
      (6, 0, .08,), (6, 1, .07,), (6, 2, .06,), (6, 4, .21,), (6, 5, .21,),
      ]
   node_first = 3
   node_final = 1

   dir_graph = networkx.DiGraph()
   dir_graph.add_node(node_first)
   dir_graph.add_weighted_edges_from(net_graph)
   return dir_graph, node_first, node_final

#
def __test_get_graph_03__(num_nodes):

   # 1.5*(cos(i)+sin(j)+1)**2
   # (i-j)**2 + 2*sin(i) + 2*cos(j)+1
   net_graph = (
      [(i, j, float(1.5 * (numpy.cos(i) + numpy.sin(j) + 1)**2),)
       for i in range(num_nodes) for j in range(num_nodes) if i != j])
   node_first = 3
   node_final = 1

   dir_graph = networkx.DiGraph()
   dir_graph.add_node(node_first)
   dir_graph.add_weighted_edges_from(net_graph)
   return dir_graph, node_first, node_final

# *** Test code / Deprecated (networkx)

#
def __test_networkx_try_01__():

   dir_graph, node_first, node_final = __test_get_graph_01__()
   Alleyoop.shortest_almost_hamiltonian(dir_graph, node_first, node_final)

# *** Test code / Deprecated (itertools.product)

#
def __test_itertools_try_01__():

   Alleyoop.brute_force_itertools()

#
def __test_cartesian_try_01__():

   # You'll also find a product-type fcn. in networkx.

   dir_graph, node_first, node_final = __test_get_graph_01__()

   graphed = networkx.cartesian_product(dir_graph, dir_graph)
   log.debug('test_cartesian:  once: cnt. graphed.nodes: %d' % (len(graphed),))

   graphed = networkx.cartesian_product(dir_graph, graphed)
   log.debug('test_cartesian: twice: cnt. graphed.nodes: %d' % (len(graphed),))

   graphed = networkx.cartesian_product(dir_graph, graphed)
   log.debug('test_cartesian: thrice: cnt graphed.nodes: %d' % (len(graphed),))

   graphed = networkx.cartesian_product(dir_graph, graphed)
   log.debug('test_cartesian: fource: cnt graphed.nodes: %d' % (len(graphed),))

# *** Test code / Less deprecated, or not at all (custom generator)

#
def __test_permutations_try_01__(aoop):

   """

   node_nums = [1, 2, 3, 4, 5,]
   generator = Alleyoop.perm_unique(node_nums)
   a = list(generator)

   #print(a)
   log.debug('__test_permutations_try_01__: %d paths from %d nodes permutated'
             % (len(a), len(node_nums),))

   dir_graph, node_first, node_final = __test_get_graph_01__()
   aoop.shortest_hamiltonian_orig(dir_graph, node_first, node_final)

   dir_graph, node_first, node_final = __test_get_graph_02__()
   aoop.shortest_hamiltonian_orig(dir_graph, node_first, node_final)

   dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=7)
   aoop.shortest_hamiltonian_orig(dir_graph, node_first, node_final)

   dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=10)
   aoop.shortest_hamiltonian_orig(dir_graph, node_first, node_final)

   """

   # MAYBE: To speed this up, you could use multiple cores but divvying up
   #        the problem. But each core can at most reduce time by one-half,
   #        so there's still an upper bound to what's feasible.
   #        But each new node seems to add a factor of 10 complexity...
   #
   # I tested with self.cheapest_limit = 66 on my one-core Fedora:
   #
   # 10 nodes: 66 winners / 7801 paths / 80640 tries / 0.04 mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=10)
   # 11 nodes: 66 winners / 12192 paths / 725760 tries / 0.41 mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=11)
   # 12 nodes: 66 winners / 17053 paths / 7257600 tries / 4.08 mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=12)
   # 13 nodes: 66 winners /  paths /  tries /  mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=13)
   # 14 nodes: 66 winners /  paths /  tries /  mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=14)
   # 15 nodes: 66 winners /  paths /  tries /  mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=15)
   #
   # Note that self.cheapest_limit = 1 does not change it that much:
   #
   # 12 nodes:  1 winners / 17053 paths / 7,257,600 tries / 3.97 mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=12)
   #
   # Let's add a short-circuit to the loop and give up if the path is too long.
   #
   # 12 nodes:  1 winners / 17053 paths / 7,257,600 tries / 1.8 mins.
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=12)
   #
   # Okay, this time I wrote my own iterating fcn.
   #
   # 10 nodes:  1 winners /  paths /  tries /  mins.
   #dir_graph, node_first, node_final = __test_get_graph_01__()
   #dir_graph, node_first, node_final = __test_get_graph_02__()
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=5)
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=6)
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=7)
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=8)
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=9)
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=10)
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=11)
   # 259645 tries / 350792 tries / 0.0 mins.:
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=12)
   # num_nodes=13 / 0.2 mins (2,116,769 tries):
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=13)
# LIMIT IS 14? maybe test 15 on server, but server is only a few magnitudes
# faster than my dev machine. Maybe you could run timing tests on individual
# calls in iterate_hamiltonian -- i.e., maybe [].append() is costly
# or maybe replace self.dir_graph[curr_node][next_node]['weight']
   # num_nodes=14 / 3.2 mins (34,409,785 tries):
   #dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=14)
   ## num_nodes=15 /  mins:
   ##dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=15)
   ## num_nodes=16 /  mins:
   ##dir_graph, node_first, node_final = __test_get_graph_03__(num_nodes=16)
   #
   aoop.shortest_hamiltonian(dir_graph, node_first, node_final)

# *** Main thunk

#
if (__name__ == '__main__'):

   aoop = Alleyoop()
   aoop.go()

   # Uncomment this to test. Since we don't have a test framework...
#   sys.exit()


   time_0 = time.time()

   """
   # The networkx library is neat but overkill.
   __test_networkx_try_01__()

   __test_itertools_try_01__()

   __test_cartesian_try_01__()
   """

   __test_permutations_try_01__(aoop)

   log.info('Testing complete! Ran in %s'
            % (misc.time_format_elapsed(time_0),))


# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: If you make changes to this file, be sure to restart Mr. Do!

import conf
import copy
import g
from gwis.query_overlord import Query_Overlord
from item.feat import track
from item.feat import branch
from item.feat import byway
from item import geofeature
from item.feat import route
from item.feat import route_step
from item.util.item_query_builder import Item_Query_Builder
from item.util import revision
import math
from util_ import db_glue
from util_ import gml
from util_ import geometry
from util_ import rect
from datetime import datetime
from datetime import timedelta
import scipy.stats as stats
import time

#from lxml import etree
#import os
#import sys
#import uuid

from utils.work_item_job import Work_Item_Job

__all__ = ('Conflation',)

log = g.log.getLogger('conflation')

# Defaults and constants

# Highest degree of byway graph
# Relative probability of backtracking from a block rather than going forward
BACKTRACKING_PROB = 1E-25
#TODO: figure out highest degree of graph (for now, I will assume it is 8)
GRAPH_DEGREE_MAX = 8
eps = 1.0/(GRAPH_DEGREE_MAX + 1)

class Conflation(Work_Item_Job):

   __slots__ = (
      'qb',
      'new_byways',
      'track',
      'fresh_id',
      'point_blocks',
      'final_path',
      'obs',
      )

   # *** Constructor

   def __init__(self, wtem, mr_do):
      Work_Item_Job.__init__(self, wtem, mr_do)
      self.qb = None

   # -- ENTRY POINT -----------------------------------------------------------

   #
   @staticmethod
   def process_request(wtem, mr_do):
      conf = Conflation(wtem, mr_do)
      conf.process_request_()

   # -- COMMON ----------------------------------------------------------------

   #
   def job_cleanup(self):
      if self.qb is not None:
         self.qb.db.close()
         self.qb = None
      Work_Item_Job.job_cleanup(self)

   #
   def setup_qbs(self):

      username = self.wtem.created_by

      db = db_glue.new()

      if self.wtem.revision_id is None:
         rev = revision.Current()
      else:
         rev = revision.Historic(self.wtem.revision_id, allow_deleted=False)

      (branch_id, branch_hier) = branch.Many.branch_id_resolve(db, 
                           self.wtem.branch_id, branch_hier_rev=rev)
      if not branch_hier:
         raise Exception(
            'Branch with stack_id %d not found in database at %s.'
            % (self.wtem.branch_id, rev.short_name(),))

      self.qb = Item_Query_Builder(db, username, branch_hier, rev)

      self.qb.item_mgr = self.qb.item_mgr

      Query_Overlord.finalize_query(self.qb)

   # -- ALL STAGES ------------------------------------------------------------

   #
   def make_stage_lookup(self):
      self.stage_lookup = [
         self.do_process_input,
         self.do_conflation,
         self.do_build_output,
         self.job_mark_complete,
         ]

   # -- STAGE 1 ---------------------------------------------------------------

   #
   def do_process_input(self):

      self.stage_initialize('Processing input')

      self.setup_qbs()

      log.info('** INPUT *******************')
      log.info(' track_id = %d' % (self.wtem.track_id,))
      log.info(' revision_id = %s' % (self.wtem.revision_id,))
      log.info(' cutoff_distance = %d' % (self.wtem.cutoff_distance,))
      log.info(' distance_error = %s' % (self.wtem.distance_error,))
      log.info('****************************')

      self.qb.filters.include_item_aux = True
      tracks = track.Many()
      geofeature.Many.search_by_stack_id(tracks, self.wtem.track_id, self.qb)
      if len(tracks):
         self.track = tracks[0]
      else:
         raise Exception('Track not found or access denied.')
      self.fresh_id = 0

      self.new_byways = list()
      self.point_blocks = {}


   # -- STAGE 2 ---------------------------------------------------------------

   #
   def do_conflation(self):
      '''Viterbi algorithm'''

      now = time.time()
      self.stage_initialize('Conflating track')

      # Observations (track points)
      obs = [(float(tp.x), float(tp.y), tp.timestamp,)
             for tp in self.track.track_points]
      self.sanitize(obs)
      self.fetch_byways(obs)

      # List of dicts mapping an observation index and a byway step to the
      # composite probability that observation came from that byway
      V = [{}]
      # List of dicts mapping observation index and byway ID to the most likely
      # path (list of Steps) leading to that byway in the current iteration
      path = [{}]
      # List of lists giving the IDs of the byway visited at each step.
      visited_ids = [[]]

      # Get nearby blocks
      nearby_byways = self.get_nearby_blocks(obs[0])
      # If there are no nearby blocks, create one.
      if (len(nearby_byways) == 0):
         bounds = self.new_block_bounds(obs, 0)
         block = self.create_new_block(obs, bounds)
         nearby_byways.append(block)

      # We use this to keep track of which is the current best result
      # (byway_meta, probability)
      max_result = [(None, 0,),]

      def initialize(blocks):
         # Initialize when t == 0
         for b in blocks:
            # one for each direction (forward and backward)
            V[0]['f' + str(b.stack_id)] = self.emit_p(b, obs[0])
            V[0]['b' + str(b.stack_id)] = self.emit_p(b, obs[0])
            visited_ids[0].append(b.stack_id)
            path[0]['f' + str(b.stack_id)] = [Step(b, b.nid1, b.nid2),]
            path[0]['b' + str(b.stack_id)] = [Step(b, b.nid2, b.nid1),]
            max_result[0] = (b, V[0]['f' + str(b.stack_id)],)

      initialize(nearby_byways)

      # Run Viterbi for t > 0
      progress = 0
      t = 1
      while t < len(obs):
         # Latest entry in V maps blocks to their probability of being the true
         # location of this observation
         V.append({})
         path.append({})
         visited_ids.append(list())
         current_prog = math.floor(t * 100 / len(obs))
         if (current_prog > progress):
            progress = current_prog
            self.stage_work_item_update(stage_progress=progress)
         
         # Get the blocks that could have produced this observation
         nearby_blocks = self.get_nearby_blocks(obs[t])
         candidate_steps = list()
         # For each nearby block, add it to candidate_blocks if it is connected
         # to the end of any of the possible paths from the previous iteration
         for y in nearby_blocks:
            step = Step(y, y.nid1, y.nid2)
            for prev_id in V[t-1].keys():
               if self.trans_p(path[t-1][prev_id][-1], step) > 0:
                  candidate_steps.append(step)
                  break
            step = Step(y, y.nid2, y.nid1)
            for prev_id in V[t-1].keys():
               if self.trans_p(path[t-1][prev_id][-1], step) > 0:
                  candidate_steps.append(step)
                  break

         # If there are no nearby blocks, or all nearby blocks have a
         # transition probability of 0, create a new block and rewind Viterbi
         # to the first observation where the new block or connected blocks had
         # any emission probability
         if (len(candidate_steps) == 0):
            bounds = self.new_block_bounds(obs, t, visited_ids[t-1])
            blocks = list()
            fixed = False
            if (bounds[0] == bounds[1]):
               main_ob = obs[bounds[0]]
               # all we need is to create an intersection
               nearby = self.get_nearby_blocks(main_ob,
                                               self.wtem.distance_error)
               # Check if there are endpoints of new blocks nearby, If so,
               # extend and connect
               for b in nearby:
                  if (not b.stack_id in visited_ids[t-1]):
                     points = gml.flat_to_xys(b.geometry_wkt)
                     if (dist(main_ob, points[0])
                        < self.wtem.distance_error):
                        self.continue_block(b, -1)
                        fixed = True
                     elif (dist(main_ob, points[-1])
                        < self.wtem.distance_error):
                        self.continue_block(b, 1)
                        fixed = True
                     elif (self.create_intersection(b, main_ob)):
                        fixed = True
                        break
                     else:
                        continue
                     # Remove the old split block since its geometry has changed
                     for bwy in self.new_byways:
                        if bwy.stack_id == b.stack_id:
                           self.new_byways.remove(bwy)
                           break
                     # save modified block
                     self.new_byways.append(b)
               blocks.extend(self.get_connected_blocks(
                  self.get_nearest_block(main_ob,visited_ids[t-1])))
            if (not fixed):
               new_block = self.create_new_block(
                              obs, bounds, visited_ids[t-1])

               blocks = self.get_connected_blocks(new_block)
               blocks.append(new_block)
            emission = False
            for index in range(0, len(obs)-1):
               for b in blocks:
                  if (self.dist_ob_block(obs[index], b)[0]
                      < self.wtem.cutoff_distance):
                     emission = True
                     break
               if (emission):
                  break
            t = index
            # If rewinding to the beginning, reset the data structures
            if t > 0:
               del V[t:]
               del path[t:]
               del max_result[t:]
               del visited_ids[t:]
            else:
               V = [{}]
               path = [{}]
               max_result = [(None, 0,),]
               visited_ids = [[]]
               initialize(self.get_nearby_blocks(obs[0]))
               t = 1
            continue

         fix_bool = True
         max_last = (None, 0,)
      
         # Iterate over all possible blocks for this observation
         for candidate in candidate_steps:
            direction = 'f'
            if (candidate.forward_node == candidate.bywaymeta.nid1):
               direction = 'b'
            candidate_id = direction + str(candidate.bywaymeta.stack_id)

            # Select the block that most probably would have preceded this
            # block and the probability
            # of that path
            (prob, state,) = max(
               [(V[t-1][prev_id]
                 * self.trans_p(path[t-1][prev_id][-1], candidate)
                 * self.emit_p(candidate.bywaymeta, obs[t]),
                 prev_id,)
                for prev_id in V[t-1].keys()])

            # Save the probability of this block if higher than 0
            if (prob > 0):
               V[t][candidate_id] = prob
               # Keep track of the last really close blocks at this point
               if ((not candidate.bywaymeta.stack_id in visited_ids[t])
                   and (candidate.bywaymeta.dist <= self.wtem.distance_error)):
                  visited_ids[t].append(candidate.bywaymeta.stack_id)

            # Save the most likely path leading to this block
            path[t][candidate_id] = path[t-1][state] + [candidate]

            if (prob > max_last[1]):
               max_last = (candidate_id, prob)
            if (prob > (10**-20)):
               fix_bool = False
      
         if (len(visited_ids[t]) == 0) and (t > 0):
            visited_ids[t] = visited_ids[t-1]

         if (max_last[1] > 0):
            max_result.append(max_last)
         else:
            max_result.append(max_result[t-1])
      
         # If all values are too small, make bigger (does not affect
         # final results, which are used for comparison and not in an
         # absolute way)
         if fix_bool and (max_last[1] > 0):
            multiplier = round(1 / max_last[1])
            for k in V[t].keys():
               V[t][k] = V[t][k] * multiplier

         # Break if the algorithm did not find any possible blocks (should not
         # happen if we are adding new blocks)
         if (max_last[1] <= 0):
            break
         t += 1

      log.debug('Finished Viterbi!')
      log.debug('Time for conflation: %s' % (str(time.time() - now),))
      self.final_path = path[t-1][max_result[-1][0]]
      self.obs = obs
      self.stage_work_item_update(stage_progress=100)

   # -- STAGE 3 ---------------------------------------------------------------

   #
   def do_build_output(self):

      self.stage_initialize('Building output')

      ride = self.create_ride(self.final_path, self.obs)

      # store results in db
      for i in xrange(0, len(ride.rsteps)):
         step = ride.rsteps[i]
         is_modified = False
         is_new = False
         if (step.byway_stack_id <= 0):
            is_new = True
            is_modified = True
         if ((step.beg_node_id <= 0) or (step.fin_node_id <= 0)):
            is_modified = True
         split_id_str1 = ''
         split_id_str2 = ''
         if (step.split_from_stack_id is not None):
            split_id_str1 = ', split_from_stack_id'
            split_id_str2 = ',' + str(step.split_from_stack_id)
         sql = (
            """
            INSERT INTO conflation_job_ride_steps 
               (job_id,
                byway_stack_id,
                byway_geofeature_layer_id,
                step_number,
                geometry,
                beg_node_id,
                fin_node_id,
                step_name,
                forward,
                beg_time,
                fin_time,
                is_modified,
                is_new
                %s)
            VALUES
               (%d, %d, %d, %d, '%s', %d, %d,
                '%s', %s, '%s', '%s', %s, %s
                %s)
            """ % (split_id_str1,
                   self.wtem.system_id,
                   step.byway_stack_id,
                   step.byway_geofeature_layer_id,
                   i,
                   step.geometry,
                   step.beg_node_id,
                   step.fin_node_id,
                   step.step_name,
                   step.forward,
                   step.beg_time,
                   step.fin_time,
                   is_modified,
                   is_new,
                   split_id_str2))

         self.qb.db.transaction_begin_rw()
         self.qb.db.sql(sql)
         self.qb.db.transaction_commit()

   # ***

###############################################################################
# Utils
###############################################################################

   #
   def fetch_byways(self, obs, max_dist=None):

      if max_dist is None:
         max_dist = self.wtem.cutoff_distance

      # Number of observations to use in a viewport (used to improve
      # algorithm speed)
      num_viewport = 50

      for t in range(0, len(obs)):
         if (t % num_viewport) == 0:
            # Grab the next set of blocks
            v_obs = [(obs[n][0], obs[n][1])
                     for n in range(t, min(len(obs),t + num_viewport))]
            viewport = ObsViewport(v_obs, self.wtem.cutoff_distance)
            self.qb.viewport.include = viewport
            byways = byway.Many()
            byways.search_for_items(self.qb)

         ob_key = (str(obs[t][0]) + ',' + str(obs[t][1]))

         byways_meta = list()
         for b in byways:
            dist, dist_nid1, dist_nid2 = self.dist_ob_block(obs[t], b)
            if (dist < max_dist):
               byways_meta.append(BywayMeta(b.stack_id,
                                            b.name,
                                            b.beg_node_id,
                                            b.fin_node_id,
                                            dist,
                                            dist_nid1,
                                            dist_nid2,
                                            b.geometry_wkt,
                                            b.geometry_svg,
                                            b.geofeature_layer_id))

         self.point_blocks[ob_key] = byways_meta

   #
   def get_nearby_blocks(self, ob, max_dist=None, include=None, ignore=None):

      if max_dist is None:
         max_dist = self.wtem.cutoff_distance

      ob_key = (str(ob[0]) + ',' + str(ob[1]))
      byways_meta = list()
      if (not ob_key in self.point_blocks.keys()):
         self.fetch_byways([ob])
      for b in self.point_blocks[ob_key]:
         if (include is not None):
            if (not b.stack_id in include):
               continue
         if (ignore is not None):
            if (b.stack_id in ignore):
               continue
         if ((b.dist < max_dist)
             and (not (b.stack_id
                       in [new.stack_id for new in self.new_byways]))):
            byways_meta.append(b)
      for b in self.new_byways:
         if (include is not None):
            if (not b.stack_id in include):
               continue
         if (ignore is not None):
            if (b.stack_id in ignore):
               continue
         dist, dist_nid1, dist_nid2 = self.dist_ob_block(ob, b)
         if (dist < max_dist):
            b.dist = dist
            b.dist_nid1 = dist_nid1
            b.dist_nid2 = dist_nid2
            byways_meta.append(b)

      return byways_meta

   #
   # Returns true if there is a block within 'distance' of the given
   # observation.
   #
   def is_near_block(self, ob, distance, include=None, ignore=None):

      nearby_blocks = self.get_nearby_blocks(ob, distance)

      if (len(nearby_blocks) == 0):
         return False

      elif ((include is None) and (ignore is None)):
         return True

      for b in nearby_blocks:
         if (ignore is not None):
            if (b.stack_id in ignore):
               # Ignore this byway
               continue
         if include is None:
            # We found a block that was not ignored and there is no requisite
            # for including blocks.
            return True
         else:
            # The block must be in the given list
            if (b.stack_id in include):
               return True

      # Nothing found.
      return False

   #
   def get_fresh_id(self):
      self.fresh_id -= 1
      return self.fresh_id

   #
   def get_nearest_block(self, ob, include=None, ignore=None):
      nearby_blocks = self.get_nearby_blocks(ob)
      if (len(nearby_blocks) == 0):
         return None
      else:
         closest = None
         for b in nearby_blocks:
            if (include is not None):
               if (not b.stack_id in include):
                  continue
            if (ignore is not None):
               if (b.stack_id in ignore):
                  continue
            if ((closest is None) or (b.dist < closest.dist)):
               closest = b
         return closest

   #
   # Returns the emission probability for block b and observation ob
   #
   def emit_p(self, b, ob):
      dist = self.dist_ob_block(ob, b)[0]
      return stats.norm.pdf(dist, 0, self.wtem.distance_error)

   #
   # Gets the distance between the given observation and the given block
   #
   def dist_ob_block(self, ob, b):
      geom = gml.flat_to_xys(b.geometry_wkt)
      result = dist_ob_line_segment(ob, geom[0], geom[1])
      for n in range(1, len(geom)-1):
         new_dist = dist_ob_line_segment(ob, geom[n], geom[n+1])
         if new_dist < result:
            result = new_dist
      return result, dist(ob, geom[0]), dist(ob, geom[-1])

   #
   # Returns the transition probability from the last step in a path 
   # to a new step
   #
   def trans_p(self, last_step, new_step):
      if (last_step.bywaymeta.stack_id == new_step.bywaymeta.stack_id):
         if (last_step.forward_node == new_step.forward_node):
            # Same step
            return eps
         else:
            # Reverse
            return eps * BACKTRACKING_PROB
      elif (new_step.backward_node == last_step.forward_node):
         # Connected, check to make sure node is actually close
         if (((new_step.backward_node == new_step.bywaymeta.nid1)
              and (new_step.bywaymeta.dist_nid1
                   < self.wtem.cutoff_distance))
             or ((new_step.backward_node == new_step.bywaymeta.nid2)
                 and (new_step.bywaymeta.dist_nid2
                      < self.wtem.cutoff_distance))):
            return eps
      return 0

   #
   # Get a list of blocks connected to the given block
   #
   def get_connected_blocks(self, block, node_id=None):
      self.qb.viewport.include = block
      byways = byway.Many()
      byways.search_for_items(self.qb)

      results = list()
      for b in byways:
         meta = BywayMeta(b.stack_id,
                          b.name,
                          b.beg_node_id,
                          b.fin_node_id,
                          0,
                          0,
                          0,
                          b.geometry_wkt,
                          b.geometry_svg,
                          b.geofeature_layer_id)
         if (is_connected(meta, block, node_id)
             and not b.stack_id in [new.stack_id for new in self.new_byways]):
            results.append(meta)
      for b in self.new_byways:
         if (is_connected(b, block, node_id)):
            results.append(b)

      return results

   # 
   def sanitize(self, obs):
      n = 0
      while n < len(obs)-1:
         total_distance = dist(obs[n],obs[n+1])
         if (total_distance > self.wtem.cutoff_distance):
            # We need intermediate points, as these are too far away
            
            # First, figure out how many points there should be
            num_points = math.ceil(total_distance/self.wtem.distance_error)
            
            # Second, add the new observations
            x_dif = obs[n+1][0] - obs[n][0]
            y_dif = obs[n+1][1] - obs[n][1]
            time_dif = (obs[n+1][2] - obs[n][2]).seconds
            last_x = obs[n][0]
            last_y = obs[n][1]
            last_time = obs[n][2]
            for i in range(1, num_points):
               last_x = last_x + x_dif/num_points
               last_y = last_y + y_dif/num_points
               last_time = last_time + timedelta(seconds=(time_dif/num_points))
               obs.insert(n+1,(last_x,last_y,last_time))
               n += 1
               
         n += 1

   #
   def create_ride(self, byways, obs):
      rd = route.One()
      for t in range(0, len(byways)):
         b = byways[t]
         if ((len(rd.rsteps) == 0)
             or not (rd.rsteps[-1].byway_stack_id == b.bywaymeta.stack_id)
             or not (rd.rsteps[-1].forward
                     == (b.forward_node == b.bywaymeta.nid2))):
            rs = route_step.One()
            rs.step_name = b.bywaymeta.name
            rs.byway_stack_id = b.bywaymeta.stack_id
            rs.geometry = b.bywaymeta.geometry_wkt
            rs.beg_node_id = b.bywaymeta.nid1
            rs.fin_node_id = b.bywaymeta.nid2
            rs.forward = (b.forward_node == b.bywaymeta.nid2)
            rs.byway_geofeature_layer_id = b.bywaymeta.gflid
            rs.split_from_stack_id = b.bywaymeta.split_from_stack_id

            # Add timestamps to blocks
            rs.beg_time = obs[t][2]
            if (len(rd.rsteps) > 0):
               # the previous block ends when this one starts
               rd.rsteps[-1].fin_time = obs[t][2]
            #rs.landmarks_compute(self.qb)
            rd.rsteps.append(rs)

      rd.rsteps[-1].fin_time = obs[t][2]
      return rd

###############################################################################
# Block Creation Utils
###############################################################################

   # Finds the indices in obs of the first and last observations to be used to
   # create a new byway around obs[index], making sure its starting point
   # connects to a block in 'include'
   def new_block_bounds(self, obs, index, include=None):
      # Find the first point for the new byway - keep moving backwards until we
      # find a byway that is less than the STD away
      first_point_index = self.find_endpoint_index(
         obs, index, -1, include=include)

      blocks_to_ignore = include

      # Find where the byway ends. Keep moving forward until we find a
      # byway that is less than the STD away.
      last_point_index = self.find_endpoint_index(
         obs, first_point_index, 1, ignore=blocks_to_ignore)

      return first_point_index, last_point_index


   #
   # Finds the index in obs of the new block's endpoint.
   #find_endpoint_index new_block_bounds
   def find_endpoint_index(self, obs, index, direction,
                           include=None, ignore=None):
      endpoint_index = index
      def in_bounds(index, direction):
         if (direction == -1):
            return index > 0
         else:
            return index < len(obs)-1

      while (in_bounds(endpoint_index, direction)):
         if (dist(obs[index], obs[endpoint_index]) > self.wtem.distance_error):
            # If we get far enough from the initial blocks, then we can once
            # again consider them
            ignore = None
         if not self.is_near_block(obs[endpoint_index],
                                   self.wtem.distance_error,
                                   include, ignore):
            endpoint_index += direction
         else:
            break
      return endpoint_index

   #
   # Creates a block around observation obs[first_point_index:last_point_index]
   #
   def create_new_block(self, obs, bounds, last_block_ids=None):
      first_point_index = bounds[0]
      last_point_index = bounds[1]

      new_block = BywayMeta(self.get_fresh_id(),
                            'New Block',
                            self.get_fresh_id(),
                            self.get_fresh_id(),
                            0,
                            0,
                            0,
                            None,
                            None,
                            1)

      new_block_points = []
      one_point = False
      for i in range(first_point_index, last_point_index+1):
         new_block_points.append((obs[i][0], obs[i][1]))
      if (len(new_block_points) == 1):
         # Single points need to be handled differently, because when connecting
         # to nearby blocks the point may be moved
         one_point = True
         new_block_points.append(new_block_points[0])
      new_block.geometry_wkt = (
         'LINESTRING(%s)' % (gml.wkt_coords_format(new_block_points),))

      # Extend byway both ways and split (or connect if end node near enough)
      ignore_ids = self.continue_block(new_block, -1, last_block_ids)
      if (one_point):
         fix_onepoint(new_block)
      ignore = [new_block.stack_id]
      if (one_point and ignore_ids is not None):
         ignore.extend(ignore_ids)
      self.continue_block(new_block, 1, ignore=ignore)
      
      if (one_point):
         fix_onepoint(new_block)

      # Smooth new byway geometry
      new_block.geometry_wkt, new_block.geometry_svg = (
         self.smooth_path(new_block.geometry_wkt))

      # Save byway to block cache
      #new_block.geometry_wkt = 'LINESTRING(%s)' % (
      #   gml.wkt_coords_format(new_block.geometry_wkt),)
      self.new_byways.append(new_block)

      return new_block

   #
   # Fixes geometry when dealing with connecting single points
   #
   def fix_onepoint(block):
      points = gml.flat_to_xys(block.geometry_wkt)
      if len(points) == 3:
         # remove extra point, we don't need it anymore
         del points[1]
         block.geometry_wkt = (
            'LINESTRING(%s)' % (gml.wkt_coords_format(points),))

   #
   # Connects a block to the nearest block in the given direction.
   #
   def continue_block(self, new_block, direction, last_block_ids=None,
                      ignore=None):
      if direction == -1:
         endpoint_index = 0
      else:
         endpoint_index = -1

      extending_points = gml.flat_to_xys(new_block.geometry_wkt)
      
      if ignore is None:
         ignore = [new_block.stack_id]
      # If there are no blocks nearby, no need to extend this block
      nearest_block = self.get_nearest_block(
         extending_points[endpoint_index],
         last_block_ids,
         ignore=ignore)
      if (nearest_block is None
          or nearest_block.dist > self.wtem.distance_error):
         return None
      ignore_ids = [nearest_block.stack_id]

      near_points = gml.flat_to_xys(nearest_block.geometry_wkt)

      # If we are close to an endpoint of another block, connect to it.
      if (dist(extending_points[endpoint_index], near_points[0])
          <= self.wtem.distance_error):
         # add blocks that connect to that endpoint to ignore list for next
         # block continuation
         ignore_ids.extend(
            [b.stack_id for b in self.get_connected_blocks(
               nearest_block, nearest_block.nid1)])
         if direction == -1:
            extending_points[0] = near_points[0]
            new_block.nid1 = nearest_block.nid1
         else:
            extending_points[-1] = near_points[0]
            new_block.nid2 = nearest_block.nid1
      elif (dist(extending_points[endpoint_index], near_points[-1])
            <= self.wtem.distance_error):
         # add blocks that connect to that endpoint to ignore list for next
         # block continuation
         ignore_ids.extend(
            [b.stack_id for b in self.get_connected_blocks(
               nearest_block, nearest_block.nid2)])
         if direction == -1:
            extending_points[0] = near_points[-1]
            new_block.nid1 = nearest_block.nid2
         else:
            extending_points[-1] = near_points[-1]
            new_block.nid2 = nearest_block.nid2
      else:
         # Get location of closest point on the nearest block and the expected
         # index in that block's sequence of points.
         point = self.proj_block(
            extending_points[endpoint_index], nearest_block)

         new_node, b1_id, b2_id = self.split_block(nearest_block, point)
         ignore_ids = [b1_id, b2_id]

         # Connect the current block to the intersection
         if direction == -1:
            extending_points.insert(0, point)
            new_block.nid1 = new_node
         else:
            extending_points.append(point)
            new_block.nid2 = new_node
      
      new_block.geometry_wkt = (
         'LINESTRING(%s)' % (gml.wkt_coords_format(extending_points),))
      return ignore_ids
      

   #
   # Returns closest point on a block and its expected index. This is based in
   # part on Flashclient code.
   #
   def proj_block(self, point, block):

      geom_str = ("ST_GeomFromText('%s', %d)"
                  % (block.geometry_wkt,
                     conf.default_srid,))

      rows = self.qb.db.sql(
         """
         SELECT
            ST_AsEWKT(
               ST_Line_Interpolate_Point(
                  %s, ST_Line_Locate_Point(
                        %s, ST_SetSRID(ST_Point(%s, %s), %d)))) AS geom
         """ % (geom_str, geom_str,
                point[0], point[1],
                conf.default_srid,))

      point = geometry.wkt_line_to_xy(rows[0]['geom'])[0]

      # Get block geometry
      block_points = gml.flat_to_xys(block.geometry_wkt)

      return point

   #
   # Smooths the path given.
   # Returns the smoothed path as a new list.
   #
   def smooth_path(self, geom_str):
      results = self.qb.db.sql(
         """
         SELECT
            ST_AsEWKT(ST_Simplify('%s', 5)) AS geom,
            ST_AsSVG(ST_Scale(ST_Simplify('%s', 5), 1, -1, 1), 0, %d)
               AS geom_svg
         """ % (geom_str, geom_str, conf.db_fetch_precision,))

      return results[0]['geom'], results[0]['geom_svg']
   
   #
   # Find blocks that intersect this block nearby and create an intersection
   #
   def create_intersection(self, b, main_ob):
      nearby = self.get_nearby_blocks(main_ob, self.wtem.distance_error)
      for b_near in nearby:
         if (b_near.stack_id != b.stack_id):
            # Check for geometry intersections
            intersections = intersections_byways(b, b_near)
            for i in intersections:
               if dist(i, main_ob) < self.wtem.distance_error:
                  # create intersection at this point
                  new_node = self.split_block(b, i)
                  self.split_block(b_near, i, new_node)
                  return True
      return False

   def split_block(self, b, intersection, new_node_id=None):
      points = gml.flat_to_xys(b.geometry_wkt)
      index = get_point_index(b, intersection)

      # Insert the new vertex into the byway
      points.insert(index, intersection)

      # Split the byway at the new vertex
      new_split_block = copy.deepcopy(b)
      new_split_block.stack_id = self.get_fresh_id()
      new_split_block.split_from_stack_id = b.stack_id
      geom1 = list()
      geom2 = list()
      # TODO: this can be done without a for loop
      for i in range(0,len(points)):
         if (i <= index):
            geom1.append(points[i])
         if (i >= index):
            geom2.append(points[i])

      if (new_node_id is None):
         new_split_block.nid2 = self.get_fresh_id()
      else:
         new_split_block.nid2 = new_node_id
      b.nid1 = new_split_block.nid2
   
      # Remove the old split block since its geometry has changed
      for block in self.new_byways:
         if block.stack_id == b.stack_id:
            self.new_byways.remove(block)
            break

      # Save the new split blocks to the byways list
      new_split_block.geometry_wkt = (
         'LINESTRING(%s)' % (gml.wkt_coords_format(geom1),))
      self.new_byways.append(new_split_block)
      b.geometry_wkt = (
         'LINESTRING(%s)' % (gml.wkt_coords_format(geom2),))
      self.new_byways.append(b)
      return b.nid1, new_split_block.stack_id, b.stack_id

###############################################################################
# Static Methods
###############################################################################

def get_point_index(b, point):
   points = gml.flat_to_xys(b.geometry_wkt)
   dist_best = float('inf')
   i_best = 0
   for i in range(0, len(points)-1):
      dist = dist_point_line(point, points[i], points[i+1])
      if ((dist < dist_best) and (dist is not None)):
         i_best = i
         dist_best = dist
   return i_best + 1

def intersections_byways(b1, b2):
   intersections = list()
   points1 = gml.flat_to_xys(b1.geometry_wkt)
   points2 = gml.flat_to_xys(b2.geometry_wkt)
   for i in range(1,len(points1)):
      for j in range(1, len(points2)):
         intersection = intersection_segments((points1[i-1], points1[i]),
                                              (points2[j-1], points2[j]))
         if (intersection is not None):
            intersections.append(intersection)
   return intersections
      
def intersection_segments(line1, line2):
   if opposite_side(line1, line2) and opposite_side(line2, line1):
      return intersection_lines(line1, line2)
   else:
      return None

def opposite_side(line1, line2):
   side_p1 = distance_indicative(line1[0], line1[1], line2[0])
   side_p2 = distance_indicative(line1[0], line1[1], line2[1])

   # If side_p1 and side_p2 are of the different sign then opp sides.
   return (side_p1 * side_p2 < 0)

# Return an indicative distance of point from line segment. Sign
# indicates the side and magnitude is an indication of the distance.
def distance_indicative(start, end, p):
   return ((end[1] - start[1]) * (start[0] - p[0]) -
           (end[0] - start[0]) * (start[1] - p[1]))

# Return intersection point of two lines.
def intersection_lines(line1, line2):
   u = (((line2[1][0] - line2[0][0]) * (line1[0][1] - line2[0][1])
         - (line2[1][1] - line2[0][1]) * (line1[0][0] - line2[0][0]))
        / ((line2[1][1] - line2[0][1]) * (line1[1][0] - line1[0][0])
           - (line2[1][0] - line2[0][0]) * (line1[1][1] - line1[0][1])))

   return (line1[0][0] + u * (line1[1][0] - line1[0][0]),
           line1[0][1] + u * (line1[1][1] - line1[0][1]))

# MAYBE: Move these to a utility class, like util_.geometry, util.misc, etc.

#
def dist(a, b):
   return math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2)

#
# Returns the distance between a point and a line. This is based in part on
# Flashclient code and takes perpendicularity into account.
#
def dist_point_line(pointA, point1, point2):
   # Return the dot product: ab . bc
   def dotx(a, b, c):
      ab = [b[0] - a[0], b[1] - a[1]]
      ac = [c[0] - a[0], c[1] - a[1]]
      return (ab[0] * ac[0] + ab[1] * ac[1])

   # check for non-perpendicularity
   if ((dotx(point1, point2, pointA) < 0)
       or (dotx(point2, point1, pointA) < 0)):
      return None

   # distance to _line_ defined by segment
   return (abs((point2[0]-point1[0])*(point1[1]-pointA[1])
               -(point1[0]-pointA[0])*(point2[1]-point1[1]))
            / dist(point1,point2))


#
def dist_ob_line_segment(o, l1, l2):
   def dist2(p1, p2):
      return ((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)

   length_squared = dist2(l1, l2)
   if length_squared == 0:
      return math.sqrt(dist2(o,l1))
   t = (((o[0]-l1[0]) * (l2[0]-l1[0]) + (o[1]-l1[1]) * (l2[1]-l1[1]))
         / length_squared)
   if (t < 0):
      return math.sqrt(dist2(o,l1))
   if (t > 1):
      return math.sqrt(dist2(o,l2))
   return math.sqrt(dist2(o, (l1[0] + t * (l2[0]-l1[0]),
                              l1[1] + t * (l2[1]-l1[1]))))

#
# Returns true if block b1 is connected to block b2
#
def is_connected(b1, b2, node_id=None):
   if (node_id is not None):
      return ((b1.nid1 == node_id
              or b1.nid2 == node_id)
              and (b2.nid1 == node_id
                   or b2.nid2 == node_id))
   else:
      return (b1.nid1 == b2.nid1
              or b1.nid1 == b2.nid2
              or b1.nid2 == b2.nid1
              or b1.nid2 == b2.nid2)


###############################################################################
# Helper Classes
###############################################################################

class BywayMeta(object):

   __slots__ = ('stack_id',
                'name',
                'nid1',
                'nid2',
                'dist',
                'dist_nid1',
                'dist_nid2',
                'geometry_wkt',
                'geometry_svg',
                'gflid',
                'split_from_stack_id',)

   def __init__(self, bid, name, nid1, nid2,
                dist, dist_nid1, dist_nid2,
                geo, geo_svg, gflid):
      self.stack_id = bid
      self.name = name
      self.nid1 = nid1
      self.nid2 = nid2
      self.dist = dist
      self.dist_nid1 = dist_nid1
      self.dist_nid2 = dist_nid2
      self.geometry_wkt = geo
      self.geometry_svg = geo_svg
      self.gflid = gflid
      self.split_from_stack_id = None

   #
   def sql_intersect(self, col):
      'Return a SQL WHERE snippet returning true when I intersect column col.'
      return ("""ST_Intersects(%s, ST_Expand(ST_GeomFromText('%s', %d),%d))"""
              % (col, self.geometry_wkt, conf.default_srid, 30,))

   def __str__(self):
      return str(self.stack_id)

#
# Viterbi path step
#
class Step(object):

   __slots__ = ('bywaymeta',
                'forward_node',
                'backward_node',)

   def __init__(self, bywaymeta, front, back):
      self.bywaymeta = bywaymeta
      self.forward_node = front
      self.backward_node = back

   def __str__(self):
      return ('(' + str(self.bywaymeta.stack_id) + ': '
              + str(self.forward_node)
              + ', ' + str(self.backward_node) + ')')

#
# Viewport made up of a string of observations
#
class ObsViewport(object):

   __slots__ = ('geometry_wkt',
                'cutoff',)

   def __init__(self, obs, cutoff_distance):
      if len(obs) > 1:
         self.geometry_wkt = (
            'LINESTRING(%s)' % (gml.wkt_coords_format(obs),))
      else:
         self.geometry_wkt = 'POINT(%s %s)' % (obs[0][0], obs[0][1],)
      self.cutoff = cutoff_distance

   #
   def sql_intersect(self, col):
      'Return a SQL WHERE snippet returning true when I intersect column col.'
      return ("ST_Intersects(%s, ST_Expand(ST_GeomFromText('%s', %d), %d))"
              % (col, self.geometry_wkt, conf.default_srid, self.cutoff,))

# ***

if (__name__ == '__main__'):
   pass


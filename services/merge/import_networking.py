# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

from decimal import Decimal
import os
import re
import sys
import time

import conf
import g

log = g.log.getLogger('import_init')

from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger

from merge.import_geowiki import Import_Geowiki
from merge.import_init import Feat_Skipped

class Import_Networking(Import_Geowiki):

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Geowiki.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Import_Geowiki.reinit(self)

   # ***

   #
   def audit_connectivity(self):

      log.info('Processing node_endpoints...')

      num_feats = len(self.ccp_fids) + len(self.agy_fids) + len(self.new_fids)

      prog_log = self.progr_get(log_freq=5000, loop_max=num_feats)

      # FIXME: Implement our helper fcn., node_cache_consume.
      log.warning('node_cache_consume: FIXME: Not Implemented.')

      ccp_fids = set()
      # Ug. I tried map() and lambda but failed. The hard way:
      for fid_set in self.ccp_fids.values():
         for fid_ in fid_set:
            ccp_fids.add(fid_)

      collections = [ccp_fids, self.agy_fids, self.new_fids,]
      for collection in collections:

         # We use an inner progger to help debug, to make sure we look at each 
         # collection while debugging.
         prog_lite = Debug_Progress_Logger(copy_this=self.debug.debug_prog_log)
         prog_lite.log_listen = None
         prog_lite.log_silently = True
         prog_lite.log_freq = prog_log.log_freq / len(collections)

         # Get the list of FIDs.
         if isinstance(collection, dict):
            feat_fids = collection.keys()
         else:
            g.assurt(isinstance(collection, set))
            feat_fids = collection

         # Examine each feature's endpoints.
         for fid in feat_fids:

            feat = self.import_lyr.GetFeature(fid)
            g.assurt(feat is not None)

            self.node_cache_consume(feat)

            prog_log.loops_inc()
            if prog_lite.loops_inc():
               break

   #
   def node_cache_consume(self, feat):

      # FIXME: Implement. Use endpoints to find or update node_endpoint and its
      # cache.

      # FIXME: Double-check that the database transaction uses data we insert
      # but have yet to commit.

   # 1. Look in node_endpoint cache for a match; if not found, create one.
   # 2. Update the cache table to bump its match count.

      pass

   # *** Split Segment Reassembly


# FIXME: We need to the node_endpoint cache to do this correctly.
   #
   def splitset_combine_adjacent(self, old_byway, ccp_m_vals):

      g.assurt(False) # FIXME: Can only combine adjacent as a separate
                      #        operation.

      log.verbose3('Reducing line segments based on similarity.')
      # Before combining, record the number of splits
      self.stats_bucket_usage_remember('split_fts_x_counts_1', 
                                       len(ccp_m_vals), old_byway.stack_id)
      # Combine segments that share the same attributes. This is so we don't
      # end up with tons of tiny segments.
      m_ordered = ccp_m_vals.keys()
      m_ordered.sort()
      superconflated_feats = set()
      last_splitd = None
      consecutive_count = 1
      for m_beg in m_ordered:
         splitd = ccp_m_vals[m_beg]
         log.verbose4('    splitd: m_beg_fix %s / m_fin_fix %s' 
                      % (splitd.m_beg_fix, splitd.m_fin_fix,))
         g.assurt(m_beg == splitd.m_beg)
         new_defn = splitd
         if last_splitd is not None:
            log.verbose4('    last_splitd: m_beg_fix %s / m_fin_fix %s' 
                         % (last_splitd.m_beg_fix, last_splitd.m_fin_fix,))
            g.assurt(splitd.m_beg_fix == last_splitd.m_fin_fix)
            # See if the last segment is the same as this segment, and
            # combine if so.
            if self.assemble_is_split_neighbor_equal(old_byway,
                                                     last_splitd, splitd):
               new_defn = self.assemble_combine_neighbors(old_byway, 
                     ccp_m_vals, last_splitd, splitd, superconflated_feats,
                     consecutive_count)
               consecutive_count += 1

# FIXME: feat_is_new is removed

            elif not last_splitd.feat_is_new:
               self.splitset_target_add_unconjoined(old_byway, last_splitd)
               consecutive_count = 1
         last_splitd = new_defn
      #
      if not last_splitd.feat_is_new:
         self.splitset_target_add_unconjoined(old_byway, last_splitd)
      # Add the old update feats to the target and mark Superconflated.
      self.stats['split_fts_superconflated'] += len(superconflated_feats)
      for feat in superconflated_feats:
         self.tlayer_add_reject(feat, 'Superconflated')
      # Add to the number-of-segments-split stat.
      self.stats_bucket_usage_remember('split_fts_x_counts_2', 
                                       len(ccp_m_vals), old_byway.stack_id)
      return ccp_m_vals

   #
   def splitset_target_add_unconjoined(self, old_byway, splitd):
      # The splitd's feature is just an intermediate feature we haven't touched
      g.assurt(not splitd.feat_is_new)
      context = splitd.feat.GetFieldAsString(self.defs.confln_context)
      log.verbose2('context: %s' % (context,))
      #if srcstate == 'Standalone':
      #   cclass = 'Divided (Standin)'
      #elif srcstate == 'Matched (Reference)':
      #   cclass = 'Divided (Reference)'
      #else:
      g.assurt(context == 'Ccp (Missing)')
      # The 'unconjoined' feature just needs its context updated.
      #splitd.feat.SetField(self.defs.confln_context, context)
      #
      splitd.feat_is_new = True

   # 
   # MAYBE: Can we use this fcn. (or its algorithm) to resegmentize the 
   # Cyclopath road network?
   def assemble_is_split_neighbor_equal(self, old_byway, 
                                              lhs_splitd, 
                                              rhs_splitd):
      equal = False
      lhs_feat = lhs_splitd.feat
      rhs_feat = rhs_splitd.feat
      # Check the attributes we care about and see if they're equal.
      equal = self.compare_matched_feats_(old_byway, lhs_feat, rhs_feat)
      return equal

   #
   # Derived classes should override this and add their own logic.
   def compare_matched_feats_(self, old_byway, lhs_feat, rhs_feat):
      # Compare the two features.
      is_equal = self.compare_matched_feats(old_byway, lhs_feat, rhs_feat)
      # Do some sanity checking.
      lhs_agy_id = lhs_feat.GetFieldAsInteger(self.defs.confln_agy_obj_id)
      rhs_agy_id = rhs_feat.GetFieldAsInteger(self.defs.confln_agy_obj_id)
      # FIXME: I'm seeing splits where I wouldn't expect them. I.e., two
      # segments with same Ccp Id and same Agy ID: why was the original segment
      # split?
      # ANSWER: A number of different reasons.
      # (1) The update data has multiple features with the same AGY_ID.
      #     The cases I saw, the difference was that Proposed was N for one 
      #     and Y for the other: so I'm assuming someone split the feature 
      #     and the new segments didn't get new IDs, or maybe the original 
      #     data used m-values and the m-values were not captured. In any 
      #     case, it looks like AGY_ID isn't the unique ID I thought it was!
      #     (It usually almost always is, but not for 34 features).
      # (2) If the update line segment overruns (covers/intersects and crosses
      #     over) the input segment, the conflated segment is split by how much
      #     the overrun is, even though the split is not just shy of the input 
      #     segment. It's hard to explain. But I think RoadMatcher uses this 
      #     weird little segment somehow.
      if lhs_agy_id == rhs_agy_id:
         if is_equal:
            # I wouldn't expect any/many of these.
            self.stats['split_self_split_equal'] += 1
         else:
            # This is what you should expect to happen.
            self.stats['split_self_split_unique'] += 1
      # If the two features come from the same 'layer' or 'feature class' or
      # whatever, make sure they're not the same feature.
      g.assurt(id(lhs_feat) != id(rhs_feat))
      # This doesn't work?:
      #  if id(lhs_feat.GetDefnRef()) == id(rhs_feat.GetDefnRef()):
      # But this does?:
      lhs_dr = lhs_feat.GetDefnRef()
      rhs_dr = rhs_feat.GetDefnRef()
      same_fids = lhs_feat.GetFID() == rhs_feat.GetFID()
      g.assurt((id(lhs_dr) != id(rhs_dr)) or not same_fids)
      return is_equal

   #
   def compare_matched_feats(self, old_byway, lhs_feat, rhs_feat):
      # Compare the attributes we care about.
      differences = 0
      difftype = 1
      for ta_def in self.defs.attrs_metadata:
         if ta_def.comparable:
            # lhs_feat could be old or new feat. rhs_feat is old feat.
            #lhs_val = self.field_val_fetch(ta_def, old_byway, lhs_feat)
            #rhs_val = self.field_val_fetch(ta_def, old_byway, rhs_feat)
            lhs_val = self.defs.ta_def_get_field_value(ta_def, lhs_feat, 
                                                       use_target=True)
            rhs_val = self.defs.ta_def_get_field_value(ta_def, rhs_feat, 
                                                       use_target=True)
            # The empty string might be meaningless, or it might be meaningful.
            compare_em = True
            if ta_def.cmp_ignore_empties:
               if ta_def.field_type == ogr.OFTString:
                  if not lhs_val or not rhs_val:
                     compare_em = False
            # For comparable values, we expect them to be non None.
            #g.assurt((lhs_val is not None) and (rhs_val is not None))
            # Record the number of differences.
            #if lhs_val != rhs_val:
            if compare_em and (lhs_val != rhs_val):
               self.stats_bucket_usage_increment('compare_difftype_x_feats', 
                                                 difftype)
               differences += 1
            difftype += 1
      log.verbose4('is_equal_update_feats: differences: %d' % (differences,))
      # Keeps stats of cnts of differences.
      self.stats_bucket_usage_remember('compare_feats_x_differences', 
                                       differences, old_byway.stack_id)
      # If there are no differences, the two features are logically
      # (attributely) equivalent.
      return differences == 0

   #
   def assemble_combine_neighbors(self, old_byway, ccp_m_vals, lhs_splitd, 
                                  rhs_splitd, superconflated_feats,
                                  consecutive_count):
      log.verbose3('Combining neighborlies: removing %s and %s [%d]'
                   % (lhs_splitd.m_beg_fix, rhs_splitd.m_beg_fix,
                      consecutive_count,))
      # Remove the two existing definitions from the lookup.
      ccp_m_vals.pop(lhs_splitd.m_beg)
      ccp_m_vals.pop(rhs_splitd.m_beg)
      # Mark the original split segment feats as super-conflated.
      g.assurt(not rhs_splitd.feat_is_new)
      if (lhs_splitd.feat is not None) and (rhs_splitd.feat is not None):
         # NO: g.assurt(lhs_splitd.feat.GetFID() != rhs_splitd.feat.GetFID())
         if not lhs_splitd.feat_is_new:
            superconflated_feats.add(lhs_splitd.feat)
         superconflated_feats.add(rhs_splitd.feat)
      else:
         # These are two missing Standalone input features.
         g.assurt((lhs_splitd.feat is None) and (rhs_splitd.feat is None))
         # Which shouldn't happen.
         g.assurt(False)
      self.stats['split_fts_conjoined'] += 1
      # Setup the new feature if we need to.
      if lhs_splitd.feat_is_new:
         new_feat = lhs_splitd.feat
         log.verbose4('  >> old new feat FID: %d' % (new_feat.GetFID(),))
      else:
         context = 'Ccp (Conjoined)'
         try:
            new_feat = self.field_val_setup_all(old_byway, lhs_splitd.feat,
                                                context, just_copy_from=True)
         except Feat_Skipped:
            log.error('assemble_combine_neighbors: Feat_Skipped?')
            # 2012.08.13: This doesn't happen?
            g.assurt(False)
         log.verbose4('  >> new new feat FID: %d' % (new_feat.GetFID(),))
      # Set the meta attributes of the new feature.
      #
      lhs_agy_id = lhs_feat.GetFieldAsInteger(self.defs.confln_agy_obj_id)
      rhs_agy_id = rhs_feat.GetFieldAsInteger(self.defs.confln_agy_obj_id)
      #lhs_stack_id = lhs_splitd.feat.GetFieldAsInteger(
      #                   self.defs.confln_ccp_stack_id)
      #rhs_stack_id = rhs_splitd.feat.GetFieldAsInteger(
      #                   self.defs.confln_ccp_stack_id)
      #log.verbose4(' lhs_stack_id:rhs_stack_id / %d:%d' 
      #             % (lhs_stack_id, rhs_stack_id,))
      #g.assurt(lhs_stack_id == rhs_stack_id)
      # Merge the update attributes.
      for ta_def in self.defs.attrs_metadata:
         # When comparable=None, it means wait to compute until writing target.
         if ta_def.comparable is not None:
            #fname = ta_def.field_source or ta_def.field_target
            fname = ta_def.field_target
            # Get the LHS value. This value is the stacked value if the LHS
            # feature has previously been stacked.
            #lhs_val = self.field_val_fetch(ta_def, old_byway, lhs_splitd.feat)
            lhs_val = self.defs.ta_def_get_field_value(ta_def, lhs_splitd.feat,
                                                       use_target=True)
            #g.assurt(lhs_val is not None)
            if lhs_val:
               log.verbose4('  >> fname: %s / lhs: %s' % (fname, lhs_val,))
            # else, lhs_val was set on previous loop iteration.
            # Get the RHS value.
            g.assurt(not rhs_splitd.feat_is_new)
            #rhs_val = self.field_val_fetch(ta_def, old_byway, rhs_splitd.feat)
            rhs_val = self.defs.ta_def_get_field_value(ta_def, rhs_splitd.feat,
                                                       use_target=True)
            #g.assurt(rhs_val is not None)
            if rhs_val:
               log.verbose4('  >> fname: %s / rhs: %s' % (fname, rhs_val,))
            # Treat LHS specially depending on stackable or not.
            if (((lhs_val is not None) or (rhs_val is not None))
                and ta_def.stackable):
               g.assurt(not ta_def.comparable)
               if fname not in lhs_splitd.stacked_fields:
                  lhs_splitd.stacked_fields[fname] = set()
                  if (lhs_val is not None) and (lhs_val != ''):
                     log.verbose4('  adding lhs stacked[%s].add(%s)'
                                  % (fname, lhs_val,))
                     lhs_splitd.stacked_fields[fname].add(lhs_val)
               if (rhs_val is not None) and (rhs_val != ''):
                  lhs_splitd.stacked_fields[fname].add(rhs_val)
                  log.verbose4('  adding rhs stacked[%s].add(%s)'
                               % (fname, rhs_val,))
               # Store the stringified value in the feature.
               g.assurt(len(lhs_splitd.stacked_fields) > 0)
               if ta_def.attr_type == str:
                  the_val = ', '.join(lhs_splitd.stacked_fields[fname])
               elif ta_def.attr_type == bool:
                  # This is a tricky way to see if all elems are the same (==).
                  distinct_n = len(set(lhs_splitd.stacked_fields))
                  #g.assurt(distinct_n in (1,2,))
                  if distinct_n == 1:
                     the_val = lhs_splitd.stacked_fields[fname][0]
                  elif distinct_n == 2:
                     # Use whatever the def. says to use when the two values
                     # differ. Obviously, this is a lossy combination!
                     the_val = ta_def.stackable_xor
                  else:
                     g.assurt(False)
               else:
                  # We only supports strs and bools currently.
                  g.assurt(False)
               log.verbose4('  stacked fname: %s: %s' % (fname, the_val,))
            #
            else:
               # Not ta_def.stackable, or both None.
               #
               # Earlier, we said that comparing the empty string to a
               # non-empty string was comparable; here we make sure to use the
               # non-empty one.
               if ((ta_def.cmp_ignore_empties)
                   and (ta_def.field_type == ogr.OFTString)):
                  the_val = lhs_val
                  if not the_val:
                     the_val = rhs_val
                     # the_val still might be empty, if both lhs and rhs were.
               else:
                  g.assurt(lhs_val == rhs_val)
                  the_val = lhs_val
            # For now, even if this is a new feature for the target layer, we
            # use the update layer's field name, just to keep the custom fcns'
            # logic simpler.
            if the_val is not None:
               log.verbose4('  SetField: %s: %s' 
                            % (ta_def.field_target, the_val,))
               new_feat.SetField(ta_def.field_target, the_val)
            #log.debug('----')
      # Merge the geometries.
      lhs_geom_wkt = lhs_splitd.feat.GetGeometryRef().ExportToWkt()
      rhs_geom_wkt = rhs_splitd.feat.GetGeometryRef().ExportToWkt()
      lhs_xy_list = geometry.wkt_line_to_xy(lhs_geom_wkt)
      rhs_xy_list = geometry.wkt_line_to_xy(rhs_geom_wkt)
      # 20111126: (496216.495626578, 4992407.135004374) from earlier segment
      # becomes   (496216.495627, 4992407.135) when it's stored. And then you
      # get 
      #    d_lhs_xy_end: (Decimal('496216.50'), Decimal('4992407.13'))
      #    d_rhs_xy_beg: (Decimal('496216.50'), Decimal('4992407.14'))
      # so reducing precision just for this comparison. For now. 'til it
      # crashes again.
      # FIXME: See conf.node_tolerance
      d_lhs_xy_end = geometry.raw_xy_make_precise(lhs_xy_list[-1], 
                                                  conf.node_tolerance)
      d_rhs_xy_beg = geometry.raw_xy_make_precise(rhs_xy_list[0], 
                                                  conf.node_tolerance)
      #g.assurt(d_lhs_xy_end == d_rhs_xy_beg)
      if d_lhs_xy_end != d_rhs_xy_beg:
         log.verbose4('  lhs_xy_list: %s' % (lhs_xy_list,))
         log.verbose4('  rhs_xy_list: %s' % (rhs_xy_list,))
         log.verbose4('  d_lhs_xy_end: %s' % (d_lhs_xy_end,))
         log.verbose4('  d_rhs_xy_beg: %s' % (d_rhs_xy_beg,))
         g.assurt(False)
      new_xy_list = lhs_xy_list[0:-1] + rhs_xy_list[1:]
      new_geom_wkt = geometry.xy_to_wkt_line(new_xy_list)
      new_geom = ogr.CreateGeometryFromWkt(new_geom_wkt)
      g.assurt(new_geom.GetZ() == 0)
      #new_geom.FlattenTo2D()
      new_feat.SetGeometryDirectly(new_geom)
      g.assurt(new_feat.GetGeometryRef().IsSimple())
      g.assurt(not new_feat.GetGeometryRef().IsRing())

      # Add the new, combined segment definition to the lookup.
      new_defn = Split_Defn(new_feat, 
                            lhs_splitd.m_beg_raw, # LHS's beg
                            rhs_splitd.m_fin_raw, # RHS's end
                            lhs_splitd.splitstart,
                            rhs_splitd.splitend,
                            lhs_splitd.cnf_xy_beg_raw, 
                            rhs_splitd.cnf_xy_fin_raw,
                            lhs_splitd.stacked_fields)
      new_defn.feat_is_new = True
      ccp_m_vals[new_defn.m_beg] = new_defn
      return new_defn

   # End of: *** Split Segment Reassembly

   # ***

# ***

if (__name__ == '__main__'):
   pass


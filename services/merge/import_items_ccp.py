# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

from decimal import Decimal
import os
import sys
import time

import conf
import g

log = g.log.getLogger('io_items_ccp')
#from util_ import logging2
#log.setLevel(logging2.VERBOSE1)

from item import item_base
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_.shapefile_wrapper import Shapefile_Wrapper

from merge.import_base import Import_Base
from merge.import_init import Feat_Skipped
from merge.import_items_agy import Import_Items_Agy

# For yer notes, to selectively run code:
# if log.getEffectiveLevel() <= logging2.VERBOSE4:

# ***

class Split_Defn(object):

   __slots__ = (
      # The line subsegment.
      'feat',
      # The beginning and finishing m-values.
      'm_beg_raw',
      'm_fin_raw',
      'm_beg_fix',
      'm_fin_fix',
      # The 'raw' geometry has conf.geom_precision, i.e., %.6f
      'cnf_xy_beg_raw',
      'cnf_xy_fin_raw',
      # The 'fixed' geometry has conf.node_precision, i.e., %.1f
      'cnf_xy_beg_fix',
      'cnf_xy_fin_fix',
      # Geom-is-Golden is usually True, meaning trust the geometry in the
      # Shapefile. If it's False, we'll use (or reconstruct) the old_byway's 
      # geometry.
      'geom_is_golden',
      'new_geom_wkt',
      # A byway that is split into many has one beginning segment, zero or 
      # more intermediate segments, and one finishing segment.
      'split_grp_beg',
      'split_grp_fin',
      # Commands that the user can send embedded in each feature.
      'fcommand_delete',
      'fcommand_revert',
      )

   def __init__(self, feat, 
                      m_beg_raw, m_fin_raw, 
                      cnf_xy_beg_raw, cnf_xy_fin_raw, 
                      geom_is_golden=True):

      self.feat = feat

      # The raw m-values.
      self.m_beg_raw = m_beg_raw
      self.m_fin_raw = m_fin_raw
      # The normalized m-values.
      # 2012.07.27: Don't use node_tolerance, which is 0.1 meters, especially
      # since we're dealing with some fraction btw. 0 and 1 inclusive. But we
      # also don't want to use raw precision, since ST_line_locate_point (used
      # in line_segment_get_m_value) doesn't return 0 or 1 exactly. So, for
      # now, hoping that geom_tolerance is appropriate (6 digits of precision).
      # 2012.07.30: line_segment_get_m_value is returning 1.26149125515092e-06,
      # which quantizes to '0.000001'. So try less tolerant tolerance.
      #self.m_beg_fix = Decimal(str(m_beg_raw)).quantize(conf.geom_tolerance)
      #self.m_fin_fix = Decimal(str(m_fin_raw)).quantize(conf.geom_tolerance)
      self.m_beg_fix = Decimal(str(m_beg_raw)).quantize(conf.mval_tolerance)
      self.m_fin_fix = Decimal(str(m_fin_raw)).quantize(conf.mval_tolerance)

      # These two can be None. They're the byway's node endpoints; there are 
      # just one each of these for each collection of Split_Defns.
      self.cnf_xy_beg_raw = cnf_xy_beg_raw
      self.cnf_xy_fin_raw = cnf_xy_fin_raw
      # The source feature's normalized endpoints.
      if cnf_xy_beg_raw is not None:
         self.cnf_xy_beg_fix = geometry.raw_xy_make_precise(cnf_xy_beg_raw)
      if cnf_xy_fin_raw is not None:
         self.cnf_xy_fin_fix = geometry.raw_xy_make_precise(cnf_xy_fin_raw)

      # This pertains to _NEW_GEOM. The feature is not used often, so this is
      # generally False.
      self.geom_is_golden = geom_is_golden

      # If the geometry is not golden, we'll compare it to the existing byway
      # segment geometry, so this is for RoadMatcher, wherein we expect the
      # m-vals to be somehow related. (If geometry is golden, on the other
      # hand, there's no reason to expect m-vals to make sense, i.e., if the
      # new geometry is to the right of the old geometry, both m-vals will be
      # 1.0.)
      if not self.geom_is_golden:
         # 2013.04.27: The latest Shapefile [lb] got from 'the client' has
         # edited geometry with _NEW_GEOM indicated so this assert was
         # firing. This is the m-value of the feature's geometry compared to
         # the existing byway's geometry.  So if the user edited it and didn't
         # mark _NEW_GEOM, this shouldn't be a hard-stop; for now we log an
         # error, but we really want to move the feature to the FIXME layer.
         # FIXME: Move this feature to the FIXME layer.
         # No: g.assurt(self.m_fin_fix > self.m_beg_fix)
         if self.m_fin_fix <= self.m_beg_fix:
            # This happens when, e.g., the geometry is to the right of the
            # byway. it's edited, but geom_is_golden is not indicated.
            # You might see, for example, m_fin_fix = m_beg_fix = 1.0.
            log.warning('Split_Defn: not geom_is_golden but unexpected geom')
            log.warning(' m_beg_fix: %s' % (self.m_beg_fix,))
            log.warning( 'm_fin_fix: %s' % (self.m_fin_fix,))
            log.warning(' feat.GetFID: %s' % (feat.GetFID(),))
            log.warning(' feat.CCP_ID: %s'
               % (feat.GetFieldAsInteger('CCP_ID'),))
            log.warning(' feat.AGY_ID: %s'
               % (feat.GetFieldAsInteger('AGY_ID'),))
            # FIXME: 2013.04.27: Verify CCP_ID 1133735 in latest Bikeways
            #        import.
            # Can we catch this earlier and make it a FIXME? The problem is we
            # don't want to assume the new geometry is what we want -- maybe
            # we're just consuming attributes and keeping Cyclopath's
            # geometries. So don't fail -- log a warning for now, don't consume
            # the geometry, and maybe we can set the ACTION on the feature?
            # (It's been a while since [lb] edited the import code, and now
            # right before the CcpV3 release is not time to get lost in this
            # code.)
            log.warning(
               'Geom changed but user did not set geom_is_golden: CCP_ID: %s'
               % (feat.GetFieldAsInteger('CCP_ID'),))
            # 2013.04.27: Oh, sweet, [lb] already coded for this!
            # FIXME: How do we use this from here? Maybe return something
            #        to the caller to indicate to do this, or maybe the 
            #        caller should check the condition of this if-block
            #        before calling us in the first place.
            #? self.splitset_reject_segments(ccp_m_vals, 'node_mismatch',
            #?                               m_beg_fix)
# FIXME: Should we just use EDIT_DATE and import all geometries with a recent
#        EDIT_DATE? I.e., assume _NEW_GEOM is true for all features edited by
#        the intern (any EDIT_DATE after the first one, which is May or June
#        something of 2012).

      # This is the geometry that gets saved. We need this if we manipulate a
      # source feature's geometry, or if we're recreating a missing split
      # segment.
      self.new_geom_wkt = None

      # RoadMatcher uses the fields "splitstart" and "splitend" to distinguish
      # between the end segments of a set of split segments and the interior 
      # segments (such that interior segments had both splitstart and splitend 
      # set). Here, we use similar fields, but with opposite meanings. We
      # indicate if the segment if the first segment in a series of split
      # segments or if it's the last.
      if geom_is_golden:
         self.split_grp_beg = None
         self.split_grp_fin = None
      else:
         # Assume all segments are interior, or split on both ends.
         self.split_grp_beg = False
         self.split_grp_fin = False
         # Now see if the segment is an exterior segment.
         # ADD_TO_WIKI: Comparing Decimal: This is funny:
         #   (Pdb) Decimal('1.0') == 1
         #   True
         #   (Pdb) Decimal('1.0') == 1.0
         #   False
         # Wrong: if self.m_beg_fix == 0.0:
         # Could use: if self.m_beg_fix == Decimal('0.0'):
         if self.m_beg_fix == 0:
            self.split_grp_beg = True
         # Wrong: if self.m_fin_fix == 1.0:
         # Could use: if self.m_fin_fix == Decimal('1.0'):
         if self.m_fin_fix == 1:
            self.split_grp_fin = True

      self.fcommand_delete = False
      self.fcommand_revert = False

   #
   def __str__(self):
      try:
         #feat_name = self.feat.GetField(self.defs.confln_ccp_name)
         feat_name = ('%s (%d)' 
                      % (self.feat.GetField('CCP_NAME'), 
                         self.feat.GetFID(),))  
      except ValueError:
         feat_name = '%d' % (self.feat.GetFID(),)
      return (
         """splitdef: feat: %s / m_vals: %s to %s / geom_is_golden: %s
xys: beg: %s
     fin: %s"""
         % (feat_name,
            self.m_beg_fix,
            self.m_fin_fix,
            self.geom_is_golden,
            self.cnf_xy_beg_fix,
            self.cnf_xy_fin_fix,
            ))

# ***

class Import_Items_Ccp(Import_Items_Agy):

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Items_Agy.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Import_Items_Agy.reinit(self)

   # *** Entry point.

   #
   def fids_ccp_consume(self):

      log.info('Processing %d matched features (against %d Ccp byways).' 
               % (self.stats['count_fids_ccp'], len(self.ccp_fids),))

      #prog_log = self.progr_get(log_freq=5, loop_max=len(self.ccp_fids))
      prog_log = self.progr_get(log_freq=25, loop_max=len(self.ccp_fids))

      # Search for all the byways at once, and process them one at a time. This
      # is the best use of resources, in terms of speed and memory (it's faster
      # to fetch all at once and less memory intensive to process one by one).
      self.byways_get_many_by_id(self.ccp_fids, 
                                 prog_log,
                                 self.fids_ccp_consume_callback)

   #
   def fids_ccp_consume_callback(self, qb, gf, prog_log):
      # We can ignore qb... we already know what it is.
      g.assurt(id(qb) == id(self.qb_src))
      self.fids_ccp_consume_byway(gf)

   #
   def fids_ccp_consume_byway(self, old_byway):

      # Get the source features.
      feat_fids = self.ccp_fids[old_byway.stack_id]
      feats = []
      for fid in feat_fids:
         feat = self.import_lyr.GetFeature(fid)
         g.assurt(feat is not None)
         # The _ACTION should be 'Import'. We don't care what '_CONTEXT' is.
         g.assurt(feat.GetField('_ACTION') == self.defs.action_import)
         # Add the feat to the list.
         feats.append(feat)

      log.verbose3('=======================================')
      log.verbose3('Stack ID: %d / No. Feats: %d' 
                   % (old_byway.stack_id, len(feats),))

      # Assemble a lookup of update segments, keyed by m_value.
      #   lookup[m_value] => Split_Defn

      ccp_m_vals = self.splitset_assemble_segments(old_byway, feats)
      if ccp_m_vals:
         try:
            self.splitset_examine_assembled(old_byway, ccp_m_vals)
            self.splitset_consume_assembled(old_byway, ccp_m_vals)
         except Feat_Skipped, e:
            # This happens if we find issues with the geometry and
            # geom_is_golden is not set (i.e., for Bikeways import).
            # We've saved the features as FIXMEs already, so no-op.
            pass
      # else, Discovered Coincident (Overlapping) segments and made FIXMEs.

      # Cleanup memory.
      for feat in feats:
         feat.Destroy()

      log.verbose3('===========================  EOFeat  ==')

   # *** Assemble Features By M-Value

   #
   def splitset_assemble_segments(self, old_byway, feats):

      log.verbose3('Calculating m-values for update segments.')

      has_shared_m_vals = False

      # _NEW_GEOM may or may not be set on each of the features. It has to be
      # the same for all features we're assembling or we'll mark 'em FIXME.
      fcommands_newgeo = set()
      # Same goes for _DELETE and _REVERT.
      fcommands_delete = set()
      fcommands_revert = set()

      ccp_m_vals = {}
      for feat in feats:

         g.assurt(feat.GetGeometryRef().IsSimple())
         g.assurt(not feat.GetGeometryRef().IsRing())

         # Cook the feature (it's still raw).
         try:
            new_feat = self.field_val_setup_all(old_byway, feat, context=None)
         except Feat_Skipped:
            log.error(
               'splitset_assemble_segments: Feat_Skipped? old_byway: %s'
               % (old_byway,))
            # 2012.08.13: This doesn't happen?
            g.assurt(False)

         # FIXME: What to do about orientation? Do we reverse the m-vals or
         #        something?
         # FIXME: This isn't the right code for it, but we still may need to
         #        deal with orientation...
         # reversed = self.defs.ogr_str_as_bool(feat, 
         #         self.defs.confln_direction_reversed, False)
         # log.verbose4('reversed: %s' % (reversed,))
         # if reversed:
         #    self.stats['split_fts_reversed'] += 1
         # else:
         #    self.stats['split_fts_unreversed'] += 1

         # When we used RoadMatcher (or maybe it was our intern) when a
         # Cyclopath byway got split, not all the splits ended up in the
         # Conflation. If _NEW_GEOM is enabled, we use that column to decide
         # if a feature's geometry is golden, otherwise we make sure it matches
         # the old_byway's geometry (i.e., endpoints and vertices).
         if self.spf_conf.use__new_geom:
            # By default, all geometries in the conflation are not golden. If
            # someone -- i.e., [lb] or [ao] -- edited the conflation Shapefile 
            # and fixed a Stack_Id's features' geometries, then _NEW_GEOM might
            # be 'Y'.
            geom_is_golden = self.defs.ogr_str_as_bool(feat, 
                           self.defs.confln_new_geom, False)
         else:
            # If 'Use _NEW_GEOM' is not set, always use the geometry from the
            # Shapefile, no questions asked.
            geom_is_golden = True
         fcommands_newgeo.add(geom_is_golden)
         # Same goes for _DELETE and _REVERT.
         # BUG nnnn: If you have a feature with no geom but with a Ccp ID and 
         #           marked _DELETE, it'll probably get FIXME'd before if gets
         #           here, since the geometry is bad/missing.
         fcommands_delete.add(self.defs.ogr_str_as_bool(feat, 
                              self.defs.confln_delete, False))
         fcommands_revert.add(self.defs.ogr_str_as_bool(feat, 
                              self.defs.confln_revert, False))

         # Get points for the feat's endpoints.
         cnf_xy_beg_raw, cnf_xy_fin_raw = self.feat_get_xys(feat)

         # Get m-values from 0 to 1. We use conf.geom_tolerance so we end up
         # with, e.g., 0 instead of 1.26149125515092e-06.
         m_beg_raw = self.line_segment_get_m_value(old_byway, cnf_xy_beg_raw)
         m_fin_raw = self.line_segment_get_m_value(old_byway, cnf_xy_fin_raw)
         log.verbose4('  >> m_beg_raw: %.8f / m_fin_raw: %.8f' 
                      % (m_beg_raw, m_fin_raw,))

         splitd = Split_Defn(new_feat,
                             m_beg_raw, m_fin_raw,
                             cnf_xy_beg_raw, cnf_xy_fin_raw,
                             geom_is_golden)

         if splitd.m_beg_fix == splitd.m_fin_fix:
            has_shared_m_vals = True
         else:
            # See comments above, in Split_Defn ctor. This happens when the
            # user edits geometry and doesn't indicate _NEW_GEOM. We're
            # assuming the geometry is like the byway's geometry, but that's no
            # longer true. So don't assert, since this is just a data error.
            # FIXME: Detect this earlier and/or move feature to FIXME layer.
            # No: g.assurt(splitd.m_beg_fix < splitd.m_fin_fix)
            if splitd.m_beg_fix >= splitd.m_fin_fix:
               log.warning(
                  'spltset_assem_segs: not geom_is_golden but unexpected geom')
               log.warning(' m_beg_fix: %s' % (splitd.m_beg_fix,))
               log.warning( 'm_fin_fix: %s' % (splitd.m_fin_fix,))
               log.warning(' feat.GetFID: %s / old_byway: %s'
                         % (feat.GetFID(), str(old_byway),))
               log.warning(
                  'Geom changed but feat not set geom_is_golden: byway: %s'
                  % (str(old_byway),))
               # FIXME: Can we call reject from here, or earlier, on this
               #        feature(s)?
               #? self.splitset_reject_segments(ccp_m_vals, 'node_mismatch',
               #?                               m_beg_fix)

         # Make a tuple and key by m_value.

         # If the lookup already has this m-value, something's wrong.
         if splitd.m_beg_fix in ccp_m_vals:
            has_shared_m_vals = True
         else:
            ccp_m_vals[splitd.m_beg_fix] = splitd

      # end for

      g.assurt(ccp_m_vals)

      bad_reasons = []
      # Check for segments sharing the same m-value.
      if has_shared_m_vals:
         bad_reasons.append('Shared M-Value')
         self.stats['splits_m_val_shared'] += len(feats)
      # Check for overlapping segments.
      if not self.splitset_assemble_verify(old_byway, ccp_m_vals):
         bad_reasons.append('Overlapped M-Vals')
         self.stats['splits_m_val_overlapped'] += len(feats)
      # Check that _NEW_GEOM is consistent.
      if len(fcommands_newgeo) != 1:
         g.assurt(len(fcommands_newgeo) == 2)
         bad_reasons.append('_NEW_GEOM Varies')
         self.stats['splits_fcommand_varies'] += len(feats)
      # Same goes for _DELETE and _REVERT.
      if fcommands_delete:
         if len(fcommands_delete) == 1:
            splitd.fcommand_delete = fcommands_delete.pop()
         else:
            g.assurt(len(fcommands_delete) == 2)
            bad_reasons.append('_DELETE Varies')
            self.stats['splits_fcommand_varies'] += len(feats)
      if fcommands_revert:
         if len(fcommands_revert) == 1:
            splitd.fcommand_revert = fcommands_revert.pop()
         else:
            g.assurt(len(fcommands_revert) == 2)
            bad_reasons.append('_REVERT Varies')
            self.stats['splits_fcommand_varies'] += len(feats)
      if splitd.fcommand_delete and splitd.fcommand_revert:
         bad_reasons.append('Multiple Commands')
         self.stats['fixme_multiple_cmds'] += len(feats)
      # Make FIXMEs for any bad reasons.
      if bad_reasons:
         bad_reason = ', '.join(bad_reasons)
         for feat in feats:
            self.tlayer_add_fix_me(feat, bad_reason)
            # Skipping: self.stats, since we got it above.
         ccp_m_vals = {}

      return ccp_m_vals

   #
   def line_segment_get_m_value(self, old_byway, xy_pt):
      # Get a float from 0 to 1.
      # I.e., "%.6f %.6f" % (xy_pt[0], xy_pt[1],)
      point_sql = geometry.xy_to_raw_point_lossless(xy_pt)
      sql = (
         "SELECT ST_line_locate_point('%s', ST_AsEWKT(%s))" 
         % (old_byway.geometry, point_sql,))
      rows = self.qb_src.db.sql(sql)
      m_value = float(rows[0]['st_line_locate_point'])
      g.assurt((m_value >= 0.0) and (m_value <= 1.0))
      # BUG nnnn: Our data is only precise to so many decimal places.
      # FIXME: Is 6 decimal places the right answer?
      # The two same points, e.g., (516463.067685249, 4982349.58417596) can 
      # produce a non-zero distance, e.g., 0.00000000002257524624910030074527.
      # The OGR library uses 15 digits of precision, which in the prior two 
      # e.gs. results in 9 decimal places (EXPLAIN: What's the bounds for UTM
      # 15N? 500,000 meters is just over 300 miles.)
      # Calculating distance requires multiplication and addition. The result
      # of an addition is as good as the smallest number of decimal places in
      # the addends. The result of a multiplication is as good as the number of
      # significant digits.
      log.verbose4('_get_m_value: %.6f' % m_value)
      return m_value

   #
   def splitset_assemble_verify(self, old_byway, ccp_m_vals):
      log.verbose3('Verifying nonoverlapping line segments based on m-values.')
      verified = True
      m_ordered = ccp_m_vals.keys()
      m_ordered.sort()
      last_splitd = None
      for m_beg_fix in m_ordered:
         splitd = ccp_m_vals[m_beg_fix]
         g.assurt(m_beg_fix == splitd.m_beg_fix)
         if last_splitd is not None:
            if last_splitd.m_fin_fix > splitd.m_beg_fix:
               verified = False
               break
         last_splitd = splitd
      return verified

   # *** Recreate Missing Features

   #
   def splitset_examine_assembled(self, old_byway, ccp_m_vals):

      g.assurt(ccp_m_vals)

      # Note that geom_is_golden is the same for all splitds in the collection,
      # so we can pick any one. Also, we checked that _DELETE and _REVERT are 
      # the same for all features in the collection, so looking at just one
      # feat is fine.
      for splitd in ccp_m_vals.itervalues():
         geom_is_golden = splitd.geom_is_golden
         do_delete = splitd.fcommand_delete
         do_revert = splitd.fcommand_revert
         break # We just need to look at one splitdef.

      if do_delete or do_revert:
         # We've already checked that not both are specified.
         g.assurt(do_delete ^ do_revert)
         if do_delete and do_revert:
            self.splitset_reject_segments(ccp_m_vals, 'multiple_cmds')
         else:
            # Process the feature-command.
# FIXME: This is not implemented: process delete and revert cmds.
            self.splitset_process_fcommand(old_byway, ccp_m_vals, 
                                           do_delete, do_revert)
      elif not geom_is_golden:
         # If _NEW_GEOM in use, we want to create missing line segments and 
         # reconnect the new splits to the old_byway's endpoint(s).
         self.splitset_create_missing_segments(old_byway, ccp_m_vals)
      else: # geom_is_golden is True
         # If _NEW_GEOM set, the user may or may not have set the context.
         # But we don't care what the user says. Set a new context.
         for splitd in ccp_m_vals.itervalues():
            splitd.feat.SetField(self.defs.confln_context, 'Ccp (Splitseg)')

   # *** Missing Segment Recreation

   #
   def splitset_create_missing_segments(self, old_byway, ccp_m_vals):

      log.verbose3('Creating missing segments based on m-values.')

      (src_xy_beg_raw, src_xy_fin_raw, src_xy_beg_fix, src_xy_fin_fix
            ) = self.byway_get_endpoint_xys(old_byway)

      log.verbose4('  >> src_beg %s / src_end %s' 
                   % (src_xy_beg_fix, src_xy_fin_fix,))

      m_ordered = ccp_m_vals.keys()
      m_ordered.sort()
      last_splitd = None
      for m_beg_fix in m_ordered:

         splitd = ccp_m_vals[m_beg_fix]

         g.assurt(m_beg_fix == splitd.m_beg_fix)

         log.verbose4(
            ' .. m_beg_fix %s / m_fin_fix %s / split_grp beg-end %s-%s'
            % (splitd.m_beg_fix, splitd.m_fin_fix, 
               splitd.split_grp_beg, splitd.split_grp_fin,))
         log.verbose4('    cnf_beg %s / cnf_end %s' 
                      % (splitd.cnf_xy_beg_fix, splitd.cnf_xy_fin_fix))

         # Set the default context.
         splitd.feat.SetField(self.defs.confln_context, 'Ccp (Splitseg)')

         # See if the prevision segment is missing.
         missing_last_segment = False
         #
         if last_splitd is None:
            # This is the first split segment by m-value. See if its endpoint
            # matches old_byway's.
            if not splitd.split_grp_beg:
               # This is the first m_val, but it's not 0, meaning we're
               # missing a line segment before this one. Create it.
               # DOUBLECHECK: Stack ID 1114167. I'm curious about
               #              Orientation.
               log.verbose3('    .. missing first line segment')
               g.assurt(splitd.m_beg_fix > 0)
               m_seg_beg_raw = Decimal('0.0')
               m_seg_beg_fix = Decimal('0.0')
               m_seg_end_raw = splitd.m_beg_raw
               m_seg_end_fix = splitd.m_beg_fix
               cnf_xy_beg_raw = src_xy_beg_raw
               cnf_xy_fin_raw = splitd.cnf_xy_beg_raw
               missing_last_segment = True
               self.stats['split_missing_beg'] += 1
            else:
               g.assurt(splitd.m_beg_fix == 0)
            # If _NEW_GEOM is not set, complain if the node endpoint doesn't 
            # match old_byway's.
            if splitd.cnf_xy_beg_fix != src_xy_beg_fix:
               #log.warning('_missing_segments: first split seg node mismatch')
               #log.warning(' cnf: %s' % (splitd.cnf_xy_beg_fix,))
               #log.warning(' src: %s' % (src_xy_beg_fix,))
               #log.warning(' old_byway: %s' % (str(old_byway),))
               self.stats['split_missing_mismatch_first'].append(
                  (splitd.cnf_xy_beg_fix, src_xy_beg_fix, str(old_byway),))

               # Save ccp_m_vals features to fixme layer; raise Feat_Skipped.
               self.splitset_reject_segments(ccp_m_vals, 'node_mismatch', 
                                                         m_beg_fix)
         else:
            # If there's a previous segment, it should connect to this one,
            # but not overlap it.
            if last_splitd.m_fin_fix == splitd.m_beg_fix:
               # It does [connect to this one].
               g.assurt(last_splitd.cnf_xy_fin_raw == splitd.cnf_xy_beg_raw)
            else:
               # It doesn't.
               log.verbose3('    .. missing inner line segment')
               # Verify the last xy doesn't match and it doesn't overlap.
               g.assurt(last_splitd.cnf_xy_fin_fix != splitd.cnf_xy_beg_fix)
               # Specify the missing segment's m-values.
               #g.assurt(last_splitd.m_fin_fix < splitd.m_beg_fix)
               if last_splitd.m_fin_fix >= splitd.m_beg_fix:
                  # 2013.04.27: This look similar to the above cases of data
                  # error (search 'geom_is_golden but unexpected geom') but
                  # [lb] doesn't think it is. This is a hard fact, so we can
                  # assert, right? I guess we won't find out until there's
                  # bad data in some future import to bite us.
                  # (And if this is just a data error, move the feature to
                  #  the 'fixme' layer; see splitset_reject_segments.)
                  log.error(
                     'spltset_cr_mssg_sgs: geom_is_golden but unexpected geom')
                  log.error(' m_fin_fix: %s' % (last_splitd.m_fin_fix,))
                  log.error( 'm_beg_fix: %s' % (splitd.m_beg_fix,))
                  log.error(' splitd.feat.GetFID: %s / old_byway: %s'
                            % (splitd.feat.GetFID(), str(old_byway),))
                  # This is kosher, right? [lb] thinks so...:
                  g.assurt(False)
               m_seg_beg_raw = last_splitd.m_fin_raw
               m_seg_beg_fix = last_splitd.m_fin_fix
               m_seg_end_raw = splitd.m_beg_raw
               m_seg_end_fix = splitd.m_beg_fix
               g.assurt(last_splitd.cnf_xy_fin_raw is not None)
               cnf_xy_beg_raw = last_splitd.cnf_xy_fin_raw
               cnf_xy_fin_raw = splitd.cnf_xy_beg_raw
               missing_last_segment = True
               self.stats['split_missing_inn'] += 1
         #
         if missing_last_segment:
            g.assurt(m_seg_beg_fix not in ccp_m_vals)
            # If the old_byway's geometry is not simple or is a ring, raise.
            try:
               new_feat = self.field_val_setup_all(old_byway, src_feat=None,
                                                   context='Ccp (Missing)')
            except Feat_Skipped:
               log.warning('_missing_segments: old_byway has bad geom')
               log.warning(' old_byway: %s' % (old_byway,))
               # Save ccp_m_vals features to fixme layer; raise Feat_Skipped.
               self.splitset_reject_segments(ccp_m_vals, 'bad_old_geom')
            g.assurt(not splitd.geom_is_golden)
            ccp_m_vals[m_seg_beg_fix] = Split_Defn(
                                             new_feat,
                                             m_seg_beg_raw, m_seg_end_raw,
                                             cnf_xy_beg_raw, cnf_xy_fin_raw,
                                             splitd.geom_is_golden)

         # Sanity checking.
         if not splitd.split_grp_fin:
            g.assurt(splitd.m_fin_fix < 1)
         else:
            g.assurt(splitd.m_fin_fix == 1)
            # This is only good to cm. That is, when you ask for a substring
            # from m_beg_fix > 0 to m_fin_fix = 0, the computed last point
            # doesn't necessarily equal the source last point. For the first
            # point, I've seen more decimal place precision. Maybe should
            # profile the data....
            # FIXME: The missing line segments' end points exacerbate the node
            # xy bug.
            # 
            # Check if the split-from node is different from split-into's 
            # node, if _NEW_GEOM being enforced but it's not set for feat.
            if splitd.cnf_xy_fin_fix != src_xy_fin_fix:
               # MAYBE: Probably shouldn't be a warning... maybe we can make a
               # debug level between INFO and WARNING that's like a warning (in
               # that it conveys something more important than an info) but
               # that doesn't show up in logcheck, so devs see the warning when
               # testing but we don't care if users trigger the warning because
               # the features will be saved as fixmes to the output layer.
               #log.warning('_missing_segments: final split seg node mismatch')
               #log.warning(' cnf: %s' % (splitd.cnf_xy_fin_fix,))
               #log.warning(' src: %s' % (src_xy_fin_fix,))
               #log.warning(' old_byway: %s' % (str(old_byway),))
               self.stats['split_missing_mismatch_final'].append(
                  (splitd.cnf_xy_fin_fix, src_xy_fin_fix, str(old_byway),))

               # 
               # Save ccp_m_vals features to fixme layer; raise Feat_Skipped.
               self.splitset_reject_segments(ccp_m_vals, 'node_mismatch', 
                                                         m_beg_fix)

         last_splitd = splitd
      # end for

      if last_splitd.split_grp_beg:
         # Because of precision issues, only the fixed precision value is sure
         # to be zero. E.g., I've seen m_beg_raw = 0.00370370493, which is
         # nonzero if using conf.geom_precision but 0 if conf.node_precision.
         g.assurt(last_splitd.m_beg_fix == 0)
         # We're here because the last segment was the first and only segment, 
         # meaning either this byway is not being split, or it's being split
         # into two but the second segment is missing from the Shapefile (i.e.,
         # the Henry-or-RoadMatcher problem-question).
         g.assurt(len(ccp_m_vals) == 1)
         g.assurt(last_splitd.m_fin_fix <= 1)

      # Check if the final segment is missing.
      if last_splitd.m_fin_fix < 1:
         log.verbose3('    .. missing final line segment')
         g.assurt(last_splitd.cnf_xy_fin_fix != src_xy_fin_fix)
         m_seg_beg_raw = last_splitd.m_fin_raw
         m_seg_beg_fix = last_splitd.m_fin_fix
         m_seg_end_raw = Decimal('1.0')
         m_seg_end_fix = Decimal('1.0')
         cnf_xy_beg_raw = last_splitd.cnf_xy_fin_raw
         cnf_xy_fin_raw = src_xy_fin_raw
         g.assurt(m_seg_beg_fix not in ccp_m_vals)
         # Setup the new, missing feature, which fails if the old_byway's
         # geometry is not simple or is a ring.
         try:
            new_feat = self.field_val_setup_all(old_byway, src_feat=None,
                                                context='Ccp (Missing)')
         except Feat_Skipped:
            log.warning('_missing_segments: old_byway has bad geom')
            log.warning(' old_byway: %s' % (old_byway,))
            # Save ccp_m_vals features to fixme layer; raise Feat_Skipped.
            self.splitset_reject_segments(ccp_m_vals, 'bad_old_geom')
         #
         g.assurt(not splitd.geom_is_golden)
         ccp_m_vals[m_seg_beg_fix] = Split_Defn(
               new_feat,
               m_seg_beg_raw, m_seg_end_raw,
               cnf_xy_beg_raw, cnf_xy_fin_raw,
               splitd.geom_is_golden)
         self.stats['split_missing_fin'] += 1
         # This is the final line segment.
         g.assurt(ccp_m_vals[m_seg_beg_fix].split_grp_beg is False)
         g.assurt(ccp_m_vals[m_seg_beg_fix].split_grp_fin is True)

      # See if there's really just one line segment.
      if len(ccp_m_vals) == 1:
         ccp_m_vals[m_ordered[0]].feat.SetField(
            self.defs.confln_context, 'Ccp (1-to-1)')

      for splitd in ccp_m_vals.itervalues():
         g.assurt(splitd.feat.GetFieldAsString('_CONTEXT'))

   #
   def splitset_reject_segments(self, ccp_m_vals, reason, m_beg_fix=None):
      g.assurt(reason in ('multiple_cmds', 'node_mismatch', 'bad_old_geom',))
      if reason == 'multiple_cmds':
         g.assurt(m_beg_fix is None)
         others_context = 'Multiple Commands'
         stats_key = 'fixme_multiple_cmds'
      elif reason == 'node_mismatch':
         g.assurt(m_beg_fix is not None)
         splitd = ccp_m_vals[m_beg_fix]
         self.tlayer_add_fix_me(splitd.feat, 'Node Mismatch')
         self.stats['fixme_node_mismatch'] += 1
         # We're sneaky: mark the current node as the mismatch but the
         # others in the group also need to be rejected.
         del ccp_m_vals[m_beg_fix]
         #
         others_context = 'Mismatch Groupie'
         stats_key = 'fixme_mismatch_grpee'
      elif reason == 'bad_old_geom':
         g.assurt(m_beg_fix is None)
         others_context = 'Bad Old Byway Geom'
         stats_key = 'fixme_bad_byway_geom'
      else:
         g.assurt(False)
      for splitd in ccp_m_vals.itervalues():
         self.tlayer_add_fix_me(splitd.feat, others_context)
         self.stats[stats_key] += 1
      raise Feat_Skipped()

   # *** Consume the split features.

   #
   def splitset_consume_assembled(self, old_byway, ccp_m_vals):

      g.assurt(ccp_m_vals)

      # We used to recombine split segments, because with some sources, there
      # are a lot of unnecessary splits. But we can't know if an endpoint and
      # its two byways can be replaced by a single entity until we've consumed
      # all of the changes, since the byway might be split because of an
      # intersection. So resegmenting is a secondary step.
      # BUG nnnn: FIXME: From Export, choice to run resegmenter
      #                  also choice to run autonoder.

# FIXME: use these. also use in import_items_agy 
#        (which should be a simple subset of this file...).
#      self.confln_delete = '_DELETE'
#      self.confln_revert = '_REVERT'

      if len(ccp_m_vals) == 1:
         m_beg_fix = ccp_m_vals.keys()[0]
         splitd = ccp_m_vals[m_beg_fix]
         # User can really write whatever they want for the context, but we
         # change it to 1-to-1.
         splitd.feat.SetField(self.defs.confln_context, 'Ccp (1-to-1)')
         # Update the database -- save the byway for the branch, and save its
         # changed link_values and recalculate its rating, etc. We'll also save
         # the new feature to the target Shapefile.
         self.splitset_consume_1to1_match(old_byway, splitd)
      else:
         # Create the new line segments and split-byways in the geodatabase,
         # and save the new features to the target Shapefile.
         self.splitset_create_new_byways(old_byway, ccp_m_vals)
         # Delete the original, split-from byway, and cleanup its link_values,
         # etc.
         self.splitset_finalize_split_from(old_byway)

   # ***

   #
   def splitset_process_fcommand(self, old_byway, ccp_m_vals, 
                                       do_delete, do_revert):

# FIXME: Implement: Process _DELETE and _REVERT
#        for delete, see mark_deleted...
      log.warning('splitset_process_fcommand: FIXME: Implement me!')
      log.warning(' ++ do_delete: %s / do_revert: %s / old_byway: %s'
                  % (do_delete, do_revert, old_byway,))

   #
   def splitset_consume_1to1_match(self, old_byway, splitd):

      log.verbose4('_1to1_match: stack id: %d' % (old_byway.stack_id,))

      if not splitd.geom_is_golden:
         # See notes somewhere else.
         # Wrong: g.assurt(splitd.m_beg_fix == 0.0)
         # Wrong: g.assurt(splitd.m_fin_fix == 1.0)
         g.assurt(splitd.m_beg_fix == 0)
         g.assurt(splitd.m_fin_fix == 1)
         g.assurt(splitd.split_grp_beg)
         g.assurt(splitd.split_grp_fin)

      # The context is already set.
      g.assurt(splitd.feat.GetField(self.defs.confln_context) 
               == 'Ccp (1-to-1)')

      # Check geometry against old_byway and complain if edited and not
      # geom_is_golden.
      # FIXME: We're only checking endpoints here, not the whole geometry...
      if not splitd.geom_is_golden:
         (src_xy_beg_raw, src_xy_fin_raw, src_xy_beg_fix, src_xy_fin_fix
               ) = self.byway_get_endpoint_xys(old_byway)
         if ((splitd.cnf_xy_beg_fix != src_xy_beg_fix)
             and (splitd.cnf_xy_fin_fix != src_xy_fin_fix)):
            self.tlayer_add_fix_me(splitd.feat, 'Node Mismatch')
            self.stats['fixme_node_mismatch'] += 1
            raise Feat_Skipped()

      # Finalize the feature's geometry.
      self.target_feature_finalize_geom(splitd)

      # Add the intermediate feature to the target layer.
      new_feat = self.tlayer_add_import(splitd.feat)
      g.assurt(new_feat is not None)

      # Update the geodatabase.
      self.splitset_update_old_byway(old_byway, new_feat)

      # Bump the count.
      self.stats['splitsets_1to1_matches'] += 1

   #
   def splitset_update_old_byway(self, old_byway, new_feat):

      new_geom_wkt = new_feat.GetGeometryRef().ExportToWkt()
      # FIXME: Can we just compare WKTs? What about one-way/direction?
      log.verbose(' >>   new_geom_wkt: %s' % (new_geom_wkt,))
      log.verbose(' >>  old_byway.wkt: %s' % (old_byway.geometry_wkt,))
      # Error: log.debug(' >> old_byway.geom: %s' % (old_byway.geometry_,))
      # None:  log.debug(' >>  old_byway.svg: %s' % (old_byway.geometry_svg,))

      new_geom_list = geometry.wkt_line_to_xy(new_geom_wkt, 
                                    precision=conf.node_precision)
      old_geom_list = geometry.wkt_line_to_xy(old_byway.geometry_wkt,
                                    precision=conf.node_precision)

      log.verbose(' >>   new_geom_list: %s' % (new_geom_list,))
      log.verbose(' >>   old_geom_list: %s' % (old_geom_list,))
      log.verbose(' >>          equal?: %s' 
                  % (bool(new_geom_list == old_geom_list),))

      # Depending on what's changed, update the byway and/or link_values.
      do_save_byway = False

      # See if the geometry has changed.
      geom_is_changed = (new_geom_list != old_geom_list)

      # Create a new byway. We might trash it later.
      new_byway = self.byway_create(old_byway, new_geom_wkt, geom_is_changed)

      if geom_is_changed:
         log.verbose2('stdin_fts_cnsm_b: geom changed: %s / %s / %s' 
                      % (new_geom_list, old_geom_list, new_byway,))
         do_save_byway = True
         # NOTE: On save, the byway will fix its connectivity, i.e., update its
         #       byway node IDs and maintain the node_* tables as appropriate.

      do_save_byway |= self.byway_setup(new_byway, old_byway, new_feat)

      # If geometry or one or more attributes changed, save the new byway.
      if do_save_byway:

         if new_byway.stack_id in self.qb_cur.item_mgr.item_cache:
            # DEVS: This happened previously, but [lb] not sure it still
            #       happens: this can happen because of ref_item being cached.
            log.error(': unexpected: item in cache: %s / %s'
               % (new_byway,
                  self.qb_cur.item_mgr.item_cache[new_byway.stack_id],))

         self.byway_save(new_byway, old_byway)

         log.verbose2('stdin_fts_cnsm_bway: saved new bway: %s' % (new_byway,))
         ref_byway = new_byway
      else:
         new_byway = None
         ref_byway = old_byway
         log.verbose2('stdin_fts_cnsm_bway: using old bway: %s' % (old_byway,))

      # We first made an intermediate feature and set all the fields. Later, 
      # we (maybe) saved a new byway. Then we copied the intermediate feature
      # to the (temporary) target layer. Finally, we're saving associated
      # Cyclopath values (link_values, ratings, etc.).
      self.feat_assoc_save(new_feat, old_byway, new_byway)

      # MAYBE: Only call this if attribute/tag values that affect ratings are
      #        edited.
      # FIXME: Does this make sense here?
      g.assurt(ref_byway is not None)
      # FIXME: We we just call the byway directly? Depends if qb_cur is usable.
      ref_byway.refresh_generic_rating(self.qb_cur)

   # ***

   #
   def splitset_create_new_byways(self, old_byway, ccp_m_vals):
      log.verbose3('Creating geometry and new byways for each line segment.')
      (src_xy_beg_raw, src_xy_fin_raw, src_xy_beg_fix, src_xy_fin_fix
            ) = self.byway_get_endpoint_xys(old_byway)
      log.verbose4('  >> src_beg %s / src_end %s' 
                   % (src_xy_beg_fix, src_xy_fin_fix,))
      m_ordered = ccp_m_vals.keys()
      m_ordered.sort()
      last_splitd = None # This is simply for debugging.
      for m_beg_fix in m_ordered:
         splitd = ccp_m_vals[m_beg_fix]
         g.assurt(m_beg_fix == splitd.m_beg_fix)
         cfl_context = splitd.feat.GetFieldAsString(self.defs.confln_context)
         log.verbose('cfl_context: %s / %s' % (cfl_context, old_byway,))
         g.assurt(cfl_context)
         if ((self.debug.split_with_all_new_features)
             or (cfl_context == 'Ccp (Missing)')):
            # Because of missing split segments, we don't always have the xy
            # values. But we always have the m-values. To make things simple,
            # we always recreate the split segment geometry.
            # NOTE: Using raw floats, expect for ends.
            # FIXME: Substitute 0 and 1 if m_beg_fix == 0 or m_fin_fix == 1 ??
            #        Otherwise, we're passing, e.g., 0.9999997778378374 ?
            #        Should really just replace new seg with actual endpoints..
            if splitd.split_grp_beg:
               g.assurt(splitd.m_beg_fix == 0)
               m_beg_raw = Decimal('0.0')
            else:
               m_beg_raw = splitd.m_beg_raw
            if splitd.split_grp_fin:
               g.assurt(splitd.m_fin_fix == 1)
               m_fin_raw = Decimal('1.0')
            else:
               m_fin_raw = splitd.m_fin_raw
            # NOTE: Using m_beg_raw and m_fin_raw, not m_beg_fix and m_fin_fix.
            geom_wkt = self.splitset_create_segment(old_byway, 
                                                    m_beg_raw, m_fin_raw)
            # See if we should use the conflated feature's endpoints, which
            # exactly match the Cyclopath endpoints. This is only useful if
            # you're having issues with precision, e.g., if your mapping fcns.
            # are not symmetric. I.e., are xy and m_val equal in the two 
            # equations, m_val = get_m(line, xy), and xy = get_xy(line, m_val).
            if not self.debug.split_dont_replace_xy_endpoints:
               xy_list = geometry.wkt_line_to_xy(geom_wkt)
               log.verbose4('xy_list: 0: %s / -1: %s' 
                            % (xy_list[0], xy_list[-1],))
               # This could be a matched segment or a missing segment.
               g.assurt(splitd.cnf_xy_beg_raw is not None)
               xy_list[0] = splitd.cnf_xy_beg_raw
               g.assurt(splitd.cnf_xy_fin_raw is not None)
               xy_list[-1] = splitd.cnf_xy_fin_raw
               geom_wkt = geometry.xy_to_wkt_line(xy_list)
               log.verbose4(' >> hybrid geom_wkt: %s' % (geom_wkt,))
            else:
               log.verbose4(' >> created geom_wkt: %s' % (geom_wkt,))
         else:
            log.verbose4(' >> cfl_context: %s' % (cfl_context,))
            g.assurt(cfl_context.startswith('Ccp ('))
            geom_wkt = splitd.feat.GetGeometryRef().ExportToWkt()
            log.verbose4(' >> splitd.feat geom_wkt: %s' % (geom_wkt,))
         if not self.debug.split_dont_replace_xy_endpoints:
            # Rather than using the endpoint calculated from the m_values, use
            # the original endpoint values.
            # FIXME: Shouldn't this be src_xy_beg_fix? Or should we fix all
            # byways in one fell swoop.
            xy_list = geometry.wkt_line_to_xy(geom_wkt)
            if splitd.split_grp_beg:
               xy_list[0] = src_xy_beg_raw
            if splitd.split_grp_fin:
               xy_list[-1] = src_xy_fin_raw
            geom_wkt = geometry.xy_to_wkt_line(xy_list)
            log.verbose4(' >> hy-end geom_wkt: %s' % (geom_wkt,))

         # Get the two nodes' xys.
         (new_xy_beg_raw, new_xy_fin_raw, 
          new_xy_beg_fix, new_xy_fin_fix,
               ) = self.geom_get_endpoint_xys(geom_wkt)
         log.verbose4('     new_xy_beg_raw %s / _end %s' 
                      % (new_xy_beg_raw, new_xy_fin_raw,))

         # FIXME: Line segments should not reduce to a point, but how do we
         # handle this error?
         g.assurt(new_xy_beg_fix != new_xy_fin_fix)

         # Ug, these probably fire, don't they?
         # FIXME: I need to replace xy ends of new geom with real xys... or
         # just create the missing segments and replace their xys.
         if splitd.split_grp_beg:
            g.assurt(splitd.m_beg_fix == 0)
            # FIXME: If I care, I should make this a stat like the similar one.
            g.assurt(geometry.distance(src_xy_beg_raw, new_xy_beg_raw) < 2.0)
         if splitd.split_grp_fin:
            g.assurt(splitd.m_fin_fix == 1)
            g.assurt(geometry.distance(src_xy_fin_raw, new_xy_fin_raw) < 2.0)
         # The OGR-calculated line doesn't exactly match the one from
         # RoadMatcher. But we need to re-calculate the line since we're
         # missing line segments, so all the split segments should be
         # calculated using the same algorithm, i.e., OGR.
         # FIXME: Make a bucket for the distances that these are off.
         #        And fix this, there's a worse node/xy problem now.
         # FIXME: See, e.g., stack ID 1130512: i bet the calculated line
         #        segments don't match... but how serious is it?
         if splitd.cnf_xy_beg_raw is not None:
            self.geom_compare_noded_xys_dist('beg', splitd.cnf_xy_beg_raw, 
                                                    new_xy_beg_raw)
         if splitd.cnf_xy_fin_raw is not None:
            self.geom_compare_noded_xys_dist('fin', splitd.cnf_xy_fin_raw, 
                                                    new_xy_fin_raw)
         splitd.cnf_xy_beg_raw = new_xy_beg_raw
         splitd.cnf_xy_fin_raw = new_xy_fin_raw
         splitd.cnf_xy_beg_fix = new_xy_beg_fix
         splitd.cnf_xy_fin_fix = new_xy_fin_fix
         if last_splitd is not None:
            log.verbose4('  >> last end: %s / this beg: %s' 
               % (last_splitd.cnf_xy_fin_raw, splitd.cnf_xy_beg_raw,))
            g.assurt(last_splitd.cnf_xy_fin_fix == splitd.cnf_xy_beg_fix)
            g.assurt(last_splitd.cnf_xy_fin_raw == splitd.cnf_xy_beg_raw)

         g.assurt(splitd.feat is not None)

         # Setup the new geometry and try to save the feature.
         splitd.new_geom_wkt = geom_wkt
         self.target_feature_finalize_geom(splitd)
         # Leave context None, since we've already set it.
         new_feat = self.tlayer_add_import(splitd.feat, context=None)
         g.assurt(new_feat is not None)

         if new_feat is not None:

            # Create the new split byway and apply new_feat's byway attrs.
            new_byway = self.byway_create(old_byway, geom_wkt,
                                          is_geom_changed=True,
                                          is_split_from=True)
            # Setup the new byway with values we've already setup in new_feat.
            do_save_byway = self.byway_setup(new_byway, old_byway, new_feat)
            # Save the new byway.
            self.byway_save(new_byway, old_byway)

            log.verbose1('splitset_create_new_byways: saved new bway: %s' 
                         % (new_byway,))
            log.verbose1(' >> split-from: %s' % (old_byway,))

            # Store the new and old stack IDs.
            new_feat.SetField('SPLIT_FROM', old_byway.stack_id)
            new_feat.SetField(self.defs.confln_ccp_stack_id, 
                              new_byway.stack_id)

            # We've already saved the feature to the Shapefile, but we just set
            # some fields, so re-save the feature.
            the_layer = self.target_layers_temp[self.tlyr_import]
            ogr_err = the_layer.SetFeature(new_feat)
            g.assurt(not ogr_err)

            # Create or update Cyclopath link_values and set Shapefile feat
            # class fields.
            self.feat_assoc_save(new_feat, old_byway, new_byway)

            # FIXME: Does this make sense here?
            g.assurt(new_byway is not None)
            new_byway.refresh_generic_rating(self.qb_cur)

         # Setup the next loop iteration. Used just for debugging.
         last_splitd = splitd

      # end for
      return

   #
   def splitset_finalize_split_from(self, old_byway):

      # Because mark_deleted just UPDATEs existing rows to set
      # deleted to true, we need to save a new version of the
      # old byway (the deleted version).

      log.verbose4('Finalizing the split-from byway.')

      #self.qb_cur.item_mgr.item_cache_add(old_byway)
      #prepared = self.qb_cur.grac_mgr.prepare_item(
      #   self.qb_cur, old_byway, Access_Level.editor,
      #   ref_item=None)
      #if old_byway.valid and old_byway.is_dirty():
      #   old_byway.version_finalize_and_increment(self.qb_cur,
      #     self.qb_cur.item_mgr.rid_new, same_version=False,
      #     same_revision=False)
      #   old_byway.save(self.qb_cur, self.qb_cur.item_mgr.rid_new)
      #
      # We've loaded groups_accesses.
      # Argh, but what's target_groups? The old byway's groups_access?
      #old_byway.prepare_and_save_item(self.qb_cur, 
      #   target_groups=None,
      #   rid_new=self.qb_cur.item_mgr.rid_new,
      #   ref_item=None)
      #
      old_byway.validize(self.qb_cur, is_new_item=False,
         dirty_reason=item_base.One.dirty_reason_item_user,
         ref_item=old_byway)
      old_byway.version_finalize_and_increment(self.qb_cur,
         self.qb_cur.item_mgr.rid_new,
         same_version=False, same_revision=False)
      # Hmmm, save() raises if the db.sql raises... so...
      try:
         old_byway.save(self.qb_cur, self.qb_cur.item_mgr.rid_new)
      except Exception, e:
         log.error('splitset_finalize_split_from: failed: %s / %s'
                   % (str(e), old_byway,))
         raise
      #
      # Do it like item does it when deleting split-from link_values:
      # fake a target_groups lookup and call grac_mgr to prepare gia
      # records and re-check permissions.
      #target_groups = {}
      #for gia in old_byway.groups_access.itervalues():
      #   target_groups[gia.group_id] = gia.access_level_id
      #old_byway.prepare_and_save_item(self.qb_cur, 
      #   target_groups=target_groups,
      #   rid_new=self.qb_cur.item_mgr.rid_new,
      #   ref_item=None)

      old_byway.mark_deleted(self.qb_cur, f_process_item_hydrated=None)

   # *** Helpers for previous fcns.

   #
   def splitset_create_segment(self, old_byway, m_seg_beg_raw, m_seg_end_raw):
      g.assurt(old_byway.geometry) # I think this is set...
      sql = ((
            """
            SELECT ST_AsText(ST_line_substring('%%s', %%.%df, %%.%df)) 
               AS geometry_wkt
            """
            % (conf.geom_precision, conf.geom_precision,))
         % (old_byway.geometry, m_seg_beg_raw, m_seg_end_raw,))

      rows = self.qb_src.db.sql(sql)
      new_geom_wkt = rows[0]['geometry_wkt']
      log.verbose4('ST_line_substring: %.2f:%.2f | new_geom_wkt: %s' 
                   % (m_seg_beg_raw, m_seg_end_raw, new_geom_wkt,))
      return new_geom_wkt

   # 
   def geom_compare_noded_xys_dist(self, beg_or_fin, cnf_xy, new_xy):
      #if geometry.distance(cnf_xy, new_xy) > 1.0:
      #   log.verbose4('> old byway geom_wkt %s' % (old_byway.geometry_wkt,))
      #   geom = splitd.feat.GetGeometryRef()
      #   log.verbose4('> update feat geom %s' % (geom,))
      #   g.assurt(False)
      dist = geometry.distance(cnf_xy, new_xy)
      log.verbose4('     dist: %s / cnf_xy_%s: %s / new_xy_%s: %s' 
                   % (dist, beg_or_fin, cnf_xy, beg_or_fin, new_xy,))
      if dist == 0:
         dist = Decimal('0')
      elif dist < 1:
         # EXPLAIN: Magic numbers. Why not use conf.node_tolerance?
         dist = Decimal(str(dist)).quantize(Decimal('.1'))
      else:
         dist = Decimal(str(dist)).quantize(Decimal('1'))
      # FIXME: Do I care to distinguish between beg and end?
      self.stats_bucket_usage_increment('split_nodes_geom_x_counts', dist)

   # ***

   # *** Geometry fcns. used just by this class.

   # Used by Missing Segment Recreation and Making New Byways.
   # 
   def byway_get_endpoint_xys(self, bway):
      log.verbose4(' >> bway geom_wkt: %s' % (bway.geometry_wkt,))
      return self.geom_get_endpoint_xys(bway.geometry_wkt)

   #
   def geom_get_endpoint_xys(self, geometry_wkt):
      locs_svg = geometry.wkt_line_to_xy(geometry_wkt)
      log.verbose4('locs_svg[00]: %s' % (locs_svg[0],))
      log.verbose4('locs_svg[-1]: %s' % (locs_svg[-1],))
      src_xy_beg_raw = locs_svg[0]
      src_xy_fin_raw = locs_svg[-1]
      src_xy_beg_fix = geometry.raw_xy_make_precise(src_xy_beg_raw)
      src_xy_fin_fix = geometry.raw_xy_make_precise(src_xy_fin_raw)
      return src_xy_beg_raw, src_xy_fin_raw, src_xy_beg_fix, src_xy_fin_fix

   #
   def feat_get_xys(self, feat):
      geom = self.feature_geom_prepare(feat)
      pt_count = geom.GetPointCount()
      g.assurt(pt_count >= 2)
      log.verbose4('geom.GetPoint(0): %s' % (geom.GetPoint(0),))
      log.verbose4('geom.GetPoint(pt_count - 1): %s' 
                  % (geom.GetPoint(pt_count - 1),))
      cnf_xy_beg_raw = geom.GetPoint(0)
      cnf_xy_fin_raw = geom.GetPoint(pt_count - 1)
      # The Cyclopath geometry is 2D, so lost the z-value.
      cnf_xy_beg_raw = (cnf_xy_beg_raw[0], cnf_xy_beg_raw[1],)
      cnf_xy_fin_raw = (cnf_xy_fin_raw[0], cnf_xy_fin_raw[1],)
      return cnf_xy_beg_raw, cnf_xy_fin_raw

   # This fcn. flattens 25D line strings created by OGR.
   def feature_geom_prepare(self, feat):
      #
      geom = feat.GetGeometryRef()
      g.assurt(geom is not None)
      #
      g.assurt(geom.GetGeometryCount() == 0) # Just curious...
      g.assurt(geom.IsValid())
      g.assurt(not geom.IsEmpty())
      #
      # From what [lb] can tell, there are two types of 2-dimensional objects
      # in PostGIS: those with Z-values and those without Z-values. The Z-value
      # in PostGIS is used to represent height. So it's not a true Z-value in
      # the sense that a line string with z-values is 3-dimensional: the
      # z-values are just heights (i.e., in meters) as opposed to being related
      # to the projection (like x and y are).
      #
      # So wkbLineString is a line string of x,y coordinates, and 
      # wkbLineString25D is a line string of x,y coords w/ z-values. (The 25D 
      # is, [lb] guesses, suppose to indicate that it's not really 3-D, but 
      # also isn't really 2-D -- it's somewhere in between.)
      #
      # See also 2.5D extension discussed in OPENGIS PROJECT DOCUMENT 99-402r2
      #   http://lists.refractions.net/pipermail/postgis-devel/attachments/20041222/f8c95036/99-402r2.obj
      #
      log.verbose('geom: type: %s' % (geom.GetGeometryType(),))
      # 
      # So far, we've only seen 25D line strings in this fcn. [lb] says either
      # we created the line string using OGR, or it was imported from a
      # Shapefile and possibly converted to 25D. But in the future, if we see 
      # normal wkbLineString lines instead, investigate and take out the 
      # assertion.
      Shapefile_Wrapper.verbose_print_geom_type(geom.GetGeometryType())
      g.assurt(ogr.wkbLineString25D == geom.GetGeometryType())
      # 
      # FIXME: All the early Cyclopath import scripts run a transform on the 
      #        data, but I (a) think this is a no-op (the data should already 
      #        be in the correct projection) and (b) this doesn't seem like
      #        good form (i.e., do the transform in ArcGIS first and _then_ 
      #        export the data...).
      #geom.Transform(self.geom_xform)
      # So far, this script has only seen shapefiles whose features' z-levels
      # are not set. For consistency, we make sure all the z-levels are the
      # same (so that comparing points just compares the x and the y), but, 
      # in practice, they're already all the same value, anyway.
      # 2012.07.30: [lb] I used to just see GetZ() == -9999.0 but now I'm 
      #                  seeing it equal to 0.0, but I'm not sure what code
      #                  path I've changed. Oh, well!
      g.assurt((geom.GetZ() == -9999.0) or (geom.GetZ() == 0.0))
      geom.FlattenTo2D() # Set the z-value to 0 so enforce_dims_geometry works.
      g.assurt(ogr.wkbLineString == geom.GetGeometryType())
      #
      return geom

   # ***

   #
   # FIXME: Double-check that all feats in target have this called.
   def target_feature_finalize_geom(self, splitd):
      log.verbose4('  finalizing: %s' 
         % (splitd.feat.GetFieldAsString(self.defs.confln_context),)) 
      # This can sometimes be redundant (we generally keep the feature's
      # geometry updated) but for 'Ccp (Missing)' we have not set the
      # geometry yet. Also, we may have altered the geometry in 
      # splitset_create_new_byways to better-connect it to the network.
      if splitd.new_geom_wkt is not None:
         # FIXME: the new_geom is not precisionized. Does that matter?
         new_geom = ogr.CreateGeometryFromWkt(splitd.new_geom_wkt)
         new_geom.FlattenTo2D()
         splitd.feat.SetGeometryDirectly(new_geom)
         g.assurt(splitd.feat.GetGeometryRef().IsSimple())
         g.assurt(not splitd.feat.GetGeometryRef().IsRing())
         #log.verbose4('new_geom: %s' % (new_geom,))

   # ***

# ***

if (__name__ == '__main__'):
   pass


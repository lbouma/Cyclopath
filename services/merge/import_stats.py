# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys

import conf
import g

log = g.log.getLogger('import_stats')

from item.feat import node_endpoint

from merge.import_base import Import_Base

class Import_Stats(Import_Base):

   __slots__ = (
      'stats',
      'stats_f',
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Base.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Import_Base.reinit(self)
      # A bunch of stats. Used to guess if the data looks okay and complain if
      # things seem weird (like, if the script creates lots of new node IDs,
      # which would imply the input data is not well connected).
      self.init_stats()
      # Also used to report to user.
      self.stats_f = None

   # ***

   #
   def init_stats(self):

      self.stats = {}

      # *** Stats about the source feats.

      # In import_init, we preprocess the Shapefile and validate features.
      # These stats reflect the features we cannot process until the user
      # cleans them up.

      self.stats['fixme_empty_geom'] = 0
      #
      self.stats['fixme_bad_geom_type'] = 0
      self.stats['fixme_bad_geom_unsimple'] = 0
      self.stats['fixme_bad_geom_ring'] = 0
      #
      self.stats['fixme_multi_geom_src'] = 0
      self.stats['fixme_multi_geom_fin'] = 0
      #
      self.stats['fixme_multiple_cmds'] = 0
      self.stats['fixme_node_mismatch'] = 0
      self.stats['fixme_mismatch_grpee'] = 0
      self.stats['fixme_bad_byway_geom'] = 0
      #
      self.stats['fixme_other_reason'] = 0
      self.stats['fixme_wrong_action'] = 0
      #
      self.stats['fixme_negative_ccp_id'] = 0
      #
      self.stats['fixme_missing_feats'] = 0

      # If a feature is marked _ACTION='Ignore', we do just that; these
      # types of features do not need to be cleaned up and are not imported.

      self.stats['ignore_fts_total'] = 0

      # These are also from import_init -- they're counts of valid features we
      # can process.

      self.stats['count_fids_ccp'] = 0
      self.stats['count_fids_agy'] = 0
      self.stats['count_fids_new'] = 0

      # *** Stats about the import process.

      self.stats['splits_m_val_shared'] = 0
      self.stats['splits_m_val_overlapped'] = 0
      self.stats['splits_fcommand_varies'] = 0

      #
      self.stats['splitsets_1to1_matches'] = 0

      #
      self.stats['split_fts_conjoined'] = 0
      self.stats['split_fts_superconflated'] = 0
      # The conflation data isn't perfect.
      #?self.stats['split_fts_missing_segments'] = 0
      self.stats['split_fts_x_counts_1'] = {}
      self.stats['split_fts_x_counts_2'] = {}
      #
      self.stats['split_fts_reversed'] = 0
      self.stats['split_fts_unreversed'] = 0
      #
      self.stats['split_self_split_equal'] = 0
      self.stats['split_self_split_unique'] = 0
      #
      self.stats['split_missing_beg'] = 0
      self.stats['split_missing_inn'] = 0
      self.stats['split_missing_fin'] = 0
      #
      self.stats['split_missing_mismatch_first'] = []
      self.stats['split_missing_mismatch_final'] = []
      #
      self.stats['split_nodes_nearby_cnt'] = 0
      #
      self.stats['split_nodes_geom_x_counts'] = {}
      #
      self.stats['count_new_byways_total'] = 0
      self.stats['count_new_byways_refed'] = 0
      self.stats['count_new_byways_newed'] = 0
      self.stats['count_new_byways_not_split'] = 0
      #
      self.stats['count_link_values_all'] = 0
      self.stats['count_link_values_new'] = 0
      self.stats['count_link_values_old'] = 0
      #
      self.stats['field_string_spaces'] = 0
      #
      self.stats['compare_feats_x_differences'] = {}
      self.stats['compare_difftype_x_feats'] = {}

   # ***

   #
   def log(self, line):
      # Write to RESULTS.txt in user's download.
      if self.stats_f is not None:
         self.stats_f.write(line)
         self.stats_f.write('\n')
      # Write to console and/or server log file.
      log.info(line)

   #
   def prepare_log(self):

      g.assurt(self.stats_f is None)

      if self.import_lyr is not None:

         # Make the path, e.g., /ccp/var/cpdumps/ + {GUID} + .out/RESULTS.txt
         oname = '%s.out' % (self.mjob.wtem.local_file_guid,)
         opath = os.path.join(conf.shapefile_directory, oname)
         # If the 'out' directory exists, write to a text file.
         if os.path.exists(opath):
            spath = os.path.join(opath, 'RESULTS-%s.txt'
                                        % (self.import_lyr.GetName(),))
            g.assurt(not os.path.exists(spath))
            try:
               self.stats_f = open(spath, 'w')
            except IOError, e:
               log.error('Problem opening stats file!: %s' % (str(e),))

      else:

         g.assurt(self.shpf_class == 'incapacitated')

   #
   def close_log(self):

      if self.stats_f is not None:
         self.stats_f.close()
         self.stats_f = None

   # ***

   #
   def spats_stew(self):

      self.prepare_log()
      self.create_log()
      self.close_log()

   #
   def create_log(self):

      self.log('')
      #self.log('Hear ye! Hear ye! These be teh stets!')
      self.log('%s %s' % (', '.join(['Hear ye!'] * 2), 'These be teh stets!',))
      self.log('-------------------------------------')

      # *** Source Feature Counts

      self.log('')
      self.log('** Feature counts / Source Shapefiles **')
      self.log('')
      #
      self.log('Features from the Import Shapefile:      %9d'
               % (self.import_lyr.GetFeatureCount(),))
      if self.agency_lyr is not None:
         self.log('Features from the Agency Shapefile:      %9d'
                  % (self.agency_lyr.GetFeatureCount(),))

      # *** FIXMEs

      total_fixmes = (
           0
         + self.stats['fixme_empty_geom']
         + self.stats['fixme_bad_geom_type']
         + self.stats['fixme_bad_geom_unsimple']
         + self.stats['fixme_bad_geom_ring']
         + self.stats['fixme_multi_geom_src']
         + self.stats['fixme_multi_geom_fin']
         + self.stats['fixme_multiple_cmds']
         + self.stats['fixme_node_mismatch']
         + self.stats['fixme_mismatch_grpee']
         + self.stats['fixme_bad_byway_geom']
         + self.stats['fixme_other_reason']
         + self.stats['fixme_wrong_action']
         + self.stats['fixme_negative_ccp_id']
         + self.stats['fixme_missing_feats']
         #
         + self.stats['splits_m_val_shared']
         + self.stats['splits_m_val_overlapped']
         + self.stats['splits_fcommand_varies']
         )

      self.log('')
      self.log('** Feature counts / Unconsumed features **')
      self.log('')
      #
      self.log('FIXME / Empty Geometries:                %9d'
               % (self.stats['fixme_empty_geom'],))
      #
      self.log('FIXME / Bad Geometry: Wrong Type:        %9d'
               % (self.stats['fixme_bad_geom_type'],))
      self.log('FIXME / Bad Geometry: Not Simple:        %9d'
               % (self.stats['fixme_bad_geom_unsimple'],))
      self.log('FIXME / Bad Geometry: Ring:              %9d'
               % (self.stats['fixme_bad_geom_ring'],))
      #
      # FIXME: Add FIXME / Bad Geometry: Coincident.
      #
      #
      self.log('FIXME / Multi-Geometries (Source count): %9d'
               % (self.stats['fixme_multi_geom_src'],))
      self.log('FIXME / New Features from Multi-Geoms:   %9d'
               % (self.stats['fixme_multi_geom_fin'],))
      #
      self.log('FIXME / Features With Conflicting Cmds:  %9d'
               % (self.stats['fixme_multiple_cmds'],))
      self.log('FIXME / Features Whose Nodes Mismatch:   %9d'
               % (self.stats['fixme_node_mismatch'],))
      self.log('FIXME / Features Grouped w/ Mismatches:  %9d'
               % (self.stats['fixme_mismatch_grpee'],))
      self.log('FIXME / Missing Feats w/ Bad Byway Geom: %9d'
               % (self.stats['fixme_bad_byway_geom'],))
      #
      self.log('FIXME / Was Marked FIXME:                %9d'
               % (self.stats['fixme_other_reason'],))
      self.log('FIXME / Unknown _ACTION:                 %9d'
               % (self.stats['fixme_wrong_action'],))
      #
      self.log('FIXME / Negative Ccp IDs:                %9d'
               % (self.stats['fixme_negative_ccp_id'],))
      #
      self.log('FIXME / Missing Agy Features:            %9d'
               % (self.stats['fixme_missing_feats'],))
      #
      self.log('------------------------------------------------')
      self.log('***** TOTAL FIXMEs:                      %9d'
               % (total_fixmes,))

      # *** Ignores

      total_ignores = self.stats['ignore_fts_total']

      self.log('')
      self.log('** Feature counts / Ignored features **')
      self.log('')
      #
      self.log('IGNORE / _ACTION = "Ignore":             %9d'
               % (self.stats['ignore_fts_total'],))
      #
      self.log('------------------------------------------------')
      self.log('***** TOTAL Ignores:                     %9d'
               % (total_ignores,))

      # *** Byway Nodes

      # FIXME: Implement node stats.

      # *** Valid Features

      total_count_fids = (
           0
         + self.stats['count_fids_ccp']
         + self.stats['count_fids_agy']
         + self.stats['count_fids_new']
         )

      self.log('')
      self.log('** Feature counts / Valid features **')
      self.log('')
      #
      self.log('VALID / Cyclopath Matches:               %9d'
               % (self.stats['count_fids_ccp'],))
      self.log('VALID / New and Conflated:               %9d'
               % (self.stats['count_fids_agy'],))
      self.log('VALID / Unknown and Unconflated:         %9d'
               % (self.stats['count_fids_new'],))
      #
      self.log('------------------------------------------------')
      self.log('***** TOTAL Valid Features:              %9d'
               % (total_count_fids,))

      # *** Stats Stats

      total_features_examined = (
           0
         + total_fixmes
         + total_ignores
         + total_count_fids
         )

      self.log('')
      self.log('** Feature counts / All features **')
      self.log('')
      #
      self.log('FIXME  / All FIXMEs:                     %9d'
               % (total_fixmes,))
      self.log('Ignore / All Ignored:                    %9d'
               % (total_ignores,))
      self.log('VALID  / All Valid:                      %9d'
               % (total_count_fids,))
      #
      self.log('------------------------------------------------')
      self.log('***** TOTAL Features Examined:           %9d'
               % (total_features_examined,))

      # *** Processing stats

      self.log('')
      self.log('** Processing stats / Matched features **')
      self.log('')

      self.log('FIXME / Splits with 1+ Shared M-Values:  %9d'
               % (self.stats['splits_m_val_shared'],))
      self.log('FIXME / Splits with Overlapped M-Values: %9d'
               % (self.stats['splits_m_val_overlapped'],))
      self.log('FIXME / Splits with Feat. Cmd Variation: %9d'
               % (self.stats['splits_fcommand_varies'],))

      # FIXME: Clean up the remaining stats code.

      #
      #
      self.log('Update features reversed:                %9d'
               % (self.stats['split_fts_reversed'],))
      self.log('Update features unreversed:              %9d'
               % (self.stats['split_fts_unreversed'],))
      self.log('')
      #
      self.log('Self-splits equal:                       %9d'
               % (self.stats['split_self_split_equal'],))
      self.log('Self-splits unique:                      %9d'
               % (self.stats['split_self_split_unique'],))
      #
      # FIXME: Missing has two meanings in this file: split segments that were
      # not created, and features in update but not in conflated.
      self.log('Splits missed / beginning:               %9d'
               % (self.stats['split_missing_beg'],))
      self.log('Splits missed / insiding:                %9d'
               % (self.stats['split_missing_inn'],))
      self.log('Splits missed / ending:                  %9d'
               % (self.stats['split_missing_fin'],))
      # FIXME: This is ... more important and should be up higher.
      self.log('Conjoined split features:                %9d'
               % (self.stats['split_fts_conjoined'],))
      #
      self.log('')
      #
      self.log('Superconflated features:                 %9d'
               % (self.stats['split_fts_superconflated'],))
      #
      self.log('')
      #
      self.log('Agency XY near Ccp Node:                 %9d'
               % (self.stats['split_nodes_nearby_cnt'],))
      #
      self.log('Updated Byways (1-1 Matches):            %9d'
               % (self.stats['splitsets_1to1_matches'],))
      #
      self.log('')
      #
      self.log('New Byways (Referenced):                 %9d'
               % (self.stats['count_new_byways_refed'],))
      self.log('New Byways (Totally New):                %9d'
               % (self.stats['count_new_byways_newed'],))
      self.log('')
      self.log('New Byways (Not Split):                  %9d'
               % (self.stats['count_new_byways_not_split'],))
      self.log('')
      self.log('New Byways Total:                        %9d'
               % (self.stats['count_new_byways_total'],))
      #
      self.log('')
      #
      self.log('Link Values Total:                       %9d'
               % (self.stats['count_link_values_all'],))
      self.log('Link Values Created:                     %9d'
               % (self.stats['count_link_values_new'],))
      self.log('Link Values Updated:                     %9d'
               % (self.stats['count_link_values_old'],))
      #
      self.log('')
      #
      self.log('String Fields w/ Space Values:           %9d'
               % (self.stats['field_string_spaces'],))

      #
      self.log('')
      #
      # HACK:
      self.log('Node ID Match Stats: Expected vs. Actual FIXMEs:')
      counts = node_endpoint.One.n_node_id_matches.keys()
      counts.sort()
      for stat_count_diff in counts:
         count = node_endpoint.One.n_node_id_matches[stat_count_diff]
         self.log('    num. nodes different: %7d / cnt: %9d'
                  % (stat_count_diff, count,))

      #
      self.log('')
      #
      threshold_fcn = lambda bval, blen: bval >= 20 or blen < 5
      self.stats_write_bucket_stat(
         'No. old byways per no. new segments before conjoin',
         'split_fts_x_counts_1', threshold_fcn)
      self.stats_write_bucket_stat(
         'No. old byways per no. new segments when split',
         'split_fts_x_counts_2', threshold_fcn)
      #
      self.log('')
      #
      self.stats_write_bucket_stat(
         "No. new xys per dist from update feature's xy",
         'split_nodes_geom_x_counts')

      #
      self.log('')
      #
      # The bikeways update data has lots of attribute gaps. We're going to end
      # up with lots of tiny segments. This is to check that we succeed.
      threshold_fcn = lambda bval, blen: bval > 4 or blen < 2
      self.stats_write_bucket_stat(
         'No. features per no. differences when compared',
         'compare_feats_x_differences', threshold_fcn)
      #
      self.stats_write_bucket_stat(
         'No. features per difference-type when compared',
         'compare_difftype_x_feats')
      logged_preamble = False
      #difftypes = ''
      difftype = 1
      bucket_keys = self.stats['compare_difftype_x_feats'].keys()
      for ta_def in self.defs.attrs_metadata:
         if ta_def.comparable:
            if difftype in bucket_keys:
               if not logged_preamble:
                  self.log('  .. for difftypes:')
                  logged_preamble = True
               self.log("     [%9d] => '%s'" % (difftype, ta_def.attr_source,))
            #difftypes += ', %9d (%s)' % (difftype, ta_def.attr_source,)
            difftype += 1
      #self.log('  .. for difftypes: %s' % (difftypes,))

      #
      self.log('')
      #
      self.log('No. first split seg node mismatches:     %9d'
               % (len(self.stats['split_missing_mismatch_first']),))
      mismatch_cnt = 1
      for mismatch_tup in self.stats['split_missing_mismatch_first']:
         log.warning(' %4d. cnf: %s' % (mismatch_cnt, mismatch_tup[0],))
         log.warning('       src: %s' % (mismatch_tup[1],))
         log.warning(' old_byway: %s' % (mismatch_tup[2],))
         mismatch_cnt += 1

      #
      self.log('')
      #
      self.log('No. final split seg node mismatches:     %9d'
               % (len(self.stats['split_missing_mismatch_final']),))
      mismatch_cnt = 1
      for mismatch_tup in self.stats['split_missing_mismatch_final']:
         log.warning(' %4d. cnf: %s' % (mismatch_cnt, mismatch_tup[0],))
         log.warning('       src: %s' % (mismatch_tup[1],))
         log.warning(' old_byway: %s' % (mismatch_tup[2],))
         mismatch_cnt += 1

      # FIXME: Can we report the total execution time?

      #
      self.log('')
      #

   # ***

   #
   def stats_bucket_usage_increment(self, stat_key, bucket_value):
      self.stats[stat_key].setdefault(bucket_value, 0)
      self.stats[stat_key][bucket_value] += 1

   #
   def stats_bucket_usage_remember(self, stat_key, bucket_value, payload):
      self.stats[stat_key].setdefault(bucket_value, list())
      self.stats[stat_key][bucket_value].append(payload)

   #
   def stats_write_bucket_stat(self, desc, stats_key, threshold_fcn=None):
      self.log('%s:' % (desc,))
      stat_bucket = self.stats[stats_key]
      if not stat_bucket:
         self.log('  bucket empty!')
      else:
         self.stats_write_bucket_stat_(stat_bucket, None)
         if threshold_fcn is not None:
            self.stats_write_bucket_stat_(stat_bucket, threshold_fcn)

   #
   def stats_write_bucket_stat_(self, stat_bucket, threshold_fcn):
      bucket_values = stat_bucket.keys()
      bucket_values.sort()
      last_log = ''
      if threshold_fcn is not None:
         last_log = '-- Repeat of previous for ArcMap cxpx --'
      for bucket_value in bucket_values:
         bucket_payload = stat_bucket[bucket_value]
         payloads = ''
         if isinstance(bucket_payload, int):
            bucket_len = bucket_payload
         else:
            g.assurt(isinstance(bucket_payload, list))
            bucket_len = len(bucket_payload)
            # Include the payloads for outliers.
            if ((threshold_fcn is not None)
                and threshold_fcn(bucket_value, bucket_len)):
               # FIXME: For use in ArcMap, maybe just print() this, and
               # maybe do it after stats so it's not so messy on my screen.
               payloads = (' (%s)'
                           % (','.join([str(x) for x in bucket_payload]),))
         if threshold_fcn is None:
            self.log('  >> [%9d] => used x %9d%s'
                     % (bucket_value, bucket_len, payloads,))
         elif payloads:
            if last_log:
               self.log(last_log)
               last_log = ''
            msg = ('  >> [%9d] => used x %9d%s'
                   % (bucket_value, bucket_len, payloads,))
            print(msg)
            if self.stats_f is not None:
               self.stats_f.write(msg)
               self.stats_f.write('\n')

   # ***

# ***

if (__name__ == '__main__'):
   pass


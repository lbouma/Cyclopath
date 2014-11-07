# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import re
import sys
import time

import conf
import g

log = g.log.getLogger('import_cyclop')

from util_ import misc

from merge.import_items_ccp import Import_Items_Ccp

class Import_Cyclop(Import_Items_Ccp):

   stage_num_base = None

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Import_Items_Ccp.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Import_Items_Ccp.reinit(self)

   # ***

   #
   def job_cleanup(self):
      Import_Items_Ccp.job_cleanup(self)

   # *** Substages

   #
   def make_substage_lookup(self):
      substage_lookup = [
         self.substage_prepare_shapefile,
         self.substage_preprocess_feats,
         self.substage_find_missing,
         self.substage_process_fids_ccp,
         self.substage_process_fids_agy,
         self.substage_process_fids_new,
         self.substage_fix_connectivity,
         self.substage_process_cleanup,
         ]
      Import_Items_Ccp.make_substage_lookup(self, Import_Cyclop.stage_num_base,
                                                 substage_lookup)

   #
   def feature_classes_import(self):
      # If we start load a Shapefile and don't find a Cyclopath config, and if
      # we're not conflating, we skip it.
      if self.shpf_class != 'incapacitated':
         time_0 = time.time()
         # Call the substage fcn.
         self.substage_fcn_go()
         # Print elapsed time.
         log.info('... done "%s" in %s'
                  % (self.mjob.wtem.latest_step.stage_name,
                     misc.time_format_elapsed(time_0),))
      else:
         # We still have to call stage_initialize to bump the stage num.
         self.mjob.stage_initialize('Skipping Shapefile...')

   # Substage 1
   def substage_prepare_shapefile(self):
      self.mjob.stage_initialize('Analyzing Shapefile')
      self.import_initialize()

   # Substage 2
   def substage_preprocess_feats(self):
      self.mjob.stage_initialize('Preprocessing Source Features')
      # Load the features from the source shapefile and do simple validation.
      self.shapefile_organize_feats()

   # Substage 3
   def substage_find_missing(self):
      self.mjob.stage_initialize('Finding Missing Features')
      # Add missing update features to the target shapefile.
      if (self.agency_lyr is not None) and (not self.debug.debug_skip_missing):
         self.missing_features_consume()

   # Substage 4
   def substage_process_fids_ccp(self):
      self.mjob.stage_initialize('Importing Matched Features')
      # Assemble all the split features and replace any missing geometry.
      # This fcn. is in the splits derived class and is used for both roadmr
      # and cyclop import_types. This fcn. may raise an exception (for why?)
      self.fids_ccp_consume()

   # Substage 5
   def substage_process_fids_agy(self):
      self.mjob.stage_initialize('Importing Unmatched Features')
      # Consume self.fids_agy.
      self.fids_agy_consume()

   # Substage 6
   def substage_process_fids_new(self):
      self.mjob.stage_initialize('Processing Unconflated Features')
      # Conflate self.fids_agy.
      self.fids_new_consume()

   # Substage 7
   def substage_fix_connectivity(self):
      self.mjob.stage_initialize('Fixing Network Connectivity')
      # Go through the features' endpoints and fix intersections.
      self.audit_connectivity()

   # Substage 8
   def substage_process_cleanup(self):
      self.mjob.stage_initialize('Cleaning up and Saving Shapefiles')
      # Copy from the temporary layers to the target layers (since OGR does not
      # support deleting fields, the only way to remove fields is create a new
      # layer without 'em). The save makes the new layers and the cleanup
      # deletes the old (temp) layers. We'll save the Shapefile in the base
      # class, via substage_cleanup, since we share that code with export.
      self.target_layers_save() # this fcn. uses a prog_log
      self.target_layers_cleanup() # this fcn. is quick

      # NOTE: This script does not create branch conflicts. Those are created
      #       when you run an 'update' operation on the branch. I [lb] say
      #       this now because I keep thinking I need to make branch
      #       conflicts in this script....
      # BUG nnnn: Can you find and resolve conflicts in ArcGIS by loading the
      #           latest Ccp revision and comparing three layers: old Ccp rev,
      #           new Ccp rev, and Bikeways branch?

# ***

if (__name__ == '__main__'):
   pass


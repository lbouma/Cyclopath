# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import sys
import time

import conf
import g

from item.feat import byway
from item.feat import region
from item.feat import terrain
from item.feat import waypoint
from item.util.item_type import Item_Type
from util_ import misc

from merge.export_base import Export_Base

log = g.log.getLogger('export_cyclop')

class Export_Cyclop(Export_Base):

   stage_num_base = None

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Export_Base.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Export_Base.reinit(self)

   # *** Substages

   #
   def make_substage_lookup(self):
      substage_lookup = [
         self.substage_initialize,
         self.substage_export_byway,
# FIXME: Implement these:
         #self.substage_export_region,
         #self.substage_export_terrain,
         #self.substage_export_waypoint,
         self.substage_export_cleanup,
         ]
      Export_Base.make_substage_lookup(self, Export_Cyclop.stage_num_base,
                                             substage_lookup)

   #
   def feature_classes_export(self):
      self.substage_fcn_go()

   # Substage 1
   def substage_initialize(self):
      self.mjob.stage_initialize('Init export')

      # The base classes use spf_conf which hasn't been defined yet.
      g.assurt(self.mjob.wtem.for_revision)
      self.spf_conf.revision_id = self.mjob.wtem.for_revision
      g.assurt(self.mjob.wtem.branch_id)
      self.spf_conf.branch_id = self.mjob.wtem.branch_id

      all_errs = []
      self.setup_qbs(all_errs)
      g.assurt(not all_errs)

      # We raise in setup_qbs if anything goes wrong -- which it really
      # shouldn't for export, since our work_item cannot be created in the
      # first place if the branch doesn't exist (as opposed to import, where
      # the branch id or branch name the user specifies in the Shapefile could
      # be wrong).
      g.assurt(self.spf_conf.branch_id == self.mjob.wtem.branch_id)
      g.assurt(self.qb_src.branch_hier[0][0] == self.spf_conf.branch_id)
      # But unlike import, where the user may or may not specify the branch
      # name (they can specify the branch id and/or the branch name), export
      # only ever uses the branch ID, and then setup_qbs updates the spf_conf's
      # branch_name.
      g.assurt(self.qb_src.branch_hier[0][2] == self.spf_conf.branch_name)

      log.debug('substage_initialize: spf_conf: %s' % (str(self.spf_conf),))

      self.shapefile_engine_prepare()

      self.shapefile_create_targets(skip_tmps=True)

      # Create the geometry-less config "features".
      self.ccp_conf_create_feats()

   # Substage 2
   def substage_export_byway(self):
      self.mjob.stage_initialize('Export byway')
      self.load_and_export_items(byway)

   # Substage 3
   def substage_export_region(self):
      self.mjob.stage_initialize('Export region')
      self.load_and_export_items(region)

   # Substage 4
   def substage_export_terrain(self):
      self.mjob.stage_initialize('Export terrain')
      self.load_and_export_items(terrain)

   # Substage 5
   def substage_export_waypoint(self):
      # FIXME: Rename waypoint -> geopoint (ask mm and ml first)
      self.mjob.stage_initialize('Export waypoint')
      self.load_and_export_items(waypoint)

   # Substage 6
   def substage_export_cleanup(self):
      self.mjob.stage_initialize('Cleanup export')
      # NOTE: The substage controller will increment stage_num_times and will
      # call substage_cleanup, which calls shapefile_release_targets, which
      # saves and closes the target Shapefiles.
      # Nothing to do...
      pass

   # ***

   #
   def load_and_export_items(self, feat_class):

      log.info('load_and_export_items: working on type: %s'
               % (Item_Type.id_to_str(feat_class.One.item_type_id),))

      time_0 = time.time()

      prog_log = self.progr_get(log_freq=100)

      self.qb_src.filters.rating_special = True

      self.qb_src.filters.include_item_stack = True

      log.debug('load_and_export_items: filter_by_regions: %s'
                % (self.qb_src.filters.filter_by_regions),)

      # The merge_job setup the item_mgr, which we use now to load the byways
      # and their attrs and tags.
      feat_search_fcn = 'search_for_items' # E.g. byway.Many().search_for_items
      
      self.qb_src.item_mgr.load_feats_and_attcs(
            self.qb_src, feat_class, feat_search_fcn,
            processing_fcn=self.feat_export,
            prog_log=prog_log,
            heavyweight=False)

      log.info('... exported %d features in %s'
               % (prog_log.progress,
                  misc.time_format_elapsed(time_0),))

   # ***

   #
   def feat_export(self, qb, gf, prog_log):

      # On export, there really is no context. It's all... Cyclopath.

      new_feat = self.field_val_setup_all(gf, context='')

      # FIXME: see temp_layer_add -- check geom for validness
      #        Or does that only matter for PostGIS, when importing features?

   # ***

# ***

if (__name__ == '__main__'):
   pass


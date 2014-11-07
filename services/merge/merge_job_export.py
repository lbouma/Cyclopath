# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: If you make changes to this file, be sure to restart Mr. Do!

import os
import shutil
import sys
import time

import conf
import g

from grax.access_level import Access_Level
#from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from item.feat import branch
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from util_ import db_glue
from util_.path_helper import Path_Helper

from merge.make_ccp_yml import Make_Ccp_Yml
from merge.ccp_export import Ccp_Export
from merge.export_cyclop import Export_Cyclop
from merge.merge_job_base import Merge_Job_Base

__all__ = ('Merge_Job_Export',)

log = g.log.getLogger('merg_job_exp')

# ***

class Merge_Job_Export(Merge_Job_Base):

   __slots__ = (
      )

   # *** Constructor

   def __init__(self, wtem, mr_do):
      Merge_Job_Base.__init__(self, wtem, mr_do)

   # *** 

   #
   @staticmethod
   def process_request(wtem, mr_do):
      mi = Merge_Job_Export(wtem, mr_do)
      mi.process_request_()

   # *** 

   #
   def job_cleanup(self):
      Merge_Job_Base.job_cleanup(self)

   #
   def process_request_(self):
      Merge_Job_Base.process_request_(self)

   # *** The stage function lookup.

   #
   def make_stage_lookup(self):

      # Make a fake handler just to see how many substages it has.
      handler = Ccp_Export(self, None)
      g.assurt(self.handler is not None)
      # The handler is triggered by do_do_export. It eventually  calls 
      # feature_classes_export.
      n_sub_stages = len(handler.substage_lookup)
      # The substage handler is called multiple times, one for each substage.
      do_do_exports = n_sub_stages * [self.do_do_export,]

      self.stage_lookup = []
      self.stage_lookup += [
         self.do_reserve_directory,          # Stages 1-2.
         self.do_make_import_config,
         ]
      Export_Cyclop.stage_num_base = len(self.stage_lookup) + 1
      self.stage_lookup += do_do_exports     # A bunch more stages.
      self.stage_lookup += [
         self.do_create_archive,             # The cleanup stages.
         self.do_notify_users,
         self.job_mark_complete,
         ]

      self.handler = None
      handler = None

   # *** Stage fcn. defs

   # *** STAGE 1: SECURE DIR.

   #
   def do_reserve_directory(self):

      self.stage_initialize('Reserving directory')

      fpath, rand_path = Path_Helper.path_reserve(
                           basedir=conf.shapefile_directory,
                           extension='', is_dir=False)

      log.debug('do_reserve_directory: rand_path: %s' % (rand_path,))
      log.verbose('do_reserve_directory: wtem: %s' % (self.wtem,))

      # Remember the path.
      g.assurt(not self.wtem.local_file_guid)
      self.wtem.local_file_guid = rand_path
      # Resave the work item job data.
      # FIXME: It's not obvious that local_file_guid is part of job_def.
      self.wtem.job_data_update()

      # Make the dummy 'usr' directory (we use it just for the yml, to appease
      # the code originally writ for import and now being used for export).
      oname = '%s.usr' % (self.wtem.local_file_guid,)
      opath = os.path.join(conf.shapefile_directory, oname)
      try:
         os.mkdir(opath)
         # 2013.05.06: Need to chmod?
         os.chmod(opath, 02775)
      except OSError, e:
         g.assurt(False)
         raise

   # *** STAGE 2: CREATE YML.

   #
   def do_make_import_config(self):

      self.stage_initialize('Creating YML')

      log.verbose('do_make_import_config: wtem: %s' % (self.wtem,))

      if Merge_Job_Base.use_yaml_conf:

         cfg_path = self.get_import_config_path('usr')

         g.assurt(self.handler.qb_src is not None)
         as_yml = Make_Ccp_Yml.produce(self.handler.qb_src, self.wtem)

         try:
            #as_yml = yaml.dump(self.cfg, default_flow_style=True)
            yaml_stream = file(cfg_path, 'w')
            yaml_stream.write(as_yml)
            yaml_stream.close()
         except Exception, e:
            failure_reason = (
               'merge_job_export cannot save yaml file: %s / %s' 
               % (cfg_path, str(e),))
            self.job_mark_failed(failure_reason)

      # else, not using ccp.yml.

   # *** STAGE 3: EXPORT CCP.

   #
   def do_do_export(self):

      # NOTE: This fcn. gets called multiple times, once for each substage.
      # Skipping: self.stage_initialize

      log.verbose('do_do_export: wtem: %s' % (self.wtem,))

      self.do_import_or_export('export_callback')

   # *** STAGE 4: CREATE ZIP.

   #
   def do_create_archive(self):

      # The import code is written to expect a 'usr' and an 'out' directory,
      # and expects the input yml to be in the 'usr' directory. Since the
      # import doesn't create an output yml file (that's our job) just copy the
      # one we already created.
      if Merge_Job_Base.use_yaml_conf:
         try:
            cfg_src = self.get_import_config_path('usr')
            cfg_cur = self.get_import_config_path('cur')
            shutil.copy(cfg_src, cfg_cur)
         except IOError, e:
            log.warning('Could not copy yaml config: %s' % (str(e),))
            raise
      # else, the handler added geometryless fields to the shapefile by
      #       calling Ccp_Merge_Conf.record_as_feats().

      # 2013.05.02: Include the Shapefile metadata, and license.
      # MAGIC_NUMBERS: Hard-coding well known paths.
      oname = '%s.out' % self.wtem.local_file_guid
      # SYNC_ME: self.file_driver.CreateDataSource uses this zipname.
      opath = os.path.join(
         conf.shapefile_directory, oname, self.wtem.get_zipname())
      #
      # FIXME/BUG nnnn: This is the public basemap's metadata, so it's missing
      # any metadata about attributes specific to leafy branches. E.g., if
      # you're exporting the Metc Bikeways 2012 branch, the metadata is missing
      # the bike_facil attribute, which is specific to Metc.

      # os.curdir is '.', and its os.abspath is '/'.
      # sys.path[0] is the path to the simplejson library...
      # so we cheat and use the environment variable.
      metadata_path = os.path.abspath(
         '%s/../scripts/daily/export_docs/metadata/ccp_road_network.htm'
         % (os.path.abspath(os.environ['PYSERVER_HOME']),))
      shutil.copy(metadata_path, opath)
      #
      license_path = os.path.abspath(
         '%s/../scripts/daily/export_docs/metadata/LICENSE.txt'
         % (os.path.abspath(os.environ['PYSERVER_HOME']),))
      shutil.copy(license_path, opath)

# FIXME_2013_06_11: Revisit this.
# FIXME: Does route_analysis.py include the license and its metadata?


      # Call the work_item_job base class to zip up the 'out' directory 
      # and copy the zip to the 'out' directory.
      Merge_Job_Base.do_create_archive(self)

   # *** STAGE 5: NOTIFY PPL.

   #
   def do_notify_users(self):

      Merge_Job_Base.do_notify_users(self)

   # ***

# ***

if (__name__ == '__main__'):
   pass


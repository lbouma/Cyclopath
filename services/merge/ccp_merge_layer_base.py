# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

import os
import re
import sys
import time

import conf
import g

log = g.log.getLogger('ccpio_lyr_bs')

from util_ import db_glue
from util_.shapefile_wrapper import Shapefile_Wrapper

from merge.ccp_merge_attrs import Ccp_Merge_Attrs

class Ccp_Merge_Layer_Base(Ccp_Merge_Attrs):

   __slots__ = (
      # The OGRSFDriver for Shapefiles, whose name is 'ESRI Shapefile'.
      'file_driver',
      # The OGRDataSource of the target Shapefile; essentially this is just a
      # directory on the hard drive.
      'outp_datasrc',
      # An OGRSpatialReference object. The projection used by the Shapefiles
      # should match the production you've set for Cyclopath.
      'spat_ref',
      # Collections of Shapefiles. Or, more specifically, layers: in OGR, these
      # are OGRLayer objects, which are part of a data source (or folder on
      # your hard drive). Note that the 'temp' layers are only used during
      # processing and are deleted later (OGR does not support deleting fields
      # from a layer (i.e., OGRFields from an OGRLayers), so we copy select
      # fields from 'temp' to 'final' and save just the 'final' layers).
      'target_layers_final',
      'target_layers_temp',
      'target_layers_temp_names',
      )

   # *** Constructor

   def __init__(self, mjob, branch_defs):
      Ccp_Merge_Attrs.__init__(self, mjob, branch_defs)

   # ***

   #
   def reinit(self):
      Ccp_Merge_Attrs.reinit(self)
      self.file_driver = None
      self.outp_datasrc = None
      self.spat_ref = None
      self.target_layers_final = {}
      self.target_layers_temp = {}
      self.target_layers_temp_names = set()

   # ***

   #
   def substage_cleanup(self, maybe_commit):
      # The import might skip a sequence of substages if the Shapefile cannot
      # be processed; see self.shpf_class == 'incapacitated'. Otherwise, save
      # the target Shapefile layer.
      if self.outp_datasrc is not None:
         self.shapefile_release_targets()
      Ccp_Merge_Attrs.substage_cleanup(self, maybe_commit)

   # ***

   # FIXMEBUTNOTNOW: These could be util fcns., or a new util class.

   #
   def shapefile_engine_prepare(self):

      log.info('Preparing shapefiles engine...')

      # OGR provides dozens of drivers to read different types of file formats.
      # But I can't find the documention (list of drivers) online. So just
      # snoop.
      # FIXME: Do this just if debugging.
      for driver_i in xrange(ogr.GetDriverCount()):
         log.verbose(' >> ogr driver[%d]: %s' 
                     % (driver_i, ogr.GetDriver(driver_i).GetName(),))

      # We want the shapefile driver, which is also the first one in the list.
      self.file_driver = ogr.GetDriverByName('ESRI Shapefile')

      # Make the '.out' and '.fin' directories.
      opath = self.mjob.make_working_directories()

      # The datasource is just another directory, and each layer is saved as a
      #   Shapefile, so it doesn't make sense to let the user have much 
      #   influence over what we name these files.
      # Make the folder name the same as the zip we'll create, 
      #   e.g., "Cyclopath-Export".
      datasource_name = self.mjob.wtem.get_zipname()
      spath = os.path.join(opath, datasource_name)

      log.debug('shapefile_engine_prepare: spath:')
      log.debug('%s' % (spath,))
      self.outp_datasrc = self.file_driver.CreateDataSource(spath)

      # 2014.09.04: chmod, lest: `ls -l ./...out`:
      #  drwxr-s--- 2 www-data www-data 4.0K 2014-08-19 13:14 Cyclopath-Export/
      os.chmod(spath, 02775)

      self.spat_ref = osr.SpatialReference()
      # This is wrong: 
      #   self.spat_ref.SetWellKnownGeogCS('WGS84')
      # This just writes some meta info:
      #   self.spat_ref.SetWellKnownGeogCS('NAD83')
      # But this writes just the basics:
      #   nZone = 15
      #   bNorth = True
      #   self.spat_ref.SetUTM(nZone, bNorth)
      # i.e., the basics are:
      #   PROJECTION["Transverse_Mercator"],
      #   PARAMETER["latitude_of_origin",0],
      #   PARAMETER["central_meridian",-93],
      #   PARAMETER["scale_factor",0.9996],
      #   PARAMETER["false_easting",500000],
      #   PARAMETER["false_northing",0],
      #   UNIT["Meter",1]]
      # The documentation says this should work but I get nothing:
      #   self.spat_ref.SetWellKnownGeogCS('EPSG:26915')
      # But I found that this works:
      #   self.spat_ref.ImportFromEPSG(26915)
      self.spat_ref.ImportFromEPSG(conf.default_srid)

   #
   def shapefile_create_targets(self, skip_tmps=False):

      log.info('Creating target shapefile layers...')

      #gdb_handle = ogr.Open(self.mjob.cfg.export_name, bUpdate)
      # FIXME: If Python says outp_datasrc is 'NoneType', means files already
      #        exist, so delete the missing.shp first

      g.assurt(not len(self.target_layers_final))
      g.assurt(not len(self.target_layers_temp))
      g.assurt(not len(self.target_layers_temp_names))

      # Name the layers like the original layers are named...
      # FIXME: on import don't read any layer ending 'Rejected'?? Or do these 
      # have _ACTION='Ignore'?

      for lname in self.get_output_layer_names():

         log.debug('shapefile_create_targets: layer: %s' % (lname,))
         # Make the target layer.
         self.target_layers_final[lname] = (
                  self.outp_datasrc.CreateLayer(
                        lname, self.spat_ref, ogr.wkbLineString25D))
         # Make the temporary layer.
         if not skip_tmps:
            tname = lname + '_tmp'
            self.target_layers_temp[lname] = (
                  self.outp_datasrc.CreateLayer(
                        tname, self.spat_ref, ogr.wkbLineString25D))
            self.target_layers_temp_names.add(tname)

      # Debug fcns. Existing and new ESRI shapefiles all seem to support random
      # access based on FID. But only new shapefiles support CreateField.
      for lname, layer in self.target_layers_final.iteritems():
         Shapefile_Wrapper.gdb_layer_test_capabilities(layer)

      # Create a bunch of fields.
      if not skip_tmps:
         for fname, ftype, field_width in self.defs.attrs_temporary:
            field_defn = ogr.FieldDefn(fname, ftype)
            self.shapefile_target_create_field(field_defn, 
                                               self.target_layers_temp, 
                                               field_width)
      for ta_def in self.defs.attrs_metadata:
         # Create the new target field.
         if ta_def.field_target:
            field_name = ta_def.field_target
            field_defn = ogr.FieldDefn(field_name, ta_def.field_type)
            self.shapefile_target_create_field(field_defn, 
                                               self.target_layers_final,
                                               ta_def.field_width)
            if not skip_tmps:
               self.shapefile_target_create_field(field_defn, 
                                                  self.target_layers_temp,
                                                  ta_def.field_width)
         # Create a temporary field for the old-named field.
         if not skip_tmps:
            if ((ta_def.field_source)
                and (ta_def.field_source.lower()
                     != ta_def.field_target.lower())):
               field_name = ta_def.field_source
               field_defn = ogr.FieldDefn(field_name, ta_def.field_type)
               self.shapefile_target_create_field(field_defn, 
                                                  self.target_layers_temp,
                                                  ta_def.field_width)

   #
   def shapefile_target_create_field(self, field_defn, layer_lookup, 
                                           field_width):
      # Warning 6: Normalized/laundered field name: 'SURF_TYPE' to 'SURF_TYP_1'
      for lname, layer in layer_lookup.iteritems():
         ogr_err = layer.CreateField(field_defn)
         g.assurt(not ogr_err)
         if field_defn.GetType() == ogr.OFTString:
            # Readjust its width.
            g.assurt(int(field_width) > 0)
            # The default width is 0.
            cur_width = field_defn.GetWidth()
            if cur_width != field_width:
               field_defn.SetWidth(field_width)
            log.verbose('_create_field: OFTString width was: %d/ now: %d'
                        % (cur_width, field_width,))
         else:
            g.assurt(field_width is None)

   #
   def shapefile_release_targets(self):

      log.info('Saving target shapefile layers...')

      # We could iterate through the individual layers in target_layers_final 
      # or we could just tell the data source to save. But because I'm [lb]
      # O.C.D., let's do both.

      g.assurt(self.outp_datasrc is not None)
      g.assurt(self.file_driver is not None)

      layer_nums = xrange(self.outp_datasrc.GetLayerCount())
      for layer_i in layer_nums:
         layer = self.outp_datasrc.GetLayer(layer_i)
         #lname = layer.GetName()
         layer.SyncToDisk()

      # This does the exact same thing.
      for lname, layer in self.target_layers_final.iteritems():
         layer.SyncToDisk()

      self.target_layers_final = {}

      g.assurt(not self.target_layers_temp)
      g.assurt(not self.target_layers_temp_names)

      self.outp_datasrc.SyncToDisk()

      log.debug('shapefile_release_targets: Closing target data source.')

      self.outp_datasrc.Release()
      self.outp_datasrc = None

      # The C OGR supports self.file_driver.Release() but not the Py OGR.
      self.file_driver = None

   # ***

# ***

if (__name__ == '__main__'):
   pass


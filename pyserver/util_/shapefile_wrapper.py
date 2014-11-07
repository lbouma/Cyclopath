# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

import os
import sys

import conf
import g

log = g.log.getLogger('shapefile_wr')

# ***

#
def ojint(openjump_int):
   # OpenJUMP adds a '.0' after the integer and makes the field a string
   # when you edit an integer... heh? I'm so confused... anyway, a work-around!
   try:
      if openjump_int.endswith('.0'):
         openjump_int = openjump_int[:-2]
   except AttributeError:
      # Not a string; possibly an int or float.
      pass
   return int(openjump_int)

#
def ojints(openjump_ints):
   ints = []
   try:
      # Input can be, e.g., '123', '123, 456', '[123, 456]', etc.
      ints = [ojint(x) for x in openjump_ints.strip('[]()').split(',') if x]
   except AttributeError:
      # Not a string; possibly an int or float.
      ints = [int(openjump_ints),]
      # raises if not convertible to int.
   return ints

# ***

class Shapefile_Wrapper(object):

   geom_types = {
      ogr.wkbLineString: (ogr.wkbLineString,
                          ogr.wkbLineString25D,
                          ogr.wkbMultiLineString,
                          ogr.wkbMultiLineString25D,),
      ogr.wkbPoint:      (ogr.wkbPoint,
                          ogr.wkbPoint25D,
                          ogr.wkbMultiPoint,
                          ogr.wkbMultiPoint25D,),
      ogr.wkbPolygon:    (ogr.wkbPolygon,
                          ogr.wkbPolygon25D,
                          ogr.wkbMultiPolygon,
                          ogr.wkbMultiPolygon25D,),
      }

   geom_multis = [
      ogr.wkbMultiLineString,
      ogr.wkbMultiLineString25D,
      ogr.wkbMultiPoint,
      ogr.wkbMultiPoint25D,
      ogr.wkbMultiPolygon,
      ogr.wkbMultiPolygon25D,
   ]

   __slots__ = (

      # The path to the Shapefile.
      'shp_name',
      # The main of the main ID field.
      'pkey_field',
      # The main ogr handle to the data.
      'gdb_handle',
      # We always deal w/ 1-layer Shapefiles,
      # and here it is.
      'gdb_layer',
      # This is our spatial reference system,
      'ccp_srs',
      # and this is the transform from Shapefile data.
      'geom_xform',

      # Details about the Shapefile being processed.
      'feats_geom_empty',
      'feats_geom_none',
      'feats_geom_invalid',
      'feats_geom_unsimple',
      'feats_geom_ring',
      'feats_geom_badtype',
      'feats_geom_n_single',
      'feats_geom_n_multis',
      )

   #
   def __init__(self, shp_name, pkey_field):

      self.shp_name = shp_name
      self.pkey_field = pkey_field

   # ***

   #
   def source_close(self):

      self.geom_stats_print()

      self.gdb_handle.Release()
      self.gdb_handle = None
      self.gdb_layer = None

   #
   def source_open(self):

      # *** Open the Shapefile.

      log.debug('Opening Shapefile: %s' % (self.shp_name,))

      self.gdb_handle = ogr.Open(self.shp_name)
      if self.gdb_handle is None:
         err_s = 'Could not open shapefile: %s' % (self.shp_name,)
         log.error(err_s)
         raise Exception(err_s)

      # *** Look for the geometry layer.

      if self.gdb_handle.GetLayerCount() != 1:
         err_s = ('Unexpected number of layers in Shapefile: %s'
                  % (self.gdb_handle.GetLayerCount(),))
         log.error(err_s)
         raise Exception(err_s)

      self.gdb_layer = self.gdb_handle.GetLayerByIndex(0)

      log.info('Found feature layer: %s (%d features)'
                % (self.gdb_layer.GetName(),
                   self.gdb_layer.GetFeatureCount(),))

      # *** We don't need to check the spatial ref but [lb] is cxpxing
      #      boilerplate code.

      # MAGIC_NUMBER: FIXME: This should be from conf...
      self.ccp_srs = osr.SpatialReference()
      self.ccp_srs.SetProjCS('UTM 15N (NAD83)')
      self.ccp_srs.SetWellKnownGeogCS('')
      self.ccp_srs.SetUTM(15, True)

      shapefile_srs = self.gdb_layer.GetSpatialRef()
      expected_srs = osr.SpatialReference()
      expected_srs.ImportFromEPSG(conf.default_srid)
      if shapefile_srs is None:
         log.warning('Shapefile has no SRS defined, assuming EPSG:%d'
                     % (conf.default_srid,))
         shapefile_srs = osr.SpatialReference()
         shapefile_srs.ImportFromEPSG(conf.default_srid)
      else:
         log.debug('shapefile_srs: ===========>\n%s' % (shapefile_srs,))
         g.assurt(shapefile_srs.IsSame(expected_srs))
      self.geom_xform = osr.CoordinateTransformation(shapefile_srs,
                                                     self.ccp_srs)

      if not self.gdb_layer.TestCapability(ogr.OLCRandomRead):
         err_s = ('Your Shapefile does not support Random Read of FIDs: %s'
                  % (self.shp_name,))
         #log.error(err_s)
         #raise Exception(err_s)
         log.warning(err_s)

      # Blather some details about the shapefile.
      # DEVS: These only log.verbose...
      Shapefile_Wrapper.shapefile_debug_examine_1(self.gdb_layer)
      Shapefile_Wrapper.shapefile_debug_examine_2(self.gdb_layer)

      self.geom_stats_reset()

   # ***

   #
   def get_line_geoms(self, feat):

      geoms = self.get_some_geoms(feat, ogr.wkbLineString)

      return geoms

   #
   def get_point_geoms(self, feat):

      geoms = self.get_some_geoms(feat, ogr.wkbPoint)

      return geoms

   #
   def get_polygon_geoms(self, feat):

      geoms = self.get_some_geoms(feat, ogr.wkbPolygon, also_warn=True)

      return geoms

   #
   def get_some_geoms(self, feat, geom_type, also_warn=False):

      geoms = []

      pkey_val = feat.GetFieldAsInteger(self.pkey_field)

      geom = feat.GetGeometryRef()

      if geom is None:

         self.feats_geom_none.append(pkey_val)

      else:

         geom.FlattenTo2D()

         # This is... weird. self.gdb_layer.GetSpatialRef() says
         # NAD_1983_UTM_Zone_15N, and ArcGIS says the import data
         # is UTM 15, but, on import, ogr complains,
         # 'Geometry SRID (0) does not match column SRID (26915)\n'.
         # So... transform it... [lb] wonders if this is innocuous:
         # maybe ExportToWkt() just isn't spitting out the SRID....
         # Doesn't work: geom.AssignSpatialReference(self.ccp_srs)
         geom.Transform(self.geom_xform)

         if geom.IsEmpty():
            if also_warn:
               log.warning('get_some_geoms: empty geom: %s: %s'
                           % (self.pkey_field, pkey_val,))
            self.feats_geom_empty.append(pkey_val)
         if not geom.IsValid():
            if also_warn:
               log.warning('get_some_geoms: not valid %s: objectid: %s'
                           % (self.pkey_field, pkey_val,))
            self.feats_geom_invalid.append(pkey_val)
         if not geom.IsSimple():
            if also_warn:
               log.warning('get_some_geoms: not simple %s: objectid: %s'
                           % (self.pkey_field, pkey_val,))
            self.feats_geom_unsimple.append(pkey_val)
# FIXME: segment this, maybe in the middle? or can our code ring it?
#         if anything, you could see how many rings are in the ccp data
#         and maybe make a tool to fix them...
         if geom.IsRing():
            if also_warn:
               log.warning('get_some_geoms: ring geom: %s: %s'
                           % (self.pkey_field, pkey_val,))
            self.feats_geom_ring.append(pkey_val)

         if geom.GetGeometryType() in Shapefile_Wrapper.geom_types[geom_type]:
            if geom.GetGeometryType() not in Shapefile_Wrapper.geom_multis:
               geoms.append(geom)
               self.feats_geom_n_single += 1
            else:
               for part_n in xrange(geom.GetGeometryCount()):
                  geoms.append(geom.GetGeometryRef(part_n))
               if len(geoms) < 2:
                  log.warning(
                     'get_some_geoms: unexpected: multi: no. parts: %d'
                     % (len(geoms),))
               self.feats_geom_n_multis += 1
         else:
            log.warning('get_some_geoms: not line string: pkey_val: %s'
                        % (pkey_val,))
            self.feats_geom_badtype.append(pkey_val)

      return geoms

   # ***

   #
   def geom_stats_print(self):

      geom_fail_attrs = ['feats_geom_empty',
                         'feats_geom_none',
                         'feats_geom_invalid',
                         'feats_geom_unsimple',
                         'feats_geom_ring',
                         'feats_geom_badtype',]

      for mbr in geom_fail_attrs:
         arr = getattr(self, mbr)
         if arr:
            log.warning('geom_stats_print: no. %s: %s' % (mbr, len(arr),))

      for mbr in geom_fail_attrs:
         arr = getattr(self, mbr)
         if arr:
            log.warning('geom_stats_print: all %s: %s' % (mbr, arr,))

      log.debug('geom_stats_print: no. single: %d'
                % (self.feats_geom_n_single,))

      log.debug('geom_stats_print: no. multis: %d'
                % (self.feats_geom_n_multis,))

   #
   def geom_stats_reset(self):

      self.feats_geom_empty = []
      self.feats_geom_none = []
      self.feats_geom_invalid = []
      self.feats_geom_unsimple = []
      self.feats_geom_ring = []
      self.feats_geom_badtype = []

      self.feats_geom_n_single = 0
      self.feats_geom_n_multis = 0

   # ***

   #
   @staticmethod
   def gdb_layer_test_capabilities(gdb_layer):
      log.verbose4('  >> TestCapability: layer: %s / RandomRead: %s'
                   % (gdb_layer.GetName(),
                      'True' if gdb_layer.TestCapability(ogr.OLCRandomRead)
                              else 'False',))
      log.verbose4('  >> TestCapability: layer: %s / CreateField: %s'
                   % (gdb_layer.GetName(),
                      'True' if gdb_layer.TestCapability(ogr.OLCCreateField)
                              else 'False',))

   #
   @staticmethod
   def ogr_layer_feature_count(ogr_layer):
      ogr_layer.ResetReading()
      bForce = False
      num_feats = ogr_layer.GetFeatureCount(bForce)
      if num_feats == -1:
         # A proper Shapefile should include an index that also indicates the
         # count.
         log.warning('ogr_layer_feature_count: GetFeatureCount: lazy!')
         bForce = True
         num_feats = ogr_layer.GetFeatureCount(bForce)
      g.assurt(num_feats >= 0)
      return num_feats

   #
   @staticmethod
   def shapefile_debug_examine_1(slayer):

      log.debug('Examining shapefile...')

      # NOTE: OGR provides the following fcns for getting attr data:
      #           GetFieldAsString('blah')
      #           GetFieldAsInteger('bluh')
      #           GetFieldAsDouble('blegh')

      slayer.ResetReading()

      for feat in slayer:

         # FIXME: Call Destroy()?

         feat_defn = slayer.GetLayerDefn()

         for i in xrange(0, feat_defn.GetFieldCount()):
            field_defn = feat_defn.GetFieldDefn(i)
            if field_defn.GetType() == ogr.OFTInteger:
               field_as = '%d' % feat.GetFieldAsInteger(i)
            elif field_defn.GetType() == ogr.OFTReal:
               field_as = '%.3f' % feat.GetFieldAsDouble(i)
            elif field_defn.GetType() == ogr.OFTString:
               field_as = '%s' % feat.GetFieldAsString(i)
            else:
               field_as = '%s' % feat.GetFieldAsString(i)
            log.debug('  >> field: %11s / e.g., %10s | %10s'
                        % (field_defn.GetName(), field_as, feat.GetField(i),))

         break # Just show the feat defns for one row

   #
   @staticmethod
   def shapefile_debug_examine_2(slayer):

      log.debug('Examining shapefile...')

      # NOTE: OGR provides the following fcns for getting attr data:
      #           GetFieldAsString('blah')
      #           GetFieldAsInteger('bluh')
      #           GetFieldAsDouble('blegh')

      slayer.ResetReading()

      for feat in slayer:

         # FIXME: Call Destroy()?

         feat_defn = slayer.GetLayerDefn()

         for i in xrange(feat_defn.GetFieldCount()):
            field_defn = feat_defn.GetFieldDefn(i)
            if field_defn.GetType() == ogr.OFTInteger:
               field_type = "'type':     'int'"
            elif field_defn.GetType() == ogr.OFTReal:
               field_type = "'type':  'double'"
            elif field_defn.GetType() == ogr.OFTString:
               field_type = "'type':  'string'"
            else:
               field_type = "'type': 'unknown'"
            log.debug("      { 'source': 'mtc', %s, 'name': '%s', },"
                         % (field_type, field_defn.GetName(),))

         #log.verbose('E.g., FID: %d' % (feat.GetFID(),))
         #log.verbose('type(feat), dir(feat): %s / %s'
         #            % (type(feat), dir(feat)))

         break # Just show the feat defns for one row

   # *** OGR-related helpers, mostly debug fcns.

   # "2.5D extension as per 99-402"
   geom_type_lookup = {
      ogr.wkb25Bit: 'wkb25Bit',
      ogr.wkbUnknown: 'wkbUnknown',
      ogr.wkbPoint: 'wkbPoint',
      ogr.wkbLineString: 'wkbLineString',
      ogr.wkbPolygon: 'wkbPolygon',
      ogr.wkbMultiPoint: 'wkbMultiPoint',
      ogr.wkbMultiLineString: 'wkbMultiLineString',
      ogr.wkbMultiPolygon: 'wkbMultiPolygon',
      ogr.wkbGeometryCollection: 'wkbGeometryCollection',
      ogr.wkbNone: 'wkbNone',
      ogr.wkbLinearRing: 'wkbLinearRing',
      ogr.wkbPoint25D: 'wkbPoint25D',
      ogr.wkbLineString25D: 'wkbLineString25D',
      ogr.wkbPolygon25D: 'wkbPolygon25D',
      ogr.wkbMultiPoint25D: 'wkbMultiPoint25D',
      ogr.wkbMultiLineString25D: 'wkbMultiLineString25D',
      ogr.wkbMultiPolygon25D: 'wkbMultiPolygon25D',
      ogr.wkbGeometryCollection25D: 'wkbGeometryCollection25D',
      }

   try:
      geom_type_lookup.extend({
         ogr.wkb25DBit: 'wkb25DBit',
         })
   except AttributeError:
      # Older ogr (pre osgeo.__version__ => '1.7.3')
      pass

   #
   @staticmethod
   def verbose_print_geom_type(geom_type):
      try:
         log.verbose('geom: wkb type: %s'
                     % (Shapefile_Wrapper.geom_type_lookup[geom_type],))
      except KeyError:
         log.verbose('geom: type unknown: %s' % (geom_type,)) # -2147483646

   # ***

# ***

if (__name__ == '__main__'):
   pass


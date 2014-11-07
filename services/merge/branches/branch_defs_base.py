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

import conf
import g

log = g.log.getLogger('br_defs_base')

from merge.import_init import Feat_Skipped

# NOTE: TA ==> Target Attribute.
#       Maps between Cyclopath tags and attributes and Shapefile fields.

class Branch_Defs_Base(object):

   # ***

   def __init__(self, mjob):
      #
      self.mjob = mjob
      #
      self.init_import_defns()
      #
      self.init_field_defns()
      #
      self.init_field_domains()
      #
      self.init_metadata()

   # ***

   #
   def init_field_defns(self):

      self.attrs_temporary = list()

      self.attrs_metadata = []

      # Sometimes we need just a subset of the list, which is the collection of
      # field definitions for specific branches.
      # FIXME: This feature is not well defined.
      self.attrs_by_branch = {}

   #
   def init_field_domains(self):

      # For string enum fields, we check the field values when we read them to
      # make sure they match a value in the enum.
      #
      # Also, ArcGIS -- or maybe OpenJUMP or RoadMatcher -- sometimes truncates
      # field values, so the collection here is a dictionary. The keys are the
      # expected values from the shapefile and their values are the value we
      # should use for the Cyclopath attribute value. (Update: I've heard that
      # exporting from ArcGIS to shapefile truncates strings (key names and
      # values?), possibly because of the shapefile specification.)

      # Derived classes should update this.

      self.attrs_field_values = {}

   #
   def init_import_defns(self):

      # SYNC_ME: See Branch_Defs_Base.init_import_defns
      #          and Public_Basemap_Defs.init_field_defns

      # Cyclopath Import and Conflation attributes.
      self.confln_action = 'ACTION_'
      self.confln_context = '_CONTEXT'
      self.confln_delete = '_DELETE'
      self.confln_revert = '_REVERT'
      self.confln_conflated = '_CONFLATED'
      self.confln_new_geom = '_NEW_GEOM'

      # MAYBE: Will we need to worry about line segment direction? I.e., if we
      # conflate two lines that run in opposite values, the m-values will need
      # to be reversed.
      # MAYBE?: self.confln_direction_reversed = '_REVERSED'

      # In the Hausdorff import script, OTHERS_IDS is used to indicate
      # copying of attributes between items.
      self.confln_others_ids = 'OTHERS_IDS'

      # Edited indicator.
      self.confln_edit_date = 'EDIT_DATE'

      # Item_Versioned name and stack ID.
      self.confln_ccp_system_id = 'CCP_SYS'
      self.confln_ccp_stack_id = 'CCP_ID'
      self.confln_ccp_version = 'CCP_VERS'
      self.confln_ccp_name = 'CCP_NAME'

      # Agency IDs.
      self.confln_agy_obj_id = 'AGY_ID'
      self.confln_agy_name = 'AGY_NAME'

      self.confln_required_fields = [
         self.confln_action,
         self.confln_context,
         self.confln_delete,
         self.confln_revert,
         # Nope: self.confln_conflated
         # Nope: self.confln_confidence
         # Nope: self.confln_new_geom
         # Nope: self.confln_edit_date
         #self.confln_ccp_system_id
         self.confln_ccp_stack_id,
         #self.confln_ccp_version
         self.confln_ccp_name,
         self.confln_agy_obj_id,
         # self.confln_agy_name,
         ]

      # MAYBE: 'def' makes [lb] think of 'default', not 'definition'.
      self.action_shpf_def = 'CCP_'
      # MAGIC_NUMBER: When _ACTION == 'CCP_', generally CCP_ID == -1, but
      #               this isn't strictly enforced (it's just so when you
      #               sort by stack ID in you GIS app that the spf_confs
      #               group together at the top of the list).
      self.shpf_def_stack_id = -1
      self.action_import = 'Import'
      self.action_ignore = 'Ignore'
      self.action_fix_me = 'FIXME'

   #
   def init_metadata(self):

      # For Cyclopath string-type attributes, we define a set of acceptable
      # input values (the attribute's "domain"). This is useful for checking
      # data integrity and also for making a nice drop-down list of values in
      # the user interface.

      # FIXME: self.attrs_ccp_enums is not implemented...
      self.attrs_ccp_enums = {}
      for attr_name, attr_values in self.attrs_field_values.iteritems():
         enum = set()
         for attr_val in attr_values.itervalues():
            enum.add(attr_val)
         value_restraint = '"%s"' % ('","'.join(enum))
         log.verbose4('.. adding enum: %s: %s' % (attr_name, value_restraint,))
         self.attrs_ccp_enums[attr_name] = value_restraint

   # *** Target Attribute Definition

   # The target attribute definition describes an attribute as its imported,
   # modified, and exported and saved.

   # Remember: The Shapefile spec. says 10-characters max for a field name.
   #           If it's longer, it'll get laundered to a 10-character width.

   class TA_Defn(object):

      def __init__(self,
                   attr_source='',     # Cyclopath attribute internal_name
                   attr_type=None,     # Python type, e.g., str
                   byway_source='',    # byway.One attribute name
                   # FIXME: You can access byway cols and attribute link_values
                   #        Ratings are made into mock cols. What about notes?
                   #        Discussions? Nonwiki Items (Watchers?)?
                   field_target='',    # Target shapefile field name
                   field_type=None,    # .shp type, e.g., ogr.OFTString
                   field_source='',    # Update shapefile fld name; c.b.N
                   field_width=None,   # For OFTString, number of characters
                   field_clone=False,  # If a CCP_ field, if we copy src field.
                   val_callback=None,  # Returns attr. value; can be None
                   attr_edit=True,     # Is new attr. value editable?
                   deleted_on=None,    # How to save if attr_type bool
                   comparable=False,   # If attr is special, for joining
                   stackable=False,    # For less-special, coalesce vals?
                   stackable_xor=None, # How to coalesce certain types.
                   settable=False,     # If we look for this value in the input
                   cmp_ignore_empties=False, # If '' == 'whatever'
                   ):

         # Not always true:
         #  g.assurt((attr_source and attr_type) or (byway_source))
         g.assurt(field_target)
         # Note that field type is ogr.OFT*, e.g., ogr.OFTInteger, 
         # which range from 0 (OFTInteger) to 11 (ogr.OFTDateTime).
         # We could but currently don't support many of the OFT types:
         #  ogr.OFTBinary, OFTDate, OFTDateTime, ogr.OFTTime
         #  ogr.OFTIntegerList, ogr.OFTRealList, ogr.OFTStringList
         #  ogr.OFTWideString
         g.assurt(field_type in (ogr.OFTInteger,
                                 ogr.OFTReal,
                                 ogr.OFTString,))

         #
         self.attr_source = attr_source
         self.attr_type = attr_type
         self.byway_source = byway_source
         self.field_target = field_target
         self.field_type = field_type
         self.field_source = field_source or field_target
         # Manually specify the field_width. Ogr defaults it to 80 (though if
         # you call ogr.FieldDefn(fname, ftype).GetWidth(), ogr reports '0').
         # If you try to set a value with more characters than field_width
         # (e.g., using SetFrom), ogr willfully truncates the value and writes
         # to std_err something like,
         #    Warning 1: Value '...' of field NOTES has been truncated to 80
         #    characters. This warning will not be emitted any more for that
         #    layer.
         # which means you're calling fcn. won't know of the error (or at least
         # not without checking the value it tried to set, after setting it).
         self.field_width = field_width
         self.field_clone = field_clone
         self.val_callback = val_callback
         self.attr_edit = attr_edit
         if deleted_on is None:
            self.deleted_on = ()
         else:
            self.deleted_on = deleted_on
         self.comparable = comparable
         self.stackable = stackable
         self.stackable_xor = stackable_xor
         self.settable = settable
         self.cmp_ignore_empties = cmp_ignore_empties

         # For, now comparable and stackable are exclusive of one another. I
         # [lb] was thinking not comparable and not stackable might mean the
         # max or avg value for be used, or something. Meh.
         #g.assurt((comparable is None) or (comparable ^ stackable))

         # This is the stack ID of the new attribute, set once it's created.
         self.ccp_atid = None

      #
      def __str__(self):
         sstr = ('TA_Defn: ft: %s / bs: %s'
                 % (field_target,
                    byway_source,))
         return sstr

   # end: class TA_Defn

   # *** TA_Defn wrappers, one for each atomic type

   # NOTE: The following attrs_define_* fcns. are very similar to one another.

   #
   def attrs_define_boolean(self,
         attr_source='',
         #attr_type=bool,
         byway_source='',
         field_target='',
         #field_type=ogr.OFTString,
         field_source='',

         # FIXME: This should be 1, ideally?
         field_width=5, # MAGIC_NUMBER: max(len('true'), len('false'))

         field_clone=False,
         val_callback=None,
         attr_edit=True,
         deleted_on=None,
         comparable=False,
         stackable=False,
         stackable_xor=None,
         settable=False,
         cmp_ignore_empties=False,
         #
         by_branch='',
         ):
      g.assurt(field_target)
      if deleted_on is None:
         # Delete Ccp attr if bool is False or None.
         # No?: deleted_on = (False, None,)
         deleted_on = ('', None,)
      ta_def = Branch_Defs_Base.TA_Defn(
                  attr_source=attr_source, #
                  attr_type=bool, #
                  byway_source=byway_source,
                  field_target=field_target,
                  field_type=ogr.OFTString, #
                  field_source=field_source,
                  field_width=field_width,
                  field_clone=field_clone,
                  val_callback=val_callback,
                  attr_edit=attr_edit,
                  deleted_on=deleted_on,
                  comparable=comparable,
                  stackable=stackable,
                  stackable_xor=stackable_xor,
                  settable=settable,
                  cmp_ignore_empties=cmp_ignore_empties,
                  )
      self.attrs_by_branch[by_branch].append(ta_def)
      self.attrs_metadata.append(ta_def)
      return ta_def

   #
   def attrs_define_integer(self,
         attr_source='',
         #attr_type=int,
         byway_source='',
         field_target='',
         #field_type=ogr.OFTInteger,
         field_source='',
         field_width=None,
         field_clone=False,
         val_callback=None,
         attr_edit=True,
         deleted_on=None,
         comparable=False,
         stackable=False,
         settable=False,
         cmp_ignore_empties=False,
         by_branch='',
         ):
      g.assurt(field_target)
      # Integers cannot be stacked, unless, e.g., you made 'em a
      # comma-separated string list of ints, or if you averaged them, etc.
      g.assurt(not stackable)
      ta_def = Branch_Defs_Base.TA_Defn(
                  attr_source=attr_source, #
                  attr_type=int, #
                  byway_source=byway_source,
                  field_target=field_target,
                  field_type=ogr.OFTInteger, #
                  field_source=field_source,
                  field_width=field_width,
                  field_clone=field_clone,
                  val_callback=val_callback,
                  attr_edit=attr_edit,
                  deleted_on=deleted_on,
                  comparable=comparable,
                  stackable=stackable,
                  settable=settable,
                  cmp_ignore_empties=cmp_ignore_empties,
                  )
      self.attrs_by_branch[by_branch].append(ta_def)
      self.attrs_metadata.append(ta_def)
      return ta_def

   #
   def attrs_define_float(self,
         attr_source='',
         #attr_type=float,
         byway_source='',
         field_target='',
         #field_type=ogr.OFTReal,
         field_source='',
         field_width=None,
         field_clone=False,
         val_callback=None,
         attr_edit=True,
         deleted_on=None,
         comparable=False,
         stackable=False,
         settable=False,
         cmp_ignore_empties=False,
         by_branch='',
         ):
      g.assurt(field_target)
      # Integers cannot be stacked, unless, e.g., you made 'em a
      # comma-separated string list of ints, or if you averaged them, etc.
      g.assurt(not stackable)
      ta_def = Branch_Defs_Base.TA_Defn(
                  attr_source=attr_source, #
                  attr_type=float, #
                  byway_source=byway_source,
                  field_target=field_target,
                  field_type=ogr.OFTReal, #
                  field_source=field_source,
                  field_width=field_width,
                  field_clone=field_clone,
                  val_callback=val_callback,
                  attr_edit=attr_edit,
                  deleted_on=deleted_on,
                  comparable=comparable,
                  stackable=stackable,
                  settable=settable,
                  cmp_ignore_empties=cmp_ignore_empties,
                  )
      self.attrs_by_branch[by_branch].append(ta_def)
      self.attrs_metadata.append(ta_def)
      return ta_def

   #
   def attrs_define_string(self,
         attr_source='',
         #attr_type=str,
         byway_source='',
         field_target='',
         #field_type=ogr.OFTString,
         field_source='',

         # FIXME: What's the OGR default? I think it's 50.
         field_width=50,

         field_clone=False,
         val_callback=None,
         attr_edit=True,
         deleted_on=None,
         comparable=False,
         stackable=False,
         settable=False,
         cmp_ignore_empties=False,
         by_branch='',
         ):
      # deleted_on = ('', None,) is implied
      g.assurt(field_target)
      if deleted_on is None:
         # Delete attr if string is empty or None.
         deleted_on = ('', None,)
      ta_def = Branch_Defs_Base.TA_Defn(
                  attr_source=attr_source, #
                  attr_type=str, #
                  byway_source=byway_source,
                  field_target=field_target,
                  field_type=ogr.OFTString, #
                  field_source=field_source,
                  field_width=field_width,
                  field_clone=field_clone,
                  val_callback=val_callback,
                  attr_edit=attr_edit,
                  deleted_on=deleted_on,
                  comparable=comparable,
                  stackable=stackable,
                  settable=settable,
                  cmp_ignore_empties=cmp_ignore_empties,
                  )
      self.attrs_by_branch[by_branch].append(ta_def)
      self.attrs_metadata.append(ta_def)
      return ta_def

   # ***

   #
   def field_val_setup_all(self, dst_layer, old_byway, src_feat, context,
                                 just_copy_from=False, bad_geom_okay=False):
      skip_feat = ''
      # Get a handle on the layer.
      layer_defn = dst_layer.GetLayerDefn()
      # Make the new feature.
      dst_feat = ogr.Feature(layer_defn)
      # Set the geometry and fields.
      if src_feat is not None:
         g.assurt(not just_copy_from) # Not used.
         if just_copy_from:
            ogr_err = dst_feat.SetFrom(src_feat, forgiving=False)
         else:
            #ogr_err = dst_feat.SetGeometry(src_feat.GetGeometryRef())
            ogr_err = dst_feat.SetFrom(src_feat, forgiving=True)
         g.assurt(not ogr_err)
         g.assurt(dst_feat.GetFID() == -1)
         g.assurt(dst_feat.GetGeometryRef() is not None)
         g.assurt((dst_feat.GetGeometryRef().GetZ() == -9999.0)
                  or (dst_feat.GetGeometryRef().GetZ() == 0))
         dst_feat.GetGeometryRef().FlattenTo2D()
      else:
         g.assurt(old_byway is not None)
         geometry_wkt = old_byway.geometry_wkt
         if geometry_wkt.startswith('SRID='):
            geometry_wkt = geometry_wkt[geometry_wkt.index(';')+1:]
         old_geom = ogr.CreateGeometryFromWkt(geometry_wkt)
         old_geom.FlattenTo2D() # Keep enforce_dims_geometry happy.
         dst_feat.SetGeometryDirectly(old_geom)
         # If a split-into segment is missing, we'll try to copy the old
         # byway's geometry, which means the old_byway's geometry has not been
         # vetted yet.
         if not dst_feat.GetGeometryRef().IsSimple():
            skip_feat = 'simple'
         if dst_feat.GetGeometryRef().IsRing():
            skip_feat += ' and ' if skip_feat else ''
            skip_feat += 'isring'
      # Set the fields.
      # DEV_TRICK: 2013.04ish: [lb] was importing the Bikeways Shapefile anew,
      #            after it had been edited. A few features were edited
      #            weirdly. Here's how I trapped the error on a dbg prompt.
      #      if old_byway.stack_id == 1358797:
      #         import pdb;pdb.set_trace()
      if not just_copy_from:
         for ta_def in self.attrs_metadata:
            self.field_val_setup_one(ta_def, dst_feat, old_byway, src_feat)
      # We've copied the context from the src_feat, but if the caller specified
      # it, use that instead.
      if skip_feat:
         context = 'Bad geom: %s' % (skip_feat,)
      if context:
         dst_feat.SetField(self.confln_action, self.action_fix_me)
         dst_feat.SetField(self.confln_context, context)
      if skip_feat and not bad_geom_okay:
         raise Feat_Skipped()
      # Finally, add the feature to the layer.
      # NOTE to the callees: If you call SetField or SetGeometry on this
      #      returned feature, you have to call SetFeature for the changes to
      #      stick.
      ogr_err = dst_layer.CreateFeature(dst_feat)
      g.assurt(not ogr_err)
      log.verbose('field_val_setup_all: dst_feat/CreateFeat: FID: %d'
                  % (dst_feat.GetFID(),))
      return dst_feat

   #
   # FIXME: Will this fcn. work for polygons and points? If so, rename
   # old_byway...
   def field_val_setup_one(self, ta_def, dst_feat, old_byway, src_feat):

      # This fcn. is called just once, after the source feature and source
      # byway are loaded.
      the_val = None

      # We expect at least a byway or a feature to be the source, or both.
      # If both are set, we prefer to find the_val in the source shapefile
      # (i.e., because we're importing). We use the source byway to hydrate
      # the_val otherwise (either because it's NULL/Unset in the source
      # shapefile or because we're exporting).
      #
      # FIXME: If we export a file with an attribute value set, and the
      #        user deletes/unsets the value in a GIS app and we import
      #        the Shapefile, will we unset/clear the value in Cyclopath??
      #        BUG nnnn: Test unset attr value, delete feature, and revert
      #                  feature on import.
      #
      g.assurt((old_byway is not None) or (src_feat is not None))

      # First see if the source feature has the target field set. This may or
      # may not matter, as we'll find out.
      source_val = None
      source_set = False
      if src_feat is not None:
         try:
            source_val = self.ta_def_get_field_value(ta_def, src_feat,
                                                     use_target=True)
            source_set = True
         except Exception, e:
            try:
               source_val = self.ta_def_get_field_value(ta_def, src_feat,
                                                        use_source=True)
               source_set = True
            except Exception, e:
               pass

      # Find the value per the target attribute definition. There are three
      # source types and two source objects, so that's six places we need to
      # look to find the_val. [callback, link attr, bway attr,] x [bway, feat,]
      if ta_def.val_callback is not None:
         # This is a calculated value, and we always expect target to be None.
         g.assurt((source_val is None) and (not source_set))
         # Call the custom callback to make the value.
         the_val = ta_def.val_callback(ta_def, old_byway, src_feat)
         # If the callback returns None, it either means there's no information
         # or the information does not indicate positive (i.e., instead of None
         # the value could have been 0, '' or False).

      # 2013.05.02: "Where have you been all my life?!" [lb] finds that
      #             TA_Defns using ta_def.attr_source are all NULL in the
      #             export Shapefile. Didn't this used to work for Cycloplan?
      #             I know I implemented the fast-loading of attributes since,
      #             but I don't remember not using attr_source (and using
      #             ccp_atid instead), and a cursory examination of the 2012
      #             CcpV2 Cycloplan demo doesn't suggest I changed anything.
      # Weird and old and wrong: elif ta_def.ccp_atid:
      elif ta_def.ccp_atid or ta_def.attr_source:
         # This is a byway attribute (link_value). If the target field is
         # already set, use that value. Then try the source field. Lastly, try
         # the byway.
         if source_set:
            the_val = source_val
         elif old_byway is not None:
            # See also:
            #   item_mgr.cache_attrnames[attc_attr.internal_name] = attc_attr
            if ta_def.ccp_atid:
               attr = self.mjob.handler.attributes_all[ta_def.ccp_atid]
               try:
                  # This fails (throws AttributeError) unless heavyweight
                  # link_values are being used. It also fails if the byway says
                  # the attribute is unset or deleted (KeyError). If it works,
                  # it'll be the real value, or a defauly value which could be
                  # None.
                  the_val = old_byway.link_values[ta_def.ccp_atid].get_value(
                                                                        attr)
               except AttributeError:
                  # This means old_byway.link_values isn't set but maybe
                  # old_byway.attrs is.
                  # This won't throw but could also return None.
                  the_val = old_byway.attr_val(attr.value_internal_name)
               except KeyError:
                  # The byway says the attribute is informationless (i.e.,
                  # unset or deleted).
                  #verbose
                  log.verbose5('field_val_setup_one: no attr: %s / %s'
                               % (attr.value_internal_name, old_byway,))
            else:
               g.assurt(ta_def.attr_source)
               # This returns None on not found/absent so this is easy.
               the_val = old_byway.attr_val(ta_def.attr_source)
         else:
            log.warning('field_val_setup_one: ccp_atid defined, no val: %s'
                        % (ta_def.ccp_atid,))
            g.assurt(False) # I don't think we'll find ourselves here.

      elif ta_def.byway_source:
         if source_set:
            # FIXME: A 'None' value is ignored by item_base.
            the_val = source_val
         elif old_byway is not None:
            the_val = getattr(old_byway, ta_def.byway_source)
         else:
            log.warning('field_val_setup_one: byway_source defined, no val: %s'
                        % (ta_def.byway_source,))
            g.assurt(False) # I don't think we'll find ourselves here.

      else:
         # Only ta_def.field_target is set, meaning this is not an attribute,
         # and it's not a byway value; it's just a field in the Shapefile (like
         # _ACTION, _CONTEXT, _DELETE, etc.). Sometimes we keep this value the
         # same and sometimes we don't.
         if ta_def.field_clone and source_set:
            the_val = source_val

      # If the value is a deleted_on value, unset the field.
      if ta_def.deleted_on and (the_val in ta_def.deleted_on):
   # FIXME: What about integers? We want to be able to store 0, and using,
   # i.e., -1 for special purposes is not cool.

# FIXME: Shapefile Integer fields *must* be set. So use a magic number!
#        Or, use a String field.......
         the_val = None

      # Store the value in the target feature's target field.
      field_idx = dst_feat.GetFieldIndex(ta_def.field_target)
      g.assurt(field_idx != -1)
      if the_val is not None:
         log.verbose5('field_val_setup_one: target: %10s / the_val: %s'
                      % (ta_def.field_target, the_val,))
         dst_feat.SetField(ta_def.field_target, the_val)
      else:
         log.verbose5('field_val_setup_one:  unset: %10s / the_val: %s'
                      % (ta_def.field_target, the_val,))
         dst_feat.UnsetField(field_idx)

   # ***

   SPACES_RE = re.compile(r'^ +$')

   #
   def link_value_get_field_value(self, ta_def, the_val):
      val_boolean, val_integer, val_string = [None,] * 3
      if ta_def.attr_type == bool:
         g.assurt(isinstance(the_val, bool))
         val_boolean = the_val
      elif ta_def.attr_type == int:
         g.assurt(isinstance(the_val, int))
         val_integer = the_val
      elif ta_def.attr_type == str:
         g.assurt(isinstance(the_val, str))
         if Branch_Defs_Base.SPACES_RE.search(the_val):
            self.stats['field_string_spaces'] += 1
            the_val = ''
         val_string = the_val
      else:
         g.assurt(False)
      return val_boolean, val_integer, val_string

   #
   def ta_def_get_field_value(self, ta_def, feat,
                                    use_target=False,
                                    use_source=False):

      # The field_type is the ogr value type, which indicates which fcn we call
      # to get the value (GetFieldAs____()).
      if ta_def.field_type == ogr.OFTInteger:
         ogr_fcn = feat.GetFieldAsInteger
      elif ta_def.field_type == ogr.OFTReal:
         ogr_fcn = feat.GetFieldAsDouble
      elif ta_def.field_type == ogr.OFTString:
         ogr_fcn = feat.GetFieldAsString
      else:
         # See list of OFTs. Search this file: OFT types.
         #  ogr.OFTInteger, ogr.OFTReal, ogr.OFTString
         #  ogr.OFTBinary, OFTDate, OFTDateTime, ogr.OFTTime
         #  ogr.OFTIntegerList, ogr.OFTRealList, ogr.OFTStringList
         #  ogr.OFTWideString
         log.error('Unknown field_type: %s' % (str(ta_def.field_type),))
         g.assurt(False)

      # Note that we fetch from the update-named field, and not the
      # target-named field. The target field is write-only.
      g.assurt(use_target ^ use_source)
      if use_target:
         fname = ta_def.field_target
      elif use_source:
         fname = ta_def.field_source
      g.assurt(fname)

      # If you know the field exists, you can call IsFieldSet, but only if you
      # know the field is defined, lest, e.g., # ERROR 1: No such field: '...'.
      if feat.GetFieldIndex(fname) != -1:
         if feat.IsFieldSet(fname):
            val_raw = ogr_fcn(fname)
            if ta_def.attr_type == bool:
               g.assurt(val_raw is not None)
               the_val = self.ogr_to_bool(val_raw)
               g.assurt(isinstance(the_val, bool))
            else:
               the_val = ta_def.attr_type(val_raw)
            g.assurt(the_val is not None)
         else:
            the_val = None
      else:
         raise Exception('ta_def_get_field_value: does not exist: %s'
                         % (fname,))

      return the_val

   #
   def ta_def_get_attr_value(self, ta_def, ref_byway):
      try:
         # If byway_source wasn't a string, this would throw TypeError
         the_val = getattr(ref_byway, ta_def.byway_source)
      except AttributeError:
         # The byway should always have the attribute defined, so this
         # is a programmer error.
         raise Exception('byway_source not found on byway: %s / %s'
                         % (ta_def.byway_source, ref_byway,))
      return the_val

   # *** Class helpers

   #
   def ogr_str_as_bool(self, feat, field_name, default):
      # Always return a value. Caller should use default=None if they want to
      # know if the field really exists or not. Or set confln_required_fields.
      g.assurt(field_name)
      if feat.GetFieldIndex(field_name) == -1:
         val = default
      else:
         val = feat.GetFieldAsString(field_name)
         if val == '':
            val = default
         else:
            try:
               val = self.ogr_to_bool(val)
            except Exception, e:
               log.warning('ogr_str_as_bool: %s' % (str(e),))
               val = default
      return val

   #
   # FIXME: Move to util file?
   def ogr_to_bool(self, test_value):
      truth = None
      if isinstance(test_value, float):
         log.verbose('ogr_to_bool: float: %.2f' % (test_value,))
         truth = True if test_value else False
      elif isinstance(test_value, str):
         log.verbose('ogr_to_bool: str: %s' % (test_value,))
         if test_value.lower() in ('y', 'yes', 'true', '1',):
            truth = True
         elif test_value.lower() in ('n', 'no', 'false', '0',):
            truth = False
         else:
            raise Exception('Not a boolean value: %s' % (test_value,))
      elif isinstance(test_value, int):
         log.verbose('ogr_to_bool: int: %s' % (test_value,))
         truth = True if test_value else False
      elif isinstance(test_value, bool):
         log.verbose('ogr_to_bool: bool: %s' % (test_value,))
         truth = test_value
      else:
         raise Exception('Unexpected type: %s' % (type(test_value),))
      log.verbose('ogr_to_bool: truth: %s' % (truth,))
      return truth

   # ***

# ***

if (__name__ == '__main__'):
   pass


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
import re
import socket
import sys
import time
import traceback

import conf
import g

from grax.access_level import Access_Level
from item import item_base
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from item.feat import route
from item.grac import group
from item.util import ratings
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml

from merge.branches.branch_defs_base import Branch_Defs_Base
from merge.ccp_export import Ccp_Export
from merge.ccp_import import Ccp_Import

log = g.log.getLogger('pub_bmap_defs')

class Public_Basemap_Defs(Branch_Defs_Base):

   # FIXME: What do we want here?
   # BUG nnnn: Is there a cap on name length, in flashclient and pyserver
   # (in sql it's just a TEXT object...)
   #field_width=256,
   # I think Shapefile text field widths are capped at 255. 
   # FIXME: Should we limit Ccp names to 255, too?
   esri_max_text = 255

   def __init__(self, mjob):
      Branch_Defs_Base.__init__(self, mjob)

   # *** Entry routine

   # This is boiler plate code for any branch that wants to support merge/IO.

   #
   @staticmethod
   def process_export(mjob):
      if mjob.the_def is None:
         g.assurt(mjob.handler is None)
         mjob.the_def = Public_Basemap_Defs(mjob)
         mjob.handler = Ccp_Export(mjob, mjob.the_def)
      okay = mjob.handler.do_export()
      return okay

   # See do_do_import
   @staticmethod
   def process_import(mjob):
      if mjob.the_def is None:
         g.assurt(mjob.handler is None)
         mjob.the_def = Public_Basemap_Defs(mjob)
         mjob.handler = Ccp_Import(mjob, mjob.the_def)
      okay = mjob.handler.do_import()
      return okay

   # ***

   # FIXME: Part of export should be auditing. 
   # E.g., search for lefthangingbros or search for non-intersections, etc.

   # 
   def init_field_defns(self):

      Branch_Defs_Base.init_field_defns(self)

      self.attrs_by_branch['baseline'] = []

      # When importing a roadmr conflation, we use an intermediate shapefile to
      # help manage information. For that intermediate shapefile, we define
      # some fields.

      self.attrs_temporary.extend(
         [
         # We use SPLIT_FROM internally to keep track of split-from byways.
         # This value needn't be shown to the user (saved to a Shapefile).
         # FIXME: Or maybe showing SPLIT_FROM after an import would help audit.
         ('SPLIT_FROM', ogr.OFTInteger, None,),
         ])

      # When importing or exporting, we have to know the mapping of Shapefile
      # fields to Cyclopath attributes. Or, more accurately, the mapping of
      # source information to outputs, since not all source information derives
      # from a Shapefile -- for instance, you can use a callback function if 
      # your source data is calculated. Also, not all source information is
      # output to the same destination: some information may go to a 
      # Shapefile while other information may find itself in Cyclopath.

      # *** Cyclopath Conflation fields

      # NOTE: These are shapefile feature fields only and not Cyclopath attrs.

      # SYNC_ME: See Branch_Defs_Base.init_import_defns 
      #          and Public_Basemap_Defs.init_field_defns

      self.attrs_define_string(
         # No: attr_source='...',
         field_target=self.confln_action, # 'ACTION_',
         field_width=8,
         comparable=None, stackable=False, settable=True,
         by_branch='baseline')

      # Deprecated: The following fields are part of the merge/import* scripts.
      #             But the hausdorff_import.py script is much easier to use --
      #             for one, the interface is simpler (there's just one field,
      #             and most actions can be solved with a simple single char.
      #             command, and sometimes marking one feature alone can affect
      #             multiple features), but also, the other script uses Fiona,
      #             rather than communicating with osgeo directly (osgeo is
      #             complicated and non-Pythonic), and the other script does
      #             everything in bulk and limits its dependence on the
      #             Cyclopath database, so it's really tight and fast, and it's
      #             easy to maintain the code ([lb] admits that the
      #             services/import* scripts are confusing, not just because
      #             it's ten thousand plus lines of code, but also because the
      #             code is spread across multiple classes of a hierarchy; and
      #             while I like class hierarchies, sometimes they go too far=)
      self.attrs_define_string(
         # No: attr_source='...',
         field_target=self.confln_context, # '_CONTEXT',
         field_width=64,
         field_clone=True,
         comparable=None, stackable=False, settable=True,
         by_branch='baseline')

      if False:

         self.attrs_define_boolean(
            # No: attr_source='...',
            field_target=self.confln_conflated, # '_CONFLATED',
            comparable=None, stackable=False, settable=True,
            by_branch='baseline')

         self.attrs_define_integer(
            # No: attr_source='...',
            field_target=self.confln_confidence, # '_PCT_SURE',
            comparable=None, stackable=False, settable=True,
            by_branch='baseline')

         self.attrs_define_boolean(
            # No: attr_source='...',
            field_target=self.confln_new_geom, # '_NEW_GEOM',
            comparable=None, stackable=False, settable=True,
            by_branch='baseline')

         self.attrs_define_boolean(
            # No: attr_source='...',
            field_target=self.confln_delete, # '_DELETE',
            comparable=None, stackable=False, settable=True,
            by_branch='baseline')

         self.attrs_define_boolean(
            # No: attr_source='...',
            field_target=self.confln_revert, # '_REVERT',
            comparable=None, stackable=False, settable=True,
            by_branch='baseline')

         # MAYBE?:
         #self.attrs_define_boolean(
         #   # No: attr_source='...',
         #   field_target=self.confln_direction_reversed, # '_REVERSED',
         #   comparable=None, stackable=False, settable=True,
         #   by_branch='baseline')

      self.attrs_define_string(
         # No: attr_source='...',
         field_target=self.confln_others_ids, # 'OTHERS_IDS',
         # Use max width since we don't know how long it's going to be.
         field_width=Public_Basemap_Defs.esri_max_text,
         comparable=None, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_string(
         # No: attr_source='...',
         field_target=self.confln_edit_date, # 'EDIT_DATE',
         # MAYBE: Date format is 'mm/dd/yyyy', so we just need 10 chars?
         field_width=10,
         comparable=None, stackable=False, settable=True,
         by_branch='baseline')

      # FIXME: What about Cyclopath attrs?
      # Choose from 
      #    geofeature columns (gfl, z, one way, term(inal) ids)
      #    joins (aadt, elevation, rating)
      #    attachments (tags and attributes)
      #    basics (item_versioned, gia)

      # *** Cyclopath values, from item_versioned, geofeature, and byway.

      # Item_Versioned

      self.attrs_define_integer(
         # Instead of attr_source, using byway_source.
         byway_source='system_id',
         field_target=self.confln_ccp_system_id, # 'CCP_SYS',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         # Instead of attr_source, using byway_source.
         byway_source='stack_id',
         field_target=self.confln_ccp_stack_id, # 'CCP_ID',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         # Instead of attr_source, using byway_source.
         byway_source='version',
         field_target=self.confln_ccp_version, # 'CCP_VERS',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_string(
         byway_source='name',
         field_target=self.confln_ccp_name, # 'CCP_NAME',
         field_width=Public_Basemap_Defs.esri_max_text,
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      # Some interesting historic details...

      # FIXME: APRIL2014: When importing MnDOT trails, use
      #        new latest_rid et al Shapefile fields to check
      #        for version conflicts, i.e., check that for each
      #        edited geometry or attribute in the Shapefile that
      #        a user didn't edit the same via flashclient, or that
      #        the item wasn't otherwise edited and saved to the db.

      self.attrs_define_integer(
         byway_source='valid_start_rid',
         field_target='latest_rid',
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      # 04.2014: [lb] not quite sure this is useful but maybe it's interesting.
      self.attrs_define_string(
         val_callback=self.calculate_latest_usr,
         field_target='latest_usr',
         field_width=Public_Basemap_Defs.esri_max_text,
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      # FIXME: Is this useful? How about, Is this easy to fetch?:
      # self.attrs_define_integer(
      #    byway_source='last_edited_lval',
      #    field_target='latest_att',
      #    comparable=True, stackable=False, settable=True,
      #    by_branch='baseline')

      self.attrs_define_integer(
         val_callback=self.calculate_create_rid,
         field_target='create_rid',
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_string(
         byway_source='created_user',
         field_target='create_usr',
         field_width=Public_Basemap_Defs.esri_max_text,
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      # NOTE: It's up to the branches to define attrs for 
      #         self.confln_agy_obj_id, # 'AGY_ID'
      #         self.confln_agy_name, # 'AGY_NAME'

      # Skipping: version, system_id, branch_id, valid_start_rid,
      #           valid_until_rid

      # Geofeature

      self.attrs_define_integer(
         byway_source='z',
         field_target='z_level',
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_integer(
         # FIXME: How do you make this value settable?
         #byway_source='geofeature_layer_id',
         field_target='gf_lyr_id',
         val_callback=self.gf_lyr_resolve_id,
         #comparable=True, stackable=False, settable=True,
         comparable=True, stackable=False, settable=False,
         by_branch='baseline')
      #
      self.attrs_define_string(
         # FIXME: How do you make this value settable?
         field_target='gf_lyr_nom',
         # FIXME: What do we want here?
         field_width=50,
         val_callback=self.gf_lyr_resolve_nom,
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      # Byway

      self.attrs_define_integer(
         byway_source='one_way',
         field_target='one_way',
         comparable=True, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         val_callback=self.calculate_is_disconnected,
         field_target='wconnected',
         comparable=True, stackable=False, settable=False,
         by_branch='baseline')

      # Byway-associated (tables)

      self.attrs_define_float(
         byway_source='generic_rating',
         field_target='rtng_gnric',
         comparable=None, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         byway_source='user_rating',
         field_target='rtng_yours',
         comparable=None, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_float(
         val_callback=self.calculate_rating_avg,
         field_target='rtng_mean',
         comparable=None, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         val_callback=self.calculate_rating_cnt,
         field_target='rtng_count',
         comparable=None, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_float(
         byway_source='bsir_rating',
         field_target='rtng_bsir',
         comparable=None, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_float(
         byway_source='cbf7_rating',
         field_target='rtng_cbf7',
         comparable=None, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_float(
         byway_source='ccpx_rating',
         field_target='rtng_ccpx',
         comparable=None, stackable=False, settable=False,
         by_branch='baseline')

      # Skipping: split_from_stack_id

      # *** Cyclopath values, from link_values.

      self.attrs_define_string(
         # MAYBE: Let this be set on import.
         field_target='item_tags',
         # FIXME: What char width do we want here?
         field_width=100,
         val_callback=self.byway_tag_list,
         comparable=True, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         attr_source='/byway/speed_limit',
         field_target='speedlimit',
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_integer(
         attr_source='/byway/lane_count',
         field_target='lane_count',
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_integer(
         attr_source='/byway/outside_lane_width',
         field_target='out_ln_wid',
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_integer(
         attr_source='/byway/shoulder_width',
         field_target='shld_width',
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_string(
         attr_source='/byway/cycle_facil',
         #field_target=self.field_bike_facil, # 'BIKE_FACIL'
         field_target='bike_facil',
         field_width=32,
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_string(
         attr_source='/byway/cautionary',
         field_target='cautionary',
         field_width=32,
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_string(
         attr_source='/byway/cycle_route',
         field_target='cycleroute',
         field_width=32,
         comparable=True, stackable=False, settable=True,
         by_branch='baseline')

      #self.attrs_define_integer(
      #   #attr_source='/byway/aadt',
      #   byway_source='',
      #   field_target='',
      #   comparable=True, stackable=False, 
      #   by_branch='baseline')

   # BUG nnnn: Add more attachments: annotations and tags

      # *** Cyclopath byway nodes.

      # LHS Node

      self.attrs_define_integer(
         byway_source='beg_node_id',
         field_target='ndl_nodeid',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_float(
         byway_source='node_lhs_elevation_m',
         field_target='ndl_elev',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         byway_source='node_lhs_reference_n',
         field_target='ndl_ref_no',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         byway_source='node_lhs_dangle_okay',
         field_target='ndl_dngl_k',
         comparable=False, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_integer(
         byway_source='node_lhs_a_duex_rues',
         field_target='ndl_duex_k',
         comparable=False, stackable=False, settable=True,
         by_branch='baseline')

      # RHS Node

      self.attrs_define_integer(
         byway_source='fin_node_id',
         field_target='ndr_nodeid',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_float(
         byway_source='node_rhs_elevation_m',
         field_target='ndr_elev',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         byway_source='node_rhs_reference_n',
         field_target='ndr_ref_no',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

      self.attrs_define_integer(
         byway_source='node_rhs_dangle_okay',
         field_target='ndr_dngl_k',
         comparable=False, stackable=False, settable=True,
         by_branch='baseline')

      self.attrs_define_integer(
         byway_source='node_rhs_a_duex_rues',
         field_target='ndr_duex_k',
         comparable=False, stackable=False, settable=True,
         by_branch='baseline')

      #

      self.attrs_define_float(
         byway_source='geometry_len',
         field_target='geom_len',
         comparable=False, stackable=False, settable=False,
         by_branch='baseline')

   # *** Helpers: val_callback handlers

   #
   def gf_lyr_resolve_id(self, ta_def, bway, feat):
      gf_lyr_id, gf_lyr_nom = self.gf_lyr_resolve(ta_def, bway, feat)
      return gf_lyr_id

   #
   def gf_lyr_resolve_nom(self, ta_def, bway, feat):
      gf_lyr_id, gf_lyr_nom = self.gf_lyr_resolve(ta_def, bway, feat)
      return gf_lyr_nom

   gf_lyr_nom_nom = 'gf_lyr_nom'
   gf_lyr_id_nom = 'gf_lyr_id'

   #
   def gf_lyr_resolve(self, ta_def, bway, feat):
      qb = self.mjob.handler.qb_cur
      # The Shapefile contains both the ID and the name. Use the one that's
      # different. If they're both different, yikes.
      new_gfl_id = None
      gfl_id_orig = None
      if bway is not None:
         gfl_id_orig = bway.geofeature_layer_id
         new_gfl_id = gfl_id_orig
      if ((feat is not None) 
          and (feat.GetFieldIndex(Public_Basemap_Defs.gf_lyr_nom_nom) != -1)
          and (feat.GetFieldIndex(Public_Basemap_Defs.gf_lyr_id_nom) != -1)):
         new_id_by_nom = gfl_id_orig
         if feat.IsFieldSet(gf_lyr_nom_nom):
            fld_nom_nom = feat.GetFieldAsString(gf_lyr_nom_nom)
            try:
               new_id_by_nom, layer_name = (
                  qb.item_mgr.geofeature_layer_resolve(qb.db, fld_nom_nom))
            except Exception, e:
               # FIXME: How do you accumulate errors for the user?
               log.warning('Unexpected geofeature type name: %s / %s'
                           % (fld_nom_nom, str(e),))
         # else, gf_lyr_nom_nom field is 0 or None.
         #
         new_id_by_id = gfl_id_orig
         fld_id_nom = None
         # See above; we've already checked that the field exists, but this
         # checks to see that it's set, i.e., != ''.
         if feat.IsFieldSet(gf_lyr_id_nom):
            fld_id_nom = feat.GetFieldAsInteger(gf_lyr_id_nom)
            try:
               new_id_by_id, layer_name = (
                  qb.item_mgr.geofeature_layer_resolve(qb.db, fld_id_nom))
            except Exception, e:
               # FIXME: How do you accumulate errors for the user?
               log.warning('Unexpected geofeature type id (1): %s / %s' 
                           % (fld_id_nom, str(e),))
         # else, gf_lyr_id_nom field is '' or None.
         #
         if (    (gfl_id_orig is not None)
             and (new_id_by_nom != gfl_id_orig) 
             and (new_id_by_id != gfl_id_orig) 
             and (new_id_by_nom != new_id_by_id)):
            # FIXME: User warning, too
            log.warning('New Geofeature Layer Mismatch: %s and %s (%s)'
                        % (new_id_by_id, new_id_by_nom, fld_id_nom,))
         else:
            if (new_id_by_nom != gfl_id_orig):
               new_gfl_id = new_id_by_nom
            elif (new_id_by_id != gfl_id_orig):
               new_gfl_id = new_id_by_id
      new_gfl_nom = None
      if new_gfl_id is not None:
         try:
            layer_id, new_gfl_nom = (
               qb.item_mgr.geofeature_layer_resolve(qb.db, new_gfl_id))
         except Exception, e:
            # FIXME: How do you accumulate errors for the user?
            log.warning('Unexpected geofeature type id (2): %s / %s'
                        % (new_gfl_id, str(e),))
      log.verbose4(' || gfl_id_resolve: %s / %s' % (new_gfl_id, new_gfl_nom,))
      return new_gfl_id, new_gfl_nom
   # FIXME: We need a fcn. to read gfl lyr id or nom if user changes it?

   #
   def calculate_create_rid(self, ta_def, bway, feat):
      # Is this worth the effort?
      # Should we add SQL to item_versioned.sql_apply_squelch_filters?
      creatd_rid_sql = (
         """
         SELECT valid_start_rid FROM item_versioned
         WHERE stack_id = %d AND version = 1
         """ % (bway.stack_id,))
      rows = self.mjob.handler.qb_cur.db.sql(creatd_rid_sql)
      g.assurt(len(rows) == 1)
      start_rid = rows[0]['valid_start_rid']
      return start_rid

   #
   def calculate_is_disconnected(self, ta_def, bway, feat):
      return 0 if bway.is_disconnected else 1

   #
   def calculate_latest_usr(self, ta_def, bway, feat):
      # Is this worth the effort?
      # Should we add SQL to item_versioned.sql_apply_squelch_filters?
      latest_usr_sql = (
         """
         SELECT username FROM revision WHERE id = %d
         """ % (bway.valid_start_rid,))
      rows = self.mjob.handler.qb_cur.db.sql(latest_usr_sql)
      g.assurt(len(rows) == 1)
      latest_usr = rows[0]['username']
      return latest_usr

   # FIXME: Bulk load ratings? It's quick and takes < 100 Mb...
   #        And if we don't want to load 'em all, we could make a temp table...
   #
   def calculate_rating_avg(self, ta_def, bway, feat):
      # FIXME: Use current rating?
      rating_avg = bway.rating_useravg(self.mjob.handler.qb_cur.db)
      # DEV_TRICK: Stop on a specific feature during import:
      #      if bway.stack_id == 1019246:
      #         import pdb;pdb.set_trace()
      return rating_avg

   #
   def calculate_rating_cnt(self, ta_def, bway, feat):
      # FIXME: Use current rating?
      rating_cnt = bway.rating_usercnt(self.mjob.handler.qb_cur.db)
      return rating_cnt

   #
   def byway_tag_list(self, ta_def, bway, feat):
      tags = list(bway.tagged)
      tags.sort()
      tag_list = ', '.join(tags)
      return tag_list

   # ***

# ***

if (__name__ == '__main__'):
   pass


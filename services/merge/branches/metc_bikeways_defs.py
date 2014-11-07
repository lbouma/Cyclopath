# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

'''


UPDATE item_versioned SET deleted = TRUE FROM work_item 
  WHERE work_item.system_id = item_versioned.system_id;
DELETE FROM work_item_step;
DELETE FROM work_item;
DELETE FROM group_item_access WHERE item_type_id = 29; -- merge_job
DELETE FROM group_item_access WHERE item_type_id = 33; -- merge_job_download
DELETE FROM group_item_access WHERE item_type_id = 30; -- route_analysis_job
DELETE FROM group_item_access WHERE item_type_id = 40; -- route_analysis_job_download
DELETE FROM group_item_access WHERE item_type_id = 42; -- merge_export_job
DELETE FROM group_item_access WHERE item_type_id = 43; -- merge_import_job
delete from merge_job;
delete from route_analysis_job;

-- Skipping callback_dat, last_modified, callback_raw
SELECT work_item_id AS id, step_number AS no,
   stage_name, stage_num AS sno, stage_progress AS prg, 
   status_code AS scode, status_text AS stext, 
   cancellable AS cncl,
   callback_dat AS cdat
FROM work_item_step ORDER BY work_item_id DESC, step_number DESC;


# AFTER EDITING SHAPEFILE IN ARCGIS, MAKE THE IMPORT ZIP:
cd /ccp/dev/Import_Bikeways
win_dir=/win/Users/Pee\ Dubya/Desktop/_Cyclopath/_Cycloplan.Shapefiles/2013.04.01-bkup-Export_Output/2012.08.02-Import_Bikeways
/bin/cp -f "$win_dir/Agency".* .
/bin/cp -f "$win_dir/Export_Output".* .
cd /ccp/dev
rmrm Import_Bikeways.zip ; zip -r Import_Bikeways Import_Bikeways/ ; chmod 664 Import_Bikeways.zip


# 2013.04.25
cd /ccp/dev/Import_Bikeways
win_dir=/win/Users/Pee\ Dubya/Desktop/_Cyclopath/_Cycloplan.Shapefiles/Export_Output/2013.04.25.OpenJump.2512313
/bin/cp -f "$win_dir/Agency".* .
/bin/cp -f "$win_dir/Export_Output".* .
cd /ccp/dev
rmrm Import_Bikeways.zip ; zip -r Import_Bikeways Import_Bikeways/
/bin/cp -f Import_Bikeways.zip /ccp/var/shapefiles/
/bin/chmod 664 /ccp/var/shapefiles/Import_Bikeways.zip
scp /ccp/var/shapefiles/Import_Bikeways.zip $lbpr:/ccp/var/shapefiles/


rmrm /ccp/var/cpdumps/*.zip /ccp/var/cpdumps/*.usr /ccp/var/cpdumps/*.out /ccp/var/cpdumps/*.fin
sudo /bin/rm -rf /ccp/var/cpdumps/*.zip /ccp/var/cpdumps/*.usr /ccp/var/cpdumps/*.out /ccp/var/cpdumps/*.fin


2012.06.04: FIXME next!



# Feb-20 02:14:32 # Script completed in 2690.59 secs. ~44 min
# NOTE: ccp.yml branch name must match this one!
ccp_script=./ccp.py
py_port=80
re
$ccp_script -U landonb --no-password -m "Ignored." \
   -c -t merge_import_job \
   -b "Metc Bikeways 2012" \
   -e download_fake "/ccp/dev/Import_Bikeways.zip" \
   -e name "" -e job_act "create" -e for_group_id 0 -e for_revision 0 \
   -e job_local_run 1 \
   --py_port $py_port

==============

# To test export:
cd /ccp/dev/cp/pyserver/
ccp_script=./ccp.py
re ; $ccp_script -U landonb --no-password -m "Ignored." \
   -c -t merge_export_job \
   -b "Metc Bikeways 2012" \
   -e job_local_run 1 -e job_act "create" -e name "" \
   -e for_group_id 0 -e for_revision 0 -e email_on_finish 1 \
   -e filter_by_region "Lynnhurst"


cd /ccp/dev/cp/pyserver/
ccp_script=./ccp.py
py_port=80
re ; $ccp_script -U landonb --no-password -m "Ignored." \
   -c -t merge_export_job \
   -b 0 \
   -e job_local_run 1 -e job_act "create" -e name "" \
   -e for_group_id 0 -e for_revision 0 -e email_on_finish 1 \
   -e filter_by_region "Lynnhurst" \
   --py_port $py_port



# ROUTE ANALYSIS
cd /ccp/dev/cp/pyserver/
ccp_script=./ccp.py
py_port=80
re ; sudo -u apache INSTANCE=minnesota \
   PYTHONPATH=/ccp/opt/usr/lib/python:/ccp/opt/usr/lib/python2.7/site-packages:/ccp/opt/gdal/lib/python2.7/site-packages:/ccp/opt/usr/lib/python2.7/site-packages:/ccp/opt/usr/lib/python:/ccp/opt/usr/lib/python2.7/site-packages: \
   PYSERVER_HOME=/export/scratch/ccp/dev/cp/pyserver \
   $ccp_script -U landonb --no-password \
   -c -t route_analysis_job -m "Ignored." \
   -e name "" -e job_act "create" \
   -e name Job3 \
   -e job_local_run 1 -e n 1 \
   --py_port $py_port




what about -V? it's in the config...
make test.zip...


   -e download_fake \
      "/win/Users/Pee Dubya/Desktop/_Cyclopath/2011.04.MetC.Bikeways.zip" \


# For revision ID, use the revision from when the cyclopath export was
# created, on or before 13 Jan 2011. The largest ID in the conflated data
# shapefile is 14124, which is 2010-12-26. Seems like a safe bet.
#
# FIXME: Make 2011.04.MetC.Bikeways.zip: 
#  Cyclopath-Bikeways_Conflation/Cycloplan Data Package/bikeways/bikeways.shp
#  Cyclopath.Cycloplan/2011.11.09.Matched.and.Standalone/Export_Output.shp'


'''

import re
import socket
import sys
import time
import traceback

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
#sys.path.insert(0, os.path.abspath('%s/../../../pyserver' 
#                % (os.path.abspath(os.curdir),)))
#import pyserver_glue

import conf
import g

log = g.log.getLogger('metc_bikewyz')

# From pyserver
from grax.access_level import Access_Level
from item import item_base
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.feat import route
from item.grac import group
from item.link import link_attribute
from item.link import link_tag
from item.util import ratings
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml

from merge.ccp_export import Ccp_Export
from merge.ccp_import import Ccp_Import
from merge.branches.public_basemap_defs import Public_Basemap_Defs

# *** MetC_Bikeways_Defs

class MetC_Bikeways_Defs(Public_Basemap_Defs):

   # *** Constructor

   def __init__(self, mjob):
      Public_Basemap_Defs.__init__(self, mjob)
      #
      g.assurt(len(self.attrs_by_branch['metc_bikeways']) > 0)

   # *** Entry routine

   # This is boiler plate code for any branch that wants to support merge/IO.

   #
   @staticmethod
   def process_export(mjob):
      if mjob.the_def is None:
         g.assurt(mjob.handler is None)
         mjob.the_def = MetC_Bikeways_Defs(mjob)
         mjob.handler = Ccp_Export(mjob, mjob.the_def)
      okay = mjob.handler.do_export()
      return okay

   #
   @staticmethod
   def process_import(mjob):
      if mjob.the_def is None:
         g.assurt(mjob.handler is None)
         mjob.the_def = MetC_Bikeways_Defs(mjob)
         mjob.handler = Ccp_Import(mjob, mjob.the_def)
      okay = mjob.handler.do_import()
      return okay

   # ***

   #
   def init_import_defns(self):

      Public_Basemap_Defs.init_import_defns(self)
      
      # Cyclopath Import and Conflation attributes.
      self.field_bike_facil = 'BIKE_FACIL'

      self.confln_required_fields += [
         self.field_bike_facil,
         ]

   # In Cyclopath, most attributes have an internal name, which lets us use
   # them in the code. The internal name is generally prefixed, so it's easy
   # for programmers to think about them (e.g., /byway/speed_limit).
   #import_attr_prefix = '/metc_bikeways/'

   #
   def init_field_defns(self):

      Public_Basemap_Defs.init_field_defns(self)

      self.attrs_by_branch['metc_bikeways'] = []

      # Notes:
      # 
      #    * You can get a list of column names and definitions for each 
      #    shapefile by enabling the fcns., shapefile_debug_examine_*. 
      #    This is useful for copy-n-pasting into this script.
      # 
      #    * Remember to keep shapefile field names under 10 characters.
      # 
      #    * Go here for a detailed discussion of the input data, read:
      # 
      #        http://cyclopath.org/wiki/Tech:Cycloplan/Conflation

      # BUG nnnn: Write script to wget the wiki and distribute with the source.

      # The first set of attributes are the important ones. This information is
      # sacred.

      # Skipping: M-values, which are not used in the bikeways data set.

      # At one point, I [lb] renamed Bikeways' CLASS to AGY_TYPE, but it's 
      # just  Road, Paved Trail, Trail, and Other.... which is redundant 
      # because the same information is captured by Bikeways' TYPE.
      #
      # FIXME: We should set uses_custom_control in the attribute table,
      #        either add to attrs_define_* params or just do a schema-update
      #        later? makes more sense to do it here?
      self.attrs_define_string(
         attr_source='/metc_bikeways/bike_facil',
         field_target=self.field_bike_facil, # 'BIKE_FACIL'

         # MAGIC_NUMBER: 32...
         # FIXME: The Ccp database uses TEXT which is unlimited (within reason)
         # length. We only use 32 because we have to say something for the
         # Shapefile... should we just use 256? 1024? I [lb] have two concerns:
         # 1. does the field width affect speed (filesize I care less about,
         # but that's probably all that's affected... it'd be easy to guess, I
         # suppose, just add a column to a Shapefile and compare the
         # filesizes); and 2. what happens if there's a value in Ccp that's
         # longer than the one in the Shapefile? This alls seems like it can be
         # automated, too: there's no need to magic numbers....
         field_width=32,

         comparable=True, stackable=False, settable=True,
         by_branch='metc_bikeways')
# FIXME_2013_06_11: Revisit this.


# FIXME: Omit most of the MetC attributes.

      # 2012.06.21: MetC has instructed us not to worry about Proposed features
      # for now. The Shapefile we have has lots of features that need cleanup,
      # and 20% of 'em are Proposed features.
      self.attrs_define_boolean(
         # FIXME: For now, we'll maintain PROPOSED during the import->export
         #        process, but we won't include it as an attribute. We'll
         #        hopefully have time in the future to process this data...
         #
         #        Once ready, add attr_source so we save this attribute:
         #        
         #          attr_source='/metc_bikeways/propsd_fac',
         #
         field_target='PROPOSED',
         val_callback=None,
         comparable=True, stackable=False, settable=True,
         by_branch='metc_bikeways')

      # NOTE: Next two, AGY_ID and AGY_NAME, are probably boilerplace for
      # each branch. (We don't want to add the attrs to the public basemap, 
      # and the id/name scheme might varie between branches/data sources.)

      self.attrs_define_integer(
         # MetC does not care about Agency IDs, and [lb] and [ao] have already
         # used ArcMap's attribute copy tool to totally taint the dataset.
         # We'll copy the value between Shapefiles, since it's useful for
         # auditing, but otherwise we don't need it. So don't set attr_source.
         # NO: attr_source='/metc_bikeways/agency_ids',
         # NOTE: In the original Bikeways.shp, this is called OBJECTID. In our
         #       Conflation, we've changed the field name to AGY_ID.
         field_target=self.confln_agy_obj_id, # 'AGY_ID',
         comparable=False, stackable=False, settable=True,
         by_branch='metc_bikeways')

      self.attrs_define_string(
         # NOTE: Difference in attribute and field names...
         # MAYBE: If stacked and > 255 chars, alt_names will be truncated when
         #        it's exported to AGY_NAME.
         attr_source='/metc_bikeways/alt_names',
         field_target=self.confln_agy_name, # 'AGY_NAME',
         # NOTE: The name field is only 50 wide in Bikeways.shp, but we might
         #       want to stack names, so use max.
         # Shapefile max is 255 characters... AFAI[lb]K.
         field_width=255,
         val_callback=None,
         # [lb] still [2012.06.21] isn't sure if name is comparable and/or
         # stackable.
         #comparable=False, stackable=False, settable=True,
         comparable=True, stackable=False, settable=True,
         cmp_ignore_empties=True,
         by_branch='metc_bikeways')

# FIXME: After import bikeways, make this and other attrs 'custom' so
#        they don't clutter the list (since no one uses this and other
#        attrs, at least not now, so we'll keep the data but hide the
#        GUI widget).
      self.attrs_define_string(
         attr_source='/metc_bikeways/from_munis',
         field_target='AGY_SOURCE',
         # MAGIC_NUMBER: Value from Bikeways.shp.
         field_width=32,
         val_callback=None,
         # FIXME: We really don't want to stack these... but we want to combine
         # ones that are empty with ones that are set...
         #comparable=False, stackable=True, settable=True,
         # FIXME: check that this doesn't segmentize Cyclopath byways, 
         # otherwise we'll need to figure something out, like stacking 
         comparable=True, stackable=False, settable=True,
         cmp_ignore_empties=False,
         by_branch='metc_bikeways')

      # The 'discrepancy' attributes are used to identify attribute mis-matches
      # between the Bikeways source and Cyclopath.

      # The remaining attributes are less important. If split segments from
      # the same Cyclopath segment have different values for the fields below,
      # we'll combine, or stack, the values. As such, these values are ignored 
      # when considering feature equality.

      self.attrs_define_string(
         attr_source='/metc_bikeways/surf_type',
         field_target='SURF_TYPE',
         # MAGIC_NUMBER: Value from Bikeways.shp.
         #field_width=25,
         # FIXME: But this value is stackable...
         field_width=75,
         val_callback=None,
         comparable=False, stackable=True, settable=True,
         by_branch='metc_bikeways')

      self.attrs_define_string(
         attr_source='/metc_bikeways/jurisdiction',
         field_target='JURISDICTI',
         # MAGIC_NUMBER: Value from Bikeways.shp.
         #field_width=10,
         # FIXME: But this value is stackable...
         field_width=30,
         val_callback=None,
         comparable=False, stackable=True, settable=True,
         by_branch='metc_bikeways')

      # NOTE: Side applies to one-ways, not to bike lanes.
      #       If there are two one-ways side-by-side, one with have the
      #       opposite side value than the other, like "North or East" and 
      #       "South or West".
      #       It is also used to indicate what side of a road a Paved Trail is
      #       on. I.e., the geometry for the trail is the centerline of the 
      #       agency road and the SIDE means what side the trail runs along...
      # -- 1. If there are two, parallel one-way bike trails, the two segments
      # -- are marked opposite one another, e.g., one is West and one is East.
      # -- 2. If the Shapefile editor was lazy and used a road centerline to
      # -- indicate a bike trail, the SIDE indicates to which side of the road
      # -- the bike trail really exists. (This is the case where a Bikeways
      # -- bike trail exactly matches the geometry of a Cyclopath local road,
      # -- for instance, indicating someone was a lazy editor.)
      self.attrs_define_string(
         attr_source='/metc_bikeways/line_side',
         field_target='LINE_SIDE',
         # MAGIC_NUMBER: Value from Bikeways.shp.
         #field_width=16,
         # FIXME: But this value is stackable...
         field_width=48,
         val_callback=None,
         comparable=False, stackable=True, settable=True,
         by_branch='metc_bikeways')

      # NOTE: Oneway is just a boolean, unlike Cyclopath: it doesn't indicate
      # the direction of the one-way, just that it is a one way.
      self.attrs_define_boolean(
         attr_source='/metc_bikeways/agy_oneway',
         field_target='AGY_ONEWAY',
         val_callback=None,
         comparable=False, stackable=True, settable=True,
         #comparable=True, stackable=False, settable=True,
         stackable_xor=None,
         by_branch='metc_bikeways')

      self.attrs_define_boolean(
         attr_source='/metc_bikeways/agy_paved',
         field_target='AGY_PAVED',
         val_callback=None,
         comparable=False, stackable=True, settable=True,
         #comparable=True, stackable=False, settable=True,
         stackable_xor=None,
         by_branch='metc_bikeways')

      # MAYBE: The AADT data is inconsistent and incorrect.
      # 1. When a lazy editor used a road centerline to mark a trail, the AADT
      # from the road is set on the trail.
      # 2. Not all adjacent line segments have the same AADT -- in some cases,
      # both are set but different, but in a lot of cases only one is set --
      # which means when we compare adjacent line segments to see if they can
      # be combined, we need a callback that says to just take the largest
      # value of the two line segments (i.e., stackable=True). But there's
      # a FIXME because stackable only works on strings, not ints... we just
      # need a compare() callback.
      #self.attrs_define_string(
      #   field_target='ROAD_AADT',
      #   field_type=ogr.OFTInteger,
      #   field_source='ROAD_AADT',
      #   val_callback=None, 
      #   comparable=False, stackable=True, settable=True,
      #   compare=self.compare_aadt, FIXME: Implement compare...
      #   by_branch='metc_bikeways')

      # *** These fields are only used on export, to help the user audit. We do
      #     not inspect these fields on import.

      self.attrs_define_boolean(
         # Leave attr_source unset to indicate not an attribute; i.e., we'll
         # compute this value when we're ready to save to the Shapefile, but 
         # we won't save the value in Cyclopath.
         # Leave unset: attr_source='/metc_bikeways/diff_facil',
         field_target='DIFF_FACIL',
         val_callback=self.get_diff_bike_facility,
         # Also set comparable to None so the importer doesn't look for the
         # field on import.
         comparable=None, stackable=False, settable=False,
         by_branch='metc_bikeways')

      self.attrs_define_boolean(
         # Leave unset: attr_source='/metc_bikeways/diff_onewy',
         field_target='DIFF_ONEWY',
         val_callback=self.get_diff_oneway,
         comparable=None, stackable=False, settable=False,
         by_branch='metc_bikeways')

      self.attrs_define_boolean(
         # Leave unset: attr_source='/metc_bikeways/diff_blane',
         field_target='DIFF_BLANE',
         val_callback=self.get_diff_bikelane,
         comparable=None, stackable=False, settable=False,
         by_branch='metc_bikeways')

      self.attrs_define_string(
         # Leave unset: attr_source='/metc_bikeways/diff_paved',
         field_target='DIFF_PAVED',
         # MAGIC_NUMBER: 16.
         field_width=16,
         val_callback=self.get_diff_paved,
         comparable=None, stackable=False, settable=False,
         by_branch='metc_bikeways')

      self.attrs_define_string(
         # Leave unset: attr_source='/metc_bikeways/diff_shldr',
         field_target='DIFF_SHLDR',
         # MAGIC_NUMBER: 16.
         field_width=16,
         val_callback=self.get_diff_shoulder,
         comparable=None, stackable=False, settable=False,
         by_branch='metc_bikeways')

      # *** 'Type' domain lookups for the various bits of info. it contains.

      # These are used during a RoadMatcher import.

      # Bicycle Facility.

      self.gflid_domain_fac_bike_trail = (
         byway.Geofeature_Layer.Bike_Trail,
         byway.Geofeature_Layer.Major_Trail,
         )
      self.gflid_domain_fac_road_road = (
         byway.Geofeature_Layer.Byway_Alley,
         byway.Geofeature_Layer.Local_Road,
         byway.Geofeature_Layer.Major_Road,
         byway.Geofeature_Layer.Highway,
         byway.Geofeature_Layer.Expressway,
         byway.Geofeature_Layer.Expressway_Ramp,
         #byway.Geofeature_Layer.Railway,
         #byway.Geofeature_Layer.Private_Road,
         byway.Geofeature_Layer.Other_Ramp,
         byway.Geofeature_Layer.Parking_Lot,
         )

      # These are not used:
      self.gflid_domain_surf_paved = (
         byway.Geofeature_Layer.Major_Road,
         byway.Geofeature_Layer.Major_Trail,
         byway.Geofeature_Layer.Highway,
         byway.Geofeature_Layer.Expressway,
         byway.Geofeature_Layer.Expressway_Ramp,
         )
      self.gflid_domain_surf_unpaved = (
         byway.Geofeature_Layer.Doubletrack,
         byway.Geofeature_Layer.Singletrack,
         )
      self.gflid_domain_surf_unknown = (
         byway.Geofeature_Layer.Byway_Alley,
         byway.Geofeature_Layer.Local_Road,
         byway.Geofeature_Layer.Sidewalk,
         byway.Geofeature_Layer.Bike_Trail,
         byway.Geofeature_Layer.Unknown,
         byway.Geofeature_Layer.Other,
         )

      # 'SURF_TYPE' domain lookups.

      self.surf_domain_paved = (
         'Asphalt',
         'Concrete',
         )
      self.surf_domain_unpaved = (
         'Boardwalk',
         'Dirt',
         'Gravel',
         'Turf',
         )

      # Bike Shoulder Tag Domain

      # MAGIC NUMBER/NAMEs: Tag names gleaned from SQL query circa 2011.11.18:
      #  select iv.name from tag join item_versioned as iv using (system_id) 
      #     where name like '%shoulder%' order by name asc;

      # These are not used. Could be used for should discrepancy.
      self.ccp_tag_domain_shoulder_good = set([
         'bike shoulder',
         'busy, good shoulder',
         'good shoulder',
         'great! recently repaved, wide shoulders',
         'nice shoulder',
         'shoulder',
         'shoulder lane',
         'striped shoulder',
         'striped shoulder on bridge',
         'wide shoulder',
         'wide shoulder path',
         'wide shoulder, safe',
         ])
      self.ccp_tag_domain_shoulder_bad = set([
         'bad traffic, bad shoulder,'
         'busy, no shoulder',
         'busy, no shoulder, dangerous',
         'limited shoulder',
         'narrow shoulder',
         'no shoulder',
         'no shoulders',
         'no true shoulder',
         'poor shoulder',
         'rough road, no shoulder, busy',
         'shoulder ends',
         'shoulder, minimal',
         'shoulder narrow',
         'small shoulder',
         ])
      # Ignoring:
      #   'south shoulder',
      #   'traffic speed or shoulder condition',

   # *** Field/Attribute Value Fetchers

   # These fcns. all apply just to the first RoadMatcher import.

   # NOTE: Instead of throwing asserts, it's better to log errors, since it
   # sucks if your three-hour script dies two hours in because of a silly data
   # misunderstanding.

   # bway is old_byway, if it exists; feat is src_feat, if it exists (i.e.,
   # one of the other might not exist, e.g., on export, bway is old_byway and
   # feat is always None; on import, feat is always set by bway may or may not
   # be (the latter if the feat is a new line segment)).

   #
   def get_diff_bike_facility(self, ta_def, bway, feat):
      the_val = False
      if bway is not None:
         if feat is not None:
            # NOTE: Not using ta_def.field_source, since ta_def is just the 
            #       definition for DIFF_FACIL.
            bike_facil = feat.GetFieldAsString(self.field_bike_facil)
         else:
            # We're not importing, but we can at least see if we've already set
            # this value and go from there.
            bike_facil = bway.attr_val('/metc_bikeways/bike_facil')
            # These were the original facil. names used before we shortened
            # them (and underscored them), so that the Shapefile field width
            # is constrained to a max. of 10 chars.
            #   Unknown/Other
            #   Narrow Shoulder
            #   Bike Shoulder
            #   Bike Trail
            #   Bike Lane

         if bike_facil == 'paved_trail':
            if (bway.geofeature_layer_id not in 
                self.gflid_domain_fac_bike_trail):
               the_val = True
         elif bike_facil in ('bike_lane', 'shld_lovol', 'hway_lovol',):
            if (bway.geofeature_layer_id not in 
                self.gflid_domain_fac_road_road):
               the_val = True
         elif bike_facil == 'rdway_shared':
            # Skipping: 'rdway_shared'
            pass
         # WEIRD: 2012.08.01: If the value in the Shapefile is the
         # space character, " ", we merely see an empty string, "".
         elif bike_facil == '':
            bike_facil = None
         elif bike_facil is not None:
            log.error('diff_class: unknown bike_facil: "%s" / FID: %s'
                      % (bike_facil, 
                         feat.GetFID() if feat is not None else 'n/a',))
      log.verbose(' || get_diff_bike_facility: %s' % (the_val,))
      return the_val

   #
   def get_diff_oneway(self, ta_def, bway, feat):
      the_val = None
      if bway is not None:
         if feat is not None:
            is_one_way = self.ogr_str_as_bool(feat, 'AGY_ONEWAY', False)
         else:
            is_one_way = bway.attr_val('/metc_bikeways/agy_oneway')
            if is_one_way is None:
               is_one_way = False
         # Cast to bool since one_way is in (-1,0,1,) and ^ won't like that.
         if is_one_way ^ bool(bway.one_way):
            the_val = True
      log.verbose(' || get_diff_oneway: %s' % (the_val,))
      return the_val

   #
   def get_diff_bikelane(self, ta_def, bway, feat):
      the_val = None
      if bway is not None:
         if feat is not None:
            bike_facil = feat.GetFieldAsString(self.field_bike_facil)
         else:
            bike_facil = bway.attr_val('/metc_bikeways/bike_facil')
         feat_bike_lane = (bike_facil == 'Bike Lane')
         # MAGIC NUMBER: Tag names gleaned from SQL query circa 2011.11.18:
         #  select iv.name from tag join item_versioned as iv using (system_id)
         #     where name like '%lane%' order by name asc;
         tags_bikelane = bway.has_tag('bikelane')
         tags_bike_lane = bway.has_tag('bike lane')
         tags_bike_lanes = bway.has_tag('bike lanes')
         bway_bike_lane = tags_bikelane or tags_bike_lane or tags_bike_lanes
         bway_bike_lane = False
         # We don't care if Cyclopath is missing the bike lane tag, since it's
         # value set is a lot less rich. So the xor operator, e.g., 
         #    if feat_bike_lane ^ bway_bike_lane
         # would produce too much useless information.
         if (not feat_bike_lane) and bway_bike_lane:
            the_val = True
      log.verbose(' || get_diff_bikelane: %s' % (the_val,))
      return the_val

   #
   def get_diff_paved(self, ta_def, bway, feat):

      # The bway is the line segment that's saved in the database from the
      # previous revision and could be a split-ancestor. The feat is the new
      # version of the (possibly split) segment that's either about to be 
      # saved or is just being saved to a new Shapefile... like, testing the
      # water before committing to commit.

      # Default to no discrepancy.
      the_val = ''
      if bway is not None:
         if feat is not None:
            # If empty string, defaults to True.
            feat_ispaved = self.ogr_str_as_bool(feat, 'AGY_PAVED', True)
         else:
            feat_ispaved = bway.attr_val('/metc_bikeways/agy_paved')
            if not feat_ispaved:
               feat_ispaved = True
         # MAGIC NUMBER: Tag names gleaned from SQL query circa 2011.11.18:
         #  SELECT iv.name from AS tag JOIN item_versioned AS iv 
         #     USING (system_id) WHERE name LIKE '%pave%' ORDER BY name ASC;
         tags_unpaved = bway.has_tag('unpaved')
         tags_ispaved = bway.has_tag('paved')
         if not tags_ispaved and not tags_unpaved:
            # Always assume paved if not specified.
            # MAYBE: Need to check classification, since some are inherently
            # not paved.
            tags_ispaved = True
         log.verbose('feat_ispaved: %s / tags_ispaved: %s / tags_unpaved: %s'
                  % (feat_ispaved, tags_ispaved, tags_unpaved,))
         if feat_ispaved and tags_unpaved:
            the_val += '+Agy|-Tag'
         elif not feat_ispaved and tags_ispaved:
            the_val += '-Agy|+Tag'
         elif tags_unpaved and tags_ispaved:
            the_val += '-Tag|+Tag'
      log.verbose(' || get_diff_paved: %s' % (the_val,))
      return the_val

   # anon_v2=> select distinct(value_integer), count(*) 
   #           from link_value where lhs_stack_id = 2223111
   #           group by value_integer order by value_integer;
   #  value_integer | count  
   # ---------------+--------
   #              0 | 106623
   #              1 |     84
   #              2 |    270
   #              3 |    380
   #              4 |   1396
   #              5 |   2387
   #              6 |    667
   #              7 |    101
   #              8 |   1294
   #              9 |    127
   #             10 |   3051
   #             11 |     65
   #             12 |    359
   #             13 |     49
   #             14 |     22
   #             15 |     15
   #             16 |     12
   #             18 |      9
   #                |    336
   # (19 rows)

   #
   def get_diff_shoulder(self, ta_def, bway, feat):
      the_val = ''
      agy_bike_shoulder = False
      ccp_bike_shoulder = False
      ccp_poor_shoulder = False

      if bway is not None:

         if feat is not None:
            bike_facil = feat.GetFieldAsString(self.field_bike_facil)
         else:
            bike_facil = bway.attr_val('/metc_bikeways/bike_facil')

         if bike_facil in ('shld_lovol', 'hway_lovol',):
            agy_bike_shoulder = True

         ccp_bike_shoulder = self.ccp_tag_domain_shoulder_good.intersection(
                                                                bway.tagged)
         ccp_bike_shoulder = len(ccp_bike_shoulder) > 0
         ccp_poor_shoulder = self.ccp_tag_domain_shoulder_bad.intersection(
                                                                bway.tagged)
         ccp_poor_shoulder = len(ccp_poor_shoulder) > 0

         # Indicate the discrepancies.
         if ccp_bike_shoulder and ccp_poor_shoulder:
            the_val += '+Tag-Tag'
         if ccp_bike_shoulder:
            if ccp_bike_shoulder ^ agy_bike_shoulder:
               the_val += '+Tag-Agy'

         # See also about shoulder width info.
         shoulder_width = bway.attr_val('/byway/shoulder_width')
         # FIXME: What's a good threshold?
         if shoulder_width is not None:
            if (shoulder_width > 3) and (not agy_bike_shoulder):
               the_val += 'Attr >3'
            elif (shoulder_width <= 3) and (agy_bike_shoulder):
               the_val += 'Attr <=3'

      log.verbose(' || get_diff_shoulder: %s' % (the_val,))
      return the_val

   # *** 

# ***

if (__name__ == '__main__'):
   pass


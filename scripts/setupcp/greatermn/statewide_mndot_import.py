#!/usr/bin/python

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./statewide_mndot_import.py --help
#

# $ ./statewide_mndot_import.py --run-setup
#
#  2013.11.14: Script completed in 41.89 mins.
#
#
# $ ./statewide_mndot_import.py --run-import \
#     -U landonb --no-password \
#     -x "Cook" -x "Lake" -x 38
# there are 13 lines in -x 0, some are state line roads, but not all
#
# ./statewide_mndot_import.py --run-import -U landonb --no-password -x "Washington"
# ./statewide_mndot_import.py --run-import -U landonb --no-password -x "saint louis"
#   --skip-coverage-area
#   --force-update-geofeature
#
# $ ./statewide_mndot_import.py --run-teardown
#

# BUG nnnn/FIXME: 2014.02.12: There might be a node_endpoint bug in here.
#                 After importing the Statewide data, it looks like
#                 node_endpoint, node_byway, and node_endpt_px are missing
#                 nodes...
#                 and it looks like duplicate nodes were maybe created...

__import_order_sql__ = (
"""

./statewide_mndot_import.py -U landonb --no-password \
   --run-import --link-values-only --skip-coverage-area \
   -x "lake"



SELECT sc.county_name, sc.county_num, count(*) AS line_count
FROM mndot_counties AS mc
JOIN state_counties AS sc ON (sc.county_num = mc.cnty_code)
GROUP BY sc.county_name, sc.county_num
ORDER BY line_count;

mahnomen is smallest: 1058 lines
hennepin is largest: 55402 lines



SELECT county_name, county_num
FROM state_counties
WHERE county_num IN (
   SELECT DISTINCT(cnty_code)
   FROM mndot_counties
   WHERE ccp_conflict IS NOT NULL
      OR ccp_stack_id IS NOT NULL) ORDER BY county_name;
 county_name | county_num 
-------------+------------
 carlton     |          9
 chisago     |         13
 cook        |         16
 houston     |         28
 lake        |         38
 pine        |         58
 swift       |         76
 washington  |         82

BEGIN TRANSACTION;
SET TRANSACTION READ WRITE;
SET CONSTRAINTS ALL DEFERRED;
LOCK TABLE revision IN EXCLUSIVE MODE;

BEGIN TRANSACTION;
SET TRANSACTION READ WRITE;
SET CONSTRAINTS ALL DEFERRED;
LOCK TABLE revision IN SHARE ROW EXCLUSIVE MODE;


ROLLBACK;



ccpv3_demo=> select count(*) from mndot_counties;
 count  
--------
 443617

ccpv3_demo=> select count(*) from mndot_counties
               where ccp_stack_id is null and ccp_conflict is null;
 count 
-------
  1398

ccpv3_demo=> select count(*) from mndot_counties
               where ccp_stack_id is not null and ccp_conflict is null;
 count  
--------
 291157

ccpv3_demo=> select count(*) from mndot_counties
               where ccp_stack_id is null and ccp_conflict is not null;
 count  
--------
 113567




FIXME: I still haven't update all the state attributes yet...

ccpv3_demo=> select count(*) from link_value where branch_id = 2500677;
 count  
--------
 657696  <-- After making links for counties 1 through 20
 In Ccpv1 live, just 469698 lvals...


./statewide_mndot_import.py -U landonb --no-password \
   --run-import --link-values-only \
   -x 31 -x 32 -x 33 -x 34 -x 35 -x 36 -x 37 -x 38 -x 39 -x 40 \
   -x 41 -x 42 -x 43 -x 44 -x 45 -x 46 -x 47 -x 48 -x 49 -x 50 \
   -x 51 -x 52 -x 53 -x 54 -x 55 -x 56 -x 57 -x 58 -x 59 -x 60 \
   -x 61 -x 62 -x 63 -x 64 -x 65 -x 66 -x 67 -x 68 -x 69 -x 70 \
   -x 71 -x 72 -x 73 -x 74 -x 75 -x 76 -x 77 -x 78 -x 79 -x 80 \
   -x 81 -x 82 -x 83 -x 84 -x 85 -x 86 -x 87

./statewide_mndot_import.py -U landonb --no-password \
   --run-import --link-values-only \
   -x 21 -x 22 -x 23 -x 24 -x 25 -x 26 -x 27 -x 28 -x 29 -x 30

FIXME: What about -x 0?


mkdir /ccp/var/log/greatermn
cd /ccp/dev/cp/scripts/setupcp/greatermn
nohup \
   ./statewide_mndot_import.py -U landonb --no-password \
   --run-import --link-values-only \
   -x 21 -x 22 -x 23 -x 24 -x 25 -x 26 -x 27 -x 28 -x 29 -x 30 \
   | tee /ccp/var/log/greatermn/mndot_counties-attrs-cntys_21_to_30.log 2>&1 &



/* MOVE_ME: This is a way to audit database for duplicate link_values */

--FIXME: Your script hosed ccpv3_demo:
--SELECT * FROM _lv AS lv1
SELECT
   lv1.lhs_stk_id
   , lv1.rhs_stk_id
   , lv1.brn_id
   , lv1.stk_id
   , lv2.brn_id
   , lv2.stk_id
   , lv1.start_rid
   , lv2.start_rid
   , lv1.acs
   , lv1.infer
   , lv1.vi
   , lv2.acs
   , lv2.infer
   , lv2.vi
--SELECT DISTINCT(lv1.start_rid)
FROM _lv AS lv1
JOIN _lv AS lv2 ON ((lv1.lhs_stk_id = lv2.lhs_stk_id)
                AND (lv1.rhs_stk_id = lv2.rhs_stk_id)
                AND (lv1.stk_id != lv2.stk_id))
WHERE lv1.until_rid = 2000000000
  AND lv2.until_rid = 2000000000
  AND lv1.del IS FALSE
  AND lv2.del IS FALSE
  -- Ignore /item/alert_email and /item/reminder_email.
  AND lv1.lhs_stk_id NOT IN (2498796, 2518539, 2518540)
  AND lv2.lhs_stk_id NOT IN (2498796, 2518539, 2518540)
  -- Ignore /post/revision links, which are multiple-okay.
  AND lv1.rhs_stk_id NOT IN (2498796, 2518539, 2518540)
  AND lv2.rhs_stk_id NOT IN (2498796, 2518539, 2518540)
ORDER BY lv1.start_rid
;

/* You can probably delete this: but I had to delete some
duplicate link_values... hopefully that problem is fixed! */
DELETE FROM group_item_access AS gia
   USING item_versioned AS iv
   WHERE (gia.item_id = iv.system_id)
     AND (iv.valid_start_rid IN (22379, 22384, 22397));
DELETE FROM link_value AS lv
   USING item_versioned AS iv
   WHERE (lv.system_id = iv.system_id)
     AND (iv.valid_start_rid IN (22379, 22384, 22397));
DELETE FROM tag AS tg
   USING item_versioned AS iv
   WHERE (tg.system_id = iv.system_id)
     AND (iv.valid_start_rid IN (22379, 22384, 22397));
DELETE FROM attachment AS at
   USING item_versioned AS iv
   WHERE (at.system_id = iv.system_id)
     AND (iv.valid_start_rid IN (22379, 22384, 22397));
DELETE FROM item_stack AS ist
   USING item_versioned AS iv
   WHERE (ist.stack_id = iv.stack_id)
     AND (iv.valid_start_rid IN (22379, 22384, 22397));
/* SO LONG!
DELETE FROM item_versioned AS iv
   WHERE (iv.valid_start_rid IN (22379, 22384, 22397));
DELETE FROM item_versioned WHERE valid_start_rid = 22379;
DELETE FROM item_versioned WHERE valid_start_rid = 22384;
DELETE FROM item_versioned WHERE valid_start_rid = 22397;
*/


/* Oops, I deleted some tags, dummy. */
ccpv3_demo=> select * from attachment as at join item_versioned as iv using (system_id) where (iv.valid_start_rid IN (22379, 22384, 22397));
 system_id | stack_id | version | branch_id | stack_id | version | deleted | reverted |       name       | valid_start_rid | valid_until_rid | branch_id |      tsvect_name       
-----------+----------+---------+-----------+----------+---------+---------+----------+------------------+-----------------+-----------------+-----------+------------------------
   4055050 |  4568106 |       1 |   2500677 |  4568106 |       1 | f       | f        | brick road       |           22379 |      2000000000 |   2500677 | 'brick':1 'road':2
   4055051 |  4568107 |       1 |   2500677 |  4568107 |       1 | f       | f        | graded road      |           22379 |      2000000000 |   2500677 | 'grade':1 'road':2
   4055052 |  4568108 |       1 |   2500677 |  4568108 |       1 | f       | f        | gravel road      |           22379 |      2000000000 |   2500677 | 'gravel':1 'road':2
   4055053 |  4568109 |       1 |   2500677 |  4568109 |       1 | f       | f        | soil road        |           22379 |      2000000000 |   2500677 | 'road':2 'soil':1
   4055054 |  4568110 |       1 |   2500677 |  4568110 |       1 | f       | f        | high volume      |           22379 |      2000000000 |   2500677 | 'high':1 'volum':2
   4055055 |  4568111 |       1 |   2500677 |  4568111 |       1 | f       | f        | heavy commercial |           22379 |      2000000000 |   2500677 | 'commerci':2 'heavi':1

SELECT * FROM _lv WHERE lhs_stk_id
IN (4568106, 4568107, 4568108, 4568109, 4568110, 4568111);

DELETE FROM group_item_access AS gia
   USING link_value AS lv
   WHERE (gia.item_id = lv.system_id)
     AND (lv.lhs_stack_id
          IN (4568106, 4568107, 4568108, 4568109, 4568110, 4568111));
DELETE FROM link_value WHERE lhs_stack_id
IN (4568106, 4568107, 4568108, 4568109, 4568110, 4568111);





mkdir /ccp/var/log/greatermn
cd /ccp/dev/cp/scripts/setupcp/greatermn
./statewide_mndot_import.py --database ccpv3_live --run-setup

   # What?: Why is the log file empty
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x "watonwan" \
   | tee /ccp/var/log/greatermn/mndot_counties-001-watonwan.log 2>&1

   # What?: Why is the log file empty
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x "lake" \
   | tee /ccp/var/log/greatermn/mndot_counties-002-lake.log 2>&1

   # At least the log file works against the nohup...
nohup \
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x "cook" \
   | tee /ccp/var/log/greatermn/mndot_counties-003-cook.log 2>&1 &

nohup \
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x "Anoka" \
   -x "Carver" \
   -x "Dakota" \
   -x "Hennepin" \
   -x "Ramsey" \
   -x "Scott" \
   -x "Washington" \
   | tee /ccp/var/log/greatermn/mndot_counties-004-metro_counties.log 2>&1 &

nohup \
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x "big stone" \
   | tee /ccp/var/log/greatermn/mndot_counties-005-big_stone.log 2>&1 &

# watonwan 83
# lake 38
# cook 16
# metro 2,10,19,27,62,70,82
# big stone 41
# brown 8
nohup \
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x 1 -x 3 -x 4 -x 5 -x 6 -x 7 -x 9 \
   -x 11 -x 12 -x 13 -x 14 -x 15 -x 17 -x 18 \
   -x 20 -x 21 -x 22 -x 23 -x 24 -x 25 -x 26 -x 28 -x 29 \
   -x 30 -x 31 -x 32 -x 33 -x 34 -x 35 -x 36 -x 37 -x 39 \
   -x 40 -x 42 -x 43 -x 44 -x 45 -x 46 -x 47 -x 48 -x 49 \
   -x 50 -x 51 -x 52 -x 53 -x 54 -x 55 -x 56 -x 57 -x 58 -x 59 \
   -x 60 -x 61 -x 63 -x 64 -x 65 -x 66 -x 67 -x 68 -x 69 \
   -x 71 -x 72 -x 73 -x 74 -x 75 -x 76 -x 77 -x 78 -x 79 \
   -x 80 -x 81 -x 84 -x 85 -x 86 -x 87 \
   | tee /ccp/var/log/greatermn/mndot_counties-006-seventy_six_counties.log 2>&1 &

nohup \
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x "lincoln" \
   | tee /ccp/var/log/greatermn/mndot_counties-007-lincoln.log 2>&1 &

nohup \
   ./statewide_mndot_import.py \
   -U landonb --no-password \
   --database ccpv3_live \
   --run-import \
   -x "brown" \
   | tee /ccp/var/log/greatermn/mndot_counties-008-brown.log 2>&1 &


"""
)

# FIXME: run node_cache_maker.py after
#        fix and run byway_rating script after
#        for conflict ccp, check functional class and compare other attrs?

# FIXME: You're not overwriting existing link_values, are you? Or making dups?

script_name = ('Import MN basemap data into basemap branch')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-11-13'

# ***

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../../util'
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# ***

# NOTE: Import logging first, before other Ccp imports.
import logging
from item.util.item_type import Item_Type
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE1
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('mndot_import')

# ***

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

import os
import sys

import re
import time
import traceback

import conf
import g

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.access_style import Access_Style
from grax.item_manager import Item_Manager
from gwis.exception.gwis_error import GWIS_Error
from item import item_revisionless
from item import item_stack
from item import item_versioned
from item import item_user_access
from item import geofeature
from item import link_value
from item.attc import attachment
from item.attc import attribute
from item.attc import tag
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
from item.feat import region
from item.grac import group
from item.grac import group_item_access
from item.grac import new_item_policy
from item.util.mndot_helper import MnDOT_Helper
from item.util.revision import Revision
from util_ import db_glue
from util_ import geometry
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base
from util_.shapefile_wrapper import Shapefile_Wrapper
from util_.streetaddress import addressconf
from util_.streetaddress import streetaddress

from merge.ccp_merge_layer_base import Ccp_Merge_Layer_Base

# ***

debug_quickie_on = None
#debug_quickie_on = 1000
#debug_quickie_on = 100
#debug_quickie_on = 10
#debug_quickie_on = 3
#debug_quickie_on = 1

# This is how many rows to try to insert at once in db
# when importing from the Shapefiles into the mndot_* tables.
insert_bucket_size = 10000
#insert_bucket_size = 1000
#insert_bucket_size = 100
#insert_bucket_size = 10
#insert_bucket_size = 3
#insert_bucket_size = 1

# This is how many line segments to process from the mndot_*
# tables before calling INSERT. Note that any UPDATEs happen
# immediately, since you can't coalesce UPDATEs.
import_bucket_size = 100
#import_bucket_size = 50
#import_bucket_size = 25 # Averaging 1.93 items per second.
#import_bucket_size = 10
#import_bucket_size = 3
#import_bucket_size = 1

commit_oftener = False
#commit_oftener = True

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 1000
#debug_prog_log.debug_break_loop_cnt = 100
#debug_prog_log.debug_break_loop_cnt = 10
#debug_prog_log.debug_break_loop_cnt = 3
#debug_prog_log.debug_break_loop_cnt = 1

debug_skip_commit = False
#debug_skip_commit = True

if debug_quickie_on:
   insert_bucket_size = debug_quickie_on
   import_bucket_size = debug_quickie_on
   debug_prog_log.debug_break_loops = True
   debug_prog_log.debug_break_loop_cnt = debug_quickie_on
   debug_skip_commit = True

# This is just to save a few seconds while debugging.
debug_n_new_byways = None
debug_n_new_nodes = None
# 2013.11.15: count_new_: no. new byways: 443617 / # new nodes: 235083
# FIXME: Do not check in uncommented:
# This is the whole state:
#debug_n_new_byways = 443617
#debug_n_new_nodes = 235083
# This is the Cook and Lake counties:
#debug_n_new_byways = 
#debug_n_new_nodes = 

# If you've writ rows to item_stack and item_versioned, you can set these
# values so you use the same IDs when you rerun the script.
debug_fst_stack_id = None
debug_fst_system_id = None
debug_cur_stack_id = None
debug_cur_system_id = None
#
#debug_fst_stack_id = 
#debug_fst_system_id = 
#debug_cur_stack_id = 
#debug_cur_system_id = 

debug_mndot_objectids = []
# This is a section of I-94 that a user added to Cyclopath.
# Let's see if we can conflate it...
#debug_mndot_objectids = [415101,]
# Lane count going from 0 to 10? Maybe 0 to 2... maybe.
#debug_mndot_objectids = [404282,]
#Nov-25 11:17:22  DEBG      mndot_import
# mndot_at_lvals_up: exstg lval: sys: 5924125 (stk: 2443597) v: 2 / 
#     rid: 133 / value_integer = 10 was 0 (/byway/lane_count)

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     or debug_n_new_byways
                     or debug_n_new_nodes
                     )

if debugging_enabled:
   log.warning('****************************************')
   log.warning('*                                      *')
   log.warning('*      WARNING: debugging_enabled      *')
   log.warning('*                                      *')
   log.warning('****************************************')

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   # ***

   #
   def prepare(self):

      Ccp_Script_Args.prepare(self)

      # *** Shapefile directory

      self.add_argument(
         '--shapefile-dir', dest='shapefile_dir', action='store', type=str,
         default='/ccp/var/shapefiles/greatermn/mndot_tda',
         help='The path to the MnDOT Shapefiles')

      # *** Shapefile names

      self.add_argument(
         '--shp-counties', dest='shp_counties', action='store', type=str,
         default='STATEWIDE_COUNTIES.shp',
         help='The name of the county basemap data Shapefile')

      self.add_argument(
         '--shp-road-chars', dest='shp_road_chars', action='store', type=str,
         default='Road_characteristics.shp',
         help='The name of the road characteristics Shapefile')

      self.add_argument(
         '--shp-vol-aadt', dest='shp_vol_aadt', action='store', type=str,
         default='TRAFFIC_VOLUME_AADT.shp',
         help='The name of the all-traffic aadt volume Shapefile')

      self.add_argument(
         '--shp-vol-hcaadt', dest='shp_vol_hcaadt', action='store', type=str,
         default='TRAFFIC_VOLUME_HCADT.shp',
         help='The name of the heavy commercial only aadt volume Shapefile')

      # *** Task Choices

      self.add_argument(
         '--run-setup', dest='run_setup', action='store_true',
         help='Do not import into Cyclopath; just populate MnDOT tables')

      self.add_argument(
         '--run-import', dest='run_import', action='store_true',
         help='Import from MnDOT tables into Cyclopath basemap')

      self.add_argument(
         '--run-teardown', dest='run_teardown', action='store_true',
         help='Delete the MnDOT tables from the database')

      # *** Runtime Options

      # You can split the import into multiple operations if you want...
      self.add_argument(
         '-x', '--restrict-counties', dest='restrict_counties',
         default=[], action='append', type=str,
         help='County name or ID to use to limit import')

      # If you're just testing or importing county-by-count, you can skip
      # recalculating the branch coverage area. It's generally a fast
      # operation, but on some dev machines it takes a number of seconds.
      self.add_argument(
         '--skip-coverage-area', dest='skip_coverage_area',
         default=False, action='store_true',
         help='Do not call byway.Many.branch_coverage_area_update')

      # You can also split the import into just line segments or just
      # link_values.
      self.add_argument(
         '--line-segments-only', dest='line_segments_only',
         default=False, action='store_true',
         help='Only create Cyclopath byways; skip the link_values')
      #
      self.add_argument(
         '--link-values-only', dest='link_values_only',
         default=False, action='store_true',
         help='Only create Cyclopath link_values; skip the byways')

      self.add_argument(
         '--force-update-geofeature', dest='force_update_geofeature',
         default=False, action='store_true',
         help='Update geofeature row columns when adding link_values')

      self.add_argument(
         '--update-existing-lvals', dest='update_existing_lvals',
         default=False, action='store_true',
         help="Update conflict byways' link_values if they differ")

   #
   def verify_handler(self):

      ok = Ccp_Script_Args.verify_handler(self)

      if (not debugging_enabled) and self.cli_opts.skip_coverage_area:
         log.info('.....................................')
         log.info('Skipping coverage_area update... fyi.')
         log.info('.....................................')

      if (not (self.cli_opts.run_setup
               or self.cli_opts.run_import
               or self.cli_opts.run_teardown)):
         log.error('Nothing to do: try one or more of: %s, %s, or %s'
                   % ('--run-setup', '--run-import', '--run-teardown',))
         ok = False

      if (self.cli_opts.run_import
          and self.cli_opts.line_segments_only
          and self.cli_opts.link_values_only):
         log.error('Nothing to do: try just one of %s or %s'
                   % ('--line-segments-only', '--link-values-only',))
         ok = False

      return ok

   # ***

# *** Statewide_MnDOT_Import

class Statewide_MnDOT_Import(Ccp_Script_Base):

   class Row_Iter(object):

      def __init__(self):
         pass

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

   # ***

   #
   def query_builder_prepare(self):
      Ccp_Script_Base.query_builder_prepare(self)

   # ***

   #
   # Called by go() with a hot 'n ready self.qb.
   def go_main(self):

      do_commit = False

      try:

         self.qb.db.transaction_begin_rw()

         # MAYBE: Add a new command that runs setup and imports, and maybe
         #        tearsdown, rather than having to run this script three
         #        times. But for now, while developing, it's easiest to
         #        split the operation into three distinct tasks, and it's
         #        just a run-once import script, anyway, so get over it.

         if self.cli_opts.run_setup:
            self.mndot_tables_dropinit()
            self.mndot_tables_populate()
            self.mndot_tables_indexify()

         if self.cli_opts.run_import:
            self.mndot_tables_to_ccp()

         if self.cli_opts.run_teardown:
            self.mndot_tables_delete()

         log.debug('Committing transaction')

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         # FIXME: g.assurt()s that are caught here have empty msgs?
         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   # *** TABLE MANAGEMENT

   #
   def mndot_tables_dropinit(self):

      self.mndot_tables_delete()
      self.mndot_tables_create()

   #
   def mndot_tables_delete(self):

      mndot_tables = (
         'mndot_counties',
         'mndot_road_char',
         'mndot_vol_aadt',
         'mndot_vol_hcaadt',)

      for table_name in mndot_tables:
         log.debug('Dropping mndot table: %s' % (table_name,))
         drop_sql = ("DROP TABLE IF EXISTS %s.%s"
                     % (conf.instance_name, table_name,))
         self.qb.db.sql(drop_sql)

   #
   def mndot_tables_create(self):

      self.table_create_counties()
      self.table_create_road_char()
      self.table_create_vol_aadt()
      self.table_create_vol_hcaadt()

   #
   def mndot_tables_populate(self):

      # 2013.11.13
      #  counties:   444343 loops took 2.03 mins.
      #  road_char:  229647 loops took 2.91 mins.
      #  vol_aadt:    33692 loops took 0.18 mins.
      #  vol_hcaadt:   4405 loops took 0.02 mins.

      self.table_populate_counties()
      self.table_populate_road_char()
      self.table_populate_vol_aadt()
      self.table_populate_vol_hcaadt()

   #
   def mndot_tables_indexify(self):

      self.table_indexify_counties()
      self.table_indexify_road_char()
      self.table_indexify_vol_aadt()
      self.table_indexify_vol_hcaadt()

   # *** CREATE AND INDEX TABLES

   #
   def table_create_counties(self):

      log.debug('Creating mndot table: mndot_counties')

      create_sql = (
         """
         CREATE TABLE %s.mndot_counties (

            mndot_counties_id SERIAL PRIMARY KEY

            , objectid INTEGER  -- Shapefile ID

            --, tis_one INTEGER
            --, tis_id INTEGER           -- 'tis_code'
            , tis_code TEXT            -- 'tis_code'
            , tis_directional TEXT     -- 'directiona'
            , traffic_direction TEXT   -- 'traf_dir'
            , divided_roadway TEXT     -- 'divid'
            , begm REAL
            , endm REAL

            , str_name TEXT
            --, str_pfx TEXT
            --, base_name TEXT
            --, str_type TEXT
            --, str_sfx TEXT
            --, e_911 TEXT

            , rte_syst SMALLINT
            --, rte_num INTEGER

            , cnty_code SMALLINT

            --, date_pro TIMESTAMP
            --, date_act TIMESTAMP
            --, date_edt TIMESTAMP

            , mndot_road_char_id INTEGER

            , ccp_conflict INTEGER
            , conflict_confidence SMALLINT

            , ccp_stack_id INTEGER
         )
         """ % (conf.instance_name,))
      self.qb.db.sql(create_sql)

      add_geom_sql = (
         """
         SELECT AddGeometryColumn('mndot_counties', 'geometry', %d,
                                  'LINESTRING', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)

      # The node pts are lossy, like node_byway, so we can find existing nodes,
      # as opposed to being lossless, like node_endpt_xy.
      #
      add_geom_sql = (
         """
         SELECT AddGeometryColumn('mndot_counties', 'beg_node_pt', %s,
                                  'POINT', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)
      #
      add_geom_sql = (
         """
         SELECT AddGeometryColumn('mndot_counties', 'fin_node_pt', %s,
                                  'POINT', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)

   #
   def table_indexify_counties(self):

      log.debug('Indexing mndot table: mndot_counties')

      # TIS_CODE index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_tis_code;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_tis_code
            ON mndot_counties (tis_code)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # DIRECTIONA index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_tis_directional;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_tis_directional
            ON mndot_counties (tis_directional)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # RTE_SYST index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_rte_syst;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_rte_syst
            ON mndot_counties (rte_syst)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # CCP_CONFLICT index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_ccp_conflict;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_ccp_conflict
            ON mndot_counties (ccp_conflict)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # CCP_STACK_ID index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_ccp_stack_id;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_ccp_stack_id
            ON mndot_counties (ccp_stack_id)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # GEOMETRY index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_geometry;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_geometry ON mndot_counties
            USING GIST (geometry);
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # VALID GEOMETRY constraint
      #
      drop_constr_sql = (
         """
         SELECT cp_constraint_drop_safe(
                  'mndot_counties',
                  'enforce_valid_geometry');
         """)
      #
      create_constr_sql = (
         """
         ALTER TABLE mndot_counties ADD CONSTRAINT enforce_valid_geometry
            CHECK (IsValid(geometry));
         """)
      #
      self.qb.db.sql(drop_constr_sql)
      self.qb.db.sql(create_constr_sql)

      # More GEOMETRY indices
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_beg_node_pt;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_beg_node_pt ON mndot_counties
            USING GIST (beg_node_pt);
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)
      ##
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_counties_fin_node_pt;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_counties_fin_node_pt ON mndot_counties
            USING GIST (fin_node_pt);
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

   #
   def table_create_road_char(self):

      log.debug('Creating mndot table: mndot_road_char')

      create_sql = (
         """
         CREATE TABLE %s.mndot_road_char (

            mndot_road_char_id SERIAL PRIMARY KEY

            , objectid INTEGER

            , tis_id TEXT
            , directional_tis_id TEXT

            , from_true_miles REAL
            , to_true_miles REAL

            , route_system_code SMALLINT
            , route_system_name TEXT
            , route_system_abbreviation TEXT

            --, route_system_report TEXT
            --, roadway_name TEXT
            --, directional_roadway_name TEXT
            --, directional_roadway_name TEXT
            --, from_ref_post_offset TEXT
            --, to_ref_post_offset TEXT

            , divided_oneway_code CHAR(1)
            , divided_oneway TEXT
            , dir_travel_on_segment_code TEXT
            , direction_travel_on_segment TEXT

            --, corridor_code TEXT
            --, corridor TEXT
            --, control_section_code SMALLINT
            --, legislative_route_code SMALLINT
            --, national_highway_system_code SMALLINT
            --, truck_route_classification SMALLINT
            --, urban_municipal_code SMALLINT
            --, urban_municipal TEXT
            --, city_numr_fed_aid_urban_area SMALLINT

            , functional_classification_code SMALLINT
            , functional_classification TEXT

            , surface_type_code TEXT
            , surface_type TEXT
            , surface_width TEXT
            , right_shoulder_type_code TEXT
            , right_shoulder_type TEXT
            , right_shoulder_width TEXT
            , left_shoulder_type_code TEXT
            , left_shoulder_type TEXT
            , left_shoulder_width TEXT
            --, median_type_code SMALLINT
            --, median_type TEXT
            --, median_width SMALLINT
            --, curbs_code SMALLINT
            --, curbs TEXT

            , number_of_lanes_im SMALLINT
            , number_of_lanes_dm SMALLINT
            , total_number_of_lanes SMALLINT
            --, turning_lanes_i_code SMALLINT
            --, turning_lanes_i TEXT
            --, turning_lanes_d_code SMALLINT
            --, turning_lanes_d TEXT
            --, additional_lanes_code SMALLINT
            --, additional_lanes TEXT

            , control_of_access_code SMALLINT
            , control_of_access TEXT

            --, inventory_date TIMESTAMP
            --, update_date TIMESTAMP
            --, description TEXT
         )
         """ % (conf.instance_name,))
      self.qb.db.sql(create_sql)

      add_geom_sql = (
         """
         SELECT AddGeometryColumn('mndot_road_char', 'geometry', %s,
                                  'LINESTRING', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)

   #
   def table_indexify_road_char(self):

      log.debug('Indexing mndot table: mndot_road_char')

      # GEOMETRY index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_road_char_geometry;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_road_char_geometry ON mndot_road_char
            USING GIST (geometry);
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # TIS_ID index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_road_char_tis_id;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_road_char_tis_id
            ON mndot_road_char (tis_id)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # DIRECTIONAL_TIS_ID index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_road_char_directional_tis_id;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_road_char_directional_tis_id
            ON mndot_road_char (directional_tis_id)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # ROUTE_SYSTEM_CODE index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_road_char_route_system_code;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_road_char_route_system_code
            ON mndot_road_char (route_system_code)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # FUNCTIONAL_CLASSIFICATION_CODE index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_road_char_functional_classification_code;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_road_char_functional_classification_code
            ON mndot_road_char (functional_classification_code)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # CONTROL_OF_ACCESS_CODE index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_road_char_control_of_access_code;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_road_char_control_of_access_code
            ON mndot_road_char (control_of_access_code)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

   #
   def table_create_vol_aadt(self):

      log.debug('Creating mndot table: mndot_vol_aadt')

      create_sql = (
         """
         CREATE TABLE %s.mndot_vol_aadt (

            mndot_vol_aadt_id SERIAL PRIMARY KEY

            , objectid INTEGER

            -- The TIS ID, e.g., 0300000610
            --, route_ident INTEGER
            , route_ident TEXT
            -- The start of the TIS ID, e.g., 03
            --, route_system_code TEXT
            -- The end of the TIS ID, e.g., 610
            --, route_number INTEGER

            --, sequence_number INTEGER
            --, route_name TEXT
            --, location_description TEXT
            --, vehicle_class_number SMALLINT

            , aadt_1992 INTEGER
            , aadt_1994 INTEGER
            , aadt_1995 INTEGER
            , aadt_1996 INTEGER
            , aadt_1997 INTEGER
            , aadt_1998 INTEGER
            , aadt_1999 INTEGER
            , aadt_2000 INTEGER
            , aadt_2001 INTEGER
            , aadt_2002 INTEGER
            , aadt_2003 INTEGER
            , aadt_2004 INTEGER
            , aadt_2005 INTEGER
            , aadt_2006 INTEGER
            , aadt_2007 INTEGER
            , aadt_2008 INTEGER
            , aadt_2009 INTEGER
            , aadt_2010 INTEGER
            , aadt_2011 INTEGER
            , aadt_2012 INTEGER
            --, current_year INTEGER
            --, current_volume INTEGER
         )
         """ % (conf.instance_name,))
      self.qb.db.sql(create_sql)

      add_geom_sql = (
         """
         SELECT AddGeometryColumn('mndot_vol_aadt', 'geometry', %s,
                                  'LINESTRING', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)

   #
   def table_indexify_vol_aadt(self):

      log.debug('Indexing mndot table: mndot_vol_aadt')

      # GEOMETRY index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_vol_aadt_geometry;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_vol_aadt_geometry ON mndot_vol_aadt
            USING GIST (geometry);
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # ROUTE_IDENT index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_vol_aadt_route_ident
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_vol_aadt_route_ident
            ON mndot_vol_aadt (route_ident)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

   #
   def table_create_vol_hcaadt(self):

      log.debug('Creating mndot table: mndot_vol_hcaadt')

      create_sql = (
         """
         CREATE TABLE %s.mndot_vol_hcaadt (

            mndot_vol_hcaadt_id SERIAL PRIMARY KEY

            , objectid INTEGER

            -- The TIS ID, e.g., 0300000610
            --, route_ident INTEGER
            , route_ident TEXT
            -- The start of the TIS ID, e.g., 03
            --, route_system_code TEXT
            -- The end of the TIS ID, e.g., 610
            --, route_number INTEGER

            --, sequence_number INTEGER
            --, route_name TEXT
            --, location_description TEXT
            --, vehicle_class_number SMALLINT

            --, hcaadt_1992 INTEGER
            , hcaadt_1994 INTEGER
            --, hcaadt_1995 INTEGER
            , hcaadt_1996 INTEGER
            --, hcaadt_1997 INTEGER
            , hcaadt_1998 INTEGER
            --, hcaadt_1999 INTEGER
            , hcaadt_2000 INTEGER
            --, hcaadt_2001 INTEGER
            , hcaadt_2002 INTEGER
            --, hcaadt_2003 INTEGER
            , hcaadt_2004 INTEGER
            --, hcaadt_2005 INTEGER
            , hcaadt_2006 INTEGER
            , hcaadt_2007 INTEGER
            , hcaadt_2008 INTEGER
            , hcaadt_2009 INTEGER
            , hcaadt_2010 INTEGER
            , hcaadt_2011 INTEGER
            , hcaadt_2012 INTEGER
            --, current_year INTEGER
            --, current_volume INTEGER
         )
         """ % (conf.instance_name,))
      self.qb.db.sql(create_sql)

      add_geom_sql = (
         """
         SELECT AddGeometryColumn('mndot_vol_hcaadt', 'geometry', %s,
                                  'LINESTRING', 2)
         """ % (conf.default_srid,))
      self.qb.db.sql(add_geom_sql)

   #
   def table_indexify_vol_hcaadt(self):

      log.debug('Indexing mndot table: mndot_vol_hcaadt')

      # GEOMETRY index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_vol_hcaadt_geometry;
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_vol_hcaadt_geometry ON mndot_vol_hcaadt
            USING GIST (geometry);
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

      # ROUTE_IDENT index
      #
      drop_index_sql = (
         """
         DROP INDEX IF EXISTS mndot_vol_hcaadt_route_ident
         """)
      #
      create_index_sql = (
         """
         CREATE INDEX mndot_vol_hcaadt_route_ident
            ON mndot_vol_hcaadt (route_ident)
         """)
      #
      self.qb.db.sql(drop_index_sql)
      self.qb.db.sql(create_index_sql)

   # *** POPULATE TABLES from Shapefiles

   #
   def get_prog_log(self):
      # Use a prog logger to show progress to the dev running this script,
      # and set debug_break_loops so we can batch process chunks of data.
      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_silently = True
      #
      prog_sql = Debug_Progress_Logger(log_freq=insert_bucket_size)
      prog_sql.debug_break_loops = True
      prog_log.log_freq = prog_sql.log_freq
      prog_sql.info_print_speed_enable = True
      prog_sql.info_print_speed_beging = 1
      prog_sql.info_print_speed_during = 0
      prog_sql.info_print_speed_finish = 1
      return (prog_log, prog_sql,)

   #
   def table_populate_counties(self):

      log.debug('Populating mndot table: mndot_counties')

      self.db_commit_maybe()

      shp_name = os.path.join(self.cli_opts.shapefile_dir,
                              self.cli_opts.shp_counties)

      # *** Open the Shapefile.

      self.shpw = Shapefile_Wrapper(shp_name, 'OBJECTID')
      self.shpw.source_open()

      # *** Iterate through the layer features and make rows to insert.

      rows_to_insert = []

      (prog_log, prog_sql,) = self.get_prog_log()

      self.shpw.gdb_layer.ResetReading()

      n_features = Shapefile_Wrapper.ogr_layer_feature_count(
                                          self.shpw.gdb_layer)
      log.info('Importing %d county feats...' % (n_features,))
      prog_sql.loop_max = n_features
      prog_log.loop_max = n_features

      for feat in self.shpw.gdb_layer:

         geoms = self.shpw.get_line_geoms(feat)

         for geom in geoms:

#                   ST_MakePoint(ROUND(ST_X(ST_StartPoint('SRID=%d;%s')), 1),
#                                ROUND(ST_Y(ST_StartPoint('SRID=%d;%s')), 1)),
#                   ST_MakePoint(ROUND(ST_X(ST_EndPoint('SRID=%d;%s')), 1),
#                                ROUND(ST_Y(ST_EndPoint('SRID=%d;%s')), 1))
# ccpv3_demo=> select (1.5499999999999 * 10)::INT;

            row_to_insert = (
               """(%d, '%s', '%s', '%s', '%s',
                   %f, %f, %s, %d, %d,
                   'SRID=%d;%s',
                   ST_SetSRID(
                     ST_MakePoint(
                        ROUND(ST_X(ST_StartPoint('SRID=%d;%s'))::NUMERIC, 1),
                        ROUND(ST_Y(ST_StartPoint('SRID=%d;%s'))::NUMERIC, 1)),
                     %d),
                   ST_SetSRID(
                     ST_MakePoint(
                        ROUND(ST_X(  ST_EndPoint('SRID=%d;%s'))::NUMERIC, 1),
                        ROUND(ST_Y(  ST_EndPoint('SRID=%d;%s'))::NUMERIC, 1)),
                     %d)
                   )"""
               % (int(feat.GetFieldAsString('OBJECTID')),
                  #int(feat.GetFieldAsString('TIS_CODE')), # tis_id
                  feat.GetFieldAsString('TIS_CODE'), # tis_id
                  feat.GetFieldAsString('DIRECTIONA'), # tis_directional
                  feat.GetFieldAsString('TRAF_DIR'), # traffic_direction
                  feat.GetFieldAsString('DIVID'), # divided_roadway
                  #
                  float(feat.GetFieldAsString('BEGM')),
                  float(feat.GetFieldAsString('ENDM')),
                  self.qb.db.quoted(feat.GetFieldAsString('STR_NAME')),
                  int(feat.GetFieldAsString('RTE_SYST')),
                  int(feat.GetFieldAsString('CNTY_CODE') or 0),
                  #
                  conf.default_srid,
                  geom.ExportToWkt(),
                  #
                  conf.default_srid,
                  geom.ExportToWkt(),
                  conf.default_srid,
                  geom.ExportToWkt(),
                  conf.default_srid,
                  #
                  conf.default_srid,
                  geom.ExportToWkt(),
                  conf.default_srid,
                  geom.ExportToWkt(),
                  conf.default_srid,
                  ))
            rows_to_insert.append(row_to_insert)

            # On runic, [lb] sees 10,000 iters every 45 secs., or 222.2 / sec.
            if prog_sql.loops_inc():
               self.table_insert_counties(rows_to_insert)
               rows_to_insert = []

         # end: for geom in geoms

         if prog_log.loops_inc():
            break

      if rows_to_insert:
         self.table_insert_counties(rows_to_insert)
         rows_to_insert = []

      prog_sql.loops_fin()

      # *** Cleanup

      self.shpw.source_close()

   #
   def table_insert_counties(self, rows_to_insert):

      #log.debug('Partial insert into mndot table: mndot_counties')

      insert_sql = (
         """
         INSERT INTO %s.mndot_counties (
            objectid
            --, tis_id
            , tis_code
            , tis_directional
            , traffic_direction
            , divided_roadway
            , begm
            , endm
            , str_name
            , rte_syst
            , cnty_code

            , geometry
            , beg_node_pt
            , fin_node_pt
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(rows_to_insert),))

      self.qb.db.sql(insert_sql)

   #
   def table_populate_road_char(self):

      log.debug('Populating mndot table: mndot_road_char')

      self.db_commit_maybe()

      shp_name = os.path.join(self.cli_opts.shapefile_dir,
                              self.cli_opts.shp_road_chars)

      # *** Open the Shapefile.

      self.shpw = Shapefile_Wrapper(shp_name, 'OBJECTID')
      self.shpw.source_open()

      # *** Iterate through the layer features and make rows to insert.

      rows_to_insert = []

      (prog_log, prog_sql,) = self.get_prog_log()

      self.shpw.gdb_layer.ResetReading()

      n_features = Shapefile_Wrapper.ogr_layer_feature_count(
                                          self.shpw.gdb_layer)
      log.info('Importing %d road_char feats...' % (n_features,))
      prog_sql.loop_max = n_features
      prog_log.loop_max = n_features

      for feat in self.shpw.gdb_layer:

         geoms = self.shpw.get_line_geoms(feat)

         for geom in geoms:

            row_to_insert = (

               ("(%d, '%s', '%s', %f, %f, %d, '%s', '%s', '%s', '%s'"
                + ", '%s', '%s', %d, '%s', '%s', '%s', '%s', '%s', '%s', '%s'"
                + ", '%s', '%s', '%s', %d, %d, %d, %d, '%s', 'SRID=%d;%s')")
               % (

   # NOTE: GetFieldAsInteger is forgiving, so cast instead.
   # In the Shapefile, everything except OBJECTID is a string...
   int(feat.GetFieldAsString('OBJECTID')),
   feat.GetFieldAsString('TIS_ID'), # tis_id
   feat.GetFieldAsString('DIRECTIONA'), # directional_tis_id
   float(feat.GetFieldAsString('FROM_TRUE_')), # from_true_miles
   float(feat.GetFieldAsString('TO_TRUE_MI')), # to_true_miles
   #
   int(feat.GetFieldAsString('ROUTE_SYST')), # route_system_code
   feat.GetFieldAsString('ROUTE_SY_1'), # route_system_name
   feat.GetFieldAsString('ROUTE_SY_2'), # route_system_abbreviation
   feat.GetFieldAsString('DIVIDED_ON'), # divided_oneway_code
   feat.GetFieldAsString('DIVIDED__1'), # divided_oneway
   ##
   feat.GetFieldAsString('DIR_TRAVEL'), # dir_travel_on_segment_code
   feat.GetFieldAsString('DIRECTION_'), # direction_travel_on_segment
   int(feat.GetFieldAsString('FUNCTIONAL')), # functional_classification_code
   feat.GetFieldAsString('FUNCTION_1'), # functional_classification
   feat.GetFieldAsString('SURFACE_TY'), # surface_type_code
   #
   feat.GetFieldAsString('surface__1'), # surface_type
   feat.GetFieldAsString('surface_wi'), # surface_width
   feat.GetFieldAsString('RIGHT_SHOU'), # right_shoulder_type_code
   feat.GetFieldAsString('RIGHT_SH_1'), # right_shoulder_type
   feat.GetFieldAsString('RIGHT_SH_2'), # right_shoulder_width
   ##
   feat.GetFieldAsString('LEFT_SHOUL'), # left_shoulder_type_code
   feat.GetFieldAsString('LEFT_SHO_1'), # left_shoulder_type
   feat.GetFieldAsString('LEFT_SHO_2'), # left_shoulder_width
   int(feat.GetFieldAsString('NUMBER_OF_')), # number_of_lanes_im
   int(feat.GetFieldAsString('NUMBER_OF1')), # number_of_lanes_dm
   #
   int(feat.GetFieldAsString('TOTAL_NUMB')), # total_number_of_lanes
   int(feat.GetFieldAsString('CONTROL_OF')), # control_of_access_code
   feat.GetFieldAsString('CONTROL__1'), # control_of_access

                  conf.default_srid,
                  geom.ExportToWkt(),
                  ))
            rows_to_insert.append(row_to_insert)

            if prog_sql.loops_inc():
               self.table_insert_road_char(rows_to_insert)
               rows_to_insert = []

         # end: for geom in geoms

         if prog_log.loops_inc():
            break

      if rows_to_insert:
         self.table_insert_road_char(rows_to_insert)
         rows_to_insert = []

      prog_sql.loops_fin()

      # *** Cleanup

      self.shpw.source_close()

   #
   def table_insert_road_char(self, rows_to_insert):

      #log.debug('Partial insert into mndot table: mndot_road_char')

      insert_sql = (
         """
         INSERT INTO %s.mndot_road_char (
            objectid
            , tis_id
            , directional_tis_id
            , from_true_miles
            , to_true_miles
            , route_system_code
            , route_system_name
            , route_system_abbreviation
            , divided_oneway_code
            , divided_oneway
            , dir_travel_on_segment_code
            , direction_travel_on_segment
            , functional_classification_code
            , functional_classification
            , surface_type_code
            , surface_type
            , surface_width
            , right_shoulder_type_code
            , right_shoulder_type
            , right_shoulder_width
            , left_shoulder_type_code
            , left_shoulder_type
            , left_shoulder_width
            , number_of_lanes_im
            , number_of_lanes_dm
            , total_number_of_lanes
            , control_of_access_code
            , control_of_access

            , geometry
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(rows_to_insert),))

      self.qb.db.sql(insert_sql)

   #
   def table_populate_vol_aadt(self):

      log.debug('Populating mndot table: mndot_vol_aadt')

      self.db_commit_maybe()

      shp_name = os.path.join(self.cli_opts.shapefile_dir,
                              self.cli_opts.shp_vol_aadt)

      # *** Open the Shapefile.

      self.shpw = Shapefile_Wrapper(shp_name, 'OBJECTID')
      self.shpw.source_open()

      # *** Iterate through the layer features and make rows to insert.

      rows_to_insert = []

      (prog_log, prog_sql,) = self.get_prog_log()

      self.shpw.gdb_layer.ResetReading()

      n_features = Shapefile_Wrapper.ogr_layer_feature_count(
                                          self.shpw.gdb_layer)
      log.info('Importing %d road_char feats...' % (n_features,))
      prog_sql.loop_max = n_features
      prog_log.loop_max = n_features

      for feat in self.shpw.gdb_layer:

         geoms = self.shpw.get_line_geoms(feat)

         for geom in geoms:

            row_to_insert = (
                # This silly interpolation makes 22 '%d's.
               ("(%%d, '%%s'%s, 'SRID=%%d;%%s')" % (', %d' * 20,))
               % (int(feat.GetFieldAsString('OBJECTID')),
                  feat.GetFieldAsString('ROUTE_IDEN'), # route_ident
                  int(feat.GetFieldAsString('AADT_1992')),
                  int(feat.GetFieldAsString('AADT_1994')),
                  int(feat.GetFieldAsString('AADT_1995')),
                  int(feat.GetFieldAsString('AADT_1996')),
                  int(feat.GetFieldAsString('AADT_1997')),
                  int(feat.GetFieldAsString('AADT_1998')),
                  int(feat.GetFieldAsString('AADT_1999')),
                  int(feat.GetFieldAsString('AADT_2000')),
                  int(feat.GetFieldAsString('AADT_2001')),
                  int(feat.GetFieldAsString('AADT_2002')),
                  int(feat.GetFieldAsString('AADT_2003')),
                  int(feat.GetFieldAsString('AADT_2004')),
                  int(feat.GetFieldAsString('AADT_2005')),
                  int(feat.GetFieldAsString('AADT_2006')),
                  int(feat.GetFieldAsString('AADT_2007')),
                  int(feat.GetFieldAsString('AADT_2008')),
                  int(feat.GetFieldAsString('AADT_2009')),
                  int(feat.GetFieldAsString('AADT_2010')),
                  int(feat.GetFieldAsString('AADT_2011')),
                  int(feat.GetFieldAsString('AADT_2012')),

                  conf.default_srid,
                  geom.ExportToWkt(),
                  ))
            rows_to_insert.append(row_to_insert)

            if prog_sql.loops_inc():
               self.table_insert_vol_aadt(rows_to_insert)
               rows_to_insert = []

         # end: for geom in geoms

         if prog_log.loops_inc():
            break

      if rows_to_insert:
         self.table_insert_vol_aadt(rows_to_insert)
         rows_to_insert = []

      prog_sql.loops_fin()

      # *** Cleanup

      self.shpw.source_close()

   #
   def table_insert_vol_aadt(self, rows_to_insert):

      #log.debug('Partial insert into mndot table: mndot_vol_aadt')

      insert_sql = (
         """
         INSERT INTO %s.mndot_vol_aadt (
            objectid
            , route_ident
            , aadt_1992
            , aadt_1994
            , aadt_1995
            , aadt_1996
            , aadt_1997
            , aadt_1998
            , aadt_1999
            , aadt_2000
            , aadt_2001
            , aadt_2002
            , aadt_2003
            , aadt_2004
            , aadt_2005
            , aadt_2006
            , aadt_2007
            , aadt_2008
            , aadt_2009
            , aadt_2010
            , aadt_2011
            , aadt_2012

            , geometry
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(rows_to_insert),))

      self.qb.db.sql(insert_sql)

   #
   def table_populate_vol_hcaadt(self):

      log.debug('Populating mndot table: mndot_vol_hcaadt')

      self.db_commit_maybe()

      shp_name = os.path.join(self.cli_opts.shapefile_dir,
                              self.cli_opts.shp_vol_hcaadt)

      # *** Open the Shapefile.

      self.shpw = Shapefile_Wrapper(shp_name, 'OBJECTID')
      self.shpw.source_open()

      # *** Iterate through the layer features and make rows to insert.

      rows_to_insert = []

      (prog_log, prog_sql,) = self.get_prog_log()

      self.shpw.gdb_layer.ResetReading()

      n_features = Shapefile_Wrapper.ogr_layer_feature_count(
                                          self.shpw.gdb_layer)
      log.info('Importing %d road_char feats...' % (n_features,))
      prog_sql.loop_max = n_features
      prog_log.loop_max = n_features

      for feat in self.shpw.gdb_layer:

         geoms = self.shpw.get_line_geoms(feat)

         for geom in geoms:

            row_to_insert = (
                # Makes a ton of '%d's, d.
               ("(%%d, '%%s'%s, 'SRID=%%d;%%s')" % (', %d' * 13,))
               % (int(feat.GetFieldAsString('OBJECTID')),
                  feat.GetFieldAsString('ROUTE_IDEN'), # route_ident
                  # There's a cute lite Esri behavior here in how it renames
                  # columns to the 10 char max: HCAADT_1994 becomes HCAADT_199,
                  # and then Esri just counts from there... ([lb] would expect,
                  # with the typical naming behaviour, HCAADT_1994 becomes
                  # HCAADT_199, and then HCAADT_1996 turns into HCAADT__01 etc.
                  int(feat.GetFieldAsString('HCAADT_199')), # HCAADT_1994
                  int(feat.GetFieldAsString('HCAADT_200')), # HCAADT_1996
                  int(feat.GetFieldAsString('HCAADT_201')), # HCAADT_1998
                  int(feat.GetFieldAsString('HCAADT_202')), # HCAADT_2000
                  int(feat.GetFieldAsString('HCAADT_203')), # HCAADT_2002
                  int(feat.GetFieldAsString('HCAADT_204')), # HCAADT_2004
                  int(feat.GetFieldAsString('HCAADT_205')), # HCAADT_2006
                  int(feat.GetFieldAsString('HCAADT_206')), # HCAADT_2007
                  int(feat.GetFieldAsString('HCAADT_207')), # HCAADT_2008
                  int(feat.GetFieldAsString('HCAADT_208')), # HCAADT_2009
                  int(feat.GetFieldAsString('HCAADT_209')), # HCAADT_2010
                  int(feat.GetFieldAsString('HCAADT_210')), # HCAADT_2011
                  int(feat.GetFieldAsString('HCAADT_211')), # HCAADT_2012

                  conf.default_srid,
                  geom.ExportToWkt(),
                  ))
            rows_to_insert.append(row_to_insert)

            if prog_sql.loops_inc():
               self.table_insert_vol_hcaadt(rows_to_insert)
               rows_to_insert = []

         # end: for geom in geoms

         if prog_log.loops_inc():
            break

      if rows_to_insert:
         self.table_insert_vol_hcaadt(rows_to_insert)
         rows_to_insert = []

      prog_sql.loops_fin()

      # *** Cleanup

      self.shpw.source_close()

   #
   def table_insert_vol_hcaadt(self, rows_to_insert):

      #log.debug('Partial insert into mndot table: mndot_vol_hcaadt')

      insert_sql = (
         """
         INSERT INTO %s.mndot_vol_hcaadt (
            objectid
            , route_ident
            , hcaadt_1994
            , hcaadt_1996
            , hcaadt_1998
            , hcaadt_2000
            , hcaadt_2002
            , hcaadt_2004
            , hcaadt_2006
            , hcaadt_2007
            , hcaadt_2008
            , hcaadt_2009
            , hcaadt_2010
            , hcaadt_2011
            , hcaadt_2012

            , geometry
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(rows_to_insert),))

      self.qb.db.sql(insert_sql)

   # ***

   #
   def mndot_tables_to_ccp(self):

      #self.cli_args.close_query(do_commit=False)
      self.qb.db.transaction_finish(do_commit=False)

      self.mndot_import_prepare()

      self.ccp_hausdorff_bucket = {}

      self.public_group_id = group.Many.public_group_id(self.qb.db)

      # Start by locking the revision table, making a new revision, and
      # claiming as many stack and system IDs as we think we'll need.
      # And then unlock the revision table: since all of our line segments
      # are new to Cyclopath, we don't have to worry about conflicting with
      # overlapping user edits.

      self.claim_revision_and_seq_ids()

      # TEST_ME: Commit changes from flashclient while this script is running.

      # Process the line segments. One by one. Unfortunately, there's not
      # really a way to bulk process them, since we have to check our database
      # for matching line segments. It's about Conflate, conflate, conflate!

      self.import_tediously()

      # Now we can calculate the revision geometry and coverage_area.

      self.update_relevant_geometry_summaries()

      #? self.qb.db.transaction_begin_rw()

      self.hausdorff_bucket_show(self.ccp_hausdorff_bucket, 'ccp hausdorff')

   # ***

   #
   def mndot_import_prepare(self):

      self.all_branch_ids = []
      branch_ids_sql = (
         "SELECT DISTINCT stack_id FROM branch ORDER BY stack_id ASC")
      rows = self.qb.db.sql(branch_ids_sql)
      for row in rows:
         self.all_branch_ids.append(row['stack_id'])
      g.assurt(self.all_branch_ids)

      self.the_counties = {}
      self.county_ids = []
      self.where_clause_counties = ''
      self.where_clause_complete = ''

      if self.cli_opts.restrict_counties:

         self.the_counties = MnDOT_Helper.resolve_to_county_ids(
                        self.qb, self.cli_opts.restrict_counties)
         self.county_ids = self.the_counties.keys()

         self.county_ids_str_set = (
            "(%s)" % (','.join([str(x) for x in self.county_ids]),))
         if len(self.county_ids) == 1:
            self.where_clause_counties = (
               "(cnty_code = %d)" % (self.county_ids[0],))
         else:
            self.where_clause_counties = (
               "(cnty_code IN %s)"
               % (self.county_ids_str_set,))
         self.where_clause_complete = (
            "WHERE %s" % (self.where_clause_counties,))

         log.debug('Restricting import by county(ies): %s / %s'
                   % (self.the_counties.values(), self.county_ids,))

      # end: if self.cli_opts.restrict_counties

      self.limit_clause_complete = ''
      if debug_prog_log.debug_break_loops:
         limit_ct = import_bucket_size * debug_prog_log.debug_break_loop_cnt
         self.limit_clause_complete = "LIMIT %d" % (limit_ct,)
         log.debug('mndot_import_prepare: %s'
                   % (self.limit_clause_complete,))

   # ***

   #
   def claim_revision_and_seq_ids(self):

      revision.Revision.revision_lock_dance(
         self.qb.db, caller='statewide_mndot_import')

      self.claim_next_revision()

      self.claim_sequence_ids()

      self.qb.db.transaction_finish(do_commit=(not debug_skip_commit))

      #log.debug("claim_revision_and_seq_ids: Released lock on 'revision'")

   #
   def claim_next_revision(self):

      # Peek at the next revision ID.
      self.qb.item_mgr.start_new_revision(self.qb.db)

      g.assurt(self.qb.item_mgr.rid_new)

      log.debug('claim_next_revision: new revision: %d'
                % (self.qb.item_mgr.rid_new,))

      group_ids = [self.public_group_id,]

      if not self.the_counties:
         changenote = 'Greater MN import'
      else:
         county_names = []
         for county_name in self.the_counties.values():
            county_names.append(' '.join([x.capitalize() for x
                                          in county_name.split(' ')]))
         county_list = ', '.join(county_names)
         ridx = county_list.rfind(', ')
         if ridx != -1:
            county_list = county_list[:ridx+1] + ' and ' + county_list[ridx+2:]
         changenote = (
            'Greater MN: %s count%s'
            % (county_list, 'y' if len(self.the_counties) == 1 else 'ies',))

      if self.cli_opts.line_segments_only:
         changenote += ' (line segments)'
      if self.cli_opts.link_values_only:
         changenote += ' (tags and attrs)'

      log.debug('claim_next_revision: rid_new: %d'
                % (self.qb.item_mgr.rid_new,))
      log.debug('claim_next_revision: changenote: "%s"'
                % (changenote,))

      Item_Manager.revision_save(
         self.qb,
         self.qb.item_mgr.rid_new,
         self.qb.branch_hier,
         'localhost',
         self.qb.username,
         changenote,
         group_ids,
         activate_alerts=False,
         processed_items=None,
         reverted_revs=None,
         skip_geometry_calc=True,
         skip_item_alerts=True)

      if not debug_skip_commit:
         Revision.revision_claim(self.qb.db, self.qb.item_mgr.rid_new)
      else:
         # Fake and use last revision or inserting into item_versioned will
         # fail because valid_start_rid doesn't exist otherwise.
         self.qb.item_mgr.rid_new -= 1

   #
   # This is like item_mgr.finalize_seq_vals(db): fiddle w/ the seq. values.
   def claim_sequence_ids(self):

      # Claim as many stack IDs and system IDs as we figure we'll need:
      # stack IDs for each line segment and each distanct node endpoint,
      # and system IDs for each line segment and one each for each
      # branch-node.

      # The input data has duplicates: same tis_directional ID and same
      # geometry. But where there are many rows in mndot_counties, there
      # are just one row in each of mndot_road_char, mndot_vol_aadt, and
      # mndot_vol_hcaadt. Forunately, it's just the objectid that's different.

      where_clause = ''
      if self.county_ids:
         where_clause = (
            "WHERE (lhs.cnty_code IN %s) AND (rhs.cnty_code IN %s)"
            % (self.county_ids_str_set,
               self.county_ids_str_set,))

      duplicate_pairs_sql = (
         """
         SELECT lhs.objectid AS lhs_objid,
                rhs.objectid AS rhs_objid
         FROM mndot_counties AS lhs
         JOIN mndot_counties AS rhs
            ON (lhs.tis_directional = rhs.tis_directional
                AND lhs.objectid < rhs.objectid
                AND lhs.geometry = rhs.geometry)
         %s
         """ % (where_clause,))

      time_0 = time.time()

      rows = self.qb.db.sql(duplicate_pairs_sql)

      misc.time_complain('duplicate_pairs_sql', time_0, 10.0, True)

      self.duplicate_oids = set()
      if rows:
         log.debug('Found %d duplicate mndot_counties rows' % (len(rows),))
         #log.debug('%s' % (rows,))
         for row in rows:
            self.duplicate_oids.add(row['rhs_objid'])
         if not self.where_clause_complete:
            self.where_clause_complete = "WHERE "
         else:
            self.where_clause_complete += " AND "
         self.where_clause_complete += (
            "(objectid NOT IN (%s))"
            % (','.join([str(x) for x in self.duplicate_oids]),))

      #

      self.fst_stack_id = debug_fst_stack_id
      if not self.fst_stack_id:
         # It's fine to peek when developing and debugging, but it requires
         # holding on to the revision table lock for a while -- so if we're
         # not too concerned that someone will otherwise edit the statewide
         # data in parallel while we update the database, we can work without
         # the revision lock.
         if self.qb.item_mgr.use_sequence_peeker:
            self.fst_stack_id = self.qb.db.sequence_peek_next(
                                    'item_stack_stack_id_seq')
      #
      self.fst_system_id = debug_fst_system_id
      if not self.fst_system_id:
         if self.qb.item_mgr.use_sequence_peeker:
            self.fst_system_id = self.qb.db.sequence_peek_next(
                                    'item_versioned_system_id_seq')
      log.debug('claim_sequence_ids: fst_stack_id: %s / fst_system_id: %s'
                % (self.fst_stack_id, self.fst_system_id,))

      #

      need_n_stack_ids, need_n_system_ids = self.count_new_byways_and_nodes()

      log.debug(
         'claim_sequence_ids: need_n_stack_ids: %d / need_n_system_ids: %d'
                % (need_n_stack_ids, need_n_system_ids,))

      #

      self.cur_stack_id = debug_cur_stack_id
      self.cur_system_id = debug_cur_system_id

      if self.qb.item_mgr.use_sequence_peeker:

         self.lst_stack_id = self.fst_stack_id + need_n_stack_ids - 1
         self.lst_system_id = self.fst_system_id + need_n_system_ids - 1
         log.debug('claim_sequence_ids: lst_stack_id: %s / lst_system_id: %s'
                   % (self.lst_stack_id, self.lst_system_id,))

         if (not self.cli_opts.link_values_only) and (not debug_skip_commit):
            self.qb.db.sequence_set_value('item_stack_stack_id_seq',
                                          self.lst_stack_id)
            self.qb.db.sequence_set_value('item_versioned_system_id_seq',
                                          self.lst_system_id)

         if not self.cur_stack_id:
            self.cur_stack_id = self.fst_stack_id

         if not self.cur_system_id:
            self.cur_system_id = self.fst_system_id

   # ***

   #
   def count_new_byways_and_nodes(self):

      self.n_new_byways = debug_n_new_byways
      if not self.n_new_byways:
         self.n_new_byways = self.count_new_items_byways()

      self.n_new_nodes = debug_n_new_nodes
      if not self.n_new_nodes:
         self.n_new_nodes = self.count_new_items_nodes()

      need_n_stack_ids = self.n_new_byways + self.n_new_nodes
      # Each node has separate entries for each branch.
      need_n_system_ids = (
         self.n_new_byways + (self.n_new_nodes * len(self.all_branch_ids)))

      log.debug('count_new_: no. new byways: %d / no. new nodes: %d'
                % (self.n_new_byways, self.n_new_nodes,))

      return need_n_stack_ids, need_n_system_ids

   #
   def count_new_items_byways(self):

      new_byway_count_sql = (
         """
         SELECT COUNT(*) FROM (
            SELECT *
            FROM mndot_counties
            %s
            ORDER BY cnty_code ASC, objectid ASC
            %s) AS foo
         """ % (self.where_clause_complete,
                self.limit_clause_complete,))

      rows = self.qb.db.sql(new_byway_count_sql)

      g.assurt(len(rows) == 1)
      n_new_byways = rows[0]['count']

      return n_new_byways

   #
   def count_new_items_nodes(self):

      # Get the total count of unique endpoints in new data.

      log.debug('count_new_items_nodes: counting distinct nodes...')

      mndot_endpoint_count_sql = (
         """
         SELECT COUNT(*) FROM (
            SELECT DISTINCT src_node_pt FROM (
               SELECT src_node_pt FROM (
                  SELECT mndot_counties.beg_node_pt AS src_node_pt
                     FROM mndot_counties
                     %s
                     ORDER BY cnty_code ASC, objectid ASC
                     %s) AS inner_foo
               UNION
               SELECT src_node_pt FROM (
                  SELECT mndot_counties.fin_node_pt AS src_node_pt
                     FROM mndot_counties
                     %s
                     ORDER BY cnty_code ASC, objectid ASC
                     %s) AS inner_bar
            ) AS foo
         ) AS bar
         """ % (self.where_clause_complete,
                self.limit_clause_complete,
                self.where_clause_complete,
                self.limit_clause_complete,))

      time_0 = time.time()

      rows = self.qb.db.sql(mndot_endpoint_count_sql)

      misc.time_complain('mndot_endpoint_count_sql', time_0, 10.0, True)

      g.assurt(len(rows) == 1)
      n_endpoints_mndot = rows[0]['count']

      # Get the total count of unique endpoints when combined.

      log.debug('count_new_items_nodes: counting distinct nodes...')

      __delete_me__ = (
         """

         SELECT COUNT(*) FROM (
            SELECT DISTINCT src_node_pt FROM (
               SELECT mndot_counties.beg_node_pt AS src_node_pt
                  FROM mndot_counties WHERE (cnty_code = 38)
               UNION
               SELECT mndot_counties.fin_node_pt AS src_node_pt
                  FROM mndot_counties WHERE (cnty_code = 38)
            ) AS foo
         ) AS bar
1340

         SELECT COUNT(beg_node_pt) AS src_node_pt
            FROM mndot_counties WHERE (cnty_code = 38)
1656; same for fin_node_pt
         SELECT DISTINCT(beg_node_pt) AS src_node_pt
            FROM mndot_counties WHERE (cnty_code = 38)
1122
         SELECT DISTINCT(fin_node_pt) AS src_node_pt
            FROM mndot_counties WHERE (cnty_code = 38)
1140


            SELECT COUNT(src_node_pt) FROM (
               SELECT mndot_counties.beg_node_pt AS src_node_pt
                  FROM mndot_counties WHERE (cnty_code = 38)
               UNION
               SELECT mndot_counties.fin_node_pt AS src_node_pt
                  FROM mndot_counties WHERE (cnty_code = 38)
            ) AS foo
1340...??? wrong! or because UNION eliminates duplicates?

127758
126418
         """)

      distinct_endpoint_count_sql = (
         """
         SELECT COUNT(*) FROM (
            SELECT DISTINCT src_node_pt FROM (
               SELECT src_node_pt FROM (
                  SELECT mndot_counties.beg_node_pt AS src_node_pt
                     FROM mndot_counties
                     %s
                     ORDER BY cnty_code ASC, objectid ASC
                     %s) AS inner_foo
               UNION
               SELECT src_node_pt FROM (
                  SELECT mndot_counties.fin_node_pt AS src_node_pt
                     FROM mndot_counties
                     %s
                     ORDER BY cnty_code ASC, objectid ASC
                     %s) AS inner_bar
               UNION
               SELECT node_endpt_xy.endpoint_xy AS src_node_pt
                  FROM node_endpt_xy
            ) AS foo
         ) AS bar
         """ % (self.where_clause_complete,
                self.limit_clause_complete,
                self.where_clause_complete,
                self.limit_clause_complete,))

      time_0 = time.time()

      rows = self.qb.db.sql(distinct_endpoint_count_sql)

      misc.time_complain('distinct_endpoint_count_sql', time_0, 10.0, True)

      g.assurt(len(rows) == 1)
      n_endpoints_finish = rows[0]['count']

      # Get the count of existing unique endpoints.

      existing_endpoint_count_sql = (
         """
         SELECT COUNT(*)
            FROM (
               SELECT DISTINCT(endpoint_xy)
               FROM node_endpt_xy
               ) AS foo
         """)

      time_0 = time.time()

      rows = self.qb.db.sql(existing_endpoint_count_sql)

      misc.time_complain('existing_endpoint_count_sql', time_0, 10.0, True)

      g.assurt(len(rows) == 1)
      n_endpoints_begin = rows[0]['count']

      # BUG nnnn: The count of distinct node_endpt_xy points is
      #           126418, but the raw count(*) (sans distinct) is
      #           126641. This is only okay if the reason is that
      #           the touching lines do not make an intersection,
      #           i.e., there's an underpass or overpass. But [lb]
      #           thinks things that don't intersect shouldn't
      #           share endpoint geometries... precision is a loosy
      #           1 decimeter, so just move one of the endpoints
      #           10 or more centimeters...
      #             SELECT COUNT(*) FROM node_endpt_xy;
      #            vs.
      #             SELECT COUNT(*) FROM (SELECT DISTINCT(endpoint_xy)
      #                                   FROM node_endpt_xy) AS foo;

      # Simple subtraction tells us how many new nodes we'll create.

      n_new_nodes = n_endpoints_finish - n_endpoints_begin

      log.debug('n_endpoints_finish: %d / n_endpoints_begin: %d'
                % (n_endpoints_finish, n_endpoints_begin,))

      return n_new_nodes

   # ***

   our_mndot_counties_cols = (
      'mndot_road_char_id',
      'ccp_conflict',
      'conflict_confidence',
      'ccp_stack_id',)

   #
   def import_tediously(self):

      tediously_time_0 = 0
      runtime_guess = 0

      counties_db = self.qb.db.clone()

      self.stats_prepare()

      (prog_log, prog_sql,) = self.get_prog_log()
      # The insert_bucket_size is fine for most of the bulk inserts,
      # but what we're doing here is a lot more time consuming.
      prog_log.log_freq = import_bucket_size
      prog_log.callee = 'import_tediously log'
      prog_log.info_print_speed_enable = True
      prog_log.info_print_speed_beging = 0
      prog_log.info_print_speed_during = 0
      prog_log.info_print_speed_finish = 1
      #
      prog_sql.log_freq = import_bucket_size
      prog_sql.callee = 'import_tediously sql'
      prog_sql.info_print_speed_enable = True
      prog_sql.info_print_speed_during = 1

      # Already done: self.qb.db.transaction_begin_rw()

      try:

         generator = None

         where_clause = ''
         if self.where_clause_complete:
            where_clause = self.where_clause_complete
            log.debug('import_tediously: %s' % (where_clause,))
         if debug_mndot_objectids:
            if not where_clause:
               where_clause = "WHERE "
            else:
               where_clause += " AND "
            where_clause += (
               "(mc.objectid IN (%s))"
               % (','.join([str(x) for x in debug_mndot_objectids]),))
            log.debug('import_tediously: %s' % (where_clause,))

         counties_sql = (
            """
            SELECT *,
               ST_Length(geometry) AS geom_len,
               ST_AsText(mc.beg_node_pt) AS beg_node_wkt,
               ST_AsText(mc.fin_node_pt) AS fin_node_wkt
               FROM mndot_counties AS mc
               %s
               ORDER BY mc.cnty_code ASC, mc.objectid ASC
               %s
            """ % (where_clause,
                   self.limit_clause_complete,))

         log.info('import_tediously: fetching mndot line segments...')

         counties_sql_time_0 = time.time()

         counties_db.dont_fetchall = True
         results = counties_db.sql(counties_sql)
         #results = counties_db.sql(mndot_lines_sql)
         g.assurt(results is None)

         misc.time_complain('counties_sql', counties_sql_time_0, 2.0, True)

         tediously_time_0 = time.time()

         n_line_segments = counties_db.rowcount()
         log.info('Starting rip on %d line segments...' % (n_line_segments,))
         prog_sql.loop_max = n_line_segments
         prog_log.loop_max = n_line_segments

         # MAGIC_NUMBER: Assuming ~2 ops per sec:
         #               [lb] observes runtime averages on production server
         #               of 1.8 to 2.1 line segments per second (if you bulk
         #               insert 10,000 rows at a time; at 1 row at a time,
         #               runtime averages fall in half).
         runtime_guess = float(n_line_segments) / 1.95
         runtime_fmtd, scale, units = misc.time_format_scaled(runtime_guess)
         error_fmtd, e_sc, e_un = misc.time_format_scaled(0.15 * runtime_guess)
         log.info('Expected runtime: %s, +/- %s' % (runtime_fmtd, error_fmtd,))

         self.mndot_line_ccp_insert_reset()
         self.endpoint_node_cache = {}
         self.new_endp_node_cache = {}
         for branch_id in self.all_branch_ids:
            self.endpoint_node_cache[branch_id] = {}
            self.new_endp_node_cache[branch_id] = {}
         self.new_node_stk_ids = set()
         self.new_node_pt_xys = set()
         if not self.cli_opts.line_segments_only:
            self.load_maybe_create_attrs_and_tags()

         generator = counties_db.get_row_iter()
         for row_county in generator:

            #log.debug('import_tediously: oid: %7d'
            #          % (row_county['objectid'],))

            row_road_char = None

            row_iter = None

            line_already_processed = True

            if not self.cli_opts.link_values_only:
               # First check the values that this script sets, to see if we've
               # processed this line segment previously.
               for our_col in Statewide_MnDOT_Import.our_mndot_counties_cols:
                  try:
                     if row_county[our_col]:
                        #log.warning('our col already set: %s: %s'
                        #            % (our_col, row_county[our_col],))
                        misc.dict_list_append(
                           self.mndot_lines_already_processed,
                           row_county['objectid'],
                           (our_col, row_county[our_col],))
                  except KeyError:
                     row_county[our_col] = None
               # Skip this line if we've already processed it.
               if row_county['ccp_stack_id'] or row_county['ccp_conflict']:
                  line_already_processed = True
                  self.num_mndot_lines_already_bywayed += 1
               else:
                  line_already_processed = False
                  # Load data from the three other MnDOT resources.
                  row_road_char = self.mndot_line_load_road_char(row_county)
                  row_aadt = self.mndot_line_load_vol_aadt(row_county)
                  row_hcaadt = self.mndot_line_load_vol_hcaadt(row_county)
                  # See if there's a matching Cyclopath byway.
                  self.mndot_line_find_ccp_match(row_county)
                  # Add a new byway and link_values for the MnDOT line.
                  row_iter = self.mndot_line_ccp_insert_new(
                     row_county, row_road_char, row_aadt, row_hcaadt)

            if not self.cli_opts.line_segments_only:
               if row_road_char is None:
                  row_road_char = self.mndot_line_fetch_road_char(row_county)
               self.mndot_attributes_ccp_consume(row_county, row_road_char,
                                                 line_already_processed,
                                                 row_iter)

            if prog_sql.loops_inc():
               self.mndot_line_ccp_insert_bulk()

            if prog_log.loops_inc():
               break

      finally:

         # We really only need the try/finally to avoid psycopg2 exception on
         # KeyboardInterrupt: "Cannot rollback when multiple cursors open."

         if generator is not None:
            generator.close()
            generator = None

         self.mndot_line_ccp_insert_bulk()

         counties_db.dont_fetchall = False
         #counties_db.curs_recycle()
         counties_db.close()

         prog_log.loops_fin()

      # end: try/finally

      #self.cli_args.close_query(do_commit=(not debug_skip_commit))
      self.qb.db.transaction_finish(do_commit=(not debug_skip_commit))

      self.stats_report()

      if tediously_time_0 and prog_sql.runtime_guess:
         # MAGIC_NUMBER: Complain when time is 1.2 times our guess.
         misc.time_complain('import_tediously', tediously_time_0,
                            prog_sql.runtime_guess * 1.2)
         tediously_delta = time.time() - tediously_time_0
         if prog_sql.runtime_guess < tediously_delta:
            prefix_with = ''
            guess_was = 'longer'
            off_by = tediously_delta - prog_sql.runtime_guess
         else:
            prefix_with = '-'
            guess_was = 'less time'
            off_by = prog_sql.runtime_guess - tediously_delta
         off_by /= tediously_delta
         off_by *= 100.0
         log.debug(
            '%s %s than expected: off by %s%.2f%% / actual: %s / guess: %s'
            % ('Byway import took', guess_was, prefix_with, off_by,
               misc.time_format_scaled(tediously_delta)[0],
               misc.time_format_scaled(prog_sql.runtime_guess)[0],))

   # ***

   # Some of these tags might be new...
   # These are used in mndot_attributes_link_values_update.
   tags_we_use = (
      'prohibited',
      'unpaved',
      'brick road',
      'graded road',
      'gravel road',
      'soil road',
      'high volume',
      'heavy commercial',)

   #
   def load_maybe_create_attrs_and_tags(self):

      # These attributes already exist... right?
      # If not, see the postgres fcn., cp_attribute_create().

      self.attr_lane_count = attribute.Many.get_system_attr(
                  self.qb, '/byway/lane_count')

      self.attr_shoulder_width = attribute.Many.get_system_attr(
                  self.qb, '/byway/shoulder_width')

      self.attr_cycle_facil = attribute.Many.get_system_attr(
                  self.qb, '/byway/cycle_facil')

      is_rows_to_insert = []
      iv_rows_to_insert = []
      ir_rows_to_insert = []
      at_rows_to_insert = []
      tg_rows_to_insert = []
      gia_rows_to_insert = []

      self.tag_lookup = {}
      for tag_name in Statewide_MnDOT_Import.tags_we_use:

         # Tags are in the base branch only and run from rid 1 to infinity, so
         # this search is super simple.
         select_sql = (
            """
            SELECT tag.stack_id
            FROM tag
            JOIN item_versioned AS iv
               USING (system_id)
            WHERE iv.name = '%s'
            """ % (tag_name,))

         rows = self.qb.db.sql(select_sql)

         if rows:

            g.assurt(len(rows) == 1)
            self.tag_lookup[tag_name] = rows[0]['stack_id']

            log.debug('Found tag: %-20s / %d'
                      % (tag_name, rows[0]['stack_id'],))

         else:

            tag_stk_id = self.qb.item_mgr.seq_id_steal_stack_id(self.qb.db)
            tag_sys_id = self.qb.item_mgr.seq_id_steal_system_id(self.qb.db)

            is_row_to_insert = (
               "(%d, '%s', %d, %d)"
               % (tag_stk_id,
                  self.qb.username,
                  Access_Style.pub_editor,
                  Access_Infer.pub_editor,
                  ))
            is_rows_to_insert.append(is_row_to_insert)
            #
            iv_row_to_insert = (
               "(%d, %d, %d, %d, %s, %s, '%s', %d, %d)"
               % (tag_sys_id,
                  self.qb.branch_hier[0][0],
                  tag_stk_id,
                  1,       # version
                  'FALSE', # deleted
                  'FALSE', # reverted
                  tag_name, # name
                  self.qb.item_mgr.rid_new, # valid_start_rid
                  conf.rid_inf, # 2000000000
                  ))
            iv_rows_to_insert.append(iv_row_to_insert)
            #
            ir_row_to_insert = (
                  "(%d, %d, %d, %d, %d, '%s', '%s'::INET, '%s', '%s', '%s')"
               % (tag_sys_id,
                  1, # acl_grouping
                  self.qb.branch_hier[0][0],
                  tag_stk_id,
                  1, # version
                  # via trigger: edited_date
                  self.qb.username, # edited_user
                  self.qb.remote_ip, # edited_addr
                  self.qb.remote_host, # edited_host
                  '', # edited_note
                  'mndot_import', # edited_what
                  ))
            ir_rows_to_insert.append(ir_row_to_insert)
            #
            at_row_to_insert = (
               "(%d, %d, %d, %d)"
               % (tag_sys_id,
                  self.qb.branch_hier[0][0],
                  tag_stk_id,
                  1, # version
                  ))
            at_rows_to_insert.append(at_row_to_insert)
            #
            tg_row_to_insert = (
               "(%d, %d, %d, %d)"
               % (tag_sys_id,
                  self.qb.branch_hier[0][0],
                  tag_stk_id,
                  1, # version
                  ))
            tg_rows_to_insert.append(tg_row_to_insert)
            #
            gia_row_to_insert = (
               """(%d, %d, %d, %d, %d,
                   %d, %d, %d, %s, %s,
                   %d, %d, %s, %s, '%s'
                  )"""
               % (
                  # Interpolations 1-5
                  self.public_group_id,
                  tag_sys_id,
                  self.qb.branch_hier[0][0],
                  tag_stk_id,
                  1, # version

                  # Interpolations 6-10
                  1, # acl_grouping
                  self.qb.item_mgr.rid_new, # valid_start_rid
                  conf.rid_inf, # valid_until_rid
                  'FALSE', # deleted
                  'FALSE', # reverted

                  # Interpolations 11-15
                  Access_Level.editor, # access_level_id
                  Item_Type.TAG, # item_type_id
                  "NULL", # link_lhs_type_id
                  "NULL", # link_rhs_type_id
                  tag_name, # name
                  ))
            gia_rows_to_insert.append(gia_row_to_insert)

            self.tag_lookup[tag_name] = tag_stk_id

            log.debug('New tag: %s / %d' % (tag_name, tag_stk_id,))

      if is_rows_to_insert:
         g.assurt(iv_rows_to_insert)
         g.assurt(ir_rows_to_insert)
         g.assurt(at_rows_to_insert)
         g.assurt(tg_rows_to_insert)
         g.assurt(gia_rows_to_insert)
         item_stack.Many.bulk_insert_rows(self.qb, is_rows_to_insert)
         item_versioned.Many.bulk_insert_rows(self.qb, iv_rows_to_insert)
         item_revisioned.Many.bulk_insert_rows(self.qb, ir_rows_to_insert)
         attachment.Many.bulk_insert_rows(self.qb, at_rows_to_insert)
         tag.Many.bulk_insert_rows(self.qb, tg_rows_to_insert)
         group_item_access.Many.bulk_insert_rows(self.qb, gia_rows_to_insert)

   #
   def mndot_line_load_road_char(self, row_county):

      the_row = self.find_matching_mndot(
         #row_county, 'tis_code', 'mndot_road_char', 'tis_id')
         row_county, 'tis_directional',
         'mndot_road_char', 'directional_tis_id')

      if the_row is not None:
         row_county['mndot_road_char_id'] = the_row['mndot_road_char_id']
      else:
         # There are some strays in the county data...
         # BUG nnnn/MAYBE: Should 'strays' be marked for manual inspection?
         #log.debug('missing entry: mndot_road_char: row: %s' % (row_county,))
         self.objectids_suspect['no_road_char'].append(row_county['objectid'])

      return the_row

   #
   def mndot_line_fetch_road_char(self, row_county):

      the_row = None

      if row_county['mndot_road_char_id']:
         road_char_sql = (
            """
            SELECT *, -1 AS st_hausdorffdistance FROM mndot_road_char
            WHERE mndot_road_char.mndot_road_char_id = %d
            """ % (row_county['mndot_road_char_id'],))
         rows = self.qb.db.sql(road_char_sql)
         g.assurt(len(rows) == 1)
         the_row = rows[0]
      else:
         self.objectids_suspect['no_road_char'].append(row_county['objectid'])

      return the_row

   #
   def mndot_line_load_vol_aadt(self, row_county):

      the_row = self.find_matching_mndot(
         row_county, 'tis_code', 'mndot_vol_aadt', 'route_ident')

      return the_row

   #
   def mndot_line_load_vol_hcaadt(self, row_county):

      the_row = self.find_matching_mndot(
         row_county, 'tis_code', 'mndot_vol_hcaadt', 'route_ident')

      return the_row

   # ***

   # WEIRD_WEIRD:
   #
   # ST_Intersects returns false on the raw geometry for line segments
   #  that are, like, one billionth off, but if we convert to text and
   #  then back to raw, it works... huh. E.g., this returns true:
   #
   #    SELECT ST_Intersects(
   #       ST_GeomFromText(
   #    'LINESTRING(473484.812000209 4842074,473904 4842071)'),
   #       ST_GeomFromText(
   #    'LINESTRING(473484.812000208 4842074,473904 4842071)'));
   #
   #  but this is false:
   #
   #    SELECT ST_Intersects(
   #     '0102000020236900000200000097FB7C3F33E61C41CFF001A0...'::GEOMETRY,
   #     '0102000020236900000200000086FB7C3F33E61C41CFF001A0...'::GEOMETRY);
   #
   # Note that [lb] tried ST_Simplify, too, but I couldn't get it to change
   # any lines I gave it.
   #
   #  E.g., these return the same thing:
   #   SELECT ST_AsText('...'::GEOMETRY);
   #   SELECT ST_AsText(ST_Simplify('...'::GEOMETRY, 0.01));
   #   SELECT ST_AsText(ST_Simplify('...'::GEOMETRY, 1));
   #   SELECT ST_AsText(ST_Simplify('...'::GEOMETRY, 100));
   #
   # So this doesn't work:
   #
   #   road_char_sql = (
   #      """
   #      SELECT * FROM mndot_road_char
   #         WHERE tis_id = '%s'
   #           AND ST_Intersects(geometry, '%s'::GEOMETRY)
   #      """ % (row_county['tis_code'], row_county['geometry'],))
   #
   # but it's best use the Hausdorff distance, because even simplifying
   # the line isn't very reliable.

   #
   def find_matching_mndot(self, row_county, tis_code_attr,
                                 table_name, column_name):

      the_row = None

      beg_fraction_sql = (
         "(SELECT ST_Line_Locate_Point(other.geometry, '%s'::GEOMETRY))"
         % (row_county['beg_node_pt'],))

      fin_fraction_sql = (
         "(SELECT ST_Line_Locate_Point(other.geometry, '%s'::GEOMETRY))"
         % (row_county['fin_node_pt'],))

      other_sql = (
         """
         SELECT
            *,
            CASE WHEN %s < %s THEN
               ST_HausdorffDistance(
                  '%s'::GEOMETRY, ST_Line_Substring(other.geometry, %s, %s))
            ELSE
               ST_HausdorffDistance(
                  '%s'::GEOMETRY, ST_Line_Substring(other.geometry, %s, %s))
            END AS st_hausdorffdistance
         FROM
            %s AS other
         WHERE
            other.%s = '%s'
         """ % (beg_fraction_sql,
                fin_fraction_sql,
                #
                row_county['geometry'],
                beg_fraction_sql,
                fin_fraction_sql,
                #
                row_county['geometry'],
                fin_fraction_sql,
                beg_fraction_sql,
                #
                table_name,
                column_name,
                #
                row_county[tis_code_attr],))

      other_rows = self.qb.db.sql(other_sql)

      best_hausdorff = -1
      second_best_hd = -1
      for row in other_rows:
         hausdorff_dist = row['st_hausdorffdistance']
         self.hausdorff_bucket_add(self.hausdorff_buckets[table_name],
                                   hausdorff_dist)
         if best_hausdorff < 0:
            best_hausdorff = hausdorff_dist
            the_row = row
         else:
            if hausdorff_dist < best_hausdorff:
               second_best_hd = best_hausdorff
               best_hausdorff = hausdorff_dist
               the_row = row
            elif second_best_hd < 0:
               second_best_hd = hausdorff_dist
            elif hausdorff_dist < second_best_hd:
               second_best_hd = hausdorff_dist
            # else, third_or_less_best

      if best_hausdorff > 0.1:
         # This can happen when the road_chars line is split somewhere between
         # the endpoints of the candidate, and if it's split near an endpoint
         # of the candidate, the longest shortest distance, or hausdorff dist,
         # will be from near one candidate endpoint to the other endpoint.
         if best_hausdorff > row_county['geom_len']:
            # _match_mndot: unexpected: 305.372452087 - 300.873529128
            #               = 4.49892295953 / oid: 18923 / len: 655.899477323
            #               This is because the county line is full length
            #               and there are two road_char lines, split right
            #               in the middle of the county line... silly.
            self.best_hausdorff_gt_geom_len.append(
               (best_hausdorff,
                row_county['objectid'],
                row_county['geom_len'],))

      hausdirff = 0
      if second_best_hd >= 0:
         hausdirff = second_best_hd - best_hausdorff
         if hausdirff < 10:
            self.ccp_match_not_so_confident.append(
               (second_best_hd, best_hausdorff, hausdirff,
                row_county['objectid'], row_county['geom_len'],))
         else:
            if False:
               log.debug(
                  '_match_mndot: hausdorff: best: %.7f / 2nd: %.7f / %d total'
                  % (best_hausdorff, second_best_hd, len(other_rows),))
      else:
         if False:
            log.debug('_match_mndot: one match: hausdorff: %.7f'
                      % (best_hausdorff,))

      return the_row

   # ***

   #
   def mndot_line_find_ccp_match(self, row_county):

      # MAGIC_NUMBER: What's a good tolerance?
      #               For now, trying 2 meter radius.
      radius_m = 2.0

# FIXME/IMPLEMENT/Bug nnnn: Fetch also
#   gf.geofeature_layer_id
# and compare against row_county's rte_syst when making your match
# decision, i.e., don't match freeway to simple road.

      nearby_byways_sql = (
         """
         SELECT
            gf.system_id,
            gf.stack_id,
            gf.version,
            gf.geometry,
            ST_Length(gf.geometry) AS geom_len,
            gf.geofeature_layer_id
         FROM
            geofeature AS gf
         JOIN
            item_versioned AS iv
               ON (iv.system_id = gf.system_id)
         WHERE
            ST_GeometryType(gf.geometry) = 'ST_LineString'
            AND gf.branch_id = %d
            AND iv.valid_until_rid = %d
            AND iv.deleted IS FALSE
            AND gf.geofeature_layer_id NOT IN (%s)
-- FIXME: This should use ST_DWithin, not ST_Buffer
            AND ST_Intersects(gf.geometry, ST_Buffer('%s'::GEOMETRY, 2.0))
         """ % (self.qb.branch_hier[0][0],
                conf.rid_inf,
               # Exclude Ccp bike trails, sidewalks; since MnDOT data is roads.
                ','.join([str(x) for x in
                          byway.Geofeature_Layer.non_motorized_gfids]),
                row_county['geometry'],))

      outer_rows = self.qb.db.sql(nearby_byways_sql)

      ccp_conflict_stack_id = None
      ccp_conflict_system_id = None

      best_hausdorff = -1
      second_best_hd = -1
      for row_ccp_gf in outer_rows:

         # All of the MnDOT lines are segmented, but not all of the Cyclopath
         # lines are. So snip the Cyclopath candidate according to the MnDOT
         # line.

         beg_fraction_sql = (
            "SELECT ST_Line_Locate_Point('%s'::GEOMETRY, '%s'::GEOMETRY)"
            % (row_ccp_gf['geometry'], row_county['beg_node_pt'],))
         fract_rows = self.qb.db.sql(beg_fraction_sql)
         beg_fraction = fract_rows[0]['st_line_locate_point']
         #
         fin_fraction_sql = (
            "SELECT ST_Line_Locate_Point('%s'::GEOMETRY, '%s'::GEOMETRY)"
            % (row_ccp_gf['geometry'], row_county['fin_node_pt'],))
         fract_rows = self.qb.db.sql(fin_fraction_sql)
         fin_fraction = fract_rows[0]['st_line_locate_point']
         #
         if beg_fraction > fin_fraction:
            tmp_fraction = beg_fraction
            beg_fraction = fin_fraction
            fin_fraction = tmp_fraction

         hausdorff_sql = (
            """
            SELECT
               ST_HausdorffDistance(
                  '%s'::GEOMETRY,
                  ST_Line_Substring('%s'::GEOMETRY, %f, %f))
            """ % (row_county['geometry'],
                   row_ccp_gf['geometry'],
                   beg_fraction,
                   fin_fraction,))

         hausrowss = self.qb.db.sql(hausdorff_sql)
         g.assurt(len(hausrowss) == 1)

         hausdorff_dist = hausrowss[0]['st_hausdorffdistance']

         self.hausdorff_bucket_add(self.ccp_hausdorff_bucket, hausdorff_dist)

         if False:
            log.debug(
               '%s: %6d%s / objid: %7d (len %.2f) / stk_id: %8d (len %.2f)'
               % ('_find_ccp_match: hausdorff',
                  int(hausdorff_dist),
                  str(hausdorff_dist - int(hausdorff_dist))[1:7]
                   if hausdorff_dist else 0.0,
                  row_county['objectid'], row_county['geom_len'],
                  row_ccp_gf['stack_id'], row_ccp_gf['geom_len'],))

         if best_hausdorff < 0:
            best_hausdorff = hausdorff_dist
            ccp_conflict_stack_id = row_ccp_gf['stack_id']
            ccp_conflict_system_id = row_ccp_gf['system_id']
         else:
            if hausdorff_dist < best_hausdorff:
               second_best_hd = best_hausdorff
               best_hausdorff = hausdorff_dist
               ccp_conflict_stack_id = row_ccp_gf['stack_id']
               ccp_conflict_system_id = row_ccp_gf['system_id']
            elif second_best_hd < 0:
               second_best_hd = hausdorff_dist
            elif hausdorff_dist < second_best_hd:
               second_best_hd = hausdorff_dist
            # else, third_or_less_best

      # end: for row_ccp_gf in outer_rows

      # MAGIC_NUMBER... what's our final tolerance? One meter?
      #                 or should we scale according to geometry length?
      # FIXME: A longer line with a lower hausdorff is more confident.
      #
      # FIXME: Use geofeature_layer_id to decide?
      #
      #
      if (best_hausdorff >= 0) and (best_hausdorff < 1.0):

         row_county['ccp_conflict'] = ccp_conflict_stack_id
         #? ccp_conflict_system_id

# FIXME: store multiple conflict IDs?? one column or many?

# FIXME: What about Confidence?
#            row_county['conflict_confidence'] = ???

      # end: for row_ccp_gf in outer_rows

      return

   #
   def mndot_line_ccp_insert_new(self, row_county, row_road_char,
                                       row_aadt, row_hcaadt):

      if row_county['ccp_conflict']:
         ccp_stack_id = row_county['ccp_conflict']
         ccp_system_id = None
      else:
         ccp_stack_id = self.get_new_stack_id()
         ccp_system_id = self.get_new_system_id()
         row_county['ccp_stack_id'] = ccp_stack_id

      beg_node_stack_id, beg_node_sys_id = (
         self.ccp_insert_new_node(row_county, row_road_char, row_aadt,
                                  row_hcaadt, ccp_stack_id,
                                  'beg_node_pt', 'beg_node_wkt'))
      fin_node_stack_id, fin_node_sys_id = (
         self.ccp_insert_new_node(row_county, row_road_char, row_aadt,
                                  row_hcaadt, ccp_stack_id,
                                  'fin_node_pt', 'fin_node_wkt'))

      byway_gfl_id, control_of_access = self.get_gflid_and_access(
                                          row_county, row_road_char)
      one_way_code = self.get_one_way_code(row_county, row_road_char)
      bridge_level_z = byway.One.z_level_med # z (just set to middle value)

      row_iter = Statewide_MnDOT_Import.Row_Iter()
      row_iter.row_county = row_county
      row_iter.row_road_char = row_road_char
      row_iter.row_aadt = row_aadt
      row_iter.row_hcaadt = row_hcaadt
      row_iter.ccp_stack_id = ccp_stack_id
      row_iter.ccp_system_id = ccp_system_id
      row_iter.beg_node_stack_id = beg_node_stack_id
      row_iter.fin_node_stack_id = fin_node_stack_id
      row_iter.byway_gfl_id = byway_gfl_id
      row_iter.control_of_access = control_of_access
      row_iter.one_way_code = one_way_code
      row_iter.bridge_level_z = bridge_level_z

      # If there's a Ccp conflict, we'll just update mndot_counties, but
      # we won't add a Cyclopath byway. Otherwise, make the new byway by
      # populating rows in all your favorite tables: item_stack,
      # item_versioned, geofeature, group_item_access, byway_rating, etc.
      if not row_county['ccp_conflict']:
         self.mndot_line_ccp_insert_geofeature_et_al(row_iter)

      # NOTE: Not writing aadt for child branches...
      # MAYBE: Add AADT for all the years, or just the latest?
      # MAYBE: Specify AADT year via self.cli_opts?
      #        These hard-coded values are buried pretty deep in this script...
      if row_aadt is not None:
         # MAGIC_NUMBER: 2012. The latest year of aadt data.
         # MAGIC_NUMBER: 'auto'mobile traffic, or all motor traffic.
         self.mndot_line_ccp_update_aadt(row_iter, row_aadt,
                                         'aadt_2012', 2012, 'auto')
      if row_hcaadt is not None:
         # MAGIC_NUMBER: 'heavy' commercial traffic, or just big trucks.
         self.mndot_line_ccp_update_aadt(row_iter, row_hcaadt,
                                         'hcaadt_2012', 2012, 'heavy')

      # Update the mndot_counties row.
      self.mndot_line_ccp_insert_update_row_county(row_county)

      # The big ugly all things mndot table.
      self.mndot_line_ccp_insert_update_byway_mndot(row_iter)

      return row_iter

   # ***

   #
   def get_new_stack_id(self):
      if self.qb.item_mgr.use_sequence_peeker:
         if self.cur_stack_id > self.lst_stack_id:
            log.warning('get_new_stack_id: out of stack IDs!')
            #g.assurt(False)
            import pdb;pdb.set_trace()
         stack_id = self.cur_stack_id
         self.cur_stack_id += 1
      else:
         stack_id = self.qb.db.sequence_get_next(
                        'item_stack_stack_id_seq')
      return stack_id

   #
   def get_new_system_id(self):
      if self.qb.item_mgr.use_sequence_peeker:
         if self.cur_system_id > self.lst_system_id:
            log.warning('get_new_system_id: out of system IDs!')
            #g.assurt(False)
            import pdb;pdb.set_trace()
         system_id = self.cur_system_id
         self.cur_system_id += 1
      else:
         system_id = self.qb.db.sequence_get_next(
                        'item_versioned_system_id_seq')
      return system_id

   # ***

   # FIXME: These mappings to geofeature layer are really just bad guesses...

   # "The Route System of the Route. Defined by the jurisdiction of the road."
   #
   # MAYBE: We might need more Geofeature_Layer types, or we could attr or tag
   #        the byway...
   mndot_route_system = {
      # Interstate
      1: byway.Geofeature_Layer.Expressway,
      # US Highway
      2: byway.Geofeature_Layer.Highway,
      # MN Highway
      3: byway.Geofeature_Layer.Highway,
      # County State Aid Highway
      # ARGH: There are a bunch of local roads in Two Harbors marked CSAH...
      #        also 7 and 10, County Road and Municipal Street.... hrmm...
      4: byway.Geofeature_Layer.Highway,
      # Municipal State Aid Street
      5: byway.Geofeature_Layer.Major_Road,
      # NOTE: No 6.
      # County Road
      7: byway.Geofeature_Layer.Local_Road,
      # Township Road
      8: byway.Geofeature_Layer.Local_Road,
      # Unincorporated Township Road
      9: byway.Geofeature_Layer.Local_Road,
      # Municipal Street
      10: byway.Geofeature_Layer.Local_Road,
   # ??? are these just local roads?
      # National Park Road
      11: byway.Geofeature_Layer.Local_Road,
      # National Forest Road
      12: byway.Geofeature_Layer.Local_Road,
      # Indian Service Road
      13: byway.Geofeature_Layer.Local_Road,
      # State Forest Road
      14: byway.Geofeature_Layer.Local_Road,
      # State Park Road
      15: byway.Geofeature_Layer.Local_Road,
      # Military Road
      16: byway.Geofeature_Layer.Local_Road,
      # National Monument Road
      17: byway.Geofeature_Layer.Local_Road,
      # National Wildlife Road
      18: byway.Geofeature_Layer.Local_Road,
      # Frontage Road
      # NOTE: No 19 in data.
      19: byway.Geofeature_Layer.Local_Road,
      # State Game Preserve Road
      20: byway.Geofeature_Layer.Local_Road,
      # NOTE: No. 21 not in metadata but is in data.
      #       [lb] poked around and most of these look like
      #            small roads without a road_characteristics match.
      21: byway.Geofeature_Layer.Local_Road,
      # Ramp
      22: byway.Geofeature_Layer.Expressway_Ramp,
      # Privately maintained road open to public use
      23:byway.Geofeature_Layer.Local_Road,
      }

   # SELECT DISTINCT(functional_classification_code),
   #    functional_classification
   #    FROM mndot_road_char ORDER BY functional_classification_code

   # This lookup uses the functional classification to map the route_system
   # code to a Cyclopath classification. This is because the input data isn't
   # perfect: for example, the route system code, "County State Aid Highway",
   # maps to municipal streets sometimes, and other times to actual highways.
   # So the route system does not directly map to the Cyclopath
   # classifications, and neither does the functional class, since, e.g.,
   # "Rural Major collector" is sometimes what Cyclopath would consider a
   # Major Road, and othertimes it's a "highway".
   mndot_functional_class = {
      # Rural Principal arterial - Interstate
      1: {byway.Geofeature_Layer.Expressway:
           byway.Geofeature_Layer.Expressway,},
      # Rural Principal arterial - Other
      2: {
          byway.Geofeature_Layer.Highway:
           byway.Geofeature_Layer.Highway,
          byway.Geofeature_Layer.Major_Road:
           byway.Geofeature_Layer.Major_Road,},
      # Rural Minor arterial
      6: {
          byway.Geofeature_Layer.Highway:
           byway.Geofeature_Layer.Highway,
          byway.Geofeature_Layer.Major_Road:
           byway.Geofeature_Layer.Major_Road,
          # Also maps from County Road, Township Road
          byway.Geofeature_Layer.Local_Road:
           byway.Geofeature_Layer.Local_Road,
          },
      # Rural Major collector
      7: {
          # Highway 61...
          byway.Geofeature_Layer.Highway:
           byway.Geofeature_Layer.Highway,
          # Also, Cramer Rd, a forest road in Soup Nat.
          byway.Geofeature_Layer.Local_Road:
           byway.Geofeature_Layer.Major_Road,
          # And might as well include the in-between.
          byway.Geofeature_Layer.Major_Road:
           byway.Geofeature_Layer.Major_Road,
          # The problem is the meaning of "collector road" in
          # a rural vs. urban area, in terms of traffic volume,
          # and to a lesser extent perhaps, driving speed.
          },
      # Rural Minor collector
      8: {byway.Geofeature_Layer.Local_Road:
           byway.Geofeature_Layer.Local_Road,
          # E.g., local roads in Two Harbors w/ rte sys CSAH.
          byway.Geofeature_Layer.Highway:
           byway.Geofeature_Layer.Major_Road,},
      # Rural Local
      9: {byway.Geofeature_Layer.Local_Road:
           byway.Geofeature_Layer.Local_Road,
          # E.g., local roads in Two Harbors w/ rte sys CSAH.
          byway.Geofeature_Layer.Highway:
           byway.Geofeature_Layer.Major_Road,},
      # Urban Principal arterial - Interstate
      11: {byway.Geofeature_Layer.Expressway:
            byway.Geofeature_Layer.Expressway,},
      # Urban Principal arterial - Other freeways or expressways
      # This depends on control_of_access_code
      #12: {byway.Geofeature_Layer.Expressway:
      #      byway.Geofeature_Layer.Expressway,},
      12: {byway.Geofeature_Layer.Highway:
            byway.Geofeature_Layer.Highway,},
      # Urban Other Principal Arterials
      14: {byway.Geofeature_Layer.Major_Road:
            byway.Geofeature_Layer.Major_Road,
           # Also, rte syst County State Aid Highway
           byway.Geofeature_Layer.Highway:
            byway.Geofeature_Layer.Highway,},
      # Urban Minor arterial
      16: {byway.Geofeature_Layer.Major_Road:
            byway.Geofeature_Layer.Major_Road,
           # Also, rte syst County State Aid Highway
           byway.Geofeature_Layer.Highway:
            byway.Geofeature_Layer.Highway,
           # And Municipal Street...
           byway.Geofeature_Layer.Local_Road:
            byway.Geofeature_Layer.Local_Road,
           },
      # Urban Collector
      # Pairs w/ Rte Syst: Municipal State Aid Street
      17: {byway.Geofeature_Layer.Local_Road:
            byway.Geofeature_Layer.Local_Road,
           byway.Geofeature_Layer.Major_Road:
            byway.Geofeature_Layer.Major_Road,
           # Also, CSAH.
           byway.Geofeature_Layer.Highway:
            byway.Geofeature_Layer.Major_Road,},
      # Urban Local
      # Pairs w/ Rte Syst: Municipal State Aid Street
      19: {byway.Geofeature_Layer.Local_Road:
            byway.Geofeature_Layer.Local_Road,
           byway.Geofeature_Layer.Major_Road:
            byway.Geofeature_Layer.Major_Road,
           # Hrm... MN Highway, too. Or at least roadways crossing highways in
           # Brainerd. Also, County State Aid Highway.
           byway.Geofeature_Layer.Highway:
            byway.Geofeature_Layer.Highway,
           },
      }

   # SELECT DISTINCT(control_of_access_code), control_of_access
   #    FROM mndot_road_char ORDER BY control_of_access_code;
   #                   1 | No control of access
   #                   2 | Partial control of access
   #                   3 | Full control of access
   CTL_OF_ACC_NONE = 1
   CTL_OF_ACC_PARTIAL = 2
   CTL_OF_ACC_FULL = 3

   #
   def get_gflid_and_access(self, row_county, row_road_char):

      byway_gfl_id_1 = Statewide_MnDOT_Import.mndot_route_system[
                                          row_county['rte_syst']]

      if row_road_char is not None:

         byway_gfl_id_2 = Statewide_MnDOT_Import.mndot_route_system[
                                 row_road_char['route_system_code']]

         if byway_gfl_id_1 != byway_gfl_id_2:
            # There are some mndot_counties lines marked Muni State Aid Streets
            # which we consider a Major Road, where the mndot_road_char says
            # just Municipal Street.
            #if ((byway_gfl_id_1 != byway.Geofeature_Layer.Major_Road)
            #    and ()):
            # MAGIC_NUMBERS: See Statewide_MnDOT_Import.mndot_route_system.
            if ((row_county['rte_syst'] != 5)
                and (row_road_char['route_system_code'] != 10)):
               log.warning(
                  '%s / %s / %s'
                  % ('get_gfl_id: different: rte_syst',
                     'counties: %2s (gfl: %2d) (oid: %7s)'
                     % (row_county['rte_syst'],
                        byway_gfl_id_1,
                        row_county['objectid'],),
                     'road_char: %2s (gfl: %2d) (oid: %7s)'
                     % (row_road_char['route_system_code'],
                        byway_gfl_id_2,
                        row_road_char['objectid'],),))

         fcntal_to_rtesyst = Statewide_MnDOT_Import.mndot_functional_class[
                           row_road_char['functional_classification_code']]

         try:
            # This corrects, e.g., CSAH when it's not a highway but just a
            # major road.
            byway_gfl_id_1 = fcntal_to_rtesyst[byway_gfl_id_1]
         except KeyError:
            log.warning(
               '%s / %s / %s'
               % ('get_gfl_id: differs',
                  'counties: rte_syst: %2s (gfl: %2d) (oid: %7s)'
                  % (row_county['rte_syst'],
                     byway_gfl_id_1,
                     row_county['objectid'],),
                  'road_char: funct_class: %2s (oid: %7s)'
                  % (row_road_char['functional_classification_code'],
                     row_road_char['objectid'],),))

      # Assume no control of access unless explicitly set.

      control_of_access = Statewide_MnDOT_Import.CTL_OF_ACC_NONE

      if row_road_char is not None:

         control_of_access = row_road_char['control_of_access_code']

         warning = ''
         if byway_gfl_id_1 in (byway.Geofeature_Layer.Expressway,
                               byway.Geofeature_Layer.Expressway_Ramp,):
            if control_of_access != Statewide_MnDOT_Import.CTL_OF_ACC_FULL:
               warning = 'Expected control: full: expressway/ramp'
         #elif byway_gfl_id_1 in (byway.Geofeature_Layer.Highway,):
         #   # Not true: Hwy 61 North of Two Harbors, where it's a two lane,
         #   # has no control of access, but the divided 61 between Duluth and
         #   # Two Harbors has partial control of access. You can bike on 61
         #   # there, but there are no driveways, cross traffic has to stop
         #   # before each couplet, and sometimes there are acceleration and
         #   # deceleration lanes.
         #   #if (control_of_access
         #   #    != Statewide_MnDOT_Import.CTL_OF_ACC_PARTIAL):
         #   #   warning = 'Expected control: partial: highway'
         #   # Some highways in the city are full control of access...
         #   #if control_of_access == Statewide_MnDOT_Import.CTL_OF_ACC_FULL:
         #   #   warning = 'Unexpected control: full: highway'
         #   pass
         #else:
         elif byway_gfl_id_1 not in (byway.Geofeature_Layer.Highway,):
            if control_of_access == Statewide_MnDOT_Import.CTL_OF_ACC_FULL:
               warning = 'Expected control: none or partial: not-hway/xprssway'
         if warning:
            log.warning(
               '%s / oid: %7d / ctl o acc: %d / gfl: %d / rte: %d / fun: %d'
               % (warning,
                  row_county['objectid'],
                  control_of_access,
                  byway_gfl_id_1,
                  row_county['rte_syst'],
                  row_road_char['functional_classification_code']))

      return byway_gfl_id_1, control_of_access

   # MAGIC_NUMBER: Per
   #  http://www.dot.state.mn.us/maps/gdma/data/metadata/road_metadata.html
   # this is the definition of traffic_direction, which has three values:
   # 'B': "The traffic flows both directions."
   # 'I': "The traffic flows towards the direction of increasing mileage only."
   # 'D': "The traffic flows towards the direction of decreasing mileage only."
   # In the MnDOT data, there are:
   #   'B':  409158
   #   'I':  20871
   #   'D':  13587
   #   '' :  There's one of these in the state data,
   #         and it's an off ramp in the dir. of the line...
   TRAFFIC_FLOW_BOTH = 'B'
   TRAFFIC_FLOW_IDIR = 'I'
   TRAFFIC_FLOW_DDIR = 'D'

   # SELECT DISTINCT(divided_oneway), divided_oneway_code
   # FROM mndot_road_char ORDER BY divided_oneway_code;
   #
   #                  divided_oneway                  | divided_oneway_code 
   # -------------------------------------------------+---------------------
   #  Undivided 2-way roadway                                           | T
   #  Divided roadway or One-way couplet                                | M
   #  1-way roadway carrying traffic towards decreasing reference posts | F
   #  1-way roadway carrying traffic towards increasing reference posts | R

   # For freeways in the source data, you'll find two multilines that each
   # have both directions' geometries, and one multiline will be TIS1234-I
   # and the other will be TIS1234-D, for example, and the divided roadway
   # value is 'M', because each line segment is part of a one-way couplet.
   # THe 'F' and 'R' values are more likely used on one-ways in a city,
   # e.g., 3rd St and 4th St in downtown Minneapolis might technically
   # also be a one-way couplet, they're not a freeway couplet, so they're
   # marked as just normal one ways and use 'F' or 'R', where TIS IDs like
   # 1234567-I correspond to 'F', and those like 1234567-D correspond to 'R'.
   # Which actually seems backwards! Argh, weird, anyway, [lb] thinks
   # divided_oneway is wrong, and the description of 'F' and 'R' are backwards.
   #
   DIV1WAY_TWO_WAY_UNDIVIDED = 'T'
   DIV1WAY_DIVIDED_ROADWAY_OR_COUPLET = 'M'
   DIV1WAY_ONE_WAY_TOWARD_DECREASING = 'F'
   DIV1WAY_ONE_WAY_TOWARD_INCREASING = 'R'

   #
   def get_one_way_code(self, row_county, row_road_char):

      # MAGIC_NUMBER
      # In Cyclopath, one_way=0 is both directions,
      #               one_way=1 is in the direction of the line segment,
      #               and one_way=-1 is the reverse direction.

      traffic_dir = row_county['traffic_direction']

      if traffic_dir == Statewide_MnDOT_Import.TRAFFIC_FLOW_BOTH: # 'B'
         one_way_code = 0
      elif traffic_dir == Statewide_MnDOT_Import.TRAFFIC_FLOW_IDIR: # 'I'
         if row_county['begm'] < row_county['endm']:
            one_way_code = 1
         elif row_county['begm'] > row_county['endm']:
            one_way_code = -1
         else:
            # There's a funny loop-d-loop in the data in the iron range
            # (in Saint Louis county): a west-bound road clover-leafs under
            # itself, but there's a node where the clover leaf starts, and
            # where it ends, so it looks like a ring, but it's not, it's just
            # underpassing itself.
            #
            # ... so this might be wrong, but just assume increasing mileage.
            one_way_code = 1
            log.warning('weirdo loop-d-loop: begm == endm: objectid: %d'
                        % (row_county['objectid'],))
      elif traffic_dir == Statewide_MnDOT_Import.TRAFFIC_FLOW_DDIR: # 'D'
         if row_county['begm'] < row_county['endm']:
            one_way_code = -1
         else:
            g.assurt(row_county['begm'] > row_county['endm'])
            one_way_code = 1
      elif traffic_dir == '':
         #   '' :  There's one of these in the state data,
         #         and it's an off ramp in the dir. of the line...
         one_way_code = 1
         log.warning('no traffic_direction: row_county: %s' % (row_county,))
      else:
         g.assurt(False)

      #

      if row_road_char is not None:

         div1way_code = row_road_char['divided_oneway_code']

         if one_way_code == 0:
            expect = (Statewide_MnDOT_Import.DIV1WAY_TWO_WAY_UNDIVIDED,)
         elif one_way_code == -1:
            # NOTE: Using 'increasing' since logic is backwards?
            expect = (
               Statewide_MnDOT_Import.DIV1WAY_ONE_WAY_TOWARD_INCREASING,
               Statewide_MnDOT_Import.DIV1WAY_DIVIDED_ROADWAY_OR_COUPLET,)
         elif one_way_code == 1:
            # NOTE: Using 'decreasing' since logic is backwards?
            expect = (
               Statewide_MnDOT_Import.DIV1WAY_ONE_WAY_TOWARD_DECREASING,
               Statewide_MnDOT_Import.DIV1WAY_DIVIDED_ROADWAY_OR_COUPLET,)
         else:
            g.assurt(False)

         if div1way_code not in expect:
            # There's a cute parkway in Two Harbors that's a divided roadway
            # between 11th St and 15th St, and row_county says 'M', for divided
            # roadway or couplet, but row_road_char divided_oneway says
            # undivided 2-way roadway. So, er, false positive warning. But at
            # least the row_county data is the correct data, so we don't have
            # to consume the row_road_char data.
            self.divided_oneway_different.append(
               (row_county['objectid'],
                row_county['tis_directional'],
                one_way_code,
                div1way_code,))

      # We probably don't care about direction_travel_on_segment: the one_way
      # is good enough to figure it out.
      #
      # SELECT DISTINCT(direction_travel_on_segment),dir_travel_on_segment_code
      # FROM mndot_road_char ORDER BY dir_travel_on_segment_code;
      #
      # direction_travel_on_segment | dir_travel_on_segment_code 
      #-----------------------------+----------------------------
      # EASTBOUND                   | EB
      # EASTBOUND+WESTBOUND         | EB+WB
      # NORTHBOUND                  | NB
      # NORTHBOUND+SOUTHBOUND       | NB+SB
      # SOUTHBOUND                  | SB
      # SOUTHBOUND+NORTHBOUND       | SB+NB
      # WESTBOUND                   | WB
      # WESTBOUND+EASTBOUND         | WB+EB

      return one_way_code

   # ***

   #
   def ccp_insert_new_node(self, row_county, row_road_char,
                                 row_aadt, row_hcaadt, ccp_stack_id,
                                 which_endpoint, endpoint_wkt):

      node_pt_xy = geometry.wkt_point_to_xy(row_county[endpoint_wkt],
                                            precision=None)

      for branch_id in self.all_branch_ids:
         self.ccp_insert_new_node_branch(
            row_county, row_road_char, row_aadt, row_hcaadt,
            ccp_stack_id, which_endpoint, endpoint_wkt,
            node_pt_xy, branch_id)

      try:
         tup = self.new_endp_node_cache[self.qb.branch_hier[0][0]][node_pt_xy]
      except KeyError:
         tup = self.endpoint_node_cache[self.qb.branch_hier[0][0]][node_pt_xy]

      return tup

   #
   def ccp_insert_new_node_branch(self,
         row_county, row_road_char, row_aadt, row_hcaadt, ccp_stack_id,
         which_endpoint, endpoint_wkt, node_pt_xy, branch_id):

      node_stack_id = None
      node_system_id = None
      found_match = False
      try:
         # See if there's a node for this branch.
         node_stack_id, node_system_id = (
            self.endpoint_node_cache[branch_id][node_pt_xy])
         found_match = True
      except KeyError:
         try:
            # See if there's a new node for the basemap and use its stack_id.
            if branch_id != self.qb.branch_hier[0][0]:
               node_stack_id, node_system_id = (
                  # No: self.endpoint_node_cache
                  self.new_endp_node_cache[self.qb.branch_hier[0][0]][
                                                         node_pt_xy])
               # No: node_stack_id = self.get_new_stack_id()
               node_system_id = self.get_new_system_id()
               found_match = False
               self.endpoint_node_cache[branch_id][node_pt_xy] = (
                                    node_stack_id, node_system_id,)
               self.new_endp_node_cache[branch_id][node_pt_xy] = (
                                    node_stack_id, node_system_id,)
               #self.new_node_stk_ids.add(node_stack_id)
         except KeyError:
            pass

      if node_stack_id is None:
         ne_sql = (
            """
            SELECT
               ne.system_id,
               ne.branch_id,
               ne.stack_id,
               ne.version,
               ne.reference_n
            FROM node_endpt_xy AS nexy
            LEFT OUTER JOIN node_endpoint AS ne
               ON (ne.stack_id = nexy.node_stack_id)
            WHERE nexy.endpoint_xy = '%s'::GEOMETRY
              AND ne.branch_id = %d
            ORDER BY nexy.node_stack_id, ne.branch_id ASC
            """ % (row_county[which_endpoint],
                   branch_id,))
         rows = self.qb.db.sql(ne_sql)

         if rows:
            node_ref_n = None
            n_branch_rows = 0
            for row in rows:
               g.assurt(row['stack_id'])
               g.assurt(row['system_id'])
               # Not true: g.assurt(row['version'] == 1)
               if ((node_ref_n is None)
                   or ((row['branch_id'] == branch_id)
                       and (row['reference_n'] > node_ref_n))):
                  node_stack_id = row['stack_id']
                  if row['branch_id'] == branch_id:
                     node_system_id = row['system_id']
                  node_ref_n = row['reference_n']
               if row['branch_id'] == branch_id:
                  n_branch_rows += 1
            if n_branch_rows > 1:
               self.same_nodes_with_multiple_intersections.append(
                  (node_stack_id, rows,))
            if node_system_id is None:
               # We found a node, but in a different branch.
               node_system_id = self.get_new_system_id()
            found_match = True
            self.endpoint_node_cache[branch_id][node_pt_xy] = (
                                  node_stack_id, node_system_id,)
            # No: self.new_endp_node_cache[branch_id][node_pt_xy] = (
            #                          node_stack_id, node_system_id,)
            # No: self.new_node_stk_ids.add(node_stack_id)

      if node_stack_id is None:
         # Get a new node stack ID.
         node_stack_id = self.get_new_stack_id()
         node_system_id = self.get_new_system_id()
         found_match = False
         self.endpoint_node_cache[branch_id][node_pt_xy] = (node_stack_id,
                                                            node_system_id,)
         self.new_endp_node_cache[branch_id][node_pt_xy] = (node_stack_id,
                                                            node_system_id,)
         self.new_node_stk_ids.add(node_stack_id)
         self.new_node_pt_xys.add(node_pt_xy)

      if not found_match:

         # Skipping: self.is_rows_to_insert (no item_stack rows for nodes)

         iv_row_to_insert = (
            "(%d, %d, %d, %d, %s, %s, '%s', %d, %d)"
            % (node_system_id,
               branch_id,
               node_stack_id,
               1,       # version
               'FALSE', # deleted
               'FALSE', # reverted
               '',      # name
               1,       # valid_start_rid
               conf.rid_inf, # 2000000000
               ))
         self.iv_rows_to_insert.append(iv_row_to_insert)
         #log.debug('ccp_insert_new_node_branch: oid: %7d / iv: %s'
         #          % (row_county['objectid'], iv_row_to_insert,))

         if branch_id == self.qb.branch_hier[0][0]:
            nexy_row_to_insert = (
               "(%d, '%s'::GEOMETRY)"
               % (node_stack_id, row_county[which_endpoint],))
            self.nexy_rows_to_insert.append(nexy_row_to_insert)

         #elev_time_0 = time.time()
         #elevation_m = node_endpoint.Many.elevation_get_for_pt(node_pt_xy)
         #misc.time_complain('elevation_get_for_pt', elev_time_0, 0.01, True)
         elevation_m = 0.0

         ne_row_to_insert = (
            "(%d, %d, %d, %d, %d, %f)"
            % (node_system_id,
               branch_id,
               node_stack_id,
               1, # version
               #
               # Call node_cache_maker.py to set these:
               1, # reference_n: this might be a lie...
               #referencers,
               elevation_m, # required (NOT NULL)
               #
               # These'll get used by a yet-to-be-built flashclient feature:
               #dangle_okay,
               #a_duex_rues,
               ))
         self.ne_rows_to_insert.append(ne_row_to_insert)

         # Skipping: node_attribute table (with node_id and elevation_meters);
         #           the table is deprecated.

      # Skipping: node_bway; just let node_cache_maker.py deal with it...
      #   nb_row_to_insert = (
      #      "(%d, %d, %d, '%s'::GEOMETY)"
      #      % (branch_id,
      #         node_stack_id,
      #         ccp_stack_id,
      #         row_county[which_endpoint],))
      #   self.nb_rows_to_insert.append(nb_row_to_insert)

      # Skipping: item_versioned (no need to UPDATE name).

   # ***

   #
   def mndot_line_ccp_insert_geofeature_et_al(self, row_iter):

      is_row_to_insert = (
         "(%d, '%s', %d, %d)"
         % (row_iter.ccp_stack_id,
            self.qb.username,
            Access_Style.pub_editor,
            Access_Infer.pub_editor,
            ))
      self.is_rows_to_insert.append(is_row_to_insert)

      iv_row_to_insert = (
         "(%d, %d, %d, %d, %s, %s, %s, %d, %d)"
         % (row_iter.ccp_system_id,
            self.qb.branch_hier[0][0],
            row_iter.ccp_stack_id,
            1,       # version
            'FALSE', # deleted
            'FALSE', # reverted
            self.qb.db.quoted(row_iter.row_county['str_name']), # name
            self.qb.item_mgr.rid_new, # valid_start_rid
            conf.rid_inf, # 2000000000
            ))
      self.iv_rows_to_insert.append(iv_row_to_insert)
      #log.debug('mndot_line_ccp_insert_geofeature_et_al: oid: %7d / iv: %s'
      #          % (row_iter.row_county['objectid'], iv_row_to_insert,))

2014.05.21: Bitrot: Added item_revisionless table:
   Missing self.ir_rows_to_insert.append

      gf_row_to_insert = (
         "(%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, '%s'::GEOMETRY)"
         % (row_iter.ccp_system_id,
            self.qb.branch_hier[0][0],
            row_iter.ccp_stack_id,
            1,       # version
            row_iter.byway_gfl_id, # geofeature_layer_id
            row_iter.control_of_access,
            row_iter.bridge_level_z, # z
            row_iter.one_way_code,
            row_iter.beg_node_stack_id,
            row_iter.fin_node_stack_id,
            # split_from_stack_id,
            row_iter.row_county['geometry'],
            ))
      self.gf_rows_to_insert.append(gf_row_to_insert)

      gia_row_to_insert = (
         """(%d, %d, %d, %d, %d,
             %d, %d, %d, %s, %s,
             %d, %d, %s, %s, %s
             )"""
         % (
            # Interpolations 1-5
            self.public_group_id,
            row_iter.ccp_system_id,
            self.qb.branch_hier[0][0],
            row_iter.ccp_stack_id,
            1, # version

            # Interpolations 6-10
            1, # acl_grouping
            self.qb.item_mgr.rid_new, # valid_start_rid
            conf.rid_inf, # valid_until_rid
            'FALSE', # deleted
            'FALSE', # reverted

            # Interpolations 11-15
            Access_Level.editor, # access_level_id
            Item_Type.BYWAY, # item_type_id
            "NULL", # link_lhs_type_id
            "NULL", # link_rhs_type_id
            self.qb.db.quoted(row_iter.row_county['str_name']), # name
            ))
      self.gia_rows_to_insert.append(gia_row_to_insert)

      for branch_id in self.all_branch_ids:
         # 'br' stands for 'byway rating'.
         # NOTE: We'll fix the rating(s) later, when we go through
         #       attributes, or afterwards, when you run the br script,
         #       byway_ratings_populate.py.
         for rater_username in conf.rater_usernames:
            br_row_to_insert = (
               "(%d, %d, '%s', %d)"
               % (branch_id,
                  row_iter.ccp_stack_id,
                  rater_username,
                  2.5, # MAGIC_NUMBER: a '2.5' rating is in the middle.
                  ))
            self.br_rows_to_insert.append(br_row_to_insert)

   # ***

   #
   def mndot_line_ccp_update_aadt(self, row_iter,
                                        row_aadt_or_hcaadt,
                                        aadt_colname,
                                        aadt_year, aadt_type):

      # If row_counties['ccp_conflict'], we may have written the aadt
      # before, so try UPDATEing first. Otherwise, row['ccp_stack_id']
      # is a new stack ID and those rows will get bulk INSERTed.
      if row_aadt_or_hcaadt[aadt_colname] > 0:
         #
         update_sql = (
            """
            UPDATE aadt SET aadt = %d
            WHERE byway_stack_id = %d
              AND branch_id = %d
              AND aadt_year = %d
              AND aadt_type = '%s'
            """ % (row_aadt_or_hcaadt[aadt_colname],
                   row_iter.ccp_stack_id,
                   self.qb.branch_hier[0][0],
                   aadt_year,
                   aadt_type,))
         #
         rows = self.qb.db.sql(update_sql)
         if not self.qb.db.rowcount():
            # The aadt is -1 when there's no value, so just ignore it.
            if row_aadt_or_hcaadt[aadt_colname] >= 0:
               if row_iter.ccp_stack_id not in self.aadt_ccp_stack_ids:
                  new_aadt_row = (
                     "(%d, %d, %d, %d, '%s')"
                     % (self.qb.branch_hier[0][0],
                        row_iter.ccp_stack_id,
                        row_aadt_or_hcaadt[aadt_colname], # aadt
                        aadt_year,
                        aadt_type,
                        ))
                  #log.debug('mndot_line_ccp_update_aadt: %s'
                  #          % (new_aadt_row,))
                  self.aadt_rows_to_insert.append(new_aadt_row)
                  # So that we don't insert a duplicate row.
                  self.aadt_ccp_stack_ids.add(row_iter.ccp_stack_id)
         else:
            # Updated existing row.
            g.assurt(self.qb.db.rowcount() == 1)

   # ***

   #
   def mndot_line_ccp_insert_update_row_county(self, row_county):

      update_cols = []
      # See also: Statewide_MnDOT_Import.our_mndot_counties_cols
      if row_county['mndot_road_char_id']:
         uc = "mndot_road_char_id = %d" % (row_county['mndot_road_char_id'],)
         update_cols.append(uc)
      if row_county['ccp_conflict']:
         uc = "ccp_conflict = %d" % (row_county['ccp_conflict'],)
         update_cols.append(uc)
      if row_county['conflict_confidence']:
         uc = "conflict_confidence = %d" % (row_county['conflict_confidence'],)
         update_cols.append(uc)
      if row_county['ccp_stack_id']:
         uc = "ccp_stack_id = %d" % (row_county['ccp_stack_id'],)
         update_cols.append(uc)
      if update_cols:
         update_sql = (
            """
            UPDATE mndot_counties
            SET %s
            WHERE mndot_counties_id = %d
            """ % (','.join(update_cols),
                   row_county['mndot_counties_id'],))
         #
         rows = self.qb.db.sql(update_sql)
         g.assurt(rows is None)
         g.assurt(self.qb.db.rowcount() == 1)

   # ***

   #
   def mndot_line_ccp_insert_update_byway_mndot(self, row_iter):

      # NOTE: I think this is deletable, and table_bulk_insert_byway_mndot
      #       is deletable, etc., because we can just join the mndot tables,
      #       i.e., this table is redundant if we just need the data to make
      #       link_values... which we should just do that.
      #
      if False:
         # FIXME/DELETE_THIS_MAYBE: The byway_mndot table has INTs for all
         # the columns but the mndot data is mostly TEXT codes...
         by_row_to_insert = (
            """
            (%d, %d, %d, %d, %d,
             %d, %d, '%s', %s, %s,
             ?, ?, %d, %d, %d,
             '%s', %d)
            """
            % (# 1-5:
               row_iter.ccp_stack_id,
               self.qb.branch_hier[0][0],
               #system_id
               #version
               row_iter.bridge_level_z,
               row_iter.one_way_code,
               row_iter.beg_node_stack_id,
               # 6-10:
               row_iter.fin_node_stack_id,
               #split_from_stack_id
               row_iter.row_road_char['control_of_access_code'],
               #speed_limit
               #outside_lane_width
               row_iter.row_county['tis_directional'],
               #row_iter.row_road_char['directional_tis_id'],
               row_iter.row_county['begm'], # mval_beg
               row_iter.row_county['endm'], # mval_end
               # 11-15:
            #?? mval_increases
            #?? ccp_conflict
               row_iter.row_county['rte_syst'], # route_system_code
               #row_iter.row_road_char['route_system_code'],
               row_iter.row_county['cnty_code'],
               row_iter.row_road_char['divided_oneway_code'],
               #
               row_iter.row_road_char['dir_travel_on_segment_code'],
               row_iter.row_road_char['functional_classification_code'],
               # lane_count_total
               row_iter.row_road_char['total_number_of_lanes'],
            #?? lane_count_mval_i
            #?? lane_count_mval_d
               #
               row_iter.row_road_char['surface_width'],
               row_iter.row_road_char['surface_type_code'],
               row_iter.row_road_char['right_shoulder_width'],
               row_iter.row_road_char['right_shoulder_type_code'],
               row_iter.row_road_char['left_shoulder_width'],
               #
               row_iter.row_road_char['left_shoulder_type_code'],
               ))
         self.by_rows_to_insert.append(by_row_to_insert)

   # ***

   #
   def mndot_attributes_ccp_consume(self, row_county, row_road_char,
                                          line_already_processed,
                                          row_iter):

      byway_already_processed = False

      byway_stk_id = row_county['ccp_stack_id']
      if not byway_stk_id:
         byway_stk_id = row_county['ccp_conflict']
         # Since we UPDATE item_versioned immediately to change an existing
         # link_value's valid_until_rid, but we bulk INSERT later, if two or
         # more mndot lines share the same Ccp conflict, we don't want to
         # add the same link twice.
         if byway_stk_id in self.ccp_byways_attrs_processed:
            byway_already_processed = True
      g.assurt(byway_stk_id > 0)

      if not byway_already_processed:

         if row_iter is not None:
            byway_gfl_id = row_iter.byway_gfl_id
            control_of_access = row_iter.control_of_access
            one_way_code = row_iter.one_way_code
            bridge_level_z = row_iter.bridge_level_z
         else:
            byway_gfl_id, control_of_access = self.get_gflid_and_access(
                                                row_county, row_road_char)
            one_way_code = self.get_one_way_code(row_county, row_road_char)
            bridge_level_z = byway.One.z_level_med

         # Maybe update geofeature columns, or maybe compare calculated values
         # against existing byway conflict and complain if different.
         self.mndot_attributes_geofeature_update(
            row_county, row_road_char,
            line_already_processed, row_iter, byway_stk_id,
            byway_gfl_id, control_of_access, one_way_code, bridge_level_z)

         # Go through mndot attributes and make or update link_values.
         if row_road_char is not None:
            self.mndot_attributes_link_values_update(
               row_county, row_road_char,
               line_already_processed, row_iter, byway_stk_id,
               byway_gfl_id, control_of_access, one_way_code, bridge_level_z)

         self.ccp_byways_attrs_processed.add(byway_stk_id)

   # ***

   #
   def mndot_attributes_geofeature_update(self,
         row_county, row_road_char,
         line_already_processed, row_iter, byway_stk_id,
         byway_gfl_id, control_of_access, one_way_code, bridge_level_z):

      if self.cli_opts.force_update_geofeature:
            #
            # NOTE: This is a very unwiki clobber, but we most likely just made
            #       this geofeature, so we're still just initializing it.
            #
            g.assurt(False) # There's gotta be a better way: update the
            #               # existing geofeature's valid_until_rid and
            #               # then make a new version...
            #
            one_way_code = self.get_one_way_code(row_county, row_road_char)
            bridge_level_z = byway.One.z_level_med # z (just set to mid. value)
            update_sql = (
               """
               UPDATE geofeature AS gf
               SET geofeature_layer_id = %d,
                   control_of_access = %d,
                   one_way = %d,
                   z = %d
               FROM item_versioned AS iv
               WHERE gf.stack_id = %d
                 AND gf.branch_id = %d
                 AND gf.system_id = iv.system_id
                 AND iv.valid_until_rid = %d
               """ % (byway_gfl_id,
                      control_of_access,
                      one_way_code,
                      bridge_level_z,
                      byway_stk_id,
                      self.qb.branch_hier[0][0],
                      conf.rid_inf,))
            rows = self.qb.db.sql(update_sql)
            g.assurt(len(rows) == 0)
            g.assurt(self.qb.db.rowcount() == 1)
         # else: we either just imported line_segments and created the
         #       geofeature, or we're making link_values and not touching
         #       the geofeature (because it's just fine).
      else:
         select_sql = (
            """
            SELECT iv.name,
                   gf.geofeature_layer_id,
                   gf.control_of_access,
                   gf.one_way,
                   gf.z
            FROM geofeature AS gf
            JOIN item_versioned AS iv USING (system_id)
            WHERE gf.stack_id = %d
              AND gf.branch_id = %d
              AND iv.valid_until_rid = %d
            """ % (byway_stk_id,
                   self.qb.branch_hier[0][0],
                   conf.rid_inf,))
         rows = self.qb.db.sql(select_sql)

         if ((line_already_processed or row_county['ccp_conflict'])
             and (len(rows) != 1)):
            log.error('mndot_attrs_gf_upd: byway_stk_id: %d / %s'
                      % (byway_stk_id, rows,))
            g.assurt(False)

         elif rows:

            if rows[0]['geofeature_layer_id'] != byway_gfl_id:
               self.geofeature_gflids_different.append(
                  (byway_stk_id,
                   row_county['objectid'],
                   rows[0]['name'],
                   row_county['str_name'],
                   rows[0]['geofeature_layer_id'],
                   byway_gfl_id,))
            #
            # This is wrong: We use the 'restricted' tag.
            # geofeature.control_of_access is a new, underimplemented attr.
            #  if rows[0]['control_of_access'] != control_of_access:
            #     col_conflicts.append(
            #        'control_of_access: ccp: %s / mndot: %s'
            #        % (rows[0]['control_of_access'],
            #           control_of_access,))
            if rows[0]['one_way'] != one_way_code:
               self.geofeature_oneways_different.append(
                  (byway_stk_id,
                   row_county['objectid'],
                   rows[0]['name'],
                   row_county['str_name'],
                   rows[0]['one_way'],
                   one_way_code,))
            if rows[0]['z'] != bridge_level_z:
               self.geofeature_zlevels_different.append(
                  (byway_stk_id,
                   row_county['objectid'],
                   rows[0]['name'],
                   row_county['str_name'],
                   rows[0]['z'],
                   bridge_level_z,))

      return

   # ***

   #       SELECT DISTINCT(tcode), stype FROM (
   #          SELECT DISTINCT(surface_type_code) AS tcode,
   #                 surface_type AS stype
   #             FROM mndot_road_char
   #          UNION
   #          SELECT DISTINCT(right_shoulder_type_code) AS tcode,
   #                 right_shoulder_type AS stype
   #             FROM mndot_road_char
   #          UNION
   #          SELECT DISTINCT(left_shoulder_type_code) AS tcode,
   #                 left_shoulder_type AS stype
   #             FROM mndot_road_char
   #       ) AS foo
   #       ORDER BY tcode;
   #
   #  tcode |                               stype                              
   # -------+------------------------------------------------------------------
   #
   # These codes are used by surface_type and right_/left_shoulder_type.
   #
   #  A     | Primitive
   #  B     | Unimproved
   #  C     | Graded and drained
   #  D     | Soil-surfaced
   #  E     | Gravel or stone
   #  F     | Bituminous surface-traveled
   #  G     | Mixed bituminous - type unknown
   #  G1    | Mixed bituminous - low-type
   #  G2    | Mixed bituminous - high-type
   #  G3    | Mixed bituminous - resurfacing
   #  G4    | Mixed bituminous - new construction
   #  I     | Bituminous concrete
   #  I3    | Bituminous concrete - resurfacing
   #  I4    | Bituminous concrete - new construction
   #  J     | Portland cement concrete
   #  J3    | Portland cement concrete - resurfacing
   #  J4    | Portland cement concrete - new construction
   #  K     | Brick
   #  L     | Block
   #  NV    | Not applicable
   #
   # These codes are not used by surface_type, but are used by right_/left_.
   #
   #  00    | No Shoulder
   #  1     | NV
   #  M     | NV
   #  M1    | Bituminous composite shoulder - 1 foot bitiminous, inside portion
   #  M2    | Bituminous composite shoulder - 2 foot bitiminous, inside portion
   #  M3    | Bituminous composite shoulder - 3 foot bitiminous, inside portion
   #  M4    | Bituminous composite shoulder - 4 foot bitiminous, inside portion
   #  M5    | Bituminous composite shoulder - 5 foot bitiminous, inside portion
   #  M6    | Bituminous composite shoulder - 6 foot bitiminous, inside portion
   #  M7    | Bituminous composite shoulder - 7 foot bitiminous, inside portion
   #  M8    | Bituminous composite shoulder - 8 foot bitiminous, inside portion
   #  N     | NV
   #  N1    | Concrete composite shoulder - 1 foot concrete, inside portion
   #  N2    | Concrete composite shoulder - 2 foot concrete, inside portion
   #  S     | Sod Shoulder
   #
   # These codes are only used by right_shoulder_type, and not left_shoulder.
   #  02    | NV
   #  10    | NV
   #  M9    | Bituminous composite shoulder - 9 foot bitiminous, inside portion
   #  N3    | Concrete composite shoulder - 3 foot concrete, inside portion

   PAVEMENT_BRICK = 'K'
   PAVEMENT_GRADED = 'C' # This is below gravel and soil according to nevadadot
                         # http://www.nevadadot.com/uploadedFiles/NDOT
                         #  /Traveler_Info/Maps/nyecounty1963_006.pdf
   PAVEMENT_GRAVEL = 'E'
   PAVEMENT_SOD = 'S' # Only applies to shoulders
   PAVEMENT_SOIL = 'D'
   PAVEMENT_CODE_UNPAVED = (
      'A', 'B', 'C', 'D', 'E', 'S',
      )
   PAVEMENT_CODE_PAVED = (
      'F',
      # The 'G's are a lot of local roads.
      'G', 'G1', 'G2', 'G3', 'G4',
      # The 'I's are city collectors.
      'I', 'I3', 'I4',
      # This is a mix of city streets and collectors.
      'J', 'J3', 'J4',
      'K', # Brick
      # Block is, what, concrete slabs?
      'L', # Block
      'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9',
      # There are only 15 of these:
      'N1', 'N2', 'N3',
      )
   PAVEMENT_CODE_UNKNOWN_OR_NO_SHOULDER = (
      # 'M' and 'N' is used once as right_ and left_shoulder_type_code...
      #   Nicollet Ave., in Saint Peter; nice trail along
      #   local road without a shoulder.
      # '02' is used once as right_shoulder_type.
      # '1' is used 4 times as right sldr type and once as left.
      #   A few are on a freeway that has a shoulder, and a few
      #   are in New Prague on a local road that seems to have a
      #   few feet of pavement past the painted white line...
      # '10' is used once, on US 10 in Detroit Lakes, where it looks
      #   like there's a tiny shoulder...
      # 'NV' is used by 36399 line segs as either left or right shldr...
      #   where there is no shoulder. And 18121 times as surface type, on
      #   what look like paved roads.
      'NV', '02', '1', '10', 'M', 'N', '00',
      )

   #
   def mndot_attributes_link_values_update(self,
         row_county, row_road_char,
         line_already_processed, row_iter, byway_stk_id,
         byway_gfl_id, control_of_access, one_way_code, bridge_level_z):

      # We've already processed row_county, because those attributes all
      # match columns in the geofeature table, or they're not attribute
      # that we consume. Maybe someday in the future we'll be interested
      # in these, or maybe not ever.
      #     Skipping: row_county['divided_roadway']
      #     Skipping: row_county['begm']
      #     Skipping: row_county['endm']
      # We've also already processed vol_aadt and vol_hcaadt, so all that's
      # left is mndot_road_char... which is jam packed full of interesting
      # values. Except for ones we ignore:
      #     Skipping: row_road_char['from_true_miles']
      #     Skipping: row_road_char['to_true_miles']
      # And a bunch of row_road_char columns we already processed, like
      # route_system_code, functional_classification, divided_oneway, and
      # direction_travel_on_segment.
      #     Skipping: row_road_char['median_type_code']
      #     Skipping: row_road_char['median_type']
      #     Skipping: row_road_char['median_width']
      #     Skipping: row_road_char['curbs_code']
      #     Skipping: row_road_char['curbs']
      # And Cyclopath doesn't break out lane count by directionality,
      # so, e.g., an undivided three lane road is not well represented
      # in Cyclopath.
      #     Skipping: row_road_char['number_of_lanes_im']
      #     Skipping: row_road_char['number_of_lanes_dm']
      # We also don't store the total roadway width.
      #     Skipping: row_road_char['surface_width']

      # Cyclopath attributes:
      #
      # Bicycle Facility   | /byway/cycle_facil        | Can set shldr type
      # Direction          | /byway/one_way            | DEPRECATED; Use gf
      # Speed limit        | /byway/speed_limit        | NO DATA
      # Total no. of lanes | /byway/lane_count         | Okay to set
      # Width outside lane | /byway/outside_lane_width | NO DATA
      # Usable shldr space | /byway/shoulder_width     | Okay to set
      # Controlled Access  | /byway/no_access          | DEPREC; Use gf &or tag
      #
      # Cyclopath tags:
      #
      # 'paved', 'unpaved', 'prohibited'

      add_tags = []

      # ***

      if control_of_access == Statewide_MnDOT_Import.CTL_OF_ACC_FULL:
         add_tags.append('prohibited')

      # ***

      surf_type = row_road_char['surface_type_code']
      if surf_type in Statewide_MnDOT_Import.PAVEMENT_CODE_UNPAVED:
         add_tags.append('unpaved')
         if surf_type == Statewide_MnDOT_Import.PAVEMENT_BRICK:
            add_tags.append('brick road')
         elif surf_type == Statewide_MnDOT_Import.PAVEMENT_GRADED:
            add_tags.append('graded road')
         elif surf_type == Statewide_MnDOT_Import.PAVEMENT_GRAVEL:
            add_tags.append('gravel road')
         elif surf_type == Statewide_MnDOT_Import.PAVEMENT_SOIL:
            add_tags.append('soil road')

      # ***

   # FIXME: Add 'hill' tag? Need to update or write elevation script...

      # *** Total no. of lanes.

      if one_way_code == 0:
         attr_lane_count = int(row_road_char['total_number_of_lanes'])
      else:
         # For one way, use left or right width (the one that's not zero).
         attr_lane_count = max(row_road_char['number_of_lanes_im'],
                               row_road_char['number_of_lanes_dm'])
         warning = ''
         traffic_dir = row_county['traffic_direction']
         if traffic_dir == Statewide_MnDOT_Import.TRAFFIC_FLOW_BOTH: # 'B'
            warning = 'one_way set but traffic_dir not'
         elif traffic_dir == Statewide_MnDOT_Import.TRAFFIC_FLOW_IDIR: # 'I'
            if row_road_char['number_of_lanes_im'] != attr_lane_count:
               warning = 'I: not using increasing mileage lane count'
         elif traffic_dir == Statewide_MnDOT_Import.TRAFFIC_FLOW_DDIR: # 'D'
            if row_road_char['number_of_lanes_dm'] != attr_lane_count:
               warning = 'D: not using decreasing mileage lane count'
         if warning:
            log.warning('%s: oid: %7s / %s / %s'
                        % (warning,
                           row_county['objectid'],
                           row_county,
                           row_road_char,))

      # *** Right shoulder width, if paved.

      attr_shoulder_width = None
      r_shldr_type = row_road_char['right_shoulder_type_code']
      try:
         r_shldr_width = int(row_road_char['right_shoulder_width'])
      except ValueError:
         # 'NV', 'UN'
         r_shldr_width = 0
         r_shldr_type = 'NV'
      if one_way_code != 0:
         if r_shldr_type in Statewide_MnDOT_Import.PAVEMENT_CODE_PAVED:
            if r_shldr_width > 0:
               attr_shoulder_width = r_shldr_width
            else:
               self.shoulder_paved_no_width.append(
                  (row_county['objectid'], None, None,))
         # else, ignore left shoulder on one ways.
      else:
         # This is a two-way road. In Cyclopath, we only have one shoulder
         # value for each line segment, so if the shoulder isn't paved on
         # one side, it's not paved on either; or, more pointedly, take the
         # worst value from either side.
         l_shldr_type = row_road_char['left_shoulder_type_code']
         try:
            l_shldr_width = int(row_road_char['left_shoulder_width'])
         except ValueError:
            # 'NV', 'UN'
            l_shldr_width = 0
            l_shldr_type = 'NV'
         if ((r_shldr_type in Statewide_MnDOT_Import.PAVEMENT_CODE_PAVED)
             and (l_shldr_type in Statewide_MnDOT_Import.PAVEMENT_CODE_PAVED)):
            shldr_width = min(r_shldr_width, l_shldr_width)
            if shldr_width > 0:
               attr_shoulder_width = shldr_width
               if r_shldr_width != l_shldr_width:
                  self.shoulder_width_different.append(
                     (row_county['objectid'],
                      r_shldr_width,
                      l_shldr_width,
                      shldr_width,))
            else:
               self.shoulder_paved_no_width.append(
                  (row_county['objectid'], r_shldr_width, l_shldr_width,))
         elif ((r_shldr_type in Statewide_MnDOT_Import.PAVEMENT_CODE_PAVED)
               or (l_shldr_type in Statewide_MnDOT_Import.PAVEMENT_CODE_PAVED)
               ):
            self.shoulder_pavement_differs.append(
               (row_county['objectid'],
                r_shldr_type,
                l_shldr_type,
                r_shldr_width,
                l_shldr_width,))

      # *** Traffic volume-ish.

      # MAGIC_NUMBER: A 'heavy volume' road is 2500+ vehicles.
      #
      # See: http://ntl.bts.gov/DOCS/98072/index.html
      #
      #         Development  of  the
      #     B i c y c l e  C o m p a t i b i l i t y  I n d e x:
      #         _a_level_of_  Service  Concept,
      #         FINAL REPORT
      #
      #                Publication No. FHWA-RD-98-072
      #                        December 1998
      #
      # SELECT COUNT(*), ST_Length(ST_Collect(geometry))
      #  FROM mndot_vol_aadt WHERE aadt_2012 > -1
      #                        AND aadt_2012 < 2500;
      #    count |    st_length    
      #   -------+-----------------
      #     5174 | 18082709.9216947
      #
      # SELECT COUNT(*), ST_Length(ST_Collect(geometry))
      #  FROM mndot_vol_aadt WHERE aadt_2012 > -1
      #                        AND aadt_2012 >= 2500;
      #   count |    st_length     
      #  -------+------------------
      #    6449 | 10517567.8584869
      #
      # [lb] didn't find any study on heavy commercial traffic volumes,
      #      so this is a complete guess. Is 300 a good threshold?
      #      Let's run some tiles and see what we see!
      #
      # SELECT COUNT(*), ST_Length(ST_Collect(geometry))
      #  FROM mndot_vol_hcaadt WHERE hcaadt_2012 > -1
      #                          AND hcaadt_2012 < 300;
      #   count |    st_length     
      #  -------+------------------
      #    2159 | 11454149.2926198
      #
      # SELECT COUNT(*), ST_Length(ST_Collect(geometry))
      #  FROM mndot_vol_hcaadt WHERE hcaadt_2012 > -1
      #                          AND hcaadt_2012 >= 300;
      #   count |    st_length     
      #  -------+------------------
      #    4297 | 11565420.9034839

      vol_aadt = None
      vol_hcaadt = None
      if row_iter is not None:
         if row_iter.row_aadt is not None:
            vol_aadt = row_iter.row_aadt['aadt_2012']
         if row_iter.row_hcaadt is not None:
            vol_hcaadt = row_iter.row_hcaadt['hcaadt_2012']
      else:
         vol_aadt_sql = (
            """
            SELECT DISTINCT ON (aadt_year) aadt_year, aadt
            FROM aadt
            WHERE byway_stack_id = %d
              AND aadt_type = 'auto'
            ORDER BY aadt_year DESC
            """ % (byway_stk_id,))
         rows = self.qb.db.sql(vol_aadt_sql)
         if rows:
            g.assurt(len(rows) == 1)
            vol_aadt = rows[0]['aadt']
         #
         vol_hcaadt_sql = (
            """
            SELECT DISTINCT ON (aadt_year) aadt_year, aadt
            FROM aadt
            WHERE byway_stack_id = %d
              AND aadt_type = 'heavy'
            ORDER BY aadt_year DESC
            """ % (byway_stk_id,))
         rows = self.qb.db.sql(vol_hcaadt_sql)
         if rows:
            g.assurt(len(rows) == 1)
            vol_hcaadt = rows[0]['aadt']

      is_high_volume = None
      if vol_aadt:
         if vol_aadt < conf.vol_addt_high_volume_threshold: # E.g., 2500
            is_high_volume = False
         else:
            is_high_volume = True
            add_tags.append('high volume')
      if vol_hcaadt:
         if vol_hcaadt < conf.vol_addt_heavy_commercial_threshold: # E.g., 300
            if is_high_volume is None:
               is_high_volume = False
         else:
            if is_high_volume is None:
               is_high_volume = True
            add_tags.append('heavy commercial')

      attr_cycle_facil = None
      if ((control_of_access != Statewide_MnDOT_Import.CTL_OF_ACC_FULL)
          # MAYBE: Would it be a good idea to include Major_Roads w/ shoulders?
          and (byway_gfl_id in (byway.Geofeature_Layer.Highway,
                                #byway.Geofeature_Layer.Major_Road,
                                ))):
         # MAGIC_NUMBER: A 'bikeable' shoulder is 4 feet wide or wider.
         if ((attr_shoulder_width is not None)
             and (attr_shoulder_width >= 4)):
            if is_high_volume:
               attr_cycle_facil = 'shld_hivol'
            else:
               attr_cycle_facil = 'shld_lovol'
         else:
            if is_high_volume:
               attr_cycle_facil = 'hway_hivol'
            else:
               attr_cycle_facil = 'hway_lovol'

      # ***

      lval_defs = []

      for tag_name in add_tags:
         g.assurt(tag_name in Statewide_MnDOT_Import.tags_we_use)
         tag_stk_id = self.tag_lookup[tag_name]
         lval_defs.append((tag_stk_id,
                           None,
                           None,
                           'tag',))

      if attr_lane_count:
         lval_defs.append((self.attr_lane_count.stack_id,
                           'value_integer',
                           attr_lane_count,
                           self.attr_lane_count.value_internal_name,))

      if attr_shoulder_width:
         lval_defs.append((self.attr_shoulder_width.stack_id,
                           'value_integer',
                           attr_shoulder_width,
                           self.attr_shoulder_width.value_internal_name,))

      if attr_cycle_facil:
         lval_defs.append((self.attr_cycle_facil.stack_id,
                           'value_text',
                           attr_cycle_facil,
                           self.attr_cycle_facil.value_internal_name,))

      for ldef in lval_defs:

         lval_attc_stk_id = ldef[0]
         lval_value_attr = ldef[1]
         lval_value_value = ldef[2]
         lval_attc_friendly = ldef[3]

         lval_sys_id = None
         lval_stk_id = None
         lval_version = 1

         # Check link_value first to see if one already exists, which happens
         # if we've run this script before, or if the mndot line segment has
         # a Cyclopath match.

         processed_link = False

         if line_already_processed or row_county['ccp_conflict']:

            select_sql = (
               """
               SELECT
                  iv.system_id
                  , iv.stack_id
                  , iv.version
                  , iv.valid_start_rid
                  , iv.deleted
                  , iv.reverted
                  --, lv.value_boolean
                  , lv.value_integer
                  --, lv.value_real
                  , lv.value_text
                  --, lv.value_binary
                  --, lv.value_date
               FROM link_value AS lv
               JOIN item_versioned AS iv
                  USING (system_id)
               WHERE lv.lhs_stack_id = %d
                 AND lv.rhs_stack_id = %d
                 AND iv.branch_id = %d
                 AND iv.valid_until_rid = %d
               """ % (lval_attc_stk_id,
                      byway_stk_id,
                      self.qb.branch_hier[0][0],
                      conf.rid_inf,))

            rows = self.qb.db.sql(select_sql)

            if rows:

               #g.assurt(len(rows) == 1)
               if len(rows) > 1:
                  import pdb;pdb.set_trace()

               lval_row = rows[0]

               if lval_value_attr:
                  # An attribute.
                  curr_value = lval_row[lval_value_attr]
                  new_value = lval_value_value
               else:
                  # A tag.
                  curr_value = None if not lval_row['deleted'] else 'deleted'
                  new_value = None

               lval_stk_id = lval_row['stack_id']

               curr_start_rid = lval_row['valid_start_rid']

               if curr_value != lval_value_value:
                  # A new value!
                  self.lvals_already_same_value += 1
                  lval_sys_id = lval_row['system_id']
                  lval_version = lval_row['version']
                  if curr_start_rid < self.qb.item_mgr.rid_new:
                     if ((not row_county['ccp_conflict'])
                         or self.cli_opts.update_existing_lvals):
                        update_sql = (
                           """
                           UPDATE item_versioned
                           SET valid_until_rid = %d
                           WHERE system_id = %d
                           """ % (self.qb.item_mgr.rid_new,
                                  lval_sys_id,))
                        rows = self.qb.db.sql(update_sql)
                        g.assurt((not rows) and (self.qb.db.rowcount() == 1))
                        update_sql = (
                           """
                           UPDATE group_item_access
                           SET valid_until_rid = %d
                           WHERE item_id = %d
                             AND valid_until_rid = %d
                           """ % (self.qb.item_mgr.rid_new,
                                  lval_sys_id,
                                  conf.rid_inf,))
                        rows = self.qb.db.sql(update_sql)
                        g.assurt((not rows) and (self.qb.db.rowcount() == 1))
                        # Get a new system ID for the next item version.
                        lval_sys_id = self.qb.item_mgr.seq_id_steal_system_id(
                                                                  self.qb.db)
                        lval_version += 1
                        log_msg = 'chg fr. %s' % (curr_value,)
                     else:
                        log_msg = 'left as %s' % (curr_value,)
                        processed_link = True
                  else:
                     # This only happens if re-running script on same Rev.
                     g.assurt(curr_start_rid == self.qb.item_mgr.rid_new)
                     if lval_value_attr:
                        if lval_value_attr == 'value_integer':
                           new_value = lval_value_value
                        elif lval_value_attr == 'value_text':
                           new_value = "'%s'" % (lval_value_value,)
                        update_sql = (
                           """
                           UPDATE link_value
                           SET %s = %s
                           WHERE system_id = %d
                           """ % (lval_value_attr,
                                  new_value,
                                  lval_sys_id,))
                        rows = self.qb.db.sql(update_sql)
                        g.assurt((not rows) and (self.qb.db.rowcount() == 1))
                        lval_version = rows[0]['version']
                     # else: # A tag. And its link_value exists.
                     log_msg = 'upd fr. %s' % (curr_value,)
                     processed_link = True
                  # We either set valid_until_rid on the existing link_value,
                  # or we UPDATEd its row; remember this for reporting.
                  self.existing_link_values_updated.append(
                     (row_county['objectid'],
                      byway_stk_id,
                      lval_stk_id,
                      lval_version,
                      curr_start_rid,
                      lval_value_attr,
                      new_value,
                      log_msg,
                      lval_attc_friendly,))
               else:
                  # curr_value == lval_value_value, so nothing to do.
                  processed_link = True

            # end: if (existing link_value) rows

         # end: if line_already_processed

         if processed_link:
            # This only happens if we re-run the script of the same Rev.
            # number. So, this never happens.
            continue

         if not lval_sys_id:
            lval_sys_id = self.qb.item_mgr.seq_id_steal_system_id(self.qb.db)

         if not lval_stk_id:
            lval_stk_id = self.qb.item_mgr.seq_id_steal_stack_id(self.qb.db)
            if lval_stk_id in self.item_stack_ids_processed:
               import pdb;pdb.set_trace()
               pass
            is_row_to_insert = (
               "(%d, '%s', %d, %d)"
               % (lval_stk_id,
                  self.qb.username,
                  Access_Style.pub_editor,
                  Access_Infer.pub_editor,
                  ))
            self.is_rows_to_insert.append(is_row_to_insert)

         self.item_stack_ids_processed.add(lval_stk_id)

         iv_row_to_insert = (
            "(%d, %d, %d, %d, %s, %s, %s, %d, %d)"
            % (lval_sys_id,
               self.qb.branch_hier[0][0],
               lval_stk_id,
               lval_version,
               'FALSE', # deleted
               'FALSE', # reverted
               'NULL',  # name
               self.qb.item_mgr.rid_new, # valid_start_rid
               conf.rid_inf, # 2000000000
               ))
         self.iv_rows_to_insert.append(iv_row_to_insert)

2014.05.21: Bitrot: Added item_revisionless table:
   Missing self.ir_rows_to_insert.append

         if lval_value_attr == 'value_integer':
            value_integer = str(lval_value_value)
            value_text = "NULL"
         elif lval_value_attr == 'value_text':
            value_integer = "NULL"
            value_text = "'%s'" % (lval_value_value,)
         else:
            # A tag.
            value_integer = "NULL"
            value_text = "NULL"
         lv_row_to_insert = (
            "(%d, %d, %d, %d, %d, %d, %s, %s)"
            % (lval_sys_id,
               self.qb.branch_hier[0][0],
               lval_stk_id,
               lval_version,
               lval_attc_stk_id,
               byway_stk_id,
               #value_boolean,
               value_integer,
               #value_real,
               value_text,
               #value_binary,
               #value_date,
               ))
         self.lv_rows_to_insert.append(lv_row_to_insert)

         gia_row_to_insert = (
            """(%d, %d, %d, %d, %d,
                %d, %d, %d, %s, %s,
                %d, %d, %s, %s, %s
                )"""
            % (
               # Interpolations 1-5
               self.public_group_id,
               lval_sys_id,
               self.qb.branch_hier[0][0],
               lval_stk_id,
               lval_version,

               # Interpolations 6-10
               1, # acl_grouping
               self.qb.item_mgr.rid_new, # valid_start_rid
               conf.rid_inf, # valid_until_rid
               'FALSE', # deleted
               'FALSE', # reverted

               # Interpolations 11-15
               Access_Level.editor, # access_level_id
               Item_Type.LINK_VALUE, # item_type_id
               Item_Type.ATTRIBUTE if lval_value_attr else Item_Type.TAG,
               Item_Type.BYWAY, # link_rhs_type_id
               "NULL", # name
               ))
         self.gia_rows_to_insert.append(gia_row_to_insert)

      # end: for ldef in lval_defs

      return

   # ***

   #
   def mndot_line_ccp_insert_bulk(self):

      if self.is_rows_to_insert:
         item_stack.Many.bulk_insert_rows(self.qb,
                                          self.is_rows_to_insert)

      if self.iv_rows_to_insert:
         item_versioned.Many.bulk_insert_rows(self.qb,
                                              self.iv_rows_to_insert)

      if self.ir_rows_to_insert:
         item_revisionless.Many.bulk_insert_rows(self.qb,
                                                 self.ir_rows_to_insert)

      if self.ne_rows_to_insert:
         g.assurt(self.nexy_rows_to_insert)
         self.table_bulk_insert_node_endpoint(self.ne_rows_to_insert)
         #self.table_bulk_insert_node_byway(self.nb_rows_to_insert)
         self.table_bulk_insert_node_endpt_xy(self.nexy_rows_to_insert)
      else:
         g.assurt(not self.nexy_rows_to_insert)

      if self.gf_rows_to_insert:
         geofeature.Many.bulk_insert_rows(self.qb, self.gf_rows_to_insert)
         byway.Many.bulk_insert_ratings(self.qb, self.br_rows_to_insert)
      else:
         g.assurt(not self.br_rows_to_insert)

      if self.lv_rows_to_insert:
         link_value.Many.bulk_insert_rows(self.qb, self.lv_rows_to_insert)

      if self.gia_rows_to_insert:
         group_item_access.Many.bulk_insert_rows(self.qb,
                                                 self.gia_rows_to_insert)

      if self.aadt_rows_to_insert:
         byway.Many.bulk_insert_volume_aadt(self.qb, self.aadt_rows_to_insert)

      if self.by_rows_to_insert:
         self.table_bulk_insert_byway_mndot(self.by_rows_to_insert)

      self.mndot_line_ccp_insert_reset()

   #
   def mndot_line_ccp_insert_reset(self):

      self.is_rows_to_insert = [] # item_stack

      self.iv_rows_to_insert = [] # item_versioned

      self.ir_rows_to_insert = [] # item_revisionless

      self.ne_rows_to_insert = [] # node_endpoint
      #self.nb_rows_to_insert = [] # node_byway
      self.nexy_rows_to_insert = [] # node_endpt_xy

      self.gf_rows_to_insert = [] # geofeature
      self.br_rows_to_insert = [] # byway_rating

      self.lv_rows_to_insert = [] # link_value

      self.gia_rows_to_insert = [] # group_item_access

      self.aadt_rows_to_insert = [] # aadt
      self.aadt_ccp_stack_ids = set()

      self.by_rows_to_insert = [] # byway_mndot

   #
   def table_bulk_insert_node_endpoint(self, ne_rows_to_insert):

      insert_sql = (
         """
         INSERT INTO %s.node_endpoint (
            system_id
            , branch_id
            , stack_id
            , version
            , reference_n
            --, referencers
            , elevation_m
            --, dangle_okay
            --, a_duex_rues
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(ne_rows_to_insert),))

      self.qb.db.sql(insert_sql)

   #
   def table_bulk_insert_node_endpt_xy(self, nexy_rows_to_insert):

      insert_sql = (
         """
         INSERT INTO %s.node_endpt_xy (
            node_stack_id
            , endpoint_xy
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(nexy_rows_to_insert),))

      self.qb.db.sql(insert_sql)

   #
   def table_bulk_insert_byway_mndot(self, by_rows_to_insert):

      insert_sql = (
         """
         INSERT INTO %s.byway_mndot (
            byway_stack_id
            , branch_id
            --, version
            --, system_id
            , bridge_level_z
            , one_way_code
            , beg_node_id
            , fin_node_id
            --, split_from_stack_id
            , control_of_access_code
            --, speed_limit
            --, outside_lane_width
            , directional_tis_id
            , mval_beg
            , mval_end
            , mval_increases
            , ccp_conflict
            , route_system_code
            , cnty_code
            , divided_oneway_code
            , dir_travel_on_segment_code
            , functional_classification_code
            , lane_count_total
            , lane_count_mval_i
            , lane_count_mval_d
            , surface_width
            , surface_type_code
            , right_shoulder_width
            , right_shoulder_type_code
            , left_shoulder_width
            , left_shoulder_type_code
            ) VALUES
               %s
         """ % (conf.instance_name,
                ','.join(by_rows_to_insert),))

      self.qb.db.sql(insert_sql)

   # ***

   #
   def update_relevant_geometry_summaries(self):

      self.qb.db.transaction_begin_rw()

      self.update_geometry_revision()

      self.update_geometry_branch()

      #self.cli_args.close_query(do_commit=(not debug_skip_commit))
      self.qb.db.transaction_finish(do_commit=(not debug_skip_commit))

   #
   def update_geometry_revision(self):

      # Update revision geosummaries.

      log.debug('Calculating revision geometries...')

      group_ids = [self.public_group_id,]

      time_0 = time.time()

      Revision.geosummary_update(
         self.qb.db,
         self.qb.item_mgr.rid_new,
         self.qb.branch_hier,
         group_ids)

      misc.time_complain('geosummary_update', time_0, 30.0, True)

   #
   def update_geometry_branch(self):

      # Update branch coverage_area.

      log.debug('Recalculaing branch coverage_area...')

      branches = branch.Many()
      branches.search_by_stack_id(self.qb.branch_hier[0][0], self.qb)
      g.assurt(len(branches) == 1)
      branch_ = branches[0]

      if not self.cli_opts.skip_coverage_area:

         byway.Many.branch_coverage_area_update(
            self.qb.db, branch_, self.qb.item_mgr.rid_new)

   # ***

   #
   def delete_me(self):

      hrm = (
"""

0. claim a revision first, so we don't have to hold the lock?
we'd have to get the lock to get stack IDs, though...
need as many stack ids as county segments,
 and maybe one or two more for each line's endpoint...ug...
maybe we can count node_byway matches and eliminate?



1. um... can we join counties against the
three other tables to get candidates?
2. for each candidate, look for Cyclopath match
3. pop tables


""")

   # ***

   #
   def db_commit_maybe(self):

      if commit_oftener:
         #self.cli_args.close_query(do_commit=debug_skip_commit)
         self.qb.db.transaction_finish(do_commit=(not debug_skip_commit))
         self.qb.db.transaction_begin_rw()

   # ***

   #
   def stats_prepare(self):

      self.hausdorff_buckets = {}
      self.hausdorff_buckets['mndot_road_char'] = {}
      self.hausdorff_buckets['mndot_vol_aadt'] = {}
      self.hausdorff_buckets['mndot_vol_hcaadt'] = {}

      self.objectids_suspect = {}
      self.objectids_suspect['no_road_char'] = []

      self.ccp_match_not_so_confident = []
      self.best_hausdorff_gt_geom_len = []
      self.same_nodes_with_multiple_intersections = []

      self.mndot_lines_already_processed = {}
      self.num_mndot_lines_already_bywayed = 0

      self.lvals_already_same_value = 0

      self.ccp_byways_attrs_processed = set()

      self.geofeature_gflids_different = []
      self.geofeature_oneways_different = []
      self.geofeature_zlevels_different = []
      self.existing_link_values_updated = []
      self.divided_oneway_different = []
      self.shoulder_paved_no_width = []
      self.shoulder_width_different = []
      self.shoulder_pavement_differs = []

      self.item_stack_ids_processed = set()

   #
   def stats_report(self):

      if self.mndot_lines_already_processed:
         log.warning('')
         log_msg = (
            'No. mndot_counties rows maybe already processed: %d / skipped: %d'
            % (len(self.mndot_lines_already_processed),
               self.num_mndot_lines_already_bywayed,)) 
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         #log.warning(
         #   'These mndot_counties rows were reprocessed: %s'
         #   % (self.mndot_lines_already_processed.keys(),))
         for oid, kvals in self.mndot_lines_already_processed.iteritems():
            log.warning('OID: %7s / Col-Vals: %s' % (oid, kvals,))

      # ***

      self.hausdorff_bucket_show(self.hausdorff_buckets['mndot_road_char'],
                                 'mndot_road_char')
      self.hausdorff_bucket_show(self.hausdorff_buckets['mndot_vol_aadt'],
                                 'mndot_vol_aadt')
      self.hausdorff_bucket_show(self.hausdorff_buckets['mndot_vol_hcaadt'],
                                 'mndot_vol_hcaadt')

      # ***

      if self.objectids_suspect['no_road_char']:
         log.debug('')
         log_msg = ('No. County line segs w/out road characteristics: %d'
                   % (len(self.objectids_suspect['no_road_char']),))
         log.debug('=' * len(log_msg))
         log.debug(log_msg)
         log.debug('=' * len(log_msg))
         log.debug('OIDs: %s' % (self.objectids_suspect['no_road_char'],))

      # ***

      if self.ccp_match_not_so_confident:
         log.warning('')
         log_msg = ('No. Ccp matches not very confident: %d'
                     % (len(self.ccp_match_not_so_confident),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for unconfidence_tup in self.ccp_match_not_so_confident:
            log.warning(
               '%s %6d.%s - %6d.%s = %6d.%s / oid: %7s / len: %6d.%s'
               % ('_match_mndot: weird:',
                  # second_best_hd:
                  int(unconfidence_tup[0]),
                  str(float(unconfidence_tup[0]
                            - int(unconfidence_tup[0])))[2:4],
                  # best_hausdorff:
                  int(unconfidence_tup[1]),
                  str(float(unconfidence_tup[1]
                            - int(unconfidence_tup[1])))[2:4],
                  # hausdirff:
                  int(unconfidence_tup[2]),
                  str(float(unconfidence_tup[2]
                            - int(unconfidence_tup[2])))[2:4],
                  # row_county['objectid']:
                  unconfidence_tup[3],
                  # row_county['geom_len']:
                  int(unconfidence_tup[4]),
                  str(float(unconfidence_tup[4]
                            - int(unconfidence_tup[4])))[2:4],))

      # ***

      if self.best_hausdorff_gt_geom_len:
         log.warning('')
         log_msg = ('No. MnDOT matches whose Hausdorff is very long: %d'
                     % (len(self.best_hausdorff_gt_geom_len),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for long_geom_tup in self.best_hausdorff_gt_geom_len:
            log.warning(
               '%s %6d.%s / objectid: %7s / len: %6d.%s'
               % ('_match_mndot: unexpected: best:',
                  # best_hausdorff:
                  int(long_geom_tup[0]),
                  # No '0.', and just one-hundreth.
                  str(float(long_geom_tup[0] - int(long_geom_tup[0])))[2:4],
                  # row_county['objectid']:
                  long_geom_tup[1],
                  # row_county['geom_len']:
                  int(long_geom_tup[2]),
                  str(float(long_geom_tup[2] - int(long_geom_tup[2])))[2:4],))

      # ***

      if self.same_nodes_with_multiple_intersections:
         log.warning('')
         log_msg = (
            'No. Cyclopath nodes being used by two or more intersections: %d'
            % (len(self.same_nodes_with_multiple_intersections),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for two_plus_tup in self.same_nodes_with_multiple_intersections:
            log.warning(
               '_ins_new_nde: 2+ ids on nd xy: best: node_stack_id: %d'
               % (two_plus_tup[0],)) # node_stack_id
            for row_bway in two_plus_tup[1]:
               log.warning('_ins_new_nde: row: %s' % (row_bway,))

      # ***

      if self.existing_link_values_updated:
         log.warning('')
         log_msg = (
            'No. existing link_values updated: %d'
            % (len(self.existing_link_values_updated),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for existing_lval_tup in self.existing_link_values_updated:
            log.warning(
               '%s %7s / bway: %7s / lval: %7s.%d@r%5d / %13s = %2s %s (%s)'
               % ('Existg lval update: oid:',
                  existing_lval_tup[0],
                  existing_lval_tup[1],
                  existing_lval_tup[2],
                  existing_lval_tup[3],
                  existing_lval_tup[4],
                  existing_lval_tup[5],
                  existing_lval_tup[6],
                  existing_lval_tup[7],
                  existing_lval_tup[8],))

      # ***

      if self.geofeature_gflids_different:
         log.warning('')
         log_msg = (
            'No. byway-mndot gflid differences: %d'
            % (len(self.geofeature_gflids_different),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for geofeature_attrs_tup in self.geofeature_gflids_different:
            log.warning(
               '%s stk: %7d | oid: %7d / nom: "%s" | "%s" / gflid: %s | %s'
               % ('Byway gflid dif.:',
                  geofeature_attrs_tup[0],
                  geofeature_attrs_tup[1],
                  geofeature_attrs_tup[2],
                  geofeature_attrs_tup[3],
                  geofeature_attrs_tup[4],
                  geofeature_attrs_tup[5],))

      # ***

      if self.geofeature_oneways_different:
         log.warning('')
         log_msg = (
            'No. byway-mndot oneway differences: %d'
            % (len(self.geofeature_oneways_different),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for geofeature_attrs_tup in self.geofeature_oneways_different:
            log.warning(
               '%s stk: %7d | oid: %7d / nom: "%s" | "%s" / oneway: %s | %s'
               % ('Byway oneway dif.:',
                  geofeature_attrs_tup[0],
                  geofeature_attrs_tup[1],
                  geofeature_attrs_tup[2],
                  geofeature_attrs_tup[3],
                  geofeature_attrs_tup[4],
                  geofeature_attrs_tup[5],))

      # ***

      if self.geofeature_zlevels_different:
         log.warning('')
         log_msg = (
            'No. byway-mndot z-level differences: %d'
            % (len(self.geofeature_zlevels_different),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for geofeature_attrs_tup in self.geofeature_zlevels_different:
            log.warning(
               '%s stk: %7d | oid: %7d / nom: "%s" | "%s" / z: %s | %s'
               % ('Byway zlvl dif.:',
                  geofeature_attrs_tup[0],
                  geofeature_attrs_tup[1],
                  geofeature_attrs_tup[2],
                  geofeature_attrs_tup[3],
                  geofeature_attrs_tup[4],
                  geofeature_attrs_tup[5],))

      # ***

      if self.divided_oneway_different:
         log.warning('')
         log_msg = (
            'No. county vs. road_characteristic one way differences: %d'
            % (len(self.divided_oneway_different),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for divided_oneway_tup in self.divided_oneway_different:
            log.warning(
               '%s oid: %7d / tis: %13s / 1_way: %2d / div1way: %2s'
               % ('Meh: divided_oneway differs:',
                  divided_oneway_tup[0],
                  divided_oneway_tup[1],
                  divided_oneway_tup[2],
                  divided_oneway_tup[3],))

      # ***

      if self.shoulder_paved_no_width:
         log.warning('')
         log_msg = (
            'No. paved shldr no width: %d'
            % (len(self.shoulder_paved_no_width),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for paved_shoulderless_tup in self.shoulder_paved_no_width:
            log.warning(
               'Paved shldr no width: oid: %7s / r: %s / l: %s'
               % (paved_shoulderless_tup[0],
                  paved_shoulderless_tup[1],
                  paved_shoulderless_tup[2],))

      # ***

      if self.shoulder_width_different:
         log.warning('')
         log_msg = (
            'No. right vs. left shoulder differences: %d'
            % (len(self.shoulder_width_different),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for shoulder_width_tup in self.shoulder_width_different:
            log.warning(
               'Diff. shoulder widths: oid: %7s / r: %s / l: %s / use: %s'
               % (shoulder_width_tup[0],
                  shoulder_width_tup[1],
                  shoulder_width_tup[2],
                  shoulder_width_tup[3],))

      # ***

      if self.shoulder_pavement_differs:
         log.warning('')
         log_msg = (
            'No. right vs. left shoulder-paved differences: %d'
            % (len(self.shoulder_pavement_differs),))
         log.warning('=' * len(log_msg))
         log.warning(log_msg)
         log.warning('=' * len(log_msg))
         for differs_tup in self.shoulder_pavement_differs:
            log.warning(
               '%s oid: %7s / r: %2s / l: %2s / rw: %s / lw: %s'
               % ('Diff. shldr paveds:',
                  differs_tup[0],
                  differs_tup[1],
                  differs_tup[2],
                  differs_tup[3],
                  differs_tup[4],))

      # ***

      log.debug('')

      stat_sql = "SELECT COUNT(objectid) FROM mndot_counties"
      rows = self.qb.db.sql(stat_sql)
      log.debug('Total no. of mndot_counties rows: %d' % (rows[0]['count'],))

      stat_sql = (
         """SELECT COUNT(objectid) FROM mndot_counties
            WHERE (ccp_stack_id IS NULL) AND (ccp_conflict IS NULL)""")
      rows = self.qb.db.sql(stat_sql)
      log.debug('Total no. of rows unprocessed or duplicate: %d'
                % (rows[0]['count'],))

      stat_sql = (
         """SELECT COUNT(objectid) FROM mndot_counties
            WHERE (ccp_stack_id IS NOT NULL) AND (ccp_conflict IS NULL)""")
      rows = self.qb.db.sql(stat_sql)
      log.debug('Total no. of new byways created: %d'
                % (rows[0]['count'],))

      stat_sql = (
         """SELECT COUNT(objectid) FROM mndot_counties
            WHERE (ccp_stack_id IS NULL) AND (ccp_conflict IS NOT NULL)""")
      rows = self.qb.db.sql(stat_sql)
      log.debug('Total no. of Cyclopath matches: %d'
                % (rows[0]['count'],))

      # ***

      log.debug('')

      if not self.where_clause_complete:
         where_clause_prefix = "WHERE"
      else:
         where_clause_prefix = self.where_clause_complete + " AND"

      stat_sql = ("SELECT COUNT(objectid) FROM mndot_counties %s"
                  % (self.where_clause_complete,))
      rows = self.qb.db.sql(stat_sql)
      log.debug('No. of mndot_counties rows considered for this import: %d'
                % (rows[0]['count'],))

      if not self.cli_opts.link_values_only:

         stat_sql = (
            """SELECT COUNT(objectid) FROM mndot_counties
               %s (ccp_stack_id IS NULL) AND (ccp_conflict IS NULL)
            """ % (where_clause_prefix,))
         rows = self.qb.db.sql(stat_sql)
         log.debug('No. rows not processed (duplicates) this import: %d'
                   % (rows[0]['count'],))

         stat_sql = (
            """SELECT COUNT(objectid) FROM mndot_counties
               %s (ccp_stack_id IS NOT NULL) AND (ccp_conflict IS NULL)
            """ % (where_clause_prefix,))
         rows = self.qb.db.sql(stat_sql)
         log.debug('No. of new byways created this import: %d'
                   % (rows[0]['count'],))

         stat_sql = (
            """SELECT COUNT(objectid) FROM mndot_counties
               %s (ccp_stack_id IS NULL) AND (ccp_conflict IS NOT NULL)
            """ % (where_clause_prefix,))
         rows = self.qb.db.sql(stat_sql)
         log.debug('No. of Cyclopath matches this import: %d'
                   % (rows[0]['count'],))

      if not self.cli_opts.line_segments_only:

         stat_sql = (
            """SELECT COUNT(*) FROM link_value AS lv
               JOIN item_versioned AS iv USING (system_id)
               JOIN mndot_counties AS mc
                  ON ((mc.ccp_stack_id = lv.stack_id)
                      OR (mc.ccp_conflict = lv.stack_id))
               WHERE
                  iv.valid_start_rid = %d
            """ % (self.qb.item_mgr.rid_new,))
         rows = self.qb.db.sql(stat_sql)
         log.debug('No. of new link_values created this import: %d'
                   % (rows[0]['count'],))

      log.debug('')

   # ***

   hausdorff_bucket_def = [
      (0,      '                     0 ',),
      (0.0001, '        0 -      .0001 ',),
      (0.0005, '    .0001 -      .0005 ',),
      (0.0010, '    .0005 -      .0010 ',),
      (0.0100, '    .001  -      .010  ',),
      (0.1000, '   0.01   -     0.10   ',),
      (0.25,   '   0.10   -     0.25   ',),
      (1.0,    '   0.25   -     1.0    ',),
      (2.0,    '   1      -     2      ',),
      (5.0,    '   2      -     5      ',),
      (10.0,   '   5      -    10      ',),
      (100.0,  '  10      -   100      ',),
      (250.0,  ' 100      -   250      ',),
      (1000.0, ' 250      -  1000      ',),
      (-1,     '            >1000.0    ',),
      ]

   #
   def hausdorff_bucket_add(self, hausdorff_bucket, hausdorff_dist):

      hausdorff_dist_str = Statewide_MnDOT_Import.hausdorff_bucket_def[-1][1]
      for bdef in Statewide_MnDOT_Import.hausdorff_bucket_def:
         if hausdorff_dist <= bdef[0]:
            hausdorff_dist_str = bdef[1]
            break
      misc.dict_count_inc(hausdorff_bucket, hausdorff_dist_str)

   #
   def hausdorff_bucket_show(self, hausdorff_bucket, msg):

      printed_header = False

      for bdef in Statewide_MnDOT_Import.hausdorff_bucket_def:
         try:
            dist_cnt = hausdorff_bucket[bdef[1]]
            if dist_cnt > 0:
               if not printed_header:
                  log.debug('')
                  log_msg = ('Hausdorff distance distribution: %s' % (msg,))
                  log.debug('=' * len(log_msg))
                  log.debug(log_msg)
                  log.debug('=' * len(log_msg))
                  printed_header = True
               log.debug('*** dist_val: %s / dist_cnt: %d'
                         % (bdef[1], dist_cnt,))
         except KeyError:
            pass

   # ***

# HRM...
   mndot_lines_sql = (
      """
      SELECT

         /* mndot_counties */
         mc.mndot_counties_id
         , mc.divided_roadway
         , mc.begm
         , mc.objectid
         , mc.tis_directional
         , mc.cnty_code
         , mc.geometry
         , mc.endm
         , mc.tis_code
         , mc.beg_node_pt
         , mc.ccp_conflict
         , mc.ccp_stack_id
         , mc.str_name
         --, mc.mndot_road_char_id
         , mc.fin_node_pt
         , mc.rte_syst
         , mc.traffic_direction

         /* mndot_road_char */
         , mrc.mndot_road_char_id
         --, mrc.objectid AS mrc_objectid
         , mrc.tis_id
         , mrc.directional_tis_id
         , mrc.from_true_miles
         , mrc.to_true_miles
         , mrc.route_system_code
         , mrc.route_system_name
         , mrc.route_system_abbreviation
         , mrc.divided_oneway_code
         , mrc.divided_oneway
         , mrc.dir_travel_on_segment_code
         , mrc.direction_travel_on_segment
         , mrc.functional_classification_code
         , mrc.functional_classification
         , mrc.surface_type_code
         , mrc.surface_type
         , mrc.surface_width
         , mrc.right_shoulder_type_code
         , mrc.right_shoulder_type
         , mrc.right_shoulder_width
         , mrc.left_shoulder_type_code
         , mrc.left_shoulder_type
         , mrc.left_shoulder_width
         , mrc.number_of_lanes_im
         , mrc.number_of_lanes_dm
         , mrc.total_number_of_lanes
         , mrc.control_of_access_code
         , mrc.control_of_access
         , mrc.geometry

      FROM mndot_counties AS mc

   -- LEFT OUTER JOIN instead?
      JOIN mndot_road_char AS mrc
         ON (mrc.tis_id = mc.tis_code
             AND ST_Intersects(mc.geometry, mrc.geometry))

      LEFT OUTER JOIN mndot_vol_aadt AS mva
         ON (mva.route_ident = mc.tis_code
             AND ST_Intersects(mc.geometry, mva.geometry))

      LEFT OUTER JOIN mndot_vol_hcaadt AS mvh
         ON (mvh.route_ident = mc.tis_code
             AND ST_Intersects(mc.geometry, mvh.geometry))
      """)

   # ***

# ***

if (__name__ == '__main__'):
   smndoti = Statewide_MnDOT_Import()
   smndoti.go()


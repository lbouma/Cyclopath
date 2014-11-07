#!/usr/bin/python

# Copyright (c) 2006-2014 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ ./hausdorff_import.py --help
#
# For a good example, see:
#
#  /ccp/dev/cp/scripts/setupcp/greatermn/fix_statewide_import.sh

# This script can be used to import Shapefiles that have been
# edited by an external editor, such as OpenJUMP. The Shapefile
# uses a special field/attribute to specify how to process each
# feature, which might be an existing Cyclopath geofeature. You
# can ignore features, add them as new geofeatures, update the
# existing geofeature's attributes or geometry, or try to conflate
# features without a Cyclopath connection.

# Note: The scripts/setupcp/greatermn/statewide_mndot_import.py
#       script was written last Fall and uses PostGIS's
#       ST_HausdorffDistance. PostGIS says it calculates "the
#       'Discrete Hausdorff Distance'. This is the Hausdorff distance
#       restricted to discrete points for one of the geometries." The docs
#       also say, "This algorithm is NOT equivalent to the standard Hausdorff
#       distance. However, it computes an approximation that is correct for
#       a large subset of useful cases. One important part of this subset is
#       Linestrings that are roughly parallel to each other, and roughly equal
#       in length. This is a useful metric for line matching." This author's
#       [lb's] experience has shown the PostGIS implementation is pretty good.
#       Nonetheless, if you want to compute the Hausdorff without invoking
#       PostGIS, see pyserver/util_/geometry.py::hausdorff_distance.


# FIXME: After running script, verify these:
#        2903774



# FIXME: MORE IDEAS:
#        1. Short line lens
#        1a. lots of dangles;
#        1b. lots of split intersection errors, e.g.,
#        split intersection, maybe (
#                 b1
#           --a1--|--a2--c1--
#                 d1
#        where a,b,c,d are unique street names and a2 is a tiny
#        segment after the intersection: obviously, it should be
#        c1, so some split tool split a0 into a1 and a2
#        when the a0-c1 and b1-d1 intersection was made.
#        1c. I've even found a bicycle trail intersection (a,b,c,d all
#        trails) where a2 is a tiny road segment (with no name, like the
#        trail segments)
"""
Time: 1.621 ms
ccpv3_lite=> select * from _by where stk_id = 1476966;
 sys_id | brn_id  | stk_id  | v | del | rvt | nom | start_rid | until_rid  | acs | infer | len | spl_fr | gfl_id |  z  | dd | beg_nd  | fin_nd  
--------+---------+---------+---+-----+-----+-----+-----------+------------+-----+-------+-----+--------+--------+-----+----+---------+---------
 210063 | 2500677 | 1476966 | 1 | f   | f   |     |     11095 | 2000000000 |   8 | 0x20  | .4  |        |     11 | 134 |  0 | 1476967 | 1476950
(1 row)

Time: 22.329 ms
ccpv3_lite=> select * from _rev where id in (11095);
  id   |    timestamp     |     host      |  user   |      comment       | bbox_perim | gsum_perim | geom_perim |  br_id  | rvtok | rvtct | lcktm | alrt 
-------+------------------+---------------+---------+--------------------+------------+------------+------------+---------+-------+-------+-------+------
 11095 | 2010-02-20 09:00 | 71.195.26.124 | vlang29 | hopkins bike paths | 4906.6     | 7002.9     | 10796.1    | 2500677 | t     |     0 |       | t
(1 row)
"""
#        2. Dangles
#        3. Intersection opportunities


# FIXME: Include Rev edits in export (and editors names?)
#        E.g., rev 6723 has some weird artifacts, like a 1/2 meter bike trail
#        jutting off a road intersection for no reason.
#
#ccpv3_lite=> select * from _rev where id in (6723);
#  id  |    timestamp     |    host     | user  | comment | bbox_perim | gsum_perim | #geom_perim |  br_id  | rvtok | rvtct | lcktm | alrt 
#------+------------------+-------------+-------+---------+------------+------------+------------+---------+-------+-------+-------+------
# 6723 | 2009-03-30 07:50 | 63.97.12.50 | wafer |         | 4409.4     | 5637.8     | 5574.5     | 2500677 | t     |     0 |       | t
#(1 row)
#
#
#

script_name = ('Another Cyclopath Import Script')
script_version = '1.0'

__version__ = script_version
__author__ = 'Landon Bouma <cyclopath@retrosoft.com>'
__date__ = '2014-03-10'


# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../util'
                   % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# *** Module globals
# FIXME: Make sure this always comes before other Ccp imports
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('hausdorff_import')

# ***

try:
   from collections import OrderedDict
except ImportError:
   # Python 2.6 or earlier, use backport.
   #  See: easy_install --prefix=/ccp/opt/usr ordereddict
   from ordereddict import OrderedDict
import copy
import datetime
from decimal import Decimal
import fcntl
import fiona
import glob
import Levenshtein
import networkx
import pprint
import re
import time
import traceback
import uuid

# Haha, Fiona is the first library [lb] has seen hook into
# the Python logging framework. Wicked! But it's DEBUG is
# very VERBOSE, especially when iterating over features.
g.log.getLogger('Fiona').setLevel(logging.INFO)

from grax.access_infer import Access_Infer
from grax.access_level import Access_Level
from grax.access_style import Access_Style
#from grax.grac_manager import Grac_Manager
from item import attachment
from item import geofeature
from item import item_base
from item import item_revisionless
from item import item_stack
from item import item_user_access
from item import item_versioned
#from item import item_user_access
from item import link_value
from item.attc import annotation
from item.attc import attribute
from item.attc import tag
from item.feat import byway
from item.feat import region
from item.feat import terrain
from item.feat import waypoint
#from item.feat import node_endpoint
from item.grac import group
from item.grac import group_item_access
from item.link import link_attribute
from item.util import item_factory
from item.util import revision
from item.util.item_type import Item_Type
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.inflector import Inflector
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base
from util_.shapefile_wrapper import ojint
from util_.shapefile_wrapper import ojints
from util_.streetaddress import addressconf
from util_.streetaddress import streetaddress

# *** Debug switches

# FIXME: Just debugging.

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 3
#debug_prog_log.debug_break_loop_cnt = 10
#debug_prog_log.debug_break_loop_cnt = 100
#debug_prog_log.debug_break_loop_cnt = 1000
#debug_prog_log.debug_break_loop_cnt = 10000

debug_prog_log_setup = Debug_Progress_Logger(copy_this=debug_prog_log)
debug_prog_log_match = Debug_Progress_Logger(copy_this=debug_prog_log)
#debug_prog_log_match.debug_break_loops = False
#debug_prog_log_match.debug_break_loops = True
#debug_prog_log_match.debug_break_loop_cnt = 1
#debug_prog_log_match.debug_break_loop_cnt = 3

debug_skip_commit = False
#debug_skip_commit = True

#debug_writerecords_1x1 = False
# Writing to the Shapefile one-by-one isn't that much slower than
# a bulk write, and it lets us display progress and handle errors
# easier (such as what an item's schema doesn't match the target
# file, on bulk write, you don't know which item causes the error).
debug_writerecords_1x1 = True

# If you try to make a big, million feature list, you'll be fine
# until you run out of memory.
debug_group_shp_writes = False
#debug_group_shp_writes = True

debug_filter_sids = None
#debug_filter_sids = set([1044560, 2835656,])
#debug_filter_sids = set([2917226, 1062928,])
#debug_filter_sids = set([1579789, 3108710,])
#debug_filter_sids = set([1579333,])
#debug_filter_sids = set([2853074,])
#debug_filter_sids = set([2864869,])
# What happened to Hennepin? Aha- Wrong Item Type Id in GIA.
#debug_filter_sids = set([1115523, 2838711, 2842326,])
# Now link_value lhs/rhs item types need fixing (well, setting).
#debug_filter_sids = set([2853074,])
#debug_filter_sids = set([1446205,])
#debug_filter_sids = set([1446138,])
#debug_filter_sids = set([1126405,])
#debug_filter_sids = set([4110337,])
#debug_filter_sids = set([4110788,])

# Ex. for rpdb: b /ccp/dev/cycloplan_test/scripts/setupcp/geofeature_io.py:4866

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_prog_log_setup.debug_break_loops
                     or debug_prog_log_match.debug_break_loops
                     or debug_skip_commit
                     # Skipping: debug_writerecords_1x1
                     # Skipping: debug_group_shp_writes
                     or debug_filter_sids
                     )

if debugging_enabled:
   log.warning('****************************************')
   log.warning('*                                      *')
   log.warning('*      WARNING: debugging_enabled      *')
   log.warning('*                                      *')
   log.warning('****************************************')

# *** Cli arg. parser

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)
      #
      self.groups_none_use_public = True

   #
   def prepare(self):

      Ccp_Script_Args.prepare(self)

      # Actions to perform.

      # *** First, build the Hausdorff cache and make intermediate Shapefiles.

      self.add_argument('--init-importer', '--pre-process',
          dest='init_importer', action='store_true', default=False,
         help='load source Shapefile(s) into cache')

      # Shapefile input file.
      #
      # (Note: this could probably be any type of valid input file
      #  that Fiona supports, like GeoJSON, but for most practical
      #  uses, you'll be supplying a Shapefile. Also, the binary
      #  Shapefile is apparently quicker to process than a GeoJSON
      #  file... but we'll be doing most of our processing in memory
      #  or using psql, so I can't imagine a very noticeable difference
      #  in the type of source file format).

      # OpenJUMP doesn't filter layers very well, so it's easier to work with
      # multiple Shapefiles, each as their own layer. This script will consume
      # all source Shapefiles first, before doing any work, to assemble the
      # whole map.
      self.add_argument('--source-dir', dest='source_dir',
         action='store', type=str, required=False,
         help='/path/to/your/source/shapefiles/ which contains Source/')

      # If you've already imported data and accidentally made duplicates, tell
      # the script how to distinguish the older items from the newer ones.
      self.add_argument('--first-suspect', dest='first_suspect',
         action='store', type=int, default=0,
         help='the first Cyclopath Stack ID of the newly imported items')
      self.add_argument('--final-suspect', dest='final_suspect',
         action='store', type=int, default=0,
         help=
       'the final Cyclopath Stack ID of the possibly duplicate imported items')
      # MAYBE: We could also filter by revision_id, but then we'd have to edit
      #        the Shapefile export script to dump the items version=1
      #        valid_start_rid into the export.
      # MAYBE: We could also indicate new features somehow in the input file,
      #        and make the hausdorff_cache that way.

      # Specify a known x,y point in the network to help locate disjoint
      # subgraphs.
      self.add_argument('--known-point-xy', dest='known_pt_xy',
         #action='append', default=[], nargs=2,
         action='append',
         # This is a point for Mpls-St. Paul/Minnesota.
         #default=[480292.5, 4980909.8,],
         default=[conf.known_node_pt_x, conf.known_node_pt_y,],
         nargs=2,
         help='a point on the connected tree; used to find disjoint islands')

      # TODO: Delete this feature: this is a hack to accomodate some
      #       date problems I created.
      self.add_argument('--fix-silent-delete-issue',
         dest='fix_silent_delete_issue', action='store_true',
         default=False, help=
           'when new item OPERATION set to old item but old OPERATION empty')

      self.add_argument('--use-old-stack-IDs-when-possible',
         dest='use_old_stack_IDs_when_possible',
         action='store_true', default=False, help=
           "when two items are marked duplicates, used older item's stack ID")

      # *** Second, preprocess items and create intermediate Shapefiles.

      # For line segments, try matching items without a Cyclopath association
      # to existing byways.
      #
      # You can run --init-importer and --try-matching iteratively
      # before running --process-edits to clean up the data and
      # make changes to this script.

      self.add_argument('--try-matching', dest='try_matching',
         action='store_true', default=False,
         help='search cache for duplicate items (using Hausdorff, etc.)')

      self.add_argument('--buffer-threshold', dest='buffer_threshold',
         action='store', type=float,
         #default=4.0, # 90457 match pairs, 296937 result features.
# FIXME: Test these...
         #default=6.0,
         default=10.0,
         help='line segments within these many meters will be hausdorffed')

      self.add_argument('--fragment-minimum', dest='fragment_minimum',
         action='store', type=float,
         #default=5,
         #default=10,
         default=4,
         help='Fragments shorter than this cannot be trusted')

      self.add_argument('--fragment-hausdorff-maximum', dest='frag_haus_max',
         action='store', type=float,
         #default=5,
         default=10,
         help=
            'Hausdorff dist for frags less than this may indicate duplicates')
      #
      self.add_argument('--fragment-hausdorff-lenient',
         dest='frag_haus_lenient', action='store', type=float,
         #default=20,
         default=30,
         help='Like --fragment-hausdorff-maximum, but for strong addy matches')

      self.add_argument('--show-conflations', dest='show_conflations',
         action='store_true', default=False,
         help='include features for each pair of conflated segments')

      # The fragments Shapefiles can be, e.g., ten times larger than the
      # everylayer Shapefile, so it's opt-in.
      self.add_argument('--show-fragments', dest='show_fragments',
         action='store_true', default=False,
         help='make fragment geometry Shapefile that shows matching decisions')

      # *** Third, lock down the revision table.

      # See: Ccp_Script_Args' --instance-master

      self.add_argument('--revision-user', dest='revision_user',
         action='store', type=str, required=False, default='',
         help='the username for the revision table; anon user if not set')

      # *** Fourth, split the import across multiple cores by using
      #     --instance-worker, --items-limit, and --items-offset,
      #     and calling either of these two commands.

      # Process edited items. This might be adding new ones, or editing or
      # deleting existing items.

      self.add_argument('--process-edits', dest='process_edits',
         action='store_true', default=False,
         help='search cache for and process edited features/items')

      self.add_argument('--fix-gravel-unpaved-issue',
         dest='fix_gravel_unpaved_issue', action='store_true', default=False,
         help='remove erroneous gravel and unpaved tags from suspects')

      self.add_argument('--merge-names', dest='merge_names',
         action='store_true', default=False,
         help='intelligently combine street names when merging items')

      self.add_argument('--friendly-names', dest='friendly_names',
         action='store_true', default=False,
         help='convert DOT classifs to friendly names (e.g., MNTH->State Hwy')

      # BUG nnnn: --last-edited-* is not used: Does OpenJUMP support this?
      # If you don't want to check every item to see if it's been
      # edited, you can do it smartly using a timestamp field.
      #
      self.add_argument('--last-edited-attr', dest='last_edited_attr',
         action='store', type=str, default='',
         help='name of the last-edited attribute (improves performance)')
      self.add_argument('--last-edited-date', dest='last_edited_date',
         action='store', type=str, default='',
         help='assume feat unedited unless last-edited on or after this date')

      self.add_argument('--check-everything', dest='check_everything',
         action='store_true', default=False,
         help='check all in Shapefile and not just feats with Operation')

      self.add_argument('--checkout-revision', dest='checkout_revision',
         action='store', type=int, default=None,
         help='for testing, revision at which to checkout (default: latest)')

      # *** Miscellaneous.

      self.add_argument('--shapefile-srid', dest='shapefile_srid',
         action='store', type=int, default=26915,
         help='Shapefile srid to use to make crs')

      self.add_argument('--shapefile-driver', dest='shapefile_driver',
         action='store', type=str, default='ESRI Shapefile',
         help='Shapefile driver to use')

      # *** Import/Export the other geofeature types.

      self.add_argument('--import', dest='do_import',
         action='store_true', default=False,
         help='import items from preprocessed Shapefile')

      self.add_argument('--export', dest='do_export',
         action='store_true', default=False,
         help='export items to Shapefile')
      # FIXME/BUG nnnn: Speed up vector checkout by eliminating link_values
      #      APRIL2014     from flashclient; keep them in the database and
      #                    use them on commit, and maybe at other times, but
      #                    limit their use in flashclient to try to speed up
      #                    checkout and rendering and to reduce resource usage.
      #                 Option A:
      #                   1. When exporting to Shapefile, option to also create
      #                      and populate item cache tables.
      #                   2. On commit and elesewhere, keep cache table in sync
      #                      with item data.
      #                   3. Use cache table to send public geometry,
      #                      attributes, and link_value values, etc., to
      #                      clients.
      #                 Option B:
      #                   1. Remake the geofeature columns for the byway
      #                      attributes (speed limit, etc.) and also make
      #                      a tagged column (e.g., comma-separated text).
      #                   2. Get link_values for commit, but otherwise
      #                      let client refer to attributes by name and not
      #                      worry about their stack_ids or permissions, etc.
      # FIXME/APRIL2014: For now, make sure flashclient isn't lazy-loading
      #                  heavyweight link_values when in viewing mode.

      self.add_argument('--item-type', dest='item_type',
         action='store', type=str, required=False, default='byway',
         help='type of item to import or export, if it cannot be discerned',
         choices=('byway', 'region', 'terrain', 'waypoint',))

      self.add_argument('--update-geosummary', dest='update_geomsummary',
         action='store_true', default=False,
         help='call revision.Revision.geosummary_update; skip for big edits')

      self.add_argument('--import-fix-mndot-polies',
         dest='import_fix_mndot_polies', action='store_true', default=False,
         help='convert COUNTYNAME/MUNI_NAME/TWP_NAME it CCP_NAME')

# FIXME: APRIL2014: For re-conflating the State import data, we
#        need to indicate the rids around the import, so we can
#        ignore items we've edited since the import (since we can
#        assume an edited item is considered audited and we don't
#        have to try conflating it).
#        Perhaps, e.g.,
#         --first-suspect ==> --beg-conflation-rid / --fin-conflation-rid
#        And/Or, e.g., 
#         --first-suspect ==> --first-suspect / --final-suspect
#        I.e., caller can specify an rid window or a stack ID window.
#        Whatever items were created during the rid window, or
#        whatever items' stack IDs fall in the stack ID window,
#        are suspect, except those that have been edited since
#        the window closed.
   
   #
   def verify_handler(self):

      ok = Ccp_Script_Args.verify_handler(self)

      num_actions = (0
         + (1 if self.cli_opts.init_importer else 0)
         + (1 if self.cli_opts.instance_master else 0)
         + (1 if self.cli_opts.try_matching else 0)
         + (1 if self.cli_opts.process_edits else 0)
         + (1 if self.cli_opts.do_import else 0)
         + (1 if self.cli_opts.do_export else 0)
         )
      if num_actions != 1:
         actions = ['--init-importer',
                    '--instance-master',
                    '--try-matching',
                    '--process-edits',
                    '--import',
                    '--export',
                    ]
         log.error('Please specify one of %s' % (', '.join(actions),))
         ok = False

      if not self.cli_opts.init_importer:
         self.master_worker_expected = True

      if not self.cli_opts.instance_master:
         if not self.cli_opts.source_dir:
            log.error('Please specify --source-dir with this action')
            ok = False
         elif ((not self.cli_opts.do_export)
               and (not os.path.exists(self.cli_opts.source_dir))):
            log.error('The --source-dir was not found: %s'
                      % (self.cli_opts.source_dir,))
            ok = False

      if self.cli_opts.last_edited_attr:
         if not self.cli_opts.last_edited_date:
            log.error('Specify --last-edited-date w/ --last-edited-attr')
            ok = False
         else:
            try:
               # E.g., time.strptime('14 Mar 2014', '%d %b %Y')
               self.cli_opts.last_edited_date = time.mktime(
                  time.strptime(self.cli_opts.last_edited_date, '%d %b %Y'))
            except ValueError:
               log.error('Last edited date should be, e.g., "14 Mar 2014".')
               ok = False

      if ( ((   (self.cli_opts.item_type != 'byway')
             or (not self.cli_opts.init_importer))
            and (   #self.cli_opts.known_pt_xy or
                    self.cli_opts.fix_silent_delete_issue
                 or self.cli_opts.use_old_stack_IDs_when_possible))
          or ((   (self.cli_opts.item_type != 'byway')
               or (not self.cli_opts.try_matching))
              and (   self.cli_opts.show_conflations
                   or self.cli_opts.show_fragments))
          or ((   (self.cli_opts.item_type != 'byway')
               or (not self.cli_opts.process_edits))
              and (   self.cli_opts.friendly_names))
            ):
            log.error('Incompatible cli switches. See --help')
            ok = False

      return ok

# *** Hausdorff_Import

class Hausdorff_Import(Ccp_Script_Base):

   __slots__ = (
      # We collect stats for the curious developer.
      'stats', 
      # We symlink to the latest output Shapefiles (so that we don't
      # overwrite previous output).
      'target_path',
      #
      'target_schema',
      'intermed_feats',
      'slayers', # Shapefile layers, i.e., one layer == one shapefile
      'everylayer', # The Everylayer is a copy of all other layers,
                    # too make searching for items by stack ID easy
                    # (in OpenJUMP, you search *per layer*, but you
                    # don't know what layer a random stack ID is in).
      # During preprocessing, we count the number of times each unique stack ID
      # is referenced so that we know which geofeatures we'll be splitting in
      # twain. We use this information to tweak the feature when we write it to
      # the intermediate shapefile, so that we can later save to the Cyclopath
      # database using a multi-processor-aware approach.
      'sid_use_count',
      'sid_use_noops',
      'sid_del_count',
      'sid_del_lists',
      'recorded_sids', # Stack IDs we've writ to the target Shapefiles.


# FIXME: Rename: CCP_FROMS_ ==> OTHERS_IDS
# FIXME: Rename: DELETE_ ==> OPERATION,
#                 and change the meaning of Y and N to D and U,
#                 as in, CRUD.
#
#
#
      # A lookup of stack ID to OPERATION indication. This also includes
      # CCP_FROMS_ since CCP_FROMS_ is just like OPERATION with stack IDs.
      # FIXME: Remove CCP_FROMS_?
      'sid_delete_froms', # Stack IDs mentioned by OPERATION and CCP_FROMS_.
      # As part of preprocessing, we look for disjoint trees in the forest.
      'the_forest', # All nodes, regardless of controlled access.
      'sub_forest', # Only uncontrolled access roads.
      'favorite_tree', # The best connected (most nodes) tree in the forest.
      # To help with matching, we distinguish real Expressway Ramps from those
      # that don't actually connect to an Expressway.
      'expressway_endpts',
      #
      # Used by the workers.
      'hydrated_items',
      'processed_sids',
      'problem_items',
      'analyzed_sids',
      'create_feats',
      'update_feats',
      'create_lvals',
      'update_lvals',
      'delete_nodes_for',
      'insert_brats',
      'brats_dbldict',
      'insert_aadts',
      'aadts_dbldict',
      #
      'attr_to_field',
      'field_attr_cache_name',
      'field_attr_cache_sid',
      'bad_tag_sids',
      #
      'mndot_geom',
      'mndot_region',
      'ccp_region',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      #
      self.stats = {}
      #
      self.target_path = None
      #
      self.target_schema = None
      self.intermed_feats = None
      self.slayers = None
      self.everylayer = None
      self.sid_use_count = None
      self.sid_use_noops = None
      self.sid_del_count = None
      self.sid_del_lists = None
      self.recorded_sids = None
      self.sid_delete_froms = None
      self.the_forest = None
      self.sub_forest = None
      self.favorite_tree = None
      self.expressway_endpts = None
      #
      self.hydrated_items = None
      self.processed_sids = None
      self.problem_items = None
      self.analyzed_sids = None
      self.create_feats = None
      self.update_feats = None
      self.create_lvals = None
      self.update_lvals = None
      self.delete_nodes_for = None
      self.insert_brats = None
      self.brats_dbldict = None
      self.insert_aadts = None
      self.aadts_dbldict = None
      #
      self.attr_to_field = None
      self.field_attr_cache_name = None
      self.field_attr_cache_sid = None
      self.bad_tag_sids = None
      #
      self.mndot_geom = None
      self.mndot_region = None
      self.ccp_region = None

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      # Skipping: Ccp_Script_Base.go_main(self)

      do_commit = False

      try:

         if self.cli_opts.init_importer:
            self.init_importer()
         else:
            self.setup_importer()
            if self.cli_opts.instance_master:
               self.instance_master()
            else:
               if self.cli_opts.try_matching:
                  g.assurt(self.cli_opts.item_type == 'byway')
                  self.try_matching()
               elif (self.cli_opts.process_edits
                     or self.cli_opts.do_import):
                  self.process_edits()
               elif self.cli_opts.do_export:
                  self.do_export_non_byway()
               else:
                  g.assurt(False)

         if debug_skip_commit:
            raise Exception('DEBUG: Skipping commit: Debugging')
         do_commit = True

      except Exception, e:

         # FIXME: g.assurt()s that are caught here have empty msgs?
         log.error('Exception!: "%s" / %s' % (str(e), traceback.format_exc(),))

      finally:

         self.cli_args.close_query(do_commit)

   #
   # *** Initial setup phase.
   #

   #
   def init_importer(self):

      self.stats_init_initer()

      if self.cli_opts.item_type == 'byway':
         self.init_cache_tables()

      self.consume_source_shps()

      if self.cli_opts.item_type == 'byway':
         # TODO: gf_type_bucket='controlled', to fix freeways...
         self.match_cache_populate(gf_type_bucket='shared_use')

      self.stats_show_initer()

   #
   def init_cache_tables(self):

      log.info('Dropping view maybe: hausdorff_cache.')
      drop_sql = "DROP VIEW IF EXISTS _hm"
      self.qb.db.sql(drop_sql)

      log.info('Dropping view maybe: hausdorff_cache.')
      drop_sql = "DROP VIEW IF EXISTS _hm2"
      self.qb.db.sql(drop_sql)

      log.info('Dropping table maybe: hausdorff_cache.')
      drop_sql = "DROP TABLE IF EXISTS hausdorff_cache"
      self.qb.db.sql(drop_sql)

      log.info('Creating table certainly: hausdorff_cache.')
      create_sql = (
         """
         CREATE TABLE hausdorff_cache (

            /* MAYBE: Use a branch ID? Or is the cache
                      always just created, processed,
                      and then dumped?
              branch_id INTEGER NOT NULL */

              stack_id INTEGER NOT NULL
            , name TEXT
            , gf_lyr_nom TEXT
            , gf_lyr_id INTEGER
            , gf_lyr_bucket TEXT
            , match_cmd TEXT
            , one_way INTEGER
            , well_connected BOOLEAN
            , nneighbr_1 INTEGER
            , nneighbr_n INTEGER
            )
         """)
      self.qb.db.sql(create_sql)

      table_name = 'hausdorff_cache'
      geometry_col = 'geometry'
      dimension = 2
      addgeom_sql = (
         """
         SELECT AddGeometryColumn('%s', '%s', %d, 'LINESTRING', %d)
         """ % (table_name, geometry_col, conf.default_srid, dimension,))
      self.qb.db.sql(addgeom_sql)

   #

   # https://en.wikipedia.org/wiki/Connectivity_%28graph_theory%29
   #
   # The main Cyclopath tree in the forest is considered the connected tree.
   # All other disjoint trees' features are considered, well, disjoint.
   byway_00_tree_type = set([
      'connected',
      'sovereign',
      ])
   byway_01_geof_type = set([
      'segregated',
      'shared_use',
      'controlled',
      'transition', # Verified Expressway Ramp.
      'fifth_hand',
      ])
   byway_02_guidance = set([
      'update', # A feature the user has marked as keeping/updating
                # and doesn't need to be matched against other items
                # (though other items might be matched against it).
      'repeat', # Basically an 'update', but when CCP_FROMS_ is set;
                #  really just used for auditing the import process.
      'delete', # A user can mark a feature deleted, and we'll mark features
                # deleted during preprocesssing. While applying edits,
                # features marked delete will have their corresponding
                # Cyclopath items marked delete.
      'donate', # A line marked as a duplicate as other lines, where the
                # user wants us to programmatically determine the matching
                # lines. We can be a lot more confident about a donated line's
                # matches since the user told us the donated line must go.
      'reject', # A donation for which we cannot find matches; user must fix.
      'ignore', # Deleted freshies marked deleted are ignored, since they don't
                # exist in Cyclopath; and deleted split-froms that have one
                # or more siblings not deleted are marked 'ignore', since the
                # stack ID lives on.
      'nogeom', # This problem is so serious it deserves its own category.
      'noring', # Ditto.
                #
      # 'detain', # During the design phase, an option to quarantine items
      #         # was introducted. These items would be temporarily deleted
      #         # from Cyclopath, and then someone would clean up the data
      #         # using Shapefiles and finally re-import the clean data.
      #         # However, the problem data is just disconected byways --
      #         # those that screw up the geocoder (finding points in the
      #         # network) and that screw up the route finder (finding edges
      #         # between points) -- and we've since introduce the geofeature
      #         # attribute, is_disconnected, so we don't need this option
      #         # to solve that problem.
      ])
   # # Network analysis states:
   # layer_02_analysis = set([
   #    'pending', # waiting for Hausdorff et al
   #    'no_match',
   #    'no_haus',
   #    'too_short',
   #    'good_haus',
   #    'good_frag',
   #    'poor_haus',
   #    'couplet',
   #    'same_endpts',
   #    'undeadended_old',
   #    'undeadended_new',
   #    'extendeadend_old',
   #    'extendeadend_new',
   #    'deadends_same_len',
   #    ])

   intermediate_fields_byway = [
      #  1234567890
      (u'GUIDANCE', 'str',),
      (u'OPERATION', 'str',),
      (u'CCP_ID', 'int:9',),
      (u'CCP_NAME', 'str',),
      (u'gf_lyr_id', 'int:9',),
      (u'gf_lyr_nom', 'str',),
      (u'CCP_FROMS_', 'str',),
      (u'import_err', 'str',),
      (u'speedlimit', 'int:9',),
      (u'lane_count', 'int:9',),
      (u'item_tags', 'str',),
      (u'z_level', 'int:9',),
      (u'one_way', 'int:9',),
      (u'out_ln_wid', 'int:9',),
      (u'shld_width', 'int:9',),
      (u'bike_facil', 'str',),
      (u'cautionary', 'str',),
      #
      (u'wconnected', 'str',),
      (u'wangdangle', 'str',),
      (u'nneighbr_1', 'int:9',),
      (u'nneighbr_n', 'int:9',),
      (u'gfl_typish', 'str',),
      #
      (u'CCP_SYS', 'int:9',),
      (u'CCP_VERS', 'int:9',),
      (u'new_length', 'float:19.11',),
      #
      #(u'OBJECTID', 'int:9',),

      # Deprecated:
      #(u'ACTION_', 'str',),
      #(u'CONTEXT_', 'str',),
      ]

   intermediate_schema_byway = {
      'geometry': 'LineString',
      'properties': OrderedDict(intermediate_fields_byway),
      }

   # MAYBE: Move all these item-specific pieces of data to the appropriate
   #        item classes? For now, to make editing this file easier, [lb]
   #        is keeping everything here.
   # MAYBE: Are more item-specific lookups really necessary?
   region_00_tree_type = set([
      # Skipping: state/province/administrative district and beyond
      'county',
      'township',
      'city', # municipality
      'neighborhood',
      'yogabbagabba', # everything else
      'non-byway', # also everything else, e.g., non-byway, for shapefiles not
                   # originally exported from Cyclopath (so no item_tags field
                   # with which to discern the layer name).
      ])
   #region_01_geof_type = set([
   #   ])
   # We at least need a Shapefile definition for each item type.
   intermediate_fields_non_byway = [
      (u'GUIDANCE', 'str',),
      (u'OPERATION', 'str',),
      (u'CCP_ID', 'int:9',),
      (u'CCP_NAME', 'str',),
      (u'gf_lyr_id', 'int:9',),
      (u'gf_lyr_nom', 'str',),
      (u'CCP_FROMS_', 'str',),
      (u'import_err', 'str',),
      (u'item_tags', 'str',),
      (u'z_level', 'int:9',),
      (u'gfl_typish', 'str',),
      (u'CCP_SYS', 'int:9',),
      (u'CCP_VERS', 'int:9',),
      (u'AREA', 'float:19.11',),
      (u'PERIMETER', 'float:19.11',),
      (u'POPULATION', 'int:9',),
      #(u'OBJECTID', 'int:9',),
# missing a few...

# {'geometry': {'type': 'Polygon', 'coordinates': [[(222512.76, 5050709.15), (221708.37, 5050747.78), (221726.82, 5051153.33), (221732.2, 5051553.23), (222539.39, 5051515.79), (222534.78, 5051114.33), (222512.76, 5050709.15)]]}, 'type': 'Feature', 'id': '0', 'properties': OrderedDict([(u'AREA', 651350.6103), (u'PERIMETER', 3226.5449), (u'MUN_', 1.0), (u'MUN_ID', 328.0), (u'MUNI_NAME', u'Barry'), (u'FIPS', u'03718'), (u'MCD', u'0210'), (u'POPULATION', 25)])}


      ]
   intermediate_schema_non_byway = {
      'geometry': 'SET_ME_BUDDY',
      'properties': OrderedDict(intermediate_fields_non_byway),
      }

   # ***

   #
   def consume_source_shps(self):

      self.sid_use_count = {}
      self.sid_use_noops = {}
      self.sid_del_count = {}
      self.sid_del_lists = {}
      self.sid_delete_froms = set()
      self.the_forest = networkx.Graph()
      self.sub_forest = networkx.Graph()
      self.expressway_endpts = set()
      #
      self.mndot_geom = {}
      self.mndot_geom['city'] = {}
      self.mndot_geom['township'] = {}
      self.mndot_region = {}
      self.mndot_region['city'] = {}
      self.mndot_region['township'] = {}
      self.ccp_region = {}
      self.ccp_region['city'] = {}
      self.ccp_region['township'] = {}

      source_files = self.get_source_files('Source')

      common_crs = None
      for source_shp in source_files:
         try:
            log.info('Preprocessing Shapefile: %s'
                     % (os.path.basename(source_shp),))
            with fiona.open(source_shp, 'r') as source_data:
               if len(source_data) == 0:
                  log.warning('Skipping empty Shapefile: %s' % (source_shp,))
               else:
                  common_crs = self.preprocess_source_shp_feats(
                                          source_data, common_crs)
                  if self.cli_opts.item_type == 'byway':
                     self.preprocess_source_build_network(source_data)
                  elif self.cli_opts.item_type == 'region':
                     self.preprocess_source_regions(source_data)
         except Exception, e:
            log.error('Unable to process source: %s' % (str(e),))
            raise

      if self.cli_opts.item_type == 'byway':
         self.analyze_graph()

      try:
         try:
            if self.cli_opts.item_type == 'byway':
               target_schema = Hausdorff_Import.intermediate_schema_byway
            else:
               target_schema = Hausdorff_Import.intermediate_schema_non_byway
            self.prepare_target_shapefiles(target_schema,
                                           touch_note='note_prepared')
         except Exception, e:
            log.error('Unable to prepare targets: %s' % (str(e),))
            raise
         try:
            self.cache_process_sources(source_files)
            if self.cli_opts.item_type == 'byway':
               self.cache_table_indices_create()
         except Exception, e:
            log.error('Unable to process inputs: %s' % (str(e),))
            raise
      finally:
         for shpfile in self.slayers.values():
            try:
               shpfile.close()
            except:
               pass
         self.slayers = None
         try:
            self.everylayer.close()
         except:
            pass
         self.everylayer = None

      self.symlink_target_shapefiles(link_name='Prepared')

   #
   def get_source_files(self, dir_base):

      g.assurt(dir_base in ('Source', 'Conflated', 'Prepared',))

      glob_path = os.path.join(
         self.cli_opts.source_dir, dir_base, '*.shp')
      source_files = glob.glob(glob_path)

      # Ignore the Everylayer file. This is just one Shapefile containing all
      # the features in all the other Shapefiles.
      source_files = [x for x in source_files
                      if os.path.basename(x) != 'everylayer.shp']

      if not source_files:
         log.error('No source Shapefiles were found in: %s' % (glob_path,))
         sys.exit(1)

      return source_files

   #
   def preprocess_source_shp_feats(self, source_data, common_crs):

      if self.cli_opts.item_type == 'byway':
         if source_data.schema['geometry'] not in ('LineString',
                                                   '3D LineString',
                                                   # MAYBE: MultiLineString
                                                   ):
            raise Exception('Source Shapefile not LineString type (%s)'
                            % (source_data.schema['geometry'],))
      elif self.cli_opts.item_type in ('region', 'terrain',):
         if source_data.schema['geometry'] not in ('Polygon',
                                                   'MultiPolygon',
                                                   # MAYBE: 3D?
                                                   ):
            raise Exception('Source Shapefile not (Multi)Polygon type (%s)'
                            % (source_data.schema['geometry'],))
      elif self.cli_opts.item_type == 'waypoint':
         if source_data.schema['geometry'] != 'Point':
            raise Exception('Source Shapefile not Point type (%s)'
                            % (source_data.schema['geometry'],))
      else:
         g.assurt(False)

      if not common_crs:
         common_crs = source_data.crs.copy()
      elif common_crs and source_data.crs and (common_crs != source_data.crs):
         raise Exception('CRSes do not match: %s / %s'
                         % (common_crs, source_data.crs,))

      return common_crs

   #
   def preprocess_source_build_network(self, source_data):
      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log_setup)
      #prog_log.log_freq = 20000
      #prog_log.loop_max = len(source_data)
      prog_log.setup(prog_log, 20000, len(source_data))
      log.info('Preprocessing %d features...' % (len(source_data),))
      for shpfeat in source_data:
         # Parse the guidance and some stack IDs.
         guidance, ccp_stack_id, ccp_ref_sids = (
            self.parse_guidance_and_stk_ids(shpfeat, initing=True))
         # Add this feature to the network, maybe.
         try:
            pt_xy_1, pt_xy_n = self.parse_endpoints(shpfeat)
         except:
            # This is a control feature, i.e., no geometry.
            pt_xy_1, pt_xy_n = (None, None,)
         if pt_xy_1 is not None:
            # BUG nnnn: This is how you determine 'is_disconnected'.
            # Check byway not, e.g., Expressway, Railroad, Private, etc.
            gf_lyr_id, gf_lyr_name = self.parse_gf_lyr_type(shpfeat)
            byway_gfl = byway.Geofeature_Layer
            if gf_lyr_id and (gf_lyr_id
                              not in byway_gfl.controlled_access_gfids):
               # And check byway not tagged impassable.
               add_tags, del_tags = self.tag_list_assemble(shpfeat)
               if not add_tags.intersection(byway_gfl.controlled_access_tags):
                  self.sub_forest.add_edge(pt_xy_1, pt_xy_n)
            self.the_forest.add_edge(pt_xy_1, pt_xy_n)
            # Make a set of just Expressway endpoints.
            if gf_lyr_id in (byway_gfl.Expressway, byway_gfl.Expressway_Ramp,):
               self.expressway_endpts.add(pt_xy_1)
               self.expressway_endpts.add(pt_xy_n)
         if prog_log.loops_inc():
            break
      prog_log.loops_fin()

   #
   def preprocess_source_regions(self, source_data):

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log_setup)
      #prog_log.log_freq = 20000
      #prog_log.loop_max = len(source_data)
      prog_log.setup(prog_log, 20000, len(source_data))
      log.info('Preprocessing %d features...' % (len(source_data),))
      for shpfeat in source_data:
         new_props = {}
         self.cache_source_data_clean_props_special(shpfeat, new_props,
                                                    first_time=True)


         if prog_log.loops_inc():
            break
      prog_log.loops_fin()

   #
   def analyze_graph(self):

      if self.cli_opts.known_pt_xy:

         connected_pt = (
            round(float(self.cli_opts.known_pt_xy[0]), conf.node_precision),
            round(float(self.cli_opts.known_pt_xy[1]), conf.node_precision),
            )

         time_0 = time.time()

         log.info('Analyzing graph...')

         try:
# FIXME: The sub_forest is non-controlled access, but the sub_forect
#        itself might be disjointed. See: is_disconnected.
            self.favorite_tree = networkx.node_connected_component(
                                       self.sub_forest, connected_pt)
         except KeyError, e:
            # Check connected_pt and try again. It wasn't added to the forest.
            log.error('Your connected point is not that well connected! %s'
                      % (str(e),))
         # Checking 'in list' vs. 'in set' is magnitudes slower,
         # so set-ify the list.
         self.favorite_tree = set(self.favorite_tree)

         log.info('Connected %d nodes (of %d; %d disj.) in %s [%d total node]'
                   % (len(self.favorite_tree),
                      len(self.sub_forest),
                      len(self.sub_forest) - len(self.favorite_tree),
                      misc.time_format_elapsed(time_0),
                      len(self.the_forest),))

   #
   def prepare_target_shapefiles(self, target_schema, touch_note=''):

      self.target_schema = target_schema
      if self.cli_opts.item_type == 'byway':
         self.target_schema['geometry'] = 'LineString'
      elif self.cli_opts.item_type == 'region':
         self.target_schema['geometry'] = 'MultiPolygon'
      elif self.cli_opts.item_type == 'terrain':
         self.target_schema['geometry'] = 'MultiPolygon'
      elif self.cli_opts.item_type == 'waypoint':
         self.target_schema['geometry'] = 'Point'
      else:
         g.assurt(False)

      # Make an output directory and an associated symlink.
      self.target_path = os.path.join(
         self.cli_opts.source_dir,
         '%s-%s' % (datetime.date.today().strftime('%Y_%m_%d'),
                    str(uuid.uuid4()),))
      try:
         os.mkdir(self.target_path, 02775)
      except OSError, e:
         log.error('Unexpected: Could not make randomly-named directory: %s'
                   % (str(e),))
         raise

      # Leave a note for ourselves...
      if touch_note:
         misc.file_touch(os.path.join(self.target_path, touch_note))

      target_crs = self.get_crs_from_srid(self.cli_opts.shapefile_srid)
      target_driver = self.cli_opts.shapefile_driver

      # Create some target layers:
      # We'll dig into each source Shapefile and copy each feature we find to
      # one of the target layers, depending on attributes of the item (so that
      # OpenJump is more powerful).

      # NOTE: This is the easy way to make a new Shapefile, except
      #       we've closed all the source Shapefiles already:
      #         sink = fiona.open('/tmp/foo.shp', 'w', **source.meta)

      if self.cli_opts.item_type == 'byway':
         layer_00_tree_type = Hausdorff_Import.byway_00_tree_type
         layer_01_geof_type = Hausdorff_Import.byway_01_geof_type
      elif self.cli_opts.item_type == 'region':
         layer_00_tree_type = Hausdorff_Import.region_00_tree_type
         layer_01_geof_type = [None,]
      else:
         layer_00_tree_type = ('non-byway',)
         layer_01_geof_type = [None,]

      self.intermed_feats = {}
      self.recorded_sids = set()
      self.slayers = {}
      try:
         for lt00 in layer_00_tree_type:
            for lt01 in layer_01_geof_type:
               if lt01:
                  lyr_name = '%s-%s' % (lt00, lt01,)
               else:
                  lyr_name = '%s' % (lt00,)
               self.intermed_feats[lyr_name] = []
               self.slayers[lyr_name] = fiona.open(
                  os.path.join(self.target_path, '%s.shp' % lyr_name),
                  'w',
                  crs=target_crs,
                  driver=target_driver,
                  schema=self.target_schema)
         self.everylayer = fiona.open(
            os.path.join(self.target_path, 'everylayer.shp'),
            'w',
            crs=target_crs,
            driver=target_driver,
            schema=self.target_schema)
      except Exception, e:
         log.error('Unable to open output targets: %s' % (str(e),))
         raise

   #
   def symlink_target_shapefiles(self, link_name):

      prepared_link = os.path.join(self.cli_opts.source_dir, link_name)
      # Make a link to the current output directory.
      # If you delete the directory pointed to by the link, but not the link,
      # exists returns False; but we want to know if the *link* exists.
      # No: if os.path.exists(prepared_link):
      if os.path.lexists(prepared_link):
         if os.path.islink(prepared_link):
            os.unlink(prepared_link)
         else:
            raise Exception(
               'Unexpected: Desired symlink exists but not a symlink: %s'
               % (prepared_link,))

      os.symlink(self.target_path, prepared_link)

   #
   def get_crs_from_srid(self, srid):
      g.assurt(srid == 26915) # Sorry, folks, this fcn. isn't very bright.
      if srid == 26915:
         # MAGIC_VALUES: This dict. reverse engineered by loading exising
         # Shapefile with Fiona.
         crs = {
            u'units': u'm',
            u'no_defs': True,
            u'datum': u'NAD83',
            u'proj': u'utm',
            u'zone': 15,
            }
      return crs

   #

   #
   def add_err(self, shpfeat, error_str):
      shpfeat['properties'].setdefault('import_err', '')
      if shpfeat['properties']['import_err']:
         shpfeat['properties']['import_err'] += '; '
      shpfeat['properties']['import_err'] += error_str

   #
   def parse_endpoints(self, shpfeat):

      xy_1 = shpfeat['geometry']['coordinates'][0]
      xy_n = shpfeat['geometry']['coordinates'][-1]
      pt_xy_1 = (round(xy_1[0], conf.node_precision),
                 round(xy_1[1], conf.node_precision),)
      pt_xy_n = (round(xy_n[0], conf.node_precision),
                 round(xy_n[1], conf.node_precision),)

      return pt_xy_1, pt_xy_n

   #
   def parse_gf_lyr_type(self, shpfeat):
      gf_lyr_id = None
      gf_lyr_name = None
      try:
         gf_lyr_id, gf_lyr_name = (
            self.qb.item_mgr.geofeature_layer_resolve(
               self.qb.db, shpfeat['properties']['gf_lyr_nom']))
      except Exception, e:
         # KeyError if gf_lyr_nom not in source, or TypeError if None.
         try:
            gf_lyr_id, gf_lyr_name = (
               self.qb.item_mgr.geofeature_layer_resolve(
                  self.qb.db, shpfeat['properties']['gf_lyr_id']))
         except Exception, e:
            if self.cli_opts.item_type == 'region':
               gf_lyr_id = region.Geofeature_Layer.Default
               gf_lyr_name = 'Default'
            #elif self.cli_opts.item_type == 'terrain':
            #   #Open_Space = 101
            #   #Water = 102
            #   #Waterbody = 103
            #   #Flowline = 104
            elif self.cli_opts.item_type == 'waypoint':
               gf_lyr_id = waypoint.Geofeature_Layer.Default
               gf_lyr_name = 'Default'
            elif not self.cli_opts.init_importer:
               log.warning(
                  'parse_gf_lyr_type: could not discern gfl_nom/_id: %s'
                  % (str(e),))
               self.add_err(shpfeat, 'unknown gf_lyr_nom (%s)'
                  % (shpfeat['properties']['gf_lyr_nom'],))
      return gf_lyr_id, gf_lyr_name

   #
   def parse_guidance_and_stk_ids(self, shpfeat, initing=False,
                                        update_ctrl_fields=False):

      guidance = None
      ccp_stack_id = None
      ccp_ref_sids = []
      del_ref_sids = []
      ccp_from_sids = []

      err_str = None
      err_val = None
      err_hint = None

      if not err_str:
         if 'CCP_ID' in shpfeat['properties']:
            try:
               ccp_stack_id = ojint(shpfeat['properties']['CCP_ID'])
               if ccp_stack_id and (ccp_stack_id < -2):
                  ccp_stack_id = None
                  err_str = 'Nonpositive CCP_ID stack ID'
               else:
                  shpfeat['properties']['CCP_ID'] = ccp_stack_id
            except:
               err_str = 'Invalid CCP_ID stack ID'
            if err_str:
               err_val = shpfeat['properties']['CCP_ID']
               err_hint = ' (hint: try: -1, or a stack ID (an integer > 0))'
         else:
            g.assurt((not initing) and update_ctrl_fields)
            shpfeat['properties']['CCP_ID'] = -1

      if not err_str:
         try:
            guidance_raw = shpfeat['properties']['OPERATION']
         except KeyError:
            guidance_raw = None
         if guidance_raw:
            if guidance_raw in ('D', 'd',):
               guidance = 'delete'
            elif guidance_raw in ('U', 'u',):
               guidance = 'update'
            elif guidance_raw in ('S', 'SI', 'SPLIT_INTO',):
               guidance = 'donate'
            else:
               # An int, or ints, or another string. If another string
               # (like 'couplet'), we won't change the source geofeature in
               # Cyclopath.  If an int or ints, those are stack IDs we'll use
               # to update this feature.
               if not err_str:
                  try:
                     # raises if not convertible to int(s).
                     del_ref_sids = ojints(guidance_raw)
                     #guidance = 'update'
                     guidance = 'repeat'
                     for ref_sid in del_ref_sids:
                        if ref_sid <= 0:
                           err_str = 'Nonpositive OPERATION referenece ID'
                           break
                        # Maintain collection of split-from IDs.
                        if self.cli_opts.fix_silent_delete_issue and initing:
                           self.sid_delete_froms.add(ref_sid)
                  except:
                     err_str = 'Unrecognized OPERATION value'
                  if err_str:
                     err_val = shpfeat['properties']['OPERATION']
                     err_hint = (
                        ' (hint: try: "", "Y", "N", or positive "ID[,ID...]")')
         else:
            # The OPERATION field is unset; see if there's an earlier guidance.
            try:
               guidance = shpfeat['properties']['GUIDANCE']
            except KeyError:
               # The GUIDANCE field is not set in the source.
               guidance = None
            if ((guidance)
                and (guidance not in Hausdorff_Import.byway_02_guidance)):
               err_str = 'Unrecognized GUIDANCE value'
               err_val = shpfeat['properties']['GUIDANCE']
               err_hint = (
                  ' (hint: try: "%s", or "%s")'
                  % ('","'.join(Hausdorff_Import.byway_02_guidance[:-1]),
                     Hausdorff_Import.byway_02_guidance[-1],))

      if not err_str:
         if 'CCP_FROMS_' in shpfeat['properties']:
            ccp_from_sids_raw = shpfeat['properties']['CCP_FROMS_']
            if ccp_from_sids_raw:
               try:
                  ccp_from_sids = ojints(ccp_from_sids_raw)
                  for ref_sid in ccp_from_sids:
                     if ref_sid <= 0:
                        err_str = 'Nonpositive CCP_FROMS_ referenece ID'
                        break
               except:
                  err_str = 'Unrecognized CCP_FROMS_ value'
            if err_str:
               err_val = shpfeat['properties']['CCP_FROMS_']
               err_hint = ' (hint: try: positive stack ID(s) "ID[,ID...]")'

      # Clear the import err, which may have been set in an earlier
      # processing session. We'll set it again if the feature is still
      # in an error state.
      shpfeat['properties']['import_err'] = ''

      ccp_ref_sids = del_ref_sids + ccp_from_sids # Ordered list.
      if not err_str:
         # There might be more than one feature with the same CCP_ID,
         # which means the user is splitting the item in twain, or
         # more. Make a lookup of stack IDs.
         if initing and (guidance not in ('delete', 'ignore',)):
            if (ccp_stack_id) and (ccp_stack_id > 0):
               misc.dict_count_inc(self.sid_use_count, ccp_stack_id)
               if not guidance:
                  misc.dict_count_inc(self.sid_use_noops, ccp_stack_id)
            if ((self.cli_opts.use_old_stack_IDs_when_possible)
                and (del_ref_sids)):
               # MAYBE: dict_list_append is kind of like
               #         add_edge(ccp_ref_sids[0], ccp_stack_id)
               #        Maybe I should start using a Graph for
               #        these purposes...?
               if ccp_stack_id > 0:
                  #misc.dict_list_append(self.sid_del_lists, del_ref_sids[0],
                  #                                          ccp_stack_id)
                  for del_ref_sid in del_ref_sids:
                     misc.dict_list_append(self.sid_del_lists, del_ref_sid,
                                                               ccp_stack_id)

         # During the processing phase, reset values.
         if update_ctrl_fields:
            shpfeat['properties']['GUIDANCE'] = guidance
            shpfeat['properties']['OPERATION'] = ''
            shpfeat['properties']['CCP_FROMS_'] = ','.join(
                              [str(x) for x in ccp_ref_sids])
            shpfeat['properties'].setdefault('CCP_VERS', -1)
            if shpfeat['geometry'] is not None:
               if self.cli_opts.item_type == 'byway':
                  shpfeat['properties']['new_length'] = geometry.xy_line_len(
                                    shpfeat['geometry']['coordinates'])
               elif self.cli_opts.item_type in ('region', 'terrain',):
                  try:
                     shpfeat['properties']['PERIMETER'] = geometry.xy_line_len(
                                    shpfeat['geometry']['coordinates'][0])
                  except TypeError:
                     shpfeat['properties']['PERIMETER'] = geometry.xy_line_len(
                                    shpfeat['geometry']['coordinates'][0][0])
                  if shpfeat['geometry']['type'] == 'Polygon':
                     geom_wkt = geometry.xy_to_ewkt_polygon(
                        shpfeat['geometry']['coordinates'])
                  elif shpfeat['geometry']['type'] == 'MultiPolygon':
                     geom_wkt = geometry.xy_to_ewkt_polygon_multi(
                        shpfeat['geometry']['coordinates'])
                  else:
                     g.assurt(False)
                  area_sql = ("SELECT ST_Area('%s'::GEOMETRY)" % (geom_wkt,))
                  try:
                     rows = self.qb.db.sql(area_sql)
                  except InternalError:
                     raise
                  g.assurt(len(rows) == 1)
                  shpfeat['properties']['AREA'] = rows[0]['st_area']

      else:
         log.error('%s (%s)%s / %s'
            % (err_str, err_val, err_hint, pprint.pformat(shpfeat),))
         self.add_err(shpfeat, err_str)

      return guidance, ccp_stack_id, ccp_ref_sids

   #

   #
   def cache_process_sources(self, source_files):

      log.debug('Successfully created the target Shapefiles')

      for source_shp in source_files:
         try:
            with fiona.open(source_shp, 'r') as source_data:
               log.info('Scanning shapefile: %s (%d features)'
                        % (os.path.basename(source_shp),
                           len(source_data),))
               self.cache_source_data(source_data)
         except Exception, e:
            log.error('Unable to process source file: %s' % (str(e),))
            raise

      if not debug_writerecords_1x1:
         log.debug('Writing features to Shapefiles...')
         for lyr_name in self.slayers.keys():
            feat_list = self.intermed_feats[lyr_name]
            if feat_list:
               self.slayers[lyr_name].writerecords(feat_list)
               self.everylayer.writerecords(feat_list)
            del self.intermed_feats[lyr_name]
         del self.intermed_feats

   #
   def cache_table_indices_create(self):

      # Create cache table indices.

      log.debug('Creating cache table indices...')

      index_sql = (
         """
         CREATE INDEX hausdorff_cache_geometry
            ON hausdorff_cache USING GIST (geometry)
         """)
      self.qb.db.sql(index_sql)

      for col_name in ('stack_id',
                       'name',
                       'gf_lyr_nom',
                       'gf_lyr_id',
                       'match_cmd',):
         index_sql = (
            """
            CREATE INDEX hausdorff_cache_%s ON hausdorff_cache (%s)
            """ % (col_name, col_name,))
         self.qb.db.sql(index_sql)

   #
   def cache_source_data(self, source_data):

      cache_rows = []

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log_setup)
      if self.favorite_tree is not None:
         prog_log.log_freq = 5000
      else:
         prog_log.log_freq = 10000
      #prog_log.log_freq = 1
      prog_log.loop_max = len(source_data)
      prog_log.setup(prog_log, prog_log.log_freq, len(source_data))

      for shpfeat in source_data:

         # The OPERATION attribute is set by the user as follows:
         #
         #      'D' -- Delete this feature. If there's a CCP_ID, delete
         #             the corresponding Cyclopath feature; otherwise,
         #             just forget about this feature and don't copy
         #             to the target Shapefile.
         #      'K' -- Keep this feature. If there's a CCP_ID,
         #             we'll compare the feature against the Cyclopath
         #             feature to see if we should update the geometry
         #             or any metadata.
         #    {int} -- If there's an integer value for OPERATION, it indicates
         #             that this feature and another feature are logically
         #             similar. The user can mark the other feature's OPERATION
         #             or not; if the user doesn't mark the other feature's
         #             OPERATION, it implies that this item is the younger,
         #             duplicate item, so it should be deleted and its
         #             properties can be merged with the older, original
         #             item. However, if the referenced item's OPERATION is
         #             set by the user, we'll keep this feature and merge
         #             properties from the referenced item (that is, this
         #             segment is a split-into, and the referenced item is the
         #             split-from). I know this is confusing, but the idea is
         #             to keep the OpenJUMP mouse and keyboard usage as minimal
         #             as possible when editing Shapefiles.
         #  {blank} -- An empty OPERATION might mean this feature has not been
         #             audited by the user, or perhaps another feature is
         #             marked as a duplicate of this feature. If the former,
         #             we'll try matching this item; if the latter, we know
         #             we don't have to bother.
         #  'SPLIT_INTO' | 'SI' | 'S' | 'DONATE'
         #          -- This means we want to try to get rid of this feature,
         #             and split it into or have it be absorbed by other
         #             features. This is useful for, e.g., a user draws a
         #             really long line where roads don't exist on the map,
         #             and later you import the segmented road network, and
         #             you want to get rid of the user's original line but
         #             keep their metadata.

         # Specify update_ctrl_fields to clear OPERATION and move OPERATION ref
         # IDs to CCP_FROMS_, and to set GUIDANCE and the geometry length.
         guidance, ccp_stack_id, ccp_ref_sids = (
            self.parse_guidance_and_stk_ids(
               shpfeat, update_ctrl_fields=True))

         if debug_filter_sids and (ccp_stack_id not in debug_filter_sids):
            continue

         # Cleanup the feature properties. This script has three distinct
         # runtime behaviors: initing, preparing, and processing. And each
         # time it creates Shapefiles with slightly different schemas. Each
         # schema shares a common set of fields, but, e.g., the conflation
         # schema (the preparing step) contains a bunch of extra fields that
         # contains values about the conflation.
         # So redo the properties lookup, using our schema's fields.
         # Avoid: "Record does not match collection schema: [..] != [..]"
         new_props = {}
         if self.cli_opts.item_type == 'byway':
            use_field_defn = Hausdorff_Import.intermediate_fields_byway
         else:
            use_field_defn = Hausdorff_Import.intermediate_fields_non_byway
         for defn in use_field_defn:
            fldn, rown = defn
            try:
               new_props[fldn] = shpfeat['properties'][fldn]
            except KeyError:
               new_props[fldn] = None
         self.cache_source_data_clean_props_special(shpfeat, new_props,
                                                    first_time=False)
         shpfeat['properties'] = new_props

         if self.cli_opts.item_type == 'byway':
            try:
               pt_xy_1, pt_xy_n = self.parse_endpoints(shpfeat)
               if (geometry.distance(pt_xy_1, pt_xy_n)
                   < (pow(0.1, conf.node_precision) * 2.1)): # E.g., 0.21
                  guidance = 'noring'
                  self.add_err(shpfeat, 'ring geometry')
                  self.stats['feats_ring_geometry'] += 1
                  #log.warning('cache_source_data: ring geom: %s' % (shpfeat,))
            except:
               pt_xy_1, pt_xy_n = None, None
               guidance = 'nogeom'
               self.add_err(shpfeat, 'missing geometry')
               self.stats['feats_missing_geometry'] += 1
               #log.warning('cache_source_data: bad geom: %s' % (shpfeat,))
         #elif shpfeat['geometry']['type'] == 'Point':
         #elif shpfeat['geometry']['type'] == 'Polygon':
         #elif shpfeat['geometry']['type'] == 'MultiPolygon':
         else:
            if not shpfeat['geometry']:
               guidance = 'nogeom'
               self.add_err(shpfeat, 'missing geometry')
               self.stats['feats_missing_geometry'] += 1

         # If the user copies an OLD stack ID into a NEW feature's OPERATION
         # but does not mark the OLD feature's OPERATION, it implies that we're
         # deleting the new feature (a duplicate, with OPERATION set) and
         # keeping the old feature (the original, with OPERATION not set).
         try:
            if ((self.cli_opts.fix_silent_delete_issue)
                and (self.sid_use_count[ccp_stack_id] == 1)):
               if ((not guidance)
                   and (ccp_stack_id in self.sid_delete_froms)):
                  g.assurt(self.sid_use_noops[ccp_stack_id] == 1)
                  # This is the original item. Since another item references
                  # us with their OPERATION, and since our guidance is blank,
                  # it means we're being kept.
                  log.verbose('fix_silent_delete_issue hack: update: %s'
                              % (ccp_stack_id,))
                  guidance = 'update'
                  self.stats['feats_magic_del_new'] += 1
                  misc.dict_count_inc(self.stats['feats_magic_del_sids'],
                                      ccp_stack_id)
                  #
                  new_ref_sids = (self.sid_del_lists[ccp_stack_id]
                                  + ccp_ref_sids) # ccp_ref_sids is empty
                  shpfeat['properties']['CCP_FROMS_'] = str(new_ref_sids
                                                            ).strip('[]()')
                  ccp_ref_sids = new_ref_sids
               elif (guidance == 'repeat') and (ccp_ref_sids):
                  all_used_once = True
                  for ref_sid in ccp_ref_sids:
                     if self.sid_use_noops[ref_sid] != 1:
                        all_used_once = False
                        break
                  if all_used_once:
                     log.verbose('fix_silent_delete_issue hack: delete: %s'
                                 % (ccp_stack_id,))
                     guidance = 'delete'
                     self.stats['feats_magic_del_old'] += 1
                     for ref_sid in ccp_ref_sids:
                        misc.dict_count_inc(self.stats['feats_magic_del_sids'],
                                            ref_sid)
         except:
            pass
         # RAMBLINGS:
         # If the user wants to copy the new feature's geometry,
         # they have two options: mark the old feature SPLIT_INTO
         # and hope for a line match; or, they can swap the stack
         # IDs of the two features so that the old stack ID is
         # paired with the new geometry, and then they can use
         # CCP_FROMS_ to reference the original feature -- which
         # now has the duplicate's stack ID -- to be sure that
         # metadata is copied. The only thing missing is if we
         # want to preference one line's attributes and the
         # other line's geometry when we do a merge; currently,
         # whatever geometry you choose, we'll merge metadata
         # *into* that line but we won't overwrite existing data.
         # E.g., consider two duplicates, A and B, that are
         # logically the same street, and A says 40 mph (which
         # is correct) and B says 20 mph (which is wrong), but
         # B has better geometry. With the techniques described
         # above, swapping the IDs to use B's geometry also means
         # we will change speedlimit to the erroneous 20 mph
         # (since we don't merge values that are already set).
         # MAYBE: More OPERATION commands or something?
         #        GIVE_PROP (this is SPLIT_INTO)
         #        GIVE_GEOM
         #        TAKE_PROP (this is CCP_FROMS_)
         #        TAKE_GEOM
         #

        # # If we're re-initing (--init-importer) using the output of
        # # a previous conflation (--try-matching), get rid of the old
        # # conflation results.
        # if guidance in Hausdorff_Import.layer_02_analysis:
        #    # Let's re-run the analysis. guidance == '' will also trigger
        #    # matching, but marking this 'pending' gives the DEV a little
        #    # more information if auditing intermediate Shapefiles.
        #    guidance = 'pending'
        # # else, guidance either '' or in byway_02_guidance.

         # NOTE: The stack ID collection is a set, not a list. On [lb]'s
         #       machines, using a list runs around 16 loops/sec., but
         #       using a set runs at 3000 loops/sec. Just a friendly
         #       reminder to choose your collections wisely!
         well_connected = True
         if (pt_xy_1 is not None) and (self.favorite_tree is not None):
            well_connected = pt_xy_1 in self.favorite_tree
            shpfeat['properties']['wconnected'] = (
               '1' if well_connected else '0')
            # Count the dangles.
            # If there's one neighbor, it's just the other endpoint;
            #  meaning, this endpt is a dangle.
            # If there are two neighbors, this is a pass-through point:
            #  there's not really an intersection here, it's just where
            #  two lines meet. This is useful for a number of reasons.
            #  1. Cyclopath doesn't like rings, so roundabouts and
            #     "courts" need to be split into multiple segments.
            #  2. Sometimes roads change names in the middle of a "block".
            #  3. Roads attributes might have changed, like speed limit,
            #     or shoulder width.
            #  4. To add an endpoint for the route finder, which doesn't
            #     know how to suggest to people to start or end a trip
            #     in the middle of a line segment.
            #     BUG nnnn: Middle-of-the-line O/D routing.
            nneighbr_1 = len(self.the_forest.neighbors(pt_xy_1))
            nneighbr_n = len(self.the_forest.neighbors(pt_xy_n))
            g.assurt((nneighbr_1 > 0) and (nneighbr_n > 0))
            shpfeat['properties']['nneighbr_1'] = nneighbr_1
            shpfeat['properties']['nneighbr_n'] = nneighbr_n
            min_cnt = min(nneighbr_1, nneighbr_n)
            max_cnt = max(nneighbr_1, nneighbr_n)
            if min_cnt == 1:
               if max_cnt == 1:
                  shpfeat['properties']['wangdangle'] = 'desolate island'
               elif max_cnt == 2:
                  shpfeat['properties']['wangdangle'] = 'deadend dangle'
               else:
                  shpfeat['properties']['wangdangle'] = 'dangle nubbin'
            elif min_cnt == 2:
               if max_cnt == 2:
                  shpfeat['properties']['wangdangle'] = 'sandwich segment'
               else:
                  shpfeat['properties']['wangdangle'] = 'manwich segment'
            elif min_cnt == 3:
               if max_cnt == 3:
                  shpfeat['properties']['wangdangle'] = 'couplet wire'
               else:
                  shpfeat['properties']['wangdangle'] = 'party wire'
            else:
               shpfeat['properties']['wangdangle'] = 'normal wiring'
         elif self.cli_opts.item_type == 'byway':
            shpfeat['properties']['wconnected'] = '-1'
            shpfeat['properties']['wangdangle'] = ''
            shpfeat['properties']['nneighbr_1'] = -1
            shpfeat['properties']['nneighbr_n'] = -1

         # The Shapefile contains both the geofeature layer ID and its friendly
         # name. We expect that the user would only edit the name, so we give
         # its value preference over the ID value.
         gf_lyr_id, gf_lyr_name = self.parse_gf_lyr_type(shpfeat)
         # We group features is sets based on the geofeature layer based on
         # types of vehicles allowed: bikes only, shared use, controlled
         # access, the other "other" category, and a special category for
         # non-expressway "ramps".
         gf_type_bucket = 'fifth_hand' # "Other" geofeature layer types.
         if gf_lyr_id:
            byway_gfl = byway.Geofeature_Layer
            if gf_lyr_id in byway_gfl.non_motorized_gfids:
               gf_type_bucket = 'segregated'
            elif gf_lyr_id in byway_gfl.motorized_uncontrolled_gfids:
               gf_type_bucket = 'shared_use'
            elif gf_lyr_id in byway_gfl.controlled_access_gfids:
               gf_type_bucket = 'controlled'
            # else, "Other", and the like.
            if gf_lyr_id == byway.Geofeature_Layer.Expressway_Ramp:
               if (    (pt_xy_1 not in self.expressway_endpts)
                   and (pt_xy_n not in self.expressway_endpts)):
                  gf_lyr_id, gf_lyr_name = (
                     self.qb.item_mgr.geofeature_layer_resolve(
                        self.qb.db, byway.Geofeature_Layer.Other_Ramp))
                  gf_type_bucket = 'transition'
               else:
                  gf_type_bucket = 'shared_use'
            shpfeat['properties']['gf_lyr_id'] = gf_lyr_id
            shpfeat['properties']['gf_lyr_nom'] = gf_lyr_name
            shpfeat['properties']['gfl_typish'] = gf_type_bucket

         # We make ten or so Shapefiles. Ideally, we'd just make one, but
         # OpenJUMP can only stylize a single attribute per layer, so we
         # use multiple Shapefiles so we have the ability to stylize more
         # discerningly.
         target_lyr_name = self.get_target_lyr(shpfeat,
                        well_connected, gf_type_bucket)

         # If you create intersections with a GIS tool, you'll end up
         # with multiple features with the same stack ID. During import,
         # we want to delete the old item (the split-from) and create a
         # bunch of new items (the split-intos). So we need to create a
         # new feature to tell us to delete the old item, and we need to
         # reset the stack IDs of the new features so we create new items.
         delfeat = None
         if ((guidance not in ('delete', 'ignore', 'nogeom',))
             and (ccp_stack_id > 0)):
            try:
               if self.sid_use_count[ccp_stack_id] > 1:
                  # We only want one delete feature, but we'll come through
                  # this loop for each split-into, so check that we haven't
                  # made the delete feature yet.
                  if ccp_stack_id not in self.recorded_sids:
                     # More than one feature uses the same stack ID, so
                     # make a duplicate feature to delete the old item.
                     del_stack_id = ccp_stack_id
                     delfeat = copy.deepcopy(shpfeat)
                     delfeat['properties']['GUIDANCE'] = 'delete'
                  # else, item marked deleted earlier.
                  #
                  # Remember our roots.
                  new_ref_sids = [ccp_stack_id,] + ccp_ref_sids
                  shpfeat['properties']['CCP_FROMS_'] = str(new_ref_sids
                                                            ).strip('[]()')
                  # Set the stack ID negative so the worker task assigns a
                  # new stack ID to this new line segment.
                  shpfeat['properties']['CCP_ID'] = -1
                  # NOTE: Not setting ccp_stack_id = -1, so when we conflate
                  #       items we can still find the old item in the database.
                  #
                  # We can assume that if the user didn't mark OPERATION,
                  # and they split the feature, that they want to update
                  # this feature and we don't need to conflate it... right?
                  guidance = guidance or 'update'
                  if guidance == 'noring':
                     guidance = 'update'
               # else, item stack ID used just once.
               #
            except:
               pass
         # else, guidance is 'deleted', or this is a new item.

         # Check if the user used an editing shortcut: mark the old item
         # deleted and mark the new item as replacing the old item, so we
         # merge features and use the new one's geometry but preference the
         # old one's attributes/link_values. (The other way we might handle
         # two duplicates is to mark the new one deleted and to reference it
         # from the old one so its attributes (but not its geometry) are
         # merged into the old item.)
         #
         # If the user identified two items as duplicates -- and didn't
         # indicate any splits -- always use the old items' stack ID
         # (regardless of whose attributes and geometry we preference).

         if (self.cli_opts.use_old_stack_IDs_when_possible
             and (ojint(shpfeat['properties']['CCP_ID']) != -1)):

            refed_sid = None
            if guidance == 'repeat':
               g.assurt(ccp_ref_sids)
               is_new_item = True
               refed_sid = ccp_ref_sids[0]
            elif guidance == 'delete':
               is_new_item = False
               refed_sid = ccp_stack_id

            if refed_sid is not None:
               try:
                  if is_new_item:
                     refee_sid = ccp_stack_id
                  else:
                     # This item may or may not exist in the lookup, so
                     # this might raise KeyError.
                     refee_sid = self.sid_del_lists[ccp_stack_id][0]
                  # The reference Stk ID is the old stack ID.
                  if ((refed_sid > 0)
                      and (refed_sid not in self.sid_use_count) # being deled
                      and (self.sid_use_count[refee_sid] == 1) # othr not splt
                      and (len(self.sid_del_lists[refed_sid]) == 1)): # refed 1
                     # Assume other feature's stack ID and swap it in ref IDs.
                     if not is_new_item:
                        misc.dict_count_inc(
                           self.stats['feats_magic_swap_sids'],
                           ccp_stack_id)
                        # Get new item's stack ID.
                        refed_sid = refee_sid
                        self.stats['feats_magic_swap_old'] += 1
                     else:
                        misc.dict_count_inc(
                           self.stats['feats_magic_swap_sids'],
                           refed_sid)
                        self.stats['feats_magic_swap_new'] += 1
                     ccp_ref_sids = [x for x in ccp_ref_sids if x != refed_sid]
                     ccp_ref_sids.insert(0, ccp_stack_id)
                     shpfeat['properties']['CCP_FROMS_'] = ','.join(
                                       [str(x) for x in ccp_ref_sids])
                     # If older, change to newer's ID; else, other way 'round.
                     log.verbose(
                        'cache_source_data: swapparoo: %s: us: %s / ref: %s'
                        % (guidance, ccp_stack_id, refed_sid,))
                     ccp_stack_id = refed_sid
                     shpfeat['properties']['CCP_ID'] = refed_sid
               except KeyError:
                  pass # refed_sid not found in one of the lookups.

         # If you split a feature and mark one deleted, don't really delete the
         # Cyclopath item since the other feature will use the stack ID.
         if guidance == 'delete':
            try:
               if self.sid_use_count[ccp_stack_id] > 0:
                  guidance = 'ignore'
            except KeyError:
               pass
            try:
               if self.sid_del_count[ccp_stack_id] > 0:
                  # Since we checkout items at revision minus one, if two
                  # features with the same stack ID are marked delete, the
                  # second delete that's processed will cause a duplicate
                  # key error when it tries to finalize the old item version
                  # (by setting the row with valid_until_rid to the current
                  # rid, but that item's valid_start_rid is also the current
                  # rid, hence the collision).
                  guidance = 'ignore'
            except KeyError:
               self.sid_del_count[ccp_stack_id] = 0
            self.sid_del_count[ccp_stack_id] += 1

         # If guidance is still 'repeat', it means the feature referenced
         # another item using its OPERATION field, and we looked at the other
         # item and determined its OPERATION was deliberately marked, which
         # means this feature is assumed to be a split-into.
         if guidance == 'repeat':
            #?: guidance = 'update'
            pass

         shpfeat['properties']['GUIDANCE'] = guidance

         # We're getting ready to copy the feature to the intermediate
         # Shapefile. We're also getting ready to make a new row in
         # the matching cache table. 'OKAY' means we don't need to
         # match; otherwise, it's 'conflate' or 'donate', both or
         # which require matching.
         match_cmd = 'OKAY'
         if self.cli_opts.first_suspect:
            # MAYBE/BUG nnnn: Something like first_suspect but
            # where you don't have to import duplicates into the
            # database... maybe in the Shapefile, these features
            # all just have a -2 stack ID...
            if (    (ccp_stack_id >= self.cli_opts.first_suspect)
                and (ccp_stack_id <= self.cli_opts.final_suspect)):
               if not guidance:
                  match_cmd = 'conflate'

         if guidance == 'donate':
            match_cmd = 'donate'

         if not shpfeat['properties']['import_err']:

            if ((self.cli_opts.item_type == 'byway')
                and (guidance not in ('delete', 'ignore',))):
               insert_vals = (
         "(%d, %s, '%s', %d, '%s', '%s', %d, %s, %d, %d, '%s'::GEOMETRY)"
                  % (ccp_stack_id,
                     self.qb.db.quoted(
                        shpfeat['properties']['CCP_NAME']),
                     shpfeat['properties']['gf_lyr_nom'],
                     gf_lyr_id,
                     gf_type_bucket,
                     match_cmd,
                     shpfeat['properties']['one_way'] or 0,
                     "TRUE" if well_connected else "FALSE",
                     nneighbr_1,
                     nneighbr_n,
                     geometry.xy_to_ewkt_line(
                        shpfeat['geometry']['coordinates']),
                     ))
               cache_rows.append(insert_vals)

         # Copy feature to target layer.
         if target_lyr_name is not None:
            try:
               if shpfeat is not None:
                  if debug_writerecords_1x1:
                     self.slayers[target_lyr_name].write(shpfeat)
                     self.everylayer.write(shpfeat)
                  else:
                     self.intermed_feats[target_lyr_name].append(shpfeat)
                  self.recorded_sids.add(ccp_stack_id)
               if delfeat is not None:
                  if debug_writerecords_1x1:
                     self.slayers[target_lyr_name].write(delfeat)
                     self.everylayer.write(delfeat)
                  else:
                     self.intermed_feats[target_lyr_name].append(delfeat)
                  self.recorded_sids.add(del_stack_id)
            except Exception, e:
               log.error('Problem writing feature: %s' % (str(e),))
               raise

         if prog_log.loops_inc():
            break

      # end: for shpfeat in source_data

      prog_log.loops_fin()

      # Update the cache table.

      if cache_rows:

         log.debug('cache_source_data: inserting into hausdorff_cache')

         time_0 = time.time()

         insert_sql = (
            """
            INSERT INTO hausdorff_cache
               (  stack_id
                , name
                , gf_lyr_nom
                , gf_lyr_id
                , gf_lyr_bucket
                , match_cmd
                , one_way
                , well_connected
                , nneighbr_1
                , nneighbr_n
                , geometry
                ) VALUES
                  %s
            """ % (','.join(cache_rows),))

         self.qb.db.sql(insert_sql)

         log.debug('cache_source_data: inserted %d rows in %s'
                   % (len(cache_rows),
                      misc.time_format_elapsed(time_0),))

   RE_ccp_township = re.compile(r'(.*) Twp\.?\s*$', re.IGNORECASE)

   #
   def cache_source_data_clean_props_special(self, shpfeat, new_props,
                                                   first_time=None):

      if self.cli_opts.import_fix_mndot_polies:
         new_name = None
         new_tags = None
         try:
            new_name = shpfeat['properties']['TWP_NAME']
            new_tags = 'township'
            if first_time:
               self.mndot_geom['township'][new_name] = shpfeat['geometry']
               misc.dict_count_inc(self.mndot_region['township'],
                                   new_name)
         except KeyError:
            try:
               new_name = shpfeat['properties']['MUNI_NAME']
               new_tags = 'city'
               if first_time:
                  self.mndot_geom['city'][new_name] = shpfeat['geometry']
                  misc.dict_count_inc(self.mndot_region['city'],
                                      new_name)
            except KeyError:
               try:
                  new_name = shpfeat['properties']['COUNTYNAME']
                  new_tags = 'county'
               except KeyError:
                  if 'CCP_NAME' not in shpfeat['properties']:
                     log.warning('--import-fix-mndot-polies but confused: %s'
                                 % (shpfeat,))
                  elif ojint(shpfeat['properties']['CCP_ID']) > 0:
                     new_props['CCP_NAME'] = re.sub(r'^St.? +', 'Saint ',
                                       shpfeat['properties']['CCP_NAME'])
                     shpfeat['properties']['CCP_NAME'] = new_props['CCP_NAME']
                     # This is an existing Cyclopath item. See if it's a
                     # township but not really marked as such.
                     try:
                        new_name = Hausdorff_Import.RE_ccp_township.match(
                           shpfeat['properties']['CCP_NAME']).group(1).strip()
                        new_tags = 'township'
                        if first_time:
                           misc.dict_count_inc(self.ccp_region['township'],
                                               new_name)
                     except AttributeError:
                        if ((shpfeat['properties']['item_tags'])
                           and (shpfeat['properties']['item_tags'].find('city')
                                != -1)):
                           if first_time:
                              misc.dict_count_inc(self.ccp_region['city'],
                                          shpfeat['properties']['CCP_NAME'])

         if new_name:
            new_props['CCP_NAME'] = new_name
            new_props['item_tags'] = new_tags
            shpfeat['properties']['CCP_NAME'] = new_name
            shpfeat['properties']['item_tags'] = new_tags
         if not first_time:
            name = shpfeat['properties']['CCP_NAME']
            if ojint(shpfeat['properties']['CCP_ID']) > 0:
               if shpfeat['properties']['item_tags']:
                  # Consume other geometry if MnDOT geometry exists.
                  if (shpfeat['properties']['item_tags'].find('city')
                      != -1):
                     try:
                        if self.mndot_region['city'][name] == 1:
                           shpfeat['geometry'] = self.mndot_geom['city'][name]
                           self.stats['regions_consume_geom_city'] += 1
                     except KeyError:
                        pass
                  if (shpfeat['properties']['item_tags'].find('township')
                      != -1):
                     try:
                        if self.mndot_region['township'][name] == 1:
                           shpfeat['geometry'] = self.mndot_geom['township'][
                                                                        name]
                           self.stats['regions_consume_geom_twns'] += 1
                     except KeyError:
                        pass
            else:
               # This is a new MnDOT geofeature; see if we already got one of
               # these.
               # There's a small bug here: if two or more MnDOT townships have
               # the same name and there's one Ccp conflict, both MnDOT
               # townships are marked delete- but one of them is really valid.
               if ((new_tags == 'city')
                   and (name in self.ccp_region['city'])
                   and (self.ccp_region['city'][name] == 1)
                   and (name in self.mndot_region['city'])
                   and (self.mndot_region['city'][name] == 1)):
                  new_props['OPERATION'] = 'D'
                  shpfeat['properties']['OPERATION'] = 'D'
                  self.stats['regions_tossed_other_city'] += 1
               elif ((new_tags == 'township')
                   and (name in self.ccp_region['township'])
                   and (self.ccp_region['township'][name] == 1)
                   and (name in self.mndot_region['township'])
                   and (self.mndot_region['township'][name] == 1)):
                  new_props['OPERATION'] = 'D'
                  shpfeat['properties']['OPERATION'] = 'D'
                  self.stats['regions_tossed_other_twns'] += 1

   #
   def get_target_lyr(self, shpfeat, well_connected=None, gf_type_bucket=None):
      if self.cli_opts.item_type == 'byway':
         if well_connected is None:
            g.assurt(gf_type_bucket is None)
            well_connected = (shpfeat['properties']['wconnected'] == '1')
            gf_type_bucket = shpfeat['properties']['gfl_typish']
         if not gf_type_bucket:
            log.warning('get_target_lyr: no gf_type_bucket: %s'
                        % (shpfeat['properties'],))
         target_lyr_name = (
            '%s-%s'
            % ('connected' if well_connected else 'sovereign',
               gf_type_bucket,))
      elif ((self.cli_opts.item_type == 'region')
            and (shpfeat['properties']['item_tags'])):
         if shpfeat['properties']['item_tags'].find('county') != -1:
            target_lyr_name = 'county'
         elif shpfeat['properties']['item_tags'].find('township') != -1:
            target_lyr_name = 'township'
         elif shpfeat['properties']['item_tags'].find('city') != -1:
            target_lyr_name = 'city'
         elif shpfeat['properties']['item_tags'].find('neighborhood') != -1:
            target_lyr_name = 'neighborhood'
         else:
            target_lyr_name = 'yogabbagabba'
      else:
         target_lyr_name = 'non-byway'
      return target_lyr_name

   # ***

   #
   def match_cache_populate(self, gf_type_bucket='shared_use'):

      log.info('Dropping table maybe: hausdorff_match.')
      drop_sql = "DROP TABLE IF EXISTS hausdorff_match"
      self.qb.db.sql(drop_sql)

      # DEVS: You could limit the result, but even 100,000 results takes just a
      #       few seconds to fetch.
      limit_sql = ""
      #if debug_prog_log_setup.debug_break_loops:
      #   limit_sql = "LIMIT %d" % (debug_prog_log_setup.debug_break_loop_cnt,)

      # Exclude bike trails, sidewalks, freeways, etc.
      if gf_type_bucket == 'segregated':
         gfl_ids = byway.Geofeature_Layer.non_motorized_gfids
      elif gf_type_bucket == 'shared_use':
         gfl_ids = byway.Geofeature_Layer.motorized_uncontrolled_gfids
      elif gf_type_bucket == 'controlled':
         gfl_ids = byway.Geofeature_Layer.controlled_access_gfids
      else:
         # We don't support matching other geofeature layer types.
         g.assurt(False)
      gfl_ids = [str(x) for x in gfl_ids]
      gfl_ids = ','.join(gfl_ids)
      # MAYBE: Also compare freeway to freeway, and trails to trails.

      # NOTE: Using ST_DWithin instead of ST_Intersects; the latter is slower.

      cross_join_sql = (
         """
         SELECT
            --gf_new.branch_id::INT AS gf_new_branch_id
              gf_new.stack_id::INT AS gf_new_stack_id
            , gf_new.name::TEXT AS gf_new_name
            , gf_new.gf_lyr_nom::TEXT AS gf_new_gf_lyr_nom
            , gf_new.gf_lyr_id::INT AS gf_new_gf_lyr_id
            , gf_new.one_way::INT AS gf_new_one_way
            , gf_new.nneighbr_1::INT AS gf_new_nneighbr_1
            , gf_new.nneighbr_n::INT AS gf_new_nneighbr_n
            , gf_new.match_cmd::TEXT AS gf_new_match_cmd
            , gf_new.geometry::GEOMETRY AS gf_new_geometry
            --
            --gf_old.branch_id::INT AS gf_old_branch_id,
            , gf_old.stack_id::INT AS gf_old_stack_id
            , gf_old.name::TEXT AS gf_old_name
            , gf_old.gf_lyr_nom::TEXT AS gf_old_gf_lyr_nom
            , gf_old.gf_lyr_id::INT AS gf_old_gf_lyr_id
            , gf_old.one_way::INT AS gf_old_one_way
            , gf_old.nneighbr_1::INT AS gf_old_nneighbr_1
            , gf_old.nneighbr_n::INT AS gf_old_nneighbr_n
            , gf_old.match_cmd::TEXT AS gf_old_match_cmd
            , gf_old.geometry::GEOMETRY AS gf_old_geometry
            --
            , ST_HausdorffDistance(gf_new.geometry, gf_old.geometry)::REAL
               AS hausdorff_dist
            , '%s'::TEXT AS gf_type_bucket
         %%s
         FROM hausdorff_cache AS gf_new
         JOIN hausdorff_cache AS gf_old
            ON (    (gf_new.match_cmd <> 'OKAY')
                --AND (gf_old.match_cmd IS TRUE)
                AND (gf_old.match_cmd <> 'donate')
                --AND (gf_new.branch_id == gf_old.branch_id)
                AND (gf_new.stack_id != gf_old.stack_id)
                AND (ST_DWithin(gf_new.geometry,
                                gf_old.geometry,
                                %s)))
         WHERE 
               ----(gf_new.branch_id == gf_old.branch_id)
               --gf_old.branch_id = %d AND
               --gf_new.branch_id = %d AND
           (gf_new.stack_id != gf_old.stack_id)
           AND gf_new.gf_lyr_id IN (%s)
           AND gf_old.gf_lyr_id IN (%s)
           AND gf_new.match_cmd <> 'OKAY'
           --AND gf_old.match_cmd = 'OKAY'
           AND gf_old.match_cmd <> 'donate'
         %s
         """ % (gf_type_bucket,
                #self.cli_opts.buffer_threshold, # 10 meters
                self.cli_opts.frag_haus_lenient, # 30 meters
                self.qb.branch_hier[0][0],
                self.qb.branch_hier[0][0],
                gfl_ids,
                gfl_ids,
                limit_sql,
                ))

      select_into_sql = cross_join_sql % ("INTO hausdorff_match",)

      time_0 = time.time()

      log.info('Making Hausdorff cross join table: match radius: %s meters'
               #% (self.cli_opts.buffer_threshold,))
               % (self.cli_opts.frag_haus_lenient,))

      rows = self.qb.db.sql(select_into_sql)
      g.assurt(rows is None)

      match_count_sql = "SELECT COUNT(*) FROM hausdorff_match"
      rows = self.qb.db.sql(match_count_sql)
      match_count = rows[0]['count']

      log.debug('match_cache_populate: found %d candidate matches in %s'
         % (match_count, misc.time_format_elapsed(time_0),))

      # We'll all make a few DEV views.

      just_select_sql = cross_join_sql % ('',)

      view_wrapper_sql = (
         """
         SELECT
            gf_old_stack_id                  AS old_sid
            , gf_new_stack_id                AS new_sid
            , to_char(
               hausdorff_dist, '999999D0')   AS Hausdiff
            , SUBSTRING(gf_old_name FOR 40)  AS old_nom
            , SUBSTRING(gf_new_name FOR 40)  AS new_nom
            , gf_old_gf_lyr_nom              AS old_gfl
            , gf_old_one_way                 AS old_1wy
            , gf_old_nneighbr_1              AS old_nn1
            , gf_old_nneighbr_n              AS old_nnn
            , gf_old_match_cmd               AS old_cmd
            , gf_new_gf_lyr_nom              AS new_gfl
            , gf_new_one_way                 AS new_1wy
            , gf_new_nneighbr_1              AS new_nn1
            , gf_new_nneighbr_n              AS new_nnn
            , gf_new_match_cmd               AS new_cmd
         %s
         ORDER BY hausdorff_dist
         """)

      view_fetch_sql = (
         "CREATE OR REPLACE VIEW _hm AS %s"
         % (view_wrapper_sql % ("FROM hausdorff_match",),))
      rows = self.qb.db.sql(view_fetch_sql)

      view_match_sql = (
         "CREATE OR REPLACE VIEW _hm2 AS %s"
         % (view_wrapper_sql
            % ("FROM (%s) AS foo" % just_select_sql,),))
      rows = self.qb.db.sql(view_match_sql)

   #
   # *** Worker threads common setup fcns.
   #

   #
   def setup_importer(self):

      self.qb.item_mgr.start_new_revision(self.qb.db,
         use_latest_rid=self.cli_opts.instance_worker)
      log.debug('Got %s rid_new: %d'
         % ('latest' if self.cli_opts.instance_worker else 'new',
            self.qb.item_mgr.rid_new,))

      if not self.cli_opts.instance_master:
         self.qb.item_mgr.rid_latest_really = True
         # Pin the revision because workers create new versions of items.
         # Each worker is guaranteed to work on unique, non-overlapping sets
         # of items, but items can reference other items, so make sure the
         # references are all the same revision.
         self.qb.revision = revision.Historic(self.qb.item_mgr.rid_new)
         self.qb.branch_hier[0] = (self.qb.branch_hier[0][0],
                                   self.qb.revision,
                                   self.qb.branch_hier[0][2],)
         # Call self.qb.revision.setup_gids(self.qb.db, self.qb.username) or ?:
         #  self.qb.branch_hier_set(self.qb.branch_hier)
      self.qb.item_mgr.load_cache_attachments(self.qb)

      self.attr_to_field = {
         '/byway/speed_limit': 'speedlimit',
         '/byway/lane_count': 'lane_count',
         '/byway/outside_lane_width': 'out_ln_wid',
         '/byway/shoulder_width': 'shld_width',
         '/byway/cycle_facil': 'bike_facil',
         '/byway/cautionary': 'cautionary',
         # Skipping attributes:
         #  /metc_bikeways/bike_facil     branch-specific
         #  /byway/aadt                   not used
         #  /byway/one_way                not used
         #  /byway/cycle_route            not implemented
         #  /byway/no_access              not used
         #  /metc_bikeways/alt_names      meh
         #  /metc_bikeways/from_munis     meh
         #  /metc_bikeways/surf_type      meh
         #  /metc_bikeways/jurisdiction   meh
         #  /metc_bikeways/line_side      meh
         #  /metc_bikeways/agy_oneway     meh
         #  /metc_bikeways/agy_paved      meh
         # We'll copy multi-user attributes deliberately. See below for:
         #  /item/alert_email             see below
         #  /item/reminder_email          deprecated
         #
         }

      self.field_attr_cache_name = {}
      self.field_attr_cache_sid = {}
      if self.cli_opts.item_type == 'byway':
         for attr_name in self.attr_to_field.iterkeys():
            the_attr = attribute.Many.get_system_attr(self.qb, attr_name)
            g.assurt(the_attr is not None)
            self.field_attr_cache_name[
               self.attr_to_field[attr_name]] = the_attr
            self.field_attr_cache_sid[the_attr.stack_id] = the_attr

      self.bad_tag_sids = set()
      if self.cli_opts.item_type == 'byway':
         for bad_tag in Hausdorff_Import.bug_nnnn_bad_tags:
            the_tag = self.qb.item_mgr.cache_tag_lookup_by_name(bad_tag)
            if the_tag is None:
               log.warning('setup_importer: Could not find tag: %s'
                           % (bad_tag,))
            else:
               self.bad_tag_sids.add(the_tag.stack_id)

   #
   # *** Master instance: wait for Ctrl-C
   #

   #
   def instance_master(self):

      log.info('Finalizing revision so workers have a valid rid')

      changenote = self.cli_opts.changenote or 'hausdorff_import'
      # Save the new revision and finalize the sequence numbers.
      group_names_or_ids = self.cli_args.group_ids
      self.finish_script_save_revision(
         group_names_or_ids,
         # Use the user given on the CLI or use the anonymous user.
         self.cli_opts.revision_user or self.qb.username,
         changenote,
         dont_claim_revision=False,
         skip_item_alerts=True)

      rid_new = self.qb.item_mgr.rid_new

      self.cli_args.close_query(do_commit=(not debug_skip_commit))

      log.info('Locking again...')
      # Grab the revision lock again...
      self.query_builder_prepare()

      log.info('Waiting for Ctrl-C...')
      # Cannot wait for Ctrl-C and block at the same time, so loop.
      while not Ccp_Script_Base.master_event.isSet():
         Ccp_Script_Base.master_event.wait(timeout=1)

      log.info('Received Ctrl-C; recomputing revision geometry for gids: %s'
               % (group_names_or_ids,))
      time_0 = time.time()
      revision.Revision.geosummary_update(self.qb.db,
                                          rid_new,
                                          self.qb.branch_hier,
                                          group_names_or_ids)
      misc.time_complain('geosummary_update', time_0, 2.0)

   # **** Process edited items: preprocess Shapefile and load Cyclopath Items

   #
   def process_source_shp(self, source_shp, f_shpfeat, sid_fields=None,
                                                       sid_depends=False):

      self.load_relevant_items(source_shp, sid_fields, sid_depends)

      # Pageinate the source. C.f. compile_stack_ids().
      idx_beg_at = self.cli_opts.items_offset
      idx_fin_at = idx_beg_at + self.cli_opts.items_limit

      with fiona.open(source_shp, 'r') as source_data:

         prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
         #loop_max = (self.cli_opts.items_offset
         #            + self.cli_opts.items_limit) or len(source_data)
         loop_max = self.cli_opts.items_limit or len(source_data)
         #prog_log.setup(prog_log, 1, loop_max)
         prog_log.setup(prog_log, 7500, loop_max)

         log.debug('process_source_shp: processing %s%d feats from %s'
            % ('%d of ' % (loop_max,) if loop_max != len(source_data) else '',
               len(source_data),
               '/'.join([os.path.basename(os.path.dirname(source_shp)),
                         os.path.basename(source_shp)]),))

         cur_idx = 0

         for shpfeat in source_data:

            if (((not idx_fin_at)
                 or ((idx_beg_at <= cur_idx)
                      and (idx_fin_at > cur_idx)))
                and ((not debug_filter_sids)
                     or (ojint(shpfeat['properties']['CCP_ID']
                         in debug_filter_sids)))):

               f_shpfeat(shpfeat)

               if prog_log.loops_inc():
                  break

               if debug_group_shp_writes:
                  if prog_log.progress % prog_log.log_freq == 0:
                     log.debug('Writing features to Shapefiles...')
                     for lyr_name in self.slayers.keys():
                        feat_list = self.intermed_feats[lyr_name]
                        if feat_list:
                           self.slayers[lyr_name].writerecords(feat_list)
                           self.everylayer.writerecords(feat_list)
                           self.intermed_feats[lyr_name] = []
                     # No: self.intermed_feats = {}
            if idx_fin_at and (cur_idx == (idx_fin_at + 1)):
               break
            cur_idx += 1

         # end: for shpfeat in source_data

         prog_log.loops_fin()

         self.record_problem_features(source_data, self.problem_items.values())
         self.problem_items = {}

   #
   def load_relevant_items(self, source_shp, sid_fields=None,
                                             sid_depends=False):

      # Using the features' CCP_ID attributes, compile
      # a list of stack IDs and bulk-load the items.

      # Compile a list of stack IDs.
      stack_ids = self.compile_stack_ids(source_shp, sid_fields, sid_depends)

      if stack_ids:
         # Bulk-load the items.
         self.bulk_load_items(stack_ids)

      self.problem_items = {}

   #
   def compile_stack_ids(self, source_shp, sid_fields=None,
                                           sid_depends=False):

      # If the caller is multi-procing us, we need to select a sequential
      # subset of the features in the source Shapefile. If not, we'll process
      # them all. In either case, compile a list of stack_ids so we can save
      # time by bulk-loading all the items we'll need.

      # Three attributes reference Cyclopath stack IDs:
      #  CCP_ID, OPERATION, and CCP_FROMS_.

      if sid_fields is None:
         sid_fields = ('CCP_ID', 'OPERATION', 'CCP_FROMS_',)

      with fiona.open(source_shp, 'r') as source_data:

         if self.cli_opts.items_limit <= 0:
            feats_slice = source_data
         else:
            feats_slice = []
            idx_beg_at = self.cli_opts.items_offset
            idx_fin_at = idx_beg_at + self.cli_opts.items_limit
            with fiona.open(source_shp, 'r') as source_data:
               log.debug('compile_stack_ids: examining no. features: %s'
                         % (len(source_data),))
               prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
               # We don't break early, so use the total length of the data,
               # and ignore debug_prog_log.debug_break_loop_cnt.
               prog_log.log_freq = 10000
               prog_log.loop_max = len(source_data)
               cur_idx = 0
               for shpfeat in source_data:
                  if ((not idx_fin_at)
                      or ((idx_beg_at <= cur_idx) and (idx_fin_at > cur_idx))):
                     feats_slice.append(shpfeat)
                  if idx_fin_at and (cur_idx == (idx_fin_at + 1)):
                     break
                  cur_idx += 1
                  # NOTE: Don't break early...
                  prog_log.loops_inc()
               prog_log.loops_fin()

         log.debug('compile_stack_ids: found no. features to process: %s'
                   % (len(feats_slice),))

         prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
         prog_log.setup(prog_log, 25000, len(feats_slice))
         stack_ids = set()
         for shpfeat in feats_slice:
            shpfeat_sids = set()
            for prop_name in sid_fields:
               stack_id = None
               possible_sid = shpfeat['properties'][prop_name]
               if possible_sid and (possible_sid != 'D'):
                  try:
                     #possible_sids = ojint(possible_sid)
                     possible_sids = set(ojints(possible_sid))
                     for stack_id in possible_sids:
                        if stack_id > 0:
                           shpfeat_sids.add(stack_id)
                  except ValueError:
                     stack_id = None
                     log.warning('compile_stack_ids: invalid ccp_id: %s'
                                 % (pprint.pformat(shpfeat['properties']),))
               if (stack_id is None) and (sid_depends):
                  break # Next feat; ignore this feat's other fields.
            if ((shpfeat_sids)
                and ((not debug_filter_sids)
                     or (shpfeat_sids.intersection(debug_filter_sids)))):
               stack_ids = stack_ids.union(shpfeat_sids)
            if prog_log.loops_inc():
               break # For debugging; see: debug_prog_log.debug_break_loop_cnt
         prog_log.loops_fin()

      # end: with fiona.open(source_shp, 'r') as source_data

      log.debug('compile_stack_ids: found no. items to load: %s'
                % (len(stack_ids),))
      #if debug_skip_commit:
      #   log.debug(stack_ids)

      return stack_ids

   #
   def bulk_load_items(self, stack_ids):

      self.hydrated_items = {}
      self.processed_sids = set()

      time_0 = time.time()

      prog_log = Debug_Progress_Logger()
      prog_log.setup(prog_log, 7500, len(stack_ids))

      # ProgrammingError: rel. "temp_stack_id__hdi_load_items" already exists
      load_qb = self.qb.clone(db_get_new=True)

      # Since --process-edits can run in parallel with itself, make sure we
      # checkout items in the state of the revision before the one we just
      # created.
      if self.cli_opts.checkout_revision:
         load_qb.revision = revision.Historic(self.cli_opts.checkout_revision)
      else:
         load_qb.revision = revision.Historic(self.qb.item_mgr.rid_new - 1)
      load_qb.branch_hier[0] = (load_qb.branch_hier[0][0],
                                load_qb.revision,
                                load_qb.branch_hier[0][2],)
      # Call load_qb.revision.setup_gids(load_qb.db, load_qb.username) or ?:
      #  load_qb.branch_hier_set(load_qb.branch_hier)

      # self.qb.filters.only_stack_ids = (
      #    ','.join([str(x) for x in stack_ids]))
      # MAYBE: Mightn't we want to use a temporary join table?
      load_qb.load_stack_id_lookup('hdi_load_items', stack_ids)

      load_qb.filters.include_item_stack = True

      # See: byway's update_clauses_rating_special.
      load_qb.filters.rating_special = True

      load_qb.filters.make_geometry_ewkt = True

      item_module = item_factory.get_item_module(self.cli_opts.item_type)
      g.assurt(item_module is not None)

      load_qb.item_mgr.load_feats_and_attcs(
         load_qb,
         item_module,
         feat_search_fcn='search_for_items',
         processing_fcn=self.collect_hydrated,
         prog_log=prog_log,
         heavyweight=True,
         fetch_size=0,
         keep_running=None,
         diff_group=None,
         load_groups_access=True)

      # self.qb.filters.only_stack_ids = ''
      load_qb.filters.stack_id_table_ref = ''
      load_qb.filters.include_item_stack = False

      log.debug('bulk_load_items: collected %d items in %s'
                % (prog_log.progress,
                   misc.time_format_elapsed(time_0),))

   #
   def collect_hydrated(self, qb, bway, prog_log):

      # This fcn. is not very resource friendly. Gobble gobble gobble!

      self.hydrated_items[bway.stack_id] = bway

   # Used just by process_edits.
   def problem_items_add(self, shpfeat):

      new_props = {}
      for fldn, rown in self.target_schema['properties'].iteritems():
         try:
            new_props[fldn] = shpfeat['properties'][fldn]
         except KeyError:
            new_props[fldn] = None
      shpfeat['properties'] = new_props

      #self.problem_items[shpfeat['properties']['OBJECTID']] = shpfeat
      self.problem_items[shpfeat['id']] = shpfeat

   # Used just by process_edits.
   def record_problem_features(self, source_data, problems_list):

      if problems_list:

         problems_path = os.path.join(self.target_path, 'layer-problems.shp')
         problems_lock = os.path.join(self.target_path, 'layer-problems.lock')

         log.debug('record_problem_features: flocking problems shapefile...')

         try:
            probs_lock = open(problems_lock, 'w')
            fcntl.flock(probs_lock.fileno(), fcntl.LOCK_EX)
         except IOError, e:
            probs_lock = None
            log.error('Unable to open and lock problems file: %s' % (str(e),))

         if probs_lock is not None:
            log.debug('record_problem_feats: recording no. problem feats: %s'
                      % (len(problems_list),))
            try:
               layer_problems = None
               target_crs = self.get_crs_from_srid(
                        self.cli_opts.shapefile_srid)
               if not os.path.exists(problems_path):
                  # First worker.
                  layer_problems = fiona.open(
                     problems_path, 'w',
                     crs=target_crs,
                     driver=self.cli_opts.shapefile_driver,
                     schema=self.target_schema)
               else:
                  # Second or subsequent worker.
                  layer_problems = fiona.open(
                     problems_path, 'a',
                     crs=target_crs,
                     driver=self.cli_opts.shapefile_driver,
                     schema=self.target_schema)
               if not debug_writerecords_1x1:
                  layer_problems.writerecords(problems_list)
               else:
                  # If you need to debug, run through this path.
                  prog_log = Debug_Progress_Logger(
                     copy_this=debug_prog_log_match)
                  prog_log.setup(prog_log, 10000, len(problems_list))
                  for problem_feat in problems_list:
                     layer_problems.write(problem_feat)
                     if prog_log.loops_inc():
                        break
                  prog_log.loops_fin()
            except Exception, e:
               log.error('record_problem_feats: failed: %s' % (str(e),))
            finally:
               if layer_problems is not None:
                  layer_problems.close()
               fcntl.flock(probs_lock.fileno(), fcntl.LOCK_UN)

         self.stats['problem_items'] += len(problems_list)

   #
   # *** Line Matching fcns.
   #

   #
   def try_matching(self):

      self.stats_init_matching()

      try:

         target_crs = self.get_crs_from_srid(self.cli_opts.shapefile_srid)
         if self.cli_opts.show_conflations:
            target_schema = Hausdorff_Import.fragment_schema
         else:
            target_schema = Hausdorff_Import.matching_schema
         target_driver = self.cli_opts.shapefile_driver
         try:
            self.prepare_target_shapefiles(target_schema,
                                           touch_note='note_matched')
         except Exception, e:
            log.error('Unable to prepare targets: %s' % (str(e),))
            raise

         self.iterate_matches()

      finally:

         for shpfile in self.slayers.values():
            try:
               shpfile.close()
            except:
               pass
         self.slayers = None
         try:
            self.everylayer.close()
         except:
            pass
         self.everylayer = None

      self.symlink_target_shapefiles(link_name='Conflated')

      self.stats_show_matching()

   # **** Matching fcns.

   matching_fields = [
      #  1234567890
      (u'GUIDANCE', 'str',),
      (u'OPERATION', 'str',),
      (u'CCP_ID', 'int:9',),
      (u'CCP_NAME', 'str',),
      (u'CCP_FROMS_', 'str',),
      (u'verdict', 'str',),
      (u'matches', 'str',),
      (u'gf_lyr_nom', 'str',),
      #(u'Shape_Leng', 'float:19.11',),
      (u'new_length', 'float:19.11',),
      (u'import_err', 'str',),
      (u'speedlimit', 'int:9',),
      (u'lane_count', 'int:9',),
      (u'item_tags', 'str',),
      (u'z_level', 'int:9',),
      (u'one_way', 'int:9',),
      (u'out_ln_wid', 'int:9',),
      (u'shld_width', 'int:9',),
      (u'bike_facil', 'str',),
      (u'cautionary', 'str',),
      (u'wconnected', 'str',),
      (u'wangdangle', 'str',),
      (u'nneighbr_1', 'int:9',),
      (u'nneighbr_n', 'int:9',),
      (u'gf_lyr_id',  'int:9',),
      (u'gfl_typish', 'str',),
      (u'CCP_SYS', 'int:9',),
      (u'CCP_VERS', 'int:9',),
      #(u'OBJECTID', 'int:9',),
      # Deprecated:
      #(u'ACTION_', 'str',),
      #(u'CONTEXT_', 'str',),
      ]

   #matching_lookup = {}
   #for tup in matching_fields:
   #   matching_lookup[tup[0]] = tup[1]

   matching_schema = {
      'geometry': 'LineString',
      'properties': OrderedDict(matching_fields),
      }

   # These are the 10-char-or-less Shapefile output fields.
   # NOTE: The order determines the default column ordering in OpenJUMP et al.
   fragment_fields = [
      #  1234567890
      (u'GUIDANCE', 'str',),
      (u'OPERATION', 'str',),
      (u'CCP_ID', 'int:9',),
      (u'old_stk_id', 'int:9',),
      (u'CCP_FROMS_', 'str',),
      (u'verdict', 'str',),
      (u'matches', 'str',),
      (u'mstrength1', 'int:9',),
      (u'mstrength2', 'int:9',),
      (u'mstrength3', 'int:9',),
      (u'mstrength4', 'int:9',),
      (u'reasoning', 'str',),
      (u'gf_lyr_nom', 'str',),
      (u'CCP_NAME', 'str',),
      (u'old_name', 'str',),
      (u'leven_norm', 'int:9',),
      (u'addy_match', 'int:9',),
      #(u'Shape_Leng', 'float:19.11',),
      (u'new_length', 'float:19.11',),
      (u'old_length', 'float:19.11',),
      (u'raw_len_nm', 'int:9',),
      (u'old_len_nm', 'int:9',),
      (u'new_len_nm', 'int:9',),
      (u'frg_len_nm', 'int:9',),
      (u'haus_dist', 'float:19.11',),
      (u'haus_norm', 'int:9',),
      (u'frag_haus', 'float:19.11',),
      (u'frag_norm', 'int:9',),
      #(u'frag1_len', 'float:19.11',),
      #(u'frag1_norm', 'int:9',),
      #(u'frag2_len', 'float:19.11',),
      #(u'frag2_norm', 'int:9',),
      (u'import_err', 'str',),
      (u'speedlimit', 'int:9',),
      (u'lane_count', 'int:9',),
      (u'item_tags', 'str',),
      (u'z_level', 'int:9',),
      (u'one_way', 'int:9',),
      (u'out_ln_wid', 'int:9',),
      (u'shld_width', 'int:9',),
      (u'bike_facil', 'str',),
      (u'cautionary', 'str',),
      (u'wconnected', 'str',),
      (u'wangdangle', 'str',),
      (u'nneighbr_1', 'int:9',),
      (u'nneighbr_n', 'int:9',),
      (u'gf_lyr_id',  'int:9',),
      (u'gfl_typish', 'str',),
      (u'old_gfl_tp', 'str',),
      (u'CCP_SYS', 'int:9',),
      (u'CCP_VERS', 'int:9',),
      #(u'OBJECTID', 'int:9',),
      # Deprecated:
      #(u'ACTION_', 'str',),
      #(u'CONTEXT_', 'str',),
      ]

   fragment_lookup = {}
   for tup in fragment_fields:
      fragment_lookup[tup[0]] = tup[1]

   fragment_schema = {
      'geometry': 'LineString',
      'properties': OrderedDict(fragment_fields),
      }

   match_fields = {
      #'GUIDANCE': ,
      #'OPERATION': ,
      #'CCP_ID',
      'old_stk_id': 'gf_old_stack_id',
      'verdict': 'verdict',
      'matches': 'matches',
      'mstrength1': 'mstrength1',
      'mstrength2': 'mstrength2',
      'mstrength3': 'mstrength3',
      'mstrength4': 'mstrength4',
      'reasoning': 'reasoning',
      #'CCP_NAME': 'gf_new_name',
      'old_name': 'gf_old_name',
      'leven_norm': 'leven_norm',
      'addy_match': 'addy_match',
      #'Shape_Leng',
      'new_length': 'gf_new_length',
      'old_length': 'gf_old_length',
      'raw_len_nm': 'raw_len_nm',
      'old_len_nm': 'gf_old_frag_norm',
      'new_len_nm': 'gf_new_frag_norm',
      'frg_len_nm': 'frg_len_nm',
      'haus_dist': 'hausdorff_dist',
      'haus_norm': 'haus_norm',
      'frag_haus': 'frag_haus',
      'frag_norm': 'frag_norm',
      #'frag1_len': 'frag1_len',
      #'frag1_norm': 'frag1_norm',
      #'frag2_len': 'frag2_len',
      #'frag2_norm': 'frag2_norm',
      #'CCP_FROMS_',
      #'import_err',
      #'gf_lyr_nom': 'gf_new_gf_lyr_nom',
      'old_gfl_tp': 'gf_old_gf_lyr_nom',
      #'speedlimit',
      #'lane_count',
      #'item_tags',
      #'z_level',
      #'one_way',
      #'out_ln_wid',
      #'shld_width',
      #'bike_facil',
      #'cautionary',
      #'wconnected',
      #'wangdangle',
      #'nneighbr_1',
      #'nneighbr_n',
      #'gf_lyr_id',
      #'gfl_typish',
      #'CCP_SYS',
      #'CCP_VERS',
      #'OBJECTID',
      #'ACTION_',
      #'CONTEXT_',
      }

   #
   def iterate_matches(self):

      limit_offset_sql = ""
      if self.cli_opts.items_limit > 0:
         limit_offset_sql = (
            "LIMIT %d OFFSET %d"
            % (self.cli_opts.items_limit,
               self.cli_opts.items_offset,))

      fetch_matches_sql = (
         """
         SELECT
              --gf_old_branch_id,
              gf_old_stack_id
            , gf_old_name
            , gf_old_gf_lyr_nom
            , gf_old_gf_lyr_id
            , gf_old_one_way
            , gf_old_nneighbr_1
            , gf_old_nneighbr_n
            , gf_old_match_cmd
            , gf_old_geometry
            , ST_AsText(gf_old_geometry) AS gf_old_geometry_wkt
            , ST_Length(gf_old_geometry) AS gf_old_length
            , ST_StartPoint(gf_old_geometry) AS gf_old_lhs_pt
            , ST_EndPoint  (gf_old_geometry) AS gf_old_rhs_pt
            , ST_AsText(ST_StartPoint(gf_old_geometry)) AS gf_old_lhs_pt_wkt
            , ST_AsText(ST_EndPoint  (gf_old_geometry)) AS gf_old_rhs_pt_wkt
            --
            --, gf_new_branch_id
            , gf_new_stack_id
            , gf_new_name
            , gf_new_gf_lyr_nom
            , gf_new_gf_lyr_id
            , gf_new_one_way
            , gf_new_nneighbr_1
            , gf_new_nneighbr_n
            , gf_new_match_cmd
            , gf_new_geometry
            , ST_AsText(gf_new_geometry) AS gf_new_geometry_wkt
            , ST_Length(gf_new_geometry) AS gf_new_length
            , ST_StartPoint(gf_new_geometry) AS gf_new_lhs_pt
            , ST_EndPoint  (gf_new_geometry) AS gf_new_rhs_pt
            , ST_AsText(ST_StartPoint(gf_new_geometry)) AS gf_new_lhs_pt_wkt
            , ST_AsText(ST_EndPoint  (gf_new_geometry)) AS gf_new_rhs_pt_wkt
            --
            , hausdorff_dist
            , gf_type_bucket
         FROM hausdorff_match
         WHERE gf_type_bucket = 'shared_use'
         ORDER BY hausdorff_dist
         %s
         """ % (limit_offset_sql,))

      iter_db = self.qb.db.clone()

      # MAYBE: Use dont_fetchall...
      iter_db.dont_fetchall = True

      log.debug('try_matching: loading query...')

      rows = iter_db.sql(fetch_matches_sql)

      log.debug('try_matching: processing %d matches...'
                % (iter_db.rowcount(),))

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log_match)
      prog_log.setup(prog_log, 10000, iter_db.rowcount())

      self.analyzed_sids = set()

      suspects = []

      generator = iter_db.get_row_iter()
      for row_hm in generator:

         if (debug_filter_sids
             and (row_hm['gf_new_stack_id'] not in debug_filter_sids)
             and (row_hm['gf_old_stack_id'] not in debug_filter_sids)):
            continue

         #log.debug('try_matching: row_hm: %s' % (row_hm,))

         # Some Levenshtein examples:
         #
         #  'City Centre Dr' / 'City Centre Dr'
         #  - distance: 0 / ratio: 1.0
         #
         #  'Radio Dr / County Hwy 13' / 'Radio Dr'
         #  - distance: 16 / ratio: 0.5
         #
         #  'Hargis Pkwy' / 'Hargis Rabt'
         #  - distance: 4 / ratio: 0.636363636364
         #
         #  'Pilot Knob Rd / County Hwy 31' / 'Pilot Knob Rd'
         #  - distance: 16 / ratio: 0.619047619048
         #
         #  '' / 'Petersburg St'
         #  - distance: 13 / ratio: 0.0
         #
         #  '89th St W' / 'Aviary Path'
         #  - distance: 10 / ratio: 0.2

         # Not needed...
         #ldist = Levenshtein.distance(row_hm['gf_old_name'],
         #                             row_hm['gf_new_name'])
         ##log.debug('Levenshtein.distance: %s' % (ldist,))

         lratio = Levenshtein.ratio(row_hm['gf_old_name'],
                                    row_hm['gf_new_name'])
         #log.debug('Levenshtein.ratio: %s' % (lratio,))

         # Stats are 0 to 100, inclusive, representing 0.00 to 1.00.
         levenormalized = int(round(lratio, 2) * 100)
         misc.dict_count_inc(self.stats['levenshtein_rat'], levenormalized)

         row_hm['leven_norm'] = levenormalized

         self.hausdorff_bucket_add(self.stats['hausd_dist_raw'],
                                   row_hm['hausdorff_dist'])

         self.analyze_suspect_row(row_hm, lratio, suspects)

         if prog_log.loops_inc():
            break

      iter_db.close()

      prog_log.loops_fin()

      self.record_match_results(suspects)

   #
   def analyze_suspect_row(self, row_hm, lratio, suspects):

      self.analyzed_sids.add(row_hm['gf_new_stack_id'])

      if (not row_hm['gf_old_length']) or (not row_hm['gf_new_length']):

         log.warning('analyze_suspect_row: no len? %s' % (row_hm,))
         row_hm['verdict'] = 'unrelated'
         self.mstrength_init(row_hm)
         row_hm['reasoning'] = 'zero-length raw geometry'
         suspects.append(row_hm)

      else:

         self.segmentized_hausdorff(row_hm, lratio, suspects)
         suspects.append(row_hm)

   #
   def segmentize_line(self, row_hm, segmentee_prefix, segmentor_prefix):

      # There are lots of ways that two lines might relate spactial, but with
      # road geometry, we general see a handful of varieties:
      # 1. Un-segmentized vs. segmentized
      #    E.g., in one layer, a single line segment is 1000 m long,
      #          but in the other layer, that logical road is represented
      #          by 10 100m-long line segments.
      # 1b. Staggered/overlapping segments
      #    E.g., a road from an intersection passed a driveway before going
      #          under a bridge and then finding another intersection. In one
      #          layer, there are two line segments, broken at the bridge
      #          line; in the other layer, there are also two line segments,
      #          but broken at the driveway.
      # The conflation process calculates the Hausdorff using just the
      # overlapping line segment and ignores both layers' tails. So the
      # fragment segments are less than or equal to the length of their
      # source line, and the Hausdorff is pretty tight.
      # 2. The cul-de-sac
      #    E.g., imagine a straight line next to one U-shaped: |), or D.
      #    Here, the fragment segments are likely the same as their source
      #    lines, but the Hausdorff will be large.
      # 3. The highway crossing.
      #    E.g., two lines represent the highway couplets, and there's a
      #    line segment making the network connection where a road crosses.
      #    The crossing segment and the two segments of the crossing road
      #    will be analzed, and the projection of one line on to the other
      #    will create a fragment segment will little or no length, so we
      #    probably won't even need to calculate the Hausdorff. For small
      #    connecting lines -- like, 1 m -- we may need human help, or
      #    maybey we just assume that small line segments aren't likely
      #    to be duplicates? except when they are...
# FIXME: Audit small line segments, too!

      segmentee_geom = row_hm['%s_geometry' % (segmentee_prefix,)]
      segmentee_len = row_hm['%s_length' % (segmentee_prefix,)]

      #segmentor_geom = row_hm['%s_geometry' % (segmentor_prefix,)]
      segmentor_wkt = row_hm['%s_geometry_wkt' % (segmentor_prefix,)]
      #segmentor_len = row_hm['%s_length' % (segmentor_prefix,)]
      segmentor_lhs_pt = row_hm['%s_lhs_pt' % (segmentor_prefix,)]
      segmentor_rhs_pt = row_hm['%s_rhs_pt' % (segmentor_prefix,)]

      # NOTE: ST_Line_Locate_Point renamed ST_LineLocatePoint in PostGIS 2.1.0.
      beg_fragment_sql = (
         "(SELECT ST_Line_Locate_Point('%s'::GEOMETRY, '%s'::GEOMETRY))"
         % (segmentee_geom, segmentor_lhs_pt,))
      fin_fragment_sql = (
         "(SELECT ST_Line_Locate_Point('%s'::GEOMETRY, '%s'::GEOMETRY))"
         % (segmentee_geom, segmentor_rhs_pt,))

      line_substring_sql = (
         """
         SELECT
            substring_geom AS fragment_geom
            , ST_Length(substring_geom) AS fragment_length
         FROM (
            SELECT
               CASE WHEN %s < %s THEN
                  ST_AsText(ST_Line_Substring('%s'::GEOMETRY, %s, %s))
               ELSE
                  ST_AsText(ST_Line_Substring('%s'::GEOMETRY, %s, %s))
               END AS substring_geom
               ) AS foo
         """ % (beg_fragment_sql,
                fin_fragment_sql,
                #
                segmentee_geom,
                beg_fragment_sql,
                fin_fragment_sql,
                #
                segmentee_geom,
                fin_fragment_sql,
                beg_fragment_sql,
                ))

      rows = self.qb.db.sql(line_substring_sql)

      g.assurt(len(rows) == 1)
      row = rows[0]

      frag_xys = geometry.wkt_line_to_xy(row['fragment_geom'])
      row_hm['%s_frag_xys' % (segmentor_prefix,)] = frag_xys

      frag_len = row['fragment_length']
      row_hm['%s_frag_len' % (segmentor_prefix,)] = frag_len

      frag_len_ratio = 1.0 - (abs(segmentee_len - frag_len) / segmentee_len)
      frag_len_normd = int(round(frag_len_ratio, 2) * 100)
      misc.dict_count_inc(self.stats['%s_frag_len_norm' % (segmentor_prefix,)],
                                     frag_len_normd)
      row_hm['%s_frag_norm' % (segmentor_prefix,)] = frag_len_normd

      return frag_xys, frag_len, frag_len_ratio, frag_len_normd

   #
   def segmentized_hausdorff(self, row_hm, lratio, suspects):

      # Calculate segmented Hausdorff difference.

      (old_frag_xys, old_frag_len, old_frag_len_ratio, old_frag_len_normd,
         ) = self.segmentize_line(row_hm, 'gf_old', 'gf_new')
      (new_frag_xys, new_frag_len, new_frag_len_ratio, new_frag_len_normd,
         ) = self.segmentize_line(row_hm, 'gf_new', 'gf_old')

      hd_tup = geometry.hausdorff_distance(old_frag_xys, new_frag_xys)
      frag_haus = hd_tup[0]
      row_hm['frag_haus'] = frag_haus
      self.hausdorff_bucket_add(self.stats['hausd_dist_seg'], frag_haus)
      #
      frag_ratio = geometry.normalize_hausdorff(old_frag_xys, new_frag_xys,
                                                frag_haus)
      frag_norm = int(round(frag_ratio, 2) * 100)
      row_hm['frag_norm'] = frag_norm
      misc.dict_count_inc(self.stats['frag_hausdo_rat'], frag_norm)

      # Calculate old/new line length ratio.
      # The ratio is from 0 to 1, 1 being the same length lines,
      # and 1 being infinitely different lengths.
      old_len = row_hm['gf_old_length']
      new_len = row_hm['gf_new_length']
      longest_len = float(max(old_len, new_len))
      orig_pair_len_ratio = 1.0 - (abs(old_len - new_len)
                                   / longest_len)
      orig_pair_len_norm = int(round(orig_pair_len_ratio, 2) * 100)
      misc.dict_count_inc(self.stats['orig_pair_len_norm'], orig_pair_len_norm)
      row_hm['raw_len_nm'] = orig_pair_len_norm

      # Calculate shortest/longest line length ratio.
      shortest_len = float(min(old_frag_len, new_frag_len))
      frag_pair_len_ratio = 1.0 - (abs(longest_len - shortest_len)
                                   / longest_len)
      frag_pair_len_norm = int(round(frag_pair_len_ratio, 2) * 100)
      misc.dict_count_inc(self.stats['frag_pair_len_norm'], frag_pair_len_norm)
      row_hm['frg_len_nm'] = frag_pair_len_norm

      # See if the two lines share any nodes.

# FIXME: LOOK FOR CUL-DE-SAC and EXTENDED DEAD-END, and for node sharing.

# We need to the network graph like in init to
#   determine dead endness.
# We can compare x,y of endpts (a1-b1, a1-b2, a2-b1, a2-b2)
# but to determine dangleness... ya know, maybe do that in
# init, instead!
# wangdangle

      old_geom_xy = geometry.wkt_line_to_xy(
         row_hm['gf_old_geometry_wkt'], conf.node_precision)
      new_geom_xy = geometry.wkt_line_to_xy(
         row_hm['gf_new_geometry_wkt'], conf.node_precision)
      shared_endpts_ = set(
            [old_geom_xy[0], old_geom_xy[-1],
             new_geom_xy[0], new_geom_xy[-1],])
      #
      old_geom_xy_1 = geometry.wkt_point_to_xy(
         row_hm['gf_old_lhs_pt_wkt'], conf.node_precision)
      old_geom_xy_n = geometry.wkt_point_to_xy(
         row_hm['gf_old_rhs_pt_wkt'], conf.node_precision)
      new_geom_xy_1 = geometry.wkt_point_to_xy(
         row_hm['gf_new_lhs_pt_wkt'], conf.node_precision)
      new_geom_xy_n = geometry.wkt_point_to_xy(
         row_hm['gf_new_rhs_pt_wkt'], conf.node_precision)
      shared_endpts = set(
            [old_geom_xy_1, old_geom_xy_n,
             new_geom_xy_1, new_geom_xy_n,])

      # Calculate normalized total Hausdorff distance.
      haus_ratio = geometry.normalize_hausdorff(old_geom_xy, new_geom_xy,
                                                row_hm['hausdorff_dist'])
      haus_norm = int(round(haus_ratio, 2) * 100)
      row_hm['haus_norm'] = haus_norm
      misc.dict_count_inc(self.stats['raw_hausdo_rat'], haus_norm)

      # MAYBE: Do the two lines intersect? Multiple times?
      #        What's the Hausdorff of opposite side segments?
      #        What's the general direction of each line (from
      #         one endpt to the other)?

      # Take another look at the street name.
      self.stats['name_cmps']['all'] += 1
      good_addy_match = False
      row_hm['addy_match'] = ''
      if row_hm['leven_norm'] >= 100:
         row_hm['addy_match'] = 'equal'
         good_addy_match = True
         self.stats['name_cmps']['equal'] += 1
      else:
         # Names are not equal. See if they're similar in some specific ways
         # you'll probably see in the data.

# FIXME: In process-edits, merge street name.
# Split on '/', e.g., "Main St / US Hwy 2"
         # MAYBE: Use streetaddress to compare street name (and ignore prefixes
         # and suffixes, so, e.g., "Main St" and "E Main" would register
         # as similarly named streets (whose name is maybe, "E Main St")).
         # NOTE: To use the parser, add a house number and municipalities.
         old_addyp = self.parse_streetaddy(row_hm['gf_old_name'])
         new_addyp = self.parse_streetaddy(row_hm['gf_new_name'])
         if not old_addyp:
            row_hm['addy_match'] = 'invalid old'
            log.debug('segmntzd_hausdorff: old name not addyable: %s (%d)'
                      % (row_hm['gf_old_name'], row_hm['gf_old_stack_id'],))
            # This happens when the name is multiple names, e.g.,
            #  "Hill And Dale Dr NW / County Rd 70"
            # MAYBE: Compare component route names... ug, that seems tedious.
         if not new_addyp:
            # See previous comments; we could split on '/' and compare
            # individual route names... but that seems like hard work.
            # Would it be worth it?
            row_hm['addy_match'] = 'invalid new'
            log.debug('segmntzd_hausdorff: new name not addyable: %s (%d)'
                      % (row_hm['gf_new_name'], row_hm['gf_new_stack_id'],))
         if not row_hm['addy_match']:
            if old_addyp['street'] == new_addyp['street']:
               row_hm['addy_match'] = 'streets'
               self.stats['name_cmps']['streets'] += 1
            # Even if the streets match, the match might be stronger.
            if (row_hm['gf_old_name'].startswith(row_hm['gf_new_name'])
                or row_hm['gf_new_name'].startswith(row_hm['gf_old_name'])):
               row_hm['addy_match'] = 'begins'
               good_addy_match = True
               self.stats['name_cmps']['starts'] += 1
            else:
               try:
                  row_hm['gf_old_name'].index(row_hm['gf_new_name'])
                  row_hm['addy_match'] = 'contains'
                  self.stats['name_cmps']['within'] += 1
                  good_addy_match = True
               except ValueError:
                  pass
               try:
                  row_hm['gf_new_name'].index(row_hm['gf_old_name'])
                  row_hm['addy_match'] = 'contains'
                  self.stats['name_cmps']['within'] += 1
                  good_addy_match = True
               except ValueError:
                  pass

      if good_addy_match:
         # What's the leven distribution for our simple algorithm:
         self.stats['name_cmps']['good_match'] += 1
         misc.dict_count_inc(self.stats['name_cmps']['leven_distrib'],
                             row_hm['leven_norm'])

      #
      if (not old_frag_len_ratio) or (not new_frag_len_ratio):
         self.mstrength_init(row_hm)
         #row_hm['GUIDANCE'] = 'no_haus'
         row_hm['verdict'] = 'keep' # segments unrelated
         row_hm['reasoning'] = 'zero-len-frag-geom'
      else:
         flags = []
         # hausdorff is 0+ m; frag_ratio is 0 to 1
         # leven_norm is from 0 to 1, 1 being exact match;
         # frag_len_ratio is 0 to 1, 1 being an exact match.
         if frag_ratio >= 0.75:
            #row_hm['GUIDANCE'] = 'good_frag'
            row_hm['verdict'] = 'copy attrs' # duplicate segment
            flags.append('+frag-hausn')
         else:
            #row_hm['GUIDANCE'] = 'poor_haus'
            row_hm['verdict'] = 'keep' # might be a unique item
            flags.append('-frag-hausn')
         if (row_hm['hausdorff_dist']
             <= self.cli_opts.buffer_threshold): # <= 10 meters
            #row_hm['GUIDANCE'] = 'update'
            row_hm['verdict'] = 'copy attrs' # looks like a duplicate
            flags.append('+good-hausd')
      # FIXME: Does this work as intended?:
         # If donate item, be a little more lenient...
         elif ((row_hm['gf_new_match_cmd'] == 'donate')
               and (row_hm['hausdorff_dist']
                    <= (self.cli_opts.buffer_threshold * 2))): # <= 20 meters
            #row_hm['GUIDANCE'] = 'update'
            row_hm['verdict'] = 'copy attrs' # looks like a duplicate
            flags.append('+loose-hausd')
      # FIXME: What's a good value here?
         if row_hm['haus_norm'] >= 0.75:
            row_hm['verdict'] = 'copy attrs' # duplicate segment
            flags.append('+base-hausn')
# These overwrite any "copy ..." we may have decided...
         if (row_hm['frag_haus']
             > (self.cli_opts.frag_haus_lenient # 30 meters
                 if good_addy_match
                 else self.cli_opts.frag_haus_max)): # 10 meters
            #row_hm['GUIDANCE'] = 'poor_haus' 
            row_hm['verdict'] = 'keep' # maybe a unique item
            flags.append('-frag-hausd')
         if (min(old_frag_len, new_frag_len)
             < self.cli_opts.fragment_minimum): # < 4 meters
            #row_hm['GUIDANCE'] = 'too_short'
            row_hm['verdict'] = 'unsure' # cannot guess; need user's help
            flags.append('-short-frags')
         if len(shared_endpts) == 2:
            # The two lines share the same endpoints. They're
            # probably duplicates, if not couplets, if they're
            # one-ways. Without further analysis, our lame stab
            # at a guess says we'll say these are duplicates if
            # there's a strong name match and the lines are not
            # one-ways, otherwise we'll defer action to the user.
            #row_hm['GUIDANCE'] = 'same_endpts'
            if ((not good_addy_match)
                or (row_hm['gf_old_one_way'])
                or (row_hm['gf_new_one_way'])):
               row_hm['verdict'] = 'unsure'
               flags.append('-couplets')
         #if len(shared_endpts) == 3:
         #   # MAYBE: We could also assume two endpoints are "the same" if
         #   # they're within some threshold, like, the size of an
         #   # intersection... but the line segment would have to be
         #   # longer than a certain length, to know we're dealing with,
         #   # e.g., a city street and not an intersection connector.
         #   # Then we could determine if the old line is a deadend and
         #   # the new line is a new, extended road.
         #   pass
         if row_hm['verdict'].startswith('copy'):
            both_dead_ends = False
            if ((row_hm['gf_old_nneighbr_1'] == 1)
                or (row_hm['gf_old_nneighbr_n'] == 1)):
               if ((row_hm['gf_new_nneighbr_1'] > 1)
                   and (row_hm['gf_new_nneighbr_n'] > 1)):
                  # Extended dead-end; new is longer.
                  #row_hm['GUIDANCE'] = 'undeadended_new'
                  row_hm['verdict'] = 'copy geom'
                  flags.append('-deadend-new')
               else:
                  both_dead_ends = True
            elif ((row_hm['gf_new_nneighbr_1'] == 1)
                  or (row_hm['gf_new_nneighbr_n'] == 1)):
               if ((row_hm['gf_old_nneighbr_1'] > 1)
                   and (row_hm['gf_old_nneighbr_n'] > 1)):
                  # Extended dead-end; old is longer.
                  #row_hm['GUIDANCE'] = 'undeadended_old'
                  row_hm['verdict'] = 'copy attrs'
                  flags.append('-deadend-old')
               else:
                  both_dead_ends = True
            if both_dead_ends:
               if row_hm['gf_new_length'] > row_hm['gf_old_length']:
                  #row_hm['GUIDANCE'] = 'extendeadend_new'
                  row_hm['verdict'] = 'copy geom'
                  flags.append('+deadend-new')
               elif row_hm['gf_old_length'] > row_hm['gf_new_length']:
                  #row_hm['GUIDANCE'] = 'extendeadend_old'
                  row_hm['verdict'] = 'copy attrs'
                  flags.append('+deadend-old')
               else:
                  #row_hm['GUIDANCE'] = 'deadends_same_len'
                  row_hm['verdict'] = 'copy attrs'
                  flags.append('deadends-same')



   # FIXME: If good raw or frag haus, compare one-way values... determine if
   #        direction is same or opposite, or if one is one-way and the other
   #        is not. Maybe the two lines are couplets, or one is the old
   #        two-way/one-way and the other is the new couplet/two-way.



# FIXME: If the old name is not set but the new one is: probably a new
#        development replaced an old, unnamed road...
#        so level_norm should not be as important...
#        ALSO: the duplicate-feature 'copy *' verdict does not consider
#              the name...

         # Match Strength confidence. This is just a wild guess.
         if True:
            row_hm['mstrength1'] = int(
                 ((1.0/3.0) * row_hm['leven_norm'])
               + ((1.0/3.0) * frag_norm)
               + ((1.0/6.0) * old_frag_len_normd)
               + ((1.0/6.0) * new_frag_len_normd)
               )
         if True:
            row_hm['mstrength2'] = int(
                 ((1.0/2.0) * row_hm['leven_norm'])
               + ((1.0/2.0) * frag_norm)
               )
         if True:
            row_hm['mstrength3'] = int(
                 ((1.0/3.0) * row_hm['leven_norm'])
               + ((1.0/3.0) * frag_norm)
               + ((1.0/3.0) * frag_pair_len_norm)
               )
         if True:
            haus_frag_norm = int(round(frag_ratio * frag_pair_len_ratio, 2)
                                 * 100)
            row_hm['mstrength4'] = int(
                 ((1.0/2.0) * row_hm['leven_norm'])
               + ((1.0/2.0) * haus_frag_norm)
               )
         row_hm['reasoning'] = ' '.join(flags) if flags else ''

      # end: else not: if (not old_frag_len_ratio) or (not new_frag_len_ratio)

   #
   def parse_streetaddy(self, route_name):

      # Weird: There's an item named "Bone Lake Route, Scandia, MN"
      # already in the db...
      if route_name.count(',') == 0:
         addr_example = '123 %s, City, MN' % (route_name,)
      elif route_name.count(',') == 1:
         addr_example = '123 %s, MN' % (route_name,)
      else:
         addr_example = '123 %s' % (route_name,)
      addyp = streetaddress.parse(addr_example)
      if not addyp:
         addyp = streetaddress.parse(route_name)

      if addyp:

         try:
            if ((int(addyp['number']) != 123)
                  and (addyp['city'] != 'MPLS')
                  and (addyp['state'] != 'MN')):
               log.debug('parse_streetaddy: parsed odd/1: %s' % (route_name,))
               addyp = None
            # else, addr parsed our fake data correctly.
         except KeyError:
            log.debug('parse_streetaddy: parsed odd/2: %s' % (route_name,))
            addyp = None

         if addyp is not None:

            unprepared = False
            for component in ('unit',
                              'unit_prefix',
                              'postal_code',
                              'postal_code_ext',):
               try:
                  if addyp[component]:
                     unprepared = True
                     break
               except KeyError:
                  pass

            if unprepared:
               log.debug('parse_streetaddy: parsed odd/3: %s' % (route_name,))
               addyp = None

         if addyp is not None:

            for component in ('street',
                              'street_type',):
               if addyp[component]:
                  #addyp[component] = ' '.join(
                  #   [x.capitalize() if x not in ('US',) else x
                  #    for x in addyp[component].split() if x])
                  # Capitalize some words, lower case others, and upper others.
                  new_val = []
                  for word in addyp[component].split():
                     if (   (word == 'US')
                         or (word in addressconf.States.FIPS_STATES)
                         or (word.startswith('UT-'))):
                        new_val.append(word)
                     elif word in ('OF',):
                        new_val.append(word.lower())
                     else:
                        new_val.append(word.capitalize())
                  addyp[component] = ' '.join(new_val)

      return addyp

   #
   def record_match_results(self, suspects):

      unique_matches = set() # For DEV logging.
      matches_by_new = {} # To find row_hm by stack ID.
      split_into_donatees = {}
      for row_hm in suspects:
         # Use a dict list b/c each line seg may have been many times suspect.
         misc.dict_list_append(
            matches_by_new, row_hm['gf_new_stack_id'], row_hm)
         unique_matches.add(row_hm['gf_new_stack_id'])
         # Figure out what items are marked duplicates of others, so we can
         # mark the others' CCP_FROMS_ values. This fixes a problem with
         # SPLIT_INTO, e.g., a user made a really long line for USTH 55
         # but in Statewide MN we got hundreds of line segments for that
         # road. Since Shapefile has a 254-char limit on text length,
         # we cannot store the list of stack IDs in the really long
         # line being deleted, but we need to store that stack ID in
         # all of the small replacement lines.
         if ((row_hm['verdict'].startswith('copy'))
             and (row_hm['gf_new_match_cmd'] == 'donate')):
            misc.dict_list_append(
               split_into_donatees, row_hm['gf_old_stack_id'], row_hm)

      log.info(
         'record_match_results: no. new w/ 1+ match: %d / no. tested: %d'
         % (len(unique_matches), len(suspects),))

      source_files = self.get_source_files('Prepared')

      for source_shp in source_files:

         with fiona.open(source_shp, 'r') as source_data:

            log.info('record_match_results: Processing %d features from %s...'
                     % (len(source_data), os.path.basename(source_shp),))

            prog_log = Debug_Progress_Logger(copy_this=debug_prog_log_match)
            prog_log.setup(prog_log, 10000, len(source_data))

            for shpfeat in source_data:

               if (debug_filter_sids
                   and (row_hm['gf_new_stack_id'] not in debug_filter_sids)
                   and (row_hm['gf_old_stack_id'] not in debug_filter_sids)):
                  continue

               self.record_match_result_feat(shpfeat, matches_by_new,
                                                      split_into_donatees)

               if prog_log.loops_inc():
                  break
               if debug_group_shp_writes:
                  if prog_log.progress % prog_log.log_freq == 0:
                     log.debug('Writing features to Shapefiles...')
                     for lyr_name in self.slayers.keys():
                        feat_list = self.intermed_feats[lyr_name]
                        if feat_list:
                           self.slayers[lyr_name].writerecords(feat_list)
                           self.everylayer.writerecords(feat_list)
                           self.intermed_feats[lyr_name] = []
                     # No: self.intermed_feats = {}

            prog_log.loops_fin()

   #
   def record_match_result_feat(self, shpfeat, matches_by_new,
                                               split_into_donatees):

      guidance, ccp_stack_id, ccp_ref_sids = (
         self.parse_guidance_and_stk_ids(shpfeat))

      try:
         rows_hm = matches_by_new[ccp_stack_id]
      except KeyError:
         # This means there were no matches for this line segment,
         # either because the segment is already okay, or because
         # it's not near any other okay lines.
         rows_hm = None

      # Hrm. Who created Shape_Length? It was truncated to "Shape_Leng".
      # And while I [lb] assumed it was standard to record the geometry
      # length for each feature, it doesn't seem to be so.
      try:
         del shpfeat['properties']['Shape_Leng']
      except KeyError:
         pass

      try:
         # If another item was marked SPLIT_INTO/donate, it was looking
         # for a match to consume it -- this is useful for importing
         # segmentized lines and then getting rid of really long lines,
         # so that you don't have to manually match or segmentize the
         # long line to get the road better connected to the network.
         # E.g., a user draws 60 miles of highway as one line, and
         # then you import the segmentized road network from the DOT.
         donation_rows = split_into_donatees[ccp_stack_id]
      except KeyError:
         donation_rows = []

# FIXME: Tabulate results.
#        Look for 'couplet', cul-de-sac, extended dead end, etc.

      if rows_hm is not None:

         verdicts = {}
         verdicts['keep'] = []
         verdicts['copy attrs'] = []
         verdicts['copy geom'] = []
         verdicts['unsure'] = []
         # Not needed: verdicts['unsure']

         flags = []

         for row_hm in rows_hm:

            resfeat = copy.deepcopy(shpfeat)
            resfeat['properties']['old_stk_id'] = (
               row_hm['gf_old_stack_id'])
            resfeat['properties']['old_name'] = row_hm['gf_old_name']
            for fldn, rown in Hausdorff_Import.match_fields.iteritems():
               # At least set the property to None, else Fiona complains:
               # "Record does not match collection schema: [..] != [..]"
               if Hausdorff_Import.fragment_lookup[fldn] == 'float:19.11':
                  resfeat['properties'].setdefault(fldn, 0.0)
               elif Hausdorff_Import.fragment_lookup[fldn] == 'int:9':
                  resfeat['properties'].setdefault(fldn, 0)
               elif Hausdorff_Import.fragment_lookup[fldn] == 'str':
                  resfeat['properties'].setdefault(fldn, '')
               else:
                  resfeat['properties'].setdefault(fldn, None)
               try:
                  resfeat['properties'][fldn] = row_hm[rown]
               except KeyError:
                  pass

            if self.cli_opts.show_conflations:
               self.record_match_result_target(resfeat)

            # Could do: if resfeat['properties']['GUIDANCE']
            #verdicts[row_hm['verdict']].append((resfeat, row_hm,))
            verdicts[row_hm['verdict']].append(row_hm)
            #verdicts[row_hm['verdict']].append(row_hm['gf_old_stack_id'])
            flags.append('%s: %s' % (row_hm['verdict'], row_hm['reasoning'],))

            # Make a feature for the segmentized line fragment.
            if ((self.cli_opts.show_conflations)
                and (self.cli_opts.show_fragments)):
               for prefix in ('gf_old', 'gf_new',):
                  try:
                     frag = copy.deepcopy(resfeat)
                     frag['geometry']['coordinates'
                        ] = row_hm['%s_frag_xys' % (prefix,)]
                     frag['properties']['new_length'
                        ] = row_hm['%s_frag_len' % (prefix,)]
                     frag['properties']['verdict'
                        ] = ('FRAG_%s' % (prefix,))
                     self.mstrength_init(frag)

                     self.record_match_result_target(frag)

                  except KeyError:
                     pass # Didn't compute HD.
         # end: for row_hm in rows_hm

         shpfeat['properties']['matches'] = (
            'Of %d: %d Data / %d Geom / %d Keep / %d Unsure / %s'
            % (len(rows_hm),
               len(verdicts['copy attrs']),
               len(verdicts['copy geom']),
               len(verdicts['keep']),
               len(verdicts['unsure']),
               ' | '.join(set(flags)),))

         prefix = ''
         ref_sids = []
         duplicates = verdicts['copy attrs'] + verdicts['copy geom']
         duplicate_sids = set([x['gf_old_stack_id'] for x in duplicates])
         donator_sids = set([x['gf_new_stack_id'] for x in donation_rows])
         #matched_sids = set([x['gf_old_stack_id'] for x in duplicates])
         #duplicate_sids = matched_sids.difference(donator_sids)
         duplicate_sids = set(duplicate_sids).difference(donator_sids)
         if donator_sids:
            # MAYBE: Take the best match rather than a bunch?
            #  ref_sids += donator_sids
            best_ref = None
            for donat_hm in donation_rows:
               if ((best_ref is None)
                  #or (best_ref['hausdorff_dist'] < donat_hm['hausdorff_dist'])
                    #or (best_ref['frag_haus'] < donat_hm['frag_haus'])
                    or (best_ref['frag_norm'] > donat_hm['frag_norm'])
                    ):
                  best_ref = donat_hm
            if len(duplicates) > 1:
               log.warning('chose best donator (of %d) / %s / %s'
                           % (len(duplicates), ccp_stack_id,
                              #best_ref['gf_old_stack_id'],))
                              best_ref['gf_new_stack_id'],))
            #ref_sids.append(best_ref['gf_old_stack_id'])
            #ref_sids.append(best_ref['gf_new_stack_id'])
            #prefix += 'ACCEPT-FROM-'
            #prefix += 'ACCEPT-FROM-' + str(best_ref['gf_old_stack_id'])
            prefix += 'ACCEPT-FROM-' + str(best_ref['gf_new_stack_id'])
            #
            shpfeat['properties']['CCP_FROMS_'] = str(
                           best_ref['gf_new_stack_id'])
            #shpfeat['properties']['OPERATION'] =
            shpfeat['properties']['GUIDANCE'] = 'update'
            #
            if guidance == 'donate':
               log.warning(
                  'donator becomes the donatee! was donate: %s / matched: %s'
                  #% (ccp_stack_id, best_ref['gf_old_stack_id'],))
                  % (ccp_stack_id, best_ref['gf_new_stack_id'],))

         if duplicate_sids:
            ref_sids += duplicate_sids
            if guidance == 'donate':
               prefix += 'DONATE-ATTRS-TO-'
               shpfeat['properties']['CCP_FROMS_'] = ','.join(
                                    [str(x) for x in ref_sids])
               shpfeat['properties']['GUIDANCE'] = 'delete'
            elif len(duplicates) == 1:
               if verdicts['copy attrs']:
                  prefix += 'COPY-ATTR-TO-'
               else:
                  g.assurt(verdicts['copy geom'])
                  prefix += 'COPY-GEOM-TO-'
            else:
               # NOTE: MNTH MnDOT says Highway, but we say Freeway, so we don't
               #       match... see: 2874006, which says couplet against
               #       two small frags...
               prefix += 'COUPLETS?-'
         elif not donator_sids:
            if verdicts['keep']:
               prefix += 'KEEPER'
               if not verdicts['unsure']:
                  prefix += 'KEEPER'
                  # No: Conflation isn't working well.
                  # We want to re-investigate these...
                  #  shpfeat['properties']['GUIDANCE'] = 'update'
                  # CHECK: 1100289/2801362
               else:
                  prefix += 'KEEPER?'
            elif verdicts['unsure']:
               prefix += 'UNSURE'
            else:
               g.assurt(False)
         #shpfeat['properties']['CCP_FROMS_'] = row_hm['gf_old_stack_id']
         #shpfeat['properties']['OPERATION'] =
         #shpfeat['properties']['GUIDANCE'] =
         #guidance=
         shpfeat['properties']['verdict'] = prefix + ','.join(
                                    [str(x) for x in ref_sids])

         # SPLIT_INTO is coming here- wow, does that save a lot of busy work!
         # You'll get "Warning 1: Value 'COUPLETS-3854183,3853879,...' if
         # field verdict has been truncated to 254 characters. This should be
         # a problem so long as it's just a donatee which is being deleted,
         # since only then is CCP_FROMS_ not used.
         if ((len(shpfeat['properties']['verdict']) > 254)
             and (guidance not in ('delete', 'donate',))):
            log.warning('long verdict: %s' % (shpfeat,))

         self.record_match_result_target(shpfeat)

      else:

         # rows_hm is None, so either this item wasn't part of matching, or we
         # didn't find any matches.

         for fldn in Hausdorff_Import.match_fields.iterkeys():
            if Hausdorff_Import.fragment_lookup[fldn] == 'float:19.11':
               shpfeat['properties'].setdefault(fldn, 0.0)
            elif Hausdorff_Import.fragment_lookup[fldn] == 'int:9':
               shpfeat['properties'].setdefault(fldn, 0)
            else:
               shpfeat['properties'].setdefault(fldn, None)

         self.mstrength_init(shpfeat)
         #if ((self.cli_opts.first_suspect)
         #    and (ccp_stack_id >= self.cli_opts.first_suspect)
         #    and (ccp_stack_id <= self.cli_opts.final_suspect)
         #    and (not guidance)):
         if ccp_stack_id in self.analyzed_sids:
            if not guidance:
               #shpfeat['properties']['OPERATION'] = 'U'
               #shpfeat['properties']['GUIDANCE'] = 'no_match'
               shpfeat['properties']['verdict'] = 'keep'
               shpfeat['properties']['reasoning'] = 'no Cyclopath match'
            else:
               #shpfeat['properties']['OPERATION'] = 'U'
               # Skip: shpfeat['properties']['GUIDANCE'] = 'update'
               shpfeat['properties']['verdict'] = 'skipped'
               shpfeat['properties']['reasoning'] = 'user override'
         else:
            # We didn't analyze this feature; just copy it forward.
            # Skip: shpfeat['properties']['GUIDANCE'] = 'update'
            shpfeat['properties']['verdict'] = ''
            shpfeat['properties']['reasoning'] = ''

         self.record_match_result_target(shpfeat)

   #
   def record_match_result_target(self, shpfeat):

      # NOTE: [lb] observes different processing speeds with single
      #       writes. Sometimes 300 lps, sometimes 1000 lps, etc.,
      #       and a 500,000 feature list sometimes says 30 mins to
      #       go but completes in 6 minutes.
      #       Try debug_group_shp_writes to speed things up...

      target_lyr_name = self.get_target_lyr(shpfeat)

      new_props = {}
      for fldn, rown in self.target_schema['properties'].iteritems():
         try:
            new_props[fldn] = shpfeat['properties'][fldn]
         except KeyError:
            new_props[fldn] = None
      shpfeat['properties'] = new_props

      try:
         if debug_group_shp_writes:
            self.intermed_feats[target_lyr_name].append(shpfeat)
         else:
            try:
               len(shpfeat['geometry']['coordinates'][0][0][0])
            except TypeError:
               if shpfeat['geometry']['type'] == 'Polygon':
                  # Turn Polygon into MultiPolygon.
                  shpfeat['geometry']['coordinates'] = [
                     shpfeat['geometry']['coordinates'],]
                  shpfeat['geometry']['type'] = 'MultiPolygon'
            try:
               self.slayers[target_lyr_name].write(shpfeat)
            except KeyError:
               # E.g., "KeyError: 'connected-None'"
               log.warning('record_match_result_tgt: target_lyr_name: %s / %s'
                           % (target_lyr_name, shpfeat['properties'],))
            self.everylayer.write(shpfeat)
      except Exception, e:
         conf.break_here() # To help a DEV.
         raise

   #
   def mstrength_init(self, dbrow_or_shpfeat):
      for idx in xrange(1,4):
         try:
            dbrow_or_shpfeat['properties']['mstrength%d' % (idx,)] = 0
         except KeyError:
            dbrow_or_shpfeat['mstrength%d' % (idx,)] = 0

   #
   # *** Process edited items
   #

   # Using copy and insert:
   #  processed_fields = copy.copy(intermediate_fields_byway)
   #  processed_fields.insert(0, (u'LASTIMPORT', 'str',))
   # Or using addition:
   #
   processed_fields_byway = ([(u'LASTIMPORT', 'str',),]
                             + intermediate_fields_byway)
   processed_schema_byway = {
      'geometry': 'LineString',
      'properties': OrderedDict(processed_fields_byway),
      }
   #
   processed_fields_non_byway = ([(u'LASTIMPORT', 'str',),]
                                 + intermediate_fields_non_byway)
   processed_schema_non_byway = {
      'geometry': 'LineString',
      'properties': OrderedDict(processed_fields_non_byway),
      }

   #
   def process_edits(self):

      self.stats_init_worker()

      self.create_feats = {}
      self.update_feats = {}
      self.create_lvals = {}
      self.update_lvals = {}
      self.delete_nodes_for = set()
      self.insert_brats = []
      self.brats_dbldict = {}
      self.insert_aadts = []
      self.aadts_dbldict = {}

      target_crs = self.get_crs_from_srid(self.cli_opts.shapefile_srid)
      if self.cli_opts.item_type == 'byway':
         target_schema = Hausdorff_Import.processed_schema_byway
      else:
         target_schema = Hausdorff_Import.processed_schema_non_byway
      target_driver = self.cli_opts.shapefile_driver
      try:
         self.prepare_target_shapefiles(target_schema,
                                        touch_note='note_processed')
      except Exception, e:
         log.error('Unable to prepare targets: %s' % (str(e),))
         raise

      if not self.cli_opts.instance_worker:
         changenote = (
            self.cli_opts.changenote
            or 'import %s'
               % (Inflector.pluralize(self.cli_opts.item_type, True),))
         group_names_or_ids = self.cli_args.group_ids
         self.finish_script_save_revision(group_names_or_ids,
                                          self.qb.username,
                                          changenote,
                                          dont_claim_revision=False,
                                          skip_item_alerts=True)

      # This import script keeps all features it's processed, always, even
      # those that are marked deleted in Cyclopath. This is so it's easy to
      # remove bad data from Cyclopath temporarily while you fix it offline,
      # and then to import it back later. Those Shapefiles are in Processed/.
      if self.cli_opts.item_type == 'byway':
         subpath = 'Conflated'
      else:
         subpath = 'Prepared'

      # At one point we examined all Shapefiles, but now we just look at
      # the everylayer.
      source_files = self.get_source_files(subpath)

      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log_match)
      prog_log.setup(prog_log, 1, len(source_files))

      try:

         for source_shp in source_files:

            self.process_source_shp(source_shp, self.process_edited_item)

            if prog_log.loops_inc():
               break # For debugging; see: debug_prog_log.debug_break_loop_cnt

      finally:
         for shpfile in self.slayers.values():
            try:
               shpfile.close()
            except:
               pass
         self.slayers = None
         try:
            self.everylayer.close()
         except:
            pass
         self.everylayer = None
      self.symlink_target_shapefiles(link_name='ImportResults')

      prog_log.loops_fin()

      self.save_db_changes()

      if ((not self.cli_opts.instance_worker)
          and (self.cli_opts.update_geomsummary)):
         log.info('Recomputing revision geometry for gids: %s'
                  % (group_names_or_ids,))
         time_0 = time.time()
         revision.Revision.geosummary_update(self.qb.db,
                                             self.qb.item_mgr.rid_new,
                                             self.qb.branch_hier,
                                             group_names_or_ids)
         misc.time_complain('geosummary_update', time_0, 2.0)

      self.stats_show_worker()

   # **** Process edited items: process one feature

   #
   def process_edited_item(self, shpfeat):

      guidance, ccp_stack_id, ccp_ref_sids = (
         self.parse_guidance_and_stk_ids(shpfeat))

      g.assurt((not guidance)
               or (guidance
                   in Hausdorff_Import.byway_02_guidance))

      the_item = None
      if ccp_stack_id > 0:
         try:
            the_item = self.hydrated_items[ccp_stack_id]
         except KeyError:
            log.warning('proc_edited_itms: no such item: stack_id: %d'
                        % (ccp_stack_id,))
            self.add_err(shpfeat, 'no such item (%d)' % (ccp_stack_id,))
      # else, ccp_stack < 0, so we'll create a new item.

      if the_item is not None:

         if ccp_stack_id in self.processed_sids:
            # This happens if you split a byway and mark one deleted.
            # The one mark deleted will be changed to 'ignore', since
            # we don't want to really delete the item, since another
            # feature keeps it alive. It also happens if you split
            # a feature one or more times and mark all the new features
            # deleted: we only need to delete the item once
            if (not ((guidance == 'ignore')
                     or ((guidance == 'delete') and (the_item.deleted)))):
               conf.break_here() # To help a DEV.
               g.assurt(False)

         elif guidance != 'ignore':
            self.processed_sids.add(ccp_stack_id)

            shpfeat_ver = -1
            try:
               shpfeat_ver = ojint(shpfeat['properties']['CCP_VERS'])
            except KeyError:
               # Not part of Shapefile; we'll check all features.
               pass
            except ValueError:
               # Field value is not an int.
               log.warning('proc_edited_itms: bad version: %s'
                           % (pprint.pformat(shpfeat),))
               self.add_err(shpfeat, 'invalid version (%s)'
                                     % (shpfeat['properties']['CCP_VERS'],))

            if (shpfeat_ver >= 0) and (the_item.version != shpfeat_ver):
               log.warning(
                  'proc_edited_itms: version conflict: %s (%s) / %s (%s)'
                  % (the_item,
                     the_item.version,
                     pprint.pformat(shpfeat['properties']),
                     shpfeat_ver,))
               self.add_err(shpfeat, 'version conflict (%d vs. %d)'
                  % (shpfeat['properties']['CCP_VERS'], the_item.version,))

      # end: if the_item is not None

      if shpfeat is not None:
         # If we just assigned an error, or if an error already existed,
         # don't process the feature.
         if shpfeat['properties']['import_err']:
            self.problem_items_add(shpfeat)
            shpfeat = None
         else:
            self.process_edited_item_(the_item, shpfeat,
                  guidance, ccp_stack_id, ccp_ref_sids)

   #
   def process_edited_item_(self, the_item, shpfeat,
               guidance, ccp_stack_id, ccp_ref_sids):

      # If guidance isn't set, we don't look at the item, unless
      # explicitly told to.
      if (((not guidance) and (not self.cli_opts.check_everything))
          or (guidance == 'donate')
          or (guidance == 'reject')
          or (guidance == 'ignore')
          or (guidance == 'noring')):
         proc_cmd = 'ignore'
         the_item = None
      elif (not guidance) and self.cli_opts.check_everything:
         proc_cmd = 'update'
      else:
         proc_cmd = guidance

      # If the Shapefile uses the last-edited convention,
      # we can ignore features we know haven't been edited.
      if (proc_cmd != 'ignore') and self.cli_opts.last_edited_attr:
         try:
            last_edited_raw = shpfeat['properties'][
                     self.cli_opts.last_edited_attr]
            try:
               # E.g., time.strptime('14 Mar 2014', '%d %b %Y')
               feat_last_edited = time.mktime(
                  time.strptime(last_edited_raw, '%d %b %Y'))
               if (feat_last_edited < self.cli_opts.last_edited_date):
                  proc_cmd = 'ignore'
                  #shpfeat['properties']['GUIDANCE'] = guidance
            except ValueError, e:
               log.warning('Bad last_edited_raw: %s / %s'
                           % (last_edited_raw, str(e),))
               raise
         except KeyError, e:
            log.warning('Shapefile has no such attribute "%s"'
                        % (self.cli_opts.last_edited_attr,))

      if the_item is None:
         if proc_cmd in ('update', 'repeat',):
            the_item = self.edited_item_create_new(shpfeat, ccp_ref_sids)
            shpfeat['properties']['GUIDANCE'] = 'create'
         elif proc_cmd == 'delete':
            # else, whatever, user created new item and marked deleted...
            log.debug('proc_edited_itms: ignoring delete on new item: %s'
                      % (pprint.pformat(shpfeat['properties']),))
         else:
            # Else, ignore, so, ignore.
            self.stats['items_noop_item'] += 1
      else:
         if proc_cmd in ('update', 'repeat',):
            self.edited_item_update_item(the_item, shpfeat, ccp_ref_sids)
         elif proc_cmd == 'delete':
            # The delete fcn. will call itself recursively on the item's
            # link_values.
            self.edited_item_delete_item(the_item, self.update_feats)
            self.stats['items_delete_item'] += 1
         else:
            self.stats['items_noop_item'] += 1

      if (the_item is not None) and (not the_item.deleted) and ccp_ref_sids:

         was_dirty = the_item.dirty
         the_item.dirty = item_base.One.dirty_reason_none
         g.assurt((was_dirty == item_base.One.dirty_reason_none)
                  or (was_dirty == item_base.One.dirty_reason_item_auto))

         # The first ID in the list is considered the split-from stack ID.
         first_ref = True
         for ref_sid in ccp_ref_sids:
            try:
               ref_item = self.hydrated_items[ref_sid]
            except KeyError:
               # This can happen if you rerun the import on old Shapefiles
               # that deleted items... and maybe for other reasons.
               log.warning('proc_edited_itms: no ref item: stack_id: %d'
                           % (ref_sid,))
               self.add_err(shpfeat, 'no such CCP_FROMS_ item (%d)'
                                     % (ref_sid,))
               self.problem_items_add(shpfeat)
               ref_item = None
            if ref_item is not None:
               # MAYBE: Only if self.cli_opts.item_type == 'byway' ?
               self.consolidate_duplisplits(shpfeat, the_item, ref_item,
                                            first_ref)
            first_ref = False

         if ((was_dirty == item_base.One.dirty_reason_none)
             and (the_item.dirty == item_base.One.dirty_reason_item_auto)):
            # Reset the dirty flag lest validize complain.
            the_item.dirty = item_base.One.dirty_reason_none
            # NOTE: This import script doesn't merge geometry btw. features.
            try:
               if the_item.geometry_changed is None:
                  the_item.geometry_changed = False
            except AttributeError:
               try:
                  the_item.geometry_changed = False
                  # Wasn't set; now it is.
               except AttributeError:
                  pass # Not a geofeature.

            self.edited_item_validize(the_item)

# FIXME: THIS IS NOT THREAD-SAFE! We should bulk-write and lock/open/close
#        shapefiles... or just make sure --process-edits is never run
#        in parallel.
#         g.assurt((not self.cli_opts.items_limit)
#                  and (not self.cli_opts.items_offset))
      self.record_match_result_target(shpfeat)

   #
   def edited_item_validize(self, the_item):

      the_item.system_id = self.qb.db.sequence_get_next(
                              'item_versioned_system_id_seq')
      the_item.version += 1
      the_item.acl_grouping = 1
      the_item.valid_start_rid = self.qb.item_mgr.rid_new

      if self.cli_opts.item_type == 'byway':
         beg_node_id = the_item.beg_node_id
         fin_node_id = the_item.fin_node_id

      the_item.clear_item_revisionless_defaults()
      the_item.validize(
         self.qb,
         is_new_item=False,
         dirty_reason=item_base.One.dirty_reason_item_auto,
         #ref_item=None)
         ref_item=the_item)

      # The validize fcn. resets the node ID, because it assumes the item
      # was sent from the client or something and its node ID needs
      # resetting...
      if self.cli_opts.item_type == 'byway':
         if not the_item.geometry_changed:
            the_item.beg_node_id = beg_node_id
            the_item.fin_node_id = fin_node_id
         else:
            self.delete_nodes_for.add(the_item.stack_id)

      g.assurt(the_item.stack_id not in self.update_feats)
      self.update_feats[the_item.stack_id] = the_item

   # **** Process edited items: add new items

   #
   def edited_item_create_new(self, shpfeat, ccp_ref_sids):

      # BUG nnnn: Allow other item types: region, terrain, etc.

      item_module = item_factory.get_item_module(self.cli_opts.item_type)
      new_item = item_module.One()

      # Item Versioned
      new_item.system_id = self.qb.db.sequence_get_next(
                              'item_versioned_system_id_seq')
      shpfeat['properties']['CCP_SYS'] = new_item.system_id
      new_item.branch_id = self.qb.branch_hier[0][0]
      new_item.stack_id = self.qb.db.sequence_get_next(
                              'item_stack_stack_id_seq')
      shpfeat['properties']['CCP_ID'] = new_item.stack_id
      new_item.version = 1
      shpfeat['properties']['CCP_VER'] = new_item.version
      new_item.deleted = False
      new_item.reverted = False
      new_item.name = shpfeat['properties']['CCP_NAME']
      if self.cli_opts.friendly_names:
         # See also: self.cli_opts.merge_names
         new_item.name = self.cleanup_byway_name(new_item.name, new_item)
         shpfeat['properties']['CCP_NAME'] = new_item.name
      new_item.valid_start_rid = self.qb.item_mgr.rid_new
      new_item.valid_until_rid = conf.rid_inf
      # Item Revisionless
      new_item.acl_grouping = 1
      # Skipping: new_item.edited_date
      # Skipping: new_item.edited_user
      # Skipping: new_item.edited_addr
      # Skipping: new_item.edited_host
      # Skipping: new_item.edited_note
      # Skipping: new_item.edited_what
      # Item User Access / These are inferred from GIA records
      new_item.access_level_id = Access_Level.editor
      # Item Stack
      new_item.access_style_id = Access_Style.pub_editor
      new_item.access_infer_id = Access_Infer.pub_editor
      # Geofeature
      if self.cli_opts.item_type == 'byway':
         new_item.geometry_wkt = geometry.xy_to_ewkt_line(
            shpfeat['geometry']['coordinates'])
      elif self.cli_opts.item_type in ('region', 'terrain',):
         if shpfeat['geometry']['type'] == 'Polygon':
            new_item.geometry_wkt = geometry.xy_to_ewkt_polygon(
               shpfeat['geometry']['coordinates'])
         elif shpfeat['geometry']['type'] == 'MultiPolygon':
            new_item.geometry_wkt = geometry.xy_to_ewkt_polygon_multi(
               shpfeat['geometry']['coordinates'])
         else:
            g.assurt(False)
      elif self.cli_opts.item_type == 'point':
         new_item.geometry_wkt = geometry.xy_to_ewkt_point(
            shpfeat['geometry']['coordinates'])
      new_item.geometry_changed = True
      new_item.z = shpfeat['properties']['z_level'] or byway.One.z_level_med
      if self.cli_opts.item_type == 'byway':
         new_item.is_disconnected = (shpfeat['properties']['wconnected']
                                     != '1')
      # Geofeature layer type
      gf_lyr_id, gf_lyr_name = self.parse_gf_lyr_type(shpfeat)
      if gf_lyr_id:
         new_item.geofeature_layer_id = gf_lyr_id
         shpfeat['properties']['gf_lyr_id'] = gf_lyr_id
      else:
         self.problem_items_add(shpfeat)
      # Byway
      if self.cli_opts.item_type == 'byway':
         new_item.one_way = shpfeat['properties']['one_way'] or 0
      if ccp_ref_sids:
         # Whether or not the referenced item is really being deleted and this
         # item is replacing it doesn't matter; just record a split-from ID...


# FIXME: Only if the other ID > ours?
         new_item.split_from_stack_id = ccp_ref_sids[0]
         g.assurt(new_item.split_from_stack_id > 0)



      # Skipping: new_item.beg_node_id and new_item.fin_node_id
      #           We'll set these later...

      if shpfeat['properties']['import_err']:
         new_item = None

      if new_item is not None:

         self.add_new_item_gia(new_item)

         new_item.fresh = True
         new_item.validize(
            self.qb,
            is_new_item=True,
            dirty_reason=item_base.One.dirty_reason_item_auto,
            ref_item=None)
         g.assurt(new_item.stack_id not in self.create_feats)
         self.create_feats[new_item.stack_id] = new_item
         self.stats['items_new_gfs'] += 1

         new_item.link_values_reset(self.qb)

         for field_name, ccp_attr in self.field_attr_cache_name.iteritems():
            field_val = shpfeat['properties'][field_name]
            if field_val:
               if ((ccp_attr.value_type == 'integer')
                   and (field_val > 0)):
                  self.add_new_lval_attc(new_item, ccp_attr,
                     value_integer=field_val, value_text=None)
               elif ccp_attr.value_type == 'text':
                  self.add_new_lval_attc(new_item, ccp_attr,
                     value_integer=None, value_text=field_val)
               else:
                  g.assurt(False) # Shouldn't happen; see self.attr_to_field.

         add_tags, del_tags = self.tag_list_assemble(shpfeat)
         for tag_name in add_tags:
            self.add_new_tag_lval(new_item, tag_name)
         # Skipping: del_tags, since this byway is new.
 
         new_item.lvals_wired_ = True
         new_item.lvals_inclusive_ = True
         

# FIXME: Ensure that tagged and attrs is updated
      # BUG nnnn: If we add a line to the basemap branch, do we have
      #           to make generic ratings for all leafy branches??
         if self.cli_opts.item_type == 'byway':
            new_item.generic_rating_calc(self.qb)

      return new_item

   #
   def add_new_item_gia(self, new_item, group_id=None, acl_id=None):

      if group_id is None:
         group_id = group.Many.public_group_id(self.qb.db)
      if acl_id is None:
         acl_id = Access_Level.editor

      new_item.groups_access = {}

      session_id = None
      new_gia = new_item.group_access_add_or_update(self.qb,
                     (group_id, acl_id, session_id,),
                     item_base.One.dirty_reason_grac_auto)

      new_gia.branch_id = new_item.branch_id
      new_gia.stack_id = new_item.stack_id
      new_gia.version = new_item.version
      g.assurt(new_gia.item_id == new_item.system_id)
      new_gia.acl_grouping = 1
      #new_gia.valid_start_rid = self.qb.revision.rid
      # This item classes don't like it when the rids are set.
      #  new_gia.valid_start_rid = self.qb.item_mgr.rid_new
      #  new_gia.valid_until_rid = conf.rid_inf
      #new_gia.link_lhs_type_id = None
      #new_gia.link_rhs_type_id = None

   #
   def add_new_lval_attc(self, new_item, lhs_item, value_integer=None,
                                                   value_text=None):

      return self.add_new_lval_base(new_item,
         lhs_item.item_type_id, lhs_item.stack_id,
         value_integer, value_text)

   #
   def add_new_lval_lval(self, new_item, old_lval):

      return self.add_new_lval_base(new_item,
         old_lval.link_lhs_type_id, old_lval.lhs_stack_id,
         old_lval.value_integer, old_lval.value_text)

   #
   def add_new_lval_base(self, new_item, lhs_type_id, lhs_stack_id,
                                         value_integer=None,
                                         value_text=None):

      new_lval = link_value.One()

      new_lval.system_id = self.qb.db.sequence_get_next(
                              'item_versioned_system_id_seq')
      new_lval.branch_id = self.qb.branch_hier[0][0]
      new_lval.stack_id = self.qb.db.sequence_get_next(
                              'item_stack_stack_id_seq')
      new_lval.version = 1
      new_lval.deleted = False
      new_lval.reverted = False
      new_lval.name = None
      new_lval.valid_start_rid = self.qb.item_mgr.rid_new
      new_lval.valid_until_rid = conf.rid_inf
      # Item Revisionless
      new_lval.acl_grouping = 1
      # Skipping: new_lval.edited_date
      # Skipping: new_lval.edited_user
      # Skipping: new_lval.edited_addr
      # Skipping: new_lval.edited_host
      # Skipping: new_lval.edited_note
      # Skipping: new_lval.edited_what
      # Item User Access / These are inferred from GIA records
      new_lval.access_level_id = Access_Level.editor
      new_lval.link_lhs_type_id = lhs_type_id
      new_lval.link_rhs_type_id = new_item.item_type_id
      # Item Stack
      new_lval.access_style_id = Access_Style.pub_editor
      new_lval.access_infer_id = Access_Infer.pub_editor
      # Link_Value
      new_lval.lhs_stack_id = lhs_stack_id
      new_lval.rhs_stack_id = new_item.stack_id
      new_lval.value_integer = value_integer
      new_lval.value_text = value_text
      # Skipping: new_lval.value_boolean/_real/_text/_binary/_date

      self.add_new_item_gia(new_lval)

      new_lval.fresh = True
      new_lval.validize(
         self.qb,
         is_new_item=True,
         dirty_reason=item_base.One.dirty_reason_item_auto,
         ref_item=None)
      g.assurt(new_lval.stack_id not in self.create_lvals)
      self.create_lvals[new_lval.stack_id] = new_lval
      new_item.wire_lval(self.qb, new_lval, heavywt=True)
      self.stats['items_new_lval'] += 1

   #
   def add_new_tag_lval(self, new_item, tag_name):

      the_tag = self.qb.item_mgr.cache_tag_lookup_by_name(tag_name)

      if the_tag is not None:

         tag_stack_id = the_tag.stack_id

      else:

         the_tag = tag.One()
         #the_tag.system_id = self.qb.db.sequence_get_next(
         #                        'item_versioned_system_id_seq')
         the_tag.branch_id = self.qb.branch_hier[0][0]
         the_tag.stack_id = self.qb.db.sequence_get_next(
                                 'item_stack_stack_id_seq')
         the_tag.version = 1
         the_tag.deleted = False
         the_tag.reverted = False
         the_tag.name = tag_name
         the_tag.valid_start_rid = self.qb.item_mgr.rid_new
         the_tag.valid_until_rid = conf.rid_inf
         # Item Revisionless
         the_tag.acl_grouping = 1
         # Skipping: the_tag.edited_date
         # Skipping: the_tag.edited_user
         # Skipping: the_tag.edited_addr
         # Skipping: the_tag.edited_host
         # Skipping: the_tag.edited_note
         # Skipping: the_tag.edited_what
         # Item User Access / These are inferred from GIA records
         the_tag.access_level_id = Access_Level.editor
         # Item Stack
         the_tag.access_style_id = Access_Style.pub_editor
         the_tag.access_infer_id = Access_Infer.pub_editor

         self.add_new_item_gia(the_tag)

         # We have to save the new tag now in case other competing
         # threads are trying to make the same new tag.
         tag_qb = self.qb.clone(db_get_new=self.cli_opts.instance_worker)
         tag_qb.revision = revision.Current()
         tag_qb.branch_hier[0] = (tag_qb.branch_hier[0][0],
                                  tag_qb.revision,
                                  tag_qb.branch_hier[0][2],)
         # Call tag_qb.revision.setup_gids(tag_qb.db, tag_qb.username) or ?:
         #  tag_qb.branch_hier_set(tag_qb.branch_hier)
         if self.cli_opts.instance_worker:
            tag_qb.db.transaction_begin_rw('tag')
         # Check again, now that we have the lock.
         find_tag_sql = tag.Many.stack_id_lookup_by_name_sql_(tag_qb, tag_name)
         rows = tag_qb.db.sql(find_tag_sql)
         if rows:
            log.debug('add_new_tag_lval: new tag added by another thread!: %s'
                      % (rows[0]['stack_id'],))
            g.assurt(len(rows) == 1)
            g.assurt(self.cli_opts.instance_worker)
            tag_stack_id = rows[0]['stack_id']
            tag_qb.db.transaction_rollback()
            the_tag = tag.One()
            the_tag.stack_id = tag_stack_id
            the_tag.name = tag_name
         else:
            try:
               #the_tag.valid = True
               #the_tag.dirty_reason_add(item_base.One.dirty_reason_item_auto)
               the_tag.fresh = True
               the_tag.validize(
                  self.qb,
                  is_new_item=True,
                  dirty_reason=item_base.One.dirty_reason_item_auto,
                  ref_item=None)
               the_tag.save(tag_qb, self.qb.item_mgr.rid_new)
               self.qb.item_mgr.cache_tag_insert(the_tag)
               tag_stack_id = the_tag.stack_id
               self.stats['items_new_tag'] += 1
               misc.dict_count_inc(self.stats['edit_tag_add_name'],
                                   the_tag.name)
            except Exception, e:
               log.warning('add_new_tag_lval: the_tag.save failed: %s'
                           % (str(e),))
               tag_stack_id = None
               self.stats['items_err_tag'] += 1
            if self.cli_opts.instance_worker:
               if tag_stack_id and (not debug_skip_commit):
                  log.debug('add_new_tag_lval: committing new tag: %s'
                            % (the_tag,))
                  tag_qb.db.transaction_commit()
               else:
                  log.debug('add_new_tag_lval: testing; rolling back new tag')
                  tag_qb.db.transaction_rollback()

      if tag_stack_id:
         self.add_new_lval_attc(new_item, the_tag,
            value_integer=None, value_text=None)

   # **** Process edited items: update existing items

   #
   def edited_item_update_item(self, the_item, shpfeat, ccp_ref_sids):

      is_edited = False

      g.assurt(the_item.stack_id == ojint(shpfeat['properties']['CCP_ID']))

      # Geofeature layer type
      shpfeat_gf_lyr_id, shpfeat_gf_lyr_name = self.parse_gf_lyr_type(shpfeat)
      if not shpfeat_gf_lyr_id:
         self.problem_items_add(shpfeat)

      shpfeat_split_from_sid = None
      if ccp_ref_sids:
         shpfeat_split_from_sid = ccp_ref_sids[0]
         g.assurt(shpfeat_split_from_sid > 0)

      # MAGIC_NUMBERS: This binary values ORed together are just for debugging.
      #                What matters is if the value is 0 or not.
      updated_item = 0x0000
      if the_item.name != shpfeat['properties']['CCP_NAME']:
         the_item.name = shpfeat['properties']['CCP_NAME']
         updated_item |= 0x0001
         self.stats['edit_ccp_name'] += 1
      if self.cli_opts.friendly_names:
         # See also: self.cli_opts.merge_names
         friendly_name = self.cleanup_byway_name(the_item.name, the_item)
         if friendly_name != the_item.name:
            shpfeat['properties']['CCP_NAME'] = friendly_name
            the_item.name = friendly_name
            if not (updated_item & 0x0001):
               updated_item |= 0x0001
               self.stats['edit_ccp_name'] += 1

      if the_item.geofeature_layer_id != shpfeat_gf_lyr_id:
         shpfeat['properties']['gf_lyr_id'] = shpfeat_gf_lyr_id
         shpfeat['properties']['gf_lyr_nom'] = shpfeat_gf_lyr_name
         the_item.geofeature_layer_id = shpfeat_gf_lyr_id
         updated_item |= 0x0002
         self.stats['edit_gfl_id'] += 1

      if the_item.z != shpfeat['properties']['z_level']:
         the_item.z = shpfeat['properties']['z_level']
         updated_item |= 0x0004
         self.stats['edit_z_level'] += 1

      if self.cli_opts.item_type == 'byway':

         if the_item.one_way != shpfeat['properties']['one_way']:
            the_item.one_way = shpfeat['properties']['one_way'] or 0
            updated_item |= 0x0008
            self.stats['edit_one_way'] += 1

         # 2014.07.23: Leave is_disconnected up to the route planner to manage.
         #   is_disconnected = (shpfeat['properties']['wconnected'] != '1')
         #   if the_item.is_disconnected ^ is_disconnected:
         #      the_item.is_disconnected = is_disconnected
         #      updated_item |= 0x0010
         #      self.stats['edit_is_disconnected'] += 1

      if ((shpfeat_split_from_sid)
          and (the_item.split_from_stack_id != shpfeat_split_from_sid)):

# FIXME: Only if really split, not if CCP_FROMS_, but if dupl sids
# FIXME: Only if the other ID > ours?
         the_item.split_from_stack_id = shpfeat_split_from_sid
         updated_item |= 0x0020
         self.stats['edit_split_from_sid'] += 1
         g.assurt(the_item.split_from_stack_id > 0)

      if self.cli_opts.item_type == 'byway':
         wkt_to_xy_fcn = geometry.wkt_line_to_xy
         xy_to_xy_fcn = geometry.xy_to_xy_line
         xy_eq_xy_fcn = geometry.xy_eq_xy_line
         xy_to_ewkt_fcn = geometry.xy_to_ewkt_line
      elif self.cli_opts.item_type in ('region', 'terrain',):
         wkt_to_xy_fcn = geometry.wkt_polygon_to_xy
         xy_to_xy_fcn = geometry.xy_to_xy_polygon
         xy_eq_xy_fcn = geometry.xy_eq_xy_polygon
         if shpfeat['geometry']['type'] == 'Polygon':
            xy_to_ewkt_fcn = geometry.xy_to_ewkt_polygon
         elif shpfeat['geometry']['type'] == 'MultiPolygon':
            xy_to_ewkt_fcn = geometry.xy_to_ewkt_polygon_multi
         else:
            g.assurt(False)
      elif self.cli_opts.item_type == 'point':
         wkt_to_xy_fcn = geometry.wkt_point_to_xy
         xy_to_xy_fcn = geometry.xy_to_xy_point
         xy_eq_xy_fcn = geometry.xy_eq_xy_point
         xy_to_ewkt_fcn = geometry.xy_to_ewkt_point

      theitem_geom_xy = wkt_to_xy_fcn(
         the_item.geometry_wkt, conf.node_precision)
      shpfeat_geom_xy = xy_to_xy_fcn(
         shpfeat['geometry']['coordinates'], conf.node_precision)

# BUG nnnn: Fix node cache table to use xy_eq_xy_line.
      #if theitem_geom_xy != shpfeat_geom_xy:
      # NOTE: Using tolerance because we previously used Decimal
      #       which may have rounded the other way, so we need
      #       twice the tolerance.
      if not xy_eq_xy_fcn(theitem_geom_xy,
                          shpfeat_geom_xy,
                          conf.node_threshold):
         the_item.geometry_wkt = xy_to_ewkt_fcn(
            shpfeat['geometry']['coordinates'])
         the_item.geometry_changed = True
         if self.cli_opts.item_type == 'byway':
            the_item.beg_node_id = None
            the_item.fin_node_id = None
         updated_item |= 0x0040
         self.stats['edit_geometry'] += 1
      else:
         the_item.geometry_changed = False

      if not updated_item:
         self.stats['items_noop_item'] += 1
      else:

         # The geometry fetched doesn't include the SRID, e.g.,
         # 'LINESTRING(...)' instead of 'SRID=26915;LINESTRING(...)'.
         if not the_item.geometry_wkt.startswith('SRID='):
            the_item.geometry_wkt = (
               'SRID=%d;%s' % (conf.default_srid, the_item.geometry_wkt,))

         self.edited_item_validize(the_item)

         self.stats['items_edit_item'] += 1

      for field_name, ccp_attr in self.field_attr_cache_name.iteritems():
         attr_name = ccp_attr.value_internal_name
         # MAGIC_NUMBER: All the attributes are physical measurements,
         #               so -1/<0 is reserved to mean: delete this lval.
         if ccp_attr.value_type == 'integer':
            field_val = None
            try:
               field_val = int(shpfeat['properties'][field_name])
            except KeyError:
               # Not set in source Shapefile, so just ignore.
               pass
            except TypeError:
               log.warning(
                  'edited_item_update_item: field not integer: %s / %s'
                  % (field_name, shpfeat,))
            if field_val:
               if field_val < 0:
                  self.delete_lval_attc(the_item, ccp_attr)
                  self.stats['edit_attr_delete'] += 1
                  updated_item |= 0x0100
               # MAGIC_NUMBER: We ignore '0' or unset from the source;
               #               if user wants to be deliberate, they can
               #               use -1 to delete the value. But a 0 or
               #               null shouldn't cause existing val to reset.
               elif field_val > 0:
                  try:
                     if the_item.attrs[attr_name] != field_val:
                        self.update_lval_attc(the_item, ccp_attr,
                           value_integer=field_val, value_text=None)

                        self.stats['edit_attr_edit'] += 1
                        updated_item |= 0x0200
                  except KeyError:
                     # the_item.attrs[attr_name] n/a
                     self.add_new_lval_attc(the_item, ccp_attr,
                        value_integer=field_val, value_text=None)
                     self.stats['edit_attr_add'] += 1
            # else, field_val is 0 or None, so ignore it.
         elif ccp_attr.value_type == 'text':
            field_val = None
            try:
               field_val = shpfeat['properties'][field_name]
            except KeyError:
               # Not set in source Shapefile, so just ignore.
               pass
            if field_val:
               try:
                  if the_item.attrs[attr_name] != field_val:
                     self.update_lval_attc(the_item, ccp_attr,
                        value_integer=None, value_text=field_val)
                     self.stats['edit_attr_edit'] += 1
                     updated_item |= 0x0400
               except KeyError:
                  # the_item.attrs[attr_name] n/a
                  self.add_new_lval_attc(the_item, ccp_attr,
                     value_integer=None, value_text=field_val)
                  self.stats['edit_attr_add'] += 1
         else:
            g.assurt(False)
      # end: for field_name, ccp_attr in self.field_attr_cache_name.iteritems()

      add_tags_raw, del_tags_raw = self.tag_list_assemble(shpfeat)
      # Ug: user tags are not always lowercase, e.g., on byway:1077570
      # is CAUTION.
      item_tags = set([x.lower() for x in the_item.tagged])
      if add_tags_raw != item_tags:
         add_tags = add_tags_raw.difference(item_tags)
         del_tags = item_tags.difference(add_tags_raw)
         # Not necessary: del_tags += del_tags_raw
         #  that is, we delete tags that are not referenced in Shapefile.
         for tag_name in add_tags:
            self.add_new_tag_lval(the_item, tag_name)
            self.stats['edit_tag_add'] += 1
            misc.dict_count_inc(self.stats['edit_tag_add_name'], tag_name)
            updated_item |= 0x1000
         for tag_name in del_tags:
            the_lval = None
            the_tag = self.qb.item_mgr.cache_tag_lookup_by_name(tag_name)
            for lval in the_item.link_values.itervalues():
               if lval.lhs_stack_id == the_tag.stack_id:
                  the_lval = lval
                  break
            if the_lval is not None:
               self.edited_item_delete_item(the_lval, self.update_lvals)
               self.stats['items_delete_lval'] += 1
               # 37,104 times on 50,000 features! It's the erroneous
               # unpaved/gravel tags that were applied to the state data...
               self.stats['edit_tag_delete'] += 1
               misc.dict_count_inc(self.stats['edit_tag_del_name'], tag_name)
               updated_item |= 0x2000
            else:
               log.error('tagged indicates tag but not in cache: %s / %s'
                         % (tag_name, the_item,))

      if updated_item and (self.cli_opts.item_type == 'byway'):
         the_item.generic_rating_calc(self.qb)

   #
   def update_lval_attc(self, the_item, lhs_item, value_integer=None,
                                                  value_text=None):

      try:
         the_lval = the_item.link_values[lhs_item.stack_id]
         self.update_lval_lval(the_lval, value_integer, value_text)
         self.stats['items_edit_lval'] += 1
      except KeyError:
         log.error('where is the heavyweight lval?: %s / %s'
                   % (the_item, lhs_item,))

   #
   def delete_lval_attc(self, the_item, lhs_item):

      try:
         the_lval = the_item.link_values[lhs_item.stack_id]
         the_lval.deleted = True
         self.update_lval_lval(the_lval, the_lval.value_integer,
                                         the_lval.value_text)
         self.stats['items_delete_lval'] += 1
      except KeyError:
         log.error('where is the heavyweight lval?: %s / %s'
                   % (the_item, lhs_item,))

   #
   def update_lval_lval(self, the_lval, value_integer=None, value_text=None):

      the_lval.value_integer = value_integer
      the_lval.value_text = value_text

      if (not the_lval.fresh) and (not the_lval.valid):
         the_lval.system_id = self.qb.db.sequence_get_next(
                                 'item_versioned_system_id_seq')
         the_lval.version += 1
         the_lval.acl_grouping = 1
         the_lval.valid_start_rid = self.qb.item_mgr.rid_new
         #
         the_lval.clear_item_revisionless_defaults()
         the_lval.validize(
            self.qb,
            is_new_item=False,
            dirty_reason=item_base.One.dirty_reason_item_auto,
            ref_item=None)
         g.assurt(the_lval.stack_id > 0)
         g.assurt(the_lval.stack_id not in self.update_lvals)
         self.update_lvals[the_lval.stack_id] = the_lval
      else:
         g.assurt(
               (the_lval.fresh and (the_lval.stack_id in self.create_lvals))
            or (the_lval.valid and (the_lval.stack_id in self.update_lvals)))

   #
   def edited_item_delete_item(self, the_item, update_dict):

      # MAYBE: The delete is applied to the database immediately.
      #        We might want to try to bulk-process deleting, like
      #        we do adding and updating items.

      if the_item.deleted:
         log.error('process_split_from: the_item already marked deleted?: %s'
                   % (str(the_item),))
      else:
         #log.debug('edited_item_delete_item: mark deleted: %s' % (the_item,))
         g.assurt(not the_item.valid)
         # The mark_deleted command updates that database immediately.
         # MAYBE: It also expects self.qb.grac_mgr to be set, which
         #        we could easily do, but let's try bulk-delete instead.
         #  g.assurt(self.qb.grac_mgr is None)
         #  self.qb.grac_mgr = Grac_Manager()
         #  the_item.mark_deleted(self.qb, f_process_item_hydrated=None)
         the_item.system_id = self.qb.db.sequence_get_next(
                                 'item_versioned_system_id_seq')
         the_item.version += 1
         the_item.acl_grouping = 1
         the_item.deleted = True
         the_item.valid_start_rid = self.qb.item_mgr.rid_new
         #
         try:
            if the_item.geometry_changed is None:
               the_item.geometry_changed = False
         except AttributeError:
            try:
               the_item.geometry_changed = False
               # Wasn't set; now it is.
            except AttributeError:
               pass # Not a geofeature.

         #
         try:
            if not the_item.geometry_wkt.startswith('SRID='):
               the_item.geometry_wkt = (
                  'SRID=%d;%s' % (conf.default_srid, the_item.geometry_wkt,))
         except AttributeError:
            pass # Not a geofeature.
         #
         g.assurt(the_item.stack_id not in update_dict)
         update_dict[the_item.stack_id] = the_item
         #
         try:
# FIXME/VERIFY: the_item.link_values should be non-multi lvals,
# like notes, normal attrs, tags, and discussions/posts.
            for lval in the_item.link_values.itervalues():
               # MAYBE: Do not delete the discussion/posts links...
               if lval.link_lhs_type_id in set([Item_Type.TAG,
                                                Item_Type.ATTRIBUTE,
                                                Item_Type.ANNOTATION,]):
                  # EXPLAIN: This is just so checking out all current
                  # link_values when populating the cache is faster,
                  # right?
                  self.edited_item_delete_item(lval, self.update_lvals)
                  self.stats['items_delete_lval'] += 1
         except AttributeError:
            pass # the_item.link_values is None.

   # BUG nnnn: Our db contains uppercase chars in tag names...
   #           seems silly, even if our software always does
   #           lower().
   #

   bug_nnnn_bad_tags = ('gravel road', 'unpaved',)

   #
   def tag_list_assemble(self, shpfeat, check_disconnected=False):

      add_tags = set()
      del_tags = set()

      try:
         for tag_name in shpfeat['properties']['item_tags'].split(','):
            tag_name = tag_name.strip().lower()
            if tag_name:
               if tag_name.startswith('-'):
                  del_tags.add(tag_name)
               else:
                  add_tags.add(tag_name)
         if self.cli_opts.fix_gravel_unpaved_issue:
            ccp_stack_id = ojint(shpfeat['properties']['CCP_ID'])
            if (    (ccp_stack_id >= self.cli_opts.first_suspect)
                and (ccp_stack_id <= self.cli_opts.final_suspect)):
               for bad_tag in Hausdorff_Import.bug_nnnn_bad_tags:
                  try:
                     add_tags.remove(bad_tag)
                  except KeyError:
                     pass
                  del_tags.add(bad_tag)
      except AttributeError:
         # AttributeError: 'NoneType' object has no attribute 'split'
         #  i.e., shpfeat['properties']['item_tags'] is None.
         pass

      # MAGIC_NAME: New disconnected tag.

      if ((check_disconnected)
          and (self.cli_opts.item_type == 'byway')):
         # 2014.07.23: Nowadays the route planner handles is_disconnected.
         try:
            if shpfeat['properties']['wconnected'] == '1':
               del_tags.add('disconnected')
            else:
               add_tags.add('disconnected')
         except KeyError:
            pass

      return add_tags, del_tags

   #
   def consolidate_duplisplits(self, shpfeat, target_item, source_item,
                                     first_ref):

      # If OPERATION contains a stack ID, it means the feature/item is being
      # deleted because it's a duplicate of another item. If CCP_FROMS_
      # contains a stack ID, it means the feature/item being created or
      # edited should get a clone of the reference item's lvals, etc.

      # Skipping: geometry. This is a clone of metadata, not of geometry.

      # We only consume values that aren't set in the target, i.e., we won't
      # overwrite existing target_item attributes or lvals.

      # See: edited_item_update_item(), which is similar, but compares a
      # Cyclopath item to a Shapefile feature.

      self.merge_byway_fields(shpfeat, target_item, source_item, first_ref)

      self.merge_non_user_lvals(shpfeat, target_item, source_item)

      self.merge_byway_aadt(shpfeat, target_item, source_item)

      self.merge_byway_ratings(shpfeat, target_item, source_item)

      self.merge_user_lvals(shpfeat, target_item, source_item)

   #
   def merge_byway_fields(self, shpfeat, target_item, source_item, first_ref):

      # MAGIC_NUMBERS: This binary values ORed together are just for debugging.
      #                What matters is if the value is 0 or not -- if it's not
      #                0, we edited the item and new to save a new version.
      updated_item = 0x0000

      # Do this first, so cleanup_byway_name has an accurate value.
      if ((not target_item.geofeature_layer_id)
          and source_item.geofeature_layer_id):
         gf_lyr_id, gf_lyr_name = (
            self.qb.item_mgr.geofeature_layer_resolve(
               self.qb.db, source_item.geofeature_layer_id))
         target_item.geofeature_layer_id = gf_lyr_id
         shpfeat['properties']['gf_lyr_id'] = gf_lyr_id
         shpfeat['properties']['gf_lyr_nom'] = gf_lyr_name
         updated_item |= 0x0002
         self.stats['split_gfl_id'] += 1
      elif target_item.geofeature_layer_id != source_item.geofeature_layer_id:
         self.stats['diffs_gfl_id'] += 1
      # else, they're equal.

      if (not target_item.name) and source_item.name:
         target_item.name = source_item.name
         updated_item |= 0x0001
         self.stats['split_ccp_name'] += 1
      elif (target_item.name
            and source_item.name
            and (target_item.name != source_item.name)):
         self.stats['diffs_ccp_name'] += 1
         if self.cli_opts.merge_names:
            if target_item.name.startswith(source_item.name):
               # Already got similar, but elongated, name.
               #log.debug('mrg_by_flds: keep longer target name: "%s" ==> "%s"'
               #          % (source_item.name, target_item.name,))
               pass
            elif source_item.name.startswith(target_item.name):
               # Source name starts with target name but is longer.
               # MN Stk IDs: 2920672.
               #log.debug('mrg_by_flds: swap longer source name: "%s" ==> "%s"'
               #          % (target_item.name, source_item.name,))
               target_item.name = source_item.name
               updated_item |= 0x0001
            else:
               # We preference the old name by default, since we assume our
               # map data is better than the data we're importing!
               unclean_merge = '/'.join([source_item.name, target_item.name,])
               target_item.name = self.cleanup_byway_name(unclean_merge,
                                                          target_item)
               updated_item |= 0x0001
               #log.debug('mrg_by_flds: merged route names: "%s" ==> "%s"'
               #          % (target_item.name, source_item.name,))
      # else, the names are equal.
      shpfeat['properties']['CCP_NAME'] = target_item.name

      # BUG nnnn: z-levels for polygons? Or are they just hard-coded?
      #
      if not target_item.z:
         target_item.z = byway.One.z_level_med
      if not source_item.z:
         source_item.z = byway.One.z_level_med
      if (   (target_item.z != byway.One.z_level_med) # != 134
          or (source_item.z != byway.One.z_level_med)):
         if (    (target_item.z == byway.One.z_level_med)
             and (source_item.z != byway.One.z_level_med)):
            target_item.z = source_item.z
            updated_item |= 0x0004
            self.stats['split_z_level'] += 1
         elif target_item.z != source_item.z:
            self.stats['diffs_z_level'] += 1
         # else, they're equal.
      shpfeat['properties']['z_level'] = target_item.z

      if (not target_item.one_way) and source_item.one_way:
         target_item.one_way = source_item.one_way
         shpfeat['properties']['one_way'] = target_item.one_way
         updated_item |= 0x0008
         self.stats['split_one_way'] += 1
      elif target_item.one_way != source_item.one_way:
         self.stats['diffs_one_way'] += 1
      # else, they're equal.

      # NOTE: The split_from_stack_id isn't important, or at least
      #       nothing is implemented that uses it. [lb] thinks the best
      #       it could do is to help a historical trail for a user, e.g.,
      #       in the client, highlight all split-intos with the same
      #       split-from, and maybe show the original, split-from line.

      if first_ref and (not target_item.split_from_stack_id):

# FIXME: Add split-from to export Shapefile?         
# FIXME: Only if the other ID > ours?
         target_item.split_from_stack_id = source_item.stack_id
         updated_item |= 0x0010
         self.stats['split_split_from_sid'] += 1
         g.assurt(target_item.split_from_stack_id > 0)
      elif target_item.split_from_stack_id != source_item.split_from_stack_id:
         self.stats['diffs_split_from_sid'] += 1
      # else, they're equal.

      if updated_item:
         target_item.dirty = item_base.One.dirty_reason_item_auto

   #

   # E.g., "MSAS 103".
   #RE_mndot_msas = re.compile(r'^\s*MSAS\s+\d+\s*$')
   # E.g., "M-1179". MN Stk Ids: 1359673
   #RE_mndot_mdash = re.compile(r'^\s*M-\d+\s*$')
   # There are a few named UT-... but they're in the woods.
   RE_mndot_names = re.compile(r'^\s*(M-|MSAS |T-)\d+\s*$')

   # Python 2.7's re.sub accepts flags, but not 2.6's, so compile them first.
   RE_mndot_usth = re.compile(r'(\s|^)USTH\s+(\d+)', re.IGNORECASE)
   RE_mndot_mnth1 = re.compile(r'(\s|^)MN TH\s+(\d+)', re.IGNORECASE)
   RE_mndot_mnth2 = re.compile(r'(\s|^)MNTH\s+(\d+)', re.IGNORECASE)
   RE_mndot_csah1 = re.compile(r'(\s|^)CSAH\s+(\d+)', re.IGNORECASE)
   RE_mndot_csah2 = re.compile(r'(\s|^)Co Rd\s+(\d+)', re.IGNORECASE)
   RE_mndot_cr = re.compile(r'(\s|^)CR-(\d+)', re.IGNORECASE)
   RE_mndot_isth = re.compile(r'(\s|^)ISTH\s+(\d+)', re.IGNORECASE)
   # These are no longer needed now that we capitalize() route names...
   RE_mndot_sp = re.compile(r'(\s|^)STATE PARK RD\s+(\d+)', re.IGNORECASE)
   RE_mndot_nf = re.compile(r'(\s|^)NATIONAL FOREST RD\s+(\d+)', re.IGNORECASE)

   #
   def cleanup_byway_name(self, byway_name, ref_item, delimiter='/'):

      if byway_name:
         route_names = [x for x in
                        [x.strip() for x in byway_name.split(delimiter)]
                         if x]
      else:
         route_names = []

      parsed_addrs = []

      for route_name in route_names:

         # Normalize certain names, like DOT road classification-type names.
         if self.cli_opts.friendly_names:
            # Some roads from MnDOT are ugly connector identifiers. We can
            # whack these.
            if Hausdorff_Import.RE_mndot_names.match(route_name) is not None:
               if ((ref_item is not None)
                   and (ref_item.geofeature_layer_id not in (
                           byway.Geofeature_Layer.Expressway_Ramp,
                           byway.Geofeature_Layer.Other_Ramp,))):
                  #log.debug('clnup_by_nom: MSAS/M- named item not ramp: %s'
                  #          % (ref_item,))
                  pass
               # Use a blank name instead.
               route_name = ''
            else:
               # Fix MNTH, etc. E.g.s,
               #  USTH 8 => US Hwy 8
               #  MNTH 50 => State Hwy 50
               #  CSAH 61 => County Rd 61
               #  ISTH 94 => I-94 or I 94
               fname = route_name
               fname = re.sub(Hausdorff_Import.RE_mndot_usth,
                              '\\1US Hwy \\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_mnth1,
                              '\\1State Hwy \\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_mnth2,
                              '\\1State Hwy \\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_csah1,
                              '\\1County Rd \\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_csah2,
                              '\\1County Rd \\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_cr,
                              '\\1County Rd \\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_isth,
                              '\\1I-\\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_sp,
                              '\\1State Park Rd \\2', fname)
               fname = re.sub(Hausdorff_Import.RE_mndot_nf,
                              '\\1National Forest Rd \\2', fname)
               if fname != route_name:
                  #log.debug(
                  #  'clnup_by_nom: friendly name: %s / fr: %s / in: %s'
                  #  % (fname, route_name, byway_name,))
                  route_name = fname

         # Deek out the parser. Supply a house number and citystate.
         addr_parsed = self.parse_streetaddy(route_name)

         # Add address to the ordered list we'll cull when we fish out dupls.
         parsed_addrs.append((route_name, addr_parsed,))

      # 2014.04.07: Maybe: Cleanup periods in names. There are 417 names with
      # periods in them. Some are abbreviations, e.g., "St. Paul". Others are
      # extraneous marks that we could/should remove, e.g., "2419 S. 9th St.".
      # And others are not names, e.g., "4/10/11 path ends here.".
      #  SELECT DISTINCT(name) FROM item_versioned WHERE name like '%.%'
      #  ORDER BY name;
      # You can uncomment this too poke around with the address object. The
      # parse_streetaddy call removes periods in the prefix, suffix, and
      # street type, so we could just 
      #
      #  try:
      #     if byway_name and (byway_name.index('Ave.') != -1):
      #        conf.break_here('ccpv3')
      #  except ValueError:
      #     pass

      unparsable = set()
      full_names = {}
      for paddr in parsed_addrs:
         route_name, addr_parsed = paddr
         if not addr_parsed:
            unparsable.add(route_name)
         else:
            new_name = ' '.join(
               [x for x in [
                  addr_parsed['prefix'],
                  addr_parsed['street'],
                  addr_parsed['street_type'],
                  addr_parsed['suffix'],] if x])
            if route_name != new_name:
               log.debug('clnup_by_nom: normalized name: "%s" ==> "%s"'
                         % (route_name, new_name,))
               route_name = new_name
            exact_match = False
            for match_list in full_names.values():
               for match_tup in match_list:
                  other_name, other_addr = match_tup
                  if route_name == other_name:
                     exact_match = True
                     break
            if not exact_match:
               if addr_parsed['street'] not in full_names:
                  misc.dict_list_append(full_names,
                                        addr_parsed['street'],
                                        (route_name, addr_parsed,))
               else:
                  # We've seen a route with this street name already, but the
                  # prefixes or suffices or street types differ.
                  new_list = []
                  merged = False
                  match_list = full_names[addr_parsed['street']]
                  for match_tup in match_list:
                     other_name, other_addr = match_tup
                     if not merged:
                        mergeable = False
                        for component in ('prefix',
                                          'suffix',
                                          'street_type',):
                           if (addr_parsed[component]
                               and other_addr[component]
                               and (addr_parsed[component]
                                    != other_addr[component])):
                              mergeable = False
                        if mergeable:
                           for component in ('prefix',
                                             'suffix',
                                             'street_type',):
                              if not addr_parsed[component]:
                                 addr_parsed[component] = other_addr[component]
                           new_name = ' '.join(
                              [x for x in [
                                 addr_parsed['prefix'],
                                 addr_parsed['street'],
                                 addr_parsed['street_type'],
                                 addr_parsed['suffix'],] if x])
                           log.debug(
                              'clnup_by_nom: merged names "%s" + "%s" ==> "%s"'
                              % (full_names[addr_parsed['street']],
                                 route_name,
                                 new_name,))
                           new_list.append((new_name, addr_parsed,))
                           merged = True
                     if not merged:
                        # Not mergeable, so keep the existing match.
                        new_list.append((other_name, other_addr,))
                  # end: for match_tup in match_list
                  if not merged:
                     # Not merged, so add to list.
                     new_list.append((route_name, addr_parsed,))
                  full_names[addr_parsed['street']] = new_list
            # else, exact_match, so ignore the duplicate.

   # FIXME: Sort by street type. E.g., for highways in small towns, put local
   #        street name before highway name, e.g., "Main St / US Hwy 11",
   #        rather than "US Hwy 11 / Main St".

      route_names = list(unparsable)
      for match_tup in full_names.values():
         route_names += [x[0] for x in match_tup]

      new_name = ' / '.join(route_names)

      #if new_name != byway_name:
      #   log.debug('clnup_by_nom: changing: "%s" ==> "%s"'
      #             % (byway_name, new_name,))

      return new_name

   #
   def merge_non_user_lvals(self, shpfeat, target_item, source_item):

      # Make any links in the target that are found in the source.
      # Note that we've already added and deleted tags and attributes
      # according to the feature fields, so just be sure not to re-add
      # tags we deleted or attributes to unset.
      del_tag_sids = set()
      add_tag_names, del_tag_names = self.tag_list_assemble(shpfeat)
      for tag_name in del_tag_names:
         tag_item = self.qb.item_mgr.cache_tag_lookup_by_name(tag_name)
         if tag_item is not None:
            del_tag_sids.add(tag_item.stack_id)

      tag_names = []

      for lval in source_item.link_values.itervalues():
         add_ok = True
         if lval.link_lhs_type_id == Item_Type.TAG:
            # Check not scrubbing 'gravel road' and 'unpaved', or not
            # deleted by user via feature field.
            if (((self.cli_opts.fix_gravel_unpaved_issue)
                 and (lval.lhs_stack_id in self.bad_tag_sids))
                or (lval.lhs_stack_id in del_tag_sids)):
               add_ok = False
            if add_ok:
               try:
                  the_tag = self.qb.item_mgr.cache_tags[lval.lhs_stack_id]
                  tag_names.append(the_tag.name)
               except KeyError:
                  log.warning('Missing tag? No tag found with stack ID: %s'
                              % (lval.lhs_stack_id,))
               if lval.lhs_stack_id not in target_item.link_values:
                  # The tag isn't already set or wasn't deleted; add it.
                  self.add_new_lval_lval(target_item, lval)
                  self.stats['split_lval_add'] += 1
                  misc.dict_count_inc(self.stats['edit_tag_add_name'],
                                      the_tag.name)
         elif lval.link_lhs_type_id == Item_Type.ATTRIBUTE:
            try:
               target_lval = target_item.link_values[lval.lhs_stack_id]
            except KeyError:
               target_lval = None
            try:
               ccp_attr = self.field_attr_cache_sid[lval.lhs_stack_id]
               fieldn = self.attr_to_field[ccp_attr.value_internal_name]
            except KeyError:
               ccp_attr = None
            if ccp_attr is not None:
               g.assurt(not ccp_attr.multiple_allowed) # Am I right?
               if target_lval is None:
                  self.add_new_lval_attc(target_item, ccp_attr,
                                         value_integer=lval.value_integer,
                                         value_text=lval.value_text)
                  shpfeat['properties'][fieldn] = lval.value_integer
                  self.stats['split_lval_add'] += 1
               elif ccp_attr.value_type == 'integer':
                  if not target_lval.value_integer:
                     #self.update_lval_attc(target_lval, ccp_attr,
                     #   value_integer=lval.value_integer, value_text=None)
                     self.update_lval_lval(target_lval,
                                           value_integer=lval.value_integer,
                                           value_text=lval.value_text)
                     shpfeat['properties'][fieldn] = lval.value_integer
                     self.stats['split_lval_edit'] += 1
                  elif (target_lval.value_integer != lval.value_integer):
                     self.stats['diffs_lval_edit'] += 1
                  else:
                     # The attribute values are equal.
                     self.stats['split_lval_skip'] += 1
               elif ccp_attr.value_type == 'text':
                  if not target_lval.value_text:
                     #self.update_lval_attc(target_lval, ccp_attr,
                     #   value_integer=None, value_text=lval.value_text)
                     self.update_lval_lval(target_lval,
                                           value_integer=lval.value_integer,
                                           value_text=lval.value_text)
                     shpfeat['properties'][fieldn] = lval.value_text
                     self.stats['split_lval_edit'] += 1
                  elif (target_lval.value_text != lval.value_text):
                     self.stats['diffs_lval_edit'] += 1
                  else:
                     # The attribute values are equal.
                     self.stats['split_lval_skip'] += 1

            # else, this is some other attribute we don't care about.
         else:
            # ANNOTATION, POST, or DISCUSSION.
            if lval.lhs_stack_id not in target_item.link_values:
               self.add_new_lval_lval(target_item, lval)
               # Skipping shpfeat['properties'], which doesn't show notes/posts
               self.stats['split_lval_add'] += 1
            else:
               # A similar link_value already exists for the target.
               self.stats['split_lval_skip'] += 1

      shpfeat['properties']['item_tags'] = ','.join(tag_names)

   #
   def merge_byway_aadt(self, shpfeat, target_item, source_item):

      # Skipping: We don't show or allow editing of AADT via Shpfile.

      aadt_fetch_sql = target_item.aadt_fetch_sql(aadt_type='',
                                                  all_records=True)
      target_rows = self.qb.db.sql(aadt_fetch_sql)
      #
      aadt_fetch_sql = source_item.aadt_fetch_sql(aadt_type='',
                                                  all_records=True)
      source_rows = self.qb.db.sql(aadt_fetch_sql)
      #
      if (not target_rows) and source_rows:
         for source_row in source_rows:
            # See we might try merging to the same item from more than one
            # other item, we have to check for duplicates.
            try:
               add_row = source_row['aadt_type'] not in self.aadts_dbldict[
                  target_item.stack_id][source_row['aadt_year']]
            except KeyError:
               add_row = True
            if add_row:
               try:
                  self.aadts_dbldict[target_item.stack_id][
                     source_row['aadt_year']].add(
                           source_row['aadt_type'])
               except KeyError:
                  misc.dict_dict_update(self.aadts_dbldict,
                                        target_item.stack_id,
                                        source_row['aadt_year'],
                                        set([source_row['aadt_type'],]))
               insert_aadt = (
                  "(%d, %d, %d, %d, '%s', '%s')"
                  % (target_item.stack_id,
                     target_item.branch_id,
                     source_row['aadt'],
                     source_row['aadt_year'],
                     source_row['aadt_type'],
                     source_row['last_modified'],
                     ))
               self.insert_aadts.append(insert_aadt)
               self.stats['items_clone_aadt'] += 1

   #
   def merge_byway_ratings(self, shpfeat, target_item, source_item):

      # Skipping: We show but don't allow editing of ratings via Shpfile,
      #           and, anyway, we're just copying user ratings here, and
      #           we're not touching any of the calculated ratings (though
      #           you should re-run the ratings generator after running
      #           the import script).

      # Check the byway_rating table for user ratings.
      #
      rating_user_sql = target_item.rating_user_sql()
      target_rows = self.qb.db.sql(rating_user_sql)
      #
      rating_user_sql = source_item.rating_user_sql()
      source_rows = self.qb.db.sql(rating_user_sql)
      #
      if (not target_rows) and source_rows:
         for source_row in source_rows:
            # See we might try merging to the same item from more than one
            # other item, we have to check for duplicates.
            try:
               self.brats_dbldict[source_row['username']][target_item.stack_id]
            except KeyError:
               misc.dict_dict_update(self.brats_dbldict,
                                     source_row['username'],
                                     target_item.stack_id,
                                     True)
               brat_insert_expr = (
                  "(%d, %d, %s, %s)"
                  % (target_item.stack_id,
                     target_item.branch_id,
                     self.qb.db.quoted(source_row['username']),
                     source_row['value'],
                     # Skipping (has trigger): last_modified
                     ))
               self.insert_brats.append(brat_insert_expr)
               # MAYBE: Also update byway_rating_event?
               #        Or maybe we don't have to worry...
               self.stats['items_clone_brat'] += 1

   #
   def merge_user_lvals(self, shpfeat, target_item, source_item):

      # MAYBE: We don't copy watchers:
      #           item_findability
      #           item_event_alert
      #           item_event_read
      #        Maybe we should copy item watchers...

      # Copy watchers and reminders.
      #
      # /item/reminder_email is deleted...
      #  for multi_attr_name in ('/item/alert_email', '/item/reminder_email',):
      for multi_attr_name in ('/item/alert_email',):
         link_many = link_attribute.Many(multi_attr_name)
         all_attribute_lvals_sql = link_many.link_multiple_allowed_sql(
            self.qb, source_item.stack_id)
         rows = self.qb.db.sql(all_attribute_lvals_sql)
         for row in rows:
            #
            new_lval = link_value.One()
            #
            # Item Base
            # Skipping: dirty, fresh, valid, req, attrs, tagged,
            #           link_values, lvals_wired_, lvals_inclusive_
            #
            # Item Versioned
            new_lval.system_id = self.qb.db.sequence_get_next(
                                    'item_versioned_system_id_seq')
            new_lval.branch_id = self.qb.branch_hier[0][0]
            new_lval.stack_id = self.qb.db.sequence_get_next(
                                    'item_stack_stack_id_seq')
            new_lval.version = 1
            new_lval.deleted = False
            new_lval.reverted = False
            new_lval.name = row['name']
            new_lval.valid_start_rid = self.qb.item_mgr.rid_new
            new_lval.valid_until_rid = conf.rid_inf
            #
            # Item Revisionless
            new_lval.acl_grouping = 1
            # Skipping: new_lval.edited_date
            # Skipping: new_lval.edited_user
            # Skipping: new_lval.edited_addr
            # Skipping: new_lval.edited_host
            # Skipping: new_lval.edited_note
            # Skipping: new_lval.edited_what
            #
            # Item User Access / These are inferred from GIA records
            new_lval.access_level_id = row['access_level_id']
            # Skipping: diff_group, style_change, real_item_type_id
            new_lval.item_type_id = new_lval.item_type_id
            #
            # Item Stack
            # Skipping: stealth_secret
            new_lval.cloned_from_id = row['cloned_from_id']
            new_lval.access_style_id = row['access_style_id']
            new_lval.access_infer_id = row['access_infer_id']
            #
            # Link_Value
            new_lval.lhs_stack_id = link_many.attr_stack_id
            new_lval.rhs_stack_id = target_item.stack_id
            new_lval.link_lhs_type_id = link_many.one_class.item_type_table
            new_lval.link_rhs_type_id = target_item.item_type_id
            new_lval.value_boolean = row['value_boolean']
            new_lval.value_integer = row['value_integer']
            new_lval.value_real = row['value_real']
            new_lval.value_text = row['value_text']
            new_lval.value_binary = row['value_binary']
            new_lval.value_date = row['value_date']
            new_lval.lhs_name = multi_attr_name
            new_lval.rhs_name = target_item.name
            #new_lval.split_from_stack_id = source_item.stack_id


# FIXME: Only if really split, not if CCP_FROMS_, but if dupl sids
# FIXME: Only if the other ID > ours?
            new_lval.split_from_stack_id = row['stack_id']
            g.assurt(new_lval.split_from_stack_id > 0)



            # Skipping/Not implemented:
            #  direction_id, line_evt_mval_a, line_evt_mval_b, line_evt_dir_id
            #
            self.add_new_item_gia(new_lval)
            #
            new_lval.fresh = True
            new_lval.validize(
               self.qb,
               is_new_item=True,
               dirty_reason=item_base.One.dirty_reason_item_auto,
               ref_item=None)
            g.assurt(new_lval.stack_id not in self.create_lvals)
            self.create_lvals[new_lval.stack_id] = new_lval
            target_item.wire_lval(self.qb, new_lval, heavywt=True)
            self.stats['items_clone_lval_multiattr'] += 1

   # **** Process edited items: bulk-save database changes

   #
   def save_db_changes(self):

      self.edited_items_finalize_versions(self.update_feats.values())
      self.edited_feats_bulk_insert_rows(self.create_feats.values()
                                       + self.update_feats.values())

      self.edited_items_finalize_versions(self.update_lvals.values())
      self.edited_lvals_bulk_insert_rows(self.create_lvals.values()
                                       + self.update_lvals.values())

      if self.cli_opts.item_type == 'byway':
         self.save_db_aadt()
         self.save_db_nodes()

   #
   def save_db_aadt(self):
      # AADT.
      if self.insert_aadts:
         insert_sql = (
            """
            INSERT INTO %s.aadt (
               byway_stack_id
               , branch_id
               , aadt
               , aadt_year
               , aadt_type
               , last_modified
               ) VALUES
                  %s
            """ % (conf.instance_name,
                   ','.join(self.insert_aadts),))
         self.qb.db.sql(insert_sql)

   #
   def save_db_nodes(self):
      # We're about to commit the transaction, so mucking with the branch_hier
      # is okay. And we can't clone the database to save node stuff, since we
      # haven't save byway changes; we'd have to commit first, anyway.

      node_qb = self.qb
      node_qb.revision = revision.Current()
      node_qb.branch_hier[0] = (node_qb.branch_hier[0][0],
                                node_qb.revision,
                                node_qb.branch_hier[0][2],)
      # Call node_qb.revision.setup_gids(node_qb.db, node_qb.username) or ?:
      #  node_qb.branch_hier_set(node_qb.branch_hier)
      node_qb.db.transaction_begin_rw('node_endpoint')

      if self.delete_nodes_for:
         log.debug('save_db_chngs: deleting %d from node_byway...'
                   % (len(self.delete_nodes_for),))
         cleanup_sql = (
            """
            DELETE FROM node_byway
            WHERE branch_id = %d
              AND byway_stack_id IN (%s)
            """ % (node_qb.branch_hier[0][0],
                   ','.join([str(x) for x in self.delete_nodes_for]),))
         node_qb.db.sql(cleanup_sql)
         self.delete_nodes_for = set()

      for feat in (self.create_feats.values() + self.update_feats.values()):
         try:
            # We're saving separately in parallel so we'll get node-endpoint
            # complainst about counts since we saved at revision minus one
            # but now we're at the current revision.
            feat.save_or_update_node_endpoints(node_qb)
         except AttributeError:
            raise

   #
   def edited_items_finalize_versions(self, updated_items):

      if updated_items:

         item_sids = [str(item.stack_id) for item in updated_items]

         # Finalize item rows (change valid_until_rid of the last version from
         # conf.rid_inf to a historic rid) in the two tables, item_versioned
         # and group_item_access.
         for table_name in (group_item_access.One.item_type_table,
                            item_versioned.One.item_type_table,):
            update_sql = (
               """
               UPDATE %s.%s SET valid_until_rid = %s
               WHERE (stack_id IN (%s))
                 AND (branch_id = %d)
                 AND (valid_until_rid = %d)
               """ % (conf.instance_name,
                      table_name,
                      self.qb.item_mgr.rid_new,
                      ','.join(item_sids),
                      self.qb.branch_hier[0][0],
                      conf.rid_inf,
                      ))
            self.qb.db.sql(update_sql)

   #
   def edited_feats_bulk_insert_rows(self, edited_feats):

      item_module = item_factory.get_item_module(self.cli_opts.item_type)
      g.assurt(item_module is not None)

      is_rows = []
      iv_rows = []
      ir_rows = []
      #gf_rows = []
      by_rows = []
      gia_rows = []
      #at_rows = []
      #tg_rows = []
      rat_sids = []

      for feat in edited_feats:

         g.assurt(feat.valid or feat.deleted)

         if feat.version == 1:
            g.assurt(feat.fresh)
            expr = item_stack.One.as_insert_expression(self.qb, feat)
            is_rows.append(expr)
         else:
            g.assurt(not feat.fresh)

         expr = item_versioned.One.as_insert_expression(self.qb, feat)
         iv_rows.append(expr)

         expr = item_revisionless.One.as_insert_expression(self.qb, feat)
         ir_rows.append(expr)

         # Skipping: geofeature; use byway class instead.

         expr = item_module.One.as_insert_expression(self.qb, feat)
         by_rows.append(expr)

         self.edit_items_bulk_insert_gia(feat, gia_rows)

         # Also, byway ratings.
         if (item_module == byway) and (not feat.deleted):
            byway.One.add_insert_expressions_ratings_generic(
                  self.qb, feat, self.insert_brats, rat_sids)
         # else, don't update ratings for deleted byways, right?

      log.debug('edited_feats_bulk_insert_rows: updating feats...')

      time_0 = time.time()

      item_stack.Many.bulk_insert_rows(self.qb, is_rows)
      item_versioned.Many.bulk_insert_rows(self.qb, iv_rows)
      item_revisionless.Many.bulk_insert_rows(self.qb, ir_rows)
      item_module.Many.bulk_insert_rows(self.qb, by_rows)

# IntegrityError('insert or update on table
# "group_item_access" violates foreign key constraint
# "group_item_access_branch_id_stack_id_version_fkey"\nDETAIL:  Key
# (branch_id, stack_id, version)=(2500677, 4067168, 0) is not present in table
# "item_versioned".\n',)

      group_item_access.Many.bulk_insert_rows(self.qb, gia_rows)

      log.debug('edited_feats_bulk_insert_rows: updated feats in %s'
                % (misc.time_format_elapsed(time_0),))

      time_0 = time.time()

      if rat_sids:
         try:
            byway.Many.bulk_delete_ratings_generic(self.qb, rat_sids)
            byway.Many.bulk_insert_ratings(self.qb, self.insert_brats)
         except Exception, e:
            conf.break_here() # To help a DEV.
            raise

      log.debug('edited_feats_bulk_insert_rows: updated ratings in %s'
                % (misc.time_format_elapsed(time_0),))

   #
   def edited_lvals_bulk_insert_rows(self, edited_lvals):

      is_rows = []
      iv_rows = []
      ir_rows = []
      lv_rows = []
      gia_rows = []

      for lval in edited_lvals:

         if lval.version == 1:
            expr = item_stack.One.as_insert_expression(self.qb, lval)
            is_rows.append(expr)

         expr = item_versioned.One.as_insert_expression(self.qb, lval)
         iv_rows.append(expr)

         expr = item_revisionless.One.as_insert_expression(self.qb, lval)
         ir_rows.append(expr)

         expr = link_value.One.as_insert_expression(self.qb, lval)
         lv_rows.append(expr)

         self.edit_items_bulk_insert_gia(lval, gia_rows)

      log.debug('edited_lvals_bulk_insert_rows: updating lvals...')

      time_0 = time.time()

      item_stack.Many.bulk_insert_rows(self.qb, is_rows)
      item_versioned.Many.bulk_insert_rows(self.qb, iv_rows)
      item_revisionless.Many.bulk_insert_rows(self.qb, ir_rows)
      link_value.Many.bulk_insert_rows(self.qb, lv_rows)
      group_item_access.Many.bulk_insert_rows(self.qb, gia_rows)

      log.debug('edited_lvals_bulk_insert_rows: updated lvals in %s'
                % (misc.time_format_elapsed(time_0),))

   #
   def edit_items_bulk_insert_gia(self, item, gia_rows):
      for grp_acc in item.groups_access.itervalues():
         # If we made a new GIA record, we didn't set its rids,
         # because the owning item complains in its validize.
         g.assurt(grp_acc.group_id > 0)
         # Skipping: session_id
         # Skipping: access_level_id
         grp_acc.branch_id = item.branch_id
         grp_acc.item_id == item.system_id
         grp_acc.stack_id = item.stack_id
         grp_acc.version = item.version
         grp_acc.acl_grouping = 1
         grp_acc.deleted = item.deleted
         grp_acc.reverted = item.reverted
         grp_acc.valid_start_rid = item.valid_start_rid
         grp_acc.valid_until_rid = item.valid_until_rid
         grp_acc.name = item.name
         # Skipping: tsvect_name
         try:
            g.assurt((item.link_lhs_type_id > 0)
                     and (item.link_rhs_type_id > 0))
            grp_acc.link_lhs_type_id = item.link_lhs_type_id
            grp_acc.link_rhs_type_id = item.link_rhs_type_id
         except AttributeError:
            pass # item not a link_value.
         expr = group_item_access.One.as_insert_expression(self.qb, grp_acc,
                                                           item.item_type_id)
         gia_rows.append(expr)

   # *** Non-byway export (see work item export job for exporting byways)

   #
   def do_export_non_byway(self):

      self.stats_init_export()

      item_module = item_factory.get_item_module(self.cli_opts.item_type)
      g.assurt(item_module is not None)

      if not os.path.exists(self.cli_opts.source_dir):
         try:
            os.mkdir(self.cli_opts.source_dir, 02775)
         except OSError, e:
            log.error('Unexpected: Could not make export directory: %s'
                      % (str(e),))
            raise

      target_schema = Hausdorff_Import.intermediate_schema_non_byway
      try:
         self.prepare_target_shapefiles(target_schema)
      except Exception, e:
         log.error('Unable to prepare targets: %s' % (str(e),))
         raise

      try:
         self.load_and_export_items(item_module)
      finally:
         for shpfile in self.slayers.values():
            try:
               shpfile.close()
            except:
               pass
         self.slayers = None
         try:
            self.everylayer.close()
         except:
            pass
         self.everylayer = None

      self.symlink_target_shapefiles(link_name='Exported')

      self.stats_show_export()

   #
   # C.f. services/merge/export_cyclop.py
   def load_and_export_items(self, feat_class):

      log.info('load_and_export_items: working on type: %s'
               % (Item_Type.id_to_str(feat_class.One.item_type_id),))

      time_0 = time.time()

      prog_log = Debug_Progress_Logger()
      prog_log.log_freq = 100

      self.qb.filters.rating_special = True

      self.qb.filters.make_geometry_ewkt = True

      # The merge_job setup the item_mgr, which we use now to load the byways
      # and their attrs and tags.
      feat_search_fcn = 'search_for_items' # E.g. byway.Many().search_for_items
      processing_fcn = self.feat_export
      self.qb.item_mgr.load_feats_and_attcs(
            self.qb, feat_class, feat_search_fcn,
            processing_fcn, prog_log, heavyweight=False)

      log.info('... exported %d features in %s'
               % (prog_log.progress,
                  misc.time_format_elapsed(time_0),))

   # ***

   #
   def feat_export(self, qb, gf, prog_log):

      log.debug('feat_export: gf: %s' % (str(gf),))

      new_geom = {}
      if isinstance(gf, terrain.One):
         #new_geom['type'] = 'Polygon'
         new_geom['type'] = 'MultiPolygon'
         new_geom['coordinates'] = geometry.wkt_polygon_to_xy(gf.geometry_wkt)
      elif isinstance(gf, region.One):
         #new_geom['type'] = 'Polygon'
         new_geom['type'] = 'MultiPolygon'
         new_geom['coordinates'] = geometry.wkt_polygon_to_xy(gf.geometry_wkt)
      elif isinstance(gf, waypoint.One):
         new_geom['type'] = 'Point'
         new_geom['coordinates'] = geometry.wkt_point_to_xy(gf.geometry_wkt)
      else:
         g.assurt(False)

      gf_lyr_id, gf_lyr_name = (
         self.qb.item_mgr.geofeature_layer_resolve(
            self.qb.db, gf.geofeature_layer_id))

      for tag_name in gf.tagged:
         misc.dict_count_inc(self.stats['export_tag_counts'], tag_name)

      new_props = {
         #'GUIDANCE': '',
         #'OPERATION': '',
         'CCP_ID': gf.stack_id,
         'CCP_NAME': gf.name,
         'gf_lyr_id': gf_lyr_id,
         'gf_lyr_nom': gf_lyr_name,
         ##'CCP_FROMS_': '',
         #'import_err': '',
         'item_tags': ', '.join(gf.tagged),
         #'z_level': '',
         #'gfl_typish': '',
         'CCP_SYS': gf.system_id,
         'CCP_VERS': gf.version,
         #'OBJECTID': '',
         }

      new_feat = { 'geometry': new_geom,
                   'properties': new_props, }

      self.record_match_result_target(new_feat)

      self.stats['items_total_exported'] += 1

   # ***

   # **** Initing Stats

   #
   def stats_init_initer(self):

      self.stats['feats_magic_del_new'] = 0
      self.stats['feats_magic_del_old'] = 0
      self.stats['feats_magic_del_sids'] = {}

      self.stats['feats_magic_swap_new'] = 0
      self.stats['feats_magic_swap_old'] = 0
      self.stats['feats_magic_swap_sids'] = {}

      self.stats['feats_missing_geometry'] = 0
      self.stats['feats_ring_geometry'] = 0

      self.stats['regions_consume_geom_city'] = 0
      self.stats['regions_consume_geom_twns'] = 0
      self.stats['regions_tossed_other_city'] = 0
      self.stats['regions_tossed_other_twns'] = 0

   #
   def stats_show_initer(self):

      log.info(60 * '=')

      log.info('Stats for Hausdorff Import Init')

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Number *new* feats in magic delete',
                  self.stats['feats_magic_del_new'],))
      log.info('%45s: %s'
               % ('Number *old* feats in magic delete',
                  self.stats['feats_magic_del_old'],))
      if (self.stats['feats_magic_del_new']
          != self.stats['feats_magic_del_old']):
         log.warning('Magic Delete discrepancy!')
         for stk_id, cnt in self.stats['feats_magic_del_sids'].iteritems():
            if cnt == 1:
               log.warning('  not twice+: %s (%d)' % (stk_id, cnt,))
            # else, 2, or maybe 3 or more.

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Number *new* feats in magic delete',
                  self.stats['feats_magic_swap_new'],))
      log.info('%45s: %s'
               % ('Number *old* feats in magic delete',
                  self.stats['feats_magic_swap_old'],))
      if (self.stats['feats_magic_swap_new']
          != self.stats['feats_magic_swap_old']):
         log.warning('Magic Swap discrepancy!')
         for stk_id, cnt in self.stats['feats_magic_swap_sids'].iteritems():
            if cnt == 1:
               log.warning('  not twice+: %s (%d)' % (stk_id, cnt,))

      log.info(50 * '-')

      if self.cli_opts.import_fix_mndot_polies:

         log.info('%45s: %s'
                  % ('Number MnDOT geometries: city',
                     len(self.mndot_geom['city']),))

         log.info('%45s: %s'
                  % ('Number MnDOT geometries: township',
                     len(self.mndot_geom['township']),))

         log.info('%45s: %s'
                  % ('Number Ccp names: city',
                     len(self.ccp_region['city']),))

         log.info('%45s: %s'
                  % ('Number Ccp names: township',
                     len(self.ccp_region['township']),))

         log.info('%45s: %s'
                  % ('Number geometries consumed: city',
                     self.stats['regions_consume_geom_city'],))

         log.info('%45s: %s'
                  % ('Number geometries consumed: township',
                     self.stats['regions_consume_geom_twns'],))

         log.info('%45s: %s'
                  % ('Number new features conflicted/tossed: city',
                     self.stats['regions_tossed_other_city'],))

         log.info('%45s: %s'
                  % ('Number new features conflicted/tossed: township',
                     self.stats['regions_tossed_other_twns'],))


         log.info(50 * '-')

   # **** Editing Stats

   #
   def stats_init_worker(self):

      self.stats['problem_items'] = 0
      self.stats['items_new_gfs'] = 0
      self.stats['items_new_lval'] = 0
      self.stats['items_new_tag'] = 0
      self.stats['items_err_tag'] = 0
      self.stats['items_noop_item'] = 0
      self.stats['items_edit_item'] = 0
      self.stats['items_edit_lval'] = 0
      self.stats['items_clone_aadt'] = 0
      self.stats['items_clone_brat'] = 0
      self.stats['items_clone_lval_annot'] = 0
      self.stats['items_clone_lval_multiattr'] = 0
      self.stats['items_delete_item'] = 0
      self.stats['items_delete_lval'] = 0

      for prefix in ('edit', 'split', 'diffs',):
         self.stats['%s_ccp_name' % prefix] = 0
         self.stats['%s_gfl_id' % prefix] = 0
         self.stats['%s_z_level' % prefix] = 0
         self.stats['%s_one_way' % prefix] = 0
         self.stats['%s_is_disconnected' % prefix] = 0
         self.stats['%s_split_from_sid' % prefix] = 0
         self.stats['%s_geometry' % prefix] = 0
         self.stats['%s_lval' % prefix] = 0
         self.stats['%s_lval_add' % prefix] = 0
         self.stats['%s_lval_edit' % prefix] = 0
         self.stats['%s_lval_delete' % prefix] = 0
         self.stats['%s_lval_skip' % prefix] = 0
         self.stats['%s_attr' % prefix] = 0
         self.stats['%s_attr_add' % prefix] = 0
         self.stats['%s_attr_edit' % prefix] = 0
         self.stats['%s_attr_delete' % prefix] = 0
         self.stats['%s_tag' % prefix] = 0
         self.stats['%s_tag_add' % prefix] = 0
         self.stats['%s_tag_delete' % prefix] = 0
      self.stats['edit_tag_add_name'] = {}
      self.stats['edit_tag_del_name'] = {}

   #
   def stats_show_worker(self):

      log.info(60 * '=')

      log.info('Stats for Hausdorff Import Worker')

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Number feats: w/ problems',
                  self.stats['problem_items'],))

      log.info('%45s: %s'
               % ('Number geofeatures:  unchanged',
                  self.stats['items_noop_item'],))
      log.info('%45s: %s'
               % ('Number geofeatures:     edited',
                  self.stats['items_edit_item'],))
      log.info('%45s: %s'
               % ('Number geofeatures:    created',
                  self.stats['items_new_gfs'],))

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Number link_values: edited',
                  self.stats['items_edit_lval'],))
      log.info('%45s: %s'
               % ('Number link_values:    new',
                  self.stats['items_new_lval'],))

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Number tags: new',
                  self.stats['items_new_tag'],))
      log.info('%45s: %s'
               % ('Number tags: err',
                  self.stats['items_err_tag'],))

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Number split-into cloned:  addt volumes',
                  self.stats['items_clone_aadt'],))
      log.info('%45s: %s'
               % ('Number split-into cloned: byway ratings',
                  self.stats['items_clone_brat'],))
      log.info('%45s: %s'
               % ('Number split-into cloned:   annotations',
                  self.stats['items_clone_lval_annot'],))
      log.info('%45s: %s'
               % ('Number split-into cloned:   multi-attrs',
                  self.stats['items_clone_lval_multiattr'],))

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Number deleted:       items',
                  self.stats['items_delete_item'],))
      log.info('%45s: %s'
               % ('Number deleted: link_values',
                  self.stats['items_delete_lval'],))

      log.info(50 * '-')

      for prefix in ('edit', 'split', 'diffs',):
         capped = prefix.capitalize()
         log.info('%45s: %s'
                  % ('%s items: changes to Ccp_name' % capped,
                     self.stats['%s_ccp_name' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to GFL ID' % capped,
                     self.stats['%s_gfl_id' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to Z-level' % capped,
                     self.stats['%s_z_level' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to One-way' % capped,
                     self.stats['%s_one_way' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes Is Disconnected' % capped,
                     self.stats['%s_is_disconnected' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to Split from Sid' % capped,
                     self.stats['%s_split_from_sid' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to Geometry' % capped,
                     self.stats['%s_geometry' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to attrs: updated' % capped,
                     self.stats['%s_lval' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to lvals: added' % capped,
                     self.stats['%s_lval_add' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to lvals: editd' % capped,
                     self.stats['%s_lval_edit' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to lvals: deled' % capped,
                     self.stats['%s_lval_delete' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to lvals: skipd' % capped,
                     self.stats['%s_lval_skip' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to attrs: updated' % capped,
                     self.stats['%s_attr' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to attrs: added' % capped,
                     self.stats['%s_attr_add' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to attrs: editd' % capped,
                     self.stats['%s_attr_edit' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to attrs: deled' % capped,
                     self.stats['%s_attr_delete' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to tags: updated' % capped,
                     self.stats['%s_tag' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to tags: added' % capped,
                     self.stats['%s_tag_add' % prefix],))
         log.info('%45s: %s'
                  % ('%s items: changes to tags: deled' % capped,
                     self.stats['%s_tag_delete' % prefix],))

         log.info(50 * '-')

      # ***

      log.info('%45s' % ('Number tags added by name--',))
      for tagname, addcount in self.stats['edit_tag_add_name'].iteritems():
         log.info('%45s: %s' % (tagname, addcount,))

      log.info('%45s' % ('Number tags deleted by name--',))
      for tagname, delcount in self.stats['edit_tag_del_name'].iteritems():
         log.info('%45s: %s' % (tagname, delcount,))

      log.info(50 * '-')

   # **** Matching Stats

   #
   def stats_init_matching(self):

      self.stats['hausd_dist_raw'] = {}
      self.stats['hausd_dist_seg'] = {}

      self.stats['levenshtein_rat'] = {}
      self.stats['name_cmps'] = {}
      self.stats['name_cmps']['all'] = 0
      self.stats['name_cmps']['equal'] = 0
      self.stats['name_cmps']['streets'] = 0
      self.stats['name_cmps']['starts'] = 0
      self.stats['name_cmps']['within'] = 0
      #
      self.stats['name_cmps']['good_match'] = 0
      self.stats['name_cmps']['leven_distrib'] = {}

      self.stats['orig_pair_len_norm'] = {}
      self.stats['gf_old_frag_len_norm'] = {}
      self.stats['gf_new_frag_len_norm'] = {}
      self.stats['frag_pair_len_norm'] = {}
      self.stats['frag_hausdo_rat'] = {}
      self.stats['raw_hausdo_rat'] = {}

   #
   def stats_show_matching(self):

      log.info(60 * '=')

      log.info('Stats for Hausdorff Import Matcher')

      #log.info(50 * '-')
      log.info('')

      self.hausdorff_bucket_show(self.stats['hausd_dist_raw'],
               # "Hausdorff Distance distribution: "
               'Raw line geometries and PostGIS algorithm')

      #log.info(50 * '-')
      log.info('')

      self.hausdorff_bucket_show(self.stats['hausd_dist_seg'],
               # "Hausdorff Distance distribution: "
               'Fragmented line geometry and our algorithm')

      #log.info(50 * '-')
      log.info('')

      log.info('Match Pair Levenshtein ratio distribution (0.0 to 1.0)')

      misc.pprint_dict_count_normalized(self.stats['levenshtein_rat'],
                                        log.info)

      #log.info(50 * '-')
      log.info('')

      log.info('%45s: %s'
               % ('Number street names compared:',
                  self.stats['name_cmps']['all'],))

      log.info('%45s: %s'
               % ('Number street names equal:',
                  self.stats['name_cmps']['equal'],))
      log.info('%45s: %s'
               % ('Number route name matches:',
                  self.stats['name_cmps']['streets'],))
      log.info('%45s: %s'
               % ('Number street names startswith:',
                  self.stats['name_cmps']['starts'],))
      log.info('%45s: %s'
               % ('Number street names contains:',
                  self.stats['name_cmps']['within'],))

      log.info('%45s: %s'
               % ('Number street names "good" (equal/starts/contains:)',
                  self.stats['name_cmps']['good_match'],))
      log.info('%45s: %s'
               % ('Number street names "good" leven distrib:',
                  len(self.stats['name_cmps']['leven_distrib']),))
      log.info('Leven distrib when our name match "good" (0.0 to 1.0)')
      misc.pprint_dict_count_normalized(
         self.stats['name_cmps']['leven_distrib'],
         log.info)

      #log.info(50 * '-')
      log.info('')

      log.info('Match Pair length ratio distribution (0.0 to 1.0)')

      misc.pprint_dict_count_normalized(self.stats['orig_pair_len_norm'],
                                        log.info)

      #log.info(50 * '-')
      log.info('')

      log.info('Old Fragment Pair length ratio distribution (0.0 to 1.0)')

      misc.pprint_dict_count_normalized(self.stats['gf_old_frag_len_norm'],
                                        log.info)

      #log.info(50 * '-')
      log.info('')

      log.info('New Fragment Pair length ratio distribution (0.0 to 1.0)')

      misc.pprint_dict_count_normalized(self.stats['gf_new_frag_len_norm'],
                                        log.info)

      #log.info(50 * '-')
      log.info('')

      log.info('Hausdorff Fragment Pair length distribution (0.0 to 1.0)')

      misc.pprint_dict_count_normalized(self.stats['frag_pair_len_norm'],
                                        log.info)

      #log.info(50 * '-')
      log.info('')

      log.info('Fragment Pair Hausdorff distribution (0.0 to 1.0)')

      misc.pprint_dict_count_normalized(self.stats['frag_hausdo_rat'],
                                        log.info)

      #log.info(50 * '-')
      log.info('')

      log.info('Raw Hausdorff ratio distribution (0.0 to 1.0)')

      misc.pprint_dict_count_normalized(self.stats['raw_hausdo_rat'],
                                        log.info)


      #log.info(50 * '-')
      log.info('')

   # **** Export Stats

   #
   def stats_init_export(self):

      self.stats['items_total_exported'] = 0

      self.stats['export_tag_counts'] = {}

   #
   def stats_show_export(self):

      log.info(60 * '=')

      log.info('Stats for Geofeature IO Export action')

      log.info(50 * '-')

      log.info('%45s: %s'
               % ('Total number items exported',
                  self.stats['items_total_exported'],))

      log.info(50 * '-')

      log.info('%45s' % ('Number tags by name--',))
      for tagname, tagcount in self.stats['export_tag_counts'].iteritems():
         log.info('%45s: %s' % (tagname, tagcount,))

      log.info(50 * '-')

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

      g.assurt(hausdorff_dist >= 0)
      hausdorff_dist_str = self.hausdorff_bucket_def[-1][1]
      for bdef in self.hausdorff_bucket_def:
         if hausdorff_dist <= bdef[0]:
            hausdorff_dist_str = bdef[1]
            break
      misc.dict_count_inc(hausdorff_bucket, hausdorff_dist_str)

   #
   def hausdorff_bucket_show(self, hausdorff_bucket, msg):

      printed_header = False

      for bdef in self.hausdorff_bucket_def:
         try:
            dist_cnt = hausdorff_bucket[bdef[1]]
            if dist_cnt > 0:
               if not printed_header:
                  log.debug('')
                  log_msg = ('Hausdorff Distance distribution: %s' % (msg,))
                  log.debug('=' * len(log_msg))
                  log.debug(log_msg)
                  log.debug('=' * len(log_msg))
                  printed_header = True
               log.debug('*** dist_val: %s / dist_cnt: %d'
                         % (bdef[1], dist_cnt,))
         except KeyError:
            pass

   # ***

# ***

if (__name__ == '__main__'):
   hi = Hausdorff_Import()
   hi.go()


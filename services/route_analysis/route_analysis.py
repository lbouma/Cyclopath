# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# NOTE: If you make changes to this file, be sure to restart Mr. Do!

import conf
import g

# BUG nnnn: analysis mult. threads.
# assign review to [mm]

'''

# Here's how to test via ccp.py...

# Start a route finder, so we don't have to start it for every test.

INSTANCE=minnesota___cycloplan_test
PYSERVER_HOME=/ccp/dev/cycloplan_test/pyserver
# All of Minnesota (thirty minutes to load):
sudo -u $httpd_user \
  INSTANCE=$INSTANCE \
  PYTHONPATH=$PYTHONPATH \
  PYSERVER_HOME=$PYSERVER_HOME \
  SHP_CACHE_DIR='/ccp/var/shapefiles/p3_routed' \
  $PYSERVER_HOME/../services/routedctl \
  --routed_pers=p3 \
  --purpose=analysis \
  --source_zip='/ccp/var/htdocs/cycloplan_live/exports/Minnesota.zip' \
  --shp_cache_dir='/ccp/var/shapefiles/p3_routed' \
  $svccmd
# Or just Hennepin County (one minute to load):
sudo -u $httpd_user \
  INSTANCE=$INSTANCE \
  PYTHONPATH=$PYTHONPATH \
  PYSERVER_HOME=$PYSERVER_HOME \
  SHP_CACHE_DIR='/ccp/var/shapefiles/p3_routed' \
  $PYSERVER_HOME/../services/routedctl \
  --routed_pers=p3 \
  --purpose=analysis \
  --source_zip='/ccp/var/shapefiles/test/2014.06.12-Minnesota-Hennepin.zip' \
  --shp_cache_dir='/ccp/var/shapefiles/p3_routed-test-henn' \
  --regions=Hennepin \
  $svccmd

# rt_source:
#   USER = 1
#   SYNTHETIC = 2
#   JOB = 3
#   RADIAL = 4

re
cd $cp/pyserver
./ccp.py -U landonb --no-password \
   -c -t route_analysis_job -m "Ignored." -e name "" \
   -e job_act "create" -e for_group_id 0 -e job_local_run 1 \
   -e for_revision 0 \
   -e n 5 \
   -e regions_ep_name_1 "Minneapolis" \
   -e regions_ep_name_2 "Saint Louis Park" \
   -e rt_source 1

BUG_JUL_2014/FIXME: Instructions to test regions_ep_tag_1 and regions_ep_tag_2
       like greenline
FIXME: Test all the rider profiles

   -e rt_source 1 \
   -e rt_source 2 \
   -e rt_source 3 \
   -e rt_source 4 \

# To specify the branch:
   -b "Metc Bikeways 2012"

# To test a mis-named region (i.e., no geometry):
   -e regions_ep_name_2 "St. Louis Park"

'''

try:
   from osgeo import ogr
   from osgeo import osr
except ImportError:
   import ogr
   import osr

from decimal import Decimal
import getpass
import itertools
from lxml import etree
import math
import os
import random
import re
import socket
import stat
import string
import sys
import threading
import time
import traceback
import uuid
import yaml

from grax.access_level import Access_Level
from grax.access_scope import Access_Scope
from grax.grac_manager import Grac_Manager
from grax.item_manager import Item_Manager
from grax.user import User
from gwis.query_overlord import Query_Overlord
from item import item_base
from item import link_value
from item.attc import attribute
from item.attc import tag
from item.feat import branch
from item.feat import byway
from item.feat import route
from item.feat import region
from item.grac import group
from item.jobsq import route_analysis_job
from item.link import link_tag
from item.util import ratings
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from planner.travel_mode import Travel_Mode
from util_ import db_glue
from util_ import geometry
from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.path_helper import Path_Helper
from util_.routed_ports import Routed_Ports
from util_.task_queue import Task_Queue
from util_.task_queue import Task_Queue_At_Capacity_Error
from util_.task_queue import Task_Queue_Complete_Error

from routed import Route_Daemon
from utils.work_item_job import Work_Item_Job

__all__ = ('Route_Analysis',)

log = g.log.getLogger('route_analysis')

# BUG nnnn: Run multiple threads. Since the route finder Server is
# multi-threaded, we can send route requests in parallel to use the
# server better: Create a number of worker threads that each call
# route_evaluate. Use a lock to control fetching from self.routes_queued,
# and remove routes as they are completed, and lock access to
# self.routes_analsed, too.

# DEVS: Set to True if you're already running routed. Otherwise, this script
# starts a new instance of the route finder (which takes time and memory).
SKIP_ROUTED = False
#SKIP_ROUTED = True
# Set the purpose to match the running route finder.
# NOTE: You normally want to use an 'analysis' finder, which doesn't save
# routes to the database; the 'general' finder saves your analysis routes.
SKIP_PURPOSE = 'analysis'
#SKIP_PURPOSE = 'general'

# ***

class Rider_Profile:

   __slots__ = (

      # Which planner to use.
      'travel_mode',

      # Planner p1 options.
      'p1_priority',

      # MAYBE/BUG nnnn: Implement multimodal route analysis.
      #                 For now, these options are here but
      #                 they don't do anything other than
      #                 offer symmetry with other places you'll
      #                 find the list of user route finder prefs.
      # Planner p2 options.
      'p2_depart_at',
      'p2_transit_pref',

      # Planner p3 options.
      'p3_weight_type',
      'p3_rating_pump',
      'p3_burden_pump',
      'p3_spalgorithm',

      # Personalized planning options.
      'rating_min',
      'tag_prefs',
      'tags_use_defaults'
      )

   # *** Constructor

   def __init__(self, name = None):
      self.load_defaults()
      if name is not None:
         self.load_from_file(name)

   # ***

   #
   def load_defaults(self):

      if Route_Analysis.routed_use_planner == 'p1':
         self.travel_mode = Travel_Mode.classic
      elif Route_Analysis.routed_use_planner == 'p3':
         self.travel_mode = Travel_Mode.wayward
      else:
         g.assurt(False)

      # Same defaults as in route_get.py.

      self.p1_priority = 0.5

      self.p2_depart_at = ''
      self.p2_transit_pref = 0

      # MAGIC_NUMBERS: See defaults in Conf.as.
      self.p3_weight_type = 'rat'
      self.p3_rating_pump = 4
      self.p3_burden_pump = 20
      self.p3_spalgorithm = 'as*'

      # Whatever. The minimum rating is hardcoded everywhere at 0.5.
      self.rating_min = 0.5
      self.tag_prefs = dict()
      self.tags_use_defaults = False

   # Load from rider_profiles.yml
   def load_from_file(self, name):

      try:
         g.assurt(os.getenv('PYSERVER_HOME'))
         # MAGIC_NUMBER: We run from pyserver, and this is the yml path.
         # NOTE: rider_profiles.yml is a static file, so if you change
         #       and values below, just edit the yaml to update the
         #       profiles.
         yfile = ('%s/../services/route_analysis/rider_profiles.yml'
                  % (os.getenv('PYSERVER_HOME'),))
         profiles = yaml.load(file(yfile, 'r'))
         if name in profiles:
            log.info('Loading profile: %s' % (name,))
            profile = profiles[name]
            # [lb] thought about applying the DRY policy here, or just
            # copy-pasting a bunch of try-except blocks... both seem about
            # the same amount of work, but this way keep the attrs ordered
            # the same as everywhere else (to keep the variables easy to
            # update, e.g., when adding new ones).
            no_warn = True
            try:
               self.travel_mode = int(profile['travel_mode'])
            except KeyError:
               no_warn or log.debug(' .. no yaml value for: travel_mode')
            except ValueError:
               self.travel_mode = Travel_Mode.get_travel_mode_id(
                                          profile['travel_mode'])
            #
            try:
               self.p1_priority = profile['p1_priority']
            except:
               no_warn or log.debug(' .. no yaml value for: p1_priority')
            #
            try:
               self.p2_depart_at = profile['p2_depart_at']
            except:
               no_warn or log.debug(' .. no yaml value for: p2_depart_at')
            #
            try:
               self.p2_transit_pref = profile['p2_transit_pref']
            except:
               no_warn or log.debug(' .. no yaml value for: p2_transit_pref')
            #
            try:
               self.p3_weight_type = profile['p3_weight_type']
            except:
               no_warn or log.debug(' .. no yaml value for: p3_weight_type')
            #
            try:
               self.p3_rating_pump = profile['p3_rating_pump']
            except:
               no_warn or log.debug(' .. no yaml value for: p3_rating_pump')
            #
            try:
               self.p3_burden_pump = profile['p3_burden_pump']
            except:
               no_warn or log.debug(' .. no yaml value for: p3_burden_pump')
            #
            try:
               self.p3_spalgorithm = profile['p3_spalgorithm']
            except:
               no_warn or log.debug(' .. no yaml value for: p3_spalgorithm')
            #
            try:
               self.rating_min = profile['rating_min']
            except:
               no_warn or log.debug(' .. no yaml value for: rating_min')
            #
            # For self.tag_prefs:
            try:
               self.load_tags_to_dict(profile['bonus'], tag.One.BONUS_TAG)
            except:
               no_warn or log.debug(' .. no yaml value for: tag: bonus')
            #
            # For self.tag_prefs:
            try:
               self.load_tags_to_dict(profile['penalty'], tag.One.PENALTY_TAG)
            except:
               no_warn or log.debug(' .. no yaml value for: tag: penalty')
            #
            # For self.tag_prefs:
            try:
               self.load_tags_to_dict(profile['avoid'], tag.One.AVOID_TAG)
            except:
               no_warn or log.debug(' .. no yaml value for: tag: avoid')
            #
            try:
               self.tags_use_defaults = profile['tags_use_defaults']
            except:
               if not no_warn:
                  log.debug(' .. no yaml value for: tags_use_defaults')
            #
         else:
            log.warning('Profile not found: %s / using defaults.' % (name,))
            self.load_defaults()
      except Exception, e:
         log.warning('Error parsing YAML, using default settings: %s'
                     % (str(e),))
         self.load_defaults()

   #
   def load_tags_to_dict(self, tag_str, tag_pref_value):
      if tag_str:
         for tag in tag_str.split(','):
            self.tag_prefs[string.strip(tag)] = tag_pref_value

   #
   def tag_to_stack_id(self, ranal, tag_):

      g.assurt(tag_)

      g.assurt(ranal.qb_cur.item_mgr is not None)
      g.assurt(ranal.qb_cur.item_mgr.cache_tags is not None)
      g.assurt(ranal.inverse_tags is not None)

      try:
         tag_stack_id = ranal.inverse_tags[tag_]
      except KeyError:
         g.assurt(False)

      g.assurt(tag_stack_id > 0)

      return tag_stack_id

   #
   def write_to_sock(self, ranal, sockf):

      # SYNC_ME: pyserver.gwis.command_.route_get.routed_fetch sockf()s
      #          and services.route_analysis.route_analysis.route_evaluate
      #          and services.route_analysis.route_analysis.write_to_sock.

      if self.travel_mode:
         sockf.write('travel_mode %s\n' % (self.travel_mode,))
      if self.p2_depart_at:
         sockf.write('p2_depart %s\n' % (self.p2_depart_at,))
      if self.p2_transit_pref:
         sockf.write('p2_txpref %s\n' % (str(self.p2_transit_pref),))
      if self.p3_weight_type:
         sockf.write('p3_wgt %s\n' % (self.p3_weight_type,))
      if self.p3_rating_pump:
         sockf.write('p3_rgi %d\n' % (self.p3_rating_pump,))
      if self.p3_burden_pump:
         sockf.write('p3_bdn %d\n' % (self.p3_burden_pump,))
      if self.p3_spalgorithm:
         sockf.write('p3_alg %s\n' % (self.p3_spalgorithm,))
      if self.rating_min:
         sockf.write('rating_min %s\n' % (self.rating_min,))
      for tag_ in self.tag_prefs:
         # Extract stack_ids from tag labels.
         tag_stack_id = self.tag_to_stack_id(ranal, tag_)
         if tag_stack_id is not None:
            sockf.write('tagpref %s %s\n'
                        % (tag_stack_id, self.tag_prefs[tag_],))
      sockf.write('use_defaults %g\n' % (self.tags_use_defaults,))

# ***

class Route_Analysis(Work_Item_Job):

   # Reasons why a route request might fail.
   fail_reasons = [
      ('no_route', 'No route could be found (different street networks).',),
      ('unknown', 'Internal error: Unknown response from route finder.',),
      ('no_child', 'Internal error: XML has no child element.',),
      ('Eunknown', 'Internal error: Unknown Exception.',),
      ]

   routed_use_planner = 'p3'
   profile_shortest_distance_p1 = '100pc_distance'
   profile_shortest_distance_p3 = 'fastest'

   __slots__ = (
      'qb_cur',
      'qb_src',
      'error',
      'inverse_tags',
      # Details about the route finder.
      'pidfile',
      'readyfile',
      'routed_port',
      'purpose',
      't0_routed',
      # Details about the routes being analysed.
      'n_analsed_goal',    # no. of routes we want to analyse
      'regions_ep_1_geom', # collect geometry of regions in wtem.regions_ep_1
      'regions_ep_2_geom', # collect geometry of regions in wtem.regions_ep_2
      'sources',           # node_endpoints found in regions_ep_1_geom
      'destins',           # node_endpoints found in regions_ep_2_geom
      'rider_profile',     # I.e., bikeability slider and tag_prefs, etc.
      'shortest_dist_profile',
      'routes_queued',     # list of (src,dst) node_endpoints to find-route on
      'routes_analsed',    # list of analysed (src,dst) routes
      'routes_lock',       # gated access to routes_queued and routes_analysed
      'task_queue',        # thread(s) to process routes_queued
      'shpf',
      'layers',
      'routes_thru_byways',
      'routes_failed_reason',
      )

   # *** Constructor

   def __init__(self, wtem, mr_do):
      Work_Item_Job.__init__(self, wtem, mr_do)
      self.qb_cur = None
      self.qb_src = None
      self.error = None
      self.inverse_tags = None
      self.pidfile = None
      self.readyfile = None
      self.routed_port = None
      self.purpose = None
      self.t0_routed = None
      self.n_analsed_goal = 0
      self.regions_ep_1_geom = None
      self.regions_ep_2_geom = None
      self.sources = None
      self.destins = None
      self.rider_profile = None
      self.shortest_dist_profile = None
      self.routes_queued = list()
      self.routes_analsed = list()
      self.routes_lock = threading.RLock()
      self.task_queue = None
      self.shpf = None
      self.layers = dict()
      # A lookup of byway_stack_ids. The value is no. of routes that used it.
      self.routes_thru_byways = dict()
      self.routes_failed_reason = dict()
      for defn in Route_Analysis.fail_reasons:
         self.routes_failed_reason[defn[0]] = 0

   # -- ENTRY POINT -----------------------------------------------------------

   #
   @staticmethod
   def process_request(wtem, mr_do):
      ra = Route_Analysis(wtem, mr_do)
      ra.process_request_()

   # -- COMMON ----------------------------------------------------------------

   #
   def job_cleanup(self):
      self.do_teardown()
      if self.qb_cur is not None:
         self.qb_cur.db.close()
         self.qb_cur = None
      if self.qb_src is not None:
         self.qb_src.db.close()
         self.qb_src = None
      Work_Item_Job.job_cleanup(self)

   #
   def routed_cmd(self, server_cmd, revision_arg=''):
      the_cmd = (
         # MAYBE: Other p3 planner options: --source_zip, --shp_cache_dir
         '%s --branch=%d --routed_pers=%s --purpose=%s %s %s'
         % (Route_Daemon.routedctl_path(),
            self.wtem.branch_id,
            Route_Analysis.routed_use_planner, # E.g., 'p3'
            self.purpose,
            revision_arg,
            server_cmd,))
      return the_cmd

   #
   def setup_qbs(self):

      username = self.wtem.created_by

      # Current revision: qb_cur.

      db = db_glue.new()

      # Though the job may be to analyze an old revision, the qb is set to the
      # Current revision. We need to look up regions for geometry, which we do
      # at the latest revision. (It's the route finder we talk to that's
      # running at the old revision.)
      rev = revision.Current()
      (branch_id, branch_hier) = branch.Many.branch_id_resolve(db,
                     self.wtem.branch_id, branch_hier_rev=rev)
      if not branch_hier:
         raise Exception(
            'Branch with stack_id %d not found in database at %s.'
            % (self.wtem.branch_id, rev.short_name(),))

      g.assurt(branch_hier)

      self.qb_cur = Item_Query_Builder(db, username, branch_hier, rev)

      Query_Overlord.finalize_query(self.qb_cur)

      # We need the tag lookup for resolving tag pref stack_ids, so build it
      # now.
      self.qb_cur.item_mgr = Item_Manager()
      self.qb_cur.item_mgr.load_cache_attachments(self.qb_cur)
      # Store as tag name => tag stack id.
      self.inverse_tags = dict(
         [[v.name,k] for k,v in self.qb_cur.item_mgr.cache_tags.items()])

      # Historic revision: qb_src.

      db = db_glue.new()

      if self.wtem.revision_id is None:
         rev = revision.Current()
      else:
         rev = revision.Historic(self.wtem.revision_id, allow_deleted=False)

      (branch_id, branch_hier) = branch.Many.branch_id_resolve(db,
                           self.wtem.branch_id, branch_hier_rev=rev)
      if not branch_hier:
         g.assurt(False) # We got this above, so this shouldn't/can't happen.
         raise Exception(
            'Branch with stack_id %d not found in database at %s.'
            % (self.wtem.branch_id, rev.short_name(),))

      self.qb_src = Item_Query_Builder(db, username, branch_hier, rev)

      self.qb_src.item_mgr = self.qb_cur.item_mgr

      Query_Overlord.finalize_query(self.qb_src)

   #
   def shapefiles_sync(self):
      log.info('Syncing shapefile...')
      for layer in self.layers.itervalues():
         layer.SyncToDisk()

   # -- ALL STAGES ------------------------------------------------------------

   #
   def make_stage_lookup(self):
      self.stage_lookup = [
         # Start the route finder first. We can do other setup while the route
         # finder is booting, since some of our setup also involves timely SQL.
         self.do_routed_setup,
         self.do_process_input,
         #self.do_waste_time,      # DEVS: Uncomment for testing.
         #self.do_waste_more_time, # DEVS: Uncomment for testing.
         self.do_reserve_directory,
         self.do_setup_shapefile,
         self.do_routes_selection,
         self.do_prefs_selection,
         self.do_routed_wait,
         self.do_run_requests,
         self.do_build_output,
         self.do_create_archive,
         self.do_notify_users,
         self.job_mark_complete,
         ]

   # BUG nnnn: This class needs to periodically check the work item status
   #           as well as self.wtem.mr_do.keep_running, and to preempt.
   #           This will support (a) more refined progress percent updates
   #           and (b) ability to cancel job during a stage instead of between
   #           stages.

   # -- DEBUG STAGES ----------------------------------------------------------

   # DEVS: For testing.
   def do_waste_time(self):
      self.stage_initialize('Wasting time')
      seconds = 10
      time.sleep(seconds)

   # DEVS: For testing.
   def do_waste_more_time(self):
      self.stage_initialize('Wasting more time')
      seconds = 10
      time.sleep(seconds)

   # -- STAGE 1 ---------------------------------------------------------------

   #
   def do_routed_setup(self):

      self.stage_initialize('Setting up route-finder')

      routed_pers = Route_Analysis.routed_use_planner
      purpose = 'analysis'

      self.t0_routed = time.time()

      if SKIP_ROUTED:
         purpose = SKIP_PURPOSE
         self.pidfile = conf.get_pidfile_name(self.wtem.branch_id,
                                              routed_pers,
                                              purpose)
         self.readyfile = '%s-ready' % (self.pidfile,)
         self.purpose = purpose
         return

      current_user = getpass.getuser()
      log.debug('Running as: %s' % (current_user,))
      log.debug('Running in: %s' % (os.getcwd(),))
      # We usually run as www-data/apache unless dev. is testing via ccp.py.
      # SKIP:  g.assurt((current_user == 'www-data')   # Ubuntu
      #                 or (current_user == 'apache')) # Fedora

      log.info('Starting routed ...')

      time_0 = time.time()

      # SYNC_ME: Search: Routed PID filename.
      self.purpose = ('%s-%s' % (purpose, uuid.uuid1(),))
      self.pidfile = conf.get_pidfile_name(self.wtem.branch_id,
                                           routed_pers,
                                           self.purpose)
      self.readyfile = '%s-ready' % (self.pidfile,)

      g.assurt(not os.path.exists(self.readyfile))

      # Make the revision argument for the routed daemon.
      if not self.wtem.revision_id:
         revision_arg = '--revision Current'
      else:
         revision_arg = '--revision Historic %d' % (self.wtem.revision_id,)

      # Fire up routed.

      log.info('Starting routed...')

      # Call the routed daemon, which returns once the finder is daemonized.
      the_cmd = self.routed_cmd('start')
      log.debug('do_routed_setup: cmd: %s' % (the_cmd,))
      misc.run_cmd(the_cmd, outp=log.debug)

   # -- STAGE 2 ---------------------------------------------------------------

   #
   def do_process_input(self):

      self.stage_initialize('Processing input')

      self.setup_qbs()

      log.info('** INPUT *******************')
      log.info(' n = %d' % (self.wtem.n,))
      log.info(' revision_id = %s' % (self.wtem.revision_id,))
      log.info(' rt_source = %d' % (self.wtem.rt_source,))
      log.info(' cmp_job_name = %s' % (self.wtem.cmp_job_name,))
      log.info(' regions_ep_name_1 = %s' % (self.wtem.regions_ep_name_1,))
      log.info(' regions_ep_tag_1 = %s' % (self.wtem.regions_ep_tag_1,))
      log.info(' regions_ep_name_2 = %s' % (self.wtem.regions_ep_name_2,))
      log.info(' regions_ep_tag_2 = %s' % (self.wtem.regions_ep_tag_2,))
      log.info(' rider_profile = %s' % (self.wtem.rider_profile,))
      log.info('****************************')

      # Get geometries for the source and destination regions.
      time_0 = time.time()
      log.info('Fetching region geometries...')
      self.regions_ep_1_geom = self.region_names_or_tag_to_geom(
         self.wtem.regions_ep_name_1, self.wtem.regions_ep_tag_1)
      self.regions_ep_2_geom = self.region_names_or_tag_to_geom(
         self.wtem.regions_ep_name_2, self.wtem.regions_ep_tag_2)
      log.debug('Fetched region geom in %s'
                % (misc.time_format_elapsed(time_0),))

   #
   def region_names_or_tag_to_geom(self, region_names, region_tag):
      geom = None
      if region_names:
         geom = self.region_names_to_geom(region_names)
      elif region_tag:
         geom = self.region_tag_to_geom(region_tag)
      # else: no geometry restriction; find route endpoints from anywhere.
      return geom

   #
   def region_tag_to_geom(self, region_tag):
      geom = None

      # Obtain link-values.
      lts = link_tag.Many(region_tag, Item_Type.REGION)
      lts.search_for_items(self.qb_cur)

      # Construct list of region stack IDs.
      region_stack_ids = list()
      for lt in lts:
         region_stack_ids.append(lt.rhs_stack_id)
         log.debug('Found region with stack id: %s' % (lt.rhs_stack_id,))
      log.debug('Found total %d regions.' % (len(region_stack_ids),))

      # Fetch regions with those stack IDs.
      regions = region.Many()
      regions.sql_clauses_cols_setup(self.qb_cur)

      self.qb_cur.filters.only_stack_ids = ','.join(map(str, region_stack_ids))
      geom = self.get_region_geoms(len(region_stack_ids), context=region_tag)
      self.qb_cur.filters.only_stack_ids = None
      return geom

   #
   def region_names_to_geom(self, region_names):

      geom = None

      # BUG nnnn: We should set qb.filters.filter_by_regions and call
      # region.Many().search_for_geom (or make a new qb.filters that means
      # match multiple names). For now, using [mm]'s original code, which finds
      # all regions and then matches the name. Ideally, the name match should
      # be in the inner-most select. See also regions_coalesce_geometry. And
      # note that geofeature.search_for_geom uses ST_Union, not ST_Collect...
      # we ([lb]) should explain the difference.

      if region_names.strip():
         region_names_array = map(self.qb_cur.db.quoted,
                                  map(string.strip,
                                      region_names.strip(",").split(",")))
         if region_names_array:
            where_clause = (
               """
               WHERE
                  name IN (%s)
               """ % (','.join(region_names_array),))
            geom = self.get_region_geoms(len(region_names_array), where_clause,
                                         context=region_names)
         else:
            log.warning('region_names_to_geom: empty region_names_array: %s'
                        % (region_names,))

      return geom

   #
   def get_region_geoms(self, n_expected, where_clause='', context=None):
      geom = None

      # Use region.Many() so we get regions this user can access, and not
      # all regions.
      regions = region.Many()
      regions.sql_clauses_cols_setup(self.qb_cur)

      geom_sql = (
         """
         SELECT
            ST_AsEWKT(ST_Collect(geometry)) AS geom
            , COUNT(geometry) AS n_geom
         FROM
            (%s) AS foo
         %s
         """ % (regions.search_get_sql(self.qb_cur),
                where_clause,))
      rows = self.qb_cur.db.sql(geom_sql)
      self.qb_cur.sql_clauses = None
      g.assurt(len(rows) == 1)
      geom = rows[0]['geom']

      # Check that the requested regions were found.
      n_geom = rows[0]['n_geom']
      if geom is None:
         log.warning('Region%s returned no geometry: n_geom: %d: %s'
                     % ('s' if n_expected > 1 else '',
                        n_geom,
                        where_clause,))
         err_s = ('%s %s: "%s". Please try again with a different query.'
                  % ('Oops!',
           'We did not find any geometry for the specified region name or tag',
                     context,))
         raise Exception(err_s)
      elif n_geom != n_expected:
         log.warning('region_names_to_geom: found %d geoms of %d expected (%s)'
                     % (n_geom, n_expected, where_clause,))
         # MAYBE: Raise an exception?

      return geom

   # -- STAGE 3 ---------------------------------------------------------------

   #
   def do_reserve_directory(self):

      self.stage_initialize('Reserving directory')

      # Get a unique path in the download/upload directory.
      fpath, rand_path = Path_Helper.path_reserve(
                           basedir=conf.shapefile_directory,
                           extension='', is_dir=False)

      # Remember the path.
      self.wtem.local_file_guid = rand_path
      self.wtem.job_data_update()

      log.debug('do_reserve_directory: rand_path: %s / wtem: %s'
                % (rand_path, self.wtem,))

      opath = self.make_working_directories()

   # -- STAGE 4 ---------------------------------------------------------------

   #
   def do_setup_shapefile(self):

      self.stage_initialize('Setting up shapefile')

      driver = ogr.GetDriverByName('ESRI Shapefile')

      # Create the file.
      filename = 'route.shp'
      directory_name = '%s.out' % (self.wtem.local_file_guid,)
      filepath = os.path.join(conf.shapefile_directory,
                              directory_name,
                              filename)
      log.info('Creating shapefile %s...' % (filepath,))
      self.shpf = driver.CreateDataSource(filepath)

      # Create the spatial reference.
      spat_ref = osr.SpatialReference()
      spat_ref.ImportFromEPSG(conf.default_srid)

      # Create the layers and fields.
      log.info('Creating the route layer...')
      self.create_layer('route', ogr.wkbMultiLineString, spat_ref)
      self.create_field('route', 'rdi_sl', ogr.OFTReal)
      self.create_field('route', 'rdi_sp', ogr.OFTReal)
      self.create_field('route', 'length', ogr.OFTReal)
      self.create_field('route', 'avg_rtng', ogr.OFTReal)
      log.info('Creating the byways layer...')
      self.create_layer('byway', ogr.wkbLineString, spat_ref)
      self.create_field('byway', 'id', ogr.OFTInteger)
      self.create_field('byway', 'length', ogr.OFTReal)
      self.create_field('byway', 'n_routes', ogr.OFTInteger)
      self.create_field('byway', 'n_rtng', ogr.OFTInteger)
      self.create_field('byway', 'rtng_usr', ogr.OFTReal)
      self.create_field('byway', 'rtng_sys', ogr.OFTReal)
      self.create_field('byway', 'rtng_tot', ogr.OFTReal)
      #log.info('Creating the regions layer...')
      #self.create_layer('region', ogr.wkbPolygon, spat_ref)
      #self.create_field('region', 'in_filter', ogr.OFTInteger)

      # Sync the shapefile.
      self.shapefiles_sync()

      # Set correct permissions.
      directory = os.path.join(conf.shapefile_directory, directory_name)
      #os.chmod(directory, 2775)
      #os.chmod(directory, 0775)
      os.chmod(directory, 02775)
      for root, dirs, files in os.walk(directory):
         for f in files:
            #os.chmod(os.path.join(directory, f), 2775)
            #os.chmod(os.path.join(directory, f), 0775)
            os.chmod(os.path.join(directory, f), 02775)


   #
   def create_field(self, layer, fname, ftype):
      ogr_err = self.layers[layer].CreateField(ogr.FieldDefn(fname, ftype))
      g.assurt(not ogr_err)
      # NOTE: This code doesn't use ogr.OFTString. If it did, we would want to
      #       call SetWidth() to explicitly set the number of characters.
      g.assurt(ftype != ogr.OFTString)

   #
   def create_layer(self, layer, ltype, spat_ref):
      self.layers[layer] = self.shpf.CreateLayer(layer, spat_ref, ltype)

   # -- STAGE 5 ---------------------------------------------------------------

   #
   def do_routes_selection(self):

      self.stage_initialize('Selecting routes')

      time_0 = time.time()

      # This is the main thread, so no need to get the lock when these fcns.
      # modify self.routes_queued.
      g.assurt(not self.routes_queued)

      if self.wtem.rt_source == route_analysis_job.Route_Source.USER:
         self.do_routes_selection_user()
      elif self.wtem.rt_source == route_analysis_job.Route_Source.SYNTHETIC:
         self.do_routes_selection_synthetic()
      elif self.wtem.rt_source == route_analysis_job.Route_Source.JOB:
         self.do_routes_selection_job()
      elif self.wtem.rt_source == route_analysis_job.Route_Source.RADIAL:
         self.do_routes_selection_radial()
      else:
         raise Exception('Invalid route source: %d' % (self.wtem.rt_source,))

      # For user-requested routes, there will be as many or fewer routes_queued
      # than self.wtem.n. For synthetic routes, there will always be the same
      # number queued as the user desires to analyze. For past-job routes, the
      # number queued is the number of requests we ran last time.
      self.n_analsed_goal = len(self.routes_queued)

      if not self.n_analsed_goal:
         raise Exception(
            'route_analysis: found zero user routes to analyse btw. %s and %s.'
            % (self.wtem.regions_ep_name_1 or self.wtem.regions_ep_tag_1,
               self.wtem.regions_ep_name_2 or self.wtem.regions_ep_tag_2,))

      log.debug(
         'do_routes_selection: fetched %d routes to analyse in %s'
         % (self.n_analsed_goal,
            misc.time_format_elapsed(time_0),))

   # *** ROUTE SELECTION: USER-REQUESTED ROUTES

   #
   def do_routes_selection_user(self):

      log.info('Selecting the snapshot from user-requested routes...')

      # How we select node endpoints for user-requested routes from the route
      # table:
      #
      # If regions_ep_1 is provided and regions_ep_2 is not provided:
      #   Select routes with one endpoint in regions_ep_1 and the other
      #   endpoint anywhere; route from regions_ep_1 to regions_ep_2.
      #
      # If the opposite is true: if regions_ep_2 is set and regions_ep_1 isn't:
      #   Select routes with one endpoint in regions_ep_2 and the other
      #   endpoint anywhere; route from regions_ep_1 to regions_ep_2.
      #   (The reason we bother to route in reverse is because of one-ways
      #    and other directionally-specific attributes, otherwise the user is
      #    restricted in what he/she can analyse with just one region (i.e.,
      #    routes will always be analysed from the node endpoint in region to
      #    the other node endpoint).)
      #
      # If both regions_ep_1 and regions_ep_2 are provided:
      #   Select routes with one endpoint in regions_ep_1 and the other
      #   endpoint in regions_ep_2; route from the endpoint in regions_ep_1 to
      #   the endpoint in regions_ep_2.

      # *** SELECT and WHERE clauses

      beg_match_lhs_region = "NULL::BOOLEAN"
      beg_match_rhs_region = "NULL::BOOLEAN"
      fin_match_lhs_region = "NULL::BOOLEAN"
      fin_match_rhs_region = "NULL::BOOLEAN"

      # MAYBE: [lb] is curious: Is ST_Buffer efficient? Does Postgis
      #        recommend a more efficient alternative, like it suggests
      #        using ST_DWithin in favor of "geometry && ST_Expand()"?

      # See if either node_endpoint is contained within regions_ep_1.
      if self.wtem.regions_ep_name_1 or self.wtem.regions_ep_tag_1:
         g.assurt(self.regions_ep_1_geom)
         beg_match_lhs_region = (
            """
            ST_Intersects(
               ptxy_beg.endpoint_xy, ST_Buffer(ST_GeomFromEWKT('%s'), 0))
            """ % (self.regions_ep_1_geom,))
         fin_match_lhs_region = (
            """
            ST_Intersects(
               ptxy_fin.endpoint_xy, ST_Buffer(ST_GeomFromEWKT('%s'), 0))
            """ % (self.regions_ep_1_geom,))
      else:
         g.assurt(not self.regions_ep_1_geom)

      # See if either node_endpoint is contained within regions_ep_2.
      if self.wtem.regions_ep_name_2 or self.wtem.regions_ep_tag_2:
         g.assurt(self.regions_ep_2_geom)
         beg_match_rhs_region = (
            """
            ST_Intersects(
               ptxy_beg.endpoint_xy, ST_Buffer(ST_GeomFromEWKT('%s'), 0))
            """ % (self.regions_ep_2_geom,))
         fin_match_rhs_region = (
            """
            ST_Intersects(
               ptxy_fin.endpoint_xy, ST_Buffer(ST_GeomFromEWKT('%s'), 0))
            """ % (self.regions_ep_2_geom,))
      else:
         g.assurt(not self.regions_ep_2_geom)

      # NOTE: We get Current routes but check Historic node_endpoints. This is
      #       so we can analyse using the most uptodate route data but so we
      #       can still make sure the node_endpoint actually exists in the
      #       historic revision that we want to analyse.
      # NOTE: reference_n = 0 means: If node_endpoint isn't used, don't
      #       consider it. This happens when the node_endpoint has been
      #       orphaned (so it was used (reference_n > 0) at a revision
      #       earlier than self.qb_src).

      sql = (
         """

         SELECT
            route_id
            , beg_node_id
            , fin_node_id
            , beg_match_lhs_region
            , beg_match_rhs_region
            , fin_match_lhs_region
            , fin_match_rhs_region

         FROM (

            SELECT
               rte.system_id AS route_id
               , rte.beg_nid AS beg_node_id
               , rte.fin_nid AS fin_node_id
               , %s AS beg_match_lhs_region
               , %s AS beg_match_rhs_region
               , %s AS fin_match_lhs_region
               , %s AS fin_match_rhs_region

            FROM
               route AS rte
            JOIN
               item_versioned AS rte_iv
               ON (rte_iv.system_id = rte.system_id)

            /* The beginning node endpoint. */
            JOIN
               node_endpoint AS ndpt_beg
               ON (ndpt_beg.stack_id = rte.beg_nid)
            JOIN
               item_versioned AS nbeg_iv
               ON (nbeg_iv.system_id = ndpt_beg.system_id)
            JOIN
               node_endpt_xy AS ptxy_beg
               ON (ptxy_beg.node_stack_id = ndpt_beg.stack_id)

            /* The finishing node endpoint. */
            JOIN
               node_endpoint AS ndpt_fin
               ON (ndpt_fin.stack_id = rte.fin_nid)
            JOIN
               item_versioned AS nfin_iv
               ON (nfin_iv.system_id = ndpt_fin.system_id)
            JOIN
               node_endpt_xy AS ptxy_fin
               ON (ptxy_fin.node_stack_id = ndpt_fin.stack_id)

            WHERE
               /* We only want routes where both endpoints are matched
                  to actual node_endpoints in the historic revision. */
               rte_iv.valid_until_rid = %d   -- Current: conf.rid_inf.
               AND %s                        -- Historic: for nbeg_iv.
               AND %s                        -- Historic: for nfin_iv.
               AND (nbeg_iv.branch_id = %s)
               AND (nfin_iv.branch_id = %s)
               AND (ndpt_beg.reference_n > 0)
               AND (ptxy_beg.endpoint_xy IS NOT NULL)
               AND (ndpt_fin.reference_n > 0)
               AND (ptxy_fin.endpoint_xy IS NOT NULL)

         ) AS foo

         WHERE

            FALSE

            /* See if two region globs were specified and each node matched a
               different glob. */
            OR (    (beg_match_lhs_region IS TRUE)
                AND (fin_match_rhs_region IS TRUE))
            OR (    (fin_match_lhs_region IS TRUE)
                AND (beg_match_rhs_region IS TRUE))

            /* See if one glob was specified and one node is in said glob. */
            OR (    (beg_match_rhs_region IS NULL)
                AND (fin_match_rhs_region IS TRUE))
            OR (    (beg_match_lhs_region IS TRUE)
                AND (fin_match_lhs_region IS NULL))

            /* See if no regions specified. */
            OR (    (beg_match_rhs_region IS NULL)
                AND (fin_match_rhs_region IS NULL))

         ORDER BY
            RANDOM()

         LIMIT
            %d

         """ % (
               beg_match_lhs_region,
               beg_match_rhs_region,
               fin_match_lhs_region,
               fin_match_rhs_region,
               conf.rid_inf,
               self.qb_src.revision.as_sql_where('nbeg_iv'),
               self.qb_src.revision.as_sql_where('nfin_iv'),
               # node_endpoint is flattened 'n fully hydrated; just need leaf.
               self.qb_src.branch_hier[0][0],
               self.qb_src.branch_hier[0][0],
               self.wtem.n,))

      log.info('Looking for %d routes %sbased on %sregion filter%s...'
               % (self.wtem.n,
                  '' if self.regions_ep_1_geom else 'not ',
                  '' if self.regions_ep_2_geom else 'a ',
                  's' if self.regions_ep_2_geom else '',))

      time_0 = time.time()

      self.qb_cur.db.dont_fetchall = True
      rows = self.qb_cur.db.sql(sql)

      log.debug('Found %d qualified routes in %s'
                % (self.qb_cur.db.curs.rowcount,
                   misc.time_format_elapsed(time_0),))

      log.info('Making routes lookup...')

      g.assurt(not self.routes_queued)
      generator = self.qb_cur.db.get_row_iter()
      for row in generator:
         # Skipping: row['route_id']
         beg_node_id = row['beg_node_id']
         fin_node_id = row['fin_node_id']
         beg_match_lhs_region = row['beg_match_lhs_region']
         beg_match_rhs_region = row['beg_match_rhs_region']
         fin_match_lhs_region = row['fin_match_lhs_region']
         fin_match_rhs_region = row['fin_match_rhs_region']
         # Depending on the beginning and finishing regions and the node
         # that matched, make the node endpoint pair accordingly. We adjust
         # the direction of the route request depending on which region(s)
         # was(were) matched.
         if beg_match_lhs_region or (not beg_match_rhs_region):
            # The beg_node matches the lhs region, and either the
            # rhs region was not specified, or the fin node matches
            # it.
            rt = {'beg_nid': beg_node_id, 'fin_nid': fin_node_id,}
         else:
            # Opposite of previous. The beg_match_rhs_region is True,
            # or neither region (or tag geometry) was specified.
            rt = {'beg_nid': fin_node_id, 'fin_nid': beg_node_id,}
         # Save the node endpoint pair to be routed.
         self.routes_queued.append(rt)
      generator.close()

      self.qb_cur.db.dont_fetchall = False
      self.qb_cur.db.curs_recycle()

   # *** ROUTE SELECTION: SYNTHETIC

   #
   def do_routes_selection_synthetic(self):

      # Find source and destination node_endpoints.
      log.info('Selecting sources and destins for synthetic routes...')

      # NOTE: This fcn. originally calculated the Cartesian product of the
      # fetched node endpoints to make a random collection of source and
      # destination pairs. But this uses a little more memory, e.g.,
      #     $ ./ccp.py -i
      #     >>> import itertools
      #     >>> import random
      #     >>> from util_ import mem_usage
      #     >>> mem_usage.get_usage_mb()
      #     28.375
      #     >>> a=range(1000000, 1001200)
      #     >>> b=range(1000000, 1001200)
      #     >>> c = tuple(itertools.product(a, b))
      #     >>> d = random.sample(c, len(c))
      #     >>> mem_usage.get_usage_mb()
      #     153.422
      #   also, the sources and destins are already randomly ordered, so we can
      #   just pluck 'em one by one. But the real problem is that if one of the
      #   queries returnes fewer endpoints than the number of routes the user
      #   wants to analyse: then the Cartesian product is less than that, too
      #   (e.g., the product of two ten-item lists is 100 items, but what if
      #   the user wants to analyse 1,000 routes?). To correct for this, we'll
      #   explode the endpoints lists and randomize from that.

      # This is fcn. is always called at least once. But if find-route fails on
      # any of the node endpoint pairs, we'll be called again (since we try
      # to guarantee that we'll analyse as many requests as the user
      # requested). So each list is either empty (first time this fcn. is
      # called), it's full (meaning the second or subsequent time this fcn. is
      # called), or it's partially full (meaning the first time this fcn. was
      # called it found as node endpoints as actually exist, so no need to
      # search again).
      if (self.sources is None) or (len(self.sources) == self.wtem.n):
         self.sources = self.do_routes_synthetic_find(self.regions_ep_1_geom)
      else:
         g.assurt(len(self.sources) < self.wtem.n) # We got 'em all.
      if (self.destins is None) or (len(self.destins) == self.wtem.n):
         self.destins = self.do_routes_synthetic_find(self.regions_ep_2_geom)
      else:
         g.assurt(len(self.destins) < self.wtem.n) # We got 'em all.

      # If either list is too short, make a larger, randomly-ordered list.
      sources = self.sources
      if len(sources) < self.wtem.n:
         factor = math.ceil(float(self.wtem.n) / float(len(sources)))
         sources = sources * int(factor)
         random.shuffle(sources)
         sources = sources[:self.wtem.n]
      destins = self.destins
      if len(destins) < self.wtem.n:
         factor = math.ceil(float(self.wtem.n) / float(len(destins)))
         destins = destins * int(factor)
         random.shuffle(destins)
         destins = destins[:self.wtem.n]

      # Create (src, dest) pairs to analyse.
      log.info('Making (source, destin) pairs for synthetic routes...')

      g.assurt(not self.routes_queued)
      g.assurt(len(sources) == self.wtem.n)
      g.assurt(len(destins) == self.wtem.n)

      for n in xrange(self.wtem.n):
         rt = {'beg_nid': sources[n]['node_id'],
               'fin_nid': destins[n]['node_id']}
         log.verbose('  Src: %d, Dest: %d' % (sources[n]['node_id'],
                                              destins[n]['node_id'],))
         self.routes_queued.append(rt)

      log.info('Fetched %d synthetic routes to analyse.'
               % (len(self.routes_queued),))

   #
   def do_routes_synthetic_find(self, geom_region_wkt):

      # MAYBE: We may use a JOIN to restrict node endpoints to just those
      # associated to streets and not sidewalks or bike trails. This is because
      # there was a problem picking too many nodes in islands from whence we
      # couldn't find a route to the finishing node endpoint. But I [lb] do not
      # like excluding trails and sidewalks. By excluding them, we are ignoring
      # the problem of why routes to/from them are failing. Also, there are
      # other ways to recover from the problem without excluding data from the
      # analysis.
      hack_exclude_possible_islands = True
      hack_exclude_possible_islands = False
      if hack_exclude_possible_islands:
         hack_by_class = ("AND (gf.geofeature_layer_id NOT IN (%d, %d)))"
                          % (byway.Geofeature_Layer.Bike_Trail,
                             byway.Geofeature_Layer.Sidewalk,))
      else:
         hack_by_class = ""

      # If we're doing an historic analysis, we want to find only historic
      # node_endpoints. The node_endpoint table is wiki'ed -- each node has
      # one or more versions and uses valid_start_rid and valid_until_rid --
      # but the table is new to Mpls-St.Paul circa revision 16000, and we
      # didn't bother building records for all of the previous revisions.
      #
      # Obviously, this problem only affects Mpls-St.Paul. If you're using
      # Cyclopath with a fresh map and starting at revision = 1, the
      # node_endpoint table will not have this problem.
      #
      # So if we look at node_endpoint for Mpls-St.Paul at an old revision,
      # we might find a node that's not used by any byways at that revision.
      # This isn't horrible -- the find-route will fail to find a route and
      # we'll pick additional random endpoints to make sure we analyse the
      # number of routes the user requested.

      # FIXME: Put this in conf? Make template default different than what
      #        Mpls-St.Paul uses?
      fetch_synthetic_from_geofeature = False # Should be default
      fetch_synthetic_from_geofeature = True # What Mpls-St.Paul has to use.
      # NOTE: I have no idea if there's a performance diff. btw. the two opts.

      if not fetch_synthetic_from_geofeature:
         # This is the preferred path, for newer Cyclopath installations.
         sql = self.sql_syn_from_node_endpoint(geom_region_wkt, hack_by_class)
      else:
         # This is the guaranteed results path, for Mpls-St.Paul.
         sql = self.sql_syn_from_geofeature(geom_region_wkt, hack_by_class)

      log.info('  Fetching random byway nodes for synthetic routes...')
      g.assurt(not self.qb_cur.db.dont_fetchall)
      results = self.qb_cur.db.sql(sql)
      log.info('  Fetched %d byway nodes.' % (len(results),))

      return results

   #
   def sql_syn_from_node_endpoint(self, geom_region_wkt, hack_by_class):

      # Restrict by region, maybe.
      regions_where = ""
      if geom_region_wkt:
         regions_where = (
         """
         AND ST_Intersects(ptxy.endpoint_xy,
                           ST_Buffer(ST_GeomFromEWKT('%s'),
                           0))
         """ % (geom_region_wkt,))

      # Restrict by roadway classification, maybe.
      restrict_by_class = ""
      if hack_by_class:
         restrict_by_class = (
            """
            JOIN
               geofeature AS gf
               ON (((ndpt.stack_id = gf.beg_node_id)
                    OR (ndpt.stack_id = gf.fin_node_id))
                   %s) -- AND gf.geofeature_layer_id NOT IN (...)
            """ % (hack_by_class,))

      sql = (
         """
         SELECT
            ndpt.stack_id AS node_id
         FROM
            node_endpoint AS ndpt
         JOIN
            item_versioned AS ndpt_iv
            ON (ndpt.system_id = ndpt_iv.system_id)
         JOIN
            node_endpt_xy AS ptxy
            ON (ptxy.node_stack_id = ndpt.stack_id)
         %s -- restrict_by_class (maybe restrict by byway type)
         WHERE
            ndpt.branch_id = %d
            AND %s -- revision.as_sql_where
            AND ndpt.reference_n > 0
            AND ptxy.endpoint_xy IS NOT NULL
            %s -- regions_where
         ORDER BY
            RANDOM()
         LIMIT
            %d
         """ % (restrict_by_class,
                self.qb_src.branch_hier[0][0],
                self.qb_src.revision.as_sql_where('ndpt_iv'),
                regions_where,
                self.wtem.n,))

      return sql

   #
   def sql_syn_from_geofeature(self, geom_region_wkt, hack_by_class):

      # Restrict by region, maybe.
      if geom_region_wkt:
         regions_select = (
         """
         , ST_Intersects(ST_StartPoint(geometry),
                         ST_Buffer(ST_GeomFromEWKT('%s'),
                         0)) AS beg_node_intersects
         , ST_Intersects(ST_EndPoint(geometry),
                         ST_Buffer(ST_GeomFromEWKT('%s'),
                         0)) AS fin_node_intersects
         """ % (geom_region_wkt,
                geom_region_wkt,))
      else:
         regions_select = (
         """
         , TRUE AS beg_node_intersects
         , TRUE AS fin_node_intersects
         """)

      # Format the query string.
      sql = (
         """
         SELECT
            cp_node_ids_unnest(beg_node_id,
                               fin_node_id,
                               beg_node_intersects,
                               fin_node_intersects) AS node_id
         FROM (
            SELECT
               beg_node_id
               , fin_node_id
               %s -- beg_node_intersects and fin_node_intersects
            FROM (
               SELECT
                  DISTINCT(iv.stack_id) stack_id
                  , iv.system_id
                  , iv.branch_id
                  , iv.version
                  , iv.deleted
                  , gf.beg_node_id
                  , gf.fin_node_id
                  , gf.geometry
               FROM
                  geofeature AS gf
               JOIN
                  item_versioned AS iv
                     USING (system_id)
               WHERE
                  (gf.beg_node_id IS NOT NULL)
                  AND (gf.fin_node_id IS NOT NULL)
                  AND %s -- branch and revision and last_merge_revs
                  %s -- hack_by_class (maybe restrict by byway type)
               GROUP BY
                  iv.stack_id
                  , iv.system_id
                  , iv.branch_id
                  , iv.version
                  , iv.deleted
                  , gf.beg_node_id
                  , gf.fin_node_id
                  , gf.geometry
               ORDER BY
                  iv.stack_id ASC
                  , iv.branch_id DESC
                  , iv.version DESC
               ) AS foo
            WHERE
               /* The inner query gets deleted b/c of stacked branching. */
               deleted IS FALSE
            ) AS bar
         WHERE
            /* We only care about nodes within the region(s). */
            beg_node_intersects
            OR fin_node_intersects
         ORDER BY
            RANDOM()
         LIMIT
            %d
         """ % (regions_select,
                # NO: self.qb_src.revision.as_sql_where('iv'),
                self.qb_src.branch_hier_where('iv', allow_deleted=True),
                # Restrict by roadway classification, maybe.
                hack_by_class,
                self.wtem.n,))

      return sql

   # *** ROUTE SELECTION: PAST JOB

   #
   def do_routes_selection_job(self):

      log.info('Selecting the snapshot from a previous job')

      # Selecting routes from a previous job requires self.wtem.cmp_job_name.
      if not self.wtem.cmp_job_name:
         raise Exception('Please specify a job name.')

      # Do database call to fetch source-destination pairs from specified
      # previously-requested job.
      # BUG nnnn: This requires an exact name match, and if two jobs have the
      # same name, it grabs both jobs' end nodes.
      # NOTE: Don't forget to check not deleted, and to use the branch ID,
      #       so that name-clashes only happen to the self-same branch.
      sql = (
         """
         SELECT
            rjn.beg_node_id,
            rjn.fin_node_id
         FROM
            route_analysis_job_nids AS rjn
         JOIN
            item_versioned AS iv
            ON iv.system_id = rjn.job_id
         WHERE
            iv.name = %s
            AND iv.branch_id = %d
            AND iv.deleted IS FALSE
            AND iv.valid_until_rid = %d
         """ % (self.qb_cur.db.quoted(self.wtem.cmp_job_name),
                self.wtem.branch_id,
                conf.rid_inf,))

      self.qb_cur.db.dont_fetchall = True
      rows = self.qb_cur.db.sql(sql)

      g.assurt(not self.routes_queued)
      generator = self.qb_cur.db.get_row_iter()
      for row in generator:
         rt = {'beg_nid': row['beg_node_id'],
               'fin_nid': row['fin_node_id']}
         self.routes_queued.append(rt)
      generator.close()

      self.qb_cur.db.dont_fetchall = False
      self.qb_cur.db.curs_recycle()

   # *** ROUTE SELECTION: RADIAL

   #
   def do_routes_selection_radial(self):

      log.info('Selecting sources and destins for radial routes...')

      # BUG nnnn: Radial Route Selection.
      #           ([lb]: See 2012.07.11 Cycloplan meeting notes.)

      raise Exception('BUG nnnn: Radial route selection not implemented.')

      pass

   # -- STAGE 6 ---------------------------------------------------------------

   #
   def do_prefs_selection(self):

      self.stage_initialize('Selecting preferences')

      # Load rider profile.
      self.rider_profile = Rider_Profile(self.wtem.rider_profile)
      self.shortest_dist_profile = Rider_Profile(
         Route_Analysis.profile_shortest_distance_p3)

   # -- STAGE 7 ---------------------------------------------------------------

   #
   def do_routed_wait(self):

      self.stage_initialize('Waiting for routed')

      if SKIP_ROUTED and (self.readyfile is None):
         return

      # MAGIC_NUMBER: Wait 'til routed is ready. Check every second for its
      # "done" signal. And don't wait infinitely; twenty minutes sounds like
      # plenty of time.
      wait_max = 20.0 * 60.0 # Wait 20 mins. for route finder to boot.
      prog_log = Debug_Progress_Logger(loop_max=math.ceil(wait_max))
      prog_log.log_freq = prog_log.loop_max / 100.0
      prog_log.log_listen = self.prog_update
      log.debug('Waiting for routed to load...')
      while not os.path.exists(self.readyfile):
         try:
            if SKIP_ROUTED:
               raise Exception(
                  'No route finder: Check SKIP_ROUTED and SKIP_PURPOSE.')
            if (time.time() - self.t0_routed) > wait_max:
               raise Exception(
                  'Waited too long for the route finder! Giving up.')
            time.sleep(1)
            prog_log.loops_inc()
         except Exception, e:
            log.error('Missing readyfile: %s' % (self.readyfile,))
            raise

      log.info('routed is up and running after %s'
               % (misc.time_format_elapsed(self.t0_routed),))

      self.t0_routed = None

      # Figure out the port number our routed is running on.
      # BUG nnnn: Hard-coding routed_pers. BUG nnnn: Support 'p2'.
      #           2012.07.11: Call it 'R2'. Or rd2?
      self.routed_port = Routed_Ports.find_routed_port_num(
            self.qb_cur.db,
            self.wtem.branch_id,
            Route_Analysis.routed_use_planner,
            self.purpose,
            self)

      log.debug('Found routed on port %d.' % (self.routed_port,))

   # -- STAGE 8 ---------------------------------------------------------------

   #
   def do_run_requests(self):

      self.stage_initialize('Running route requests')

      # DEVS: When employing the SKIP_ROUTED hack, all the fancy
      #       routed-port-guid stuff isn't done.
      if SKIP_ROUTED and self.routed_port is None:
         self.purpose = SKIP_PURPOSE # E.g., 'analysis'
         self.routed_port = Routed_Ports.find_routed_port_num(
            self.qb_cur.db,
            self.wtem.branch_id,
            Route_Analysis.routed_use_planner,
            self.purpose,
            self)
         g.assurt(self.routed_port)

      t0_all = time.time()

      prog_log = Debug_Progress_Logger(loop_max=self.n_analsed_goal)
      prog_log.log_freq = 1
      prog_log.log_listen = self.prog_update

      g.assurt(conf.analysis_async_limit >= 1)

      num_loops = 1
      while num_loops > 0:

         g.assurt(self.task_queue is None)
         self.task_queue = Task_Queue(num_consumers=conf.analysis_async_limit)

         # Start a job for each thread.
         for i in xrange(conf.analysis_async_limit):
            try:
               self.task_queue.add_work_item(
                     f_process=self.do_run_requests_queued,
                     process_args=[prog_log,],
                     process_kwds=None,
                     f_on_success=self.do_run_requests_success,
                     f_on_exception=self.do_run_requests_failure,
                     f_postprocess=self.do_run_requests_postprocess)
            except Task_Queue_At_Capacity_Error:
               log.error('do_run_requests: Unexpected: At Capacity.')

         # Wait for each thread to complete.
         try:
            self.task_queue.stop_consumers(wait_empty=True, do_joins=True)
         except Task_Queue_Complete_Error:
            log.warning('do_run_requests: unexpected: tasks already stopped.')

         self.task_queue = None

         # See if we're done or if we should load some more node_endpoints.
         if len(self.routes_analsed) >= self.n_analsed_goal:
            g.assurt(len(self.routes_analsed) == self.n_analsed_goal)
            done_running_requests = True
         else:
            done_running_requests = False

         if self.wtem.rt_source == route_analysis_job.Route_Source.SYNTHETIC:
            if not done_running_requests:
               # This means some of the route requests failed. Load another set
               # of routes to analyse and try again.
               log.info(
                  'Not all route requests completed okay; trying some more...')
               self.do_routes_selection_synthetic()
               num_loops += 1
               # MAGIC NUMBER: Don't do more than 3 loops. That would mean 66%
               # of route requests have failed. Give up already.
               if num_loops > 3:
                  log.error('do_run_requests: too many tries')
                  num_loops = 0
            else:
               # All done running requests.
               num_loops = 0
         else:
            num_loops = 0
            # FIXME: For user routes, we should request more routes to analyze
            #        (and we should understand why some requests fail -- is it
            #        really an island-to-island problem?).
            if self.wtem.rt_source == route_analysis_job.Route_Source.JOB:
               # This should only happen if the revision of the new job differs
               # and produces different results.
               log.warning(
                  "do_run_reqs: analysed fewer rts than before (diff't rev?)")
            # else, self.wtem.rt_source == route_analysis_job.Route_Source.USER
            #  which means there are not enough user routes to be found.

      log.debug('do_run_requests: analysed all routes in %s'
                % (misc.time_format_elapsed(t0_all),))

   # ***

   #
   # This is a thread callback fcn.
   def do_run_requests_queued(self, prog_log):

      time_0 = time.time()

      n_analysed = 0

      done_running_requests = False

      while not done_running_requests:

         self.routes_lock.acquire()
         is_locked = True
         try:
            # If there have been sufficient number of successful route
            # requests, quit.
            if len(self.routes_analsed) >= self.n_analsed_goal:
               g.assurt(len(self.routes_analsed) == self.n_analsed_goal)
               done_running_requests = True
            else:
               rt = self.routes_queued.pop()
               self.routes_lock.release()
               is_locked = False
               self.do_run_requests_queued_(rt, prog_log)
               n_analysed += 1
         except IndexError:
            done_running_requests = True
         finally:
            if is_locked:
               self.routes_lock.release()

      log.debug('do_run_requests_queued: analysed %d routes in %s'
         % (n_analysed, misc.time_format_elapsed(time_0),))

   #
   # This runs in thread context.
   def do_run_requests_queued_(self, rt, prog_log):

      analysed_rt = None

      xml = self.route_evaluate(rt)

      if xml is not None:

         try:

            log.debug('do_run_requests_qd: sending route request...')

            time_0 = time.time()

            parsed_xml = etree.fromstring(xml)

            if parsed_xml.tag in ('gwis_error', 'gwis_fatal',):

               msg = parsed_xml.get('msg')
               log.error('Error from routed: %s.' % (msg,))

               # SYNC_ME: See item.feat.route.py.
               # BUG nnnn: MAYBE: in addition to msg, GWIS_Error can include
               #           a failure code. Like python's errno. So fcns. like
               #           this don't have to parse text to figure out the
               #           error...
               # Search the error message to figure out what happened.
               if msg.find('No route exists') >= 0:
                  misc.dict_count_inc(self.routes_failed_reason, 'no_route')
               else:
                  misc.dict_count_inc(self.routes_failed_reason, 'unknown')

            else:

               try:
                  route_gml = parsed_xml.getchildren()[0]
               except IndexError:
                  log.error(
                     'do_run_requests_qd: parsed_xml got no children: %s'
                     % (etree.tostring(parsed_xml, pretty_print=True),))
                  misc.dict_count_inc(self.routes_failed_reason, 'no_child')
                  raise # Caught by outer except
               except Exception, e:
                  log.error('do_run_requests_qd: unknown failure: %s / %s'
                            % (str(e), xml,))
                  misc.dict_count_inc(self.routes_failed_reason, 'Eunknown')
                  raise # Caught by outer except

               # The 'analysis' route finder does not save routes to the
               # database. So the route we get doesn't have a stack ID.

               analysed_rt = route.One()
               # MAYBE: Do we pass self.qb_src or self.qb_cur? I think the
               #        latter.
               analysed_rt.from_gml(self.qb_cur, route_gml)

               log.debug('do_run_requests_qd: analysed route in %s'
                         % (misc.time_format_elapsed(time_0),))
               time_1 = time.time()

               self.routes_lock.acquire()
               try:
                  # Check that another thread didn't already fill in the final
                  # route.
                  if len(self.routes_analsed) < self.n_analsed_goal:
                     self.route_to_shpf(analysed_rt, rt)
                     self.route_to_blocks(analysed_rt)
                     self.routes_analsed.append(rt)
                     prog_log.loops_inc()
                  # else, another thread completed the final route, so just
                  # toss this one.
               except Exception, e:
                  log.error(
                     'do_run_requests_qd: failed recording route: %s / %s / %s'
                     % (str(e), rt, str(analysed_rt),))
                  misc.dict_count_inc(self.routes_failed_reason, 'Eunknown')
               finally:
                  self.routes_lock.release()

               log.debug(
                  'do_run_requests_qd: post-processed route in %s'
                  % (misc.time_format_elapsed(time_1),))

         except Exception, e:

            log.error('Error parsing XML: "%s" / %s'
                      % (str(e), traceback.format_exc(),))

   # ***

   #
   def do_run_requests_success(self, result, prog_log):
      log.debug('do_run_requests_success: result: %s' % (result,))

   #
   def do_run_requests_failure(self, exc_inf, prog_log):
      (err_type, err_val, err_traceback,) = exc_inf
      log.debug('do_run_requests_failure: exc_inf: %s | %s | %s'
                % (err_type, err_val, err_traceback.__str__(),))
      stack_trace = traceback.format_exc()
      log.warning('do_run_requests_failure: %s' % (stack_trace,))

   #
   def do_run_requests_postprocess(self, prog_log):
      log.debug('Done processing job')

   # ***

   #
   # Evaluate a single route.
   # This fcn. runs in thread context.
   def route_evaluate(self, rt, profile_override=None):

      log.info('Evaluating rt from %s to %s' % (rt['beg_nid'], rt['fin_nid'],))

      time_0 = time.time()

      xml = None

      try:

         # Open connection.
         sock = socket.socket()
         sock.connect(('localhost', self.routed_port))
         sockf = sock.makefile('r+')

         # Write commands.

         # SYNC_ME: pyserver.gwis.command_.route_get.routed_fetch sockf()s
         #          and services.route_analysis.route_analysis.route_evaluate
         #          and services.route_analysis.route_analysis.write_to_sock.

         # Even if the route had been originally requested by someone else,
         # for analysis, we should run it as though it is requested by the
         # user that requested the analysis job.
         if (self.wtem.created_by is not None):
            sockf.write('user %s\n' % (self.wtem.created_by))
         # Skipping: 'host %s\n'
         # Skipping: 'session_id %s\n'
         sockf.write('source %s\n' % ("analysis"))
         # MAGIC NAME: The from/to don't matter and aren't recorded to the db.
         sockf.write('beg_addr %s\n' % ("Somewhere"))
         sockf.write('beg_ptx %s\n' % (0))       # Not needed since
         sockf.write('beg_pty %s\n' % (0))       # node id is specified.
         # Since we're not sending an x,y and addr, we gotta send a node ID.
         sockf.write('beg_nid %s\n' % (rt['beg_nid']))
         # The end endpoint.
         sockf.write('fin_addr %s\n' % ("Somewhere"))
         sockf.write('fin_ptx %s\n' % (0))         # Not needed since
         sockf.write('fin_pty %s\n' % (0))         # node id is specified.
         sockf.write('fin_nid %s\n' % (rt['fin_nid']))
         # Set 
         if profile_override is None:
            self.rider_profile.write_to_sock(self, sockf)
         else:
            profile_override.write_to_sock(self, sockf)
         sockf.write('asgpx %d\n' % int(False))
         # Skipping 'save_route %d\n' (it'll default to False)

         # Execute the find operation.
         sockf.write('route\n')

         sockf.flush()

         # Read XML response.
         byte_count_str = sockf.readline().rstrip()
         if byte_count_str == '':
            log.warning(
               'No response from routing server. Please report this bug.')
            xml = None
         else:
            byte_count = int(byte_count_str)
            xml = sockf.read(byte_count)

         # Close connection.
         # NOTE: Close both to avoid "Connection reset by peer" on server.
         sockf.close()
         sock.close()

      except socket.error, e:
         log.error('Error connecting to routing server: %s' % (str(e),))

      except IOError, e:
         log.error('I/O error connecting to routing server: %s' % (str(e),))

      except Exception, e:
         log.error('Unknown error: %s.' % (str(e),))
         log.info(traceback.format_exc())

      log.debug('route_evaluate: evaluated route in %s'
                % (misc.time_format_elapsed(time_0),))

      return xml

   # ***

   #
   def get_route_sp(self, rt):
      '''Gets the shortest path distance from source to destination.'''

      sp_dist = 0.0

      # Evaluate the route with the shortest distance profile.
      xml = self.route_evaluate(rt, self.shortest_dist_profile)

      if xml is not None:

         try:

            log.debug('get_route_sp: sending route request...')

            parsed_xml = etree.fromstring(xml)

            if parsed_xml.tag in ('gwis_error', 'gwis_fatal',):

               msg = parsed_xml.get('msg')
               log.error('Error from routed: %s.' % (msg,))

            else:

               try:
                  route_gml = parsed_xml.getchildren()[0]
               except IndexError:
                  log.error(
                     'get_route_sp: parsed_xml got no children: %s'
                     % (etree.tostring(parsed_xml, pretty_print=True),))
                  raise # Caught by outer except.
               except Exception, e:
                  log.error('get_route_sp: unknown failure: %s / %s'
                            % (str(e), xml,))
                  raise # Caught by outer except.

               analysed_rt = route.One()
               # MAYBE: Do we pass self.qb_src or self.qb_cur? I think the
               #        latter.
               analysed_rt.from_gml(self.qb_cur, route_gml)

               # Calculate route length.
               for rs in analysed_rt.rsteps:
                  g.assurt(rs.edge_length is not None)
                  sp_dist += rs.edge_length

         except Exception, e:

            log.error('Error parsing XML (SD): "%s" / %s'
                      % (str(e), traceback.format_exc(),))

      log.debug('get_route_sp: finished route request (SD): sd = %.6f'
                % (sp_dist,))

      return sp_dist

   # ***

   #
   # This fcn. runs in thread context. With the lock.
   def route_to_shpf(self, rt, node_pair):

      # Create feature.
      feat = ogr.Feature(self.layers['route'].GetLayerDefn())

      # Set geometry.
      g.assurt(not rt.geometry_wkt)
      # MAYBE: We have geometry in each of the rsteps. The route daemon sends
      #        us route steps... but we just want the complete geometry.
      #        We could go through the route step strings and parse and remake
      #        the WKT... or we could just sql our way to it.
      rt.steps_fill_geometry(self.qb_cur)
      g.assurt(rt.geometry_wkt)

      geometry_wkt = rt.geometry_wkt
      if geometry_wkt.startswith('SRID='):
         geometry_wkt = geometry_wkt[geometry_wkt.index(';')+1:]
      geometry = ogr.CreateGeometryFromWkt(geometry_wkt)
      feat.SetGeometryDirectly(geometry)
      # 2012.08.12: The route is a multilinestring. It's also not always
      # simple, because not all byways are simple (which is another problem).
      # Skipping: g.assurt(feat.GetGeometryRef().IsSimple())
      g.assurt(not feat.GetGeometryRef().IsRing())

      # Set fields.
      rdi_sl = 0.0
      rdi_sp = 0.0
      length = 0.0
      tot_rtng = 0.0
      avg_rtng = 0.0

# EXPLAIN: AND ST_IsValid(bn1.node_vertex_xy) ?? Why is endpoint not valid?

      # NOTE: We're cheating a little here. The endpoint_xy never changes once
      # it's set for a node_endpoint. Since we just want the xy, we can just
      # get any matching node_endpoint -- it doesn't matter from what branch or
      # what revision, really.
      try:
         for rs in rt.rsteps:
            length += rs.edge_length
            tot_rtng += (rs.edge_length * rs.rating)
            dist_sl = self.qb_cur.db.sql(
               '''
               SELECT ST_Distance((
                  SELECT
                     ndxy_1.endpoint_xy
                  FROM
                     node_endpt_xy AS ndxy_1
                  WHERE
                     ndxy_1.node_stack_id = %d
               ), (
                  SELECT
                     ndxy_2.endpoint_xy
                  FROM
                     node_endpt_xy AS ndxy_2
                  WHERE
                     ndxy_2.node_stack_id = %d
               )) AS dist
               ''' % (node_pair['beg_nid'],
                      node_pair['fin_nid'],)
               )[0]['dist']
         g.assurt(dist_sl > 0.0)
         rdi_sl = length / dist_sl
         g.assurt(length > 0.0)
         avg_rtng = tot_rtng / length
      except Exception, e:
         log.warning('Error computing RDI: %s' % (str(e),))
         # FIXME: Should we set rdi negative or something?

      # Compute rdi_sp
      dist_sp = self.get_route_sp(node_pair)
      rdi_sp = length / dist_sp if dist_sp > 0.0 else None

      feat.SetField('length', length)
      feat.SetField('rdi_sl', rdi_sl)
      feat.SetField('rdi_sp', rdi_sp)
      feat.SetField('avg_rtng', avg_rtng)

      # Write + Cleanup.
      self.layers['route'].CreateFeature(feat)
      feat.Destroy()

      log.info('Wrote route to shapefile: RDI (SL) = %.6f, RDI (SP) = %.6f'
               % (rdi_sl, rdi_sp,))

# FIXME: Delete this
      """
      dist_sl = self.qb_cur.db.sql(
         '''
         SELECT ST_Distance((
            SELECT
               ndpt_1.endpoint_xy
            FROM
               node_endpoint AS ndpt_1
            WHERE
               ndpt_1.stack_id = %d
               AND ST_IsValid(ndpt_1.endpoint_xy)
            ORDER BY
               ndpt_1.version DESC
            LIMIT 1
         ), (
            SELECT
               ndpt_2.endpoint_xy
            FROM
               node_endpoint AS ndpt_2
            WHERE
               ndpt_2.stack_id = %d
               AND ST_IsValid(ndpt_2.endpoint_xy)
            ORDER BY
               ndpt_2.version DESC
            LIMIT 1
         )) AS dist
         ''' % (node_pair['beg_nid'],
                node_pair['fin_nid'],)
         )[0]['dist']
      """

   #
   # This fcn. runs in thread context. With the lock.
   def route_to_blocks(self, rt):
      for rstep in rt.rsteps:
         byway_stack_id = rstep.byway_stack_id
         if byway_stack_id not in self.routes_thru_byways:
            self.routes_thru_byways[byway_stack_id] = 0
         self.routes_thru_byways[byway_stack_id] += 1

   # -- STAGE 9 ---------------------------------------------------------------

   #
   def do_build_output(self):

      self.stage_initialize('Building output')

      # We need to check that all the route requests didn't fail.
      if not self.routes_thru_byways:
         raise Exception('All route requests failed!')

      prog_log = Debug_Progress_Logger(loop_max=len(self.routes_thru_byways))
      # We can save byway pretty quickly. 1000 is probably a good freq?
      prog_log.log_freq = 250
      prog_log.log_listen = self.prog_update

      try:
         self.write_route_nids()
         self.write_job_details()
         self.byways_to_shp(prog_log)
         self.shapefiles_sync()
      except Exception, e:
         raise Exception('Error building output: %s' % (str(e),))

   #
   def write_route_nids(self):

      '''Populate the route_analysis_job_nids table.'''

      log.info('Writing route nids to database...')

      values_sql = ",".join(
         map(lambda x: ('(%d,%d,%d)'
                        % (self.wtem.system_id,
                           x['beg_nid'],
                           x['fin_nid'])),
             self.routes_analsed))

      sql = (
         """
         INSERT INTO route_analysis_job_nids
            (job_id, beg_node_id, fin_node_id)
         VALUES
            %s
         """ % (values_sql,))

      # BUG 2688: Use transaction_retryable?
      # NO: Catch ERROR:  duplicate key value violates unique constraint "revision_pkey"
      # just means already entered
      # FIXME: route_analysis_job_nids does not have an explicit primary key
      self.qb_cur.db.transaction_begin_rw()
      self.qb_cur.db.sql(sql)
      self.qb_cur.db.transaction_commit()

   #
   def write_job_details(self):

      log.info('Writing job details to text file...')

      filename = 'job_details.txt'
      directory_name = '%s.out' % (self.wtem.local_file_guid,)
      filepath = os.path.join(conf.shapefile_directory,
                              directory_name,
                              filename)

      f = open(filepath, 'w')
      f.write('Job ID: %s\r\n' % (self.wtem.stack_id,))
      f.write('Job Name: %s\r\n' % (self.wtem.name,))
      f.write('Analysed %d routes of %d found of %d requested.'
           % (len(self.routes_analsed), self.n_analsed_goal, self.wtem.n,))
      # Print failure counts, if any failures.
      for defn in Route_Analysis.fail_reasons:
         if self.routes_failed_reason[defn[0]] > 0:
            # FIXME: It would be nice to print the node_endpoint IDs of what
            # failed, but hopefully after debugging what we see in the logfile,
            # we won't see many failures in the future.
            f.write('Failed / %s / no. failed: %d\r\n'
                    % (defn[1], self.routes_failed_reason[defn[0]],))

      f.close()

      os.chmod(filepath,   stat.S_IRUSR | stat.S_IWUSR
                         | stat.S_IRGRP | stat.S_IWGRP
                         | stat.S_IROTH)

   #
   def byways_to_shp(self, prog_log):

      log.info('Writing byways to shapefile...')

      # We have a list of byway stack IDs, so we'll just load that into a
      # temporary join table to load the byways we want to export.

      self.qb_src.db.transaction_begin_rw()

      self.qb_src.load_stack_id_lookup('byways_to_shp',
                                       self.routes_thru_byways)

      byways = byway.Many()

      self.qb_src.db.dont_fetchall = True
      byways.search_for_items(self.qb_src)

      log.debug('byways_to_shp: found %d of %d'
                % (self.qb_src.db.curs.rowcount,
                   len(self.routes_thru_byways),))

      g.assurt(self.qb_src.db.curs.rowcount > 0)

      generator = byways.results_get_iter(self.qb_src)
      for bw in generator:
         # Create feature.
         feat = ogr.Feature(self.layers['byway'].GetLayerDefn())
         # Set fields.
         feat.SetField('id', bw.stack_id)
         feat.SetField('n_routes', self.routes_thru_byways[bw.stack_id])
         # MAYBE: Does it matter that these ratings are for Current()?
         #        Should we also include ratings from the revision being
         #        analysed?
         feat.SetField('rtng_sys', bw.generic_rating)
         feat.SetField('rtng_usr', bw.user_rating)
         feat.SetField('n_rtng', bw.rating_cnt)
         feat.SetField('length', bw.geometry_len)
         # Set geometry.
         geometry_wkt = bw.geometry_wkt
         if geometry_wkt.startswith('SRID='):
            geometry_wkt = geometry_wkt[geometry_wkt.index(';')+1:]
         geometry = ogr.CreateGeometryFromWkt(geometry_wkt)
         feat.SetGeometryDirectly(geometry)
         g.assurt(feat.GetGeometryRef().IsSimple())
         g.assurt(not feat.GetGeometryRef().IsRing())
         # Write + Cleanup.
         self.layers['byway'].CreateFeature(feat)
         feat.Destroy()
         # Bump the progress.
         prog_log.loops_inc()
      generator.close()

      g.assurt(self.qb_src.filters.stack_id_table_ref)
      self.qb_src.db.sql("DROP TABLE %s"
                         % (self.qb_src.filters.stack_id_table_ref,))

      self.qb_src.db.dont_fetchall = False
      self.qb_src.db.transaction_rollback()
      self.qb_src.db.curs_recycle()
      # NOTE: Not calling self.qb_src.db.close()

   # -- STAGE 10 --------------------------------------------------------------

   #
   def do_create_archive(self):

      Work_Item_Job.do_create_archive(self)

   # -- STAGE 11 --------------------------------------------------------------

   #
   def do_notify_users(self):

      Work_Item_Job.do_notify_users(self)

   # -- STAGE Finishing--------------------------------------------------------

   #
   def do_teardown(self):

      # Note: There's no self.stage_initialize(...) here because that is
      # already done by self.job_mark_complete().

      log.info('Tearing down...')

      self.layers = dict()
      if self.shpf is not None:
         self.shapefiles_sync()
         self.shpf.Release()
         self.shpf = None

      if SKIP_ROUTED:
         log.info('Teardown complete.')
         return

      log.info('Stopping routed ...')

      time_0 = time.time()

      # Shutdown routed.
      # NOTE: Skipping --revision
      the_cmd = self.routed_cmd('stop')
      log.debug('do_teardown: cmd: %s' % (the_cmd,))
      misc.run_cmd(the_cmd, outp=log.debug)

      # Wait till routed is dead. Check every second for its pidfile.
      # And don't wait infinitely; three minutes sounds like plenty of time.
      # IN LIEU OF: the_cmd = self.routed_cmd('status')
      give_up = False
      wait_max = 3.0 * 60.0
      time_0 = time.time()
      prog_log = Debug_Progress_Logger(loop_max=math.ceil(wait_max))
      prog_log.log_freq = prog_log.loop_max / 100.0
      prog_log.log_listen = self.prog_update
      log.debug('Waiting for routed to exit...')
      while os.path.exists(self.pidfile) and (not give_up):
         if (time.time() - time_0) > wait_max:
            # Don't raise an Exception. Complete the job.
            log.error('Waited too long for route finder to die! Giving up.')
            give_up = True
         time.sleep(1)
         prog_log.loops_inc()

      g.assurt(not os.path.exists(self.readyfile))
      self.readyfile = None

      if give_up:
         log.info('routed is dead!')

      log.debug('do_teardown: finished in %s'
                % (misc.time_format_elapsed(time_0),))

      log.info('Teardown complete.')

   # ***

# ***

if (__name__ == '__main__'):
   pass


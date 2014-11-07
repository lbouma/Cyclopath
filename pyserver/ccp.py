#!/usr/bin/python

# NOTE: Normally, one shabangs with /usr/bin/python, but if you've loaded a 
#       different Python executable with, e.g., 'module load soft/python/2.7',
#       you'll want to tell your shell to look for that one instead. E.g.,
#
#          #!/usr/bin/env python
#
#       But we don't do this in Cyclopath because we need mod_python, which is 
#       specific to the Python in /usr/bin: so a different Python won't work 
#       unless we also download and recompile mod_python.

# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ INSTANCE=minnesota ./ccp.py --help
#

script_name = 'Cyclopath Developer Script'
script_version = '1.0'

__version__ = script_version
__author__ = 'Landon Bouma <cyclopath@retrosoft.com>'
__date__ = '2011-05-23'

# FIXME: Rename this file gwis.py?

import code
from lxml import etree
#import mimetools
#import mimetypes
import os
import re
import shutil
#import socket
import stat
import sys
import time
import traceback
import urllib
import urllib2
import uuid

import conf
import g

# NOTE: This has to come before importing other Cyclopath modules, otherwise
#       g.log.getLogger returns the base Python Logger() and not our MyLogger()
# Get the terminal width and setup the logging facility.
# FIXME: What happens if this script runs from a terminalless process; cron?
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.DEBUG
#log_level = logging2.VERBOSE1
#log_level = logging2.VERBOSE2
#log_level = logging2.VERBOSE3
#log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
# FIXME: When called from cron, we're setting 80... but we should use -1
#        so we don't wrap... can we detect when cron and use -1 then?
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

# Even though we're run from the pyserver/ directory, we still have to load the
# glue file. That's because sys.path[0] is likely '', and we need to prepend
# the actual full path so sys.path[0] can be used later on.
import os
import sys
# NOTE: Using sys.path[0], which is '', results in just '/pyserver'.
#   NO: sys.path.insert(0, os.path.abspath('%s/../pyserver' % (sys.path[0],)))
sys.path.insert(0, os.path.abspath('%s' % (os.path.abspath(os.curdir),)))
import pyserver_glue

from grax.access_level import Access_Level
from gwis import command_client
from gwis.query_filters import Query_Filters
from gwis.query_viewport import Query_Viewport
import gwis.request

from grax.user import User
#from item import link_value
from item import grac_record
from item import item_base
from item import item_user_access
from item.feat import branch
from item.jobsq import merge_export_job
from item.jobsq import merge_job
from item.jobsq import route_analysis_job
from item.jobsq import work_item
from item.jobsq.job_status import Job_Status
from item.util import item_factory
from item.util import item_type
from item.util import revision
from item.util import search_map
from util_ import db_glue
from util_ import misc
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# FIXME: This does not work; user still has to setup their locals. We can 
#        probably somehow apply the locals from ccp.py? From the command 
#        prompt, self is the Ccp_Tool_Parser object, so I think it's doable.
# These imports serve two purposes: the user doesn't have to import item
# modules from the interactive prompt, and by importing all the item
# classes here, we're at least checking the syntax of the files.
from item.attc import annotation
from item.attc import attribute
from item.attc import post
from item.attc import tag
from item.attc import thread
from item.feat import branch
from item.feat import byway
from item.feat import node_endpoint
from item.feat import node_traverse
from item.feat import region
from item.feat import route
from item.feat import route_step
from item.feat import terrain
from item.feat import track
# FIXME: track_point
# from item.feat import track_point
from item.feat import waypoint
from item.grac import group
from item.grac import group_item_access
from item.grac import group_membership
from item.grac import new_item_policy
from item.grac import user_record
from item.jobsq import merge_job
from item.jobsq import route_analysis_job
from item.jobsq import work_item
from item.jobsq import work_item_step
#from item.link import branch_conflict
from item.link import link_annotation
from item.link import link_attribute
from item.link import link_post
from item.link import link_tag
from item.link import link_thread
from item.link import link_uses_attr
from item.link import tag_counts
from planner import routed_p3
# For whatever reason, you cannot reference routed_p3.tgraph
# unless you also explicitly import the sub-module.
from planner.routed_p3 import tgraph as tgraph_p3
from planner.travel_mode import Travel_Mode

# Welcome to New Hack City.
# Since we loaded pyserver_glue, either of these works...
#sys.path.append(os.path.abspath('%s/../services' % (sys.path[0],)))
sys.path.append(
   os.path.abspath('%s/../services' % (os.path.abspath(os.curdir),)))
from mr_do import Mr_Do

## We don't use these modules in this package but yaml requires them to load
## our yaml config files, which reference them.
#from merge.ccp_merge_conf import Ccp_Merge_Conf_Base
#from merge.ccp_merge_conf import Ccp_Merge_Conf_Shim

log = g.log.getLogger('ccp_tool')
#log.setLevel(logging2.VERBOSE)

# *** Cli Parser class

class Ccp_Tool_Parser(Ccp_Script_Args):

   actions = (
      'interact',
      'create',
      'read',
      'update',
      'delete',
      'key_val',
      'search',
      'find_route',
      )

   # *** Constructor

   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   # *** Helpers

   #
   def prepare(self):

      # The base class sets up these single-char switches:
      # -v, -U, -P, -b, -V, -m, -g

      Ccp_Script_Args.prepare(self)

      # This class sets these single-char switches:
      # a, c, r, u, d, t, L, R, x, G, A, f, e, B, E, C, O, T, I, q, X, Y, F

      # Request action. One of the following.

      # Generic action switch. Redunanct.

      self.add_argument('-a', '--action', dest='action',
         action='store', default=False,
         help=
  'action: interact, create, read, update, delete, key_val, search, find_route'
         )

      # Interactive (python shell).

      self.add_argument('-i', '--interactive', dest='action',
         action='store_const', const='interact',
         help='open interactive Python prompt')

      # CRUD.

      self.add_argument('-c', '--create', dest='action',
         action='store_const', const='create',
         help='create new item')

      self.add_argument('-r', '--read', dest='action',
         action='store_const', const='read',
         help='show item')

      self.add_argument('-u', '--update', dest='action',
         action='store_const', const='update',
         help='update item')

      self.add_argument('-d', '--delete', dest='action',
         action='store_const', const='delete',
         help='delete item')

      ###self.add_argument('-k', '--key-val', dest='action',
      ###   action='store_const', const='key_val',
      ###   help='get value of key_value_pair entry')
      ## Cannot specify optional for positional, so don't do this:
      ##self.add_argument('kval_key',
      ##   help='get value of key_value_pair entry')
      #self.add_argument('-k', '--key-val', dest='kval_key',
      #   action='store', default=None, type=str,
      #   help='get value of key_value_pair entry')
      self.add_argument('-k', '--key-val', dest='kval_keys',
         action='append', default=[],
         help='get value of key_value_pair entry(ies)')

      # 

      self.add_argument('-s', '--search', dest='action',
         action='store_const', const='search',
         help='use search() fcn.')

      # Route Finding.

      # E.g.,
      #  ./ccp.py --route --p3 --from 'Java Train' --to 'Great River School'
      self.add_argument('--route', dest='action',
         action='store_const', const='find_route',
         help='find a route')

      self.add_argument('--from', dest='route_from',
         action='store', default='',
         help='the address from which to find a route')

      self.add_argument('--to', dest='route_to',
         action='store', default='',
         help='the address to which to find a route')

      self.add_argument('--p1', dest='planner_p1',
         action='store_true', default=False,
         help='Use the original, personalized routing planner')

      self.add_argument('--p2', dest='planner_p2',
         action='store_true', default=False,
         help='Use the transit-aware, multimodal route planner')

      self.add_argument('--p3', dest='planner_p3',
         action='store_true', default=False,
         help='Use the fast, static (non-personalized) route planner')

      # DEPRECATED: The p1 planner's priority is supplanted by the
      #             rating spread edge weight, but it's available
      #             here for legacy testing. E.g., for comparing the
      #             performance of the p1 finder and also to evaluate
      #             the routes it finds compares to the other finders.
      self.add_argument('--p1-priority', dest='p1_priority',
         action='store', default=None, type=float,
         help='for p1, from 0.0 to 1.0, 0.0=shortest, 1.0=bikeablest')

      self.add_argument('--p3-weight', dest='p3_weight',
         action='store', default='length', type=str,
         choices=('len', 'length',
                  'rat', 'rating',
                  'fac', 'facility',
                  'rac', 'rat-fac',
                  'prat', 'prating',
                  'pfac', 'pfacility',
                  'prac', 'prat-fac',
                  ),
         help='for p3 planner, edge weights to use')
      # MAGIC_NUMBERS: Defaults used in ccp.py, Conf.as, route_get.py,
      #                and 234-byway-is_disconnected.sql; see the value
      #                sets, pyserver/planner/routed_p3/tgraph.py's
      #                Trans_Graph.rating_pows and burden_vals.
      self.add_argument('--p3-spread', dest='p3_spread',
         action='store', default=0, type=int,
         choices=routed_p3.tgraph.Trans_Graph.rating_pows,
         help='for p3, rating burd: willingness to bike out of the way')
      self.add_argument('--p3-burden', dest='p3_burden',
         action='store', default=0, type=int,
         choices=routed_p3.tgraph.Trans_Graph.burden_vals,
         help='for p3, facil burd: willingness to bike out of the way')
      self.add_argument('--p3-path-alg', dest='p3_algorithm',
         action='store', default='astar_path', type=str,
         choices=('astar_path',
                  'all_shortest_paths',
                  'dijkstra_path',
                  'shortest_path',),
         help='for p3, which networkx shortest paths algorithm to use')

      self.add_argument('--route-do-save', dest='route_do_save',
         action='store_true', default=False,
         help='whether or not to save the new route in the database')

      # Target item type. One of the following.

      self.add_argument('-t', '--type', dest='item_type', 
         action='store', default=False, metavar='type',
         help='attc/feat/grac: [thread, byway, branch, user, etc.]')

      # Link value lhs_type.
      self.add_argument('--attc_type', dest='link_attc_type', 
         action='store', default=False, help='link_value.lhs_type')

      # Link value rhs_type.
      self.add_argument('--feat_type', dest='link_feat_type', 
         action='store', default=False, help='link_value.rhs_type')

      # If a GrAC request, the context.

      self.add_argument('-x', '--context', dest='grac_context',
         action='store', default=False,
         help='grac context: [branch, group, item, user]')

      # Target server or database.
      # 
      # Some commands connect to apache/pyserver, and others connect to
      # postgres.

      self.add_argument('-G', '--always_gwis', dest='always_gwis',
         action='store_true', default=False,
         help='use gwis protocol rather than calling sql directly')

      self.add_argument('--py_host', dest='pyserver_host',
         action='store', default='', type=str,
         help='the url where pyserver is hosted')

      self.add_argument('--py_port', dest='pyserver_port',
         action='store', default=0, type=int,
         help='the port number of the pyserver service')

      #self.add_argument('--pg_host', dest='postgres_host',
      #   action='store', default='localhost',
      #   help='the url where postgres is running')

      #self.add_argument('--pg_port', dest='postgres_port',
      #   action='store', default=5432, type=int,
      #   help='the port number of the postgres service')

      # Access level.

      #self.add_argument('-A', '--access_level', dest='access_level',
      #   action='store', default='', help=
      #   '[owner, arbiter, editor, viewer, client, denied]')
      #
      # query_filter.min_access_level
      self.add_argument('-A', '--access_level', dest='access_level',
         action='store', default=None, choices=
         (None, 'owner', 'arbiter', 'editor', 'viewer', 'client', 'denied'),
         help='access level ID')

      # Create/Update item key, value attribute pairs.

      self.add_argument('-e', '--edit', dest='edit_cols',
         action='append', default=[], nargs=2,
         help='item column value pair, e.g., -e name "My New Branch"')

      # (Single) Group Item Access record.

      self.add_argument('--gia', dest='gia_cols',
         action='append', default=[], nargs=2,
         help='group_item_access col., e.g., --gia access_level_id 3')

      # Search by Viewport.

      # Bounding Box.
      self.add_argument('-B', '--bbox', dest='viewport_bbox_in',
         action='store', default=None,
         help='the bounding box, or viewport, for a read query')
      # Exclusion Box.
      self.add_argument('-E', '--bbex', dest='viewport_bbox_ex',
         action='store', default=None,
         help='the exclusionary bounding box')

      # query_filter.filter_by_regions
      self.add_argument('--region', dest='viewport_region',
         action='store', default=None,
         help='name of region to use as bounding box for a -read')

      # *** Query_Filters

      # Most/all query_filters are support via --filter.

      # Query_Filter keyword, value pairs.

      self.add_argument('-f', '--filter', dest='filters',
         action='append', default=[], nargs=2,
         help='query_filter value pair, e.g., -f filter_by_username landonb')

      # But some query_filters also have a baked-in switch, too:

      # query_filter.pagin_count
      self.add_argument('-C', '--count', dest='filter_count',
         action='store', default=None, type=int,
         help='the number of records to retrieve')
      # query_filter.pagin_offset
      self.add_argument('-O', '--offset', dest='filter_offset',
         action='store', default=None, type=int,
         help='the page number of records to retrieve')
      # MAYBE: centerx and centery should prob. just be filters.
      # query_filter.centerx
      self.add_argument('-X', '--centerx', dest='centerx',
         action='store', default=None, type=float,
         help='full text search query centerx')
      # query_filter.centery
      self.add_argument('-Y', '--centery', dest='centery',
         action='store', default=None, type=int,
         help='full text search query centery')
      # Search by Full Text Search Query.
      # query_filter.filter_by_text_smart
      self.add_argument('-q', '--query', dest='query',
         action='store', default=None,
         help='full text search query string')
      # FIXME: Not implemented.
      self.add_argument('--center', dest='center',
         action='store', default=(0,0), nargs=2, type=int,
         help='full text search query center point')
      # Search by Stack ID.
      # FIXME: This can be specified by --filters, too, which seems silly.
      #        Choose one.
      # query_filter.only_stack_ids
      self.add_argument('-I', '--stack_ids', dest='only_stack_ids',
         action='store', default='', type=str,
         help='only get items with the specified stack ID(s)')
      # query_filter.only_associate_ids
      self.add_argument('--link_id', dest='only_associate_ids',
         action='append', default=[], type=int,
         help='filter: only get links to specified stack ID(s)')
      # Thread ID for posts.
      # NOTE: thread_stack_id is really context_id. So is really just a
      #       shortcut for --filter context_stack_id {thread_stack_id}
      # query_filter.context_stack_id
      self.add_argument('--thread_stack_id', dest='filter_thread_id',
         action='store', default=None, type=int,
         help='The thread ID of the requested posts')

      # ***

      # Send a file.

      # To send a file, we need multipart, which Python lib does not support.
      # http://atlee.ca/software/poster/index.html
      self.add_argument('-F', '--sendfile', dest='sendfile',
         action='store', default=None,
         help='upload a file with your GWIS request (used with -c(reate))')
      # BUG nnnn: Until we install and utilizer the poster library to send
      # files across GWIS to pyserver, we can at least fake an upload and
      # pyserver will wink, wink at us and just copy the file to its staging
      # area. So we can test from ccp.py and get good code coverage and take
      # advantage of the jobs queue and not have to waste time firing up
      # Firefox, loading flashclient, and testing thatuh'way. See the option,
      # -e download_fake /some/file/path/shps.zip

      self.add_argument('--verbose', dest='verbose_details',
         action='store_true', default=False,
         help='display verbose fetch details')

      self.add_argument('--allow_deleted', dest='allow_deleted',
         action='store_true', default=False,
         help='sets revision.allow_deleted')

      # ***

      self.add_argument('-W', '--wide-log', dest='wide_log',
         action='store_true', default=False,
         help='for cron, do not restrict log line width')

      self.add_argument('--log-cleanly', dest='log_cleanly',
         action='store_true', default=False,
         help='do not emit newlines to log, e.g., from GWIS, for logcheck')

      self.add_argument('--ignore-job-fail', dest='ignore_job_fail',
         action='store_true', default=False,
         help='if this is a work item job that fails, do not care')

      # ***

   #
   def verify_handler(self):
      ok = True
      # *** For key_val, so user doesn't have to specify two switches,
      #     key_val action is implied when key is supplied.
      if self.cli_opts.kval_keys:
         if self.cli_opts.action and (self.cli_opts.action != 'key_val'):
            log.error('Specified action does not recognize key_val')
            ok = False
         self.cli_opts.action = 'key_val'
      # *** Check the action
      if not (self.cli_opts.action in Ccp_Tool_Parser.actions):
         log.error('Please specify an action.')
         ok = False
      # *** Check the gwisness: we only support direct sql via read action 
      # (all other do_* commands send a gwis request to apache/pyserver).
      always_gwis_actions = ('read', 'key_val',)
      if (self.cli_opts.always_gwis
          and (self.cli_opts.action not in always_gwis_actions)):
         log.error('--always_gwis only works with the actions: %s.'
                   % (always_gwis_actions,))
         ok = False
      # *** Check the item type
      if self.cli_opts.action not in ('interact',
                                      'key_val',
                                      'search',
                                      'find_route'):
         if not self.cli_opts.item_type:
            log.error('Please specify an item type.')
            ok = False
         else:
            # Verify the item type
            if not item_factory.is_item_valid(self.cli_opts.item_type):
               log.error('Invalid item type: %s.' % (self.cli_opts.item_type,))
               ok = False
            if not (self.cli_opts.item_type 
                    in item_type.Item_Type.lookup_id_by_str):
               log.error('Unknown item type: %s.' % (self.cli_opts.item_type,))
               ok = False
      # *** Check the GrAC context
      if ok and (self.cli_opts.action == 'read'):
         item_module = item_factory.get_item_module(self.cli_opts.item_type)
         if isinstance(item_module.One(), grac_record.One):
            if not self.cli_opts.grac_context:
               log.error('Please specify a grac context.')
               ok = False
            else:
               if not (self.cli_opts.grac_context 
                       in grac_record.Many.context_types):
                  log.error('Unknown grac context: %s.' 
                      % (self.cli_opts.grac_context,))
                  ok = False
      # *** Check that only one viewport is specified
      if (self.cli_opts.viewport_bbox_in and self.cli_opts.viewport_region):
         log.error(
'Please specify neither or one of viewport_bbox and _region, but not both.')
         ok = False
      # *** Check that only one viewport is specified
      if (self.cli_opts.viewport_bbox_ex 
          and not self.cli_opts.viewport_bbox_in):
         log.error('Please specify include bbox when specifying exclude bbox.')
         ok = False
      # *** Check the Query Filters
      ok &= (    self.verify_cli_pairs_filters()
             and self.verify_cli_pairs_edit_cols()
             and self.verify_cli_pairs_gia_cols()
             and self.verify_qf_synonyms()
             and self.verify_query_filters()
             and self.verify_miscellany())
      # *** Noneify the branch if the user wants a branch list. This *must*
      # come after self.verify_qf_synonyms().
      if not self.cli_opts.branch:
         if ((self.cli_opts.action == 'read') 
             and (self.cli_opts.item_type == 'branch')):
            log.debug('verify_handler: no branch ID: none needed.')
            self.cli_opts.branch = None
         else:
            if self.cli_opts.branch is None:
               log.debug('verify_handler: no branch ID: using None.')
            else:
               log.debug('verify_handler: no branch ID: using public.')
      #
      if (self.cli_opts.allow_deleted and (self.cli_opts.action != 'read')):
         log.error('Please only use allow_deleted with the read action.')
         ok = False
      #
      if self.cli_opts.wide_log:
         logging2.config_line_format(conf.log_frmat_len, '  #  ', 999)
      # Finally check the base class. Do this last since we may have overridden
      # self.cli_opts.branch.
      ok &= Ccp_Script_Args.verify_handler(self)
      #
      return ok

   #
   def verify_cli_pairs_filters(self):
      ok = True
      kwords = Ccp_Tool_Parser.opts_to_dict(self.cli_opts.filters)
      # Check strings
      kwords.setdefault('filter_by_username', '')
      kwords.setdefault('filter_by_watch_item', '')
      kwords.setdefault('filter_by_names_exact', '')
      kwords.setdefault('filter_by_text_exact', '')
      kwords.setdefault('filter_by_text_loose', '')
      kwords.setdefault('filter_by_text_smart', '')
      kwords.setdefault('filter_by_thread_type', '')
      kwords.setdefault('filter_by_creator_include', '')
      kwords.setdefault('filter_by_creator_exclude', '')
      kwords.setdefault('only_stack_ids', '')
      kwords.setdefault('about_stack_ids', '')
      kwords.setdefault('only_lhs_stack_ids', '')
      kwords.setdefault('only_rhs_stack_ids', '')
      kwords.setdefault('filter_by_value_text', '')
      kwords.setdefault('only_item_type_ids', '')
      kwords.setdefault('use_stealth_secret', '')
      kwords.setdefault('results_style', '')
      # Check boolean values
      try:
         # NOTE: An option that's 0 might really be "0", so be sure to cast to
         # int first, lest we accidentally just bool a str, which is True if
         # the str is not empty (e.g., bool("0") is true).
         kwords['pagin_total'] = bool(int(
            kwords.get('pagin_total', False)))
         kwords['filter_by_watch_geom'] = bool(int(
            kwords.get('filter_by_watch_geom', False)))
         kwords['filter_by_watch_feat'] = bool(int(
            kwords.get('filter_by_watch_feat', False)))
         kwords['filter_by_unread'] = bool(int(
            kwords.get('filter_by_unread', False)))
         kwords['filter_by_nearby_edits'] = bool(int(
            kwords.get('filter_by_nearby_edits', False)))
         kwords['include_item_stack'] = bool(int(
            kwords.get('include_item_stack', False)))
         kwords['include_lhs_name'] = bool(int(
            kwords.get('include_lhs_name', False)))
         kwords['include_rhs_name'] = bool(int(
            kwords.get('include_rhs_name', False)))
         kwords['include_geosummary'] = bool(int(
            kwords.get('include_geosummary', False)))
         kwords['rating_restrict'] = bool(int(
            kwords.get('rating_restrict', False)))
         kwords['gia_use_sessid'] = bool(int(
            kwords.get('gia_use_sessid', False)))
         kwords['skip_tag_counts'] = bool(int(
            kwords.get('skip_tag_counts', False)))
         kwords['dont_load_feat_attcs'] = bool(int(
            kwords.get('dont_load_feat_attcs', False)))
         kwords['do_load_lval_counts'] = bool(int(
            kwords.get('do_load_lval_counts', False)))
         kwords['include_item_aux'] = bool(int(
            kwords.get('include_item_aux', False)))
         kwords['findability_ignore'] = bool(int(
            kwords.get('findability_ignore', False)))
         kwords['findability_ignore_include_deleted'] = bool(int(
            kwords.get('findability_ignore_include_deleted', False)))
         kwords['findability_recent'] = bool(int(
            kwords.get('findability_recent', False)))
         kwords['do_load_latest_note'] = bool(int(
            kwords.get('do_load_latest_note', False)))
         # This one isn't technically in qb.filters (it's just in qb).
         kwords['request_is_a_test'] = bool(int(
                                    kwords.get('request_is_a_test', False)))
      except ValueError, e:
         log.error('Expected boolean, got something else: %s.' % (str(e),))
         ok = False
      # Check integer values
      try:
         kwords['pagin_count'] = int(kwords.get('pagin_count', 0))
         kwords['pagin_offset'] = int(kwords.get('pagin_offset', 0))
         kwords['context_stack_id'] = int(kwords.get('context_stack_id', 0))
         kwords['min_access_level'] = int(kwords.get('min_access_level', 0))
         kwords['max_access_level'] = int(kwords.get('max_access_level', 0))
         kwords['only_system_id'] = int(kwords.get('only_system_id', 0))
         kwords['only_lhs_stack_id'] = int(kwords.get('only_lhs_stack_id', 0))
         kwords['only_rhs_stack_id'] = int(kwords.get('only_rhs_stack_id', 0))
         kwords['rev_min'] = int(kwords.get('rev_min', 0))
         kwords['rev_max'] = int(kwords.get('rev_max', 0))
      except ValueError, e:
         log.error('Expected integer, got something else: %s.' % (str(e),))
         ok = False
      self.cli_opts.filters = kwords
      return ok

   #
   def verify_cli_pairs_edit_cols(self):
      ok = True
      opts_dict = Ccp_Tool_Parser.opts_to_dict(self.cli_opts.edit_cols)
      self.cli_opts.edit_cols = opts_dict
      return ok

   #
   def verify_cli_pairs_gia_cols(self):
      ok = True
      opts_dict = Ccp_Tool_Parser.opts_to_dict(self.cli_opts.gia_cols)
      self.cli_opts.gia_cols = opts_dict
      return ok

   #
   def verify_qf_parse_synonymns(self, opts_name, keyw_name):
      if (getattr(self.cli_opts, opts_name)
          and self.cli_opts.filters.get(keyw_name)):
         log.error(
   'ERROR: Please specify only the option, %s, or the filter, %s, but not both'
            % (opts_name, keyw_name,))
         raise Exception()
      else:
         value = getattr(self.cli_opts, opts_name)
         if value is None:
            value = self.cli_opts.filters.get(keyw_name)
         # NOTE: value might just be None...
         # Set both self.cli_opts and self.cli_opts.filters.
         setattr(self.cli_opts, opts_name, value)
         self.cli_opts.filters[keyw_name] = value

   #
   def verify_qf_synonyms(self):
      ok = True
      # Check value synonyms
      try:
         #self.verify_qf_parse_synonymns('branch', 'branch_id')
         self.verify_qf_parse_synonymns('access_level', 'min_access_level')
         self.verify_qf_parse_synonymns('filter_count', 'pagin_count')
         self.verify_qf_parse_synonymns('filter_offset', 'pagin_offset')
         self.verify_qf_parse_synonymns('filter_thread_id', 'context_stack_id')
         self.verify_qf_parse_synonymns('query', 'filter_by_text_smart')
         self.verify_qf_parse_synonymns('viewport_region', 'filter_by_regions')
      except Exception, e:
         # NOTE: Something has already been said, so no need to say it.
         #log.error('Exception: "%s" / %s' % (str(e), traceback.format_exc(),))
         ok = False
      return ok

   #
   def verify_query_filters(self):
      ok = True
      # Check integer values
      try:
         # FIXME: Is this even necessary? argparse should type=int handle this.
         self.cli_opts.filter_count = int(self.cli_opts.filter_count)
         self.cli_opts.filter_offset = int(self.cli_opts.filter_offset)
         self.cli_opts.filter_thread_id = int(self.cli_opts.filter_thread_id)
      except ValueError:
         log.error('Expected integer, got something else.')
         ok = False
      # Check the access level
      access_level = None
      if self.cli_opts.access_level:
         try:
            access_level = int(self.cli_opts.access_level)
         except ValueError:
            try:
               access_level = Access_Level.get_access_level_id(
                                          self.cli_opts.access_level.lower())
            except Exception, e:
               log.error('Please specify a valid access level, not: %s.'
                         % self.cli_opts.access_level)
               log.verbose(' >> %s' % str(e))
               ok = False
      self.cli_opts.access_level = access_level
      self.cli_opts.filters['min_access_level'] = access_level
#      if self.cli_opts.access_level and (not self.cli_opts.password_skip):
#         log.error('Please use --no-password with --access_level.')
#         ok = False
      # Check the Stack IDs.
      if (self.cli_opts.only_stack_ids 
          and self.cli_opts.filters['only_stack_ids']):
         log.error('Please only specify only_stack_ids or only_stack_ids.')
         ok = False
      # Check the Thread ID.
      if ((self.cli_opts.action != 'read')
          and (self.cli_opts.filters['context_stack_id'] != 0)):
         log.error('Please only specify Thread ID with the read post action.')
         ok = False
      elif ((self.cli_opts.action == 'read')
            and (self.cli_opts.item_type == 'post')
            and (self.cli_opts.filters['context_stack_id'] == 0)):
         log.error('Please specify a Thread ID with the read post action.')
         ok = False
      # Check the Full Text Query.
      if (self.cli_opts.action == 'search'):
         if not self.cli_opts.query:
            log.error('To search, please specify a full text search query.')
            ok = False
      # else:
      #    if (self.cli_opts.query
      #        or self.cli_opts.centerx
      #        or self.cli_opts.centery
      #        ):
      #       log.error('Args query, centerx, centery are only for search.')
      #       ok = False
      # Check the Find Route operation.
      if (self.cli_opts.action == 'find_route'):
         if (not self.cli_opts.route_from
             or not self.cli_opts.route_to):
            log.error('To use find_route, please specify --from and --to.')
            ok = False
      else:
         if (self.cli_opts.route_from
             or self.cli_opts.route_to):
            log.error('The opts. --from and --to only apply to find_route.')
            ok = False
      #
      return ok

   #
   def verify_miscellany(self):
      ok = True
      # Check non-read ops.
      if self.cli_opts.action in ('create', 'update', 'delete',):
         if self.cli_opts.changenote is None:
            log.error('Please specify a changenote.')
            ok = False
      if self.cli_opts.action in ('update', 'delete',):
         # The user needs to identify the object being updated or deleted.
         # Except for branches, the user should use a stack ID or search
         # filter; for branches, the user can use the -b switch.
         if self.cli_opts.item_type == 'branch':
            if self.cli_opts.branch is None:
               log.error('Please specify a branch to update or delete.')
               log.error(
'Please use the -b switch, a stack ID, or filter_by_text_exact/_loose/_smart.')
               ok = False
         elif (((not self.cli_opts.filters['filter_by_names_exact'])
                and (not self.cli_opts.filters['filter_by_text_exact'])
                and (not self.cli_opts.filters['filter_by_text_loose'])
                and (not self.cli_opts.filters['filter_by_text_smart']))
               and (not (self.cli_opts.only_stack_ids 
                    or (self.cli_opts.filters['only_stack_ids'])))):
            log.error(
             'Please specify a stack ID or filter_by_text_exact/_loose_smart.')
            ok = False
      if 'stack_id' in self.cli_opts.edit_cols:
         log.error('Please do not specify --edit_cols "stack_id".')
         ok = False
      if 'version' in self.cli_opts.edit_cols:
         log.error('Please do not specify --edit_cols "version".')
         ok = False
      if 'deleted' in self.cli_opts.edit_cols:
         log.error('Please do not specify --edit_cols "deleted".')
         ok = False
      # Check the upload file.
      # First check if the user specified job_local_run, which tells the 
      # work_item to mark the new work_item as 'starting', which keeps the jobs
      # queue thread pool manager from processing the new item.
      if (('job_local_run' in self.cli_opts.edit_cols)
          or (self.cli_opts.sendfile)
          or ('download_fake' in self.cli_opts.edit_cols)):
         if ((self.cli_opts.action != 'create')
             or (self.cli_opts.item_type not in ('merge_job',
                                                 'merge_export_job',
                                                 'merge_import_job',
                                                 'route_analysis_job',))):
            log.error('%s%s'
                % ('The options, job_local_run, sendfile, or download_fake, ' 
                   'only work with --create --type [work item type].',))
            ok = False
         if ((self.cli_opts.sendfile)
             and ('download_fake' in self.cli_opts.edit_cols)):
            log.error(
              'Please use either --sendfile or -e download_fake but not both.')
            ok = False
      if (('publish_result' in self.cli_opts.edit_cols)
          and ('job_local_run' not in self.cli_opts.edit_cols)):
         log.error('Please use -e job_local_run with -e publish_result.')
         ok = False
      ## This is wrong: you do not specify the file if you're exporting.
      #if 'job_local_run' in self.cli_opts.edit_cols:
      #   if ((not self.cli_opts.sendfile) 
      #       and ('download_fake' not self.cli_opts.edit_cols)):
      #      log.error(
      #         'Please use --sendfile or -e download_fake with job_local_run')
      #      ok = False
      #if ((self.cli_opts.action == 'create')
      #    and (self.cli_opts.item_type == 'merge_job')):
      #   if ((not self.cli_opts.sendfile) 
      #       and ('download_fake' not in self.cli_opts.edit_cols)):
      #      # FIXME: How do you specify the type of merge? Do we need a new
      #      # item type or just a new class member? For now, the class assumes
      #      # import if a file is attached, else assumes export. Silly.
      #      log.warning('Do you mean to attach a file for the import job?')

      # BUG nnnn: Implement sendfile. See the third-party 'poster' module, as
      # urllib2 does not inherently support multi-part content.
      if self.cli_opts.sendfile:
            log.error('Oops, sorry! --sendfile is not implemented.')
            ok = False
      #
      return ok

   #
   @staticmethod
   def opts_to_dict(opts):
      #log.debug('Preparing attributes: %s' % (opts,))
      rows = {}
      for tpl in opts:
         rows[tpl[0]] = tpl[1]
      #log.debug('Prepared kvps: %s' % (rows,))
      return rows

# *** Ccp Tool class

class Ccp_Tool(Ccp_Script_Base):

   __slots__ = (
      'user_token',
      'commit_id_map',
      'session_id',
      )

   gwis_path = 'gwis'
   
   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, Ccp_Tool_Parser)
      self.user_token = None
      self.commit_id_map = dict()
      # Bug nnnn: This should be assigned by server, like user tokey.
      self.session_id = uuid.uuid4()

   # *** The command processor

   #
   def go_main(self):
      '''Processes the user command. Opens a connection to the database, makes
         the query builder, then thunks to the action handler.'''

      # # This is so caller can use --instance-worker --has-revision-lock
      # # to get around revision lock being held...
      # revision.Revision.revision_lock_dance(
      #    self.qb.db, caller='ccp.py')
      # # except that export uses GWIS, and the switches only work for
      # # direct scripts...

      # Thunk to the appropriate action handler.
      self.action_handler_thunk()
      # Close the transaction.
      self.cli_args.close_query(do_commit=False)
      #
      # This is a little hacky -- or maybe I just think everything's a little
      # hacky -- so maybe we'll just call this a little overloaded use of the
      # term 'do_create': if the user created a new job, the user can also
      # request that we run it. This makes testing jobs easier and avoids the
      # pain (well, inconvenience) of testing new job code using the jobs queue
      # (which is multi-threaded which is why debugging is a little trickier).
      try:
         if self.cli_opts.edit_cols['job_local_run']:
            job = self.run_job()
      except KeyError:
         pass

   # *** Command processor helpers

   #
   def action_handler_thunk(self):
      # Thunk to the action handler
      handler = getattr(self, 'do_' + self.cli_opts.action, None)
      g.assurt(handler is not None)
      try:
         # If we're doing GWIS and have credentials, send a hello.
         if (self.cli_opts.always_gwis) or (self.cli_opts.action != 'read'):
            self.user_token_init()
         # Now call the handler
         handler()
      except Exception, e:
         tb = ''
         #if not str(e):
         if True:
            tb = ' / %s' % traceback.format_exc()
         log.error('Well, nuts to that! Something went wrong: "%s"%s' 
                   % (str(e), tb,))

   # ** Action helpers

   #
   def query_builder_prepare(self):
      Ccp_Script_Base.query_builder_prepare(self)
      #
      self.qb.db.transaction_begin_rw()

   #
   def query_builder_prepare_qvp(self):
      req = None
      q_vp = Query_Viewport(req)
      if self.cli_opts.viewport_bbox_in:
         q_vp.parse_strs(self.cli_opts.viewport_bbox_in, 
                         self.cli_opts.viewport_bbox_ex)
         log.verbose('q_vp.viewport_bbox_in: %s / _ex: %s' 
                     % (q_vp.include, q_vp.exclude,))
      return q_vp

   #
   def query_builder_prepare_qfs(self):
      req = None
      q_fs = Query_Filters(req)
      # q_fs.ver_pickled = 1
      q_fs.pagin_total = self.cli_opts.filters['pagin_total']
      q_fs.pagin_count = self.cli_opts.filters['pagin_count']
      q_fs.pagin_offset = self.cli_opts.filters['pagin_offset']
      q_fs.centerx = self.cli_opts.centerx
      q_fs.centery = self.cli_opts.centery
      q_fs.filter_by_username = self.cli_opts.filters['filter_by_username']
      q_fs.filter_by_regions = self.cli_opts.filters['filter_by_regions']
      q_fs.filter_by_watch_geom = self.cli_opts.filters['filter_by_watch_geom']
      q_fs.filter_by_watch_item = self.cli_opts.filters['filter_by_watch_item']
      q_fs.filter_by_watch_feat = self.cli_opts.filters['filter_by_watch_feat']
      q_fs.filter_by_unread = self.cli_opts.filters['filter_by_unread']
      q_fs.filter_by_names_exact = self.cli_opts.filters[
                                 'filter_by_names_exact']
      q_fs.filter_by_text_exact = self.cli_opts.filters['filter_by_text_exact']
      q_fs.filter_by_text_loose = self.cli_opts.filters['filter_by_text_loose']
      q_fs.filter_by_text_smart = self.cli_opts.filters['filter_by_text_smart']
      g.assurt(q_fs.filter_by_text_smart == self.cli_opts.query)
      q_fs.filter_by_nearby_edits = self.cli_opts.filters[
                                 'filter_by_nearby_edits']
      q_fs.filter_by_thread_type = self.cli_opts.filters[
                                 'filter_by_thread_type']
      q_fs.filter_by_creator_include = self.cli_opts.filters[
                                 'filter_by_creator_include']
      q_fs.filter_by_creator_exclude = self.cli_opts.filters[
                                 'filter_by_creator_exclude']
      # q_fs.stack_id_table_ref
      # q_fs.stack_id_table_lhs
      # q_fs.stack_id_table_rhs
      q_fs.only_stack_ids = (self.cli_opts.only_stack_ids 
                             or self.cli_opts.filters['only_stack_ids'])
      q_fs.only_system_id = self.cli_opts.filters['only_system_id']
      q_fs.about_stack_ids = self.cli_opts.filters['about_stack_ids']
      q_fs.only_lhs_stack_ids = self.cli_opts.filters['only_lhs_stack_ids']
      q_fs.only_rhs_stack_ids = self.cli_opts.filters['only_rhs_stack_ids']
      q_fs.only_lhs_stack_id = self.cli_opts.filters['only_lhs_stack_id']
      q_fs.only_rhs_stack_id = self.cli_opts.filters['only_rhs_stack_id']
      q_fs.filter_by_value_text = self.cli_opts.filters['filter_by_value_text']
      q_fs.only_associate_ids = self.cli_opts.only_associate_ids
      q_fs.context_stack_id = self.cli_opts.filters['context_stack_id']
      q_fs.only_item_type_ids = self.cli_opts.filters['only_item_type_ids']
      # q_fs.only_lhs_item_types
      # q_fs.only_rhs_item_types
      q_fs.use_stealth_secret = self.cli_opts.filters['use_stealth_secret']
      q_fs.results_style = self.cli_opts.filters['results_style']
      q_fs.include_item_stack = self.cli_opts.filters['include_item_stack']
      q_fs.include_lhs_name = self.cli_opts.filters['include_lhs_name']
      q_fs.include_rhs_name = self.cli_opts.filters['include_rhs_name']
      # q_fs.rev_ids
      q_fs.include_geosummary = self.cli_opts.filters['include_geosummary']
      q_fs.rev_min = self.cli_opts.filters['rev_min']
      q_fs.rev_max = self.cli_opts.filters['rev_max']
      q_fs.rating_restrict = self.cli_opts.filters['rating_restrict']
      q_fs.min_access_level = self.cli_opts.filters['min_access_level']
      q_fs.max_access_level = self.cli_opts.filters['max_access_level']
      # q_fs.only_in_multi_geometry
      # q_fs.setting_multi_geometry
      # q_fs.skip_geometry_raw
      # q_fs.skip_geometry_svg
      # q_fs.skip_geometry_wkt
      # q_fs.make_geometry_ewkt
      # q_fs.gia_use_gids
      # q_fs.gia_use_sessid
      q_fs.gia_use_sessid = self.cli_opts.filters['gia_use_sessid']
      q_fs.skip_tag_counts = self.cli_opts.filters['skip_tag_counts']
      q_fs.dont_load_feat_attcs = self.cli_opts.filters['dont_load_feat_attcs']
      q_fs.do_load_lval_counts = self.cli_opts.filters['do_load_lval_counts']
      q_fs.include_item_aux = self.cli_opts.filters['include_item_aux']
      q_fs.findability_ignore = self.cli_opts.filters['findability_ignore']
      q_fs.findability_ignore_include_deleted = (
         self.cli_opts.filters['findability_ignore_include_deleted'])
      q_fs.findability_recent = self.cli_opts.filters['findability_recent']
      q_fs.do_load_latest_note = self.cli_opts.filters['do_load_latest_note']

      return q_fs

   # *** Action Do'ers

   # **** INTERACT

   #
   def do_interact(self):
      code.interact(local=locals())
      # Omit: I think Ctrl-D stops code.interact and then this assurt fires...
      #g.assurt(False) # code.interact() runs until user ^Ds.

   # **** READ

   #
   def do_read(self):
      many = None
      item_type_module = item_factory.get_item_module(self.cli_opts.item_type)
      if isinstance(item_type_module.One(), item_user_access.One):
         if not self.cli_opts.always_gwis:
            many = self.do_checkout_direct(item_type_module)
         else:
            many = self.do_checkout_remote()
      elif isinstance(item_type_module.One(), grac_record.One):
         if not self.cli_opts.always_gwis:
            many = self.do_grac_get_direct(item_type_module)
         else:
            many = self.do_grac_get_remote()
      else:
         g.assurt(False)
      return many

   #
   def do_checkout_direct(self, item_type_module):

      # FIXME: To make debugging a little easier, this fcn. calls the item 
      # search routines directly. Maybe make a new cli_opts switch to choose
      # between local and using gwis_send, so we can also test network
      # interface.

      many = item_type_module.Many()

      log.info('Created %s.Many()' % (self.cli_opts.item_type,))

      # From item/item_user_access.py, there are a number of ways to search:
      #
      #    search_by_stack_id
      #    search_for_items
      #    search_for_names
      #    search_by_internal_name
      #    search_for_geom
      #
      # maybe:
      #
      #    search_by_revision_id
      #    search_by_thread_id
      #    search_by_full_text
      #    search_by_network
      #    search_by_distance
      #    search_by_rhs_stack_id

      # This script currently supports just some of the methods.

      if self.cli_opts.allow_deleted:
         self.qb.revision.allow_deleted = True

      # FIXME: See branch_hier_enforce_branch
      #        We are not checking access to branch, i.e., I can ccp.py -r all
      #        MetC byways without using -U landonb.

      many.search_for_items_clever(self.qb)
      count = len(many)
      if count == 0:
         log.info('Nothing found of type %s!' % (self.cli_opts.item_type,))
      else:
         for one in many:
            if isinstance(one, item_base.One):
               # MAGIC_NUMBER: Print verbose item details if just a handful.
               if (count <= 5) or (self.cli_opts.verbose_details):
                  log.debug('>> %s' % (one.__str_verbose__(),))
               else:
                  log.debug('>> %s' % (one.__str_abbrev__(),))
            else:
               log.debug('>> %s' % (etree.tostring(one, pretty_print=True),))
               log.debug('>> count: %s' % (one.find('row').attrib['count'],))
         log.info('Found %d item%s!' % (count, 's' if count > 1 else '',))

      return many

   #
   def do_checkout_remote(self):
      query_dict = {
         'rqst': 'checkout',
         'ityp': self.cli_opts.item_type,
         }
      if self.cli_opts.link_attc_type:
         query_dict['atyp'] = self.cli_opts.link_attc_type
      if self.cli_opts.link_feat_type:
         query_dict['ftyp'] = self.cli_opts.link_feat_type
      gml_resp = self.gwis_send(query_dict)
      # FIXME: Process results? if gml_resp is not None: ...?
      many = []
      return many

   #
   def do_grac_get_direct(self, item_type_module):

      many = item_type_module.Many()

      log.info('Created %s.Many()' % (self.cli_opts.item_type,))

      many.search_by_context(self.cli_opts.grac_context, self.qb)

      count = len(many)
      if count == 0:
         log.info('Nothing found for type %s context %s!' 
                  % (self.cli_opts.item_type, self.cli_opts.grac_context,))
      else:
         for one in many:
            log.debug('>> %s' % (one,))
         log.info('Found %d item%s!' % (count, 's' if count > 1 else '',))

      return many

   #
   def do_grac_get_remote(self):
      query_dict = {
         'rqst': 'grac_get',
         'control_type': self.cli_opts.item_type,
         'control_context': self.cli_opts.grac_context,
         }
      gml_resp = self.gwis_send(query_dict)
      #
      many = []
      return many


   # **** CREATE

   #
   def do_create(self):
      self.cli_opts.edit_cols['stack_id'] = -1
      self.cli_opts.edit_cols['version'] = 0
      self.cli_opts.edit_cols['deleted'] = False
      self.gwis_commit()

   # **** UPDATE

   #
   def do_update(self):
      the_item = self.do_update_or_delete_get_item(set_deleted=False)

   # **** DELETE

   #
   def do_delete(self):
      the_item = self.do_update_or_delete_get_item(set_deleted=True)

   #
   def do_update_or_delete_get_item(self, set_deleted):
      ok = True
      if self.qb.filters.only_stack_ids:
         # only_stacks_ids is a str, and we only update or delete one item
         # at a time via ccp.py, so see that the user specifies just one ID.
         try:
            self.qb.filters.only_stack_ids = [int(
                  self.qb.filters.only_stack_ids,)]
         except ValueError, e:
            log.error('Expecting just one stack_id from --only_stack_ids.')
            ok = False
      if self.qb.filters.only_system_id:
         if self.qb.filters.only_stack_ids:
            log.error('Not expecting only_stack_ids and only_system_id.')
            ok = False
         else:
            try:
               self.qb.filters.only_system_id = int(
                     self.qb.filters.only_system_id)
            except ValueError, e:
               log.error('Not an int: only_system_id.')
               ok = False
      if ok:
         many = self.do_read()
         if len(many) > 1:
            log.warning('too many items found! please refine your name search')
         elif len(many) == 1:
            the_item = many[0]
            self.cli_opts.edit_cols['stack_id'] = the_item.stack_id
            self.cli_opts.edit_cols['version'] = the_item.version
            self.cli_opts.edit_cols['deleted'] = set_deleted
            # Need this?: self.cli_opts.edit_cols['reverted'] = set_reverted
            self.gwis_commit()
         else:
            if self.qb.filters.filter_by_names_exact:
               log.warning('item not found by exact names: %s' 
                           % (self.qb.filters.filter_by_names_exact,))
            if self.qb.filters.filter_by_text_exact:
               log.warning('item not found by exact term: %s' 
                           % (self.qb.filters.filter_by_text_exact,))
            if self.qb.filters.filter_by_text_loose:
               log.warning('item not found by loose term: %s' 
                           % (self.qb.filters.filter_by_text_loose,))
            if self.qb.filters.filter_by_text_smart:
               log.warning('item not found by smart term: %s' 
                           % (self.qb.filters.filter_by_text_smart,))
            if self.qb.filters.only_stack_ids:
               log.warning('item not found by stack ID: %d' 
                           % (self.qb.filters.only_stack_ids[0],))
            if self.qb.filters.only_system_id:
               log.warning('item not found by system ID: %d' 
                           % (self.qb.filters.only_system_id,))

   # **** KEY-VALUE PAIR

   #
   def do_key_val(self):
      if not self.cli_opts.always_gwis:
         kval_keys = ','.join([("'%s'" % x) for x in self.cli_opts.kval_keys])
         sql_kval = ("SELECT key, value FROM key_value_pair WHERE key IN (%s)"
                     % (kval_keys,))
         rows = self.qb.db.sql(sql_kval)
         log.info('==========================================================')
         if rows:
            for row in rows:
               log.info('Key Value: %s = "%s"' % (row['key'], row['value'],))
         else:
            log.info('Key Value: Nothing found for key(s): %s'
                     % (kval_keys,))
         log.info('==========================================================')
      else:
         kval_keys = ','.join([("%s" % x) for x in self.cli_opts.kval_keys])
         query_dict = {
            'rqst': 'kval_get',
            'vkey': kval_keys,
            }
         gml_resp = self.gwis_send(query_dict)

   # **** SEARCH

   #
   def do_search(self):
      # FIXME: Local search -- does -G work to force using gwis?
      s = search_map.Search_Map(self.qb)
      results = s.search()
      count_grp = len(results)
      log.debug('')
      log.debug('=========================================================')
      log.debug('========================== found %d result(s)' % (count_grp,))
      log.debug('')
      if count_grp > 0:
         count_itm = 0
         for one in results:
            log.debug('>> %s' % (one.__str__verbose__(),))
            count_itm += len(one.result_gfs)
         log.debug('')
         log.debug('=========================================================')
         log.info('Found %d group%s! (%d item%s)'
                  % (count_grp, 's' if count_grp > 1 else '',
                     count_itm, 's' if count_itm > 1 else '',))
         log.debug('')
      else:
         log.info('Search found nothing!')

   # **** FIND-ROUTE

   #
   def do_find_route(self):
      geocode_resp = self.gwis_geocode(
         self.cli_opts.route_from, 
         self.cli_opts.route_to)
      if geocode_resp is not None:
         self.gwis_route_get(geocode_resp)

   # *** GWIS Login Spoof

   #
   def user_token_init(self):
      self.user_token = None
      if self.cli_opts.username != conf.anonymous_username:
         log.info('Getting token for user: %s.' % (self.cli_opts.username,))
         self.user_token = self.gwis_login()
         log.info('User %s was %sauthenticated.' 
                  % (self.cli_opts.username, 
                     ('_not_ ' if not self.user_token else ''),))
         log.debug('User token: %s' % (self.user_token,))
         if not self.user_token:
            # FIXME: Should there be a --force opt to skip raising and allow
            # the GWIS command to be sent?
            raise Exception('Not authed!')

   # *** GWIS Helpers

   #
   def gwis_url(self, query_dict, is_gwis_login=False):
      # NOTE: body=yes is for debugging the NoneType bug.
      g.assurt('rqst' in query_dict)
      g.assurt('brid' not in query_dict)
      g.assurt('rev' not in query_dict)
      # SYNC_ME: Search: GWIS kvp.
      query_dict.update(
         {'body': 'yes',
          'gwv': conf.gwis_version,
          'sessid': self.session_id,
          })
      if not is_gwis_login:
         rev = self.qb.revision.gwis_postfix()
         # Add the query filters stuff in the URL. We can ignore username here,
         # since it goes in the metadata.
         if self.qb.branch_hier:
            query_dict['brid'] = self.qb.branch_hier[0][0]
         # else, MAYBE: We cannot get the branch list via GWIS from ccp.py.
         #              pyserver doesn't understand the meaning of '-1',
         #              and ccp.py does not send the item_names_get command.
         # FIXME: We should probably implement the other gwis cmds in ccp.py.
         if rev:
            query_dict['rev'] = rev
      # NOTE: Skipping: browid, sessid
      # Assemble the URL. But make sure rqst= comes first, for apache2sql.py.
      gwis_rqst = query_dict['rqst']
      query_str = urllib.urlencode({'rqst': query_dict['rqst'],})
      del query_dict['rqst']
      query_str += '&' + urllib.urlencode(query_dict)
      query_dict['rqst'] = gwis_rqst
      # 2012.09.24: This had been 'localhost' by default... but none of the
      # scripts set it... so how has this been working up until now?
      domain_port = self.cli_opts.pyserver_host
      if not domain_port:
         domain_port = conf.server_name
      port_num = self.cli_opts.pyserver_port
      if not port_num:
         port_num = conf.server_port
      domain_port += ':' + str(port_num)
      url = 'http://%s/%s?%s' % (domain_port, Ccp_Tool.gwis_path, query_str,)
      if not is_gwis_login:
         # Add the query filters.
         url = self.qb.filters.url_append_filters(url)
         # Add the viewport bounding box.
         url = self.qb.viewport.url_append_bboxes(url)
      #
      if not self.cli_opts.log_cleanly:
         log.debug('gwis_url: \n=======\n%s\n=======' % (url,))
      return url

   #
   def gml_metadata(self):
      sending_pass = False
      gml_metadata = None
      if self.cli_opts.username != conf.anonymous_username:
         # You can test the user__token infrastructure here.
         # Put a break here:
         #   conf.break_here()
         # Then run this script:
         #   pyserver$ ./ccp.py -G -r -t branch -U landonb --no-password
         # First time here, it's before gwis_hello, so just continue.
         #   continue
         # Second time through, change self.user_token. You could use
         # gibberish, or you could try other tokens from the table,
         # both expired and not, and other users' and not.
         # Try also: try: DELETE FROM user__token WHERE username = 'landonb';
         #  to make sure that a user without any user__token rows is also
         #  tested.
         if self.user_token:
            gml_metadata = self.gml_metadata_assemble('token', self.user_token)
         elif self.cli_opts.password:
            gml_metadata = self.gml_metadata_assemble('pass', 
                                                      self.cli_opts.password)
            sending_pass = True
         elif self.cli_opts.password_skip:
            gml_metadata = self.gml_metadata_assemble(None, None)
         else:
            log.warning('Warning: sending username but no credentials!')
      if gml_metadata is None:
         gml_metadata = etree.Element('metadata')
      if not sending_pass:
         if self.cli_opts.changenote is not None:
            gml_changenote = etree.Element('changenote')
            gml_changenote.text = self.cli_opts.changenote
            gml_metadata.append(gml_changenote)
         if self.cli_opts.filters['request_is_a_test'] is not None:
            misc.xa_set(gml_metadata, 'request_is_a_test', 
                        self.cli_opts.filters['request_is_a_test'])
      return gml_metadata

   #
   def gml_metadata_assemble(self, credential_key, credential_value):
      # Assemble the metadata xml. The following code is effectively
      # the same as:
      #    gml_s = (
      #       '<metadata><user name="%s" %s="%s"/></metadata>'
      #       % (self.cli_opts.username, credential_key, credential_value,))
      # BUG nnnn: Stop sending username since we can get from token.
      gml_user = etree.Element('user')
      g.assurt(self.cli_opts.username != conf.anonymous_username)
      misc.xa_set(gml_user, 'name', self.cli_opts.username)
      if credential_key:
         misc.xa_set(gml_user, credential_key, credential_value)
      if self.cli_opts.password_skip:
         misc.xa_set(gml_user, 'ssec', conf.gwis_shared_secret)
      gml_metadata = etree.Element('metadata')
      gml_metadata.append(gml_user)
      return gml_metadata

   #
   def gml_data(self, gml_docs=[]):
      gml_data = etree.Element('data')
      gml_metadata = self.gml_metadata()
      if gml_metadata is not None:
         gml_data.append(gml_metadata)
      for doc in gml_docs:
         gml_data.append(doc)
      self.qb.filters.xml_append_filters(gml_data)
      gml_s = etree.tostring(gml_data, pretty_print=True)
      if not self.cli_opts.log_cleanly:
         log.debug('gml_data: \n=======\n%s=======' % (gml_s,))
      #
      return gml_s

   #
   def gwis_send(self, query_dict, gml_docs=[], is_gwis_login=False):
      as_xml = None
      try:
         # Build the query string.
         url = self.gwis_url(query_dict, is_gwis_login)
         # Build the gml content body.
         gml_s = self.gml_data(gml_docs)
         # Make the HTTP request object
         # FIXME: Add upload file: self.cli_opts.sendfile
         req = urllib2.Request(url)
         req.add_data(gml_s)
         # Defaults 'application/x-www-form-urlencoded' but we want 'text/xml'.
         req.add_header('Content-Type', 'text/xml')
         # Open connection.
         #log.debug('Connecting to:   %s' % (req.get_full_url(),))
         #log.debug('      Sending:   %s' % (req.get_data(),))
         log.info('Sending request...')
         the_page = misc.urllib2_urlopen_readall(req)
         # FIXME: ccp.py doesn't actually parse the GWIS/XML... so no item
         # count.
         if the_page.startswith('<'):
            as_xml = etree.XML(the_page)
            if not self.cli_opts.log_cleanly:
               log.info('gwis_resp: \n=======\n%s=======' 
                        % (etree.tostring(as_xml, pretty_print=True),))
            if as_xml.tag == 'gwis_error':
               log.error('Error from pyserver: %s.' % (as_xml.get('msg'),))
               as_xml = None
            elif as_xml.tag == 'gwis_fatal':
               log.error('Fatal from pyserver: %s.' % (as_xml.get('msg'),))
               as_xml = None
         else:
            log.info('gwis_resp: not XML: length: %d' % (len(the_page),))
         log.info('gwis_resp: %d bytes (%.2f Kb)' 
                  % (len(the_page), len(the_page)/1024.0,))
      except urllib2.HTTPError, e:
         log.error('gwis_send failed! Exception (%s): "%s"' 
                   % (type(e), str(e),))
      except Exception, e:
         tb = ''
         #if not str(e):
         if True:
            tb = ' / %s' % traceback.format_exc()
         log.error('gwis_send failed! Exception (%s): "%s"%s' 
                   % (type(e), str(e), tb,))
      return as_xml

   # *** GWIS Commands

   # FIXME: add gwis_logout/user_goodbye so we can delete our tokens from the 
   #        user__token table...

   #
   def gwis_login(self):
      gml_docs = []
      is_gwis_login = True
      gml_resp = self.gwis_send(
         {'rqst': 'user_hello',}, gml_docs, is_gwis_login)
      # Get the token
      # NOTE: gml_resp may be None, or 'token' may not exist
      try:
         token = gml_resp.find('token').text
      except AttributeError:
         token = None
      return token

   #
   def gwis_commit(self):
      # See commit.py for an example of this XML.
      gml_docs = list()

      # Attach empty ratings and watchers documents
      # FIXME: You can probably delete these which are becoming Nonwiki items.
      gml_docs.append(etree.Element('ratings'))
      gml_docs.append(etree.Element('watchers'))

      # Attach the items document
      doc_items = etree.Element('items')
      # The GWIS GML XML uses abbreviations now. So this is the old way:
      #  doc_item = etree.Element(self.cli_opts.item_type)
      #  for k,v in self.cli_opts.edit_cols.iteritems():
      #     misc.xa_set(doc_item, k, v)
      #  doc_items.append(doc_item)
      # Now it's:
      item_module = item_factory.get_item_module(self.cli_opts.item_type)
      item = item_module.One(qb=self.qb, row=self.cli_opts.edit_cols)
      # include_input_only_attrs means pyserver includes column in the xml
      # output that it does not send to flashclient, because they are input
      # vars.
      item.append_gml(elem=doc_items, need_digest=False, 
                      include_input_only_attrs=True)
      gml_docs.append(doc_items)

      # Attach the accesses document
      if self.cli_opts.gia_cols:
         # MAYBE: We currently only support one gia record per ccp request.
         accesses_doc = etree.Element('accesses')
         gia_doc = etree.Element('item')
         misc.xa_set(gia_doc, 'stid', item.stack_id)
         gia = group_item_access.One(qb=self.qb, row=self.cli_opts.gia_cols)
         gia.append_gml(elem=gia_doc, need_digest=False, 
                        include_input_only_attrs=True)
         accesses_doc.append(gia_doc)
         gml_docs.append(accesses_doc)

      # Send the commit command
      gml_resp = self.gwis_send({'rqst': 'commit',}, gml_docs)

      # Process results.
      g.assurt(not self.commit_id_map)
      if gml_resp is not None:
         # <result><id_map cli_id='' new_id=''/>...</result>
         # These next few lines feel ripe for a utility routine.
         # Use a double-slash to get down one level.
         id_maps = gml_resp.findall('.//id_map')
         for id_map in id_maps:
            cli_id = str(id_map.get('cli_id'))
            new_id = int(id_map.get('new_id'))
            new_vers = int(id_map.get('new_vers'))
            new_ssid = int(id_map.get('new_ssid'))
            log.debug('Item "%s" saved with stack_id: %d vers: %d new_ssid: %d'
                      % (cli_id, new_id, new_vers, new_ssid,))
            self.commit_id_map[cli_id] = new_id
      else:
         log.warning('gwis_commit: No response?')

      return

   # *** Find route commands

   #
   def gwis_geocode(self, route_from, route_to):
      ''' E.g.,
      <data>
         <metadata/>
         <addrs>
            <addr addr_line="gateway fountain"/>
            <addr addr_line="700 nicollet, mpls"/>
         </addrs>
      </data>
      '''

      do_geocode = False
      doc_addrs = etree.Element('addrs')
      try:
         beg_nid = int(route_from)
      except ValueError:
         beg_nid = None
      if not beg_nid:
         doc_beg_addr = etree.Element('addr')
         misc.xa_set(doc_beg_addr, 'addr_line', route_from)
         doc_addrs.append(doc_beg_addr)
         do_geocode = True
      try:
         fin_nid = int(route_to)
      except ValueError:
         fin_nid = None
      if not fin_nid:
         doc_fin_addr = etree.Element('addr')
         misc.xa_set(doc_fin_addr, 'addr_line', route_to)
         doc_addrs.append(doc_fin_addr)
         do_geocode = True

      if do_geocode:
         gml_docs = list()
         gml_docs.append(doc_addrs)
         gml_resp = self.gwis_send({'rqst': 'geocode',}, gml_docs)

      else:
         gml_resp = etree.Element('data')

      node_not_found = False
      if beg_nid:
         node_not_found |= self.gwis_geocode_add_node_by_id(gml_resp, beg_nid)
      if fin_nid:
         node_not_found |= self.gwis_geocode_add_node_by_id(gml_resp, fin_nid)

      if node_not_found:
         gml_resp = None

      return gml_resp

   #
   def gwis_geocode_add_node_by_id(self, gml_resp, node_sid):

      if node_sid:
         nd_endpt = node_endpoint.Many.node_endpoint_get(
                           self.qb, node_sid, pt_xy=None)
         if nd_endpt is not None:
            addr_resp = etree.Element('addr')
            addr_x, addr_y = geometry.wkt_point_to_xy(nd_endpt.endpoint_wkt)
            misc.xa_set(addr_resp, 'addr', str(node_sid))
            misc.xa_set(addr_resp, 'x', addr_x)
            misc.xa_set(addr_resp, 'y', addr_y)
            gml_resp.append(addr_resp)
         node_not_found = True
      else:
         log.warning('No node found for node ID: %d' % (node_sid,))
         node_not_found = False

      return node_not_found

   #
   def gwis_route_get(self, geocode_resp):

      gml_docs = []
      preferences = self.gwis_route_get_prefs()
      gml_docs.append(preferences)

      #travel_mode = Travel_Mode.wayward
      travel_mode = Travel_Mode.bicycle
      if self.cli_opts.planner_p3:
         travel_mode = Travel_Mode.wayward
      elif self.cli_opts.planner_p2:
         travel_mode = Travel_Mode.transit
      elif self.cli_opts.planner_p1:
         # Nope: travel_mode = Travel_Mode.bicycle
         travel_mode = Travel_Mode.classic

      addrs = geocode_resp.findall('./addr/addr')

      route_req = {
         'rqst': 'route_get',
         'beg_addr': addrs[0].get('text'),
         'beg_ptx': addrs[0].get('x'),
         'beg_pty': addrs[0].get('y'),
         'fin_addr': addrs[1].get('text'),
         'fin_ptx': addrs[1].get('x'),
         'fin_pty': addrs[1].get('y'),
         # Travel_Mode signals to pyserver which route finder to call.
         'travel_mode': str(travel_mode),
         # BUG nnnn: Implement remaining p2 options:
         'p2_depart': None, # For busing/lightrailing/commutertraining.
         'p2_txpref': 0, # More biking/More busing.
         # The source is saved to the route table; just for DEVs.
         'source': 'ccp.py',
         'dont_save': not self.cli_opts.route_do_save,
         # We could also make a switch for this, for testing...
         'asgpx': '0',
         }

      route_resp = self.gwis_send(route_req, gml_docs)

      if route_resp is not None:
         self.gwis_route_get_process(route_resp)
      else:
         log.info('Find-Route found nothing!')

   #
   def gwis_route_get_prefs(self):

      preferences = etree.Element('preferences')

      # Planner p1 options.
      # EXPLAIN: These are the preferences saved to the user table and
      #          are used as defaults in the client route finder, and
      #          route_get complains if 'preferences' isn't in the XML
      #          request, but: does the finder use these? I think it
      #          uses the same-named values sent in the URI instead.
      # These two are retrieved in route_get.py:
      if self.cli_opts.p1_priority is not None:
         misc.xa_set(preferences, 'p1_priority', self.cli_opts.p1_priority)
      #misc.xa_set(preferences, '[k]', [sid,sid,]) # Tag prefs...
      # Skipping: Just part of saveable user preferences:
      # Planner p2 options.
      # Skipping: Just part of saveable user preferences:
      #              rf_p2_transit_pref
      # Planner p3 options.
      # In prefs as: rf_p3_weight_type
      #              rf_p3_rating_pump
      #              rf_p3_burden_pump
      #              rf_p3_spalgorithm
      # but in GWIS route request as abbreviations... just to be difficult.
      if self.cli_opts.p3_weight:
         try:
            weight_type = routed_p3.tgraph.Trans_Graph.weight_type_lookup[
                                                   self.cli_opts.p3_weight]
         except KeyError:
            weight_type = self.cli_opts.p3_weight
         misc.xa_set(preferences, 'p3_wgt', weight_type)
      if self.cli_opts.p3_spread:
         misc.xa_set(preferences, 'p3_rgi', self.cli_opts.p3_spread)
      if self.cli_opts.p3_burden:
         misc.xa_set(preferences, 'p3_bdn', self.cli_opts.p3_burden)
      if self.cli_opts.p3_algorithm:
         try:
            path_algorithm = routed_p3.tgraph.Trans_Graph.algorithm_lookup[
                                                self.cli_opts.p3_algorithm]
         except KeyError:
            path_algorithm = self.cli_opts.p3_algorithm
         misc.xa_set(preferences, 'p3_alg', path_algorithm)
      # Personalized route options.
      # Skipping: rating_min, tagprefs
      misc.xa_set(preferences, 'use_defaults', 'true') # tags_use_defaults

      return preferences

   #
   def gwis_route_get_process(self, route_resp):
      #log.debug('Found a route: %s' % (etree.tostring(route_resp),))
      route_doc = route_resp.find('route')
      steps_docs = route_resp.findall('.//step')
      try:
         meters_in_one_mile = 1609.34
         total_mtres = float(route_doc.get('rsn_len'))
         total_kliks = total_mtres / 1000.0
         total_miles = total_mtres / meters_in_one_mile
      except:
         total_kliks = -1
         total_miles = -1
      try:
         avg_cost = float(route_doc.get('avg_cost'))
      except:
         avg_cost = -1
      log.info('=======================================================')
      log.info('Found the route: "%s"' % (route_doc.get('name'),))
      log.info('.... route_from: "%s"' % (self.cli_opts.route_from,))
      log.info('.... -geocoded-: "%s"' % (route_doc.get('beg_addr'),))
      log.info('.... route_dest: "%s"' % (self.cli_opts.route_to,))
      log.info('.... -geocoded-: "%s"' % (route_doc.get('fin_addr'),))
      log.info('......... stats: %d steps / %.2f km (%.2f mi) / %.2f avg cost'
               % (len(steps_docs), total_kliks, total_miles, avg_cost,))
      log.info('....... planner: %s'
               % ('p1' if self.cli_opts.planner_p1
                   else 'p2' if self.cli_opts.planner_p2
                    else 'p3' if self.cli_opts.planner_p3
                     else 'p?',))
      log.info('... p1_priority: %s' % (self.cli_opts.p1_priority,))
      log.info('..... p3_weight: %s' % (self.cli_opts.p3_weight,))
      log.info('..... p3_spread: %s' % (self.cli_opts.p3_spread,))
      log.info('..... p3_burden: %s' % (self.cli_opts.p3_burden,))
      log.info('..... p3_algorm: %s' % (self.cli_opts.p3_algorithm,))
      log.info('... rte_do_save: %s' % (self.cli_opts.route_do_save,))
      log.info('=======================================================')

# *** Work item commands

   #
   def run_job(self):
      job = None
      g.assurt(self.cli_opts.edit_cols['job_local_run'])
      if len(self.commit_id_map) > 0:
         g.assurt(len(self.commit_id_map) == 1)
         stack_id = self.commit_id_map['-1']
         g.assurt(stack_id > 0)
         # Get a new qb but not the lock: mr_do assumes the work_item is stale
         # and will refresh it and get a row-level lock on it.
         qb = self.cli_args.begin_query()
         g.assurt(not qb.request_lock_for_share)
         g.assurt(not qb.request_lock_for_update)
         jobs_module = item_factory.get_item_module(self.cli_opts.item_type)
         jobs = jobs_module.Many() # i.e., merge_job or route_analysis_job
         jobs.search_by_stack_id(stack_id, qb)
         g.assurt(len(jobs) == 1)
         job = jobs[0]
         g.assurt(job.latest_step.status_text == 'starting')
         log.debug('Creating mock Mr_Do and processing new job: %s.' % (job,))
         mr_do = Mr_Do()
         mr_do.jobs_thread.keep_running.set()
         mr_do.job_callback_process(job)
         self.cli_args.close_query(do_commit=False)
         # Refresh the job.
         qb = self.cli_args.begin_query()
         jobs = jobs_module.Many() # i.e., merge_job or route_analysis_job
         jobs.search_by_stack_id(stack_id, qb)
         self.cli_args.close_query(do_commit=False)
         g.assurt(len(jobs) == 1)
         job = jobs[0]
         #
         # If the caller wants us to publish, publish. Note that the job, when
         # we first retrieved it, didn't have a results location, so we have to
         # refresh the item.
         # MEH: pyserver sends local_file_guid in the GWIS response for only
         #      this feature. Which means pyserver always sends the guid to
         #      flashclient.
         if job.latest_step.status_code != Job_Status.lookup_val['complete']:
            log_f = log.error if not self.cli_opts.ignore_job_fail else log.info
            log_f('run_job: job failed: %s' % (str(job),))
         elif self.cli_opts.edit_cols['publish_result']:
            publish_path = self.cli_opts.edit_cols['publish_result']
            publish_dir = os.path.dirname(publish_path)
            publish_file = os.path.basename(publish_path)
            if not os.path.exists(publish_dir):
               try:
                  os.mkdir(publish_dir)
                  #os.chmod(publish_dir, 2775)
                  #os.chmod(publish_dir, 0775)
                  os.chmod(publish_dir, 02775)
               except OSError, e:
                  log.error('run_job: cannot mkdir: %s' % (publish_dir,))
                  raise
            # if exists(os.path.exists(publish_path)):
            #    msg = ('run_job: file exists and we are not destructive: %s'
            #           % (publish_path,))
            #    log.error(msg)
            #    raise Exception(msg)
            oname = '%s.fin' % (job.local_file_guid,)
            zbase = '%s.zip' % (job.get_zipname(),)
            source_path = os.path.join(conf.shapefile_directory, oname, zbase)
            log.debug('run_job: copying %s to %s'
                      % (source_path, publish_path,))
            shutil.copy(source_path, publish_path)
            # os.chmod(publish_path, 0664)
            os.chmod(publish_path,   stat.S_IRUSR | stat.S_IWUSR 
                                   | stat.S_IRGRP | stat.S_IWGRP 
                                   | stat.S_IROTH )

# FIXME: The job is wasting space on the hard drive and shows up in the branch
#        managers' work item lists, so delete it and remove from the hard
#        drive.
# BUG nnnn/FIXME: Does deleting work items from flashclient delete from disk?

         # else, job succeeded, and caller didn't ask to publish.
      else:
         # len(self.commit_id_map) == 1, i.e., gwis_commit failed.
         log.warning('run_job: it appears gwis_commit failed. Doing nothing!')
      return job

# *** main()

if (__name__ == '__main__'):
   '''Cyclopath Developer Command Line Tool'''
   tool = Ccp_Tool()
   tool.go()

#import sys
#sys.exit(0)

"""

THIS IS OLD:
py ccp.py -c -t branch \
      -p name "Ramsey Cty" \
      -p parent_id 2359963 \
      -m "New Branch"
      -U landonb -P xxxxxx
THE NEW WAY:
re ; ./ccp.py -c -t branch -e name "Metc Bikeways 2011" -f request_is_a_test 1 -m "New Bikeways 2011 Branch" -U landonb --no-password

./ccp.py -r -t route -f only_system_id 375513

./ccp.py -r -t route -f only_system_id 3838612


"""


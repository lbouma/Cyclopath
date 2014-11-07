# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

from decimal import Decimal
import logging
import logging.config
import os
import sys
import uuid

# 'tis us: import conf
import g

from ConfigParser import NoOptionError
from util_ import logging2
from util_ import mem_usage
from util_ import RawConfigParser2

##
## CONFIGURABLE AND INSTANCE-SPECIFIC VALUES, FROM ./CONFIG ##
##

# NOTE: This file assumes that the pyserver root is the current directory.

# This hack is to decide whether we are local or the pyserver (running under
# mod_python).  We can only load the apache module in the latter case; see
# http://www.modpython.org/live/current/doc-html/module-apache.html
try:
   from mod_python import apache
   not_apache_parent = False
except ImportError:
   not_apache_parent = True

# Use our custom config file parser
cf = RawConfigParser2.RawConfigParser2()
cf.read('CONFIG')

os.umask(0007)

### User config.
#
# See the file CONFIG.template for explanations of these parameters. (Don't
# document them here.)
#
# Also, be careful with parameter types -- the default is string; if you want
# something else, you must be specific. If you get this wrong, conf.py won't
# care, and the problems will show up elsewhere.

## Section: [gwis]

gwis_version = cf.get('gwis', 'protocol_version')

dump_dir = cf.get('gwis', 'dump_dir')
dump_requests = cf.getboolean('gwis', 'dump_requests')
dump_responses = cf.getboolean('gwis', 'dump_responses')

gwis_shared_secret = cf.get('gwis', 'shared_secret')

## Section: [db]

db_host = cf.get('db', 'host')
# 2013.07.08: The default Postgres port is 5432; PgBouncer runs on 6432.
db_port = cf.getint('db', 'port', 5432)
db_user = cf.get('db', 'user')
# Config file can be overridden by PYSERVER_DB environment variable. This is
# useful for analysis scripts.
# 2012.12.01: Using PYSERVER_DB is somewhat deprecated. Most scripts use -D.
try:
   db_name = os.environ['PYSERVER_DB']
   sys.stderr.write("Unexpected: os.environ['PYSERVER_DB']: %s"
                    % (os.environ['PYSERVER_DB'],))
   # This is no longer acceptable. Now use CONFIG.database or CLI --database.
   # We don't need to assert (we could just get from CONFIG) but [lb] wants
   # to make sure no one is expecting this env. var. to work.
   assert(False)
except KeyError:
   db_name = cf.get('db', 'database')
db_password = cf.get('db', 'password')
db_owner = cf.get('db', 'owner')
db_owner_pass = cf.get('db', 'owner_pass')

# *** Installation directory

# Via apache, os.environ['PYSERVER_HOME'] is not set, but we can use curdir.
g.assurt(os.getcwd().endswith('pyserver'))
# This extracts the parent directory name, e.g., from
# '/ccp/dev/cp/pyserver', we get 'cp_2628', because a symlink was resolved.
ccp_dev_path = os.path.basename(os.path.dirname(os.path.realpath(os.getcwd())))
g.assurt(ccp_dev_path)

# *** List of Instances

instance_prefix = 'instance_'

server_instances = []
for conf_section in cf.sections():
   if conf_section.startswith(instance_prefix):
      server_instances.append(conf_section[len(instance_prefix):])

# *** Section: [instance_*]

if not_apache_parent:
   instance_raw = os.environ.get('INSTANCE')
else:
   # In the apache conf, the PythonInterpreter is, e.g., minnesota___greatermn
   instance_raw = apache.interpreter
uniquely_starts = instance_raw.find('___')
if uniquely_starts != -1:
   instance_name = instance_raw[:uniquely_starts]
else:
   instance_name = instance_raw
assert(instance_name is not None) # set using INSTANCE environment variable

instance_conf = instance_prefix + instance_name
assert(cf.has_section(instance_conf))

# Instance-specific Server settings.
# Bug 2713: 2012.08.16: Allow for more than one server name, but assume the 
#           first one in the list is the preferred name.
server_names = cf.getlist(instance_conf, 'server_names')
server_name = server_names[0]
server_ip = cf.get(instance_conf, 'server_ip')
server_port = cf.getint(instance_conf, 'server_port')
db_timezone = cf.get(instance_conf, 'timezone')

#
def break_here(restrict_machine=None):
   if ((not restrict_machine) or (restrict_machine in server_names)):
      # The parent process ID seems to be one for the route daemon...
      # 2014.05.08: Not working again for route daemon, getting pdb instead.
      use_pdb = not_apache_parent and (os.getppid() != 1)
      g.log.warning('===============================================')
      g.log.warning('     WAITING ON %s PYTHON DEBUGGER...'
                    % ('LOCAL' if use_pdb else 'LOCAL',))
      g.log.warning('===============================================')
      if use_pdb:
         import pdb;pdb.set_trace()
      else:
         import rpdb2
         rpdb2.start_embedded_debugger('password', fAllowRemote=True)

# DEPRECATED: We've replaced state and state_aliases with geocoderish names.
# NOTE: The Cyclopath software is not geo-restricted, e.g., to just Minnesota.
#       But we still encode some assumptions about the geographic location that
#       the map covers. This helps us, e.g., not require the user to enter a
#       State name when searching for an address. Also, historically, we've
#       excluded search results that lie more than some number of meters, like
#       30 KM, outside of branch.coverage_area, but for Statewide, we want to
#       include results in bordering states (otherwise we'll look silly if,
#       e.g., a user searches "fort francis, ontario", and we don't show any
#       results).
# An admin district is a state or province and its abbreviation,
# e.g., "MN, Minnesota"
admin_district_primary = cf.getlist(instance_conf, 'admin_district_primary',
                                    default=list())
for name_or_abbrev in admin_district_primary:
   # MAGIC_NUMBER: U.S. state & Canadian province abbrevs are two characters.
   if len(name_or_abbrev) == 2:
      admin_district_abbrev = name_or_abbrev
      break
# We can use branch.coverage_area to help choose geocoded search results to
# show, but we can also check the state indicated in the results. This is,
# e.g., "SD, South Dakota, ND, North Dakota, WI, Wisconsin, IA, Iowa, ...".
# We'll include search results that are in bordering states, but we'll rank
# them lower.
admin_districts_nearby = cf.getlist(instance_conf, 'admin_districts_nearby',
                                    default=list())
# Convert from list to set so lookups are faster.
admin_districts_nearby = set(admin_districts_nearby)
admin_districts_ok = admin_districts_nearby.union(set(admin_district_primary))
# This is the default country; currently, this value is ignored...
country_region_primary = cf.get(instance_conf, 'country_region_primary', 
                                default='United States')
# These are the old CONFIG names:
if not admin_district_primary:
   state = cf.get(instance_conf, 'state')
   state_aliases = cf.getlist(instance_conf, 'state_aliases')
   admin_district_primary = [state,] + state_aliases

# Spatial reference system ID for this instance
default_srid = cf.getint(instance_conf, 'srid')

# The node_precision and node_tolerance are used for determining network 
# connectivity.
# SYNC_ME: db_fetch_precision and node_precision/node_tolerance
# MAYBE: Is 1 centimeter too much? Maybe a decimeter?
#node_tolerance = Decimal('.01') # 1 centimeter
node_precision = 1 # I.e., 0.1 meters, or 1 decimeter.
node_tolerance = Decimal('0.%s1' % ('0' * (node_precision - 1)),)
# The nodes used to (still do) use Decimal, which doesn't round quite
# like round. So all twice the precision when comparing for equality.
#node_threshold = pow(0.1, node_precision) * 1.1
node_threshold = pow(0.1, node_precision) * 2.1
# The geom_precision is used for storing geometries and postgis calculations
# (that aren't network node related).
geom_precision = 6 # I.e., 0.000001 meters.
# Set the tolerance, i.e., Decimal('0.000001')
geom_tolerance = Decimal('0.%s1' % ('0' * (geom_precision - 1)),)
#geom_threshold = pow(0.1, geom_precision) * 1.1
# Hrmm... what should elevation be good 'to?
elev_precision = 2
elev_tolerance = Decimal('0.%s1' % ('0' * (elev_precision - 1)),)
elev_threshold = pow(0.1, elev_precision) * 1.1
#
mval_precision = 4
mval_tolerance = Decimal('0.%s1' % ('0' * (mval_precision - 1)),)
#mval_threshold = pow(0.1, mval_precision) * 1.1

# Instance-specific Routed settings.
starting_routed_port = cf.getint(instance_conf, 'starting_routed_port')
maximum_routed_ports = cf.getint(instance_conf, 'maximum_routed_ports')
routed_async_limit = cf.getint(instance_conf, 'routed_async_limit', 1)
#
remote_routed_host = cf.get(instance_conf, 'remote_routed_host', 'localhost')
remote_routed_port = cf.getint(instance_conf, 'remote_routed_port', 4666)
remote_routed_role = cf.get(instance_conf, 'remote_routed_role', '')

# Instance-specific Route Analysis setting.
analysis_async_limit = cf.getint(instance_conf, 'analysis_async_limit', 1)

# Elevation data file.
elevation_tiff = cf.get(instance_conf, 'elevation_tiff', '')
elevation_units = cf.get(instance_conf, 'elevation_units', 'meters')
elevation_mean = cf.getfloat(instance_conf, 'elevation_mean', 0.0)

# Known point in road network.
known_node_pt_x = cf.getfloat(instance_conf, 'known_node_pt_x', 0.0)
known_node_pt_y = cf.getfloat(instance_conf, 'known_node_pt_y', 0.0)

# Seed for the aliases script.
aliases_seed = cf.getint(instance_conf, 'aliases_seed', 1)

## Section: [misc]

# NOTE: System libraries will be loaded before custom ones; use caution!
#sys.path.extend(cf.get('misc', 'pythonpath').split(':'))
sys.path[:0] += cf.get('misc', 'pythonpath').split(':')

ld_library_path = cf.get('misc', 'ld_library_path')

semiprotect = cf.getint('misc', 'semiprotect')

commit_to_testing = cf.getboolean('misc', 'commit_to_testing', False)

# User authentication settings
magic_localhost_auth = cf.getboolean('misc', 'magic_localhost_auth')
magic_auth_remoteip = cf.get('misc', 'magic_auth_remoteip', '127.0.0.1')

auth_fail_hour_limit_password = cf.getint('misc', 
                                             'auth_fail_hour_limit_password')
auth_fail_hour_limit_token = cf.getint('misc', 'auth_fail_hour_limit_token')

auth_fail_day_limit_password = cf.getint('misc', 
                                             'auth_fail_day_limit_password')
auth_fail_day_limit_token = cf.getint('misc', 'auth_fail_day_limit_token')

# Python profiler settings
profiling = cf.getboolean('misc', 'profiling')
profile_file = cf.get('misc', 'profile_file')

# Email settings
mail_host = cf.get('misc', 'mail_host')
mail_from_addr = cf.get('misc', 'mail_from_addr')
internal_email_addr = cf.get('misc', 'internal_email_addr')
mail_ok_addrs = set(cf.getlist('misc', 'mail_ok_addrs'))

# TileCache
tilecache_dir = cf.get('misc', 'tilecache_dir')
tilecache_cache_dir = cf.get('misc', 'tilecache_cache_dir')
tile_size = cf.getint('misc', 'tile_size')
# The numbering of the tile cache zoom levels might be counter-intuitive:
# a lower zoom level is "more zoomed out" than larger zoom level values.
# Cyclopath defines one zoom level as being one pixel for one meter, or, one
# pixel in the png file represents one square meter in real life.
# NOTE: If you pick a zoom level one less than this, that zoom level uses one
#       pixel for two meters; the next lower zoom level is twice that, or one
#       pixel for four meters, etc.
tilecache_one_meter_to_one_pixel_zoom_level = 16
#
# MAGIC NUMBER:  '5': Smallest zoom level used in Cyclopath.
#                      This is, i.e., the state of MN.
#               '13': Largest raster zoom level used by flashclient.
#               '15': Largest zoom level used by android/mobile.
#                      Largest zoom level used in Cyclopath.
#               '19': Largest vector zoom level used by flashclient.
# SYNC_ME: These two numbers affect the tilecache.cfg.
#          See: resolutions=0.125,0.25,0.5,1,2,4,8,16,32,64,128
#          Where resolution=1 is zoom=16, res 0.125 is zoom 19,
#          res 128 is zoom 9, and so on.
#ccp_min_zoom = 9
#ccp_min_zoom = 7
#ccp_min_zoom = 6
ccp_min_zoom = 5
# Pre-Android:   ccp_max_zoom = 13
# Pre-Statewide: ccp_max_zoom = 15
# Nowadays, we let the max zoom match our clients' maximum zoom.
# Flashclient has six vector zooms, in addition to raster zooms
# 5 through 13, so the maximum client zoom is 19. (Android just
# goes to zoom 15, but we might want to add 16, which is 1:1.)
ccp_max_zoom = 19

# Checkout command constraints.
constraint_bbox_max = cf.getint('misc', 'constraint_bbox_max')
constraint_page_max = cf.getint('misc', 'constraint_page_max')
constraint_sids_max = cf.getint('misc', 'constraint_sids_max')

## Section: [geocoding]

# Geocoding services
bing_maps_id = cf.get('geocoding', 'bing_maps_id')
yahoo_app_id = cf.get('geocoding', 'yahoo_app_id')
mappoint_user = cf.get('geocoding', 'mappoint_user')
mappoint_password = cf.get('geocoding', 'mappoint_password')
mapquest_application_key = cf.get('geocoding', 'mapquest_application_key')

geocode_filter_radius = cf.getfloat('geocoding', 'filter_radius')

geocode_hit_limit = cf.getint('geocoding', 'hit_limit')
geocode_sql_limit = cf.getint('geocoding', 'sql_limit')

geocode_buffer = cf.getint('geocoding', 'geocode_buffer')

## Section: [routing]

# Route daemon settings
rating_ct_mean_threshold = cf.getint('routing', 'rating_ct_mean_threshold')
routing_penalty_left = cf.getint('routing', 'penalty_left')
routing_penalty_right = cf.getint('routing', 'penalty_right')
routing_penalty_straight = cf.getint('routing', 'penalty_straight')
# SYNC_ME: Search: Routed PID filename.
def get_pidfile_name(branch_id_or_name, routed_pers, purpose):
   pidfile = (
      os.path.join(
         cf.get('routing', 'routed_pid_dir'), 
         ('routed-pid-%s.%s.%s.%s' 
            # Note we're not using instance_name, which is missing ___blah.
          % (instance_raw, branch_id_or_name, routed_pers, purpose,))))
   return pidfile

# FIXME:
## Routing Analytics
## FIXME: Cannot run mult route daemons on same machine (at least not itamae)!
##        So either move BRA to another machine, or figure out how to re-write
##        routed.
#sparkd_pidfile = (cf.get('routing', 'routed_pid_dir')
#                  + '/' + instance_name + '-sparkd.pid')
#routed_revfile = (cf.get('routing', 'routed_pid_dir')
#                  + '/' + instance_name + '-routed.rev')

# for graphserv only, location of transit gtfsdb info
# FIXME: Graphserver paths...
# FIXME: This should depend on the instance, right?
transit_db_source = cf.get('routing', 'transit_db_source', '')
transitdb_filename = cf.get('routing', 'transit_db_gtfsdb', '')
transitdb_agency_name = cf.get('routing', 'transit_db_agency', '')

cp_maint_lock_path = cf.get('routing', 'cp_maint_lock_path', '')

## Section: [jobs_queue]

jobs_queue_port = cf.getint('jobs_queueing', 'jobs_queue_port')

# This is generally '/tmp'
mr_do_pid_dir = cf.get('jobs_queueing', 'mr_do_pid_dir')
mr_do_pidfile_basename = os.path.join(
   mr_do_pid_dir, 'mr_do-pid-%s' % (instance_raw,))

mr_do_total_consumers = cf.getint('jobs_queueing', 'mr_do_total_consumers', 1)

## Section: [logging]

### Log config

# Set the log level and message and date formats
log_level_s = cf.get('logging', 'level')
try:
   log_level = getattr(logging, log_level_s)
except:
   # For VERBOSE and NOTICE
   log_level = getattr(logging2, log_level_s)
# Message format
log_frmat = '%(asctime)s  %(levelname)-4s  %(name)16s  #  %(message)s'
# MAGIC NUMBERS       v   v    v   #   ^ +^       +^
log_frmat_names_len = 4 + 2 + 16
# Date format
log_dfmat = '%b-%d %H:%M:%S'
log_frmat_dfmat_len = 3 + 1 + 2 + 1 + 2 + 1 + 2 + 1 + 2
# Total metadata length
log_frmat_len = log_frmat_dfmat_len + 2 + log_frmat_names_len
# MAGIC NUMBER:                      ^2 spaces btw. date and names
# MAGIC NUMBERS      %b   -  %d   _  %H   :   %M  :  %S
# Save to the logfile of the instance and service that's executing this script.
if not_apache_parent:
   if (sys.argv[0].find('tilecache') >= 0):
      log_fn_extra = 'tilecache'
   elif (sys.argv[0].find('routed') >= 0):
      log_fn_extra = 'routed'
   elif (sys.argv[0].find('mr_do') >= 0):
      log_fn_extra = 'mr_do'
   elif (sys.argv[0].find('spark') >= 0):
      log_fn_extra = 'spark'
   else:
      log_fn_extra = 'misc'
else:
   log_fn_extra = 'apache'

# FIXME: Should this use instance_raw? Right now, all instances go to same
#        file... hrmm...? Would have to update 'logs' bash command.
log_fname = (cf.get('logging', 'filename') 
             % (instance_name + '-' + log_fn_extra))
             # MAYBE: 
             # % (instance_raw + '-' + log_fn_extra))

log_inited = False
def init_logging(log_to_file=True,
                 log_to_console=False,
                 log_line_len=None,
                 log_level_force=None,
                 add_thread_id=False):
   global log_inited
   if not log_inited:
      log_inited = True
      # Initialize the logger
      # global log_level, log_fname, log_frmat, log_dfmat, log_frmat_len
      if log_level_force is not None:
         default_level = log_level_force
      else:
         default_level = log_level
      logging2.init_logging(default_level, log_fname, log_frmat, log_dfmat, 
                            log_to_file, log_to_console, 
                            log_frmat_len, '  #  ', log_line_len,
                            add_thread_id)

# Add the logging facility to the 'g' namespace.
g.log = logging

db_glue_acquire_timeout_normal = cf.getfloat('logging', 
                                             'db_glue_acquire_timeout_normal')
db_glue_acquire_timeout_longer = cf.getfloat('logging', 
                                             'db_glue_acquire_timeout_longer')

db_glue_sql_time_limit = cf.getfloat('logging', 'db_glue_sql_time_limit')

## Section: [debugging]

# When to break into the debugger.
enable_winpdb_rpdb2 = cf.getboolean('debugging', 'enable_winpdb_rpdb2', False)
break_on_gwis_request = cf.getboolean('debugging', 'break_on_gwis_request',
                                      False)
break_on_assurt = cf.getboolean('debugging', 'break_on_assurt', False)
g.debug_me = break_on_assurt

# PYSERVER_HOME will not be set for apache, which is the only time we need
# winpdb, but pyserver_glue (imported above) changed us to the pyserver dir,
# so we can use the current working directory.
if enable_winpdb_rpdb2 or break_on_gwis_request or break_on_assurt:
   # WHATEVER: This path is also usually added in the apache confs,
   #           so it might be in there twice.
   # This is so code can simply call:
   #   import rpdb2
   # No: sys.path.append('%s/bin/winpdb' % (os.environ['PYSERVER_HOME'],))
   sys.path.append('%s/bin/winpdb' % (os.getcwd(),))

# Log file settings.
log_line_len = cf.getint('debugging', 'log_line_len')
if log_line_len < 0:
   # Treat -1 as None, since getint can't getnone. A value of None tells 
   # logging2 not to wrap messages.
   log_line_len = None
log_smart_wrap = cf.getboolean('debugging', 'log_smart_wrap')

# Developer informational facilities.
search_pretty_print = cf.getboolean('debugging', 'search_pretty_print', False)
db_glue_strict_assurts = cf.getboolean('debugging', 'db_glue_strict_assurts', 
                                       False)
#
debug_mem_usage = cf.getboolean('debugging', 'debug_mem_usage', False)
debug_mem_limit = cf.getfloat('debugging', 'debug_mem_limit', 1.0)
#
def debug_log_mem_usage(log_, usage_0, context=''):
   if debug_mem_usage:
      usage_1 = mem_usage.get_usage_mb()
      delta = usage_1 - usage_0
      if delta > debug_mem_limit:
         #log_.info('@mem_usage: delta: %.2f Mb / %s'
         #          % (delta, context,))
         log_.info('@mem_usage: %.2f Mb / %s' % (delta, context,))
         log_.info(' .. beg: %.2f Mb / end: %.2f Mb' % (usage_0, usage_1,))

## Section: [branching]
max_parent_chain_len = cf.getint('branching', 'max_parent_chain_len')

## Section: [shapeio]

shapefile_directory = cf.get('shapeio', 'shapefile_directory')

# Landmarks experiment.
## Section: [landmarks_experiment]
landmarks_experiment_active = cf.getboolean(
   'landmarks_experiment', 'landmarks_exp_active', False)

# There are the stack IDs of the routes being used in the experiment:
#
#   landmarks_exp_rt_stack_ids = (
#      1585730, 1590915, 1589507, 1599410, 1596538,
#      1560257, 1566106, 1594845, 1573123, 1575227,)
#
# Except we want to always show the same route to user subjects,
# regardless of if the route have since been edited.
#
# We could use a revision ID. E.g., using the last route before 22361:
#
#   22360 | 2014-04-27 21:30 | landonb | Rename branch: "Mpls-St. Paul"
#
#   landmarks_exp_rt_revision_id_lt = 22361
#
# Or we could use a date, e.g., find WHERE created < '2014-05-01'
#
# ccpv3_live=> SELECT created FROM _rt WHERE stk_id IN (
#    1585730, 1590915, 1589507, 1599410, 1596538,
#    1560257, 1566106, 1594845, 1573123, 1575227) order by created desc;
#              created            
#  -------------------------------
#   2014-05-03 13:18:07.292408-05  <!--- This is the edit to avoid, since the
#                                        experiment started before then
#   2013-09-03 04:32:53.876502-05  <!--- This was the last time one of the ten
#                                        routes in the experiment was edited.
#
#   landmarks_exp_rt_created_date_lt = '2014-05-01'
#
# But it's probably simplest just to use system IDs. Or maybe all the solution
# vectors are simple equally good, and I [lb] just like enumerating solutions.
#
#   SELECT DISTINCT ON (stk_id) stk_id, sys_id, v, created FROM _rt
#     WHERE stk_id IN (1585730, 1590915, 1589507, 1599410, 1596538,
#                      1560257, 1566106, 1594845, 1573123, 1575227) 
#       AND created < '2014-05-01' ORDER BY stk_id;
#
landmarks_exp_rt_system_ids = (
   362374, 246133, 377655, 252536, 371644,
   375513, 376582, 379485, 380966, 383542,)

##
## HARD-CODED VALUES, NOT FROM ./CONFIG ##
##

### Programmer config

gml_ns_uri = 'http://www.opengis.net/gml'

# FIXME: Delete this; it's not used?
# xml_dir = 'xml'

# Spatial reference system ID for geographic WGS84 (i.e., lat/lon degrees).
srid_latlon = 4326

# Number of digits right of the decimal point in database fetches.
# Python's Decimal('').quantize(Decimal('')) rounds 0.05 to 0.0 (and
# it rounds 0.05000001 to 0.1) so make sure to send the client three
# significant digits, otherwise, e.g., 0.0544 will be sent to client
# as 0.05 and will be returned as 0.05 but then quantize will make it
# 0.0. Oy!
# SYNC_ME: db_fetch_precision and node_precision/node_tolerance
#          The db fetch should include two more sig difs than nodes care about.
#db_fetch_precision = 2
db_fetch_precision = node_precision + 2 # = 3
postgis_precision = 15 # This is the default for, e.g., ST_AsSVG.

# The username of the generic byway rating rater.
generic_rater_username = '_r_generic'
bsir_rater_username = '_rating_bsir'
cbf7_rater_username = '_rating_cbf7'
ccpx_rater_username = '_rating_ccpx'
rater_usernames = (generic_rater_username,
                   bsir_rater_username,
                   cbf7_rater_username,
                   ccpx_rater_username,)
# If your source data has AADT on the most heavily travelled roads, you
# can assume that line segments without AADT values are less travelled.
# But if you lack AADT data altogether, don't enable this.
aadt_guess_when_missing = True
# The volume of automobile traffic as aadt that we consider 'high volume'.
vol_addt_high_volume_threshold = 2500
# The volume of heavy commercial traffic at which a road is 'heavy commercial'.
vol_addt_heavy_commercial_threshold = 300

# The username of the anonymous user. This is instance_name and instance_raw.
anonymous_username = '_user_anon_' + instance_name

# valid_until_rid of current features (RID of "infinity")
# SYNC_ME: Search: rid_inf.
rid_inf = 2000000000

# BUG nnnn: Server-side session ID management.
# Special UUIDs for group_item_access.session_id (and elsewhere?).
uuid_special_1 = uuid.UUID('00000000-0000-0000-0000-000000000000')
uuid_special_2 = uuid.UUID('FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF')

# GWIS request timeout that flashclient uses before giving up on an HTTP socket
# and alerting the user of a problem with the connection.
#
# SYNC_ME: pyserver.conf.gwis_timeout and flashclient.Conf.gwis_timeout.
#gwis_timeout = 90.0
gwis_default_timeout = 80.0
gwis_commit_timeout = 30.0

# If the revision table lock and cp_maint_lock file indicate that a commit
# has been running this long, complain to the user. In seconds.
# Note that most long operations, like updating the site, use maintenance mode,
# so the users are told via their clients that they cannot save. So this
# warning would only apply if some user's map save was taking this long.
# MAYBE: When importing Shapefiles using the import/export feature (and
#        the Mr. Do! work queue), map saves might take a number of minutes.
#        This would block Web users trying to save... and maybe unnecessarily
#        so, if the import and commit were for different branches... but import
#        doesn't happen that often...
#
# 2012.02.24: Let's start small and go from there. [lb] is really
#             just curious how often we'll see overlapping commits.
#cp_maint_warn_delay = 60.0
cp_maint_warn_delay = 0.0

# When we try to lock a database table, the timeout we specify to Psql is
# different than the timeout that the caller really wants. We specify a
# smaller value for the Psql timeout so that we don't just blindly block
# the Python thread but can respond to external events in a timeliish
# fashion.
# 2014.09.08: [lb] seeing user__token update lock often failing on statement
#             timeout.
#  Old value: psql_lock_timeout = '1250'
#psql_lock_timeout = '2500'
psql_lock_timeout = '1500'

# 2014.08.21: Debug helper...
debuggery_print_next_sql = 0

### If run as a script, print out the PYTHONPATH for this project

#if (__name__ == ('__main__')):
#   print cf.get('misc', 'pythonpath')


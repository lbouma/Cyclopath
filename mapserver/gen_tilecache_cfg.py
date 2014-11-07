#!/usr/bin/python

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
script_usage=(
'''

cd $cp/mapserver
./gen_tilecache_cfg.py

/bin/mv -f tilecache.cfg /ccp/var/tilecache-cache/cp_2628/
sudo chown -R $httpd_user /ccp/var/tilecache-cache/cp_2628/
sudo chgrp -R $httpd_user /ccp/var/tilecache-cache/cp_2628/
sudo chmod 664 /ccp/var/tilecache-cache/cp_2628/tilecache.cfg

# NOTE: [lb] experimented with a link from /ccp/opt/tilecache/tilecache.cfg
#       to /ccp/var/tilecache-cache, but I think we can just use --config
#       when calling tilecache_seed.py, and we can use TileCacheConfig in
#       the Apache config file, so we shouldn't need to copy the cfg elsewhere.
# /bin/cp -f tilecache.cfg /ccp/var/tilecache-cache/tilecache.cfg
# chmod 664 /ccp/var/tilecache-cache/tilecache.cfg

#./gen_tilecache_cfg.py --instance minnesota --force

''')

   # 2013.01.10: Make script to make tilecache.cfg... and another template
   #             bites the dust (goodbye, tilecache.cfg.template).

script_name = ('Make my tc cfg')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2013-01-10'

import os
import sys

# SYNC_ME: Search: Scripts: Load pyserver.
# Setup our paths before calling pyserver_glue, which calls os.chdir.
# FIXME: Making /mapserver chmod 2777... we should put these files
#        elsewhere: tilecache.cfg and byways_and_labels.map, so that
#        check_cache_now -- which runs via apache user -- can write
#        them without us give world-writeable permissions on the whole
#        folder...
#        FIXME: Really, [lb] wants to move wms-minnesota.map because
#        it's polluting his greps on the source...
path_to_new_file = os.path.abspath(
   '%s/tilecache.cfg' % (os.path.abspath(os.curdir),))
# Now load pyserver_glue.
sys.path.insert(0, os.path.abspath('%s/../scripts/util' 
                % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# DEVS: This is so assurts break on pdb and not rpdb.
g.iamwhoiam = True

import math
import re
import time

# Setup logging first, lest g.log.getLogger return the base Python Logger().
import logging
from util_ import logging2
from util_.console import Console
log_level = logging.WARNING
#log_level = logging.INFO
# FIXME: Setting to DEBUG until this script is more productiony.
log_level = logging.DEBUG
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)
log = g.log.getLogger('gen_tilec_cfg')

#from grax.access_level import Access_Level
from grax.item_manager import Item_Manager
#from gwis.query_branch import Query_Branch
from gwis.query_overlord import Query_Overlord
#from item import item_base
#from item import link_value
#from item.attc import attribute
from item.feat import branch
from item.feat import byway
#from item.feat import route
#from item.grac import group
#from item.link import link_attribute
#from item.link import link_tag
#from item.util import ratings
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from util_ import db_glue
#from util_ import geometry
#from util_ import gml
from util_ import misc
from util_.log_progger import Debug_Progress_Logger
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Debugging control

debug_limit = None

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 2
#debug_prog_log.debug_break_loop_cnt = 4
#debug_prog_log.debug_break_loop_cnt = 10
#debug_prog_log.debug_break_loop_cnt = 100

debug_skip_commit = False
#debug_skip_commit = True

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
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

   #
   def prepare(self, exclude_normal=False):

      Ccp_Script_Args.prepare(self)

      self.add_argument('--force', dest='force',
         action='store_true', default=False,
         help='force coverage_area update')

# *** Gen_TC_Cfg

class Gen_TC_Cfg(Ccp_Script_Base):

   # ***

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      self.cfg_f = None
      # MAGIC_NUMBER: Port 80 is the default http port.
      if conf.server_port != 80:
         self.server_url = '%s:%s' % (conf.server_name, conf.server_port,)
      else:
         self.server_url = conf.server_name

   # ***

   #
   def go_main(self):

      self.cfg_f = open(path_to_new_file, "w")
      self.write_cfgfile()
      self.cfg_f.close()
      os.chmod(path_to_new_file, 0664)
      self.cfg_f = None

   # ***

   #
   def write_cfgfile(self):

      # Write the preamble.

      self.cfg_f.write(Gen_TC_Cfg.cfg_preamble)

      # We want layers for every instance for every branch for every skin.

      if self.cli_opts.ccp_instance:
         server_instances = [self.cli_opts.ccp_instance,]
      else:
         server_instances = conf.server_instances

      for cur_instance in server_instances:

         log.debug('write_cfgfile: processing instance: %s' % (cur_instance,))

         # This is a little... cheaty.
         self.qb.db.close()
         conf.instance_name = cur_instance
         # Reset the db so we reset SEARCH_PATH.
         self.qb.db = db_glue.new()

         # NOTE: If you want to exclude a branch from the tilecache.cfg, you
         #       should set its tile_skins to NULL or ''. You won't accomplish
         #       it just be disabling permissions for a branch: branch_iterate
         #       finds them all.

         # Ignore self.cli_args.branch_id and just go through all branches.

         self.branch_iterate(qb=self.qb,
                             branch_id=None,
                             branch_callback=self.output_cfg_for_branch,
                             debug_limit=debug_limit)

      # Write the postamble.

      self.write_postamble()

   #
   def output_cfg_for_branch(self, branch_):

      username = conf.anonymous_username
      rev = revision.Current()
      branch_hier = branch.Many.branch_hier_build(
            self.qb.db, branch_.stack_id, rev)
      qb = Item_Query_Builder(self.qb.db, username, branch_hier, rev)

      # See byway.Many.branch_coverage_area_update and item_mgr.revision_save:
      # Computing the rubber-band polygon -- the so-called coverage area --
      # takes a number of seconds to compute. So best not to block a user's
      # GWIS call but to update the coverate area separately.
      # MAYBE: Move this to Mr. Do!
      # FIXME: revision.Revision.geosummary_update should move here, too?
      #        Or maybe to new Mr. Do! job?

      # See if we should bother doing this.

      needs_update = self.check_branch_last_rid_changed(qb, branch_)
      if self.cli_opts.force:
         needs_update = True

      if needs_update:
         self.branch_coverage_area_update(qb, branch_)

      # Now that we've got the branch bbox, generate the layers for each
      # branch-skin combo.

      skin_names = branch_.get_skin_names()
      for skin_name in skin_names:
         log.debug('Processing branch named "%s" (%d) / skin "%s"'
                   % (branch_.name, branch_.stack_id, skin_name,))
         self.out_cfg_for_brskin(qb, branch_, skin_name)

      if needs_update:
         self.update_branch_last_rid(qb, branch_)

   #
   def check_branch_last_rid_changed(self, qb, branch_):

      self.rid_latest = revision.Revision.revision_max(qb.db)

      self.last_rid_key_name = ('gen_tilecache_cfg-last_rid-branch_%d'
                                % (branch_.stack_id,))

      select_sql = ("SELECT value FROM key_value_pair WHERE key = '%s'"
                    % (self.last_rid_key_name,))

      rows = qb.db.sql(select_sql)

      rid_updated = False
      if rows:
         g.assurt(len(rows) == 1)
         update_last_rid = int(rows[0]['value'])
         if update_last_rid < self.rid_latest:
            rid_updated = True
      else:
         # First time for this branch!
         rid_updated = True

      return rid_updated

   #
   def update_branch_last_rid(self, qb, branch_):
      # NOTE: Not worrying about locking here. The cron script is all that
      #       calls us, and it uses a 'mkdir mutex'. But if this script did run
      #       in parallel with itself, it could overwrite key_value_pair. But
      #       it'd recover the next time it ran.
      qb.db.transaction_begin_rw()
      qb.db.insert_clobber('key_value_pair',
                           {'key': self.last_rid_key_name,},
                           {'value': self.rid_latest,})
      qb.db.transaction_commit()

   #
   def branch_coverage_area_update(self, qb, branch_):
      log.debug('branch_coverage_area_update: branch: %s' % (branch_.name,))
      qb.db.transaction_begin_rw()
      rid = self.rid_latest
      byway.Many.branch_coverage_area_update(qb.db, branch_, rid)
      qb.db.transaction_commit()

   #
   def get_tilecache_bbox(self, qb, branch_):

      # MAGIC_NUMBER: This is the maximum resolution defined for each Cyclopath
      # layer, and our bbox's maxx,maxy needs to be a multiple of it.
      ccp_max_resolution = 2048

      # Get the branch bbox, which is minx,miny,maxx,maxy

      # MAYBE: Should we cache this value in the branch table? We cache
      # coverage_area (via branch_coverage_area_update) since we need that
      # polygon to filter geocoded results. But the branch bbox is only used to
      # generate the tilecache bbox. If anything, we should move the other
      # costly bbox calculations from revision.Revision.revision_save to here.

      branch_bbox = byway.Many.get_branch_bbox(qb, branch_.stack_id)

      # Reset minx,miny to 0,0, and fix maxx,maxy to be a clean multiple so
      # tilecache.cfg's resolutions works.

      min_x = 0 # Ignoring: branch_bbox[0]
      min_y = 0 # Ignoring: branch_bbox[1]
      try:
         max_x = (int(math.ceil(float(branch_bbox[2])
                                / float(ccp_max_resolution)))
                  * ccp_max_resolution)
         max_y = (int(math.ceil(float(branch_bbox[3])
                                / float(ccp_max_resolution)))
                  * ccp_max_resolution)
      except TypeError:
         log.warning('get_tilecache_bbox: no bbox for branch?: %s'
                     % (str(branch_),))
         max_x = None
         max_y = None
         g.assurt(False) # Oh, wait, what're we going to do?

      tilecache_bbox = ('%s,%s,%s,%s' % (min_x, min_y, max_x, max_y,))

      return tilecache_bbox

   #
   def out_cfg_for_brskin(self, qb, branch_, skin_name):

# 2013.01.14: [lb]'s notes from tilecache_update redesign.
#
# BUG nnnn: As the map grows, so does the bbox. When a revision is saved, we
# should check the maps bounds and modify this value accordingly? And before
# calling tilecache_seed.py.
#bbox=0,0,524288,5013504
# BUG nnnn: This should be changed with every revision.
# This is what BOX2D says but it's including things I can't see, so the bbox
# is larger than it should be:
# bbox=301860,4909832,558375,5177140
# This is what [lb] got from ArcMap by drawing a box and writing down coords...
#bbox=400458,4908666,544525,5058686
# Okay, nevermind, tilecache_seed is doing math based on bbox and resolutions.
# Note that 524288.0 / 512.0 = 1024.0... so we either have to do math to figure
# out the extents for both minx,miny and maxx,maxy, or we just use 0,0 for
# minx,miny, use a deliberate bbox in tilecache_update, and set maxx,maxy here
# to a proper multiple of something.
#bbox=0,0,524288,5013504
# bbox=400458,4908666,544525,5058686
# is math.floor(400458.0/2048.0)*2048.0   399360
#    math.floor(4908666.0/2048.0)*2048.0  4907008
#    math.ceil(544525.0/2048.0)*2048.0    544768
#    math.ceil(5058686.0/2048.0)*2048.0   5060608
# This bbox:      bbox=399360,4907008,544768,5060608
# With this URL:  http://ccpv3/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota&SRS=EPSG:%(proj_srid)s&BBOX=425984,4915200,458752,4947968&WIDTH=256&HEIGHT=256&FORMAT=image/png
# Says:           An error occurred: Current x value 425984.000000 is too far from tile corner x 399360.000000
# 
# BUG nnnn: tilec? use LAYERS=minnesota but we want to postpend the branch_id.
# 
# FIXME: Should resolutions correspond to zoom_level? I.e.,
# #9 to 19 is zoom level... 2,4,8,16,32,64,128,256,512,1024,2048
# 6 to 19 is zoom level... 0.25,0.5,1,2,4,8,16,32,64,128,256,512,1024,2048
#resolutions=2,4,8,16,32,64,128
# Is this right?:
# resolutions=2,4,8,16,32,64,128,256,512,1024,2048
# or do we want to go the other way?
# When you call tilecache_seed.py, 0.125 is zoom 0, 0.25 is 1, etc...
# Also, Cyclopath's zoom level '9' is resolution 128 (and zoom '19' is 0.125).
# Zoom level 9 is 1:128 pixel:meters; zoom 19 is 1/8 meter per pixel.
# So the resolutions here are like zooms=19,18,17,...,9.
#
# FIXME: What's the best metasize? This should speed up tile creation...
#metasize=3,3
# MapServer's default MAXSIZE is 2048, which is metasize 8,8
#metasize=8,8
# If we increased MapServer's MAXSIZE to 4096, we can double metasize.
#metasize=16,16
#metasize=24,24
#metasize=17,17
#metasize=18,18
#metasize=19,19
#metasize=20,20
#metasize=21,21
#metasize=22,22
#metasize=23,23
# 
# EXPLAIN: metabuffer default is 10. "an integer number of pixels to request
# around the outside of the rendered tile. This is good to combat edge effects
# in various map renderers. Defaults to 10." So why don't we use it?
#
      # SYNC_ME: Search: TileCache layer name.
      # NOTE: Not using conf.instance_raw... though we could... :/
      layer_name = ('%s-%s-%s'
                    % (conf.instance_name, branch_.stack_id, skin_name,))

      tilecache_bbox = self.get_tilecache_bbox(qb, branch_)

      interp = {                                # e.g.,
         'layer_name': layer_name,              # 'minnesota-1234567-bikeways'
         'server_url': self.server_url,         # 'dev.cs.umn.edu:8081'
         'proj_srid': str(conf.default_srid),   # '26915'
         'schema': conf.instance_name,          # 'minnesota'
         'layer_skin': skin_name,               # 'bikeways'
         'tilecache_bbox': tilecache_bbox,      # '0,0,544768,5060608'
         }

      # This is the MN Bbox:
      # SELECT ST_Box2d(ST_Collect(geometry)) FROM state_counties;
      #  BOX(189783.56 4816309.33,761653.524114166 5472346.5)
      #  BOX(189783 4816309,761654 5472347)
      #  int(math.ceil(float(761654) / float(2048))) * 2048
      #  int(math.ceil(float(5472347) / float(2048))) * 2048
      # ==> 0,0,761856,5474304
# YOU NEED A BIG ENOUGH BBOX FOR METATILE TO WORK
#
# bbox=0,0,2490368,5474304
#
# E.g., trying to make tiles for 'Lake' county using a 20x20 meta tile,
#       if the bbox doesn't include the whole 20x20, tilecache_seed bails.
#
# GreaterMN:
# bbox=0,0,761856,5474304
# TileCache/Service.py raises "Zero length data returned from layer."
# bbox=0,0,2490368,5474304
# http://localhost:8088/wms?schema=minnesota&map.projection=EPSG:26915&layer_skin=bikeways&layers=standard&styles=&service=WMS&width=4096&format=image%2Fpng&request=GetMap&height=4096&srs=EPSG%3A26915&version=1.1.1&bbox=0.0%2C4194304.0%2C2097152.0%2C6291456.0
# 0.0,4194304.0,2097152.0,6291456.0
# no: 2097152.0 / 256.0 = 8192.0, / 20.0 = 409.6
# yes: 2097152.0 / 256.0 = 8192.0, / 512.0 = 16.0
# the tile request is from 0,4194304 to 2097152,6291456,
# so width is 2097152, which is 32 * 256 * 256.
# Zoom 7 is the 1:512 ratio, the eventual tile size is 256,
#  so the meta tile is 16 x 16?
#  6291456 - 4194304 = 2097152, which is the height.
# But our meta tile is 20 x 20: but whatever...
# so our bbox has to at least fit a 20 x 20 meta tile at
# the largest view, which is
# 20 * 512 * 256 = 2621440,
#  * 4 for good measure? 10485760
#
# Cannot just simply: bbox=%(tilecache_bbox)s
# but hardcode the larger, 0,0,10485760,10485760, instead.

      layer_cfg = (
'''
[%(layer_name)s]
type=WMS
layers=standard
url=http://%(server_url)s/wms?schema=%(schema)s&map.projection=EPSG:%(proj_srid)s&layer_skin=%(layer_skin)s&
extension=png
size=256,256
#bbox=%(tilecache_bbox)s
bbox=0,0,10485760,10485760
srs=EPSG:%(proj_srid)s
# SYNC_ME: conf.py's ccp_min_zoom/ccp_max_zoom: 5/19
#          Conf.as's zoom_min/zoom_max:         5/19
#          tilecache.cfg's resolutions=:        19...5
resolutions=0.125,0.25,0.5,1,2,4,8,16,32,64,128,256,512,1024,2048
extent_type=loose
metatile=yes
metasize=20,20
metabuffer=0
debug=no
''' % interp)

      self.cfg_f.write(layer_cfg)

   # ***

   cfg_preamble = (
'''# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Some examples and "documentation" are at the end of the file. See also:
# http://tilecache.org/docs/index.html

# NOTE: *All* stanzas need their own "debug=no". Otherwise, TileCache spews
# verbose chatter to the log, and the writes from different threads get all
# mixed up. It's a mess, and it results in logcheck emails that look like:
#
#   System Events
#   =-=-=-=-=-=-=
#   946121216, debug: True
#   Ce: 8.70227813721e-05, debug: True
#   e: x: 7622, y: 69112, z: 1, time: 9.29832458496e-05, debug: True

# This is the directory where the cached tiles are stored.
[cache]
type=Disk
base=%s

# Cyclopath Layers
#
# The way tilecache works, we need separate layers for each branch-skin
# combination. This is because we can't send this information to
# tilecache_seed.py, nor can Flashclient send the extra information -- we can
# only indicate what tile 'layer' we want. So we end up with a bunch of
# similarly-configured layers.
#
# SYNC_ME: The # of resolutions matches the MAGIC NUMBERs used to translate 
#          from Cyclopath to TileCache zooms.
#          See conf.ccp_min_zoom and conf.ccp_max_zoom.
'''
   # The base is, e.g., /ccp/var/tilecache-cache/cp
   % (conf.tilecache_cache_dir,))

   # ***

   # FIXME: Are the bboxes herein okay? Should they match the colorado
   #        instance.
   #        NOTE ALSO: These layers are only for colorado instance, so maybe
   #        encode the instance name in the layer name.

   #
   def write_postamble(self):

      interp = {                                # e.g.,
         'server_url': self.server_url,         # 'dev.cs.umn.edu:8081'
         }

      cfg_postamble = (
'''
# Aerial Photography Layers

# [rp]: For Minnesota, we do NOT run the MnGeo/LMIC layers through TileCache,
# because it's slower if the cache is cold (due to the 2 network hops),
# it's nice to make someone else spend the bandwidth, and I'm worried about the
# disk cache growing excessively large. Also, it's a much simpler config.

# For Colorado, we DO run the layers through TileCache, because
# * UrbanArea comes from Microsoft Research Maps (TerraServer) which is slow
#   and we want to cut off the "USGS" label it includes in every tile.
# * USGS2008 comes from USGS/Seamless, which doesn't provide layers in UTM 13
#   so we have to use MapServer to reproject.

[UrbanArea]
type=WMS
layers=UrbanArea
url=http://msrmaps.com/ogcmap6.ashx?
extension=jpg
#bbox=0,0,589824,4456448
bbox=0,0,10485760,10485760
size=256,256
srs=EPSG:26913
extent_type=loose
resolutions=0.125,0.25,0.5,1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768
metatile=yes
metabuffer=32
metasize=3,3
debug=no

[USGS2008]
type=WMS
layers=USGS2008
url=http://%(server_url)s/wms?map.projection=EPSG:26913&
extension=jpg
#bbox=0,0,589824,4456448
bbox=0,0,10485760,10485760
size=256,256
srs=EPSG:26913
extent_type=loose
resolutions=0.125,0.25,0.5,1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768
metatile=yes
metasize=3,3
debug=no

# Configuration for MC TileCache

# TileCache can load Layers or Caches from anywhere in sys.path. If you 
# prefer to load from somewhere which is *not* on sys.path, you can use
# the path configuration paramter to set a comma-separated list of 
# filesystem paths which you want prepended to sys.path.
#[tilecache_options]
#path=/home/you

# Some TileCache options are controlled by metadata. One example is the
# crossdomain_sites option, which allows you to add sites which are then
# included in a crossdomain.xml file served from the root of the TileCache
#[metadata]
#crossdomain_sites=openstreetmap.org,openaerialmap.org

# [cache] section examples: (mandatory!)
# 
# Disk:
# [cache] 
# type=Disk   (works out of the box)
# base=<full path to cache directory>
# 
# Memcached:
# [cache]
# type=Memcached  (you'll need memcache.py and memcached running!)
# servers=192.168.1.1:11211
#
# Amazon S3:
# [cache]
# type=AWSS3
# access_key=your_access_key
# secret_access_key=your_secret_access_key

# [layername] -- all other sections are named layers
#
# type={MapServerLayer,WMSLayer} 
#   *** if you want to use MapServerLayer, you *must* have Python mapscript
#       installed and available ***
# 
# mapfile=<full path to map file>   
# url=<full URL of WMS>             
# layers=<layer>[,<layer2>,<layer3>,...] 
#                                   *** optional iff layername if what
#                                       your data source calls the layer **
# extension={png,jpeg,gif}          *** defaults to "png"               ***
# size=256,256                      *** defaults to 256x256             ***
# bbox=-180.0,-90.0,180.0,90.0      *** defaults to world in lon/lat    ***
# srs=EPSG:4326                     *** defaults to EPSG:4326           ***
# levels=20                         *** defaults to 20 zoom levels      ***
# resolutions=0.1,0.05,0.025,...    *** defaults to global profile      ***
# metaTile=true                     *** metatiling off by default
#                                       requires python-imaging         ***
# metaSize=5,5                      *** size of metatile in tiles
#                                       defaults to 5 x 5               ***
# metaBuffer=10                     *** size of metatile buffer in px   ***
# mime_type=image/png  *** by default, the mime type is image/extension ***   
#                      *** but you may want to set extension=png8 for   ***
#                      *** GeoServer WMS, and this lets you set the     ***
#                      *** mime_type separately.                        ***

# The following is a demonstration of a layer which would be generated
# according to the 'Google projection'. This uses the standard values for
# a spherical mercator projection for maxextent, maxresolution, units 
# and srs.
# [google-tiles]
# type=WMS
# url=http://%(server_url)s/cgi-bin/mapserv?map=/mapdata/world.map
# layers=world
# spherical_mercator=true

# Standard MapServer layer configuration.
# [vmap0]
# type=MapServer
# layers=vmap0
# mapfile=/var/www/vmap0.map

# Rendering OpenStreetMap data with Mapnik; should use metaTiling to
# avoid labels across tile boundaries 
# [osm]
# type=Mapnik
# mapfile=/home/user/osm-mapnik/osm.xml
# spherical_mercator=true
# tms_type=google
# metatile=yes

''') % interp

      self.cfg_f.write(cfg_postamble)

   # ***

# ***

if (__name__ == '__main__'):
   gtcc = Gen_TC_Cfg()
   gtcc.go()


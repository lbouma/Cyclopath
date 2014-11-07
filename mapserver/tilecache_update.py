#!/usr/bin/python

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ pushd /ccp/dev/cp/mapserver/
#  $ sudo -u apache INSTANCE=minnesota ./tilecache_update.py -a
#
# See below for more options.

"""

=====================================================================

# Initial setup.
#
# See also: upgrade_ccpv1-v2.sh.

2013.12.05: production server setup...
2014.08.18: running a few of these again...

sudo -v

cp=/ccp/dev/cycloplan_live
#PYSERVER_HOME=$cp/pyserver
cd $cp
setcp
echo $PYSERVER_HOME

# WEIRD! If this script fails, and then you re-run it, sometimes the
#        tiles_mapserver_zoom row count is 0. But then you re-run (a
#        third time) and the row count is 300! Hrmpf!
#psql -U cycling -h localhost -p 7432 \
#   -c "SELECT COUNT(*) FROM tiles_mapserver_zoom" \
#   ccpv3_demo
cd $cp/mapserver
psql -U cycling -c "DELETE FROM tiles_mapserver_zoom" ccpv3_live
./tilecache_update.py --db-create-public-zooms
psql -U cycling -c "SELECT COUNT(*) FROM tiles_mapserver_zoom" ccpv3_live

cd $cp/mapserver
./flashclient_classes.py

cd $cp/mapserver
./make_mapfile.py

m4 wms-minnesota.m4 > wms_instance.map
/bin/mv -f wms_instance.map /ccp/var/tilecache-cache/cycloplan_live/
/bin/rm -f byways_and_labels.map

sudo /bin/rm -rf /ccp/var/tilecache-cache/cycloplan_live/fonts
/bin/cp -rf fonts/ /ccp/var/tilecache-cache/cycloplan_live
/bin/cp -f fonts.list /ccp/var/tilecache-cache/cycloplan_live

#sudo chown -R $httpd_user /ccp/var/tilecache-cache/cycloplan_live/
#sudo chgrp -R $httpd_user /ccp/var/tilecache-cache/cycloplan_live/
sudo chown -R $httpd_user:$httpd_user /ccp/var/tilecache-cache/cycloplan_live/

sudo chmod 2775 /ccp/var/tilecache-cache/cycloplan_live/
sudo chmod 2775 /ccp/var/tilecache-cache/cycloplan_live/fonts/
sudo chmod 664 /ccp/var/tilecache-cache/cycloplan_live/fonts.list
sudo chmod 664 /ccp/var/tilecache-cache/cycloplan_live/wms_instance.map
sudo chmod 664 /ccp/var/tilecache-cache/cycloplan_live/fonts/*

# Skip this one; just overwrite the existing cache.
##./tilecache_update.py --db-create-for-instance \
##   --branch -1 --remove-cache
# Hrmm... --db-create-for-instance just deletes from key_value_pair if we
#         don't use any other switches... but we can manually clean
#         key_value_pair. And it looks like reset_tables_cache_instance
#         gets called anyway and deletes from key_value_pair, so... no
#         need to call this:
#./tilecache_update.py --db-create-for-instance \
#   --branch -1 --skip-cache-segment --skip-cache-cluster

# # Use --branch -1 for production servers. For DEVS, use if using,
# # debug_prog_log.debug_break_loops, otherwise save time by not.
# ./tilecache_update.py --all --branch -1

cd $cp/mapserver
# 2013.12.05: Script completed in 11.00 mins. [just Minnesota]
# 2013.12.05: Script completed in 15.09 mins. [both branches]
# 2014.08.18: Script completed in 18.17 mins. [just Minnesota]
sudo -u $httpd_user \
   INSTANCE=minnesota___cycloplan_live \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch -1 \
      --cyclopath-cache --all \
      --skip-cache-cluster

# 2013.11.29: Script completed in 1.24 days. [just Minnesota]
# 2013.12.07: Script completed in 1.38 days. [just Minnesota]

################################# XXXXX
# Aug-18 13:59:36 INFO log_progger # Adjusted expected runtime: 16.11 hours
# 2014.08.19: Script completed in 1.13 days [just Minnesota] (script sleeps
#                          and recycles the db transsaction every iteration).
# 2014.08.19: Script completed in xxxxx days. [just Metc Bikeways 2012]

cd $cp/mapserver
sudo -u $httpd_user \
   INSTANCE=minnesota___cycloplan_live \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
   nohup /ccp/dev/cycloplan_live/mapserver/tilecache_update.py \
         --branch "Minnesota" \
         --cyclopath-cache --all \
         --skip-cache-segment \
   | tee /ccp/var/log/daily/2014.08.19-tilecache_update-cluster-mpls.log 2>&1 &
# NOTE: Using --keep-existing-caches so we don't clobber the day we just spent!
sudo -u $httpd_user \
   INSTANCE=minnesota___cycloplan_live \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
   nohup /ccp/dev/cycloplan_live/mapserver/tilecache_update.py \
         --branch "Metc Bikeways 2012" \
         --cyclopath-cache --all \
         --skip-cache-segment \
         --keep-existing-caches \
   | tee /ccp/var/log/daily/2014.08.19-tilecache_update-cluster-metc.log 2>&1 &


# Update the cache segment cache...
# 2014.08.21: 11.51 mins.
sudo -u $httpd_user \
   INSTANCE=minnesota___cycloplan_live \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
      --cyclopath-cache --all \
      --skip-cache-cluster

# Build the zoomiest-outiest tiles to test...
sudo -u $httpd_user \
   INSTANCE=minnesota___cycloplan_live \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
      --tilecache-tiles --all \
      --zoom 05 09

and then once for 10 11 12 13 14 15 (skip: 16 17 18 19)
2014.08.24: level 13: 6.18 hours
2014.08.24: level 14: 21.99 hours
2014.08.24: level 15: 3.36 days



=====================================================================

# 2013.12.05
# TESTING winningest_gfl_id fix: Uncomment debug_clusters_named, below.
sudo -u $httpd_user \
   INSTANCE=minnesota___cp_2628 \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
   ./tilecache_update.py \
         --branch "Minnesota" \
         --cyclopath-cache --all \
         --skip-cache-segment
sudo -u $httpd_user \
   INSTANCE=minnesota___cp_2628 \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
   ./tilecache_update.py \
         --branch "Metc Bikeways 2012" \
         --cyclopath-cache --all \
         --skip-cache-segment \
         --keep-existing-caches

=====================================================================

# 2013.11.18: This works on Statewide import:

sudo -u $httpd_user \
   INSTANCE=minnesota___cp_2628 \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
      --cyclopath-cache --all \
      --county "Lake"

sudo -u $httpd_user \
   INSTANCE=minnesota___cp_2628 \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
      --tilecache-tiles --all \
      --zoom 09 09 \
      --county "Lake"

Force Zoom 7 meta tile:

http://localhost:8088/wms?schema=minnesota&map.projection=EPSG:26915&layer_skin=bikeways&layers=standard&styles=&service=WMS&width=4096&format=image%2Fpng&request=GetMap&height=4096&srs=EPSG%3A26915&version=1.1.1&bbox=0.0%2C4194304.0%2C2097152.0%2C6291456.0

sudo -u $httpd_user \
   INSTANCE=minnesota___cp_2628 \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
      --tilecache-tiles --all \
      --zoom 05 05

http://localhost:8088/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=524288,4718592,1048576,5242880&WIDTH=256&HEIGHT=256&FORMAT=image/png
http://localhost:8088/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=0,4718592,524288,5242880&WIDTH=256&HEIGHT=256&FORMAT=image/png

sudo -u $httpd_user \
   INSTANCE=minnesota___cycloplan_live \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
# first:
      --cyclopath-cache --all \
      --skip-cache-cluster
# second:
      --tilecache-tiles --all \
      --zoom 05 09

=====================================================================

2013 changes to mapserver config, etc.:
 - Now branch ID and skin are in the request.
 - This script's parameters have changed.

WRONG: Don't use tilecache:
http://cycloplan.cyclopath.org/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=466944,4964352,475136,4972544&WIDTH=256&HEIGHT=256&FORMAT=image/png

RIGHT: Use MapServer:
http://cycloplan.cyclopath.org/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=466944,4964352,475136,4972544&WIDTH=256&HEIGHT=256&FORMAT=image/png


http://cycloplan.cyclopath.org/wms?schema=minnesota&map.projection=EPSG:26915&layer_skin=bikeways&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=standard&SRS=EPSG:26915&BBOX=466944,4964352,475136,4972544&WIDTH=256&HEIGHT=256&FORMAT=image/png
http://cycloplan.cyclopath.org/wms?schema=minnesota&map.projection=EPSG:26915&layer_skin=bikeways&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=466944,4964352,475136,4972544&WIDTH=256&HEIGHT=256&FORMAT=image/png

=====================================================================

These are snippets of old tilecache runs, pre-Statewide.

# --zoom 9 9: 7.43 mins.
# 2013.01.07 [pluto]: Script completed in 7.43 mins.
# Jan-07 14:58:54  DEBG  tilecache_update  #  render_and_cache_tiles: indices (12, 149) to (16, 154)
# (16-12+1) * (154-149+1) = 30 tiles
sudo -u $httpd_user INSTANCE=minnesota PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
   ./tilecache_update.py \
   --all \
   --zoom 9 9 \
   --bbox 400458 4908666 544525 5058686
Jan-07 21:24:21  DEBG  tilecache_update  #    10 (000017, 000157) = (557056.0000 5144576.0000 589824.0000 517
                                         #  7344.0000) [43.0987s : 0.023/s] 12/4
# MetaSize 3,3:
Jan-07 21:24:21  INFO       script_base  #  Script completed in 8.65 mins.
# MetaSize 18,18:
Jan-07 22:49:43  INFO       script_base  #  Script completed in 2.39 mins.

# --zoom 10 10: 13.18 mins.
# Jan-07 16:23:39  DEBG  tilecache_update  #  render_and_cache_tiles: indices (24, 299) to (33, 308)
# (33-24+1) * (308-299+1) = 100 tiles
# [lb]'s guess: 7.43 * 100.0/30.0 = 24.77 mins.
# Actual: Script completed in 13.18 mins.
# MetaSize 3,3:
Jan-07 21:54:00  DEBG  tilecache_update  #    09 (000035, 000310) = (573440.0000 5079040.0000 589824.0000 509
                                         #  5424.0000) [43.1686s : 0.024/s] 25/9
# MetaSize 3,3:
Jan-07 21:54:00  INFO       script_base  #  Script completed in 17.64 mins.
# MetaSize 8,8:
Jan-07 22:06:42  INFO       script_base  #  Script completed in 7.87 mins.
# MetaSize 16,16:
Jan-07 22:11:04  INFO       script_base  #  Script completed in 3.98 mins.
# MetaSize 24,24:
Jan-07 22:20:50  INFO       script_base  #  Script completed in 4.59 mins.
# MetaSize 20,20:
Jan-07 22:24:26  INFO       script_base  #  Script completed in 2.43 mins.
# MetaSize 21,21:
Jan-07 22:30:19  INFO       script_base  #  Script completed in 2.41 mins.
# MetaSize 22,22:
Jan-07 22:33:26  INFO       script_base  #  Script completed in 2.59 mins.
# MetaSize 23,23:
Jan-07 22:37:23  INFO       script_base  #  Script completed in 2.55 mins.
# MetaSize 19,19:
Jan-07 22:40:20  INFO       script_base  #  Script completed in 2.47 mins.
# MetaSize 18,18:
Jan-07 22:43:56  INFO       script_base  #  Script completed in 2.37 mins.
# MetaSize 17,17:
Jan-07 22:46:37  INFO       script_base  #  Script completed in 2.31 mins.


# --zoom 11 11: 35.45 mins.
# Jan-07 16:37:20  DEBG  tilecache_update  #  render_and_cache_tiles: indices (48, 599) to (66, 617)
# (66-48+1) * (617-599+1) = 361 tiles
# It's basically *4 every time... but actual time is just *2?
#   Or, 13.18*361.0/100.0 = 47.58 mins...
# MetaSize 3,3:
# Jan-07 17:12:47  INFO       script_base  #  Script completed in 35.45 mins.
# MetaSize 18,18:
Jan-07 22:56:53  INFO       script_base  #  Script completed in 5.28 mins.
# MetaSize 20,20:
Jan-07 23:00:47  INFO       script_base  #  Script completed in 2.68 mins.
# MetaSize 22,22:
Jan-07 23:05:10  INFO       script_base  #  Script completed in 2.79 mins.

# --zoom 12 12:
# Jan-07 17:13:22  DEBG  tilecache_update  #  render_and_cache_tiles: indices (97, 1198) to (132, 1235)
# (132-97+1)*(1235-1198+1) = 1368 tiles
# I slept my poo-poo, so subtract 41 mins.
# Jan-07 19:48:39  DEBG  tilecache_update  #    03 (000135, 001236) = (552960.0000 5062656.0000 557056.0000 506
#                                          #  6752.0000) [36.5717s : 0.021/s] 196/156
# Jan-07 19:48:39  INFO       script_base  #  Script completed in 155.29 mins.
# 155.29 - 41 = 114.29 mins.
# MetaSize 20,20:
Jan-07 23:13:49  INFO       script_base  #  Script completed in 7.15 mins.

# --zoom 13 13:
# MetaSize 20,20:
Jan-07 23:39:14  INFO       script_base  #  Script completed in 20.24 mins.

sudo -u $httpd_user INSTANCE=minnesota PYTHONPATH=$PYTHONPATH PYSERVER_HOME=$PYSERVER_HOME ./tilecache_update.py --all \
   --zoom 14 14 --bbox 400458 4908666 544525 5058686
# --zoom 14 14:
# MetaSize 20,20:
Jan-08 00:30:46  INFO       script_base  #  Script completed in 51.53 mins.

sudo -u $httpd_user INSTANCE=minnesota PYTHONPATH=$PYTHONPATH PYSERVER_HOME=$PYSERVER_HOME ./tilecache_update.py --all \
   --zoom 15 15 --bbox 400458 4908666 544525 5058686
# --zoom 15 15:
# MetaSize 20,20:
Jan-08 03:02:15  INFO       script_base  #  Script completed in 151.47 mins.

# For view-mode zoomed in non-raster... these are going to take a while, aren't
# they? And how much hard drive space are we talking? Oy. Maybe DEV clients can
# use runic's tilecache? I.e., in flashclient use runic's URL and not
# localhost... expect that means that offline clients are boned... which is not
# really a big deal -- and you could always enable on-demand tilecache.
# --zoom 16 16:
# --zoom 17 17:
# --zoom 18 18:
# --zoom 19 19:

http://ccpv3/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota&SRS=EPSG:26915&BBOX=425984,4915200,458752,4947968&WIDTH=256&HEIGHT=256&FORMAT=image/png

=====================================================================

This is the one and only metro area tile at zoom 9:

http://cycloplan.cyclopath.org/wms?schema=minnesota&map.projection=EPSG:26915&layer_skin=bikeways&layers=standard&styles=&service=WMS&width=4608&format=image%2Fpng&request=GetMap&height=5120&srs=EPSG%3A26915&version=1.1.1&bbox=0.0%2C4587520.0%2C589824.0%2C5242880.0

http://cycloplan.cyclopath.org/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=425984,4947968,458752,4980736&WIDTH=256&HEIGHT=256&FORMAT=image/png

=====================================================================

"""

  # For running in background from terminal you want to logoffof,
  # You cannot 'sudo ... nohup', but you can 'su ; ... nohup'.
  #   sudo su - www-data
  #   cd ${CCPV2_TRUNK}/mapserver
  #   #FiXME: This works except cannot create tcupdate.txt
  #   INSTANCE=minnesota nohup ./tilecache_update.py -N -A -L -Z | tee tcupdate.txt 2>&1 &
  #   INSTANCE=minnesota nohup ./tilecache_update.py -a | tee tcupdatE.txt 2>&1 &
  #
  # If you want a simple test (but this won't make the name cache),
  #   sudo -u apache INSTANCE=minnesota ./tilecache_update.py -z 9 9 \
  #     -x 442368.0 4964352.0 491520.0 5013504.0

# This is what cron should do:
# sudo -u $httpd_user \
# INSTANCE=minnesota \
# PYTHONPATH=$PYTHONPATH \
# PYSERVER_HOME=$PYSERVER_HOME \
# ./tilecache_update.py --all

# IF YOU EDIT THIS FILE: You should enable and test with the debug_* switches.
# Otherwise, you could waste three hours of runtime before finding faults....

# Prerequisites: build flashclient so that pyserver/VERSION.py exists, else
# pyserver_glue fails.

script_name = 'Cyclopath MapServer and TileCache Awesome Script Great Code'
script_version = '2.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2011-09-20'

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
sys.path.insert(0, os.path.abspath('%s/../scripts/util'
                   % (os.path.abspath(os.curdir),)))
import pyserver_glue

import conf
import g

# DEVS: This is so assurts break on pdb and not rpdb.
g.iamwhoiam = True

import grp
import math
import psycopg2
import pwd
import re
import shutil
import subprocess
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
log = g.log.getLogger('tilecache_update')

from grax.access_level import Access_Level
from grax.item_manager import Item_Manager
from gwis.query_filters import Query_Filters
from gwis.query_overlord import Query_Overlord
from item import link_value
from item.attc import attribute
from item.feat import branch
from item.feat import byway
from item.grac import group
from item.link import link_attribute
from item.link import link_tag
from item.util import revision
from item.util.item_query_builder import Item_Query_Builder
from item.util.item_type import Item_Type
from item.util.mndot_helper import MnDOT_Helper
from skins.tile_skin import Tile_Skin
from util_ import db_glue
from util_ import geometry
from util_ import misc
from util_ import rect
from util_.log_progger import Debug_Progress_Logger
from util_.mod_loader import Mod_Loader
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# BUG nnnn: Implement HTML imagemaps for simple mode
#           http://mapserver.org/output/imagemaps.html

# BUG nnnn: Byway ratings should be Nonwiki Items.

# BUG nnnn: The tiles used to color by generic rating... we no longer do that.
#           1) For zoomed-out tiles, the color is meaningless and confusing;
#              a user should zoom in to see rating.
#           2) For zoomed-in tiles -- if we're tiling -- maybe we can make a
#              layer that includes ratings...

# Bug nnnn: Ccpv1: bridge levels not shown in tiles; freeways always on top,
#                  hiding smaller roads near it; shadows drawn first, so
#                  byways layer might hide some byways' shadows (looks weird
#                  at intersections).

# BUG nnnn: 7th St in St Paul just east of where it was Hwy 5 is rated
#           impassable... the generic rating affects tiles and routes
#           and flashclient visualization, and cannot be changed by users??
# Bug nnnn: SW LRT in Chaska not labeled in tiles -- Kenilworth is labeled,
#           and then... nothing! Hard to follow trails in tiles, all the major
#           roads get more prominance...
# BUG nnnn: Label (significant) terrain

# FIXME: draw_class_viewer/editor/* seems... silly. And they aren't used as
#        intended (which is to display the same type of geofeature differently
#        depending on the user's access to the item). Rather than adding all
#        the extra info to the skin for each zoom level and geofeature layer
#        ID, I wonder if there's an easy way to change any geofeature depending
#        on the access level (like a single-pixel border color or something).

# FIXMEs/MAYBEs: Thoughts from late 2012:
# 1. add new attr defns for mapserver stuff:
#    for items, /mapserver/zoom_10_do_label -> yes, no, nickname
#               /mapserver/zoom_low_nickname
#    for branches, /mapserver/zoom_10_min_width ? how would mapserver
#                  config find this value?
# 2. write script to manipulate link_values? like tags and attributes?
#    ./ccp.py -u link_value --lhs_name '/mapserver/zoom_9_do_label' \
#                           --rhs_name '%Greenway%' \
#                           -f value_boolean 1
#    ./ccp.py -u link_value --lhs_name '/mapserver/zoom_nickname' \
#                           --rhs_name '%Midtown Greenway%'
#                           --rhs_gfl_type_name 'Bicycle Trail'
#                           -f value_text 'The Greenway'
#   can i add bike counts or an approx to trails instead, ie,
#      light/moderate/heavy traffic volume
#   then local/major road => really light/mod/heavy volume + mixed modal
#   /byway/modes => ('auto', 'bike', 'walk', 'etc'.)
# 3. test metc with public branch view access, or changing it via flashclient
#    at least
# 4. flashclient way to verify nodes' geometry endpoints match or not
# 5. show terrain and region names on tiles, too!

# FIXME: Add Expressway Ramp to skin. In the SQL here, it's drawn the same as
# Expressway, which is too wide. In CcpV1, it uses draw config of Local Road,
# except it's colored differently. Because of how the CcpV2 MapServer code is
# implemented, it needs its own config (in CcpV1, the color is hard-coded in
# the .map file, but in CcpV2, we can add it to the skin.)
#
# FIXME: geofeature_layer.draw_class_owner/arbiter/editor/viewer is wrong,
# and maybe draw_class table is not needed at all -- all it has that
# geofeature_layer does not have is a color column, but color should be in the
# skin, anyway.  So delete draw_class (but make sure you make skin_classic.py
# for it and its colors; also, is the 'text' column important?. And delete
# draw_param and draw_param_joined, which are superceded by the skin -- which
# also means flashclient and mobile should not request it, and nothing should
# join on it.  As for draw_class_*, those columns are just references to skin
# rows. So get rid of these columns, and either replace with just one column
# -- like, skin_item_taxa. Then, really, geofeature_layer names could be
# '/byway/blah' (it's currently feat_type and layer_name but I don't know who
# uses what). */
#
# FIXME: Rename geofeature_layer_id ==> item_subclass_id or item_taxa or
# item_type_taxa or something... it's not really a layer, is it? It's a group
# or a class or some conglomeration. Maybe 'item_class', and just have it be,
# e.g., '/byway/local_road' or 'Byway | Local Road' or whatever.

# BUG nnnn: tiles_draw_terrain is a VIEW of public terrain and it's branchless.
#           We should make a terrain cache like we do the byway cache.

# BUG nnnn: Reduce number of byway.z possibilities from 10 values (130-139)
#           to just 3, 4, or 5 values, so we can reduce tilecache_seed time.

# *** Debugging control

debug_limit = None

debug_prog_log = Debug_Progress_Logger()
debug_prog_log.debug_break_loops = False
#debug_prog_log.debug_break_loops = True
#debug_prog_log.debug_break_loop_cnt = 2
#debug_prog_log.debug_break_loop_cnt = 4
#debug_prog_log.debug_break_loop_cnt = 10
#debug_prog_log.debug_break_loop_cnt = 25
#debug_prog_log.debug_break_loop_cnt = 100

debug_skip_commit = False
#debug_skip_commit = True

debug_clusters_named = ""
#debug_clusters_named = "'MNTH 23'"
#debug_clusters_named = "'MNTH 23','2nd St S'"

# This is shorthand for if one of the above is set.
debugging_enabled = (   False
                     or debug_prog_log.debug_break_loops
                     or debug_skip_commit
                     or debug_clusters_named
                     )

if debugging_enabled:
   log.warning('****************************************')
   log.warning('*                                      *')
   log.warning('*      WARNING: debugging_enabled      *')
   log.warning('*                                      *')
   log.warning('****************************************')

# *** Script globals

insert_bulkwise = False
#insert_bulkwise = True

# ***

# FIXME: See bike_facilities_populate.py: do similar for:
#           Major Trails
#           Cycle Routes
# and move this lookup to that new script...

"""
# Use these to mess around with name cache.
# Maybe also move CREATE TABLE for name cache here --
# since you truncate the table, might as well!
# FIXME: Get rid of these: use to seed a new attribute

major_trail_prefixes = (
   ('Midtown Greenway',                'Greenway',),
   ('Hiawatha LRT',                    'Hiawatha Tr',),
   ('Grand Rounds',                    'Grand Rounds',),
   ('North Cedar Lake',                'N Cedar Lake Tr',),
   ('Cedar Lake',                      'Cedar Lake Tr',),
   ('Luce Line',                       'Luce Lice',),
   ('Gateway Trail',                   'Gateway',),
   ('Minnesota River Bluffs',          'River Bluffs',),
   ('South Saint Paul Regional Trail', 'S St Paul Tr',),
   ('RICE CREEK',                      'Rice Creek Tr',),
   ('Lake Minnetonka LRT Regional Trail', 'Lake Minnetonka Tr',),
   ('W River Pkwy Trail',              'W River Pwky',),
   ('Coon Creek Trail',                'Coon Creek Tr',),
   ('Dakota Rail',                     'Dakota Rail Trail',),
   ('Rush Creek Regional Trail',       'Rush Creek Trail',),
   ('', '',),
   )

"""

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)
      #
      self.groups_none_use_public = True

   #
   def prepare(self):
      '''Defines the CLI options for this script'''

      Ccp_Script_Args.prepare(self)

      # *** Disparate commands.

      # There are four typical usages for this script:
      # 1. Rebuild the public tables (e.g., public.tiles_mapserver_zoom).
      # 2. Rebuild the namespace tables (e.g., 'minnesota', 'colorado', etc.).
      # 3a. Populate the Cyclopath cache from scratch.
      # 3b. Do a (generally quick) update of recent changes.
      # 4a. Generate all tilecache tiles for whole branch bboxes.
      # 4b. Regenerate tiles in areas where changes have occurred.

      # *** Command 1: Rebuild the public tables.

      self.add_argument(
         #'-Z', # No shortcut: too cryptic, and command usually automated.
         '--db-create-public-zooms', dest='rebuild_cache_zooms',
         default=False, action='store_true',
         help='Command: Reset zoom cache for all instances')

      # *** Command 2: Rebuild the namespace tables.

      self.add_argument(
         #'-I', # No shortcut: too cryptic, and command usually automated.
         '--db-create-for-instance', dest='rebuild_cache_instance',
         default=False, action='store_true',
         help='Command: Reset attc and label cache for an instance')

      # If you rebuild the instance tables for all branches (--branch -1),
      # you can also remove the installation's tilecache cache folder.
      self.add_argument(
         '--remove-cache', dest='remove_cache',
         default=False, action='store_true',
         help='Command: Also remove the tilecache-cache folder')

      # *** Command 3: Populate/Update the Cyclopath cache.

      self.add_argument(
         '--cyclopath-cache', dest='generate_cyclopath_cache',
         default=False, action='store_true',
         help='With --all or --changed, rebuild Cyclopath cache')

      # *** Command 4: (Re)Generate the Tilecache cache.

      # CAVEAT: The calling user must by www-data/apache.
      #
      self.add_argument(
         '--tilecache-tiles', dest='generate_tilecache_tiles',
         default=False, action='store_true',
         help='With --all or --changed, recreate Tilecache tiles')

      # *** Options for Commands 3 and 4: Do --all or just --changed.
      #
      # Expected Runtime: It takes ~2 hours on Cyclopath circa 2011 to rebuild
      #                   all zoom levels, i.e., 9 through 15, e.g., "-z 9 15".
      self.add_argument(
         '-a', '--all', dest='rebuild_tiles_all', action='store_true',
         default=False,
         help='Rebuild all tiles from all geofeatures (~lots mins/hours)')
      #
      # Expected Runtime: Rebuilding tiles affected by geometry changes since
      #                   the last revision is generally pretty quick. But it
      #                   depends on what changed.
      self.add_argument(
         '-c', '--changed', dest='rebuild_tiles_changed', action='store_true',
         default=False,
         help='Rebuild changed tiles from feats changed since last revision')

      # *** Command 5: Recalculate Just the Label Priority.

      # 2013.01.09: Time on [pluto] on 47813 clusters: 0.47 mins. Hooray!
      self.add_argument(
         '-L', '--remake-label-priority', dest='remake_label_priority',
         default=False, action='store_true',
         help='Command: Just remake the label_priority')

      # *** Options for Commands 3 and/or 4

      # DEVS: Restrict to a bbox and/or zoom and/or tiles for testing.

      # **** Options for Command 3: Cyclopath cache options

      # Normally, you'll want to rebuild both the byway_segment cache and also
      # the byway_cluster cache, but other times you just want to test...

      self.add_argument(
         '-S', '--skip-cache-segment', dest='skip_cache_byway_segment',
         default=False, action='store_true',
         help='Do not update the byway_segment cache.')

      self.add_argument(
         '-T', '--skip-cache-cluster', dest='skip_cache_byway_cluster',
         default=False, action='store_true',
         help='Do not update the byway_cluster cache.')

      self.add_argument(
         '--keep-existing-caches', dest='keep_existing_caches',
         default=False, action='store_true',
         help='Do not drop and recreate either cache table.')

      # **** Options for both 3 and 4: Ccp Cache and Tiles runtime options

      # EXAMPLE: What's a good bbox for Minnesota for each zoom level, for
      #          testing? Find areas of the map with lots of different byway
      #          types, and other interesting items.

      # If you don't specify --bbox, the script will use the branch's
      # coverage_area (for --all) or the --bbox of the latest changes
      # (for --changed).

      self.add_argument(
         '-x', # legacy option
         '-B', # what ccp.py uses for --bbox; defined here so Ccp appears saner
         '--bbox', dest='restrict_bbox', type=float, nargs=4,
         default=None,
         help='Restrict tiles by a bounding box: --bbox XMIN YMIN XMAX YMAX')

      # You can also now specify county.
      # MAYBE: This uses the mndot_counties table. We could instead search
      #        Cyclopath for a matching region... which would be more
      #        Cyclopathy.
      self.add_argument(
         '-C', '--county', dest='restrict_counties',
         default=[], action='append', type=str,
         help='County name or ID to use to limit import')

      # **** Options for Command 4: tilecache_seed runtime options

      # Callers can specify zoom or tiles when testing and when running this
      # script asynchronously (since Python is single-threaded; but you can
      # achieve multi-threadedness by running many instances of the script
      # from, e.g., bash).

      self.add_argument(
         '-z', '--zoom', dest='restrict_zoom', type=int, nargs=2,
         default=(conf.ccp_min_zoom, conf.ccp_max_zoom),
         # E.g., --zoom 9 9 to restrict to rebuild just one zoom level.
         help='Restrict tiles by a zoom level: --zoom min_level max_level')

      # DEVS: As an alternative to --bbox, you can specify the TileCache tiles.
      # 2013.12.02: [lb] tried using this and it doesn't seem to work right --
      # I copied the tile coordinates for the lower-left zoom 5 tile (there's
      # just four tiles for the State of MN at that zoom) that flashclient
      # reported, but the bbox sent to tilecache_seed didn't share the same
      # lower-left x,y I'd seen used with the --tiles param.
      # So... the tile-coords-to-bbox translation seems wrong...
      self.add_argument(
         '-t', '--tiles', dest='tilecache_tiles', type=int, nargs=4,
         default=None,
         help='Specify TileCache tile indices: --tiles XMIN YMIN XMAX YMAX')

      # 2014.08.25: BUG nnnn: Implement: Process a window of tiles.
      # E.g., if you want to split work into three scripts, try:
      #  tilecache_update.py --split-load-total 3 --split-load-count 1 ... &
      #  tilecache_update.py --split-load-total 3 --split-load-count 2 ... &
      #  tilecache_update.py --split-load-total 3 --split-load-count 3 ... &
      self.add_argument(
         '--split-load-total', dest='split_load_total', type=int, default=None,
         help='Total scripts being used to build this zoom level(s).')
      self.add_argument(
         '--split-load-count', dest='split_load_count', type=int, default=None,
         help='1-based count of this script when using --split-load-total n')

      # *** Options for --all.

      # DEPRECATED: When this script was first writ, it was assumed it could
      # be run just once, i.e., with just one set of parameters. But it's
      # actually more complicated than that. So rather than default to
      # remaking the table and tile cache, don't
      #
      #  self.add_argument(
      #     '-T', '--skip-cache-table-remake', dest='skip_cache_table_remake',
      #     default=False, action='store_true',
      #     help='With --all or --changed, do not rebuild Cyclopath cache')
      #  self.add_argument(
      #     '-S', '--skip-cache-seed-remake', dest='skip_cache_seed_remake',
      #     default=False, action='store_true',
      #     help=
      #       'With --all or --changed, do not make tiles w/ tilecache_seed.')

      # Multiprocessor support

      # MAYBE: Enable async by default. Or set to 0 and use CONFIG proc cnt?
      # FIXME: async_procs is not implemented. See also check_cache_now.py.
      #        For now, the check_cache_now script runs this script multiple
      #        times simultaneously by using the --zoom option.
      #        FIXME: Herein, we could do something similar with the tile
      #        indices, i.e., make a queue of the tiles we want to generate
      #        and then fire off x number of side-to-side tilecache_seed
      #        processes. But, meh, unless we want to generate zoom levels
      #        16 or 17 or 18, we probably don't mind that zoom 15 takes
      #        four hours.
      # 2014.08.25: See instead: --split-load-total and --split-load-current
      self.add_argument(
         '-A', '--async-procs', dest='async_procs', type=int, default=1,
         #'-A', '--async', dest='async', default=False, action='store_true',
         help='Use mutliple processors to populate cache and make tiles.')

      # ***

      self.add_argument(
         '-n', '--skin', dest='chosen_skin',
         default=None, action='store', type=str,
         help='Specify the skins/skin_*.py file to use')

   #
   def verify(self):
      '''Verify the options. Handle the simplest of 'em.'''

      verified = Ccp_Script_Args.verify(self)

      action_cnt = (
         (0)
         + (1 if self.cli_opts.rebuild_cache_zooms is True else 0)
         + (1 if self.cli_opts.rebuild_cache_instance is True else 0)
         + (1 if self.cli_opts.generate_cyclopath_cache is True else 0)
         + (1 if self.cli_opts.generate_tilecache_tiles is True else 0)
         + (1 if self.cli_opts.remake_label_priority is True else 0)
         )
      if action_cnt != 1:
         log.error('Please specify one and only one command')
         verified = False
         self.handled = True

      if (self.cli_opts.generate_cyclopath_cache
          or self.cli_opts.generate_tilecache_tiles):
         if (not (self.cli_opts.rebuild_tiles_all
                  or self.cli_opts.rebuild_tiles_changed
                  )):
            log.error('%s%s' % ('Please specify --all or --changed with ',
                                '--cyclopath-cache or --tilecache-tiles',))
            verified = False
            self.handled = True

      if (self.cli_opts.remove_cache
          and (not (self.cli_opts.rebuild_cache_instance
                    or (self.cli_opts.generate_tilecache_tiles
                        and self.cli_opts.rebuild_tiles_all)))):
         log.error('%s%s'
                   % ('The option --remove-cache only works with commands ',
                      '--db-create-for-instance or --tilecache-tiles --all',))
         verified = False
         self.handled = True

      # These options are mutually exclusive: --bbox, --tiles, --county.
      me_cnt = ((1 if self.cli_opts.tilecache_tiles else 0)
              + (1 if self.cli_opts.restrict_bbox else 0)
              + (1 if self.cli_opts.restrict_counties else 0))
      if me_cnt > 1:
         log.error(
            'Switches --bbox, --tiles, and --county, are mutually exclusive.')
         verified = False
         self.handled = True

      # TileCache tile indices depend on zoom level. There should be only one.
      if self.cli_opts.tilecache_tiles:
         if ((len(self.cli_opts.restrict_zoom) != 2)
             or (self.cli_opts.restrict_zoom[0]
                 != self.cli_opts.restrict_zoom[1])):
            log.error(
               'The option --tiles must be used with exactly one --zoom n n')
            verified = False
            self.handled = True

      # If the user wants to rebuild tiles, we want the tiles built for
      # the www-data user.
      # FIXME: In CcpV1, tilecache_update was required (per this script) to run
      # from www-data, but I'm [lb] not convinced this is necessary. I think
      # there are two concerns: (1) which logfile gets writ, and (2) who owns
      # (or has read/write access to) the tiles we create.
      # For now, we'll just require the www-data user only if rebuilding tiles.
      if (self.cli_opts.generate_cyclopath_cache
          or self.cli_opts.generate_tilecache_tiles):
         # To rebuild tiles, run as the httpd user.
         if ((os.getenv('LOGNAME') != 'apache') # Fedora
             and (os.getenv('LOGNAME') != 'www-data')): # Ubuntu
            log.error('%s%s' % ('To (re)build tiles, please run this script ',
                                'as www-data (Ubuntu) or apache (Fedora)',))
            verified = False
            self.handled = True
            apache_user = None
         else:
            apache_user = os.getenv('LOGNAME')
            # The tilecache directory should be owned by apache or www-data.
            # os.getenv('LOGNAME') is 'www-data' (Ubuntu) or 'apache' (Fedora).
            pw_db_entry = pwd.getpwnam(apache_user)
            uid = pw_db_entry.pw_uid
            grp_db_entry = grp.getgrnam(apache_user)
            gid = grp_db_entry.gr_gid
            try:
               f_stat = os.stat(conf.tilecache_cache_dir)
            except OSError, e:
               # Weird. At other places, this is IOError.
               #  OSError: [Errno 2] No such file or directory:
               #     '/ccp/var/tilecache-cache/cycloplan_live'
               if e[0] == 2:
                  log.debug('verify: no such dir: %s' % (str(e),))
                  try:
                     # MAGIC_NUMBER: Setup the directory permissions.
                     os.mkdir(conf.tilecache_cache_dir, 02775)
                     # 2013.05.06: Need to chmod?
                     os.chmod(conf.tilecache_cache_dir, 02775)
                     f_stat = os.stat(conf.tilecache_cache_dir)
                  except OSError, e:
                     log.error('verify: OSError: %s' % (str(e),))
                     raise Exception('verify: Cannot mkdir %s.'
                                     % (conf.tilecache_cache_dir,))
               else:
                  log.warning('verify: unexpected error: %s' % (str(e),))
                  raise Exception('verify: Cannot os.stat %s.'
                                  % (conf.tilecache_cache_dir,))
# FIXME: verbose
            log.debug('Cache dir "%s" owned by usr/grp "%s"/"%s".'
               % (conf.tilecache_cache_dir, f_stat.st_uid, f_stat.st_gid,))
            if (f_stat.st_uid != uid) or (f_stat.st_gid != gid):
               log.error(
                  'User %s must own "%s" / not %s-%s / uid %d-%d / gid %d-%d'
                  % (apache_user, conf.tilecache_cache_dir,
                     pw_db_entry.pw_name, grp_db_entry.gr_name,
                     f_stat.st_uid, uid, f_stat.st_gid, gid,))
               verified = False
               self.handled = True

      return verified

# *** TileCache_Update

class TCU(Ccp_Script_Base):

   # *** Constructor

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)

      self.cur_branch_sid = None
      self.cur_skin_name = None
      self.cur_tile_skin = None

      self.locks_locked = []

   # ***

   # This script's main() is very simple: it makes one of these objects and
   # calls go(). Our base class reads the user's command line arguments and
   # creates a query_builder object for us at self.qb before thunking to
   # go_main().

   #
   def go_main(self):

      self.qb.db.transaction_begin_rw()

      log.info('Go go main main')

      # DROP and CREATE the cache tables, maybe.

      if self.cli_opts.rebuild_cache_zooms:
         # Usually, it's either a DEV or a cron job that blocks other cron jobs
         # that calls us, but we can sync with other instances, just in case.
         # This adds a silly layer of complexity -- if the script fails, you'll
         # have to remember to delete from async_locks on your own. Anyway,
         # make sure we're the only one accessing the tilecache tables.
         self.get_lock_for_script()

         # Delete and re-create the public GFL-skin-and-zoom cache tables.
         self.reset_tables_cache_skin()

      elif ((self.cli_opts.rebuild_cache_instance)
            or (self.cli_opts.generate_cyclopath_cache
                and self.cli_opts.rebuild_tiles_all
                and (not self.cli_opts.restrict_counties)
                and (not self.cli_opts.restrict_bbox))):

         # Get the script-wide lock just in case.
         # 2013.05.26: Hahaha, "just in case"! Totally in case!
         #  I [lb] forget --skip-cache-table-remake and this is running
         #  from apache_check_cache_now on multiple branches, so only one
         #  branch was running and the rest died on not getting the lock! So
         #  this is totally a necessary mechanism. Hooray for locking!

         # See comments above: we're don't really need to lock, but it's good
         # form. And don't forget to delete from async_locks if this scripts
         # dies while holding any locks.
         self.get_lock_for_script()

         # Recreate the cache tables for the instance.
         # MAYBE: Do this for all instances?
         #          for server_instance in conf.server_instances:
         self.reset_tables_cache_instance()

      # Prepare the bbox, if caller is asking to restrict what we do.

      self.prepare_bbox_restriction()

      # Update the Cyclopath cache tables.

      self.update_cyclopath_cache()

      # Commit now. We'll commit updates to the key_value_pair as we go through
      # the tile layers.

      self.query_builder_destroy(do_commit=(not debug_skip_commit))

      # Make a new qb for the tiles operation.
      g.assurt(self.qb is None)
      self.query_builder_prepare()

      # Update the MapServer tiles using TileCache.

      self.update_tilecache_cache()

      # Release the locks.

      if self.locks_locked:
         self.qb.db.transaction_begin_rw()
         # (Always release locks in the opposite order from whence you locked.)
         self.locks_locked.reverse()
         for lock_name in self.locks_locked:
            self.qb.db.delete('public.async_locks', {'lock_name': lock_name,})
            log.debug('ASYNC_LOCKS: Released lock named: %s.' % (lock_name,))
         self.locks_locked = []
         # Count it!
         self.query_builder_destroy(do_commit=(not debug_skip_commit))

      # Cleanup.

      self.query_builder_destroy(do_commit=(not debug_skip_commit))

      # This script is run asynchronously by check_cache_now, which sits and
      # waits while we all complete. So print a contextually helpful message.
      log.debug('go_main: finished: argv: %s' % (sys.argv,))

   # ***

   #
   def get_lock_for_script(self):
      # This tries to get a lock for script-wide operations, like deleting and
      # creating the public skin/zoom cache or the instance cache tables.
      try:
         # Try to get a lock on the row with key = 'tilecache-last_rid'.
         # This creates such an entry if one does not already exist.
         cache_level_key_name = self.get_last_rid_key_prefix()
         self.qb.db.insert_and_lock_row(
            'public.async_locks', 'lock_name', cache_level_key_name)
         log.debug('ASYNC_LOCKS: Got cache-level lock.')
         self.locks_locked.append(cache_level_key_name)
      except psycopg2.OperationalError, e:
         log.error('Could not get cache-level lock; bailing.')
         sys.exit(1)

   #
   def try_lock_for_branch(self):
      # This tries to get a lock on the branch, to prevent updating the cache
      # table simultaneously. We could also lock on recreating tiles, but
      # running the script twice accidentally on tiles doesn't hurt anything,
      # it's just a waste of time.
      locked = False
      try:
         branch_level_key_name = self.get_last_rid_key_name_byways()
         self.qb.db.insert_and_lock_row(
            'public.async_locks', 'lock_name', branch_level_key_name)
         locked = True
         log.debug('ASYNC_LOCKS: Got branch-level lock on: %s.'
                   % (branch_level_key_name,))
         self.locks_locked.append(branch_level_key_name)
      except psycopg2.OperationalError, e:
         log.warning('ASYNC_LOCKS: Could not get branch-level lock on: %s.'
                     % (branch_level_key_name,))
      return locked

   # *** Map skins table (all instances)

   #
   def reset_tables_cache_skin(self):

      log.info('Resetting the public database tables')

      # 2012.12.28: Deprecated:
      log.debug('Dropping views tiles_mapserver_view')
      for server_instance in conf.server_instances:
         self.drop_instance_table_tiles_mapserver_view(server_instance)

      # 2012.12.28: Deprecated:
      log.debug('Dropping table tiles_mapserver_zooooom')
      self.qb.db.sql("DROP TABLE IF EXISTS public.tiles_mapserver_zooooom")

      # 2012.12.28: Deprecated:
      log.debug('Dropping table tiles_mapserver_zooooom_2')
      self.qb.db.sql("DROP TABLE IF EXISTS public.tiles_mapserver_zooooom_2")

      # This is the human-readable and one-terminal-wide skin table.
      log.debug('Dropping view tiles_mapserver_zoom_view')
      self.qb.db.sql("DROP VIEW IF EXISTS public.tiles_mapserver_zoom_view")

      # This is the real skin table, with long column_names.
      log.debug('Dropping table tiles_mapserver_zoom')
      self.qb.db.sql("DROP TABLE IF EXISTS public.tiles_mapserver_zoom")

      self.prepare_mapserver_zoom_table()

   #
   def drop_instance_table_tiles_mapserver_view(self, instance_name):

      self.qb.db.sql("DROP VIEW IF EXISTS %s.tiles_mapserver_view"
                     % (instance_name,))
      dimension = 2
      self.qb.db.sql(
         """
         DELETE FROM
            geometry_columns
         WHERE
                f_table_schema = '%s'
            AND f_table_name = 'tiles_mapserver_view'
         """ % (instance_name,))

   #
   def prepare_mapserver_zoom_table(self):

      log.debug('Creating table tiles_mapserver_zoom')

      self.prepare_mapserver_zoom_table_create('tiles_mapserver_zoom', [])

      # Make a convenience view for developers.
      self.prepare_mapserver_zoom_table_view()

   #
   def prepare_mapserver_zoom_table_create(self, table_name, gfl_ids):
      if gfl_ids:
         # 2012.12.28: Deprecated:
         g.assurt(False)
         row_gfl_id = ""
         row_gfl_pk = ""
         sql_create_index = ""
      else:
         row_gfl_id = ", geofeature_layer_id INTEGER NOT NULL"
         row_gfl_pk = ", geofeature_layer_id"
         sql_create_index = (
            "CREATE INDEX %s_geofeature_layer_id ON %s (geofeature_layer_id)"
            % (table_name, table_name,))
         gfl_ids.append(None)
      # Create, e.g., tiles_mapserver_zoom or tiles_mapserver_zooooom
      sql_create_table = (
         """
         CREATE TABLE public.%s (
            skin_name           TEXT    NOT NULL -- E.g., 'bikeways'
            --, ccp_branch_id   INTEGER NOT NULL
            --, ccp_group_id    INTEGER NOT NULL
            , zoom_level        INTEGER NOT NULL
            %s
         """ % (table_name, row_gfl_id,))
      for gfl_id in gfl_ids:
         if not gfl_id:
            postfix = ""
         else:
            postfix = "_%d" % gfl_id
         interp = {'pf': postfix}
         sql_create_table += (
            """
               , do_draw%(pf)s         BOOLEAN  NOT NULL DEFAULT TRUE
               , pen_color_s%(pf)s     TEXT     NOT NULL DEFAULT '0 0 0'
               , pen_color_i%(pf)s     INTEGER  NOT NULL DEFAULT x'000000'::INT
               , pen_width%(pf)s       REAL     NOT NULL
               , pen_gutter%(pf)s      REAL     NOT NULL
               , do_shadow%(pf)s       BOOLEAN  NOT NULL DEFAULT TRUE
               , shadow_width%(pf)s    REAL     NOT NULL DEFAULT 2.0
               , shadow_color_s%(pf)s  TEXT     NOT NULL DEFAULT '255 255 255'
               , shadow_color_i%(pf)s  INTEGER  NOT NULL DEFAULT x'FFFFFF'::INT
               , do_label%(pf)s        BOOLEAN  NOT NULL DEFAULT FALSE
               , label_size%(pf)s      INTEGER  NOT NULL DEFAULT 0
               , label_color_s%(pf)s   TEXT     NOT NULL DEFAULT '0 0 0'
               , label_color_i%(pf)s   INTEGER  NOT NULL DEFAULT x'000000'::INT
               , labelo_width%(pf)s    REAL     NOT NULL DEFAULT 0.0
               , labelo_color_s%(pf)s  TEXT     NOT NULL DEFAULT '255 255 255'
               , labelo_color_i%(pf)s  INTEGER  NOT NULL DEFAULT x'FFFFFF'::INT
               , l_bold%(pf)s          BOOLEAN  NOT NULL DEFAULT FALSE
               , l_force%(pf)s         BOOLEAN  NOT NULL DEFAULT FALSE
               , l_partials%(pf)s      BOOLEAN  NOT NULL DEFAULT FALSE
               , l_outlinewidth%(pf)s  INTEGER  NOT NULL DEFAULT 3

               -- MAYBE/TRY_IT_OUT/EXPLAIN: Make the default 'auto'.
               , l_minfeaturesize%(pf)s TEXT    NOT NULL DEFAULT '1'
               --, l_minfeaturesize%(pf)s TEXT    NOT NULL DEFAULT 'auto'

               , l_restrict_named%(pf)s TEXT    NOT NULL DEFAULT ''
               , l_restrict_stack_ids%(pf)s TEXT NOT NULL DEFAULT ''
               , l_strip_trail_suffix%(pf)s BOOLEAN NOT NULL DEFAULT FALSE
               , l_only_bike_facils%(pf)s BOOLEAN  NOT NULL DEFAULT FALSE
               , p_min%(pf)s           INTEGER  NOT NULL DEFAULT 0
               , p_new%(pf)s           INTEGER  NOT NULL DEFAULT 0
               , d_geom_len%(pf)s      INTEGER  NOT NULL DEFAULT 0
               , d_geom_area%(pf)s     INTEGER  NOT NULL DEFAULT 0
               , l_geom_len%(pf)s      INTEGER  NOT NULL DEFAULT 0
               , l_geom_area%(pf)s     INTEGER  NOT NULL DEFAULT 0
            """ % interp)
      sql_create_table += ")"
      self.qb.db.sql(sql_create_table)
      self.qb.db.sql("CREATE INDEX %s_zoom_level ON %s (zoom_level)"
                     % (table_name, table_name,))
      if sql_create_index:
         self.qb.db.sql(sql_create_index)

      self.qb.db.sql(
         """
         ALTER TABLE public.%s
         ADD CONSTRAINT %s_pkey
         PRIMARY KEY (skin_name, zoom_level %s);
         """ % (table_name, table_name, row_gfl_pk,))

   #
   def prepare_mapserver_zoom_table_view(self):
      self.qb.db.sql(
         """
         CREATE VIEW public.tiles_mapserver_zoom_view AS SELECT
            skin_name               AS skn
            --, ccp_branch_id       AS
            --, ccp_group_id        AS
            , zoom_level            AS zm
            , geofeature_layer_id   AS gfl
            , do_draw               AS drw
            , pen_color_s           AS dr_clrs
            , pen_color_i           AS dr_clri
            , pen_width             AS dwi
            , pen_gutter            AS dgu
            , do_shadow             AS shd
            , shadow_width          AS shw
            , shadow_color_s        AS sh_clrs
            , shadow_color_i        AS sh_clri
            , do_label              AS lbl
            , label_size            AS lbs
            , label_color_s         AS lb_clrs
            , label_color_i         AS lb_clri
            , labelo_width          AS low
            , labelo_color_s        AS lo_clrs
            , labelo_color_i        AS lo_clri
            , l_bold                AS lbld
            , l_force               AS lfor
            , l_partials            AS lpar
            , l_outlinewidth        AS lolw
            , l_minfeaturesize      AS lmfz
            , l_restrict_named      AS lrst
            , l_restrict_stack_ids  AS lrsd
            , l_strip_trail_suffix  AS lstr
            , l_only_bike_facils    AS loly
            , p_min                 AS pmin
            , p_new                 AS pnew
            , d_geom_len            AS dlen
            , d_geom_area           AS drea
            , l_geom_len            AS llen
            , l_geom_area           AS lrea
         FROM
            public.tiles_mapserver_zoom
         ORDER BY
            skin_name ASC
            , zoom_level ASC
            , geofeature_layer_id DESC
         """)

   #
   # FIXME: move this to a util class.
   RE_PARSE_COLOR = re.compile(r'\D+')
   @staticmethod
   def parse_color(color_s):
      #log.debug('parse_color: %s' % color_s)
      r,g,b = TCU.RE_PARSE_COLOR.split(color_s)
      return (int(r) << 16) + (int(g) << 8) + int(b)

   #
   def repopulate_cache_zoom(self):

      if self.cur_skin_name not in self.skins_populated:

         self.repopulate_cache_zoom_()

         self.skins_populated.add(self.cur_skin_name)

   #
   def repopulate_cache_zoom_(self):

      # Populate the skin definitions.

      table_name = 'tiles_mapserver_zoom'

      # Circa 2012: Before [lb] figured out we need thousands of MapServer
      # layers, we instead made a crazy SQL table with columns for each zoom
      # level.
      is_sane = True
      g.assurt(is_sane) # Other usage is deprecated.

      log.debug('Clearing tiles_mapserver_zoom: skin_name: %s'
                % (self.cur_skin_name,))

      delete_sql = (
         "DELETE FROM tiles_mapserver_zoom WHERE skin_name = %s"
         % (self.qb.db.quoted(self.cur_skin_name),))
      self.qb.db.sql(delete_sql)

      log.debug('Populating tiles_mapserver_zoom: skin_name: %s'
                % (self.cur_skin_name,))
      # SYNC_ME: See zoom_levels_cache in this file.
      zoom_rows = {}

      # We don't really need to sort but then the table is sorted by default.
      # This is the list of GFL IDs, used inside the outer for loop.
      gfl_ids = list(self.cur_tile_skin.gfls_deffed)
      gfl_ids.sort()
      # This is the list of zoom levels, used for the outer loop.
      zoom_levels = list(self.cur_tile_skin.zooms_deffed)
      zoom_levels.sort()
      # This is the outer loop: do zoom levels, i.e., conf.ccp_min_zoom to
      # conf.ccp_max_zoom.
      for zoom_level in zoom_levels:
         # This is the inner loop of byway.Geofeature_Layer attributes.
         # BUG nnnn: Put terrain and point pens and zooms in the skin file.
         #           (They're currently hard-coded in the map file.)
         for gfl_id in gfl_ids:
            log.verbose('_zoom_table_update: zoom_level: %d / gfl_id: %d'
                        % (zoom_level, gfl_id,))
            feat_pen = self.cur_tile_skin.feat_pens[gfl_id]
            tile_pen = self.cur_tile_skin.tile_pens[gfl_id][zoom_level]
            # Make the dict for which to insert a new row into the database.
            pkeys = {}
            pkeys['skin_name'] = self.cur_skin_name
            #pkeys['ccp_branch_id'] = zoom_level
            #pkeys['ccp_group_id'] = zoom_level
            pkeys['zoom_level'] = zoom_level
            if is_sane:
               pf = ""
               pkeys['geofeature_layer_id'] = gfl_id
               g.assurt(pkeys['geofeature_layer_id'] != 0)
            else:
               # 2012.12.28: Deprecated: We used to make columns for every
               # setting for every geofeature_layer_id, but then we figured out
               # we could just build a 300K line mapfile for MapServer and get
               # better control.
               g.assurt(False) # Deprecated
               pf = "_%d" % gfl_id
            #
            cols = {}
            cols['do_draw%s' % pf] = tile_pen.do_draw
            cols['pen_gutter%s' % pf] = tile_pen.pen_gutter
            cols['pen_width%s' % pf] = tile_pen.pen_width
            cols['pen_color_s%s' % pf] = feat_pen.pen_color
            cols['pen_color_i%s' % pf] = TCU.parse_color(feat_pen.pen_color)
            # FIXME: Maybe get rid of do_shadow? If 0 width works in STYLE...
            cols['do_shadow%s' % pf] = False
            cols['shadow_width%s' % pf] = 0
            if feat_pen.shadow_width > 0:
               cols['do_shadow%s' % pf] = True
               cols['shadow_width%s' % pf] = (tile_pen.pen_width
                                              + feat_pen.shadow_width)
            cols['shadow_color_s%s' % pf] = feat_pen.shadow_color
            cols['shadow_color_i%s' % pf] = TCU.parse_color(
                                       feat_pen.shadow_color)
            cols['do_label%s' % pf] = tile_pen.do_label
            cols['label_size%s' % pf] = tile_pen.label_size
            cols['label_color_s%s' % pf] = feat_pen.label_color
            cols['label_color_i%s' % pf] = TCU.parse_color(
                                       feat_pen.label_color)
            cols['labelo_width%s' % pf] = feat_pen.labelo_width
            cols['labelo_color_s%s' % pf] = feat_pen.labelo_color
            cols['labelo_color_i%s' % pf] = TCU.parse_color(
                                       feat_pen.labelo_color)
            cols['l_bold%s' % pf] = tile_pen.l_bold
            cols['l_force%s' % pf] = tile_pen.l_force
            cols['l_partials%s' % pf] = tile_pen.l_partials
            cols['l_outlinewidth%s' % pf] = tile_pen.l_outlinewidth
            cols['l_minfeaturesize%s' % pf] = tile_pen.l_minfeaturesize
            cols['l_restrict_named%s' % pf] = (
               '(%s)' % ('|'.join(tile_pen.l_restrict_named),))
            cols['l_restrict_stack_ids%s' % pf] = (
               '(%s)' % ('|'.join([str(x) for x
                                   in tile_pen.l_restrict_stack_ids])),)
            cols['l_strip_trail_suffix%s' % pf] = tile_pen.l_strip_trail_suffix
            cols['l_only_bike_facils%s' % pf] = tile_pen.l_only_bike_facils
            cols['p_min%s' % pf] = tile_pen.p_min
            cols['p_new%s' % pf] = tile_pen.p_new
            cols['d_geom_len%s' % pf] = tile_pen.d_geom_len
            cols['d_geom_area%s' % pf] = tile_pen.d_geom_area
            cols['l_geom_len%s' % pf] = tile_pen.l_geom_len
            cols['l_geom_area%s' % pf] = tile_pen.l_geom_area
            #
            if is_sane:
               self.qb.db.insert(table_name, pkeys, cols)
            else:
               g.assurt(False) # Deprecated usage.
               if not pkeys['zoom_level'] in zoom_rows:
                  zoom_rows[pkeys['zoom_level']] = [pkeys, cols,]
               else:
                  zoom_rows[pkeys['zoom_level']][1].update(cols)
         # end: for gfl_id in gfl_ids
      # end: for zoom_level in zoom_levels

      if zoom_rows:
         g.assurt(not is_sane)
         g.assurt(False) # Deprecated usage.
         for k,v in zoom_rows.iteritems():
            self.qb.db.insert(table_name, v[0], v[1])

   # *** Instance segment and cluster cache creation

   #
   def reset_tables_cache_instance(self):

      # See postgres': pg_namespace.nspname.
      # What we call INSTANCE is a postgres namespace.
      log.info('Resetting the namespace database tables')

      # 2012.12.28: Deprecated table:
      log.debug('Dropping (deprecated) view tiles_mapserver_view')
      self.drop_instance_table_tiles_mapserver_view(conf.instance_name)

      # Delete all the last_rid for the branch (for skins and zoom levels of
      # Cyclopath cache, and for the tilecache cache). This is, i.e.,
      #   LIKE 'tilecache-last_rid%'
      self.qb.db.sql("DELETE FROM key_value_pair WHERE key LIKE '%s%%'"
                     % (self.get_last_rid_key_prefix(),))

      # Create the cache table of individual line segments, used by TileCache
      # to draw line segments.
      if ((not self.cli_opts.skip_cache_byway_segment)
          and (not self.cli_opts.keep_existing_caches)):
         self.tile_cache_byway_segment_create()

      # Create the cache of table of resegmented line segments. We use this to
      # a) draw cycleroute line segments, and b) to label line segments.
      if ((not self.cli_opts.skip_cache_byway_cluster)
          and (not self.cli_opts.keep_existing_caches)):
         self.tile_cache_byway_cluster_create()

   # Create cache table: Byway Segments

   #
   def tile_cache_byway_segment_create(self):

      log.debug('Dropping table tiles_cache_byway_segment')

      # 2012.12.28: Deprecated: This is what this table used to be called:
      self.qb.db.sql("DROP TABLE IF EXISTS tiles_cache_byway_attcs CASCADE")

      # This is the current name of this cache table:
      self.qb.db.sql("DROP TABLE IF EXISTS tiles_cache_byway_segment CASCADE")

      log.debug('Creating table tiles_cache_byway_segment')
      # MAYBE: Do we need generic_rating? Is it used anymore? Not for tiles
      #        anymore... but maybe someday again?
      # Skipping: version INTEGER NOT NULL;
      #           see: self.last_rid_key_name (e.g., "tilecache_last_rid...").
      # Skipping: name TEXT; since this cache is only used to draw line
      #                      segments and is not used to label.
      self.qb.db.sql(
         """
         CREATE TABLE %s.tiles_cache_byway_segment (
              system_id INTEGER NOT NULL
            , stack_id INTEGER NOT NULL
            , branch_id INTEGER NOT NULL
            , geofeature_layer_id INTEGER NOT NULL
            , z_level INTEGER NOT NULL
            , generic_rating REAL NOT NULL
            , bike_facility_or_caution TEXT DEFAULT NULL
            , travel_restricted BOOLEAN NOT NULL DEFAULT FALSE
         )
         """ % (conf.instance_name,))

      self.qb.db.sql(
         """
         ALTER TABLE %s.tiles_cache_byway_segment
         ADD CONSTRAINT tiles_cache_byway_segment_pkey
            PRIMARY KEY (stack_id, branch_id)
         """ % (conf.instance_name,))

      self.add_geometry_column('tiles_cache_byway_segment')

   # Create cache table: Byway Clusters

   #
   def tile_cache_byway_cluster_create(self):

      # 2012.12.28: Deprecated: This is what this table used to be called:
      log.debug('Dropping (deprecated) table tiles_cache_byway_names')
      self.qb.db.sql("DROP TABLE IF EXISTS tiles_cache_byway_names")

      # We could use DROP TABLE ... CASCADE, or we could be deliberate.
      log.debug('Dropping view _tclust')
      self.qb.db.sql("DROP VIEW IF EXISTS _tclust")

      # This is the current name of this cache table... including a link table.
      log.debug('Dropping table tiles_cache_clustered_byways')
      self.qb.db.sql("DROP TABLE IF EXISTS tiles_cache_clustered_byways")
      log.debug('Dropping table tiles_cache_byway_cluster')
      self.qb.db.sql("DROP TABLE IF EXISTS tiles_cache_byway_cluster")

      log.debug('Creating table tiles_cache_byway_cluster')

      # MAYBE: Add column, cluster_nick TEXT NOT NULL, to store shorthand
      #  names for higher zoom levels... or just do the dirty work in
      #  make_mapfile and put the name mappings/conversion in the mapfile.

      self.qb.db.sql(
         """
         CREATE TABLE %s.tiles_cache_byway_cluster (
            cluster_id SERIAL PRIMARY KEY
            , cluster_name TEXT NOT NULL
            , branch_id INTEGER NOT NULL
            , byway_count INTEGER NOT NULL
            , label_priority INTEGER NOT NULL
            , winningest_gfl_id INTEGER NOT NULL
            , winningest_bike_facil TEXT DEFAULT NULL
            , is_cycle_route BOOLEAN NOT NULL DEFAULT FALSE
         )
         """ % (conf.instance_name,))

      self.qb.db.sql(
         """
         CREATE INDEX tiles_cache_byway_cluster_cluster_name
            ON tiles_cache_byway_cluster (cluster_name, branch_id)
         """)

      self.qb.db.sql(
         """
         CREATE INDEX tiles_cache_byway_cluster_label_priority
            ON tiles_cache_byway_cluster (label_priority)
         """)

      self.qb.db.sql(
         """
         ALTER TABLE %s.tiles_cache_byway_cluster
            ADD CONSTRAINT tiles_cache_byway_cluster_winningest_gfl_id_fkey
            FOREIGN KEY (winningest_gfl_id)
            REFERENCES geofeature_layer(id) DEFERRABLE
         """ % (conf.instance_name,))

      self.qb.db.sql(
         """
         CREATE INDEX tiles_cache_byway_cluster_is_cycle_route
            ON tiles_cache_byway_cluster (is_cycle_route)
         """)

      self.add_geometry_column('tiles_cache_byway_cluster')

      # There's also a link table.

      self.qb.db.sql(
         """
         CREATE TABLE %s.tiles_cache_clustered_byways (
            cluster_id INTEGER NOT NULL
            , byway_stack_id INTEGER NOT NULL
            , byway_branch_id INTEGER NOT NULL
         )
         """ % (conf.instance_name,))

      self.qb.db.sql(
         """
         ALTER TABLE %s.tiles_cache_clustered_byways
            ADD CONSTRAINT tiles_cache_clustered_byways_pkey
            PRIMARY KEY (cluster_id, byway_stack_id, byway_branch_id);
         """ % (conf.instance_name,))

      # And then there's the dev view.
      #
      # C.f. scripts/dev/convenience_views.sql

      self.qb.db.sql(
         """
         CREATE OR REPLACE VIEW %s._tclust AS
            SELECT
               branch_id AS brn_id,
               cluster_id AS c_id,
               cluster_name AS cluster_name,
               byway_count AS bway_cnt,
               winningest_gfl_id AS gfl_id,
               winningest_bike_facil AS bk_fac,
               is_cycle_route AS cyc_rt,
               label_priority AS lbl_pri,
               ST_Length(geometry)::BIGINT AS geom_len,
               ST_Area(ST_Box2D(geometry))::BIGINT AS geom_area
            FROM
               %s.tiles_cache_byway_cluster
            ORDER BY
               geom_area DESC
         """ % (conf.instance_name,
                conf.instance_name,))

   #
   def add_geometry_column(self, table_name):
      dimension = 2
      self.qb.db.sql(
         """
         SELECT AddGeometryColumn(
            '%s', 'geometry', (SELECT cp_srid()), 'GEOMETRY', %d)
         """ % (table_name, dimension,))
      self.qb.db.sql(
         """
         ALTER TABLE %s
            ADD CONSTRAINT enforce_valid_geometry
               CHECK (IsValid(geometry))
         """ % (table_name,))
      # Olde PostGIS 1.x format: USING GIST (geometry GIST_GEOMETRY_OPS).
      self.qb.db.sql(
         """
         CREATE INDEX %s_geometry ON %s
            USING GIST (geometry)
         """ % (table_name, table_name,))

   # ***

   #
   def setup_qbs(self, branch_, zoom_level=None):

      g.assurt(self.cur_branch_sid)

      g.assurt(not (self.cur_skin_name or zoom_level)
               or (self.cur_skin_name and zoom_level))

      # If we're updating the cache, we check the last rid used to update the
      # cache -- if it doesn't exist, we'll update from revision 0 by using
      # revision.Historic (i.e., rebuild the entire cache from scratch), or
      # we'll use revision.Update and just rebuild the parts of the cache that
      # need rebuilding. However, if we're updating tiles, we check the last
      # rid used to build the tiles for that branch-skin-zoom, and we build our
      # bbox based on that.
      self.rid_former = self.get_last_rid(zoom_level)

      self.rebuild_all = (self.cli_opts.rebuild_tiles_all
                          or (not self.rid_former))
      log.debug('setup_qbs: last rid: %d / rebuilding all?: %s'
                % (self.rid_former, self.rebuild_all,))

      # Get the current version of the database (this is so we don't have to
      # worry about someone saving and creating a new revision).
      self.rid_latest = revision.Revision.revision_max(self.qb.db)

      # Don't bother with the caches if nothing is changed.
      if ((self.cli_opts.generate_cyclopath_cache
           or self.cli_opts.generate_tilecache_tiles)
          and (not self.rebuild_all)
          and (self.rid_former == self.rid_latest)):
         self.qb_latest = None
         self.qb_update = None
         log.debug('setup_qbs: revision has not changed: nothing to do: at: %s'
                   % (self.rid_latest,))
      else:
         self.setup_qb_latest()
         self.setup_qb_update()

   #
   def close_qbs(self):

      del self.rebuild_all

      # Remove attrs that setup_qbs created.
      if self.qb_latest is not None:
         # NOTE: Not calling close, because these use self.qb.db.
         del self.qb_latest

      if self.qb_update is not None:
         # NOTE: Not calling close, because these use self.qb.db.
         # Well, we'll reset the connection if we started a transaction.
         if self.qb_update.db.transaction_in_progress():
            self.qb_update.db.transaction_rollback()
         del self.qb_update

      del self.rid_former

      del self.rid_latest

   #
   def get_skin_names(self, branch_):
      if self.cli_opts.chosen_skin:
         skin_names = [self.cli_opts.chosen_skin,]
      elif branch_.tile_skins:
         skin_names = branch_.get_skin_names()
      else:
         log.debug('Skipping branch: tile_skins not set: "%s" (%d)'
                   % (branch_.name, branch_.stack_id,))
         skin_names = []
      log.debug('get_skin_names: skin_names: %s' % (skin_names,))
      return skin_names

   #
   def get_tile_skin(self):

      module_path = ('skins.skin_%s' % (self.cur_skin_name,))
      skin_module = Mod_Loader.load_package_module(module_path)

      tile_skin = skin_module.get_skin()
      g.assurt(tile_skin is not None)

      return tile_skin

   # ***

   #
   def prepare_bbox_restriction(self):

      if self.cli_opts.restrict_counties:

         the_counties = MnDOT_Helper.resolve_to_county_ids(
                  self.qb, self.cli_opts.restrict_counties)
         self.county_ids = the_counties.keys()

         county_bbox_sql = (
            """
            SELECT ST_Box2d(ST_Collect(geometry))
            FROM state_counties WHERE county_num IN (%s)
            """ % (','.join([str(x) for x in self.county_ids]),))

         rows = self.qb.db.sql(county_bbox_sql)

         if not rows:
            raise Exception('No bbox for counties: %s'
                            % (self.cli_opts.restrict_counties,))

         g.assurt(len(rows) == 1)

         boxy = geometry.wkt_box_to_tuple(rows[0]['st_box2d'])

         self.restrict_bbox = rect.Rect(boxy[0], boxy[1], boxy[2], boxy[3])

         log.debug('restrict_bbox: by county: %s / counties: %s / ids: %s'
            % (self.restrict_bbox, the_counties.values(), self.county_ids,))

      elif self.cli_opts.restrict_bbox:

         self.restrict_bbox = rect.Rect(self.cli_opts.restrict_bbox[0],
                                        self.cli_opts.restrict_bbox[1],
                                        self.cli_opts.restrict_bbox[2],
                                        self.cli_opts.restrict_bbox[3])

         log.debug('restrict_bbox: by bbox: %s' % (self.restrict_bbox,))

      else:

         self.restrict_bbox = None

         log.debug('restrict_bbox: None')

   # ***

   #
   def update_cyclopath_cache(self):

      if self.cli_args.branch_id:
         # Find just the one branch.
         g.assurt(self.qb.branch_hier[0][0] == self.cli_args.branch_id)
      else:
         # Find all branches. E.g., caller specified --branch -1.
         g.assurt(self.cli_opts.branch[0] == -1)
         g.assurt(not self.cli_args.branch_hier)
         # What's the qb say the branch_hier is?
         g.assurt(not self.qb.branch_hier)

      self.skins_populated = set()

      # We iterate over one or more branches and one or more tile skins.

      if (self.cli_opts.rebuild_cache_zooms
          or self.cli_opts.rebuild_cache_instance
          or self.cli_opts.remake_label_priority
          or self.cli_opts.generate_cyclopath_cache):
         log.info('Updating database on all branches')
         self.branch_iterate(qb=self.qb,
                             branch_id=self.cli_args.branch_id,
                             branch_callback=self.update_cache_for_branch,
                             debug_limit=debug_limit)

      else:
         log.debug('update_cyclopath_cache: Skipping per cli_opts/args')
         g.assurt(self.cli_opts.generate_tilecache_tiles)

   #
   def update_cache_for_branch(self, branch_):

      log.debug('Updating cache: branch "%s" (%d)'
                % (branch_.name, branch_.stack_id,))
      log.debug(' ... tile_skins: %s' % (branch_.tile_skins,))

      self.cur_branch_sid = branch_.stack_id

      # Get the branch cache lock. This is really only necessary if, e.g., cron
      # is set to run the script every minute but a DEV wants to tinker on the
      # command line -- one of them shouldn't be allowed to run, or you'll end
      # up doing unnecessary work and one script's commit failing. (If the dev
      # isn't tinkering the cron tries to run us every minute, see
      # check_cache_now: we use a directory-lock to prevent calling this script
      # twice at once.)
      # RACE CONDITION?: MEH: We're called by self.branch_iterate. If two
      # scripts ran at once and branch_iterate didn't return the branches in
      # the same order to both scripts, we could end up in deadlock, i.e.,
      # script 1 locks branch A and script 2 locks branch B and then script 1
      # tries to lock branch B and script 2 tries branch A, well, that's a
      # deadlock. But it's very very very very unlikely we'll be running this
      # script twice simultaneously.
      locked = self.try_lock_for_branch()
      if locked:

         # Setup self.qb_latest and self.qb_update.
         self.setup_qbs(branch_, zoom_level=None)

         if self.qb_latest is None:
            # Because: (not rebuild_all) and (rid_former == rid_latest).
            log.debug('Branch revision ID unchanged; skipping: at rev: %d'
                      % (self.rid_latest,))
         else:
            # Don't do any work unless this branch defines some skins. We could
            # at least populate the Cyclopath cache, but what's the point?
            skin_names = self.get_skin_names(branch_)
            if skin_names:
               self.update_cache_for_branch_(branch_, skin_names)
            else:
               # 2013.05.28: Would our code even work without?
               g.assurt(False)

         self.close_qbs()

         # We'll release the branch lock when we complete the db transaction.
         # This will wake up any threads waiting on the lock.

      self.cur_branch_sid = None

   #
   def update_cache_for_branch_(self, branch_, skin_names):

      time_0 = time.time()

      self.other_stats_reset()

      # Make sure tiles_mapserver_zoom is populated and updated for whatever
      # skins this branch uses.
      if (self.cli_opts.rebuild_cache_zooms
          or self.cli_opts.rebuild_cache_instance):
         for skin_name in skin_names:
            log.debug('Processing skin: %s' % (skin_name,))
            self.cur_skin_name = skin_name
            self.cur_tile_skin = self.get_tile_skin()
            if self.cli_opts.rebuild_cache_zooms:
               self.repopulate_cache_zoom()
            # Maybe delete the existing tilecache-cache folder.
            if self.cli_opts.rebuild_cache_instance:
               self.cleanup_tilecache_cache()
         self.cur_skin_name = None
         self.cur_tile_skin = None

      # It's quick just to remake the label priority if you'd like to test a
      # new algorithm. Remake the lowest tile level (i.e., 9) to see its
      # effect.
      if self.cli_opts.remake_label_priority:
         self.remake_label_priority()

      # It takes a little while longer to rebuild the instance byway cache.
      # The line segment cache, tiles_cache_byway_segment, builds pretty
      # quickly. But the cluster cache, tiles_cache_byway_cluster, can take
      # hours to populate.
      if self.cli_opts.generate_cyclopath_cache:
         self.update_tables_instance_byways()

      self.other_stats_report()

      log.info('Updated cache for %s: %s'
               % (branch_.name,
                  misc.time_format_elapsed(time_0),))

   # *** Instance cache population

   #
   def update_tables_instance_byways(self):

      ## Start a cluster cache cache for updated segments.
      #self.cluster_changed_sids = []

      if self.qb_latest.item_mgr is not None:
         log.debug('update_tables_instance_byways: item_mgr.loaded_cache: %s'
                   % (self.qb_latest.item_mgr.loaded_cache,))
      else:
         log.debug('update_tables_instance_byways: item_mgr not created.')

      # We need to know if the bike_facil attribute is defined -- if it is,
      # whatever the bike_facil says is law, otherwise, we'll *guess* the
      # bike facility based on each byway's tags.
      # BUG nnnn: Merge bike_facil attribute to public basemap...
      # MAGIC_NUMBER: This is for the MetC branch.
      # FIXME: Standardize on this attribute -- i.e., for all branches?
      self.attr_bike_facil = attribute.Many.get_system_attr(
                  self.qb_latest, '/metc_bikeways/bike_facil')
      # Will handle later: g.assurt(self.attr_bike_facil is not None)
      self.attr_cycle_facil = attribute.Many.get_system_attr(
                  self.qb_latest, '/byway/cycle_facil')
# FIXME_2013_06_11: Also wire this into mapserver for for drawing tiles:
      self.attr_cautionary = attribute.Many.get_system_attr(
                  self.qb_latest, '/byway/cautionary')
      # Will handle later: g.assurt(self.attr_cycle_facil is not None)
      self.attr_no_access = attribute.Many.get_system_attr(
                  self.qb_latest, '/byway/no_access')
      # Will handle later: g.assurt(self.attr_no_access is not None)

      # Update the byway segment cache.
      self.prepare_tile_cache_byway_segment()

      # BUG nnnn: Implement the attr: '/byway/cycle_route'
      self.attr_cycle_route = attribute.Many.get_system_attr(
                  self.qb_latest, '/byway/cycle_route')
      # Will handle later: g.assurt(self.attr_cycle_route is not None)

      # Update the byway cluster cache.
      self.prepare_tile_cache_byway_cluster()

      # Remember what revision the Cyclopath cache now reflects.
      # NOTE: If the user used a bbox on the CLI, we assume we didn't rebuild
      #       the entire set of tiles, so we don't touch the last_rid.
      if (not self.restrict_bbox) and (not debugging_enabled):
         last_rid_key_name = self.get_last_rid_key_name_byways()
         self.qb.db.insert_clobber('key_value_pair',
                                   {'key': last_rid_key_name,},
                                   {'value': self.rid_latest,})

   # ***

   #
   def get_last_rid_key_prefix(self):
      last_rid_key_prefix = 'tilecache-last_rid'
      return last_rid_key_prefix

   #
   def get_last_rid_key_name_byways(self):

      g.assurt(self.cur_branch_sid)

      # E.g., tilecache-last_rid-branch_2500677.
      last_rid_key_name = ('%s-branch_%d'
                           % (self.get_last_rid_key_prefix(),
                              self.cur_branch_sid,))

      return last_rid_key_name

   #
   def get_last_rid_key_tilecs_basename(self):

      g.assurt(self.cur_branch_sid)
      g.assurt(self.cur_skin_name)

      # E.g., tilecache-last_rid-branch_2500677-skin_bikeways.
      last_rid_key_basename = ('%s-branch_%d-skin_%s'
                               % (self.get_last_rid_key_prefix(),
                                  self.cur_branch_sid,
                                  self.cur_skin_name,))

      return last_rid_key_basename

   #
   def get_last_rid_key_name_tilecs(self, zoom_level):

      # E.g., tilecache-last_rid-branch_2500677-skin_bikeways-zoom_7.
      last_rid_key_name = ('%s-zoom_%d'
                           % (self.get_last_rid_key_tilecs_basename(),
                              zoom_level,))

      return last_rid_key_name

   # ***

   #
   def get_last_rid(self, zoom_level=None):

      g.assurt(not (self.cur_skin_name or zoom_level)
               or (self.cur_skin_name and zoom_level))

      if not (self.cur_skin_name or zoom_level):
         last_rid_key_name = self.get_last_rid_key_name_byways()
      else:
         last_rid_key_name = self.get_last_rid_key_name_tilecs(zoom_level)

      rows = self.qb.db.sql(
         "SELECT value FROM key_value_pair WHERE key = '%s'"
         % (last_rid_key_name,))

      if rows:
         g.assurt(len(rows) == 1)
         # FIXME: Test and then close Bug 1916
         last_rid = int(rows[0]['value'])
         g.assurt(last_rid > 0)
      else:
         last_rid = 0

      return last_rid

   # ***

   #
   def setup_qb_latest(self):

      # This scripts normally runs on the public group only, but the caller can
      # choose whatever groups s/he wants. But we warn, since this behaviour
      # isn't commonplace.
      g.assurt(len(self.cli_args.group_ids) > 0)
      # Generally, we use the 'All Users' public group and the
      # _user_anon_instance private group.
      if ((len(self.cli_args.group_ids) != 2)
          or (not (set(self.cli_args.group_ids)
                   == set([group.Many.public_group_id(self.qb.db),
                           group.Many.cp_group_private_id(
                              self.qb.db, conf.anonymous_username),])))):
         log.warning('Not just using public group, but these %d groups: %s'
                     % (len(self.cli_args.group_ids),
                        self.cli_args.group_defs,))

      # Prepare the historic revision object, used to fetch link_values. It's
      # also used to fetch byways when rebuilding a cache table. In either
      # case -- whether fetching a link_value or rebuilding a cache table from
      # scratch -- we don't need to worry about deleted items.

      rev_latest = revision.Historic(self.rid_latest,
                                     gids=self.cli_args.group_ids,
                                     allow_deleted=False)

      self.qb_latest = self.get_qb_for_rev(rev_latest)

      # Be deliberate about using the proper group stack IDs instead of the
      # script-caller's groups.
   # FIXME: It seems like the default is backwards. Most scripts don't want
   #        to use the --username group stack IDs. That really only makes sense
   #        for ccp.py? The group IDs are used making the SQL to fetch items
   #        and are also used when saving revisions...
#      import pdb;pdb.set_trace()
      self.qb_latest.filters.gia_use_gids = ','.join(
            [str(x) for x in self.cli_args.group_ids])

   #
   def setup_qb_update(self):

      # Prepare the updated revision object, which may be used to fetch byways.
      # We want to fetch items that have changed between rid_former and
      # rid_latest. Include deleted items so we remove 'em from the cache.

      if (    (not self.rebuild_all)
          and (self.rid_former)
          and (not self.cli_opts.rebuild_cache_zooms)):

         # NOTE: Ignoring self.cli_args.group_ids -- we'll be using
         #       qb.filters.gia_use_gids instead.
         rev_update = revision.Updated(self.rid_former, self.rid_latest)
         self.qb_update = self.get_qb_for_rev(rev_update)
         # For revision.Updated to work with item_user_access.search_get_sql,
         # be explicit about not using gids.
         self.qb_update.username = ''
         self.qb_update.filters.gia_userless = True

         #
         self.rev_former = revision.Historic(self.rid_former,
                                             gids=self.cli_args.group_ids,
                                             allow_deleted=False)

      else:
         self.qb_update = None
         self.rev_former = None

   #
   def get_qb_for_rev(self, rev):

      # Use the anonymous user, but this value is ignored -- for qb_latest,
      # we override the user by specifying gia_use_gids, and for qb_update,
      # it's a rev.Update object, which is assumed group-less (since we want to
      # find all items that changed between two revisions, and not just those
      # items restricted to certain groups (otherwise we won't notice changes
      # in permissions that effectively remove an item from view)).
      username = conf.anonymous_username

      g.assurt(self.cur_branch_sid)
      # Prepare the branch hier for the qb object.
      branch_hier = branch.Many.branch_hier_build(
            self.qb.db, self.cur_branch_sid, rev)

      qb = Item_Query_Builder(self.qb.db, username, branch_hier, rev)

      # Prepare the base qb, which we use as a template for the other qb's.
      qb.filters.skip_geometry_raw = False
      qb.filters.skip_geometry_svg = True
      qb.filters.skip_geometry_wkt = False

      # If debugging, just grab a handful of results
      if debug_limit:
         qb.use_limit_and_offset = True
         qb.filters.pagin_count = int(debug_limit)

      g.assurt(qb.sql_clauses is None)

      qb.request_is_local = True
      qb.request_is_script = True

      qb.item_mgr = Item_Manager()
      # Skipping: qb.item_mgr.load_cache_attachments(qb)

      Query_Overlord.finalize_query(qb)

      log.debug('get_qb_for_rev: qb.filters: %s' % (str(qb.filters),))

      return qb

   # *** Populate or Update segment cache

   #
   def prepare_tile_cache_byway_segment(self):

      # Get all of the geometries and iterate over them. Don't worry, this
      # isn't going to be a slow operation if you're rebuilding everything. =)
      # Before adding tags and attachments, and just using a view, rebuilding
      # everything takes 2 hours (20110920). FIXME: What is it now?
      # 20111122: Revamped Bikeways import script.
      #    159,051 rows in tiles_cache_byway_attcs
      #    ~ 1:05 m:ss / 1,000 rows, or 172 minutes. Not too bad, I guess.
      #    Actual running time:
      # Nov-22 13:03:21  DEBG  tilecache_update  #  Updating 159052 rows...
      # Nov-22 13:14:46  DEBG  tilecache_update  #   >> ... 10000
      #    ~ 11:25 mm:ss / 10,000 rows, or 182 minutes.
      # 2013.01.02: We used to call byway.Many().get_search_sql but now we use
      #             the item_mgr to load byways (and their attrs and tags).
      #             This is a lot quicker and more memory-sensitive.

      # Load byways, and attrs and tags, for a specific revision.

      log.debug('prepare_tile_cache_byway_segment: calling item_mgr...')
      # NO: prog_log = Debug_Progress_Logger(log_freq=25000)
      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      # When running --all vs. --all --county 'x', the latter is really slow...
      if self.restrict_bbox is None:
         prog_log.log_freq = 25000
      else:
         prog_log.log_freq = 100
      prog_log.info_print_speed_enable = True
      prog_log.callee = 'prep_tcache_byway_seg'

      # NOTE: We shouldn't need to implement keep_running, since this script is
      #       single-threaded.
      keep_running = None

      time_0 = time.time()

      if self.rebuild_all:

         # Use _all_ of the geofeatures.
         qb = self.qb_latest

         if self.restrict_bbox is None:

            # DEVS: If you've been testing using debug_break_loops, this makes
            # sure the tables are free of this branch's leftovers.
            # UNKNOWN: 26 May-29 16:21:48 ERRR util_.db_glue # sql: internal:
            #          ERROR:  could not open relation with OID 28244797
            if not self.cli_opts.skip_cache_byway_segment:
               self.qb.db.sql("""
                              DELETE FROM tiles_cache_byway_segment
                              WHERE branch_id = %d
                              """ % (self.cur_branch_sid,))

            # Clean tiles_cache_byway_cluster and tiles_cache_clustered_byways,
            # even though we clean up these tables later using cluster names.
            if not self.cli_opts.skip_cache_byway_cluster:
               self.qb.db.sql("""
                              DELETE FROM tiles_cache_byway_cluster
                              WHERE branch_id = %d
                              """ % (self.cur_branch_sid,))
               self.qb.db.sql("""
                              DELETE FROM tiles_cache_clustered_byways
                              WHERE byway_branch_id = %d
                              """ % (self.cur_branch_sid,))

         else:

            # I.e., restrict_bbox or restrict_counties
            g.assurt(qb.viewport.include is None)
            g.assurt(qb.use_filters_and_viewport)
            qb.viewport.include = self.restrict_bbox

      else:
         # Use just those geometries that changed.
         qb = self.qb_update

      fetch_size = 0
      if debug_prog_log.debug_break_loops:
         fetch_size = debug_prog_log.debug_break_loop_cnt

      # NOTE: Use heavyweight so we get ratings and tags and attrs.
      if not self.cli_opts.skip_cache_byway_segment:
         if isinstance(qb.revision, revision.Historic):
            qb.item_mgr.load_feats_and_attcs(qb, byway,
               'search_by_network', self.consume_tile_cache_byway_segment,
               prog_log, heavyweight=True, fetch_size=fetch_size,
               keep_running=keep_running, max_iters=fetch_size)
         else:
            g.assurt(isinstance(qb.revision, revision.Updated))
            g.assurt(not self.rebuild_all)
            # MAYBE: update_feats_and_attcs needs revision.Historic. It
            # currently makes its own. We could just send it self.qb_latest.
            qb.item_mgr.update_feats_and_attcs(qb, byway,
               'search_by_network', self.consume_tile_cache_byway_segment,
               prog_log, heavyweight=True, fetch_size=0,
               keep_running=keep_running)

      log.info('prepare_tile_cache_byway_segment: complete: ran %s'
               % (misc.time_format_elapsed(time_0),))

   #
   def consume_tile_cache_byway_segment(self, qb, bway, prog_log):
      #log.debug('consume_tile_cache_byway_segment: bway: %s' % (str(bway),))
      if (not self.rebuild_all) or (self.restrict_bbox is not None):
         # Clear old cache values if updating or not rebuiling whole cache.
         self.tile_cache_byway_segment_delete(bway)
      if not bway.deleted:
         self.tile_cache_byway_segment_update(bway)
      # BUG nnnn: Implement line segment cluster cache for cycle_routes.
      ##if not self.rebuild_all:
      #if (not self.rebuild_all) or (self.restrict_bbox is not None):
      #   # FIXME: self.cluster_changed_sids is not used.
      #   #        But cycle_route tile stuff isn't implemented, either.
      #   self.cluster_changed_sids.append(str(bway.stack_id))

   #
   def tile_cache_byway_segment_delete(self, bway):
      # If not updating the whole cache, delete the old segment in case it's
      # wiki-deleted.
      # NOTE: Using the script's branch ID and not the item's.
      g.assurt(self.cur_branch_sid)
# FIXME: Do bulk delete, then do bulk insert!
      self.qb.db.delete('tiles_cache_byway_segment',
                        {'stack_id': bway.stack_id,
                         'branch_id': self.cur_branch_sid,})
      self.qb.db.delete('tiles_cache_clustered_byways',
                        {'byway_stack_id': bway.stack_id,
                         'byway_branch_id': self.cur_branch_sid,})

   #
   def tile_cache_byway_segment_update(self, bway):

      # Create a dictionary for the cache table row.
      cols = {}

      # We need the system_id for the mapfile, so it knows how to join the
      # geofeature table. (We could use stack_id and version instead, but it's
      # simpler just to use the system_id.)
      cols['system_id'] = bway.system_id

      # This is the byway's stack ID, needed to update the cache when a new
      # revision is saved.
      cols['stack_id'] = bway.stack_id

      # This is the branch stack ID, since we might make tiles for multiple
      # branches.
      # NOTE: Using the script's branch ID and not the item's.
      g.assurt(self.cur_branch_sid)
      cols['branch_id'] = self.cur_branch_sid

      g.assurt(bway.geometry)
      cols['geometry'] = bway.geometry

      cols['geofeature_layer_id'] = bway.geofeature_layer_id

      # RENAME: z_level to bridge_level, so as not to confuse with zoom_level.
      cols['z_level'] = bway.z

      # Add the byway rating, which we included in the byways SQL.
      # MAYBE: Should we store this? CcpV2 doesn't use the rating for byway
      #        shading, since it's confusing, especially when zoomed out.
      cols['generic_rating'] = bway.generic_rating

      # Get the bike facility.
      #
      # NOTE: We're choosing the MetC (or Agency) bike facil over public's
      #       version of the attribute.
      bike_facil = self.get_bike_facility_ccp_or_metc(bway)
      cols['bike_facility_or_caution'] = bike_facil
      # NOTE: The caution trumps the facil.
      # FIXME/BUG nnnn: [lb] wonders how using cautions affects tiles.
      #                 Will they show up on all or some zoom levels,
      #                 and what do they look like?
      if self.attr_cautionary is not None:
         try:
            cols['bike_facility_or_caution'] = (
               bway.attrs[self.attr_cautionary.value_internal_name])
         except KeyError:
            pass

      if self.attr_no_access is not None:
         try:
            cols['travel_restricted'] = (
               bway.attrs[self.attr_no_access.value_internal_name])
         except KeyError:
            # This column is required.
            cols['travel_restricted'] = False
      #
      if bway.has_tag('prohibited') or bway.has_tag('closed'):
         cols['travel_restricted'] = True

      # Save everything.
      log.verbose1(' >> byway: stack_id: %d / cols: %s'
                   % (bway.stack_id, cols,))

      # MAYBE: Should we load up cols and do a bulk insert?
# FIXME: Yeah, probably: With so many inserts, bulk is best!
#        See also other inserts in this file.
#        INSERT INTO ... () VALUE (), (), ();
      if not insert_bulkwise:
         self.qb.db.insert('tiles_cache_byway_segment', {}, cols)
      else:
         # MAYBE: Implement a bulk load... though it's pretty fast as is...
         g.assurt(False)
         # Something like: self.byway_segment_cols.append(cols)

   #
   def get_bike_facility_ccp_or_metc(self, bway):
      bike_facil = ''
      if self.attr_bike_facil is not None:
         try:
            bike_facil = (
               bway.attrs[self.attr_bike_facil.value_internal_name])
         except:
            pass
      elif self.attr_cycle_facil is not None:
         try:
            bike_facil = (
               bway.attrs[self.attr_cycle_facil.value_internal_name])
         except KeyError:
            pass
      return bike_facil

   # *** Populate or Update cluster cache

   # FIXME/BUG nnnn: Cycle Route. Finish implementing... defining... ya know.

   #
   def prepare_tile_cache_byway_cluster(self):
      if not self.cli_opts.skip_cache_byway_cluster:
         self.prepare_tile_cache_byway_cluster_same_named()
         if self.attr_cycle_route is not None:
            self.prepare_tile_cache_byway_cluster_cycleroute()

   #
   def prepare_tile_cache_byway_cluster_same_named(self):

      # Cache values to save on SQL processing time. The byway label cache,
      # tiles_cache_byway_cluster, coalesces byway names and their collected
      # geometries and is used to draw the label layer on the tiles. It's also
      # used to draw cycleroutes.

      # This is an interesting lookup operation: get the names of the clusters
      # we want to add or update. If we're building from scratch, we need all
      # byways' names. If we're just updating, we want the names of the changed
      # byways (from both the previous revision and the latest revision).

      time_0 = time.time()

      #db_byway_names = self.qb.db.clone()
      db_byway_names = db_glue.new()
      g.assurt(not db_byway_names.dont_fetchall)
      db_byway_names.dont_fetchall = True

      # We need to make some temporary tables of stack IDs.
      db_byway_names.transaction_begin_rw()

# FIXME: Performance:
#
#        IMPLEMENT: self.cli_opts.async_procs
#
#        # NOTE: 'i' means Value is an int.
#        #val_cnt_names = multiprocessing.Value('i', cnt_names)
#
#        total_names = COUNT(*)
#        total_procs = 20 # Or?: 3 * self.cli_opts.async_procs ??
#        args = []
#        for offset_multiplier in xrange(total_procs):
#           args.append((offset_multiplier, total_procs, total_names,))
#        result = Pool.map_async(rebuild_cluster_partial, args)
#        and then each worker does 1/10th of the work and uses LIMIT and
#        OFFSET to get just certain pages of names... though the pages
#        change if users edit the database, unless the workers use
#        revision.Historic and not revision.Current, which they do...
#        so we should be good, I think...
# 2014.08.25: Would this really work? A Python script only ever runs
#             on one core unless you fork it, so the question is, does
#             Pool fork or just thread?

      sql_byway_names = self.get_sql_byway_cluster_names(db_byway_names)
      rows = db_byway_names.sql(sql_byway_names)
      g.assurt(rows is None)

      log.info('prepare_tile_cache_byway_cluster: found %d names: %s'
               % (db_byway_names.curs.rowcount,
                  misc.time_format_elapsed(time_0),))

      # For each name, get a list of byways and redo the cluster for that name.

      time_0 = time.time()

      self.cluster_stats_reset()

      # MAYBE: What's a good number here?
      # NO: prog_log = Debug_Progress_Logger(log_freq=5)
      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_freq = 5 # It's tediously slow!
      prog_log.loop_max = db_byway_names.curs.rowcount
      prog_log.info_print_speed_enable = True
      prog_log.callee = 'prep_tcache_byway_clust'

      # We treat names like lowercase when we make the clusters, but the name
      # in the row is not lowercased. So, to prevent processing the same name
      # twice, we have to check the last row's name.
      last_name = None
      generator = db_byway_names.get_row_iter()

      for row in generator:
         cur_name = row['byway_name']
         if (not last_name) or (last_name.lower() != cur_name.lower()):
# FIXME: Do we have to rebuild the whole nameset, or can we just use cluster_id
#        from tiles_cache_clustered_byways to figure out what to rebuild? Or
#        doesn't that help much... seems we'd still have to rebuild by name.
            self.rebuild_cluster_named(cur_name,
                                       is_cycle_route=False,
                                       stack_ids=None)
            last_name = cur_name

         if prog_log.loops_inc():
            break

         # Let the live site live!
         # 2014.08.19: Weird: If we keep the transaction open, it blocks
         # route requests!? This makes no sense... but there it is.... I
         # don't even see any log activity for route requests if we don't
         # constantly cycle the transaction! And loading flashclient just
         # spins if we don't sleep!
         # The route request hangs here, without the transaction_* cycling:
         #  ... search_graph: travel_mode: generic / route: "Untitled" ...
         # what should come next is:
         #  ... search_graph: found node IDs in 0.10 secs.
         self.qb.db.transaction_commit()
         self.qb.db.transaction_begin_rw()
         time.sleep(0.1)

      generator.close()

      prog_log.loops_fin()

      db_byway_names.sql("DROP TABLE IF EXISTS %s"
                         % (Item_Manager.temp_table_update_sids,))

      db_byway_names.dont_fetchall = False
      db_byway_names.close()

      self.cluster_stats_report()

# Is this redundant, since prog_log reported same?
      log.info('_byway_cluster: processed %d cluster names: %s'
               % (prog_log.progress,
                  misc.time_format_elapsed(time_0),))

   #
   def get_sql_byway_cluster_names(self, db):

      where_byways_named = ""
      if debug_clusters_named:
         where_byways_named = ("AND (gf_iv.name IN (%s))"
                               % (debug_clusters_named,))

      if self.rebuild_all:

         # Use _all_ of the byways' names.
         #
         # MAYBE: If Ccp goes worldwide, would this operation become unruly?
         #        Can we shard database and distribute the operation based on
         #        locality? I.e., one server for each state/country/republic.
         # MAYBE: We're cheating and looking for all LINESTRINGs. Ideally, we
         #        should instead check geofeature_layer_id and see if it's a
         #        byway type...
         # 2013.01.02: There are at most 23,870 unique names ([lb] tested the
         #             sql statement but without the where_rev):
         where_rev = self.qb_latest.revision.as_sql_where(
                        table_name='gf_iv',
                        include_gids=False,
                        allow_deleted=False)
         where_bbox = ""
         if self.restrict_bbox is not None:
            where_bbox = (
               "AND %s" % (self.restrict_bbox.sql_intersect("gf.geometry"),))
         sql_byway_names = (
            """
            SELECT DISTINCT ON (gf_iv.name) gf_iv.name AS byway_name
            FROM geofeature AS gf
            JOIN item_versioned AS gf_iv
               ON (gf.system_id = gf_iv.system_id)
            WHERE
               ST_GeometryType(gf.geometry) = 'ST_LineString'
               AND gf_iv.name != ''
               AND gf_iv.name IS NOT NULL
               AND %s
               %s
               %s
            ORDER BY gf_iv.name ASC
            """ % (where_rev,
                   where_bbox,
                   where_byways_named,))
         #
         # We just used ST_GeometryType, but we could've used the gfl ID:
         #
         #   gf.geofeature_layed_id IN (
         #        1 -- byway unknown
         #    ,   2 -- byway other
         #    ,  11 -- local road
         #    ,  12 -- 4wd road
         #    ,  14 -- bike path
         #    ,  15 -- sidewalk
         #    ,  16 -- doubletrack
         #    ,  17 -- singletrack
         #    ,  21 -- major road
         #    ,  22 -- major trail
         #    ,  31 -- highway
         #    ,  41 -- expressway
         #    ,  42 -- expressway ramp
         #    /* Skipping:
         #    , 101 -- /terrain/open_space
         #    , 102 -- /terrain/water
         #    , 103 -- /waypoint/default
         #    , 104 -- /region/default
         #    , 105 -- /route/default
         #    , 106 -- /track/default
         #    , 108 -- /region/work_hint
         #    , 109 -- /branch/work_hint
         #    */
         #    )
         # MAYBE: In byway.py, make a collection of its gfl IDs.

      else:

         # Use just the names of those byways that changed.
         g.assurt(self.qb_update is not None)
         # The update qb was used to fetch those stack IDs that changed -- and
         # it used a temporary table of stack IDs to do so. We can reuse the
         # same table of stack IDs (alternatively, we could remake the table
         # ourselves and stick all the stack IDs in the WHERE clause, but the
         # join is probably the most ideal approach).
         rev_former = revision.Historic(self.rid_former,
                                        gids=self.cli_args.group_ids,
                                        allow_deleted=False)
         where_rev_former = self.rev_former.as_sql_where(
                              table_name='gf_iv',
                              include_gids=False,
                              allow_deleted=True)
         where_rev_latest = self.qb_latest.revision.as_sql_where(
                              table_name='gf_iv',
                              include_gids=False,
                              allow_deleted=True)
         g.assurt(not self.qb_update.filters.stack_id_table_ref)
         sid_count = Item_Manager.create_update_rev_tmp_table(self.qb_update)
         sql_byway_names = (
            """
            SELECT DISTINCT ON (gf_iv.name) gf_iv.name AS byway_name
            FROM geofeature AS gf
            JOIN item_versioned AS gf_iv
               ON (gf.system_id = gf_iv.system_id)
            JOIN %s AS stack_ids_ref
               ON (stack_ids_ref.stack_id = gf.stack_id)
            WHERE
               ST_GeometryType(gf.geometry) = 'ST_LineString'
               AND gf_iv.name != ''
               AND gf_iv.name IS NOT NULL
               AND (%s OR %s)
               %s
            ORDER BY gf_iv.name ASC
            """ % (Item_Manager.temp_table_update_sids,
                   where_rev_former,
                   where_rev_latest,
                   where_byways_named,))

      return sql_byway_names

   #
   def delete_from_byway_cluster(self, cluster_name, is_cycle_route):
      g.assurt(self.cur_branch_sid)
      # Form the common where clause.
      where_clause = (
         """
         WHERE
            LOWER(cluster_name) = LOWER(%s)
            AND branch_id = %d
            AND is_cycle_route IS %s
         """ % (self.qb.db.quoted(cluster_name),
                self.cur_branch_sid,
                'TRUE' if is_cycle_route else 'FALSE',))
      # Cleanup the link table.
      self.qb.db.sql(
         """
         DELETE FROM tiles_cache_clustered_byways
         WHERE cluster_id IN (
            SELECT cluster_id FROM tiles_cache_byway_cluster
            %s)
         """ % (where_clause,))
      # Cleanup the cluster table.
      self.qb.db.sql(
         """
         DELETE FROM tiles_cache_byway_cluster
         %s
         """ % (where_clause,))

   #

   only_whitespace = re.compile(r'^\s*$')

   #
   def rebuild_cluster_named(self, cluster_name, is_cycle_route,
                                   stack_ids=None):
      if re.match(TCU.only_whitespace, cluster_name) is None:
         self.rebuild_cluster_named_(cluster_name, is_cycle_route, stack_ids)

   #
   def rebuild_cluster_named_(self, cluster_name, is_cycle_route, stack_ids):

      # log.verbose('rebuild_cluster_named: %s' % (cluster_name,))

      # Clear the old cluster entries from the cache that match the
      # cluster_name. We've got to rebuild each cluster that matches this
      # name, since we have to re-examine connectivity.

      # MAYBE: It might be quicker to delete all clusters-named at the same
      #        time, but we use a generator to iterate over the names, so we
      #        can't currently do that without recoding some stuff above.
      # NOTE: We use LOWER because qb.filters.filter_by_text_exact uses LOWER.
      self.delete_from_byway_cluster(cluster_name, is_cycle_route)

      qb_cluster = self.qb_latest.clone(
         skip_clauses=True, skip_filtport=True, db_clone=True)

      # We only care about stack IDs and beginning and finishing node IDs. So
      # prepare the SQL clauses so we can get the raw SQL lookup and not have
      # to engage item_manager.
      # Not using: sql_clauses_cols_setup().
      g.assurt(not qb_cluster.sql_clauses)
      qb_cluster.sql_clauses = byway.Many.sql_clauses_cols_all.clone()
      # Note that we hacked bike_facility into byway.One.local_defns,
      # so we can add it here.
      # MAYBE: Move this to byway.Many.sql_clause_cols_cached

      # Add the assumed bike_facility value.
      qb_cluster.sql_clauses.inner.select += (
         """, segment.bike_facility_or_caution
         """)
      qb_cluster.sql_clauses.inner.group_by += (
         """, segment.bike_facility_or_caution
         """)
      qb_cluster.sql_clauses.inner.join += (
         """LEFT OUTER JOIN tiles_cache_byway_segment AS segment
               ON (gia.item_id = segment.system_id)
         """)
      qb_cluster.sql_clauses.outer.shared += (
         """, group_item.bike_facility_or_caution
         """)

      if not is_cycle_route:
         # We only want byways of a particular name.
         g.assurt(not stack_ids)
         g.assurt(qb_cluster.filters.filter_by_text_exact == '')
         qb_cluster.filters.filter_by_text_exact = cluster_name
      else:
         # We've been passed stack_ids.
         g.assurt(stack_ids)
         qb_cluster.filters.only_stack_ids = ','.join(stack_ids)

      g.assurt(not qb_cluster.db.dont_fetchall)
      qb_cluster.db.dont_fetchall = True

      Query_Overlord.finalize_query(qb_cluster)

      time_0 = time.time()

      byways = byway.Many()
      byways.search_get_items(qb_cluster)

      log.verbose('rebuild_cluster_named: found %d byways: %s'
                  % (qb_cluster.db.curs.rowcount,
                     misc.time_format_elapsed(time_0),))

      # For each stack ID, add its node IDs to the processing collection.

      self.cluster_pairs = []
      self.cluster_nid_cnts = {}

      generator = byways.results_get_iter(qb_cluster)
      for bway in generator:
         self.consume_tile_cache_byway_cluster(bway)
      generator.close()

      qb_cluster.db.close()

      # Process the collections we just made.
      self.process_cluster_nid_cnts(cluster_name)
      self.process_cluster_named(cluster_name, is_cycle_route)

      # log.info('rebuild_cluster_named: processed cluster: %s / %s'
      #          % (misc.time_format_elapsed(time_0),
      #             cluster_name,))

   #
   def consume_tile_cache_byway_cluster(self, bway):

      # This fcn. is really simple: we're just making a lookup that we'll
      # process shortly.

      cluster_bwys = [bway,]
      cluster_nids = set([bway.beg_node_id, bway.fin_node_id,])
      new_cluster_pair = (cluster_bwys, cluster_nids,)
      self.cluster_pairs.append(new_cluster_pair)

      # We also have to remember how many times we see each node ID.
      # If we see a node ID more than twice, it means three line segments of
      # the same name intersect, which means ST_LineMerge will make a
      # MULTILINESTRING (so assumeth [lb]). The easiest thing to do is to not
      # match on such intersections. And there shouldn't be that many of these,
      # and it'll just split what could have be one long line string into two
      # line strings.
      self.consume_tile_cache_byway_cluster_nid_cnt(bway.beg_node_id)
      self.consume_tile_cache_byway_cluster_nid_cnt(bway.fin_node_id)

   #
   def consume_tile_cache_byway_cluster_nid_cnt(self, node_stack_id):
      self.cluster_nid_cnts.setdefault(node_stack_id, 0)
      self.cluster_nid_cnts[node_stack_id] += 1

   #
   def process_cluster_nid_cnts(self, cluster_name):
      self.exclude_nids = set()
      for node_sid, use_cnt in self.cluster_nid_cnts.iteritems():
         # Keep stats of the number of times each node is used by byways of the
         # same name.
         self.stats_nid_use_cnt.setdefault(use_cnt, 0)
         self.stats_nid_use_cnt[use_cnt] += 1
         # MAGIC_NUMBER: If the node is used more than two times, exclude it.
         if use_cnt > 2:
            # log.debug('_nid_cnts: node ID %d used %d times'
            #           % (node_sid, use_cnt,))
            self.exclude_nids.add(node_sid)
            # MAYBE: Record stats to a log file, so you can examine things
            # like nodes being used by three or more of the same-named
            # byway. Anecdotally [lb] looked at a few of these are they're,
            # e.g., "Carver Park" bike trails. So probably not a big deal... or
            # at least something we can ignore for a while (maybe make a work
            # hints game for this, and have people set a node attribute like
            # dangle_ok, i.e., multi_intersect_ok).
            # MAYBE: This might be a ridiculously-sized dictionary...:
            self.stats_nids_usages.setdefault(use_cnt, [])
            self.stats_nids_usages[use_cnt].append(cluster_name)

   #
   def process_cluster_named(self, byway_name, is_cycle_route):

      # Collect stack IDs into sets based on connectivity. We'll assemble
      # geometries using PostGIS, rather than doing the linestring math
      # ourselves (seems easier that way...). But we'll use Python sets to
      # recursively iterate over the collections of sids to nids.
      #
      # Here, we go through every element once, and for each of those
      # elements, we go through what's left of the list. The Big-O here
      # is (n)+(n-1)+(n-2)+...(2)+(1). This is (n+1)*(n/2) if n is even,
      # else it's ((n+1)*((n/2)-1))+(n/2) if n is odd. Which is quadratic, or
      # big O(n^2), since (n+1)*(n/2) = pow(n,2)/2 + n/2. It's a little more
      # than half of n-squared. So quadratic. Shoot.
      # MAYBE: Is this the fastest algorithm we've got?

      # log.debug('process_cluster_named (1): %d pairs for %s'
      #           % (len(self.cluster_pairs), byway_name,))
      # This is the number of byways with the same name before clustering.
      same_named_count = len(self.cluster_pairs)
      self.stats_byways_same_named.setdefault(same_named_count, 0)
      self.stats_byways_same_named[same_named_count] += 1

      for index_i in xrange(len(self.cluster_pairs)):

         # Connect this byway cluster to subsequent clusters, if possible.

         cluster_pair = self.cluster_pairs[index_i]
         if cluster_pair is None:
            # log.verbose('cluster_pair: skipping None at idx %d' % (index_i,))
            continue

         # log.debug('cluster_pair: %s' % (cluster_pair,))
         (bwys_i, nids_i,) = cluster_pair

         # When we find a match, use the first match as storage for the new
         # pair. This way, the new pair gets processed when we process the next
         # first match.
         first_j = None
         for index_j in xrange(index_i + 1, len(self.cluster_pairs)):
            if self.cluster_pairs[index_j] is not None:
               (bwys_j, nids_j,) = self.cluster_pairs[index_j]
               # See if the two node ID pools overlap, but exclude over-used.
               if nids_i.intersection(nids_j).difference(self.exclude_nids):
                  bwys_i.extend(bwys_j)
                  nids_i = nids_i.union(nids_j)
                  new_cluster_pair = (bwys_i, nids_i,)
                  # Since we haven't processed the pairs we're matching
                  # against, use the first pair as storage for the new
                  # cluster. This way, we'll be more effecient, because
                  # it'll bubble up as we go down.
                  if not first_j:
                     first_j = index_j
                  self.cluster_pairs[index_j] = None
                  self.cluster_pairs[first_j] = new_cluster_pair
                  # Remove the one that was consumed.
                  self.cluster_pairs[index_i] = None

      self.cluster_pairs = [x for x in self.cluster_pairs if x is not None]
      # MAYBE: Do we care about the amount of clustering? E.g., if 10 byways
      #        have the same name and we reduce to 2 clusters -- do we care to
      #        make stats for that?

      # log.debug('process_cluster_named (2): %d pairs for %s'
      #           % (len(self.cluster_pairs), byway_name,))
      num_pairs = len(self.cluster_pairs)
      self.stats_byways_num_clusters.setdefault(num_pairs, 0)
      self.stats_byways_num_clusters[num_pairs] += 1

      # We've processed all the byways with this self-same name, so cluster.

      for (bwys, nids,) in self.cluster_pairs:

         # Populate the cache.
         # log.debug('process_cluster_named (3): %d bwys / %d nids'
         #           % (len(bwys), len(nids),))
         self.stats_num_byways_per_cluster.setdefault(len(bwys), 0)
         self.stats_num_byways_per_cluster[len(bwys)] += 1

         sys_ids = []
         stack_ids = []
         gfl_ids = {}
         bike_facils = {}
         for bway in bwys:
            sys_ids.append(str(bway.system_id))
            stack_ids.append(str(bway.stack_id))
            gfl_ids.setdefault(bway.geofeature_layer_id, 0)
            gfl_ids[bway.geofeature_layer_id] += 1
            #
            # We didn't load attrs or tagged; we get the bike facility or
            # caution from the segment cache, not really from the item, per se.
            # Wrong: bike_facil = self.get_bike_facility_ccp_or_metc(bway)
            bike_facil = bway.bike_facility_or_caution
            if bike_facil:
               #log.debug('bike_facility: %s' % (bike_facil,))
               bike_facils.setdefault(bike_facil, 0)
               bike_facils[bike_facil] += 1

         # if len(gfl_ids) > 1:
         #    log.debug(' ... multiple gfl_ids: found %d distinct'
         #              % (len(gfl_ids),))

         winningest_gfl_id = None
         largest_usage_cnt = 0
         for gfl_id, usage_cnt in gfl_ids.iteritems():
            if (not largest_usage_cnt) or (usage_cnt > largest_usage_cnt):
               winningest_gfl_id = gfl_id
               largest_usage_cnt = usage_cnt

         if len(gfl_ids) > 1:
            # log.verbose(' ... multiple gfl_ids for "%s": %s / chose: %s'
            #             % (byway_name, gfl_ids, winningest_gfl_id,))
            self.stats_gfl_usages.setdefault(len(gfl_ids), 0)
            self.stats_gfl_usages[len(gfl_ids)] += 1

         # MAYBE: Use None (psql NULL) or '' string or 'None'?
         #        It shouldn't matter...
         winningest_bike_facil = 'NONE'
         largest_usage_cnt = 0
         for bike_facil, usage_cnt in bike_facils.iteritems():
            if (not largest_usage_cnt) or (usage_cnt > largest_usage_cnt):
               winningest_bike_facil = bike_facil
               largest_usage_cnt = usage_cnt

         g.assurt(self.cur_branch_sid)

         insert_sql = (
            """
            INSERT INTO tiles_cache_byway_cluster
               (cluster_name
                , branch_id
                , byway_count
                , geometry
                , label_priority
                , winningest_gfl_id
                , winningest_bike_facil
                , is_cycle_route
                )
               SELECT
                  %s
                  , %d
                  , %d
                  , ST_LineMerge(ST_Collect(gf.geometry))
                  , 1 -- Lowest priority
                  , %d
                  , %s
                  , %s
               FROM geofeature AS gf
               WHERE system_id IN (%s)
            """ % (self.qb.db.quoted(byway_name),
                   self.cur_branch_sid,
                   len(bwys),
                   winningest_gfl_id,
                   self.qb.db.quoted(winningest_bike_facil),
                   'TRUE' if is_cycle_route else 'FALSE',
                   ','.join(sys_ids),))
         self.qb.db.sql(insert_sql)

         # Get the cluster ID of the new entry.
         cid_sql = "SELECT CURRVAL('tiles_cache_byway_cluster_cluster_id_seq')"
         rows = self.qb.db.sql(cid_sql)
         if rows:
            g.assurt(len(rows) == 1)
            new_cluster_id = rows[0]['currval']
            # log.verbose(' ... new cluster_id: %d' % (new_cluster_id,))
            self.priority_set(new_cluster_id)
            cols = {}
            cols['cluster_id'] = new_cluster_id
            cols['byway_branch_id'] = self.cur_branch_sid
            for stack_id in stack_ids:
               cols['byway_stack_id'] = stack_id
               # EXPLAIN: What is the link table used for?
               #          Right now, we update based on stack ID or name of
               #          what was updated, so the link table seems
               #          unnecessary?
               # MAYBE: Should we load up cols and do a bulk insert?
               # ?: self.qb.db.insert_clobber('tiles_cache_clustered_byways',
               #                              {}, cols)
               self.qb.db.insert('tiles_cache_clustered_byways', {}, cols)
         else:
            low.error('No rows for cluster: %s' % (byway_name,))

   #
   # Just the label priority...
   def remake_label_priority(self):
      self.priority_set(new_cluster_id=None)

   #
   def priority_set(self, new_cluster_id):

      if new_cluster_id:
         where_clause = "WHERE cluster_id = %d" % (new_cluster_id,)
         db_clusters = self.qb.db
      else:
         where_clause = ""
         db_clusters = self.qb.db.clone()
         g.assurt(not db_clusters.dont_fetchall)
         db_clusters.dont_fetchall = True

      cluster_sql = (
         """
         SELECT
            cluster_id
            , ST_Length(geometry) AS geom_len
            , winningest_gfl_id
            , winningest_bike_facil
            , is_cycle_route
         FROM tiles_cache_byway_cluster
         %s
         """ % (where_clause,))

      rows = db_clusters.sql(cluster_sql)

      if rows is not None:

         g.assurt(len(rows) == 1)

         self.priority_set_row(rows[0])

      else:

         g.assurt(not new_cluster_id)

         log.debug('priority_set: Found %d clusters'
                   % (db_clusters.curs.rowcount,))

         time_0 = time.time()

         prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
         prog_log.log_freq = 2000
         prog_log.loop_max = db_clusters.curs.rowcount
         #prog_log.info_print_speed_enable = True
         prog_log.callee = 'priority_set'

         generator = db_clusters.get_row_iter()
         for row in generator:
            self.priority_set_row(row)
            if prog_log.loops_inc():
               break
         generator.close()

         if not new_cluster_id:
            db_clusters.close()

         prog_log.loops_fin()

# Is this redundant, since prog_log reported same?
         # MAYBE: A lot of these time logs are redundant -- loops_fin does it.
         log.info('priority_set: processed %d clusters: %s'
                  % (prog_log.progress,
                     misc.time_format_elapsed(time_0),))

   #
   def priority_set_row(self, row):

      geom_len = row['geom_len']

      # MAGIC_NUMBER: The MapServer docs say PRIORITY can be 1 to 10,
      #               from lowest to highest.
      label_priority = 1
      # We prioritize based on cluster length and bike facility
      # characteristics. We start with a basic priority value based on
      # the cluster length, and then we "bonus" the priority with there's
      # a bike facility present. This means -- especially when zoomed out
      # -- that roads with bike lanes and bike shoulders and cycle routes
      # and more likely to be labeled than just any old normal street.
      if geom_len < 62.5:
         label_priority = 1
      elif geom_len < 125.0:
         label_priority = 2
      elif geom_len < 250.0:
         label_priority = 3
      elif geom_len < 500.0:
         label_priority = 4
      elif geom_len < 1000.0:
         label_priority = 5
      elif geom_len < 2500.0:
         label_priority = 6
      elif geom_len < 6000.0:
         label_priority = 7
      elif geom_len < 10000.0:
         label_priority = 8
      else: # >= 10000.0
         label_priority = 9

      if row['winningest_gfl_id'] in (
            byway.Geofeature_Layer.Bike_Trail,
            byway.Geofeature_Layer.Major_Trail,):
         label_priority += 1
         if row['winningest_gfl_id'] == byway.Geofeature_Layer.Major_Trail:
            label_priority += 1
      if row['winningest_bike_facil']:
         # log.verbose('winningest_bike_facil: %s'
         #             % (row['winningest_bike_facil'],))
         label_priority += 1
      if row['is_cycle_route']:
         label_priority += 1

      if label_priority > 10:
         label_priority = 10

      # SKIPPING: There's also byway_count but geom_len seems better.

      g.assurt((label_priority >= 1) and (label_priority <= 10))
      update_sql = (
         """
         UPDATE tiles_cache_byway_cluster
         SET label_priority = %d
         WHERE cluster_id = %d
         """ % (label_priority, row['cluster_id'],))
      self.qb.db.sql(update_sql)
      self.stats_priorities.setdefault(label_priority, 0)
      self.stats_priorities[label_priority] += 1

      # Keep stats on the lengths by logarithmic pigeon hole.
      # [0, 10)
      # [10, 20)
      # ...
      # [80, 90)
      # [90, 100)
      # [100, 200)
      # ...
      # [1000, 2000)
      # [2000, 3000)
      # ...
      # [10000, 20000)
      range_min, range_max = misc.float_pigeon_hole(geom_len)
      if range_min and range_max:
         stat_index = range_min
      else:
         stat_index = -1
      stat_tuple = [0, range_max,]
      self.stats_cluster_lens.setdefault(stat_index, stat_tuple)
      self.stats_cluster_lens[stat_index][0] += 1
      g.assurt(self.stats_cluster_lens[stat_index][1] == range_max)

   #
   def prepare_tile_cache_byway_cluster_cycleroute(self):

      # MAYBE: Instead of using is_cycle_route, we could make a new
      #        geofeature_layer_id that indicates cycle_route, like
      #        Bike Trail vs. Major Trail.

      time_0 = time.time()

      #db_cycle_route_names = self.qb.db.clone()
      db_cycle_route_names = db_glue.new()
      g.assurt(not db_cycle_route_names.dont_fetchall)
      db_cycle_route_names.dont_fetchall = True

      sql_cycle_route_names = self.get_sql_cycle_route_names()
      rows = db_cycle_route_names.sql(sql_cycle_route_names)
      g.assurt(rows is None)

      log.info('_cluster_cycleroute: found %d names: %s'
               % (db_cycle_route_names.curs.rowcount,
                  misc.time_format_elapsed(time_0),))

      time_0 = time.time()

      # NO: prog_log = Debug_Progress_Logger(log_freq=1)
      prog_log = Debug_Progress_Logger(copy_this=debug_prog_log)
      prog_log.log_freq = 1
      prog_log.loop_max = db_cycle_route_names.curs.rowcount
      #prog_log.info_print_speed_enable = True
      prog_log.callee = '_cluster_cycleroute'

      last_name = None
      generator = db_cycle_route_names.get_row_iter()
      for row in generator:
         cur_name = row['value_text']
         if (not last_name) or (last_name.lower() != cur_name.lower()):
# FIXME: Do we have to rebuild the whole nameset, or can we just use cluster_id
#        from tiles_cache_clustered_byways to figure out what to rebuild? Or
#        doesn't that help much... seems we'd still have to rebuild by name.
            self.rebuild_cycle_route_named(cur_name)
            last_name = cur_name
         if prog_log.loops_inc():
            break
      generator.close()

      prog_log.loops_fin()

      db_cycle_route_names.close()

      self.cluster_stats_report()

# Is this redundant, since prog_log reported same? Maybe don't call loops_fin?
      log.info('_cluster_cycleroute: processed %d cycleroute names: %s'
               % (prog_log.progress,
                  misc.time_format_elapsed(time_0),))

   #
   def get_sql_cycle_route_names(self):

      if self.rebuild_all:

         # Use _all_ of the cycle routes' names.

         where_rev = self.qb_latest.revision.as_sql_where(
                        table_name='lv_iv',
                        include_gids=False,
                        allow_deleted=False)

         where_bbox = ""
         if self.restrict_bbox is not None:
            where_bbox = (
               "AND %s" % (self.restrict_bbox.sql_intersect("gf.geometry"),))

         sql_cycle_route_names = (
            """
            SELECT DISTINCT ON (lval.value_text) value_text
            FROM link_value AS lval
            JOIN item_versioned AS lv_iv
               ON (lval.system_id = lv_iv.system_id)
            WHERE
               lval.lhs_stack_id = %d
               AND %s
               %s
            ORDER BY lval.value_text ASC
            """ % (self.attr_cycle_route.stack_id,
                   where_rev,
                   where_bbox,))

      else:

         # Use just the names of those byways that changed.

         g.assurt(self.qb_update is not None)

         rev_former = revision.Historic(self.rid_former,
                                        gids=self.cli_args.group_ids,
                                        allow_deleted=False)

         where_rev_former = self.rev_former.as_sql_where(
                              table_name='lv_iv',
                              include_gids=False,
                              allow_deleted=True)

         where_rev_latest = self.qb_latest.revision.as_sql_where(
                              table_name='lv_iv',
                              include_gids=False,
                              allow_deleted=True)

         sql_cycle_route_names = (
            """
            SELECT DISTINCT ON (lval.value_text) value_text
            FROM link_value AS lval
            JOIN item_versioned AS lv_iv
               ON (lval.system_id = lv_iv.system_id)
            WHERE
               lval.lhs_stack_id = %d
               AND (%s OR %s)
            ORDER BY lval.value_text ASC
            """ % (self.attr_cycle_route.stack_id,
                   where_rev_former,
                   where_rev_latest,))

      return sql_cycle_route_names

   #
   def rebuild_cycle_route_named(self, cycle_route_name):

# FIXME: verbose...
      log.debug('rebuild_cycle_route_named: %s' % (cycle_route_name,))

      time_0 = time.time()

      link_many = link_attribute.Many('/byway/cycle_route')
      # No: link_many.attribute_load(self.qb_latest)
      attr_stack_id = self.attr_cycle_route.stack_id
      link_many.attr_stack_id = attr_stack_id

      self.qb_latest.filters.only_lhs_stack_id = attr_stack_id
      self.qb_latest.filters.filter_by_value_text = cycle_route_name

      g.assurt(self.qb_latest.sql_clauses is None)
      self.qb_latest.sql_clauses = (
         link_attribute.Many.sql_clauses_cols_all.clone())

      sql_links = link_many.search_get_sql(self.qb_latest)
      self.qb_latest.sql_clauses = None

      links = self.qb_latest.db.sql(sql_links)

      rhs_stack_ids = []
      for row_lval in links:
         rhs_stack_ids.append(str(row_lval['rhs_stack_id']))

      log.info('rebuild_cycle_route_named: processed %d lvals in %s'
               % (len(links),
                  misc.time_format_elapsed(time_0),))

      self.cluster_stats_reset()

      if rhs_stack_ids:
         self.rebuild_cluster_named(cycle_route_name,
                                    is_cycle_route=True,
                                    stack_ids=rhs_stack_ids)
      else:
         log.warning('rebuild_cycle_route_named: nothing for "%s": %s'
                     % (cycle_route_name, sql_links,))

   # ***

   #
   def cluster_stats_reset(self):

      # This counts the number of times same-named byways share the same node.
      self.stats_nid_use_cnt = {}
      self.stats_nids_usages = {}
      self.stats_byways_same_named = {}
      self.stats_byways_num_clusters = {}
      self.stats_num_byways_per_cluster = {}
      self.stats_gfl_usages = {}

   #
   def cluster_stats_report(self):

      log.debug('')
      log.debug('*** STATS ***')
      log.debug('')

      if self.stats_nid_use_cnt:
         log.debug('Counts of count of same-named byways using same node')
         use_cnts = self.stats_nid_use_cnt.keys()
         use_cnts.sort()
         for use_cnt in use_cnts:
            log.debug(' ... Node use count: %2d / Occurrences: %9d'
                      % (use_cnt, self.stats_nid_use_cnt[use_cnt],))
         log.debug('')

      if self.stats_nids_usages:
         log.debug('Byway names with nodes shared by 3 or more segments')
         use_cnts = self.stats_nids_usages.keys()
         use_cnts.sort()
         for use_cnt in use_cnts:
            log.debug(' ... Node use count: %2d / Byway names: %s'
                      % (use_cnt, self.stats_nids_usages[use_cnt],))
         log.debug('')

      if self.stats_byways_same_named:
         log.debug('Numbers of byways with the same name before clustering')
         bway_cnts = self.stats_byways_same_named.keys()
         bway_cnts.sort()
         for bway_cnt in bway_cnts:
            log.debug(
               ' ... No. byways in same-named group: %7d / Occurrences: %7d'
               % (bway_cnt, self.stats_byways_same_named[bway_cnt],))
         log.debug('')

      if self.stats_byways_num_clusters:
         log.debug('Numbers of byway clusters with same name after clustering')
         numbers_of_clusters = self.stats_byways_num_clusters.keys()
         numbers_of_clusters.sort()
         for number_of_clusters in numbers_of_clusters:
            log.debug(
               ' ... No. clusters in same-named group: %7d / Occurrences: %7d'
               % (number_of_clusters,
                  self.stats_byways_num_clusters[number_of_clusters],))
         log.debug('')

      if self.stats_num_byways_per_cluster:
         log.debug('Numbers of byways with same name and connected')
         numbers_of_byways = self.stats_num_byways_per_cluster.keys()
         numbers_of_byways.sort()
         for number_of_byways in numbers_of_byways:
            log.debug(
               ' ... No. same-named connected byways: %7d / Occurrences: %7d'
               % (number_of_byways,
                  self.stats_num_byways_per_cluster[number_of_byways],))
         log.debug('')

      if self.stats_gfl_usages:
         log.debug('Counts of count of byways per same-named cluster')
         numbers_of_byway_names = self.stats_gfl_usages.keys()
         numbers_of_byway_names.sort()
         for number_of_byway_names in numbers_of_byway_names:
            log.debug(
               ' ... No. different GFL IDs in cluster: %7d / Occurrences: %7d'
               % (number_of_byway_names,
                  self.stats_gfl_usages[number_of_byway_names],))
         log.debug('')

   #
   def other_stats_reset(self):

      self.stats_priorities = {}
      self.stats_cluster_lens = {}

   #
   def other_stats_report(self):

      if self.stats_priorities:
         log.debug('Counts of assigned priorities')
         numbers_of_clusters = self.stats_priorities.keys()
         numbers_of_clusters.sort()
         for number_of_clusters in numbers_of_clusters:
            log.debug(
               ' ... Priority: %7d / Occurrences: %7d'
               % (number_of_clusters,
                  self.stats_priorities[number_of_clusters],))
         log.debug('')

      # Logarithmic stats of cluster lengths.
      # MAYBE: Also do one of these for all byways?
      if self.stats_cluster_lens:
         log.debug('Cluster lengths')
         cluster_len_ranges = self.stats_cluster_lens.keys()
         cluster_len_ranges.sort()
         for range_min in cluster_len_ranges:
            stat_tuple = self.stats_cluster_lens[range_min]
            if range_min < 0:
               range_min = 0
            log.debug(
               ' ... Range (m): %6d to %6d / Occurrences: %7d'
               % (range_min, stat_tuple[1], stat_tuple[0],))
         log.debug('')

   # *** Render tiles

   #
   def update_tilecache_cache(self):

      if self.cli_opts.generate_tilecache_tiles:
         log.info('Updating Tilecache tile cache on all branches')
         # If branch_id is -1, we go through all the branches, otherwise we'll
         # just go through one branch.
         self.branch_iterate(self.qb,
                             self.cli_args.branch_id,
                             self.update_tiles_for_branch,
                             debug_limit)

      else:
         log.debug('update_tilecache_cache: Skipping per cli_opts/args')
         g.assurt(self.cli_opts.rebuild_cache_zooms
                  or self.cli_opts.rebuild_cache_instance
                  or self.cli_opts.remake_label_priority
                  or self.cli_opts.generate_cyclopath_cache)

   #
   def update_tiles_for_branch(self, branch_):

      self.cur_branch_sid = branch_.stack_id

      # Don't do any work unless one or more skins are attached.
      skin_names = self.get_skin_names(branch_)
      if skin_names:
         self.update_tiles_for_branch_(branch_, skin_names)

      self.cur_branch_sid = None

   # Random thoughts on locking...
   # We don't bother with try_lock_for_branch when updating tiles:
   # since we're not writing to the database, if we ran the script
   # simultaneously, we'd only be rewriting tiles. Perhaps earlier revisions
   # of tiles, but who cares: this would only happen if cron isn't working
   # properly or if a DEV is messing around on the command line. And we could
   # also conceivably want to update tiles and then -- when a new revision is
   # saved -- update the database while tiles are still being updated. Meaning,
   # we'd need a different lock name. And then what? Would we make a lock for
   # every branch-skin-zoom combination? This all seems very tedious.

   #
   def update_tiles_for_branch_(self, branch_, skin_names):

      log.debug('TileCache: processing branch "%s" (%d) / skins: %s'
                % (branch_.name, branch_.stack_id, skin_names,))

      branch_time_0 = time.time()

      self.branch_bboxes = {}

      # We have to iterate over the skins and look at their last_rids to
      # decide if we should call tilecache_seed.
      for skin_name in skin_names:

         skin_time_0 = time.time()

         self.cur_skin_name = skin_name
         self.cur_tile_skin = self.get_tile_skin()

         if self.cli_opts.restrict_zoom:
            zoom_min = self.cli_opts.restrict_zoom[0]
            zoom_max = self.cli_opts.restrict_zoom[1]
            zoom_levels = range(zoom_min, zoom_max + 1)
         else:
            zoom_levels = list(self.cur_tile_skin.zooms_deffed)
            zoom_levels.sort()

         for zoom_level in zoom_levels:

            log.debug(
               'Processing branch named "%s" (%d) / skin "%s" / zoom %d'
               % (branch_.name, branch_.stack_id, skin_name, zoom_level,))

            zoom_time_0 = time.time()

            # Setup self.qb_latest and self.qb_update.
            self.setup_qbs(branch_, zoom_level)

            if self.qb_latest is None:
               # Because: (not rebuild_all) and (rid_former == rid_latest).
               log.debug('BranZoomSkin rev. ID unchanged; skipping: at rev: %d'
                         % (self.rid_latest,))
            else:
               # Determine the bbox we'll tell tilecache_seed.py about.
               self.setup_tile_indices(zoom_level)
               # EXPLAIN: Why would indices xmin,xmax,ymin,ymax not compute?
               if self.tile_indices_okay:
                  # Maybe delete the existing tilecache-cache folder.
                  self.cleanup_tilecache_cache()
                  # Render the tiles. We'll call tilecache_seed.py.
                  self.render_and_cache_tiles(zoom_level)
               else:
                  log.warning('upd_tiles_for_br_: not self.tile_indices_okay')

            self.close_qbs()

            log.info('Processed branch "%s" skin "%s" zoom %d: ran %s'
               % (branch_.name, skin_name, zoom_level,
                  misc.time_format_elapsed(zoom_time_0),))

         self.cur_skin_name = None
         self.cur_tile_skin = None

         log.info(
            'Processed branch "%s" skin "%s": ran %s'
            % (branch_.name,
               skin_name,
               misc.time_format_elapsed(skin_time_0),))

      del self.branch_bboxes

      log.info('Processed branch "%s": ran %s'
               % (branch_.name,
                  misc.time_format_elapsed(branch_time_0),))

   #
   def setup_tile_indices(self, zoom_level):

      self.tile_xmin = None
      self.tile_ymin = None
      self.tile_xmax = None
      self.tile_ymax = None

      if not self.cli_opts.tilecache_tiles:
         if self.determine_indices_bbox():
            self.determine_tile_indices(zoom_level)
      else:
         # FIXME: This code is not used/untested. You might be able to get tile
         #        indices by enabling a debug option in flashclient that shows
         #        the tile index when you hover over a tile; otherwise, you
         #        could probably inspect the tilecache_update log file to find
         #        what indices are used.
         (self.tile_xmin,
          self.tile_ymin,
          self.tile_xmax,
          self.tile_ymax,) = self.cli_opts.tilecache_tiles

      # Ha. Use 'is not None' to accommodate 0 value. Otherwise,
      # tiles starting at 0,0 will not be rendered.
      self.tile_indices_okay = (    (self.tile_xmin is not None)
                                and (self.tile_ymin is not None)
                                and (self.tile_xmax is not None)
                                and (self.tile_ymax is not None))

   #
   def determine_indices_bbox(self):

      # Figure out the bbox of the tiles we'll be generating.

      # If we've calculated the bbox for a particular revision to the latest
      # revision for this branch, it's cached.

      if not self.rebuild_all:
         bbb_index = self.rid_former
      else:
         bbb_index = 0

      try:

         branch_bbox = self.branch_bboxes[bbb_index]

      except KeyError:

         if self.restrict_bbox is not None:

            # Specified on cmd line via --bbox or --county.
            self.xmin = self.restrict_bbox.xmin
            self.ymin = self.restrict_bbox.ymin
            self.xmax = self.restrict_bbox.xmax
            self.ymax = self.restrict_bbox.ymax

         else:

            # There's no bbox on the command line, so figure one out.
            # NOTE: If we don't specify --bbox, TileCache starts at 0,0 in the
            # SRS, but, e.g., the Mpls-St.Paul map starts at 300000,5000000. So
            # you'd increase runtime and tiles by gobs of magnitude.
            if not self.rebuild_all:
               # Use the update rev to find those byways that have changed.
               # NOTE: This finds byways whose link_value's attachments may
               #       have changed. I.e., maybe someone edited something
               #       about a byway that we don't care about. And maybe we're
               #       rebuilding a tile we don't need to rebuild. But that
               #       seems like a tough problem to solve and completely
               #       frivolous.
               # ALSO: We've already calculated the bbox for each revision
               #       (revision.bbox) so we could instead iterate from
               #       rid_former.bbox through to rid_latest.bbox, but that
               #       also seems tedious, and we probably don't need to worry
               #       about resource usage on update.
               if not self.qb_update.filters.stack_id_table_ref:
                  if not self.qb_update.db.transaction_in_progress():
                     self.qb_update.db.transaction_begin_rw()
                  Item_Manager.create_update_rev_tmp_table(self.qb_update)
               if Item_Manager.temp_table_update_sids_cnt > 0:
                  qb_bbox = self.qb_update
               else:
                  qb_bbox = None
                  branch_bbox = (None, None, None, None,)
                  log.debug('determine_indices_bbox: nothing updated: rev: %s'
                            % (str(ref_qb.revision),))
            else:
               # We're rebuilding all tiles, so determine the extent of all the
               # byways.
               qb_bbox = self.qb_latest
            g.assurt(self.cur_branch_sid)

            if qb_bbox is not None:
               branch_bbox = byway.Many.get_branch_bbox(
                           qb_bbox, self.cur_branch_sid)

            (self.xmin,
             self.ymin,
             self.xmax,
             self.ymax,) = branch_bbox

            self.branch_bboxes[bbb_index] = branch_bbox

      # If the bbox is not defined, there are no tiles to update.
      theres_tiles_to_render = False
      if ((self.xmin is None)
          or (self.ymin is None)
          or (self.xmax is None)
          or (self.ymax is None)):
         # Nothing changed. This only makes sense for --new: an --all or a
         # --bbox should find something (well, probably).
         # This is the path cron takes if there's nothing to update.
         log.info('No bbox; nothing changed; skipping tiles.')
         g.assurt(    (self.xmin is None)
                  and (self.ymin is None)
                  and (self.xmax is None)
                  and (self.ymax is None))
      else:
         log.info('Updating using bbox: (%.1f, %.1f) to (%.1f, %.1f)'
                    % (self.xmin, self.ymin, self.xmax, self.ymax,))
         theres_tiles_to_render = True

      return theres_tiles_to_render

   #
   def determine_tile_indices(self, zoom_level):

      xmin_i = TCU.coord_to_tileindex(zoom_level, self.xmin)
      ymin_i = TCU.coord_to_tileindex(zoom_level, self.ymin)
      xmax_i = TCU.coord_to_tileindex(zoom_level, self.xmax)
      ymax_i = TCU.coord_to_tileindex(zoom_level, self.ymax)
      #
      self.tile_xmin = TCU.tileindex_to_coord(zoom_level, xmin_i)
      self.tile_ymin = TCU.tileindex_to_coord(zoom_level, ymin_i)
      # We'd have to add 1 to the max tiles x and y to be sure to include
      # the upper-most and right-most tiles, but we use --padding 1 when
      # we call tilecache_seed, which does the same thing.
      # FIXME: Verify this. Also, by using --padding 1, are we really get
      #        an extra row and column of left-most and bottom-most
      #        tiles?
      # If --padding 0:
      #  xmax_i += 1
      #  ymax_i += 1
      self.tile_xmax = TCU.tileindex_to_coord(zoom_level, xmax_i)
      self.tile_ymax = TCU.tileindex_to_coord(zoom_level, ymax_i)

      #
      log.debug(
         '_tile_indices: zoom: %d / tiles (%s, %s) to (%s, %s) / %d total'
         % (zoom_level, xmin_i, ymin_i, xmax_i, ymax_i,
            (xmax_i - xmin_i + 1) * (ymax_i - ymin_i + 1),))
      #
      log.debug(
         '_tile_indices: zoom: %d / bbox (%s, %s) to (%s, %s)'
         % (zoom_level, self.tile_xmin, self.tile_ymin,
                        self.tile_xmax, self.tile_ymax,))

   #
   def get_tilecache_layer_name(self):
      # SYNC_ME: Search: TileCache layer name.
      tc_layer_name = ('%s-%s-%s' % (conf.instance_name,
                                     self.cur_branch_sid,
                                     self.cur_skin_name,))
      return tc_layer_name

   #
   def cleanup_tilecache_cache(self):

      if self.cli_opts.remove_cache:

         g.assurt(self.cur_branch_sid)
         g.assurt(self.cur_skin_name)

         # SYNC_ME: Search: TileCache layer name.
         tc_layer_name = self.get_tilecache_layer_name()

         tilecache_cache_dir = os.path.join(conf.tilecache_cache_dir,
                                            tc_layer_name)

         if os.path.exists(tilecache_cache_dir):
            log.debug('Deleting cache dir: %s' % (tc_layer_name,))
            shutil.rmtree(tilecache_cache_dir)
         else:
            log.debug('No cache dir: %s' % (tc_layer_name,))

         # Delete all the zoom level last rids for this branch-skin.
         # We use LIKE, otherwise we'd xrange(conf.ccp_min_zoom ccp_max_zoom+1)
         # This is, i.e.,
         #  LIKE 'tilecache-last_rid-branch_1234567-skin_bikeways%'
         self.qb.db.sql("DELETE FROM key_value_pair WHERE key LIKE '%s%%'"
                        % (self.get_last_rid_key_tilecs_basename(),))

# IMPLEMENT: self.cli_opts.async_procs
#
# Make metasize x metasize calls and use Pool to make just one tilecache_seed
# call at a time from the different worker threads
# FIRST: Test different 20 x 20 tile areas to see that tilecache just calls
# mapserver once regardless of the divisibility of x and y -- i.e.,
# use --tiles, i.e.,
# --tiles 0 0 19 19 should be just one mapserver call, and
# --tiles 1 1 20 20 should also be just one call, but different bbox
#
# import multiprocessing
# multiprocessing.cpu_count()
# processes should be smaller than cpu_count... specify in CONFIG...
# work_queue = multiprocessing.Pool(processes=4)
#
# Jan-08 00:30:47  DEBG  tilecache_update  #  render_and_cache_tiles: indices (782, 9587) to (1063, 9880)
# Jan-08 00:30:47  DEBG  tilecache_update  #  render_tiles: zoom: 15 / use bbox: True: (400384.0, 4908544.0) to
#                                          #   (544256.0, 5058560.0)

   #
   def render_and_cache_tiles(self, zoom_level):
      'Update the tiles in the bounding box at the given zoom'

      log.debug('render_tiles: zoom: %d / tile bbox: (%s, %s) to (%s, %s)'
                % (zoom_level, self.tile_xmin, self.tile_ymin,
                               self.tile_xmax, self.tile_ymax,))

      # SYNC_ME: This is where ./gen_tilecache_cfg.py creates the config,
      #          also see TileCacheConfig in the Apache conf.
      tilecache_cfg_switch = ('--config=%s/tilecache.cfg'
                              % (conf.tilecache_cache_dir,))

      # Confine this render to the correct bounding box. Note: tilecache is
      # configured to generate a buffer around this bbox (which just defaults
      # to 10 pixels, to avoid edge artifacts...).
      bbox_option = '--bbox=%d,%d,%d,%d' % (self.tile_xmin, self.tile_ymin,
                                            self.tile_xmax, self.tile_ymax,)

      g.assurt(self.cur_skin_name)
      tc_layer_name = self.get_tilecache_layer_name()

      # Map Cyclopath levels to TileCache levels (FIXME: this mapping depends
      # strongly on the TileCache config).
      #
      # SYNC_ME: See tilecache.cfg's resolutions. TileCache assigns zoom
      #          numbers based on the number of resolutions that are defined.
      #
      # CP  TC  resolution
      #  5  14  2048
      #  6  13  1024
      #  7  12   512
      #  8  11   256
      #  9  10   128
      # 10  09    64
      # 11  08    32
      # 12  07    16
      # 13  06     8
      # 14  05     4
      # 15  04     2
      # 16  03     1:1
      # 17  02   0.5
      # 18  01   0.25
      # 19  00   0.125
      #
      tc_level = conf.ccp_max_zoom - zoom_level

      # Call tilecache_seed.py to render the actual tiles.

      os.chdir(conf.tilecache_dir)

      # --force to force rebuild - these tiles are stale
      #
      # --padding because tilecache_seed.py doesn't seem to actually guarantee
      # that all tiles within the bounding box will be rebuilt!?
      #
      args = ['nice',
              './tilecache_seed.py',
              '--force',
              # FIXME: Should we pad? We already figure out the tile indices
              #        explicitly, so I think we might be making extra tiles
              #        around the perimeter... but better safe than sorry?
              '--padding=1',
              tilecache_cfg_switch,
              bbox_option,
              tc_layer_name,
              str(tc_level),
              # NOTE: The zoom range in tilecache_seed.py is inclusive on the
              # bottom and exclusive on the top, so we have to add 1.
              str(tc_level+1),
              ]

      log.debug('tilecache_seed args: %s' % (args,))

      # FIXME: PERFORMANCE: Use multiprocessing.Pool to use multiple cores to
      #                     make tiles.

      # Trap output so we can log it instead of getting cron emails about it.
      (sout, serr) = subprocess.Popen(args,
                                      stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT).communicate()

      found_err = False
      log.debug('')
      log.debug('TileCache output:')
      log.debug('')
      for line in sout.split('\n'):
         if line:
            log.debug('  %s' % line)
            if line.lower().find('err') != -1:
               found_err = True
      log.debug('')
      # FIXME: What's communicate()? This is different than other usages, e.g.,
      #p = subprocess.Popen(args,
      #                     shell=True,
      #                     # bufsize=bufsize,
      #                     stdin=subprocess.PIPE,
      #                     stdout=subprocess.PIPE,
      #                     stderr=subprocess.STDOUT,
      #                     close_fds=True)
      #(sin, sout_err) = (p.stdin, p.stdout)
      #while True:
      #   line = sout_err.readline()
      #   if not line:
      #      break
      #   else:
      #      line = line.strip()
      #sin.close()
      #sout_err.close()
      #p.wait()

      if found_err:
         log.error('')
         log.error('*****************************************')
         log.error('*                                       *')
         log.error('*    WARNING: tilecache_seed failed     *')
         log.error('*                                       *')
         log.error('*****************************************')
         log.error('')

      # Remember the last_rid for this branch, skin, and zoom.
      if (not self.restrict_bbox) and (not debugging_enabled):
         self.last_rid_update_for_zoom(zoom_level)

   #
   def last_rid_update_for_zoom(self, zoom_level):
      # This fcn. updates the last_rid for the branch-skin-zoom. We could just
      # use insert_clobber but we'd rather over-engineer instead and check for
      # concurrency issues.
      #
      # Get a new db connection -- we can't commit with mult. cursors open.
      # NO: db = self.qb.db.clone()
      db = db_glue.new()
      db.transaction_begin_rw()
      # Read the current last_rid value.
      last_rid_key_name = self.get_last_rid_key_name_tilecs(zoom_level)
      select_sql = ("SELECT value FROM key_value_pair WHERE key = '%s'"
                    % (last_rid_key_name,))
      rows = db.sql(select_sql)
      # See what the last value writ is.
      error_on = None
      if rows:
         g.assurt(len(rows) == 1)
         saved_last_rid = int(rows[0]['value'])
         if saved_last_rid >= self.rid_former:
# FIXME: 2013.02.13: [lb] sees this on --update. Are we
#        unnecessarily rebuilding tiles when revision has
#        not changed?
            log.warning('Unexpected: saved last_rid >= our last_rid: %d >= %d'
                        % (saved_last_rid, self.rid_former,))
         else:
            # Try to update the last_rid.
            update_sql = (
               "UPDATE key_value_pair SET value = '%s' WHERE key = '%s'"
               % (str(self.rid_latest), last_rid_key_name,))
            try:
               db.sql(update_sql)
               db.transaction_commit()
            except psycopg2.extensions.TransactionRollbackError, e:
               # This happens on concurrent update.
               error_on = 'update'
      else:
         # Try to insert the last_rid.
         insert_sql = (
            "INSERT INTO key_value_pair (key, value) VALUES ('%s', '%s')"
            % (last_rid_key_name, str(self.rid_latest),))
         # This isn't already set, is it? If so, we'd want to reset it.
         if db.integrity_errs_okay:
            log.warning(
               'last_rid_update_for_zoom: unexpected integrity_errs_okay')
         db.integrity_errs_okay = True
         try:
            db.sql(insert_sql)
            db.transaction_commit()
         except psycopg2.IntegrityError, e:
            # This happens on duplicate key value violates unique constraint.
            error_on = 'insert'
         db.integrity_errs_okay = False
      if error_on:
         db.transaction_rollback()
         rows = db.sql(select_sql)
         g.assurt(len(rows) == 1)
         newer_last_rid = rows[0]['value']
         log.warning('Unable to %s: "%s" concurrently set to: "%s"'
                     % (error_on, last_rid_key_name, newer_last_rid,))
      db.close()

   # *** Utility fcns.

   @staticmethod
   def coord_to_tileindex(zoom, c):
      '''Return the tile index containing coordinate c at zoom level zoom. See
      the technical documentation for more information.'''
      return int(c / TCU.meters_per_tile(zoom))

   @staticmethod
   def meters_per_tile(zoom):
      # The tile size, conf.tile_size, is, e.g., 256 pixels.
      # CcpV1 used MAGIC_NUMBER 16: return 1.0 * conf.tile_size / 2**(zoom-16)
      # Zoom  5: 524288.0 meters/tile
      #  ... 16: 256.0 meters/tile (1:1 meter:pixel)
      #  ... 19:  32.0 meters/tile
      return (
         float(conf.tile_size)
         / float(2**(zoom - conf.tilecache_one_meter_to_one_pixel_zoom_level)))

   @staticmethod
   def tileindex_to_coord(zoom, i):
      '''Return the coordinate of the smaller edge of tile with index i.'''
      return (i * TCU.meters_per_tile(zoom))

# ***

if (__name__ == '__main__'):
   tcu = TCU()
   tcu.go()


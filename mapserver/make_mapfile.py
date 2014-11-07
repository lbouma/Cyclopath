#!/usr/bin/python

# Copyright (c) 2006-2012 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# Usage:
#
#  $ cd $cp/mapserver
#  $ ./make_mapfile.py
#  # Don't forget to rebuild the actual mapfile!
#  # (The file this script creates is used as an include by m4.)
#  $ m4 wms-minnesota.m4 > /ccp/var/tilecache-cache/wms-minnesota.map
#
# DEVS: Try this:
# SYNC: The MS_MAPFILE setting the httpd.conf matches wms-[instance].map:
'''

sudo -v

psql -U cycling -c "DELETE FROM tiles_mapserver_zoom" ccpv3_demo
cd $cp/mapserver
./tilecache_update.py --db-create-public-zooms
# WEIRD! If this script fails, and then you re-run it, sometimes the
#        tiles_mapserver_zoom row count is 0. But then you re-run (a
#        third time) and the row count is 300! Hrmpf!
#psql -U cycling -h localhost -p 7432 \
#   -c "SELECT COUNT(*) FROM tiles_mapserver_zoom" \
#   ccpv3_demo
psql -U cycling -c "SELECT COUNT(*) FROM tiles_mapserver_zoom" ccpv3_demo

cd $cp/mapserver
./flashclient_classes.py

cd $cp/mapserver
./make_mapfile.py
#./make_mapfile.py --bridge 134 134

m4 wms-minnesota.m4 > wms_instance.map
/bin/mv -f wms_instance.map /ccp/var/tilecache-cache/cp_2628/
/bin/rm -f byways_and_labels.map

sudo /bin/rm -rf /ccp/var/tilecache-cache/cp_2628/fonts
/bin/cp -rf fonts/ /ccp/var/tilecache-cache/cp_2628
/bin/cp -f fonts.list /ccp/var/tilecache-cache/cp_2628

sudo chown -R $httpd_user /ccp/var/tilecache-cache/cp_2628/
sudo chgrp -R $httpd_user /ccp/var/tilecache-cache/cp_2628/
sudo chmod 2775 /ccp/var/tilecache-cache/cp_2628/
sudo chmod 2775 /ccp/var/tilecache-cache/cp_2628/fonts/
sudo chmod 664 /ccp/var/tilecache-cache/cp_2628/fonts.list
sudo chmod 664 /ccp/var/tilecache-cache/cp_2628/wms_instance.map
sudo chmod 664 /ccp/var/tilecache-cache/cp_2628/fonts/*

sudo -u $httpd_user \
   INSTANCE=minnesota___cp_2628 \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
      --tilecache-tiles --all \
      --zoom 05 11




      --zoom 07 07
      --zoom 08 11


      --zoom 08 11










      --zoom 05 05
      --zoom 05 06

--zoom 05 09




sudo -u $httpd_user \
   INSTANCE=minnesota___cp_2628 \
   PYTHONPATH=$PYTHONPATH \
   PYSERVER_HOME=$PYSERVER_HOME \
    ./tilecache_update.py \
      --branch "Minnesota" \
      --tilecache-tiles --all \
      --zoom 05 05 \
      --bbox 0 1179648.0 524288 1703936.0
--bbox 0 4718592 524288 5242880


Zoom 6...
http://localhost:8088/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=262144,4718592,524288,4980736&WIDTH=256&HEIGHT=256&FORMAT=image/png

'''
#
#  NOTE: mapserver/wms.map includes the mapfile that this script makes,
#        mapserver/byways.map.

script_name = ('Make my mapfile')
script_version = '1.0'

__version__ = script_version
__author__ = 'Cyclopath <info@cyclopath.org>'
__date__ = '2012-12-28'

import math
import re

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys
# Setup our paths before calling pyserver_glue, which calls os.chdir.
# FIXME: See comments in gen_tilecache_cfg.py about why mapserver/
#        is world-writeable and why we should fix it... maybe.
path_to_new_file = os.path.abspath(
   '%s/byways_and_labels.map' % (os.path.abspath(os.curdir),))
# Now load pyserver_glue.
assert(os.path.sep == '/') # We only run on Linux.
sys.path.insert(0, os.path.abspath('%s/../scripts/util' 
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
log_level = logging2.VERBOSE2
log_level = logging2.VERBOSE4
#log_level = logging2.VERBOSE
conf.init_logging(True, True, Console.getTerminalSize()[0]-1, log_level)

log = g.log.getLogger('make_mapfile')

#from grax.access_level import Access_Level
#from gwis.query_branch import Query_Branch
#from item import item_base
#from item import link_value
#from item.attc import attribute
#from item.feat import branch
from item.feat import byway
#from item.feat import route
#from item.grac import group
#from item.link import link_attribute
#from item.link import link_tag
#from item.util import ratings
#from item.util import revision
from item.util.item_type import Item_Type
from skins.tile_skin import Tile_Pen
from skins.tile_skin import Tile_Skin
from util_ import db_glue
#from util_ import geometry
#from util_ import gml
from util_.mod_loader import Mod_Loader
from util_.script_args import Ccp_Script_Args
from util_.script_base import Ccp_Script_Base

# *** Cli Parser class

class ArgParser_Script(Ccp_Script_Args):

   #
   def __init__(self):
      Ccp_Script_Args.__init__(self, script_name, script_version)

   #
   def prepare(self):

      Ccp_Script_Args.prepare(self)

      # 2013.12.02:
      #
      #    SELECT z_level, COUNT(*)
      #    FROM tiles_cache_byway_segment
      #    GROUP BY z_level ORDER BY z_level;
      #
      #        z_level | count  
      #       ---------+--------
      #            130 |     59
      #            131 |     23
      #            132 |    161
      #            133 |    469
      #            134 | 483287
      #            135 |    362
      #            136 |    912
      #            137 |    217
      #            138 |     30
      #       (9 rows)
      #
      # BUG nnnn: Fix z_levels 130, 131, 137, 138 to use 132-136... save so
      #           much tilecache time...
      #
      # DEVS: Use this (temporarily) when testing tiles to make it 88.8%
      #       faster. E.g., -l 134 134
      # 
      self.add_argument(
         '-l', '--bridge', dest='bridge_levels', type=int, nargs=2,
         default=(byway.One.z_level_min, byway.One.z_level_max),
         help='For debugging: render just these bridge_levels (130 to 138)')

   #
   def verify(self):

      verified = Ccp_Script_Args.verify(self)

      if ((self.cli_opts.bridge_levels[0] < byway.One.z_level_min)
          or (self.cli_opts.bridge_levels[1] > byway.One.z_level_max)):
         log.error('Please specify bridge levels between %d and %d, inclusive.'
                   % (byway.One.z_level_min, byway.One.z_level_max,))
         verified = False
         self.handled = True

      return verified

   # ***

# *** TileCache_Update

# FIXME_2013_06_12: mapserver config or logrotate or cron needs to deal with
#                    /tmp/mapserv.debug.txt
# FIXME: 2013.05.29: On runic, /tmp/mapserv.debug.txt is 4Gb and Bash commands
#  BUG nnnn:         are failing because tmp space is full... do we have to
#                    manually delete this file?
# 2013.09.03: The file is 100 Mb and [lb] doesn't see any errors, so it's
#             not known what logcheck would look for (unless we just made
#             rules to ignore all the non-error lines). 
#             So maybe we don't need to add the generated file's log to
#             logcheck.

class Make_Mapfile(Ccp_Script_Base):

   # ***

   # The gfl ordering is the order in which each type of geofeature_layer is
   # drawn. This only applies per z-level, so that a line with a larger z-level
   # always gets drawn on top of lines with lower z-levels. But in each z-level
   # group, we'll stack lines according to geofeature_layer. This is because,
   # e.g., expressways are drawn wider than trail and we don't want a highway
   # parallel to a trail to be drawn atop the trail.
   # SYNC_ME: Search geofeature_layer table. Search draw_class table, too.
   gfl_ordering = [
      byway.Geofeature_Layer.Expressway,
      byway.Geofeature_Layer.Expressway_Ramp,
      byway.Geofeature_Layer.Railway,
      byway.Geofeature_Layer.Private_Road,
      byway.Geofeature_Layer.Other_Ramp,
      byway.Geofeature_Layer.Parking_Lot,
      byway.Geofeature_Layer.Highway,
      byway.Geofeature_Layer.Unknown,
      byway.Geofeature_Layer.Other,
      byway.Geofeature_Layer.Sidewalk,
      byway.Geofeature_Layer.Doubletrack,
      byway.Geofeature_Layer.Singletrack,
      byway.Geofeature_Layer._4WD_Road,
      byway.Geofeature_Layer.Byway_Alley,
      byway.Geofeature_Layer.Local_Road,
      byway.Geofeature_Layer.Major_Road,
      byway.Geofeature_Layer.Bike_Trail,
      byway.Geofeature_Layer.Major_Trail,
      ]

   # ***

   def __init__(self):
      Ccp_Script_Base.__init__(self, ArgParser_Script)
      self.map_f = None

   # ***

   #
   def go_main(self):

      self.map_f = open(path_to_new_file, "w")
      self.write_mapfile()
      self.map_f.close()
      self.map_f = None

   # ***

   #
   def write_mapfile(self):

      # CcpV1 used a very basic mapfile for the line segments. It defined one
      # layer for each zoom level, and each layer includes the same sub-layer
      # file which defines the SQL to call to get the byways. 1) Unfortunately,
      # a MapServer limitation makes it hard to use data from the database
      # to skin layers according to zoom level and geofeature_layer (since
      # the colors and widths, etc., vary from zoom to zoom and from
      # geofeature_layer to geofeature_layer, and since MapServer doesn't read
      # these cell values except for the first row to match, you have to cross
      # join a lookup table that defines columns for all possible combinations,
      # but this makes the mapfile and cache tables tedious and confusing).
      # 2) Also, since we use the same SQL and MapServer only lets us use
      # FILTER to change the WHERE clause, we can't change the ORDER BY, which
      # is a problem: if we sort by z-level and then by geofeature_layer, we'll
      # end up with highways obscuring bike paths (like Mpls' Kenilworth Trail,
      # which runs alongside I-394). This is fine when there's an underpass,
      # but if the two lines are simply parallel, since the highway line is
      # wider, it'll obscure the bike trail line.
      # So in CcpV2, we split each zoom-level layer into multiple layers, one
      # for each geofeature_layer, and we also make layers for ornaments, like
      # bike lane and bikeable shoulder, and we process each z-level as a
      # separate layer. Basically, we make lots of layers.

      # BUGBUG: MapServer is weird. When you define a style using attributes,
      # e.g., LAYER ... CLASS ... STYLE COLOR [pen_color] WIDTH [pen_width]
      # END ... then MapServer only computes the STYLE once, so it uses the
      # color and width of the first row it finds in the database query: so
      # if a later row has a different color and width, it doesn't apply, as
      # MapServer just uses the first color and width it finds. So! We have to
      # define CLASSes for each of the geofeature layer types... or we have to
      # define LAYERs for all possible combinations of zoom_levels, z-levels,
      # and geofeature_layer or embellishment.

# BUG nnnn: Restrict byway z-level to 130 to 138, inclusive. Maybe even make
# the list shorter: we should have street-level, underpass and overpass, and
# maybe under-under and over-over, for extreme cases... but what about
# curly-ques? maybe we do need all 9 nine levels... anyway, make sure client
# cannot set whatever z it wants, though.
# select z, count(*) from geofeature where geofeature_layer_id = 31 group by z order by z;
#  z  | count 
#-----+-------
# 130 |    14
# 132 |     9
# 133 |    82
# 134 |  6809
# 135 |    48
# 136 |     6
# 137 |    42
# 138 |     3

      # One layer for each zoom_level (e.g., 9 through 15).
      for zoom_level in xrange(conf.ccp_min_zoom, conf.ccp_max_zoom+1):

         self.map_f.write("\n   # *** Zoom Level Layers: %d\n" % (zoom_level,))

         scale_denominator = self.get_scale_denominator(zoom_level)

         # One layer for each z_level (e.g., 130 through 138).

         # HACK: This is so we only have to do three passes and not 9...
         if ((self.cli_opts.bridge_levels[0] == byway.One.z_level_min)
             and (self.cli_opts.bridge_levels[1] == byway.One.z_level_max)):
            z_levels = ['130,131,132,133', '134', '135,136,137,138',]
         else:
            z_levels = [str(x) for x in range(self.cli_opts.bridge_levels[0],
                                             self.cli_opts.bridge_levels[1]+1)]

         for z_level_group in z_levels:

            self.map_f.write("\n   # *** Z-Level Layers: %s\n" % (z_levels,))

            # One layer for each geofeature_layer.
            # 2012.12.28: There are currently 13 geofeature_layer.
            for gfl_id in Make_Mapfile.gfl_ordering:

               self.map_f.write("\n   # *** GFL ID Layers: %d\n" % (gfl_id,))

               # NOTE: We're not checking do_draw here, because the skin can be
               #       changed at runtime (i.e., without generating a new
               #       mapfile).
               # Make one layer for the geofeature_layer and one each layer for
               # the embellishments (like bike facility type, closed, etc.).
               # 2012.12.28: 7 zoom levels, 9 z-levels, and 13 geofeature
               #             layers is 819 layers. If you also include the
               #             embellishment and label layers, that's
               #             819 * 4 = 3276 layers.
               # 2013.11.18: Now 9 tile zoom levels, 7 to 15.
               # 2013.11.19: Now 10 tile zoom levels, 6 to 15.
               # NOTE: The docs say MapServer < v5 supported 200 layers
               #       maxmimum, but the current MapServer has no limit.
               #         http://www.mapserver.org/mapfile/
               args = {
                  'srid': conf.default_srid,
                  'zoom_level': zoom_level,
                  'z_levels': z_level_group,
                  'z_levels_name': z_level_group.replace(',', '_'),
                  'gfl_id': gfl_id,
                  'scale_denominator': scale_denominator,
                  }

               # NOTE: These are drawn in order, so the later functions are
               #       drawn laster.
               # The layer for the geofeature type.
               self.add_layer_geofeature(args)

               # The bike facility embellishment.
               # MAGIC_NUMBER: The 'bike_facil' key is used... many places.
               #               And then there's the caution attr, too.
               self.add_layer_bike_facility('bike_facil', args)
               self.add_layer_bike_facility('cautionary', args)
               # The bike cluster -- draw on top of all else! (except closed!)
               self.add_layer_cycle_route(args)
               # The closed/restricted embellishment.
               self.add_layer_restricted(args)
               # The line segment labels!
               # NOTE: We left LABELCACHE on, so labels will be cached until
               #       the whole layer is rendered, so MapServer can figure out
               #       priorities and remove excess labels, etc.
               # BUG nnnn: Label regions and lakes and parks and whatnots.
               self.add_layer_labels(args)

            # end: for gfl_id

         # end: for zoom_level

      # end: for geofeature_layer

   # ***

   # 

   # MapServer is told the scale thusly: "MINSCALEDENOM: Maximum scale at which
   # this LAYER is drawn. Scale is given as the denominator of the actual scale
   # fraction, for example for a map at a scale of 1:24,000 use 24000."
   #
   # Since we're scaling from real life meters (our projection) to
   # computer-monitor resolution (72 DPI), we have to convert from
   # dots-per-inch to meters.

   screen_dpi = 72.0
   meters_per_inch = 0.0254 # Exactly. So sayeth the governments.
   dpi_in_meters = screen_dpi / meters_per_inch

   #
   def get_scale_denominator(self, zoom_level):

      # 2013.11.19: [lb] adding Zooms 6, 7 and 8 for Greater MN.
      # Zoom 8 worked with existing code (I just had to change
      # the ccp_min_zoom in pyserver and flashclient, and add
      # the zooms to the skins files, and rerun all the scripts
      # that generate code and confs). But Zoom 7 doesn't work
      # with the calculated scale denominators:
      #  Wrong for Zoom 7:
      #     MINSCALEDENOM 1451338
      #     MAXSCALEDENOM 1451339
      #  What we want is one more:
      #     MINSCALEDENOM 1451339
      #     MAXSCALEDENOM 1451340
      #  Our calculated value is 1451338.5826771655... so there
      #  must be enough error in precision that it's affected
      #  our calculation.
      #  But that's okay: the demon scale calculation being used
      #  was a little strict: it insisted that there was only one
      #  acceptable demoninator. But we have room for fudge.
      g.assurt(zoom_level > 0)
      offset = conf.tilecache_one_meter_to_one_pixel_zoom_level - zoom_level
      scale = math.pow(2.0, offset)
      exactish_scale_denom = scale * Make_Mapfile.dpi_in_meters
      # Here's the old, strict code:
      #  scale_denominator_int_0 = int(math.floor(exactish_scale_denom))
      #  scale_denominator_int_1 = scale_denominator_int_0 + 1
      # Since our zoom levels are mults. of two of one another, it's easy to
      # adjust the demon scale to be more accepting. The easiest, fudgiest
      # thing to do is just to use one-quarter of the scale we calculated:
      # we won't bump into the adjacent zoom levels' scale denominator windows.
      # 2013.11.19:
      # Zoom_level || scale denominator || window
      # 05 MINSCALEDENOM 
      # 06 MINSCALEDENOM 
      # 07 MINSCALEDENOM 1451339
      # 08 MINSCALEDENOM 725669
      # 09 MINSCALEDENOM 362834
      # 10 MINSCALEDENOM 181417
      # 11 MINSCALEDENOM 90708
      # 12 MINSCALEDENOM 45354
      # 13 MINSCALEDENOM 22677
      # 14 MINSCALEDENOM 11338
      # 15 MINSCALEDENOM 5669    ...
      # 16 MINSCALEDENOM 2834    etc.
      # 17 MINSCALEDENOM 1417    1417 +/- 354 = 1063 -> 1771
      # 18 MINSCALEDENOM 708      708 +/- 177 =  531 -> 885
      # 19 MINSCALEDENOM 354      354 +/-  88 =  266 -> 442
      one_quarter_denom = int(exactish_scale_denom / 4.0)
      scale_denominator_int_0 = int(exactish_scale_denom) - one_quarter_denom
      scale_denominator_int_1 = int(exactish_scale_denom) + one_quarter_denom

      args = {
         'zoom_level': zoom_level,
         'scale': scale,
         'resolution': round(Make_Mapfile.dpi_in_meters, 2),
         'exactish_scale_denom': round(exactish_scale_denom, 2),
         'scale_denominator_int_0': scale_denominator_int_0,
         'scale_denominator_int_1': scale_denominator_int_1,
         }

      # "MAXSCALEDENOM [double] Minimum scale at which this CLASS is drawn.
      #  Scale is given as the denominator of the actual scale fraction, for
      #  example for a map at a scale of 1:24,000 use 24000. Implemented in
      #  MapServer 5.0, to replace the deprecated MAXSCALE parameter."
      #  http://geography.about.com/cs/maps/a/mapscale.htm

      scale_denominator = (
"""# * scale       = %(scale)d meters/pixel
      # * resolution  = ~%(resolution)s pixels per meter at 72 DPI
      # * scale * res = ~%(exactish_scale_denom)s
      MINSCALEDENOM %(scale_denominator_int_0)d
      MAXSCALEDENOM %(scale_denominator_int_1)d\
""") % args

      return scale_denominator

   # ***

   #
   def get_layer_segments_common(self, args):

      # CAVEAT: MapServer complains if the LAYER NAME has dashes in it?

      layer_segments_common = (
"""
      METADATA
         "wms_title" "byways"
      END

      NAME "byways-zoom_%(zoom_level)d-zlvl_%(z_levels_name)s-gfl_%(gfl_id)d-%(em)s"

      GROUP "standard"

      STATUS ON

      TYPE LINE

      # Include the db login credentials.
include(database.map)
      # Include the zoom_level scale.
      %(scale_denominator)s\
""") % args

      return layer_segments_common

   #
   def get_layer_clusters_common(self, args):

      layer_clusters_common = (
"""
      METADATA
         "wms_title" "labels"
      END

      NAME "labels__zoom_%(zoom_level)d__zlvl_%(z_levels_name)s__gfl_%(gfl_id)d__%(em)s"

      GROUP "standard"

      STATUS ON

      TYPE LINE

      # Include the login credentials.
include(database.map)

      # Include the zoom_level scale.
      %(scale_denominator)s

      LABELITEM "cluster_name"\
""") % args

      return layer_clusters_common

   #
   def get_layer_params_segment(self, args):

      # SELECT ...
      #         --, segment.geometry
      # JOIN ...
      #      --JOIN item_versioned AS gf_iv
      #      --   ON (gf.system_id = gf_iv.system_id)
      # WHERE ...
      #         --AND (segment.geofeature_layer_id = %(gfl_id)d)

      # NOTE: Don't use spaces after DATA " before the geometry column name.

      layer_segment = (
"""   %(layer_params_common)s

      # Tell MapServer how to find the geometry.
      # Also restrict the results for this specific layer
      #  (using: skin, do_draw, z_level, zoom_level, and geofeature_layer).

      DATA "geometry FROM (

         SELECT
            stack_id
            , bike_facility_or_caution
            , travel_restricted
            , geometry
            , geofeature_layer_id
            , skin_name
            , pen_color_s
            , pen_width
            , pen_gutter
            , shadow_width
            , shadow_color_s

         FROM (

            SELECT
               segment.stack_id
               , segment.bike_facility_or_caution
               , segment.travel_restricted
               , cluster.geometry AS cluster_geom
               , gf.geometry
               , gf.geofeature_layer_id
               , skin.skin_name
               , skin.pen_color_s
               , skin.pen_width
               , skin.pen_gutter
               , skin.shadow_width
               , skin.shadow_color_s
               , skin.d_geom_len AS min_geom_len
               , skin.d_geom_area AS min_geom_area

            FROM %%schema%%.tiles_cache_byway_segment AS segment

            JOIN %%schema%%.tiles_cache_clustered_byways AS clust_link
               ON ((segment.stack_id = clust_link.byway_stack_id)
               AND (segment.branch_id = clust_link.byway_branch_id))

            JOIN %%schema%%.tiles_cache_byway_cluster AS cluster
               ON (clust_link.cluster_id = cluster.cluster_id)

            JOIN %%schema%%.geofeature AS gf
               ON (segment.system_id = gf.system_id)

            JOIN public.tiles_mapserver_zoom AS skin
               ON (skin.geofeature_layer_id = segment.geofeature_layer_id)

            WHERE
               (skin.skin_name = '%%layer_skin%%')
               AND (skin.do_draw IS TRUE)
               AND (skin.zoom_level = %(zoom_level)d)
               AND (segment.z_level IN (%(z_levels)s))
               AND (gf.geofeature_layer_id = %(gfl_id)d)
               %(select_where)s

         ) AS foo

         WHERE
               (ST_Length(cluster_geom) >= min_geom_len)
           AND (ST_Area(ST_Box2D(cluster_geom)) >= min_geom_area)

      ) AS segment USING UNIQUE stack_id USING SRID=%(srid)d"
""") % args
      # FIXME: Is stack_id ever not unique?
      #        I.e., "AS segment USING UNIQUE stack_id"

      return layer_segment

   #
   def get_layer_params_cluster(self, args):

      # NOTE: Don't use spaces after DATA " before the geometry column name.

      # HACKNNOUNCEMENT! l_restrict_stack_ids is used at the upper zoom levels
      # to pick 'n' choose bike trails to show (along with min length and min
      # area) and we also do a silly solid and strip the strings ' Trail' or 
      # ' State Trail' off the end of the names, so that, e.g.,
      # 'Luce Line Trail' doesn't overlap 'Gateway Trail', especially since
      # the lines are often _shorter_ than the text, so the labels often
      # finish on funny angles (and the label text is drawn past the end of
      # the line segment, incorrectly implying the line segment goes that far).

      # BUG nnnn/EXPLAIN/FIND_AND_FIX_SOURCE_OF_PROBLEM: Haha: 'NONE'!?
      #  Like, literally, Python None converted to 'NONE'. Tee-hee.
      #
      #  SELECT DISTINCT(winningest_bike_facil) FROM tiles_cache_byway_cluster;
      #  winningest_bike_facil 
      # -----------------------
      #  NONE
      #  shld_hivol
      #  hway_lovol
      #  shld_lovol
      #  bike_lane
      #  rdway_shrrws
      #  paved_trail
      #  hway_hivol

      try:
         args['m_per_char'] = Tile_Pen.zoom_level_meters_per_label_char[
                                                      args['zoom_level']]
      except KeyError:
         args['m_per_char'] = 0
      # HRM: Maybe 'MINFEATURESIZE auto' will work better than this...
      # NO: 'MINFEATURESIZE auto' doesn't work too well: args['m_per_char'] = 0

      # MAGIC_NUMBERS: To show labels at higher zoom levels of important trails
      # that have long names that would otherwise be excluded, we strip some
      # words. E.g.s,
      #  Midtown Greenway -> Greenway
      #  Lake Minnetonka LRT Regional Trail -> Lake Minnetonka LRT
      #  Luce Line Trail -> Luce Line
      args['hacky_strreduce'] = '((^Midtown )|(Regional )?(State )?Trail$)'

      layer_cluster = (
"""   %(layer_params_common)s

      DATA "geometry FROM (

         SELECT
            DISTINCT ON (cluster_id) cluster_id
            , cluster_name
            , geometry
            , is_cycle_route
            , skin_name
            , label_priority
            , label_size
            , label_color_s
            , labelo_color_s
            , label_fontface

         FROM (

            SELECT
               cluster.cluster_id
               , CASE WHEN ((skin.l_restrict_stack_ids != '')
                            OR (skin.l_strip_trail_suffix))
                  THEN regexp_replace(cluster.cluster_name,
                                      '%(hacky_strreduce)s',
                                      '')
                  ELSE cluster.cluster_name
                     END AS cluster_name
               , cluster.geometry
               , cluster.is_cycle_route
               , skin.skin_name
               , CASE WHEN (skin.p_new = 0)
                  THEN cluster.label_priority
                  ELSE skin.p_new
                     END AS label_priority
               , skin.p_min
               , skin.label_size
               , skin.label_color_s
               , skin.labelo_color_s
               , CASE WHEN (NOT skin.l_bold)
                   THEN 'libsansreg'
                   ELSE 'libsansbold'
                     END AS label_fontface
               , skin.l_geom_len AS min_geom_len
               , skin.l_geom_area AS min_geom_area
               , skin.l_restrict_stack_ids

            FROM %%schema%%.tiles_cache_byway_cluster AS cluster

            JOIN %%schema%%.tiles_cache_clustered_byways AS clust_link
              ON ((cluster.cluster_id = clust_link.cluster_id)
              AND (cluster.branch_id = clust_link.byway_branch_id))

            JOIN public.tiles_mapserver_zoom AS skin
               ON (skin.geofeature_layer_id = cluster.winningest_gfl_id)

            WHERE
                  (skin.skin_name = '%%layer_skin%%')
              AND (skin.%(skin_do_op)s IS TRUE)
              AND (skin.zoom_level = %(zoom_level)d)
              AND (cluster.winningest_gfl_id = %(gfl_id)d)
              AND ((NOT skin.l_only_bike_facils)
                   OR (cluster.winningest_bike_facil IN (
                       --'no_facils'
                         'paved_trail'
                       --, 'loose_trail'
                       , 'protect_ln'
                       , 'bike_lane'
                       , 'rdway_shrrws'
                       , 'bike_blvd'
                       --, 'rdway_shared'
                       , 'shld_lovol'
                       , 'shld_hivol'
                       --, 'hway_hivol'
                       --, 'hway_lovol'
                       --, 'gravel_road'
                       , 'bk_rte_u_s'
                       , 'bkway_state'
                       ----, 'major_street'
                       --, 'facil_vary'
                       -- Skipping: cautionaries:
                       --  no_cautys, constr_open, constr_closed,
                       --  poor_visib, facil_vary
                       )))
              AND ((skin.l_restrict_named = '')
                   OR (EXISTS(SELECT
                     regexp_matches(cluster.cluster_name,
                     skin.l_restrict_named))
                   ))
              AND ((skin.l_restrict_stack_ids = '')
                  OR (EXISTS(SELECT
                    regexp_matches(clust_link.byway_stack_id::TEXT,
                                   skin.l_restrict_stack_ids))
                  ))
              %(select_where)s
         ) AS foo

         WHERE
               (label_priority >= p_min)
           AND (ST_Length(geometry) >= min_geom_len)
           AND (ST_Area(ST_Box2D(geometry)) >= min_geom_area)
           AND ((l_restrict_stack_ids != '')
                OR (%(m_per_char)d = 0)
                OR ((ST_Length(geometry)::INTEGER
                     > (CHAR_LENGTH(cluster_name) * %(m_per_char)d))
                    ))

       ) AS cluster USING UNIQUE cluster_id USING SRID=%(srid)d"
""") % args
      # FIXME: Is cluster_id ever not unique?
      #        I.e., "AS cluster USING UNIQUE cluster_id"

      return layer_cluster

   # ***

   #
   def add_layer_geofeature(self, args):

      # In the CLASS definition, from tiles_mapserver_zoom:
      # Using: do_draw, pen_color_s, pen_width, pen_gutter
      #        shadow_width, shadow_color_s
      # Not used: pen_color_i (int of pen_color_s)
      # Not used?: do_shadow
      # Not used: shadow_color_i (int of shadow_color_s)
      # Skipping: do_label, label_size, label_color_s, label_color_i
      #                     labelo_width, labelo_color_s, labelo_color_i

      # MapServer BUGBUG: Don't split the F-R-O-M and the table name (in the
      #                   DATA section): MapServer has a simple parser and
      #                   cannot follow newlines, and it uses the table name to
      #                   ask PostGIS what the SRID of the geometry column is.

      # Skipping: FILTER. The filter is just the WHERE clause that MapServer
      # uses when it executes the SQL specified by DATA. This is useful if you
      # INCLUDE a sub-mapfile that has DATA in it, so you can use the same
      # sub-mapfile for multiple layers. But we're customizing the DATA, so
      # skip it.
      # No:
      #  # Tell MapServer to add this to the WHERE clause.
      #  FILTER "(zoom_level = %(zoom_level)d)
      #          AND (geofeature_layer_id = %(gfl_id)d)
      #          AND (do_draw IS TRUE)"

      # NOTE: %layer_skin% is passed via the URL. MapServer maps key=value
      #       pairs from the query_string...

      args['em'] = 'line_seg'
      args['layer_params_common'] = self.get_layer_segments_common(args)
      args['select_where'] = ""
      args['layer_prefix'] = self.get_layer_params_segment(args)

      # NO: (MapServer 5.x):
      #  EXPRESSION (("[do_draw_41]" =~ /t/) AND ([geofeature_layer_id_] = 41))
      # NO: (MapServer 6.x):
      #  EXPRESSION (("[do_draw_41]" =~ 't') AND ([geofeature_layer_id_] = 41))
      layer_text = (
"""
   LAYER
      %(layer_prefix)s
      CLASS
         NAME 'Byways for GFL ID %(gfl_id)d'
         STYLE
            WIDTH [shadow_width]
            COLOR [shadow_color_s]
         END
         STYLE
            COLOR [pen_color_s]
            WIDTH [pen_width]
         END
# 2013.05.07: [lb] removes this but cannot remember why... though
#                  it really looks wrong: gutter should come before
#                  shadow and regular pen.
#         STYLE
#            COLOR [shadow_color_s]
#            WIDTH [pen_gutter]
#         END
      END
   END
""") % args

      self.map_f.write(layer_text)

   #
   def add_layer_bike_facility(self, attr_pen_key, args):

# Does this still make sense? Probably not. [lb] guesses that the facil trumps
# the gfl layer id (to verify, check layer ordering in mapfile).

      # Skipping: "[bike_facility_or_caution]" = "paved_trail")
      #           since it is its own byway (and has a GFL ID).

      facil_classes = []

      for skin_name in Tile_Skin.get_skins_list():

         log.verbose(
            'add_layer_bike_facil: skin_name: %s / attr_pen_key: %s'
            % (skin_name, attr_pen_key,))

         args['skin_name'] = skin_name

         # Load the dynamic skin module.
         module_path = ('skins.skin_%s' % (skin_name,))
         skin_module = Mod_Loader.load_package_module(module_path)
         tile_skin = skin_module.get_skin()
         g.assurt(tile_skin is not None)

         # Load the tile pen (defined for each gfl_id and zoom_level).
         tile_pen = tile_skin.tile_pens[args['gfl_id']][args['zoom_level']]

         log.debug('add_lyr_bk_facil: do_draw: %5s / gfl_id: %02d / zoom: %02d'
                   % (tile_pen.do_draw, args['gfl_id'], args['zoom_level'],))
         if not tile_pen.do_draw:
            continue

         # Load the Attr_Pen for the bike_facil pens.
         # 'bike_facil'
         facil_pens = tile_skin.attr_pens[attr_pen_key]

         # The dict is keyed by each pen's attr_key, so just itervalues.
         for attr_pen in facil_pens.itervalues():



# FIXME: for each pen, make a set() of zooms?
#        like, changing width and gutter based on zoom?
#        or not drawing a facil 'til a certain zoom, since zooms right now
#          just go off gfl_id but not attr_pen...
#        args['zoom_level']


            log.verbose(' .. trav. attr_pen: attr_key: %s'
                        % (attr_pen.attr_key,))

            facil_styles = []

            g.assurt(not 'pen_gutter' in args)
            args['pen_gutter'] = float(tile_pen.pen_gutter)
            g.assurt(not 'pen_width' in args)
            args['pen_width'] = float(tile_pen.pen_width)

            g.assurt(not 'attr_key' in args)
            args['attr_key'] = attr_pen.attr_key
            g.assurt(not 'key_friendly' in args)
            args['key_friendly'] = attr_pen.key_friendly
            g.assurt(not 'dashon_color' in args)
            args['dashon_color'] = attr_pen.dashon_color

            # We might add dashes and gutters, so add a background line.
            # The background line won't be visible if there are no dashes and
            # no gutters.
            g.assurt(not 'nodash_color' in args)
            if attr_pen.nodash_color:
               # NOTE: The get_style_bike_facility expects dashon_color.
               args['dashon_color'] = attr_pen.nodash_color
            else:
               # Default to white.
               args['dashon_color'] = '255 255 255'
            style_text = self.get_style_bike_facility(args)
            # Restore args' dashon_color.
            args['dashon_color'] = attr_pen.dashon_color

            # Add the background line.
            facil_styles.append(style_text)

            # Maybe do dashing.
            g.assurt(not ((attr_pen.interval_square)
                          and ((attr_pen.dashon_interval)
                               or (attr_pen.nodash_interval))))
            # From MapServer-6.0.1.pdf:
            # PATTERN [double on] [double off] [double on] [double off] ... END
            dashed_parms = ''
            if attr_pen.interval_square:
               dashed_parms = ("""
            LINECAP BUTT
            PATTERN %s %s END"""
                  % (float(tile_pen.pen_width),
                     float(tile_pen.pen_width),))
            if attr_pen.dashon_interval:
               g.assurt(attr_pen.nodash_interval)
               dashed_parms = ("""
            LINECAP BUTT
            PATTERN %s %s END"""
                  % (float(attr_pen.dashon_interval),
                     float(attr_pen.nodash_interval),))
            if dashed_parms:
               # Add the dashed, foreground line.
               style_text = self.get_style_bike_facility(args, dashed_parms)

               facil_styles.append(style_text)

            # Add the dashon_color line.

            # But first, if there's gutter, make sure to leave a little of the
            # background line showing.
            # 
            gut_width = attr_pen.gut_width
            if args['zoom_level'] < attr_pen.guts_ok_at_zoom:
               gut_width = 0

            # SYNC_ME: gut_width reduction: mapserver/make_mapfile.py
            #                               flashclient/items/feats/Byway.as
            if gut_width > 0:
               if gut_width > 3:
                  args['pen_width'] -= 4.0
               elif gut_width > 1:
                  args['pen_width'] -= 2.0
               # MAGIC_NUMBERS: There are two bumpers on either side of two
               #                one-pixel gutters.
               one_pixel_gutter = 2.0
               #gutt_width = args['pen_width'] + (2.0 * one_pixel_gutter)
               #rail_width = gutt_width + (2.0 * args['gut_width'])
               #full_width = rail_width + (2.0 * one_pixel_gutter)

               # The offset is half of the centerline, plus the gutter
               # separator width, plus half of the gutter.
               offset_pixels = ((args['pen_width'] / 2.0)
                                + one_pixel_gutter
                                + (gut_width / 2.0))

            # This is the centerline.
            style_text = self.get_style_bike_facility(args)
            facil_styles.append(style_text)

            # Add the gutter lines, if requested.
            if gut_width > 0:

               # Not used: no_gut_color...

               args['pen_width'] = gut_width

               if attr_pen.gut_on_color:
                  # Remember that get_style_bike_facility expects dashon_color.
                  args['dashon_color'] = attr_pen.gut_on_color

               # From MapServer-6.0.1.pdf:
               # 
               # For lines, an OFFSET of n -99 will produce a line geometry
               # that is shifted n SIZEUNITS perpendicular to the original line
               # geometry. A positive n shifts the line to the right when seen
               # along the direction of the line. A negative n shifts the line
               # to the left when seen along the direction of the line.

               gutter_parms = ("""
            LINECAP BUTT
            PATTERN %s %s END
            OFFSET %d -99"""
                     % (float(attr_pen.gut_on_interval),
                        float(attr_pen.no_gut_interval),
                        offset_pixels,))

               style_text = self.get_style_bike_facility(args, gutter_parms)
               facil_styles.append(style_text)

               gutter_parms = ("""
            LINECAP BUTT
            PATTERN %s %s END
            OFFSET -%d -99"""
                     % (float(attr_pen.gut_on_interval),
                        float(attr_pen.no_gut_interval),
                        offset_pixels,))

               style_text = self.get_style_bike_facility(args, gutter_parms)
               facil_styles.append(style_text)

            # end: if gut_width

            facil_class = self.get_class_bike_facility(args, facil_styles)
            facil_classes.append(facil_class)

            del args['pen_gutter']
            del args['pen_width']
            del args['attr_key']
            del args['key_friendly']
            del args['dashon_color']

            # end: for attr_pen in facil_pens.itervalues()

         del args['skin_name']

         # end: for skin_name in Tile_Skin.get_skins_list()

      args['em'] = attr_pen_key # 'bike_facil' or 'cautionary'
      args['layer_params_common'] = self.get_layer_segments_common(args)
      args['select_where'] = (
         """AND (segment.bike_facility_or_caution IS NOT NULL)
            AND (segment.bike_facility_or_caution != '')
         """)
      args['layer_prefix'] = self.get_layer_params_segment(args)
      args['facil_classes'] = ''.join(facil_classes)

      layer_text = (
"""
   LAYER
      %(layer_prefix)s
      %(facil_classes)s
   END
""") % args

      self.map_f.write(layer_text)

   #
   def get_class_bike_facility(self, args, facil_styles):

      g.assurt(not 'facil_styles' in args)
      args['facil_styles'] = ''.join(facil_styles)

      class_text = (
"""
      CLASS
         NAME 'Bike Facil: %(skin_name)s / %(key_friendly)s / %(gfl_id)d'
         EXPRESSION ("[skin_name]" = "%(skin_name)s" AND "[bike_facility_or_caution]" = "%(attr_key)s")
         %(facil_styles)s
      END""") % args

      del args['facil_styles']

      return class_text

   #
   def get_style_bike_facility(self, args, extra_parms=''):

      g.assurt(not 'extra_parms' in args)
      args['extra_parms'] = extra_parms

      style_text = (
"""
         STYLE
            COLOR %(dashon_color)s
            WIDTH %(pen_width)s%(extra_parms)s
         END""") % args

      del args['extra_parms']

      return style_text

   #
   def add_layer_cycle_route(self, args):

      args['em'] = 'cycle_route'
      args['layer_params_common'] = self.get_layer_segments_common(args)
      args['select_where'] = "AND (cluster.is_cycle_route IS TRUE)"
      args['skin_do_op'] = 'do_draw'
      args['layer_prefix'] = self.get_layer_params_cluster(args)

# FIXME: Fiddle with STYLE...
         ##COLOR 136 103 3
         ##WIDTH [width]
         #COLOR 188 0 0
         #WIDTH 1
# FIXME: Get the STYLEs from the skin file.
      layer_text = (
"""
   LAYER
      %(layer_prefix)s
      CLASS
         NAME 'Byway Clusters / Cycle Routes'
         STYLE
            WIDTH 2
            COLOR 0 180 255
         END
      END
   END
""") % args

      self.map_f.write(layer_text)

   #
# FIXME/BUG nnnn: Add restricted/closed to skin_file (single pixel red line).
   def add_layer_restricted(self, args):

      args['em'] = 'travel_restriction'
      args['layer_params_common'] = self.get_layer_segments_common(args)
      args['select_where'] = "AND (segment.travel_restricted IS TRUE)"
      args['layer_prefix'] = self.get_layer_params_segment(args)

# FIXME: Get the STYLEs from the skin file.
#        And find better colors/design.

# FIXME: This is really ugly at zoom 9.
#        Also, the width 3 is maybe a gray line with end cap that overlaps
#         funny with intersecting lines of different z-level...
      layer_text = (
"""
   LAYER
      %(layer_prefix)s
      CLASS
         NAME 'Byway Travel Restrictions'
#         STYLE
#            WIDTH 3
#            COLOR 206 178 159
#         END
         STYLE
            WIDTH 1
#            COLOR 249 82 74
            COLOR 188 9 0
         END
      END
   END
""") % args

      self.map_f.write(layer_text)

   #
   def add_layer_labels(self, args):

      args['em'] = 'resegmented_labels'
      args['layer_params_common'] = self.get_layer_clusters_common(args)
      args['select_where'] = ""
      args['skin_do_op'] = 'do_label'

      args['layer_prefix'] = self.get_layer_params_cluster(args)

      for skin_name in Tile_Skin.get_skins_list():

         args['skin_name'] = skin_name

         # Load the dynamic skin module.
         module_path = ('skins.skin_%s' % (skin_name,))
         skin_module = Mod_Loader.load_package_module(module_path)
         tile_skin = skin_module.get_skin()
         g.assurt(tile_skin is not None)

         # Load the tile pen (defined for each gfl_id and zoom_level).
         tile_pen = tile_skin.tile_pens[args['gfl_id']][args['zoom_level']]

         if not tile_pen.do_label:
            continue

         args['label_force'] = tile_pen.l_force
         args['label_partials'] = tile_pen.l_partials
         args['label_outlinewidth'] = tile_pen.l_outlinewidth
         args['label_minfeaturesize'] = tile_pen.l_minfeaturesize

         # NOTE: With or without 'POSITION auto' doesn't seem to matter.

         layer_text = (
"""
   LAYER
      %(layer_prefix)s
      CLASS
         NAME 'Byway Segment and Cluster Label: %(skin_name)s'
         EXPRESSION ("[skin_name]" = "%(skin_name)s")
         LABEL
            ANGLE follow
            BUFFER 1
            COLOR [label_color_s]
            FONT [label_fontface]
            MINDISTANCE 9
            MINFEATURESIZE %(label_minfeaturesize)s
            MINSIZE 8
            OUTLINECOLOR [labelo_color_s]
            OUTLINEWIDTH %(label_outlinewidth)d
            FORCE %(label_force)s
            PARTIALS %(label_partials)s
            POSITION auto
            PRIORITY [label_priority]
            #REPEATDISTANCE 7
            SIZE [label_size]
            TYPE truetype
         END
      END
   END
""") % args

         self.map_f.write(layer_text)

         del args['label_minfeaturesize']
         del args['label_outlinewidth']
         del args['label_partials']
         del args['label_force']
         del args['skin_name']

         # end: for skin_name in Tile_Skin.get_skins_list()

# ***

if (__name__ == '__main__'):
   mm = Make_Mapfile()
   mm.go()


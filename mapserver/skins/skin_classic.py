# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

# DEVS: See skin_bikeways.py; this file just makes an artsy-fartsy zoom 6
#       of the State of Minnesota.

# SYNC_ME: Search: Scripts: Load pyserver.
import os
import sys

import conf
import g

from item.feat import branch
from item.feat import byway
from item.feat import region
from item.feat import route
from item.feat import terrain
from item.feat import track
from item.feat import waypoint

import skin_bikeways
from tile_skin import Attr_Pen
from tile_skin import Feat_Pen
from tile_skin import Tile_Pen
from tile_skin import Tile_Skin

log = g.log.getLogger('skin_classic')

#
def get_skin():

   skin_classic = skin_bikeways.get_skin()

   # Steal/Use the bikeways skin's attr pens.
   skin_bikeways.assign_attr_pens(skin_classic)

   # Also mimic the bikeways skin's feat pens.
   skin_bikeways.assign_feat_pens(skin_classic)

   # And also the tile pens...
   skin_bikeways.assign_tile_pens(skin_classic)
   # ... but then overwrite the zoom 6 pens.
   re_assign_some_tile_pens(skin_classic)

   return skin_classic

#
def re_assign_some_tile_pens(skin_classic):

   # *** Zoom: 6.

   skin_classic.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=3, pen_gutter=0,
         do_label=True, label_size=8, l_bold=False, p_min=0, p_new=9,
         l_partials=True, l_force=True))
   #
   skin_classic.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=2, pen_gutter=0,
         do_label=True, label_size=8, l_bold=False, p_min=0, p_new=8,
         l_partials=True, l_force=True))
   #
   skin_classic.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8, l_bold=False, p_min=0, p_new=7,
         l_partials=True, l_force=True))
   #
   skin_classic.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=2, pen_gutter=0,
         do_label=True, label_size=8, l_bold=False, p_min=0, p_new=10,
         l_partials=True, l_force=True))
   #
   skin_classic.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8, l_bold=False, p_min=0, p_new=9,
         l_partials=True, l_force=True,))
   #
   skin_classic.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8, l_bold=False, p_min=0, p_new=6,
         l_partials=True, l_force=True))

# ***

if (__name__ == '__main__'):
   pass


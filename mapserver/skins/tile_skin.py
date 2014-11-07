# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

import os
import re
import sys

import conf
import g

from item.feat import byway
from item.feat import region
from item.feat import terrain
from item.feat import waypoint
from util_ import misc

# ***

#
class Attr_Pen(object):

   __slots__ = (
      'attr_name',
      'attr_key',
      'key_friendly',
      'icon_class',
      'attr_data',
      'key_rank',
      'dashon_color',
      'nodash_color',
      'dashon_interval',
      'nodash_interval',
      'interval_square',
      'guts_ok_at_zoom',
      'gut_width',
      'gut_on_color',
      'no_gut_color',
      'gut_on_interval',
      'no_gut_interval',
      )

   #
   def __init__(self,
                attr_name,
                attr_key,
                key_friendly,
                icon_class,
                attr_data=None,
                key_rank=None,
                dashon_color='',
                nodash_color='',
                dashon_interval=0,
                nodash_interval=0,
                interval_square=False,
                guts_ok_at_zoom=0,
                gut_width=0,
                gut_on_color='',
                no_gut_color='',
                gut_on_interval=0,
                no_gut_interval=0):
      self.attr_name = attr_name
      self.attr_key = attr_key
      self.key_friendly = key_friendly
      self.icon_class = icon_class
      self.attr_data = attr_data
      self.key_rank = key_rank
      self.dashon_color = dashon_color
      self.nodash_color = nodash_color
      self.dashon_interval = float(dashon_interval)
      self.nodash_interval = float(nodash_interval)
      self.interval_square = interval_square
      self.guts_ok_at_zoom = guts_ok_at_zoom
      self.gut_width = float(gut_width)
      self.gut_on_color = gut_on_color
      self.no_gut_color = no_gut_color
      self.gut_on_interval = float(gut_on_interval)
      self.no_gut_interval = float(no_gut_interval)

   #
   def __str__(self):
      self_str = ','.join([str(getattr(self, x)) for x in Attr_Pen.__slots__])
      return self_str

# ***

#
class Feat_Pen(object):

   #
   def __init__(self,
                restrict_usage,
                friendly_name,
                pen_color,       # e.g., '163 166 189'
                shadow_width,    # e.g., 2
                shadow_color,    # e.g., '255 255 255'
                label_color,     # e.g., '0 0 0'
                labelo_width,    # e.g., 3
                labelo_color):   # e.g., '163 166 189'
      self.restrict_usage = restrict_usage
      self.friendly_name = friendly_name
      self.pen_color = pen_color
      # MAYBE: Should shadow_width and labelo_width be part of Tile_Pen?
      self.shadow_width = float(shadow_width)
      self.shadow_color = shadow_color
      self.label_color = label_color
      self.labelo_width = float(labelo_width)
      self.labelo_color = labelo_color

# ***

#
class Tile_Pen(object):

   # When choosing labels to draw, it looks super silly to draw a label when
   # the text is longer than the geometry (on the screen, i.e., geometry length
   # in pixels, not in meters). For some zoom levels, we choose which
   # geometries and labels to draw based on line segment length and area. But
   # for other zoom levels, it's easier to decide what to draw based on whether
   # or not we can figure out if the label will just be a straight label (and
   # not one that follows a curved line segment) because the line segment is so
   # short, or if we can figure out that the label, when drawn, will nicely
   # follow and represent the actual line geometry. And one might think there'd
   # be a MapServer option to tell it not to draw labels unless they fit over
   # the whole path of the line segment, but [lb] cannot find one... so, take a
   # ruler, stick it to your monitor, and figure out how many of the widest
   # characters (like 'a', and not 'i', in non-fixed width font) can be drawn
   # per meter of actual line segment geometry.
   zoom_level_meters_per_label_char = {
      #5: ,
      #6: ,
      7: 1000,
      #7: 2668,
      8: 1334,
      # Zoom 9 was measured by [lb] with a caliper (real life caliper pressed
      # against monitor) using "Stillwater Blvd N / State Hwy 5" as an example,
      # except maybe the 'i' and the 'l's make this too wide (in which case try
      # 1 char per 1km, rather than 2/3 km per char).
      #9: 670, # 670 meters, of 2/3 km at zoom 9.
      #9: 500,
#      9: 400,
      10: 250,
      11: 125,
      12: 75,
      13: 0,
      14: 0,
      15: 0,
      16: 0,
      #17: ,
      #18: ,
      #19: ,
      }

   #
   def __init__(self,
                zoom_level,
                do_draw,
                pen_width=1,
                pen_gutter=0,
                do_label=False,
                label_size=8,
                l_bold=False,
                l_force=False,
                l_partials=False,
                # MAGIC_NUMBER: MapServer docs recomment outline widths
                #               of 3 or 5 pixels, or none.
                l_outlinewidth=3,

                # MAYBE/TRY_IT_OUT: Make the default 'auto'.
                l_minfeaturesize='1',

                l_restrict_named='',
                l_restrict_stack_ids='',
                l_strip_trail_suffix=False,
                l_only_bike_facils=False,
                p_min=1,
                p_new=0,
                d_geom_len=0,
                d_geom_area=0,
                l_geom_len=0,
                l_geom_area=0,
                ):
      self.zoom_level = zoom_level
      self.do_draw = do_draw
      self.pen_width = float(pen_width)
      self.pen_gutter = float(pen_gutter)
      self.do_label = do_label
      self.label_size = label_size
      self.l_bold = l_bold
      self.l_force = l_force
      self.l_partials = l_partials
      self.l_outlinewidth = l_outlinewidth
      self.l_minfeaturesize = l_minfeaturesize
      self.l_restrict_named = l_restrict_named
      self.l_restrict_stack_ids = l_restrict_stack_ids
      self.l_strip_trail_suffix = l_strip_trail_suffix
      self.l_only_bike_facils = l_only_bike_facils
      self.p_min = p_min
      self.p_new = p_new
      self.d_geom_len = d_geom_len
      self.d_geom_area = d_geom_area
      self.l_geom_len = l_geom_len
      self.l_geom_area = l_geom_area

# ***

#
class Tile_Skin(object):

   # FIXME/BUG nnnn: These are all grouped together for now, but
   #                 it'd be nice to draw each of these uniquely.
   gfl_local_road_et_al = [
      byway.Geofeature_Layer.Byway_Alley,
      byway.Geofeature_Layer.Local_Road,
      byway.Geofeature_Layer.Unknown,
      byway.Geofeature_Layer.Other,
      byway.Geofeature_Layer._4WD_Road,
      byway.Geofeature_Layer.Sidewalk,
      byway.Geofeature_Layer.Doubletrack,
      byway.Geofeature_Layer.Singletrack,
      byway.Geofeature_Layer.Expressway_Ramp,
      byway.Geofeature_Layer.Private_Road,
      byway.Geofeature_Layer.Other_Ramp,
      byway.Geofeature_Layer.Parking_Lot,
      ]

   # 2013.09.03: Make it easy to compile a list of the skins
   #             (e.g., to use the names to import Python modules).
   skins_list = None

   #
   def __init__(self):
      self.attr_pens = {}
      self.feat_pens = {}
      self.tile_pens = {}
      # CAVEAT: You need to define pens for each GFL and zooms for each GFL and
      #         zoom level. If you don't, you'll get a KeyError eventually.
      self.gfls_deffed = set()
      self.zooms_deffed = set()
      #
      # This is to make sure the DEVs order their pens with explicit key_ranks
      # after all inexplicit pens.
      self.on_explicit_key_ranks = False

   #
   def assign_attr_pen(self, attr_pen):
      g.assurt(attr_pen.attr_name and attr_pen.attr_key)
      if attr_pen.key_rank is None:
         g.assurt(not self.on_explicit_key_ranks)
         try:
            key_rank = len(self.attr_pens[attr_pen.attr_name])
         except KeyError:
            key_rank = 0
         attr_pen.key_rank = key_rank
      else:
         # The pen specifies its own key_rank. These should always come last!
         self.on_explicit_key_ranks = True
      g.assurt(attr_pen.key_rank is not None)
      misc.dict_dict_update(
         self.attr_pens,
         attr_pen.attr_name,
         attr_pen.attr_key,
         attr_pen)

   #
   def assign_feat_pen(self, gfl_id_or_ids, feat_pen):
      try:
         # See if it's a collection.
         for gfl_id in gfl_id_or_ids:
            self.feat_pens[gfl_id] = feat_pen
            self.gfls_deffed.add(gfl_id)
      except TypeError, e:
         # Nope, not a collection, so assume int.
         gfl_id = int(gfl_id_or_ids)
         self.feat_pens[gfl_id] = feat_pen
         self.gfls_deffed.add(gfl_id)

   #
   def assign_tile_pen(self, gfl_id_or_ids, tile_pen):
      try:
         # See if it's a collection.
         for gfl_id in gfl_id_or_ids:
            self.tile_pens.setdefault(gfl_id, {})
            self.tile_pens[gfl_id][tile_pen.zoom_level] = tile_pen
      except TypeError, e:
         # Nope, not a collection, so assume int.
         gfl_id = int(gfl_id_or_ids)
         self.tile_pens.setdefault(gfl_id, {})
         self.tile_pens[gfl_id][tile_pen.zoom_level] = tile_pen
      self.zooms_deffed.add(tile_pen.zoom_level)

   # ***

   re_skin_name = re.compile(r"^skin_([a-zA-Z0-9_]+)\.py$")

   #
   @staticmethod
   def get_skins_list():

      if Tile_Skin.skins_list is None:
         # MAGIC_NUMBER/MAGIC_PATH: All of our scripts import pyserver_glue, so
         # we can always assume the curdir is pyserver/. The skins are in the
         # mapserver directory.
         Tile_Skin.skins_list = []
         for dirpath, dirnames, filenames in os.walk('../mapserver/skins'):
            #log.verbose(' >> dirpath: %s' % dirpath) # ../mapserver/skins
            #log.verbose(' >> dirnames: %s' % dirnames) # []
            #log.verbose(' >> filenames: %s' % filenames) # [{files}]
            for fname in filenames:
               # MAGIC_NUMBER: See mapserver/skins/skin_*.py: All skin files
               #               follow this format.
               #if fname.startswith('skin_') and fname.endswith('.py'):
               grps = Tile_Skin.re_skin_name.match(fname)
               if grps is not None:
                  skin_name = grps.group(1)
                  Tile_Skin.skins_list.append(skin_name)

      return Tile_Skin.skins_list

# ***

if (__name__ == '__main__'):
   pass


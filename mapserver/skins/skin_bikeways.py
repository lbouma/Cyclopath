# Copyright (c) 2006-2013 Regents of the University of Minnesota.
# For licensing terms, see the file LICENSE.

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
from tile_skin import Attr_Pen
from tile_skin import Feat_Pen
from tile_skin import Tile_Pen
from tile_skin import Tile_Skin

log = g.log.getLogger('skin_bikeways')

# NOTE: MapServer is picky about formatting. No leading whitespace in color
#       strings.

# NOTE: MapServer does not support attributes for labelo_width, so we
#       implement it, and we only support values 3 and 5. See the *.map
#       files if you want other values.

# SYNC_ME: Search: Skin GFL IDs. This whole file should assign pens and
#          config zooms for all byway.Geofeature_Layer attributes.

# FIXME: zoom 11: label outline of 4 on white bg is best 
#                 for gfl_id 31 and 21, 3 okay for ID 41, and 3 pixels for 
#                 zoom 9 and 10

# FIXME: Where are the GFL IDs for terrain and points and non-byways?

# FIXME: Make custom pens for these... and can we dash the line for
#        singletrack??

# BUG nnnn: Draw labels with same shadow background as byway color.

# BUG nnnn: Label restricted access in tiles like you do with vectors -- use
#           single red line running down middle of road, e.g.

# MAYBE: Make a skin_classic.py for CcpV1.

__documentation__="""

All of the color values, pixel widths, etc., for each zoom level, and for each
item and geofeature_layer type, and for the map background, etc., can be found
in the skins directory. Currently, we use the skin_bikeways module:

mapserver/skins/skin_bikeways.py

(You can ignore skin_classic, which is intended to mimic CcpV1. It's also used
to test that the system handles multiple skins. But skin_classic probably won't
be implemented -- right now, it's just a copy of skin_bikeways.)

Here's how it works:

1. Manually edit skin_bikeways.py.

1b. ./tilecache_update.py --db-create-public-zooms

2. For tilecache, we run mapserver/gen_tilecache_cfg.py and it uses the values
in the skin file to make /ccp/var/tilecache-cache/cycloplan_live/tilecache.cfg.

3. For mapserver, we run mapserver/make_mapfile.py and it uses the values in
the skin file to make /ccp/var/tilecache-cache/cycloplan_live/wms_instance.map
(which nowadays is a 500,000 line generated file).

4. pyserver doesn't use the skin file -- part of the CcpV2 upgrade process is
to load the data from the skin files into database tables. So pyserver _could_
send the skin file database tables to flashclient via GWIS, but it doesn't.

5. Instead of using GWIS to get the color values (which is half of what CcpV1
does -- the other half being that a lot of colors are just hard-coded in
Conf.as in CcpV2), in CcpV2, we run mapserver/flashclient_classes.py which
makes flashclient/assets/skins/Skin_Bikeways.as -- so the color values are
all hard-coded in CcpV2, and the Flex module is auto-generated from the same
skin_bikeways.py that mapserver and tilecache use.

One advantage to pre-generating the file is that we don't have to wait for the
so-called "draw config" before loading the map.

6. 2013.06.07: The mobile implementation is still pending.
"""

#
def get_skin():

   skin_bikeways = Tile_Skin()

   # The attr_pen definition applies to all
   # geofeature_layers at a specific zoom.
   assign_attr_pens(skin_bikeways)

   # A feat_pen applies to a single
   # geofeature_layer across all zooms.
   assign_feat_pens(skin_bikeways)

   # The gfl_zoom definitions each apply to a
   # single geofeature_layer at a specific zoom.
   assign_tile_pens(skin_bikeways)

   return skin_bikeways

#
def assign_attr_pens(skin_bikeways):

   # FIXME: The attr pens are not wired to make_mapfile.py.

   # Reset the explicit enforcer for 'draw_class'.
   skin_bikeways.on_explicit_key_ranks = False

   # This is from the CcpV1 draw_class (and draw_param_joined) table(s).
# FIXME: In CcpV2, what color is this... white?
   # CcpV1: 14075316/0xd6c5b4/214 197 180
   # SYNC_ME: Search: Background color.
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'draw_class', 'background', 'Background', '',
      dashon_color='234 241 252',))
   skin_bikeways.assign_attr_pen(Attr_Pen( # 16777215/0xffffff/255 255 255
      'draw_class', 'shadow', 'Shadow', '',
      dashon_color='255 255 255',))
   skin_bikeways.assign_attr_pen(Attr_Pen( # 8912896/0x880000/136 0 0
      'draw_class', 'work_hint', 'Work Hint', '',
      dashon_color='136 0 0',))

   # CITE: "Portland by Bicycle" Citywide Bike Map, by the City of Portland.
   #       http://www.portlandoregon.gov/transportation/article/391729

   # SYNC_ME: Search: bike_facil values.

   # Reset the explicit enforcer for 'bike_facil'.
   skin_bikeways.on_explicit_key_ranks = False

   # *** Road/Bikeway Type: Urban Classifications

# FIXME/BUG nnnn: All these string attr_key values should probable be an int
#                 enum, for the sake of collection lookup efficiency.

   # This could be thought of as "Special index: -1" since this is the
   # non-option, i.e., the, this-road-has-no-bike-facility facility. But
   # we want this option to show up in the dropdown, so just make it the
   # first pen in the 'bike_facil' attr_name group, and it'll be assigned
   # key_rank=0.
   skin_bikeways.assign_attr_pen(Attr_Pen(
      # attr_name, attr_key, key_friendly, ...
      #'bike_facil', 'No Facilities', 'No Facilities',
      # SYNC_ME: no_facils/facil_vary: mapserver/skins/skin_bikeways.py
      #          flashclient/views/panel_items/Widget_Bike_Facility
      'bike_facil', 'no_facils', 'No Facilities',
      'views.ornaments.bike_facility.Facilities_None',
      attr_data={'bikeability_boon': False,},
      dashon_color='199 200 202', nodash_color='',
      dashon_interval=0, nodash_interval=0,
      gut_width=0, gut_on_color='', no_gut_color='',
      gut_on_interval=0, no_gut_interval=0,
      ))

# FIXME_2013_06_14: These next two should be enabled for Trail only?
#                   Or they should cause the Road Type to change...
#                   And then if user changes road type, these change?
#                   Or maybe we don't care? Anyway, we have two or more
#                   GUI components that are inter-dependent and should
#                   be wired as such.

   # 'Multi-use path', 0x323092, 'solid', 'purple'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      # MAGIC_NUMBER: 'Bike Trail' is from the Bikeways Shapefile.
      # 2013.08.2?: Per MnDOT meeting.
      #'bike_facil', 'Bike Trail', 'Multi-Use Path (Bike/Walk)',
      'bike_facil', 'paved_trail', 'Shared Use Path (Paved)',
      'views.ornaments.bike_facility.Shared_Path_Paved',
      attr_data={'bikeability_boon': True,},
      dashon_color='50 48 146',
      ))

   # 'Multi-use path (unpaved)', 0x323092, 'dashed', 'purple'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      # MAGIC_NUMBER: 'multi_unpaved' is just because.
      #'bike_facil', 'Multi-Use Path (Unpaved)', 'Multi-Use Path (Unpaved)',
      # 2013.08.2?: Per MnDOT meeting.
      'bike_facil', 'loose_trail', 'Shared Use Path (Unpaved)',
      'views.ornaments.bike_facility.Shared_Path_Unpaved',
      # FIXME/EXPLAIN: There should be an additional pref. to include unpaved,
      # since most "normal" riders well be adverse to riding on unpavement.
      # [lb] personally desires: attr_data={'bikeability_boon': True,},
      #      so make bikeabilities like tag prefs: users can thumbs up/down
      #      different attribute values.
      attr_data={'bikeability_boon': False,},
      dashon_color='50 48 146', nodash_color='255 255 255',
      interval_square=True,))

   # These next four are ordered for a reason.
   # Answer: The gutters and colors come first:
   #         so the green guttered bike boulevard
   #         comes before the green straight line shared road
   #         before blue guttered bike lane
   #         and finally dumb old normal bike lane =)
   #         Also, the color order in the dropdown is more visually
   #         distinguished: purple-green-blue-orange
   #           rather than: purple-blue-green-orange
   #         As Robert Ripley would say, Believe It or Not!
   #         I mean, You Have to See it To Believe iT!
   #         And as Wikipedia once said, "Wisconsin Dells -- This Ripley's
   #         museum looks like a plane flew through the front and has a car
   #         parked on the side. It is located in the Downtown Strip."
   # https://en.wikipedia.org/wiki/Ripley%27s_Believe_It_or_Not!#Wisconsin
   # 2013.09.03: [lb] reordered, from
   #  Bicycle Boulevard, Shared Roadway, Protected Bike Lane, Normal Bike Lane
   # to Bike Lane, Protected Bike Lane, Shared Lane Markings, Bicycle Boulevard

   # 'Bike Lane: Protected, Buffered', 0x008bb0, 'bordered', 'blue'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'protect_ln', 'Protected Bike Lane',
      'views.ornaments.bike_facility.Bike_Lane_Protected',
      attr_data={'bikeability_boon': True,},
      #dashon_color='0 139 176', guts_ok_at_zoom=7, gut_width=1.0,))
      dashon_color='0 139 176', guts_ok_at_zoom=7, gut_width=2.0,))

   # 'Bike Lane', 0x008bb0, 'solid', 'blue'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'bike_lane', 'Bike Lane',
      'views.ornaments.bike_facility.Bike_Lane_OnRoad',
      attr_data={'bikeability_boon': True,},
      dashon_color='0 139 176',))

   #
   #
   # BUG nnnn/FIXME: Instead of squares of colors, can we make white circles?
   #  MnDOT suggested a blue line with white cirles on top of it.
   #  [lb] guesses the paint_bike_facility fcn. needs tweaking --
   #   draw a solid line, and then walk the line and draw little circles.
   #
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'rdway_shrrws', 'Shared Lane Markings',
      'views.ornaments.bike_facility.Roadway_Sharrows',
      attr_data={'bikeability_boon': True,},
      dashon_color='0 139 176', nodash_color='255 255 255',
      interval_square=True,))

   # 'Bike boulevards / Neighborhood Greenways', 0x78a22d, 'bordered', 'green'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'bike_blvd', 'Bicycle Boulevard',
      'views.ornaments.bike_facility.Bike_Boulevard',
      attr_data={'bikeability_boon': True,},
      dashon_color='120 162 45', guts_ok_at_zoom=7, gut_width=1.0,))

   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'rdway_shared', 'Shared Roadway',
      'views.ornaments.bike_facility.Roadway_Shared',
      attr_data={'bikeability_boon': True,},
      dashon_color='120 162 45',))

   # *** Road/Bikeway Type: Shoulder and Rural Classifications

   # 'Shared Roadway with Wider Outside Lane', 0xed891d, 'orange'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'shld_lovol', 'Shoulder (Low Volume)',
      'views.ornaments.bike_facility.Shoulder_Low_Vol',
      attr_data={'bikeability_boon': True,},
      # orange: dashon_color='237 137 29',))
      # but make it brown, like low-volume highway
      dashon_color='114 90 73', guts_ok_at_zoom=7, gut_width=2.0,))

# FIXME/BUG nnnn: Hard-coded gut_width applies to all zoom levels.
#                 If you zoom to the largest vector level, you'll
#                 see that roads with this facility are extra fat.
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'shld_hivol', 'Shoulder (High Volume)',
      'views.ornaments.bike_facility.Shoulder_High_Vol',
      attr_data={'bikeability_boon': True,},
      dashon_color='217 97 124', guts_ok_at_zoom=7, gut_width=2.0,))
   # KEEP: This is the old visualization for high vol shoulder:
   #       Pink squares inside with orange gutters.
   #   dashon_color='217 97 124', nodash_color='255 255 255',
   #   dashon_interval=4, nodash_interval=4,
   #   gut_on_color='237 137 29',  guts_ok_at_zoom=7, gut_width=4.0,

   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'hway_lovol', 'Highway (Low Volume)',
      'views.ornaments.bike_facility.Highway_Low_Vol',
      attr_data={'bikeability_boon': False,},
      #dashon_color='237 137 29',))
      # The 'good' bikeability rating.
      # FIXME: Revisit this color.
      dashon_color='114 90 73',))

   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'hway_hivol', 'Highway (High Volume)',
      'views.ornaments.bike_facility.Highway_High_Vol',
      attr_data={'bikeability_boon': False,},
      # The pinkish 'caution' color.
      # FIXME: This is probably a horrible color choice.
      dashon_color='217 97 124',))

   # FIXME: We could just use the 'unpaved' tag, but for simplicity -- i.e.,
   #        we want the agencies to use this application to maintain their
   #        bikeways data -- it makes more sense to reduce the number of
   #        mouse clicks, i.e.#2, keep everything in the one dropdown menu.
   skin_bikeways.assign_attr_pen(Attr_Pen(
      #'bike_facil', 'hwayunpavd', 'Rural Road (Unpaved)',
      'bike_facil', 'gravel_road', 'Gravel Road',
      #'bike_facil', 'gravel_road', 'Gravel Road (Almanzo)',
      'views.ornaments.bike_facility.Gravel_Road',
      attr_data={'bikeability_boon': False,},
      #dashon_color='237 137 29',))
      # The 'good' bikeability rating.
      # FIXME: Revisit this color. #a1a5ac
      dashon_color='161 165 172',))

# FIXME/BUG nnnn: Decide on color/style for this new bike facility.
# 'Bike Lane', 0x008bb0, 'solid', 'blue'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'bk_rte_u_s', 'U.S. Bike Route',
      'views.ornaments.bike_facility.Bike_Route_U_S',
      attr_data={'bikeability_boon': True,},
#dashon_color='0 139 176',))
dashon_color='0 255 0',))

# FIXME/BUG nnnn: Decide on color/style for this new bike facility.
# 'Bike Lane', 0x008bb0, 'solid', 'blue'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'bike_facil', 'bkway_state', 'State Bikeway',
      'views.ornaments.bike_facility.Bikeway_State',
      attr_data={'bikeability_boon': True,},
#dashon_color='0 139 176',))
dashon_color='0 0 255',))

   # # 'Major Street', 0xc7c8ca, 'solid-not-as-thick', 'light grey'
   # skin_bikeways.assign_attr_pen(
   #    'bike_facil', 'major_street', 'Major Street',
   #    'views.ornaments.bike_facility.Major_Street',
   #    attr_data={'bikeability_boon': False,},
   #    Attr_Pen(pen_color='199 200 202')), 

   # *** DEVS: WATCH OUT! Special ordering hereafter.

   # MAGIC_NUMBER: Special index: -2 is specified when more than one item is
   #               selected and they have varying bike facilities. This option
   #               is not display in the dropdown but is used to draw the
   #               button.
   # MUST: This must be after all Attr_Pen()s that _do_not_ specify key_rank.
   skin_bikeways.assign_attr_pen(Attr_Pen(
      #attr_name='bike_facil', attr_key='Facilities Varies',
      # SYNC_ME: no_facils/facil_vary: mapserver/skins/skin_bikeways.py
      #          flashclient/views/panel_items/Widget_Bike_Facility
      attr_name='bike_facil', attr_key='facil_vary',
      key_friendly='Varies',
      icon_class='views.ornaments.bike_facility.Facilities_Vary',
      attr_data={'bikeability_boon': False,},
      # MAGIC_NUMBER/SYNC_ME: -2 matches
      #  flashclient.utils.misc.Combo_Box_V2.INDEX_VARIES
      dashon_color='0 0 0', key_rank=-2))

   # *** Road/Bikeway Type: Cautionary Classifications

   # Reset the explicit enforcer for 'bike_facil'.
   skin_bikeways.on_explicit_key_ranks = False

   skin_bikeways.assign_attr_pen(Attr_Pen(
      # attr_name, attr_key, key_friendly, ...
      #'bike_facil', 'No Facilities', 'No Facilities',
      # SYNC_ME: no_cautys
      'cautionary', 'no_cautys', 'No Cautions',
      'views.ornaments.bike_facility.Cautions_None',
      attr_data={'bikeability_boon': False,},
      dashon_color='199 200 202', nodash_color='',
      dashon_interval=0, nodash_interval=0,
      guts_ok_at_zoom=7, gut_width=0.0, gut_on_color='', no_gut_color='',
      gut_on_interval=0, no_gut_interval=0,))

   ## 'Shared Roadway / Difficult Connection', 0x78a22d, 'solid', 'green',
   ##                                0xd9617c, 'tiny dash bordered', 'red'
   #skin_bikeways.assign_attr_pen(Attr_Pen(
   #   #'cautionary', 'Use Extra Caution', 'Use Extra Caution',
   #   'cautionary', 'extra_cautn', 'Use Extra Caution',
   #   'views.ornaments.bike_facility.Use_Extra_Caution',
   #   attr_data={'bikeability_boon': False,},
   #   dashon_color='217 97 124', nodash_color='255 255 255',
   #   # Note that short dashes show artifacts when drawn at an angle,
   #   # i.e., it looks great if the byway is drawn along either the
   #   # x or y axis, but at, e.g., a 45 degree angle, it gets jaggy.
   #   #dashon_interval=2, nodash_interval=2,
   #   dashon_interval=4, nodash_interval=4,
   #   ))

   skin_bikeways.assign_attr_pen(Attr_Pen(
      'cautionary', 'constr_open', 'Construction (Open)',
      'views.ornaments.bike_facility.Construction_Open',
      attr_data={'bikeability_boon': False,},
      dashon_color='217 97 124', nodash_color='255 255 255',
      dashon_interval=4, nodash_interval=4,
      ))

   # NOTE: The two Construction cautions are the same style...
   #       but the Closed Construction caution is sort of special:
   #       it means the byway segment has a 'closed' tag. Meaning:
   #       both flashclient and mapserver will draw a single pixel
   #       red centerline to indicate closed.
   #
   #
   #
# FIXME: Wire flashclient to add/remove tags for special facils!!
#
#
#
   skin_bikeways.assign_attr_pen(Attr_Pen(
      'cautionary', 'constr_closed', 'Construction (Closed)',
      'views.ornaments.bike_facility.Construction_Closed',
      attr_data={'bikeability_boon': False,},
      dashon_color='217 97 124', nodash_color='255 255 255',
      dashon_interval=4, nodash_interval=4,
      ))

   # FIXME: [lb] likes this visualization but it's new (not in Portland Legend;
   #        not meant for any particular facility).
   skin_bikeways.assign_attr_pen(Attr_Pen(
      #'cautionary', 'Extra Caution 2', 'Use Extra Caution 2',
      #'cautionary', 'Poor Visibility', 'Poor Visibility',
      'cautionary', 'poor_visib', 'Poor Visibility',
      'views.ornaments.bike_facility.Poor_Visibility',
      attr_data={'bikeability_boon': False,},
      dashon_color='120 162 45', nodash_color='255 255 255',
      gut_on_color='217 97 124',
      #guts_ok_at_zoom=7, gut_width=2.0, gut_on_interval=2, no_gut_interval=2,
      guts_ok_at_zoom=7, gut_width=4.0, gut_on_interval=3, no_gut_interval=3,
      ))

   # 'Difficult Connection', 0xd20d44, 'dashed', 'red'
   skin_bikeways.assign_attr_pen(Attr_Pen(
      #'cautionary', 'Difficult Connection', 'Difficult Connection',
      'cautionary', 'diffi_conn', 'Difficult Connection',
      'views.ornaments.bike_facility.Difficult_Connection',
      attr_data={'bikeability_boon': False,},
      dashon_color='210 13 68', nodash_color='255 255 255',
      interval_square=True,))

   #
   # BUG nnnn: Is Controlled Access a Caution?
   #           A checkbox?
   # skin_bikeways.assign_attr_pen(Attr_Pen(
   #    #'cautionary', 'Controlled Access', 'Controlled Access',
   #    'cautionary', 'cntrld_acs', 'Controlled Access',
   #    'views.ornaments.bike_facility.Controlled_Access',
   #    attr_data={'bikeability_boon': False,},
   #    dashon_color='255 0 0', nodash_color='255 255 255',))

   # # 'Climb', 0x4b4c4d, 'chevron', 'dark grey'
   # skin_bikeways.assign_attr _pen(
   #    'cautionary', 'climb', 'Climb',
   #    'views.ornaments.bike_facility.Climb',
   #    attr_data={'bikeability_boon': False,},
   #    Attr_Pen(pen_color='75 76 77'),)

   # *** DEVS: WATCH OUT! Special ordering hereafter.

   # MAGIC_NUMBER: Special index: -2 is specified when more than one item is
   #               selected and they have varying bike facilities. This option
   #               is not display in the dropdown but is used to draw the
   #               button.
   # MUST: This must be after all Attr_Pen()s that _do_not_ specify key_rank.
   skin_bikeways.assign_attr_pen(Attr_Pen(
      #attr_name='cautionary', attr_key='Facilities Varies',
      # SYNC_ME: no_facils/facil_vary: mapserver/skins/skin_bikeways.py
      #          flashclient/views/panel_items/Widget_Bike_Facility
      attr_name='cautionary', attr_key='facil_vary',
      key_friendly='Varies',
      # NOTE: The cautions use the same 'varies' icon as the facilities.
      icon_class='views.ornaments.bike_facility.Facilities_Vary',
      attr_data={'bikeability_boon': False,},
      # MAGIC_NUMBER/SYNC_ME: -2 matches
      #  flashclient.utils.misc.Combo_Box_V2.INDEX_VARIES
      dashon_color='0 0 0', key_rank=-2))

#
def assign_feat_pens(skin_bikeways):

   # *** Pen and Label colors for all zoom levels.

   # *** Byway geofeature_layers

   skin_bikeways.assign_feat_pen(byway.Geofeature_Layer.Expressway,
      Feat_Pen(restrict_usage=False, friendly_name='Expressway',
         pen_color='163 166 189', shadow_width=2, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=3, labelo_color='163 166 189'))

   skin_bikeways.assign_feat_pen(byway.Geofeature_Layer.Highway,
      Feat_Pen(restrict_usage=False, friendly_name='Highway',
         pen_color='150 119 107', shadow_width=2, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=3, labelo_color='234 241 252'))

   skin_bikeways.assign_feat_pen(byway.Geofeature_Layer.Major_Road,
      Feat_Pen(restrict_usage=False, friendly_name='Major Road',
         pen_color='114 90 73', shadow_width=0, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=3, labelo_color='234 241 252'))

   # FIXME: Fix the hex on Major_Trail. Same in Conf.as.
   skin_bikeways.assign_feat_pen(byway.Geofeature_Layer.Major_Trail,
      Feat_Pen(restrict_usage=False, friendly_name='Major Trail',
         pen_color='208 171 65', shadow_width=2, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=3, labelo_color='208 171 65'))

   skin_bikeways.assign_feat_pen(byway.Geofeature_Layer.Bike_Trail,
      Feat_Pen(restrict_usage=False, friendly_name='Bike Trail',
         pen_color='208 171 65', shadow_width=2, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=3, labelo_color='208 171 65'))

   # FIXME: [lb] just copied this from the Expressway definition. This should
   #        be a dashed or crossed line or something.
   skin_bikeways.assign_feat_pen(byway.Geofeature_Layer.Railway,
      Feat_Pen(restrict_usage=False, friendly_name='Railway',
         pen_color='163 166 189', shadow_width=2, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=3, labelo_color='163 166 189'))

   # Tile_Skin.gfl_local_road_et_al:
# FIXME: Draw each of these differently... like, dashed lines for singletrack.
   for id_and_name in [
         (byway.Geofeature_Layer.Byway_Alley, 'Alley',),
         (byway.Geofeature_Layer.Local_Road, 'Local Road',),
         (byway.Geofeature_Layer.Unknown, 'Unknown',),
         (byway.Geofeature_Layer.Other, 'Other',),
         (byway.Geofeature_Layer._4WD_Road, '4WD Road',),
         (byway.Geofeature_Layer.Sidewalk, 'Sidewalk',),
         (byway.Geofeature_Layer.Doubletrack, 'Doubletrack',),
         (byway.Geofeature_Layer.Singletrack, 'Singletrack',),
         (byway.Geofeature_Layer.Expressway_Ramp, 'Expressway Ramp',),
         (byway.Geofeature_Layer.Private_Road, 'Private Road',),
         (byway.Geofeature_Layer.Other_Ramp, 'Other Ramp',),
         (byway.Geofeature_Layer.Parking_Lot, 'Parking Lot',),
         ]:
      skin_bikeways.assign_feat_pen(id_and_name[0],
         Feat_Pen(restrict_usage=False, friendly_name=id_and_name[1],
            pen_color='66 51 39', shadow_width=0, shadow_color='255 255 255',
            label_color='0 0 0', labelo_width=3, labelo_color='234 241 252'))

   # CcpV1 draw_class table:
   #  41 | super        | 2007-11-19 15:59:31.8362-06   | 15908644
   #  11 | small        | 2007-03-05 16:08:58.72922-06  | 16777215
   #  21 | medium       | 2007-03-05 16:08:58.72922-06  | 16775795
   #  31 | large        | 2007-03-05 16:08:58.72922-06  | 16775795
   #   1 | shadow       | 2010-03-29 17:02:51.852329-05 | 16777215
   #   6 | watch_region | 2008-08-23 15:40:55.893769-05 | 16711680
   #   4 | background   | 2010-03-29 17:02:51.852329-05 | 14075316
   #   3 | water        | 2010-03-29 17:02:51.852329-05 |  8828110
   #   5 | point        | 2010-03-29 17:02:51.852329-05 |  8537053
   #   8 | route        | 2010-03-29 17:02:51.852329-05 |  8835271
   #   9 | region       | 2010-03-29 17:02:51.852329-05 |  6710886
   #  10 | track        | 2011-07-13 21:01:38.746757-05 |    39168
   #  12 | bike_trail   | 2013-04-27 18:35:14.183393-05 | 14663679
   #   2 | open_space   | 2013-04-27 18:35:14.183393-05 |  7969073
   #   7 | work_hint    | 2013-04-27 18:35:14.183393-05 |  8912896
   #  22 | major_trail  | 2013-04-27 19:59:15.245566-05 | 14663679

   # *** Region geofeature_layers

   # NOTE: CcpV1 color value.
   skin_bikeways.assign_feat_pen(region.Geofeature_Layer.Default,
      Feat_Pen(restrict_usage=True, friendly_name='Route',
         # 6710886/0x666666/102 102 102
         pen_color='102 102 102', shadow_width=0, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=0, labelo_color='255 255 255'))

   # *** Route geofeature_layers

   # NOTE: CcpV1 color value.
   skin_bikeways.assign_feat_pen(route.Geofeature_Layer.Default,
      Feat_Pen(restrict_usage=True, friendly_name='Route',
         # SYNC_ME: flashclient/Conf.as::route_color
         #          mapserver/skins/skin_bikeways.py::assign_feat_pen(route...
         # 8835271/0x86d0c7/134 208 199 # lite blue
         #pen_color='134 208 199',
         # 2f852a # bright green
         pen_color='47 133 42',
         shadow_width=0, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=0, labelo_color='255 255 255'))

   # *** Terrain geofeature_layers

   # FIXME: These are not wired. terrain-m4.map needs to be redone per byways.

   # #COLOR 121 153 49
   # COLOR 54 189 111
   # #COLOR 195 231 148
   # #COLOR 98 212 148
   skin_bikeways.assign_feat_pen(terrain.Geofeature_Layer.Open_Space,
      Feat_Pen(restrict_usage=True, friendly_name='Park/Open Space',
         pen_color='54 189 111', shadow_width=0, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=0, labelo_color='255 255 255'))

   # #COLOR 134 180 206
   # COLOR 50 153 212
   # #COLOR 144 180 208
   # #COLOR 118 148 235
   skin_bikeways.assign_feat_pen(terrain.Geofeature_Layer.Water,
      Feat_Pen(restrict_usage=True, friendly_name='Water',
         #pen_color='50 153 212', shadow_width=0, shadow_color='255 255 255',
         # Lighter blue, to make different from bike lane facil color.
         pen_color='94 197 255', shadow_width=0, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=0, labelo_color='255 255 255'))

   # *** Track geofeature_layers

   # NOTE: CcpV1 color value.
   skin_bikeways.assign_feat_pen(track.Geofeature_Layer.Default,
      Feat_Pen(restrict_usage=True, friendly_name='Track',
         # 8912896/0x009900/0 153 0
         pen_color='0 153 0', shadow_width=0, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=0, labelo_color='255 255 255'))

   # *** Waypoint geofeature_layers

   # NOTE: CcpV1 color value.
   skin_bikeways.assign_feat_pen(waypoint.Geofeature_Layer.Default,
      Feat_Pen(restrict_usage=True, friendly_name='Point of Interest',
         # 8537053/0x8243dd/130 67 221
         pen_color='130 67 221', shadow_width=0, shadow_color='255 255 255',
         label_color='0 0 0', labelo_width=0, labelo_color='255 255 255'))

# ***

# MAGIC_NAMES! sql: SELECT * FROM _tclust WHERE gfl_id = 41;
l_restrict_names_expressway = (
   'ISTH 94',
   'ISTH 90',
   'I-94 / US Hwy 52',
   'ISTH 35',
   'US Hwy 169',
   'I-35W',
   'I-35E',
   'I-494',
   'US Hwy 212',
   'I-35',
   'I-694',
   )

# MAGIC_NAMES! sql: SELECT * FROM _tclust WHERE gfl_id = 31;
# SELECT cluster_name, SUM(geom_len) FROM _tclust WHERE gfl_id = 31 GROUP BY cluster_name ORDER BY sum DESC;
# SELECT cluster_name, SUM(geom_area) FROM _tclust WHERE gfl_id = 31 GROUP BY cluster_name ORDER BY sum DESC;
__ignore_meeee1__ = (
"""
SELECT byway_stack_id, gfl_id, geom_len, geom_area FROM _tclust
   JOIN tiles_cache_clustered_byways AS _tcbyways
        ON ((_tcbyways.cluster_id = _tclust.c_id)
        AND (_tcbyways.byway_branch_id = _tclust.brn_id))
   WHERE _tclust.cluster_name = 'MNTH 61';
""")

l_restrict_stack_ids_highway_06 = (

   # Stack ID | geom len | geom area

   # MNTH 61:
   ##3607034, # |    63206 | 1513419963
   #3606890, # |    49755 | 1083352643
   #3606952, # |    35035 |  585378844
   #2542570, # |    23541 |  265762196
   #4057369, # |    20335 |  198324997
   #2542569, # |    19856 |  176656339
   #2542641, # |    10816 |   55824790
   #2542571, # |     8238 |   30932200

   # Gunflint Tr:
   3606769, # |    74335 | 1548624991
   #3605905, # |     8654 |   19464708
   #3604967, # |     4143 |    3557420
   #1035118, # |      802 |     235918

   )

l_restrict_names_highway_05 = (
   'MNTH 47',
   'MNTH 61',
   'Gunflint Tr',
   'Arrowhead Tr',
   )

l_restrict_names_highway_06 = l_restrict_names_highway_05 + (
   'USTH 53',
   'USTH 10',
   'USTH 61',
   'MNTH 1', # NOTE: Regex matches, e.g., 'MNTH 19'
   'MNTH 23',
   'MNTH 46',
   'MNTH 200',
   'USTH 52',
   'USTH 2',
   'Hwy 65',
   'USTH 71',
   'USTH 53',
   'USTH 169',
   'MNTH 62',
   'MNTH 16',
   'MNTH 13',
   )

# MAGIC_NAMES! sql: SELECT * FROM _tclust WHERE gfl_id = 21;
l_restrict_names_major_road = (
   'Northfield Blvd / County Hwy 47',
   'County Rd 61',
   )

# MAGIC_NAMES! sql: SELECT * FROM _tclust WHERE gfl_id IN (14, 22);
# NOTE: This lookup not used; see l_restrict_stack_ids_major_trail_06.
l_restrict_names_major_trail = (
   'Sunrise Prairie Trail',
   'River Pkwy Trail',
   'Minnesota River Bluffs',
   'Cedar Lake Regional Trail',
   'Minnesota River Bottoms Trail',
   'Minnehaha Creek Trail',
   'Hardwood Creek Trail',
   'Elm Creek Blvd Trail',
   # 2014.8.18: Recently added DNR trails:
   'Arrowhead State Trail',
   'Blazing Star State Trail',
   'Blufflands State Trail',
   'Casey Jones State Trail',
   'Central Lakes State Trail',
   'Cuyuna Lakes State Trail',
   #'Dakota Rail State Trail',
   'Dakota Trail', # FIXME: Use LIKE '%lowercase_query%'
   #'Dakota Trail - Mound/St. Boni', # Added by users years ago
   #'Dakota Trail - Wayzata/Mound', # Added by users years ago
   'Douglas State Trail',
   'Gandy Dancer State Trail',
   'Gateway Trail', # Added by users years ago
   'Glacial Lakes State Trail',
   'Gitchi-Gami State Trail',
   'Goodhue-Pioneer State Trail',
   'Great River Ridge State Trail',
   'Heartland State Trail',
   'Luce Line Trail', # Added by users years ago
   'Matthew Lourey State Trail',
   'Mill Towns State Trail',
   'Minnesota River State Trail',
   'Minnesota Valley State Trail',
   #'Pengilly to Goodland State Trail', # Not bikeable.
   'Saginaw Grade State Trail',
   'Sakatah Singing Hills State Trail',
   'Shooting Star State Trail',
   'Taconite State Trail',
   'Willard Munger State Trail', # Added by users years ago
   )

# MAGIC_NUMBERS: This is pretty messed up, but [lb] can't figure out a better
# way. At the upper zoom levels, there's no good algorithm for figuring out
# labels than just picking stack IDs from the database... enjoy!
__ignore_meeee__ = (
"""
SELECT * FROM _tclust 
   WHERE gfl_id IN (14, 22)
     AND geom_len > 10000
     AND geom_area > 50000000;

SELECT _tcbyways.byway_stack_id, * FROM _tclust
   JOIN tiles_cache_clustered_byways AS _tcbyways
        ON ((_tcbyways.cluster_id = _tclust.c_id)
        AND (_tcbyways.byway_branch_id = _tclust.brn_id))
   WHERE gfl_id IN (14, 22) and geom_len > 10000 and geom_area > 50000000;
""")

l_restrict_stack_ids_major_trail_06 = (

   4112805, # 'Arrowhead State Trail'
   4111980, # 'Blazing Star State Trail'
   4112395, # 'Blufflands State Trail' (6 segments)
   4112741, # 'Blufflands State Trail' (60 segments)
   4112063, # 'Casey Jones State Trail' (24 segments)
   4112062, # 'Casey Jones State Trail' (4 segments)
   4112681, # 'Casey Jones State Trail' (17 segments)
   4112767, # 'Central Lakes State Trail' (53 segments)
   4113317, # 'Cuyuna Lakes State Trail' (23 segments)

   # MAYBE/FIXME: The 'Dakota Trail' is not contiguous,
   #              e.g., 'Dakota Trail - Wayzata/Mound' is
   #              six segments
   # WHEN FIXING DUPLICATES, rename all dakota segments:
   # Dakota Rail Regional Trail
   # These segments are too short:
   #1373898, # 'Dakota Trail - Wayzata/Mound'
   #1375239, # 'Dakota Trail - Mound/St. Boni'
   #1531411, # 'Dakota Trail - St. Boni/Mayer'

   4111826, # 'Douglas State Trail' (17 segments)
   4112612, # 'Gandy Dancer State Trail' (36 segments)
   1124373, # Gateway Trail # 18585 Km
   #4112200, # 'Glacial Lakes State Trail' (3 segments)
   4112168, # 'Glacial Lakes State Trail' (36 segments)
   4112465, # 'Gitchi-Gami State Trail' (1 segments)
   4112441, # 'Gitchi-Gami State Trail' (26 segments)
   4112457, # 'Gitchi-Gami State Trail' (22 segments)
   4112923, # 'Gitchi-Gami State Trail' (4 segments)
   4112385, # 'Gitchi-Gami State Trail' (19 segments)
   4112963, # 'Gitchi-Gami State Trail' (7 segments)
   4112961, # 'Gitchi-Gami State Trail' (5 segments)
   # In 06: 4112268, # 'Goodhue-Pioneer State Trail' (8 segments)
   4111733, # 'Goodhue-Pioneer State Trail' (4 segments)
   4111842, # 'Great River Ridge State Trail' (18 segments)
   4113159, # 'Heartland State Trail' (76 segments)
   1134849, # Luce Line Trail # 31166 Km
   4111347, # 'Matthew Lourey State Trail' (113 segments)
   4111754, # 'Mill Towns State Trail' (6 segments)
   4112116, # 'Minnesota River State Trail' (19 segments)
   # In 06: 4112082, # 'Minnesota River State Trail' (4 segments)
   # In 06: 4112102, # 'Minnesota River State Trail' (13 segments)
   4111483, # 'Minnesota Valley State Trail' (25 segments)
   4113031, # 'Paul Bunyan State Trail' (118 segments)
   4113575, # 'Paul Bunyan State Trail' (46 segments)
   # Not bikeable: 'Pengilly to Goodland State Trail'
   4113499, # 'Saginaw Grade State Trail' (2 segments)
   4111792, # 'Sakatah Singing Hills State Trail' (69 segments)
   4112008, # 'Shooting Star State Trail' (39 segments)
   4112910, # 'Taconite State Trail' (94 segments)

   # This one doesn't show?:
   1579909, # 'Willard Munger State Trail' || 51 K
   # what about these?:
   4070759, # Willard Munger State Trail || 36 K
   4112216, # Willard Munger State Trail || 20 K

   )

l_restrict_stack_ids_major_trail_07 = l_restrict_stack_ids_major_trail_06 + (

   4112268, # 'Goodhue-Pioneer State Trail' (8 segments)
   4112082, # 'Minnesota River State Trail' (4 segments)
   4112102, # 'Minnesota River State Trail' (13 segments)

   # 2014.08.21: Gateway Trail
   #    cluster_id | branch_id | cnt |    st_length     
   #    ------------+-----------+-----+------------------
   #          91444 |   2500677 |  43 | 18584.7199595018
   #          91445 |   2500677 |   8 |  10332.778438965
   #          91447 |   2500677 |   1 | 36.9068267881751
   #          91446 |   2500677 |   1 | 18.0433890107968
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 91444 LIMIT 1;
   # See above: 1124373, # Gateway Trail || 18 K
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 91445 LIMIT 1;
   # Overlaps: 1135339, # Gateway Trail || 10 K
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 91447 LIMIT 1;
   #1435712, # Gateway Trail || short...
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 91446 LIMIT 1;
   #1425872, # Gateway Trail || short...

   4112200, # 'Glacial Lakes State Trail' (3 segments)

   # 2014.08.21: Willard Munger State Trail
   #   cluster_id | branch_id | cnt |    st_length     
   #  ------------+-----------+-----+------------------
   #       166038 |   2500677 |  34 | 51080.3033523543
   #       166037 |   2500677 |  19 |  36325.074607377
   #       166040 |   2500677 |  22 | 20314.1904669263
   #       166036 |   2500677 |   5 | 3212.26509660066
   #       166039 |   2500677 |   4 | 1394.28527625792
   #       166041 |   2500677 |   1 | 853.244957176265
   #       166042 |   2500677 |   1 | 416.190885921174
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 166038 LIMIT 1;
   # See above: 1579909, # Willard Munger State Trail || 51 K
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 166037 LIMIT 1;
#   4070759, # Willard Munger State Trail || 36 K
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 166040 LIMIT 1;
#   4112216, # Willard Munger State Trail || 20 K
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 166036 LIMIT 1;
   #1580033, # Willard Munger State Trail || 3.2 K
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 166039 LIMIT 1;
   #4112641, # Willard Munger State Trail || 1.4 K
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 166041 LIMIT 1;
   #4113259, # Willard Munger State Trail || 853 m
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 166042 LIMIT 1;
   #4113263, # Willard Munger State Trail || 400 m


   # FIXME: I deleted my trail!
   #        Figure out a better solution than using stk ids.
   #        For now...
   #  SELECT cluster_id, branch_id, byway_count AS cnt, ST_Length(geometry)
   #     FROM tiles_cache_byway_cluster
   #     WHERE cluster_name = 'Sunrise Prairie Trail'
   #     ORDER BY ST_Length DESC;
   #   cluster_id | branch_id | cnt |    st_length     
   #  ------------+-----------+-----+------------------
   #       152210 |   2500677 |  25 | 21533.3570236714
   #       152209 |   2500677 |   5 | 4991.30007082306
   #       152208 |   2500677 |   1 | 138.622539699755
   #       152211 |   2500677 |   1 | 121.852868735683
   #  SELECT byway_stack_id FROM tiles_cache_clustered_byways
   #     WHERE cluster_id = 152210 LIMIT 1;
   1138202, # Sunrise Prairie Trail # 21533 m
   1579764, # Sunrise Prairie Trail # 4.991 Km

   1124361, # Midtown Greenway # 6.933 Km

   # The Mtka LRT is a nice trail, but it overlaps with the Greenway label.
   # But maybe it's interesting at this level to have some overlap.
   1134718, # Lake Minnetonka LRT Regional Trail # 27808 Km
)

l_restrict_stack_ids_major_trail_08 = l_restrict_stack_ids_major_trail_07 + (

)

l_restrict_stack_ids_major_trail_05 = l_restrict_stack_ids_major_trail_08 + (

   # These are just straight line labels from zoom 05 to 08...
   # BUG nnnn/FIXME: Resegment Dakota Trail by naming all segments the same,
   #                 e.g., just 'Dakota Rail Regional Trail'.
   1373898, # 'Dakota Trail - Wayzata/Mound'
   1375239, # 'Dakota Trail - Mound/St. Boni'
   1531411, # 'Dakota Trail - St. Boni/Mayer'
   #  But they're okay in zoom 5, which doesn't use labels...

   # FIXME/EXPLAIN: What's up with the small segment?
   4113245, # 'Cuyuna Lakes State Trail' (3 segments)

   # This is here because it overlaps with the other label at zooms 6-8.
   1135339, # Gateway Trail || 10 K
)

# 2014.08.21: Looking for deleted byways:
# ','.join([str(x) for x in l_restrict_stack_ids_major_trail_05])
# SELECT stk_id FROM _gia WHERE d IS TRUE AND stk_id IN (...);

__ignore_meeee3__ = (
"""
SELECT * FROM _tclust 
   WHERE gfl_id IN (14, 22)
     AND geom_len > 10000
     AND geom_area > 50000000;

SELECT _tcbyways.byway_stack_id, * FROM _tclust
   JOIN tiles_cache_clustered_byways AS _tcbyways
        ON ((_tcbyways.cluster_id = _tclust.c_id)
        AND (_tcbyways.byway_branch_id = _tclust.brn_id))
   --WHERE cluster_name = 'Lake Minnetonka LRT Regional Trail';
   --WHERE cluster_name = 'Sunrise Prairie Trail';
   WHERE cluster_name = 'Midtown Greenway';
""")

# ***

#
def assign_tile_pens(skin_bikeways):

   # Below, we're skipping:
   #  branch.Geofeature_Layer.Default
   #  region.Geofeature_Layer.Default
   #  route.Geofeature_Layer.Default
   #  terrain.Geofeature_Layer.*
   #  track.Geofeature_Layer.Default
   #  waypoint.Geofeature_Layer.Default

   # *** Zoom: 5.

   # NOTE: Labels don't really work at zoom 5. First, you get tons of
   #       collisions, so you have to be really deliberate about what
   #       rows to retrieve from the database. Second, because, e.g.,
   #       the State of MN is made of four tiles (at 256x256 tile size),
   #       we have problems with partial labels (that just get clipped
   #       in the middle of their name, in the middle of the state).

   # Byway
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=5,
         do_draw=True, pen_width=3, pen_gutter=0,
         d_geom_area=10000000,
         do_label=False,
         label_size=8, l_bold=True, p_min=10, p_new=9,
         #l_restrict_named=l_restrict_names_expressway
         ))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=5,
         do_draw=True, pen_width=2, pen_gutter=0,
         d_geom_area=100000000,
         do_label=False,
         label_size=8, l_bold=True, p_min=10, p_new=8,
         l_restrict_named=l_restrict_names_highway_05))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=5,
         do_draw=True, pen_width=1, pen_gutter=0,
         d_geom_area=100000000,
         do_label=False,
         label_size=8, l_bold=False, p_min=10, p_new=7,
         l_restrict_named=l_restrict_names_major_road))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=5,
      do_draw=True, pen_width=1, pen_gutter=0,
      d_geom_area=1000000,
      do_label=False,
      label_size=8, l_bold=True, p_min=10, p_new=10,
      #l_restrict_named=l_restrict_names_major_trail,
      #l_restrict_distinct=True,))
      l_restrict_stack_ids=l_restrict_stack_ids_major_trail_05,
      l_minfeaturesize='1',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=5,
         do_draw=False, pen_width=1, pen_gutter=0,
         d_geom_area=100000000,
         do_label=False,
         label_size=8, l_bold=False, p_min=10, p_new=6))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=5,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))
   # CALLME-MAYBE: Show state region, and maybe cities...
   # Region
   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=5,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   # MAYBE: Show large lakes and label them... but [lb] kind of likes
   #        the minimalistic map.
   # Terrain
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=5,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=5,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=5,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=5,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   # Waypoint
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=5,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   #
   # Route
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=5,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=9))
   # Track
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=5,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))

   # *** Zoom: 6.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=6,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=False, # l_geom_area=1000000,
         label_size=8, l_bold=False, p_min=0, p_new=9,
         #l_restrict_named=l_restrict_names_expressway
         ))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=6,
#         do_draw=True, pen_width=2, pen_gutter=0,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True,
         label_size=8, l_bold=False, p_min=0, p_new=8,
         #l_restrict_named=l_restrict_names_highway_06
         l_restrict_stack_ids=l_restrict_stack_ids_highway_06
         ))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=6,
         do_draw=True, pen_width=1, pen_gutter=0,
         d_geom_len=0, d_geom_area=1000000,
         do_label=False,
         label_size=8, l_bold=False, p_min=0, p_new=7,
         l_restrict_named=l_restrict_names_major_road))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=6,
      do_draw=True, pen_width=1, pen_gutter=0,
      d_geom_len=10000, d_geom_area=50000000,
      do_label=True,
      #l_geom_len=10000, l_geom_area=50000000,
      label_size=8, l_bold=False, p_min=0, p_new=10,
      l_partials=True, l_force=True,
      l_restrict_stack_ids=l_restrict_stack_ids_major_trail_06,
      l_minfeaturesize='1',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8, l_bold=False, p_min=0, p_new=6))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=6,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   # Region
   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=6,
         do_draw=True, pen_width=2, pen_gutter=0,
         do_label=False, label_size=8))
   # Terrain
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=3, pen_gutter=0,
         do_label=False, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=3, pen_gutter=0,
         do_label=False, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   # Waypoint
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=6,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   #
   # Route
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=6,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=9))
   # Track
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=6,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=8))

   # *** Zoom: 7.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True,
         #          Stack ID | gfl_id | geom len | geom area
         # Zane Ave: 4263179 |     11 |    18985 |   9786788
         #l_geom_len=10000, l_geom_area=50000000,
         l_geom_len=10000, l_geom_area=10000000,
         label_size=8, l_bold=False, p_min=0, p_new=9,
         #l_partials=True, l_force=True,
         #l_restrict_named=l_restrict_names_expressway
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True,
         #l_geom_len=10000, l_geom_area=50000000,
         #l_geom_len=5000, l_geom_area=10000000,
         label_size=8, l_bold=False, p_min=0, p_new=8,
         #l_restrict_named=l_restrict_names_highway_06
         #l_restrict_stack_ids=l_restrict_stack_ids_highway_06
         l_only_bike_facils=True,
         #l_partials=True, l_force=True,
l_minfeaturesize='auto',

# 2013.12.05: DEV cxpx to help test l_only_bike_facils.
#             But this is almost just as slow as calling ./tilecache_update.py.
#
# This is what flashclient uses:
# http://localhost:8088/tilec?&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=minnesota-2500677-bikeways&SRS=EPSG:26915&BBOX=262144,4849664,393216,4980736&WIDTH=256&HEIGHT=256&FORMAT=image/png
#
# This is the metatile that tilecache_seed uses, except not 5120x5120 or it's a
# different zoom you see (because of the bbox... so it's not really what seed
# uses).
# http://localhost:8088/wms?schema=minnesota&map.projection=EPSG:26915&layer_skin=bikeways&layers=standard&styles=&service=WMS&width=256&format=image/png&request=GetMap&height=256&srs=EPSG:26915&version=1.1.1&bbox=262144,4849664,393216,4980736

         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=1, pen_gutter=0,
#         do_draw=False, pen_width=1, pen_gutter=0,
# FIXME: In the metro area, it's a mess. Can we just draw the longer majors?
d_geom_len=10000, #d_geom_area=3000000,
         do_label=False,
         #l_geom_area=1000000,
         label_size=8, l_bold=False, p_min=0, p_new=7,
         #l_restrict_named=l_restrict_names_major_road
         ))

   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=7,
      #do_draw=True, pen_width=1, pen_gutter=0,
do_draw=True, pen_width=2, pen_gutter=0,
d_geom_len=0, d_geom_area=3000000,
      do_label=True,

      label_size=8, l_bold=False, p_min=0, p_new=10,

      #l_geom_len=10000, l_geom_area=50000000,
      #l_geom_len=2500, l_geom_area=1000000,
#l_geom_len=10000,
      #l_partials=True, l_force=True,

# FIXME: [lb] really doesn't get MapServer sometimes.
#        Without force, we get zero bike trails except Willard Munger.
#        But with force, we get two Luce Lines (overlapping) and
#        one Gateway, and one Sunrise Prairie, and overlapping
#        Willard Mungers. And I'm out of time and patience to keep
#        messing with this!
#l_force=True,
# Is the problem that MapServer tosses *both* labels when they overlap?!
      l_force=True,
      l_restrict_stack_ids=l_restrict_stack_ids_major_trail_07,
      l_outlinewidth=5,

      l_strip_trail_suffix=True,

      #l_minfeaturesize='auto',
      l_minfeaturesize='1',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=7,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=2, pen_gutter=0,
         do_label=False, label_size=2))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=False, label_size=3))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=False, label_size=3))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=7,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=7,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=0))

   # *** Zoom: 8.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=8, p_min=0, p_new=9,
         # Use min. label geom len. so metro area isn't inundated with labels.
         l_geom_len=100000, l_geom_area=0,
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=8,
#         do_draw=True, pen_width=2, pen_gutter=0,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8, p_min=0, p_new=8,
         l_minfeaturesize='auto',
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False, label_size=0, p_min=0, p_new=7,
         l_geom_len=0, l_geom_area=1000000,
         ))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=8,
      do_draw=True, pen_width=2, pen_gutter=0,
      do_label=True, label_size=8, p_min=0, p_new=10,
      #l_geom_len=0, l_geom_area=0,
      #l_partials=True, l_force=True,
      l_force=True,
      l_restrict_stack_ids=l_restrict_stack_ids_major_trail_08,
      l_minfeaturesize='1',
      l_strip_trail_suffix=True,
      l_outlinewidth=5,
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=8,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=2, pen_gutter=0,
         do_label=False, label_size=2))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=False, label_size=3))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=False, label_size=3))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=8,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=8,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=0))

   # *** Zoom: 9.

   # See also: tile_skin.Tile_Pen.zoom_level_meters_per_label_char,
   # which tries to make sure we only label lines where the label
   # will fit the line and not be longer than the line; this is in
   # lieu of l_geom_len and l_geom_area.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=8, p_min=0, p_new=9,
         # Use min. label geom len. so metro area isn't inundated with labels.
         l_geom_len=100000, l_geom_area=0,
         l_minfeaturesize='auto',
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=8, p_min=0, p_new=8,
         l_minfeaturesize='auto',
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8, p_min=0, p_new=7,
         l_minfeaturesize='auto',
         ))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=9,
      do_draw=True, pen_width=1, pen_gutter=0,
      # 2013.12.04: Ideally, Major Trail would be a thing, but Major Trail
      #             is not applied anywhere...
      do_label=True, label_size=8, p_min=0, p_new=10,
      l_strip_trail_suffix=True,
      l_minfeaturesize='auto',
      l_outlinewidth=5,
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=9,
         do_draw=False, pen_width=1, pen_gutter=0,
         do_label=False, label_size=8))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=2, pen_gutter=0,
         do_label=False, label_size=2))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=False, label_size=3))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=False, label_size=3))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=9,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=9,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=0))

   # *** Zoom: 10.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=6, pen_gutter=0,
         do_label=True, label_size=8, p_min=0, p_new=9,
         l_minfeaturesize='auto',
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=4, pen_gutter=0,
         do_label=True, label_size=8, p_min=0, p_new=8,
         l_minfeaturesize='auto',
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=0, p_min=0, p_new=7,
         l_minfeaturesize='auto',
         ))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=10,
      do_draw=True, pen_width=2, pen_gutter=0,
      do_label=True, label_size=8, p_min=0, p_new=10,
      l_strip_trail_suffix=True,
      l_minfeaturesize='auto',
      l_outlinewidth=5,
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=10,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=4, pen_gutter=0,
         do_label=False, label_size=4))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=4, pen_gutter=0,
         do_label=False, label_size=4))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=10,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=6, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=10,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))

   # *** Zoom: 11.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=7, pen_gutter=0,
         do_label=True, label_size=7,
         l_minfeaturesize='auto',
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=5,
         l_minfeaturesize='auto',
         ))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=2, pen_gutter=0,
         do_label=True, label_size=8,
         l_minfeaturesize='auto',
         ))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=11,
      do_draw=True, pen_width=2, pen_gutter=0,
      do_label=True, label_size=8,
      #l_strip_trail_suffix=True,
      l_minfeaturesize='auto',
      l_outlinewidth=5,
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   # This one is tough: I kind of like seeing all the streets, but it's
   # borderline (or toppled over the edge) cluttered. I'm leaning on leaving
   # it: seeing the smaller streets wiggle around will help route-builders.
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      #Tile_Pen(zoom_level=11,
      #   do_draw=False, pen_width=0, pen_gutter=0,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=5))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=5, pen_gutter=0,
         do_label=True, label_size=5))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=11,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=7, pen_gutter=0,
         # 9 is rather small...
         #do_label=True, label_size=9))
         #do_label=True, label_size=10))
         do_label=True, label_size=11))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=11,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))

   # *** Zoom: 12.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_gutter=4, pen_width=6,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_gutter=2, pen_width=4,
         do_label=True, label_size=8))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=12,
      do_draw=True, pen_width=2, pen_gutter=0,
      do_label=True, label_size=8,
      l_minfeaturesize='auto',
      l_outlinewidth=5,
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=6, pen_gutter=0,
         do_label=True, label_size=6))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=6, pen_gutter=0,
         do_label=True, label_size=6))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=12,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=12,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))

   # *** Zoom: 13.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_gutter=5, pen_width=7,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_gutter=4, pen_width=6,
         do_label=True, label_size=8))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=13,
      do_draw=True, pen_gutter=1, pen_width=3,
      do_label=True, label_size=8,
      l_minfeaturesize='auto',
      l_outlinewidth=5,
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   # FIXME: [lb] is not sure these should be labeled.
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=2, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=4, pen_gutter=0,
         do_label=True, label_size=4))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=13,
         do_draw=False, pen_width=0, pen_gutter=0,
         do_label=False, label_size=0))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=9, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=13,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))

   # **************************************************************************
   # These zooms are (were?) used on mobile, but flashclient draws vectors at
   # these levels.
   # DOCUMENT_ME: What are the android vector levels?

   # *** Zoom: 14.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=9, pen_gutter=0,
         do_label=True, label_size=11))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_gutter=8, pen_width=8,
         do_label=True, label_size=10))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_gutter=6, pen_width=7,
         do_label=True, label_size=8))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=14,
      do_draw=True, pen_width=4, pen_gutter=0,
      do_label=True, label_size=8,
      l_minfeaturesize='auto',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=4, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=4, pen_gutter=0,
         do_label=True, label_size=4))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=10, pen_gutter=0,
         do_label=True, label_size=10))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=10, pen_gutter=0,
         do_label=True, label_size=10))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=14,
         do_draw=False, pen_width=6, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=10, pen_gutter=0,
         do_label=True, label_size=10))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=14,
         do_draw=True, pen_width=3, pen_gutter=0,
         do_label=True, label_size=3))

   # *** Zoom: 15.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=13, pen_gutter=0,
         do_label=True, label_size=13))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=12, pen_gutter=0,
         do_label=True, label_size=12))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=10, pen_gutter=0,
         do_label=True, label_size=10))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=15,
      do_draw=True, pen_width=9, pen_gutter=0,
      do_label=True, label_size=8,
      l_minfeaturesize='auto',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=9, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=6, pen_gutter=0,
         do_label=True, label_size=6))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=12, pen_gutter=0,
         do_label=True, label_size=12))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=12, pen_gutter=0,
         do_label=True, label_size=12))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=15,
         do_draw=False, pen_width=9, pen_gutter=0,
         do_label=True, label_size=9))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=11, pen_gutter=0,
         do_label=True, label_size=11))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=15,
         do_draw=True, pen_width=6, pen_gutter=0,
         do_label=True, label_size=6))

   # *** Zoom: 16.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=14, pen_gutter=0,
         do_label=True, label_size=14))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=12, pen_gutter=0,
         do_label=True, label_size=12))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=16,
      do_draw=True, pen_width=11, pen_gutter=0,
      do_label=True, label_size=11,
      l_minfeaturesize='auto',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=11, pen_gutter=0,
         do_label=True, label_size=11))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=6, pen_gutter=0,
         do_label=True, label_size=6))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=14, pen_gutter=0,
         do_label=True, label_size=14))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=14, pen_gutter=0,
         do_label=True, label_size=14))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=16,
         do_draw=False, pen_width=11, pen_gutter=0,
         do_label=True, label_size=11))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=12, pen_gutter=0,
         do_label=True, label_size=12))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=16,
         do_draw=True, pen_width=9, pen_gutter=0,
         do_label=True, label_size=9))

   # *** Zoom: 17.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=17, pen_gutter=0,
         do_label=True, label_size=17))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=14, pen_gutter=0,
         do_label=True, label_size=14))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=17,
      do_draw=True, pen_width=13, pen_gutter=0,
      do_label=True, label_size=13,
      l_minfeaturesize='auto',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=13, pen_gutter=0,
         do_label=True, label_size=13))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=17,
         do_draw=False, pen_width=12, pen_gutter=0,
         do_label=True, label_size=12))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=13, pen_gutter=0,
         do_label=True, label_size=13))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=17,
         do_draw=True, pen_width=12, pen_gutter=0,
         do_label=True, label_size=12))

   # *** Zoom: 18.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=19, pen_gutter=0,
         do_label=True, label_size=19))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=18,
      do_draw=True, pen_width=15, pen_gutter=0,
      do_label=True, label_size=15,
      l_minfeaturesize='auto',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   #
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=18,
         do_draw=False, pen_width=13, pen_gutter=0,
         do_label=True, label_size=13))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=14, pen_gutter=0,
         do_label=True, label_size=14))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=18,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))

   # *** Zoom: 19.

   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Expressway,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=19, pen_gutter=0,
         do_label=True, label_size=19))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Highway,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Road,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   #
   # 2013.12.05: No line segments are marked Major Trail so both Bike Trail and
   #             Major Trail use the same pen.
   bike_trail_pen = Tile_Pen(zoom_level=19,
      do_draw=True, pen_width=15, pen_gutter=0,
      do_label=True, label_size=15,
      l_minfeaturesize='auto',
      )
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Major_Trail,
                                 bike_trail_pen)
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Bike_Trail,
                                 bike_trail_pen)
   # 
   skin_bikeways.assign_tile_pen(Tile_Skin.gfl_local_road_et_al,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   #
   skin_bikeways.assign_tile_pen(byway.Geofeature_Layer.Railway,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=False))

   skin_bikeways.assign_tile_pen(region.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=8, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Open_Space,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Water,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Waterbody,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   skin_bikeways.assign_tile_pen(terrain.Geofeature_Layer.Flowline,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=1, pen_gutter=0,
         do_label=True, label_size=8))
   #
   skin_bikeways.assign_tile_pen(waypoint.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=19,
         do_draw=False, pen_width=14, pen_gutter=0,
         do_label=True, label_size=14))
   #
   skin_bikeways.assign_tile_pen(route.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=15, pen_gutter=0,
         do_label=True, label_size=15))
   #
   skin_bikeways.assign_tile_pen(track.Geofeature_Layer.Default,
      Tile_Pen(zoom_level=19,
         do_draw=True, pen_width=18, pen_gutter=0,
         do_label=True, label_size=18))

# ***

if (__name__ == '__main__'):
   pass


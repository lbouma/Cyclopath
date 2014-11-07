/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Configuration and defaults
//
// NOTE: This file is for instance-wide configuration, i.e., things you don't
//       need to customize when you install Cyclopath (use Conf_Instance.as
//       for that).

package {

   import flash.utils.Dictionary;
   import mx.collections.ArrayCollection;
   import mx.utils.StringUtil;

   import assets.skins.*;
   import grax.Access_Level;
   import items.utils.Travel_Mode;
   import utils.misc.Logging;
   import views.base.App_Mode_Base;
   import views.panel_routes.Route_Viz;
   import views.panel_routes.Route_Viz_Color_Map;

   public class Conf {

      // *** Static class variables

      // The logger cannot be specified yet, since Conf gets loaded first.
      protected static var log:Logging = null;

      // *** Instance-specific config variables
      //
      // These values are left null here and assigned during main.init() via
      // instance_config() below. The actual values for each variable are
      // defined in Conf_Instance.

      // SYNC_ME: These vars match the Objects in Conf_Instance.as, e.g.,
      //          see: public static const config_mn.

      // The name of this instance.
      public static var instance_name:String;

      // EPSG SRS identifier
      public static var srid:int;

      // Defaults for these map parameters.
      public static var map_zoom:int;
      public static var map_center_x:Number;
      public static var map_center_y:Number;

      // WMS settings.
      public static var wms_url_base:String;
      public static var wms_url_aerial:String;

      // Photo layers available for aerial viewing
      [Bindable] public static var photo_layers:ArrayCollection;

      // Multimodal routing properties
      [Bindable] public static var transit_services:Object;

      // example address for Address_Example
      [Bindable] public static var address_example:String;

      // A welcome message on boot.
      public static var welcome_popup:Class;

      // welcome text in help panel
      [Bindable] public static var welcome_text:String;

      public static var instance_info_email:String;

      public static var cheater_branch_sid:int;

      // *** Standard config variables

      // Interface
      public static var external_interface_okay:Boolean = true;

      // GWIS
      public static const gwis_url:String = '/gwis?';
      public static const gwis_version:String = '3';

      // URLs
      public static const help_url:String = 'http://cyclopath.org/wiki';
      public static const maint_img_url:String = 'misc/maintenance.png';
      public static const wms_url_cyclopath:String = '/tilec?';

      // Zoom limits
      public static const zoom_max:int = 19;
      //public static const zoom_min:int = 9;
      //public static const zoom_min:int = 7;
      //public static const zoom_min:int = 6;
      public static const zoom_min:int = 5;

// BUG nnnn: Show vectors at higher zooms when outstate, otherwise
//           it's ridiculously hard to edit county roads...
//
//
      // At zoom levels less than or equal to this value, fetch raster tiles
      // instead of vectors.
      public static const raster_only_zoom:int = 13;
      // For Statewide, seeing vectors at higher zooms is nice, but in the city
      // it can take a while to load the viewport.
      //public static const raster_only_zoom:int = 11;

      // Don't zoom closer than this when using Map_Canvas.lookat()
      public static const zoom_max_lookat:int = 17;

      // Only draw the node widget at this zoom level or higher (closer).
      public static const node_widget_zoom:int = 17;

      // Only draw the direction arrows at this zoom level or higher
      public static const direction_arrow_zoom:int = 15;

      // Only draw point labels at this zoom level or higher
      public static const point_label_zoom:int = 15;

      // Minimum distance (in m) that activates the save reminder.  After each
      // pop-up, it expand to be less 'nagging'.
      public static const save_reminder_distance:int = 1500;

      // Map Modes
      // FIXME: [lb] Are these names that the client displays?
      //             If not, they do not belong here, i.e., they're not values
      //             a dev would change, so we should use a simple Enum-type
      //             class, like Access_Style. Using a class means the value is
      //             more strongly typed (the compiler will complain if you get
      //             the enum name wrong, but it won't complain if you get a
      //             string name wrong). And ctags or code-completion might
      //             work better with an enum rather than string names in code.
      //
      // FIXME: See G.map.rev_workcopy and G.map.rev_viewport:
      //        We've already got a way to determine this... except for
      //        "Feedback" mode. [lb] would rather not have two constructs
      //        that do the same thing.
      public static const map_mode_normal:String = 'Normal';
      public static const map_mode_historic:String = 'Historic';
      public static const map_mode_feedback:String = 'Feedback';

      // Options for view stack controls
      public static const view_stack_depth:int = 10;
      // Time between 'large' view ops before updating stack (ms)
      public static const view_stack_delay:int = 3000;
      // Minimum change in canvas space necessary for stack update (pixels)
      public static const view_stack_pan_min:int = 100;

      // These define fetch and discard behavior (See the technical docs for
      // details.) Units: pixels.
      //
      // Real values -- these small values are to prevent unnecessary fetches
      // with the small pans that occur incidentally with clicking around for
      // other purposes.
      // BUG nnnn: 2013.05.22: Are these pixels? 12 seems really small for a
      //           buffer... if you pan, it doesn't feel like we retain a lot
      //           of the map, especially compared to other Web maps.
      public static const fetch_hys:int = 12;
      public static const discard_hys:int = 12;
      // Debug values -- DEVS can use these to find ideal values for *_hys.
      //public static const fetch_hys:int = -100;
      //public static const discard_hys:int = 75;

      // How frequently to do intermediate fetches while panning.
      //
      // BUG 0056: This must remain at infinity for the time being, for
      //           performance reasons.
      public static const drag_update_interval:int = int.MAX_VALUE;

      // Maximum number of characters displayable in a label for a point.
      // If larger, it's shortened and shows '...'.
      public static const max_point_label_len:int = 25;

      // When editing byways, snap dragged endpoints if within this many
      // pixels of an intersection.
      public static const byway_snap_radius:int = 12;

      // Byway endpoints within this distance are assumed to be equal.
      // 2013.07.11: C'mon, what're the units? Meters? Node tolerance
      // is one decimeter, or 0.1 meters. See pyserver/conf.py and
      // reasonings in the code and docs. Basically, source data is
      // not that accurate, and 10 cm seems like plenty of real world
      // space for an intersection, considering that even singletrack
      // is at least as wide as a tire.
      //public static const byway_equal_thresh:Number = 0.001;
      // 2013.07.11: [lb] thinks this is meters. Make it 0.1 of them.
      public static const byway_equal_thresh:Number = 0.1;

      // Ignore leading and trailing whitespace within element text values
      // when parsing XML.
      XML.ignoreWhitespace = true;

      // Force users to log in in order to use the system.
      public static const force_login:Boolean = false;

      // Navigation panel config. See also Map_Canvas.pan().
      public static const pan_step_small:Number = 0.25;
      public static const pan_step_large:Number = 0.5;

      // Latest activity pageinator parameters.
      public static const recent_changes_list_size:int = 20;

      // Latest activity pageinator parameters.
      public static const item_watchers_list_size:int = 20;

      // Some button colors.
      public static const button_fill_light:int = 0xffffff;
      public static const button_fill_dark:int = 0xcccccc;
      public static const dark_button_fill_light:int = 0xa1a3a6;
      public static const dark_button_fill_dark:int = 0x6b6c6f;
      public static const save_button_fill_light:int = 0xaaff33;
      public static const save_button_fill_dark:int = 0x88cc11;
      public static const button_highlight:int = 0x009dff;
      // Adobe defaults (or maybe that's, Flex SDK defaults).
      public static const flex_button_fill_light:int = 0xE6EEEE;
      public static const flex_button_fill_dark:int = 0xFFFFFF;

      // Discussion grid colours.
      public static const grid_alt_colours:Array = [0xffffff, 0xeeeeee,];

      // *** Debugging variables

      // Whether or not to draw the fetch regions on the map. This is only
      // useful for double-checking your bounding box maths.
      public static const debug_draw_fetch_regions:Boolean = false;

      // *** Debugging Group Panels

      // NOTE: 2011.03.22 / Normally [lb]'d advocate creating a branch for code
      //       that's not going to production, but in this case, I'm using
      //       it while developing, but I also need to disable it for user
      //       testing. I'll move this to a branch someday soon. Promises.
      public static const debug_trial_bug_2077_group_panels:Boolean = false;

      // **** Debug Log/Trace Facility

      // If using the m4_DEBUG_TIME macros to hunt down time-consuming
      // operations, set this to the threshold that the macro uses to decide
      // whether or not to report an operation's elapsed time.
      public static const debug_time_threshold_ms:int = 10;

      // ***

      // For heavy operations, set the frequency that our one and only
      // application thread should preempt itself so the Flash plugin can
      // handle the mouse and otherwise appear responsive to the user.
      // FIXME: [lb] is still not sure the optimal value.
      public static const callLater_take_a_break_threshold_ms:int = 333;
      //public static const callLater_take_a_break_threshold_ms:int = 667;

      // ***

      // Send log message if this many milliseconds elapse with no new events.
      public static const gwis_log_pause_threshold:int = 3000;

      // Send a log message if this many events accumulate.
      public static const gwis_log_count_threshold:int = 64;

      // Send a 'heartbeat' log message every 3 minutes.
      public static const gwis_log_heartbeat_interval:int = 1000 * 180;

      // Check server for status message every this number of seconds.
      public static const gwis_pyserver_message_interval:Number = 60;

      // ***

      // Height and width of tiles in pixels (must match server config).
      public static const tile_size:int = 256;

      // Number of commands that can be undone.
      public static const undo_stack_depth:int = 0;

      // Some UI strings.
      public static const error_title:String = 'Error';

      // Map_Key slide time (the amount of time spent sliding up or down when
      // shown).
      public static const map_key_slide_time:Number = 334;

      // The amount of delay before the byway tooltip is displayed after
      // a mouse over event.
      public static const byway_tooltip_time:Number = 240;

      // Time to wait on hover before tool tipping a route on the map (in ms).
      public static const route_path_tooltip_delay:Number = 366;

      // Delay before auto-updating a route's path.
      //public static const route_path_update_delay:Number = 350;
      public static const route_path_update_delay:Number = 667;

      // Delay time before preemptively geocoding the from or to address.
      public static const route_pregeocode_delay:Number = 1894;

      // On the route details panel, when user clicks the circle with the
      // letter to the left of the route stop name in the destinations list,
      // how long to wait to let user drag entry, otherwise, click to lookat.
      public static const route_stop_drag_delay:Number = 350;

      // Length of typing pause (ms) before recording Command_Text_Edit command
      public static const text_edit_record_delay:Number = 500;
      // Maximum time (ms) between clicks to generate a double click. Must be
      // kind of long to compensate for selections taking too long (the 2nd
      // click is delayed until the selection is complete).
      // MEH: Test this: 400 msec. seems a bit high?
      //      2013.02.15: [lb] I guess I haven't noticed any issue recently.
      //                       Perhaps the issue was fixed by something else.
      public static const double_click_time:Number = 400;

      // Number of pixels to add to the width/height of a label.
      public static const map_label_width_padding:Number = 10;
      public static const map_label_height_padding:Number = 4;

      // How long user has to hover over context menu symbol before
      // automatically showing context menu.
      public static const context_menu_hover_timeout:Number = 400;

      // *** Map Visualization: *View* (Style) Config

      // SYNC_ME: Search: Application background color. Conf.as and main.css.
      public static const application_background_color:int = 0x3a3a3c;

      // We could load the list of skins from the server or parse through the
      // assets/skins directory, or we could just hard-code the available skins
      // here.
      public static const map_sknnng_skins:Array = [
         {_name: 'skin_bikeways',
          label: 'Bikeways Inventory',
          skin_class: Skin_Bikeways},
         {_name: 'skin_classic',
          label: 'Cyclopath Classic',
          skin_class: Skin_Classic},
         ];
      public static var tile_skin:Class = Skin_Bikeways;

      // Drawing parameters that aren't fetched from the server.
      // FIXME/MAGIC_NUMBERS: Some of these duplicate server parameters...
      //                      [lb] thinks... do they match the TileCache skins?
      // CcpV1: public static const background_color:int = 0xd6c5b4;
      public static function get background_color() :int
      {
         // FIXME: [lb] is using dashon_color because there are just a few
         //        'draw_class' entries and I didn't want to have to make a new
         //        class, like another Attr_Pen... though maybe we should.
         return tile_skin.attr_pens['draw_class']['background']
                                                ['dashon_color'];
      }
      public static const disabled_alpha:Number = 0.4;

      // FIXME/BUG nnnn: Skin these?
      //        These values maybe should go in, e.g., skin_bikeways.py.
      // EXPLAIN: private_colors[0] is never accessed? Maybe was used for
      //          something in the earlier days of CcpV1.
      public static const private_colors:Array = [0xeed5d2, 0xffe4e1,];
      public static const private_color:int = private_colors[1];
      public static const shared_colors:Array = [0xe1ffe4, 0xd1ffd4,];
      public static const shared_color:int = shared_colors[0];
      public static const color_access_levels:Array = new Array();
      // [lb] isn't sold on hard-coding lots of color values in code. But it's
      // not like using a CSS file would be any easier for us. In a sense,
      // Conf.as is really just a style sheet.
      color_access_levels[Access_Level.owner] = 0xffe4e1;
      color_access_levels[Access_Level.editor] = 0xa1ffb3;
      color_access_levels[Access_Level.viewer] = 0xa0b3cc;

      //
      public static const comment_color:int = 0x781ae5;
      public static const comment_color_diffing:int = 0x9988aa;
      public static const comment_color_feedback:int = 0xbdbdbd;
      public static const comment_width:Number = 2;
      // SYNC_ME: flashclient/Conf.as::route_color
      //          mapserver/skins/skin_bikeways.py::assign_feat_pen(route...
      //public static const route_color:int = 0x86d0c7;
      public static var route_color:int = 0x2f852a;
      public static const route_alpha:Number = 1.0;
      public static const route_width:Number = 5;
      public static const selection_color:int = 0x0000ff;
      public static const selection_glow_radius:Number = 6;
      public static const selection_line_width:Number = 2;
      public static const selection_elbow_size:Number = 6;
      public static const avoided_tag_color:int = 0xc60018;
      public static const node_widget_color:int = background_color;

      // The Map_Label background color.
      public static const label_halo_color:int = background_color;
      public static const label_halo_route:int = 0xABFF00;

      public static const branch_conflict_color:int = 0xe9e9e9;
      // Route Sharing (new route_stop table) colors.
      public static const route_edit_color:int = 0x3563d5;
      public static const route_transit_stop_color:int = 0x8e80ff;

      //
      public static const path_highlight:String = 'Path_Highlight';
      public static const mouse_highlight:String = 'Mouse_Highlight';
      // FIXME: The attachment_highlight is also used on tags and attrs,
      //        if [lb] understands its usage correctly. Also by threads,
      //        via Widget_Attachment_Place_Widget.
      public static const attachment_highlight:String = 'Annot_Highlight';
      public static const attachment_hover_highlight:String =
                                                      'Annot_Hover_Highlight';
      public static const resolver_highlight:String = 'Sel_Resolve_Highlight';

      //
      public static const highlight_alpha:Number = 0.7;
      public static const path_highlight_color:int = 0x00ff44;
      public static const mouse_highlight_color:int = 0x00ff44;
      public static const attc_hover_highlight_color:int = 0x44ff00;
      public static const attc_highlight_color:int = 0x00ff44;
      public static const resolver_highlight_color:int = 0x00ff44;
      public static const vertex_highlight_color:int = 0x00ff44;
      public static const route_stop_highlight_color:int = 0xede74a;

      //
      public static const change_color:int = 0x00ff44;
      public static const annotation_change_color:int = 0x44ff88;

      //
      public static const vgroup_old_color:int = 0xff0000;
      public static const vgroup_new_color:int = 0x0000ff;
      public static const vgroup_move_old_color:int = 0xff8888;
      public static const vgroup_move_new_color:int = 0x8888ff;

      public static const vgroup_move_both_color:int = 0x88ff88;
      public static const vgroup_move_arrow_color:int = 0x777777;

      public static const vgroup_static_color:int = 0xdddddd;
      // The dark static color is used when diffing routes.
      public static const vgroup_dark_static_color:int = 0xcccccc;

      //
      public static const vgroup_static_label_color:int = 0x666666;
      public static const aerial_label_color:int = 0x666666;

      //
      public static const point_widget_bgcolor:int = 0xffffc0;
      public static const point_widget_border_color:int = 0x000000;

      //
      public static const loading_widget_bgcolor:int = 0xffffc0;
      public static const loading_widget_border_color:int = 0x000000;

      // Colors used by route reactions.
      public static const reac_widget_bgcolor:int = 0xffffc0;
      public static const reac_widget_border_color:int = 0xaaaaaa;
      public static const reac_bar_bgcolor:int = 0xffffc0;
      public static const reac_bar_border_color:int = 0xaaaaaa;

      // Alert box.
      public static const alert_box_fgcolor:int = 0xff0000;
      public static const alert_box_bgcolor:int = 0xffcccc;
      public static const alert_box_border_color:int = 0xff0000;

      // Byway connectivity highlight drawing parameters. Make sure that you
      // don't configure the width to descend below zero.
      //
      // Initial width of the highlight.
      public static const byway_connectivity_width_start:Number = 3;
      // Arithmetic decrement to the width applied at each step outward.
      public static const byway_connectivity_width_decrement:Number = 1.5;
      // Number of outward steps to take.
      public static const byway_connectivity_depth:Number = 1;
      // Color of the highlight.
      public static const byway_connectivity_color:int = 0x00ff44;
      // Size of the squares at start/end vertices.
      public static const byway_connectivity_vertex_size:int = 4;

      // Node builder highlight color.
      public static const node_endpoint_builder_color:int = 0x000000;

      // Search Results colors.
      public static const search_result_color:int = 0xc96c5e;
      public static const search_result_border_color:int = 0x000000;
      public static const search_result_highlighted_color:int = 0xf8e399;
      public static const search_result_highlighted_border_color:int
                                                                  = 0xf8e399;

      // Node builder config.
      public static const nb_sensitivity:int = 25;
      public static const nb_dist_t_limit:int = 15;
      public static const nb_circle_max_radius:int = 250;
      public static const nb_circle_dot_radius:int = 5;
      public static const nb_byway_short_length:int = 25;  // meters

      // Byway rating colors.
      // DB_SYNC_TO: Make sure these stay consistent with tilecache_update.py
      //             generic colors.
      public static const rating_colors_generic:Object =
         {
         0: 0xceb29f,
         1: 0xb5947d,
         2: 0x96776b,
         3: 0x725a49,
         4: 0x423327
         };
      // User colors.
      public static const rating_colors_user:Object =
         {
         0: 0xffc597,
         1: 0xeca778,
         2: 0xe6894b,
         3: 0xe06c1e,
         4: 0xa85117
         };

      //
      public static const shadow_color_user_rated:int = 0xf2f22a;

      // One-way byway directional arrow drawing parameters.
      // Distance between multiple arrows on a single byway.
      public static const byway_arrow_separation:Number = 200;
      // Length of the entire arrow (including tip and tail)
      public static const byway_arrow_length:Number = 15;
      public static const byway_arrow_color_light:int = background_color;
      public static const byway_arrow_color_dark:int
         = rating_colors_generic[3];

      // Color of ratings-needed highlight.
      public static const rating_needed_color:int = 0x00c4ff;

      // Enabling/disabling the Region of the Day feature.
      public static var region_of_the_day:Boolean = false;

      // Colour of the region of the day.
      public static var region_of_the_day_color:Number = 0x2d63de;

      // Route stop name presented to user for points clicked in map.
      //public static const route_stop_map_name:String ='Point entered in map';
      public static const route_stop_map_name:String = 'Point on map';

      // *** Route Viz

      // IMPORTANT: When changing the labels also change the references in the
      //            color map class. The color map functions reference the
      //            labels in the mapping functions. It's a hack, but it cleans
      //            up the map syntax.

      //
      public static var default_route_colors:Array =
      [
         { 'label': 'Normal', 'hex': route_color}
      ];

      //
      public static var rating_route_colors:Array =
      [
         { 'label': 'Poor',        'hex': 0x86d0c7 },
         { 'label': 'Fair',        'hex': 0x649791 },
         { 'label': 'Good',        'hex': 0x517871 },
         { 'label': 'Excellent',   'hex': 0x3e5a55 }
      ];

      //
      // 2012.05.07: Rename 'Bicycle Path' to 'Bike Trail'.
      //   Why?
      //   1. Google results for "bicycle path": 1,050,000;
      //                       for "bike trail": 7,480,000.
      //   2. Both path and trail can mean unpaved or paved surface for
      //      bicycling. Bike trail seems to be more commonly used when talking
      //      about bike facilities.
      //        [1] https://en.wikipedia.org/wiki/Path
      //        [2] https://en.wikipedia.org/wiki/Trail#Bicycle_trails
      //   3. Even the State of MN calls them trails:
      //        [3] http://www.dnr.state.mn.us/state_trails/index.html
      //   4. And landonb's favorite reason for renaming, "Bike Trail" is two
      //      characters shorter than "Bicycle Path".
      //   5. Since we now have "Major Trail", which sounds better than
      //      "Major Path".
      public static var byway_layer_route_colors:Array =
      [
         { 'label': 'Major Road',            'hex': 0xb1bdda },
         { 'label': 'Local Road',            'hex': 0x8795b2 },
         { 'label': 'Sidewalk',              'hex': 0x5e6e85 },
         { 'label': 'Bike Trail',            'hex': 0x2d3743 },
         // FIXME: Fix the hex on Major Trail. Same in skin_bikeways.py.
         { 'label': 'Major Trail',           'hex': 0x2d3743 }
      ];

      //
      public static var grade_route_colors:Array =
      [
         // [lb] doesn't mind the word 'Steep' so much as how much
         //      screen real estate it consumes.
         //{ 'label': 'Steep Uphill',          'hex': 0x9f554d },
         { 'label': 'Uphill',                'hex': 0x9f554d },
         { 'label': 'Moderate Uphill',       'hex': 0xc96c5e },
         { 'label': 'Slight Uphill',         'hex': 0xf58a72 },
         { 'label': 'Level',                 'hex': 0xe0d729 },
         { 'label': 'Slight Downhill',       'hex': 0xa3c041 },
         { 'label': 'Moderate Downhill',     'hex': 0x768f3a },
         //{ 'label': 'Steep Downhill',        'hex': 0x56672e }
         { 'label': 'Downhill',              'hex': 0x56672e }
      ];

      //
      public static var bonus_or_penalty_tagged_route_colors:Array =
      [
         { 'label': 'Normal',                'hex': route_color },
         { 'label': 'Bonus/Penalty',         'hex': 0x7457a5 }
      ];

      //
      public static var travel_mode_route_colors:Array =
      [
         { 'label': 'Bicycle',               'hex': 0xe0d729 },
         { 'label': 'Bus/Train',             'hex': 0x2d3743 }
      ];

      // The first argument to Route_Viz is the database id.

      //
      public static var route_vizs:Array =
         [
         // SYNC_ME: Search: viz table.
         new Route_Viz(
            1, 'Normal', default_route_colors,
               Route_Viz_Color_Map.DEFAULT),
         new Route_Viz(
            2, 'Rating', rating_route_colors,
               Route_Viz_Color_Map.RATING),
         new Route_Viz(
            3, 'Byway Type', byway_layer_route_colors,
               Route_Viz_Color_Map.BYWAY_LAYER),
         new Route_Viz(
            4, 'Slope', grade_route_colors,
               Route_Viz_Color_Map.GRADE),
         // 2013.03.19: Renamed 'Bonus/Penalty' to 'Tag Preference'.
         new Route_Viz(
            5, 'Tag Preference', bonus_or_penalty_tagged_route_colors,
               Route_Viz_Color_Map.BONUS_OR_PENALTY_TAGGED),
         new Route_Viz(
            6, 'Transit Type', travel_mode_route_colors,
               Route_Viz_Color_Map.TRANSIT_TYPE)
         ];

      // Route Reaction/Feedback Drag colors (Bug 2714).
      //
      public static const route_feedback_old_outline:int = 0xff0000;
      public static const route_feedback_old_color_selected:int = 0xff3333;
      public static const route_feedback_old_color:int = 0xffbbbb;
      //
      public static const route_feedback_new_outline:int = 0x000077;
      public static const route_feedback_new_color_selected:int = 0x3333ff;
      public static const route_feedback_new_color:int = 0xbbbbff;

      // Direction parameters
      // Minimum length between vertices in a block to generate a direction
      // vector for computing turn angles.
      public static const route_step_dir_length:Number = 5;

      // Variables to access the components of bearing.
      public static const r_name:int = 0; // name if max_angle is relative
      public static const c_name:int = 1; // name if max_angle is on compass
      public static const max_angle:int = 2; // max angle for category
      public static const image:int = 3; // image used for category

      // Bearings for route directions. START, END, and WAYPOINT are included
      // for easy html generation. These should not be reordered. (START must
      // always be the 2nd to last element and END must be the last element.)
      public static const bearing:Array =
         [
            // SYNC_ME: Search: cue png (htdocs/main.html flashclient/Conf.as).
            ['Right', 'E',
               50, '/assets/img/misc_right.png'],
            ['Slight right', 'NE',
               80, '/assets/img/misc_right.png'],
            ['Forward', 'N',
               100, '/assets/img/misc_up.png'],
            ['Slight left', 'NW',
               130, '/assets/img/misc_left.png'],
            ['Left', 'W',
               190, '/assets/img/misc_left.png'],
            ['Sharp left', 'SW',
               250, '/assets/img/misc_left.png'],
            ['Backward', 'S',
               290, '/assets/img/misc_down.png'],
            ['Sharp right', 'SE',
               350, '/assets/img/misc_right.png'],
            ['Right', 'E',
               360, '/assets/img/misc_right.png'],
            // Don't reorder these:
            // Also, note neg. angles, this
            // lets angle classification work.
            ['Transit stop', 'Transit stop',
               -1, '/assets/img/route_stop_transit.png'],
            // SYNC_ME: The route_stop_bicycle.png file is only used/loaded by
            //          main.html (to use on the printable cue sheet; see
            //          Direction_Step.html_text).
            // BUG nnnn: 2012.09.26: CcpV1 main.html may not be setting the png
            //                       correctly (didn't use .src = ).
            ['Bicycle stop', 'Bicycle stop',
               -1, '/assets/img/route_stop_bicycle.png'],
            // CAVEAT: Do not change the order of these elements!
            ['Start', 'Start',
               -1, '/assets/img/misc_start.png'],
            ['End', 'End',
               -1, '/assets/img/misc_end.png']
         ];

      // FIXME: Next three fcns. belong in a presentation class... maybe one
      //        of the Route panels' classes, since that's what uses this html.

      // The header for directions html page.
      public static function directions_html_header() :String
      {
         var html_text:String = (<![CDATA[
            <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
            <html>
            <head>
            <title> Route Directions </title>
            <style type="text/css">
               <!--
               .header {
                  font-family:Verdana, Arial, Helvetica, sans-serif;
                  font-weight: bold;
                  font-size: 10px; }
               .normal {
                  font-family:Verdana, Arial, Helvetica, sans-serif;
                  font-size: 10px; }
               -->
            </style>
            </head>
            <body>
            <table border="0" width="400"><tr><td>
            <div align="center">
            <h2>Cyclopath Cue Sheet</h2>
            <table border="0" cellpadding="2">
            ]]>).toString();
         return html_text;
      }

      // The table header for directions html page.
      public static function directions_html_table(
         first_col_width:int=46, first_col_label:String="Odo.") :String
      {
         var html_text:String = StringUtil.substitute(
            (<![CDATA[
            </table>
            </div>
            <table border="0" cellpadding="2" width="400" rules="groups">
               <colgroup align="center">
               <colgroup align="center" span="2">
               <colgroup align="center">
               <thead>
                  <tr>
                     <th width="{first_col_width}" align="left" class="header">
                        {0}
                     </th>
                     <th colspan="2" class="header">
                        <div align="left">Do This</div>
                     </th>
                     <th width="46" align="left" class="header">Leg</th>
                  </tr>
               </thead>
               <tbody>
            ]]>).toString(),
            [
               first_col_label,
            ]
         );
         return html_text;
      }

      // The tail for directions html page.
      public static const directions_html_tail:String =
         '</tbody> </table> </td> </tr> </table> </body> </html>';

      // Byways, with the same name, that are shorter than this distance
      // will be merged in the directions, no matter what the turn angle is.
      public static const dir_merge_length:Number = 100;

      // Byways, with the same name, that turn less than this angle(in degrees)
      // will be merged in the directions, no matter what its length is.
      public static const dir_merge_angle:Number = 30;

      // Determines whether only old or new byways & points are drawn.
      // (Corresponds to diff_toggle.selectedIndex)
      public static const hb_old:int = 0;
      public static const hb_new:int = 1;
      public static const hb_both:int = 2; // default

      // Which planner to use by default.
      public static const rf_planner_default_default:int = Travel_Mode.wayward;
      // Classic, personalized route finder p1 preferences defaults.
      public static const rf_p1_priority_default:Number = 0.5;
      // Multimodal planner p2 options.
      public static const rf_p2_enable_default:Boolean = false;
      public static const rf_p2_transit_pref_default:int = 0;
      public static const rf_p2_date_reset_time:int = 900000; // 15 * 60 * 1000
      // Planner p3 defaults.
      public static const rf_p3_weight_type_default:String = 'rat';
      // MAGIC_NUMBERS: Defaults used in ccp.py, Conf.as, route_get.py,
      //                and 234-byway-is_disconnected.sql; see the value
      //                sets, pyserver/planner/routed_p3/tgraph.py's
      //                Trans_Graph.rating_pows and burden_vals.
      public static const rf_p3_rating_pump_default:int =  4;
      public static const rf_p3_burden_pump_default:int =  20;
      public static const rf_p3_spalgorithm_default:String = 'as*';

      // DB_SYNC_ME: See tag_preference_type table.
      public static const rf_tag_pref_codes:Array = ['ignore',  // 0
                                                     'bonus',   // 1
                                                     'penalty', // 2
                                                     'avoid'];  // 3

      public static const flashclient_settings_default:XML = null;
      public static const routefinder_settings_default:XML = null;

      // Search Results constants. The number of results to show in results
      // list per page.
      // CcpV1: Was: (max is 23). CcpV3: Uses paginator, and sets limit to 10.
      // FIXME: Statewide UI: Can we increase the paginator size?
      // MAYBE:  What about calculating it from window height / row height?
      //public static const search_num_results_show:int = 10;
      // 2013.04.19: 20 Seems nicer, especially with a tall window. And it
      //             matches how many threads the discussions lists show.
      public static const search_num_results_show:int = 20;
      public static const search_result_letter_size:int = 11;
      public static const search_result_label_size:int = 15;
      public static const geocode_results_page_size:int = 3;

      // The startup application mode. Generally, you won't want to start in
      // anything but view mode.
      public static const map_default_mode:App_Mode_Base = G.view_mode;
      // BUG 2792: Re-enable editing:
      //public static const edit_restriction:Boolean = false;
      //public static const edit_restriction:Boolean = true;
      // 2013.07.23: CcpV2 Welcome Message and Map Editing Opt-In.
      public static const bug_nnnn_ccpv2_message:Boolean = false;
// BUG nnnn/FIXME: Disable this soon... maybe.
//uncomment      public static const bug_nnnn_known_issues:Boolean = false;
      public static const bug_nnnn_known_issues:Boolean = true;
      public static const edit_restriction:Boolean = false;
      // In addition to edit_restriction, see cp_maint_beg/cp_maint_end.
      // The latter is set by the server and can change during runtime;
      // the former is compiled into flashclient.

      // Default 'Display Options' geofeature item layer visibilities.
      // See the display_opts_id_* options in Map_Layer_Toggler.
      public static const map_default_show_facils:Boolean = true;
      public static const map_default_show_points:Boolean = true;
      public static const map_default_show_regions:Boolean = false;
      public static const map_default_show_links:Boolean = true;

      // *** Geofeature Layer Drawing Parameters

      // The draw_param lookup is loaded from the server. It describes the
      // colors and line widths (but not label widths) to use to draw specific
      // geofeature layer types, based on the current tile skin. The lookup is
      // populated by the following fcn., import_xml.
      //
      // FIXME: Statewide UI: Make sure you load the draw_class_param for the
      //        skin on the tiles being used. See table: tiles_mapserver_zoom.
      //        Maybe add checkbox for old-school Cyclopath skin?
      //        And make sure you reload the draw param when the client skin
      //        changes.
      //
      // draw_param = { Draw_Class.MEDIUM: { color: 16775795,
      //                                     10: { width: 6.0,
      //                                           label: true },
      //                                     11: { width: 2.0,
      //                                           label: false },
      //                Draw_Class.SUPER:  { color: 15908644,
      //                                     ...
      // 2013.05.06: Deprecated: Conf.draw_param.
      public static var draw_param:Dictionary;

      //
      public static function get shadow_color() :int
      {
         return Conf.tile_skin.attr_pens
            ['draw_class']['shadow']['dashon_color'];
      }

      // Geofeature draw class lookups. These map Geofeature layers to Draw
      // classes.

      // 2013.05.06: Deprecated: These three:
      public static var geofeature_layer_by_id:Dictionary;
      public static var geofeature_layers_by_type:Dictionary;
      public static var draw_class_by_gfl:Dictionary;

      // *** Constructor

      public function Conf() :void
      {
         m4_ASSERT(false); // Not instantiable.
      }

      // *** Static class methods

      // Import the XML config information retrieved from the server.
      public static function import_xml(xml:XML) :void
      {
         m4_ASSERT(false); // 2013.05.06: Deprecated, w/ GWIS_Value_Map_Get.

         // Build the geofeature_layer lookup (matches geofeature types and
         // layers to draw_class IDs for viewers, editors, and owners).

         if (!(xml.draw_param_joined.row is XMLList)) {
            throw new Error('Not XMLList');
         }
         if ((xml.draw_param_joined.row is XML)) {
            throw new Error('Is XML');
         }
         Conf.draw_param =
            Conf.import_xml_draw_param(xml.draw_param_joined.row);

         // Build the draw_param lookup (matches geofeature_layer IDs and zoom
         // levels to text label sizes and colors).

         Conf.import_xml_geofeature_layer(xml.geofeature_layer.row);

         Conf.import_xml_mapserver_zoom(xml.tiles_mapserver_zoom.row);

         m4_DEBUG('Imported XML config data.');
      }

      // Build a dictionary lookup for the draw_param table.
      //
      // The dictionary is built like,
      //
      //    lookup[draw_class_id]['color']
      //    lookup[draw_class_id][zoom_level]['width']
      //    lookup[draw_class_id][zoom_level]['label']
      //    lookup[draw_class_id][zoom_level]['label_size']
      //
      protected static function import_xml_draw_param(xml_list:XMLList)
         :Dictionary
      {
         m4_ASSERT(false); // 2013.05.06: Deprecated, w/ GWIS_Value_Map_Get.

         var lookup:Dictionary = new Dictionary();
         var dc_id:int;
         var row:XML;
         var value:String;
         var zoom:int;
         for each (row in xml_list) {
            // Draw class ID
            dc_id = int(row.@draw_class_id);
            if (!lookup[dc_id]) {
               lookup[dc_id] = new Dictionary();
            }
            // Zoom level
            value = row.@zoom;
            if (value !== null) {
               zoom = int(value);
               if (!lookup[dc_id][zoom]) {
                  lookup[dc_id][zoom] = new Dictionary();
               }
            }
            // NOTE Color is always set, but draw_class_id 1 and 4
            //      (shadow and background, respectively) do not
            //      specify width, label, or label_size.
            // Color
            lookup[dc_id]['color'] = int(row.@color);
            // Width
            value = row.@width;
            if (value !== null) {
               lookup[dc_id][zoom]['width'] = Number(value);
            }
            // Label
            value = row.@label;
            if (value !== null) {
               lookup[dc_id][zoom]['label'] = Boolean(int(value));
            }
            // Label size
            value = row.@label_size;
            if (value !== null) {
               lookup[dc_id][zoom]['label_size'] = Number(value);
            }
         }
         return lookup;
      }

      // Build dictionary lookups for geofeature layers and draw types.
      //
      // The dictionarys are structured as follows:
      //
      //    Conf.geofeature_layer_by_id[gfl_id]          => layer_name
      //    Conf.geofeature_layers_by_type[feat_type]    => Array of layer_name
      //    Conf.draw_class_by_gfl[gfl_id][access_level] => draw class ID
      //
      protected static function import_xml_geofeature_layer(xml_list:XMLList)
         :void
      {
         m4_ASSERT(false); // 2013.05.06: Deprecated, w/ GWIS_Value_Map_Get.

         var row:XML;
         var gfl_id:int;
         var feat_type:String;
         var layer_name:String;
         var restrict_usage:Boolean;

         m4_DEBUG('import_xml_geofeature_layer');

         // Create some fresh lookups.
         Conf.geofeature_layer_by_id = new Dictionary();
         Conf.geofeature_layers_by_type = new Dictionary();
         Conf.draw_class_by_gfl = new Dictionary();

         // Populate the lookups from what the server says.
         for each (row in xml_list) {

            // Parse the GML.

            // Geofeature ID
            gfl_id = int(row.@gfl_id);
            // Geofeature type
            feat_type = row.@feat_type;
            // NOTE The bang! is testing if the key exists, not if the
            //      resulting value is false (in Python, this would throw
            //      KeyError if the key didn't exist).
            if (!Conf.geofeature_layers_by_type[feat_type]) {
               m4_DEBUG('  new type:', feat_type);
               Conf.geofeature_layers_by_type[feat_type] =
                  new Array();
            }
            // Geofeature type layer name
            layer_name = row.@layer_name;
            // Geofeature type restrict usage
            restrict_usage = Boolean(int(row.@restrict_usage));

            // Populate the lookups.

            m4_DEBUG(' new layer:', feat_type, '.', layer_name);

            // Create a new lookup, maybe.
            if (!Conf.draw_class_by_gfl[gfl_id]) {
               Conf.draw_class_by_gfl[gfl_id] = new Dictionary();
            }
            else {
               // The server shouldn't send duplicate IDs, so this is
               // unreachable code.
               m4_ASSERT_SOFT(false);
            }

            // Add to lookup of layer name by geofeature layer ID.
            Conf.geofeature_layer_by_id[gfl_id] = layer_name;

            // Add to lookup of geofeature_layer details by item type.
            Conf.geofeature_layers_by_type[feat_type].push(
               { id: gfl_id,
                 label: layer_name,
                 restrict_usage: restrict_usage });

            // Add to lookups of draw class ID by ID and access level.
            // Setting draw-class for client to be the same as that of viewer.
            Conf.draw_class_by_gfl[gfl_id][Access_Level.client] =
               row.attribute('draw_class_viewer');
            Conf.draw_class_by_gfl[gfl_id][Access_Level.viewer] =
               row.attribute('draw_class_viewer');
            Conf.draw_class_by_gfl[gfl_id][Access_Level.editor] =
               row.attribute('draw_class_editor');
            Conf.draw_class_by_gfl[gfl_id][Access_Level.arbiter] =
               row.attribute('draw_class_arbiter');
            Conf.draw_class_by_gfl[gfl_id][Access_Level.owner] =
               row.attribute('draw_class_owner');
         }
      }

      // Build dictionary lookups for geofeature layers and draw types.
      //
      // The dictionarys are structured as follows:
      //
      //    Conf.geofeature_layer_by_id[gfl_id]          => layer_name
      //    Conf.geofeature_layers_by_type[feat_type]    => Array of layer_name
      //    Conf.draw_class_by_gfl[gfl_id][access_level] => draw class ID
      //
      protected static function import_xml_mapserver_zoom(xml_list:XMLList)
         :void
      {
         m4_ASSERT(false); // 2013.05.06: Deprecated, w/ GWIS_Value_Map_Get.

         m4_VERBOSE('import_xml_mapserver_zoom');

         // SYNC_ME: Search tiles_mapserver_zoom columns.
         var mapserv_cols:Array = [
            [ 'do_draw', Boolean ],
            [ 'pen_color_i', int ],
            [ 'pen_width', Number ],
            [ 'pen_gutter', Number ],
            [ 'do_shadow', Boolean ],
            [ 'shadow_width', Number ],
            [ 'shadow_color_i', int ],
            [ 'do_label', Boolean ],
            [ 'label_size', int ],
            [ 'label_color_i', int ],
            [ 'labelo_width', Number ],
            [ 'labelo_color_i', int ]
            ];

         for each (var row:XML in xml_list) {
            // Zoom Level
            var mapserv_layer_group:String = row.@mapserv_layer_group;
            var zoom_level:int = int(row.@zoom_level);
            var gfl_id:int = int(row.@gflid);
            // FIXME: Some gfl_ids, e.g., 14, are not in draw_param: because
            //        they are drawn like other features, e.g., 14 (bike path)
            //        is drawn like 11 (local road).
            if ((gfl_id in Conf.draw_param)
                && (zoom_level in Conf.draw_param[gfl_id])) {
               m4_VERBOSE2('import_xml_mapserver_zoom: zoom:', zoom_level,
                           '/ gfl_id:', gfl_id);
               var lookup:Dictionary;
               lookup = Conf.draw_param[gfl_id][zoom_level]
               for each (var defn:Array in mapserv_cols) {
                  var key_name:String = defn[0];
                  lookup[defn[0]] = defn[1](row.attribute(key_name));
                  m4_VERBOSE2(' .. key_name:', key_name, '/ value:',
                              lookup[defn[0]]);
               }
            }
            else {
               m4_VERBOSE2('import_xml_mapserver_zoom: skipping: zoom:',
                           zoom_level, '/ gfl_id:', gfl_id);
            }
         }
      }

      // *** Init methods

      //
      public static function init_logger() :void
      {
         // Setup the logger.
         Conf.log = Logging.get_logger('** CONF **');
      }

      //
      public static function init_instance() :void
      {
         // Setup the instance (e.g., Minnesota or Colorado).
         Conf.instance_config();
      }

      // Load Instance-specific parameters *after* application initialization
      // (since we rely on G.url_base to determine which instance this is).
      public static function instance_config() :void
      {
         for (var key:String in Conf_Instance.active_config) {
            Conf[key] = Conf_Instance.active_config[key];
         }
         // Fix the URL if we're running pyserver remotely, and tell our code
         // to avoid triggering sandbox exceptions if we're not wrapped in HTML
         // (and JavaScript).
         // We can guess this by looking at the current URL.
         var file_url_re:RegExp = /^file:\/\/\//;
         if (file_url_re.test(G.url_base)) {
            Conf.external_interface_okay = false;
            G.file_base = G.url_base.replace(/^(file:\/\/\/.+)\/.*/, "$1");
            G.url_base = Conf_Instance.url_base_if_file;
            m4_DEBUG2('*new* G.url_base:', G.url_base,
                      '/ file_base:', G.file_base);
            // Also, don't restrict the log file line length... [lb] thinks....
            Conf_Instance.debug_logging_line_length_default = 0;
         }
      }

   }
}


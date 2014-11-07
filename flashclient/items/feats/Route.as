/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.feats {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.geom.Point;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import mx.collections.ArrayCollection;
   import mx.controls.Alert;
   import mx.core.IToolTip;
   import mx.managers.ToolTipManager;
   import mx.utils.ObjectUtil;
   import mx.utils.StringUtil;
   import mx.utils.UIDUtil;

   import grax.Access_Infer;
   import grax.Access_Level;
   import grax.Aggregator_Base;
   import items.Geofeature;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Geofeature_Layer;
   import items.utils.Item_Type;
   import items.utils.Landmark;
   import items.utils.Travel_Mode;
   import utils.geom.Dual_Rect;
   import utils.geom.Geometry;
   import utils.geom.MOBRable_DR;
   import utils.misc.Collection;
   import utils.misc.Data_Change_Event;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Map_Label;
   import utils.misc.Set_UUID;
   import utils.misc.Strutil;
   import utils.misc.Timeutil;
   import utils.rev_spec.*;
   import views.base.App_Action;
   import views.base.Map_Layer;
   import views.base.Paint;
   import views.base.UI;
   import views.map_widgets.Item_Sprite;
   import views.map_widgets.tools.Tool_Pan_Select;
   import views.map_widgets.tools.Tool_Route_Destination;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Geofeature;
   import views.panel_routes.Panel_Item_Route;
   import views.panel_routes.Panel_Routes_Box;
   import views.panel_routes.Route_Details_Panel_Historic;
   import views.panel_routes.Route_Editor_UI;
   import views.panel_routes.Route_Stop;
   import views.panel_routes.Route_Stop_Editor;
   import views.panel_routes.Route_Viz;
   import views.panel_routes.Route_Viz_Diff_Map;

   public class Route extends Geofeature {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Route');

      // MAGIC_NUMBER: 160 is route z-level.
      // The client does not send z-level for routes since it's always the
      // same: 160. We might change this in the future, but for now this is
      // strictly the case.
      // SYNC_ME: pyserver/item/feat/route.py::route.Geofeature_Layer.Z_DEFAULT
      //          flashclient/items/feats/Route.as::Route.z_level_always
      protected static const z_level_always:int = 160;

      // *** Mandatory attributes

      public static const class_item_type:String = 'route';
      public static const class_gwis_abbrev:String = 'rt';
      public static const class_item_type_id:int = Item_Type.ROUTE;

      // The Class of the details panel used to show info about this item.
      public static const dpanel_class_static:Class = Panel_Item_Route;

      // SYNC_ME: Search geofeature_layer table.
      public static const geofeature_layer_types:Array = [
         Geofeature_Layer.ROUTE_DEFAULT,
         ];

      // *** Other static attributes

      // A lookup of Route by stack_id
      public static var all:Dictionary = new Dictionary();

      // FIXME: Diff Mode: Fix historic mode.
      protected static var history_detail_panel:Route_Details_Panel_Historic;

      protected static var tooltip:IToolTip; // tooltip display on mouse over

      // MAYBE: 2012.10.16: [lb]: Do these belong in a view class and not the
      //        item (model) class? Or maybe the item manager class (so we can
      //        avoid static vars in this class)? I can fix in CcpV2...
      // Feedback mode.
      public static const FB_OFF:int = 0;
      public static const FB_DRAGGING:int = 1;
      public static const FB_SELECTING:int = 2;
      // Feedback instance.
      public static const FB_NEW:int = 1;
      public static const FB_OLD:int = 2;

      // FIXME: These statics belong in Item_Manager or Find_Route_Manager.
      //
      // Originally-requested route (fresh from the route-finder).
      // Already evaluated routes.
      public static var evaluated:Array = new Array();
      // Feedback highlighting and selecting.
      public static var highlighted_step:Route_Step = null;
      public static var selected_steps:Array = new Array();

      // *** Instance variables

      // These are sent to and from the server.
      public var details:String;
      public var beg_addr:String;
      public var fin_addr:String;
      public var rsn_len:Number;
      //public var rsn_min:Number;
      //public var rsn_max:Number;
      //public var n_steps:Number;
      //public var beg_nid:Number;
      //public var fin_nid:Number;
      public var avg_cost:Number;
      public var stale_steps:int;
      public var stale_nodes:int;

      // This references Travel_Mode and represents the routed used to generate
      // the route (like, p1, p2, or p3, unlike Route_Step, where travel_mode
      // represents the mode of travel, like bike or bus).
      public var travel_mode:int;

      public var p1_priority:Number = NaN;
      public var p2_depart_at:String;
      public var p2_transit_pref:int;
      public var p3_weight_attr:String;
      public var p3_weight_type:String;
      public var p3_rating_pump:int;
      public var p3_burden_pump:int;
      public var p3_spalgorithm:String;
      public var tags_use_defaults:Boolean;

      // Not sent by server: source, z, host

      // Computed values.
      public var computed_length:Number; // meters (bicycle portion only)
      public var alternate_length:Number;
      public var total_time:Number; // seconds

      // If we just fetched a new route, it's considered unlibraried
      // until the user explicitly saves it.
      // MAYBE: The unlibraried bool probably belongs in a common base
      //        class for gia-restricted type items.
      public var unlibraried:Boolean = false;

      // Route steps and directions will be null if the route is half-loaded/
      // not hydrated.
      protected var rsteps_:Array;

      // We store lightweight Route_Stop_Editor objects in rstops.
      // Each route has at least two route stops: the origin and the
      // destination of the route. Users can also add extra route
      // stops. The heavierweight Route_Stop objects, in edit_stops,
      // manage the view and are what the user interacts with on the
      // map and in the route details panel. The rstops items, on the
      // other hand, store just data objects. We especially use them
      // with the Route_Path_Edit_Command to track edits to the route.
      public var rstops:Array;

      // An array of objects of the same type as the rstops array.
      // This array contains the position/name state of edit_stops from
      // when the last Route_Path_Edit_Command was performed
      public var last_cmd_stops:Array;

      // An array of Route_Stops used to populate the view of named or
      // important route stops.
      // 2014.06.27: The use of rstops and edit_stops and last_cmd_stops
      // is somewhat confusing. They're all collections of route_stops.
      // The rstops member is immutable. last_cmd_stops is used by
      // Route_Path_Edit_Command. And this.edit_stops is what the user
      // plays with.
      public var edit_stops:Array = new Array();

      // If the user longpresses on the route and they haven't asked for
      // immediate route_stop editing, we'll start route_stop editing.
      // Not needed: we use tool_pan_select's longpress timer:
      //   public var rstop_editing_enabler:Timer;
      public var rstop_editing_enabled:Boolean;
      protected var num_dests_:* = null;
      [Bindable] public var num_rstops_selected:int = 0;

      // A list of Route_Segment objects, each representing the route steps
      // between two adjacent route stops, used by Route_Path_Edit_Command
      // while updating path segments (i.e., after the user moves, removes,
      // or adds a route stop).
      public var updating_segments:Array;

      // When the byways of the road network are edited, they might invalidate
      // existing routes. If the server sees this, it can send the orignal
      // route as well as a newly computed route using the current road
      // network.
      public var alternate_steps:Array;
      public var alternate_xs:Array;
      public var alternate_ys:Array;

      public var directions:Array;
      // For route manip.
      public var alternate_directions:Array;

      // *** View-related attributes.

      // The Panel_Item_Route panel.
      public var route_panel_:Panel_Item_Route;
      // MAYBE: Replace master_route with item_stack.master_item...
      public var master_route:Route;

      // We want to draw routes that have active panels or whose
      // Route_List_Entry checkbox is selected. Since there could
      // be more than one Route_List, we track the selected state
      // of the checkbox here, in the Route, and each Route_List_Entry
      // adjusts its checkbox to match this bool.
      protected var filter_show_route_:Boolean = false;
      // We also track the Route_Lists to which this route belongs. When there
      // are no more Route_List associations and no more panel associations, we
      // can discard the route (if we so choose, otherwise we can just leave it
      // in memory; the latter is nice if you want to let users paginate route
      // lists and not discard routes when they leave a page).
      public var route_list_membership:Set_UUID = new Set_UUID();
      // To avoid excessive coupling -- and possibly an import loop -- make
      // Panel_Routes_Library to us who to call. Otherwise, we'd have to
      // spaghetti it, e.g., G.app.routes_panel.routes_library.blah().
      static public var looked_at_list_callback:Function = null;
      // The route could be, e.g., attached to a route panel, or a discussion
      // panel, or both.
      public var keep_showing_while_paneled:Set_UUID = new Set_UUID();

      // This is used by route reactions to remember the route returned by the
      // server, since the user is allowed to edit the route. With other items,
      // the undo/redo command history can essentially revert an item to the
      // server state, and the user can also discard all edits and reload the
      // entire map. So route has it's own special way of reverting to its
      // server state.
      public var fresh_route:Route = null;

      // This is a collection of route stop labels. It used to be called
      // rstop_labels. It's just letters of the alphabet atop the route stop
      // circles (the "A", "B", "C", etc., labels).
      protected var rstop_labels:Array;

      // The path_arrows (the straight, dashed line that we draw when the user
      // is dragging a route stop around) are not editable or interactive, so
      // we use a regular Sprite and not an Item_Sprite.
      protected var path_arrows:Sprite;

      // For drawing a circle at the current route step.
      protected var current_dir_step_sprite:Sprite;
      protected var current_dir_step:Array;

      // The route stops are interactive, so make these Item_Sprites.
      // These are the colorful circles beneath the A, B, C, etc., labels.
      public var rstop_sprite:Item_Sprite;
      // This is the draggable route stop.
      protected var temporary_rstop:Item_Sprite;

      // Helpers for route manip.
      protected var tooltip_timer:Timer;
      protected var last_mouse_over:MouseEvent;
      protected var delight_on_mouse_out:Boolean;

      // Route Feedback Drag mode and instance.
      public var feedback_mode:int = Route.FB_OFF;
      public var feedback_instance:int = Route.FB_OFF;

      public var routes_viz:Route_Viz = null;

      public var landmarks_loaded:Boolean = false;
      public var show_landmarks:Boolean = false;

      // *** Constructor

      //
      public function Route(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         this.geofeature_layer_id = Geofeature_Layer.ROUTE_DEFAULT;

         this.z_level = Route.z_level_always;

         this.directions = new Array();
         this.alternate_directions = new Array();

         this.rstop_labels = new Array();
         this.path_arrows = new Sprite();
         this.current_dir_step_sprite = new Sprite();
         // This is needed after gml_consume, before super().
         this.rstop_sprite = new Item_Sprite(this);
         this.temporary_rstop = new Item_Sprite(this);

         this.routes_viz = Conf.route_vizs[0];

         super(xml, rev);

         this.sprite.addChild(this.temporary_rstop);

         // Show a toolTip on the route if the user hovers over the geometry.
         if (Conf.route_path_tooltip_delay > 0) {
            this.tooltip_timer = new Timer(Conf.route_path_tooltip_delay, 1);
            this.tooltip_timer.addEventListener(
               TimerEvent.TIMER, this.on_tooltip_timer, false, 0, true);
         }
      }

      // ***

      //
      public static function redraw_all() :void
      {
         m4_TALKY('redraw_all: Route.all.len:', Route.all.length);
         for each (var route:Route in Route.all) {
            if (route.visible) {
               route.draw();
            }
         }
      }

      // ***

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            // NOTE: Geofeature also goes through it's all, so... this is
            //       probably redundant.
            var sprite_idx:int = -1;
            // We'll reset Route.all so don't bother deleting from it.
            var skip_delete:Boolean = true;
            for each (var route:Route in Route.all) {
               route.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Route.all = new Dictionary();
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Route = (to_other as Route);
         super.clone_once(other);

         other.details = this.details;

         other.beg_addr = this.beg_addr;
         other.fin_addr = this.fin_addr;
         other.rsn_len = this.rsn_len;
         // Skipping/Not received from server:
         //    rsn_min, rsn_max, n_steps, beg_nid, fin_nid
         other.avg_cost = this.avg_cost;
         m4_TALKY('clone_once: avg_cost:', other.avg_cost);
         other.stale_steps = this.stale_steps;
         other.stale_nodes = this.stale_nodes;

         other.travel_mode = this.travel_mode;
         other.p1_priority = this.p1_priority;
         other.p2_depart_at = this.p2_depart_at;
         other.p2_transit_pref = this.p2_transit_pref;
         other.p3_weight_attr = this.p3_weight_attr;
         other.p3_weight_type = this.p3_weight_type;
         other.p3_rating_pump = this.p3_rating_pump;
         other.p3_burden_pump = this.p3_burden_pump;
         other.p3_spalgorithm = this.p3_spalgorithm;
         other.tags_use_defaults = this.tags_use_defaults;
         // Not sent by server: tagprefs for when route was 1st requested.

         // Not sent by server: source, z, host

         other.computed_length = NaN;
         other.alternate_length = NaN;
         other.total_time = NaN;

         other.unlibraried = this.unlibraried;

         if (this.rsteps !== null) {
            other.rsteps = Collection.array_copy(this.rsteps);
         }
         //other.rstops = null;
         if (this.rstops !== null) {
            other.rstops = Collection.array_copy(this.rstops);
         }
         //other.rstops_sync();
         other.edit_stops_set(Collection.array_copy(this.edit_stops));
         if (this.last_cmd_stops !== null) {
            other.last_cmd_stops = Collection.array_copy(this.last_cmd_stops);
         }

         other.alternate_steps = null;
         other.alternate_xs = null;
         other.alternate_ys = null;

         // Skipping: rstop_editing_enabled

         // Skipping: updating_segments (used when user edits rte, adds stops)

         // Skipping: route_panel_
         // Skipping: master_route

         // Skipping: filter_show_route_
         //           route_list_membership
         //           looked_at_list_callback
         //           keep_showing_while_paneled

         // Skipping: fresh_route
         //           rstop_labels
         //           path_arrows
         //           current_dir_step_sprite
         //           current_dir_step
         //           rstop_sprite
         //           temporary_rstop
         //           tooltip_timer
         //           delight_on_mouse_out

         // Skipping: other.feedback_mode = this.feedback_mode;
         // Skipping: other.feedback_instance = this.feedback_instance;

         // Skipping: routes_viz
         //           show_landmarks
      }

      //
      override protected function clone_update( // on-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Route = (to_other as Route);
         super.clone_update(other, newbie);

         if ((!other.computed_length) || (isNaN(other.computed_length))) {
            other.computed_length = this.computed_length;
            m4_TALKY('clone_update: computed_length:', other.computed_length);
         }
         if ((!other.alternate_length) || (isNaN(other.alternate_length))) {
            other.alternate_length = this.alternate_length;
            m4_TALKY2('clone_update: alternate_length:',
                      other.alternate_length);
         }
         if ((!other.total_time) || (isNaN(other.total_time))) {
            other.total_time = this.total_time;
            m4_TALKY('clone_update: total_time:', other.total_time);
         }

         if ((other.rsteps === null) && (this.rsteps !== null)) {
            other.stale_steps = this.stale_steps;
            other.stale_nodes = this.stale_nodes;
            // STYLE GUIDE: ObjectUtil doesn't really work
            //    var arr:Array = ObjectUtil.copy(other_arr) as Array;
            //    for each (var cls:My_Class in arr) { ... }
            //    TypeError: Error #1034: Type Coercion failed:
            //       cannot convert Object@f39acd79 to my.project.My_Class.
            //    for each (var o:Object in arr) { ... }
            //    TypeError: Error #1009: Cannot access a property or method
            //       of a null object reference.
            m4_TALKY2('clone_update: copying rsteps: len:',
                      (this.rsteps !== null) ? this.rsteps.length : 'null');
            other.rsteps = Collection.array_copy(this.rsteps);
         }

         if ((other.rstops === null) && (this.rstops !== null)) {
            m4_TALKY2('clone_update: copying rstops: len:',
                      (this.rstops !== null) ? this.rstops.length : 'null');
            other.rstops = new Array();
            var rstop:Route_Stop_Editor;
            for each (rstop in this.rstops) {
               var other_stop:Route_Stop_Editor = new Route_Stop_Editor();
               other_stop.name_ = rstop.name_;
               other_stop.node_id = rstop.node_id;
               m4_ASSERT_SOFT(other_stop.node_id > 0);
               // MAGIC_NUMBER: Use stop_version=1 for route stops that the
               // server sends so we can distinguish them from new
               // route stops that the user creates that are not yet
               // geocoded.
               other_stop.stop_version = 1;
               other_stop.x_map = rstop.x_map;
               other_stop.y_map = rstop.y_map;
               other_stop.is_endpoint = rstop.is_endpoint;
               other_stop.is_pass_through = rstop.is_pass_through;
               other_stop.is_transit_stop = rstop.is_transit_stop;
               other_stop.internal_system_id = rstop.internal_system_id;
               other_stop.external_result = rstop.external_result;
               other_stop.street_name_ = null;
               other_stop.editor = null;
               other.rstops.push(other_stop);
            }

            // Call rstops_sync and set:
            //    other.last_cmd_stops
            //    other.edit_stops
            other.rstops_sync();
         }

         if ((other.alternate_steps === null)
             && (this.alternate_steps !== null)) {
            m4_TALKY2('clone_update: alternate_steps.len:',
                      this.alternate_steps.length);
            other.alternate_steps =
               Collection.array_copy(this.alternate_steps);
            other.alternate_xs = Collection.array_copy(this.alternate_xs);
            other.alternate_ys = Collection.array_copy(this.alternate_ys);

            other.mark_route_panel_dirty();
         }

         // We're called after lazy-loading the route, so make sure we update
         // the directions and whatnot.
         // NOTE: This sets: computed_length
         //                  alternate_length
         //                  total_time
         //                  directions
         //                  alternate_directions
         // EXPLAIN: But above, we just copied:
         //             computed_length, alternate_length, total_time
         //          and now we're recalculating? Should be fine...
         //           I guess the recalculate only applies if rsteps
         //           are loaded, so maybe the copy above is good for
         //           routes that aren't fully hydrated.
         other.update_route_stats();
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         m4_TALKY('gml_consume: gml?:', (gml !== null));

         super.gml_consume(gml);

         if (gml !== null) {

            if ((this.name_) && (gml.@name) && (this.name_ != gml.@name)) {
               m4_WARNING('!! name_:', this.name_, '/ gml.@name:', gml.@name);
               m4_ASSERT_SOFT(this.name_ == gml.@name);
            }

            // Base class consumes: name, ids, stealth_secret, etc.

            this.details = gml.@details;

            // The beg_addr and fin_addr are stored with the route so it's
            // easy to know the names of the endpoints, but if the route has
            // its route stops loaded, the names of the route stop endpoints
            // will be used instead, at least in the view.
            this.beg_addr = gml.@beg_addr;
            this.fin_addr = gml.@fin_addr;
            // Skipping: rsn_min, rsn_max, n_steps, beg_nid, fin_nid
            this.rsn_len = Number(gml.@rsn_len);
            this.avg_cost = Number(gml.@avg_cost);
            this.stale_steps = int(gml.@stale_steps);
            this.stale_nodes = int(gml.@stale_nodes);
            m4_TALKY2('gml_consume: stale_steps:', this.stale_steps,
                      '/ stale_nodes:', stale_nodes);
            // Calculated below: computed_length, alternate_length, total_time

            this.travel_mode = int(gml.@travel_mode);
            m4_TALKY('gml_consume: travel_mode:', this.travel_mode);
            this.p1_priority = Number(gml.@p1_priority);
            this.p2_depart_at = gml.@p2_depart_at;
            this.p2_transit_pref = int(this.p2_transit_pref);
            this.p3_weight_attr = gml.@p3_weight_attr;
            this.p3_weight_type = gml.@p3_weight_type;
            this.p3_rating_pump = int(gml.@p3_rating_pump);
            this.p3_burden_pump = int(gml.@p3_burden_pump);
            this.p3_spalgorithm = gml.@p3_spalgorithm;
            this.tags_use_defaults = Boolean(int(gml.@tags_use_defaults));
            // Not sent by server: tagprefs for when route was 1st requested.
            m4_TALKY7('gml_consume: p1_priority:', this.p1_priority,
                      '/ p3_atr:', this.p3_weight_attr,
                      '/ p3_wgt:', this.p3_weight_type,
                      '/ p3_rat:', this.p3_rating_pump,
                      '/ p3_bdn:', this.p3_burden_pump,
                      '/ p3_alg:', this.p3_spalgorithm,
                      '/ tags_use_defs:', this.tags_use_defaults);

            // Not sent by server: source, z, host

            m4_TALKY('gml_consume: access_infer_id:', this.access_infer_id);
            m4_TALKY('gml_consume: access_level_id:', this.access_level_id);
            // Not sent from server: unlibraried (we must deduce):
            if ((this.access_infer_id == Access_Infer.sessid_arbiter)
                && (this.access_level_id == Access_Level.arbiter)) {
               this.unlibraried = true;
            }

            // Consumed below: rsteps_

            // Consumed below: rstops
            // Consumed below: alternate_steps, alternate_xs, alternate_ys
            // Consumed below: directions, alternate_directions

            m4_ASSERT_SOFT((this.z_level == 0)
                           || (this.z_level == Route.z_level_always));
            this.z_level = Route.z_level_always;

            // m4_VERBOSE('gml_consume: gml:', gml);
            // m4_VERBOSE('gml_consume: gml.step:', gml.step);
            // m4_VERBOSE('gml_consume: gml..step:', gml..step);

            // MAYBE: This should be renamed 'rstep' but android still uses
            //        this name.
            if ('step' in gml) {
               this.rsteps = new Array();
               this.compute_xys(gml.step, this.rsteps, this.xs, this.ys);
               m4_TALKY('gml_consume: num rsteps:', this.rsteps.length);
               if (this.rsteps.length == 0) {
                  m4_WARNING('gml_consume: no rsteps:', gml.step);
               }
            }
            else {
               // Leave rsteps null to indicate this object is not a hydrated
               // route.
               m4_ASSURT(this.rsteps === null);
            }

            // BUG_JUL_2014: BUG nnnn: See route:
            //                         "molly quinn to Humphry terminal"
            // The duplicate road network problem (in the data) causes
            // a really, weird, super long, out of the way route to be
            // recalculated (repair route feature). This might be a data
            // problem (probably), or it might be a route planner problem
            // (less likely).
            // [lb] had a note that the route repair just repaired the 2nd
            // leg of the route (i.e., three route endpoints), but the 1st
            // leg was appropriately repaired... so maybe a server error?

            if ('alternate' in gml) {
               // Parse alternate geometry, too. This is sent when the road
               // network has changed and the byways that the old route
               // followed have changed.
               this.alternate_steps = new Array();
               this.alternate_xs = new Array();
               this.alternate_ys = new Array();

               this.compute_xys(gml.alternate[0].step,
                                this.alternate_steps,
                                this.alternate_xs,
                                this.alternate_ys);

               m4_TALKY2('gml_consume: num alternate_steps:',
                         this.alternate_steps.length);
            }

            // MAYBE: Here and earlier, using 'step' and 'stop' and not 'rst?p'
            // MAYBE: This should be renamed 'rstop' but android still uses
            //        this name.
            if ('waypoint' in gml) {
               this.rstops = this.compute_rstops(gml.waypoint);
               this.rstops_sync();
               m4_TALKY('gml_consume: rstops.length:', this.rstops.length);
               if (this.rstops.length == 0) {
                  m4_WARNING('gml_consume: no rstops:', gml.waypoint);
               }
            }

            this.update_route_stats();

            m4_TALKY('gml_consume: this:', this);
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         gml.setName(Route.class_item_type); // 'route'

         // Remove the xy string text that Geofeature adds since we don't
         // want that for the route (we give route steps instead).
         gml.setChildren('');

         // Don't send:
         //    beg_addr
         //    fin_addr
         //    rsn_len
         //    //rsn_min
         //    //rsn_max
         //    //n_steps
         //    //beg_nid
         //    //fin_nid
         //    avg_cost
         //    stale_steps
         //    stale_nodes
         //    // These are sent by the gwis command, and apply to when the
         //    // route was first created, so we don't send them when saving
         //    // changes to a route:
         //    travel_mode
         //    p1_priority
         //    p2_depart_at
         //    p2_transit_pref
         //    p3_weight_attr
         //    p3_weight_type
         //    p3_rating_pump
         //    p3_burden_pump
         //    p3_spalgorithm
         //    tags_use_defaults
         //    computed_length
         //    alternate_length
         //    total_time

         // FIXME/EXPLAIN: How does this make sense? Travel_Mode is fixed.
         gml.@travel_mode = this.travel_mode;

         gml.@details = this.details;

         // Skipping: unlibraried

         gml.@source = 'put_feature';

         if (this.rsteps !== null) {
            var rstep_xml:XML;
            var rstep:Route_Step;
            for each (rstep in this.rsteps) {
               // MAYBE: This should be renamed 'rstep' but android still uses
               //        this name.
               rstep_xml = <step
                     step_name={rstep.step_name}
                     travel_mode={rstep.travel_mode}
                     beg_time={rstep.beg_time}
                     fin_time={rstep.fin_time} />;
               rstep_xml.@forward = int(rstep.forward);

               if (rstep.travel_mode == Travel_Mode.bicycle) {
                  rstep_xml.@byway_id = rstep.byway_system_id;
                  rstep_xml.@byway_stack_id = rstep.byway_stack_id;
                  rstep_xml.@byway_version = rstep.byway_version;
               }
               else {
                  rstep_xml.appendChild(
                     Geometry.coords_xys_to_string(
                        this.xs.slice(rstep.beg_index, rstep.fin_index),
                        this.ys.slice(rstep.beg_index, rstep.fin_index)));
               }

               gml.appendChild(rstep_xml);
            }
         }

         if (this.edit_stops !== null) {
            var rstop_xml:XML;
            var rstop_obj:Route_Stop;
            for each (rstop_obj in this.edit_stops) {
               // MAYBE: This should be renamed 'rstop' but android still uses
               //        this name.
               rstop_xml = <waypoint
                              node_id={rstop_obj.node_id}
                              x={rstop_obj.x_map}
                              y={rstop_obj.y_map}
                              />;
               // Not sent: rstop_obj.stop_version
               // Not sent: rstop_obj.is_endpoint
               rstop_xml.@is_pass_through = int(rstop_obj.is_pass_through);
               rstop_xml.@is_transit_stop = int(rstop_obj.is_transit_stop);
               rstop_xml.@int_sid = rstop_obj.internal_system_id;
               rstop_xml.@ext_res = int(rstop_obj.external_result);
               // Skipping: street_name_
               if (rstop_obj.name_ !== null) {
                  rstop_xml.@name = rstop_obj.name_;
               }
               gml.appendChild(rstop_xml);
            }
         }

         // Skipping: the rest....

         return gml;
      }

      // *** Base class overrides

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Route.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Route.all;
      }

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         m4_TALKY('item_cleanup:', this);

         // We used to call:
         //    G.map.routes_viewed.removeItemAt(this);
         // but we don't no more.
         // MAYBE: Should we check that we're not in a route_list or attached
         // to a panel still?

         if (i == -1) {
            try {
               i = (G.map.layers[this.zplus] as Map_Layer).getChildIndex(
                                                             this.sprite);
            }
            catch (e:ArgumentError) {
               // Error #2025: The supplied DisplayObject must be a child of
               //              the caller.
               // No-op
            }
            catch (e:TypeError) {
               // No-op
            }
         }

         var rs_label:Map_Label;
         for each (rs_label in this.rstop_labels) {
            if (rs_label.parent === G.map.route_labels) {
               m4_TALKY('item_cleanup: removing rs label:', rs_label);
               G.map.route_labels.removeChild(rs_label);
            }
            else {
               m4_TALKY2('item_cleanup: EXPLAIN: Why label missing?:',
                         rs_label);
               m4_TALKY(' .. parent:', rs_label.parent);
            }
         }
         //?: this.rstop_labels = new Array();

         try {
            m4_TALKY('item_cleanup: remove path_arrows from direction_arrows');
            G.map.direction_arrows.removeChild(this.path_arrows);
         }
         catch (e:ArgumentError) {
            // No-op
         }
         try {
            G.map.vertices.removeChild(this.rstop_sprite);
            G.map.vertices.removeChild(this.current_dir_step_sprite);
         }
         catch (e:ArgumentError) {
            // No-op
         }

         m4_TALKY2('item_cleanup: rem on_mouse_over- on_mouse_out lstnrs:',
                   this);
         this.sprite.removeEventListener(MouseEvent.MOUSE_OVER,
                                         this.on_mouse_over);
         this.sprite.removeEventListener(MouseEvent.MOUSE_OUT,
                                         this.on_mouse_out);

         if (this.tooltip_timer !== null) {
            this.tooltip_timer.removeEventListener(
               TimerEvent.TIMER, this.on_tooltip_timer);
            this.tooltip_timer = null;
         }

         // Remove self from base class lookup.
         if (!skip_delete) {
            delete Route.all[this.stack_id];
         }

         super.item_cleanup(i, skip_delete);
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         return true;
      }

      // ***

      //
      public function disable_rstop_editing() :void
      {
         m4_DEBUG('disable_rstop_editing: rstop_editing_enabled=f:', this);
         this.rstop_editing_enabled = false;
         for each (var rt_stop:Route_Stop in this.edit_stops) {
            m4_DEBUG('disable_rstop_editing: rstop_selected=f:', rt_stop);
            if (rt_stop.rstop_selected) {
               rt_stop.rstop_selected = false;
               this.num_rstops_selected -= 1;
            }
            rt_stop.rstop_deselecting = false;
            rt_stop.draw();
            if (G.map.tool_cur.dragged_object === rt_stop) {
               m4_DEBUG('disable_rstop_editing: dragged_object=null');
               G.map.tool_cur.dragged_object = null;
            }
         }
         if (G.map.tool_is_active(Tool_Route_Destination)) {
            m4_DEBUG('disable_rstop_editing: cancel route destination tool');
            G.map.tool_choose('tools_pan');
         }
         this.num_rstops_selected = 0;
         this.mark_route_panel_dirty();
      }

      // ***

      //
      // FIXME: Delete this someday. This fcn. rewritten for route manip,
      //        but [lb] already found a few things missing so keeping this
      //        fcn. for the time being. For one, this fcn. calls merge_stop...
      //        so we should test whatever merge_stop resolves and then
      //        delete the fcns., draw_DELETE_ME and merge_stop.
      /*/
      public function draw_DELETE_ME(is_drawable:Object=null) :void
      {
         var i:int = 0;
         var x:Number;
         var y:Number;
         var step:Route_Step;
         var gr:Graphics = this.sprite.graphics;

         var startx:Number = G.map.xform_x_map2cv(this.xs[0]);
         var starty:Number = G.map.xform_y_map2cv(this.ys[0]);
         var endx:Number = G.map.xform_x_map2cv(this.xs[this.xs.length - 1]);
         var endy:Number = G.map.xform_y_map2cv(this.ys[this.ys.length - 1]);

         super.draw();

         gr.clear();

         // remove old map rstop_labels
         if (this.rstop_labels !== null) {
            for (i = 0; i < this.rstop_labels.length; i++) {
               if (this.rstop_labels[i] !== null) {
                  this.sprite.removeChild(this.rstop_labels[i]);
               }
            }
            this.rstop_labels = null;
         }

         // remove old transit stops, start/end markers
         if (this.rstops !== null) {
            for (i = 0; i < this.rstops.length; i++) {
               this.sprite.removeChild(this.rstops[i]);
            }
            this.rstops = null;
         }

         if (this.selected) {
            // blue selection outline
            Paint.line_draw(gr, this.xs, this.ys, this.draw_width + 4,
                            Conf.selection_color);
            // use route viz to render the route
            G.user.route_viz.route_line_render(this, this.rsteps);
         }
         else {
            // render the route normally
            Paint.line_draw(gr, this.xs, this.ys, this.draw_width,
                            Conf.route_color);
         }

         // workaround for weird flash bug
         // flash would fill the last line segment with green
         gr.moveTo(startx, starty);

         // FIXME: Probably put following in new fcn.

         // Find and place labels and route stop markers.
         var rstops:Array = new Array(); // {rsteps: [...], x:, y:}
         var transit_label_txt:String;
         var transit_label_type:String;
         var tx:Number;
         var ty:Number;
         var j:int;

         this.rstops = new Array();
         this.rstop_labels = new Array();

         this.merge_stop(this.rsteps[0], startx, starty, rstops);
         for (i = 0; i < this.rsteps.length; i++) {
            step = this.rsteps[i];
            if ((step.transit_type == 'board_bus')
                || (step.transit_type == 'board_train')
                || (step.transit_type == 'alight_bus')
                || (step.transit_type == 'alight_train')) {

               if ((step.forward && (step.transit_type == 'alight_bus'
                                     || step.transit_type == 'alight_train'))
                   || (!step.forward && (step.transit_type == 'board_bus'
                                     || step.transit_type == 'board_train'))) {
                  tx = G.map.xform_x_map2cv(this.xs[step.fin_index - 1]);
                  ty = G.map.xform_y_map2cv(this.ys[step.fin_index - 1]);
               }
               else {
                  tx = G.map.xform_x_map2cv(this.xs[step.beg_index]);
                  ty = G.map.xform_y_map2cv(this.ys[step.beg_index]);
               }

               this.merge_stop(step, tx, ty, rstops);
            }
         }
         this.merge_stop(this.rsteps[this.rsteps.length - 1],
                         endx,
                         endy,
                         rstops);

         // Create labels and route stops for these points.
         for (i = 0; i < rstops.length; i++) {
            transit_label_txt = '';
            transit_label_type = null;

            for (j = 0; j < rstops[i].rsteps.length; j++) {
               step = rstops[i].rsteps[j];
               if (j > 0) {
                  transit_label_txt += ', ';
               }
               if (i == 0 && j == 0) {
                  // special case for first stop
                  transit_label_txt += 'Start';
                  transit_label_type = null;
               }
               else if ((i == rstops.length - 1 )
                        && (j == rstops[i].rsteps.length - 1)) {
                  // special case for last stop
                  transit_label_txt += 'End';
                  transit_label_type = null;
               }
               else if (step.transit_type == 'board_bus'
                        || step.transit_type == 'alight_bus') {
                  if (transit_label_type != 'bus') {
                     transit_label_txt += 'Bus ';
                  }
                  transit_label_txt += step.transit_name;
                  transit_label_type = 'bus';
               }
               else {
                  if (transit_label_type != 'train') {
                     transit_label_txt += 'Train ';
                  }
                  transit_label_txt += step.transit_name;
                  transit_label_type = 'train';
               }
            }

            this.rstops.push(new Transit_Stop(rstops[i].rsteps,
                                              i == 0,
                                              i == rstops.length - 1,
                                              rstops[i].x,
                                              rstops[i].y));

            this.rstop_labels.push(new Map_Label(transit_label_txt,
                                                 15,
                                                 0,
                                                 rstops[i].x - 2,
                                                 rstops[i].y - 24));
         }

         // place all labels and rstops in the map
         for (i = 0; i < this.rstops.length; i++) {
            this.sprite.addChild(this.rstops[i]);
            this.sprite.addChild(this.rstop_labels[i]);
         }
      }
      /*/

      //
      override public function draw(is_drawable:Object=null) :void
      {
         var drawable:Boolean;
         if (is_drawable !== null) {
            drawable = (is_drawable as Boolean);
         }
         else {
            drawable = this.is_drawable;
         }

         m4_TALKY2('draw: sel?:', this.selected, '/ drawable:', drawable,
                   this);

         // MAYBE: Care about this.master_route.route_panel_?
         var conflict_old_sel:Boolean = (
            (this.route_panel_ !== null)
            && (this.route_panel_.tab_route_details !== null)
            && (this.route_panel_.tab_route_details.conflict_old !== null)
            && (this.route_panel_.tab_route_details.conflict_old.selected));
         var conflict_new_sel:Boolean = (
            (this.route_panel_ !== null)
            && (this.route_panel_.tab_route_details !== null)
            && (this.route_panel_.tab_route_details.conflict_new !== null)
            && (this.route_panel_.tab_route_details.conflict_new.selected));
         var conflict_diff_sel:Boolean = (
            (this.route_panel_ === null)
            || (this.route_panel_.tab_route_details === null)
            || (this.route_panel_.tab_route_details.conflict_diff === null)
            || (this.route_panel_.tab_route_details.conflict_diff.selected));

         var show_primary:Boolean = (
            (this.alternate_steps === null)
            || conflict_old_sel
            || conflict_diff_sel
            || !this.rev_is_working);
         var show_alternate:Boolean = (
            (this.alternate_steps !== null)
            && (this.rev_is_working)
            && (conflict_new_sel || conflict_diff_sel));

         // Must show at least one version (maybe two)
         m4_ASSERT(show_primary || show_alternate);

         //m4_TALKY('draw: this.route_panel_:', this.route_panel_);
         //m4_TALKY('draw: this.master_route:', this.master_route);
         //m4_TALKY('draw: is_drawable:', is_drawable);
         //m4_TALKY('draw: this.visible:', this.visible);
         //m4_TALKY('draw: this.sprite.visible:', this.sprite.visible);

         super.draw();

         this.sprite.graphics.clear();

         // Remove old source and destination map labels.
         for each (var rs_label:Map_Label in this.rstop_labels) {
            if (rs_label.parent === G.map.route_labels) {
               m4_TALKY('draw: remove map rs label:', rs_label);
               G.map.route_labels.removeChild(rs_label);
            }
            // We're called from geofeatures_redraw_and_relabel for
            // new objects, so we may have never been labeled before.
            //   else {
            //      m4_TALKY('draw: EXPLAIN: Why is label missing?:', label);
            //      m4_TALKY(' .. parent:', label.parent);
            //   }
         }
         m4_TALKY('draw: reset map rs labels:', this.rstop_labels.length);
         this.rstop_labels = new Array();

         // Cleanup this.rstop_sprite.
         for (var i:int = this.rstop_sprite.numChildren - 1; i >= 0; i--) {
            this.rstop_sprite.removeChildAt(i);
         }

         this.current_dir_step_sprite.graphics.clear();

         if ((this.is_drawable) && (this.visible)) {
            this.draw_finally(show_primary, show_alternate);
         }
         else {
            ////this.label_reset();
            //this.label.visible = false;
         }
      }

      //
      public function draw_finally(show_primary:Boolean,
                                   show_alternate:Boolean) :void
      {
         var gr:Graphics = this.sprite.graphics;

         var nongeo:Boolean = (
               (this.is_vgroup_new || this.is_vgroup_old)
            && (this.counterpart !== null)
            && (this.digest_nongeo != this.counterpart.digest_nongeo));

         var selected_highlighted:Boolean = this.selected || this.highlighted;
         m4_TALKY2('draw_finally: selected_highlighted:',
                   selected_highlighted);

         // At higher zooms, make sure users can see the map beneath.
         var settings_alpha:Number = G.tabs.settings.settings_panel
                  .settings_options.route_transparency_slider.value;
         if (!G.map.zoom_is_vector()) {
            // Note that using line_draw's alpha doesn't work; rather,
            // set the sprite alpha.
            if (settings_alpha == 1.0) {
               this.sprite.alpha = 0.45;
            }
            else {
               this.sprite.alpha = settings_alpha;
            }
         }
         else {
            //this.sprite.alpha = 1.0;
            this.sprite.alpha = settings_alpha;
         }

         // Route Line Outline
         if (selected_highlighted && (this.feedback_mode == Route.FB_OFF)) {
            // Regular mode route selection outline.
            if (show_primary) {
               m4_TALKY('draw_finally: rt oline: line_draw: primary');
               Paint.line_draw(gr,
                               this.xs,
                               this.ys,
                               this.draw_width + 4,
                               Conf.selection_color);
            }

            if (show_alternate) {
               m4_TALKY('draw_finally: rt oline: line_draw: alternate');
               Paint.line_draw(gr,
                               this.alternate_xs,
                               this.alternate_ys,
                               this.draw_width + 4,
                               Conf.selection_color);
            }
         }
         else if (this.feedback_mode != Route.FB_OFF) {
            // Feedback mode route line outline.
            m4_TALKY('draw_finally: rt feedback oline: line_draw');
            Paint.line_draw(gr,
                            this.xs,
                            this.ys,
                            this.draw_width + 4,
                            ((this.feedback_instance == Route.FB_OLD)
                             ? Conf.route_feedback_old_outline
                             : Conf.route_feedback_new_outline));
         }
         else if (nongeo) {
            // Historic mode: green highlight for nongeometric changes.
            m4_TALKY('draw_finally: rt historic green highlight: line_draw');
            m4_ASSERT(show_primary && !show_alternate);
            Paint.line_draw(gr,
                            this.xs,
                            this.ys,
                            this.draw_width + 4,
                            Conf.change_color);
         }

         // Route Line.
         if ((G.map.rmode == Conf.map_mode_feedback)
             && (this.feedback_instance == Route.FB_OLD)) {
            // Route Feedback: Old route.
            m4_TALKY('draw_finally: rt feedback: old route: line_draw');
            Paint.line_draw(gr,
                            this.xs,
                            this.ys,
                            this.draw_width,
                            Conf.route_feedback_old_color);
         }
         else if (show_alternate && show_primary) {
            // m4_TALKY('draw: show_alternate && show_primary');
            // do a route-step comparison between current and alternate
            m4_TALKY('draw_finally: rt alternate diffs');
            m4_ASSERT(!this.rev_is_diffing);
            this.draw_alternate_diff(gr,
                                     this.rsteps,
                                     this.alternate_steps,
                                     this.xs,
                                     this.ys,
                                     Conf.vgroup_move_old_color,
                                     true);
            this.draw_alternate_diff(gr,
                                     this.alternate_steps,
                                     this.rsteps,
                                     this.alternate_xs,
                                     this.alternate_ys,
                                     Conf.vgroup_move_new_color,
                                     false);
         }
         else if (this.rev_is_working && selected_highlighted) {
            // m4_TALKY('draw: rev_is_working/current && selected');
            // Use route visualization to render the route.
            // FIXME: Correct re-use of is_path_editable?
            m4_TALKY('draw_finally: rt selected: highlighted: working rev.');
            this.draw_pri_or_alt(
               show_primary, show_alternate, this.is_path_editable());
         }
         else if (this.rev_is_diffing) {
            m4_ASSERT(show_primary && !show_alternate);
            if (this.counterpart === null) {
               // either a deleted or new route
               m4_TALKY('draw_finally: rt: rev_is_diffing: no counterpart');
               Paint.line_draw(gr,
                               this.xs,
                               this.ys,
                               this.draw_width,
                               (this.is_vgroup_old ? Conf.vgroup_old_color
                                                   : Conf.vgroup_new_color));
            }
            else {
               // do a route-step level geometry comparison and render it
               m4_TALKY('draw_finally: rt: rev_is_diffing: counterpart diff');
               this.draw_geometry_diff();
            }
         }
         else {
            // Unselected or historic route view.
            m4_TALKY('draw_finally: rt: unselected or historic');
            this.draw_pri_or_alt(
               show_primary, show_alternate, /*editable=*/false);
         }

         // Restore selections, if needed (feedback mode only).
         if (this.feedback_mode == Route.FB_SELECTING) {
            for each (var step:Route_Step in Route.selected_steps) {
               if (this.rsteps.indexOf(step) >= 0)
                  this.rs_select(step, true);
            }
         }

         // workaround for weird flash bug
         // flash would fill the last line segment with green
         var sx:Number;
         var sy:Number;
         gr.moveTo(sx, sy);

         // draw the rstops and add labels
         var letter:int = 0;
         var places:int = 1;
         var lettering:String;
         for (var i:int = 0; i < this.edit_stops.length; i++) {
            if (!this.edit_stops[i].is_stop_valid) {
               // Remove route stop with no x,y from the map.
               m4_TALKY2('draw_finally: i:', i, '/ !edit_stop.is_stop_valid:',
                         this.edit_stops[i]);
               if (this.edit_stops[i].parent !== null) {
                  this.rstop_sprite.removeChild(this.edit_stops[i]);
               }
               continue;
            }
            else if (this.edit_stops[i].parent === null) {
               // The route stop was not valid but now it's valid, so add it.
               m4_TALKY2('draw_finally: i:', i, '/ edit_stop.is_stop_valid:',
                         this.edit_stops[i]);
               this.rstop_sprite.addChild(this.edit_stops[i]);
            }
            // else, the route stop is already setup, and we're its parent.

            sx = this.edit_stops[i].x_cv;
            sy = this.edit_stops[i].y_cv;

            if (selected_highlighted) {
               m4_TALKY2('draw_finally: i:', i, '/ rstop_selected:',
                         this.edit_stops[i]);
               // No: this.edit_stops[i].rstop_selected = true;
               //     otherwise you draw _all_ route stops highlighted.
               this.edit_stops[i].draw();
            }
            else {
               m4_TALKY2('draw_finally: i:', i, '/ rstop_selected=f:',
                         this.edit_stops[i]);
               if (this.edit_stops[i].rstop_selected) {
                  this.edit_stops[i].rstop_selected = false;
                  this.num_rstops_selected -= 1;
               }
               if (this.edit_stops[i].graphics !== null) {
                  // Remove the old route stop circle.
                  m4_TALKY2('draw_finally: i:', i, '/ clearing edit_stop:',
                            this.edit_stops[i]);
                  this.edit_stops[i].graphics.clear();
               }
               if ((this.edit_stops[i].is_endpoint)
                   || (!this.edit_stops[i].is_pass_through)) {
                  m4_TALKY3('draw_finally: i:', i,
                            '/ !is_pass_thru or is_endpt:',
                            this.edit_stops[i]);
                  this.draw_circle(this.edit_stops[i].color, sx, sy, 6);
               }
            }

            if (((this.edit_stops[i].is_endpoint)
                 || (!this.edit_stops[i].is_pass_through))
                && (selected_highlighted)) {
               // Label the route stop with a letter, or letters, if there
               // are more than 26 stops. We just start repeating the same
               // letter in the latter case, but I doubt this case has ever
               // been tested.
               // E.g., 'A', 'B', ..., 'Z', 'AA', 'BB', ...
               lettering = '';
               for (var col_num:int = 1; col_num <= places; col_num++) {
                  lettering += Strutil.letters_uc[letter];
               }
               m4_TALKY2('draw_finally: i', i, 'nlttr', letter, 'nplcs',
                         places, 'alttr', lettering, '/', this.edit_stops[i]);
               var rs_label:Map_Label;
               rs_label = new Map_Label(lettering,
                                        /*size=*/12,
                                        /*rotation=*/0,
                                        sx - 2, sy - 0, this);
               m4_TALKY('draw_finally: adding rs label:', rs_label);
               this.rstop_labels.push(rs_label);
               G.map.route_labels.addChild(rs_label);
               // The next time we label a route_stop, use the next letter
               // in the alphabet.
               letter++;
               if (letter >= Strutil.letters_uc.length) {
                  letter = 0;
                  places += 1;
               }
            }
         } // end: for (var i:int = 0; i < this.edit_stops.length; i++)

         this.rstop_sprite.visible = selected_highlighted;
         // [lb] is not quite sure about including this one:
         m4_TALKY('draw_finally: path_arrows.visible:', selected_highlighted);
         this.path_arrows.visible = selected_highlighted;

         if (this.current_dir_step !== null) {
            this.current_dir_step_sprite.graphics.clear();
            this.current_dir_step_sprite.graphics.lineStyle(2, 0x000000);
            this.current_dir_step_sprite.graphics.beginFill(0xffff00);
            this.current_dir_step_sprite.graphics.drawCircle(
                         G.map.xform_x_map2cv(this.current_dir_step[0]),
                         G.map.xform_y_map2cv(this.current_dir_step[1]),
                         6);
            this.current_dir_step_sprite.graphics.endFill();
         }
      }

      //
      protected function draw_pri_or_alt(
         show_primary:Boolean,
         show_alternate:Boolean,
         editable:Boolean) :void
      {
         m4_TALKY3('draw_pri_or_alt: show_pri?:', show_primary,
                   '/ show_alt?:', show_alternate,
                   '/ editable?:', editable);
         if (editable) {
            if (show_primary) {
               this.draw_edit_mode(this.rsteps);
            }
            else if (show_alternate) {
               this.draw_edit_mode(this.alternate_steps);
            }
         }
         else {
            m4_TALKY('draw_finally: path_arrows.graphics.clear');
            this.path_arrows.graphics.clear();
            //m4_TALKY6('draw_pri_or_alt: xs.len:', this.xs.length,
            //          '/ ys.len:', this.ys.length,
            //          '/ rsteps.len:', (this.rsteps !== null)
            //                           ? this.rsteps.length : 'null',
            //          '/ show_primary:', show_primary,
            //          '/ show_alternate:', show_alternate);
            //m4_TALKY('draw_pri_or_alt: this:', this);
            if (show_primary) {
               // Instead of the boring old solid light blue line, which is
               // also the default route line ornamentation, use whatever the
               // user chose from the Visualization dropdown.
               //
               // Boring:
               //    var gr:Graphics = this.sprite.graphics;
               //    Paint.line_draw(gr, this.xs, this.ys,
               //                        this.draw_width, Conf.route_color);
               //
               // More Interestinger:
               if (this.rsteps !== null) {
                  this.routes_viz.route_line_render(
                     this, this.rsteps, /*alternate=*/false);
               }
            }
            else if (show_alternate) {
               // Boring:
               //   Paint.line_draw(gr, this.alternate_xs, this.alternate_ys,
               //                   this.draw_width, Conf.route_color);
               // The new haute:
               if (this.alternate_steps !== null) {
                  this.route_panel.route_viz.route_line_render(
                     this, this.alternate_steps, /*alternate=*/true);
               }
            }
            else {
               m4_TALKY('draw_pri_or_alt: skipping route_line_render:', this);
            }
         }
      }

      //
      override public function init_item(item_agg:Aggregator_Base,
                                         soft_add:Boolean=false)
         :Item_Versioned
      {
         var updated_item:Item_Versioned = super.init_item(item_agg, soft_add);

         if (updated_item === null) {
            m4_TALKY('item_cleanup: add path_arrows to direction_arrows');
            G.map.direction_arrows.addChild(this.path_arrows);
            G.map.vertices.addChild(this.rstop_sprite);
            G.map.vertices.addChild(this.current_dir_step_sprite);

            // NOTE: Map_Controller has its own handlers. We make sure to
            //       coordinate our behavior, so we don't accidentally do
            //       two things when the user is only expecting one.
            m4_TALKY('init: add on_mouse_over- on_mouse_out listnrs:', this);
            if (this.master_item === null) {
               this.sprite.addEventListener(MouseEvent.MOUSE_OVER,
                              this.on_mouse_over, false, 0, true);
               this.sprite.addEventListener(MouseEvent.MOUSE_OUT,
                              this.on_mouse_out, false, 0, true);
            }
         }
         // else, we cloned to an existing item, so don't bother with sprites.

         return updated_item;
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_TALKY('init_add: this:', this);
         super.init_add(item_agg, soft_add);
         if (!soft_add) {
            if (this !== Route.all[this.stack_id]) {
               if (this.stack_id in Route.all) {
                  m4_WARNING('init_add: overwrite:', Route.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Route.all[this.stack_id] = this;
            }
         }
         else {
            var master_route:Route = Route.all[this.stack_id];
            if (master_route !== null) {
               this.master_route = master_route;
               m4_DEBUG('init_add: master_route: set:', this);
            }
            else{
               m4_WARNING('init_add: master_route: none?', this);
            }
         }
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_TALKY('init_update: this:', this);
         var route:Route = Route.all[this.stack_id];
         if (route !== null) {
            m4_VERBOSE(' >> existing:', existing);
            m4_VERBOSE(' >> route:', route);
            m4_ASSERT((existing === null) || (existing === route));
            // If the local item is hydrated, only update if the server item
            // is also hydrated, so that we don't overwrite the item when just
            // updating a Route_List.

// FIXME_2013_06_11: Check that clone() calls clone_update() and all's good.
//            if ((!route.hydrated) || (this.hydrated)) {
//               this.clone_item(route);
//               /*
//               super.init_update(route, item_agg);
//
//               // This is cheating... kind of. Why duplicate code?
//               this.clone_item(route);
//               */
//            }
//            else {
//               m4_TALKY('init_update: not updating: rt:', existing);
//            }
//            this.clone_update(route, /*newbie=*/false);
            this.clone_item(route);
         }
         else {
            m4_WARNING('Route not found: stack_id:', this.stack_id);
            m4_ASSERT_SOFT(false);
         }
         return route;
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         var is_loaded:Boolean = (super.is_item_loaded(item_agg)
                                  || (this.stack_id in Route.all));
         m4_TALKY('is_item_loaded: is_loaded:', is_loaded, '/ this:', this);
         return is_loaded;
      }

      //
      override public function get is_revisionless() :Boolean
      {
         return true;
      }

      //
      override public function label_draw(halo_color:*=null) :void
      {
         m4_TALKY('label_draw');
         m4_ASSERT(halo_color === null);
         halo_color = Conf.label_halo_route;
         // The base class adds a new Map_Label, for the the route name_,
         // and not for the route stops.
         super.label_draw(halo_color);
      }

      //
      override public function label_reset() :void
      {
         // If you're having problems with route labels, either the name_ label
         // or the route stop letter labels, it's easier to debug them in this
         // Class, rather than mucking around in Geofeature. [lb] was having a
         // problem with route labels being removed, but that problem was label
         // conflicts with byways. The problem was solved in that collides fcn.
         m4_TALKY('label_reset');
         super.label_reset();
      }

      //
      override public function get use_ornament_selection() :Boolean
      {
         return false;
      }

      //
      override public function vertices_redraw() :void
      {
         // EXPLAIN: This a no-op for routes, right?
         m4_TALKY2('vertices_redraw: vertices.len:',
                   (this.vertices !== null) ? this.vertices.length : 'null');
         super.vertices_redraw();
      }

      // *** Developer methods

      // 2013.09.05: [lb] used getUID to figure out why deep links were
      //               using the wrong route object (the new one from GWIS
      //               and not the one that's already loaded).
      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' / ' + ((this.rsteps_ !== null)
                  ? String(this.rsteps_.length) : 'empty') + ' steps'
                 + ', ' + ((this.rstops !== null)
                  ? String(this.rstops.length) : 'empty') + ' stops'
                 //+ ' / details: ' + (this.details)
                 //+ ' / beg_addr: ' + (this.beg_addr)
                 //+ ' / fin_addr: ' + (this.fin_addr)
                 //+ ' / rsn_len: ' + (this.rsn_len)
                 //+ ' / computed_length: ' + (this.computed_length)
                 //+ ' / alternate_length: ' + (this.alternate_length)
                 //+ ' / total_time: ' + (this.total_time)
                 + ' / fShw?: ' + (this.filter_show_route_)
                 + ', lib?: ' + (!this.unlibraried)
                 + ', avgc: ' + String(this.avg_cost)
                 + ', stalee: ' + String(this.stale_steps)
                 + ', stalen: ' + String(this.stale_nodes)
                 + ' / ' + ((this.route_panel_ !== null)
                            ? this.route_panel_.toString_Terse() : 'no panel')
                 + ' / ' + ((this.master_route !== null)
                            ? this.master_route.toString_Terse()
                              : 'no master rte')
                 );
      }

      //
      override public function toString_Terse() :String
      {
         return (super.toString_Terse()
                 + ((this.filter_show_route_) ? ' fShowRte' : '')
                 + ' ' + ((this.route_panel_ !== null)
                          ? this.route_panel_.toString_Terse() : 'panelless')
                 + ' ' + ((this.master_route !== null)
                         ? this.master_route.toString_Terse() : 'nomastrrte')
                 );
      }

      //
      override public function toString_Verbose() :String
      {
         return (super.toString_Verbose()
                 + ' / nsteps: '
                 + ((this.rsteps_ !== null)
                    ? String(this.rsteps_.length) : 'null')
                 + ' / nstops: '
                 + ((this.rstops !== null)
                    ? String(this.rstops.length) : 'null')
                 //+ ' / details: ' + (this.details)
                 //+ ' / beg_addr: ' + (this.beg_addr)
                 //+ ' / fin_addr: ' + (this.fin_addr)
                 //+ ' / rsn_len: ' + (this.rsn_len)
                 //+ ' / computed_length: ' + (this.computed_length)
                 //+ ' / alternate_length: ' + (this.alternate_length)
                 //+ ' / total_time: ' + (this.total_time)
                 + ' / fltr_show: ' + (this.filter_show_route_)
                 + ' / lib: ' + (!this.unlibraried)
                 + ' / avgc: ' + String(this.avg_cost)
                 + ' / stlstps: ' + String(this.stale_steps)
                 + ' / stlnds: ' + String(this.stale_nodes)
                 + ' / pnl: ' + ((this.route_panel_ !== null)
                                 ? this.route_panel_.class_name_tail : 'null')
                 + ' / mrt: ' + ((this.master_route !== null)
                                 ? this.master_route.toString_Terse() : 'null')
                 //+ ' / uuid: ' + UIDUtil.getUID(this)
                 + ' / ' + UIDUtil.getUID(this)
                 );
      }

      //
      public function toString_Plops() :String
      {
         var verbose:String = (
            //this.toString_Terse() + 
            //super.toString_Terse() + 
              ' / tvl_mod: ' + (this.travel_mode)
            + ' / p1_pri: ' + (this.p1_priority)
            + ' / p2_dep: ' + (this.p2_depart_at)
            + ' / p2_txp: ' + (this.p2_transit_pref)
            + ' / p3_attr: ' + (this.p3_weight_attr)
            + ' / p3_type: ' + (this.p3_weight_type)
            + ' / p3_rating: ' + (this.p3_rating_pump)
            + ' / p3_burden: ' + (this.p3_burden_pump)
            + ' / p3_spalg: ' + (this.p3_spalgorithm)
            + ' / tags_defs: ' + (this.tags_use_defaults)
            );
         return verbose;
      }

      // *** Instance methods

      //
      protected function compute_len_and_ids() :void
      {
         var step:Route_Step;

         // FIXME: delete this? and just use rsn_len?
         this.computed_length = Number(0);

         // Note that length is only accumulated for biking, alternate
         // modes of transportation are not summed.
         for each (step in this.rsteps) {
            if (step.travel_mode == Travel_Mode.bicycle) {
               this.computed_length += step.step_length;
            }
         }

         this.alternate_length = Number(0);
         if (this.alternate_steps !== null) {
            for each (step in this.alternate_steps) {
               if (step.travel_mode == Travel_Mode.bicycle) {
                  this.alternate_length += step.step_length;
               }
            }
         }

         m4_TALKY4('compute_len_and_ids:',
                   'computed_length:', this.computed_length,
                   '/ alternate:', this.alternate_length,
                   '/ rsn_len', this.rsn_len);
      }

      //
      protected function compute_rstops(xml:XMLList) :Array
      {
         var result:Array = new Array();
         var name:String;
         var stop_xml:XML;

         for each (stop_xml in xml) {

            if ('@name' in stop_xml) {
               name = stop_xml.@name;
            }
            else {
               name = null;
            }

            var rstope:Route_Stop_Editor = new Route_Stop_Editor();
            rstope.name_ = name;
            rstope.node_id = int(stop_xml.@node_id);
            m4_ASSERT_SOFT(rstope.node_id > 0);
            // MAGIC_NUMBER: User version=1 for real route stops.
            rstope.stop_version = 1;
            rstope.x_map = Number(stop_xml.@x);
            rstope.y_map = Number(stop_xml.@y);
            // Skipping: is_endpoint
            rstope.is_pass_through = Boolean(int(stop_xml.@is_pass_through));
            rstope.is_transit_stop = Boolean(int(stop_xml.@is_transit_stop));
            rstope.internal_system_id = int(stop_xml.@int_sid);
            rstope.external_result = Boolean(int(stop_xml.@ext_res));
            // Skipping: street_name_
            rstope.editor = null;
            result.push(rstope);

            m4_VERBOSE('compute_rstops: stop_xml.node_id:', stop_xml.@node_id);
         }

         return result;
      }

      //
      public function compute_smart_name() :void
      {
         var step:Route_Step;
         var max_len:int = 0;
         var step_names:Dictionary = new Dictionary();
         var smart_name:String = null;
         var step_name:String;

         // Do only for routes not in library.
         if (!this.can_view) {

            // Build step name dictionary.
            for each (step in this.rsteps) {
               if (!(step.step_name in step_names)) {
                  step_names[step.step_name] = 0;
               }
               step_names[step.step_name] += step.step_length;
            }

            // Find longest step.
            for (step_name in step_names) {
               if (step_names[step_name] > max_len) {
                  max_len = step_names[step_name];
                  smart_name = step_name;
               }
            }

            this.name_ = 'Route via ' + smart_name;
         }
         // else... we'll use the name saved in the database, or the local
         // item's name.
      }

      //
      protected function compute_step_dir(step:Route_Step,
                                          leaving_step:Boolean,
                                          xs:Array,
                                          ys:Array) :Array
      {
         var start_at_zero:Boolean = !leaving_step;

         var i:int = (start_at_zero ? step.beg_index : step.fin_index - 1);
         var dir:int = (start_at_zero ? 1 : -1);
         var mul:Number = (leaving_step ? 1 : -1);

         var vec_len:Number = 0;
         var result:Array = [xs[i], ys[i],];

         // 2014?: BUGMAYBE: I [lb] opened a bunch of routes, was later on the
         //        Routes panel, then click side panels' 'x'es to close panels
         //        not active, and null object reference
         // update_route_stats: Route:1569236.6$ "Roseville-TheDepot" 
         //                      fShowRte Panel_Item_Route6877 1 selected
         //m4_VERBOSE('compute_step_dir: result:', result);


         while (vec_len < Conf.route_step_dir_length) {
            vec_len += Geometry.distance((xs[i] - xs[i + dir]) * mul,
                                         (ys[i] - ys[i + dir]) * mul,
                                         0, 0);
            i += dir;
            if (step.is_endpoint(i)) {
               break;
            }
         }
         result[0] = (result[0] - xs[i]) * mul;
         result[1] = (result[1] - ys[i]) * mul;

         return result;
      }

      //
      protected function compute_xys(xml:XMLList,
                                     rsteps:Array,
                                     xs:Array,
                                     ys:Array)
         :void
      {
         var i:int;
         var step_xml:XML;
         var prev_step:Route_Step = null;
         var step:Route_Step;

         var step_xs:Array;
         var step_ys:Array;

         for each (step_xml in xml) {
            step = new Route_Step(step_xml);
            rsteps.push(step);

            step_xs = new Array();
            step_ys = new Array();

            step.beg_index = xs.length;

            Geometry.coords_string_to_xys(step_xml.text(), step_xs, step_ys);

            if (!step.forward) {
               step_xs.reverse();
               step_ys.reverse();
            }

            for (i = 0; i < step_xs.length; i++) {
               // Don't push 1st coord of intermediate steps.
               if (i == 0 && (prev_step !== null)) {
                  step.beg_index--;
                  continue;
               }

               xs.push(step_xs[i]);
               ys.push(step_ys[i]);
            }
            step.fin_index = xs.length;

            // FIXME: This was missing from route manip. Make sure this works.
            prev_step = step;
         }
      }

      // Rebuilds the direction rsteps array
      protected function directions_build(rsteps:Array,
                                          xs:Array,
                                          ys:Array) :Array
      {
         ////m4_VERBOSE('directions_build: xs:', xs, '/ ys:', ys);

         var step:Route_Step;

         var dir_step:Direction_Step;
         var landmarks:Array = null;

         var n_v:Array = [NaN, NaN,]; // [nx, ny,]
         var p_v:Array = [NaN, NaN,]; // [px, py,]

         var classify:int;

         var dirs:Array = new Array();

         // Tracking the number of route_stops, but skip the first one (so
         // start the index at 1).
         var stop_num:int = 1;
         var stop_name:String;

         var stop_type:int;
         var num_transit_stops:int = 0; // Keep track of board/alight stops.

         var step_num:int = 1;
         var rstep_i:int;

         //?: this.landmarks_loaded = false;

         for (rstep_i = 0; rstep_i < rsteps.length; rstep_i++) {

            step = rsteps[rstep_i];
            m4_ASSERT(step !== null);

            m4_VERBOSE(' .. dir_build: step:', step);

            // Compute the direction vector for the start of the current step.
            // MAYBE: We do this for every step. Is this really necessary?
            n_v = this.compute_step_dir(step, false, xs, ys);
            classify = G.angle_class_idx(n_v[0], n_v[1]);

            m4_VERBOSE(' .. dir_build: n_v:', n_v[0], n_v[1]);

            // We consider a step to be the same if it has the same name,
            // AND (its going in the same direction OR its relative angle
            // is too large).
            if (dirs.length == 0) {
               // The very first step, so it has a special relative class.
               // FIXME: Does step.travel_mode matter?
               //        What if this is a transit stop? (Or is that not
               //        possible?)
               dir_step = new Direction_Step(
                  Conf.bearing.length - 2,
                  classify,
                  step.step_length,
                  step.step_name,
                  0, // stop_type=0 is non multimodal
                  step.beg_time,
                  step.fin_time,
                  null,
                  [this.xs[step.beg_index],
                   this.ys[step.beg_index],],
                  null,
                  this,
                  rstep_i,
                  /*route_caller=*/'directions_build-no_dirs')
               dirs.push(dir_step);
               dirs[dirs.length - 1].geofeature_layer_id =
                  step.byway_geofeature_layer_id;
               //m4_VERBOSE(' .. dir_build: first step:', dir_step.text);
            }
            else if (step.travel_mode == Travel_Mode.bicycle) {
               // Don't include transit mode steps in the directions
               ////m4_VERBOSE(' .. dir_build: bike step: p_v:', p_v);
               ////m4_VERBOSE(' .. dir_build: bike step: n_v:', n_v);
               //m4_ASSERT((p_v[0] != 0) || (p_v[1] != 0));
               var rel_angle:Number;
               rel_angle = Geometry.ang_rel(p_v[0], p_v[1], n_v[0], n_v[1]);
               if (!Strutil.equals_ignore_case(step.step_name,
                                               dirs[dirs.length - 1].name)
                   || ((step.step_name == '')
                       && (step.byway_geofeature_layer_id
                           != dirs[dirs.length - 1].geofeature_layer_id))
                   || ((Math.abs(rel_angle - 90) > Conf.dir_merge_angle)
                       && (step.step_length > Conf.dir_merge_length))
                   || dirs[dirs.length - 1].is_route_stop) {
                  // get the relative angle between the direction we were
                  // traveling and the landmark
                  if (landmarks !== null) {
                     for each (l in landmarks) {
                        if (l.xs !== null) {
                           for (var i:int=0; i<l.xs.length; i++) {
                              // calculate angle
                              var landmark_angle:Number = 0;
                              l.angles.push(Geometry.ang_rel(
                                 p_v[0],
                                 p_v[1],
                                 l.xs[i] - this.xs[step.beg_index],
                                 l.ys[i] - this.ys[step.beg_index]));
                           }
                        }
                     }
                  }
                  dir_step = new Direction_Step(
                     G.angle_class_id(rel_angle),
                     classify,
                     step.step_length,
                     step.step_name,
                     0, // stop_type=0 is non multimodal
                     step.beg_time,
                     step.fin_time,
                     dirs[dirs.length - 1],
                     [this.xs[step.beg_index],
                      this.ys[step.beg_index],],
                     landmarks,
                     this,
                     rstep_i,
                     /*route_caller=*/'directions_build-by_bike');
                  dirs.push(dir_step);
                  //m4_VERBOSE2(' .. dir_build: stop_num:', stop_num,
                  //            '/', dir_step.text);
               }
               else {
                  // If part of the same step, add to the dist/time of previous
                  ////m4_VERBOSE(' .. dir_build: other step');
                  dirs[dirs.length - 1].rel_distance += step.step_length;
                  dirs[dirs.length - 1].fin_time = step.fin_time;
               }
               dirs[dirs.length - 1].geofeature_layer_id =
                  step.byway_geofeature_layer_id;
               //m4_VERBOSE3(' .. dir_build: bike step:', dir_step.text,
               //            '/ rt.stack_id:', this.stack_id,
               //            '/ step_num:', step_num);
               step_num += 1;
            }

            // Check if we've reached a route stop.
            var found_rstop:Boolean = false;
            try {
               found_rstop = (
                   ((step.fin_node_id == this.rstops[stop_num].node_id)
                    && (step.forward))
                || ((step.beg_node_id == this.rstops[stop_num].node_id)
                    && (!step.forward)));
            }
            catch (e:TypeError) {
               // this.rstops is empty.
               m4_WARNING(' .. step_num:', step_num);
               m4_WARNING(' .. rsteps.length:', rsteps.length);
               m4_WARNING(' .. edit_stops.length:', this.edit_stops.length);
               m4_WARNING(' .. step.forward:', step.forward);
               m4_WARNING(' .. step.beg_node_id:', step.beg_node_id);
               m4_WARNING(' .. step.fin_node_id:', step.fin_node_id);
               m4_WARNING(' .. stop_num:', stop_num);
               if (this.rstops !== null) {
                  m4_WARNING(' .. rstops.length:', this.rstops.length);
                  m4_WARNING(' .. rstops[stop_num]:', this.rstops[stop_num]);
                  if (this.rstops[stop_num] !== null) {
                     m4_WARNING2(' .. rstops[stop_num].node_id:',
                                 this.rstops[stop_num].node_id);
                  }
               }
               else {
                  // This happened on loading a saved, edited, non-libraried
                  // route.
                  // BUG nnnn/FIXMEFIXME: route_stop version 2 not being saved!
                  m4_WARNING(' .. rstops: null');
               }
               m4_ASSERT(false);
            }

            if (found_rstop) {

               if ((this.rstops[stop_num].is_endpoint)
                   || (!this.rstops[stop_num].is_pass_through)) {
                  stop_name = this.rstops[stop_num].name_;
                  if (stop_name === null) {
                     stop_name = this.street_name(stop_num);
                  }
                  ////m4_VERBOSE(' .. dir_build: found stop_name:', stop_name);
               }
               else {
                  stop_name = null;
                  ////m4_VERBOSE(' .. dir_build: found pass_through stop');
               }

               // Select a different direction code if it's the last route
               // stop.
               if (this.rstops[stop_num].is_transit_stop) {
                  num_transit_stops++;
                  // If even # of stops, we're alighting transit else boarding.
                  // FIXME: MAGIC_NUMBER: Replace these with new class type.
                  // I.e.,
                  //    stop_type = ((num_transit_stops % 2) == 0
                  //                 ? Stop_Type.alight
                  //                 : Stop_Type.board);
                  stop_type = ((num_transit_stops % 2) == 0 ? -1 : 1);
                  ////m4_VERBOSE2(' .. dir_build: transit stop:',
                  ////            ((stop_type == -1) ? 'alight' : 'board'));
               }
               else {
                  // FIXME: MAGIC_NUMBER: Replace this with new class type.
                  // I.e.,
                  //    stop_type = Stop_Type.not_transit
                  stop_type = 0; // MAGIC_NUMBER: 0 means not a transit stop.
                  ////m4_VERBOSE(' .. dir_build: not a transit stop');
               }

               stop_num++;
               if (stop_num == this.rstops.length) {
                  if (stop_name === null) {
                     stop_name = 'Destination';
                  }
                  dir_step = new Direction_Step(
                     Conf.bearing.length - 1,   // rel_direction
                     Conf.bearing.length - 1,   // abs_direction
                     0,                         // rel_distance
                     stop_name,
                     stop_type,
                     step.beg_time,
                     step.fin_time,
                     dirs[dirs.length - 1],     // prev(Direction_Step)
                     [this.xs[step.fin_index-1],
                      this.ys[step.fin_index-1],],
                     null,
                     this,
                     rstep_i,
                     /*route_caller=*/'directions_build-unnamed_dest');
                  dirs.push(dir_step);
               }
               else if ((stop_name !== null) || (stop_type != 0)) {
               //else if ((stop_name !== null)
               //         || (stop_type != Stop_Type.no_transit)) { }
                  // We skip intermediate rstops that don't have names
                  // and are not transit stops.
                  // MAGIC_NUMBERS:     The 3rd-from-last Conf.bearing entry is
                  // 'Bicycle stop' and the 4th-from-last Conf.bearing entry is
                  // 'Transit stop'.
                  classify = ((stop_type == 0) ? Conf.bearing.length - 3
                                               : Conf.bearing.length - 4);
                  //classify = ((stop_type == Stop_Type.no_transit)
                  //               ? Conf.bearing.length - 3
                  //               : Conf.bearing.length - 4);
                  dir_step = new Direction_Step(
                     classify,                  // rel_direction
                     classify,                  // abs_direction
                     0,                         // rel_distance
                     stop_name,
                     stop_type,
                     step.beg_time,
                     step.fin_time,
                     dirs[dirs.length - 1],     // prev(Direction_Step)
                     [this.xs[step.fin_index-1],
                      this.ys[step.fin_index-1],],
                     null,
                     this,
                     rstep_i,
                     /*route_caller=*/'directions_build-named_dest');
                  dirs.push(dir_step);
               }
            }

            // Compute the direction vector for the end of the current
            // step (used potentially for the next step to get the
            // relative turn angle)
            p_v = this.compute_step_dir(step, true, xs, ys);
            ////m4_VERBOSE(' .. dir_build: end of step: p_v:', p_v);
            ////m4_VERBOSE(' .. dir_build: end of step: n_v:', n_v);

            // Landmarks experiment.
            // set next landmarks
            if ((step.landmarks !== null)
                && (step.landmarks.length > 0)
                && (this.show_landmarks)) {
               landmarks = step.landmarks;
               // calculate distances (use for points for now)
               var l:Landmark;
               for each (l in landmarks) {
                  if (l.xs !== null) {
                     l.dist = Geometry.distance(l.xs[0],
                                                l.ys[0],
                                                this.xs[step.beg_index],
                                                this.ys[step.beg_index]);
                  }
               }

               // This isn't the only place that we'll set landmarks true,
               // since, if we look for landmarks but find none for all of
               // the route steps, then we won't set loaded to true.
               this.landmarks_loaded = true;
            }
            else {
               landmarks = null;
            }
         } // end: for (rstep_i = 0; rstep_i < rsteps.length; rstep_i++)

         return dirs;
      }

      //
      protected function draw_alternate_diff(gr:Graphics,
                                             main_steps:Array,
                                             other_steps:Array,
                                             xs:Array,
                                             ys:Array,
                                             main_color:int,
                                             draw_neutral:Boolean) :void
      {
         var step_in_other:Boolean = false;
         var i:int;
         var m:Route_Step;
         var o:Route_Step;
         var x:Number;
         var y:Number;

         for each (m in main_steps) {
            step_in_other = false;
            for each (o in other_steps) {
               if (o.byway_stack_id == m.byway_stack_id) {
                  step_in_other = (o.byway_version == m.byway_version);
                  break;
               }
            }

            if (!step_in_other || draw_neutral) {
               x = G.map.xform_x_map2cv(xs[m.beg_index]);
               y = G.map.xform_y_map2cv(ys[m.beg_index]);

               gr.lineStyle(this.draw_width,
                            (step_in_other ? Conf.vgroup_dark_static_color
                                           : main_color),
                            Conf.route_alpha);
               gr.moveTo(x, y);
               for (i = m.beg_index + 1; i < m.fin_index; i++) {
                  x = G.map.xform_x_map2cv(xs[i]);
                  y = G.map.xform_y_map2cv(ys[i]);
                  gr.lineTo(x, y);
               }
            }
         }
      }

      //
      protected function draw_circle(color:int, x:int, y:int, radius:int) :void
      {
         var gr:Graphics = this.sprite.graphics;

         gr.beginFill(color);
         gr.lineStyle(2, 0x000000);
         gr.drawCircle(x, y, radius);
         gr.endFill();
      }

      //
      protected function draw_edit_mode(rsteps:Array) :void
      {
         var normal_steps:Array = new Array();
         var dirty_steps:Array = new Array();
         var s:Route_Step;

         var prev:Route_Stop_Editor = this.rstops[0];
         var next:Route_Stop_Editor = this.rstops[1];
         var i:int = 2;
         var j:int;
         var k:int;

         var in_dirty_seg:Boolean;

         var gr:Graphics = this.sprite.graphics;
         var sx:Number;
         var sy:Number;
         var ex:Number;
         var ey:Number;

         m4_TALKY2('draw_edit_mode: rsteps.length:',
                   (rsteps !== null) ? rsteps.length : 'null');
         m4_TALKY2('draw_edit_mode: rstops.length:',
                   (rstops !== null) ? rstops.length : 'null');
         m4_TALKY3('draw_edit_mode: this.edit_stops.length:',
                   (this.edit_stops !== null)
                    ? this.edit_stops.length : 'null');

         // Render route steps first.
         for each (s in rsteps) {

            //m4_TALKY3('draw_edit_mode: i:', i,
            //        '/ prev:', (prev !== null) ? prev : 'null',
            //        '/ prev.editor', (prev !== null) ? prev.editor : 'null');
            //m4_TALKY2('.. / next:', (next !== null) ? next : 'null',
            //        '/ next.editor', (next !== null) ? next.editor : 'null');

            in_dirty_seg = (
                  (   (prev === null)
                   || (prev.editor === null)
                   || (prev.editor.dirty_stop))
               || (   (next === null)
                   || (next.editor === null)
                   || (next.editor.dirty_stop))
               );

            if (!in_dirty_seg) {
               // The rstops haven't been modified but a route stop could
               // have been inserted; check for that.
               j = this.edit_stops.indexOf(prev.editor);
               k = this.edit_stops.indexOf(next.editor);
               in_dirty_seg = ((j < 0) || (k < 0) || (k != j + 1));
            }

            if (in_dirty_seg) {
               dirty_steps.push(s);
            }
            else {
               normal_steps.push(s);
            }

            // Check to see if this route step reaches a route stop.
            if (    ((s.forward) && (s.fin_node_id == next.node_id))
                || ((!s.forward) && (s.beg_node_id == next.node_id))) {
               if (i < this.rstops.length) {
                  prev = next;
                  next = this.rstops[i++];
               }
               // else: we're already done.
            }

         } // for each (s in rsteps)

         // Draw dirty parts in the old diff color.
         if (dirty_steps.length > 0) {
            var rviz_dirty:Route_Viz = new Route_Viz(
               -1, 'dirty', null,
               function(step:Route_Step) :int
                  { return Conf.vgroup_move_old_color; });
            m4_TALKY('draw_edit_mode: dirty_steps.len:', dirty_steps.length);
            rviz_dirty.route_line_render(
               this,
               dirty_steps,
               (rsteps === this.alternate_steps));
         }

         // Draw unchanged parts with a solid color.
         if (G.map.rmode == Conf.map_mode_feedback) {
            // Color with plain color.
            // FIXME: RtFbDrag: [lb]: Make this more readable.
            //        And make lambda fcn. static class fcn. or something.
            var rviz_unchanged:Route_Viz = new Route_Viz(
               -1, 'new', null,
               function(step:Route_Step) :int
                  { return Conf.route_feedback_new_color; });
            rviz_unchanged.route_line_render(
               this,
               normal_steps,
               (rsteps === this.alternate_steps));
         }
         else {
            if (normal_steps.length > 0) {
               m4_TALKY('draw_edit_mode: normal_steps:', normal_steps.length);
               this.route_panel.route_viz.route_line_render(
                  this,
                  normal_steps,
                  (rsteps === this.alternate_steps));
            }
         }

         // Now draw dotted lines to fill in dirty parts of the route.

         m4_TALKY('draw_edit_mode: clear path_arrows graphics before redraw');
         this.path_arrows.graphics.clear();

         this.current_dir_step_sprite.graphics.clear();

         m4_TALKY('draw_edit_mode: edit_stops.len:', this.edit_stops.length);
         for (i = 1; i < this.edit_stops.length; i++) {

            if ((!this.edit_stops[i - 1].is_stop_valid)
                || (!this.edit_stops[i].is_stop_valid)) {
               continue;
            }

            j = this.rstops.indexOf(this.edit_stops[i - 1].orig_stop);
            k = this.rstops.indexOf(this.edit_stops[i].orig_stop);
            // Note that k == i except when the route is edited, because
            // edit_stops will have deviated from rstops.

            // don't draw a line if points aren't dirty and order hasnt changed
            // [lb]'s non-negative rewording of previous comment:
            //  Only draw a (dashed) line (indicating route request is
            //  outstanding for a route segment) if points are dirty or if
            //  order has changed.
            m4_TALKY6('draw_edit_mode: j:',
                      Strutil.string_pad(j, 3, ' ', false),
                      '/ k:', Strutil.string_pad(k, 3, ' ', false),
                      '/ edit_stops[i-1].dirty_stop:',
                      this.edit_stops[i-1].dirty_stop,
                      '/ [i].dirty_stop:', this.edit_stops[i].dirty_stop);
            if (   (!this.edit_stops[i-1].dirty_stop)
                && (!this.edit_stops[i].dirty_stop)
                && ((j + 1) == k)) {
               continue;
            }

            sx = this.edit_stops[i - 1].x_cv;
            sy = this.edit_stops[i - 1].y_cv;
            ex = this.edit_stops[i].x_cv;
            ey = this.edit_stops[i].y_cv;

            // This is a fat dashed line we draw straight-as-the-crow-flies
            // from the existing neighbor node to where the user has the mouse.
            m4_TALKY('draw_edit_mode: line_draw_dashed: line_draw_dashed');
            Paint.line_draw_dashed(gr, 20, sx, sy, ex, ey,
                                   0.75 * this.draw_width,
                                   Conf.route_edit_color);

            // This is an arrow we draw pointing from the neighbor to the new
            // node/mouse position.
            m4_TALKY('draw_edit_mode: redraw path_arrows: arrow_tip_draw');
            Paint.arrow_tip_draw(this.path_arrows.graphics,
                                 (sx + ex) / 2.0, (sy + ey) / 2.0,
                                 ex - sx, ey - sy,
                                 int(this.draw_width * 1.5),
                                 this.draw_width * 2,
                                 Conf.route_edit_color, 1);
         }

         // m4_TALKY('draw_edit_mode: this.visible:', this.visible);
         // m4_TALKY2('draw_edit_mode: this.sprite.visible:',
         //           this.sprite.visible);
      }

      //
      protected function draw_geometry_diff() :void
      {
         var diff_color_map:Function = Route_Viz_Diff_Map.color_diff(this);
         var route_viz:Route_Viz;
         route_viz = new Route_Viz(-1, 'diff', null, diff_color_map);
         route_viz.route_line_render(this, this.rsteps, /*alternate=*/false);
      }

      //
      override public function label_maybe() :void
      {
         m4_TALKY('label_maybe:', this);
         super.label_maybe();
      }

      //
      override protected function label_parms_compute() :void
      {
         m4_TALKY('label_parms_compute:', this);
         this.label_parms_compute_line_segment();
      }

      //
      override public function panel_get_for_geofeatures(
         feats_being_selected:*,
         loose_selection_set:Boolean=false,
         skip_new:Boolean=false)
            :Panel_Item_Geofeature
      {
         m4_ASSERT(feats_being_selected.length == 1);
         var route:Route = feats_being_selected.item_get_random();
         m4_ASSERT(route !== null);
         m4_TALKY('gpfgfs: route.route_panel:', route.route_panel);
         m4_ASSERT(!route.route_panel.panel_close_pending); // Am I right?
         return route.route_panel;
      }

      //
      // FIXME: Test two routes whose stops align. Is this pre-route manip code
      //        useful? If it's handled okay, delete this function.
      //        [lb] is not sure this behavior was preserved post-route manip.
      //        See also: rs_under_mouse.
      /*/
      //
      protected function merge_stop(step:Route_Step, tx:Number, ty:Number,
                                    rstops:Array) :void
      {
         // merge this stop into stops array based on location
         // we want to group them by proximity so that stops right on
         // top of each other are displayed differently.
         // - won't fix very close stops that might overlap, but this
         //   is a situation easier for the user to tell what's going on
         var stop_found:Boolean = false;
         for (var j:int = 0; j < rstops.length; j++) {
            if (Math.abs(rstops[j].x - tx) < 10
                && Math.abs(rstops[j].y - ty) < 10) {
               rstops[j].rsteps.push(step);
               stop_found = true;
               break;
            }
         }

         if (!stop_found) {
            // must create a new stop
            rstops.push({rsteps: [step], x: tx, y: ty});
         }
      }
      /*/

      //
      protected function rs_highlight(rs:Route_Step, highlight:Boolean) :void
      {
         var color:int;
         if (Route.selected_steps.indexOf(rs) == -1) {
            color = ((this.feedback_instance == Route.FB_NEW)
                     ? Conf.route_feedback_new_color
                     : Conf.route_feedback_old_color);
         }
         else {
            color = ((this.feedback_instance == Route.FB_NEW)
                     ? Conf.route_feedback_new_color_selected
                     : Conf.route_feedback_old_color_selected);
         }

         Paint.line_draw(this.sprite.graphics,
                         this.xs.slice(rs.beg_index, rs.fin_index + 1),
                         this.ys.slice(rs.beg_index, rs.fin_index + 1),
                         this.draw_width,
                         (highlight ? Conf.mouse_highlight_color : color));
      }

      //
      protected function rs_highlight_maybe(evt:MouseEvent) :void
      {
         var rs:Route_Step = this.rs_under_mouse(evt);

         // De-highlight old step.
         if ((Route.highlighted_step !== null)
             && (Route.highlighted_step !== rs)) {
            this.rs_highlight(Route.highlighted_step, false);
         }

         // Highlight new step.
         if ((rs !== null)
             && (Route.highlighted_step !== rs)) {
            this.rs_highlight(rs, true);
         }

         // Update highlighted step.
         Route.highlighted_step = rs;
      }

      //
      protected function rs_select(rs:Route_Step, select:Boolean) :void
      {
         Paint.line_draw(this.sprite.graphics,
                         this.xs.slice(rs.beg_index, rs.fin_index + 1),
                         this.ys.slice(rs.beg_index, rs.fin_index + 1),
                         this.draw_width,
                         (select
                          ? ((this.feedback_instance == Route.FB_NEW)
                             ? Conf.route_feedback_new_color_selected
                             : Conf.route_feedback_old_color_selected)
                          : ((this.feedback_instance == Route.FB_NEW)
                             ? Conf.route_feedback_new_color
                             : Conf.route_feedback_old_color)));

         // Remove the pointing widget, if any.
         if (this.route_panel.widget_feedback.feedback.pw !== null) {
            this.route_panel.widget_feedback.feedback.pw.on_close();
         }
      }

      //
      protected function rs_toggle_select(evt:MouseEvent) :void
      {
         var rs:Route_Step = this.rs_under_mouse(evt);

         if (rs !== null) {
            if (Route.selected_steps.indexOf(rs) == -1) {
               this.rs_select(rs, true);
               Route.selected_steps.push(rs);
            }
            else {
               this.rs_select(rs, false);
               Route.selected_steps.splice(
                  Route.selected_steps.indexOf(rs), 1);
            }
         }

         this.route_panel.widget_feedback.feedback.update_segment_list();
      }

      // Find route step under mouse pointer.
      protected function rs_under_mouse(evt:MouseEvent) :Route_Step
      {
         var p:Array = new Array(2);
         var dist:Number;
         var min_dist:Number = Infinity;
         var min_i:int = -1;

         var mx:Number = G.map.xform_x_stage2map(evt.stageX);
         var my:Number = G.map.xform_y_stage2map(evt.stageY);

         var rs:Route_Step = null;

         // Find closest route geometry segment.
         for (var i:int = 0; i < this.xs.length - 1; i++) {
            dist = Geometry.distance_point_line(
                        mx, my,
                        this.xs[i], this.ys[i],
                        this.xs[i + 1], this.ys[i + 1]);
            if (dist < min_dist) {
               min_dist = dist;
               min_i = i;
            }
         }

         // Find the route step (min_i, min_i + 1) belongs to.
         if ((min_i > -1)
             && (min_dist < G.map.xform_scalar_cv2map(this.draw_width / 2))) {
            for each (rs in this.rsteps) {
               if (   (min_i >= rs.beg_index)
                   && (min_i + 1 >= rs.beg_index)
                   && (min_i <= rs.fin_index)
                   && (min_i + 1 <= rs.fin_index)) {
                  return rs;
               }
            }
         }

         return null;
      }

      // Update edit_stops and last_cmd_stops to match rstops.
      public function rstops_sync() :void
      {
         m4_TALKY('rstops_sync: no. rstops:', this.rstops.length);

         // Remove old rstops from the route stop sprite layer.
         for (var i:int = this.rstop_sprite.numChildren - 1; i >= 0; i--) {
            this.rstop_sprite.removeChildAt(i);
         }

         // Setup edit_stops and last_cmd_stops.

         this.edit_stops_set(new Array());
         this.last_cmd_stops = new Array();

         for each (var curr_rstope:Route_Stop_Editor in this.rstops) {

            var new_rstop:Route_Stop;

            if (curr_rstope.editor === null) {
               if (this.master_route === null) {
                  new_rstop = new Route_Stop(this, curr_rstope);
               }
               else {
                  new_rstop = new Route_Stop(this.master_route, curr_rstope);
               }
               m4_ASSERT_SOFT(this.master_route === this.master_item);
            }
            else {
               m4_DEBUG2('rstops_sync: curr_rstope.editor:',
                         curr_rstope.editor);
               new_rstop = curr_rstope.editor;
            }

            var last_rstop:Route_Stop_Editor = new Route_Stop_Editor();
            last_rstop.name_ = curr_rstope.name_;
            last_rstop.node_id = curr_rstope.node_id;
            m4_ASSERT_SOFT(last_rstop.node_id > 0);
            last_rstop.stop_version = curr_rstope.stop_version;
            last_rstop.x_map = curr_rstope.x_map;
            last_rstop.y_map = curr_rstope.y_map;
            last_rstop.is_endpoint = curr_rstope.is_endpoint;
            last_rstop.is_pass_through = curr_rstope.is_pass_through;
            last_rstop.is_transit_stop = curr_rstope.is_transit_stop;
            last_rstop.internal_system_id = curr_rstope.internal_system_id;
            last_rstop.external_result = curr_rstope.external_result;
            last_rstop.street_name_ = curr_rstope.street_name_;
            last_rstop.editor = new_rstop;
            last_rstop.orig_stop = curr_rstope;
            last_rstop.dirty_stop = false;

            m4_DEBUG('rstops_sync: last_rstop:', last_rstop);

            // EXPLAIN: How exactly does editor work? It's so the last_rstop
            // and curr_rstope objects can both reference the same Route_Stop?
            curr_rstope.editor = new_rstop;

            m4_DEBUG('rstops_sync: curr_rstope:', curr_rstope);

            new_rstop.name_ = curr_rstope.name_;
            //
            if (new_rstop.node_id == 0) {
               new_rstop.node_id = curr_rstope.node_id;
            }
            else {
               m4_ASSERT_SOFT(new_rstop.node_id == curr_rstope.node_id);
            }
            //
            if (new_rstop.stop_version == 0) {
               m4_ASSERT_SOFT(false);
               new_rstop.stop_version = curr_rstope.stop_version;
            }
            else {
               m4_ASSERT_SOFT(new_rstop.stop_version
                              == curr_rstope.stop_version);
            }
            //
            new_rstop.x_map = curr_rstope.x_map;
            new_rstop.y_map = curr_rstope.y_map;
            new_rstop.is_endpoint = curr_rstope.is_endpoint;
            new_rstop.is_pass_through = curr_rstope.is_pass_through;
            new_rstop.is_transit_stop = curr_rstope.is_transit_stop;
            new_rstop.internal_system_id = curr_rstope.internal_system_id;
            new_rstop.external_result = curr_rstope.external_result;
            m4_TALKY2('rstops_sync: new_rstop.street_name_ = :',
                      curr_rstope.street_name_);
            new_rstop.street_name_ = curr_rstope.street_name_;
            new_rstop.orig_stop = curr_rstope;
            new_rstop.dirty_stop = false;

            m4_DEBUG('rstops_sync: new_rstop:', new_rstop);

            this.edit_stops_push(new_rstop);
            this.last_cmd_stops.push(last_rstop);
         }
      }

      // Return an array of Route_Steps such that the first step in the list
      // starts at the given start node, and the last step ends at the given
      // end node. This assumes that start node and the end node exist in route
      public function steps_between(start_node:int, end_node:int) :Array
      {
         var s:Route_Step;
         var looking_for_start:Boolean = true;
         var results:Array = new Array();

         m4_TALKY3('steps_between: beg nd:', start_node,
                   '/ end nd:', end_node,
                   '/ no. rsteps', this.rsteps.length);

         for each (s in this.rsteps) {

            m4_VERBOSE('rstep', s.beg_node_id, s.fin_node_id, s.forward);

            if (looking_for_start) {
               // only add step if it matches the start node
               if ((s.forward && s.beg_node_id == start_node)
                   || (!s.forward && s.fin_node_id == start_node)) {
                  looking_for_start = false;
                  m4_VERBOSE3('found beg rstep: beg_node_id:', s.beg_node_id,
                              '/ fin_node_id:', s.fin_node_id,
                              '/ fwd?:', s.forward);
               }
            }
            if (!looking_for_start) {
               // Add all steps, but return if we've found the end.
               //m4_VERBOSE2('adding rstep',
               //            s.beg_node_id, s.fin_node_id, s.forward);
               results.push(s);
               if ((s.forward && s.fin_node_id == end_node)
                   || (!s.forward && s.beg_node_id == end_node)) {
                  // The results are ready.
                  m4_VERBOSE3('found fin rstep: beg_node_id:', s.beg_node_id,
                              '/ fin_node_id:', s.fin_node_id,
                              '/ fwd?:', s.forward);
                  break;
               }
            }
         }

         if (results.length == 0) {
            // EXPLAIN: Added 2012.10.26 for route reactions, but [lb] is
            //          curious why this would happen.
            m4_WARNING('EXPLAIN: steps_between: no results?');
            G.sl.event(
               'route/steps_between/failure',
               {route_id: this.stack_id,
                version: this.version,
                start_node_id: start_node,
                end_node_id: end_node,
                result_length: results.length});
         }

         return results;
      }

      //
      public function street_name(rt_stop_or_num:Object) :String
      {
         var rs_editor:Route_Stop_Editor;
         rs_editor = (rt_stop_or_num as Route_Stop_Editor);
         if (rs_editor === null) {
            rs_editor = (this.rstops[rt_stop_or_num as int]
                         as Route_Stop_Editor);
         }
         // MEH: This fcn. is/was inefficient (who cares?), because it walks
         // the list of route steps. So we cache the street name. It's up to
         // the rest of the code to invalidate the cache value when
         // appropriate.
         var street_name:String = rs_editor.street_name_;
         // NOTE: Callers generally check rs_editor.name_ first and then
         //       call us if that's empty. Which is why this fcn. ignores it.
         if (!street_name) {
            var rt_step:Route_Step;
            for each (rt_step in this.rsteps) {
               if (   (rt_step.beg_node_id == rs_editor.node_id)
                   || (rt_step.fin_node_id == rs_editor.node_id)) {
                  m4_TALKY2('street_name: rs_editor.node_id:',
                            rs_editor.node_id);
                  m4_TALKY3('street_name: beg_node_id fin_node_id step_name:',
                            rt_step.beg_node_id, rt_step.fin_node_id,
                            rt_step.step_name, rt_step);
                  street_name = rt_step.step_name;
                  break;
               }
            }
            if (!street_name) {
               if (rs_editor === this.rstops[0]) {
                  street_name = this.rsteps[0].step_name;
                  m4_TALKY('street_name: first step:', street_name);
               }
               else if (rs_editor === this.rstops[this.rstops.length-1]) {
                  street_name = this.rsteps[this.rsteps.length-1].step_name;
                  m4_TALKY('street_name: last step:', street_name);
               }
               if (!street_name) {
                  street_name = Conf.route_stop_map_name;
                  m4_TALKY('street_name: default stop name:', street_name);
               }
            }
            m4_TALKY('street_name: street_name_ = :', street_name);
            if (street_name != 'Point on map') {
               rs_editor.street_name_ = 'Point near ' + street_name;
            }
            else {
               rs_editor.street_name_ = street_name;
            }
         }
         return street_name;
      }

      //
      public function temporary_rstop_clear() :void
      {
         m4_DEBUG('temporary_rstop_clear: temporary_rstop');
         this.removeEventListener(MouseEvent.MOUSE_MOVE,
                                  this.on_mouse_move);
         this.temporary_rstop.graphics.clear();
         UI.cursor_set_native_arrow();
      }

      //
      protected function temporary_rstop_draw(event:MouseEvent) :void
      {
         m4_DEBUG('temporary_rstop_draw: temporary_rstop');

         var p:Array = new Array(2);
         var in_segment:Boolean = false;

         var closest_p:Array = null;
         var closest_l:Number;

         var mx:Number = G.map.xform_x_stage2map(event.stageX);
         var my:Number = G.map.xform_y_stage2map(event.stageY);

         for (var i:int = 1; i < this.xs.length; i++) {
            in_segment = Geometry.project(
                              mx, my,
                              this.xs[i - 1], this.ys[i - 1],
                              this.xs[i], this.ys[i], p, .5);
            if (in_segment) {
               // found the point so compare it to the closest point
               if ((closest_p === null)
                   || (Geometry.distance(p[0], p[1], mx, my) < closest_l)) {
                  closest_p = [p[0], p[1]];
                  closest_l = Geometry.distance(p[0], p[1], mx, my);
               }
            }
         }

         if (closest_p === null) {
            // pick the end point or start point
            if (Geometry.distance(mx, my, this.xs[0], this.ys[0])
                < Geometry.distance(mx, my,
                                    this.xs[this.xs.length - 1],
                                    this.ys[this.ys.length - 1])) {
               closest_p = [this.xs[0], this.ys[0]];
            }
            else {
               closest_p = [this.xs[this.xs.length - 1],
                            this.ys[this.ys.length - 1]];
            }
         }

         Route_Stop.draw_point(G.map.xform_x_map2cv(closest_p[0]),
                               G.map.xform_y_map2cv(closest_p[1]),
                               this.temporary_rstop.graphics);
      }

      //
      protected function tooltip_display(on:Boolean) :void
      {
         var tt:String;

         m4_TALKY2('tooltip_display: on:', on, '/ sel?:', this.selected,
                   '/ is_clckbl?', this.is_clickable);

         if (on) {
            m4_ASSERT(this.last_mouse_over !== null);
            if (tooltip !== null) {
               ToolTipManager.destroyToolTip(tooltip);
            }
            tooltip = null;

            if (this.selected) {
               return; // Do not show tooltips for selected items.
            }

            if (!this.is_clickable) {
               return; // The user disabled routes at this zoom; no tooltip.
            }

            if (this.is_multimodal) {
               // BUG nnnn: We could show info about this transit leg, dummy!
               return; // The route cannot be edited, so don't tease the user.
            }

            if (!this.can_edit) {
               tt = 'Click the route to select it.';
            }
            if (this.feedback_mode == Route.FB_SELECTING) {
               // If the user is in route feedback mode...
               tt = 'Click the route to select roads for your feedback.';
            }
            else {
               // If the user is in route editing mode...
               tt =
                  'Click the route to select it. You can also edit its path.';
            }

            tooltip = ToolTipManager.createToolTip(
               tt, this.last_mouse_over.stageX, this.last_mouse_over.stageY);
         }
         else {
            if (tooltip !== null) {
               ToolTipManager.destroyToolTip(tooltip);
            }
            tooltip = null;
         }

         this.last_mouse_over = null;
      }

      //
      public function update_route_stats() :void
      {
         m4_TALKY5('update_route_stats: hydrated:', this.hydrated,
            '/ rsteps:', (this.rsteps !== null) ? this.rsteps.length : 'null',
            '/ rstops:', (this.rstops !== null) ? this.rstops.length : 'null',
            '/ invalid:', this.invalid,
            '/ links_lazy_loaded:', this.links_lazy_loaded);

         // MAYBE: Are we doing this for sub-segments that we just delete
         //        anyway? If stack_id is 0, we should bail now?
         m4_TALKY('update_route_stats:', this.softstr);

         if (this.rsteps !== null) {

            this.compute_len_and_ids();

            this.directions = this.directions_build(this.rsteps,
                                                    this.xs,
                                                    this.ys);

            if (this.alternate_steps !== null) {
               this.alternate_directions = this.directions_build(
                  this.alternate_steps, this.alternate_xs, this.alternate_ys);
               var idx:int = this.alternate_steps.length - 1;
               this.total_time =
                  this.alternate_steps[idx].fin_time
                  - this.alternate_steps[0].beg_time;
            }
            else {
               this.alternate_directions = new Array();
               this.total_time =
                  this.rsteps[this.rsteps.length - 1].fin_time
                  - this.rsteps[0].beg_time;
               // m4_TALKY('abs start time=', this.rsteps[0].beg_time);
               // m4_TALKY2('abs end time=',
               //           this.rsteps[this.rsteps.length-1].fin_time);
               // m4_TALKY('total time=', this.total_time);
            }
         }
      }

      // *** Event handlers

      //
      override public function on_mouse_doubleclick(
         event:MouseEvent,
         processed:Boolean)
            :Boolean
      {
         m4_DEBUG('on_mouse_doubleclick:', this, '/ target:', event.target);
         processed = true;
         // Skipping: super.on_mouse_doubleclick(ev, processed);
         //  Geofeature selects all vertices (for Byways and Regions).
         // This is a little hacky: if we don't process the click,
         // Map_Canvas_Controller will recenter the map; but it won't
         // zoom the viewport because it checks to see if we're a Route
         // or not, which we are, so it doesn't zoom... which explains
         // why it's a hack of a little sorts.
         //return true;
         return false;
      }

      // This is called via Tool_Pan_Select via on_mouse_up, after it
      // knows we're not processing a double-click.
      override public function on_mouse_down(event:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_down:', this.softstr);

         if ((this.is_path_editable(
              /*assume_editing_enabled=*/this.rstop_editing_enabled))
             && (G.panel_mgr.effectively_active_panel
                 === this.route_panel)) {
            if (!this.route_stop_still_under_mouse(event)) {
               m4_DEBUG2('on_mouse_down: dragged_object:',
                         G.map.tool_cur.dragged_object);
               var mx:Number = G.map.xform_x_stage2map(event.stageX);
               var my:Number = G.map.xform_y_stage2map(event.stageY);
               var new_rstop:Route_Stop;
               new_rstop = Route_Editor_UI.route_stop_insert(this, mx, my);
               m4_DEBUG('on_mouse_down: new_rstop:', new_rstop);
               new_rstop.on_roll_over(event, /*called_by_route=*/true);
               new_rstop.on_mouse_down(event, /*called_by_route=*/true);
            }
            else {
               // There's an existing route stop upon which being clicked.
               // This is unexpected, since Route_Stop should get the click
               // first, and its on_mouse_down calls stopPropagation...
               m4_ASSERT_SOFT(false);
            }
         }
         else {
            m4_DEBUG2('on_mouse_down: !active_panel: !is_path_editable:',
                      this);
         }

         this.on_mouse_down_route_stop_safe(event);

         // Geofeature on_mouse_down is a no-op.
         super.on_mouse_down(event);
      }

      public function on_mouse_down_route_stop_safe(event:MouseEvent)
         :void
      {
         this.tooltip_display(false);
         if (this.tooltip_timer !== null) {
            this.tooltip_timer.stop();
         }

         if ((G.map.rmode == Conf.map_mode_feedback)
             && (this.feedback_mode == Route.FB_SELECTING)
             && (Route.highlighted_step !== null)) {
            this.rs_toggle_select(event);
         }
      }

      //
      // NOTE: Map_Controller is also monitoring mouse move.
      public function on_mouse_move(event:MouseEvent) :void
      {
         m4_DEBUG2('on_mouse_move: temporary_rstop: is_path_editable:',
                   this.is_path_editable());
         if ((G.map.rmode == Conf.map_mode_feedback)
             && (this.feedback_mode == Route.FB_SELECTING)) {
            this.rs_highlight_maybe(event);
         }
         else if (this.is_path_editable()) {
            m4_DEBUG('on_mouse_move: temporary_rstop_draw');
            this.temporary_rstop_draw(event);
         }
      }

      //
      override public function on_mouse_out(event:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_out:', this);

         // Note the event.target and event.currentTarget === this.sprite.

         // Bugfix: If you hover the mouse over the route stop of an unselected
         // route, you'll get a rapid back-and-forth flip-flopping of two UI
         // components. The mouse over causes the route_stop sprite and label
         // to be drawn, which causes a mouse_out on the route, which then
         // removes the route_stop sprite and label, which causes on_roll_out
         // on the route_stop, and then the route gets an on_mouse_over and
         // we start the whole silly cycle over again.

         if (!this.route_stop_still_under_mouse(event)) {

            // This just unsets the route highlight...
            super.on_mouse_out(event);

            if ((G.map.rmode == Conf.map_mode_feedback)
                && (this.feedback_mode == Route.FB_SELECTING)) {
               this.rs_highlight_maybe(event);
            }

            m4_TALKY2('on_mouse_out: delight_on_mouse_out:',
                      this.delight_on_mouse_out);

            if (this.delight_on_mouse_out) {

               this.highlighted = false;
               if (this.is_drawable) {
                  this.draw();
               }

               this.delight_on_mouse_out = false;
            }
         }

         if (this.selected) {
            if (this.is_path_editable()) {
               m4_DEBUG('on_mouse_out: temporary_rstop_clear');
               this.temporary_rstop_clear();
            }
         }

         // If a real mouse out, naturally hide the tooltip, and also if the
         // mouse is now over a Route_Stop, which has its own tooltip (which
         // is the route stop name).
         this.tooltip_display(false);
         if (this.tooltip_timer !== null) {
            this.tooltip_timer.stop();
         }
      }

      //
      override public function on_mouse_over(event:MouseEvent) :void
      {
         m4_TALKY('on_mouse_over:', this, '/ sel?:', this.selected);

         // This just sets the route highlight...
         super.on_mouse_over(event);

         if (!this.selected) {
            // Start the tooltip timer.
            this.last_mouse_over = event;
            if (this.tooltip_timer !== null) {
               m4_DEBUG('on_mouse_over: starting tooltip_timer');
               this.tooltip_timer.reset();
               // See: Conf.route_path_tooltip_delay (366 ms.).
               this.tooltip_timer.start();
            }
            else {
               this.tooltip_display(true);
            }

            // Always select the route on the map, which tells the user that
            // it's hot (i.e., clickable)... not that the tooltip doesn't
            // already indicate the same think.
            this.delight_on_mouse_out = true;
            this.highlighted = true;
            if (this.is_drawable) {
               this.draw();
            }
         }
         else {
            // Show temporary route stop.
            m4_TALKY2('on_mouse_over: is_path_editable:',
                      this.is_path_editable());
            if ((this.is_path_editable())
                && (!this.route_stop_still_under_mouse(event))) {
               m4_DEBUG('on_mouse_over: temporary_rstop_draw');
               this.sprite.addEventListener(MouseEvent.MOUSE_MOVE,
                                            this.on_mouse_move);
               this.temporary_rstop_draw(event);
               UI.cursor_set_native_finger();
            }
         }

         // If we are in the feedback mode and this route is locked, it
         // means that we are ready to select route segments. In this case,
         // hovering should highlight route steps, and clicking should
         // toggle them.
         if ((G.map.rmode == Conf.map_mode_feedback)
             && (this.feedback_mode == Route.FB_SELECTING)) {
            // NOTE: Map_Controller will also see the same mouse move events.
            this.sprite.addEventListener(MouseEvent.MOUSE_MOVE,
                                         this.on_mouse_move);
            this.rs_highlight_maybe(event);
         }

         // Prevent other routes from handling event and hijacking highlights.
         event.stopPropagation();
      }

      //
      public function on_tooltip_timer(event:TimerEvent) :void
      {
         this.tooltip_display(true);
      }

      //
      protected function route_stop_still_under_mouse(event:MouseEvent)
         :Boolean
      {
         var stay_golden_ponyboy:Boolean = false;

         if (this.sprite !== null) {
            if (this.sprite.stage !== null) {
               if (event !== null) {
                  var results:Array = null;
                  results = this.sprite.stage.getObjectsUnderPoint(
                                 new Point(event.stageX, event.stageY));
                  m4_DEBUG2('route_stop_still_under_mouse: results.length:',
                            (results !== null) ? results.length : 'null');
                  if (results !== null) {
                     for each (var o:Object in results) {
                        // Note the that Route_Stop for checked out routes is
                        // in edit_stops (Route_Stops), not rstops (Objects).
                        if (o is Route_Stop) {
                           if ((o as Route_Stop).route === this) {
                              m4_DEBUG('rstop_still_undr_mouse sty_gldn_pnyb');
                              stay_golden_ponyboy = true;
                              break;
                           }
                           else {
                              m4_DEBUG2('rstop_still_undr_mouse: rt_stop.rte:',
                                        (o as Route_Stop).route);
                              m4_DEBUG('rstop_still_undr_mouse: this:', this);
                           }
                        }
                     }
                  }
               }
               m4_ASSERT_ELSE_SOFT;
            }
            m4_ASSERT_ELSE_SOFT;
         }
         m4_ASSERT_ELSE_SOFT;

         return stay_golden_ponyboy;
      }

      // *** Base class getters and setters

      //
      override public function get actionable_at_raster() :Boolean
      {
         return true;
      }

      // MAYBE: This class doesn't do anything if the current selected state
      // is the same as the one being requested. However, if the item was
      // selected before its panel was ready, currently, the client has to
      // clear item selected and then set it again to force us to show the
      // route panel. Can't we just detect if we're selected but not associated
      // with any panel, and then do something proactive about it?

      // overridden to bring selected route to the front
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         var cur_selected:Boolean = this.selected;

         super.set_selected(s, nix, solo);

         // De-select any selected map items. Note that this doesn't clear the
         // user's selection -- whatever was selected is still part of its
         // panel's selection set, so the user can restore the old map
         // selection by re-activating that selection's panel.

         // Remember that this is the active_route.
         if (s) {
            if ((G.item_mgr.active_route !== null)
                && (G.item_mgr.active_route !== this)) {
               m4_WARNING2('selected: deselect active_route:',
                           G.item_mgr.active_route);
               G.item_mgr.active_route.set_selected(false, /*nix=*/true);
            }
            m4_DEBUG('set_selected: setting active_route: this:', this);
            G.item_mgr.active_route = this;
         }
         else {
            if ((G.item_mgr.active_route !== null)
                && (G.item_mgr.active_route !== this)) {
               m4_WARNING2('selected: unexpected active_route:',
                           G.item_mgr.active_route);
               m4_WARNING('selected: was expecting this:', this);
               // MAYBE: Don't clear active_route?
               // 2014.04.29: This might be causing panel to force-show
               // the route details panel when you're trying to see the
               // find route panel.
// trying this:
               G.item_mgr.active_route = null;
            }
            else {
               m4_DEBUG2('set_selected: clearing active_route: this:',
                         this.toString_Terse());
               G.item_mgr.active_route = null;
            }
         }

         // Fiddle with other things.
         var r_index:int;
         if (s != cur_selected) {
            if (s) {
               // Swap last child with this route -- move the route sprite to
               // the top of the display list (by putting the sprite as the
               // last child).
               // EXPLAIN: Why swap sprites instead of just placing this one at
               //          the back of the list? Though the only side-effect of
               //          this is that the route or items that were selected
               //          don't sink below the newly selected item but sink
               //          below other items, too, which might appear awkward.
               //m4_DEBUG('set_selected: this.sprite:', this.sprite);
               //m4_DEBUG2('set_selected: this.sprite.parent:',
               //          this.sprite.parent);
               if (this.sprite.parent !== null) {
                  r_index = this.sprite.parent.getChildIndex(this.sprite);
                  //m4_DEBUG('set_selected: r_index:', r_index);
                  this.sprite.parent.swapChildrenAt(
                     r_index, this.sprite.parent.numChildren - 1);
               }
               else {
                  // 2013.09.09: Logged in w/ routes, then logged out, null ref
                  // I can see the 'A' and 'B' labels... ug.
                  // 2013.09.12: [lb] logged in and tried to save two deleted
                  // routes. -- Happens on roll over, trying to set the route
                  // selected, so the route must be deleted but still in the
                  // route_list, I'm guessing.
                  // 2014.07.16: [lb] is pretty sure this just means the route
                  // has already been removed from the map.
                  // No: m4_ASSERT_SOFT(false);
               }

               // 2013.12.11: This is wrong: When the user mouses over a route
               // in the route list that's on the map -- even if it's panel has
               // not been opened -- this code path is followed and we're
               // recording a view event on the route. But the user is just
               // looking at its geometry; it's not like this is a real route
               // view event.
               //  this.signal_route_view();

               if (!this.is_multimodal) {
// activate route editing mode
                  Route_Editor_UI.route_edit_start();
               }
            }
            else {
               if (!this.is_multimodal) {
                  // deactivate route editing mode
                  Route_Editor_UI.route_edit_stop();
               }
               this.disable_rstop_editing();
            }
            m4_TALKY('set_selected: set_selected: path_arrows.visible:', s);
            this.rstop_sprite.visible = s;
            this.path_arrows.visible = s;
         }
      }

      //
      override protected function set_selected_ensure_finalize(
         s:Boolean,
         nix:Boolean=false) :void
      {
         m4_TALKY2('set_selected_ensure_finalize: s:', s, '/ nix:', nix,
                   '/ is_drawable:', this.is_drawable, '/', this);
         super.set_selected_ensure_finalize(s, nix);
      }

      //
      override public function set visible(v:Boolean) :void
      {
         var old_label_visible:Boolean = false;
         if (this.label !== null) {
            old_label_visible = this.label.visible;
         }
         m4_DEBUG('set visible:', v, '/', this);
         super.visible = v;
         if (!v) {
            var rs_label:Map_Label;
            for each (rs_label in this.rstop_labels) {
               if (rs_label.parent === G.map.route_labels) {
                  m4_TALKY('set visible: removing map rs label:', rs_label);
                  G.map.route_labels.removeChild(rs_label);
               }
               else {
                  m4_DEBUG2('visible: EXPLAIN: Why is rs label missing?:',
                            rs_label);
                  m4_DEBUG(' .. parent:', rs_label.parent);
               }
            }
            m4_TALKY('set visible: resetting rs label:', rs_label);
            this.rstop_labels = new Array();
         }
         if (v != old_label_visible) {
            // 2013.12.17: With calling this, the changing of route visibility
            // is quick. But recaculating labels takes a while... but it looks
            // nice...
            G.map.geofeatures_relabel();
         }
      }

      // *** Getters and setters

      //
      public function get counterpart() :Route
      {
         return (this.counterpart_untyped as Route);
      }

      //
      override public function get counterpart_gf() :Geofeature
      {
         return this.counterpart;
      }

      //
      override public function get discardable() :Boolean
      {
         // EXPLAIN: We do delete Routes, but... discardable is really just
         //          used when panning, right? So Routes can be discarded,
         //          it's just that that doesn't automatically happen on pan?
         //          2013.09.09: Well, when you change users, branches, or
         //          revisions, this value is checked to see if we should
         //          reload the item (see G.map.items_preserve).
         return false;
      }

      //
      [Bindable] public function get filter_show_route() :Boolean
      {
         // This fcn. pertains to the checkbox in the routes list, basically
         // (if the route is loaded into a page on the routes lists). We'll
         // still draw the route on the map if there's a details panel for
         // it, but if there's no route panel, we only draw the route if the
         // user selected its list_entry.
         //  Nope: ((this.route_panel_ !== null) && ...);
         // EXPLAIN/FIXME: For route history, [lb] is not sure that checking
         //                rev_is_working makes sense.
         var cbox_selected:Boolean;
         // EXPLAIN: Why do we show if not working? Implies Diff or Historic?
         //          How do you view historic routes?
         cbox_selected = ((!this.rev_is_working) || (this.filter_show_route_));
         m4_TALKY3('get filter_show_route:', this.filter_show_route_,
                   '/ rev:', this.rev.friendly_name,
                   '/ working?:', this.rev_is_working, '/ ', this.softstr);
         return cbox_selected;
      }

      //
      public function set filter_show_route(cbox_selected:Boolean) :void
      {
         // Any code may set cbox_selected to false, but only a
         // Route_List_Entry should set cbox_selected to true.
         this.set_filter_show_route(cbox_selected, /*force=*/false);
      }

      //
      public function set_filter_show_route(cbox_selected:Boolean,
                                            force:Boolean=false) :void
      {
         m4_TALKY5('set_filter_show_route:',
                   'cbox_selected/filter_show_route:', cbox_selected,
                   '/ force:', force,
                   '/ filter_show_route_:', this.filter_show_route_,
                   '/ this:', this);

         if ((this.filter_show_route_ != cbox_selected) || (force)) {

            this.filter_show_route_ = cbox_selected;

            // m4_TALKY3('set filter_show_route: visible:', this.visible,
            //           '/ is_drawable:', this.is_drawable,
            //           '/ selected:', this.selected);

            if ((this.visible != this.is_drawable) || (force)) {
               this.visible = this.is_drawable;
               // Call draw_all so we draw the route name_ label.
               //this.draw();
               this.draw_all();
            }

            if (!this.visible) {
               // m4_TALKY('set filter_show_route: not visible:', this);
               this.set_selected(false);
            }

            // Tell the Route_List_Entry listeners to adjust their checkboxes.
            m4_TALKY('set_filter_show_route: dispatchEvt: routeFilterChanged');
            this.dispatchEvent(new Event('routeFilterChanged'));
         }
      }

      //
      public function route_list_membership_add(rte_lst_entry:Object) :void
      {
         m4_DEBUG('route_list_membership_add: rte_lst_entry:', rte_lst_entry);
         this.route_list_membership.add(rte_lst_entry);
         this.route_remove_from_map_maybe();
      }

      //
      public function route_list_membership_nix(rte_lst_entry:Object) :void
      {
         m4_DEBUG('route_list_membership_nix: rte_lst_entry:', rte_lst_entry);
         this.route_list_membership.remove(rte_lst_entry);
         this.route_remove_from_map_maybe();
      }

      //
      protected function route_remove_from_map_maybe() :void
      {
         var is_drawable:Boolean = this.is_drawable;

         m4_TALKY3('route_remove_from_map_maybe: is_drawable:', is_drawable,
                   '/ route_list_membership.len:',
                   this.route_list_membership.length);

         var remove_from_map:Boolean =
            ((!is_drawable) && (this.route_list_membership.length <= 0));

         m4_TALKY2('route_remove_from_map_maybe: remove_from_map:',
                   remove_from_map);

         // Reset the checkbox flag if we're no longer part of a route list.
         if (this.route_list_membership.length == 0) {
            m4_TALKY('rte_rem_fr_map_maybe: clear filter_show_rte:', this);
            this.filter_show_route_ = false;
         }

         // FIXME/MAYBE: [lb] is not sure that we should do this...
         //  maybe test it first...
         // TEST_THIS_CODE: test_this_code = true is untested.
         var test_this_code:Boolean = false;
         if (test_this_code) {
            if (remove_from_map) {
               G.map.item_discard(this);
            }
         }
      }

      //
      public function set_visible_with_panel(
         any_panel:Detail_Panel_Base,
         panel_attach:Boolean,
         panel_release:Boolean) :void
      {
         m4_DEBUG3('set_visible_with_panel: any_panel:', any_panel,
                   '/ panel_attach:', panel_attach,
                   '/ panel_release:', panel_release)

         if (any_panel !== null) {
            if (panel_attach) {
               this.keep_showing_while_paneled.add(any_panel);
            }
            else {
               this.keep_showing_while_paneled.remove(any_panel);
            }
            if (this.visible != this.is_drawable) {
               this.visible = this.is_drawable;
               if (!this.visible) {
                  // m4_DEBUG('set_visible_with_panel: not visible:', this);
                  this.set_selected(false);
               }
               this.draw_all();
            }
         }
      }

      //
      public function signal_route_view() :void
      {
         m4_DEBUG2('signal_route_view: route_list_membership:',
                   route_list_membership);

         // Tell the route library to update its list. If all routes existed in
         // the list, we could signal an event, but because new routes won't be
         // in the list, we have to contact the list directly.
         //Insufficient:
         //m4_DEBUG('signal_route_view: dispatchEvent: routeViewCountIt');
         //this.dispatchEvent(new Data_Change_Event('routeViewCountIt', this));
         if (Route.looked_at_list_callback !== null) {
            Route.looked_at_list_callback(this);
         }
         m4_ASSERT_ELSE_SOFT;
      }

      //
      public function update_cur_dir(coords:Array) :void
      {
         this.current_dir_step = coords;
         this.draw();
      }

      // ***

      //
      public function get from_canaddr() :String
      {
         var is_beg:Boolean = true;
         var is_fin:Boolean = false;
         return this.get_addr_name(is_beg, is_fin);
      }

      //
      public function get to_canaddr() :String
      {
         var is_beg:Boolean = false;
         var is_fin:Boolean = true;
         return this.get_addr_name(is_beg, is_fin);
      }

      // ***

      //
      public function get_addr_name(is_beg:Boolean, is_fin:Boolean) :String
      {
         var name:String = null;
         if ((this.rstops !== null) && (this.rstops.length > 0)) {
            var rstop_i:int;
            if (is_beg) {
               rstop_i = 0;
            }
            else {
               m4_ASSURT(is_fin);
               rstop_i = this.rstops.length - 1;
            }
            name = this.rstops[rstop_i].name_;
            if (name === null) {
               name = this.street_name(rstop_i);
            }
         }
         if ((name === null) || (name == '')) {
            if (is_beg) {
               name = this.beg_addr;
            }
            else {
               name = this.fin_addr;
            }
         }
         if ((name === null) || (name == '')) {
            // What about using the final edge's street name?
            if ((this.rstops !== null) && (this.rstops.length >= 2)) {
               if (is_beg) {
                  name = this.street_name(/*stop_num=*/0);
               }
               else {
                  name = this.street_name(this.rstops.length-1);
               }
               if (name != 'Point on map') {
                  name = 'Point near ' + name;
               }
            }
            else {
               name = Conf.route_stop_map_name;
            }
         }
         return name;
      }

      //
      public function get alternate_html_text() :String
      {
         if (this.alternate_steps === null) {
            return "";
         }
         else {
            return this.html_text_build(this.alternate_directions,
                                        this.alternate_length);
         }
      }

      //
      public function get html_text() :String
      {
         return this.html_text_build(this.directions, this.rsn_len);
      }

      //
      public function html_text_build(dirs:Array, dir_len:Number) :String
      {
         m4_TALKY2('html_text_build: dirs.len:', dirs.length,
                   '/ dir_len:', dir_len);
         // NOTE: dir_len isn't used. What was the original intent?

         var i:int = 0;
         var dr:Direction_Step;
         var first_col_width:int;
         var first_col_label:String;
         var the_fourth_row:String = '';
         var direction_steps:String = '';

         var html_text:String = '';

         if (!this.is_multimodal) {
            // only have length text
            first_col_width = 46;
            first_col_label = 'Odo.';
         }
         else {
            // change length text and add a time row
            first_col_width = 66;
            first_col_label = 'Time';
            the_fourth_row = StringUtil.substitute(
               (<![CDATA[
               <tr>
                  <td class="header">Total Time:</td>
                  <td class="normal">
                     {0}
                  </td>
               </tr>
               ]]>).toString(),
               [
                  Timeutil.total_time_to_pretty_string(this.total_time),
               ]
            );
         }

         // build direction steps in html rows
         for each (dr in dirs) {
            if ((i++) % 2 == 0) {
               direction_steps += '<tr bgcolor="#E7E7E7">'
                           + dr.html_text(is_multimodal) + '</tr>\n';
            }
            else {
               direction_steps += '<tr>'
                           + dr.html_text(is_multimodal) + '</tr>\n';
            }
         }

         html_text = StringUtil.substitute(
            (<![CDATA[
               {0}
               <tr>
                  <td class="header">From:</td>
                  <td class="normal">{1}</td>
               </tr>
               <tr>
                  <td class="header">To:</td>
                  <td class="normal">{2}</td>
               </tr>
               <tr>
                  <td class="header">Length:</td>
                  <td class="normal">
                     {3}
                  </td>
               </tr>
               {4}
               {5}
               {6}
               {7}
            ]]>).toString(),
            [
               Conf.directions_html_header(),
               this.from_canaddr,
               this.to_canaddr,
               Strutil.meters_to_miles_pretty(this.rsn_len),
               the_fourth_row,
               Conf.directions_html_table(first_col_width, first_col_label),
               direction_steps,
               Conf.directions_html_tail,
            ]
         );

         return html_text;
      }

      //
      override public function get hydrated() :Boolean
      {
         var hydrated:Boolean = (this.rsteps !== null);
         m4_ASSERT((hydrated && (this.rsteps !== null))
                   || ((!hydrated) && (this.rsteps === null)));
         //m4_DEBUG('get hydrated (route):', hydrated);
         hydrated &&= super.hydrated;
         ////m4_DEBUG('get hydrated (&& super):', hydrated);
         //if (!hydrated) {
         //   m4_DEBUG(' .. this.links_lazy_loaded:', this.links_lazy_loaded);
         //   m4_DEBUG(' .. this.invalid:', this.invalid);
         //}
         return hydrated;
      }

      //
      override public function get is_clickable() :Boolean
      {
         var is_clickable:Boolean = false;
         if (this.master_route === null) {
            if (G.map.rmode == Conf.map_mode_feedback) {
               is_clickable = (this.feedback_instance == Route.FB_NEW);
            }
            else {
               is_clickable = (
                  super.is_clickable
                  && (G.tabs.settings.routes_clickable
                     || (!this.route_panel.widget_route_footer.save_footer
                          .route_clicks_ignore.selected)
                      || (!G.map.zoom_is_vector())
                      || (!this.rev_is_working)));
            }
         }
         // else, an older route version; the route line is viewable but not
         //                               clickable/interactiveable.
         return is_clickable;
      }

      //
      override public function get is_drawable() :Boolean
      {
         var is_drawable:Boolean = super.is_drawable;

         // All routes have their own panels, which are registered with the
         // panel manager, but that doesn't mean the panel is visible.
         //var is_registered:Boolean =
         //   G.panel_mgr.is_panel_registered(this.route_panel_);
         var is_panel_showing:Boolean = false;
         var is_panel_closed_or_closing:Boolean = true;
         var rt_panel:Panel_Item_Route;
         if (this.master_route === null) {
            rt_panel = this.route_panel_;
         }
         else {
            rt_panel = this.master_route.route_panel_;
         }
         if (rt_panel !== null) {
            if (G.panel_mgr.tab_index_get(rt_panel) >= 0) {
               is_panel_showing = true;
            }
            if (!rt_panel.panel_close_pending) {
               is_panel_closed_or_closing = false;
            }
         }

         m4_TALKY7('get is_drawable: super.is_drawable:', is_drawable,
                   '/ filter_show_route:', this.filter_show_route,
                   '/ keep_showing_while_paneled.len:',
                   this.keep_showing_while_paneled.length,
                   '/ is_panel_showing:', is_panel_showing,
                   '/ is_panel_closed_or_closing:',
                   is_panel_closed_or_closing);

         is_drawable &&= (
               (this.filter_show_route)
            || (this.keep_showing_while_paneled.length > 0)
            || ((is_panel_showing) && (!(is_panel_closed_or_closing))));
         m4_TALKY('get is_drawable: is_drawable:', is_drawable);

         return is_drawable;
      }

      //
      override public function get is_labelable() :Boolean
      {
         var is_labelable:Boolean = ((super.is_labelable) && (this.hydrated));
         m4_TALKY4('is_labelable:', is_labelable,
                   '/ this.is_drawable:', this.is_drawable,
                   '/ !this.hidden_by_filter():', !this.hidden_by_filter(),
                   '/ this.hydrated:', this.hydrated);
         return is_labelable;
      }

      //
      public function get is_multimodal() :Boolean
      {
         return (this.travel_mode == Travel_Mode.transit);
      }

      //
      public function get is_path_clickable() :Boolean
      {
         // We could have the panel change us, or we could just be a little
         // coupled and wire the route to the panel. At least having a getter
         // is better than writing route.route_panel.tab_route_details...
         // everywhere.
         return ((!this.route_panel.widget_route_footer.save_footer
                   .route_clicks_ignore.selected)
                 && (this.master_route === null));
      }

      //
      public function get is_path_edit_immediately() :Boolean
      {
         var editable:Boolean = (
            this.route_panel.widget_route_footer.save_footer
            .route_clicks_drag_rstop.selected);
         m4_DEBUG('is_path_edit_immediately: editable/1:', editable);

         // To enable the long-press feature to get around when the checkbox is
         // not checkbox (e.g., Drag Route Line to Add Stops is not selected),
         // the Tool_Pan_Select tool hacks our enabling flag.
         editable ||= this.rstop_editing_enabled;
         m4_DEBUG('is_path_edit_immediately: editable/2:', editable);

         return editable;
      }

      //
      public function is_path_editable(assume_editing_enabled:Boolean=false)
         :Boolean
      {

         // FIXME: App Mode Stuff:
         //
         //   Allow editing when:
         //
         //   - route is new and route_modify_new is allowed
         //   - route is saved, private and route_modify_private is allowed
         //   - route is saved, shared/public and item_edit is allowed
         //
         // 2013.05.03: [mm] notes: This logic does not check for ownership,
         // e.g. it checks is_private, but does not check if the route is owned
         // by the current user. Is that a problem? Or should this.can_edit
         // (also in the return clause) take care of that?
         //
         // 2013.05.07: [lb] notes that is_private and the rest of the
         // access_infer values are only indicative of an item's scope,
         // and should generally just be used to draw different colored
         // backgrounds in application widgets. We shouldn't use access_infer
         // for any permissions decisions. But for this Boolean it looks like
         // we want to let user's edit their private routes when they might
         // not otherwise be able to edit a shared or public route. So the
         // real question is, is that the desireable behaviour?
         //
         var allowed_by_mode:Boolean = (

            ((this.unlibraried)
             && (G.app.mode.is_allowed(App_Action.route_modify_new)))

            ||

            ((!this.unlibraried)
             && (this.is_private)
             && (G.app.mode.is_allowed(App_Action.route_modify_own)))

            ||

            ((!this.unlibraried)
             && ((this.is_shared) || (this.is_public))
             && (G.app.mode.is_allowed(App_Action.route_modify_all)))
         );

         // If the user checked the "Click on Routes to Add Stops" checkbox
         // or has longpressed on the route and is still holding the mouse
         // down, the path is considered editable.
         var route_stops_okay:Boolean =
            (assume_editing_enabled
             //|| this.rstop_editing_enabled
             || (this.is_path_edit_immediately && this.is_path_clickable));

         var is_editable:Boolean =
            ((this.selected)
             && (!this.is_multimodal)
             && (this.rev_is_working)
             && (this.is_clickable)
             && (this.master_route === null)
             && (this.can_edit)
             && (allowed_by_mode)
             && (this.feedback_mode != Route.FB_SELECTING)
             && (this.feedback_instance != Route.FB_OLD)
             && (G.map.tool_is_active(Tool_Pan_Select))
             && (route_stops_okay));

         m4_TALKY6('is_path_editable:',
                     'is_editable: ', is_editable,
                   '/ is_private:  ', this.is_private,
                   '/ is_shared:   ', this.is_shared,
                   '/ is_public:   ', this.is_public,
                   '/ fresh:       ', this.fresh);
         m4_TALKY6('                 ',
                   '/ can_edit:    ', this.can_edit,
                   '/ alwd_by_mode:', allowed_by_mode,
                   '/ rev_is_workg:', this.rev_is_working,
                   '/ is_clickable:', this.is_clickable,
                   '/ is_private:  ', this.is_private);
         m4_TALKY4('                 ',
                   '/ pth_edt_immd:', this.is_path_edit_immediately,
                   '/ rs_edtg_nbld:', this.rstop_editing_enabled,
                   '/ rt_stops_ok: ', route_stops_okay);

         return is_editable;
      }

      //
      [Bindable] public function get is_route_stop_selection_deleteable()
         :Boolean
      {
         // If the user selects all the route stops or all but one route stop,
         // we cannot bulk-delete the selected route stops.
         return (this.num_rstops_selected < (this.num_dests - 1));
      }

      //
      public function set is_route_stop_selection_deleteable(ignored:Boolean)
         :void
      {
         m4_ASSERT(false);
      }

      //
      public function get num_dests() :int
      {
         var rstop:Route_Stop;
         if (this.num_dests_ === null) {
            this.num_dests_ = 0;
            this.num_rstops_selected = 0;
            if (this.edit_stops !== null) {
               var stop_0:Route_Stop = this.edit_stops[0];
               var stop_n:Route_Stop = this.edit_stops[
                                 this.edit_stops.length-1];
               if (stop_0 !== null) {
                  stop_0.is_endpoint = true;
               }
               if (stop_n !== null) {
                  stop_n.is_endpoint = true;
               }
               for each (rstop in this.edit_stops) {
                  // We used to only consider named, properly geocoded stops in
                  // the num_dests count, so you could not delete the last two
                  // named stops, but the code is now smart enough to treat
                  // unnamed route stops with as much courtesy as named stops.
                  // Ignoring: ((rstop.is_endpoint || (!rstop.is_pass_through))
                  //            && (rstop.name))
                  if (rstop !== Route_Editor_UI.new_stop) {
                     m4_DEBUG('num_dests: rstop:', rstop);
                     this.num_dests_++;
                  }
                  if (rstop.rstop_selected) {
                     this.num_rstops_selected += 1;
                  }
               }
            }
            m4_DEBUG2('get num_dests: num_rstops_selected:',
                      this.num_rstops_selected);
         }
         return (this.num_dests_ as int);
      }

      //
      public function edit_stop_name_fcn(
         rt_stop_:*,
         to:*=null,
         do_or_undo:*=null) :*
      {
         var rt_stop:Route_Stop = (rt_stop_ as Route_Stop);
         m4_DEBUG('edit_stop_name_fcn: rt_stop:', rt_stop);

         if (do_or_undo !== null) {
            m4_DEBUG('edit_stop_name_fcn: to:', to);
            rt_stop.name_ = String(to);
            // Consider this stop no longer pass-through if named.
            rt_stop.is_pass_through = (rt_stop.name_ == '');
         }

         return rt_stop.name_;
      }

      //
      public function edit_stops_push(rstop:Route_Stop) :void
      {
         if (this.edit_stops.length > 1) {
            var old_lastie:Route_Stop;
            old_lastie = this.edit_stops[this.edit_stops.length-1];
            old_lastie.is_endpoint = false;
            if (rstop !== Route_Editor_UI.new_stop) {
               this.num_dests_ += 1;
               m4_TALKY2('edit_stops_push: two or more: rstop:', rstop,
                         '/ num_dests_:', this.num_dests_);
            }
         }
         else if (rstop !== Route_Editor_UI.new_stop) {
            this.num_dests_ += 1;
            m4_TALKY2('edit_stops_push: just one: rstop:', rstop,
                      '/ num_dests_:', this.num_dests_);
         }
         if (rstop.rstop_selected) {
            this.num_rstops_selected += 1;
         }
         rstop.is_endpoint = true;
         this.edit_stops.push(rstop);
      }

      //
      public function edit_stops_set(new_stops:Array) :void
      {
         if (this.edit_stops !== null) {
            for each (var old_rstop:Route_Stop in this.edit_stops) {
               old_rstop.is_endpoint = false;
            }
         }
         this.edit_stops = new_stops;
         for each (var new_rstop:Route_Stop in this.edit_stops) {
            new_rstop.route = this;
         }
         this.num_dests_ = null;
         this.num_rstops_selected = 0;
         if (new_stops !== null) {
            // Set the is_endpoint route stops.
            var ignored:int = this.num_dests;
         }
      }

      //
      public function mark_route_panel_dirty() :void
      {
         if (this.route_panel_ !== null) {
            G.panel_mgr.panels_mark_dirty([this.route_panel_,]);
         }
         else if (this.master_route !== null) {
            m4_ASSERT_SOFT(false); // Shouldn't happen...
         }
      }

      //
      public function get route_panel() :Panel_Item_Route
      {
         var rt_panel:Panel_Item_Route;
         if (this.master_route !== null) {
            rt_panel = this.master_route.route_panel;
         }
         else {
            if (this.route_panel_ === null) {
               this.route_panel_ = (G.item_mgr.item_panel_create(this)
                                    as Panel_Item_Route);
               this.route_panel_.route = this;
               m4_DEBUG2('get route_panel: created route_panel_:',
                         this.route_panel_);
               // this.visible is false until the panel is set (because if the
               // panel is removed, we don't want to show the sprite) so tickle
               // the route now that this.is_drawable may return true.
               this.geofeature_added_to_map_layer();
            }
            rt_panel = this.route_panel_;
         }
         return rt_panel;
      }

      //
      public function set route_panel(route_panel:Panel_Item_Route) :void
      {
         m4_ASSERT_SOFT(false); // Never called. Search: \.route_panel_? =
      }

      //
      public function get rsteps() :Array
      {
         return this.rsteps_;
      }

      //
      public function set rsteps(rsteps:Array) :void
      {
         this.rsteps_ = rsteps;
         // Tell interested parties of our success.
         // 2013.04.30: This isn't the most robust solution, but it's better
         //             than what was coded, which was a tight loop in
         //             Route_Editor_UI waiting for this to happen (using a
         //             bunch of callLaters).
         //             (It's not the best solution because we don't discern by
         //             the route: we signal routeStepsLoaded via item_mgr, so
         //             listeners have to check if they care.)
         if (this.rsteps_ !== null) {
            m4_DEBUG('rsteps: dispatchEvent: routeStepsLoaded');
            this.dispatchEvent(new Event('routeStepsLoaded'));
         }
      }

   }
}


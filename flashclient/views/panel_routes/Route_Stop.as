/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.geom.Point;
   import flash.utils.Timer;
   import mx.core.IToolTip;
   import mx.managers.ToolTipManager;
   import mx.utils.ColorUtil;

   import gwis.GWIS_Geocode;
   import items.Record_Base;
   import items.feats.Route;
   import items.feats.Route_Step;
   import items.utils.Travel_Mode;
   import utils.geom.Geometry;
   import utils.misc.Draggable;
   import utils.misc.Logging;
   import utils.misc.Strutil;
   import views.base.UI;
   import views.commands.Route_Path_Edit_Command;
   import views.map_widgets.tools.Tool_Pan_Select;
   import views.panel_routes.Address_Resolved;
   import views.panel_routes.Route_Editor_UI;
   import views.panel_routes.Route_Stop_Editor;

   // Route_Stop is a Draggable that is created dynamically when a route's
   // geometry is to be edited. In addition to mirroring the data contained
   // within a route's stop objects, it tracks dirtiness and geocoding state,
   // and can be rendered.
   public class Route_Stop extends Sprite implements Draggable {

      // *** Static members

      protected static var log:Logging = Logging.get_logger('@Route_Stop');

      protected static var tooltip:IToolTip; // tooltip display on mouse over

      // *** Instance variables

      public var route:Route;

      public var name_:String;
      // The node_id is used to figure out if the route_stop is geocoded.
      // (See also: internal_system_id.)
      public var node_id:int;
      // The version is used internally to help with route path editing.
      // It's 1 for route stops from the server, and it's 0 for new route
      // stops, and then it's increased 1 for every time that we geocode
      // a new x,y for the stop, or that the user drags it around the map.
      // We compare stop_versions in the route edit command to know what
      // route segments need to be updated.
      public var stop_version:int;

      // The user assigns x,y via geocoding or by interacting with map.
      public var x_map:Number = NaN;
      public var y_map:Number = NaN;

      // The first and last route stops in the route's route stop list
      // are considered the endpoints. We always show these in the route
      // list and give them colorful lettered labels on the map.
      public var is_endpoint:Boolean;
      // A "pass-through" route stop is basically an unnamed route stop.
      // We don't show this in the route stop list, and they're not
      // especially higlighted on the map.
      public var is_pass_through:Boolean;

      // Transit stops are handled differently, or at least we didn't
      // update the code to handle editing transit stops with as much
      // robustness as one can edit non-transit route stops.
      public var is_transit_stop:Boolean;
      // The is_arrive flag is used for multimodal route stops.
      protected var is_arrive:Boolean;

      // If the user searches for a destination by name, we might geocode to
      // a Cyclopath item:
      public var internal_system_id:int;
      // Or we might find a geocode result using a third-party geocode service:
      public var external_result:Boolean;
      // Or, if the user dragged or clicked to create the route stop, neither
      // of the last two are set.

      // The street name is a generated using a nearby route step's byway's
      // name. We'll use this to identify the route stop if it's not otherwise
      // explicitly named.
      public var street_name_:String;

      // The orig_stop object is used during route requests, after a route stop
      // is added, moved, or removed, so we can draw the old route line as well
      // as draw arrows (path_arrows) indicating the pending changes.
      public var orig_stop:Route_Stop_Editor;
      // New stops and moved stops are marked dirty while we fetch new route
      // segments to stitch into the route. We mark 'em dirty so the route
      // can draw route steps to and from dirty stops in a different color,
      // so the user knows which segments of the route are being recomputed.
      public var dirty_stop:Boolean;

      // If the user clicks on a route stop on the map, we highlight it
      // and show it in the route stop list.
      public var rstop_selected:Boolean;
      // To implement click-to-select and then click-to-deselect route stops,
      // and to distinguish from dragging and other types of clicking,
      // on_mouse_down sometimes sets the deselecting flag to true, and then
      // on_mouse_up knows to toggle the route stop selectedness.
      public var rstop_deselecting:Boolean;

      protected var mouse_is_over:Boolean;
      protected var mouse_was_finger:Boolean;
      // We hold on to the mouse_over event for the toolTip coordinates.
      protected var last_mouse_over:MouseEvent;
      // We pause briefly after a mouse_over, before showing the toolTip,
      // in case the user is about to do something other than hover the
      // mouse over the route stop (i.e., don't pop up the toolTip
      // immediately, in case the user is trying to drag the route stop
      // or just wants to select it).
      protected var tooltip_timer:Timer;

      // These had been in Route_Stop_Entry but Flex reuses GUI components so
      // these belong here.
      public var gwis_geocode:GWIS_Geocode;
      // This object handles the list of results, or lack of results, and the
      // disambiguiator (sp).
      public var addy_geocode:Address_Resolved = new Address_Resolved();

      // *** Constructor

      // A note about the Route_Stop class compared to the route stop Object:
      // * There are two types of route stop objects in flashclient:
      //     1. an Object; and
      //     2. a Route_Stop object.
      // Expect to deal with this class, Route_Stop. The Object representation
      // is mostly just used by Route to remember what the server sent it.
      // (The Route stores route stop Objects in route.rstops.
      //  It's in route.edit_stops that you'll find these Route_Stop objects.)

      public function Route_Stop(
         r:Route,
         rt_stop_obj:Route_Stop_Editor, // Lightweight; from XML from server.
         is_pass_through:Boolean=false)
      {
         this.route = r;

         this.orig_stop = rt_stop_obj;

         if (rt_stop_obj !== null) {
            this.name_ = rt_stop_obj.name_;
            this.node_id = rt_stop_obj.node_id;
            m4_ASSERT_SOFT(this.node_id > 0);
            this.stop_version = rt_stop_obj.stop_version;
            this.x_map = Number(rt_stop_obj.x_map);
            this.y_map = Number(rt_stop_obj.y_map);
            this.is_endpoint = rt_stop_obj.is_endpoint;
            this.is_pass_through = rt_stop_obj.is_pass_through;
            this.is_transit_stop = rt_stop_obj.is_transit_stop;
            this.internal_system_id = rt_stop_obj.internal_system_id;
            this.external_result = rt_stop_obj.external_result;
            //m4_TALKY('Route_Stop: street_name_:', rt_stop_obj.street_name_);
            this.street_name_ = rt_stop_obj.street_name_;
            // Skipping: rt_stop.editor
         }
         else {
            this.name_ = '';
            this.node_id = 0;
            this.stop_version = 0;
            this.x_map = NaN;
            this.y_map = NaN;
            this.is_endpoint = false;
            this.is_pass_through = is_pass_through;
            this.is_transit_stop = false;
            this.internal_system_id = 0;
            this.external_result = false;
            this.street_name_ = null;
            // Skipping: rt_stop.editor
         }

         this.dirty_stop = false;

         // roll-over for tooltip and highlight
         // NOTE: Use ROLL_OVER/ROLL_OUT and not MOUSE_OVER/MOUSE_OUT,
         //       otherwise you may see a flicker. For more information,
 // http://polygeek.com/1519_flex_the-difference-between-rollover-and-mouseover
         // FIXME: In Transit_Stop, these were MOUSE_OVER and MOUSE_OUT?
         this.addEventListener(MouseEvent.ROLL_OVER, this.on_roll_over,
                               false, 0, true);
         this.addEventListener(MouseEvent.ROLL_OUT, this.on_roll_out,
                               false, 0, true);

         // timer tooltip setup
         this.tooltip_timer = new Timer(Conf.route_path_tooltip_delay, 1);
         this.tooltip_timer.addEventListener(TimerEvent.TIMER,
                                             this.on_tooltip_timer,
                                             false, 0, true);

         m4_TALKY2('Route_Stop: route.can_edit:', this.route.can_edit,
                   '/ is_transit_stop:', this.is_transit_stop);
         if ((this.route.can_edit) && (!this.is_transit_stop)) {
            m4_TALKY('Route_Stop: add on_mouse_down on_mouse_up lstns:', this);

            // WATCHOUT: We compete with other mouse handlers, like the
            //           pan/select tool and the map canvas. We try not
            //           to let any two mouse handlers profess the same event.
            this.addEventListener(MouseEvent.MOUSE_DOWN, this.on_mouse_down,
                                  false, 0, true);
            this.addEventListener(MouseEvent.MOUSE_UP, this.on_mouse_up,
                                  false, 0, true);
         }

         if (this.is_transit_stop) {
            var i:int;
            var w:Object;
            var num_transit_stops:int = 0;
            for (i = 0; i < r.rstops.length; i++) {
               w = r.rstops[i];
               if (w.is_transit_stop) {
                  num_transit_stops++;
                  if (w === rt_stop_obj) {
                     this.is_arrive = num_transit_stops % 2 != 0;
                  }
               }
            }
         }
      }

      // ***

      //
      protected function clone_once(to_other:Record_Base) :void
      {
         var other:Route_Stop = (to_other as Route_Stop);
         //super.clone_once(other);
         m4_ASSERT(false); // Not implemented.
      }

      //
      protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Route_Stop = (to_other as Route_Stop);
         //super.clone_update(other, newbie);
         m4_ASSERT(false); // Not implemented.
      }

      // NOTE: No gml_consume: Route.as does that for us.

      // *** getters/setters for canvas coordinates

      //
      public function get x_cv() :Number
      {
         return G.map.xform_x_map2cv(this.x_map);
      }

      //
      public function get y_cv() :Number
      {
         return G.map.xform_y_map2cv(this.y_map);
      }

      //
      public function set x_cv(x:Number) :void
      {
         this.x_map = G.map.xform_x_cv2map(x);
      }

      //
      public function set y_cv(y:Number) :void
      {
         this.y_map = G.map.xform_y_cv2map(y);
      }

      // ***

      //
      protected function clear_other_rstop_selections() :void
      {
         // 2013.06.09: [lb] Add to style guide: how not to name things:
         //                var w:Route_Stop;
         //             - Hard to read code; hard to search-for; etc.
         var other_stop:Route_Stop;
         for each (other_stop in this.route.edit_stops) {
            if (other_stop !== this) {
               m4_TALKY2('clear_other_rstop_selects: other: rstop_selected=f:',
                         other_stop);
               if (other_stop.rstop_selected) {
                  other_stop.rstop_selected = false;
                  this.route.num_rstops_selected -= 1;
               }
               other_stop.draw();
            }
         }
      }

      //
      public function get color() :int
      {
         var i:int = this.route.edit_stops.indexOf(this);

         if (i == 0) {
            // MAGIC_NUMBER: FIXME: Make conf opt.: Not quite green.
            return 0x00bb00;
         }
         else if (i == this.route.edit_stops.length - 1) {
            // MAGIC_NUMBER: FIXME: Make conf opt.: RED.
            return 0xff0000;
         }
         else if (this.is_transit_stop) {
            return Conf.route_transit_stop_color;
         }
         else {
            return Conf.route_color;
         }
      }

      //
      protected function get is_rstop_editable() :Boolean
      {
         var is_editable:Boolean = false;
         is_editable = this.route.is_path_editable(
                  /*assume_editing_enabled=*/true);
         return is_editable;
      }

      //
      public function get is_stop_worthy() :Boolean
      {
         // A route stop is "worthy" if it's "important enough" that
         // we want to show it in the route stop list on the route
         // details panel. Worthy stops are shown on the map with a
         // bigger circle and a letter that matches a letter in the
         // route stop list; unworthy stops are drawn more boringly
         // on the map, with a smaller circle and without a letter.
         var is_worthy:Boolean = (
            // The first or last route stop in the list,
            //  named or unnamed, is_pass_through or not,
            //  is always worthy.
               (this.is_endpoint)
            // A named, geocoded route stop (and not just an x,y)
            // is worthy -- this lets a user promote route stops
            // to the route list by naming them, or deleting route
            // stop names to banish them from the list.
            || (!this.is_pass_through)
            // We always show the temporary route stop created by
            // "Add Destination" in the route list.
            || (this === Route_Editor_UI.new_stop)
            // We'll show an unnamed route stop in the route list
            // if the user clicks the route stop on the map.
            || (this.rstop_selected));
         // Note that we don't care about this.is_stop_valid, or
         // if this.name_ is set or not (the latter is really masked
         // by is_pass_through, which is basically
         //   is_pass_through = !(Boolean(this.name))
         return is_worthy;
      }

      //
      public function get is_stop_valid() :Boolean
      {
         return ((!isNaN(this.x_map)) && (!isNaN(this.y_map)));
      }

      //
      public function get name_or_street_name() :String
      {
         var stop_name:String;
         if ((this.name_ !== null) && (this.name_ != '')) {
            stop_name = this.name_;
            m4_DEBUG('get name_or_street_name: this.name_:', stop_name);
         }
         else {
            stop_name = this.street_name;
            m4_DEBUG('get name_or_street_name: street_name:', stop_name);
         }
         return stop_name;
      }

      //
      public function get street_name() :String
      {
         var street_name:String;
         var s:Route_Step;

         if (this.dirty_stop || (this.orig_stop === null)) {
            // We've moved off the original point, or we don't have one,
            // so we can't just look through the route for steps.
            street_name = Conf.route_stop_map_name;
            m4_TALKY('get street_name: default:', street_name);
         }
         else {
            // Use the street name.
            street_name = this.route.street_name(this.orig_stop);
            m4_TALKY('get street_name: orig_stop:', street_name);
         }

         return street_name;
      }

      // *** Event listeners

      //
      public function drag(xdelta:Number, ydelta:Number) :void
      {
         //m4_VERBOSE('drag');

         m4_ASSERT(!this.route.is_multimodal);

         this.x_cv = this.x_cv + xdelta;
         this.y_cv = this.y_cv + ydelta;
         this.name_ = null;

         this.internal_system_id = 0;
         this.external_result = false;
         this.street_name_ = null;

         var rt_panel:Panel_Item_Route_Details
            = this.route.route_panel.tab_route_details;
         var rs_entry:Route_Stop_Entry =
            ((rt_panel.rstops.grid_rstops.itemToItemRenderer(this))
             as Route_Stop_Entry);
         // It's too slow to do a full item details update, so instead we look
         // up the route_stop's entry in the panel and manually update the text
         // field (since that's all that's needed).
         if (rs_entry !== null) {
            rs_entry.address_label.text = this.street_name;
            rs_entry.address_label.setStyle('color', 0x999999);
         }

         this.rstop_deselecting = false;

         // Clear all other route stop selections.
         if (this.route.num_rstops_selected > 1) {
            m4_DEBUG('drag: deselecting other selected route stops');
            this.clear_other_rstop_selections();
            m4_ASSERT_SOFT(this.route.num_rstops_selected == 1);
         }

         Route_Editor_UI.notify_stop_changed(this, true);
      }

      //
      public function on_mouse_down(event:MouseEvent,
                                    called_by_route:Boolean=false)
                                       :void
      {
         m4_DEBUG3('on_mouse_down: is_rstop_editable', this.is_rstop_editable,
                   '/ tool_cur:', G.map.tool_cur,
                   '/ by rte?:', called_by_route, '/', this.route.softstr);
         m4_DEBUG('on_mouse_down: route.selected', this.route.selected);
         m4_DEBUG('on_mouse_down: route.highlighted', this.route.highlighted);

         // If the route isn't already selected: make it so.
         // Not needed: this.route.set_selected(false);
         if (!this.route.selected) {
            m4_DEBUG('on_mouse_down: sel route via stop:', this.route.softstr);
            if (G.item_mgr.active_route !== null) {
               G.item_mgr.active_route.set_selected(false);
            }
            this.route.set_selected(true, /*nix=*/false, /*solo=*/true);
            // Note we're just selecting the route and the user has to click
            // a second time on the route stop to select this object for real
            // (i.e., only set route selected or route stop selected as
            // response to single mouse click, i.e., don't do two things).
         }
         else {

            if (this.rstop_selected) {
               // Toggle the route stop: if selected, deselect it.
               m4_DEBUG('on_mouse_down: already selected: rstop_deselecting');
               m4_ASSERT_SOFT(!this.rstop_deselecting);
               this.rstop_deselecting = true;
            }

            if ((this.is_rstop_editable) && (this.route.is_path_clickable)) {

               m4_DEBUG2('on_mouse_down: rstop_selected=t',
                         '/ rstop_editing_enabled:', this);

               if (!called_by_route) {
                  // EXPLAIN: What does this do? Redraw the route
                  //          stops or something?
                  this.route.on_mouse_down_route_stop_safe(event);
               }

               if (!this.rstop_selected) {
                  this.rstop_selected = true;
                  this.route.num_rstops_selected += 1;
               }

               if (this.route.is_path_edit_immediately) {
                  G.map.tool_cur.dragged_object = this;
                  m4_DEBUG('on_mouse_down: dragged_object:', this);
                  m4_DEBUG('on_mouse_down: rstop_editing_enabled=t:', this);
                  this.route.rstop_editing_enabled = true;
               }

               this.draw();

               // We could de-select any other selected stop, but allowing
               //   users to select many of them allows users to reorder
               //   unnamed route stops.
               // this.clear_other_rstop_selections();
               //
               this.route.mark_route_panel_dirty();
            }

            this.tooltip_display(false);
            this.tooltip_timer.stop();
         }

         G.map.double_click.detector_reset();
      }

      //
      public function on_mouse_up(event:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_up: sel?:', this.rstop_selected, '/', this);

         // Don't disable route_stop editing yet; keep the dashed line and
         // arrows until the route request completes.
         //  m4_DEBUG('on_mouse_down: disabling rstop_editing_enabled');
         //  route.rstop_editing_enabled = false;

         if ((this.rstop_selected)
             && (G.map.tool_cur is Tool_Pan_Select)) {
            (G.map.tool_cur as Tool_Pan_Select).void_next_clear = true;
         }

         // Check this.dirty_stop -- only do the Route_Path_Edit_Command if the
         // user dragged the route stop. Otherwise they just clicked it.
         // 2013.12.14: Timer is disabled always now. FYI.
         if ((this.dirty_stop) && (!Route_Editor_UI.use_update_timer)) {
            m4_DEBUG2('on_mouse_up: tool_cur.dragged_object:',
                      G.map.tool_cur.dragged_object);
            m4_DEBUG2('on_mouse_up: tool_cur.dragging:',
                      G.map.tool_cur.dragging);
            m4_DEBUG2('on_mouse_up: Route_Editor_UI.new_stop:',
                      Route_Editor_UI.new_stop);
            if (G.map.tool_cur.dragging) {
               m4_DEBUG('on_mouse_up: route_update');
               Route_Editor_UI.route_update(this.route);
               // Wait for route request to clear it: this.dirty_stop = false;
               //   (see: Route.rstops_sync, called from route_update_stitch)
             }
             else {
               m4_DEBUG('on_mouse_up: nixxing unused new route stop');
               Route_Editor_UI.route_stop_remove(this);
               //? Route_Editor_UI.new_stop = null;
             }
         }

         if (G.map.tool_cur.dragged_object !== null) {
            m4_ASSERT_SOFT(G.map.tool_cur.dragged_object === this);
         }

         if (this.rstop_deselecting) {
            this.rstop_deselecting = false;
            m4_DEBUG('on_mouse_up: rstop_selected=f:', this);
            if (this.rstop_selected) {
               this.rstop_selected = false;
               this.route.num_rstops_selected -= 1;
            }
            m4_DEBUG('on_mouse_up: rstop_editing_enabled=f:', this);
            this.route.rstop_editing_enabled = false;
            this.draw();
            this.route.mark_route_panel_dirty();
         }

         G.map.double_click.detector_reset();
      }

      //
      public function on_roll_out(event:MouseEvent) :void
      {
         m4_TALKY('on_roll_out');

         this.mouse_is_over = false;
         this.draw();

         if (!this.mouse_was_finger) {
            UI.cursor_set_native_arrow();
         }
         this.mouse_was_finger = false;

         this.tooltip_display(false);
         this.tooltip_timer.stop();

         if (this.route !== null) {
            this.route.on_mouse_out(event);
         }
      }

      //
      public function on_roll_over(event:MouseEvent,
                                   called_by_route:Boolean=false) :void
      {
         m4_TALKY('on_roll_over:', this);

         this.mouse_is_over = true;
         this.last_mouse_over = event;

         if (!G.map.buttonMode) {
            if (this.is_rstop_editable) {
               UI.cursor_set_native_finger();
            }
         }
         else {
            // Another tool is already active, so don't pretend we're hot,
            // or we've already set the finger cursor.
            this.mouse_was_finger = true;
         }

         this.tooltip_timer.reset();
         this.tooltip_timer.start();

         this.draw();
      }

      //
      public function on_tooltip_timer(event:TimerEvent) :void
      {
         m4_DEBUG('on_tooltip_timer');
         if (this.mouse_is_over) {
            this.tooltip_display(true);
         }
      }

      // instance methods

      //
      public function draw() :void
      {
         m4_DEBUG('draw: sel?:', this.rstop_selected, '/ rt_stop:', this);
         Route_Stop.draw_point(this.x_cv,
                               this.y_cv,
                               this.graphics,
                               this.color,
                               this.mouse_is_over,
                               this.rstop_selected,
                               this.is_endpoint,
                               this.is_pass_through);
      }

      //
      public static function draw_point(x_cv:Number,
                                        y_cv:Number,
                                        g:Graphics,
                                        color:int=-1,
                                        mouse_is_over:Boolean=true,
                                        rstop_selected:Boolean=false,
                                        is_endpoint:Boolean=false,
                                        is_pass_through:Boolean=false) :void
      {
         m4_DEBUG4('draw_point: mouse_is_over:', mouse_is_over,
                   '/ rstop_selected:', rstop_selected,
                   '/ is_endpoint:', is_endpoint,
                   '/ is_pass_through:', is_pass_through);

         if (color < 0) {
            color = Conf.route_color;
         }

         var radius:Number;
         // If the route is rstop_selected, draw a larger circle.
         if ((is_endpoint) || (!is_pass_through)) {
            radius = (rstop_selected ? 12 : 10);
         }
         else {
            radius = (rstop_selected ? 8 : 6);
         }

         g.clear();
         g.lineStyle(/*thickness=*/2, /*color=*/0x000000);

         if (mouse_is_over || rstop_selected) {
            // MAGIC_NUMBER: -25 means darken 25% towards the color black.
            //g.beginFill(ColorUtil.adjustBrightness2(color, /*brite=*/-25));
            g.beginFill(ColorUtil.adjustBrightness2(color, /*brite=*/-50));
         }
         else {
            g.beginFill(color);
         }

         // If the route is rstop_selected, draw a larger circle.
         g.drawCircle(x_cv, y_cv, radius);
         g.endFill();

         if (rstop_selected) {
            g.lineStyle(/*thickness=*/2, Conf.route_stop_highlight_color);
            g.beginFill(ColorUtil.adjustBrightness2(color, /*brite=*/-50));
            radius -= 2;
            g.drawCircle(x_cv, y_cv, radius);
            g.endFill();
         }

      }

      //
      // See/C.f.: Route_Directions.lookat_dstep/Route_Stop.lookat_rstop.
      public function lookat_rstop() :void
      {
         m4_TALKY('lookat_rstop: rstop:', this);
         G.map.pan_and_zoomto(this.x_cv,
                              this.y_cv,
                              // FIXME/EXPLAIN: What's a good zoom level?
                              (G.map.zoom_level < 15 ? 15 : G.map.zoom_level)
                                 // This is 2:1 meters:pixel.
                              );
      }

      // If two route stops are near one another, hide the inferior one if
      // within this distance.
      protected static const ttip_rstop_nearness:int = 8;

      //
      protected function tooltip_display(on:Boolean) :void
      {
         var tt:String = ''; // tooltip text
         var i:int;
         var j:int;
         var letter:int;
         var name:String;

         var w:Route_Stop;
         var rstops:Array = new Array();

         m4_DEBUG('tooltip_display: on:', on, '/', this);

         if (on) {

            m4_ASSERT(this.last_mouse_over !== null);

            // remove any current tooltip
            if (tooltip !== null) {
               ToolTipManager.destroyToolTip(tooltip);
            }

            rstops.push(this);
            for each (w in this.route.edit_stops) {
               if ((w !== this)
                   && (   (w.is_endpoint)
                       || (!w.is_pass_through)
                       || (w.is_transit_stop))
                   && (Geometry.distance(this.x_cv, this.y_cv, w.x_cv, w.y_cv)
                       <= Route_Stop.ttip_rstop_nearness)) {
                  // We found a route_stop that is very close to this one.
                  rstops.push(w);
               }
            }

            for (i = 0; i < rstops.length; i++) {

               if (i > 0) {
                  tt += ',\n';
               }

               w = rstops[i];
               letter = 0;
               for (j = 0; j < this.route.edit_stops.length; j++) {
                  // FIXME: Make db constraint:
                  //          not (is_pass_through and is_transit_stop)
                  if (   (this.route.edit_stops[j].is_endpoint)
                      || (!this.route.edit_stops[j].is_pass_through)
                      || (this.route.edit_stops[j].is_transit_stop)) {
                     if (this.route.edit_stops[j] === w) {
                        // 2014.04.28: Haha, we can't trust the ordering of the
                        // outer rstops array, so we have to loop over the
                        // route's edit stops for every outer route stop.
                        break;
                     }
                     letter++;
                  }
               }

               if (w.name_ === null) {
                  name = w.street_name;
               }
               else {
                  name = w.name_;
               }

               if (w.is_transit_stop) {
                  if (w.is_arrive) {
                     tt += Strutil.letters_uc[letter] + ': Board ' + name;
                  }
                  else {
                     tt += Strutil.letters_uc[letter] + ': Get off ' + name;
                  }
               }
               else if ((w.is_endpoint) || (!w.is_pass_through)) {
                  tt += Strutil.letters_uc[letter] + ': ' + name;
               }
               // else: is_pass_through (user-suggested clicked to create
               //       intermediate route_stop and didn't name it, so it's
               //       not important), so ignore it (it's only included
               //       because it's less than 8 meters from another stop).
            }

            if (rstops.length == 0) {
               // "Point entered on map"
               if ((!name) || (name == Conf.route_stop_map_name)) {
                  name = 'Intermediate route stop or checkpoint';
               }
               tt = name;
            }

            m4_DEBUG('tooltip_display: tt:', tt);
            if (tt.length > 0) {
               // show the tooltip at the last mouse event
               tooltip = ToolTipManager.createToolTip(
                  tt, last_mouse_over.stageX, last_mouse_over.stageY);
            }
         }
         else {
            // hide and destroy the tooltip if it is visible
            if (tooltip !== null) {
               ToolTipManager.destroyToolTip(tooltip);
            }
            tooltip = null;
         }

         // clear last mouse over event
         this.last_mouse_over = null;
      }

      // *** Moved from Route_Stop_Entry

      //
      public function geocoded_clear(keep_results:Boolean=false) :void
      {
         if (this.gwis_geocode !== null) {
            this.gwis_geocode.cancel();
            this.gwis_geocode = null;
         }
         m4_DEBUG2('geocoded_clear: addy_geocode.clear_addy: keep_results:',
                   keep_results);
         this.addy_geocode.clear_addy(keep_results);
      }

      // Update a route stop's name to the specified string and begin
      // the geocoding process.
      public function geocode_start(raw_addr_input:String) :void
      {
         if ((raw_addr_input != '')
             && (!this.addy_geocode.is_geocoded())
             && (!this.addy_geocode.results_none)
             && (!this.addy_geocode.results_error)
             && (this.addy_geocode.results_xml === null)) {
            if (this.gwis_geocode !== null) {
               if (this.gwis_geocode.addrs[0] != raw_addr_input) {
                  m4_DEBUG('geocode_start: canceling old gwis_geocode');
                  this.geocoded_clear();
               }
               else {
                  m4_DEBUG('geocode_start: not canceling old gwis_geocode');
               }
            }
            else {
               m4_DEBUG('geocode_start: starting new gwis_geocode');
            }
            if (this.gwis_geocode === null) {

               this.x_map = NaN;
               this.y_map = NaN;
               this.name_ = raw_addr_input;
               if (this === Route_Editor_UI.new_stop) {
                  // clear this now since the user has chosen to enter text
                  Route_Editor_UI.new_stop = null;
                  G.map.tool_choose('tools_pan');
                  // Trigger: this.route.route_panel.repopulate();
                  // so that, e.g., "Cancel" changes back to "Add Destination".
                  this.route.mark_route_panel_dirty();
               }

               this.gwis_geocode = new GWIS_Geocode(
                  [raw_addr_input,],
                  this.on_gwis_getgeocode_okay,
                  this.on_gwis_getgeocode_fail);
               var found_duplicate:Boolean;
               found_duplicate = G.map.update_supplemental(
                                       this.gwis_geocode);
               m4_ASSERT_SOFT(!found_duplicate);
            }
         }
      }

      //
      public function on_gwis_getgeocode_fail(
         gwis_req:GWIS_Geocode, rset:XML) :void
      {
         this.gwis_geocode = null;

         //this.addy_geocode.clear_addy();
         this.addy_geocode.results_error = true;
         this.addy_geocode.error_message = rset.@msg;

         m4_WARNING2('on_gwis_getgeocode_fail: GWIS_Geocode failed:',
                     this.addy_geocode);

         var rt_panel:Panel_Item_Route_Details
            = this.route.route_panel.tab_route_details;
         var rs_entry:Route_Stop_Entry =
            ((rt_panel.rstops.grid_rstops.itemToItemRenderer(this))
             as Route_Stop_Entry);
         rs_entry.show_addy_resolver();
      }

      // Called when GWIS_Geocode finishes. If both to and from addresses
      // have been unambiguously geocoded, proceed to route finding; if not,
      // present the disambiguation dialog box.
      // C.f. Address_Resolver.on_gwis_getgeocode_okay / Route_Stop_Entry.same
      public function on_gwis_getgeocode_okay(
         gwis_req:GWIS_Geocode, results:XML) :void
      {
         m4_DEBUG('on_gwis_getgeocode_okay: results:', results.toXMLString());
         m4_DEBUG('on_gwis_getgeocode_okay: gwis_req.addrs:', gwis_req.addrs);

         var results_xml:XML = null;
         results_xml = results.addr[0];
         m4_DEBUG('on_gwis_getgc_ok: results_xml:', results_xml);
         m4_DEBUG('on_gwis_getgc_ok: results_xml.addr:', results_xml.addr);

         this.gwis_geocode = null;
         this.addy_geocode.clear_addy();

         if (results_xml !== null) {
            this.addy_geocode.results_xml = results_xml.addr;
            var results_len:int = this.addy_geocode.results_xml.length();
            for (var i:int = 0; i < results_len; i++) {
               this.addy_geocode.results_xml[i].@results_index = i;
            }
            m4_DEBUG2('gwis_getgeocode_ok/2: _chosen.results_xml:',
                      this.addy_geocode.results_xml.toXMLString());
            m4_DEBUG2('gwis_getgeocode_ok/3: _chosen.results_xml.length():',
                      this.addy_geocode.results_xml.length());

            // If first result smells of confidence, than auto-choose-mo-tron.
            if ((results_xml.addr.length() >= 1)
                && (results_xml.addr[0].@gc_ego == 100)) {

               m4_DEBUG('gwis_getgeocode_ok/4: using first confident result');

               this.addy_geocode.choose_addy(/*results_index=*/0);
               // We'll update this.addr_crazyclear_btn next.

               this.name_ = this.addy_geocode.proper_address;
               this.x_map = this.addy_geocode.geocoded_ptx;
               this.y_map = this.addy_geocode.geocoded_pty;
               //this.geocoded_w = this.addy_geocode.geocoded_w;
               //this.geocoded_h = this.addy_geocode.geocoded_h;
               //this.gc_fulfiller = this.addy_geocode.gc_fulfiller;
               //this.gc_confidence = this.addy_geocode.gc_confidence;

               // Create new Route_Path_Edit_Command and call panel_activate.
               Route_Editor_UI.route_update(this.route);
            }
            // else, we'll show the geocoder destination resolver.
         }
         m4_ASSERT_ELSE_SOFT; // else, no results_xml, so, would've errored.

         var rt_panel:Panel_Item_Route_Details
            = this.route.route_panel.tab_route_details;
         var rs_entry:Route_Stop_Entry =
            ((rt_panel.rstops.grid_rstops.itemToItemRenderer(this))
             as Route_Stop_Entry);
         rs_entry.show_addy_resolver();
      }

      // ***

      //
      override public function toString() :String
      {
         // Skip super.toString(), which just returns '[object Route_Stop]'.
         return ('RteStop '
                 + '"' + Strutil.snippet(this.name_) + '"'
                 //+ ' | x_m ' + this.x_map
                 //+ ' | y_m ' + this.y_map
                 + ' v' + String(this.stop_version)
                 + (this.rstop_selected ? ' rs_sel' : '')
                 + (this.dirty_stop ? ' dirty' : '')
                 + (this.is_endpoint ? ' endp' : '')
                 + (this.is_pass_through ? ' xthru' : '')
                 + (this.node_id ? (' nid:' + String(this.node_id) + '.') : '')
                 + (this.internal_system_id
                    ? (' sysid:' + String(this.internal_system_id)) : '')
                 + (this.external_result ? ' external' : '')
                 + (this.is_transit_stop ? ' transit' : '')
                 + (this.is_arrive ? ' arrive' : '')
                 + ((this.street_name_ !== null)
                    ? (' (' + Strutil.snippet(this.street_name_) + ')')
                    : ' (nostr.)')
                 + ' / ' + this.route.softstr
                 );
      }

      //
      public function get loudstr() :String
      {
         // Skip super.toString(), which just returns '[object Route_Stop]'.
         return ('Route_Stop:'
                 + ' | name_ ' + this.name_
                 + ' | nid ' + String(this.node_id)
                 + ' | ver ' + String(this.stop_version)
                 + ' | is_endpt? ' + this.is_endpoint
                 + ' | pass_thru? ' + this.is_pass_through
                 + ' | tx_stop? ' + this.is_transit_stop
                 + ' | int_sid? ' + this.internal_system_id
                 + ' | ext_res? ' + this.external_result
                 + ' | st_nam: ' + this.street_name_
                 + ' | arrive? ' + this.is_arrive
                 + ' | x_m ' + this.x_map
                 + ' | y_m ' + this.y_map
                 + ' | dirty? ' + this.dirty_stop
                 + ' | rstop_sel? ' + this.rstop_selected
                 + ' | route: ' + this.route
                 );
      }

      //
      public function get softstr() :String
      {
         return this.toString();
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets.tools {

   import flash.display.Sprite;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.geom.Rectangle;
   import flash.ui.Keyboard;
   import flash.utils.Timer;

   import items.Geofeature;
   import items.feats.Byway;
   import items.feats.Route;
   import items.feats.Terrain;
   import items.utils.Tile;
   import items.verts.Vertex;
   import utils.geom.Geometry;
   import utils.misc.A_Star;
   import utils.misc.Logging;
   import utils.misc.Strutil;
   import utils.rev_spec.*;
   import views.base.App_Action;
   import views.base.Map_Canvas_Base;
   import views.base.Map_Zoom_Listener;
   import views.base.Paint;
   import views.map_widgets.Bubble_Node;
   import views.map_widgets.Item_Sprite;
   import views.panel_items.Panel_Item_Geofeature;
   import views.panel_items.Panel_Item_Versioned;
   import views.panel_routes.Route_Stop;

   public class Tool_Pan_Select extends Map_Tool implements Map_Zoom_Listener {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:Pan_Sel');

      // *** Instance variables

      protected var bubble_widget:Sprite; // sprite for active bubble nodes
      protected var mouse_line:Sprite;

      // radius of bubble cursor activation, negative disables it
      public var bubble_radius:Number;

      protected var bubbled:Bubble_Node;

      // The last selected bubble_node
      protected var anchor_:Bubble_Node;

      protected var path:Array;
      protected var last_bubbled:Bubble_Node;
      protected var last_path:Array;

      public var shift_down:Boolean; // Read-only
      // Set to true on vertex mouse up to disable clearing of the
      // next selection
      protected var void_next_clear_:Boolean;

      // 2013.06.08: Don't pan unless mouse_down-to-mouse_up was most than just
      // a quickie. Oftentimes, user is just trying to select an item on the
      // map, and this makes it rather annoying (especially since loading the
      // viewport takes a few seconds, and the display flickers... and we
      // haven't fixed either of those things).
      protected const min_pan_threshold:int = 13; // pixels.

      // If the user clicks and holds on two or more items, show the selection
      // resolver.
      protected var long_press_timer:Timer = null;
      public var handled_in_long_press:Boolean = false;
      protected var mouse_down_gf:Geofeature = null;
      // Somehow, keeping a handle to the mouse event after it's processed is
      // legal...
      protected var mouse_down_ev:MouseEvent = null;

      // *** Constructor

      // EXPLAIN: What are the radius units? Also, FYI, that's for finding node
      //          endpoint neighbors.
      public function Tool_Pan_Select(map:Map_Canvas_Base, radius:Number=40)
      {
         super(map);
         //m4_DEBUG('Tool_Pan_Select: bubble_radius:', radius);
         this.bubble_radius = radius;
         this.use_finger_cursor = false;
         this.path = null;
         this.last_path = null;
         this.last_bubbled = null;

         // MAGIC_NUMBER: Wait a good second or so while mouse is pressed.
         this.long_press_timer = new Timer(/*delay=*/1167, /*repeatCount=*/1);
         this.long_press_timer.addEventListener(
            TimerEvent.TIMER, this.on_long_press_timer);
      }

      // *** Getters and setters and applies-tos

      //
      public function get anchor() :Bubble_Node
      {
         return this.anchor_;
      }

      public function set anchor(i:Bubble_Node) :void
      {
         m4_TALKY('set anchor: i:', i);
         if (this.anchor_ !== null) {
            this.anchor_.draw();
            this.bubble_widget.removeChild(this.anchor_);
         }
         this.anchor_ = i;
         if (i !== null) {
            this.bubble_widget.addChild(this.anchor_);
            this.mouse_line_update();
            i.draw();
         }
      }

      //
      override public function mouse_event_applies_to(target_:Object) :Boolean
      {
         //return (item is Geofeature);
         // 2013.06.08: The same tool is used on Vertices, too.
         return ((target_ is Geofeature) || (target_ is Vertex));
      }

      //
      override public function get tool_is_advanced() :Boolean
      {
         return false;
      }

      //
      override public function get tool_name() :String
      {
         return 'tools_pan';
      }

      // Panning and selecting is always allowed.
      override public function get useable() :Boolean
      {
         return G.app.mode.is_allowed(App_Action.map_pan_zoom);
      }

      // The Pan/Select tool is the only tool that responds to double click.
      override public function get uses_double_click() :Boolean
      {
         return true;
      }

      override public function get void_next_clear() :Boolean
      {
         return this.void_next_clear_;
      }

      override public function set void_next_clear(void_it:Boolean) :void
      {
         m4_DEBUG('setting void_next_clear: void_it:', void_it);
         this.void_next_clear_ = void_it;
      }

      // *** Double click detector mouse handlers

      // MAYBE: Should the dragging behaviour be moved out of Map_Tool.as
      //        and put here, or be put in its own class?
      override public function on_mouse_down(ev:MouseEvent,
                                             could_be_double_click:Boolean)
                                                :void
      {
         // MAYBE: We don't need this override anymore, do we?
         super.on_mouse_down(ev, could_be_double_click);
         // Only clear the de-select indicator if we know this is truly the
         // start of a single mouse click, and not potentially a double click.
         if ((!this.map.double_click.detecting)
             || (this.map.double_click.complete_first_click)) {
            // MAYBE: Verify this is true:
            m4_DEBUG('  >> void_next_clear: do not need to clear on down?');
            // No:
            //    this.void_next_clear = false;
         }

         if (this.map.double_click.detecting) {
            this.long_press_timer.reset();
            this.long_press_timer.start();
            this.mouse_down_gf = this.map.get_geofeature(ev);
            // MAYBE: It might technically be illegal to keep this reference,
            //        but testing says the object is still okay to use after
            //        the event is processed.
            this.mouse_down_ev = ev;
         }
      }

      // MAYBE: While holding the mouse down on the map and panning, nothing
      //        updates until the mouse is released. We could, e.g., call
      //        update_viewport_items and load items and/or tiles while the
      //        user is panning, perhaps if the user pauses mouse movements
      //        for 1/3 of a second or so.

      // This is a fake mouse up, and not in competition with double click.
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         m4_DEBUG5('on_mouse_up: target:', Strutil.snippet(String(ev.target)),
                   '/ processed:', processed,
                   '/ dragging:', this.dragging,
                   '/ dragged_object:', ((this.dragged_object !== null)
                                         ? this.dragged_object : 'null'),
                   '/ handled_in_long_p:', this.handled_in_long_press);

         processed = this.handled_in_long_press;
         this.handled_in_long_press = false;
         this.long_press_timer.stop();

         var active_route_stop:Route_Stop = null;

         if (!processed) {
            if (this.dragging) {
               if (this.dragged_object is Vertex) {
                  // Nothing to do here.
                  this.map.double_click.detector_reset();
               }
               else if (this.dragged_object is Route_Stop) {
                  // No, wait, don't do this yet: we might submit a route
                  // request, so keep the dashed lines and arrows until
                  // the new route segments are received.
                  //  m4_DEBUG('on_mouse_up: resetting rstop_editing_enabled');
                  //  (this.dragged_object as Route_Stop)
                  //     .route.rstop_editing_enabled = false;
                  m4_DEBUG('on_mouse_up: target:', ev.target);
                  m4_DEBUG('on_mouse_up: currentTarget:', ev.currentTarget);
                  // Route_Stop has its own on_mouse_up handler. But if the
                  // user drags fast enough, the mouse up might not happen on
                  // the Route_Stop. E.g.,
                  //    on_mouse_up: target: [object Loader]
                  if (!(ev.target is Route_Stop)) {
                     m4_DEBUG('on_mouse_up: target !Route_Stop: on_mouse_up');
                     active_route_stop = (this.dragged_object as Route_Stop);
                  }
                  // else, the Route_Stop handler will get the event normally.
                  // Stop the double-click detector.
                  this.map.double_click.detector_reset();
               }
               else {

                  // BUG_FALL_2013: TEST: Clicking and panning and editing.
                  // [lb] had a problem with panning happening when I meant
                  //      to select an item (I think that's what it was).
                  //      Anyway, just test this better, then fix bugs and
                  //      remove this comment.

                  // Otherwise, user just dragged the map, so refresh the
                  // viewport.
                  // BUG nnnn: Better panning.
                  //           1. Fade tiles in as they load.
                  //           2. Keep a bigger region outside the viewport
                  //           that is saved, and sometimes users pan back
                  //           from whence they panned, so use another
                  //           hueristic for discarding, i.e., keep more crap
                  //           around in memory longer to give the user a less
                  //           crappy, pleasing experience.
                  this.map.update_viewport_items();
               }
               processed = true;
            }
            else if (ev.target is Route_Stop) {
               // BUG_JUL_2014: There might be a problem double-clicking route
               // widgets, i.e., are we calling Route_Stop.on_mouse_up twice
               // because of the double-click detector? [lb] had a problem
               // with something and wrote this comment and hasn't reproduced
               // the problem (but not for lack of trying; I haven't tried).
               m4_DEBUG('on_mouse_up: ev.target is Route_Stop: on_mouse_up');
               active_route_stop = (ev.target as Route_Stop);
               this.map.double_click.detector_reset();
               processed = true;
            }
         }

         if (!processed) {
            if (!this.dragging) {
               // User wasn't panning. This is either a real mouse click, or
               // it's the first click in what could be a double-click. If it's
               // the later, we don't want to de-select items until we know
               // what this click is all about.
               if (this.shift_down) {
                  // using shift-select, so select everything on path
                  if ((this.bubbled !== null) && (this.anchor !== null)) {
                     this.select_path(this.path);
                     G.map.highlights_clear(Conf.path_highlight);
                     processed = true;
                  }
                  if (this.bubbled !== null) {
                     this.anchor = this.bubbled;
                     // FIXME: Don't set processed if !this.anchor, right?
                  }
               }
               else {
                  if (!processed) {
                     var feat:Geofeature = null;
                     feat = this.map.get_geofeature(ev);
                     if (feat !== null) {
                        m4_DEBUG('on_mouse_up: clicked feat:', feat);
                        //processed = feat.on_mouse_up_select_item(ev);
                        processed = this.on_mouse_up_select_item(ev);
                     }
                     else if (ev.ctrlKey) {
                        // else, user didn't click a Geofeature, but they have
                        // the ctrl key down, meaning they're maintaining a
                        // selection, so make sure not to deselect any items.
                        m4_DEBUG('on_mouse_up: ctrl-clicked- but no feat');
                        processed = true;
                     }
                     else {
                        if (!(G.tabs.settings.close_panel_on_noselect)) {
                           // On no-select, don't do anything, i.e., keep the
                           // active selection active.
                           m4_DEBUG('on_mouse_up: ignoring click-on-nothing');
                           processed = true;
                        }
                        // else, keep the selected items selected.
                        // Always reset selectn resolver after "nothing" click.
                        this.map.sel_resolver.reset_resolver();
                     }
                     m4_DEBUG('on_mouse_up: processed:', processed);

                     // Clear the selection if no ctrl key and no vertex is
                     // selected; Geofeature handles selecting the last-clicked
                     // feat. (except when in feedback mode, where the route is
                     // never deselected).
                     m4_TALKY2('  ctrl:', ev.ctrlKey,
                                 '/ void_next_clear:', this.void_next_clear);
                     // VERIFY: This code is disabled in CcpV2. [lb] replaced
                     //         it with the processed Boolean.
                     //if ((!ev.ctrlKey)
                     //    && (!this.void_next_clear)
                     //    && (this.map.rmode != Conf.map_mode_feedback)) {
                     //   // Implicitly calls: this.map.map_selection_clear()
                     //   G.panel_mgr.effectively_active_panel = null;
                     //   this.map.sel_resolver.reset_resolver();
                     //}
                  }
                  if ((!processed) && (!(ev.target is Vertex))) {
                     if (!G.map.attachment_mode_on) {
                        // User clicked map in regular mode, so deselect all.
                        // On no-select, deselect all and close the active
                        // panel.
                        if ((G.panel_mgr.effectively_active_panel !== null)
                            && (G.panel_mgr.effectively_active_panel
                                is Panel_Item_Geofeature)) {
                           m4_DEBUG('on_mouse_up: closing active feat panel');
                           G.panel_mgr.effectively_active_panel.close_panel();
                        }
                     }
                     //
                     this.map.sel_resolver.reset_resolver();
                  }
               }
            }
         }

         this.void_next_clear = false;

         // Note that the base class, Map_Tool, returns processed unaltered.
         processed = super.on_mouse_up(ev, processed);

         // The Route_Stop mouse handler expects to run after the tool handler,
         // so we wait until now to call it.
         if (active_route_stop !== null) {
            m4_DEBUG('on_mouse_up: Route_Stop: on_mouse_up (calling)');
            active_route_stop.on_mouse_up(ev);
         }

         return processed;
      }

      // This fcn. is called by the Tool_Pan_Select tool.
      protected function on_mouse_up_select_item(ev:MouseEvent) :Boolean
      {
         m4_DEBUG('on_mouse_up_select_item: target:', ev.target);

         // See if the user is using the ctrl key, which affects if we're
         // adding the selected feat to the selectedset, or if we're
         // removing it.
         if (!ev.ctrlKey) {
            // If the user clicked something that's already selected, don't
            // clear it. NOTE: If multiple sprites are on top of each other,
            // and a buried sprite is selected, this will deselect the buried
            // sprite and bring up the selection resolver.
            var feat:Geofeature = this.map.get_geofeature(ev);
            //if ((feat !== null) && (!feat.selected)) {
            if (feat !== null) {
               if (!G.map.attachment_mode_on) {
                  m4_DEBUG('on_mouse_up_select_item: nullifying eap');
                  G.panel_mgr.effectively_active_panel = null;
                  this.map.sel_resolver.reset_resolver();
               }
               else {
                  if (!feat.selected) {
                     this.map.sel_resolver.reset_resolver();
                  }
               }
               //this.map.sel_resolver.reset_resolver();
            }
         }
         // else, ctrlKey is pressed, so we'll just toggle set selected.

         // Select this feat if it's the only feat under the cursor, or
         // prompt the user with the selection resolver.
         // See Selection_Resolver.resolver_complete, which toggles the
         // Geofeature's selected.
         var the_one_item:Geofeature = this.map.sel_resolver.do_resolve(
                                                ev, /*two_plus=*/false);
         m4_DEBUG('on_mouse_up_select_item: the_one_item:', the_one_item);

         // Select the vertices if all the other selected items' vertices are
         // also selected.
         if ((the_one_item !== null)
             && (the_one_item.selected)
             && (G.item_mgr.vertices_selected)) {
            the_one_item.vertices_select_all();
         }

         // Some items, like routes, react to mouse-down. In CcpV1, they set
         // there own mouse listener, but then you'll get two reactions: one
         // by the map canvas and one by the item. Which is why in CcpV2,
         // there's just one, albeit one intelligent, mouse listener.
         if (the_one_item !== null) {
            the_one_item.on_mouse_down(ev);
         }

         // All single clicks on geofeatures are handled.
         const processed:Boolean = true;
         return processed;
      }

      // *** Event handlers

      //
      public function long_press_timer_reset() :void
      {
         this.long_press_timer.reset();
         // Skip: this.handled_in_long_press = false;
         this.mouse_down_gf = null;
         this.mouse_down_ev = null;
      }

      //
      override public function drag(x_old:Number, y_old:Number,
                                    x_new:Number, y_new:Number) :void
      {
         var sx:Number;
         var sy:Number;

         this.long_press_timer_reset();

         if (this.dragged_object === null) {
            var pan_map:Boolean = false;
            if ((!this.shift_down) || (this.anchor === null)) {
               m4_VERBOSE('drag: no shift or anchor: panning');
               pan_map = true;
            }
            else {
               // EXPLAIN: Please someone tell me what this does.
               // We only pan if the map contain this.anchor?
               // And this.anchor is a Bubble_Node, which is used to highlight
               // connectivity?
               // OH, WAIT: This causes the map to pan if the user is dragging
               // something at the edge of the viewport.
               sx = this.map.xform_x_map2cv(this.anchor.b_x) + x_new - x_old;
               sy = this.map.xform_y_map2cv(this.anchor.b_y) + y_new - y_old;
               if (this.map.view_rect.contains_canvas_point(sx, sy)) {
                  m4_VERBOSE('drag: shift and anchor and contains: panning');
                  pan_map = true;
               }
               else {
                  m4_VERBOSE('drag: shift and anchor but no contains: no pan');
               }
            }
            if (pan_map) {
               // But don't pan if we haven't really strayed that far, because
               // a lot of quickie clicks are accidentals: the user is just
               // trying to selected an item by clicks sloppily.
               if (Geometry.distance(x_new, y_new, x_old, y_old)
                   > this.min_pan_threshold) { // 13 pixels
                  m4_VERBOSE('drag: calling this.map.pan');
                  this.map.pan(x_new - x_old, y_new - y_old);
               }
               else {
                  m4_VERBOSE('drag: threshold not violated; not panning');
               }
            }
         }
         else {
            m4_VERBOSE('drag: this.dragged_object:', this.dragged_object);
            // 2013.04.08: EXPLAIN: Why both using Working and Current and not
            //                      Follow? Well, [lb] is trying t'other.
            if (this.dragged_object is Vertex) {
               //if ((this.map.rev_viewport is utils.rev_spec.Working)
               if ((this.map.rev_viewport is utils.rev_spec.Follow)
                   && G.app.mode.is_allowed(App_Action.item_edit)
                   && ((this.map.selectedset.item_get_random()
                        .actionable_at_raster)
                       || (this.map.zoom_is_vector()))) {
                  this.dragged_object.drag(x_new - x_old, y_new - y_old);
               }
            }
            else if (this.dragged_object is Route_Stop) {
               //if ((this.map.rev_viewport is utils.rev_spec.Current)
               if ((this.map.rev_viewport is utils.rev_spec.Follow)
                   && (this.dragged_object as Route_Stop).route.selected) {
                  this.dragged_object.drag(x_new - x_old, y_new - y_old);
               }
            }
            else {
               m4_ASSERT(false); // This shouldn't happen, this tool doesn't
                                 // support dragging byways, just dragging
                                 // the map.
            }
         }
      }

      //
      // NOTE: V1 comment: It would be nice to use Keyboard.SHIFT,
      //         however on some computers, the charCode is reported as 0.
      //       V2 comment: The charCode is 0 because a "real" key hasn't
      //         been pressed, just a modifier key. (Re: Keyboard.SHIFT, Flex
      //         docs show it being compared against keyCode, not charCode:
      //         i.e., if (ev.keyCode == Keyboard.SHIFT) ... .)
      protected function on_keyboard_event(ev:KeyboardEvent) :void
      {
         m4_TALKY('on_keyboard_event: shift_down:', this.shift_down);
         m4_TALKY7('  >> ev:',
            '/ charCode:', ev.charCode,
            '/ keyCode:', ev.keyCode,
            '/ alt:', ev.altKey,
            '/ ctrl:', ev.ctrlKey,
            '/ shift:', ev.shiftKey,
            '/ fromCharCode:', String.fromCharCode(ev.charCode));

         if (this.dragged_object !== null) {
            m4_TALKY('  >> Ignoring: user is panning');
            return;
         }

         if (G.map.rmode != Conf.map_mode_feedback) {
            if (!ev.ctrlKey) {
               G.map.highlight_manager.set_layer_visible(
                  Conf.mouse_highlight, false);

               if (ev.shiftKey == this.shift_down) {
                  return;
               }

               if (this.bubbled !== null) {
                  this.bubbled.radius = -1;
                  this.bubbled.draw();
                  if (this.bubbled !== this.anchor) {
                     this.bubble_widget.removeChild(this.bubbled);
                  }
               }

               this.anchor = null;
               this.path = null;
               this.last_path = null;
               this.last_bubbled = null;

               this.bubbled = null;
               this.mouse_line.graphics.clear();
               this.map.highlights_clear(Conf.path_highlight);

   // FIXME: mouse_line_update not being called

               if (ev.shiftKey && !this.shift_down) {
                  this.shift_down = true;
                  this.anchor_choose_maybe();
                  this.mouse_line_update();
                  G.map.highlight_manager.set_layer_visible(
                     Conf.path_highlight, true);
               }
               else if (!ev.shiftKey && this.shift_down) {
                  this.shift_down = false;
                  G.map.highlight_manager.set_layer_visible(
                     Conf.path_highlight, false);
               }
            }
            else { // ev.ctrlKey
               G.map.highlight_manager.set_layer_visible(
                  Conf.mouse_highlight, true);
            }
         }
         // else, (G.map.rmode == Conf.map_mode_feedback), so no-op.
      }

      //
      public function on_long_press_timer(ev:TimerEvent) :void
      {
         m4_DEBUG('on_long_press_timer: target', this.mouse_down_ev.target);

         var feat:Geofeature = this.map.get_geofeature(this.mouse_down_ev);
         m4_ASSURT(feat === this.mouse_down_gf);

         // If the feature is a Route, the longpress is user asking to drag.
         var route:Route = (feat as Route);
         if ((route !== null) && (route.is_path_clickable)) {
            if (!route.is_path_edit_immediately) {
               m4_DEBUG('on_mouse_up: rstop_editing_enabled=t');
               route.rstop_editing_enabled = true;
               route.on_mouse_down(this.mouse_down_ev);
            }
            else {
               //m4_ASSERT_SOFT(route.currently editing route stop...);
            }
         }
         //else if (this.mouse_down_gf !== null) { ... }
         else if (feat !== null) {
            // Longpress on feature brings up selection resolver.
            //
            //chosen_one = this.map.sel_resolver.do_resolve(this.mouse_down_gf,
            //   this.drag_orig_x, this.drag_orig_y, /*two_plus=*/true);
            var chosen_one:Geofeature = this.map.sel_resolver.do_resolve(
                                    this.mouse_down_ev, /*two_plus=*/true);
            if (this.map.sel_resolver.last_candidate_count > 1) {
               m4_DEBUG('on_long_press_timer: chosen_one:', chosen_one);
               if (chosen_one !== null) {
                  // Select the vertices if all the other selected items'
                  // vertices are also selected.
                  if ((chosen_one.selected)
                      && (G.item_mgr.vertices_selected)) {
                     chosen_one.vertices_select_all();
                  }
                  //??chosen_one.on_mouse_down(ev);
                  chosen_one.on_mouse_down(this.mouse_down_ev);
                  this.handled_in_long_press = true;
               }
            }
            // else, we just showed selection resolver for one item...
            // the one, selected item.
         }
         else {
            // Long press on "nothing" clears selection.
            var do_clear_selection:Boolean = false;
            if (this.mouse_down_ev.target === G.map) {
               // "Nothing" was really selected.
               m4_DEBUG2('on_long_press_timer: target: G.map');
               do_clear_selection = true;
            }
            else {
               var item_sprite:Item_Sprite;
               item_sprite = (this.mouse_down_ev.target as Item_Sprite);
               if (item_sprite !== null) {
                  if (item_sprite.item is Terrain) {
                     // A terrain is top-most sprite.
                     m4_DEBUG2('on_long_press_timer: target: Terrain');
                     do_clear_selection = true;
                  }
                  else if (item_sprite.item is Tile) {
                     // A tile was hit.
                     m4_DEBUG2('on_long_press_timer: target: Tile');
                     do_clear_selection = true;
                  }
               }
            }
            if (do_clear_selection) {
               G.map.map_selection_clear();
               if (G.item_mgr.active_route !== null) {
                  m4_DEBUG2('on_long_press_timer: active_route:',
                            G.item_mgr.active_route);
                  G.item_mgr.active_route.set_selected(false);
               }
            }
         }
      }

      //
      override public function on_mouse_move(x:Number, y:Number) :void
      {
         //m4_VERBOSE('on_mouse_move: dragged_object:', this.dragged_object);

         // The parent might drag the map or the dragged_object.
         super.on_mouse_move(x, y);

// BUG_FALL_2013: Test placing and dragging route stops more thoroughly.
// FIXME: Does this affect Route_Stop? Or is dragged_item set, so it's ok?
         if (this.shift_down) {
            this.mouse_line_update();
         }
      }

      //
      public function on_zoom(o_level:int, n_level:int) :void
      {
         this.anchor_ = null;
         this.bubbled = null;
      }

      // *** Other instance methods

      //
      override public function activate() :void
      {
         m4_TALKY('activate');

         this.bubble_widget = new Sprite();
         this.mouse_line = new Sprite();
         this.mouse_line.mouseChildren = false;
         this.mouse_line.mouseEnabled = false;
         this.map.addChild(this.bubble_widget);
         this.map.addChild(this.mouse_line);

         this.map.zoom_listeners.add(this);

         // Mouse listeners.
         this.map.stage.addEventListener(KeyboardEvent.KEY_DOWN,
                                         this.on_keyboard_event,
                                         false, 0, true);
         this.map.stage.addEventListener(KeyboardEvent.KEY_UP,
                                         this.on_keyboard_event,
                                         false, 0, true);
         // Mouse helpers
         this.shift_down = false;
         this.void_next_clear = false;
      }

      // Possibly selects an anchor, so the user doesn't have to click once
      // in the beginning.  It picks an anchor if a non-null bubble node
      // is within snapping distance, otherwise it reverts to original
      // click-anchor behavior.
      protected function anchor_choose_maybe() :void
      {
         var x:Number = G.map.xform_x_cv2map(G.map.mouseX);
         var y:Number = G.map.xform_y_cv2map(G.map.mouseY);
         var qradius:Number = this.bubble_radius / this.map.scale;
         var i:Bubble_Node;

         m4_TALKY('anchor_choose_maybe');

         if (this.bubble_radius > 0) {
            i = G.map.node_snapper.nearest(x, y, qradius);
            if (i !== null) { // anchor is found
               //m4_DEBUG('anchor_choose_maybe: bubble_radius: -1');
               i.bubble_radius = -1;
            }
            this.anchor = i;
            this.highlight_update();
         }
      }

      //
      protected function calculate_path() :void
      {
         if (this.bubbled === null || this.anchor === null) {
            this.path = null;
         }
         else if (this.bubbled === this.last_bubbled) {
            this.path = this.last_path;
         }
         else {
            this.last_bubbled = this.bubbled;
            this.last_path = A_Star.search(this.anchor, this.bubbled);
            this.path = this.last_path;
         }
      }

      //
      protected function containment_distance(x:Number, y:Number,
                                              r:Number) :Number
      {
         return this.center_distance(x, y) + r;
      }

      //
      protected function center_distance(x:Number, y:Number) :Number
      {
         return Geometry.distance(G.map.xform_x_map2cv(x),
                                  G.map.xform_y_map2cv(y),
                                  G.map.mouseX, G.map.mouseY);
      }

      //
      override public function deactivate() :void
      {
         m4_TALKY('deactivate');

         this.map.zoom_listeners.remove(this);

         this.map.removeChild(this.bubble_widget);
         this.map.removeChild(this.mouse_line);

         this.map.stage.removeEventListener(KeyboardEvent.KEY_DOWN,
                                            this.on_keyboard_event);
         this.map.stage.removeEventListener(KeyboardEvent.KEY_UP,
                                            this.on_keyboard_event);

         this.bubble_widget = null;
         this.mouse_line = null;

         this.anchor = null;

         if (this.bubbled !== null) {
            this.bubbled.radius = -1;
         }
         this.bubbled = null;

         this.path = null;
         this.last_path = null;
         this.last_bubbled = null;

         this.shift_down = false;
         G.map.highlights_clear(Conf.path_highlight);

         // must reset in case the menu is displayed
         G.map.sel_resolver.reset_resolver();
      }

      //
      protected function intersecting_distance(x:Number, y:Number,
                                               r:Number) :Number
      {
         return this.center_distance(x, y) - r;
      }

      //
      protected function highlight_update() :void
      {
         var prev_node:Bubble_Node;
         var curr_node:Bubble_Node;
         var byway:Byway;

         //m4_VERBOSE('highlight_update');

         this.calculate_path();
         this.map.highlights_clear(Conf.path_highlight);

         if (this.path !== null) {
            for each (curr_node in this.path) {
               if (prev_node !== null) {
                  byway = prev_node.connecting_byway(curr_node);
                  if (byway !== null) {
                     byway.set_highlighted(true, Conf.path_highlight);
                  }
               }
               prev_node = curr_node;
            }
         }
      }

      // When the user holds the Shift key down, clicks an endpoint, and moves
      // the mouse, we draw a straight line from the endpoint to the cursor,
      // and we highlight the blocks one would traverse to go from endpoint to
      // cursor. If the user clicks, all of the blocks indicated are selected.
      // This fcn. handles drawing the straight line and the black bubble under
      // the cursor that indicates when the mouse is over an endpoint.
      protected function mouse_line_update() :void
      {
         var x:Number = G.map.xform_x_cv2map(G.map.mouseX);
         var y:Number = G.map.xform_y_cv2map(G.map.mouseY);
         var qradius:Number = this.bubble_radius / this.map.scale;

         //m4_VERBOSE('mouse_line_update');

         if (this.bubbled !== null) {
            this.bubbled.radius = -1;
            this.bubbled.draw();
            if (this.bubbled !== this.anchor
                && this.bubble_widget.contains(this.bubbled)) {
               this.bubble_widget.removeChild(this.bubbled);
            }
            this.bubbled = null;
         }

         if (this.bubble_radius > 0) {
            this.bubbled = G.map.node_snapper.nearest(x, y, qradius);
            if (this.bubbled !== null) {
               this.bubbled.bubble_radius
                  = this.containment_distance(this.bubbled.b_x,
                                              this.bubbled.b_y,
                                              this.bubbled.radius);
               if (this.bubbled !== this.anchor) {
                  this.bubble_widget.addChild(this.bubbled);
               }
               this.bubbled.draw();
            }
            this.highlight_update();
         }

         this.mouse_line.graphics.clear();
         if (this.anchor !== null) {
            Paint.line_draw(this.mouse_line.graphics,
                            [this.anchor.b_x, x],
                            [this.anchor.b_y, y], 2.5, 0x222222);
         }
      }

      //
      protected function select_path(path:Array) :void
      {
         var curr_node:Bubble_Node;
         var prev_node:Bubble_Node;
         var byway:Byway;

         m4_TALKY('select_path');

         if (path === null) {
            return;
         }

         for each (curr_node in path) {
            if (prev_node !== null) {
               byway = prev_node.connecting_byway(curr_node);
               if (byway !== null) {
                  byway.set_selected(!byway.is_selected());
               }
            }
            prev_node = curr_node;
         }

         this.last_bubbled = null;
         this.last_path = null;
         this.path = null;
      }

   }
}


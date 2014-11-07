/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Part of the Map class hierarchy.

package views.base {

   import flash.display.InteractiveObject;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.ui.Keyboard;
   import flash.utils.Timer;
   import mx.core.UITextField;
   import mx.events.FlexEvent;
   import mx.events.ResizeEvent;

   import items.Geofeature;
   import items.feats.Byway;
   import items.feats.Route;
   import items.feats.Terrain;
   import items.verts.Vertex;
   import utils.misc.Double_Click_Detector;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.map_widgets.Item_Sprite;
   import views.map_widgets.tools.Tool_Node_Endpoint_Build;
   import views.panel_routes.Route_Editor_UI;

   public class Map_Canvas_Controller extends Map_Canvas_Commands {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('MC_Contrller');

      // *** Instance attributes

      // A collection of objects to be notified when the zoom level changes.
      public var zoom_listeners:Set_UUID;

      // A mouse event helper class to circumvent Flash's mouse event either-or
      // limitation, whereby it sends either up, down, and click events, or
      // doubleclick events, but not both, according to doubleClickEnabled.
      public var double_click:Double_Click_Detector;

      // Too prevent over-wheeling, we use a shut-out timer to prevent
      // processing too many wheel events in a small amount of time.
      protected var mouse_wheel_count:int = 0;
      protected var mouse_wheel_timer:Timer = null;

      //
      protected var creation_completed:Boolean = false;
      protected var branch_and_nip_ready:Boolean = false;

      // *** Constructor

      public function Map_Canvas_Controller()
      {
         super();

         this.zoom_listeners = new Set_UUID();

         // NOTE: Not listening for ResizeEvent.RESIZE. See main.mxml:
         //       G.app.map_canvas catches the event and calls G.map.on_resize
         //       (our fcn.) only if the app is started.
         //this.addEventListener(ResizeEvent.RESIZE, this.on_resize);

         // Wait until the map is completely created before setting the mouse
         // handlers.
         this.addEventListener(FlexEvent.CREATION_COMPLETE,
                               this.on_creation_complete, false, 0, true);
      }

      // *** Startup methods

      //
      override public function startup() :void
      {
         // NOTE: this.zoomto() is not yet working when this method is called.
         super.startup();
         // The map supports a number of keyboard shortcuts, so hook the 'board
         G.app.stage.addEventListener(KeyboardEvent.KEY_DOWN,
                                      this.on_keydown, false, 0, true);
         // Other objects in the listen to listen to us for zoom level changes.
         this.zoom_listeners.add(G.app.zoombar);
      }

      // *** Event handlers

      // Resize and update the map.
      public function on_resize(event:ResizeEvent=null,
                                skip_update:Boolean=false)
         :void
      {
         m4_DEBUG_CLLL('<callLater: G.map.on_resize');

         // m4_DEBUG('on_resize: G.app.w:', G.app.width, '/ h:', G.app.height);
         // m4_DEBUG2('on_resize: w:', G.app.map_canvas.width,
         //          '/ h:', G.app.map_canvas.height);
         // m4_DEBUG2('on_resize: w:', this.parent.width,
         //                    '/ h:', this.parent.height);

         // EXPLAIN: ResizeEvent is always null. Did it use to be used?
         m4_ASSERT(event === null);

         // I don't understand why this.width and this.height are incorrect.
         // The hack in measure() helps somewhat, but the parent's dimensions
         // are still more reliable.
         if (!G.app.map_key.visible) {
            G.app.map_key.on_canvas_change_dimensions();
            G.app.map_key.visible = true;
         }

         if (G.app.invitation_bar.visible) {
            G.app.panel_window_canvas.y = G.app.invitation_bar.height;
         }
         else {
            G.app.panel_window_canvas.y = 0;
         }

         this.view_rect_resize();
         this.invalidateSize();
         if (!skip_update) {
            this.update_viewport_items();
         }
      }

      // Key-down event handler. Ignore event if focus is on a control which
      // should have higher typing priority.
      public function on_keydown(ev:KeyboardEvent) :void
      {
         var focus:InteractiveObject = G.app.stage.focus;

         m4_VERBOSE8('on_keydown:',
            '/ charCode:', ev.charCode,
            '/ keyCode:', ev.keyCode,
            '/ alt:', ev.altKey,
            '/ ctrl:', ev.ctrlKey,
            '/ shift:', ev.shiftKey,
            '/ fromCharCode:', String.fromCharCode(ev.charCode),
            '/ dragging:', G.map.tool_cur.dragging);

         if (!(focus is UITextField)) {
            if (!G.map.tool_cur.dragging) {
               this.on_keydown_mouseless(ev);
            }
            else {
               this.on_keydown_dragging(ev);
            }
         }
      }

      //
      protected function on_keydown_mouseless(ev:KeyboardEvent) :void
      {
         //
         // NOTE: For the list of Keyboard key Macros, see:
         //  http://livedocs.adobe.com/flex/3/langref/flash/ui/Keyboard.html
         //
         // FIXME: Make addEventListener style and push code to other
         //        classes? i.e., for (var lstnr:Function in
         //        this.on_keydown_listeners) In other words, make command
         //        objects rather than having one really big switch
         //        statement.
         //
         var pan_step:Number =
            ev.shiftKey ? Conf.pan_step_large : Conf.pan_step_small;
         var zoom_step:Number = ev.shiftKey ? 2 : 1;
         var handled:Boolean = true;
         var route:Route = null;

         switch (ev.keyCode) {
            case Keyboard.DELETE:      // (keyCode 46, charCode 127)
            case Keyboard.BACKSPACE:   // (keyCode 8, charCode 8)
               route = (this.selectedset.item_get_random() as Route);
               if (route !== null) {
                  m4_DEBUG('on_keydown_mouseless: del/bs: rt:', route.softstr);
                  Route_Editor_UI.selected_rstops_delete(route);
               }
               else {
                  Geofeature.vertex_selected_delete();
               }
               break;

            case 187:                  // (kC 187, cC 43 '+', or 61 '=')
            case Keyboard.NUMPAD_ADD:  // (keyCode 107, charCode 43)
               // NOTE Keyboard.EQUAL (187) is in the docs, but not the SDK
               this.zoom_in(zoom_step);
               break;
            case 189:                  // (keycode 189, charcode 45)
            case Keyboard.NUMPAD_SUBTRACT: // - (keyCode 109, charCode 45)
               // NOTE Keyboard.MINUS (189) is in the docs, but the
               //      compiler complains. I guess not surprisingly
               //      Keyboard.ADD doesn't turn up in either place.
               this.zoom_in(-zoom_step);
               break;
            case Keyboard.HOME:        // (keyCode 36, charCode 0)
               this.zoomto(Conf.zoom_min);
               break;
            case Keyboard.END:         // (keyCode 35, charCode 0)
               this.zoomto(Conf.zoom_max);
               break;
            case Keyboard.RIGHT:       // (keyCode 39, charCode 0)
               G.map.pan_frac(-pan_step, 0);
               break;
            case Keyboard.DOWN:        // (keyCode 40, charCode 0)
               G.map.pan_frac(0, -pan_step);
               break;
            case Keyboard.LEFT:        // (keyCode 37, charCode 0)
               G.map.pan_frac(pan_step, 0);
               break;
            case Keyboard.UP:          // (keyCode 38, charCode 0)
               G.map.pan_frac(0, pan_step);
               break;

            // BUG_FALL_2013/BUG nnnn: Don't change tools when dragging.
            // Also, if dragging a route, pressing ESC cancels the drag.
            case Keyboard.ESCAPE:      // Pan/Select Map_Tool
               route = (this.selectedset.item_get_random() as Route);
               if (route !== null) {
                  m4_DEBUG('on_keydown_mouseless: escape: rt:', route.softstr);
                  route.disable_rstop_editing();
               }
               else {
                  this.tool_choose('tools_pan');
               }
               break;

            default:
               handled = false;
               break;
         }
         // Map_Tool palette shortcuts
         if (!handled) {
            // Note that keyCode is case-insensitive: you cannot discern if
            // the user is using the shift or capslock modifier. So we
            // use a separate case to examine alphabetic characters using
            // charCode, in case we want to distinguish between upper and
            // lower case (in some apps, the lowercase key selects the tool
            // 'group', and the uppercase key cycles through the individuals
            // tools in that group.)
            //
            // EXPLAIN: Does this work on international keyboards?
            handled = true;
            switch (ev.charCode) {
               case 115: // Pan/[s]elect Map_Tool
               //case 83: // Pan/[S]elect Map_Tool
                  this.tool_choose('tools_pan');
                  break;
               case 97: // [a]dd Point
               //case 65: // [A]dd Point
                  if (this.tool_dict['tools_point_create'].useable) {
                     this.tool_choose('tools_point_create');
                  }
                  break;
               case 98:  // Add [b]yway
               //case 66:  // Add [B]yway
                  if (this.tool_dict['tools_byway_create'].useable) {
                     this.tool_choose('tools_byway_create');
                  }
                  break;
               case 114: // Add [r]egion
               //case 82: // Add [R]egion
                  if (this.tool_dict['tools_region_create'].useable) {
                     this.tool_choose('tools_region_create');
                  }
                  break;
               case 118: // Add [v]ertex
               //case 86: // Add [V]ertex
                  if (this.tool_dict['tools_vertex_add'].useable) {
                     this.tool_choose('tools_vertex_add');
                  }
                  break;
               case 122: // Split Byway [z]
               //case 90: // Split Byway [Z]
                  if (this.tool_dict['tools_byway_split'].useable) {
                     this.tool_choose('tools_byway_split');
                  }
                  break;
               case 120: // Make Intersection [x]
               //case 88: // Make Intersection [X]
                  if (this.tool_dict['tools_node_endpoint_build'].useable) {
                     this.tool_choose('tools_node_endpoint_build');
                  }
                  break;
               // Control Panel shorts
               // FIXME: These are not discoverable
               case 99: // [c]onnectivity
               //case 67: // [C]onnectivity
                  G.tabs.settings.settings_panel.settings_options
                     .connectivity_cbox.selected
                        = !G.tabs.settings.connectivity;
                  Byway.connectivity_remove_maybe();
                  break;
               case 105: // Toggle Reg[i]ons
               //case 73: // Toggle Reg[I]ons
                  G.tabs.settings.regions_visible
                     = !G.tabs.settings.regions_visible;
                  break;
               case 111: // o, as is Open?
               //case 79: // O
                  G.tabs.settings.settings_panel.settings_options
                     .sticky_intersections.selected
                        = !G.tabs.settings.sticky_intersections;
                  break;
               case 112: // Aerial [p]hotos
                  // MAYBE: This feels more like it should be G.map.aerial=.
                  this.aerial_enabled = !this.aerial_enabled;
                  break;
               case 47: // "/" (forward slash) for search.
                  G.app.ccp_header.search_box.search_query.setFocus();
                  G.app.ccp_header.search_box.search_query.text = "";
                  break;
               // 2013.08.22: Chrome's Ctrl-Shift-T restores last closed tab,
               //             and maintains a list of 10 previously closed
               //             tabs.
               // IDEAL/BUG nnnn: Implement Shift-T to open closed item
               //                 detail panels.
               // 
               case 116: // Last [t]ab
               //case 84: // Last [T]ab
                  if (ev.shiftKey) {
                     m4_DEBUG('Bug nnnn: Shift-T opens closed details panels');
                  }
                  break;
               /*/ MEH: Fix this: Let user change aerial tiles source.
               case 80: // Cycle through Aerial [P]hotos
                  var idx:int = G.tabs.settings.settings_panel.settings_options
                                 .aerial_layer.selectedIndex;
                  if (idx != -1) {
                     idx += 1;
                     if (idx >=
                           G.tabs.settings.settings_panel.settings_options
                              .aerial_layer.numChildren) {
                        idx = 0;
                     }
                     G.tabs.settings.settings_panel.settings_options
                        .aerial_layer.selectedIndex = idx;
                  }
                  break;
               /*/
               // MAYBE: Control-key-commands to get to popular panels:
               /*/
               // Ctrl-S/G Search/Go-To
               // Ctrl-R Find Bike Route
               // Ctrl-B Find Bike/Transit Route
               // Ctrl-C Find Commute Partners (better name?)
               case 103: // g
               case 71: // G
                  //FIXME: Need to clear keyboard buffer so that the 'g'
                  //       doesn't appear in the text box
                  //UI.goto_popup_open();
                  break;
               // Brainstorming: Seems like we could find something useful
               // for Keyboard.SPACE. Maybe also map Ctrl-Home or something
               // to a user's 'home' location.
               /*/
               default:
                  handled = false;
                  break;
            }
         }
         // Number keys (0 through 9)
         if (!handled) {
            // Map the number keys to zoom as well as aerial photo opacity.
            // Use Ctrl for one and Alt for the other. 0 is 48 and 9 is 57.
            if ((ev.ctrlKey)
                && (ev.charCode >= 49)    // >= '1'
                && (ev.charCode <= 53))   // <= '5'
               {
               // There are 5 levels of opacity so we use Ctrl-1 to -5
               // NOTE: Magic numbers: Valid Alpha are (.2 .4 .6 .8 1.0)
               var alpha:Number = (ev.charCode - 48.0) / 5.0;
               G.tabs.settings.settings_panel.settings_options.block_alpha(
                                                                     alpha);
            }
            else if ((ev.altKey)
                     && (ev.charCode >= 48)
                     && (ev.charCode <= 57)) {
               // Zoom min is 9, Zoom max is 19, so map 0 to min and advance
               // from there.
               // 2013.09.18: The min is now 7... but, whatever.
               // 2013.11.21: The min is now 5... but, whatever.
               var zoom_lvl:int = Conf.zoom_min + ev.charCode - 48;
               m4_ASSERT(zoom_lvl <= Conf.zoom_max);
               this.zoomto(zoom_lvl);
               handled = true;
            }
         }
      }

      //
      protected function on_keydown_dragging(ev:KeyboardEvent) :void
      {
         m4_DEBUG('on_keydown_dragging: ev:', ev);
         var handled:Boolean = true;
         switch (ev.keyCode) {
            case Keyboard.ESCAPE:
            case Keyboard.SPACE:
            case Keyboard.DELETE:      // (keyCode 46, charCode 127)
            case Keyboard.BACKSPACE:   // (keyCode 8, charCode 8)
               var route:Route = (this.selectedset.item_get_random() as Route);
               if (route !== null) {
                  m4_DEBUG('TEST ME: cancel_destination_add');
                  Route_Editor_UI.cancel_destination_add();
               }
               break;
            default:
               handled = false;
               break;
         }
      }

      // *** Helper fcns.

      //
      public function get_geofeature(ev:Event) :Geofeature
      {
         var feat:Geofeature = null;
         var item_sprite:Item_Sprite = (ev.target as Item_Sprite);
         if (item_sprite !== null) {
            feat = (item_sprite.item as Geofeature);
            m4_ASSERT(feat !== null);
            if (feat.is_clickable) {
               // NOTE: It could be null if the Item_Sprite is a Tile.
               // FIXME/Bug nnnn: Terrain is not selectable:
               if (feat is Terrain) {
                  m4_ASSERT_SOFT(false); // feat.is_clickable should be false.
                  m4_DEBUG2('get_geofeature: Bug nnnn: cannot select terrain:',
                            feat);
                  feat = null;
               }
               else {
                  m4_DEBUG('get_geofeature: feat:', feat);
               }
            }
            else {
               m4_DEBUG('get_geofeature: feat: not clickable', feat);
               feat = null;
            }
         }
         else {
            m4_DEBUG('get_geofeature: not Item_Sprite:', ev.target);
         }
         return feat;
      }

      //
      public function get_item_vertex(ev:Event) :Vertex
      {
         var vertex:Vertex = (ev.target as Vertex);
         // If vertex === null, then Geofeature or Tile.
         return vertex;
      }

      protected function on_creation_complete(ev:FlexEvent) :void
      {
         m4_DEBUG('creatn_compl: the map!');
         m4_ASSERT(!this.creation_completed);
         // I expected to find a parent attribute, maybe in UIComponent, that
         // indicates if creation is complete, but I couldn't find one. So we
         // maintain our own. [lb]
         this.creation_completed = true;
         if (this.branch_and_nip_ready) {
            this.add_mouse_listeners();
         }
      }

      // HACK: This gets called when Update_Revision.processed_draw_config
      //       gets set, which means it's okay to listen to mouse events and to
      //       use the tools.
      // HACK: Make sure the config is loaded, else the _Create tools fail.
      // FIXME: Listen to the Update_Revision.processed_draw_config
      //        Boolean?
      public function on_branch_and_nip_received() :void
      {
         if (!this.branch_and_nip_ready) {
            this.branch_and_nip_ready = true;
            if (this.creation_completed) {
               this.add_mouse_listeners();
            }
         }
      }

      // *** Mouse up/down/doubleclick handlers

      // Mouse-down event handler
      public function on_mouse_down(ev:MouseEvent) :void
      {
         // In raster mode, if the click is on the background (i.e., on
         // "nothing"), ev.target is main0.HDividedBox4.map_canvas.map;
         // if you click on a line segment or region (i.e., geofeature),
         // ev.target is [object Item_Sprite].
         m4_VERBOSE('on_mouse_down: target:', ev.target);
         m4_VERBOSE('  >> ev:', ev);
         m4_VERBOSE('  >> X:', ev.stageX, 'Y:', ev.stageY);

         // We only care about double clicks if the user is using the
         // Tool_Pan_Select tool.
         if (!(this.tool_cur.uses_double_click)) {
            this.double_click.detector_reset();
         }

         var could_be_double_click:Boolean = this.double_click.detecting;

         m4_DEBUG2('on_mouse_down: tool:', this.tool_cur,
                   '/ cld_be_dbl_clck:', could_be_double_click);

         // A Vertex is moveable, so if it's clicked, tell it on mouse down.
         // A Geofeature is not moveable -- only its vertices are.
         // BUG nnnn: New Shape Tools; study: new OSM iD editor.
         var vertex:Vertex = this.get_item_vertex(ev);
         if ((vertex !== null)
             && (this.tool_cur.mouse_event_applies_to(vertex))) {
            vertex.on_mouse_down(ev);
         }
         // This is a little hack: Route's are... special, because of
         // Route_Stops.
         var feat:Geofeature = null;
         feat = this.get_geofeature(ev);
         var route:Route = (feat as Route);
         if (route !== null) {
            m4_DEBUG('on_mouse_down: route:', route);
            if (route.is_path_editable()) {


// BUG_FALL_2013: Test editing a route in raster mode -- how does snap-to work?
//                Also do lots lots more route editing testing,
//                and logging on/off w/ routes, etc...
               route.on_mouse_down(ev);
            }
         }

         // Always tell the tool about the event.
         this.tool_cur.on_mouse_down(ev, could_be_double_click);
      }

      //
      public function on_mouse_up(ev:MouseEvent) :void
      {
         m4_VERBOSE('on_mouse_up: target:', ev.target);
         m4_DEBUG('on_mouse_up: tool_cur:', this.tool_cur);
         m4_VERBOSE('  ev:', ev);
         m4_DEBUG('on_mouse_up: stage.focus:', this.stage.focus);

         // If the user was dragging, this event is no longer a double click
         // candidate (we haven't call the tool's on_mouse_up, so it still
         // thinks it's dragging;).
         //
         if (G.map.tool_cur.dragging) {
            this.double_click.detector_reset();
         }
         // But the command might also think the next mouse_move event it gets
         // is okay, so stop that.
         if (G.map.tool_cur.drag_start_valid) {
            G.map.tool_cur.drag_start_valid = false;
         }
         // The tool will reset its dragged_object in its on_mouse_up, which
         // we'll call after we're confident this isn't a double click.
         // BUG nnnn: Double click really is a beast, isn't it?
         //           Maybe add this to the preso of what's what.
         //           PRESO: Why after clicking quick on an item and moving
         //                  your mouse away quickly there's a delay before
         //                  the item is selected -- because we waiting on the
         //                  double click timeout. (This is also something for
         //                  me to evaluate in other people's products going
         //                  forward in life, thinks [lb] -- attention to
         //                  detail.)

         // If this is not a double click event, complete it now
         if ((!this.double_click.detecting)
             || (this.double_click.complete_first_click)) {
            // BUG nnnn: If the user clicks down in the side panel (e.g., on a
            // scroll bar) and then releases the mouse in the map, make sure we
            // don't interpret that as a single click.
            //   E.g., if (mouse_down_detected)
            // BUG nnnn: If user pans map and moves mouse (while still being
            // clicked) over side panel, map stops panning and update is
            // requested.
            this.detector_process_single_click(ev);
            this.double_click.detector_reset();
         }
         else if (this.double_click.complete_double_click) {
            this.detector_process_double_click(ev);
            this.double_click.detector_reset();
         }
      }

      //
      public function detector_process_single_click(ev:MouseEvent) :void
      {
         var processed:Boolean = false;
         m4_DEBUG('detector_process_single_click');

         // FIXME: Delete this:
         // FIXME: I think click() is a no-op. Only found in Map_Tool.as.
         //var modifier_pressed:Boolean = ev.shiftKey || ev.ctrlKey;
         //this.tool_cur.click(ev.stageX, ev.stageY, modifier_pressed);
         // Always tell the tool about the event.
         // NOTE Don't use ||=, as we always want the fcn. to run.
         processed = this.tool_cur.on_mouse_up(ev, processed) || processed;

         // EXPLAIN: Is this comment accurate?:
         // If the user was node-building, change them to pan-selecting, so
         // they can start editing their node.
         if (this.tool_cur is Tool_Node_Endpoint_Build) {
            this.tool_choose('tools_pan');
         }
      }

      //
      public function detector_process_double_click(ev:MouseEvent) :void
      {
         var processed:Boolean = false;
         var feat:Geofeature = null;
         // Tell the item, if there's an item
         var vertex:Vertex = this.get_item_vertex(ev);
         if ((vertex !== null)
             && (this.tool_cur.mouse_event_applies_to(vertex))) {
            ev.ctrlKey = false;
            processed = vertex.on_mouse_doubleclick(ev, processed);
            m4_DEBUG('detector_process_double_click: vertex:', processed);
         }
         else {
            feat = this.get_geofeature(ev);
            if ((feat !== null)
                && (this.tool_cur.mouse_event_applies_to(feat))) {
               // EXPLAIN Why are we disabling ctrlKey?
               ev.ctrlKey = false;
               // Send a double click to the feat: in the case of byways,
               // you'll see the byway get selected and then you'll see
               // the byway enter lock-down mode.
               processed = feat.on_mouse_doubleclick(ev, processed);
               //processed = true;
               m4_DEBUG('detector_process_double_click: geofeature:', feat);
            }
            // else, it's just the map.
         }

         this.tool_cur.on_mouse_doubleclick_cleanup();

         // FIXME: Does this belong in Tool_Pan_Select? Hrm...
         // If the vertex or feat didn't handle double click, zoom in or out.
         if (!processed) {
            m4_DEBUG('detector_process_double_click: recenter maybe zoom');
            this.recenter(ev.stageX, ev.stageY);


// BUG_FALL_2013: THIS BEHAVIOUR IS WEIRD... or maybe it's brilliant.
//                 ug, revisit this...
            // CcpV2: This behavior is new. If nothing is selected,
            //        double-click zooms in.
            //        But only if nothing is selected...
            // A route can be selected and not be a part of the selectset.
            if ((!(feat is Route)) && (this.selectedset.length == 0)) {
               var zoom_step:int = (!ev.shiftKey) ? 1 : -1;
               this.zoom_in(zoom_step);
            }
         }
      }

      public function detector_process_timeout(ev1:MouseEvent=null,
                                               ev2:MouseEvent=null)
                                                :void
      {
         m4_DEBUG('detector_process_timeout')

         // Either user clicked once and is holding mouse down, or user
         // clicked twice and is holding mouse down (FIXME: what about
         // thrice down?), so ignore the select and turn into pan.
         // FIXME: In future, what about selecting item and starting drag
         //        on it?
         /*/
         if (!G.map.tool_cur.dragging) {
            //G.map.tracking_mouse = true;
            //this.tool_cur.dragging = false;
            // Tell the map to start panning.
            //this.tool_cur.drag_start_valid = true;
         }
         /*/


// BUG_FALL_2013: TEST_ME: How does dbl-click interact w/ route_stop? vertex?

         this.double_click.detector_reset();
      }

      // *** Mouse move/out/over/scroll handlers

      // Mouse-move event handler.
      public function on_mouse_move(ev:MouseEvent) :void
      {
         m4_VERBOSE2('on_mouse_move: tool:', this.tool_cur,
                     '/ X:', ev.stageX, 'Y:', ev.stageY);

         // NOTE: Each Route also listens on mouse move, so we have to be
         //       careful not to step on each other's toes, or, both react
         //       to the same event differently.
         this.tool_cur.on_mouse_move(ev.stageX, ev.stageY);
      }

      //
      public function on_mouse_out(ev:MouseEvent) :void
      {
         m4_VERBOSE2('on_mouse_out', ev.target,
                     '/ cur & rel:', ev.currentTarget, ev.relatedObject);
         UI.cursor_set_native_arrow();
         // If we're in a drag, fake a mouse-up event. Mouse-ups which occur
         // outside the application window will be lost entirely, so it is
         // better that they always happen even if at an awkward time.
         // FIXME: landonb is curious about this...
         if (this.tool_cur.dragging) {
            this.on_mouse_up(ev);
         }
      }

      //
      public function on_mouse_over(ev:MouseEvent) :void
      {
         m4_DEBUG2('on_mouse_over', ev.target,
                     '/ cur & rel:', ev.currentTarget, ev.relatedObject);
         this.tool_cur.cursor_set();
      }

      //
      public function on_mouse_wheel(ev:MouseEvent) :void
      {
         m4_VERBOSE('on_mouse_wheel: target:', ev.target);
         m4_VERBOSE('on_mouse_wheel: ev:', ev);
         const lock_out_time:Number = 250;
         const repeat_count:int = 1;
         if (this.mouse_wheel_timer === null) {
            this.mouse_wheel_timer = new Timer(lock_out_time, repeat_count);
            this.mouse_wheel_timer.addEventListener(
               TimerEvent.TIMER, this.on_mouse_wheel_timer);
            this.mouse_wheel_timer.start();
         }
         else if (this.mouse_wheel_count == 2) {
            // Make user do two wheelies, just to not be so sensitive
            if (ev.delta > 0) {
               this.zoom_in(1);
            }
            else if (ev.delta < 0) {
               this.zoom_in(-1);
            }
         }
         // else, still waiting on timer
         this.mouse_wheel_count += 1;
      }

      //
      public function on_mouse_wheel_timer(ev:TimerEvent) :void
      {
         this.mouse_wheel_count = 0;
         this.mouse_wheel_timer = null;
      }

      // *** Protected instance methods

      //
      protected function add_mouse_listeners() :void
      {
         G.app.map_mousecatcher.listeners_register();

         // 2013.06.08: [lb] reduced the number of active mouse listeners. Now
         // it's just the double click detective and the map canvas, which in
         // turn tells Geofeatures and Vertexices when they're moused.
         // BUG nnnn: The zoombar also has a mouse listener, but it sometimes
         //           interferes. E.g., click map, pan, and drag mouse across
         //           zoom bar; the pan operation terminates.
         const mouse_rank_double_click:int = 2;
         const mouse_rank_map_canvas:int = 1;

         // Double clicks are specially handled by a custom class, since Flex
         // doesn't have a robust Double Click mechanism.
         this.double_click = new Double_Click_Detector(
               this.detector_process_single_click,
               this.detector_process_double_click,
               this.detector_process_timeout,
               Conf.double_click_time);
         // The double click detective always goes first.
         this.double_click.init_listeners(this, mouse_rank_double_click);

         // Add the other mouse events.
         const useCapture:Boolean = false; // the default
         // var useWeakReference:Boolean = false; // the default
         // mouse_down and mouse_up get the event after double click detective.
         this.addEventListener(MouseEvent.MOUSE_DOWN,
                               this.on_mouse_down,
                               useCapture,
                               mouse_rank_map_canvas);
         this.addEventListener(MouseEvent.MOUSE_UP,
                               this.on_mouse_up,
                               useCapture,
                               mouse_rank_map_canvas);
         this.addEventListener(MouseEvent.MOUSE_MOVE, this.on_mouse_move);
         this.addEventListener(MouseEvent.MOUSE_WHEEL, this.on_mouse_wheel);
         this.addEventListener(MouseEvent.MOUSE_OUT,
                               UI.mouseoutover_wrap(this, this.on_mouse_out));
         this.addEventListener(MouseEvent.MOUSE_OVER,
                               UI.mouseoutover_wrap(this, this.on_mouse_over));
      }

   }
}


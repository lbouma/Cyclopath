/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// NOTE x and y args to the mouse* methods are global (stage) coordinates.

// NOTE If the tool sees a mouse event, this means that no Geofeature that was
//      interested in such an event was at the cursor's location.

package views.map_widgets.tools {

   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.geom.Point;
   import flash.utils.Timer;
   import mx.events.FlexEvent;

   import items.Item_Base;
   import items.Item_User_Access;
   import utils.misc.Draggable;
   import utils.geom.Geometry;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import views.base.App_Action;
   import views.base.Map_Canvas;
   import views.base.Map_Canvas_Base;
   import views.base.UI;

   public class Map_Tool {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Map_Tool');

      // *** Instance variables

      // [lb] isn't sure why this class has it's own reference to the map when
      // everyone else just seems to use G.map. But please note that I do
      // appreciate that this class isn't just using the global reference,
      // because that, in theory, makes this class reusable.
      protected var map:Map_Canvas;

      // Cursor stuff
      protected var use_finger_cursor:Object = true;

      // According to the New Item Policy, user must have permissions to use
      // this tool.
      //protected var user_has_permissions_:Boolean = false;
      protected var user_has_permissions_:Boolean = true;

      // *** Attributes controlling drag behavior.

      // This is the Geofeature, Vertex, or Route_Stop being dragged.
      // Search: implements Draggable.
      public var dragged_object:Draggable;

      // The dragging member is hot when the user is dragging a Vertex or
      // panning the map. But be aware, this doesn't happen after the first
      // mouse move after a mouse down; we also check that the user wasn't not
      // trying to drag or pan.
      // BUG nnnn: You can also drag new items when they're first created, if
      //           you hold the mouse down and move it around before mousing
      //           up. But [lb] finds this behaviour unnatural. See other
      //           BUG nnnns re: mimicking OSM's new iD editor's behaviour.
      //           So dragging applies: Vertex, Pan, Region/Byway/Point_Create
      public var dragging:Boolean;

      // This is true after a mouse down, and false in mouse up. It's set
      // before the mouse has moved beyond the grace pixel threshold to let us
      // know that we are in the process of figuring out if the new mousing
      // stimuli is meant as a drag/pan or not.
      public var drag_start_valid:Boolean;

      // 2013.06.08: Dragging has not been very responsive because we've been
      //   calling this.drag() too frequently. The drag operations are costly
      //   because they make Command objects and run their do_() fcns, and most
      //   Commands have high overhead. Since we can get mouse moves events
      //   every application frame, making Commands every time can make
      //   dragging seem very "jerky" and unresponsive (or slow to respond) to
      //   the user. So wait a few msecs. between drag handling.
      protected var delayed_drag_timer:Timer;
      // FIXME: What's a good timeout?
      protected const drag_wait:int = 21;

      // The number of pixels you can accidentally "shake" the mouse while
      // trying to place a Vertex and we won't reset the drag timer, so the
      // timer continues to countdown and soon fires and a drag event happens.
      // This is because a user will place a Vertex while still holding the
      // mouse down, but sometimes it's hard not to jiggle the mouse.
      protected const shaky_pixels:Number = 6;

      // [lb] is being very Python. All these :*'s are just Numbers, but
      // sometimes they want to be null (like when we're not dragging);
      protected var drag_drag_x:* = null;
      protected var drag_drag_y:* = null;
      //
      protected var drag_orig_x:* = null;
      protected var drag_orig_y:* = null;

      protected var drag_last_x:* = null;
      protected var drag_last_y:* = null;

      public var items_down_under:Array = null;

      // *** Constructor

      public function Map_Tool(map:Map_Canvas_Base)
      {
         this.map = (map as Map_Canvas);
         m4_ASSERT(this.map !== null);
         this.dragged_object = null;
         this.dragging = false;
         this.drag_start_valid = false;
      }

      // *** Instance methods

      // Called when the tool first becomes active
      public function activate() :void
      {
         // nothing in base class
      }

      // Called when tool becomes inactive
      public function deactivate() :void
      {
         // BUG_JUL_2014: MAJOR BUG: [lb] dragged vertex to connect it to
         // a byway endpoint clusted, saved the map, then tried to route,
         // and an infinite callback loop ensued...
         m4_DEBUG('deactivate: dragged_object=null / dragging=false');
         this.dragged_object = null;
         this.dragging = false;
         this.drag_start_valid = false;
      }

      // Set the cursor as appropriate for this tool.
      // NOTE There used to be custom cursors for some of the special tools,
      //      but custom cursors in Flash move jerkily because they are drawn
      //      at the end of every update cycle. Fortunately, Flash has two
      //      built-in native cursors -- the arrow pointer and the finger
      //      pointer. We use the arrow for Pan/Select and the Finger for
      //      everything else to help the user understand when they're using a
      //      special tool and when they're not.
      public function cursor_set() :void
      {
         if (!this.use_finger_cursor) {
            m4_TALKY('cursor_set: set finger off');
            UI.cursor_set_native_arrow(); // no special cursor for this tool
         }
         else {
            m4_TALKY('cursor_set: set finger on');
            UI.cursor_set_native_finger();
         }
      }

      //
      protected function do_delayed_drag(ev:TimerEvent=null,
                                         x:*=null,
                                         y:*=null)
         :void
      {
         m4_TALKY('do_delayed_drag:', ev);

         if (ev !== null) {
            m4_ASSERT((x === null) && (y === null));
            m4_ASSERT((this.drag_drag_x !== null)
                      && (this.drag_drag_y !== null));
            x = this.drag_drag_x;
            y = this.drag_drag_y;
         }
         m4_ASSERT((x !== null) && (y !== null));

         if (this.delayed_drag_timer !== null) {
            if (this.delayed_drag_timer.running) {
               this.delayed_drag_timer.stop();
            }
            this.delayed_drag_timer.reset();
         }

         m4_ASSERT((this.drag_last_x !== null)
                   && (this.drag_last_y !== null));

         m4_TALKY('do_delayed_drag: dragging/finished: calling this.drag');
         this.drag(this.drag_last_x, this.drag_last_y, x, y);
         this.drag_last_x = x;
         this.drag_last_y = y;
         this.drag_drag_x = null;
         this.drag_drag_y = null;
      }

      //
      public function drag(x_old:Number, y_old:Number,
                           x_new:Number, y_new:Number) :void
      {
         // nothing in base class
      }

      //
      protected function drag_timer_reset(x:Number, y:Number) :void
      {
         // Stop the timer, maybe, and restart the timer.
         if (this.delayed_drag_timer === null) {
            var repeat_count:int = 1;
            m4_TALKY('drag_timer_reset: do_delayed_drag: new Timer');
            this.delayed_drag_timer = new Timer(this.drag_wait, repeat_count);
            this.delayed_drag_timer.addEventListener(TimerEvent.TIMER,
                                                     this.do_delayed_drag,
                                                     false, 0, true);
         }
         else if (this.delayed_drag_timer.running) {
            m4_VERBOSE('drag_timer_reset: reset Timer');
            this.delayed_drag_timer.stop();
            this.delayed_drag_timer.reset();
         }
         else {
            m4_TALKY('drag_timer_reset: start Timer');
         }
         this.drag_drag_x = x;
         this.drag_drag_y = y;
         this.delayed_drag_timer.start();
      }

      //
      protected function force_drag_now(x:Number, y:Number) :void
      {
         m4_TALKY3('force_drag_now: do_delayed_drag: delayed_drag_timer:',
                   (this.delayed_drag_timer !== null)
                   ? this.delayed_drag_timer.running : 'null');

         if ((this.delayed_drag_timer !== null)
             && (this.delayed_drag_timer.running)) {
            this.do_delayed_drag(null, x, y);
         }
      }

      //
      public function mouse_event_applies_to(target_:Object) :Boolean
      {
         return false;
      }

      //
      public function get tool_is_advanced() :Boolean
      {
         m4_ASSERT(false); // abstract.
         return false;
      }

      //
      public function set tool_is_advanced(tia:Boolean) :void
      {
         m4_ASSERT(false); // n/a.
      }

      //
      public function get tool_name() :String
      {
         m4_ASSERT(false); // abstract.
         return null;
      }

      //
      public function set tool_name(tname:String) :void
      {
         m4_ASSERT(false); // n/a.
      }

      // Whether or not this tool can be used given the current map state
      // and the user's permissions. Similar purpose as a command's
      // performable() method.
      public function get useable() :Boolean
      {
         return (
            (this.map.rev_workcopy !== null)
            && (G.app.mode.is_allowed(App_Action.item_edit))
            //&& (G.map.rmode == Conf.map_mode_normal)
            && (this.user_has_permissions_)
            );
      }

      //
      public function get user_has_permissions() :Boolean
      {
         return this.user_has_permissions_;
      }

      //
      public function set user_has_permissions(has:Boolean) :void
      {
         m4_TALKY('user_has_permissions:', has, '/', this);
         this.user_has_permissions_ = has;
         /*/
         // FIXME: Implement? Or does 'useable' do what we want?
         if (has) {
         }
         else {
         }
         /*/
      }

      // Most tools do not support double click, so this fcn. returns false.
      // Tools that do support the deuce will override this and return true.
      public function get uses_double_click() :Boolean
      {
         return false;
      }

      // Some tools and mouse reactions select or deselect items. If a tool or
      // mouse action selects an item, and a later tool or mouse listener
      // should make sure not to deselect said item, this property should be
      // set to true. Note that this setting effectively gets reset on mouse
      // down, and it remains in effect until mouse up or until the tool is
      // done working. (But note that after the real mouse up, the double
      // click detector might be running, so this setting remains until the
      // mouse event is really finally handled, which might be some tens or
      // hundreds of milliseconds after the mouse up, and possibly after a
      // second mouse down. Mouses are complicated, it's true.)

      //
      public function get void_next_clear() :Boolean
      {
         return false;
      }

      //
      public function set void_next_clear(void_it:Boolean) :void
      {
         m4_TALKY('ignoring void_next_clear: void_it:', void_it);
         // No-op.
      }

      // *** Double click detector mouse handlers

      //
      public function on_mouse_down(ev:MouseEvent,
                                    could_be_double_click:Boolean)
                                       :void
      {
         m4_TALKY3('on_mouse_down: this:', this, '/ target:', ev.target,
                   '/ could_be_double_click:', could_be_double_click,
                   '/ useable:', this.useable, '/ dragging=f');

         this.dragging = false;
         this.drag_start_valid = true;

         //this.drag_drag_x
         //this.drag_drag_x
         this.drag_orig_x = ev.stageX;
         this.drag_orig_y = ev.stageY;
         this.drag_last_x = this.drag_orig_x;
         this.drag_last_y = this.drag_orig_y;

         // Note re: getObjectsUnderPoint. In CcpV1, we would have called it
         // now to figure out what item is being clicked, and we would have
         // used G.app.map_canvas. But for whatever reason, here, and in the
         // not-a-double-click timeout handler, getObjectsUnderPoint only
         // returns one item, the top-most item. But using stage or G.app
         // gives us many more hit objects. However, there's one less item
         // in the list here than in the double-click timeout.
         //  Returns just the top-most item:
         //   results = G.app.map_canvas.getObjectsUnderPoint(stage_pt);
         //   results = G.app.map_canvas_print.getObjectsUnderPoint(stage_pt);
         //   results = G.app.map.getObjectsUnderPoint(stage_pt);
         var stage_pt:Point = new Point(ev.stageX, ev.stageY);
         // 'TEVS: this.items_down_under is not used...
         this.items_down_under = G.app.getObjectsUnderPoint(stage_pt);
         m4_DEBUG2('on_mouse_down: no. under mouse: app:',
                   this.items_down_under.length);
      }

      // Overriders should call super() _after_ they do their thing.
      public function on_mouse_up(ev:MouseEvent, processed:Boolean) :Boolean
      {
         m4_TALKY2('on_mouse_up: this:', this, '/ processed:', processed,
                   '/ useable:', this.useable, '/ dragging=f');

         // BUG nnnn: CcpV1 doesn't record final vertex?
         //           Or do we get the last mouse move?
         this.force_drag_now(ev.stageX, ev.stageY);

         this.dragging = false;
         this.drag_start_valid = false;

         if (this.useable) {
            m4_TALKY('on_mouse_up: G.map.tool_cur.dragged_object=null');
            this.dragged_object = null;
            // FIXME: Care about if processed or not?
            this.map.cm.done();
         }

         // Can we do this? So we know if we try to use stale values.
         this.drag_drag_x = null;
         this.drag_drag_x = null;
         this.drag_orig_x = null;
         this.drag_orig_y = null;
         this.drag_last_x = null;
         this.drag_last_y = null;

         return processed;
      }

      //
      public function on_mouse_doubleclick_cleanup() :void
      {
         m4_TALKY('on_mouse_doubleclick_cleanup: this:', this, '/ dragging=f');
         // Reset things, just like in on_mouse_up
         this.dragging = false;
         this.drag_start_valid = false;
      }

      //
      public function on_mouse_move(x:Number, y:Number) :void
      {
         m4_VERBOSE2('on_mouse_move: drag_start_valid:', this.drag_start_valid,
                     '/ dragging:', this.dragging, '/ x:', x, '/ y:', y);

         // Check that the mouse click didn't happen outside the map,
         // or that we're already dragging.
         // The fcn., on_mouse_down, sets drag_start_valid.
         if (this.drag_start_valid || this.dragging) {

            // If the drag hasn't progressed beyond the click grace region,
            // don't drag.
            //   var can_drag:Boolean = true;
            //   if (Geometry.distance(x, y, this.drag_last_x,
            //                               this.drag_last_y)
            //       < this.grace_pixels) { // 13 pixels? Hrmmm
            //      can_drag = false;
            //   }
            // 2013.06.08: We're using a timeout instead -- it makes more sense
            // to let the user drag and drag and drag and soak before making an
            // undo/redo command.

            m4_VERBOSE('drag: this.dragged_object:', this.dragged_object);

            // The drag has officially started, so set drag_start_valid false.
            this.drag_start_valid = false;

            var reset_drag_timer:Boolean = false;
            // Wait for the timeout or on_mouse_up to call drag:
            //   this.drag(this.drag_last_x, this.drag_last_y, x, y);
            // so (re)set the timer instead. See: do_delayed_drag.
            // But only reset the timer if the user dragged more than a few
            // pixels, in case someone has shaky hands.
            if ((this.delayed_drag_timer === null)
                || (!(this.delayed_drag_timer.running))) {
               m4_TALKY('on_mouse_move: drag timer is not running');
               reset_drag_timer = true;
            }
            else if (Geometry.distance(x, y, this.drag_last_x,
                                             this.drag_last_y)
                     > this.shaky_pixels) { // 6 pixels? Hrmmm
               m4_VERBOSE('on_mouse_move: drag was large; resetting timer');
               reset_drag_timer = true;
            }
            else {
               // else, user didn't drag very far, so let the timer expire.
               m4_TALKY('on_mouse_move: drag was small; expiring timer');
            }

            // But not so fast. If this is the first drag, we should do
            // something. Otherwise, e.g., if you click a geofeature but
            // move the mouse away, the item won't be selected. Weird, right?
            if (!this.dragging) {
               // This is the first mouse move since mouse down. The user
               // moused down on a Vertex, which is immediately moveable.
               // (The other clickeable thing, a Geofeature, doesn't actually
               // get the click on mouse down or mouse move --
               // 1. If the user clicks and releases quick on a Geofeature,
               //    even if they mouse move a little, we only want to treat
               //    that as a Geofeature select.
               // 2. If the user clicks on a Geofeature but starts mouse
               //    moving, this means they don't want to select the item but
               //    rather want to pan the map. So pan the map and ignore the
               //    clicked-on Geofeature.
               // 3. is this function. The user clicked a Vertex and started
               //    mouse moving. This is not a map pan, nor an item select,
               //    and we won't have to wait to start getting busy. (Though
               //    we don't get busy every mouse move -- we get almost all
               //    of the mouse moves, but we only want to update the screen
               //    when (a) the mouse dragged the Vertex pretty far, or (b)
               //    after a certain timeout; both (a) and (b) make for a more
               //    fluid user interteraction.
               m4_TALKY('on_mouse_move: do_delayed_drag: dragging=t');
               this.dragging = true;
               // Now we know for sure this is not a double click.
               this.map.double_click.detector_reset();
               // Force a this.drag.
               this.do_delayed_drag(null, x, y);
               // Don't set the timer for the first move; or for 2d + subseq.
            }
            else if (reset_drag_timer) {
               this.drag_timer_reset(x, y);
            }
         }

         //m4_VERBOSE('on_mouse_move: this.dragging:', this.dragging);
      }

      // *** Instance methods

      // Derived classes use this fcn. to check if the items that are selected
      // are of the specified type, item_class, and that the item has edit
      // access or better to each of the selected items.
      protected function useable_check_type(item_class:Class) :Boolean
      {
         var is_useable:Boolean = false;
         var item:Item_User_Access;
         var has_perms:Boolean = true;

         // Tools that use this function operate on existing items -- not new
         // items -- so there's gotta be something selected to continue.
         if (this.map.selectedset.length > 0) {
            // Check that items of the specific type are selected.
            item = this.map.selectedset.item_get_random() as Item_User_Access;
            m4_VERBOSE('derives_from in Map_Tool', item, item_class);
            m4_VERBOSE6('useable: looking for:', item_class,
                        '/ found type:', Item_Base.item_get_type(item),
                        '/ a.k.a. class:', Item_Base.item_get_class(item),
                        '/ derives_from:',
                           Introspect.derives_from(item, item_class),
                        '/ no. selected:', this.map.selectedset.length);
            // If the type matches and is drawn at the current zoom level,
            // make sure the user can edit _each one_
            if ((item !== null)
                && (Introspect.derives_from(item, item_class))
                && (item.editable_at_current_zoom)) {
               // Check each selected item
               for each (item in this.map.selectedset) {
                  m4_ASSERT(item !== null);
                  m4_VERBOSE('  perms?:', has_perms, '/ item:', item);
                  if (!item.can_edit) {
                     m4_VERBOSE('  denied!');
                     has_perms = false;
                     break;
                  }
               }
               is_useable = has_perms;
            }
         }
         m4_TALKY('useable_check_type: is_useable:', is_useable);
         return is_useable;
      }

   }
}


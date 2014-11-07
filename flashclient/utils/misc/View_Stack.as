/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   /**
    * Handles maintaining a stack of views up to a configurable limit.
    * Provides the ability to walk along the stack, allowing forward and
    * back functionality.
    */
   public class View_Stack {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('View_Stack');

      // *** Object attributes

      protected var back_stack:Stack;
      protected var forward_stack:Stack;

      // time of last call to on_view_change
      protected var last_view_change_ms:int;
      protected var lock_stacks:Boolean;

      // *** Constructor

      //
      public function View_Stack()
      {
         this.back_stack = new Stack(Conf.view_stack_depth);
         this.forward_stack = new Stack(Conf.view_stack_depth);
         this.lock_stacks = false;
      }

      // *** Getters/setters

      //
      public function get forward_available() :Boolean
      {
         return (!this.forward_stack.is_empty());
      }

      //
      public function get backward_available() :Boolean
      {
         return (!this.back_stack.is_empty());
      }

      // *** Other methods

      //
      public function back() :void
      {
         var last_view:View_Port = back_stack.pop() as View_Port;
         var curr_view:View_Port = null;

         if (last_view !== null) {
            // save the current view port onto the forward stack
            curr_view = new View_Port();
            curr_view.map_cx = G.map.view_rect.map_center_x;
            curr_view.map_cy = G.map.view_rect.map_center_y;
            curr_view.map_zoom = G.map.zoom_level;
            this.forward_stack.push(curr_view);

            // show the view popped off of the back stack
            this.lock_stacks = true;
            this.view_port_show(last_view);
            this.lock_stacks = false;
         }

         this.buttons_update();
      }

      //
      protected function buttons_update() :void
      {
         /*/
         G.app.view_back.enabled = this.backward_available;
         G.app.view_forward.enabled = this.forward_available;
         /*/
      }

      //
      public function forward() :void
      {
         var last_view:View_Port = forward_stack.pop() as View_Port;
         var curr_view:View_Port = null;

         if (last_view !== null) {
            // save the current view port onto the back stack
            curr_view = new View_Port();
            curr_view.map_cx = G.map.view_rect.map_center_x;
            curr_view.map_cy = G.map.view_rect.map_center_y;
            curr_view.map_zoom = G.map.zoom_level;
            this.back_stack.push(curr_view);

            // show the view popped off of the forward stack
            this.lock_stacks = true;
            this.view_port_show(last_view);
            this.lock_stacks = false;
         }

         this.buttons_update();
      }

      // called by system components when moving the viewport.
      // arguments are map coordinates and zoom level of OLD viewport.
      public function on_view_change(mx:Number, my:Number, zoom:int) :Boolean
      {
         //m4_DEBUG2('on_view_change: zoom:', zoom,
         //          '/ mx:', mx, '/ my:', my);
         //m4_DEBUG3('on_view_change: G.map.zoom_level:', G.map.zoom_level,
         //          '/ map_center_x:', G.map.view_rect.map_center_x,
         //          '/ map_center_y:', G.map.view_rect.map_center_y);

         var last_view:View_Port = back_stack.peek() as View_Port;
         var new_view:View_Port = null;

         var changed_view:Boolean = true;

         if (this.lock_stacks) {
            //m4_DEBUG('on_view_change: short-circuit: lock_stacks');
            changed_view = false;
         }

         // Only update the view stack if the view port change has been
         // enough, that being (a) changed zoom level or large enough pan and
         // also (b) enough elapsed time in the viewport.
         if ((changed_view)
             && ((last_view === null)
                 || zoom != last_view.map_zoom
                 || (G.map.xform_xdelta_map2cv(mx - last_view.map_cx)
                     >= Conf.view_stack_pan_min)
                 || (G.map.xform_ydelta_map2cv(my - last_view.map_cy)
                     >= Conf.view_stack_pan_min))) {

            // check if enough time has passed since last major view change
            if ((G.now() - this.last_view_change_ms)
                >= Conf.view_stack_delay) {

               new_view = new View_Port();

               new_view.map_cx = mx;
               new_view.map_cy = my;
               new_view.map_zoom = zoom;

               m4_DEBUG2('on_view_change: / zoom:', zoom,
                         '/ mx:', mx, '/ my:', my);

               this.back_stack.push(new_view);
               this.forward_stack.clear();

               this.buttons_update();

               m4_ASSERT(changed_view);
            }

            // update time here so that really small pans don't reset
            // the last_view_change counter.
            this.last_view_change_ms = G.now();
         }

         return changed_view;
      }

      // After the user clicks the back or forward button, pan and zoom the
      // map.
      protected function view_port_show(view:View_Port) :void
      {
         /*
         G.map.panto(G.map.xform_x_map2cv(view.map_cx),
                     G.map.xform_y_map2cv(view.map_cy));
         G.map.zoomto(view.map_zoom);
         // Hack to fix bug 1307. See also a similar hack in Map_Canvas. For a
         // better proposed solution, see bug 1340.
         // FIXME [aa] Read those Bugs
         if (G.map.zoom_level_previous == G.map.zoom_level)
            G.map.update_viewport_items();
         */
         G.map.pan_and_zoomto(G.map.xform_x_map2cv(view.map_cx),
                              G.map.xform_y_map2cv(view.map_cy),
                              view.map_zoom);
      }

   }
}

// *** View_Port class

// This class is only used by the View_Stack class, which is why we can get
// away with declaring this class outside of the package { }.

class View_Port
{
   public var map_cx:int;
   public var map_cy:int;
   public var map_zoom:int;
}


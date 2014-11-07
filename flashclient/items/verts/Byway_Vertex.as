/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.verts {

   import flash.events.MouseEvent;
   import flash.geom.Point;

   import items.Geofeature;
   import items.feats.Byway;
   import utils.misc.Logging;
   import views.commands.Byway_Split;
   import views.commands.Byway_Vertex_Move;
   import views.commands.Command_Base;
   import views.map_widgets.Bubble_Node;
   import views.map_widgets.tools.Tool_Byway_Split;

   public class Byway_Vertex extends Vertex {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Byway_Vertex');

      // *** Instance variables

      // adjustments added to the "real" (x,y) to created the snapped (x,y)
      protected var snap_adjust_x:Number;
      protected var snap_adjust_y:Number;

      // other vertices which should be dragged along with me.
      protected var drag_buddy_parents:Array;
      protected var drag_buddy_indices:Array;

      // *** Constructor

      public function Byway_Vertex(index:int, parent:Byway)
      {
         super(index, parent);

         this.snap_adjust_x = 0;
         this.snap_adjust_y = 0;
      }

      // *** Event listeners

      //
      protected function on_byway_split_done(cmd:Command_Base) :void
      {
         m4_DEBUG('on_byway_split_done: this:', this);
         // NOTE: previously, the lines within switch_to_pan were
         // here, and were used to make the Byway_Split tool a one-use
         // tool. However, see Bug 1598 for details on how this caused
         // problems. Using callLater prevents this problem while
         // maintaining the same end user experience.
         m4_DEBUG_CLLL('>callLater: this.switch_to_pan');
         G.map.callLater(G.map.switch_to_pan);
      }

      //
      protected function on_byway_split_fail(cmd:Command_Base) :void
      {
         m4_WARNING('on_byway_split_fail: this:', this);
      }

      //
      override public function on_mouse_down(ev:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_down: target:', ev.target);
         super.on_mouse_down(ev);
         this.drag_start();
      }

      //
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         //m4_DEBUG('on_mouse_up: target:', ev.target);

         m4_ASSERT(!processed);
         processed = super.on_mouse_up(ev, processed);
         m4_ASSERT(processed);

         // This is a little coupled: see if the active tool is the splitter.
         if (G.map.tool_is_active(Tool_Byway_Split)
             && (!this.is_endpoint)) {

            var cmd:Byway_Split;
            var skip_panel:Boolean = false;
            cmd = new Byway_Split(this.parent_, this.coord_index, skip_panel);
            // The byway being split might have never been selected by the
            // user and therefore might not have its link_values and whatnot
            // lazy-loaded. So we need to use callbacks.
            // Not true: split works only on selected bwys: so always hydrated.
            //  (or maybe they're still hydrating???)
            G.map.cm.do_(cmd, this.on_byway_split_done,
                              this.on_byway_split_fail);
            m4_DEBUG('on_mouse_up: cmd.is_prepared:', cmd.is_prepared);

            // 2013.06.29: In CcpV1, the tool automatically changes back to the
            // pan tool. [lb] doesn't really like the tool to change once used,
            // but the other tools behave similarly, and, anyway, at present,
            // after adding the byway vertex, if we don't switch back to the
            // pan-select tool, the user cannot drag the new vertex, which
            // seems weird.
            G.map.callLater(G.map.switch_to_pan);
         }

         this.drag_buddy_parents = null;
         this.drag_buddy_indices = null;

         return processed;
      }

      // *** Instance methods

      //
      override public function drag(xdelta:Number, ydelta:Number) :void
      {
         var x_real_old:Number;
         var y_real_old:Number;
         var x_real_new:Number;
         var y_real_new:Number;
         var snap_new:Point;
         var bn:Bubble_Node;

// BUG_FALL_2013
// FIXME: Something is broken or not working as expected...
// If you split a byway, join the splits, split again, then try to move the
// first split's leftover vertex, it says it's not selected
         if (!this.selected) {
            m4_WARNING('drag: not selected:', this, '/', this.parent_);
         }
//         m4_ASSERT(this.selected);

         this.deselect_needed = false;

         // If we are start/end vertex, snap & record snap vector
         if (this.is_endpoint) {
            x_real_old = this.x_cv - this.snap_adjust_x;
            y_real_old = this.y_cv - this.snap_adjust_y;
            x_real_new = x_real_old + xdelta;
            y_real_new = y_real_old + ydelta;
            if (this.coord_index == 0) {
               bn = G.map.bubble_nodes[(this.parent_ as Byway).beg_node_id];
            }
            else {
               bn = G.map.bubble_nodes[(this.parent_ as Byway).fin_node_id];
            }
            // If we're a sticky intersection, don't snap. See Issue 973.
            // In brief, snapping is awkward and unneeded when moving a
            // fully formed intersection around
            if ((G.tabs.settings.sticky_intersections)
                && (this.drag_buddy_parents.length > 1)) {
               snap_new = new Point(x_real_new, y_real_new);
            }
            else {
               m4_TALKY('drag: looking for snap');
               snap_new = G.map.snap_byway(x_real_new, y_real_new,
                                           Conf.byway_snap_radius, bn,
                                           this.drag_buddy_parents);
            }
            xdelta = snap_new.x - this.x_cv;
            ydelta = snap_new.y - this.y_cv;
            this.snap_adjust_x = snap_new.x - x_real_new;
            this.snap_adjust_y = snap_new.y - y_real_new;
         }

         // This cmd. is throttled to you by: delayed_drag_timer.
         m4_DEBUG('drag: new Byway_Vertex_Move');
         var cmd:Byway_Vertex_Move;
         cmd = new Byway_Vertex_Move(this.drag_buddy_parents,
                                     this.drag_buddy_indices,
                                     xdelta,
                                     ydelta);
         G.map.cm.do_(cmd);
         // The Byway_Vertex_Move command doesn't hydrate/lazy-load items,
         // so is_prepared is always non-null.
         m4_ASSERT_SOFT(cmd.is_prepared !== null);
      }

      //
      override public function drag_start() :void
      {
         var i:int;
         var j:int;
         var node_id:int;
         var ride_i:int;
         var ride_is:Array;
         var parent:Geofeature;
         var neighbor:Byway;

         this.drag_buddy_parents = Vertex.selected_parents;
         this.drag_buddy_indices = Vertex.selected_coord_indices;

         // If we are the start or end vertex, dragging should also move
         // adjacent unselected start/end vertices if either (a) the other
         // byway is selected or (b) the sticky intersections checkbox it
         // ticked. (Selected vertices are already brought along.)
         for (i = 0; i < this.drag_buddy_parents.length; i++) {
            parent = this.drag_buddy_parents[i];
            j = this.drag_buddy_indices[i];
            if (j == 0) {
               node_id = (parent as Byway).beg_node_id;
            }
            else if (j == parent.xs.length - 1) {
               node_id = (parent as Byway).fin_node_id;
            }
            else {
               continue;  // not a start/end vertex
            }
            for each (neighbor in G.map.nodes_adjacent[node_id]) {
               if (neighbor.selected || G.tabs.settings.sticky_intersections) {
                  ride_is = new Array();
                  // these are both true if neighbor is a loop
                  if (neighbor.beg_node_id == node_id) {
                     ride_is.push(0);
                  }
                  if (neighbor.fin_node_id == node_id) {
                     ride_is.push(neighbor.xs.length - 1);
                  }
                  for each (ride_i in ride_is) {
                     this.drag_buddy_add_maybe(neighbor, ride_i);
                  }
               }
            }
         }
      }

      //
      protected function drag_buddy_add_maybe(byway:Byway, inter:int) :void
      {
         var i:int;

// FIXME: [lb] having problems here when trying to edit...
         // byway.vertices is null unless the byway is selected.
         m4_DEBUG('drag_buddy_add_maybe: byway.vertices:', byway.vertices);
         if ((byway.selected) && (!(inter in byway.vertices))) {
            m4_ERROR('drag_buddy_add_maybe: byway:', byway);
            m4_ERROR2('drag_buddy_add_maybe: byway.vertices.length:',
                      byway.vertices.length);
            m4_ERROR('drag_buddy_add_maybe: byway.vertices:', byway.vertices);
            m4_ERROR(' inter:', inter);
         }
         else {
            if (!((byway.selected)
                  && (byway.vertices[inter].selected))) {
               for (i = 0; i < this.drag_buddy_parents.length; i++) {
                  if (this.drag_buddy_parents[i] === byway
                      && this.drag_buddy_indices[i] == inter) {
                     return;
                  }
               }

               this.drag_buddy_parents.push(byway);
               this.drag_buddy_indices.push(inter);
            }
         }
      }

   }
}


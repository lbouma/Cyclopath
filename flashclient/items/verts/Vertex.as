/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.verts {

   import flash.display.Sprite;
   import flash.display.Graphics;
   import flash.events.MouseEvent;

   import items.Geofeature;
   import utils.misc.Draggable;
   import utils.misc.Logging;
   import views.base.App_Action;
   import views.commands.Vertex_Move;
   import views.map_widgets.tools.Tool_Pan_Select;

   // MAYBE: The flashclient doesn't have an, e.g., node_endpoint.py. It stores
   //        node Wiki data in Byway.as. And Vertex.as does the drawing.

   public class Vertex extends Sprite implements Draggable {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Vtils:Vertex');

      // *** Instance variables

      public var coord_index:int;
      public var parent_:Geofeature; // READ-ONLY, must be non-null

      protected var mouse_is_over:Boolean;
      protected var deselect_needed:Boolean;

      // *** Constructor

      // index is the index into the xs and ys array of parent
      public function Vertex(index:int, parent:Geofeature)
      {
         super();

         this.coord_index = index;
         this.parent_ = parent;

         // Map_Canvas_Controller calls our on_mouse_down and on_mouse_up,
         // in add_mouse_listeners.
         this.addEventListener(MouseEvent.ROLL_OVER, this.on_roll_over,
                               false, 0, true);
         this.addEventListener(MouseEvent.ROLL_OUT, this.on_roll_out,
                               false, 0, true);
      }

      // *** Static class methods

      // Return an array containing the indices of the selected vertices in
      // all selected Geofeatures.
      //
      // NOTE: It is very important that indices be increasing within each
      // Geofeature's section of the array, because other parts of the code
      // depend on this property.
      public static function get selected_coord_indices() :Array
      {
         var a:Array = new Array();
         var g:Geofeature;
         var v:Vertex;

         for each (g in G.map.selectedset) {
            for each (v in g.vertices) {
               if (v.selected) {
                  a.push(v.coord_index);
               }
            }
         }

         return a;
      }

      // Return an array of all parents of selected vertices, with each parent
      // appearing once per selected vertex (suitable for use as a parallel
      // array to selected_coord_indices).
      public static function get selected_parents() :Array
      {
         var a:Array = new Array();
         var g:Geofeature;
         var p:Object;
         var v:Vertex;

         for each (g in G.map.selectedset) {
            for each (v in g.vertices) {
               if (v.selected) {
                  a.push(g);
               }
            }
         }

         return a;
      }

      // *** Getters and setters

      //
      public function get is_dangle() :Boolean
      {
         return this.parent_.is_dangle(this.coord_index);
      }

      //
      public function get is_endpoint() :Boolean
      {
         return this.parent_.is_endpoint(this.coord_index);
      }

      //
      public function get selected() :Boolean
      {
         return this.is_selected();
      }

      //
      public function set selected(s:Boolean) :void
      {
         return this.set_selected(s);
      }

      //
      public function is_selected() :*
      {
         //m4_DEBUG3('get selected: selected_vertices:',
         //          ((this.parent_ !== null)
         //           ? this.parent_.selected_vertices : 'null'));
         return ((this.parent_.selected_vertices !== null)
                 && (this.parent_.selected_vertices.is_member(this)));
      }

      //
      public function set_selected(s:*) :void
      {
         //m4_DEBUG4('set_selected: s:', ((s !== null) ? s : 'null'),
         //          '/ idx:', coord_index,
         //          '/ parent_:', this.parent_,
         //          '/ no. sel:', this.parent_.selected_vertices.length);
         if (s != this.selected) {
            if (this.parent_.selected_vertices !== null) {
               if (s) {
                  // G.map.orn_selection can be null if there's an earlier
                  // problem, like vertices being left on the map for a
                  // byway that was deselected. So, yes, there's an earlier
                  // bug, but that doesn't mean we should let TypeError occur.
                  if ((this.parent_.selected_vertices.length == 0)
                      && (G.map.orn_selection !== null)) {
                     //G.map.orn_selection.glows.visible = false;
                     // Setting this true instead fixes the problem that
                     // dragging a vertex hides the purple highlight from
                     // everything that is selected.
                     // FIXME: If you click another item, one item of what
                     //        was previously selected remains selected.
                     G.map.orn_selection.glows.visible = true;
                  }
                  this.parent_.selected_vertices.add(this);
               }
               else { // !s
                  this.parent_.selected_vertices.remove(this);
                  if ((this.parent_.selected_vertices.length == 0)
                      && (G.map.orn_selection !== null)) {
                     G.map.orn_selection.glows.visible = true;
                  }
               }
            }
            else {
               m4_WARNING('missing selected_vertices:', this.parent_);
            }
            if (s !== null) {
               this.draw();
            }
         }
         else {
            //m4_DEBUG('set_selected: already selected or not');
         }
      }

      //
      // Get or set the x/y coord of the parent at this vertex's index.
      // For set operations, this actually modifies the parent's array.
      //

      //
      public function get x_map() :Number
      {
         return this.parent_.xs[this.coord_index];
      }

      //
      public function set x_map(x:Number) :void
      {
         this.parent_.xs[this.coord_index] = x;
      }

      //
      public function get y_map() :Number
      {
         return this.parent_.ys[this.coord_index];
      }

      //
      public function set y_map(y:Number) :void
      {
         this.parent_.ys[this.coord_index] = y;
      }

      //
      // Same as map version, but returns/sets values in canvas space
      // instead of map space.
      //

      //
      public function get x_cv() :Number
      {
         return G.map.xform_x_map2cv(this.x_map);
      }

      //
      public function set x_cv(x:Number) :void
      {
         this.x_map = G.map.xform_x_cv2map(x);
      }

      //
      public function get y_cv() :Number
      {
         return G.map.xform_y_map2cv(this.y_map);
      }

      //
      public function set y_cv(y:Number) :void
      {
         this.y_map = G.map.xform_y_cv2map(y);
      }

      // *** Mouse handlers

      // Overrides of drag must set deselect_need to false to get correct
      // ctrl click behavior
      public function drag(xdelta:Number, ydelta:Number) :void
      {
         m4_ASSERT(this.selected);
         this.deselect_needed = false;
         var cmd:Vertex_Move;
         cmd = new Vertex_Move(Vertex.selected_parents,
                               Vertex.selected_coord_indices,
                               xdelta,
                               ydelta)
         G.map.cm.do_(cmd);
         // The Vertex_Move command doesn't hydrate/lazy-load items, so
         // is_prepared is always non-null.
         m4_ASSERT_SOFT(cmd.is_prepared !== null);
      }

      // Notify sub-class of a drag start (does nothing by default)
      public function drag_start() :void
      {
         // No-op
      }

      //
      public function on_mouse_doubleclick(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         m4_DEBUG('on_mouse_doubleclick: this:', this, 'target:', ev.target);
         //m4_VERBOSE('  ev:', ev);

         m4_ASSERT(processed == false); // We're called first for dblclk.

         G.tabs.settings.sticky_intersections =
            !G.tabs.settings.sticky_intersections;
         // FIXME: Do something when making unsticky.
         //        Or fix the whole situation.
         //        What's the use case?
         //        User wants to disconnect a vertex and move it
         //        somewhere... so maybe usually sticky, but a double
         //        click releases the active byway's vertex (but what
         //        if multiple selected) and then back to sticky?
         //
         G.tabs.settings.connectivity = true;

         // We toggled sticky_intersections, so redraw the vertex.
         this.draw();

         // MAYBE: The user double-clicked a vertex. Does this mean anything?
         //        For now, not doing anything.
         processed = true;

         // BUG nnnn: You can see connectivity when you hover, but we could
         //           also color the selected vertex according to if it's
         //           snapped to any intersection it intersects.

         return processed;
      }

      // Selects the given vertex
      public function on_mouse_down(ev:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_down: target:', ev.target);
         m4_VERBOSE('  ev:', ev);

         // This is not an actual mouse down handler -- it's called shortly
         // after the down click, maybe even after the up click, to process
         // the click. So we don't have to worry about the double click
         // detector.
         // Nope: G.map.double_click.detector_reset();

         if (G.app.mode.is_allowed(App_Action.item_edit)) {

            if (!(ev.ctrlKey || ev.shiftKey || this.selected)) {
               // The user wasn't using any keyboard modifiers and this vertex
               // isn't selected any longer, so clear the vertices of all
               // selected geofeatures on the map.
               // EXPLAIN: What does a user do to trigger this behavior?
               m4_DEBUG('EXPLAIN: on_mouse_down map_selection_clear_vertices');
               // NOTE: We're clearing the geofeature _vertex_ selection set,
               //       i.e., not selected set of items.
               this.map_selection_clear_vertices();
            }

            if ((!this.selected) || (!(ev.ctrlKey || ev.shiftKey))) {
               this.deselect_needed = false;
            }

            m4_DEBUG('on_mouse_down: vertex setting selected true');
            this.set_selected(true);

            if (G.map.tool_is_active(Tool_Pan_Select)) {
               G.map.tool_cur.dragged_object = this;
               m4_TALKY2('on_mouse_down: G.map.tool_cur.dragged_object:',
                         G.map.tool_cur.dragged_object);
            }
         }
         // else, not editing, but then the vertices shouldn't be showing.
      }

      // Deselects the vertex.
      public function on_mouse_up(ev:MouseEvent, processed:Boolean) :Boolean
      {
         //m4_DEBUG('on_mouse_up: target:', ev.target);
         //m4_VERBOSE('  ev:', ev);

         // Set processed to true so that Tool_Pan_Select.on_mouse_up does
         // not refresh the viewport, which sends a bunch of checkout requests.
         var processed:Boolean = true;

         if (G.app.mode.is_allowed(App_Action.item_edit)) {
            // EXPLAIN: This is the only place this.deselect_needed is used or
            // set true. All other places set it false. So how does setting
            // it true on mouse up and only deselecting if true in mouse up
            // work? Setting it true here means user has to click again, and on
            // the second click we deselect. And this event handler only runs
            // if user is clicking the vertex sprite, right?
            if ((this.deselect_needed)
                || (!this.parent_.persistent_vertex_selecting)) {
               this.set_selected(false);
            }
            this.deselect_needed = true;
            G.map.tool_cur.void_next_clear = true;
         }
         else {
            // We don't show the vertices in non-edit mode.
            m4_WARNING2('Unexpected: user clicked vertex but not editing?:',
                        this, '/ parent_:', this.parent_);
         }

         return processed;
      }

      //
      public function on_roll_out(ev:MouseEvent) :void
      {
         // MAYBE: We could just deregister the mouse listeners when the users
         //        is not in an editable mode.
         if (G.app.mode.is_allowed(App_Action.item_edit)) {
            this.mouse_is_over = false;
            this.draw();
         }
      }

      //
      public function on_roll_over(ev:MouseEvent) :void
      {
         // MAYBE: We could just deregister the mouse listeners when the users
         //        is not in an editable mode.
         if (G.app.mode.is_allowed(App_Action.item_edit)) {
            this.mouse_is_over = true;
            // We just shade the vertex square differently to suggest to the
            // user that it's active (and can be dragged).
            this.draw();
         }
      }

      // *** Instance methods

      // Called when the parent is no longer selected.
      public function vertex_cleanup() :void
      {
         this.set_selected(false);
         // vertex_cleanup just sets vertex.set_selected(false),
         // but a vertex doesn't have to be selected to have
         // already drawn itself on the map (e.g., a small square
         // represents an un-selected vertex and a large square is
         // the selected vertex). So we still have to tell the
         // vertex to un-draw itself.
         //m4_DEBUG('vertex_cleanup: graphics.clear:', this);
         this.graphics.clear();
      }

      //
      public function draw() :void
      {
         //m4_DEBUG('draw:', this);

         var g:Graphics = this.graphics;
         var size:Number = Conf.selection_elbow_size;
         var fill:int;

         if (this.selected) {
            size *= 2;
         }

         if ((this.mouse_is_over)
             || (G.map.tool_cur.dragged_object == this)) {
            // Use different colors depending on sticky intersections.
            if (G.tabs.settings.sticky_intersections) {
               fill = Conf.vertex_highlight_color;
            }
            else {
               fill = 0xffe400;
            }
         }
         else if (this.is_endpoint) {
            // BUG nnnn: Color differently if a dangle.
            if (!this.is_dangle) {
               fill = 0x00c4ff;
            }
            else {
               fill = 0xff4200;
            }
         }
         else {
            fill = Conf.selection_color;
         }

         //m4_DEBUG('draw: graphics.clear:', this);
         g.clear();
         g.lineStyle(1, Conf.selection_color);
         g.beginFill(fill);
         g.drawRect(this.x_cv - size / 2,
                    this.y_cv - size / 2,
                    size,
                    size);
         g.endFill();
      }

      // Called when the vertex becomes visible, ie parent is selected.
      public function init() :void
      {
         // do nothing in base class
      }

      //
      public function map_selection_clear_vertices() :void
      {
         var g:Geofeature;
         for each (g in G.map.selectedset) {
            g.vertices_select_none();
         }
      }

      // ***

      //
      override public function toString() :String
      {
         return ('Vertex: idx: ' + coord_index
                 + ' / parent_:' + this.parent_
                 );
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// MAYBE: There's lots of duplicate code in here. See Bug 1735.

package views.map_widgets.tools {

   import flash.events.MouseEvent;
   import flash.geom.Point;

   import grax.Access_Level;
   import items.feats.Byway;
   import utils.misc.Logging;
   import views.base.Map_Canvas_Base;
   import views.commands.Command_Base;
   import views.commands.Geofeature_Create;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Geofeature;

// BUG nnnn: Complain to user if they make a few byways
// and none are connected to the graph...
// that, or maybe prefer to start a new byway already
// connected, i.e., always snap to existing intersection
// unless user explicitly breaks connectivity.
// Point being: make it harder for and alert user to
// disconnectivity problems.

   public class Tool_Byway_Create extends Map_Tool {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:Bwy_Crt');

      // *** Instance variables

      protected var dummy:Byway;

      // *** Constructor

      public function Tool_Byway_Create(map:Map_Canvas_Base)
      {
         super(map);
      }

      // *** Instance methods

      //
      protected function tool_cleanup() :void
      {
         m4_ASSERT(this.dummy === null);
      }

      //
      override public function drag(x_old:Number, y_old:Number,
                                    x_new:Number, y_new:Number) :void
      {
         m4_ASSERT((this.useable) && (this.dragged_object === this.dummy));
         this.dummy.move_cv(x_new - x_old, y_new - y_old);
         this.dummy.draw_all();
      }

      //
      override public function get tool_is_advanced() :Boolean
      {
         return true;
      }

      //
      override public function get tool_name() :String
      {
         return 'tools_byway_create';
      }

      //
      override public function get useable() :Boolean
      {
         return ((super.useable)
                 && (this.map.zoom_is_vector())
                 //&& (this.map.selectedset.length >= 0)
                 // This is redundant; see user_has_permissions:
                 && (G.item_mgr.create_allowed_get(Byway)));
      }

      // *** Double click detector mouse handlers

      //
      override public function on_mouse_down(ev:MouseEvent,
                                             could_be_double_click:Boolean)
                                                :void
      {
         m4_DEBUG('on_mouse_down: this.dragged_object:', this.dragged_object);

         super.on_mouse_down(ev, could_be_double_click);

         // Wait for the user to release to mouse before switching panels,
         // otherwise we won't get the on_mouse_up. That's because clearing
         // the active panel causes this.map.map_selection_clear(), which
         // triggers a tool reset (from tools_byway_create back to tools_pan).
         // Not yet: G.panel_mgr.effectively_active_panel = null;

         var xy:Point;
         xy = new Point(ev.stageX, ev.stageY);  // stage space
         xy = this.map.globalToLocal(xy);       // canvas space

         // Create a dummy item so the user has something to drag around (while
         // the mouse is down, until on_mouse_up).
         // 2013.07.19: Seriously, why do we need a dummy item?
         this.dummy = new Byway(null, G.map.rev_workcopy);

         // Since this tool is useable, we can assume the user can create
         // items of this type, and we can assume the user has at least editor
         // access. We'll set the real permissions in on_mouse_up().
         this.dummy.access_level_id = Access_Level.editor;

         // Configure the item geometry.
         this.dummy.xs = new Array(2);
         this.dummy.ys = new Array(2);
         this.dummy.x_start = this.map.xform_x_cv2map(xy.x - 16);
         this.dummy.y_start = this.map.xform_y_cv2map(xy.y);
         this.dummy.x_end = this.map.xform_x_cv2map(xy.x + 16);
         this.dummy.y_end = this.dummy.y_start;

         // A byway's name can be empty, unlike a point or region. This is
         // because we really don't need to label an unnamed road, but we'd
         // prefer that all waypoints and regions have names.
         this.dummy.name_ = '';

         // Add the dummy to the map. We'll replace it later w/ the real item.
         this.map.items_add([this.dummy,]);

         this.dummy.set_selected(true, /*nix=*/false, /*solo=*/true);

         this.dragged_object = this.dummy;

         m4_DEBUG('on_mouse_down: dragged_object: dummy:', this.dummy);
      }

      //
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         // This if is necessary because dragged_object will be null
         // if the user clicks down on a non-Map_Canvas component.
         // EXPLAIN: Why doesn't Tool_Waypoint_Create need a dummy object to be
         //          draggable?

         m4_DEBUG('on_mouse_up: this.dragged_object:', this.dragged_object);

         if (this.dragged_object !== null) {

            m4_ASSERT(this.dragged_object === this.dummy);

            m4_ASSERT(G.map.rev_workcopy !== null);

            var by:Byway;
            by = this.dummy;
            this.dummy = null;

            by.access_level_id = Access_Level.invalid;
            var cmd:Command_Base = new Geofeature_Create(by);

            G.map.cm.do_(cmd);
            // The item(s) being created are automatically considered hydrated.
            m4_ASSERT_SOFT(cmd.is_prepared !== null);
            if (!cmd.is_prepared) {
               // Map_Tool should not be useable otherwise (user does not have
               // access rights, or map is still loading, etc.).
               m4_WARNING('on_mouse_up: cannot create byway:', by.toString());
            }

            this.tool_cleanup();
            G.map.tool_choose('tools_pan');
         }
         else {
            m4_WARNING('EXPLAIN: No this.dragged_object?');
         }

         return super.on_mouse_up(ev, processed);
      }

   }
}


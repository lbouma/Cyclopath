/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// MAYBE: There's lots of duplicate code in here. See Bug 1735.

package views.map_widgets.tools {

   import flash.events.MouseEvent;
   import flash.geom.Point;

   import grax.Access_Level;
   import items.feats.Waypoint;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import views.base.Map_Canvas_Base;
   import views.commands.Command_Base;
   import views.commands.Geofeature_Create;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Geofeature;

   public class Tool_Waypoint_Create extends Map_Tool {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:Wpt_Crt');

      // *** Instance variables

      protected var dummy:Waypoint;

      // *** Constructor

      public function Tool_Waypoint_Create(map:Map_Canvas_Base)
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
         return false;
      }

      //
      override public function get tool_name() :String
      {
         return 'tools_point_create';
      }

      //
      override public function get useable() :Boolean
      {
         return ((super.useable)
                 //&& (this.map.zoom_is_vector())
                 //&& (this.map.selectedset.length >= 0)
                 // This is redundant; see user_has_permissions:
                 && (G.item_mgr.create_allowed_get(Waypoint)));
      }

      // *** Double click detector mouse handlers

      //
      override public function on_mouse_down(ev:MouseEvent,
                                             could_be_double_click:Boolean)
                                                :void
      {
         m4_DEBUG('on_mouse_down: this.dragged_object:', this.dragged_object);

         super.on_mouse_down(ev, could_be_double_click);

         // We want to immediately active the new item's details panel, so
         // clear the effectively_active_panel. We'll set the item selected
         // after we create it. This lets the user drag the item around while
         // holding the mouse down.
         G.panel_mgr.effectively_active_panel = null;

         var xy:Point;
         xy = new Point(ev.stageX, ev.stageY); // Stage space
         xy = this.map.globalToLocal(xy);  // Canvas space

         // Create a dummy item so the user has something to drag around.
         this.dummy = new Waypoint(null, G.map.rev_workcopy);

         // Since this tool is useable, we can assume the user can create
         // items of this type, and we can assume the user has at least editor
         // access. We'll set the real permissions in on_mouse_up().
         this.dummy.access_level_id = Access_Level.editor;

         // Configure the item geometry.
         this.dummy.x_cv = xy.x;
         this.dummy.y_cv = xy.y;

         // E.g., "Unnamed point". NOTE: If we didn't specify a name,
         // Widget_Name_Header.repopulate would at least put 'Unnamed point'
         // in the name header, but then a label wouldn't appear on the map --
         // that is, an unnamed byway should not have a label on the map, but
         // all points should be named, even if "unnamed".
         this.dummy.name_ =
            'Unnamed ' + this.dummy.friendly_name.toLowerCase();

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

         m4_DEBUG('on_mouse_up: this.dragged_object:', this.dragged_object);

         if (this.dragged_object !== null) {

            // 2013.04.09: The modal dialog is disruptive. Just give the point
            //             a default name and maybe highlight the name widget.
            m4_DEBUG('on_mouse_up: this.dummy:', this.dummy);

            m4_ASSERT(this.dragged_object === this.dummy);

            m4_ASSERT(G.map.rev_workcopy !== null);

            var wp:Waypoint;
            wp = this.dummy;
            this.dummy = null;

            wp.access_level_id = Access_Level.invalid;

            var cmd:Command_Base = new Geofeature_Create(wp);
            G.map.cm.do_(cmd);

            // The item(s) being created are automatically considered hydrated.
            m4_ASSERT_SOFT(cmd.is_prepared !== null);
            if (!cmd.is_prepared) {
               m4_WARNING('on_mouse_up: cannot create waypoint:', wp);
            }

            this.tool_cleanup();

            G.map.tool_choose('tools_pan');

            // FIXME: Statewide UI: Does the Waypoint's panel get displayed?
            // Was: G.app.side_panel.selectedChild = G.app.items_panel;
            //? G.app.side_panel.selectedChild = wp.?? or G.item_mgr.??
         }
         else {
            m4_WARNING('on_mouse_up: !dragged_object: dummy:', this.dummy);
         }

         return super.on_mouse_up(ev, processed);
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// MAYBE: There's lots of duplicate code in here. See Bug 1735.

package views.map_widgets.tools {

   import flash.events.MouseEvent;
   import flash.geom.Point;

   import grax.Access_Level;
   import items.feats.Region;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import views.base.Map_Canvas_Base;
   import views.commands.Geofeature_Create;
   import views.commands.Command_Base;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Geofeature;

   public class Tool_Region_Create extends Map_Tool {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:Reg_Crt');

      // *** Instance variables

      protected var dummy:Region;

      protected var regions_were_on:Boolean = false;

      // *** Constructor

      public function Tool_Region_Create(map:Map_Canvas_Base)
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
         m4_ASSERT_SOFT(this.useable && (this.dragged_object === this.dummy));
         this.dummy.move_cv(x_new - x_old, y_new - y_old);
         // NOTE: Don't drag region - it doesn't draw right, and it's
         //       confusing. See Bug 1736.
         // FIXME: Can we implement region dragging otherwise?
         //this.rg_dummy.draw_all();
// 2013_07_03: ???? Trying it:
// It seems smooth. Why does Bug 1736 says it's confusing?
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
         return 'tools_region_create';
      }

      //
      override public function get useable() :Boolean
      {
         // Regions may be created at any zoom level, so nothing special.
         // Ignoring: super.useable;
         return ((super.useable) &&
                 //&& (this.map.zoom_is_vector())
                 //&& (this.map.selectedset.length >= 0)
                 // This is redundant; see user_has_permissions:
                 (G.item_mgr.create_allowed_get(Region)));
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

         // BUG nnnn: Be able to drag region by clicking on name or crosshairs.
         //           Maybe for now, double-clicking to select all vertices
         //           works. If so, make a meta-key-click combo?
         //           At least make it more discoverable.
         // Work-around/Document for users: double click line to lock vertices,
         //   then drag.

         var xy:Point;
         xy = new Point(ev.stageX, ev.stageY); // stage space
         xy = this.map.globalToLocal(xy);  // canvas space

         // Create a dummy item so the user has something to drag around.
         this.dummy = new Region(null, G.map.rev_workcopy);

         // Since this tool is useable, we can assume the user can create
         // items of this type, and we can assume the user has at least editor
         // access. We'll set the real permissions in on_creation_confirm().
         this.dummy.access_level_id = Access_Level.editor;

         // Configure the item geometry.
         //
         var width:Number = 0.4 * G.map.view_rect.cv_width;
         var height:Number = 0.4 * G.map.view_rect.cv_height;
         //
         this.dummy.xs = new Array(5);
         this.dummy.ys = new Array(5);
         //
         this.dummy.xs[0] = G.map.xform_x_cv2map(xy.x - width / 2);
         this.dummy.xs[1] = G.map.xform_x_cv2map(xy.x + width / 2);
         this.dummy.xs[2] = this.dummy.xs[1];
         this.dummy.xs[3] = this.dummy.xs[0];
         this.dummy.xs[4] = this.dummy.xs[0];
         //
         this.dummy.ys[0] = G.map.xform_y_cv2map(xy.y - height / 2);
         this.dummy.ys[1] = this.dummy.ys[0];
         this.dummy.ys[2] = G.map.xform_y_cv2map(xy.y + height / 2);
         this.dummy.ys[3] = this.dummy.ys[2];
         this.dummy.ys[4] = this.dummy.ys[0];

         // A region should always be named and have a label, so start with
         // "Unnamed region".
         this.dummy.name_ =
            'Unnamed ' + this.dummy.friendly_name.toLowerCase();

         // Add the dummy to the map. We'll replace it later w/ the real item.
         this.map.items_add([this.dummy,]);

         // Region.set_selected sets regions_visible to true when selecting.
         this.regions_were_on = G.tabs.settings.regions_visible;

         this.dummy.set_selected(true, /*nix=*/false, /*solo=*/true);

         this.dragged_object = this.dummy;

         m4_DEBUG('on_mouse_down: dragged_object: dummy:', this.dummy);
      }

      //
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         m4_DEBUG('on_mouse_up: this.dragged_object:', this.dragged_object);

         if (this.dragged_object !== null) {

            m4_DEBUG('on_mouse_up: this.dummy:', this.dummy);

            m4_ASSERT(this.dragged_object === this.dummy);

            m4_ASSERT(G.map.rev_workcopy !== null);

            var rg:Region;
            rg = this.dummy;
            this.dummy = null;

            rg.access_level_id = Access_Level.invalid;

            var cmd:Command_Base = new Geofeature_Create(rg);
            G.map.cm.do_(cmd);

            // The item(s) being created are automatically considered hydrated.
            m4_ASSERT_SOFT(cmd.is_prepared !== null);
            if (!cmd.is_prepared) {
               m4_WARNING('on_mouse_up: cannot create region:', rg.toString());
            }

            // Remove the dummy region
            this.tool_cleanup();

            // 2013.04.09: Should we do what the Tool_Byway_Create does?:
            G.map.tool_choose('tools_pan');

            if (!this.regions_were_on) {
               Region.layer_turned_on_warn();
            }
         }
         else {
            m4_WARNING('on_mouse_up: !dragged_object: dummy:', this.dummy);
         }

         return super.on_mouse_up(ev, processed);
      }

   }
}


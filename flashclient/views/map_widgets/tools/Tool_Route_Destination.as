/* Copyright (c) 2006-2010 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets.tools {

   import flash.events.MouseEvent;

   import utils.misc.Logging;
   import views.base.Map_Canvas_Base;
   import views.panel_routes.Route_Editor_UI;

   public class Tool_Route_Destination extends Map_Tool {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:Rt_Dst');

      // *** Constructor

      public function Tool_Route_Destination(map:Map_Canvas_Base)
      {
         super(map);
      }

      // *** Instance methods

      //
      override public function get tool_is_advanced() :Boolean
      {
         return false; // MAYBE: Is this correct?
      }

      //
      override public function get tool_name() :String
      {
         return 'tools_route_dest_add';
      }

      //
      override public function get useable() :Boolean
      {
         return (
                 (super.useable)
                 //&& (this.map.zoom_is_vector())
                 //&& (this.map.selectedset.length >= 0)
                 // This is redundant; see user_has_permissions:
                 // ?? && (G.item_mgr.create_allowed_get(Waypoint))
                 );
      }

      // ***

      //
      override public function on_mouse_down(ev:MouseEvent,
                                             could_be_double_click:Boolean)
                                                :void
      {
         m4_DEBUG('on_mouse_down: tool_rte_dest');

         var x:Number = ev.stageX;
         var y:Number = ev.stageY;

         // Don't call the parent implementation, which just sets up dragging
         // the map (for the pan-select tool, or for new items that the user
         // can drag).
         // Nope: super.on_mouse_down(ev, could_be_double_click);

         this.update_new_stop(x, y);
      }

      //
      override public function on_mouse_move(x:Number, y:Number) :void
      {
         m4_VERBOSE('on_mouse_move: tool_rte_dest');

         // Skip the parent class, which does more pan-selecty stuff.
         // Nope: super.on_mouse_move(x, y);
      }

      //
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         m4_DEBUG('on_mouse_up: tool_rte_dest');

         // Change back to the pan tool.
         G.map.tool_choose('tools_pan');

         // NOTE: Calling super last.
         processed = super.on_mouse_up(ev, processed);
         return processed;
      }

      //
      // PROBABLY: This fcn. just updates static new_stop, meaning,
      // we should move this fcn. to Route_Editor_UI and make a new
      // object somewhere, so we're not doing staticy things.
      public function update_new_stop(x:Number, y:Number) :void
      {
         m4_DEBUG('update_new_stop');

         if (Route_Editor_UI.new_stop !== null) {

            // FIXME: If user is meaning to double-click, should we wait to do
            //        this?
            Route_Editor_UI.new_stop.name_ = null;
            //Route_Editor_UI.new_stop.node_id = ??;
            //Route_Editor_UI.new_stop.stop_version = ??;

            Route_Editor_UI.new_stop.x_map = G.map.xform_x_stage2map(x);
            Route_Editor_UI.new_stop.y_map = G.map.xform_y_stage2map(y);

            //Route_Editor_UI.new_stop.is_endpoint = ??;
            //Route_Editor_UI.new_stop.is_pass_through = ??;
            Route_Editor_UI.new_stop.is_transit_stop = false;

            Route_Editor_UI.new_stop.internal_system_id = 0;
            Route_Editor_UI.new_stop.external_result = false;

            //Route_Editor_UI.new_stop.street_name_ = null;
            //Route_Editor_UI.new_stop.orig_stop = null;
            //Route_Editor_UI.new_stop.dirty_stop = true;
            //Route_Editor_UI.new_stop.editor = null;

            Route_Editor_UI.notify_stop_changed(Route_Editor_UI.new_stop);
            Route_Editor_UI.new_stop = null;
         }
         else {
            // 2014.09.09: This is firing (via log_event_check.sh):
            m4_ASSERT_SOFT(false);
            G.sl.event('error/tool_rte_dest/update_new_stop',
                       {dragging: this.dragging,
                        dragged_object: this.dragged_object,
                        items_down_under: this.items_down_under});
         }
      }

   }
}


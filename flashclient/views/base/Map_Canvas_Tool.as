/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Part of the Map class hierarchy.

package views.base {

   import flash.events.Event;
   import flash.events.FocusEvent;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import mx.effects.Fade;
   import mx.effects.Move;
   import mx.events.EffectEvent;

   import utils.misc.Introspect; // for Bug nnnn
   import utils.misc.Logging;
   import views.map_widgets.tools.Map_Tool;
   import views.map_widgets.tools.Tool_Byway_Create;
   import views.map_widgets.tools.Tool_Byway_Split;
   import views.map_widgets.tools.Tool_Node_Endpoint_Build;
   import views.map_widgets.tools.Tool_Pan_Select;
   import views.map_widgets.tools.Tool_Region_Create;
   import views.map_widgets.tools.Tool_Route_Destination;
   import views.map_widgets.tools.Tool_Vertex_Add;
   import views.map_widgets.tools.Tool_Waypoint_Create;

   public class Map_Canvas_Tool extends Map_Canvas_Update {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('MC_Tool');

      // *** Class attributes

      // Tool management
      public var tool_cur:Map_Tool;
      public var tool_dict:Dictionary;

      // Fade effect for tool_palette. "Neeeet."
      protected var effect_fade:Fade = new Fade();

      // *** Constructor

      public function Map_Canvas_Tool()
      {
         super();

         // Initialize tools
         // SYNC_ME: Floating_Tool_Palette.tools_palette_basic_buttons
         this.tool_dict = new Dictionary();
         this.tool_dict['tools_pan']
            = new Tool_Pan_Select(this);
         this.tool_dict['tools_point_create']
            = new Tool_Waypoint_Create(this);
         this.tool_dict['tools_byway_create']
            = new Tool_Byway_Create(this);
         this.tool_dict['tools_region_create']
            = new Tool_Region_Create(this);
         this.tool_dict['tools_vertex_add']
            = new Tool_Vertex_Add(this);
         this.tool_dict['tools_byway_split']
            = new Tool_Byway_Split(this);
         this.tool_dict['tools_node_endpoint_build']
            = new Tool_Node_Endpoint_Build(this);
         // Circa 2012: This is a new tool for route manip.
         this.tool_dict['tools_route_dest_add']
            = new Tool_Route_Destination(this);
         // We used to default to 'tools_pan' but now we use
         // editmode_off/editmode_on. No: this.tool_choose('tools_pan');
      }

      // *** Instance methods

      //
      override protected function discard_reset() :void
      {
         if (this.tool_cur !== null) {
            this.tool_cur.deactivate();
         }
         super.discard_reset();
      }

      //
      override protected function discard_restore() :void
      {
         super.discard_restore();
         if (this.tool_cur !== null) {
            this.tool_cur.activate();
         }
      }

      // NOTE: editmode_on and editmode_off do exactly the same thing. Maybe
      //       just combine into one fcn., e.g., editmode_update().

      // Leave editing mode (disable editing tools). Idempotent.
      public function editmode_off() :void
      {
         var access_changed:Boolean = true;
         UI.editing_tools_update(access_changed);

         m4_DEBUG('edit mode to off');
         if ((this.tool_cur === null) || (!this.tool_cur.useable)) {
            this.tool_choose('tools_pan');
         }
      }

      // Enter editing mode (enable editing tools). Idempotent.
      public function editmode_on() :void
      {
         var access_changed:Boolean = true;
         UI.editing_tools_update(access_changed);

         m4_DEBUG('edit mode to on');
         if ((this.tool_cur === null) || (!this.tool_cur.useable)) {
            this.tool_choose('tools_pan');
         }
      }

      //
      public function switch_to_pan() :void
      {
         m4_DEBUG_CLLL('<callLater: switch_to_pan');
         this.tool_choose('tools_pan');
         // FIXME: This isn't timed with the others in the mouse sequence.
         //        It happens after the mouse event completes (though maybe
         //        before the click event, since it was set in mouse up?).
         this.tool_cur.void_next_clear = true;
      }

      // Set the current tool to t, which must be a string matching an entry
      // in this.tool_dict.
      public function tool_choose(t:String, short_circuit:Boolean=false) :void
      {
         m4_DEBUG('tool_choose: t:', t);

         // BUG nnnn: Drag a route and hit ESC should cancel the drag operation
         //           (otherwise user has to wait for the route requests to 
         //           finish, which can take lots of seconds). This wouldn't
         //           be so bad if it wasn't so easy to start a route drag
         //           operation...
         // DEVs: If you're dragging a route and click 'esc' (i.e., to
         //       cancel the drag action), this fcn. is called...
         //       the idea is to figure out how to go about canceling
         //       the drag, and it probably starts somewhere around here...
         if (Conf_Instance.debug_goodies) {
            m4_DEBUG(Introspect.stack_trace());
         }

         if (this.tool_cur !== null) {
            m4_TALKY(' .. deactivate:', this.tool_cur);
            this.tool_cur.deactivate();
         }
         this.tool_cur = this.tool_dict[t];
         if (this.tool_cur !== null) {
            m4_TALKY(' .. activate:', this.tool_cur);
            this.tool_cur.activate();
            this.tool_cur.cursor_set();
         }
         else {
            UI.cursor_set_native_arrow();
         }

         if (short_circuit) {
            return;
         }

         // Set the tool palette to match our selection.
         for (var i:int = 0; i < G.app.tool_palette.length; i++) {
            if ((t == G.app.tool_palette.get_tool_id(i))
                && (i != G.app.tool_palette.tool_by_index)) {
               G.app.tool_palette.tool_by_index = i;
            }
         }

         UI.save_remind_maybe();
      }

      // If the existing tool is not useable, change to Pan/Select.
      public function tool_choose_useable() :void
      {
         m4_DEBUG_CLLL('>callLater: tool_choose_useable');

         m4_VERBOSE('this.tool_cur:', this.tool_cur);

         // FIXME: This is the last debug message before the following
         //        intermittent error:
         //
         // TypeError: Error #1009: Cannot access a property or method of a
         //                         null object reference.
         // C:\autobuild\galaga\frameworks\projects\framework\src\mx
         //    \containers\TabNavigator.as|810|
         //    mx.containers::TabNavigator/keyDownHandler()
         //
         // Is this related to BUG 2088 in Panel_Manager?

         if (!this.tool_cur.useable) {
            m4_VERBOSE('tool_choose_useable: calling tool_choose');
            this.tool_choose('tools_pan');
         }
         m4_VERBOSE('tool_choose_useable: done');
      }

      // Return true if the given tool is active and useable.
      //
      // Note: "active" is true if either the given tool class OR one of its
      // descendants is active, but "useable" checks the ACTUAL active tool.
      // This can cause confusion e.g. for Tool_Pan_Select which is always
      // active, but its descendant tools are sometimes not.
      public function tool_is_active(t:Class) :Boolean
      {
         return ((this.tool_cur is t) && (this.tool_cur.useable));
      }

      // *** Getters and setters

      //
      // MAYBE: This fcn. -- or most of it -- probably belongs in the tool
      //        palette module.
      public function set map_editing_enabled(editing_enabled:Boolean) :void
      {
         m4_DEBUG('map_editing_enabled: editing_enabled:', editing_enabled);

         // We're called by the tool palette with G.app.mode changes.

         if ((G.app.tool_palette !== null)
             && (G.app.tool_palette.visible !== editing_enabled)) {

            var targets:Array = [G.app.tool_palette,];

            this.effect_fade = new Fade();
            this.effect_fade.targets = targets;
            this.effect_fade.duration = 850;
            if (editing_enabled) {
               this.effect_fade.alphaFrom = 0.0;
               this.effect_fade.alphaTo = 1.0;
               G.app.tool_palette.visible = true;
            }
            else {
               this.effect_fade.alphaFrom = 1.0;
               this.effect_fade.alphaTo = 0.0;
            }

            this.effect_fade.addEventListener(
               EffectEvent.EFFECT_END, this.on_effect_fade_end);

            m4_DEBUG('map_editing_enabled: nice effect');

            this.effect_fade.end();
            this.effect_fade.play();
         }
      }

      //
      protected function on_effect_fade_end(ev:EffectEvent) :void
      {
         m4_DEBUG('on_effect_fade_end: ev:', ev, '/ tgt:', ev.target);
         if ((ev.target as Fade).alphaTo == 0.0) {
            G.app.tool_palette.visible = false;
         }
         else {
            // This is coupled, but it's the simple way to do it.
            if (!G.app.tool_palette.played_effect_once) {
               var dont_delay:Boolean = true;
               // 2013.04.16: Because 'Allow Editing' is now a mode and the
               // floating tool palette is hidden by default, playing this
               // effect feels weird.
               var skip_effect:Boolean = true;
               G.app.tool_palette.play_effect(dont_delay, skip_effect);
            }
         }
      }

   }
}


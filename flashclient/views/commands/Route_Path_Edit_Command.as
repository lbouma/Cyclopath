/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This command merges an array of Route_Segments into the new geometry
// for an existing route.

package views.commands {

   import flash.events.Event;

   import grax.Dirty_Reason;
   import items.feats.Route;
   import items.utils.Travel_Mode;
   import utils.misc.Logging;
   import views.panel_routes.Route_Editor_UI;
   import views.panel_routes.Route_Segment;
   import views.panel_routes.Route_Stop;
   import views.panel_routes.Route_Stop_Editor;

   public class Route_Path_Edit_Command extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Rt_PEC');

      // *** Instance variables

      protected var new_segments:Array;

      protected var old_steps:Array;
      protected var old_xs:Array;
      protected var old_ys:Array;
      protected var old_stops:Array;

      // Manually editing is a valid repair option, so this command
      // clears any alternate path. On undo, we need to restore it
      protected var old_alternate_steps:Array;
      protected var old_alternate_xs:Array;
      protected var old_alternate_ys:Array;

      // Hold onto the previous last_cmd_stops state, and the new
      // last_cmd_stops created by this command
      protected var old_last_cmd_stops:Array;
      protected var new_last_cmd_stops:Array;

      // EXPLAIN: This gets set if do_ is called -- and Route_Editor_UI takes
      // it to mean that, the first time that route_update_complete is called,
      // it will perform extra checks to validate the segments' versions and
      // the route's stops' segment indices. [lb] is not quite sure how this
      // mechanism works in reality, i.e., how would I test the four different
      // scenarious, where performed_once is true and false and the extra
      // checks work and don't work.
      protected var performed_once:Boolean;
      protected var performed_once_for_update:Boolean;

      // *** Constructor

      public function Route_Path_Edit_Command(rt:Route)
      {
         var curr_rstop:Route_Stop;

         var stops_valid:Boolean = true;

         m4_ASSERT(rt.can_edit);
         m4_ASSERT(!rt.is_multimodal);

         this.performed_once = false;

         this.old_last_cmd_stops = rt.last_cmd_stops;
         this.new_last_cmd_stops = new Array();
         for each (curr_rstop in rt.edit_stops) {
            if (!curr_rstop.is_stop_valid) {
               // If a route stop is not assigned an x,y, then it's not valid.
               // This only happens after the user clicks Add Destination and
               // we pop up an empty input box for them to use to geocode. If
               // the user drags the new route stop entry to a new location in
               // the list, or if the user renames other entries in the list,
               // we'll generate commands for the undo/redo stack and we'll
               // come through here. But we don't rebuild any segments. below.
               stops_valid = false;
            }
            var rs_editor:Route_Stop_Editor = new Route_Stop_Editor();
            rs_editor.name_ = curr_rstop.name_;
            // We don't care about node_id, and it might not even exist.
            rs_editor.node_id = -1;
            // Start version at 0 until route stop is geocoded.
            rs_editor.stop_version = 0;
            rs_editor.x_map = curr_rstop.x_map;
            rs_editor.y_map = curr_rstop.y_map;
            rs_editor.is_endpoint = curr_rstop.is_endpoint;
            rs_editor.is_pass_through = curr_rstop.is_pass_through;
            rs_editor.is_transit_stop = curr_rstop.is_transit_stop;
            rs_editor.internal_system_id = curr_rstop.internal_system_id;
            rs_editor.external_result = curr_rstop.external_result;
            rs_editor.street_name_ = null; // curr_rstop.street_name_,
            rs_editor.orig_stop = curr_rstop.orig_stop;
            rs_editor.dirty_stop = curr_rstop.dirty_stop;
            rs_editor.editor = curr_rstop;
            this.new_last_cmd_stops.push(rs_editor);
         }

         if ((rt.edit_stops.length >= 2) && (stops_valid)) {

            // hold onto segments to pass to route_update_complete
            this.new_segments = new Array();

            // build desired segments, reusing the old/ route information
            // where possible
            for (var i:int = 1; i < rt.edit_stops.length; i++) {
               curr_rstop = rt.edit_stops[i];
               var prev_rstop:Route_Stop = rt.edit_stops[i - 1];

               var rseg:Route_Segment = null;
               if (   (!prev_rstop.dirty_stop)
                   && (!curr_rstop.dirty_stop)
                   && (prev_rstop.orig_stop !== null)
                   && (curr_rstop.orig_stop !== null)) {
                  // search for segments within the route that we can reuse
                  var j:int = rt.rstops.indexOf(prev_rstop.orig_stop);
                  var k:int = rt.rstops.indexOf(curr_rstop.orig_stop);

                  if (k == (j + 1)) {
                     // we use the entire route's xs and ys so that step
                     // indices still line up when we rebuild the route later
                     rseg = new Route_Segment();
                     rseg.ref_route = rt;
                     rseg.seg_route = null;
                     rseg.lhs_rstop = prev_rstop;
                     rseg.rhs_rstop = curr_rstop;
                     rseg.xs = rt.xs;
                     rseg.ys = rt.ys;
                     rseg.seg_rsteps = rt.steps_between(
                                       prev_rstop.orig_stop.node_id,
                                       curr_rstop.orig_stop.node_id);
                     rseg.seg_rstops = null;
                     rseg.rsn_len = NaN;
                     rseg.avg_cost = NaN;
                     rseg.seg_error = false;
                     rseg.lhs_version = prev_rstop.stop_version;
                     rseg.rhs_version = curr_rstop.stop_version;
                  }
               }

               if ((rseg === null) && (rt.updating_segments !== null)) {
                  // search for pending segments from a previous update that
                  // didn't have time to finish to see if we can reuse them
                  for each (var old_s:Route_Segment in rt.updating_segments) {
                     if (   (old_s.lhs_rstop === prev_rstop)
                         && (old_s.rhs_rstop === curr_rstop)
                         && (old_s.lhs_version == prev_rstop.stop_version)
                         && (old_s.rhs_version == curr_rstop.stop_version)) {
                        // found a pending request (reuse actual segment object
                        // so if the request hasn't completed, it will be
                        // updated) Note we keep any assigned error status, too
                        rseg = old_s;
                        break;
                     }
                  }
               }

               if (rseg === null) {
                  rseg = new Route_Segment();
                  rseg.ref_route = rt;
                  rseg.seg_route = null;
                  rseg.lhs_rstop = prev_rstop;
                  rseg.rhs_rstop = curr_rstop;
                  rseg.xs = null;
                  rseg.ys = null;
                  rseg.seg_rsteps = null;
                  rseg.seg_rstops = null;
                  rseg.rsn_len = NaN;
                  rseg.avg_cost = NaN;
                  rseg.seg_error = false;
                  rseg.lhs_version = prev_rstop.stop_version;
                  rseg.rhs_version = curr_rstop.stop_version;
                  // weren't able to re-use the route, so fire off a request
                  // to generate new path information
                  Route_Editor_UI.route_segment_fetch(rseg);
               }
               this.new_segments.push(rseg);
            }
         }

         // and remember old route state for undos
         this.old_steps = rt.rsteps;
         this.old_xs = rt.xs;
         this.old_ys = rt.ys;
         this.old_stops = rt.rstops;

         this.old_alternate_xs = rt.alternate_xs;
         this.old_alternate_ys = rt.alternate_ys;
         this.old_alternate_steps = rt.alternate_steps;

         //super([rt,], Dirty_Reason.item_data);
         super([rt,], Dirty_Reason.item_revisionless);
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         return 'editing route path';
      }

      //
      override public function do_() :void
      {
         super.do_();

         var rt:Route = (this.edit_items[0] as Route);

         // clear the alternate path since manual editing is a valid fix
         rt.alternate_xs = null;
         rt.alternate_ys = null;
         rt.alternate_steps = null;

         // Sync up edit_stops with new_last_cmd_stops
         // - this is mostly critical for redo commands.
         this.update_stops(rt, this.new_last_cmd_stops);

         // Send an update request. For redo, this will be completed
         // right away (and will ignore route_stop versions).
         m4_DEBUG('do_: rt.updating_segments/1:', rt.updating_segments);
         rt.updating_segments = this.new_segments;
         m4_DEBUG('do_: rt.updating_segments/2:', rt.updating_segments);

         this.performed_once_for_update = this.performed_once;
         this.route_update_complete(rt);

         this.performed_once = true;

         if (rt.is_drawable) {
            rt.draw();
         }
      }

      //
      override public function undo() :void
      {
         super.undo();

         var rt:Route = (this.edit_items[0] as Route);

         // restore the alternate paths
         rt.alternate_xs = this.old_alternate_xs;
         rt.alternate_ys = this.old_alternate_ys;
         rt.alternate_steps = this.old_alternate_steps;

         // restore old step and geometry state
         rt.xs = this.old_xs;
         rt.ys = this.old_ys;
         rt.rsteps = this.old_steps;

         // Restore the last synced route stops (important if the do_ did
         // a valid update of the route).
         m4_DEBUG('undo: rstops: old_stops.length:', this.old_stops.length);
         rt.rstops = this.old_stops;

         // Update edit_stops, which may be out of sync with valid route stops
         // if edit_stops was invalid.
         this.update_stops(rt, this.old_last_cmd_stops);

         rt.update_route_stats();

         if (rt.is_drawable) {
            rt.draw();
         }
      }

      // *** Helpers.

      //
      protected function on_rsteps_loaded(event:Event) :void
      {
         var rt:Route = (this.edit_items[0] as Route);
         m4_DEBUG('on_rsteps_loaded: routeStepsLoaded:', rt.softstr);
         this.route_update_complete(rt);
      }

      //
      protected function route_update_complete(rt:Route) :void
      {
         var wait_for_it:Boolean;
         wait_for_it = Route_Editor_UI.route_update_complete(
            rt, this.new_segments, this.performed_once_for_update);
         if (wait_for_it) {
            m4_DEBUG('route_upd_complt: listen: routeStepsLoaded:', rt);
            rt.addEventListener('routeStepsLoaded', this.on_rsteps_loaded);
         }
         else {
            m4_DEBUG('route_upd_complt: !wait_for_it: routeStepsLoaded:', rt);
            rt.removeEventListener('routeStepsLoaded', this.on_rsteps_loaded);
            // If the user is no longer dragging the route_stop, we can remove
            // the dashed as-the-crow-flies line and arrows.
            if (!G.map.tool_cur.dragging) {
               //rt.draw();
               rt.draw_all();
               m4_DEBUG('rte_upd_complete: rstop_editing_enabled=f');
               rt.rstop_editing_enabled = false;
            }
         }
      }

      //
      protected function update_stops(rt:Route, cmd_rstops:Array) :void
      {
         m4_DEBUG('update_stops: rt', rt.toString());

         // clean up sprite layer in case not all route stops make it back
         for (var i:int = rt.rstop_sprite.numChildren - 1; i >= 0; i --) {
            rt.rstop_sprite.removeChildAt(i);
         }

         rt.edit_stops_set(new Array());
         for each (var rt_stop:Route_Stop_Editor in cmd_rstops) {
            rt_stop.editor.name_ = rt_stop.name_;
            //
            // EXPLAIN: What about the missing attributes?
            //rt_stop.editor.node_id = rt_stop.node_id;
            //rt_stop.editor.stop_version = rt_stop.stop_version;
            //
            rt_stop.editor.x_map = rt_stop.x_map;
            rt_stop.editor.y_map = rt_stop.y_map;
            //
            // EXPLAIN: What about the missing attributes?
            //rt_stop.editor.is_endpoint = rt_stop.is_endpoint;
            //rt_stop.editor.is_pass_through = rt_stop.is_pass_through;
            rt_stop.editor.is_transit_stop = rt_stop.is_transit_stop;
            //
            // EXPLAIN: What about the missing attributes?
            //rt_stop.editor.internal_system_id = rt_stop.internal_system_id;
            //rt_stop.editor.external_result = rt_stop.external_result;
            //rt_stop.editor.street_name_ = rt_stop.street_name_;
            //
            rt_stop.editor.orig_stop = rt_stop.orig_stop;
            rt_stop.editor.dirty_stop = rt_stop.dirty_stop;
            //
            rt.edit_stops_push(rt_stop.editor);
         }
         rt.last_cmd_stops = cmd_rstops;
      }

   }
}


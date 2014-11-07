/* Copyright (c) 2006-2010 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import items.feats.Route;
   import items.feats.Route_Step;
   import utils.misc.Logging;

   /**
    * Route_Viz_Diff_Map contains static factory methods to return a color
    * map function for use with the Route_Viz class, to render a route for
    * the "diff" viewing mode.
    */
   public class Route_Viz_Diff_Map {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@Rt_Viz_DfMp');

      // *** Static class methods

      //
      public static function color_diff(r:Route) :Function
      {
         return function(step:Route_Step) :int
         {
            var other_rt:Route = r.counterpart;
            var step_in_other:Boolean = false;

            if (other_rt !== null) {
               var other:Route_Step;
               for each (other in other_rt.rsteps) {
                  if (other.byway_stack_id == step.byway_stack_id) {
                     step_in_other = (other.byway_version
                                      == step.byway_version);
                     break;
                  }
               }
            }

            if (step_in_other) {
               return Conf.vgroup_dark_static_color;
            }
            else if (r.is_vgroup_old) {
               return Conf.vgroup_move_old_color;
            }
            else {
               return Conf.vgroup_move_new_color;
            }
         }
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: route manip. new file.

// This command updates a route's geometry to use the alternate provided
// by the server when it detects block edits along the route.

// FIXME: Re-implement route updating...

package views.commands {

   import grax.Dirty_Reason;
   import items.feats.Route;
   import items.utils.Travel_Mode;
   import utils.misc.Collection;
   import utils.misc.Logging;

   public class Route_Conflict_Resolve_Command extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Rt_CRC');

      // *** Instance variables

      protected var new_steps:Array;
      protected var new_xs:Array;
      protected var new_ys:Array;

      protected var old_steps:Array;
      protected var old_xs:Array;
      protected var old_ys:Array;

      // *** Constructor

      public function Route_Conflict_Resolve_Command(rt:Route, use_alt:Boolean)
      {
         m4_ASSERT(!rt.is_multimodal);
         m4_ASSERT(rt.alternate_steps !== null);

         // In CcpC1, we just reference the route's arrays, but [lb] fears the
         // route's arrays may be edited, so make copies.
         if (use_alt) {
            //this.new_steps = rt.alternate_steps;
            //this.new_xs = rt.alternate_xs;
            //this.new_ys = rt.alternate_ys;
            this.new_steps = Collection.array_copy(rt.alternate_steps);
            this.new_xs = Collection.array_copy(rt.alternate_xs);
            this.new_ys = Collection.array_copy(rt.alternate_ys);

            this.old_steps = Collection.array_copy(rt.rsteps);
            this.old_xs = Collection.array_copy(rt.xs);
            this.old_ys = Collection.array_copy(rt.ys);
         }
         else {
            //this.new_steps = rt.rsteps;
            //this.new_xs = rt.xs;
            //this.new_ys = rt.ys;
            this.new_steps = Collection.array_copy(rt.rsteps);
            this.new_xs = Collection.array_copy(rt.xs);
            this.new_ys = Collection.array_copy(rt.ys);

            this.old_steps = this.new_steps;
            this.old_xs = this.old_xs;
            this.old_ys = this.old_ys;
         }

         //this.old_steps = rt.rsteps;
         //this.old_xs = rt.xs;
         //this.old_ys = rt.ys;

         //super([rt,], Dirty_Reason.item_data);
         super([rt,], Dirty_Reason.item_revisionless);
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         return 'updating route';
      }

// FIXME: Statewide UI: This command might be broken.
//        See Command_Base.activate_appropriate_panel,
//        among other things.

      //
      override public function do_() :void
      {
         super.do_();

         var rt:Route = (this.edit_items[0] as Route);

         m4_ASSERT(rt.alternate_steps !== null);

         // clear alternates so that the UI goes back to normal
         rt.alternate_steps = null;
         rt.alternate_xs = null;
         rt.alternate_ys = null;

         // update current geometry to be new version
         //rt.rsteps = this.new_steps;
         //rt.xs = this.new_xs;
         //rt.ys = this.new_ys;
         rt.rsteps = Collection.array_copy(this.new_steps);
         rt.xs = Collection.array_copy(this.new_xs);
         rt.ys = Collection.array_copy(this.new_ys);

         rt.update_route_stats();
         if (rt.is_drawable) {
            rt.draw();
         }
      }

      //
      override public function undo() :void
      {
         super.undo();

         var rt:Route = (this.edit_items[0] as Route);

         m4_ASSERT(rt.alternate_steps === null);

         // Reset alternate steps to the new geometry.
         //rt.alternate_steps = this.new_steps;
         //rt.alternate_xs = this.new_xs;
         //rt.alternate_ys = this.new_ys;
         rt.alternate_steps = Collection.array_copy(this.new_steps);
         rt.alternate_xs = Collection.array_copy(this.new_xs);
         rt.alternate_ys = Collection.array_copy(this.new_ys);

         // restore the original, invalid geometry
         //rt.rsteps = this.old_steps;
         //rt.xs = this.old_xs;
         //rt.ys = this.old_ys;
         rt.rsteps = Collection.array_copy(this.old_steps);
         rt.xs = Collection.array_copy(this.old_xs);
         rt.ys = Collection.array_copy(this.old_ys);

         rt.update_route_stats();
         if (rt.is_drawable) {
            rt.draw();
         }
      }

   }
}


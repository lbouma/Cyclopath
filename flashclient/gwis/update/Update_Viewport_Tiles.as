/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis.update {

   import utils.misc.Logging;

   // FIXME If you load the map, and while it's loading, you click the aerial
   //       checkbox, how does the system react?

   public class Update_Viewport_Tiles extends Update_Viewport_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_VP_Tiles');

      public static const on_completion_event:String = null; // 'updatedTiles';

      // *** Constructor

      public function Update_Viewport_Tiles()
      {
         super();
      }

      // *** Init methods

      //
      override protected function init_update_steps() :void
      {
         this.update_steps.push(this.update_step_viewport_common);
         this.update_steps.push(this.update_step_viewport_tiles);
      }

   }
}


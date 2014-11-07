/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// 20111004: FIXME: What's the point of this intermediate class?

package gwis.update {

   import gwis.GWIS_Base;
   import utils.misc.Logging;

   public class Update_Supplemental extends Update_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_Spplmntl');

      // Don't set on_completion_event, since we don't signal these.
      public static const on_completion_event:String = null;

      // *** Constructor

      public function Update_Supplemental()
      {
         super();
      }

      // ***

      //
      public function is_trumped_by(update_obj:Update_Base) :Boolean
      {
         // Default behavior: all supplemental requests are canceled or
         // de-queued if we're about to process a new Update request.
         var is_trumped:Boolean;
         if (update_obj is Update_Supplemental) {
            is_trumped = false;
         }
         else {
            is_trumped = true;
         }
         return is_trumped;
      }

   }
}


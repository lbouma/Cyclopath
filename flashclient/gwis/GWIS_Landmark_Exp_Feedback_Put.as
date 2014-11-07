/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   public class GWIS_Landmark_Exp_Feedback_Put extends GWIS_Landmark_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkFdbk');

      // *** Constructor

      public function GWIS_Landmark_Exp_Feedback_Put(
         feedback:String,
         callback_load:Function=null) // The only caller does not set callback.
            :void
      {
         var url:String = this.url_base('landmark_exp_feedback_put');
         var doc:XML = this.doc_empty();
         doc.appendChild(<feedback>{feedback}</feedback>);
         super(url,
               /*data=*/doc,
               /*throb=*/true,
               /*query_filters=*/null,
               /*update_req=*/null,
               /*callback_load=*/callback_load,
               /*callback_fail=*/null,
               /*caller_data=*/null);
      }

      // *** Instance methods

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

   }
}


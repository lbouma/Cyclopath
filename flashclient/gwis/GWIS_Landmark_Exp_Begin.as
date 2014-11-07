/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   public class GWIS_Landmark_Exp_Begin extends GWIS_Landmark_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkEBeg');

      // *** Constructor

      public function GWIS_Landmark_Exp_Begin(
         callback_load:Function=null) :void
      {
         var url:String = this.url_base('landmark_exp_begin');
         super(url,
               /*data=*/this.doc_empty(),
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


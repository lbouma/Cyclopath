/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import utils.misc.Logging;

   public class GWIS_Landmark_Exp_Rt_Done extends GWIS_Landmark_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkRtDn');

      // *** Instance attributes.

      protected var route_system_id:int;
      protected var route_user_id:int;

      // *** Constructor

      public function GWIS_Landmark_Exp_Rt_Done(
         route_system_id:int, route_user_id:Number=-1) :void
      {
         var url:String = this.url_base('landmark_exp_rt_done');
         this.route_system_id = route_system_id;
         this.route_user_id = route_user_id
         super(url,
               /*data=*/this.doc_empty(),
               /*throb=*/true,
               /*query_filters=*/null,
               /*update_req=*/null,
               /*callback_load=*/null,
               /*callback_fail=*/null,
               /*caller_data=*/null);
      }

      // *** Instance methods

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

      //
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);
         url = '';
         url += '&route_system_id=' + this.route_system_id;
         url += '&route_user_id=' + this.route_user_id;
         return super.finalize(url);
      }

   }
}


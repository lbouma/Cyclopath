/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   public class GWIS_Landmark_Exp_Fam_Put extends GWIS_Landmark_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkFamP');

      // *** Instance attributes.

      protected var route_system_id:int;
      protected var fam_val:int;

      // *** Constructor

      public function GWIS_Landmark_Exp_Fam_Put(
         route_system_id:int,
         fam_val:int,
         callback_load:Function=null) // The only caller does not set callback.
            :void
      {
         var url:String = this.url_base('landmark_exp_fam_put');
         this.route_system_id = route_system_id;
         this.fam_val = fam_val;
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

      //
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);
         url = '';
         url += '&route_system_id=' + this.route_system_id;
         url += '&fam=' + this.fam_val;
         return super.finalize(url);
      }

   }
}


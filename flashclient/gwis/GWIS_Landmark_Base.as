/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.update.Update_User;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_Landmark_Base extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkBase');

      // *** Constructor

      public function GWIS_Landmark_Base(
         url:String,
         data:XML=null,
         throb:Boolean=true,
         query_filters:Query_Filters=null,
         update_req:Update_Base=null,
         callback_load:Function=null,
         callback_fail:Function=null,
         caller_data:*=null) :void
      {
         super(url,
               /*data=*/data,
               /*throb=*/throb,
               /*query_filters=*/query_filters,
               /*update_req=*/update_req,
               /*callback_load=*/callback_load,
               /*callback_fail=*/callback_fail,
               /*caller_data=*/caller_data);
      }

      // *** Instance methods

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_update_user;
      }

   }
}


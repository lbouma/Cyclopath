/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.feats.Direction_Step;
   import items.utils.Landmark;
   import utils.geom.Geometry;
   import utils.misc.Logging;

   public class GWIS_Landmark_Exp_Val_Put extends GWIS_Landmark_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkVPut');

      // *** Constructor

      public function GWIS_Landmark_Exp_Val_Put(
         route_system_id:int,
         l:Landmark,
         step_number:int,
         callback_load:Function=null) :void
      {
         var url:String = this.url_base('landmark_exp_val_put');
         url += '&route_system_id=' + route_system_id;
         url += '&rating=' + l.rating;
         var doc:XML = this.doc_empty();

         doc.appendChild(<lmrk
               name={l.name}
               item_id={l.item_id}
               type_id={l.item_type_id}
               step={step_number}/>);

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


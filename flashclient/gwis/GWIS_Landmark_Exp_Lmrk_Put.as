/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.feats.Direction_Step;
   import items.utils.Landmark;
   import utils.geom.Geometry;
   import utils.misc.Logging;

   public class GWIS_Landmark_Exp_Lmrk_Put extends GWIS_Landmark_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkLPut');

      // *** Constructor

      public function GWIS_Landmark_Exp_Lmrk_Put(
         route_system_id:int,
         dirs:Array,
         callback_load:Function=null) // Of 2 callers, neither sets a callback.
            :void
      {
         var url:String = this.url_base('landmark_exp_landmark_put');
         url += '&route_system_id=' + route_system_id;
         var doc:XML = this.doc_empty();
         for each (var dir:Direction_Step in dirs) {
            for each (var l:Landmark in dir.landmarks) {
               if (l.display) {
                  var geo_str:String = '';
                  if (l.xs !== null) {
                     geo_str = Geometry.coords_xys_to_string(l.xs, l.ys);
                  }
                  doc.appendChild(<lmrk
                        name={l.name}
                        item_id={l.item_id}
                        type_id={l.item_type_id}
                        geometry={geo_str}
                        step={dir.step_number}/>);
               }
            }
         }
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


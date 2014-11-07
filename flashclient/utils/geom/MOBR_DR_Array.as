/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// An array with a minimum orthogonal bounding box, which surrounds the MOBR
// of each of the objects in the array. Said objects should also implement
// MOBRable_DR. Used with Map_Canvas.lookat()

package utils.geom {

   // NOTE: This class is dynamic because that's what you do when you extend
   //       Dictionary or Array.

   public dynamic class MOBR_DR_Array extends Array implements MOBRable_DR {

      //
      public function get mobr_dr() :Dual_Rect
      {
         // SYNC_ME: Dual_Rect.mobr_dr_from_xys / MOBR_DR_Array get mobr_dr.

         var dr:Dual_Rect = new Dual_Rect();

         var map_min_x:Number = Number.POSITIVE_INFINITY;
         var map_min_y:Number = Number.POSITIVE_INFINITY;
         var map_max_x:Number = Number.NEGATIVE_INFINITY;
         var map_max_y:Number = Number.NEGATIVE_INFINITY;

         for each (var o:Object in this) {
            var odr:Dual_Rect = o.mobr_dr;
            if (odr.map_min_x < map_min_x) {
               map_min_x = odr.map_min_x;
            }
            if (odr.map_min_y < map_min_y) {
               map_min_y = odr.map_min_y;
            }
            if (odr.map_max_x > map_max_x) {
               map_max_x = odr.map_max_x;
            }
            if (odr.map_max_y > map_max_y) {
               map_max_y = odr.map_max_y;
            }
         }

         // FIXME: order here is important.
         dr.map_min_x = map_min_x; // left
         dr.map_max_y = map_max_y; // top
         dr.map_max_x = map_max_x; // right
         dr.map_min_y = map_min_y; // bottom

         return dr;
      }

   }
}


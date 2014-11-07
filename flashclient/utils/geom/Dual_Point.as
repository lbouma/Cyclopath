/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A Dual_Point is a point which knows its coordinates in both canvas space
// and map space.

// FIXME: This class should be reimplemented as a special case of Dual_Rect,
//        but Dual_Rect has bugs which make it currently unsuitable.

// WARNING: See warnings in Dual_Rect.as

package utils.geom {

   public class Dual_Point implements MOBRable_DR {

      // *** Instance variables

      protected var map_x:Number;
      protected var map_y:Number;

      // *** Constructor

      // Arguments are in canvas space
      public function Dual_Point(cv_x:Number, cv_y:Number) :void
      {
         this.map_x = G.map.xform_x_cv2map(cv_x);
         this.map_y = G.map.xform_y_cv2map(cv_y);
      }

      // *** Getters/setters

      //
      public function get mobr_dr() :Dual_Rect
      {
         var dr:Dual_Rect = new Dual_Rect();
         dr.map_min_x = this.map_x;
         dr.map_max_y = this.map_y;
         dr.cv_height = 0;
         dr.cv_width = 0;
         return dr;
      }

   }
}


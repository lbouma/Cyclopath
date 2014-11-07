/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets {

   import flash.display.Sprite;

   import items.Geofeature;

   /**
    * A Shadow_Sprite is a special Sprite to be used for Geofeature shadows.
    * It contains a back reference to a Geofeature, which is required for
    * correct behavior with the Selection_Resolver.
    */
   public class Shadow_Sprite extends Sprite {

      protected var feature_:Geofeature;

      // *** Constructor

      public function Shadow_Sprite(feature:Geofeature)
      {
         super();
         this.feature_ = feature;
      }

      // *** Instance methods

      //
      public function get feature() :Geofeature
      {
         return this.feature_;
      }

   }
}


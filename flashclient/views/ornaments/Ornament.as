/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// An ornament is a noninteractive decoration of a Geofeature.

package views.ornaments {

   import flash.display.Sprite;

   import items.Geofeature;

   public class Ornament extends Sprite {

      // *** Instance variables

      protected var owner_:Geofeature;

      // *** Constructor

      public function Ornament(owner_:Geofeature)
      {
         super();
         this.owner_ = owner_;
      }

      // *** Instance methods

      //
      public function draw() :void
      {
         // nothing in base class
      }

   }
}


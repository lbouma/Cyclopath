/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Base class for Map_Layers and Map_Layer_Passives, to provide zplus
   attribute. */

package views.base {

   import mx.core.UIComponent;

   import utils.misc.Logging;

   public class Map_Layer_Base extends UIComponent {

      // *** Instance variables

      public var zplus:Number;

      // *** Constructor

      public function Map_Layer_Base(zplus:Number)
      {
         super();
         this.zplus = zplus;
      }

      //

      //
      override public function toString() :String
      {
         return super.toString() + ' / zplus: ' + this.zplus;
      }

   }
}


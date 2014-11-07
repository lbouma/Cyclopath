/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import flash.utils.getQualifiedClassName;
   import mx.controls.Button;
   import mx.core.Container;
   import mx.events.FlexEvent;

   import items.feats.Route;
   import utils.misc.Logging;
   import views.panel_base.Detail_Panel_Widget;

   public class Address_Chooser_Base extends Detail_Panel_Widget {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@AddyChoosB');

      // *** Instance variables

      // *** Constructor

      public function Address_Chooser_Base()
      {
         super();
      }

      // *** Getters/Setters

      //
      public function get addr_show_all_btn() :Button
      {
         m4_ASSERT(false); // Abstract.
         return null;
      }

      //
      public function set addr_show_all_btn(btn:Button) :void
      {
         m4_ASSERT(false);
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_base {

   import mx.containers.GridRow;
   import mx.events.FlexEvent;

   import utils.misc.Logging;

   // This class is c.f. Detail_Panel_Widget

   public class Detail_Panel_GridRow extends GridRow {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@DtlPnl_GRow');

      // *** Instance variables

      // This is the panel the created us and added us to its, er, panel
      //[Bindable]
      protected var dp:Detail_Panel_Base;

      protected var creation_completed:Boolean = false;

      // *** Constructor

      public function Detail_Panel_GridRow()
      {
         super();
         this.addEventListener(FlexEvent.CREATION_COMPLETE,
                               this.on_creation_complete, false, 0, true);
      }

      // *** Getters/Setters

      // The panel that creates us and adds us has to tell us who it is.
      public function set detail_panel(dp:Detail_Panel_Base) :void
      {
         m4_VERBOSE('detail_panel: dp:', dp);
         this.dp = dp;
      }

      // *** Instance methods

      // Listen for Flash to tell us it's created our child components,
      // lest we play with them before they exist
      protected function on_creation_complete(ev:FlexEvent) :void
      {
         m4_DEBUG('on_creation_complete');
         // We only get called once per object lifetime
         m4_ASSERT(!this.creation_completed);
         // I expected to find a parent attribute, maybe in UIComponent, that
         // indicates if creation is complete, but I couldn't find one. So we
         // maintain our own. [lb]
         this.creation_completed = true;
         // Schedule a call to on_panel_show
         //m4_DEBUG('callLater*: this.repopulate:', this);
      }

   }
}


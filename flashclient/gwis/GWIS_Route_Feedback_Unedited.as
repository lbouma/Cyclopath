/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: route manip. Reimplement route feedback.

package gwis {

   import mx.controls.Alert;
   import mx.managers.PopUpManager;

   import items.feats.Route;
   import utils.misc.Logging;
   import views.base.UI;
   import views.map_components.Please_Wait_Popup;
   import views.panel_routes.Route_Feedback_Popup;

   public class GWIS_Route_Feedback_Unedited extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Put_RtFB');

      // *** Instance variables

      private var feedback_window:Route_Feedback_Popup;

      // *** Constructor

      public function GWIS_Route_Feedback_Unedited(
         route:Route,
         purpose:String,
         satisfaction:int,
         feedback:String,
         fb_window:Route_Feedback_Popup) :void
      {
         var doc:XML = this.doc_empty();
         var url:String = this.url_base('route_feedback_unedited');

         this.feedback_window = fb_window;

         doc.appendChild(
            <feedback
               id={route.stack_id}
               version={route.version}
               purpose={purpose}
               satisfaction={satisfaction}>
               {feedback}
            </feedback>);

         super(url, doc);

         this.popup_enabled = true;
         this.gwis_active_alert = fb_window;
      }

      // *** Instance methods

      //
      override protected function error_present(text:String) :void
      {
         // BUG 2715: Better errors: Does this failure happen often?
         Alert.show(text, 'Feedback failed');
      }

      //
      override public function fetch() :void
      {
         // Show a Popup while processing the request
         var popup_window:Please_Wait_Popup;
         popup_window = new Please_Wait_Popup();
         UI.popup(popup_window, 'b_cancel');
         popup_window.init(
            'Sending route feedback', 'Please wait.', this, false);
         this.gwis_active_alert = popup_window;

         super.fetch();
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         Alert.show('Feedback saved successfully.', 'Feedback successful');
         PopUpManager.removePopUp(this.feedback_window);
      }

   }
}


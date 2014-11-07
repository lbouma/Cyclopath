/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.controls.Alert;
   import mx.managers.PopUpManager;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   // BUG 1828: Should search be paginated? Currently, all requests are
   // retrieved, and the client is responsible for filtering results and
   // showing pages of results. So, if user clicks checkboxes or changes
   // pages, should we send GWIS_Search requests for paginated and filtered
   // results?

   public class GWIS_Search extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Search');

      // *** Instance attributes

      // *** Constructor

      public function GWIS_Search(
         query:String,
         centerx:Number,
         centery:Number,
         callback_load:Function,
         callback_fail:Function) :void
      {
         var url:String = this.url_base('search');

         var query_filters:Query_Filters = new Query_Filters();
         query_filters.filter_by_text_smart = query;
         query_filters.centered_at.x = centerx;
         query_filters.centered_at.y = centery;

         url = query_filters.url_append_filters(url);

         var throb:Boolean = true;
         var qfs:Query_Filters = null;
         var update_req:Update_Base = null;
         super(url, this.doc_empty(), throb, qfs, update_req,
               callback_load, callback_fail);

         this.popup_enabled = true;
      }

      // ***

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

      //
      override public function equals(other:GWIS_Base) :Boolean
      {
         return false;
      }

      // Report problems to the user
      override protected function error_present(text:String) :void
      {
         PopUpManager.removePopUp(this.gwis_active_alert);
         Alert.show(text, 'No results found.');
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.controls.Alert;

   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_User_Preference_Put extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Put_Pref');

      // *** Instance attributes

      protected var show_errors:Boolean;

      // *** Constructor

      public function GWIS_User_Preference_Put(prefs:XML,
                                               show_errors:Boolean=false) :void
      {
         var url:String = this.url_base('user_preference_put');
         var doc:XML = this.doc_empty();
         var throb:Boolean = false;

         this.show_errors = show_errors;

         doc.appendChild(prefs);

         super(url, doc, throb);
      }

      // *** Instance methods

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

      //
      override protected function error_present(text:String) :void
      {
         // EXPLAIN: What causes this to happen?
         // EXPLAIN: Route manip adds show_errors, but [lb] is not sure why.
         if (this.show_errors) {
            m4_ERROR('EXPLAIN: error_present -- why is this?');
            // [lb] notes that this error message is silly: why would trying
            //      again guarantee success?
            // Alert.show('Unable to save preferences. '
            //            + 'It should work if you try again:\n\n'
            //            + text);
            super.error_present(text);
         }
         else {
            // FIXME: else, never show the error?
            m4_ERROR('error_present -- suppressing', text);
         }
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         m4_DEBUG('User preference saved successfully');
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_update_user;
      }

   }
}


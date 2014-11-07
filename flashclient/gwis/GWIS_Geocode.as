/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.controls.Alert;
   import mx.managers.PopUpManager;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_Geocode extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Geocode');

      // *** Instance variables

      public var addrs:Array;

      // *** Constructor

      public function GWIS_Geocode(
         addrs:Array,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         var url:String = this.url_base('geocode');
         var doc:XML = this.doc_empty();
         var addrs_xml:XML = <addrs/>;
         var addr:String;

         m4_ASSERT(addrs.length > 0);
         this.addrs = Collection.array_copy(addrs);
         m4_ASSERT(this.addrs.length > 0);

         for each (addr in addrs) {
            addrs_xml.appendChild(<addr addr_line={addr}/>);
            // FIXME: debug code for bug 1656 - put address line in URL too,
            // to see if it's something about the addresses.
            url += '&addr=' + encodeURI(addr);
         }

         doc.appendChild(addrs_xml);

         var throb:Boolean = true;
         var qfs:Query_Filters = null;
         var update_req:Update_Base = null;
         super(url, doc, throb, qfs, update_req,
               callback_load, callback_fail);

         this.popup_enabled = true;
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
         var equal:Boolean = false;
         var other_:GWIS_Geocode = (other as GWIS_Geocode);
         m4_ASSERT(this !== other_);
         equal = ((super.equals(other_))
                  && (Collection.array_eq(this.addrs, other_.addrs))
                  );
         m4_VERBOSE('equals?:', equal);
         return equal;
      }

      // Report problems to the user
      override protected function error_present(text:String) :void
      {
         // Don't call the base class (GWIS_Base), as it throws an Exception,
         // and we want to recover gracefully.
         // BUG 2715: Better errors: Can we tell the user why the address
         // wasn't found and what they can do to remedy the situation?
         if (this.gwis_active_alert !== null) {
            PopUpManager.removePopUp(this.gwis_active_alert);
            Alert.show(text, "Can't locate address(es)");
         }
      }

      //
      override public function on_cancel_cleanup() :void
      {
         m4_DEBUG('on_cancel_cleanup:', this.toString());
         // [lb] hasn't seen this happen but assumes if you logged out while
         // geocoding that since GWIS_Base.cancel does not, that the 'working'
         // dialog probably wouldn't go away...
         // Can we get away with just using an error handler?
         if (this.callback_fail !== null) {
            m4_DEBUG('on_cancel_cleanup: calling callback_fail');
            var rset:XML = null;
            this.callback_fail(this, rset);
         }
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         //return GWIS_Base.trumped_by_nothing;
         //return GWIS_Base.trumped_by_update_user;
         return GWIS_Base.trumped_by_update_user_or_branch;
      }

   }
}


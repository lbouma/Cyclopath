/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.utils.Stack_Id_Array;
   import utils.misc.Logging;

   public class GWIS_Stealth_Create extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Stlth_Cr');

      // *** Constructor

      //
      public function GWIS_Stealth_Create(
         item_sids:Stack_Id_Array,
         gia_use_sessid:Boolean=false,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         var url:String = this.url_base('stealth_create');
         if (int(gia_use_sessid)) {
            url += ('&guss=' + int(gia_use_sessid));
         }

         var doc:XML = this.doc_empty();

         // <ssec_sids>1,2,3,4,5</ssec_sids>
         Query_Filters.append_ids_compact(doc, 'ssec_sids', item_sids);

         var throb:Boolean = false;
         var query_filters:Query_Filters = null;
         var update_req:Update_Base = null;

         super(url, doc, throb, query_filters, update_req,
               callback_load, callback_fail);
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
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         m4_DEBUG('resultset_process: rset:', rset.toString());
         // NOTE: Caller processes results.
      }

   }
}


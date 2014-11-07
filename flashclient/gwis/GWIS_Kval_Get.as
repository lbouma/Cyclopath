/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_Kval_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/KVal_Get');

      // *** Instance attributes

      protected var kval_keys:Array = null;

      // *** Constructor

      //
      public function GWIS_Kval_Get(
         kval_keys:Array=null,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         var url:String = this.url_base('kval_get');

         this.kval_keys = kval_keys;
         if ((this.kval_keys !== null) && (this.kval_keys.length > 0)) {
            url += ('&vkey=' + this.kval_keys.join(','));
         }
         else {
            // MAGIC_NUMBER: 0 or blank will fetch cp_maint_beg and
            //                                     cp_maint_fin.
            url += ('&vkey=');
         }

         var doc:XML = this.doc_empty();

         var throb:Boolean = false;
         var query_filters:Query_Filters = null;
         var update_req:Update_Base = null;

         super(url, doc, throb, query_filters, update_req,
               callback_load, callback_fail);
      }

      // ***

      //
      override public function toString() :String
      {
         return super.toString() + ' / ' + kval_keys;
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
         //return false;
         var equal:Boolean = false;
         var other_:GWIS_Kval_Get = (other as GWIS_Kval_Get);
         m4_ASSERT(this !== other_);
         equal = ((super.equals(other_))
                  && (Collection.array_eq(this.kval_keys, other_.kval_keys))
                  );
         m4_VERBOSE('equals?:', equal);
         return equal;
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         m4_DEBUG('resultset_process: rset:', rset.toString());
         // NOTE: Caller processes the response via the callback.
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_nothing;
      }

   }
}


/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.utils.Stack_Id_Array;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_Item_Findability_Put extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Fbil_Put');

      // ***

      public var action_history_add:* = undefined;
      public var action_history_chg:* = undefined;
      public var action_squelch_pub:* = undefined;
      public var action_squelch_usr:* = undefined;

      // BUG_FALL_2013:
// FIXME: use_all_in_history is used by 'Clear All', right?
//        It's not implemented on the server...
      public var use_all_in_history:Boolean = false;

      // *** Constructor

      //
      public function GWIS_Item_Findability_Put(
         item_sids:Stack_Id_Array,
         action_obj:Object,
         // The object should have an action set.
         //  action_history_add:*=undefined
         //  action_history_chg:*=undefined
         //  action_squelch_pub:*=undefined
         //  action_squelch_usr:*=undefined
         //  use_all_in_history:Boolean=false
         callback_load:Function=null,
         callback_fail:Function=null)
            :void
      {
         var doc:XML = this.doc_empty();
         var url:String = this.url_base('item_findability_put');

         /*
         var fbil_xml:XML =
            <fbility
               fbil_hist={}
               sqel_pub=
               sqel_usr=
               hist_usr=
               />;
         */
         // <fbil_sids>1,2,3,4,5</fbil_sids>
         Query_Filters.append_ids_compact(doc, 'fbil_sids', item_sids);
         //doc.appendChild(fbil_xml);

         this.action_history_add = action_obj.action_history_add;
         this.action_history_chg = action_obj.action_history_chg;
         this.action_squelch_pub = action_obj.action_squelch_pub;
         this.action_squelch_usr = action_obj.action_squelch_usr;
         this.use_all_in_history = action_obj.use_all_in_history;

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
         var equal:Boolean = false;
         var other_:GWIS_Item_Findability_Put;
         other_ = (other as GWIS_Item_Findability_Put);
         m4_ASSERT(this !== other_);
         equal = ((super.equals(other_))
                  && (this.action_history_add == other_.action_history_add)
                  && (this.action_history_chg == other_.action_history_chg)
                  && (this.action_squelch_pub == other_.action_squelch_pub)
                  && (this.action_squelch_usr == other_.action_squelch_usr)
                  && (this.use_all_in_history == other_.use_all_in_history)
                  );
         // Base class prints this and other_ so just print our equals.
         m4_VERBOSE('equals?:', equal);
         return equal;
      }

      //
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);
         url = '';
         if (this.action_history_add != undefined) {
            url += '&hist_add=' + int(this.action_history_add);
         }
         if (this.action_history_chg != undefined) {
            url += '&hist_chg=' + int(this.action_history_chg);
         }
         if (this.action_squelch_pub != undefined) {
            url += '&sqel_pub=' + int(this.action_squelch_pub);
         }
         if (this.action_squelch_usr != undefined) {
            url += '&sqel_usr=' + int(this.action_squelch_usr);
         }
         if (this.use_all_in_history) {
            url += '&fbil_hist=' + int(this.use_all_in_history);
         }
         m4_ASSERT(this.data !== null);
         return super.finalize(url);
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         m4_DEBUG('resultset_process: rset:', rset.toString());

// FIXME: What to do? Tell widget that all was okay?
//        Maybe we need a callback...

      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_update_user;
      }

   }
}


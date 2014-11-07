/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: See results_style='rezs_name' and use Checkout; remove this file.

package gwis {

   import mx.collections.ArrayCollection;
   import mx.controls.Alert;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Item_User_Access;
   import utils.misc.Logging;

   // Gets a list of names and stack IDs of a particular item type from the
   // server for the current revision of a specified branch (though the
   // branch ID might be ignored, i.e., when getting a list of branches).

   public class GWIS_Item_History_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Itm_Hist');

      // ***

      public var stack_id:int;

      // *** Constructor

      public function GWIS_Item_History_Get(
         the_item:Item_User_Access,
         callback_load:Function=null,
         callback_fail:Function=null)
            :void
      {
         var url:String = this.url_base('item_history_get');

         m4_DEBUG('ctor: the_item:', the_item)

         var qfs:Query_Filters = new Query_Filters();
         qfs.only_stack_ids.push(the_item.stack_id);

         var doc:XML = this.doc_empty();
         var throb:Boolean = false;
         var upb:Update_Base = null;
         super(url, doc, throb, qfs, upb, callback_load, callback_fail);
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
         var other_:GWIS_Item_History_Get = (other as GWIS_Item_History_Get);
         m4_ASSERT(this !== other_);
         equal = ((super.equals(other_))
                  && (this.stack_id != other_.stack_id)
                  );
         m4_VERBOSE('equals?:', equal);
         return equal;
      }

      //
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);
         url = '';
         url += '&sid=' + this.stack_id;
         return super.finalize(url);
      }

   }
}


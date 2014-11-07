/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: See results_style='rezs_name' and use Checkout; remove this file.

package gwis {

   import mx.collections.ArrayCollection;
   import mx.controls.Alert;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   // Gets a list of names and stack IDs of a particular item type from the
   // server for the current revision of a specified branch (though the
   // branch ID might be ignored, i.e., when getting a list of branches).

   public class GWIS_Item_Names_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Itm_Noms');

      // *** Constructor

      public function GWIS_Item_Names_Get(update_req:Update_Base,
                                          item_type:String)
         :void
      {
         m4_ASSERT(item_type != '');
         var url:String = (this.url_base('item_names_get')
                           + '&ityp=' + item_type);
         m4_ASSERT(G.item_mgr.branch_id_to_load == 0);
         var throb:Boolean = true;
         var qfs:Query_Filters = null;
         super(url, this.doc_empty(), throb, qfs, update_req);
      }

      // *** Instance methods

      // NOTE: Derived classes should override resultset_process() to
      //       process the results.

      // ***

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

   }
}


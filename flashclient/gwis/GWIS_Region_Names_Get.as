/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: route reactions. This file is removed... why??
// FIXME: But in CcpV2, (a) we don't want to request data we don't need
//                          until we need it, and
//                      (b) we don't want to fetch all regions but instead
//                          want to have a filtering/layering mechanism
//                          (so we need the list of names separately).

// FIXME: See results_style='rezs_name' and use Checkout; remove this file.

package gwis {

   import flash.events.Event;
   import mx.collections.ArrayCollection;
   import mx.controls.Alert;

   import gwis.update.Update_Base;
   import utils.misc.Logging;

   public class GWIS_Region_Names_Get extends GWIS_Item_Names_Get {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rgn_Noms');

      // *** Constructor

      public function GWIS_Region_Names_Get(update_req:Update_Base=null)
         :void
      {
         super(update_req, 'region');
      }

      // *** Instance methods

      // Process the incoming result set.
      override protected function resultset_process(rset:XML) :void
      {
         m4_DEBUG('resultset_process');
         super.resultset_process(rset);
         G.map.regions_list = new Array();
         // EXPLAIN: What's the .. do again? Skips the XMLList and grabs the
         // first child?
         for each (var r:String in rset..@name) {
            G.map.regions_list.push(r);
         }
         m4_DEBUG2('dispatchEvent: regionsLoaded: G.map.regions_list.len:',
                   G.map.regions_list.length);
         G.item_mgr.dispatchEvent(new Event('regionsLoaded'));
         m4_DEBUG('resultset_process: done');
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// The GWIS_Checkout_Nonwiki_Download is an overloaded version of
// GWIS_Route_Get_New that serves up saved routes. This is a separate class
// because Flash doesn't allow multiple constructors, and it doesn't require
// the overloaded cleanup, error and resultset_process operations.

// FIXME: Rename this file? Get rid of it?

package gwis {

   import utils.misc.Logging;

   public class GWIS_Checkout_Nonwiki_Download
         extends GWIS_Checkout_Nonwiki_Items {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/JQ_Mrg_D');

      // *** Constructor

      public function GWIS_Checkout_Nonwiki_Download(
         work_item_download_type:String,
         work_item_stack_id:int)
      {
         super(work_item_download_type);
         this.query_filters.only_stack_ids.push(work_item_stack_id);
      }

      // *** Instance methods

      //
      override protected function resultset_process(rset:XML) :void
      {
         m4_WARNING('is this expected? rset:', rset.toXMLString());
         // FIXME: We don't need to call base class, right?
      }

   }
}


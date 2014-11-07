/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.panel_util.Paginator_Widget;

   public class GWIS_Checkout_Count extends GWIS_Checkout_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~Co_COUNT');

      // ***

      protected var paginator:Paginator_Widget;

      // *** Constructor

      //
      public function GWIS_Checkout_Count(
         item_type:String,
         paginator:Paginator_Widget=null,
         qfs:Query_Filters=null,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         m4_DEBUG('GWIS_Checkout_Count called');

         var item_type:String = item_type;

         // The users of this command -- discussions, reactions, analysis,
         // shapefiles, route library -- all have lists that show items from
         // the current revision. (EXPLAINED: We could support historic counts
         // but there's no demand.)
         // Skipping: G.map.rev_viewport/G.map.rev_workcopy
         var discrev:utils.rev_spec.Base = new utils.rev_spec.Current();

         if (qfs === null) {
            qfs = new Query_Filters();
         }
         qfs.pagin_total = true;
         // We can just clear include_item_stack to save the server some time
         // (in case the caller accidentally left it specified from a previous
         // GWIS command, since many times GWIS_Checkout_Count immediately
         // follows GWIS_Checkout_X). If this isn't couth, the server will
         // assert.
         qfs.include_item_stack = false;

         this.paginator = paginator;

         var update_req:Update_Base = null;
         var resp_items:Array = null;
         super(item_type, resp_items, discrev, qfs,
               update_req, callback_load, callback_fail);
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         // Skipping: super.resultset_process(rset);
         //
         // <data major="not_a_working_copy" gwis_version="2"
         //       semiprotect="0" rid_max="15747">
         //   <items ityp="merge_job">
         //     <item_count>
         //       <row count="3"/>
         //       <!-- For route reactions: -->
         //       <row count="3" likes="3" dislikes="3"/>
         //     </item_count>
         //   </items>
         // </data>
         //
         // These all work:
         //  m4_DEBUG('1:', rset[0][0][0]..@count)
         //  m4_DEBUG('2:', rset['items']..@count)
         //  m4_DEBUG('3:', rset..@count)
         //  m4_DEBUG('4:', rset..@count)
         //  m4_DEBUG('5:', rset..item_count..@count)
         // Tell the Paginator how many total records the user can expect.
         // Same as: this.paginator.records_total_count = int(rset..@count);:
         this.paginator.records_total_count
            = int(rset.items.item_count.row.@count);
         // Paginator calls this: this.paginator.update_pagination_text();
         //m4_VERBOSE('resultset_process: rset:', rset.toString());
         m4_VERBOSE2('resultset_process: records_total_cnt:',
                     this.paginator.records_total_count);
      }

   }
}


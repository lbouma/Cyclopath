/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.collections.ArrayCollection;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.panel_util.Paginator_Widget;

   public class GWIS_Checkout_Nonwiki_Items extends GWIS_Checkout_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~Co_Nonwiki');

      // *** Constructor

      //
      public function GWIS_Checkout_Nonwiki_Items(
         item_type:String,
         qfs:Query_Filters=null,
         paginator:Paginator_Widget=null,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         m4_DEBUG('GWIS_Checkout_Nonwiki_Items called');

         var item_type:String = item_type;

         // The users of this command -- thread, analysis, shapefiles -- only
         // care about items at the current revision. (EXPLAINED: We could
         // support historic counts but there's no demand.) Oh, wait, that's
         // not the real reason: Nonwiki items are revisioned. They're all
         // marked valid_start_rid:valid_until_rid == 1:rid_inf.
         // Skipping: G.map.rev_viewport/G.map.rev_workcopy
         var discrev:utils.rev_spec.Base = new utils.rev_spec.Current();

         if (qfs === null) {
            qfs = new Query_Filters();
         }
         if (paginator !== null) {
            paginator.configure_query_filters(qfs);
         }
         // MAGIC NUMBERSTRING.
         // FIXME: Is the use of this filter cool?
         // FIXME: Should probably use qfs.item_type_layer or somethin

         var update_req:Update_Base = null;
         var resp_items:Array = null;
         super(item_type, resp_items, discrev, qfs,
               update_req, callback_load, callback_fail);
      }

   }
}


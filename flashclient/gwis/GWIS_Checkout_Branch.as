/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.events.ResizeEvent;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.feats.Branch;
   import utils.misc.Counter;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class GWIS_Checkout_Branch extends GWIS_Checkout_Versioned_Items {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~Chkout_Brch');

      // *** Constructor

      // Constructor
      public function GWIS_Checkout_Branch(update_req:Update_Base) :void
      {
         m4_VERBOSE('GWIS_Checkout_Branch');

         var buddy_ct:Counter = null;
         var currev:utils.rev_spec.Base = new utils.rev_spec.Current();
         var resp_items:Array = null;
         var qfs:Query_Filters = new Query_Filters();

         // Get the branch's access_style.
         // BUG nnnn: Getting access_style for branch unnecessary unless we
         //           want to implement the "permissive" access widget.
         qfs.include_item_stack = true;
         
         super(Branch.class_item_type, // 'branch'
               currev, buddy_ct, qfs, update_req, resp_items);

         // 2013.04.05: The server used to send just the branch specifed as the
         // branch_id, i.e., it would filter on stack id using the branch id.
         // But this is opposite of what normally happens with items: we find
         // all items unless expressly filtering. So now the server treats
         // branches like items, and expects us to filter-by when we mean it.
         // * To get a list of branches, use GWIS_Checkout_Versioned_Items.
         // * Use GWIS_Checkout_Branch to get one branch -- the active branch
         //   -- and we'll set the filters accordingly.
         // Note that we do this after super() so that this.branch_id is set.
         if (this.branch_id > 0) {
            qfs.only_stack_ids.push(this.branch_id);
            m4_DEBUG('GWIS_Checkout_Branch: only_stack_ids:', this.branch_id);
         }
         else {
            m4_DEBUG('GWIS_Checkout_Branch: empty only_stack_ids');
            // This is a bit of a hack. Or not, it's coding by convention: we
            // know that the server orders by ascending stack ID, and we know
            // that the basemap has the lowest stack ID, so just ask for one
            // record and we'll get just the basemap. Otherwise, if we don't
            // specify anything, we'll get all the branches that the user can
            // see.
            qfs.pagin_count = 1;
         }
      }

      // NOTE: The reason for this class was to house maxrid_process_current
      //       here, so it only got called on the first GWIS call -- which
      //       gets the basemap branch. But the fcn. has since been moved back
      //       to a parent class. Please see the comment above the function in
      //       its new place for the reasoning.

   }
}


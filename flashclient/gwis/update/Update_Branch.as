/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis.update {

   //import flash.geom.Rectangle;
   //import flash.utils.Dictionary;

   import gwis.GWIS_Checkout_Branch;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class Update_Branch extends Update_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_Branch');

      public static const on_completion_event:String = 'updatedBranch';

      // *** Constructor

      public function Update_Branch()
      {
         super();
      }

      // *** Init methods

      //
      override protected function init_update_steps() :void
      {
         this.update_steps.push(this.update_step_branch_head_rev);
      }

      // *** Internal interface

      //
      protected function update_step_branch_head_rev() :void
      {
         m4_DEBUG('update_step_branch_head_rev: rev:', this.rev);
         var req:GWIS_Checkout_Branch;
         // Queue a request to get the branch head revision ID
         // FIXME Make sure Branch.stack_id is null
         // FIXME What if this is a diff? Do something like
         //       Update_Viewport_Base.gwis_fetch_rev_create ?
         //       NO- this is the branch head...
         m4_ASSERT((this.rev is utils.rev_spec.Current)
                   || (this.rev is utils.rev_spec.Pinned));
         m4_ASSERT(this.rev is utils.rev_spec.Current);
         req = new GWIS_Checkout_Branch(this);
         this.requests_add_request(req, this.on_process_branch);
         // After sending the GWIS_Base request but before processing the
         // response, purge everything about the branch and revision
         // FIXME How does this work w/ the GetItem call above?? Really clear
         //       branch item? Overwrite it instead? Hrmm...
         // FIXME Does update_viewport_items do same? probably a no-op, but the
         //       branch might get cleared
         // FIXME Is there a quicker way to discard items? (Can we just
         //       null'ify the data structures if changing branches, and not
         //       go through item by item?)
         // FIXME: Callees should call G.map.discard_and_update(), so maybe
         //        items_discards, etc., end up being no-ops?
         //
         // FIXME: Destroy GrAC mgr stuff here, too? It's currently done in
         //        G.map.discard_and_update. Just seems we shouldn't require
         //        one to call discard_and_update before calling update_branch.
         this.work_queue_add_unit(this.map.items_discard,
                                  [null, false], true);
         this.work_queue_add_unit(this.map.tiles_discard,
                                  [null, false], true);
         this.work_queue_add_unit(this.map.geofeatures_redraw_and_relabel,
                                  null, true);
      }

      //
      protected function on_process_branch() :void
      {
         m4_DEBUG('on_process_branch');
         //m4_ASSERT(G.item_mgr.active_branch !== null);
         // FIXME: Set the public basemap stac ID?
         //Branch.ID_PUBLIC_BASEMAP = 0;
         this.map.update_revision();
         // NOTE: branchChange is called earlier, on the branch object's
         //       init_add or init_update, triggered by gwis_complete_callback.
      }

   }
}


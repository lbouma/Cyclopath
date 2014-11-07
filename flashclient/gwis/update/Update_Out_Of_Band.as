/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis.update {

   import flash.utils.Dictionary;

   import gwis.GWIS_Base;
   import gwis.Update_Manager;
   import utils.misc.Collection;
   import utils.misc.Introspect;
   import utils.misc.Logging;

   public class Update_Out_Of_Band extends Update_Supplemental {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_OO_Band');

      public static const on_completion_event:String = null;

      // *** Instance attributes

      public var gwis_req:GWIS_Base = null;

      // *** Constructor

      public function Update_Out_Of_Band(gwis_req:GWIS_Base)
      {
         super();
         this.gwis_req = gwis_req;
      }

      // ***

      //
      public function toString() :String
      {
         return String(this.gwis_req);
      }

      //
      override public function toString_Terse() :String
      {
         return this.gwis_req.gwis_id;
      }

      // ***

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return this.gwis_req.allow_overlapped_requests;
      }

      //
      override public function get cancelable() :Boolean
      {
         return this.gwis_req.cancelable;
      }

      // SKIPPING: override protected function canceled_set().
      //           this.update_step_oob() calls requests_add_request(), which
      //           adds this.gwis_req to this.resp_lookup, which base class
      //           uses to cancel our req.; skipping: this.gwis_req.cancel().

      //
      override public function configure(mgr:Update_Manager) :void
      {
         m4_VERBOSE('configure: mgr:', mgr);
         super.configure(mgr);
         this.gwis_req.configure(this);
      }

      //
      override public function equals(other:Update_Base) :Boolean
      {
         // The base class says two objects are equal if they are the same
         // class and have the same username, branch, and revision.
         var equal:Boolean = super.equals(other);
         if (equal) {
            // Some out-of-band requests can be sent in parallel -- like
            // getting link_values for a geofeature or an attachment -- but
            // some oob requests must be serialized. We let the request class
            // decide.
            var update_oob:Update_Out_Of_Band = (other as Update_Out_Of_Band);
            m4_VERBOSE('equals: Checking gwis_req equality.');
            m4_VERBOSE('equals: update_oobs:', this, '/', update_oob);
            m4_VERBOSE2('equals:   gwis_reqs:', this.gwis_req, '/',
                        update_oob.gwis_req);
            equal = this.gwis_req.equals(update_oob.gwis_req);
         }
         return equal;
      }

      //
      override protected function init_update_steps() :void
      {
        this.update_steps.push(this.update_step_oob);
      }

      //
      override public function is_similar(other:Update_Base) :Boolean
      {
         var is_similar:Boolean = super.is_similar(other);
         if (is_similar) {
            // This and other are the same type of Update_Base class, so check
            // if the GWIS_Base objects are similar.
            var update_oob:Update_Out_Of_Band = (other as Update_Out_Of_Band);
            is_similar = this.gwis_req.is_similar(update_oob.gwis_req);
         }
         return is_similar;
      }

      //
      override public function is_trumped_by(update_obj:Update_Base) :Boolean
      {
         var update_cls:Class = Introspect.get_constructor(update_obj);
         return this.gwis_req.is_trumped_by(update_cls);
      }

      //
      protected function on_process_oob() :void
      {
         m4_DEBUG('on_process_oob');
         // The gwis_req already had its completion routine called, so nothing
         // to do. Not needed: this.map.callLater(this.gwis_complete_stages);
      }

      //
      protected function update_step_oob() :void
      {
         m4_DEBUG('update_step_oob');
         this.requests_add_request(this.gwis_req, this.on_process_oob);
         // NOTE: No need for a work queue unit, i.e., work_queue_add_unit()
      }

// FIXME: Move this gunk. Or delete it.

      // *** Helper fcns -- Process GWIS_Base responses

      // Step 4 -- Get the History Browser
      // FIXME Should this be lazy-loaded instead, i.e., when user clicks
      //       History?
      /*
      protected function update_step_history_browser() :void
      {
         // FIXME These requests are not part of resp_* lookups
         m4_DEBUG('update_step_history_browser');

         var hb:Panel_Recent_Changes = G.tabs.changes_panel;
// FIXME Comment doesn't match trunk?
         // We got the list of geofeatures and their tags, so update the filter
         // list (Fixes: Bug 883)
         m4_DEBUG('...Updating tag_filter_list');
// FIXME Does this do anything now? It uses Tag.visible_tags_ordered_array
G.tabs.settings.settings_panel.tag_filter_list.update_tags_list();
         // Refresh the History Browser if user filtering by bbox.
         // This request comes last for no particular reason, other than it
         // might speed up map load time (which I guess is a particular
         // reason); if the user is actually looking at the History Browser,
         // maybe we should send this request earlier?
FIXME: move this to update_working_copy?
       and/or as something that completion of update_viewport_* triggers
       i.e., update_supplemental but not update_out_of_band/gwis_base

just use this.view_rect instead of this.rect_new_view
         if (hb.rfil.selection == hb.rfil_viewport
             // FIXME: this.rect_new_view is Update_Viewport_Base
             && !this.rect_new_view.eq(hb.bbox)) {
            m4_DEBUG('...Updating history browser');
            hb.refetch();
         }
         // FIXME Not where when this is appropriate
         m4_DEBUG('...Updating invitation_bar');
         G.app.invitation_bar.update();
         // FIXME This goes elsewhere, and we need to resolve what to do with
         //       selected but not-visible geofeatures
// FIXME Dont discard selected items that are out of viewport
         m4_DEBUG('...Calling panels_mark_dirty on Recent Changes');
         G.panel_mgr.panels_mark_dirty([G.tabs.changes_panel]);
      }
*/


      //
      override protected function use_throbberer() :Boolean
      {
         m4_DEBUG3('use_throbberer: this.throb:', this.gwis_req.throb,
                   '/ resp_lookup_sets.len:',
                   Collection.dict_length(this.resp_lookup_sets.length));
         return this.gwis_req.throb;
      }

   }
}


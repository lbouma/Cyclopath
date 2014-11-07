/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// MEH: This class should really be an MXML widget.
//      Currently, it manages some controls that main.mxml
//      directly declares.

package views.panel_history {

   import flash.events.Event;

   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class History_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('History_Mgr');

      //public var changes_panel:Panel_Recent_Changes;

      // *** Constructor

      //
      public function History_Manager() :void
      {
         m4_DEBUG('Welcome to the History_Manager!');

         G.panel_mgr.panel_register(G.tabs.changes_panel);

         m4_DEBUG('ctor: addEventListener: revisionChange');
         G.item_mgr.addEventListener('revisionChange',
                                     this.on_revision_change);

//         this.on_revision_change();
      }

      // ***

      //
      protected function on_revision_change(event:Event=null) :void
      {
         m4_DEBUG('on_revision_change');
         this.history_browser_ui_update();
      }

      // ***

      // Enable or disable various features in the Recent Changes panel, as
      // appropriate.
      public function history_browser_ui_update() :void
      {
         // FIXME: How often is this fcn. called? I.e., does it update the
         //        panel, even when it's not being shown? Does it update even
         //        when it doesn't need to?
         m4_DEBUG('history_browser_ui_update');

         if (G.tabs.changes_panel !== null) {
            this.history_browser_ui_update_();
         }
         else {
            m4_WARNING('hist_browser_ui_update: G.tabs.changes_panel is null');
         }
      }

      // MAYBE: Move this fcn. to Panel_Recent_Changes.
      public function history_browser_ui_update_() :void
      {

         if (!(G.map.rev_viewport is utils.rev_spec.Pinned)) {

      // Wrong: G.view_mode.activate();
      // But should we still change modes?
            if ((G.app.mode !== G.edit_mode)
                && (G.app.mode !== G.view_mode)) {
               m4_ASSERT(G.app.mode === G.hist_mode);
               G.view_mode.activate();
            }

            G.app.rev_note_container.visible = false;
         }
         else {

            var rev_hist:utils.rev_spec.Historic
               = (G.map.rev_viewport as utils.rev_spec.Historic);
            var rev_diff:utils.rev_spec.Diff
               = (G.map.rev_viewport as utils.rev_spec.Diff);

            // G.map.rev_viewport is utils.rev_spec.Pinned -- a historic
            // revision.

            if (G.app.mode !== G.hist_mode) {
               m4_ASSERT((G.app.mode === G.edit_mode)
                         || (G.app.mode === G.view_mode));
               G.hist_mode.activate();
            }

            G.app.rev_note_container.visible = true;

            if (G.map.zoom_is_vector()) {
               if (rev_hist !== null) {
                  G.app.diff_toggle.visible = false;
                  G.app.diff_toggle.includeInLayout = false;
                  G.app.rev_note.text =
                     'Map shows revision ' + rev_hist.rid_old + '.';
               }
               else {
                  m4_ASSERT(rev_diff !== null);
                  G.app.diff_toggle.visible = true;
                  if (rev_diff.rid_old == rev_diff.rid_new - 1) {
                     G.app.rev_note.text
                        = ('Map shows changes made in revision '
                           + rev_diff.rid_new + '.');
                     G.app.diff_toggle.dataProvider
                        = ['Before', 'After', 'Both',];
                  }
                  else {
                     G.app.rev_note.text = ('Map compares revisions '
                                            + rev_diff.rid_old + ' and '
                                            + rev_diff.rid_new + '.');
                      G.app.diff_toggle.dataProvider
                         = [rev_diff.rid_old, rev_diff.rid_new, 'Both',];
                  }
                  G.app.diff_toggle.selectedIndex = G.map.diff_show;
               }
            }
            else {
               G.app.diff_toggle.visible = false;
               G.app.diff_toggle.includeInLayout = false;
// FIXME: Statewide UI: These names are too wide for a Label.
//                      Use Text and htmlText...
               if (rev_hist !== null) {
                  G.app.rev_note.text = (
      'Map shows current revision. Zoom in to view revision '
                     + rev_hist.rid_old + '.');
               }
               else {
                  m4_ASSERT(rev_diff !== null);
                  if (rev_diff.rid_old == rev_diff.rid_new - 1) {
                     G.app.rev_note.text = (
      'Map shows current revision. Zoom in to view changes made in revision '
                        + rev_diff.rid_new + '.');
                  }
                  else {
                     G.app.rev_note.text = (
      'Map shows current revision. Zoom in to compare revisions '
                        + rev_diff.rid_old + ' and '
                        + rev_diff.rid_new + '.');
                  }
               }
            }
         }
      }

      // ***

   }
}


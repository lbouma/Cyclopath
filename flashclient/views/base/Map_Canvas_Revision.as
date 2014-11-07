/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Part of the Map class hierarchy.

package views.base {

   import flash.events.Event;

   import gwis.update.Update_Viewport_Items;
   import items.Item_Revisioned;
   import items.Item_Versioned;
   import utils.geom.MOBR_DR_Array;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.panel_history.Panel_Recent_Changes;
   import views.panel_items.Panel_Item_Versioned;

   public class Map_Canvas_Revision extends Map_Canvas_Viewport {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('MC_Revision');

      // *** Class attributes

      // We use three attributes to track revisions:
      // 1. The desired revision of the user's working copy.
      // 2. The actual revision of the user's working copy.
      //    Callers clear actual and set desired when getting a fresh rev.
      // 3. The actual revision of the server, which is >= user's working copy.

      // 2013.04.08: I [lb] added rev_workcopy a while ago to complement
      // rev_viewport. Maybe the idea was that you could look at a historic
      // revision and also maintain your working revision (like dirty items?
      // but we tell users to save before changing revisions or branches, so
      // why add such a feature? so you can switch back and forth btw. historic
      // and working?). Anyway, other than that idea, I can't remember what the
      // point is/was.
      //
      // Nowadays, rev_loadnext is set when changing to a different revision.
      protected var rev_loadnext_:utils.rev_spec.Base = null;
      //
      // Once we start loading the map, we'll set rev_viewport.
      protected var rev_viewport_:utils.rev_spec.Base = null;
      //
      // And rev_workcopy is just a wrapper around rev_viewport to return a
      // utils.rev_spec.Working object, maybe (if viewport is not Historic).
      // Don't need: protected var rev_workcopy_:utils.rev_spec.Working = null;
      //
      // Finally, we track the branch mainline's revision as saved on the
      // server. Whenever users save, the mainline revision increments, and
      // then we can ask the user if you want to update their working copy.
      // FIXME: The mainline isn't quite implemented yet. Never has been. So
      //        partially is better than nothingally, right?
      //        And note: rev_mainline only matters when rev_workcopy-
      //        rev_viewport is utils.rev_spec.Working (not Historic).
      public var rev_mainline:utils.rev_spec.Follow = null;
      //
      // MAYBE: This is added by route reactions. We could maybe replace String
      //        with an Enumeration class. Or maybe we can use rev_* attribute
      //        instead.
      // Map Modes (Reaction Modes)
      [Bindable] public var rmode:String = Conf.map_mode_normal;

      protected var _diff_show:int = Conf.hb_both;

      protected var remember_selected:Set_UUID = null;

      // *** Constructor

      public function Map_Canvas_Revision()
      {
         // On boot, we don't have any clue what the latest revision ID is, so
         // use Current. The first GWIS response will include the latest
         // revision ID, which we'll use to update this.rev_workcopy and to
         // set this.rev_viewport.
         this.rev_loadnext_ = new utils.rev_spec.Current();
         // Skipping: this.rev_viewport_
         m4_DEBUG('ctor: rev_loadnext:', this.rev_loadnext.friendly_name);
         m4_DEBUG2('ctor: rev_viewport:',
                   (this.rev_viewport !== null) ? 'yes' : 'no');
         m4_DEBUG2('ctor: rev_workcopy:',
                   (this.rev_workcopy !== null) ? 'yes' : 'no');

         super();
      }

      // *** Getters and setters

      // Whether to display old/new byways/points
      public function get diff_show() :int
      {
         return this._diff_show;
      }

      //
      public function set diff_show(ds:int) :void
      {
         m4_DEBUG('diff_show: ds:', ds);
         this._diff_show = ds;
         G.map.geofeatures_redraw();
         G.map.geofeatures_relabel();
         // FIXME: Can user search a diff?: G.map.search_results_draw();
      }

      // ***

      //
      public function get rev_loadnext() :utils.rev_spec.Base
      {
         return this.rev_loadnext_;
      }

      //
      public function set rev_loadnext(rev:utils.rev_spec.Base) :void
      {
         m4_ASSERT(rev !== null);

         // We'll clear rev_viewport until we hear a first peep from pyserver.
         if (this.rev_viewport !== null) {
            m4_DEBUG2('rev_loadnext: old rev_viewport:',
                      this.rev_viewport.friendly_name);
            this.rev_viewport = null;
         }
         // else, bootstrapping.

         if ((this.rev_loadnext !== null)
             && (this.rev_loadnext == rev)) {
            m4_WARNING2('Unexpected: rev:', rev.friendly_name,
               '/ rev_loadnext:', this.rev_loadnext.friendly_name);
         }

         this.rev_loadnext_ = rev;
         // Don't clear the mainline, since some widgets want the latest
         // revision ID.
         //   this.rev_mainline = null;

         // 2012.10.04: Route Feedback Drag adds map.mode.
         this.rmode = Conf.map_mode_normal;
         //this.rmode = '';

         // This seems like as good a place as any to close panels associated
         // with the map...
         // But first see if the user is looking at a panel we're about to
         // close. Our algorithm to find the "next" panel to display when we
         // close the active panel doesn't support closing multiple panels in
         // the same frame. So just switch panels first if we have to.
         var reset_active_panel:Boolean = false;
         if (G.panel_mgr.effectively_active_panel is Panel_Item_Versioned) {
            m4_TALKY('rev_loadnext: clearing effectively_active_panel/1');
            G.panel_mgr.effectively_active_panel = null;
            reset_active_panel = true;
         }
         var idx:int = G.app.side_panel.numChildren - 1;
         while (idx >= 0) {
            var item_panel:Panel_Item_Versioned = null;
            item_panel = (G.app.side_panel.getChildAt(idx)
                          as Panel_Item_Versioned);
            if (item_panel !== null) {
               // Close all item details panels.
               m4_TALKY('rev_loadnext: closing item panel: idx:', idx);
               G.app.side_panel_tabs.close_panel_at_index(idx);
            }
            idx -= 1;
         }
         if (reset_active_panel) {
            // Should we go to revision panel or to get new route panel?
            m4_TALKY('rev_loadnext: clearing effectively_active_panel/2');
            G.panel_mgr.effectively_active_panel = null;
            //G.panel_mgr.panel_activate(G.app.routes_panel);
            //G.panel_mgr.panel_activate(G.tabs.changes_panel);
            m4_TALKY2('rev_loadnext: panel_activate:',
                      G.tabs.route.find_panel);
            G.panel_mgr.panel_activate(G.tabs.route.find_panel);
         }

         // MAYBE: See Panel_Recent_Changes, which calls
         //          G.app.routes_panel.routes_looked_at
         //             .history_routes.toggle_all_check(false);
         //          G.app.routes_panel.routes_library
         //             .search_routes.toggle_all_check(false);
         //        [lb] is not saying we should call those here but we might
         //        need to wire a dispatchEvent to trigger 'em.

         // No: Make callers do this: this.discard_and_update();
      }

      //
      public function get rev_viewport() :utils.rev_spec.Base
      {
         return this.rev_viewport_;
      }

      //
      public function set rev_viewport(rev:utils.rev_spec.Base) :void
      {
         // We expect a Diff, Historic, or Working revision.
         m4_ASSERT(!(rev is utils.rev_spec.Current));

         if (rev === null) {
            this.rev_viewport_ = null;
            this.rev_loadnext_ = null;
            //this.rmode = '';
            this.rmode = Conf.map_mode_normal;

            m4_DEBUG('rev_viewport: set rev_viewport null');
         }
         else if (this.rev_viewport_ != rev) {

            this.rev_viewport_ = rev;
            this.rev_loadnext_ = null;

            // 2012.10.04: Route Feedback Drag adds map.mode.
            // MAYBE: Do we still need this.mode? Can't we use rev_viewport?
            //if (this.rev_loadnext is utils.rev_spec.Working) {
            if ((this.rev_viewport_ is utils.rev_spec.Working)
                || (this.rev_viewport_ is utils.rev_spec.Historic)) {
               this.rmode = Conf.map_mode_normal;
            }
            else {
               m4_ASSERT(this.rev_viewport_ is utils.rev_spec.Diff);
               this.rmode = Conf.map_mode_historic;
            }

            // Compare: Update_Revision.updatedRevision and revisionChange.
            var bubbles:Boolean = false;
            G.item_mgr.dispatchEvent(new Event('revisionChange', bubbles));

            m4_DEBUG('rev_viewport: new rev_viewport:', this.rev_viewport_);
         }
         else {
            m4_WARNING('EXPLAIN: rev_viewport: revision already set:', rev);
            m4_WARNING(Introspect.stack_trace());
            m4_ASSERT(this.rev_loadnext_ === null);
         }
      }

      //
      // MAYBE: Have this fcn. return utils.rev_spec.Working (or null if not)
      //        and make new rev_loadnext ??
      public function get rev_workcopy() :utils.rev_spec.Working
      {
         return (this.rev_viewport_ as utils.rev_spec.Working);
      }

      //
      public function set rev_workcopy(rev:utils.rev_spec.Working) :void
      {
         m4_DEBUG2('rev_workcopy: rev_viewport:',
                   (rev !== null) ? rev.friendly_name : 'null');
         // A caller calls this fcn. to indicate the start of a working copy.
         this.rev_viewport = rev;
         this.rev_mainline = new utils.rev_spec.Changed(
                                    G.map.rev_workcopy.rid_last_update,
                                    G.map.rev_workcopy.rid_last_update);
      }

      // *** Instance methods

      //
      override protected function discard_preserve() :void
      {
         // MAYBE/BUG nnnn: Restore all active item panels. For now, just the
         //                 active one. (It's simple to set a collection of
         //                 items' item.selected = true, but for other panels,
         //                 whose items are not selected, we'd have to do a
         //                 little more work, e.g., make a panel of the proper
         //                 item type, fiddling with items_selected and
         //                 feats_selected, and then adding the panel to the
         //                 panel manager via G.panel_mgr.panel_register.)
         var item_panel:Panel_Item_Versioned = (
            G.panel_mgr.effectively_active_panel
            as Panel_Item_Versioned);
         if (item_panel !== null) {
            this.remember_selected = new Set_UUID();
            var item:Item_Versioned;
            for each (item in item_panel.items_selected) {
               //this.remember_selected.add(item.stack_id);
               this.remember_selected.add(item);
            }
         }
         m4_DEBUG3('discard_reset: no. remember_selected:',
                   ((this.remember_selected !== null)
                   ? this.remember_selected.length : 'null'));

         super.discard_preserve();
      }

      // Reset features and related infrastructure.
      override protected function discard_reset() :void
      {
         // Setting rev_loadnext triggers a map reset. Tell the update
         // callbacks to call us after all the items are loaded.
         if ((this.remember_selected !== null)
             && (this.remember_selected.length > 0)) {
            G.item_mgr.addEventListener(
               Update_Viewport_Items.on_completion_event,
               this.on_updated_items);
         }

         // Callers should setup this.rev_workcopy before calling this fcn.
         if (this.rev_loadnext === null) {
            m4_WARNING('Unexpected: rev_loadnext is null; using Current');
            // DEVS: If this is firing, before calling discard_and_update
            //       you should mark your rev_loadnext.
            m4_ASSERT_SOFT(false);
            this.rev_loadnext = new utils.rev_spec.Current();
         }
         else {
            m4_DEBUG2('discard_reset: init: rev_loadnext:',
                      this.rev_loadnext.friendly_name);
            this.rev_loadnext = this.rev_loadnext;
         }

         super.discard_reset();
      }

      // Look at the active revision(s).
      // This is only called from main.mxml, by the "Look At" button
      public function lookat_rev() :void
      {
         var revs:MOBR_DR_Array = new MOBR_DR_Array();
         var hb:Panel_Recent_Changes = G.tabs.changes_panel;
         var rev_diff:utils.rev_spec.Diff;
         if (this.rev_viewport is utils.rev_spec.Diff) {
            rev_diff = (this.rev_viewport as utils.rev_spec.Diff);
            m4_ASSERT(rev_diff.rid_new in hb.gs_cache);
            revs.push(hb.gs_cache[rev_diff.rid_new]);
            if (rev_diff.rid_old < rev_diff.rid_new - 1) {
               m4_DEBUG('lookat_rev: rev_diff.rid_old:', rev_diff.rid_old);
               m4_DEBUG('lookat_rev: hb.gs_cache:', hb.gs_cache);
               m4_ASSERT(rev_diff.rid_old in hb.gs_cache);
               revs.push(hb.gs_cache[rev_diff.rid_old]);
            }
         }
         else if (this.rev_viewport is utils.rev_spec.Historic) {
            var rid_old:int = (this.rev_viewport
                               as utils.rev_spec.Historic).rid_old;
            m4_DEBUG('lookat_rev: rev_hist.rid_old:', rid_old);
            m4_DEBUG('lookat_rev: hb.gs_cache:', hb.gs_cache);
            m4_ASSERT(rid_old in hb.gs_cache);
            revs.push(hb.gs_cache[rid_old]);
         }
         else {
            m4_ASSERT(false);
         }
         this.lookat(revs);
      }

      //
      protected function on_updated_items(ev:Event) :void
      {
         m4_DEBUG2('on_updated_items: updatedItems /',
                   'Update_Viewport_Items.on_completion_event');

         G.item_mgr.removeEventListener(
            Update_Viewport_Items.on_completion_event, this.on_updated_items);

         if (this.remember_selected === null) {
            m4_WARNING('on_updated_items: remember_selected is null');
         }
         else if (this.remember_selected.length == 0) {
            m4_WARNING('on_updated_items: remember_selected is empty');
         }
         else {
            //var stack_id:int;
            //for each (stack_id in this.remember_selected) {
            var old_item:Item_Versioned;
            var tmp_item:Item_Revisioned;
            var new_item:Item_Versioned;
            var ignore_deleted:Boolean = true;
            for each (old_item in this.remember_selected) {

            // FIXME/BUG nnnn: We'll find Geofeatures in the viewport -- so if
            // the user has a Geofeature selected outside of the viewport, it's
            // not found and not re-selected. Likewise, a selected note is not
            // reselected, because notes are only loaded when you click an
            // item. So we'd have to Checkout the missing items, and then
            // select them in the loaded callback... the correct solution
            // might be for this fcn., on_update_items, to run once after
            // Update_Revision, and to run the Supplemental checkout command,
            // and then to set the item selected on checkout success.

               tmp_item = Item_Revisioned.item_find_new_old_any(
                                       old_item, ignore_deleted);
               new_item = (tmp_item as Item_Versioned);
               if (new_item !== null) {
                  m4_TALKY('on_updated_items: selecting new_item:', new_item);
                  new_item.set_selected(true, /*nix=*/false, /*solo=*/false);
               }
               else {
                  m4_TALKY2('on_updated_items: new_item not found: old_item:',
                            old_item);
               }
            }
         }
         this.remember_selected = null;
      }

   }
}


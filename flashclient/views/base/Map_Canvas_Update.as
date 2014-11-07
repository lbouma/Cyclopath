/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Part of the Map class hierarchy.

package views.base {

   import flash.events.Event;
   import flash.utils.Dictionary;

   import assets.skins.*;
   import gwis.GWIS_Base;
   import gwis.Update_Manager;
   import gwis.update.Update_Branch;
   import gwis.update.Update_Revision;
   import gwis.update.Update_User;
   import gwis.update.Update_Viewport_Items;
   import gwis.update.Update_Viewport_Tiles;
   import gwis.update.Update_Working_Copy;
   //import utils.misc.Introspect;
   import utils.misc.Logging;

   // This class handles interaction with Update_Manager, which coordindates
   // communicating with the server.

   public class Map_Canvas_Update extends Map_Canvas_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('MapCanvasUpd');

      // *** Instance variables

      public var update_mgr:Update_Manager;

      protected var updates_out:Dictionary;

      public var basics_loaded:Boolean = false;

      // *** Constructor

      public function Map_Canvas_Update()
      {
         super();
         this.update_mgr = new Update_Manager(this);
      }

      // *** Update_Manager convenience functions

      //
      public function update_branch() :void
      {
         m4_DEBUG('update_branch');
         // FIXME: Make sure we don't have to clear or make a new Branch
         //        object, like reset rev, so we get branch head rid, or
         //        something.
         // NOTE: The callee is responsible for clearing all the item lookups
         //       and map canvas layers.
         // NOTE: Once branch is updated, Update_Branch calls update_revision.
         this.update_mgr.schedule_in_band(Update_Branch);
      }

      //
      public function update_map_sknnng(skin_class:Class) :void
      {
         m4_DEBUG('update_map_sknnng: Switching skins:', String(skin_class));
         Conf.tile_skin = skin_class;
         m4_DEBUG('update_map_sknnng: geofeatures_redraw');
         G.map.geofeatures_redraw();
         // The bike facility widget should be redrawn, too.
         m4_DEBUG('update_map_sknnng: panels_mark_dirty: null');
         G.panel_mgr.panels_mark_dirty(null);
      }

      //
      public function update_panel_layout(panel_layout_option:Object) :void
      {
         m4_WARNING3('update_panel_layout: panel_layout_option:',
                     panel_layout_option._name,
                     panel_layout_option.label);
         G.panel_mgr.change_layout_theme(panel_layout_option._name);
      }

      //
      public function update_revision() :void
      {
         m4_DEBUG('update_revision');

         // When the revision changes, we have to load revisiony things (things
         // that stay constant throught a revision) such as the user's new item
         // policy, as well as a list of tags and regions (so we can cache them
         // locally), the map draw config (which really changes less often than
         // per revision, so maybe should be fetched less often), and we should
         // update what's in the viewport and refresh other items we've loaded.
         // See Update_Revision.update_step_region_names for, i.e.,
         //    schedule_oo_band(GWIS_Region_Names_Get).
         this.update_mgr.schedule_in_band(Update_Revision);
         this.update_mgr.schedule_in_band(Update_Viewport_Items);
      }

      //
      public function update_supplemental(gwis_req:GWIS_Base) :Boolean
      {
         m4_DEBUG('update_supplemental');
         var found_duplicate:Boolean;
         found_duplicate = this.update_mgr.schedule_oo_band(gwis_req);
         return found_duplicate;
      }

      //
      public function update_user() :void
      {
         // Called first from User.startup, which calls User.logout(),
         // which calls discard_and_update, then this fcn. Then main calls
         // G.map.update_user(). But for the former, we're not initialized.
         //m4_DEBUG(Introspect.stack_trace());
         if (!(G.initialized)) {
            m4_DEBUG('update_user: not setting event listeners: too early');
         }
         else {
            m4_DEBUG('update_user: setting event listeners');
            // Listen for the completion events. Update_User triggers
            // Update_Branch which kicks off Update_Revision and
            // Update_Viewport_Items. Once these all fire, the map is loaded,
            // so we can waste time loading panels in the background.
            var waitlist:Dictionary = new Dictionary();
            waitlist[Update_User.on_completion_event] = false;
            waitlist[Update_Branch.on_completion_event] = false;
            waitlist[Update_Revision.on_completion_event] = false;
            waitlist[Update_Viewport_Items.on_completion_event] = false;
            if (this.updates_out !== null) {
               // This happens during startup.
               m4_WARNING('update_user: updates_out !null:', this.updates_out);
            }
            else {
               this.updates_out = waitlist;
               // NOTE: Using just 'for', to get the keys, which are the event
               //       names.
               for (var key:String in waitlist) {
                  G.item_mgr.addEventListener(key, this.on_update_user_event);
               }
            }

            //
            this.basics_loaded = false;
            this.update_mgr.schedule_in_band(Update_User);

            // MAYBE: Load tiles quicker. Don't wait for tags and attrs,
            //        regions, etc. Implement this?:
            // this.tiles_clear();
            // this.update_mgr.schedule_in_band(Update_Viewport_Tiles);
         }
      }

      //
      public function update_viewport_items() :void
      {
         m4_DEBUG('update_viewport_items');
         //m4_DEBUG2('update_viewport_items: stack_trace:',
         //          Introspect.stack_trace());
         this.update_mgr.schedule_in_band(Update_Viewport_Items);
      }

      //
      public function update_viewport_tiles() :void
      {
         m4_DEBUG('update_viewport_tiles');
         // This fcn. is really only called when user toggles aerial tiles, so
         // we clear the lookup here.
         this.tiles_clear();
         this.update_mgr.schedule_in_band(Update_Viewport_Tiles);
      }

      //
      public function update_working_copy() :void
      {
m4_ASSERT(false); // FIXME: Implement this -- update working copy to latest
                  //                          revision saved on server. Use
                  //                          branch_conflicts as appropriate.
         m4_DEBUG('update_working_copy');
         this.update_mgr.schedule_in_band(Update_Working_Copy);
         //found_duplicate = this.update_mgr.schedule_oo_band(
         //                      new Update_Working_Copy(...));
      }

      // This is called when the draw config loads, when the list of attributes
      // loads, and when the list of tags load (see Update_Revision). We get
      // the active Update_Base object and tell it to do its next thang.
      public function update_viewport_nudge() :void
      {
         m4_DEBUG('update_viewport_nudge');
         var update:Update_Viewport_Items
            = (this.update_mgr.active_update_get(Update_Viewport_Items)
               as Update_Viewport_Items);
         if (update !== null) {
            m4_DEBUG('update_viewport_nudge: Found it; nudging!');
            update.update_nudge();
         }
         else {
            m4_DEBUG('update_viewport_nudge: Nothing to nudge.');
         }
      }

      // *** Abstract methods

      //
      // NOTE: This really doesn't belong here, but we gotta appease the
      //       compiler.
      public function tiles_clear() :void
      {
         m4_ASSERT(false); // Abstract
      }

      // ***

      // This waits for all the Update_* objects to complete, and then it tells
      // the hidden panels to load (like the list of routes, list of
      // discussions, etc., so that we load the map first before loading the
      // other data).
      public function on_update_user_event(event:Event) :void
      {
         var key:String;

         m4_DEBUG('on_update_user_event:', event.toString());
         m4_DEBUG('on_update_user_event: type:', event.type);
         m4_DEBUG('on_update_user_event: target:', event.target);

         if (this.updates_out === null) {
            m4_WARNING('on_update_user_event: updates_out is null');
            return;
         }

         if (event.type in this.updates_out) {
            if (this.updates_out[event.type]) {
               m4_WARNING('_event: already fired:', event.type);
            }
            this.updates_out[event.type] = true;
         }
         else {
            m4_WARNING('_event: unknown event:', event.type);
         }

         var some_waiting:Boolean = false;
         for (key in this.updates_out) {
            var waiting:Boolean = !this.updates_out[key];
            if (waiting) {
               m4_DEBUG('_event: at least still outstanding:', key);
               some_waiting = true;
               break;
            }
         }

         if (!some_waiting) {

            m4_DEBUG('on_update_user_event: all updates complete!');

            for (key in this.updates_out) {
               G.item_mgr.removeEventListener(key, this.on_update_user_event);
            }

            this.updates_out = null;
            this.basics_loaded = true;

            // HACK: This isn't this first time fetch_list is called for these
            // panels that are currently hidden and the user may never see
            // unless they activate them: The Combobo widget calls fetch_list
            // on its change action, which fires on startup. To not compete
            // with the map tiles and other, more important server requests,
            // fetch_list bails if this.basics_loaded is false.
            //
            // MAYBE: Don't load these now but wait until the user shows the
            //        panel.
            // BUG nnnn: Alternatively, do load these now, but don't pedal the
            // throbber, since once the tiles load you might dissuade users if
            // the throbber is still going. So move the throbbers to the panels
            // themselves: when the panel is loading a list, disable the list
            // and overlay a throbber of its own.

            // FIXME: Need to do this when mainline revision changes, not just
            //        when the working copy is updated.
            // FIXME: See routes_library.fetch_list: we shouldn't specify
            //        update_paginator_count.
            // FIXME: Coupling: We should use Events so we don't have to tickle
            //        the GUI controls directly (it makes this code harder to
            //        maintain).

            var update_paginator_count:Boolean = true;
            G.tabs.discuss_panel.fetch_list(update_paginator_count);
            // G.tabs.reactions_panel.fetch_list(update_paginator_count);

            // MAYBE: Is this comment still valid? FIXME: Get the count, and
            //        also get a page of results... this just gets count.
            G.tabs.changes_panel.fetch_list(update_paginator_count);

            G.app.routes_panel.routes_library.fetch_list();
            G.app.routes_panel.routes_looked_at.fetch_list();

            // This whole block is stuff we do after G.map.update_user()
            // (called from main.mxml::init()) completes. This is all a little
            // coupled. Anyway, now's a good time to load *.swf libraries.
            // Like the pdf_printer.swf file: it's cached, so we don't always
            // load it; and it's 750Kb, so we can (theoretically) make startup
            // faster; but we must load it before the user presses 'Save PDF',
            // since we can only use the Flash save dialog in response to a
            // button click, etc.
            // MAYBE: Spaghetti reference: five objects to the function.
            G.app.main_toolbar.map_layers.print_n_save.load_pdf_packages();
         }
      }

   }
}


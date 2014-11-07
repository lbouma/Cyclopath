/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME [lb] This files needs to be cleaned up. Specifically, there are a lot
//            of FIXME and comments to process and remove.

package views.base {

   import flash.display.Sprite;
   import flash.geom.Rectangle;
   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.collections.ArrayCollection;
   import mx.controls.Alert;
   import mx.events.CloseEvent;

   import grax.Access_Infer;
   //import grax.Dirty_Reason;
   import gwis.GWIS_Commit;
   import gwis.GWIS_Checkout_Base;
   import gwis.GWIS_Checkout_Versioned_Items;
   import gwis.GWIS_Route_Get_Saved;
   import gwis.update.Update_Base;
   import gwis.update.Update_Revision;
   import gwis.utils.Query_Filters;
   import items.Attachment;
   import items.Geofeature;
   import items.Item_Base;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.attcs.Attribute;
   import items.attcs.Tag;
   import items.feats.Branch;
   import items.feats.Byway;
   import items.feats.Route;
   import items.feats.Track;
   import items.utils.Tile;
   import utils.geom.Dual_Rect;
   import utils.misc.Collection;
   import utils.misc.Counter;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.misc.Strutil;
   import utils.rev_spec.*;
   import views.commands.Command_Manager;
   import views.map_widgets.Selection_Resolver;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Versioned;
   import views.panel_items.Widget_Attachment_Place_Box;
   import views.panel_routes.Panel_Item_Route;
   import views.panel_routes.Panel_Routes_Base;
   import views.panel_search.Panel_Search_Result;
   import views.panel_util.Commit_Changes_Dialog;
   import views.section_toolbar.Map_Layer_Toggler;

   public class Map_Canvas_Items extends Map_Canvas_Revision {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('MC_Items');

      public static var discard_in_progress:Boolean = false;

      // *** Object attributes

      // Layers containing the actual map data

      public var feat_labels:Map_Layer_Passive;
      public var route_labels:Map_Layer_Passive;
      public var tiles:Map_Layer;

      // The arrows and vertices layers are managed here but set by others
      public var direction_arrows:Map_Layer_Passive;
      public var vertices:Sprite; // A layer, but doesn't contain real features
      // FIXME: Missing Fernando's search stuff, i.e., search_geoms layer

      // Things on the map

      // NOTE: Map_Canvas used to contain lists of Geofeatures, Attachments,
      //       and Link_Values on the map. These are now stored as static
      //       member variables of the classes themselves. This makes this
      //       code somewhat simpler, but it also means we can only have one
      //       set of items loaded at once, i.e., you can't load Minnesota and
      //       Colorado at the same time. This is fine for now; there were a
      //       lot of things that were 'static' before (G.map, for one), so
      //       this doesn't change much, and we can always move those static
      //       things here (or to Item_Manager) in the future if we find that
      //       we want to keep disparate branches or revisions in memory.

      // Miscellany

      // This is a dummy tag for the tag filter list on Tab_Settings_Options
      // (see Tag_Filter_Viewer).
      public var untagged:Tag; // special tag used in filter

      // Regions names for autocomplete
      // FIXME: Move to Region.as ?? maybe rn. Region.name_list
      public var regions_list:Array;
      // FIXME: Where does this belong?
      public var branches_list:Array;

      // Editing infrastructure
      public var cm:Command_Manager;

      public var sel_resolver:Selection_Resolver;

      // Used on discard_and_update
      protected var do_reload_routes:Boolean = false;
      protected var routes_remember:Array;   // Routes to remember and reload.
      protected var routes_reopen:Set_UUID;  // Routes to refetch and reopen.
      protected var routes_reshow:Set_UUID;  // Routes to just reshow on map.
      protected var items_fresh:Set_UUID;    // List of Tags and Attributes
      protected var items_preserve:Set_UUID;

      protected var items_discard_keep:Dual_Rect;

      // Advanced Search
      public var searches:Map_Layer_Passive; // Higher than higherlights! :P
      public var search_geoms:Map_Layer_Passive; // lower than labels

      // Item selection mode: Attachment mode. In this mode, clicking doesn't
      // "select" items, instead it highlights/dehighlights them. This is used
      // for attaching geofeatures to attachments. User doesn't have to press
      // Ctrl to multi-highlight.
      //
      // attachment_placebox is the placebox with which the attachment mode is
      // associated.
      //
      // FIXME: Consolidate with the map_mode above and the coming-soon
      //        View/Edit modes.
      public var attachment_placebox:Widget_Attachment_Place_Box = null;

      protected var last_redraw_index:int = -2;

      // Reactions.
      // MAYBE: Coupling. This is just for routes (or route-posts), so maybe
      //        move out of this class.
      [Bindable] public var likes_visible:int;
      [Bindable] public var dislikes_visible:int;
      [Bindable] public var comments_visible:int;

      // Aerial tiles (via external WFS service, e.g., MnGEO).
      protected var _aerial_enabled:Boolean = false;
      protected var _aerial_layer_name:String;

      // Landmarks Experiment Part 2, circa 2014.
      // Whether the user has decided to participate
      public var landmark_exp_validation_active:Boolean = false;
      public var landmark_exp_routes:Array;
      public var landmark_exp_route_users:Array;

      // *** Constructor

      public function Map_Canvas_Items()
      {
         super();

         this.cm = new Command_Manager();
         this.sel_resolver = new Selection_Resolver();
      }

      // *** Startup methods

      //
      override public function startup() :void
      {
         super.startup();
         this.untagged = new Tag();
      }

      // *** Discard methods

      //
      override protected function discard_preserve() :void
      {
         var o:Object;
         var b:Byway;
         var r:Route;
         var attc:Attachment;
         var attc_class:Class;
         var item:Item_Versioned;
         var lookup:Dictionary;

         super.discard_preserve();

         // If the user is logging in, we can remember whatever routes they've
         // requested; otherwise, if they're logging out, we have to ask for
         // non-public routes again, in case the user's access changed.
         //
         // NOTE: routes_remember is a collection of special objects,
         //       and routes_reopen and routes_reshow is just a
         //       collection of stack IDs.
         this.routes_remember = new Array();  //  of [Route, Reshow, Reopen,].
         this.routes_reopen = new Set_UUID(); // Set of Routes to reopen.
         this.routes_reshow = new Set_UUID(); // Set of Routes to reshow.

         var route:Route;
         // Look for open route panels.
         var idx:int = G.app.side_panel.numChildren - 1;
         while (idx >= 0) {
            var rte_panel:Panel_Item_Route = (G.app.side_panel.getChildAt(idx)
                                              as Panel_Item_Route);
            m4_DEBUG('discard_preserve: idx:', idx, '/ rte_panel:', rte_panel);
            if (rte_panel !== null) {
               // The route panel is open and visible on the map.
               route = rte_panel.route;
               if (route !== null) {
                  m4_DEBUG('discard_preserve: route:', route);
                  if (((!this.user_loggedout) && (this.user_loggingin))
                      || (route.access_infer_id
                          & Access_Infer.pub_viewer_mask)) {
                     this.routes_reopen.add(route);
                  }
               }
               else {
                  // This happens when logging in: rte_panel is still being
                  // cleaned up, and route has already been detached.
                  m4_ASSERT_SOFT(rte_panel.panel_close_pending);
               }
            }
            idx -= 1;
         }
         // Look for routes with a show-on-map option selected.
         for each (route in Route.all) {
            if (route.hydrated) {
               m4_ASSURT(route.stack_id > 0);
               if (route.can_view) {
                  if ((this.user_loggingin) && (route.dirty)) {
                     // The user is logging in and the route is dirty, so
                     // keep our working version.
                     var reshow:Boolean = (route.filter_show_route);
                     var reopen:Boolean = (route.route_panel_ !== null);
                     this.routes_remember.push([route, reshow, reopen,]);
                  }
                  else if ((route.route_panel_ !== null)
                           && (G.panel_mgr.tab_index_get(route.route_panel_)
                               >= 0)) {
                     // The route panel is open and visible on the map.
                     // NOTE: This should be redundant. See previous for-loop.
                     this.routes_reopen.add(route);
                  }
                  else if (route.filter_show_route) {
                     // The route is visible on the map.
                     this.routes_reshow.add(route);
                  }
               }
               else {
                  m4_WARNING('EXPLAIN: Why cannot user view this route?');
               }
            }
            else {
               // If the route isn't hydrated, it was just loaded for the
               // route list (and hasn't even been shown on the map), so
               // just forget it. We'll get the route lists again, so we
               // might reload this route again (unhydrated, of course).
               m4_DEBUG('discard_preserve: route not hydrated:', route);
            }
            // Tell all existing routes to, er, go away, for now.
            // All routes are hidden... before being discarded from the map
            // on reload... not sure this is necessary.
            route.set_filter_show_route(false, /*force=*/true);
            route.set_visible_with_panel(route.route_panel_,
                                         /*panel_attach=*/false,
                                         /*panel_release=*/true);
            route.set_selected(false, /*nix=*/true);
         } // end: for each: route:Route in Route.all

         // EXPLAIN: We're resetting the user's byway ratings?
         //          Is the expectation that we'll request the same items
         //          from the server on re-load and rewrite these values?
         //          See discard_update later in this class.
         for each (o in G.item_mgr.dirtyset) {
            b = o as Byway;
            if (b !== null) {
               b.user_rating = -1;
               b.user_rating_update = false;
            }
         }

         this.items_fresh = new Set_UUID();
         this.items_preserve = new Set_UUID();
         if (this.user_loggingin) {
            // MAYBE: Is this inefficient? We're going through every Item.
            var debug_t0:int = G.now();
            for each (lookup in [Attachment.all,
                                 Geofeature.all,
                                 Link_Value.all,]) {
               for each (item in lookup) {
                  // By convention -- that is, that a logged-in user has the
                  // same or greater access than the anonymous user -- we can
                  // preserve dirty items when logging in, so long as we still
                  // check with the server and record the user's access level.
                  // 2013.09.09: We handle routes differently (see just above).
                  if ((!item.discardable) && (!(item is Route))) {
                     //m4_DEBUG('discard_preserve: preserve item:', item);
                     this.items_preserve.add(item);
                  }
               }
            }
            m4_DEBUG2('=TIME= / Populate items_preserve:',
                      (G.now() - debug_t0), 'ms');
         }
         else {
            // FIXME This is from teh original code -- remember fresh tags so
            //       we can clean them up. Here, we add attributes. But what
            //       about posts, threads, annotations, geofeatures, and links?
            for each (attc_class in [Tag, Attribute,]) {
               // NOTE fresh items are new to the working copy and not
               //      saved in the repository yet. We have to manually clean
               //      then up... why??
               for each (attc in attc_class.all) {
                  if (attc.fresh) {
                     this.items_fresh.add(attc);
                  }
               }
            }
         }
      }

      // Reset features and related infrastructure.
      override protected function discard_reset() :void
      {
         // Clear selections.

         this.map_selection_clear();
         // Not needed?: G.panel_mgr.effectively_active_panel = null;

         this.sel_resolver.reset_resolver();

         // Clear viewport.
         this.resident_rect = null;

         // Clear items from their lookups.
         G.item_mgr.cleanup_item_lookups();

         // When the items are item_cleanup()ed, they remove themselves from
         // their respective panels, so none of the temporary item details
         // panels should still be hanging around. So let's check and make sure
         // that's true.
         var idx:int = G.app.side_panel.numChildren - 1;
         // We iterate backwards through the side panel tab buttons. This just
         // checks that our logic is true: we close closeable item details
         // panels but once we see a permanent panel all the rest should be
         // expected to be permanent, too.
         var into_permanent:Boolean = false;
         while (idx >= 0) {
            m4_DEBUG2('discard_reset: idx:', idx,
                      '/ childAt:', G.app.side_panel.getChildAt(idx));
            var dpanel:Detail_Panel_Base = (G.app.side_panel.getChildAt(idx)
                                            as Detail_Panel_Base);
            // The 'viewstack_tab_hrule' VBox is a fake side_panel to draw a
            // line. So dpanel might === null.
            if (dpanel !== null) {
               if (dpanel is Panel_Item_Versioned) {
                  m4_WARNING('discard_reset: dpanel was not closed?:', dpanel);
                  m4_ASSERT_SOFT(!into_permanent);
               }
               else {
                  m4_DEBUG('discard_reset: not closing nonitm panel:', dpanel);
               }
               into_permanent = (!dpanel.closeable);
            }
            idx -= 1; // It's called an "old fashioned".
         }

         // Clear user's group memberships, new item policies, and whatnots

         // FIXME: Reset other gracs if you end up w/ more than one (see
         //        context, i.e., 'user', 'branch', etc.)
         // FIXME: Seems strange here...
         // NOTE: This always applies: to user_loggingin, user_loggedout, and
         //       branch_changed.
         if (G.grac !== null) {
            m4_DEBUG('discard_reset: resetting grac mgr');
            var reset_group_memberships:Boolean =
               (this.user_loggingin || this.user_loggedout);
            G.grac.reset_grac_mgr(reset_group_memberships);
         }

         // This seems kludgy. But it doesn't feel right in Item_Type. Should
         // we eventually move reset_processed_* flags to their item class??
         // But what about draw config? Hrmm...
         Update_Revision.reset_processed();
         // MAYBE: Do we need to touch G.item_mgr.active_branch or this.branch?
         // SILLY: What silliness... let's all check nulls now...
         // MAYBE: What's going on here? This is weird. Signal an event
         // instead, if you can't determine when a panel is available (i.e.,
         // un-spaghetti the code).
         if ((G.tabs !== null)
             && (G.tabs.route !== null)
             && (G.app.routes_panel !== null)
             && (G.app.routes_panel.routes_library !== null)) {
            // FIXME: This is awkward. 1) This is highly coupled; there's got
            //        to be a better way to trigger this. 2) [lb] has commented
            //        elsewhere that reset_route_list maybe should be deleted.
            // FIXME: See Panel_Routes_Library.on_active_branch_change:
            //        calling reset_route_list here is probably redundant now:
            G.app.routes_panel.routes_library.reset_route_list();
         }
         // else, still starting up.

         // Clear item helpers

         // Reactions.
         this.likes_visible = 0;
         this.dislikes_visible = 0;
         this.comments_visible = 0;

         Byway.connectivity_remove_maybe();

         // Call the parent

         // NOTE: We're calling the parent... in the middle of our
         //       implementation...
         super.discard_reset();

         // Initialize layers

         this.tiles = new Map_Layer(this, 1);
         // MEH: This feels kludgy. And Tile is a singleton... oh, well.
         //      We could make it part of the map and have it listen on an
         //      event.
         Tile.cleanup_all();

         this.search_geoms = new Map_Layer_Passive(901);
         this.direction_arrows = new Map_Layer_Passive(905);
         this.feat_labels = new Map_Layer_Passive(910);
         this.route_labels = new Map_Layer_Passive(920);
         // NOTE: In Map_Canvas_Base:
         //          this.highlights = new Map_Layer_Passive(930);
         //          this.higherlights = new Map_Layer_Passive(950);
         this.searches = new Map_Layer_Passive(970);
         this.locations = new Map_Layer_Passive(990);

         // Add the child sprite collections in an orderly manner.

         // NOTE: In Map_Canvas_Base:
         //          this.layer_add_child(this.highlights); // zplus: 930
         //          this.layer_add_child(this.higherlights); // zplus: 950

         this.layer_add_child(this.tiles); // zplus: 1
         this.layer_add_child(this.search_geoms); // zplus: 901
         this.layer_add_child(this.direction_arrows); // zplus: 905
         //
         this.layer_add_child(this.feat_labels); // zplus: 910
         //
         // NOTE: We interleave the addChildAt of vertices within the
         // layer_add_child calls so that route stop labels (like 'A', 'B',
         // etc.) are drawn on top of the route stop vertices.
         m4_DEBUG2('discard_reset: adding vertices: numChildren:',
                   this.numChildren);
         this.vertices = new Sprite();
         // zplus: n/a, but effectively 911
         this.addChildAt(this.vertices, this.numChildren);
         //
         this.layer_add_child(this.route_labels); // zplus: 920
         //
         this.layer_add_child(this.highlights); // zplus: 930
         this.layer_add_child(this.higherlights); // zplus: 950
         this.layer_add_child(this.searches); // zplus: 970
         this.layer_add_child(this.locations); // zplus: 990
         //
         // NOTE: This is last so the selection resolver is always drawn on
         // top of everything else.
         // zplus: n/a, but effectively 991
         this.addChildAt(this.sel_resolver, this.numChildren);
      }

      //
      override protected function discard_restore() :void
      {
         var o:Item_User_Access;
         var item:Item_Versioned;

         super.discard_restore();

         // Clear or restore dirty features

         if (this.user_loggingin) {
            // Tell items_add not to call items_add_finish.
            var complete_now:Boolean = false;
            this.items_add(this.items_preserve.as_Array(), complete_now);
            for each (item in this.items_preserve) {
               // This is a little hacky. Restore geofeature labels.
               if ((item as Geofeature) !== null
                   && (item as Geofeature).label !== null) {
                  this.feat_labels.addChild((item as Geofeature).label);
               }
            }
            if (this.loc_visible !== null) {
               this.locations.addChild(this.loc_visible);
            }
         }
         else {
            G.item_mgr.dirtyset = new Set_UUID();
            m4_ASSERT(G.item_mgr !== null);
            if (G.item_mgr !== null) {
               G.item_mgr.deletedset = new Dictionary();
               G.item_mgr.donedeleted = new Dictionary();
            }
            this.loc_visible = null;
            // Manually cleanup fresh tags: Why?
            for each (o in this.items_fresh) {
               // NOTE: this.items_fresh is just Tags and Attributes.
               //       Which do not have sprites. Hence, child index: -1.
               // MAGIC_NUMBER: -1 is the child index, which doesn't apply.
               o.item_cleanup(-1);
            }
         }

         this.items_preserve = null;
         this.items_fresh = null;

         /*/ MAYBE: Should we reload Tags and Attrs?
                    2013.03.04: This is an old comment... but we haven't tested
                    editing and discarding very much, so there are probably
                    issues to fix.
         for each (attc_class in [Tag, Attribute,]) {
            for each (attc in attc_class.all_named) {
               // NOTE This is kind of hacky -- we don't clear the lookups for
               //      Tag and Attribute so that we don't have to re-request
               //      them; but we have to re-register them with Attachment.
               //      (That is, rather than calling items_add, we go
               //      directly to the lookup.)
               Attachment.all[attc.stack_id] = attc;
            }
         }
         /*/
      }

      //
      override protected function discard_update() :void
      {
         var o:Object;
         var bway:Byway;
         var stack_id:int;

         super.discard_update();

         if (G.user.logged_in) {
            m4_DEBUG('discard_update: user logged on; preparing dirty byways');
            // Fetch all user private data (currently watch regions) and mark
            // dirty byways to update their user ratings.
            for each (o in G.item_mgr.dirtyset) {
               bway = (o as Byway);
               if (bway !== null) {
                  bway.user_rating_update = true;
               }
            }
         }

         if (!this.user_loggingin) {
            m4_DEBUG('discard_update: user not logging in; clearing cmd mgr');
            // Unless the user is logging in, clear the command manager.
            // (This fcn. is called by discard_and_update, which is called
            // after saving, when the user clears the command history
            // intentionally, when the user switches revisions, etc.)
            this.cm.clear();
         }

         // This fcn. is called when the user, branch or revision changes.

         this.do_reload_routes = false;

         if (this.user_loggingin || this.user_loggedout) {
            m4_DEBUG('discard_update: user logging on or off; update_user');
            // User context changed, so reload _everything_
            // (Note if user_loggingin, we save dirty items, but we still need
            // to reload everything to learn current user access permissions)
            // NOTE: Order matters
            this.update_user();
            if (!this.branch_changed) {
               this.do_reload_routes = true;
            }
         }
         else if (this.branch_changed) {
            m4_DEBUG('discard_update: branch_changed; update_branch');
            this.update_branch();
            // NOTE: update_branch calls update_revision when it's done.
         }
         else {
            m4_DEBUG('discard_update: must be new revision; update_revision');
            // Only the revision has changed; update it
            this.update_revision();
         }
      }

      //
      override protected function on_updated_items(ev:Event) :void
      {
         var found_duplicate:Boolean;

         super.on_updated_items(ev);

         m4_DEBUG2('on_updated_items: updatedItems /',
                   'Update_Viewport_Items.on_completion_event');

         if (this.do_reload_routes) {

            var route:Route;

            // Restore dirty routes.
            if (this.routes_remember.length > 0) {
               var parms:Array;
               var add_routes:Array = new Array();
               for each (parms in this.routes_remember) {
                  // [0] is Route [1] is reshow (on map) [2] is reopen (panel).
                  add_routes.push(parms[0]);
               }
               this.items_add(add_routes);
               for each (parms in this.routes_remember) {
                  route = parms[0];
                  if (parms[1]) {
                     // Tell the route list entries to show the filter checkbox
                     // as selected.
                     route.set_filter_show_route(true, /*force=*/true);
                  }
                  if (parms[2]) {
                     route.set_selected(true, /*nix=*/false, /*solo=*/true);
                  }
               }
               this.routes_remember = null;
            }

            // Reload routes that were visible on the map or were open.

            var stack_id:int;
            var gwis_cmd:GWIS_Route_Get_Saved;
            var working_rt:Route;

            for each (route in this.routes_reopen) {
               working_rt = Geofeature.all[route.stack_id];
               if (working_rt !== null) {
                  working_rt.set_filter_show_route(true, /*force=*/true);
                  working_rt.set_selected(true, /*nix=*/false, /*solo=*/true);
               }
               else {
                  m4_DEBUG2('on_updated_items: reopen: fetching route sid:',
                            route.stack_id);
                  gwis_cmd = new GWIS_Route_Get_Saved(
                     route.stack_id,
                     /*caller_source=*/'on_updated_items_reopen',
                     /*callback_okay=*/this.on_updated_items_reopen,
                     /*callback_fail=*/null,
                     /*as_gpx=*/false,
                     /*check_invalid=*/
                        Panel_Routes_Base.recalculate_routes_on_fetch,
                     /*gia_use_sessid=*/route.unlibraried,
                     /*get_steps_and_stops=*/true,
                     /*compute_landmarks=*/route.show_landmarks);
                  found_duplicate = this.update_supplemental(gwis_cmd);
                  m4_ASSERT_SOFT(!found_duplicate);
               }
            }
            this.routes_reopen = null;

            for each (route in this.routes_reshow) {
               working_rt = Geofeature.all[route.stack_id];
               if (working_rt !== null) {
                  working_rt.set_filter_show_route(true, /*force=*/true);
               }
               else {
                  m4_DEBUG2('on_updated_items: reshow: fetching route sid:',
                            route.stack_id);
                  gwis_cmd = new GWIS_Route_Get_Saved(
                     route.stack_id,
                     /*caller_source=*/'on_updated_items_reshow',
                     /*callback_okay=*/this.on_updated_items_reshow,
                     /*callback_fail=*/null,
                     /*as_gpx=*/false,
                     /*check_invalid=*/
                        Panel_Routes_Base.recalculate_routes_on_fetch,
                     /*gia_use_sessid=*/route.unlibraried,
                     /*get_steps_and_stops=*/true,
                     /*compute_landmarks=*/route.show_landmarks);
                  found_duplicate = this.update_supplemental(gwis_cmd);
                  m4_ASSERT_SOFT(!found_duplicate);
               }
            }
            this.routes_reshow = null;
         }
      }

      //
      protected function on_updated_items_reopen(
         gwis_cmd:GWIS_Route_Get_Saved, route:Route) :void
      {
         this.on_updated_items_route_reopen_set_unlibraried(gwis_cmd, route);
         route.set_filter_show_route(true, /*force=*/true);
         route.set_selected(true, /*nix=*/false, /*solo=*/true);
      }

      //
      protected function on_updated_items_reshow(
         gwis_cmd:GWIS_Route_Get_Saved, route:Route) :void
      {
         this.on_updated_items_route_reopen_set_unlibraried(gwis_cmd, route);
         route.set_filter_show_route(true, /*force=*/true);
      }

      //
      protected function on_updated_items_route_reopen_set_unlibraried(
         gwis_cmd:GWIS_Route_Get_Saved, route:Route) :void
      {
         // 2014.04.29: This fcn. not being called as expected. It is suppose
         // to reopen routes that were closed when the user logged on.
         // BUG nnnn/LOW PRIORITY: The user can find their anon, unsaved
         // routes in their route history, so this isn't a big deal, but
         // we could this feature so that when a user logs on, we reopen
         // whatever item panels they had open... makes it weird to edit
         // items, and then to logon, because your changes move forward
         // but we close any open item panels which probably sends the
         // user the wrong message... but at least the editing tools
         // still show the save map button.
         m4_DEBUG2('..._rte_reopen_...: gwis_cmd.used_sessid:',
                   gwis_cmd.used_sessid, '/ route:', route);
         if (gwis_cmd.used_sessid) {
            // You can make a deep link to an anon route, which gives
            // the stealth group editor access. Until the user logins,
            // the route would only otherwise have the stealth editor
            // access.
            // The server should probably tell us if the route
            // is not saved; we should not be deducing this... but... this
            // probably works well enough.
            var non_stealth:int;
            non_stealth = route.access_infer_id & ~Access_Infer.stealth_mask
            if (non_stealth == Access_Infer.sessid_arbiter) {
               m4_DEBUG('..._rte_reopen_...: unlibraried=true: route:', route);
               route.unlibraried = true;
            }
         }
      }

      // *** Item management methods

      // Discard a particular item from the map
      public function item_discard(item:Item_Versioned) :void
      {
         // NOTE: It's up to the caller to make sure the item is discardable.
         // But let's not assert m4_ASSERT(item.discardable) because that fcn.
         // is expensive.
         var gf:Geofeature = (item as Geofeature);
         if (gf !== null) {
            // It's a geofeature; have the layer discard it.
            // NOTE: Map_Layer.geofeature_discard calls gf.item_cleanup()
            // EXPLAIN: [lb] wants to check that we're not discarding a Branch.
            //          Or Explain if we do and it's okay.
            m4_ASSERT(!(item is Branch));
            try {
               // This calls item_cleanup.
               m4_DEBUG('item_discard:', item);
               this.layers[gf.zplus].geofeature_discard(gf);
            }
            catch (e:TypeError) {
               // TypeError: Error #1010: A term is undefined and has no
               //                         properties.
               // 2013.09.10: Happened on logout...
               m4_WARNING('item_discard: not in layer:', item);
            }
         }
         else {
            // Otherwise, it's an Attachment or Link_Value, so just clean up.
            item.item_cleanup(-1);
         }
      }

      // Add a list of features to the map.
      //
      // To remove features, see item_discard, items_discard,
      // sprite_items_discard, map_selection_clear, and
      // function discard_*.
      //
      // PROBABLY: new_items is mutated by this fcn., which seems like a
      //           trip-up. I.e., it's easy to get confused when you call
      //           this fcn. and then things go awry later because you
      //           didn't expect the Array to be emptied.
      //           SOLUTION?: add a third parameter, dont_mutate:Boolean?
      public function items_add(
         new_items:Array,
         complete_now:Boolean=true,
         final_items:ArrayCollection=null)
            :Boolean
      {
         var operation_complete:Boolean = true;
         var gf:Geofeature;
         var item:Item_Versioned;
         var new_items_start_ct:int = new_items.length;
         var tstart:int = G.now(); // For m4_DEBUG_TIME.

         m4_TALKY('items_add: maybe adding count:', new_items_start_ct);

         // Geofeatures are Sprites, and they're added to the Map_Canvas'
         // child list so they can draw themselves to the display
         // properly. Attachments and Link_Values, in contrast, are not
         // Sprites, are not added to the Map_Canvas' child list, and do not
         // draw themselves. What the three Classes have in common is that they
         // have an init() fcn. and derive from Item_Versioned.

         // Iterating downwards, though we could just as easy iterate upwards
         // and use shift() instead of pop().
         var spew_item_type:String;
         for (var i:int = new_items.length - 1; i >= 0; i--) {
            item = new_items.pop();
            m4_VERBOSE('items_add: initing item:', item);
            m4_VERBOSE('items_add: G.item_mgr:', G.item_mgr);
            if (!spew_item_type) {
               spew_item_type = String(Item_Base.item_get_class(item));
            }
            var updated_item:Item_Versioned = item.init_item(G.item_mgr);
            if (updated_item === null) {
               // This means the item is new to the client's lookups.
               // This is a little hacky: if geofeature, but not branch.
               if ((item is Geofeature) && (!(item is Branch))) {
                  gf = item as Geofeature;
                  // Make sure the map layer for geofeature's z-level exists.
                  this.layers_add_maybe(gf);
                  this.layers[gf.zplus].geofeature_add(gf);
               }
               if (final_items !== null) {
                  final_items.addItem(item);
               }
            }
            else {
               m4_VERBOSE('  ..UPDATED!');
               if (final_items !== null) {
                  final_items.addItem(updated_item);
               }
               // BUG nnnn: Branch conflicts: If item is dirty in working
               // copy but there's a new version on the server, make a
               // branch item conflict.
            }
            // Every 100th item processed, see if it's time to take a break, to
            // let the GUI refresh.
            // FIXME Why every 100? Just a guess! So maybe measure...
            if ((!complete_now)
                && (((new_items.length - i) % 100) == 0)
                && (G.gui_starved(tstart))) {
               operation_complete = false;
               break;
            }
         }

         if (spew_item_type) {
            spew_item_type = 'class: ' + spew_item_type;
         }
         m4_DEBUG4('items_add:', spew_item_type,
                   'added:', (new_items_start_ct - new_items.length),
                   '/ deferred:', new_items.length,
                   '/ complete:', operation_complete);
         m4_DEBUG_TIME('Map_Canvas_Items.items_add');

         return operation_complete;
      }

      // Discard map features not within the keep rectangle.
      // Returns false if preempted to let other threads run, otherwise returns
      // true if all items discarded
      // NOTE items_discard only discards visible items, like geofeatures and
      //      tiles, and related link values (but not attributes or tags, etc.)
      public function items_discard(rect_items_keep:Dual_Rect=null,
         complete_now:Boolean=true, item_types:Set=null) :Boolean
      {
         var complete_now_tstart:int = 0;
         var operation_complete:Boolean = true;
         var layer:Map_Layer;
         var tstart:int = G.now();

         if (!complete_now) {
            complete_now_tstart = tstart;
         }

         m4_DEBUG('items_discard: now:', complete_now, '/', rect_items_keep);

         if (rect_items_keep === null) {
            // Once we start discarding all items -- which could span multiple
            // callLaters -- if the user zooms again, make sure the map doesn't
            // think any items are resident.
            Map_Canvas_Items.discard_in_progress = true;
            this.zoom_level_previous = Number.NaN;
         }

         for each (layer in this.layers_ordered) {
            m4_TALKY('items_discard: discarding item_types:', item_types);
            operation_complete = layer.sprite_items_discard(
               rect_items_keep, complete_now_tstart, complete_now,
               item_types);
            if (!operation_complete) {
               // preempt thyself so others may run
               break;
            }
         }

         if ((operation_complete) && (!G.gui_starved(complete_now_tstart))) {
            m4_DEBUG('Discarding attachments and links');
            operation_complete = this.items_discard_attachments_and_links(
               complete_now_tstart);
         }
         else {
            operation_complete = false;
         }

         if (operation_complete) {
            Map_Canvas_Items.discard_in_progress = false;
            this.zoom_level_previous = this.zoom_level;
         }

         m4_DEBUG_TIME('Map_Canvas.items_discard');

         return operation_complete;
      }

      // BUG nnnn: Only support linking geofeatures and attachments, i.e., not
      //           any other combination of items (i.e., currently, all link
      //           values assumed to link attachment and geofeature
      //           exclusively).
      //           FIXME: This is false. Attributes can link to attachments.
      //           [lb] notes only LHS is always attc. RHS can be any item.
      protected function items_discard_attachments_and_links(tstart:int)
         :Boolean
      {
         var operation_complete:Boolean = true;
         var discard_ct:int = 0;
         var attc:Attachment;

         for each (attc in Attachment.all) {
            // By default, an item is discardable if it's not dirty.
            // Tags and Attributes are never discardable (unless the map
            // branch, revision, or user changes, in which case we whack
            // everything). Other items are generally discardable if
            // they're no longer visible on the map (geofeatures, handled
            // above), or if they're no longer linked to anything visible
            // on the map (attachments and link_values, handled here).
            if (attc.discardable) {
               // NOTE This deletes the attc from Attachment.all, which I
               //      think is okay because it's a Dictionary (that is, the
               //      for-each makes a list of values beforehand, and it isn't
               //      affected by us when we modify the Dictionary)
               this.item_discard(attc);
               discard_ct++;
            }
            // NOTE We repeat the loop above on items we don't delete (but
            //      hopefully it's not that many?)
            // FIXME Magic number? Make a conf var?
            if (((discard_ct % 100) == 0) && (G.gui_starved(tstart))) {
               m4_DEBUG('items_discard_attcs_&_links: preemptively breaking!');
               operation_complete = false;
               break;
            }
         }

         return operation_complete;
      }

      //
      public function map_selection_clear() :void
      {
         m4_ASSERT(false); // Abstract
      }

      // *** Save items methods

      // Start the save process.
      public function items_save_start() :void
      {
         const ban_head:String = 'Cannot save changes';
         const ban_msg:String =
            'Unable to save: there is a ban on your account '
            + 'or on the computer you are using. '
            + 'Please email ' + Conf.instance_info_email + ' for help.';

         UI.save_reminder_hide(); // clear the reminder if it was up

         // FIXME [TESTING] When's the last time this was tested?
         if (G.user.is_full_banned) {
            m4_WARNING('items_save_start: full-banned user saving:', G.user);
            Alert.show(ban_msg, ban_head);
         }
         else if ((G.user.is_banned)
                  && (G.item_mgr.contains_dirty_non_personalia)) {
            m4_WARNING('items_save_start: half-banned user saving:', G.user);
            Alert.show(ban_msg, ban_head);
         }
         else {
            var n_disconnected:int = 0;
            for each (var item:Item_User_Access in G.item_mgr.dirtyset) {
               m4_DEBUG('items_save_start: item:', item);
               var byway:Byway = (item as Byway);
               if ((byway !== null) && (!byway.deleted)) {
                  //
                  var beg_adj:Set_UUID;
                  beg_adj = G.map.nodes_adjacent[byway.beg_node_id];
                  m4_DEBUG('items_save_start: beg_adj:', beg_adj);
                  m4_DEBUG2('items_save_start: beg_adj.length:',
                            beg_adj.length);
                  m4_DEBUG2('items_save_start: beg_adj.contains:',
                            beg_adj.contains(byway));
                  if ((beg_adj === null)
                      || ((beg_adj.length == 1)
                          && (beg_adj.contains(byway)))) {
                     n_disconnected += 1;
                  }
                  //
                  var fin_adj:Set_UUID;
                  fin_adj = G.map.nodes_adjacent[byway.fin_node_id];
                  m4_DEBUG('items_save_start: fin_adj:', fin_adj);
                  if ((fin_adj === null)
                      || ((fin_adj.length == 1)
                          && (fin_adj.contains(byway)))) {
                     n_disconnected += 1;
                  }
               }
            }
            if (n_disconnected > 0) {            
               Alert.show(
                  /*text=*/"One or more edited roads or trails do "
                     + "not connect to the Cyclopath road network. "
                     + "Would you like to continue?"
                     + "\n\n"
                     + "Hint: This is okay for dead-end roads, but for "
                     + "most trails and roads, you'll want to connect "
                     + "them to the existing road network. "
                     + "You can connect roads to the network by "
                     + "dragging the ends of the road to a nearby "
                     + "intersection."
                     + "\n\n"
                     + "Click Cancel to fix the road "
                     + "network, or click Yes if you truly want to "
                     + "add dead-end or disconnected roads and trails.",
                  /*title=*/'Not all roads connected',
                  /*flags=*/Alert.YES | Alert.CANCEL,
                  /*parent=*/G.app,
                  /*closeHandler=*/this.items_save_disconnected_answer
                  );
            }
            else {
               // n_disconnected == 0, so ask for the changenote.
               this.items_save_changenote();
            }
         }
      }

      //
      public function items_save_disconnected_answer(event:CloseEvent) :void
      {
         if (event.detail == Alert.YES) {
            this.items_save_changenote();
         }
         else {
            m4_ASSERT_SOFT(event.detail === Alert.CANCEL);
         }
      }

      // Ask the user for a change note
      protected function items_save_changenote() :void
      {
         if (G.item_mgr.contains_dirty_revisioned) {
            // Some changes might be seen by other users
            // FIXME: The two links embedded here should have an ext_link_icon
            var dialog_title:String = 'Saving public changes';
            var dialog_body:String =
               "By contributing, you agree that we may study and republish "
                  + "your work; see our "
                  + "<font color='#0000ff'><u><a target='cp_mw' "
                  +        "href='http://cyclopath.org/wiki/User_Agreement'>"
                  + "User agreement</a></u></font> for details. Please note "
                  + "that all contributions may be changed or removed by "
                  + "others. You are also promising that you created your "
                  + "work yourself. <b>Do not edit with reference to a "
                  + "Google Earth window, any online or paper map, or any "
                  + "other resource that you did not create yourself</b> "
                  + "(<font color='#0000ff'><u><a target='cp_mw' "
                  + "href='http://cyclopath.org/wiki/Map_Resources'>"
                  + "details</a></u></font>).<br><br>"
                  + "Summarize your changes (optional):";
            Commit_Changes_Dialog.show(
               dialog_title,
               dialog_body,
               /*on_ok=*/this.items_save_send,
               /*input_required=*/false,
               /*on_cancel=*/null,
               /*ok_label=*/'Save',
               /*cancel_label=*/'Cancel');
         }
         else if (G.item_mgr.contains_dirty_changeless) {
            var changenote:String = '';
            this.items_save_send(changenote);
         }
         else {
            m4_ASSERT_SOFT(false);
         }
      }

      // Send the dirty features to the server.
      protected function items_save_send(changenote:String,
                                         activate_alerts:Boolean=false,
                                         routes_ignore:Set_UUID=null) :void
      {
         var wait_for_response:Boolean = false;

         if (!wait_for_response) {

            // All dirty routes have been added to the library or ignored.

            // MAYBE: BUG nnnn: Option to commit anonymously, even if logged in

            m4_DEBUG('items_save_send: changenote:', changenote);

            var gwis_put_item:GWIS_Commit;
            gwis_put_item = new GWIS_Commit(
               G.item_mgr.dirtyset,
               changenote,
               /*be_silent=*/false,
               /*callback_load=*/this.items_save_send_resp,
               // FIXME: Specify a failure callback?
               /*callback_fail=*/null,
               /*callback_payload=*/null,
               /*anon_coward=*/false,
               /*restrict_dirty=*/null,
               activate_alerts,
               /*command_mgr=*/G.map.cm);

            // EXPLAIN: Clear what's selected on the map. Why?
            // Note that we reload the whole map after a save,
            // anyway, so this probably doesn't really matter.
            this.map_selection_clear();
            // Not needed?: G.panel_mgr.effectively_active_panel = null;

            gwis_put_item.fetch();
         }
      }

      //
      protected function items_save_send_resp(gwis_commit:GWIS_Commit,
                                              rset:XML,
                                              payload:*=null) :void
      {
         m4_DEBUG('items_save_send_resp');

         // We're called after all the items have been processed. See
         // update_items_committed, which removes each item and its
         // corresponding command(s) from the command stack. So, if the
         // command stack still has items, something was not processed.
         m4_SERVED(G.map.cm.redo_length == 0);
         m4_DEBUG(' .. G.map.cm.undo_length:', G.map.cm.undo_length);
         m4_SERVED(G.map.cm.undo_length == 0);
         // FIXME: I think the logic here is okay... we used to call
         //        discard_and_update/discard_update which clears the cm.
         G.map.cm.clear();

         // 2012.11.06: CcpV1 doesn't reload the map on save, but on route
         // permissions change, the server clones the route, so the client has
         // to check out the "new" route. In CcpV2, until now, we've just done
         // the lazy and reloading the entire map after GWIS_Commit. But now
         // we've got a more intelligent mechanism in place: after commit, we
         // update the item's stack IDs if they were client IDs, and mark the
         // items not dirty. Both of these have already happened. So, really,
         // we're probably done. So this is a safety guard: reload and update
         // the items we just saved. We shouldn't _technically_ have to do
         // this, but if the client doesn't specify all attributes, the server
         // fills them in, so it could be we have an incomplete item on our
         // hands.

         //
         var gwis_checkout:GWIS_Checkout_Versioned_Items;
         //
         var buddy_ct:Counter = null;
         var update_req:Update_Base = null;
         var resp_items:Array = null;
         var callback_load:Function = this.recheckout_committed_load;
         var callback_fail:Function = null; // MAYBE??

         // On commit, we can mix item types, but checkout is type-singular.
         // Assemble a lookup of stack IDs by item type.
         var by_type:Dictionary = new Dictionary();
         var item:Item_Versioned;
         for each (item in gwis_commit.changed_items) {
            m4_TALKY(' .. item:', item);
            var item_c:String
               = Introspect.get_constructor(item).class_item_type;
            m4_ASSERT_SOFT(item.stack_id > 0);
            if (!(item_c in by_type)) {
               by_type[item_c] = new Array();
            }
            by_type[item_c].push(item.stack_id);
         }

         // Send a separate checkout command for each set of stack IDs by item
         // type.
         var item_type:String;
         for (item_type in by_type) {
            var sids:Array = by_type[item_type];
            var qfs:Query_Filters = new Query_Filters();
            var stack_id:int;
            for each (stack_id in sids) {
               qfs.only_stack_ids.push(stack_id);
            }
            m4_ASSERT(G.map.rev_workcopy !== null);
            gwis_checkout = new GWIS_Checkout_Versioned_Items(
                  item_type, G.map.rev_workcopy, buddy_ct, qfs,
                  update_req, resp_items, callback_load, callback_fail);
            var found_duplicate:Boolean;
            found_duplicate = this.update_supplemental(gwis_checkout);
            m4_ASSERT_SOFT(!found_duplicate);
         }

         // Before GWIS_Commit calls us, it tells each item to handle having
         // been saved to the server. One thing the items do is to mark
         // themselves not dirty and to remove themselves from the deletedset
         // lookup.

// Add to Style Guide/Bug Writing Guide: This is why recording how to reproduce
// a bug is so important: sometimes reproducing a bug is so hard!:
// FIXME_2013_06_11
// BUG nnnn: 2013.06.07: [lb] selected map item, opened new thread, attached
// item, switched to first item panel, clicked map item to open third panel
// (second geofeature panel), clicked new note, attached item, went back
// to thread panel, tried posting, was told to save map first, tried saving
// the map, then this fired:
         if (G.item_mgr.dirtyset.length != 0) {
            m4_ASSERT_SOFT(false);
            G.sl.event('error/items_save_send_resp/dirtyset.len',
                       {dirtyset_length: G.item_mgr.dirtyset.length});
            for each (var itmua:Item_User_Access in G.item_mgr.dirtyset) {
               G.sl.event('error/items_save_send_resp/dirtyset',
                          {itmua: itmua.toString()});
            }
            // 2014.09.16: Should we just reset the dirtyset and move on?
            G.item_mgr.dirtyset = new Set_UUID();
         }

         m4_ASSERT_SOFT(Collection.dict_length(G.item_mgr.deletedset) == 0);
         // Never: m4_ASSERT(!Collection.dict_length(G.item_mgr.donedeleted));
         // Reset client IDs to -1.
         // MAYBE: Don't do this just yet, in case the new code isn't perfect.
         // It'll be easier to debug if we don't reset the client ID generator.
         // MAYBE LATER: G.item_mgr.assign_id_reset();

         // COUPLING: This code doesn't _quite_ belong here, but none of the
         // item classes currently hook the commit command.
         // MAYBE: Maybe a committed_items event?

         // MAYBE: Use the system status bar to say "Save successful", or:
         // MAYBE: this dialog should fade away,
         //        or we should add a system message area...
         //        i.e., what application has a save success message?
         //              you just hit okay and the file is saved...

         var alert_text:String =
            'Data saved successfully.\n\n'
            + 'Please note that edits to street geometry '
            + 'may not appear on the map for a few minutes '
            + '(our server has to rebuild the tiles first).';
         var alert_title:String = 'Save successful';
         var flags:uint = mx.controls.Alert.OK
         var parent:Sprite = null;
         var clickListener:Function = gwis_commit.success_acknowledged;
         var iconClass:Class = null;
         var defaultButton:uint = mx.controls.Alert.OK;
         if (!gwis_commit.silent) {
            // MAYBE: Instead of "save success" being a modal dialog the user
            //        has to dismiss, make it a Pyserver_Message that
            //        automatic drops down?
            //                 [lb] just doesn't really t like modal dialogs.
            Alert.show(alert_text, alert_title, flags, parent,
                       clickListener, iconClass, defaultButton);
         }

         // Bug 2415 -- Don't just discard everything on save and force a 10
         //             sec. reload. Discard just working copy items and
         //             fetch 'em -- you really just want their new system
         //             IDs, right? Or are there other fields that may have
         //             changed?
         // BUG 2716: Don't refresh the whole map after saving.
         // Oops! Duplicate bugs... 2415 and 2716...
         //
         //
         // 2011.10.07: I [lb] am fudging this for now. To force a reload,
         // we set loggedout and branch-changed, otherwise we run into a few
         // errors: the issue is that we reset the current revision ID since
         // we just saved the map and we want to get the latest revision ID.
         // So, really, this might not be fudging so much as it is just that
         // these variables aren't named quite right: the variables indicate
         // how much stuff to reload (just items, just items and the branch,
         // or just items, the branch, and the latest revision ID).
         //
         // 2014.05.06: Do any of the former comments still make sense to [lb]?
      }

      //
      protected function recheckout_committed_load(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         var complete_now:Boolean = true;
         var completed:Boolean = true;
         completed = this.items_add(gwis_req.resp_items, complete_now);
         m4_DEBUG('recheckout_committed_load: completed:', completed);
      }

      // *** Aerial methods

      //
      public function get aerial_enabled() :Boolean
      {
         // This value reflects a UI checkbox,
         //  G.tabs.settings.settings_panel.settings_options.aerial_cbox.
         return this._aerial_enabled;
      }

      //
      public function set aerial_enabled(a:Boolean) :void
      {
         if (a != this.aerial_enabled) {
            this._aerial_enabled = a;
            // MAYBE: This is tightly coupled. Ideally, the widgets would be
            //        keyed by events rather than called directly.
            G.tabs.settings.settings_panel
               .settings_options.aerial_cbox.selected = a;
            G.app.main_toolbar.road_or_aerial_tbbutton
               .selectedIndex = (a ? 1 : 0);
            this.update_viewport_tiles();
            // FIXME/BUG nnnn/EXPLAIN: Why can't we make PDFs from aerial?
            // Is it because the aerial tiles are not part of the map canvas?
            G.app.main_toolbar.map_layers.set_enabled(
               Map_Layer_Toggler.map_layer_save_pdf, !a);

            G.sl.event('map/aerial',
               { status: a ? 'on' : 'off',
                 layer: this.aerial_layer_selected_name });
         }
      }

      //
      public function get aerial_layer_selected() :Object
      {
         var layer_selected:Object = null;
         if (this.aerial_enabled) {
            layer_selected =
               G.tabs.settings.settings_panel.settings_options.aerial_layer
               .selectedItem;
         }
         return layer_selected;
      }

      //
      public function get aerial_layer_selected_name() :String
      {
         var layer_name:String;
         var layer:Object = this.aerial_layer_selected;
         if (layer === null) {
            layer_name = 'Cyclopath';
         }
         else {
            if (layer._name) {
               layer_name = layer._name;
            }
            else {
               layer_name = layer.label;
            }
         }
         return layer_name;
      }

      //
      override public function update_viewport_tiles() :void
      {
         // 2014.05.22: We're sending a lot of these... and in the
         //             same event packet, too. Anyway looking at
         //             a network trace would think we're sloppy.
         //G.sl.event('map/aerial',
         //   { status: this.aerial_enabled ? 'on' : 'off',
         //     layer: this.aerial_layer_selected_name });
         super.update_viewport_tiles();
      }

      // *** Tile methods

      // Remove all tiles.
      override public function tiles_clear() :void
      {
         m4_DEBUG('tiles_clear');
         // Discard and recreate the tiles layer
         var old_filters:Array = this.tiles.filters;
         this.tiles
            = (this.child_replace(
                  this.tiles, new Map_Layer(this, this.tiles.zplus))
               as Map_Layer);
         // Also dump the class's lookup
         Tile.cleanup_all();
         // Restore filters.
         this.tiles.filters = old_filters;
      }

      //
      public function tiles_discard(rect_items_keep:Dual_Rect=null,
         complete_now:Boolean=true) :Boolean
      {
         var complete_now_tstart:int = 0;
         var operation_complete:Boolean = true;
         var layer:Map_Layer;
         var tstart:int = G.now();

         if (!complete_now) {
            complete_now_tstart = tstart;
         }

         m4_DEBUG('tiles_discard: now:', complete_now);
         if (rect_items_keep !== null) {
            m4_DEBUG('  rect_keep:', rect_items_keep.gwis_bbox_str);
         }

         m4_DEBUG('Discarding tile layer tiles');
         operation_complete = this.tiles.sprite_items_discard(
            rect_items_keep, complete_now_tstart, complete_now);

         m4_DEBUG_TIME('Map_Canvas.tiles_discard');

         return operation_complete;
      }

      // Clear and fetch tiles for current view
      //
      // FIXME: This function is called only when turning on/off aerial
      // photos, but the bulk of it is generic. In case it is needed for other
      // purposes, please separate out the first line (G.sl.event) as it is
      // applicable only if this function is called only while turning aerial
      // photos on/off.

      // *** Draw and label methods

      // Label all features which need labeling.
      protected function geofeatures_label() :void
      {
         // MAYBE: PERFORMANCE: Old comment (pre-2013): This is being called
         //                     when zooming and takes a lot of time.
         //                     That is, it starves the rest of flashclient.
         //                     Use callLater to split up this long operation?
         var layer:Map_Layer;
         var tstart:int = G.now();
         for each (layer in this.layers_ordered) {
            layer.geofeatures_label();
         }
         m4_DEBUG_TIME('Map_Canvas.geofeatures_label');
      }

      //
      protected function geofeatures_labels_discard() :void
      {
         var layer:Map_Layer;
         var tstart:int = G.now();
         // Discard and recreate the label layer.
         this.feat_labels = (this.child_replace(
                              this.feat_labels,
                              new Map_Layer_Passive(this.feat_labels.zplus))
                             as Map_Layer_Passive);
         // Reset feature labeling
         for each (layer in this.layers_ordered) {
            layer.labels_reset();
         }
         m4_DEBUG_TIME('Map_Canvas.geofeatures_labels_discard');
      }

      // Redraw all the map features
      public function geofeatures_redraw() :void
      {
         var tstart:int = G.now();
         var layer_i:int;
         if (this.last_redraw_index == -2) {
            layer_i = 0;
         }
         else {
            layer_i = this.last_redraw_index;
         }
         if (layer_i < this.layers_ordered.length) {
            var layer:Map_Layer = this.layers_ordered[layer_i];
            m4_DEBUG2('geofeatures_redraw: geofeatures_redraw: layer:',
                      Strutil.class_name_tail(String(layer)));
            var redraw_finished:Boolean;
            redraw_finished = layer.geofeatures_redraw();
            this.last_redraw_index = layer_i;
            if (redraw_finished) {
               this.last_redraw_index += 1;
            }
         }
         if (this.last_redraw_index >= this.layers_ordered.length) {
            if (this.loc_visible !== null) {
               this.loc_visible.draw();
            }
            this.last_redraw_index = -2;
         }
         else {
            m4_DEBUG_CLLL('>callLater: this.geofeatures_redraw');
            this.callLater(this.geofeatures_redraw);
         }
         m4_DEBUG_TIME('Map_Canvas.geofeatures_redraw'); // Uses tstart.
      }

      //
      public function geofeatures_redraw_and_relabel() :Boolean
      {
         m4_DEBUG('geofeatures_redraw_and_relabel: geofeatures_redraw');
         var completed:Boolean = true;
         var tstart:int = G.now();
         m4_DEBUG_CLLL('<callLater: geofeatures_redraw_and_relabel');
         this.geofeatures_redraw();
         // FIXME Label before getting attachments (annotations, really), since
         // that operation takes so dang long, and user is staring at
         // incomplete map for too long... or maybe stop spinning after
         // geofeatures received but still waiting on annotations.
         this.geofeatures_relabel();
         //this.geofeatures_labels_discard();
         this.search_results_draw();
         //
         m4_DEBUG_TIME2('Map_Canvas.geofeatures_redraw_and_relabel',
            (G.now() - tstart), 'ms');
         return completed;
      }

      // Clear all labels and relabel the map
      public function geofeatures_relabel() :void
      {
         var tstart:int = G.now();
         this.geofeatures_labels_discard();
         this.geofeatures_label();
         m4_DEBUG_TIME('Map_Canvas.geofeatures_relabel');
      }

      // MAYBE: Is this (really) the proper package for this fcn.?
      public function search_results_draw() :void
      {
         // Remove all sprites.
         while (this.searches.numChildren > 0) {
            this.searches.removeChildAt(0);
         }
         while (this.search_geoms.numChildren > 0) {
            this.search_geoms.removeChildAt(0);
         }
         // Add sprites, if search panel active.
         m4_DEBUG2('search_results_draw: effectively_active_panel:',
                   G.panel_mgr.effectively_active_panel);
         m4_DEBUG2('search_results_draw:             search_panel:',
                   G.app.search_panel);
         if (G.panel_mgr.effectively_active_panel === G.app.search_panel) {
            var results:Array = new Array();
            var o:Object;
            for each (o in G.app.search_panel.results_list.dataProvider) {
               // Reorder results so that highlighted results are drawn
               // on top of other results.
               if ((o as Panel_Search_Result).highlighted) {
                  results.push(o as Panel_Search_Result);
               }
               else {
                  results.unshift(o as Panel_Search_Result);
               }
            }
            m4_DEBUG('search_results_draw: results.length:', results.length);
            var sr:Panel_Search_Result;
            for each (sr in results) {
               sr.draw();
               this.search_geoms.addChild(sr.geo_sprite);
               this.searches.addChild(sr);
            }
         }
      }

      // *** Attachment Mode methods.

      //
      public function attachment_mode_start(
         placebox:Widget_Attachment_Place_Box) :void
      {
         m4_DEBUG('entering attachment mode');
         G.map.tool_choose('tools_pan');
         this.attachment_placebox = placebox;
      }

      //
      public function attachment_mode_stop(skip_tool_change:Boolean=false)
         :void
      {
         m4_DEBUG('leaving attachment mode');
         if (!skip_tool_change) {
            G.map.tool_choose('tools_pan');
         }
         this.attachment_placebox = null;

         // Refresh attachment highlights.
         UI.attachment_highlights_update();
      }

      //
      public function get attachment_mode_on() :Boolean
      {
         return (this.attachment_placebox !== null ? true : false);
      }

   }
}


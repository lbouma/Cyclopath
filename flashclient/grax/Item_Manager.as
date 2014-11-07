/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.controls.Alert;

   import gwis.GWIS_Base;
   import gwis.GWIS_Checkout_Base;
   import gwis.GWIS_Checkout_Versioned_Items;
   import gwis.GWIS_Commit;
   import gwis.GWIS_Grac_Get;
   import gwis.GWIS_Item_Findability_Get;
   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Attachment;
   import items.Geofeature;
   import items.Item_Base;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.attcs.Annotation;
   import items.attcs.Attribute;
   import items.attcs.Tag;
   import items.feats.Branch;
   import items.feats.Byway;
   import items.feats.Region;
   import items.feats.Route;
   import items.feats.Track;
   import items.feats.Waypoint;
   import items.jobsq.Work_Item;
   import items.utils.Item_Type;
   import items.utils.Landmark;
   import items.utils.Stack_Id_Array;
   import utils.geom.Dual_Rect;
   import utils.geom.Geometry;
   import utils.misc.Collection;
   import utils.misc.Counter;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.misc.Strutil;
   import utils.rev_spec.*;
   import views.base.UI;
   import views.commands.Command_Manager;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_routes.Landmark_Experiment_Popup;
   import views.panel_util.Alert_Dialog;

   // COUPLING ALERT: The Item_Manager has knowledge of both the views and the
   //                 model. It's very much a controller class. E.g., it knows
   //                 what route is selected on the map, and the active branch,
   //                 and other mappy-itemmy-panelly stuff. We work closely
   //                 with Panel_Manager and Map_Canvas.

   public class Item_Manager extends Aggregator_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('GRC/ITM_Mgr');

      // *** Instance variables

      // Unique Item Stack IDs -- an ID pool for new items. This starts at -1
      // and continues negative-ward. Upon commit, the server will send us the
      // new, positive stack IDs. But until commit, this is how we track new
      // items.
      protected var fresh_id_seq:int = 0;

      // *** "Special" Items
      //
      // In CcpV1, the item classes have static class members to maintain a
      // reference to the "selected" items of certain types. E.g., if you were
      // looking at a note, the Annotation class had a static class reference
      // to that note's panel. So you could only show one note panel (which
      // also happens to obscure the geofeature panel).
      //
      // In CcpV2, we let the user create more than one selection set of the
      // same types of items, i.e., the user can have two geofeature details
      // panels that show details about two different sets of items. We also
      // don't want to couple the item classes to the panel. So we're tossed
      // out the static class references to panels and made lookups for them
      // here.
      //

      // The one, the only, the active branch.
      public var active_branch_:Branch = null;
      //
      // When the working copy is changing, this is the loading branch stack ID
      public var branch_id_to_load:int = 0;

      // A lookup of user's creation rights by item type.
      public var create_allowed_by_type:Dictionary = new Dictionary();

      // A list of outstanding GWIS_Checkouts for item details -- we only get
      // a subset of an item's data when we load the map, but when the user
      // selects items on the map, we load additional data.
      protected var lazy_load_reqs:Set_UUID = new Set_UUID();

      // The is a list of locally deleted items. These are either existing
      // items from the server, or they're items the user created in their
      // working copy but then deleted. Regarding the latter, we have to
      // keep a copy of locally-deleted "fresh" items (with client IDs;
      // never saved to the server) because of how link_values work.
      // NOTE: By design, this only contains unadultered stack_ids, i.e., not
      //       (diff) new or old, since this collection cannot be used in Diff
      //       mode.
      public var deletedset:Dictionary = new Dictionary();
      // This is needed for items we delete and save so we don't confuse them
      // with unsaved deleted items.
      public var donedeleted:Dictionary = new Dictionary();
      // 2013.06.03: [lb] finally moving dirtyset here. Hopefully your brains
      // will adjust to typing G.item_mgr.dirtyset instead of G.map.dirtyset.
      // The dirtyset contains map items and other items the user has edited.
      public var dirtyset:Set_UUID = new Set_UUID();
      // 2014.08.19: So we only bug the user once about the power of delete.
      public var on_delete_warned_once:Boolean = false;

      // Region of the Day. This is an old experiment that's no longer enabled
      // and hasn't been tested for CcpV2. It's a cool idea, though. And maybe
      // something we want for, e.g., Greater Minnesota.
      public var region_of_the_day:Region = null;

      // ***

      // MAYBE: That we store the active route is a CcpV1 hold-over: since
      //        CcpV3 handles multiple route panels, and since a route is
      //        only selected -- and hence, only active -- when its panel
      //        is active, we should _calculate_ the active_route rather
      //        than manage a handle to it. That is, we should check
      //        effectively_active_panel and use its route (if it's
      //        a route details panel...). Nonetheless, the code is already
      //        wired, and with multiple route panels this still seems to work,
      //        so, so be it.
      protected var active_route_:Route = null;

      // ***

      // MAYBE: These variables feel more mappy. Should we move them to the map
      //        canvas classes?

      // If highlighted_attachment is set, the user is looking at a
      // Geofeature detail panel and clicked on a note in the list -- which
      // means, add a highlight to all items on the map to which the note
      // is attached. This does not affect the map selection set.
      //
      // MAYBE: Rather than being in Item_Manager, feels more mappy; move there
      public var highlighted_attachment:Attachment;

      // When the user selects and double-clicks one or more items in the map,
      // we "lock" or "group" the vertices, so that dragging one vertex drags
      // them all (so you can move the whole block or the whole group of
      // blocks).
      // FIXME: This is a canvas activity. Does it belong in the Item Manager?
      public var vertices_selected:Boolean = false;

      // NOTE: saving_discussion is only used for defensive programming, i.e.,
      //       assurting. So while it doesn't really belong here (it belongs
      //       somewhere in the panel_discussions code) it also doesn't really
      //       matter.
      public var saving_discussion:Boolean;

      // 2014.05.11: [lb] keeping this new, little-used attribute out of
      // Geofeature class and adding it here (which avoids object bloat,
      // since we instantiate thousands of Geofeatures, and this feature
      // will not be used very often).
      // This is a lookup of previous item versions, since we don't want
      // to add these to any of the normal item lookups.
      // NOTE: This class is just a dumping ground; other classes manage the
      //       past_versions lookup, which maps stack IDs -> Arrays of items,
      //        where each array is indexed by (item version - 1).
      public var past_versions:Dictionary = new Dictionary();

      // *** Lists of Item Classes and Functions

      // Currently, item lists are static class variables of the item classes
      // themselves. Static class variables are generally Bad, in that they're
      // Lazy Solutions, but there's currently no Compelling Reason to stop
      // capitalizing on them, so here's a patch: this is the list of all the
      //    public static var all:Dictionary;
      // lists found in the item classes.

      protected static var item_all_cleanups:Array = [
         //
         Byway.cleanup_all,
         Region.cleanup_all,
         Waypoint.cleanup_all,
         //
         Route.cleanup_all,
         //
         Attribute.cleanup_all,
         Tag.cleanup_all,
         //
         Geofeature.cleanup_all,
         Attachment.cleanup_all,
         Link_Value.cleanup_all,
         //Nonwiki_Item.cleanup_all,
         //
         //Tile.cleanup_all,
         ];

      protected static var item_all_base_classes:Array = [
         Geofeature,
         Attachment,
         Link_Value,
         //Nonwiki_Item,
         ];

      // *** Constructor

      public function Item_Manager()
      {
         super();
      }

      // *** Dealing with Items

      // Item_Revisioned stack ID lookup.

      // Assigns the Item_Versioned a unique 'fresh' id.  This is to make
      // distinctions between new Item_Versioned's on the same client.
      // When sent to the server, the negative fresh id's are mapped to the
      // permanent id's.
      //
      // feature must have an id of 0.  0 is the invalid id number and is
      // used for tempory Geofeatures during creation, etc.
      // FIXME Check the trunk; I don't find evidence of the last comment
      // FIXME Should this fcn. and the next be moved to Item_Revisioned?
      public function assign_id(item:Item_Versioned) :void
      {
         // FIXME: Should bless_new come before assign_id, such that this fcn.
         //        only works if user has editor access to the item?
         m4_ASSERT(item.invalid);
         // DEVS: CAVEAT: Callers are responsible for ensuring that the item
         //               has been removed from all system lookups, i.e., a
         //               lot of Dictionaries are keyed by items' stack_ids.
         item.stack_id = this.assign_id_new();
         // Skipping: version and system_id.
         if (G.item_mgr.active_branch !== null) {
            // Is this right? What about tags?
            item.branch_id = G.item_mgr.active_branch.stack_id;
         }
         m4_ASSERT_ELSE_SOFT;
      }

      //
      public function assign_id_new() :int
      {
         this.fresh_id_seq--;
         return this.fresh_id_seq;
      }

      //
      public function assign_id_reset() :void
      {
         this.fresh_id_seq = 0;
         m4_ASSERT(false); // Not called.
         // MAYBE: To implement, would need to verify places that are using
         //        client IDs are updated or cleared. Like the access style / 
         //        sharing widget, which displays different text based on if
         //        user responded before about an item's permissions.
         //        See also update_items_committed.
      }

      // Item_Manager's deletedset stores the actual object in it, so this
      // utility checks to see if the given id is present in the set.
      public function is_item_deleted(stack_id:int) :Boolean
      {
         var item:Item_Versioned = this.item_deleted_get(stack_id);
         return (item !== null);
      }

      //
      public function item_deleted_get(stack_id:int) :Item_Versioned
      {
         var item:Item_Versioned;

         var item_dels:Item_Versioned;
         var item_done:Item_Versioned;
         item_dels = this.deletedset[stack_id];
         item_done = this.donedeleted[stack_id];
         if (item_dels !== null) {
            item = item_dels;
            if (item_done !== null) {
               // Do either of these happen?
               m4_ASSERT_SOFT(item_dels === item_done);
               m4_ASSERT_SOFT(false);
            }
         }
         else if (item_done !== null) {
            item = item_done;
         }

         return item;
      }

      // Find an item without knowing its item type by stack ID.
      public function item_here_there_anywhere(client_id:int)
         :Item_Versioned
      {
         var item:Item_Versioned = null;
         var items_found:int = 0;
         var item_class:Class;
         for each (item_class in Item_Manager.item_all_base_classes) {
            if (client_id in item_class.all) {
               // Find the item by its client ID or permanent ID.
               item = item_class.all[client_id];
               m4_DEBUG2('_here_there_anywh: item_class.all[client_id]:',
                         client_id, '/ item:', item);
               //
               m4_ASSERT(items_found == 0);
               items_found += 1;
            }
         }
         if (item === null) {
            // Maybe it's a deleted item.
            item = this.item_deleted_get(client_id);
            m4_DEBUG2('_here_there_anywh: item_deleted_get(client_id):',
                      client_id, '/ item:', item);
         }
         // If Nonwiki, there should be no hits, otherwise there should be
         // one hit, from Attachment.all, Geofeature.all, or Link_Value.all.
         m4_ASSURT(items_found <= 1);
         return item;
      }

      // Update items that have been saved, or whose permissions were saved.
      public function update_items_committed(
         client_id_map:Dictionary,
         command_mgr:Command_Manager,
         gwis_req:GWIS_Commit)
            :void
      {
         // The Link_Value items are special: they store references to the
         // attachment and geofeature objects but also their stack IDs.
         Link_Value.update_items_committed(client_id_map);

         // Find the item, unset its Dirty_Reason flags, reset its GIA per
         // style_change, update its stack_id, etc.
         m4_DEBUG('update_items_committed: client_id_map:', client_id_map);
         var commit_info:Object = null;
         for each (commit_info in client_id_map) {
            // 2013.04.02: [lb] originally wrote a not-well tested for-loop on
            // the string keys of Dictionary, and parsed these back to the
            // cli_id int. [mm] fixed this to use parseInt (a Flex fcn that
            // converts hex and ignores whitespace). But [lb] now figures
            // adding cli_id to the Object and using for-each makes even
            // more sense.
            // var client_id:int = (key_ as int);
            // var client_id:int = parseInt(key_);
            var client_id:int = commit_info.cli_id;
            var permanent_id:int = commit_info.new_id;
            m4_VERBOSE4(' .. commit_info: client_id:', client_id,
                                    '/ permanent_id:', permanent_id,
                                    '/ new_version:', commit_info.new_vers,
                                    '/ commit_info:', commit_info);

            var item:Item_Versioned = null;
            item = this.item_here_there_anywhere(client_id);
            if (item === null) {
               // Nonwiki items do not use a class lookup, so if the item was
               // in memory, it's just being managed by a panel widget.
               // Also, node endpoints will be processed by the Byway during
               // update_item_committed.
               m4_DEBUG3('update_items_committed: not found:',
                         '/ client_id:', client_id,
                         '/ permanent_id:', permanent_id);
            }
            else {
               m4_DEBUG2('update_items_committed: cli_id:', client_id,
                  '/ prm_id:', permanent_id, '/ item:', item.toString());
               // Tell the item that the save was a-okay.
               item.update_item_committed(commit_info);
               // Remove any commands from the Command_Manager to which this
               // item belongs.
               if (command_mgr !== null) {
                  // NOTE: Even if a command has other items attached to it, it
                  //       will still be removed if this item belongs to it.
                  //G.map.cm.clear(item);
                  command_mgr.clear(item);
               }

               // Is this item still dirty?
               //m4_DEBUG(' still dirty?: item:', item);
            }
         }

         // Check for uncommitted, deleted freshies.
         // E.g., if you split a byway, and then rejoin the splits, and then
         // save, the two, fresh, unsaved splits are dirty and their command
         // wasn't cleared.
         // 2014.02.04: This isn't just freshies. This is any deleted item.
         // 2014.09.14: This also happens when you drag a byway endpoint to the
         //             middle of another byway, create an xsection, and save.
         var deleted_freshie:Item_Versioned = null;
         for each (deleted_freshie in this.deletedset) {
            m4_DEBUG(' deleted_freshie:', deleted_freshie);
            commit_info = null;
            deleted_freshie.update_item_committed(commit_info);
            if (command_mgr !== null) {
               //G.map.cm.clear(deleted_freshie);
               command_mgr.clear(deleted_freshie);
            }
         }

         // For OOB requests, like Byway Ratings, if there's no undo/redo
         // stack, there's no command manager.
         if (command_mgr !== null) {

            m4_DEBUG2('update_items_committed: command_mgr.undos.length:',
                      command_mgr.undos.length);
            m4_DEBUG2('update_items_committed: command_mgr.redos.length:',
                      command_mgr.redos.length);

            m4_ASSERT_SOFT(command_mgr.undos.length == 0);
            m4_ASSERT_SOFT(command_mgr.redos.length == 0);

            m4_DEBUG2('update_items_committed: command_mgr.unsaved_change_ct:',
                      command_mgr.unsaved_change_ct);

            // 2014.09.16: Fired on a user.
            m4_ASSERT_SOFT(command_mgr.unsaved_change_ct == 0);
            if (command_mgr.unsaved_change_ct != 0) {
               G.sl.event('error/item_mgr/unsaved_change_ct',
                          {unsaved_change_ct: command_mgr.unsaved_change_ct,
                           command_mgr: command_mgr.toString(),
                           client_id_map: client_id_map,
                           gwis_req: gwis_req.toString()
                          });
            }

            command_mgr.clear();
         }

         // Tell the editing tool palette to fix its buttons.
         UI.editing_tools_update();
      }

      // *** Dealing with panels

      //
      public function item_panel_create(item:Item_Versioned) :Detail_Panel_Base
      {
         m4_DEBUG('item_panel_create: item:', item);
         var pnl_class:Class;
         var the_panel:Detail_Panel_Base = null;
         pnl_class = Introspect.ctor(item).dpanel_class_static;
         m4_DEBUG('item_panel_create: pnl_class:', pnl_class);
         if (pnl_class !== null) {
            the_panel = new pnl_class();
            G.panel_mgr.panel_register(the_panel);
            m4_DEBUG2('item_panel_create: item:', Strutil.snippet(item.name_),
                      '/ pnl:', the_panel);
         }
         m4_ASSERT_ELSE_SOFT;
         return the_panel;
      }

      // *** Item Class helpers

      // NOTE: For now, the classes themselves maintain lookups of items of
      // their type using class attributes. Ideally, the Item_Manager should
      // shoulder the burden of managing these collections, so that we're not
      // limited to one per class (that is, if Item_Manager managed items, we
      // could maintain two different maps in memory; currently, we can't).
      // SIMILAR_TO: Grac_Manager.cleanup_grac_lookups.
      // This fcn. is called by Item_Manager.discard_reset()
      public function cleanup_item_lookups() :void
      {
         m4_DEBUG('cleanup_item_lookups: zapping itms fr. local working copy');

         // Disable the attachment highlight.
         this.highlighted_attachment = null;

         // Clear our list of deleted items. This also happens in
         // discard_restore, so this probably isn't necessary, but it's
         // complete.
         this.deletedset = new Dictionary();
         this.donedeleted = new Dictionary();

         // MAYBE: Are we missing other attributes of ours to clear?
         //        Look above where we declare 'em all...

         // Each item type manages their own item collections. Clear 'em.
         var cleanup_f:Function;
         for each (cleanup_f in Item_Manager.item_all_cleanups) {
            cleanup_f();
         }
         // Skipping: Tile.cleanup_all();
         //           (See Map_Canvas_Items.tiles_clear().)

         this.create_allowed_by_type = new Dictionary();
      }


      // *** Dealing with Branches

      //
      [Bindable] public function get active_branch() :Branch
      {
         m4_VERBOSE('get active_branch:', this.active_branch_);
         return this.active_branch_;
      }

      //
      public function set active_branch(branch:Branch) :void
      {
         m4_DEBUG('set active_branch: branch:', branch);
         m4_DEBUG2('set active_branch: active_branch_:',
                   this.active_branch_);

         //m4_ASSERT( === null);
         /*/
         if ((this.active_branch_ === null)
             && (Branch.ID_PUBLIC_BASEMAP == 0)) {
            m4_ASSERT(branch.parent_id == 0);
            Branch.ID_PUBLIC_BASEMAP = branch.stack_id;
         }
         /*/
         m4_ASSERT(Branch.ID_PUBLIC_BASEMAP > 0);
         this.active_branch_ = branch;
         this.branch_id_to_load = 0;
         if (branch !== null) {
            m4_ASSERT(branch.revision !== null);
            // Hrm. Whatever?
            //      rev_viewport is null,
            //       or it's the same revision as branch.revision,
            //      but it's not the same object.
            //      So this fires.
            //      Do we care? [lb] thinks we should use equals(),
            //      and not object comparison. I.e., logically
            //      equivalent, but not necessarily the same
            //      object in memory.
            // m4_ASSERT_SOFT(branch.revision === G.map.rev_viewport);
            // if (branch.revision !== G.map.rev_viewport) {
            // m4_ERROR('set active_branch: branch.revision', branch.revision);
            // m4_ERROR('set active_branch: rev_viewport', G.map.rev_viewport);
            // }
         }
         // else, user is changing branches, which set this.active_branch to
         //       null and this.branch_id_to_load to the desired branch ID.
         // FIXME: Indicate that it's loading?

         // Alert listeners that the branch changed (or is changing).
         // Search: branchChange/on_active_branch_change.
         m4_DEBUG('dispatchEvent: branchChange/branch_change');
         // MAYBE: It's selectionChanged, so why isn't this branchChanged?
         this.dispatchEvent(new Event('branchChange'));

         // This feels... weird here.
         // Get the user's grpa records, if applicable.
         if (branch !== null) {
            if (branch.can_arbit) {
               var rev:utils.rev_spec.Base = new utils.rev_spec.Current();
               var qfs:Query_Filters = new Query_Filters();
               qfs.only_stack_ids.push(branch.stack_id);
               var resp_items:Array = null;
               var buddy_ct:Counter = null;
               var grac_req:GWIS_Grac_Get = new GWIS_Grac_Get(
                  null, 'group_item_access', 'item', rev, G.grac,
                  resp_items, buddy_ct, qfs);
               var found_duplicate:Boolean;
               found_duplicate = G.map.update_supplemental(grac_req);
               m4_ASSERT_SOFT(!found_duplicate);
            }
         }
      }

      // *** Dealing with Jobs

      // FIXME: Why are these static?

      //
      public static function do_job(the_job:Work_Item,
                                    job_act:String,
                                    callback_load:Function) :void
      {
         var gwis_req:GWIS_Base;
         gwis_req = Item_Manager.make_job(the_job, job_act, callback_load);
         if (gwis_req !== null) {
            var found_duplicate:Boolean;
            found_duplicate = G.map.update_supplemental(gwis_req);
            m4_ASSERT_SOFT(!found_duplicate);
         }
         // FIXME: Do we have to mark the job undirty when finished?
      }

      //
      public static function make_job(the_job:Work_Item,
                                      job_act:String,
                                      callback_load:Function) :GWIS_Base
      {
         // C.f. Widget_Shapefiles.merge_job_create
         m4_DEBUG('do_job:', job_act);
         // Setup the job.
         the_job.job_act = job_act;
         // NOTE: Only branch arbiters or better can schedule jobs?
         // FIXME: 2012.05.15: Nip currently gives users editor access
         //        to jobs. Do we need to specify items_access_min still?
         // BUG nnnn: When Branch roles is implemented, revisit this fcn.
         //    for one, acl is determined in part by branch role
         // FIXME: This smells funny: Go with what the nip says and just use
         //        client here??
         //var items_access_min:int = Access_Level.editor;
         var items_access_min:int = Access_Level.client;
         var items_must_exist:Boolean = false;
         var is_prepared:Boolean = G.grac.prepare_item(
                  the_job, items_access_min, items_must_exist);
         // BUG nnnn: Do not show jobs tab when user cannot view jobs
         // BUG nnnn: For branch job mods, do not show
         //   cancel/suspend/delete if user cannot edit jobs
         //   (but do show download and progress, and username
         //
         var gwis_req:GWIS_Base = null;
         if (is_prepared) {
            the_job.dirty_set(Dirty_Reason.item_data, true);
            //
            // Commit the job.
            var jobsset:Set_UUID = new Set_UUID();
            jobsset.add(the_job);
            gwis_req = new GWIS_Commit(
               jobsset,
               /*changenote=*/'',
               /*be_silent=*/true,
               callback_load,
               /*callback_fail=*/null,
               /*callback_payload=*/null,
               /*anon_coward=*/false,
               /*restrict_dirty=*/Dirty_Reason.item_data,
               /*alert_on_activity=*/false,
               /*command_mgr=*/null);
            // Mark the job no longer dirty. Even in the commit fails, this
            // isn't like a normal save; we're a one-time-only affair. (And if
            // we don't mark it not dirty, it'll be added to the next map
            // commit.)
            the_job.dirty_set(Dirty_Reason.item_data, false);
         }
         else {
            m4_ERROR2(
               'make_job: user used ui ctrl that should not there for them')
            Alert.show('Oops! Sorry, you do not have permission to do that.',
                       'Access denied');
         }
         return gwis_req;
      }

      // *** Dealing with Notes, Points and Regions

      // FIXME: Coupling. These fcns are view-related; should be in view class.
      //        And why are these static? Totes utility fcns...

      // FIXME: Why are these static?

      //
      public static function set show_facils(vis:Boolean) :void
      {
         if (G.map.zoom_is_vector()) {
            m4_DEBUG('set show_facils: geofeatures_redraw');
            G.map.geofeatures_redraw();
         }
      }

      //
      public static function set show_links(vis:Boolean) :void
      {
         if (G.map.zoom_is_vector()) {
            m4_DEBUG('set show_links: geofeatures_redraw');
            G.map.geofeatures_redraw();
         }
      }

      //
      public static function set show_points(vis:Boolean) :void
      {
         var point:Waypoint;
         for each (point in Waypoint.all) {
            point.visible = (vis && (!point.hidden_by_filter()));
            if (!point.visible) {
               point.set_selected(false);
            }
            else {
               // Must redraw the labels because they were previously
               // filtered from the view.
               point.draw_all();
            }
         }
         // FIXME: Coupling: Fire an event rather than managing the UI here.
         G.tabs.settings.settings_panel.tag_filter_list.update_tags_list();
         if (!G.map.zoom_is_vector()) {
            G.tabs.settings.settings_panel.tag_filter_list.enabled = vis;
         }
      }

      //
      public static function set show_regions(vis:Boolean) :void
      {
         m4_DEBUG('set show_regions: vis:', vis);
         var region:Region;
         for each (region in Region.all) {
            region.visible = (vis && (!region.hidden_by_filter()));
            if (!region.visible) {
               region.set_selected(false);
            }
            else {
               // Must redraw the labels because they were previously
               // filtered from the view
               region.draw_all();
            }
         }
         G.tabs.settings.settings_panel.tag_filter_list.update_tags_list();
         if (!G.map.zoom_is_vector()) {
            G.tabs.settings.settings_panel.tag_filter_list.enabled = vis;
         }
      }

      // *** Dealing with Routes

      // The route the user last found or clicked on.
      [Bindable] public function get active_route() :Route
      {
         m4_DEBUG2('get active_route:', ((this.active_route_ !== null)
                                         ? this.active_route_ : 'null'));
         return this.active_route_;
      }

      //
      public function set active_route(route:Route) :void
      {
         m4_DEBUG('set active_route: route:', route);
         //m4_DEBUG(Introspect.stack_trace());
         this.active_route_ = route;
      }

      // *** Landmarks Experiment Begin *** //

      //
      public function landmark_exp_get(deep_link_params:Object) :void
      {
         UI.popup(new Landmark_Experiment_Popup());
      }

      // *** Landmarks Experiment End *** //
      
      // ***

      //
      public function deep_link_get(deep_link_params:Object) :void
      {
         var item_type:String = null;
         var item_class:Class = null;

         var item_stack_id:int = 0;
         var stealth_secret:String = '';

         if (deep_link_params.type) {
            try {
               item_type = deep_link_params.type.toLowerCase();
               item_class = Item_Base.item_get_class(item_type);
               m4_VERBOSE('deep_link_get: item_class:', item_class);
            }
            catch (e:Error) {
               Alert.show(
                  'Oops! Sorry, the requested item type is not recognized: '
                  + item_type,
                  'Unknown item type');
            }
         }
         else {
            // The user doesn't have to specify the item type. Using the item
            // type makes our job a little easier, and it gives the user some
            // context ("Oh, this URL links to a Cyclopath route..."). But it's
            // not required, since we can get a tiny item of any item type.
            item_type = Item_User_Access.class_item_type;
            item_class = Item_User_Access;
         }

         if (item_class !== null) {
            if (Strutil.is_uuid(deep_link_params.link)) {
               stealth_secret = deep_link_params.link;
               m4_DEBUG('deep_link_get: link:', stealth_secret);
            }
            else {
               // Note that int() just returns 0 on not-a-number so use
               // parseInt, which return isNaN instead of 0.
               var parsed:* = parseInt(deep_link_params.link);
               // Actually, the last comment -- and the Flex docs -- are
               // wrong! parseInt does return 0 instead of NaN, it seems...
               // though maybe I need a *?
               if (isNaN(parsed)) {
                  Alert.show(
                     'Oops! Sorry, the requested item identifer is confusing: '
                     + 'neither UUID or integer: ' + deep_link_params.link,
                     'Unknown item identifer');
               }
               else if (!parsed) {
                  Alert.show(
                     'Oops! The item ident. should be a UUID or positive int.',
                     'Unknown item identifer');
               }
               else {
                  item_stack_id = int(parsed);
                  m4_DEBUG('deep_link_get: stid:', item_stack_id);
               }
            }
         }

         // NOTE: The deep-link is only executed on boot, so we don't bother
         //       looking in any item class lookups (e.g., Geofeature.all).

         if ((item_class !== null) && (item_stack_id || stealth_secret)) {
            this.checkout_deeplink(item_type, item_stack_id, stealth_secret);
         }
      }

      //
      protected function checkout_deeplink(item_type:String,
                                           item_stack_id:int,
                                           stealth_secret:String)
                                             :void
      {
         var rev_cur:utils.rev_spec.Base = new utils.rev_spec.Current();
         var buddy_ct:Counter = null;
         var update_req:Update_Base = null;
         var resp_items:Array = null; // GWIS_Checkout_Base will create this.
         var callback_load:Function = this.deep_link_results_load;
         var callback_fail:Function = this.deep_link_results_fail;

         var qfs:Query_Filters = new Query_Filters();
         if (item_stack_id) {
            m4_ASSURT(stealth_secret == '');
            qfs.only_stack_ids = new Stack_Id_Array();
            qfs.only_stack_ids.push(item_stack_id);
         }
         else {
            m4_ASSURT(stealth_secret != '');
            qfs.use_stealth_secret = stealth_secret;
         }
         
         qfs.include_item_stack = true;

         if (Collection.array_in(item_type, [Route.class_item_type,
                                             Track.class_item_type,])) {
            qfs.include_item_aux = true;
         }

         var gwis_cmd:GWIS_Checkout_Versioned_Items;
         gwis_cmd = new GWIS_Checkout_Versioned_Items(
            item_type, rev_cur, buddy_ct, qfs, update_req,
            resp_items, callback_load, callback_fail);

         m4_DEBUG2('deep_link_get: item_type:', item_type,
                   '/ qfs:', qfs.toString());
         var found_duplicate:Boolean;
         found_duplicate = G.map.update_supplemental(gwis_cmd);
         m4_ASSERT_SOFT(!found_duplicate);
      }

      //
      protected function deep_link_results_fail(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_WARNING('deep_link_results_fail: deep_link_get: checkout failed');
         // FIXME: Do anything special?
      }

      //
      protected function deep_link_results_load(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         if (gwis_req.resp_items.length == 1) {
            this.deep_link_results_load_impl(gwis_req, xml);
         }
         else {
            m4_ASSERT_SOFT(gwis_req.resp_items.length == 0);
            Alert_Dialog.show(
               'Item not found',
               'The item you are trying to load does not exist '
               + 'or you are not permitted to view it.');
         }
      }

      //
      protected function deep_link_results_load_impl(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         var classy_item:* = gwis_req.resp_items[0];
         var resolved_item:Item_User_Access;
         resolved_item = (classy_item as Item_User_Access);
         m4_ASSURT(resolved_item !== null);

         m4_DEBUG('deep_link_results_load: resolved_item:', resolved_item);

         // PROBABLY_OKAY: This is true for deep-linked routes. [lb]
         //                bets it's true for any deep-linked item.
         m4_DEBUG2('deep_link_results_load: hydrated?:',
                   resolved_item.hydrated);

         m4_ASSERT(G.item_mgr === this);
         // WRONG: resolved_item.init_item(this);
         G.map.items_add([resolved_item,]);

         var item_class:Class = Introspect.get_constructor(resolved_item);
         m4_DEBUG('deep_link_results_load: item_class:', item_class);
         var item_lookup:Dictionary;
         try {
            item_lookup = (item_class as Class).get_class_item_lookup();
         }
         catch (e:TypeError) {
            // TypeError: Error #1006: get_class_item_lookup is not a function.
            //
            // DEVS: If you're here, make sure the deep-link specifies any item
            // type, otherwise item_class is simply Item_User_Access, which
            // doesn't have an item lookup. E.g.,
            //   http://ccpv3/#private?type=route&link=d751db6b-...
            m4_WARNING2('deep_link_results_load: unexpected item_class:',
                        item_class);
         }

         var the_item:Item_User_Access;
         the_item = item_lookup[resolved_item.stack_id];
         if (the_item === null) {
            the_item = resolved_item;
            m4_DEBUG('deep_link_results_load: using new item:', the_item);
         }
         else {
            m4_DEBUG('deep_link_results_load:  existing item:', the_item);
         }

         if (item_class === Item_User_Access) {
            var real_item_type_id:int;
            real_item_type_id = int((gwis_req.rset_deets[0] as XML).@rtyp);
            var item_type:String = Item_Type.id_to_str(real_item_type_id);
            if (item_type) {
               m4_DEBUG2('deep_link_results_load: getting real item type:',
                         item_type);
               var item_sid:int = the_item.stack_id;
               var stealth_secret:String = '';
               this.checkout_deeplink(item_type, item_sid, stealth_secret);
            }
            else {
               m4_WARNING2('deep_link_results_load: bad real_item_type_id:',
                           real_item_type_id);
               m4_ASSURT(false);
            }
         }
         else {

            the_item.set_selected(true, /*nix=*/false, /*solo=*/true);

            // BUG nnnn: The app. first loads the user's last viewport
            // before panning and zooming... for deep links, can we get
            // the item first and then pan-zoom, to avoid essentially
            // loading the map twice.

            // BUG nnnn: You can only load deep links via URL by reloading
            //           flashclient. So make search bar accept deep links.

            // Pan and zoom if possible/applicable.
            var feat:Geofeature = (the_item as Geofeature);
            if (feat !== null) {

               var mobr_dr:Dual_Rect;
               mobr_dr = Dual_Rect.mobr_dr_from_xys(feat.xs, feat.ys);

               if (mobr_dr.valid) {
                  G.map.lookat_dr(mobr_dr);
               }
               else {
                  m4_WARNING2('deep_link_results_load: feat: !mobr_dr.valid:',
                              feat.toString());
               }

               var rt:Route = (the_item as Route);
               if (rt !== null) {
                  // Add the deep link route to the recently viewed list.
                  rt.signal_route_view();
               }
               // else, not a route, so no recent views list.

            }
         }
      }

      // *** Lazy-loading
      //
      // For most items, we only fetch what details we need when we need them.
      // For geofeatures, we can consider the different times different details
      // are fetched:
      //
      // 1. When geofeatures are first fetched for the map, we get just enough
      // details to display the item, like fetching one-way so we can draw
      // one-way labels.
      // 2. We requests additional details according to configurable display
      // options, like getting the counts of notes and discussions attached to
      // each item so we can draw attachment highlights.
      // 3. Finally, we lazy-load all the remaining item details when a user
      // selects an item, either by clicking it in the map, or by selecing it
      // in some list in some panel somewhere, like the route library.
      //
      // Following is the implementation of 3..

      //
      public function access_style_lazy_load(item:Item_User_Access) :void
      {
         m4_DEBUG_CLLL('<callLater: access_style_lazy_load');
         if (Access_Style.is_defined(item.access_style_id)) {
            // This is not a bad thing but [lb] is curious if it ever happens,
            // so outputing a warning.
            m4_WARNING('access_style_lazy_load: already loaded:', item);
         }
         else if (this.lazy_load_reqs.is_member(item.stack_id)) {
            m4_DEBUG('access_style_lazy_load: currently loading:', item);
         }
         else {
            // 2013.04.07: [lb] sees this fcn. being called multiple times
            // right after an item is selected. We could maintain some sort
            // of request-outstanding switch so that we can return early if
            // we've already sent a request, but the update_manager does a
            // good job of culling (and not sending) duplicate requests. See
            // cancel_obsoleted.

            // The access_style never changes so we can use the item's
            // Working or Current revision. If the server revision changes
            // (because someone else saves), we don't have to worry about
            // refetching this value to solve conflicts (though we'll have
            // to fetch the new version of the item, anyway).
            var rev_cur:utils.rev_spec.Base = item.revision;

            // Things we don't care about but preceed the callback params.
            var buddy_ct:Counter = null;
            var update_req:Update_Base = null;
            var resp_items:Array = null; // GWIS_Checkout_Base will create this
            // The callback params.
            //
            // MEH: This is the easy way to load access_style: Item_User_Access
            //      set-selected calls us with the item, and once we've got the
            //      access_style_id, we tell the item's details panel that it's
            //      dirty and to repopulate(). An alternative solution is to
            //      have the sharing widget initiate the lazy-load and either
            //      set its own callback or add a temporary listener on an
            //      access_style-loaded event. But that wiring doesn't feel as
            //      right to [lb], even if it seems more targeted (since the
            //      widget that needs access_level_id handles everything) but
            //      access_level_id is also a very itemy thing, so having the
            //      item and the item_manager handle everything feels righter.
            var callback_load:Function = this.access_style_results_load;
            var callback_fail:Function = this.access_style_results_fail;

            // Fetch this item by sid and ask server for item_stack details.
            var qfs:Query_Filters;
            qfs = new Query_Filters();
            qfs.only_stack_ids.push(item.stack_id);
            qfs.include_item_stack = true;
            // Get the thread count for the discussion widget.
            // Ignoring: G.tabs.settings.links_visible
            //   since maybe the user enabled it after the viewport
            //   was loaded, meaning, we dont't know if we asked for
            //   the attachment counts on viewport checkout (though [lb]
            //   supposes we could add a bool to the item object...).
            qfs.do_load_lval_counts = true;
            // At least we don't need the attrs and tags again.
            qfs.dont_load_feat_attcs = true;

            // Set the item type to an intermediate class.
            var item_type_str:String;
            if (item is Geofeature) {
               // Use geofeature class, so do_load_lval_counts does something.
               item_type_str = Geofeature.class_item_type;
            }
            else {
               // Set to the generic base class, 'item_user_access'.
               item_type_str = Item_User_Access.class_item_type;
            }

            m4_DEBUG('access_style_lazy_load: fetching for item:', item);
            var gwis_cmd:GWIS_Checkout_Versioned_Items;
            gwis_cmd = new GWIS_Checkout_Versioned_Items(
               item_type_str, rev_cur, buddy_ct, qfs, update_req,
               resp_items, callback_load, callback_fail);
            gwis_cmd.caller_data = item.stack_id;

            this.lazy_load_reqs.add(item.stack_id);

            var found_duplicate:Boolean;
            found_duplicate = G.map.update_supplemental(gwis_cmd);
            m4_ASSERT_SOFT(!found_duplicate);
         }
      }

      //
      protected function access_style_results_fail(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_WARNING('access_style_results_fail: checkout failed');
         // FIXME: Do anything special?
         var item_stack_id:int = int(gwis_req.caller_data);
         m4_ASSERT(item_stack_id > 0);
         this.lazy_load_reqs.remove(item_stack_id);
      }

      //
      protected function access_style_results_load(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         // 2013.08.13: This happens if you commit a new revision and forget
         // to update rid_max and then click on something just saved, since
         // we'll lazy-load/checkout the item_stack at the old revision, and
         // the item won't exist.
         //m4_ASSERT(gwis_req.resp_items.length == 1);
         if (gwis_req.resp_items.length != 1) {
            // DEVS: Is this happens, check the revision of the item you
            //       requested, since it might not exist back then.
            m4_WARNING('access_style_results_load: len != 1:', gwis_req);
            m4_WARNING2('gwis_req.resp_items.length:',
                        gwis_req.resp_items.length);
            // MAYBE: What's the user's access? It's probably the access
            // we assigned it when we created the item, before saving it...
            // so the new item is not marked lazy-loaded? Or maybe it has
            // no item_stack, or maybe we explicitly requested a refresh?
         }
         else {
            this.access_style_results_load_okay(gwis_req, xml);
         }

         var item_stack_id:int = int(gwis_req.caller_data);
         m4_ASSERT(item_stack_id > 0);
         this.lazy_load_reqs.remove(item_stack_id);
      }

      //
      protected function access_style_results_load_okay(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         var tiny_item:Item_User_Access = (gwis_req.resp_items[0]
                                           as Item_User_Access);
         m4_VERBOSE('access_style_results_load_okay: tiny_item:', tiny_item);
         var tiny_xml:XML = (gwis_req.rset_deets[0] as XML);
         m4_ASSERT(tiny_item.item_stack !== null);
         var access_style_id:int = tiny_item.item_stack.access_style_id;
         if (!Access_Style.is_defined(access_style_id)) {
            m4_WARNING2('access_style_results_load_okay: ! defined:',
                        access_style_id, '/ tiny_item:', tiny_item);
         }
         else {
            var item_type_id:int = int(tiny_xml.@rtyp);
            var item_type:String = Item_Type.id_to_str(item_type_id);
            var item_class:Class = Item_Base.item_get_class(item_type);
            // 2013.04.06: Flex yaps about possible unknown fcn unless you 'as'
            var item_lookup:Dictionary;
            item_lookup = (item_class as Class).get_class_item_lookup();
            var the_item:Item_User_Access;
            the_item = item_lookup[tiny_item.stack_id];
            if (the_item !== null) {
               if (access_style_id == the_item.access_style_id) {
                  m4_WARNING2('access_style_results_load_okay: equals ==:',
                              access_style_id, '/ the_item:', the_item);
               }
               else if (Access_Style.is_defined(the_item.access_style_id)) {
                  m4_WARNING2('access_style_results_load_okay: overwriting:',
                              access_style_id, '/ the_item:', the_item);
               }
               // NOTE: Overwriting the whole object, including: created_user,
               //       stealth_secret, cloned_from_id, access_style_id, and
               //       access_infer_id, and edited_*. (We could probably call
               //       clone() and be safe... assuming only attributes that
               //       are set are copied, which is what clone_once() is
               //       suppose to do... but this is more concise.)
               the_item.item_stack = tiny_item.item_stack;
               // Reset the latest_infer_id, so the item recalculates the
               // access_level_id the next time it is requested (note also
               // that the server sent its calculated value in item_stack,
               // so we'll just calculate the value to make sure our fcn.
               // works, so when the user edits grac records in flashclient,
               // we can keep groups_access updated correctly).
               the_item.latest_infer_id = null;
               // Also grabbing any Geofeature attributes we requested.
               var feat:Geofeature = (the_item as Geofeature);
               if (feat !== null) {
                  feat.annotation_cnt = int(tiny_xml.@nann);
                  feat.discussion_cnt = int(tiny_xml.@ndis);
               }

               m4_DEBUG2('access_style_results_load_okay: did: the_item:',
                         the_item);

               // m4_DEBUG('acc_sty_res_load: dispatching accessStyleLoaded');
               // this.dispatchEvent(new Event('accessStyleLoaded'));
               // Is this sufficient? If we signaled an event, each listener
               // would have to check the item stack ID to see if they care.
               m4_DEBUG('access_style_load_ok: panels_mark_dirty: the_item');
               G.panel_mgr.item_panels_mark_dirty([the_item,]);
            }
            else {
               m4_WARNING2('access_style_results_load_okay: !ok: tiny_item:',
                           tiny_item);
            }
         }
      }

      //
      public function link_values_lazy_load(feat:Geofeature) :void
      {
         var found_duplicate:Boolean;

         m4_DEBUG_CLLL('<callLater: link_values_lazy_load');

         m4_DEBUG('link_values_lazy_load:', feat);

         // FIXME: How long should/do Geofeatures cache the received attrs?
         //        When the revision changes, how do we invalidate the cache?
         //        Does this play well with editing the map?

         if (feat.invalid) {
            m4_WARNING('link_values_lazy_load: ignoring invalid feat:', feat);
         }
         else if (feat.fresh) {
            m4_WARNING('link_values_lazy_load: ignoring fresh feat:', feat);
         }
         else {

            // If the visual filter that highlights notes and discussions is
            // on, we've loaded those. If the visual filter that filters by
            // tags is on, we've loaded those, too.
            // FIXME: The tag filter does not apply to byways yet we still
            //        pre-load tags for byways?
            var links_vector:Array = new Array();

            links_vector.push(['annotation', null,]);

            links_vector.push(['tag', null,]);

            // Always fetch attributes the "slow" way.
            links_vector.push(['attribute', null,]);

            m4_ASSERT(feat.stack_id > 0);

            var qfs:Query_Filters;

            qfs = new Query_Filters();
            qfs.only_rhs_stack_ids.push(feat.stack_id);

            // We'll send one request for each item_type in links_vector.
            // FIXME: We shouldn't do this on Diff since we don't need
            //        heavyweight link_values. We can probably just use
            //        gf.attrs and gf.tags (but what about gf.notes?
            //        gf.discussions?).
            var gwis_req:GWIS_Checkout_Versioned_Items;
            var reqs:Array = Update_Base.gwis_fetch_rev_create_qf(
               links_vector,
               G.map.rev_viewport,
               qfs,
               /*callback_load=*/this.link_values_lazy_load_okay,
               /*callback_fail=*/this.link_values_lazy_load_fail);
            // Keep track of the outstanding requests.
            feat.links_lazy_loaded = false;
            // Send each of the requests.
            for each (gwis_req in reqs) {
               found_duplicate = G.map.update_supplemental(gwis_req);
               if (!found_duplicate) {
                  feat.links_reqs_outstanding += 1;
               }
               else {
                  // 2014.09.17:
                  // Sep-17 13:39:40 client error: uname: _user_anon_minnesota
                  //   / facil: error/item_mgr/lvals_lazy_load
                  //   / ts: 2014-09-17 14:39:41-04:00
                  //   / {'gwis_req': 'gwis21 [GWIS_Checkout_Versioned_Items]
                  //   / b2500677 / link_value / at: annotation / r22629
                  //   / qfs: &sids_rhs=1581045 / vers. 0'}
                  //  Sep-17 13:39:40 client error: uname: _user_anon_minnesota
                  //   / facil: error/item_mgr/lvals_lazy_load
                  //   / ts: 2014-09-17 14:39:41-04:00
                  //   / {'gwis_req': 'gwis22 [GWIS_Checkout_Versioned_Items]
                  //   / b2500677 / link_value / at: tag / r22629 /
                  //   qfs: &sids_rhs=1581045 / vers. 0'}
                  //  Sep-17 13:39:40 client error: uname: _user_anon_minnesota
                  //   / facil: error/item_mgr/lvals_lazy_load
                  //   / ts: 2014-09-17 14:39:41-04:00
                  //   / {'gwis_req': 'gwis23 [GWIS_Checkout_Versioned_Items]
                  //   / b2500677 / link_value / at: attribute / r22629
                  //   / qfs: &sids_rhs=1581045 / vers. 0'}
                  // I looked in the apache access.log and there are generic
                  // get-links requests but nothing for the specific item.
                  //  351358 1.2.3.4 - - [17/Sep/2014:13:39:36 -0500] "POST
                  //   /gwis?rqst=checkout&ityp=link_value&atyp=annotation
                  //  351359 1.2.3.4 - - [17/Sep/2014:13:39:36 -0500] "POST
                  //   /gwis?rqst=checkout&ityp=link_value&atyp=tag
                  //  351360 1.2.3.4 - - [17/Sep/2014:13:39:36 -0500] "POST
                  //   /gwis?rqst=checkout&ityp=link_value&atyp=attribute
                  // The &sids_rhs= is missing from the GWIS request...
                  //  except that they're not, because that part of
                  //  query_filters is part of the POST document and not
                  //  the URL...
                  // So I don't think this is necessary:
                  //   m4_ASSERT_SOFT(false);
                  //   G.sl.event('error/item_mgr/lvals_lazy_load',
                  //              {gwis_req: gwis_req.toString()});
               }
            }
            m4_DEBUG2('link_values_lazy_load: links_reqs_outstanding 1:',
                      feat.links_reqs_outstanding);

            // FIXME: We reset the boolean before getting the response:
            //          this.links_lazy_loaded = true
            //        but we really need three states, not two:
            //          not loaded, loading, and loaded
            //        I.e., if the response doesn't come back, system will
            //        not re-request attachments for map items, even if we
            //        deselects and reselects.

            // If this user is an item arbiter, request the group item
            // accesses.
            // FIXME: Only requesting Current revision, and not showing Diff
            //        of grpa changes.
            // FIXME: Not getting grpa records for non-geofeatures...
            if (feat.can_arbit) {

               m4_DEBUG('link_values_lazy_load: fetch_item_gia:', feat);
               var get_okay:Function = this.grac_get_okay;
               var get_fail:Function = this.grac_get_fail;
               feat.fetch_item_gia(get_okay, get_fail);

               feat.links_reqs_outstanding += 1;

               // This is hacky/coupled, but [lb] is tired...
               if (G.user.logged_in) {
                  var route:Route = (feat as Route);
                  if ((route !== null) && (!route.unlibraried)) {
                     var items_lookup:Dictionary = new Dictionary();
                     items_lookup[route.stack_id] = route;
                     m4_DEBUG2('link_values_lazy_load: items_lookup:',
                               items_lookup);
                     var fbil_req:GWIS_Item_Findability_Get =
                        new GWIS_Item_Findability_Get(
                           items_lookup,
                           this.findability_get_okay,
                           this.findability_get_fail);
                     // Done: fbil_req.items_in_request = items_lookup;
                     found_duplicate = G.map.update_supplemental(fbil_req);
                     if (!found_duplicate) {
                        feat.links_reqs_outstanding += 1;
                     }
                     else {
                        m4_ASSERT_SOFT(false);
                     }
                  }
               }

               m4_DEBUG2('link_values_lazy_load: links_reqs_outstanding 2:',
                         feat.links_reqs_outstanding);
            }
         }
      }

      // ***

      //
      protected function link_values_lazy_load_fail(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_WARNING('link_values_lazy_load_fail');

         var feat:Geofeature = Geofeature.all[
            gwis_req.query_filters.only_rhs_stack_ids[0]];
         if (feat !== null) {
            this.lazy_links_waiting_decrement(/*item=*/feat,
                                              /*also_dispatch=*/false);
         }
         else {
            m4_WARNING('link_values_lazy_load_fail: no feat?:', gwis_req);
         }
      }

      //
      protected function link_values_lazy_load_okay(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_DEBUG('link_values_lazy_load_okay');
         m4_ASSERT(gwis_req.query_filters.only_rhs_stack_ids.length == 1);
         var link_values_list:Array = gwis_req.resp_items;
         var stack_id:int = gwis_req.query_filters.only_rhs_stack_ids[0];
         var feat:Geofeature = Geofeature.all[stack_id];
         var notes_to_add:Stack_Id_Array = new Stack_Id_Array();
         if (feat !== null) {
            // NOTE: Not calling G.map.geofeatures_redraw(). Item sprites
            //       will redraw themselves individually, as appropriate.
            // NOTE: Skipping this.dispatchEvent(new Event('tagsLoaded'))
            //       GWIS_Checkout_Versioned_Item will signal this event.
            // Indicate that we've lazy-loaded lvals for this geofeature.
            this.lazy_links_waiting_decrement(feat);
            if (feat.links_reqs_outstanding == 0) {
               // This is actually a little premature: we have to trust
               // ourselves that whatever happens in the for loop -- like
               // link.init and whatnot -- doesn't rely on this value, since
               // the feat is not really hydrated all the way until _after_
               // the for loop completes.
               feat.links_lazy_loaded = true;
            }
            // Load any annotations that have not been loaded (since we only
            // preload attrs and tags).
            var link:Link_Value;
            for each (link in link_values_list) {
               if (link.attc === null) {
                   if (link.link_lhs_type_id == Item_Type.ANNOTATION) {
                     // 2013.01.20: In lieu of calling Link_Value.init_add now
                     // (we can't, at least not until the annotation is loaded)
                     // put it in the stranded link_values collection.
                     Link_Value.stranded_link_values.add(link);
                     // Keep a list of annotations we want to load.
                     notes_to_add.push(link.lhs_stack_id);
                  }
                  else if ((link.link_lhs_type_id == Item_Type.ATTRIBUTE)
                           || (link.link_lhs_type_id == Item_Type.TAG)) {
                     m4_ASSERT(G.item_mgr === this);
                     // 2013.09.05: Shouldn't this be G.map.items_add?
                     //   link.init(G.item_mgr);
                     G.map.items_add([link,]);
                  }
                  else {
                     m4_WARNING('_lazy_load_callback: unexpected?', link);
                     G.break_here();
                  }
               }
               else {
                  m4_WARNING('_lazy_load_callback: link.attc set?', link);
               }
            }
            if (feat.links_reqs_outstanding == 0) {
               m4_DEBUG('_lazy_load_callback: signalling linksLoaded');
               this.dispatchEvent(new Event('linksLoaded'));
               m4_DEBUG('_lazy_load_callback: signalling featLinksLoaded');
               feat.dispatchEvent(new Event('featLinksLoaded'));
            }
         }
         else {
            m4_WARNING('lazy_load_callback: feat not found: sid:', stack_id);
         }

         if (notes_to_add.length > 0) {
            // non-empty list of notes to load in
            var qfs:Query_Filters = new Query_Filters();
            qfs.only_stack_ids = notes_to_add;

            var req:GWIS_Checkout_Versioned_Items;
            var reqs:Array = Update_Base.gwis_fetch_rev_create_qf(
               ['annotation'],
               G.map.rev_viewport,
               qfs,
               /*callback_load=*/this.notes_lazy_load_okay,
               /*callback_fail=*/this.notes_lazy_load_fail);
            // FIXME: diff: [lb] notes that diffs are now just one request,
            //              so this for-each will/should be going away...
            m4_ASSERT(reqs.length == 1);
            for each (req in reqs) {
               var found_duplicate:Boolean;
               found_duplicate = G.map.update_supplemental(req);
               m4_ASSERT_SOFT(!found_duplicate);
            }
         }
      }

      //
      protected function notes_lazy_load_fail(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_WARNING('notes_lazy_load_fail');
      }

      //
      protected function notes_lazy_load_okay(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_DEBUG('notes_lazy_load_okay');

         var notes:Array = gwis_req.resp_items;

         if (notes.length > 0) {

            // A slice() with no args clones the array. We need to clone
            // it because items_add empties the array.
            var notes_clone:Array = notes.slice();
            //
            // Add all notes, which empties the [notes] array (because
            // items_add short-circuits early if it thinks it's going
            // to starve the Flex frame).
            G.map.items_add(notes);

            var note:Annotation;
            for each (note in notes_clone) {
               // Re-insert any link values for the note.

               // 2013.09.05: Should we make sure we're using the existing
               // item, in case the note is already loaded?
               note = Attachment.all[note.stack_id];
               m4_ASSERT(note !== null);

               var to_repair:Array = Link_Value.stranded_links_for_attc(note);
               var link:Link_Value;
               for each (link in to_repair) {
                  link.update_link_value_cache();
               }
            }

            m4_DEBUG('notes_lazy_load_okay: dispatching notesLoaded');
            this.dispatchEvent(new Event('notesLoaded'));
         }
      }

      // ***

      //
      protected function findability_get_callback(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_DEBUG('findability_get_callback');
      }

      //
      protected function findability_get_okay(
         gwis_req:GWIS_Item_Findability_Get, xml:XML) :void
      {
         m4_DEBUG('findability_get_okay');
         this.findability_get_cleanup(gwis_req, xml);
      }

      //
      protected function findability_get_fail(
         gwis_req:GWIS_Item_Findability_Get, xml:XML) :void
      {
         m4_WARNING('findability_get_fail');
         this.findability_get_cleanup(gwis_req, xml);
      }

      //
      protected function findability_get_cleanup(
         gwis_req:GWIS_Item_Findability_Get, xml:XML) :void
      {
         m4_DEBUG2('findability_get_cleanup: no. items:',
                   Collection.dict_length(gwis_req.items_in_request));
         for each (var item:Item_User_Access in gwis_req.items_in_request) {
            this.lazy_links_waiting_decrement(item, /*also_dispatch=*/true);
         }
      }

      // ***

      //
      protected function grac_get_okay(gwis_req:GWIS_Grac_Get) :void
      {
         m4_DEBUG('grac_get_okay');
         this.grac_get_cleanup(gwis_req);
      }

      //
      protected function grac_get_fail(gwis_req:GWIS_Grac_Get) :void
      {
         m4_WARNING('grac_get_fail');
         this.grac_get_cleanup(gwis_req);
      }

      //
      protected function grac_get_cleanup(gwis_req:GWIS_Grac_Get) :void
      {
         m4_DEBUG2('grac_get_cleanup: no. items:',
                   Collection.dict_length(gwis_req.items_in_request));
         for each (var item:Item_User_Access in gwis_req.items_in_request) {
            this.lazy_links_waiting_decrement(item, /*also_dispatch=*/true);
         }
      }

      // ***

      //
      protected function lazy_links_waiting_decrement(
         item:Item_User_Access,
         also_dispatch:Boolean=false) :void
      {
         m4_DEBUG2('lazy_links_waiting_decrement: links_reqs_outstanding:',
                   item.links_reqs_outstanding, '/ item', item);

         if (item.links_reqs_outstanding > 0) {
            item.links_reqs_outstanding -= 1;
         }
         else {
            m4_WARNING2(
               'lazy_links_waiting_decrement: links_reqs_outstanding is 0');
         }

         if ((item.links_reqs_outstanding == 0) && (also_dispatch)) {

            item.links_lazy_loaded = true;

            m4_DEBUG('_lazy_load_callback: signalling linksLoaded');
            this.dispatchEvent(new Event('linksLoaded'));

            m4_DEBUG('_lazy_load_callback: signalling featLinksLoaded');
            item.dispatchEvent(new Event('featLinksLoaded'));
         }
      }

      // ***

      //
      public function create_allowed_get(item_type:Class) :Boolean
      {
         var allowed:Boolean = false;
         if (item_type in this.create_allowed_by_type) {
            allowed = this.create_allowed_by_type[item_type];
            m4_TALKY('create_allowed_get: found:', item_type, '/', allowed);
         }
         else {
            // If you're here, look at create_allowed_set, which is called
            // from Update_Revision.on_process_new_item_policy. You might
            // want to add an item type to its lookup.
            m4_TALKY('create_allowed_get: not found: item_type:', item_type);
         }
         return allowed;
      }

      //
      public function create_allowed_set(item_type:Class,
                                         allowed:Boolean) :void
      {
         m4_TALKY('create_allowed_set: item_type:', item_type, '/', allowed);
         this.create_allowed_by_type[item_type] = allowed;
      }

      // ***

      //
      public function get contains_dirty_any() :Boolean
      {
         var is_dirty:Boolean = false;
         if ((this.contains_dirty_revisioned) // map edits
             || (this.contains_dirty_revisionless) // routes
             || (this.contains_dirty_changeless)) { // ratings/watchers
            is_dirty = true;
         }
         return is_dirty;
      }

      //
      // NOTE: Some non-wiki items, like jobs, are committed immediately, so
      //       this fcn. doesn't pertain to those. This fcn. does pertain to
      //       non-wiki items that are instead part of the (undo/redo) command
      //       stack, such as ratings and watchers, which are collected until
      //       the users hits Save Changes.
      // 2013.12.11: The last sentence is wrong. Rating and Watchers are saved
      //             out-of-band.
      public function get contains_dirty_changeless() :Boolean
      {
         var item:Item_User_Access;
         var is_dirty:Boolean = false;
         for each (item in this.dirtyset) {
            if (item.dirty_get(Dirty_Reason.mask_changeless)) {
               is_dirty = true;
               break;
            }
         }
         m4_DEBUG2('contains_dirty_changeless:', is_dirty,
                   '/ dirtyset.length:', this.dirtyset.length);
         return is_dirty;
      }

      //
      public function get contains_dirty_revisioned() :Boolean
      {
         var item:Item_Versioned;
         var is_dirty:Boolean = false;
         for each (item in this.dirtyset) {
            if (item.dirty_get(Dirty_Reason.mask_revisioned)
                && (!(item.fresh && item.deleted))) {
               // 2013.04.02: This is a silly check for orphaned attachments.
               if (!((item.fresh)
                     && (item.is_link_parasite)
                     && (Link_Value.item_get_link_values(item.stack_id)
                         === null))) {
                  //m4_DEBUG('is_dirty:', item);
                  // MAGIC_NUMBER 16 converts to hex.
                  //m4_DEBUG2('dirty_reason:',
                  //          item.get_dirty_reason().toString(16));
                  is_dirty = true;
                  break;
               }
            }
            else {
               m4_DEBUG('not dirty:', item.toString());
            }
         }
         m4_DEBUG4('contains_dirty_revisioned:', is_dirty,
                   '/ dirtyset.length:', this.dirtyset.length,
                   '/ deletedset.length:',
                   Collection.dict_length(this.deletedset));
         return is_dirty;
      }

      //
      public function get contains_dirty_revisionless() :Boolean
      {
         var item:Item_Versioned;
         var is_dirty:Boolean = false;
         for each (item in this.dirtyset) {
            if (item.dirty_get(Dirty_Reason.item_revisionless)
                && (!(item.fresh && item.deleted))) {
               // 2013.04.02: This is a silly check for orphaned attachments.
               if (!((item.fresh)
                     && (item.is_link_parasite)
                     && (Link_Value.item_get_link_values(item.stack_id)
                         === null))) {
                  //m4_DEBUG('is_dirty:', item.toString());
                  // MAGIC_NUMBER 16 converts to hex.
                  //m4_DEBUG2('dirty_reason:',
                  //          item.get_dirty_reason().toString(16));
                  is_dirty = true;
                  break;
               }
            }
            else {
               m4_DEBUG('not dirty:', item.toString());
            }
         }
         m4_DEBUG4('contains_dirty_revisionless:', is_dirty,
                   '/ dirtyset.length:', this.dirtyset.length,
                   '/ deletedset.length:',
                   Collection.dict_length(this.deletedset));
         return is_dirty;
      }

      //
      public function get contains_dirty_non_personalia() :Boolean
      {
         var item:Item_User_Access;
         var is_dirty:Boolean = false;

         if ((this.contains_dirty_revisioned)
             || (this.contains_dirty_revisionless)) {
            is_dirty = true;
         }
         else {
            for each (item in this.dirtyset) {
               if (item.dirty_get(Dirty_Reason.notbanned_mask)) {
                  is_dirty = true;
                  break;
               }
            }
         }
         m4_DEBUG2('contains_dirty_non_personalia:', is_dirty,
                   '/ dirtyset.length:', this.dirtyset.length);
         return is_dirty;
      }

      // ***

   }
}


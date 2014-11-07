/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis.update {

   import flash.events.Event;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;

   import grax.Deep_Link;
   import grax.Dirty_Reason;
   import gwis.GWIS_Checkout_Versioned_Items;
   import gwis.GWIS_Grac_Get;
   import gwis.GWIS_Region_Names_Get;
   import gwis.GWIS_Value_Map_Get;
   import items.Item_User_Access;
   import items.attcs.Annotation;
   import items.attcs.Attribute;
   import items.attcs.Post;
   import items.attcs.Tag;
   import items.attcs.Thread;
   import items.feats.Byway;
   import items.feats.Region;
   import items.feats.Route;
   import items.feats.Waypoint;
   import items.jobsq.Merge_Job;
   import items.jobsq.Route_Analysis_Job;
   import utils.geom.Dual_Rect;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.base.UI;

// FIXME: DIFF: Attrs and Tags: Diff fetching not implemented.

   public class Update_Revision extends Update_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_Revision');

      public static const on_completion_event:String = 'updatedRevision';

      // So that Update_Viewport_Base knows when it can process geofeatures and
      // link values, we maintain a set of static variables to indicate our
      // state. This is a little hacky, but it's a simple implementation.
      // (We could key off Attribute.all !== null, etc., but that Dictionary
      // is built over many item_add calls, so we'd have to wait until it was
      // completely built before nudging the update.)
      public static var processed_draw_config:Boolean = false;
      public static var processed_attc_attributes:Boolean = false;
      public static var processed_attc_tags:Boolean = false;

      // *** Constructor

      //
      public function Update_Revision()
      {
         super();
      }

      //
      public static function reset_processed() :void
      {
         m4_DEBUG2('reset_processed: processed_draw_config: was:',
                   Update_Revision.processed_draw_config);
         Update_Revision.processed_draw_config = false;
         Update_Revision.processed_attc_attributes = false;
         Update_Revision.processed_attc_tags = false;
      }

      // *** Init methods

      //
      override protected function init_update_steps() :void
      {
         // BUG nnnn: This happens if you logout while booting the application,
         //           before any GWIS is received back. Hmmm...
         if (Update_Revision.processed_draw_config) {
            m4_WARNING('init_update_steps: already processed_draw_config');
            m4_DEBUG2('Update_Revision.processed_attc_attributes:',
                      Update_Revision.processed_attc_attributes);
            m4_DEBUG2('Update_Revision.processed_attc_tags:',
                      Update_Revision.processed_attc_tags);
         }
         m4_ASSERT(!Update_Revision.processed_draw_config);
         m4_ASSERT(!Update_Revision.processed_attc_attributes);
         m4_ASSERT(!Update_Revision.processed_attc_tags);
         // When draw config is received, geofeatures can be drawn. On attrs
         // and tags, highlights and labels can be applied and attr link values
         // can be fetched.
         // Only fetch when appropriate: some information isn't revisioned, so
         // it inherently applies only to the Current revision, including the
         // draw config, the tag list, and the region names list. The tag list
         // and region names list are only used to help the user edit items and
         // work with routes, so their historic context is meaningless. New
         // Item Policies are revisioned, but only for research purposes: items
         // can only be saved at the current revision, so the historic new item
         // policy is also meaningless (I [lb] guess, though a user might be
         // curious to see a branch's old new_item_policy, but that should be
         // implemented with a new container, and not by overwriting the
         // Current list of nips).
         //if (this.rev is utils.rev_spec.Working) {
         if (this.rev is utils.rev_spec.Follow) {
            // Deprecated:
            //   this.update_steps.push(this.update_step_draw_config);
            this.update_steps.push(this.update_step_new_item_policy);
            this.update_steps.push(this.update_step_region_names);
            // 2013.05.06: draw_class/draw_param_joined replaced by skins.
            m4_DEBUG_CLLL('>callLater: _upd_stps: on_process_draw_config');
            G.map.callLater(this.on_process_draw_config);
         }
         else {
            m4_DEBUG('init_update_steps: this.rev:', this.rev.friendly_name);
            m4_ASSERT(this.rev is utils.rev_spec.Pinned);
            // We should have already got the draw config.
            ////m4_ASSERT(!(Collection.dict_is_empty(Conf.draw_param)));
            //m4_ASSERT(!(Collection.dict_is_empty(Conf.tile_skin)));
            //Update_Revision.processed_draw_config = true;
            m4_DEBUG_CLLL('>callLater: _upd_stps: on_process_draw_config');
            G.map.callLater(this.on_process_draw_config);
            // We don't need update_step_new_item_policy b/c we can leave it
            //   empty -- user has no rights to create items in a Pinned rev.
            m4_ASSERT(Collection.dict_is_empty(
                      G.item_mgr.create_allowed_by_type));
            m4_DEBUG_CLLL('>callLater: _upd_stps: on_process_new_item_policy');
            G.map.callLater(this.on_process_new_item_policy);
            // We don't need update_step_region_names b/c G.map.regions_list is
            //   only cleared when GWIS_Region_Names_Get is called.
            m4_ASSERT(G.map.regions_list is Array);
            // No callback need for update_step_region_names.
         }

         // Always fetch tags, so long as we clear Tag.all_named via
         // Item_Manager.cleanup_item_lookups (see item_all_cleanups).
         this.update_steps.push(this.update_step_tag_names);

         // We do show historic attributes, though, since they have their own
         // panel, and this'll let users see attribute changes.
         this.update_steps.push(this.update_step_attributes);
      }

      // *** Internal methods -- Init and configure update

      // *** Configure requests and callbacks

      // Get the Draw config
      protected function update_step_draw_config() :void
      {
         m4_ASSERT(false); // Deprecated. See assets/skins/skin_*.as.
         m4_DEBUG('update_step_draw_config');
         var req:GWIS_Value_Map_Get;
         // NOTE: It doesn't matter if (Conf.draw_param !== null).
         //       The old draw params are always overwritten.
         req = new GWIS_Value_Map_Get(this);
         this.requests_add_request(req, this.on_process_draw_config);
         // 2013.05.06: Adding skin support, or support for skinning.
      }

      //
      protected function update_step_tag_names() :void
      {
         m4_DEBUG('update_step_tag_names');
         // FIXME: This is the only place where we need
         //          qb.filters.skip_tag_counts = True
         //        so should we make skip_tag_counts the default?
         //        maybe not important, since flashclient should only get tags
         //        once.
         this.gwis_fetch_rev_items('tag', this.on_process_tags);
      }

      //
      protected function update_step_new_item_policy() :void
      {
         m4_DEBUG('update_step_new_item_policy: this.rev:', this.rev);
         //m4_ASSERT(this.rev is utils.rev_spec.Working);
         m4_ASSERT(this.rev is utils.rev_spec.Follow);
         var req:GWIS_Grac_Get = new GWIS_Grac_Get(
            this, 'new_item_policy', 'user', this.rev, G.grac);
         this.requests_add_request(req, this.on_process_new_item_policy);
      }

      //
      protected function update_step_region_names() :void
      {
         // Fetch the region name list, which includes private regions. It's
         // used to populate the list of regions and to autocomplete edit
         // controls.
         // NOTE: This is not a revisiony thing: we always get the region
         // names for the branch head, so one might think this better fits
         // in Update_Branch.
// FIXME: route reactions. CcpV1 gets rid of the region names fcn... why?
//        maybe it's just loading all regions now... seems wasteful!
// FIXME: Get rid of this? CcpV1 gets all regions, which is, [lb] thinks, why
//        the names list was removed (since we have the actual regions list).
//        But what if there are lots of regions and you want to filter?
//        And in CcpV2 we don't want to waste bandwidth when we don't have to.
// so this should stay, and we should BUG nnnn: Implement layering/filtering.
         var req:GWIS_Region_Names_Get = new GWIS_Region_Names_Get(this);
         this.requests_add_request(req); // no callback needed
      }

      //
      protected function update_step_attributes() :void
      {
         m4_DEBUG('update_step_attributes');
         this.gwis_fetch_rev_items('attribute', this.on_process_attributes);
      }

      // ***

      //
      protected function gwis_fetch_rev_items(item_type:String,
         completion_fcn:Function=null) :void
      {
         var reqs:Array;
         var req:GWIS_Checkout_Versioned_Items;
         var include_rect:Dual_Rect = null;
         var exclude_rect:Dual_Rect = null;
         m4_VERBOSE('gwis_fetch_rev_items: item_type:', item_type);
         // If this is a Diff, we might send multiple requests; else, just one
         reqs = this.gwis_fetch_rev_create(
            [item_type,], include_rect, exclude_rect);
         for each (req in reqs) {
            this.requests_add_request(req, completion_fcn);
         }
      }

      // *** Callbacks once request response is received and processed

      //
      protected function on_process_draw_config() :void
      {
         m4_DEBUG2('on_process_draw_config: processed_draw_config: was:',
                   Update_Revision.processed_draw_config);
         // After getting the response, tell the Viewport update it can
         // start drawing geofeatures
         Update_Revision.processed_draw_config = true;
         this.map.update_viewport_nudge();
         // Also update the tag filer list
         m4_DEBUG('on_process_draw_config: update_tags_list');
         this.requests_add_resp_post_process(
            G.tabs.settings.settings_panel.tag_filter_list.update_tags_list,
            null);
         // Refresh the Find Route dialog
         // FIXME: 2012.09.17: This has been missing. But we need it, right?
         // FIXME: Is this the right place to be doing this? Or should the
         //        component listen on an event?
         if (G.tabs.route.find_panel_ !== null) {
            m4_DEBUG('Calling G.tabs.route.find_panel.tagprefs.reload().');
            G.tabs.route.find_panel.tagprefs.reload();
            G.tabs.route.find_panel.another_tagprefs.reload();
         }
         G.deep_link.load_deep_link(Deep_Link.CONFIGURED);
      }

      //
      protected function on_process_attributes() :void
      {
         m4_DEBUG('on_process_attributes');
         // Once we have attributes, we can load link values for 'em
         Update_Revision.processed_attc_attributes = true;
         this.map.update_viewport_nudge();
         // Tell the World that the attributes were just loaded.
         m4_DEBUG('dispatchEvent: attributesLoaded');
         G.item_mgr.dispatchEvent(new Event('attributesLoaded'));
      }

      //
      protected function on_process_tags() :void
      {
         m4_DEBUG('on_process_tags');
         // Once we have tags, we can load link values for 'em.
         Update_Revision.processed_attc_tags = true;
         this.map.update_viewport_nudge();
         // Tell the World that the list of all tags was just loaded.
         m4_DEBUG('dispatchEvent: tagsLoaded');
         G.item_mgr.dispatchEvent(new Event('tagsLoaded'));
         // FIXME: Tag_Filter_Viewer
         //        (G.tabs.settings.settings_panel.tag_filter_list)
         //        catches this event: but what about Route Finder tag list?
      }

      //
      protected function on_process_new_item_policy() :void
      {
         var arr:Array;
         var item_type:Class;
         var item:Item_User_Access;
         var tool_name:String;
         var allowed:Boolean;
         // When we call bless_new, we don't want to add the item to dirtyset.
         var bless_test:Boolean = true;

         var xml:XML = null;
         var rev:utils.rev_spec.Base = new utils.rev_spec.Current();

         m4_DEBUG('on_process_new_item_policy');

         // See what item types the user is allowed to create, and modify the
         // tools accordingly.

         // NOTE: Some tools can't be decided now. Like, Vertex_Add applies to
         //       _existing_ Regions or Byways (or Terrains), so we need to
         //       check the actual item. Also Tool_Node_Endpoint_Build and
         //       Tool_Byway_Split.

         // SYNC_TO: See tool instances created in Map_Canvas_Tool().

         // Geofeatures created by map tools.
         for each (arr in
               [
               // NOTE: This is ordered like Map_Canvas_Tool()'s code.
               // Skipping: Pan_Select
               [Waypoint, ['tools_point_create']], // Tool_Waypoint_Create
               // NOTE: The Byway Split and Node Build tools make new Byways
               [Byway, ['tools_byway_create',      // Tool_Byway_Create,
                        'tools_byway_create',      // Tool_Byway_Split,
                        'tools_byway_create']],    // Tool_Node_Endpoint_Build
               [Region, ['tools_region_create']],  // Tool_Region_Create
               // Skipping: Vertex_Add (applies to existing items only)
               // Tool_Byway_Split
               // FIXME: Add? the following tools and commands?
               // [Terrain, ['tools_terrain_create']], // Tool_Terrain_Create
               // [Branch, ['tools_branch_create']], // Tool_Branch_Create
               ]) {
            item_type = arr[0];
            m4_DEBUG('  creating and blessing:', item_type);
            item = new item_type(xml, rev);
            allowed = (G.grac.bless_new(item, bless_test) !== null);
            m4_DEBUG('  allowed:', allowed);
            G.item_mgr.create_allowed_set(item_type, allowed);
            for each (tool_name in arr[1]) {
               m4_DEBUG('    configuring:', tool_name);
               // FIXME: Reset has_permissions on revision change? br change?
               this.map.tool_dict[tool_name].user_has_permissions = allowed;
            }
         }

         // Item types user may be able to create by means other than map tool.
         for each (item_type in
               [
               // Attachments
               Annotation,
               Attribute,
               Post,
               Tag,
               Thread,
               // FIXME: What about ratings and watchers?
               // Work Items
               Merge_Job,
               Route_Analysis_Job,
               // Geofeatures
               Route, // So users can clone routes.
               // FIXME/BUG nnnn: create_allowed_get(Link_Value)
               //  The new_item_policy's link_value records specify
               //  lhs and rhs item types, and sometimes even stack
               //  IDs, so the create_allowed_get mechanism doesn't
               //  work -- we would have to have it check more
               //  specific dummy Link_Values... i.e., item watcher
               //  links, bike facility links, link btw. each attr
               //  type in the attr edit list... argh.
               //   FIXME: Search: create_allowed_get Link_Value.
               //  Can't: Link_Value, // So we can en/disable link_attr wdgets
               // MAYBE: Link_Geofeature? Link_Post?
               ]) {
            m4_DEBUG('  creating and blessing:', item_type);
            item = new item_type(xml, rev);
            allowed = (G.grac.bless_new(item, bless_test) !== null);
            m4_DEBUG('  allowed:', allowed);
            G.item_mgr.create_allowed_set(item_type, allowed);
         }

         // FIXME: What about link_value permissions?
         //        I.e., can user make private watcher-attr-link_values?
         //        Are there other types of link_values that tie to a control
         //        we should enable/disable?

         // This is a little hacky, but reset the Item_Manager's deletedset and
         // dirtyset. All the calls to bless_new() added dummy items to the
         // lookups, and item_cleanup only removes item from the map and from
         // the class lookups, but not from map saving stuff.
         G.item_mgr.deletedset = new Dictionary();
         G.item_mgr.donedeleted = new Dictionary();
         G.item_mgr.dirtyset = new Set_UUID();

         // Some controls in the side panel are different depending on
         // the user's rights, so tickle the side panel panels.
         m4_DEBUG('on_process_new_item_policy: panels_mark_dirty: null');
         G.panel_mgr.panels_mark_dirty(
            //[Panel_Item_Versioned],
            null,
            Dirty_Reason.item_grac);

         // The editing tools are enabled/disabled depending on user's access.
         var access_changed:Boolean = true;
         UI.editing_tools_update(access_changed);

         // HACK: Make objects listen on G.item_mgr.active_branch
// FIXME: Does branch_and_nip_ready get reset on branch change?
//        Maybe this should be moved to public function update_revision?
//        or maybe at least out of this fcn? just verify if it's nip-specific
//        or not, since nip isn't always requested
         this.map.on_branch_and_nip_received();

         m4_DEBUG('on_process...: dispatchEvent: grac_nip_event');
         G.item_mgr.dispatchEvent(new Event('grac_nip_event'));
      }

   }
}


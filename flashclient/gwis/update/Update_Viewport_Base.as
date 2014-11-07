/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis.update {

   import flash.display.Graphics;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;

   import gwis.GWIS_Base;
   import gwis.GWIS_Checkout_Versioned_Items;
   import gwis.Update_Manager;
   import items.feats.Byway;
   import items.feats.Region;
   import items.feats.Terrain;
   import items.feats.Waypoint;
   import items.utils.Item_Type;
   import items.utils.Tile;
   import utils.geom.Dual_Rect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.base.UI;

   // FIXME If you load the map, and while it's loading, you click the aerial
   //       checkbox, how does the system react?

   public class Update_Viewport_Base extends Update_Supplemental {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_VP_Base');

      public static const on_completion_event:String = null;

      // Geofeature item types to fetch and when to fetch them
      protected static var fetch_geofeatures_always:Array;
      protected static var fetch_geofeatures_vector:Array;

      // If the user pans the map during an update, we have two options:
      // (1) fetch all items in the new view port, or (2) fetch just those
      // items we don't currently have loaded (because the user panned the map,
      // part of the view port will have items loaded, and part of it won't).
      // This flag is for debugging; usually we want to fetch just those items
      // we haven't already fetched.
      public static var debug_disable_exclude_rect:Boolean = true;

      // *** Class attributes

      // Clues about what needs fetching. When user changes zoom, tiles are
      // always fetched, but not necessarily geofeatures.
      private var zoom_level_new:int;
      // Since an int cannot represent no information, we use a Number to
      // represent the old level (which is NaN if the user just logged in).
      private var zoom_level_old:Number = NaN;
      // This is a little hack variable. It remembers the zoom level at the
      // start of updating, in case the user cancels an executing update, in
      // which case we won't know the state of the items, i.e., we won't
      // know what we've discarded from the original zoom level.
      //del?: public static var zoom_level_tmp:Number = Number.NaN;

      // Boxes defining fetch/discard behavior. See notes below and technical
      // docs on the Wiki: http://cyclopath.org/wiki/Tech:Data_Transport
      protected var rect_new_view:Dual_Rect;
      protected var rect_old_resident:Dual_Rect;
      protected var rect_items_fetch:Dual_Rect;
      protected var rect_items_keep:Dual_Rect;
      protected var rect_items_resident:Dual_Rect;

      // To handle canceling an update and issuing a new one, we track the item
      // types and their resident rects. At the start of the update, all of
      // the items share the same "resident rectangle", which is the rectangle
      // containing the items currently in memory (or in the user's working
      // copy, if you will), which is the previous view rect. At the end of the
      // update, all if the items again share the same rect, which is the new
      // view port to which the user panned. But during the update, different
      // item types will have different resident_rects, either the old viewport
      // or the new, depending on whether we've received a response from the
      // server. So when we cancel, some items we've got will be from the old
      // view rect, and some items will be from the new.
      public var rect_preserve_new:Dictionary = new Dictionary();
      // For more information on how we know what items to load, see
      // Item_Type.rect_preserve_lookup. Also, the system doesn't discard items
      // until _after_ the update operation has completed, which means the user
      // can adjust the pan while the map is still updating and we won't have
      // cleared any items previously loaded (so if the user pans too far and
      // then pans back, we won't have tossed any items yet). (This also means,
      // if the user keeps panning and panning and panning, we'll bloat the
      // system with items before finally deleting them; we'll see if there's a
      // limit to this (i.e., if flash runs out of memory or gets really
      // slow.))

      // Each of these item lookups is an Array() of Set()s which map GWIS
      // request objects to their responses. Each response is a list of items
      // to be added to the map.
      //
      // For attachements, there's just one Set, since attachments can be
      // processed whenever.
      protected var resp_attachments:Array = new Array();
      // The geofeatures lookup has a Set for each layer (terrain, byway,
      // waypoint, etc.) that are processed in order. Additionally, the very
      // first element in the Array is the Config request, since that must be
      // received and processed before any geofeatures can be rendered.
      protected var resp_geofeatures:Array = new Array();
      // Lastly, link_values can be fetched but cannot be processed until both
      // geofeatures and attachments have been received. So these get processed
      // after we process all the requests in the first two lookups.
      protected var resp_link_values:Array = new Array();

      // *** Constructor

      //
      public function Update_Viewport_Base()
      {
         super();
         Update_Viewport_Base.init_geofeature_fetch_arrays();
      }

      // *** Init methods

      //
      protected static function init_geofeature_fetch_arrays() :void
      {
         if ((Update_Viewport_Base.fetch_geofeatures_always === null)
               && (Update_Viewport_Base.fetch_geofeatures_vector === null)) {
            // These geofeatures are always fetched; applies to raster + vector

            Update_Viewport_Base.fetch_geofeatures_always = [
// FIXME: Statewide UI: Don't do this if regions layer not enabled:
               Region.class_item_type
               ];

            // These geofeatures only apply to render mode.
            Update_Viewport_Base.fetch_geofeatures_vector = [
               // NOTE The following are fetched and rendered in order.
               Terrain.class_item_type,
               Byway.class_item_type,
               Waypoint.class_item_type
               // Skipping geofeatures: region and route
               ];
         }
         else {
            m4_ASSERT(Update_Viewport_Base.fetch_geofeatures_always !== null);
            m4_ASSERT(Update_Viewport_Base.fetch_geofeatures_vector !== null);
         }
      }

      //
      override protected function init_update_steps() :void
      {
         m4_ASSERT(false); // Abstract function
      }

      //
      override protected function canceled_reset_lookups() :void
      {
         super.canceled_reset_lookups();
         this.resp_attachments = new Array();
         this.resp_geofeatures = new Array();
         this.resp_link_values = new Array();
      }

      // *** Public interface

      // Bug NNNN: Add query_filters, and extend query_filters to accommodate
      //           geofeature layer type and link value matches (Ccpln2).
      //           Maybe merge down, into Update_Supplemental?

      //
      override public function configure(mgr:Update_Manager) :void
      {
         m4_DEBUG('Configuring Update_Viewport_Base object');
         super.configure(mgr);
         // If the user pans the map, we don't have to reload items we already
         // have, so the callee tells us what the new viewport is and what the
         // old resident rect was. The intersection of the two defines the
         // rectangle of items we've already fetched that we can preserve.
         this.rect_new_view = this.map.view_rect.clone();
         if (this.map.resident_rect !== null) {
            this.rect_old_resident = this.map.resident_rect.clone();
         }
         this.zoom_level_new = this.map.zoom_level;
         //this.zoom_level_old = Update_Viewport_Base.zoom_level_tmp;
         this.zoom_level_old = this.map.zoom_level_previous;
      }

      //
      override public function equals(other:Update_Base) :Boolean
      {
         m4_ASSERT(this !== other);
         var equal:Boolean = false;
         var other_:Update_Viewport_Base = (other as Update_Viewport_Base);
         m4_DEBUG7('equals:',
            '| zoom_new:', this.zoom_level_new,
               '/', other_.zoom_level_new,
            '| zoom_old:', this.zoom_level_old,
               '/', other_.zoom_level_old,
            '| rect_new:', this.rect_new_view.gwis_bbox_str,
               '/', other_.rect_new_view.gwis_bbox_str);
         if (this.rect_old_resident !== null) {
            m4_DEBUG3('equals:',
               '| rect_old:', this.rect_old_resident.gwis_bbox_str,
               '/', other_.rect_old_resident.gwis_bbox_str);
         }
         equal = ((super.equals(other_))
                  && (this.zoom_level_new == other_.zoom_level_new)
                  // This one seems weird:
                  && (this.zoom_level_old == other_.zoom_level_old)
                  // FIXME hrm...
                  && (((this.rect_new_view !== null)
                       && (other_.rect_new_view !== null)
                       && (this.rect_new_view.eq(other_.rect_new_view)))
                      || (this.rect_new_view === other_.rect_new_view))
                  && (((this.rect_old_resident !== null)
                       && (other_.rect_old_resident !== null)
                       && (this.rect_old_resident.eq(
                                                other_.rect_old_resident)))
                      || (this.rect_old_resident ===
                                                other_.rect_old_resident)));
         return equal;
      }

      //
      override public function update_begin() :void
      {
         super.update_begin();
         this.update_init_rects();
      }

      // *** Internal methods -- Init and configure update

      //
      private function update_init_rects() :void
      {
         m4_DEBUG('update_init_rects');
         // We start with the rectangle that the user views, and we create a
         // fetch rectangle that's a little larger.
         this.rect_items_fetch = this.rect_new_view.buffer(Conf.fetch_hys);
         // Next, we make a retain rectangle that's a little larger than the
         // fetch rectangle. We don't fetch items in the rectangle, but we also
         // don't discard any that we already have in this area. This provides
         // the user a better panning experience.
         // FIXME I think the retain rect or the prefetch rect should be a
         //       little larger.
         this.rect_items_keep = this.rect_items_fetch.buffer(Conf.discard_hys);
         // If the last update request was not canceled, we don't have to fetch
         // items we already fetched.
// FIXME We should check if rev changed, like we check if user changed, or zoom
         if (this.rect_old_resident !== null) {
            this.rect_items_resident = this.rect_old_resident.intersection(
                                          this.rect_items_keep);
         }
         // For debugging, you can draw some lines to make sure the rectangles
         // are being computed properly
         this.debug_fetch_regions_draw(
            this.rect_items_fetch,
            this.rect_items_keep,
            this.rect_items_resident,
            this.rect_old_resident,
            true);
      }

      //
      protected function update_step_viewport_common() :void
      {
         m4_DEBUG('update_step_viewport_common');
         // If the zoom level changed, we need to redraw everything, lest the
         // existing items remain drawn at the prior zoom level.
         if ((isNaN(this.zoom_level_old))
             || (this.zoom_level_new != int(this.zoom_level_old))) {
            // Add the redraw as the first fcn. to process after sending the
            // GWIS_Base requests.
            this.work_queue_add_unit(this.map.geofeatures_redraw_and_relabel,
                                     null, true);
            // We don't cache tiles the user cannot see (vector vs aerial, or
            // another zoom level), so clear tiles now; this makes sure our
            // tile refetcher fcn. refetches all tiles in the viewport.
            this.map.tiles_clear();
         }

         // After receiving and loading all responses, redraw and relabel.
// FIXME Verify this does not get called on cancel, eh
         this.requests_add_resp_post_process(
            this.map.geofeatures_redraw_and_relabel, null);

         // Update the map GUI controls while we wait for the responses
         this.work_queue_add_unit(this.map.panzoom_save_fcookies,
                                  null, true);
         this.work_queue_add_unit(G.app.scale_bar.update,
                                  null, true);
      }

      // Get Geofeatures, and Their Linked-Attachments
      protected function update_step_viewport_items() :void
      {

/* what? clear vp-items lookup here, and add to it in items_add_finish,
 * and make oobs for attrs, tags, etc.? */

         if (!(this.map.zoom_is_vector(this.zoom_level_new))) {
            m4_DEBUG('update_step_viewport_items: at raster');
            // Zoom level is at or below the raster-only threshold, so discard
            // resident items.
            //
            // NOTE: Discarding here is usually redundant with the discard
            // performed in zoom_in(). It is left in place so that update()
            // will discard properly even after plain zoomto() is used.
            // FIXME Is the last comment still accurate? zoom_in calls zoomto
            //       which clears tiles but not other items.
            //
            // Add the discard routine as the first function to be executed
            // after sending all the GWIS_Base requests (note that this
            // intentionally gets added before geofeatures_redraw_and_relabel,
            // if that was just added to the queue).

            var discard_types:Set = new Set([Terrain, Byway, Waypoint,]);
            if (!G.tabs.settings.regions_visible) {
               discard_types.add(Region);
            }
            var complete_now:Boolean = false;
            var insert_first:Boolean = true;
            this.work_queue_add_unit(
               this.map.items_discard,
               [null, complete_now, discard_types],
               insert_first);

            if (G.tabs.settings.regions_visible) {
// 2013.08.24/FIXME/Bug nnnn: Whenever you load a route (double-click on one in
// the route list), we're re-requesting all the regions. Which is bad. But
// oddly, [lb] doesn't see Terrain, Byway, Waypoint being re-requested.
//
               this.work_queue_add_unit(
                  this.map.items_discard,
                  [this.rect_items_keep, complete_now, new Set([Region,])],
                  insert_first);
            }
         }
         else {
            m4_DEBUG('update_step_viewport_items: at vector');
            // After receiving and processing all items, discard what's no
            // longer in the viewport
            this.requests_add_resp_post_process(this.map.items_discard,
                                                [this.rect_items_keep,
                                                 false,
                                                 null,]);
         }

         // Rebuild nodes, update note highlights, lazy-load attr links, etc.
         this.requests_add_resp_post_process(this.map.items_add_finish, null);

         // Queue up requests for geofeatures
         this.gwis_fetch_geofeatures();
      }

      //
      protected function update_step_viewport_tiles() :void
      {
         m4_DEBUG('update_step_viewport_tiles');
         // After fetching tiles, discard tiles we no longer can see
         this.requests_add_resp_post_process(this.map.tiles_discard,
                                             [this.rect_items_keep,
                                              false,]);
         // Queue up requests for tiles
         this.gwis_fetch_tiles();
      }

      // *** Internal methods -- Prepare GWIS_Base requests

      // Fetch map features appropriate for this zoom level which intersect the
      // include rect but do not intersect the exclude rect (which may be null)
      protected function gwis_fetch_geofeatures() :void
      {
         var exclude_rect:Dual_Rect = this.rect_items_resident;

         if (this.map.zoom_is_vector(this.zoom_level_new)) {
            // Zoom level is above raster-only threshold -- fetch vectors.
            if ( (isNaN(this.zoom_level_old))
                || (!this.map.zoom_is_vector(this.zoom_level_old)) ) {
               // Previous zoom level _not_ above threshold, so no vectors
               // resident at all. Fetch all vectors in the include rect
               // without regard to the exclude rect.
               exclude_rect = null;
            }
            // else, Previous zoom level also above threshold, so exclude rect
            //       contains vectors. Fetch only vectors outside it.
            // FIXME If zooming in, this should be a no-op?
            //       Just discard newly omitted from viewport, or leave that as
            //       the resident rect, so user can zoom back out easily.
            if (!this.rect_items_fetch.eq(exclude_rect)) {
               // Get the geofeatures
               this.gwis_fetch_rev_geofeatures(
                  Update_Viewport_Base.fetch_geofeatures_vector,
                  this.rect_items_fetch, exclude_rect);
            }
            // else, this.rect_items_fetch == exclude_rect, so no-op
         }

         // Regions are always fetched, in both raster and vector modes
         if (G.tabs.settings.regions_visible) {
            this.gwis_fetch_rev_geofeatures(
               Update_Viewport_Base.fetch_geofeatures_always,
               this.rect_items_fetch, this.rect_items_resident);
         }
      }

      // Fetch map tiles appropriate for this zoom level which intersect
      // the include rect. We ignore the exclude rect since we have to iterate
      // through all of the tiles anyway, and just query the Tile lookup to see
      // what we have to fetch and what's already in memory.
      //
      // FIXME: Tiles are not permissioned nor based on branches... yet!
      protected function gwis_fetch_tiles() :void
      {
         var t:Tile;
         var xi:int;
         var yi:int;

         if ((!this.map.zoom_is_vector()) || (G.map.aerial_enabled)) {

            var xmin_i:int = Tile.coord_to_tileindex(
               this.rect_items_fetch.map_min_x);
            var ymin_i:int = Tile.coord_to_tileindex(
               this.rect_items_fetch.map_min_y);
            var xmax_i:int = Tile.coord_to_tileindex(
               this.rect_items_fetch.map_max_x);
            var ymax_i:int = Tile.coord_to_tileindex(
               this.rect_items_fetch.map_max_y);

            m4_DEBUG2('gwis_fetch_tiles: (', this.zoom_level_new,
               this.zoom_level_old, ')', xmin_i, ymin_i, xmax_i, ymax_i);

            for (xi = xmin_i; xi <= xmax_i; xi++) {
               for (yi = ymin_i; yi <= ymax_i; yi++) {
                  t = new Tile(xi, yi, G.map.aerial_enabled,
                                       G.map.aerial_layer_selected);
                  if (!Tile.tile_exists(t)) {
                     this.requests_add_req_tiles(t);
                  }
               }
            }
         }
      }

      // *** Internal methods -- Process GWIS_Base responses

      //
      override protected function gwis_results_process() :Boolean
      {
         var processed_something:Boolean = true;

         if (Logging.get_level_key('DEBUG')
             >= Update_Viewport_Base.log.current_level) {
            m4_DEBUG4('gwis_results_process:',        'no. feats:',
                      this.resp_geofeatures.length, '/ no. attcs:',
                      this.resp_attachments.length, '/ no. lvals:',
                      this.resp_link_values.length);
            var special_set:Dictionary;
            for each (special_set in this.resp_geofeatures) {
               m4_VERBOSE(' .. feats out:', special_set.toString());
            }
            for each (special_set in this.resp_attachments) {
               m4_VERBOSE(' .. attcs out:', special_set.toString());
            }
            for each (special_set in this.resp_link_values) {
               m4_VERBOSE(' .. lvals out:', special_set.toString());
            }
         }

         // Geofeature and attachments can be process simultaneously
         if ((this.resp_geofeatures.length != 0)
             || (this.resp_attachments.length != 0)) {
            if (!Update_Revision.processed_draw_config) {
               // The way CcpV2 is rigged, this shouldn't happen.
               m4_WARNING('.. still waiting on draw config');
            }
            else if (this.resp_geofeatures.length != 0) {
               m4_TALKY('gwis_results_process: processing feats');
               this.resp_geofeatures = this.gwis_complete_resp(
                  this.resp_geofeatures);
            }
            else if (this.resp_attachments.length != 0) {
               m4_TALKY('gwis_results_process: processing attcs');
               this.resp_attachments = this.gwis_complete_resp(
                  this.resp_attachments);
            }
            m4_ASSERT_ELSE_SOFT;
         }
         // Must have all geofeature and attachments before accepting links
         else if (this.resp_link_values.length != 0) {
            if (!Update_Revision.processed_attc_attributes) {
               m4_DEBUG('.. still waiting on attributes');
            }
            else if (!Update_Revision.processed_attc_tags) {
               m4_DEBUG('.. still waiting on tags');
            }
            else {
               m4_DEBUG('     links');
               this.resp_link_values = this.gwis_complete_resp(
                  this.resp_link_values);
            }
         }
         // Once the lists are empty, we're done.
         else {
            m4_DEBUG(' === all done!');
            processed_something = false;
            if (!this.canceled) {
               Item_Type.resident_rects_reset();
               // Tell the map its new resident_rect. This is kinda hacky!
               this.map.resident_rect = this.rect_items_fetch;
               // This is also hacky
               //Update_Viewport_Base.zoom_level_tmp = this.zoom_level_new;
               this.map.zoom_level_previous = this.zoom_level_new;
            }
            else {
               // The map update was canceled; update the preserve lookup
               // with the rects of items we received before we got the
               // cancel.
               Item_Type.resident_rects_merge(this.rect_preserve_new);
               // NOTE Don't need to reset Update_Viewport_Base.zoom_level_tmp
               //      - This should be handled in items_discard, which is what
               //        causes zoom_level_tmp to become obsolete.
            }
            if (this.rect_items_fetch !== null) {
               this.debug_fetch_regions_draw(
                  this.rect_items_fetch,
                  this.rect_items_keep);
            }
         }
         return processed_something;
      }

      // *** Helper fcns for internal methods

      // *** Create requests for specific item types for specific revisions

      //
      protected function gwis_fetch_rev_attachments(attachments:Array,
         include_rect:Dual_Rect=null, exclude_rect:Dual_Rect=null) :void
      {
         m4_ASSERT(false); // No longer called.
         var reqs:Array;
         var req:GWIS_Checkout_Versioned_Items;
// BUG nnnn: Diffs are now just one request.
         // If this is a Diff, we might send multiple requests; else, just one
         reqs = this.gwis_fetch_rev_create(
            attachments, include_rect, exclude_rect);
         for each (req in reqs) {
            this.requests_add_req_attachments(req);
         }
      }

      //
      protected function gwis_fetch_rev_geofeatures(geofeatures:Array,
         include_rect:Dual_Rect, exclude_rect:Dual_Rect,
         exclude_static:Boolean=false) :void
      {
         var reqs:Array;
         var req:GWIS_Checkout_Versioned_Items;
         reqs = this.gwis_fetch_rev_create(
            geofeatures, include_rect, exclude_rect);
         for each (req in reqs) {
            this.requests_add_req_geofeatures(req);
         }
      }

      //
      protected function gwis_fetch_rev_link_values(link_values:Array,
         include_rect:Dual_Rect, exclude_rect:Dual_Rect) :void
      {
         var reqs:Array;
         var req:GWIS_Checkout_Versioned_Items;
         reqs = this.gwis_fetch_rev_create(
            link_values, include_rect, exclude_rect);
         for each (req in reqs) {
            this.requests_add_req_link_values(req);
         }
      }

      // *** Add requests and work items to queues

      //
      protected function requests_add_req_attachments(req:GWIS_Base) :void
      {
         if (this.resp_attachments.length == 0) {
            this.resp_attachments.push(new Dictionary());
         }
         this.resp_lookup_sets[req] = this.resp_attachments[0];
         this.resp_attachments[0][req] = null;
         //
         this.work_queue_add_unit(req);
         // m4_DEBUG2('requests_add_req_attachments:', req, '/ queued:',
         //           this.resp_attachments);
         if (Logging.get_level_key('DEBUG')
             >= Update_Viewport_Base.log.current_level) {
            m4_DEBUG('_req_attcs: no. attcs:', this.resp_attachments.length);
            for each (var special_set:Dictionary in this.resp_attachments) {
               m4_DEBUG(' .. attcs out:', special_set.toString());
            }
         }
      }

      //
      protected function requests_add_req_geofeatures(req:GWIS_Base) :void
      {
         var group:Dictionary = new Dictionary();
         group[req] = null;
         //
         this.resp_lookup_sets[req] = group;
         this.resp_geofeatures.push(group);
         this.work_queue_add_unit(req);
         // m4_DEBUG2('requests_add_req_geofeatures:', req, '/ queued:',
         //           this.resp_geofeatures);
         if (Logging.get_level_key('DEBUG')
             >= Update_Viewport_Base.log.current_level) {
            m4_DEBUG('_req_attcs: no. feats:', this.resp_geofeatures.length);
            for each (var special_set:Dictionary in this.resp_geofeatures) {
               m4_DEBUG(' .. feats out:', special_set.toString());
            }
         }
      }

      //
      protected function requests_add_req_link_values(req:GWIS_Base) :void
      {
         if (this.resp_link_values.length == 0) {
            this.resp_link_values.push(new Dictionary());
         }
         this.resp_lookup_sets[req] = this.resp_link_values[0];
         this.resp_link_values[0][req] = null;
         //
         this.work_queue_add_unit(req);
         // m4_DEBUG2('requests_add_req_link_values:', req, '/ queued:',
         //           this.resp_link_values);
         if (Logging.get_level_key('DEBUG')
             >= Update_Viewport_Base.log.current_level) {
            m4_DEBUG('_req_attcs: no. lvals:', this.resp_link_values.length);
            for each (var special_set:Dictionary in this.resp_link_values) {
               m4_DEBUG(' .. lvals out:', special_set.toString());
            }
         }
      }

      //
      protected function requests_add_req_tiles(tile:Tile) :void
      {
         // Tiles don't currently block the loading of anything, but we still
         // want to queue up their initial GWIS_Base send
         this.work_queue_add_unit(tile);
         m4_DEBUG('requests_add_req_tiles:', tile);
      }

      // *** Developer Methods

      // Draw the fetch regions onto the map
      // This is a DEBUG fcn.
      protected function debug_fetch_regions_draw(
         fetch:Dual_Rect,
         discard:Dual_Rect,
         rprime:Dual_Rect=null,
         resident:Dual_Rect=null,
         clear_graphics:Boolean=false) :void
      {
         // NOTE this.map.graphics is its underlying UIComponent's reference,
         //      and this is the only function that draws to this.map.graphics
         var gr:Graphics = this.map.graphics;
         if (Conf.debug_draw_fetch_regions) {
            if (clear_graphics) {
               gr.clear();
            }
            // fetch -- heavy blue
            //gr.lineStyle(2, 0x0000ff);
            gr.lineStyle(4, 0x0000ff);
            gr.drawRect(fetch.cv_min_x, fetch.cv_min_y,
                        fetch.cv_width, fetch.cv_height);
            // discard -- fine blue
            if (discard !== null) {
               //gr.lineStyle(1, 0x0000ff);
               gr.lineStyle(2, 0x0000ff);
               gr.drawRect(discard.cv_min_x, discard.cv_min_y,
                           discard.cv_width, discard.cv_height);
            }
            // rprime -- heavy magenta
            if (rprime !== null) {
               //gr.lineStyle(2, 0xff00ff);
               gr.lineStyle(4, 0xff00ff);
               gr.drawRect(rprime.cv_min_x, rprime.cv_min_y,
                           rprime.cv_width, rprime.cv_height);
            }
            // resident -- fine green
            if (resident !== null) {
               //gr.lineStyle(1, 0x00ff00);
               gr.lineStyle(2, 0x00ff00);
               gr.drawRect(resident.cv_min_x, resident.cv_min_y,
                           resident.cv_width, resident.cv_height);
            }
         }
      }

   }
}


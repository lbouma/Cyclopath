/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A Byway is the smallest identifiable unit of a bikeable surface.

package items.feats {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.utils.Timer;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;
   import mx.containers.*;
   import mx.core.IToolTip;
   import mx.managers.ToolTipManager;

   import grax.Aggregator_Base;
   import grax.Dirty_Reason;
   import gwis.GWIS_Commit;
   import items.Geofeature;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.Record_Base;
   import items.attcs.Annotation;
   import items.attcs.Attribute;
   import items.attcs.Tag;
   import items.utils.Bikeability_Rating;
   import items.utils.Geofeature_Layer;
   import items.utils.Item_Type;
   import items.verts.Byway_Vertex;
   import items.verts.Vertex;
   import utils.misc.Collection;
   import utils.geom.Geometry;
   import utils.geom.MOBRable;
   import utils.misc.Draggable;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.base.App_Action;
   import views.base.Map_Layer;
   import views.base.Paint;
   import views.map_widgets.Shadow_Sprite;
   import views.ornaments.bike_facility.*;
   import views.panel_items.Panel_Item_Byway;
   import views.panel_settings.Panel_Settings;

   public class Byway extends Geofeature implements Draggable, MOBRable {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Byway');

      // *** Mandatory attributes

      public static const class_item_type:String = 'byway';
      public static const class_gwis_abbrev:String = 'by';
      public static const class_item_type_id:int = Item_Type.BYWAY;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Byway;

      // SYNC_ME: Search geofeature_layer table.
      // NOTE: The order of this is same as Widget_Item_Type dropdown items.
      public static const geofeature_layer_types:Array = [
         Geofeature_Layer.BYWAY_UNKNOWN,
         Geofeature_Layer.BYWAY_ALLEY,
         Geofeature_Layer.BYWAY_LOCAL_ROAD,
         Geofeature_Layer.BYWAY_MAJOR_ROAD,
         Geofeature_Layer.BYWAY_BIKE_TRAIL,
         Geofeature_Layer.BYWAY_MAJOR_TRAIL,
         Geofeature_Layer.BYWAY_HIGHWAY,
         Geofeature_Layer.BYWAY_EXPRESSWAY,
         Geofeature_Layer.BYWAY_EXPRESSWAY_RAMP,
         Geofeature_Layer.BYWAY_SIDEWALK,
         Geofeature_Layer.BYWAY_SINGLETRACK,
         Geofeature_Layer.BYWAY_DOUBLETRACK,
         Geofeature_Layer.BYWAY_4WD_ROAD,
         Geofeature_Layer.BYWAY_OTHER,
         Geofeature_Layer.BYWAY_RAILWAY,
         Geofeature_Layer.BYWAY_PRIVATE_ROAD,
         Geofeature_Layer.BYWAY_OTHER_RAMP,
         Geofeature_Layer.BYWAY_PARKING_LOT,
         ];

      // *** Other static variables

      // A lookup of Geofeatures by stack_id. (This is in addition to the
      // Geofeature.all lookup, since both are useful (the alternative is to
      // always loop over Geofeature.all looking for byways... so it's a
      // trade-off between speed and memory).)
      public static var all:Dictionary = new Dictionary();

      protected static var connectivity:Sprite;
      protected static var connected_byway:Byway;

      protected static var tooltip:IToolTip; // tooltip display on mouse over

      // Our parent class declares this variable, and we define it here
      // MAGIC NUMBER: Search: Z_USER_OFFSET.
      Geofeature.Z_USER_OFFSET = -129; // EXPLAIN: Magic number

      // *** Instance variables

      // NOTE: If you add an attribute, be sure to update clone().

      public var one_way:int;

      // The stack ID of the byway from which this byway was split.
      // 0 means no split this revision.
      public var split_from_stack_id:int;

      // The start and end nodes IDs are shared among byways to indicate which
      // byways connected.
      public var beg_node_id:int;
      public var fin_node_id:int;
      // Per-node values...
      // FIXME: This is the old style (having both node_endpoints' columns
      //        here); maybe we should be sending node_endpoints instead...
      //node_lhs_reference_n
      //node_lhs_referencers
      public var node_lhs_elevation_m:Number;
      //node_lhs_dangle_okay
      //node_lhs_a_duex_rues
      //
      //node_rhs_reference_n
      //node_rhs_referencers
      public var node_rhs_elevation_m:Number;
      //node_rhs_dangle_okay
      //node_rhs_a_duex_rues

      // The generic system rating, based on the Chicago Bike Federation
      // algorithm and a few other metrics.
      public var generic_rating:Number;
      // User's rating, -1 to 4: Don't Know, Excellent, Good, Fair, Impassable
      public var user_rating:int;
      // When updating map items, used to maintain private user data
      public var user_rating_update:Boolean;
      //
      // FIXME: I think rating_needed is just for Workhints
      public var rating_needed:Boolean;

      // The client-computed length of the byway
      protected var map_length:Number;

      // Show a tooltip if the user hovers the mouse over the Byway for a while
      // FIXME: This is a controller operation, and does not belong in this
      //        model class.
      protected var tooltip_timer:Timer;
      // The last mouse over event, needed for tooltip coords.
      protected var last_mouse_over:MouseEvent;

      // Sprites for byway things

      // Sprites for arrows, if the byway is a one way
      public var arrows:Sprite;
      public var arrow_tips:Sprite;

      // Sprites for the node endpoints (a box the user can drag)
      public var node_widget_start:Sprite;
      public var node_widget_end:Sprite;

      // A highlight sprite used by the Tool_Node_Endpoint_Build tool
      protected var highlight:Sprite;

      // Cache the bike_facil attribute.
      protected static var bike_facil_attr_:* = undefined;
      public static const attr_name_facil_basemap:String =
                                                   '/byway/cycle_facil';
      public static const attr_name_facil_metc:String =
                                                   '/metc_bikeways/bike_facil';

// FIXME_2013_06_14: Implement this:
      // 2013.06.14: [lb] moved the cautions to their own widget.
      protected static var cautionary_attr_:* = undefined;
      public static const attr_name_cautionary:String = '/byway/cautionary';

      // *** Constructor

      public function Byway(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         // Set the user_rating to -1, which means "Don't Know" or not rated
         this.user_rating = -1;

         super(xml, rev);

         this.shadow = new Shadow_Sprite(this);
         this.arrows = new Sprite();
         this.arrow_tips = new Sprite();
         this.arrows.addChild(this.arrow_tips);

         this.tooltip_timer = new Timer(Conf.byway_tooltip_time, 1);
         this.tooltip_timer.addEventListener(TimerEvent.TIMER,
                                             this.on_tooltip_timer,
                                             false, 0, true);

         this.map_length_update();
      }

      // *** Public Static methods

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var bway:Byway in Byway.all) {
               bway.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Byway.all = new Dictionary();

         Byway.bike_facil_attr_ = undefined;
         Byway.cautionary_attr_ = undefined;
      }

      // Set the given Byway to have connectivity displayed
      public static function connectivity_add(b:Byway) :void
      {
         if (Byway.connectivity !== null) {
            m4_WARNING2(
               'WARNING: highlight_add() while highlight still present');
            Byway.connectivity_remove();
         }

         Byway.connected_byway = b;
         Byway.connectivity = new Sprite();
         G.map.highlights.addChild(Byway.connectivity);
         Byway.connectivity.graphics.clear();

         if (G.tabs.settings.connectivity) {
//G.tabs.settings.settings_panel.settings_options.connectivity_cbox
            b.connectivity_draw(
               Byway.connectivity.graphics, 0, new Set_UUID());
         }
      }

      // Remove the connectivity and set the highlighted byway to null.
      public static function connectivity_remove() :void
      {
         m4_ASSERT(Byway.connectivity !== null);

         G.map.highlights.removeChild(Byway.connectivity);
         Byway.connected_byway = null;
         Byway.connectivity = null;
      }

      // If a connectivity highlight is present, remove it.
      public static function connectivity_remove_maybe() :void
      {
         if (Byway.connected_byway !== null) {
            Byway.connectivity_remove();
         }
      }

      // Return the selected set as an array of Byways which can be merged in
      // the order which they can be merged; if such an array cannot be built
      // (i.e., members of the selected set are not merge-compatible), return
      // null.
      //
      // NOTE: The algorithm is O(n^2) (it's basically selection sort).
      public static function mergeable_array(byway_set:Set_UUID) :Array
      {
         var tstart:int = G.now();
         var result:Array = new Array();
         var byways:Array = byway_set.as_Array();
         var i:int;
         var sl:int;

         if (byways.length < 2) {
            return null;
         }

         result.push(byways.splice(0, 1)[0]);
         while (byways.length > 0) {
            sl = byways.length; // copy b/c original changes
            for (i = 0; i < sl; i++) {
               if (byways[i].is_mergeable(result[result.length-1])) {
                  // matches end of sorted result
                  result.push(byways.splice(i, 1)[0]);
                  break;
               }
               else if (byways[i].is_mergeable(result[0])) {
                  // matches beginning of sorted result
                  result.unshift(byways.splice(i, 1)[0]);
                  break;
               }
            }
            if (i == sl) {
               // no match found
               m4_DEBUG_TIME2('Byway.mergeable_array FAILED',
                  (G.now() - tstart), 'ms');
               return null;
            }
         }

         m4_DEBUG('mergeable_array: result:', result);

         m4_DEBUG_TIME('Byway.mergeable_array');
         return result;
      }

      // *** Public instance functions

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         if (i == -1) {
            try {
               i = (G.map.layers[this.zplus] as Map_Layer).getChildIndex(
                                                             this.sprite);
            }
            catch (e:ArgumentError) {
               // Error #2025: The supplied DisplayObject must be a child of
               //              the caller.
               // No-op
            }
            catch (e:TypeError) {
               // No-op
            }
         }

         super.item_cleanup(i, skip_delete);

         // CcpV1: G.map.shadows[this.zplus].removeChildAt(i);
         if ((this.shadow) && (G.map.shadows[this.zplus] != undefined)) {
            try {
               G.map.shadows[this.zplus].removeChild(this.shadow);
            }
            catch (e:ArgumentError) {
               // No-op
            }
         }

         try {
            G.map.direction_arrows.removeChild(this.arrows);
         }
         catch (e:ArgumentError) {
            // No-op
         }

         // Remove myself from byway adjacency map
         m4_DEBUG('item_cleanup: node_mgmt: node_cleanup/beg:', this);
         G.map.node_cleanup(this.beg_node_id, this);

         if (this.beg_node_id != this.fin_node_id) {
            m4_DEBUG('item_cleanup: node_mgmt: node_cleanup/fin:', this);
            G.map.node_cleanup(this.fin_node_id, this);
         }

         this.removeEventListener(MouseEvent.MOUSE_OVER, this.on_mouse_over);
         this.removeEventListener(MouseEvent.MOUSE_OUT, this.on_mouse_out);

         this.connectivity_displayed = false;
         //
         // MAYBE: Do we need to remove the event listener?
         // this.tooltip_timer.removeEventListener(TimerEvent.TIMER,
         //                                        this.on_tooltip_timer);
         // this.tooltip_timer = null;
         //

         // Remove from loaded Byway lookup.
         // NOTE: It's up to the caller to verify that we can be deleted. Once
         //       item_cleanup is called, it's assumed we're not needed by any
         //       other items (e.g., we won't be cleaned up if an edited
         //       link_value references us).
         if (!skip_delete) {
            delete Byway.all[this.stack_id];
         }
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Byway = (to_other as Byway);
         super.clone_once(other);
         // Skipping: connectivity, connected_byway, tooltip
         other.one_way = this.one_way;
         other.split_from_stack_id = this.split_from_stack_id;
         other.beg_node_id = this.beg_node_id;
         other.fin_node_id = this.fin_node_id;
         // 2014.07.06: [lb] had an issue creating and dragging the endpoints  
         //             of a new byway the node IDs being the same... cannot
         //             yet reproduce.
         m4_TALKY2('clone_once: beg_node_id / fin_node_id:',
                   this.beg_node_id, '/', this.fin_node_id);
         other.node_lhs_elevation_m = this.node_lhs_elevation_m;
         other.node_rhs_elevation_m = this.node_rhs_elevation_m;
         other.generic_rating = this.generic_rating;
         other.user_rating = this.user_rating;
         other.rating_needed = this.rating_needed;
         // Skipping: map_length, tooltip_timer, last_mouse_over, arrows,
         //     arrow_tips, node_widget_start, node_widget_end, highlight

         // MEH: We could copy Byway link values, like speed_limit, lane_count,
         //      outside_lane_width, and shoulder_width, so that
         //      cloning an item, and reverting an item, also considers
         //      link_values, but that complicates things and might not be
         //      the correct model, anyway. Re: complication: we'd have to
         //      go through the link_values and clone them, and we'd have to
         //      make sure we handled the cloned link_values separately from
         //      the ones stored in the big lookup, Link_Value.all. Re: model:
         //      when one "reverts" an item, we'd want to revert some
         //      link_values, but not all, e.g., we wouldn't want to revert
         //      the text of an annotation, would we? As opposed to wanting to
         //      revert the tags or attributes of a specific item? Anyway,
         //      if we want "revert" to affect link_values, we have more to
         //      think about and lots of coding and debugging to make sure it
         //      works well... and then what's the payoff?
         //      Currently "revert" just affects a geofeature's name, geometry,
         //      and a few other instance attributes, but not link_values.
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Byway = (to_other as Byway);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.one_way = int(gml.@onew);
            Geometry.coords_string_to_xys(gml.text(), this.xs, this.ys);
            //m4_DEBUG('gml_consume: this.xs:', this.xs);
            //m4_DEBUG('gml_consume: this.ys:', this.ys);
            this.beg_node_id = int(gml.@nid1);
            this.fin_node_id = int(gml.@nid2);
            m4_TALKY2('a/gml_consume: beg_node_id / fin_node_id:',
                      this.beg_node_id, '/', this.fin_node_id);
            this.node_lhs_elevation_m = int(gml.@nel1);
            this.node_rhs_elevation_m = int(gml.@nel2);
            this.generic_rating = Number(gml.@grat);
            // BUG nnnn: byway_rating: Add num_raters column.
            if (gml.@urat.length() != 0) {
               this.user_rating = int(gml.@urat);
            }
            this.rating_needed = Boolean(int(gml.@rating_needed));
            // FIXME: I [lb] think rating_needed is for Workhints and can be
            //        deleted
            m4_ASSERT(!this.rating_needed);
            // EXPLAIN: split_from_stack_id only used when diffing?
            // And when client saves split-intos... but that's set
            // by Byway_Split....
            if ((rev is utils.rev_spec.Diff)
                && (gml.@splt.length() != 0)) {
               // EXPLAIN: Why does Diff send this? It doesn't seem to be used
               //          any where in the client, except when committing....
               this.split_from_stack_id = int(gml.@splt);
            }
         }
         else {
            this.one_way = 0; // EXPLAIN: Magic number
            // MAGIC NUMBER: Search: Z_USER_OFFSET.
            this.z_level = 134; // EXPLAIN: Magic number
            if (G.item_mgr !== null) {
               this.beg_node_id = G.item_mgr.assign_id_new();
               this.fin_node_id = G.item_mgr.assign_id_new();
               m4_TALKY2('b/gml_consume: beg_node_id / fin_node_id:',
                         this.beg_node_id, '/', this.fin_node_id);
            }
            else if (this.stack_id != 0) {
               m4_WARNING2('Byway: Item Manager not loaded? Is this a branch?',
                           gml);
            }
            // else, the app is starting up (see init_GetDefinitionByName()).
            this.geofeature_layer_id = Geofeature_Layer.BYWAY_LOCAL_ROAD;
            // Set the generic rating to 2, meaning 'Good'.
            // FIXME: Make a Rating_Lookup class
            this.generic_rating = 2;
            this.rating_needed = false;
            this.split_from_stack_id = 0;
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         var ids:String = '';
         var o:Object;

         gml.setName(Byway.class_item_type); // 'byway'
         gml.@onew = this.one_way;
         // 2012.08.13: Nowadays, pyserver calculates the node ID, so that we
         // don't end up with either multiple node IDs with the same (x,y), or
         // multiple (x,y)s with the same node ID.
         // NO: gml.@nid1 = this.beg_node_id;
         // NO: gml.@nid2 = this.fin_node_id;
         // Skipping: gml.@urat (user_rating; saved elsewhere)
         if (this.split_from_stack_id != 0) {
            gml.@splt = this.split_from_stack_id;
         }

         return gml;
      }

      //
      public function gml_get_item_rating() :XML
      {
         // MAYBE: Make ratings generic and apply to any item type?
         // MAYBE: Turn rating into private attribute link_value,
         //        like item_watching (/item/alert_email)?
         var rating_doc:XML =
            <rating
               stack_id={this.stack_id}
               value={this.user_rating}/>;
         return rating_doc;
      }

      // ***

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Byway.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Byway.all;
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         if (d) {
            m4_DEBUG('deleted: node_mgmt: node_cleanup: beg+fin:', this);
            G.map.node_cleanup(this.beg_node_id, this);
            G.map.node_cleanup(this.fin_node_id, this);
         }
         else {
            m4_DEBUG('deleted: node_mgmt: node_init: beg+fin:', this);
            G.map.node_init(this.beg_node_id,
                            this.x_start,
                            this.y_start,
                            this,
                            /*no_snap=*/false);
            G.map.node_init(this.fin_node_id,
                            this.x_end,
                            this.y_end,
                            this,
                            /*no_snap=*/false);
         }
         /*
         if (d) {
            if ((this.arrows !== null)
                && (G.map.direction_arrows.contains(this.arrows))) {
               G.map.direction_arrows.removeChild(this.arrows);
            }
            delete Byway.all[this.stack_id];
         }
         else {
            if (this !== Byway.all[this.stack_id]) {
               if (this.stack_id in Byway.all) {
                  m4_WARNING2('set deleted: overwrite:',
                              Byway.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Byway.all[this.stack_id] = this;
            }
         }
         */
      }

      //
      // Inits. the byway, including adding to the global byway adjacency map.
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         //m4_VERBOSE('init_add:', this);
         // Call the parent
         super.init_add(item_agg, soft_add);
         // Add to our own lookup
         if (!soft_add) {
            if (this !== Byway.all[this.stack_id]) {
               if (this.stack_id in Byway.all) {
                  m4_WARNING2('init_add: overwrite:',
                              Byway.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Byway.all[this.stack_id] = this;
            }
         }
         // Add our arrows to the map
         G.map.direction_arrows.addChild(this.arrows);
         // Init the endnodes

// FIXME_2013_06_11: [lb] changed no_snap to false. Is that wrong/bad?
// EXPLAIN: Why the no-snap???????????????????????????????????
// this is causing snapping not to work...
//         var no_snap:Boolean = true;

         m4_DEBUG('init_add: node_mgmt: node_init: beg+fin:', this);
         G.map.node_init(this.beg_node_id, this.x_start, this.y_start,
                         this, /*no_snap=*/false);
         G.map.node_init(this.fin_node_id, this.x_end, this.y_end,
                         this, /*no_snap=*/false);
         // Add mouse listeners
         //this.sprite.addEventListener(
         //   MouseEvent.MOUSE_OVER, this.on_mouse_over, false, 0, true);
         //this.sprite.addEventListener(
         //   MouseEvent.MOUSE_OUT, this.on_mouse_out, false, 0, true);
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_VERBOSE('init_update: updating:', this.toString());
         m4_ASSERT_SOFT((this.stack_id in Byway.all) || (this.deleted));
         // Fetch the byway from our lookup
         var bway:Byway = Byway.all[this.stack_id];
         if (bway !== null) {
            //m4_ASSERT_SOFT((existing === null) || (existing === bway));
            m4_ASSERT_SOFT(existing === null);
            // clone will call clone_update and not clone_once because of bway.
            // And since Byway does not define a clone_update fcn., this
            // doesn't overwrite any Byway variables, like beg_node_id, etc.
            this.clone_item(bway);
            // Usually init_update means the user logged in and we're keeping
            // hold of dirty, edited items. So there are fews things from the
            // server we really want.
            // Skipping: G.map.node_init?
            // Skipping: G.map.direction_arrows.addChild(this.arrows);
            if ((bway !== null) && (bway.user_rating_update)) {
               // update the old byway's rating
               // This happens after discarding the map but remembering dirty
               // items; we request the dirty items from the server 
               m4_ASSERT(G.user.logged_in && bway.dirty);
               bway.user_rating = this.user_rating;
               bway.user_rating_update = false;
               bway.draw();
            }
         }
         else {
            if (!this.deleted) {
               m4_WARNING('init_update: no such byway?:', this);
               m4_ASSERT_SOFT(false);
            }
         }
         return bway;
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         return (super.is_item_loaded(item_agg)
                 || (this.stack_id in Byway.all));
      }

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         m4_DEBUG('update_item_committed');
         GWIS_Commit.dump_climap(commit_info);
         if (this.dirty_get(Dirty_Reason.item_rating)) {
            this.dirty_set(Dirty_Reason.item_rating, false);
         }
         // Update Byway.all.
         this.update_item_all_lookup(Byway, commit_info);
         // Update the node IDs.
         if (commit_info !== null) {
            m4_ASSURT(commit_info.beg_nid > 0);
            m4_ASSURT(commit_info.fin_nid > 0);
            G.map.node_cleanup(this.beg_node_id, this);
            G.map.node_cleanup(this.fin_node_id, this);
            this.beg_node_id = commit_info.beg_nid;
            this.fin_node_id = commit_info.fin_nid;
            m4_TALKY2('update_item_committed: beg_node_id / fin_node_id:',
                      this.beg_node_id, '/', this.fin_node_id);
            G.map.node_init(this.beg_node_id, this.x_start, this.y_start,
                            this, /*no_snap=*/false);
            G.map.node_init(this.fin_node_id, this.x_end, this.y_end,
                            this, /*no_snap=*/false);
         }
         //
         super.update_item_committed(commit_info);
      }

      // *** Developer methods

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' / bnod: ' + this.beg_node_id
                 + ' / fnod: ' + this.fin_node_id
                 );
      }

      // *** Getters and setters

      //
      public function get connectivity_displayed() :Boolean
      {
         return Byway.connected_byway === this;
      }

      //
      public function set connectivity_displayed(value:Boolean) :void
      {
         if (value) {
            Byway.connectivity_add(this);
         }
         else if (this.connectivity_displayed) {
            // If already false, do nothing
            Byway.connectivity_remove();
         }
      }

      //
      public function get counterpart() :Byway {
         return (this.counterpart_untyped as Byway);
      }

      //
      override public function get counterpart_gf() :Geofeature {
         return this.counterpart;
      }

      //
      public function get direction_arrow_color() :int
      {
         // If byway is too light, draw the arrow dark
         if (this.rating >= 2) {
            return Conf.byway_arrow_color_light;
         }
         else {
            return Conf.byway_arrow_color_dark;
         }
      }

      //
      override public function get draw_color() :int
      {
         var draw_color:int;
         if (G.map.rmode == Conf.map_mode_historic) {
            //m4_DEBUG('draw_color: map_mode_historic');
            m4_ASSERT(this.rev_is_diffing);
            draw_color = super.draw_color;
         }
         else if (G.map.rmode == Conf.map_mode_feedback) {
            //m4_DEBUG('draw_color: map_mode_feedback');
            draw_color = super.draw_color;
         }
         else if (G.tabs.settings.shade_roads_by_rating) {
            //m4_DEBUG('draw_color: shade_roads_by_rating');
            draw_color = Conf.rating_colors_generic[
                           int(Math.round(this.rating))];
         }
         else {
            //m4_DEBUG('draw_color: geofeature layer pen');
            draw_color = Conf.tile_skin.feat_pens
                           [String(this.geofeature_layer_id)]
                           ['pen_color'];
         }
         return draw_color;
      }

      //
      override public function get drawable_at_zoom_level() :Boolean
      {
         return G.map.zoom_is_vector();
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         return G.map.zoom_is_vector();
      }

      //
      override public function get friendly_name() :String
      {
         // FIXME: Put on the Wiki on in Bugs:
         // Usability testing in late May of 2011 suggests that (1) users do
         // not find the number of selected items meaningful, and in fact some
         // find it confusing; and (2) users also reacted differently to the
         // term 'block': one GIS professional thought it meant 'census block',
         // and another person, a planner, thought it meant a city block. In
         // either cases, the user thought a block was some sort of rectangular
         // region and not a linear segment, as intended. Best not to confuse;
         // I know users will adapt to whatever word we choose, but let's use a
         // term that doesn't intersect with the current vernacular.
         // return 'Block';
         return 'Road';
      }

      //
      public function get generic_rating_str() :String
      {
         return Bikeability_Rating.rating_number_to_words(this.generic_rating);
      }

      //
      public function get length() :Number
      {
         this.map_length_update();
         return this.map_length;
      }

      //
      public function get length_cv() :Number
      {
         var cv:Number = 0;
         var i:int;
         for (i = 0; i < this.xs.length - 1; i++) {
            cv += G.distance_cv(this.xs[i], this.ys[i],
                                this.xs[i+1], this.ys[i+1]);
         }
         return cv;
      }

      //
      public function get mobr() :Rectangle
      {
         var xmin:int;
         var ymin:int;
         var xmax:int;
         var ymax:int;

         var i:int;

         xmin = this.xs[0];
         xmax = this.xs[0];
         for (i = 1; i < this.xs.length; i++) {
            if (this.xs[i] < xmin) {
               xmin = this.xs[i];
            }
            if (this.xs[i] > xmax) {
               xmax = this.xs[i];
            }
         }

         ymin = this.ys[0];
         ymax = this.ys[0];
         for (i = 1; i < this.ys.length; i++) {
            if (this.ys[i] < ymin) {
               ymin = this.ys[i];
            }
            if (this.ys[i] > ymax) {
               ymax = this.ys[i];
            }
         }

         return new Rectangle(xmin - 10,
                              ymin - 10,
                              xmax - xmin + 20,
                              ymax - ymin + 20);
      }

      //
      public function get node_lhs_elevation_m_str() :String
      {
         var elev_str:String;
         var fractionDigits:uint = 2;
         elev_str = this.node_lhs_elevation_m.toFixed(fractionDigits/*=2*/);
         m4_DEBUG('get node_lhs_elevation_m_str:', elev_str);
         return elev_str;
      }

      //
      public function set node_lhs_elevation_m_str(elev_str:String) :void
      {
         this.node_lhs_elevation_m = new Number(elev_str);
         m4_DEBUG('set node_lhs_elevation_m_str:', this.node_lhs_elevation_m);
      }

      //
      public function get node_rhs_elevation_m_str() :String
      {
         var elev_str:String;
         var fractionDigits:uint = 2;
         elev_str = this.node_rhs_elevation_m.toFixed(fractionDigits/*=2*/);
         m4_DEBUG('get node_rhs_elevation_m_str:', elev_str);
         return elev_str;
      }

      //
      public function set node_rhs_elevation_m_str(elev_str:String) :void
      {
         this.node_rhs_elevation_m = new Number(elev_str);
         m4_DEBUG('set node_rhs_elevation_m_str:', this.node_rhs_elevation_m);
      }

      //
      public function get one_way_str() :String
      {
         var direction:String = null;
         switch (this.one_way) {
            case 0:
               // Two-way
               return 'Two-way';
               break;
            case 1:
               //return ('One-way '
               //        + G.angle_class_cabbrev(this.x_end - this.x_start,
               //                                this.y_end - this.y_start)
               //        + '-bound');
               direction = G.angle_class_cabbrev(this.x_end - this.x_start,
                                                 this.y_end - this.y_start)
                           + ' One-way';
               break;
            case -1:
               //return ('One-way '
               //        + G.angle_class_cabbrev(this.x_start - this.x_end,
               //                                this.y_start - this.y_end)
               //        + '-bound');
               direction = G.angle_class_cabbrev(this.x_start - this.x_end,
                                                 this.y_start - this.y_end)
                           + ' One-way';
               break;
            default:
               m4_ASSERT(false);
               break;
         }
         return direction;
      }

      //
      public function get rating() :Number
      {
         if (this.user_rating >= 0) {
            return this.user_rating;
         }
         else {
            return this.generic_rating;
         }
      }

      // If true, vertices can be selected long-term; otherwise, they are
      // selected only between mouse-down and mouse-up. Again, should really
      // be a const.
      override public function get persistent_vertex_selecting() :Boolean
      {
         return true;
      }

      //
      public function get shadow_color() :int
      {
         if (this.user_rating < 0 || this.rev_is_diffing) {
            return Conf.shadow_color;
         }
         else {
            return Conf.shadow_color_user_rated;
         }
      }

      //
      override public function get vertex_add_enabled() :Boolean
      {
         return true;
      }

      // Coordinates of the first point of the byway.
      public function get x_start() :Number
      {
         return this.xs[0];
      }

      //
      public function set x_start(x:Number) :void
      {
         this.xs[0] = x;
      }

      //
      public function get y_start() :Number
      {
         return this.ys[0];
      }

      //
      public function set y_start(y:Number) :void
      {
         this.ys[0] = y;
      }

      // Coordinates of the last point of the byway.
      public function get x_end() :Number
      {
         return this.xs[this.xs.length-1];
      }

      //
      public function set x_end(x:Number) :void
      {
         this.xs[this.xs.length-1] = x;
      }

      //
      public function get y_end() :Number
      {
         return this.ys[this.ys.length-1];
      }

      //
      public function set y_end(y:Number) :void
      {
         this.ys[this.ys.length-1] = y;
      }

      //
      override public function get vertex_editable() :Boolean
      {
         // 2013.05.07: Only show the thin blue line in view mode, and don't
         //             show geofeature vertices or allow them to be edited.
         //return true;
         return G.app.mode.is_allowed(App_Action.item_edit);
      }

      // *** Double click detector mouse handlers

      //
      override public function on_mouse_down(ev:MouseEvent) :void
      {
         this.tooltip_display(false);
         this.tooltip_timer.stop();
         super.on_mouse_down(ev);
      }

      // Skipping: on_mouse_up and on_mouse_doubleclick

      // *** Event listeners

      //
      override public function on_mouse_over(evt:MouseEvent) :void
      {
         super.on_mouse_over(evt);
         this.connectivity_displayed = true;
         // Begin the timer to show a tooltip at the location of evt
         if (G.tabs.settings.byway_tooltips) {
            this.last_mouse_over = evt;
            this.tooltip_timer.reset();
            this.tooltip_timer.start();
         }
      }

      //
      override public function on_mouse_out(evt:MouseEvent) :void
      {
         super.on_mouse_out(evt);
         if (this.connectivity_displayed) {
            this.connectivity_displayed = false;
         }
         this.tooltip_display(false);
         this.tooltip_timer.stop();
      }

      //
      public function on_tooltip_timer(evt:TimerEvent) :void
      {
         this.tooltip_display(true);
      }

      // *** Draw-related instance methods

      // Draw a highlight on the current byway and (maybe) adjacent byways. gr
      // is the graphics object to draw on, depth is the number of recursions
      // done already, recurse being true means to recurse to the configured
      // limit, and visited is a set of already visited byways.
      protected function connectivity_draw(gr:Graphics,
                                           depth:int,
                                           visited:Set_UUID) :void
      {
         var beg_adj:Set_UUID;
         var fin_adj:Set_UUID;
         var neighbor:Byway;
         var x:Number;
         var y:Number;
         var i:int;
         var vs:int = Conf.byway_connectivity_vertex_size;

         m4_ASSERT(depth >= 0);
         m4_ASSERT(!(visited.is_member(this)));

         if (depth < Conf.byway_connectivity_depth) {
            // Recurse
            visited.add(this);
            beg_adj = G.map.nodes_adjacent[this.beg_node_id];
            fin_adj = G.map.nodes_adjacent[this.fin_node_id];
            if (beg_adj !== null) {
               for each (neighbor in beg_adj) {
                  if (!(visited.is_member(neighbor))) {
                     neighbor.connectivity_draw(gr, depth+1, visited);
                  }
               }
            }
            if (fin_adj !== null) {
               for each (neighbor in fin_adj) {
                  if (!(visited.is_member(neighbor))) {
                     neighbor.connectivity_draw(gr, depth+1, visited);
                  }
               }
            }
         }

         // line down the center
         gr.lineStyle((Conf.byway_connectivity_width_start
                       - depth * Conf.byway_connectivity_width_decrement),
                      Conf.byway_connectivity_color);
         x = G.map.xform_x_map2cv(this.x_start);
         y = G.map.xform_y_map2cv(this.y_start);

         if (G.app.mode.is_allowed(App_Action.item_edit)) {

            //m4_DEBUG('connectivity_draw: App_Action.item_edit');

            gr.moveTo(x, y);
            for (i = 1; i < this.xs.length; i++) {
               x = G.map.xform_x_map2cv(this.xs[i]);
               y = G.map.xform_y_map2cv(this.ys[i]);
               gr.lineTo(x, y);
            }

            // square at start/end vertices
            x = G.map.xform_x_map2cv(this.x_start);
            y = G.map.xform_y_map2cv(this.y_start);
            gr.drawRect(x - vs/2, y - vs/2, vs, vs);
            x = G.map.xform_x_map2cv(this.x_end);
            y = G.map.xform_y_map2cv(this.y_end);
            gr.drawRect(x - vs/2, y - vs/2, vs, vs);
         }

      }

      //
      override public function draw(is_drawable:Object=null) :void
      {
         var grs:Graphics = this.shadow.graphics;
         var x:Number;
         var y:Number;
         var i:int;
         var non_geo:Boolean = false;
         var o:Object;
         var lv:Link_Value;
         var an:Annotation;
         var alpha:Number = 1;
         var width_adjustment:Number = 0;
         var shadow_adjustment:Number = 0;

         super.draw();

         // 2013.05.23: Don't draw the endcaps: When a byway has a higher
         // bridge level, it's shadow's endcap looks funny on top of the
         // road below. Note that this is a regression since CcpV1.
         //
         // MAYBE: Draw some highlights for all z-levels before drawing the
         //        top-most line for each z-level. But disabling caps seems
         //        to do a pretty decent job (not perfect, but pertty good).
         //
         var caps:Boolean = false;

         var settings_panel:Panel_Settings = G.tabs.settings.settings_panel;
         if (settings_panel.settings_options.aerial_cbox.selected) {
            alpha = settings_panel.settings_options.alpha_slider.value;
            // MAGIC NUMBERS
            // EXPLAIN: If aerial enabled, make widths less wide...
            if (G.map.zoom_level > 15) {
               width_adjustment = -5;
            }
            else if (G.map.zoom_level == 15) {
               width_adjustment = -3;
            }
            else if (G.map.zoom_level < 15) {
               width_adjustment = -1;
            }
            shadow_adjustment = 0;
         }

         this.shadow.graphics.clear();

         // ***

         // This shadow indicates the presence of nongeometric changes.
         if (this.has_non_geo_changes()) {
            // EXPLAIN: Is this for diffing? Maybe do if-diffing so
            // we don't show attcs-exist highlight in diff mode.
            Paint.line_draw(this.shadow.graphics, this.xs, this.ys,
                            (this.draw_width
                             + 2 * this.shadow_width
                             + 2 * this.comment_width
                             + width_adjustment
                             + shadow_adjustment),
                            Conf.change_color, alpha, caps);
         }
         // MAYBE: COUPLING: Statewide UI: This is coupled.
         //                  The item classes should not know about the view.
         else if ((G.tabs.settings.links_visible)
                  && (this.annotation_cnt || this.discussion_cnt)
                  && (!this.rev_is_diffing)) {
            // Shadow to highlight presence of annotations and/or posts
            // FIXME: Make control panel option.
            //        Make fetch quicker for attachments-exist.

            Paint.line_draw(this.shadow.graphics,
                            this.xs, this.ys,
                            (this.draw_width
                             + 2 * this.shadow_width
                             + 2 * this.comment_width
                             + width_adjustment
                             + shadow_adjustment),
                            this.comment_color,
                            alpha, caps, 0, 0);
         }

         // *** The shadow knows.

         Paint.line_draw(this.shadow.graphics,
                         this.xs, this.ys,
                         this.draw_width
                          + this.shadow_width * 2
                          + width_adjustment,
                         this.shadow_color,
                         alpha, caps);

         this.sprite.graphics.clear();

         // *** Bicycle Facility

   // BUG nnnn: Draw a directional hill ornament (an arrow indicating the
   //           direction of uphill).
   // BUG nnnn: The route finder should determine uphill and downhill
   //           and not just simply avoid byways tagged "hill". I.e.,
   //           biking downhill is awesome!
   //           For each byway, assign a hill-gradient value, i.e.,
   //           0 is flat, +1 is 10 degrees uphill from beg node ID
   //           to fin node ID, and -1 is 10 degrees downhill from
   //           beg node ID to fin node ID. Then, we could penalize
   //           or reward byways according to their grade.

         var pen_group:String;
         var attr_pen_name:String;
         // A caution trumps the true facility.
         attr_pen_name = this.byway_cautionary;
         if ((attr_pen_name != '')
             && (attr_pen_name != Facility_Icon_Base.key_no_cautys)) {
            pen_group = 'cautionary';
         }
         else {
            attr_pen_name = this.bicycle_facility;
            if ((attr_pen_name != '')
                && (attr_pen_name != Facility_Icon_Base.key_no_facils)) {
               pen_group = 'bike_facil';
            }
            else {
               attr_pen_name = '';
            }
         }
         if ((attr_pen_name != '')
             && (G.tabs.settings.facils_visible)) {
            Byway.draw_bike_facil(
               this.sprite.graphics,
               xs,
               ys,
               pen_group,
               attr_pen_name,
               this.geofeature_layer_id,
               G.map.zoom_level,
               /*force_caps=*/null,
               /*skip_transform=*/false,
               alpha);
         }
         else {
            // Generally, shade_roads_by_rating is set, so this.draw_color
            // is a gradiant based on the line segment rating.
            caps = true;
            Paint.line_draw(this.sprite.graphics, this.xs, this.ys,
                            this.draw_width + width_adjustment,
                            this.draw_color, alpha, caps);
         }

         // *** "Restricted" Ornament

         // Draw an ornament, e.g., a single-pixel solid red line, indicating
         // if the street has any tag Cyclopath considers to mean the street is
         // not bikeable (e.g., illegal/impassable/unbikeable/closed/restricted
         //                     -access).
         if ((this.has_avoided_tag()) && (!this.rev_is_diffing)) {
            var line_width:Number = 1.0;
            caps = false;
            Paint.line_draw(this.sprite.graphics, this.xs, this.ys,
                            line_width, Conf.avoided_tag_color,
                            alpha, caps);
         }

         // *** Selected and/or Highlighted Ornaments

         if (this.selected) {
            this.orn_selection.draw();
         }
         if (this.highlighted) {
            G.map.highlight_manager.render_highlight(this);
         }

         // *** One-way arrow

         this.direction_arrow_placeanddraw(alpha);

         // *** Node endpoints (if editable, that is)

         if (G.app.mode.is_allowed(App_Action.item_edit)) {
            this.draw_node(this.beg_node_id);
            this.draw_node(this.fin_node_id);
         }
      }

      //
      public static function draw_bike_facil(
         gr:Graphics,
         xs:Array,
         ys:Array,
         pen_group:String,
         attr_key_name:String,
         geofeature_layer_id:int,
         zoom_level:int,
         force_caps:*=null,
         skip_transform:Boolean=false,
         alpha:Number=1.0) :void
      {
         var caps:Boolean;
         var dashed:Boolean;
         var dash_interval:int = 0;
         var elbow_size:Number = 0.0;
         var gut_on_color:int;
         var offset:Number = 0.0;

         //m4_DEBUG2('draw_bike_facil: pen_group:', pen_group,
         //          '/ attr_key_name:', attr_key_name);

         var feat_pen:Object = Conf.tile_skin.feat_pens
                                 [String(geofeature_layer_id)];
         var tile_pen:Object = feat_pen.tile_pens[String(zoom_level)];
         var bike_facil:Object = null;

         // Perhaps surprisingly, this fcn. is called via items_add, and the
         // bike_facil value might be strange, so check that it's not ood kind.

         if (!(attr_key_name in Conf.tile_skin.attr_pens[pen_group])) {
            m4_WARNING2('unknown attr_key_name:', attr_key_name,
                        '/ pen_group:', pen_group);
            // HACK!
            if (pen_group == 'bike_facil') {
               // E.g., 'no_facils'.
               attr_key_name = Facility_Icon_Base.key_no_facils;
            }
            else {
               m4_ASSERT(pen_group == 'cautionary');
               // E.g., 'no_cautys'.
               attr_key_name = Facility_Icon_Base.key_no_cautys;
            }
         }
         bike_facil = Conf.tile_skin.attr_pens[pen_group][attr_key_name];
         m4_ASSERT(bike_facil !== null);

         var pen_width:int = tile_pen['pen_width'];

         // SYNC_ME: gut_width reduction: mapserver/make_mapfile.py
         //                               flashclient/items/feats/Byway.as
         if (bike_facil['gut_width']) {

            // If there's a wide gutter make the pen_width a little narrower.
            if (bike_facil['gut_width'] > 3) {
               pen_width -= 4.0;
            }
            else if (bike_facil['gut_width'] > 1) {
               //pen_width -= bike_facil['gut_width'];
               pen_width -= 2.0;
            }

            if (bike_facil['gut_on_color'] !== null) {
               gut_on_color = bike_facil['gut_on_color'];
            }
            else {
               m4_ASSERT(bike_facil['dashon_color'] !== null);
               gut_on_color = bike_facil['dashon_color'];
            }
            //caps = (bike_facil['gut_on_interval'] == 0);
            if (force_caps !== null) {
               caps = force_caps;
            }
            else {
               caps = (bike_facil['gut_on_interval'] == 0);
            }

            // MAGIC_NUMBERS: There are two bumpers on either side of two
            //                one-pixel gutters.
            var one_pixel_gutter:Number = 2.0;
            var gutt_width:Number = Number(pen_width)
                                    + (2.0 * Number(one_pixel_gutter));
            var rail_width:Number = gutt_width
                                    + (2.0 * Number(bike_facil['gut_width']));
            var full_width:Number = rail_width
                                    + (2.0 * Number(one_pixel_gutter));

            /*
            m4_DEBUG('draw_bike_facil: line_draw/2&3');
            m4_DEBUG('draw_bike_facil: gr:', gr);
            m4_DEBUG('draw_bike_facil: alpha:', alpha);
            m4_DEBUG('draw_bike_facil: caps:', caps);
            m4_DEBUG('draw_bike_facil: elbow_size:', elbow_size);
            m4_DEBUG('draw_bike_facil: offsetshed :', offset );
            m4_DEBUG('draw_bike_facil: dashed :', dashed );
            m4_DEBUG('draw_bike_facil: gut_width:', bike_facil['gut_width']);
            m4_DEBUG('draw_bike_facil: pen_width:', tile_pen['pen_width']);
            m4_DEBUG('draw_bike_facil: full_width :', full_width );
            m4_DEBUG('draw_bike_facil: xs:', xs);
            m4_DEBUG('draw_bike_facil: ys:', ys);
            m4_DEBUG('draw_bike_facil: offset:', offset);
            m4_DEBUG('draw_bike_facil: gut_on_color:', gut_on_color);
            m4_DEBUG('draw_bike_facil: no_gut_color:', bike_facil['no_gut_color']);
            m4_DEBUG('draw_bike_facil: gut_on_interval:', bike_facil['gut_on_interval']);
            m4_DEBUG('draw_bike_facil: no_gut_interval:', bike_facil['no_gut_interval']);
            m4_DEBUG('draw_bike_facil: interval_square:', bike_facil['interval_square']);
            */

            // Paint the full background line first.
            caps = false;
            dashed = false;
            Paint.line_draw(gr, xs, ys,
                            full_width,
                            //Conf.tile_skin.attr_pens['draw_class']
                            //        ['background']['dashon_color'],
                            //0xff0000,
                            0xffffff,
                            alpha, caps, elbow_size, offset,
                            dashed,
                            '', // bike_facil['no_gut_color'],
                            0, // bike_facil['gut_on_interval'],
                            0, // bike_facil['no_gut_interval'],
                            false, // bike_facil['interval_square'],
                            skip_transform);

            // Paint the rails on top of the background.
            dashed = (bike_facil['gut_on_interval'] > 0);
            Paint.line_draw(gr, xs, ys,
                            rail_width,
                            gut_on_color,
                            alpha, caps, elbow_size, offset,
                            dashed,
                            bike_facil['no_gut_color'],
                            bike_facil['gut_on_interval'],
                            bike_facil['no_gut_interval'],
                            false, // bike_facil['interval_square'],
                            skip_transform);

            // Paint the gutter splitter next.
            dashed = false;
            // MAYBE: At least with offset, we can leave the one pixel gutter
            //        splitter transparent. But the offset doesn't work well,
            //        so we paint opaque lines.
            //        For now, our gutter splitter is white... or what the
            //        background is?

            // MAYBE: Should this layer be the rating gradient??
            //        Maybe if it's enabled from settings?

            Paint.line_draw(gr, xs, ys,
                            gutt_width,
                            //Conf.tile_skin.attr_pens['draw_class']
                            //        ['background']['dashon_color'],
                            0xffffff,
                            alpha, caps, elbow_size, offset,
                            dashed,
                            '', // bike_facil['no_gut_color'],
                            0, // bike_facil['gut_on_interval'],
                            0, // bike_facil['no_gut_interval'],
                            false, // bike_facil['interval_square'],
                            skip_transform);
         }

         if (bike_facil['dashon_color'] !== null) {

            if (force_caps !== null) {
               caps = force_caps;
            }
            else {
               caps = (bike_facil['dashon_interval'] == 0);
            }
            dashed = (bike_facil['dashon_interval'] > 0);

            /*
            m4_DEBUG('draw_bike_facil: line_draw/1');
            m4_DEBUG('draw_bike_facil: gr:', gr);
            m4_DEBUG('draw_bike_facil: caps:', caps);
            m4_DEBUG('draw_bike_facil: dashed :', dashed );
            m4_DEBUG('draw_bike_facil: pen_width:', pen_width);
            m4_DEBUG('draw_bike_facil: xs:', xs);
            m4_DEBUG('draw_bike_facil: ys:', ys);
            m4_DEBUG('draw_bike_facil: dashon_color:', bike_facil['dashon_color']);
            m4_DEBUG('draw_bike_facil: nodash_color:', bike_facil['nodash_color']);
            m4_DEBUG('draw_bike_facil: dashon_interval:', bike_facil['dashon_interval']);
            m4_DEBUG('draw_bike_facil: nodash_interval:', bike_facil['nodash_interval']);
            m4_DEBUG('draw_bike_facil: interval_square:', bike_facil['interval_square']);
            */

            Paint.line_draw(gr, xs, ys,
                            pen_width, // Use same width as non-bf.
                            bike_facil['dashon_color'],
                            alpha, caps, elbow_size, offset,
                            dashed,
                            bike_facil['nodash_color'],
                            bike_facil['dashon_interval'],
                            bike_facil['nodash_interval'],
                            bike_facil['interval_square'],
                            skip_transform);
         }

         // MAYBE: Fixing and using offset is better than painting
         //        progressively thinner lines on top of one another
         //        because you can preserve transparency.
         var not_deprecated:Boolean = false;
         if (not_deprecated) {
            if (bike_facil['gut_width']) {
               gut_on_color = bike_facil['gut_on_color'];
               if (!gut_on_color) {
                  gut_on_color = bike_facil['dashon_color'];
               }
               caps = (bike_facil['gut_on_interval'] == 0);
               //offset = (bike_facil['gut_width'] / 2.0) + 2.5;
               //offset = (bike_facil['gut_width'] / 2.0) + 3.75;
               offset = (pen_width / 2.0) + (bike_facil['gut_width'] * 2);
               dashed = (bike_facil['gut_on_interval'] > 0);

               /*
               m4_DEBUG('draw_bike_facil: line_draw/2&3');
               m4_DEBUG('draw_bike_facil: gr:', gr);
               m4_DEBUG('draw_bike_facil: caps:', caps);
               m4_DEBUG('draw_bike_facil: dashed :', dashed );
               m4_DEBUG('draw_bike_facil: gut_width:', bike_facil['gut_width']);
               m4_DEBUG('draw_bike_facil: xs:', xs);
               m4_DEBUG('draw_bike_facil: ys:', ys);
               m4_DEBUG('draw_bike_facil: offset:', offset);
               m4_DEBUG('draw_bike_facil: dashed:', dashed);
               m4_DEBUG('draw_bike_facil: gut_on_color:', gut_on_color);
               m4_DEBUG('draw_bike_facil: no_gut_color:', bike_facil['no_gut_color']);
               m4_DEBUG('draw_bike_facil: gut_on_interval:', bike_facil['gut_on_interval']);
               m4_DEBUG('draw_bike_facil: no_gut_interval:', bike_facil['no_gut_interval']);
               */

               // Draw a border on one side...
               Paint.line_draw(gr, xs, ys,
                               bike_facil['gut_width'],
                               gut_on_color,
                               alpha, caps, elbow_size, offset,
                               dashed,
                               bike_facil['no_gut_color'],
                               bike_facil['gut_on_interval'],
                               bike_facil['no_gut_interval'],
                               false, // bike_facil['interval_square'],
                               skip_transform);
               // ... and a border on the other.
               offset = 0 - offset;
               Paint.line_draw(gr, xs, ys,
                               bike_facil['gut_width'],
                               gut_on_color,
                               alpha, caps, elbow_size, offset,
                               dashed,
                               bike_facil['no_gut_color'],
                               bike_facil['gut_on_interval'],
                               bike_facil['no_gut_interval'],
                               false, // bike_facil['interval_square'],
                               skip_transform);
            }
         }
      }

      //
      protected function draw_node(nid:int) :void
      {
         var z_max:int = int.MIN_VALUE;
         var z_min:int = int.MAX_VALUE;
         var z_max_b:Byway;
         var b:Byway;

         for each (b in G.map.nodes_adjacent[nid]) {
            if (b.z_level > z_max) {
               z_max = b.z_level;
               z_max_b = b;
            }
            if (b.z_level < z_min) {
               z_min = b.z_level;
            }
         }

         for each (b in G.map.nodes_adjacent[nid]) {
            if (b.z_level == z_max) {
               b.draw_node_widgets(nid);
            }
         }
      }

      //
      protected function draw_node_widgets(nid:int) :void
      {
         // 2013.08.20: Adding check on this.selected, since we don't draw
         // vertices except for selected items, and this fcn. is called on
         // deselect.
         if (this.selected) {
            if (this.is_drawable) {
               this.draw_node_widgets_(nid);
            }
            // else... EXPLAIN: Why is the byway (and why are the vertices)
            //                  not drawable?
         }
         else {
            // Well, we can at least cleanup our sprites.
            if (this.node_widget_start !== null) {
               this.node_widget_start.graphics.clear();
               this.sprite.removeChild(this.node_widget_start);
               this.node_widget_start = null;
            }
            if (this.node_widget_end !== null) {
               this.node_widget_end.graphics.clear();
               this.sprite.removeChild(this.node_widget_end);
               this.node_widget_end = null;
            }
         }
      }

      //
      protected function draw_node_widgets_(nid:int) :void
      {
         var b:Byway;
         var xys:Array;
         var len:Number;
         var gr_nw:Graphics = null;

         // Choose the Graphics object for the node widget
         if (nid == this.beg_node_id) {
            if (this.node_widget_start === null) {
               this.node_widget_start = new Sprite();
               this.sprite.addChild(this.node_widget_start);
            }
            gr_nw = this.node_widget_start.graphics;
         }
         else if (nid == this.fin_node_id) {
            if (this.node_widget_end === null) {
               this.node_widget_end = new Sprite();
               this.sprite.addChild(this.node_widget_end);
            }
            gr_nw = this.node_widget_end.graphics;
         }
         else {
            // 2013.05.30... This is new. [lb] draggin vertices around.
            m4_ERROR2('draw_node_widgets: nid?:', nid,
                      '/ this:', this.toString());
         }
         if (gr_nw !== null) {
            gr_nw.clear();
            // If no adjacent blocks, don't draw anything. Otherwise, do.
            if (G.map.nodes_adjacent[nid].length > 1) {
               // For each adjacent block, draw the appropriate stuff.
               for each (b in G.map.nodes_adjacent[nid]) {
                  xys = b.exit_vector(nid);
                  if (xys !== null) {
                     // different Z cleanup
                     // EXPLAIN: What does this draw?
                     if ((b.z_level != this.z_level)
                         && (b.is_drawable)) {
                        len = G.map.xform_scalar_cv2map(
                           (this.draw_width / 2) + this.shadow_width + 1);
                        xys = Geometry.vector_normalized(xys, len);
                        Paint.line_draw(this.shadow.graphics, xys[0], xys[1],
                                        b.draw_width, b.draw_color, 1, false);
                     }
                     // Show the intersection indicator when zoomed in enough.
                     if (G.map.zoom_level >= Conf.node_widget_zoom) {
                        len = G.map.xform_scalar_cv2map(b.draw_width * 1.5);
                        xys = Geometry.vector_normalized(xys, len);
                        Paint.line_draw(gr_nw, xys[0], xys[1], 1,
                                        Conf.node_widget_color, 1, false);
                     }
                  }
                  else {
                     // 2014.09.15: This fired after [lb] disconnected a byway
                     // from the network, dragged its endpoints across two 
                     // byways and to the middle of two other byways, and then
                     // made four new intersections and saved.
                     // Called via:
                     //   Commit_Changes_Dialog::on_okay ->
                     //    items_save_send ->
                     //     map_selection_clear ->
                     //      set_selected ->
                     //       set_selected_ensure_removed ->
                     //        set_selected_ensure_finalize ->
                     //         Byway.draw->draw_node->draw_node_widgets->here
                     // Also called via:
                     //   link_values_lazy_load_okay ->
                     //    ... Node_Endpoint_Build/byway_split ->
                     //     ... item_discard...
                     // Also called via:
                     //   link_values_lazy_load_okay ->
                     //    ... Node_Endpoint_Build/byway_split ->
                     //     ... vertex_insert_at...
                     // Before this fires, b.exit_vector(nid) indicates, e.g.,:
                     //   exit_vector: node id not beg or fin: -3 / this:
                     //      "5th Ave NE" [items.feats::Byway:1038830.1 ...
                     //      / bnod: 1293805 / fnod: 1287271
                     //   exit_vector: node id not beg or fin: -3 / this:
                     //      "University Ave NE" [items.feats::Byway:-7.0 ...
                     //      / bnod: 1306545 / fnod: -21
                     // So G.map.nodes_adjacent is not being updated...
                     // Ignoring for now:
                     //   m4_ASSERT_SOFT(!b.selected);
                  }
               }
            } // else, (G.map.nodes_adjacent[nid].length == 1)
         }
      }

      // Return an array [[x1, x2], [y1, y2]] where (x1,y1) is the map
      // coordinates of node nid, and (x2,y2) are the coordinates of the
      // penultimate vertex on that end of the byways. ([lb] translates:
      // penultimate means "last but one", or second-to-last. I always
      // confuse that with antepenultimate, or third last.)
      protected function exit_vector(nid:int) :Array
      {
         var arr:Array = null;
         if (nid == this.beg_node_id) {
            arr = [[this.x_start, this.xs[1],],
                   [this.y_start, this.ys[1],],];
         }
         else if (nid == this.fin_node_id) {
            arr = [[this.x_end, this.xs[this.xs.length - 2],],
                   [this.y_end, this.ys[this.xs.length - 2],],];
         }
         else {
            m4_DEBUG2('exit_vector: node id not beg or fin:', nid,
                      '/ this:', this);
         }
         return arr;
      }

      //
      public function highlight_draw() :void
      {
         var vs:int = Conf.byway_connectivity_vertex_size;
         var x:Number;
         var y:Number;
         var i: Number;

         if ((this.highlight === null)
             && (G.app.mode.is_allowed(App_Action.item_edit))) {

            //m4_DEBUG('highlight_draw: App_Action.item_edit');

            this.highlight = new Sprite();

            G.map.highlights.addChild(this.highlight);

            // Line down the center
            Paint.line_draw(this.highlight.graphics, this.xs, this.ys,
                            Conf.byway_connectivity_width_start,
                            Conf.node_endpoint_builder_color);

            // Square at start and end vertices
            x = G.map.xform_x_map2cv(this.x_start);
            y = G.map.xform_y_map2cv(this.y_start);
            this.highlight.graphics.drawRect(x - vs/2, y - vs/2, vs, vs);
            x = G.map.xform_x_map2cv(this.x_end);
            y = G.map.xform_y_map2cv(this.y_end);
            this.highlight.graphics.drawRect(x - vs/2, y - vs/2, vs, vs);
         }
      }

      //
      public function highlight_remove() :void
      {
         if (this.highlight !== null) {
            G.map.highlights.removeChild(this.highlight);
            this.highlight = null;
         }
      }

      // *** Draw methods for arrows

      // Length of the line segment from start to start+1 with in the geometry
      // array, in canvas coordinates.
      protected function cv_line_length(start:int) :Number
      {
         return G.distance_cv(this.xs[start], this.ys[start],
                              this.xs[start + 1], this.ys[start + 1]);
      }

      // Change in x in canvas coords from start to start+1.
      protected function cv_vec_x(start:int) :Number
      {
         return G.map.xform_x_map2cv(this.xs[start + 1])
                - G.map.xform_x_map2cv(this.xs[start]);
      }

      // As above, but for y.
      protected function cv_vec_y(start:int) :Number
      {
         return G.map.xform_y_map2cv(this.ys[start + 1])
                - G.map.xform_y_map2cv(this.ys[start]);
      }

      // Place and draw my direction arrow.
      protected function direction_arrow_placeanddraw(alpha:Number) :void
      {
         var g:Graphics = this.arrows.graphics;
         var cv_cache:Number = this.length_cv; // Length on the canvas
         var num_arrows:int = 1;
         var arrows:Array; // array of arrays, [start len, end len]
         var p:Number; // center of arrow
         var i:int;
         var progress:Number; // progress along byway's length
         var line_length:Number; // length of a line
         var segment_start:int; // start index of segment

         // direction vector of current line segment
         var lx:Number;
         var ly:Number;
         // arrow tip location
         var sx:Number;
         var sy:Number;

         g.clear();
         this.arrow_tips.graphics.clear();

         // This is here because we should always clear the old graphics, but
         // we might not want to draw the new stuff.
         if (G.map.zoom_level < Conf.direction_arrow_zoom) {
            return;
         }
         if (this.one_way == 0) {
            return;
         }
         if (cv_cache < (2 * Conf.byway_arrow_length)) {
            // Byway is too small at this zoom level, ignore
            return;
         }

         // 20111010: Arrows are spaced 200 pixels apart.
         while ((cv_cache / num_arrows) > Conf.byway_arrow_separation) {
            num_arrows++;
         }

         if (num_arrows > 1) {
            num_arrows -= 1; // account for last ++ that broke the while loop
         }
         arrows = new Array(num_arrows);

         // assign regions to each arrow (bisect segments to place arrows)
         // FIXME: This doesn't take into consideration name labels: names get
         //        placed on top of one_way arrows because name labels are
         //        calculated on a collection of same-named byways, rather than
         //        individual byways like how arrows are placed.
         p = cv_cache / (2 * num_arrows); // halfway along separation
         for (i = 0; i < arrows.length; i++) {
            arrows[i] = [p - Conf.byway_arrow_length / 2,
                         p + Conf.byway_arrow_length / 2,];
            p += (cv_cache / num_arrows);
         }

         progress = 0;
         segment_start = 0;
         for (i = 0; i < arrows.length; i++) {
            // step along byway until arrow's start lies along a line segment
            line_length = this.cv_line_length(segment_start);
            while (progress + line_length < arrows[i][0]) {
               segment_start++;
               progress += line_length; // update progress along byway
               // update line length for next loop
               line_length = this.cv_line_length(segment_start);
            }

            lx = this.cv_vec_x(segment_start);
            ly = this.cv_vec_y(segment_start);
            // normalize vector
            lx /= line_length;
            ly /= line_length;

            sx = G.map.xform_x_map2cv(this.xs[segment_start])
                 + lx * (arrows[i][0] - progress);
            sy = G.map.xform_y_map2cv(this.ys[segment_start])
                 + ly * (arrows[i][0] - progress);

            if (this.one_way < 0) {
               // byway is going against indices, so arrow is put in front
               Paint.arrow_tip_draw(this.arrow_tips.graphics, sx, sy, -lx, -ly,
                                    Conf.byway_arrow_length / 3,
                                    Conf.byway_arrow_length / 3,
                                    this.direction_arrow_color, alpha);
            }

            g.lineStyle(2, this.direction_arrow_color, alpha);
            g.moveTo(sx, sy);
            // go around any curves and short line segments
            while (progress + line_length < arrows[i][1]) {
               g.lineTo(G.map.xform_x_map2cv(this.xs[segment_start + 1]),
                        G.map.xform_y_map2cv(this.ys[segment_start + 1]));

               segment_start++;
               progress += line_length;
               line_length = this.cv_line_length(segment_start);

               // also have to update the direction vector now
               if (arrows[i][1] - progress > 2) {
                  // Hack: don't change the direction if a very small bit
                  // of line is left.  It ends up twisting the arrow head oddly
                  lx = this.cv_vec_x(segment_start);
                  ly = this.cv_vec_y(segment_start);
                  // normalize vector
                  lx /= line_length;
                  ly /= line_length;
               }
            }

            sx = G.map.xform_x_map2cv(this.xs[segment_start])
                 + lx * (arrows[i][1] - progress);
            sy = G.map.xform_y_map2cv(this.ys[segment_start])
                 + ly * (arrows[i][1] - progress);

            // end the direction line
            g.lineTo(sx, sy);

            if (this.one_way > 0) {
               // bway is going with indices, so arrow is put at the end
               Paint.arrow_tip_draw(this.arrow_tips.graphics, sx, sy, lx, ly,
                                    Conf.byway_arrow_length / 3,
                                    Conf.byway_arrow_length / 3,
                                    this.direction_arrow_color, alpha);
            }
         }
      }

      // *** Other public instance methods

      //
      public function drag(xdelta:Number, ydelta:Number) :void
      {
         // Do nothing. This is a placeholder for dragging using the waypoint
         // create tool (which handles updating the position).
      }

      //
      protected function has_avoided_tag() :Boolean {
         var has_tag:Boolean = false;
         var tag:String;
         // NOTE: Using for and not for-each so we get keys, not values.
         for (tag in Tag.avoid_named) {
            if (this.tags.is_member(tag)) {
               has_tag = true;
               break;
            }
         }
         // 2013.05.23: We can't skip the heavyweight lookup unless we make
         // sure that we a new tag is created in the client, that this.tags
         // is updated. Currently, [lb] only knows that a heavyweight link
         // is created (but I could be wrong, I'm just being lazy and not
         // checking -- see if when making a new tag, this.tags is updated).
         // MAYBE: Don't both checking the heavyweight link_values if you
         //        know that this.tags is always == to what's in Link_Value's
         //        lookup.
         if (!has_tag) {
            var byway_set:Set_UUID = new Set_UUID(
               Link_Value.attachments_for_item(this, Tag));
            for (tag in Tag.avoid_named) {
               if (byway_set.is_member(Tag.all_named[tag])) {
                  has_tag = true;
                  break;
               }
            }
         }
         return has_tag;
      }

      //
      override public function is_dangle(vertex_idx:int) :Boolean
      {
         var is_dangle:Boolean = false;
         if (this.is_endpoint(vertex_idx)) {
            var nodes_adjacent:Set_UUID;
            // MAYBE: [lb] assumes that vertex_idx == 0 corresponds to the
            //             beg_node_id?
            if (vertex_idx == 0) {
               m4_TALKY('is_dangle: this.beg_node_id:', this.beg_node_id);
               nodes_adjacent = G.map.nodes_adjacent[this.beg_node_id];
            }
            else {
               m4_TALKY('is_dangle: this.fin_node_id:', this.fin_node_id);
               nodes_adjacent = G.map.nodes_adjacent[this.fin_node_id];
            }
            if (nodes_adjacent !== null) {
               if (nodes_adjacent.length == 1) {
                  is_dangle = true;
               }
               m4_TALKY2('is_dangle: is_dangle:', is_dangle,
                         '/ nds_adjacent.len:', nodes_adjacent.length);
            }
            else {
               // When you drag an endpoint around, Byway_Vertex_Move keeps a
               // client ID handy for situational dangling. So this case is
               // okay: e.g., if you drag a vertex from one intersection to
               // another, which the intersection is being dragged,
               // Byway_Vertex_Move uses the client ID it reserved, but then
               // you snap the byway to a new intersection, so the old client
               // ID is abandoned. But if you drag the vertex away from the
               // intersection again, you want to be able to use the same
               // client node ID.
               m4_DEBUG2('is_dangle: no nodes_adjacent: vertex_idx:',
                         vertex_idx, '/ this:', this);
               is_dangle = true;
            }
         }
         return is_dangle;
      }

      //
      // SIMILAR_TO: Route_Step.is_endpoint()
      override public function is_endpoint(i:int) :Boolean
      {
         m4_ASSERT((i >= 0) && (i < this.xs.length));
         return ((i == 0) || (i == (this.xs.length - 1)));
      }

      // Return true if this can be merged with other, false otherwise.
      public function is_mergeable(other:Byway) :Boolean
      {
         var nid:int;
         var b:Byway;

         // (a) Are they not the same byway?
         if (this === other) {
            return false;
         }

         // (b) Do they intersect?
         if (this.beg_node_id == other.beg_node_id
             || this.beg_node_id == other.fin_node_id) {
            nid = this.beg_node_id;
         }
         else if (this.fin_node_id == other.beg_node_id
                  || this.fin_node_id == other.fin_node_id) {
            nid = this.fin_node_id;
         }
         else {
            return false;
         }

         // (c) Do no other byways intersect at that node?
         for each (b in G.map.nodes_adjacent[nid]) {
            if (b !== this && b !== other) {
               return false;
            }
         }

         // (d) Is either byway a loop?
         if (this.beg_node_id == this.fin_node_id
             || other.beg_node_id == other.fin_node_id) {
            return false;
         }

         return true;
      }

      // Merge other into this. Callee is responsible for deleting joined
      // byways and removing them from the map.
      // NOTE: This operation merges geometry but not other attributes or
      //       link_values.
      public function join_byways(byways:Array) :void
      {
         m4_DEBUG('join_byways: merging no. byways:', byways.length);

         m4_DEBUG('join_byways: this:', this);

         // byways is the Byway_Merge command's this.edit_items which is the
         // strictly ordered array produced by our very own mergeable_array.
         m4_ASSERT(byways.length >= 2);

         var first_byway:Byway = (byways[0] as Byway);
         var final_byway:Byway = (byways[byways.length-1] as Byway);

         m4_DEBUG('  ... first_byway:', first_byway);
         m4_DEBUG('  ... final_byway:', final_byway);

         // Start with the x,y pairs of the first ordered byway...
         this.xs = Collection.array_copy(first_byway.xs);
         this.ys = Collection.array_copy(first_byway.ys);
         // and the first byway's node IDs.
         this.beg_node_id = first_byway.beg_node_id;
         this.fin_node_id = first_byway.fin_node_id;
         m4_TALKY2('a/join_byways: beg_node_id / fin_node_id:',
                   this.beg_node_id, '/', this.fin_node_id);

         // NOTE: Start at index 1, since we just consumed the first byway.
         for (var i:int = 1; i < byways.length; i++) {

            var nid_beg_new:int;
            var nid_fin_new:int;
            var join_xs:Array;
            var join_ys:Array;

            var next_byway:Byway = (byways[i] as Byway);
            m4_DEBUG('   ... next_byway:', next_byway);

            // merge geometry - four cases, ugh
            join_xs = Collection.array_copy(next_byway.xs);
            join_ys = Collection.array_copy(next_byway.ys);
            if (this.fin_node_id == next_byway.beg_node_id) {
               // next_byway follows forward
               m4_DEBUG2('join_byways: fin_node_id == next_byway.beg:',
                         this.fin_node_id);
               nid_beg_new = this.beg_node_id;
               nid_fin_new = next_byway.fin_node_id;
               join_xs.splice(0, 1);
               join_ys.splice(0, 1);
               this.xs = this.xs.concat(join_xs);
               this.ys = this.ys.concat(join_ys);
            }
            else if (this.fin_node_id == next_byway.fin_node_id) {
               // next_byway follows backward
               m4_DEBUG2('join_byways: fin_node_id == next_byway.fin:',
                         this.fin_node_id);
               nid_beg_new = this.beg_node_id;
               nid_fin_new = next_byway.beg_node_id;
               join_xs.reverse();
               join_ys.reverse();
               join_xs.splice(0, 1);
               join_ys.splice(0, 1);
               this.xs = this.xs.concat(join_xs);
               this.ys = this.ys.concat(join_ys);
            }
            else if (this.beg_node_id == next_byway.beg_node_id) {
               // next_byway precedes backward
               m4_DEBUG2('join_byways: beg_node_id == next_byway.beg:',
                         this.beg_node_id);
               nid_beg_new = next_byway.fin_node_id;
               nid_fin_new = this.fin_node_id;
               join_xs.reverse();
               join_ys.reverse();
               this.xs.splice(0, 1);
               this.ys.splice(0, 1);
               this.xs = join_xs.concat(this.xs);
               this.ys = join_ys.concat(this.ys);
            }
            else {
               m4_ASSERT(this.beg_node_id == next_byway.fin_node_id);
               // next_byway precedes forward
               m4_DEBUG2('join_byways: beg_node_id == next_byway.fin:',
                         this.beg_node_id);
               nid_beg_new = next_byway.beg_node_id;
               nid_fin_new = this.fin_node_id;
               this.xs.splice(0, 1);
               this.ys.splice(0, 1);
               this.xs = join_xs.concat(this.xs);
               this.ys = join_ys.concat(this.ys);
            }

            // clean up nodes
            var no_snap:Boolean = false;
            if (nid_beg_new != this.beg_node_id) {
               m4_DEBUG('join_byways: nid_beg_new != this.beg_node_id');
               this.beg_node_id = nid_beg_new;
               m4_DEBUG('join_byways: node_mgmt: node_init/beg:', this);
            }
            if (nid_fin_new != this.fin_node_id) {
               m4_DEBUG('join_byways: nid_fin_new != this.fin_node_id');
               this.fin_node_id = nid_fin_new;
               m4_DEBUG('join_byways: node_mgmt: node_init/fin:', this);
            }
            m4_TALKY2('b/join_byways: beg_node_id / fin_node_id:',
                      this.beg_node_id, '/', this.fin_node_id);
         }
      }

      //
      override public function vertex_create(index:int) :Vertex
      {
         m4_TALKY('vertex_create: new Byway_Vertex: index:', index);
         m4_TALKY('vertex_create: new Byway_Vertex: this:', this);
         // FIXME: Coupling. This belongs in a view class?
         return new Byway_Vertex(index, this);
      }

      // *** Protected instance methods

      //
      override protected function label_parms_compute() :void
      {
         this.label_parms_compute_line_segment();
      }

      // Recompute map_length based on my coordinates
      protected function map_length_update() :void
      {
         var i:int;

         this.map_length = 0;
         for (i = 0; i < this.xs.length - 1; i++) {
            this.map_length += Geometry.distance(this.xs[i], this.ys[i],
                                                 this.xs[i+1], this.ys[i+1]);
         }
      }

      //
      protected function tooltip_display(on:Boolean) :void
      {
         var tt:String; // tooltip text
         var rating:Number;
         var an:Annotation;

         var tag_array:Array;
         var tag:Tag;
         var insert_comma:Boolean = false;

         var tx:Number;
         var ty:Number;

         if (on) {
            m4_ASSERT(this.last_mouse_over !== null);

            // remove any current tooltip
            if (Byway.tooltip !== null) {
               ToolTipManager.destroyToolTip(Byway.tooltip);
            }

            // byway name
            if (this.name_.length > 0) {
               tt = this.name_ + '\n';
            }
            else {
               tt = 'Unnamed '
                    + Conf.tile_skin.feat_pens
                        [String(this.geofeature_layer_id)]
                        ['friendly_name']
                    + '\n';
            }

            // current rating
            if (this.user_rating != -1) {
               tt += 'Your Rating: ';
               rating = this.user_rating;
            }
            else {
               tt += 'Estimated Rating: ';
               rating = this.generic_rating;
            }
            tt += Bikeability_Rating.rating_number_to_words(rating);

            // Show a summary of the note, like the first 40 chars of the first
            // annotation.
            if (this.annotation_cnt) {
               // Get the first annotation and use in the tooltip
               if (an !== null) {
                  an = Link_Value.attachments_for_item(this, Annotation)[0]
                        as Annotation;
                  if (an.comments.length > 40) {
                     tt += '\nNote: ' + an.comments.slice(0, 37) + '...';
                  }
                  else {
                     tt += '\nNote: ' + an.comments.slice(0, 40);
                  }
               }
               else {
                  // BUG nnnn/MAYBE: Lazy-load notes on hover if user enabled
                  // tooltips and we haven't hydrated the item under hover.
                  m4_WARNING('tooltip_display: feat has notes but 0 loaded.');
               }
               // BUG nnnn: byway_tooltips/byway_tooltips_cbox: include post
               //           count? and note count?
            }

            // Add a list of tagnames to the tooltip.
            // MEH: We could use the lightweight 'tags' lookup instead, if
            //      the item is hydrated. This is just the original way of
            //      looking for tags (pre-lightweight), but it doesn't seem
            //      super slow or anything...
            tag_array = Link_Value.attachments_for_item(this, Tag);
            if (tag_array.length > 0) {
               if (tag_array.length > 1) {
                  tt += '\nTags: ';
               }
               else {
                  tt += '\nTag: ';
               }

               for each (tag in tag_array) {
                  if (insert_comma) {
                     tt += ', ';
                  }
                  tt += tag.text_;
                  insert_comma = true;
               }
            }

            // show the tooltip at the last mouse event
            tx = this.last_mouse_over.stageX;
            ty = this.last_mouse_over.stageY;
            Byway.tooltip = ToolTipManager.createToolTip(tt, tx, ty);
         }
         else {
            // hide and destroy the tooltip if it is visible
            if (Byway.tooltip !== null) {
               ToolTipManager.destroyToolTip(Byway.tooltip);
            }
            Byway.tooltip = null;
         }

         // clear last mouse over event
         this.last_mouse_over = null;
      }

      // *** Special Byway Attributes Getters and Setters

      /*/
      // FIXME: Is this the best way to get these values?
      //
      public function get one_way() :int
      {
         // Default: 0/two-way
         return this.attribute_get_value('/byway/one_way', 0);
      }
      //
      public function set one_way(one_way:int) :void
      {
         this.attribute_set_value_integer('/byway/one_way', one_way);
      }
      /*/

      //
      public function get speed_limit() :int
      {
         return this.attribute_get_value('/byway/speed_limit');
      }

      /*/
      //
      public function set speed_limit(speed_limit:int) :void {
         this.attribute_set_value_integer('/byway/speed_limit', speed_limit);
      }
      /*/

      //
      public function get lane_count() :int
      {
         return this.attribute_get_value('/byway/lane_count');
      }

      /*/
      //
      public function set lane_count(lane_count:int) :void
      {
         this.attribute_set_value_integer('/byway/lane_count', lane_count);
      }
      /*/

      //
      public function get outside_lane_width() :int
      {
         return this.attribute_get_value('/byway/outside_lane_width');
      }

      /*/
      //
      public function set outside_lane_width(outside_lane_width:int) :void
      {
         this.attribute_set_value_integer('/byway/outside_lane_width',
            outside_lane_width);
      }
      /*/

      //
      public function get shoulder_width() :int
      {
         return this.attribute_get_value('/byway/shoulder_width');
      }

      /*/
      //
      public function set shoulder_width(shoulder_width:int) :void
      {
         this.attribute_set_value_integer('/byway/shoulder_width', shoulder_width);
      }
      /*/

      // *** More complicated attribute link_value fcns.

      //
      public function get bicycle_facility() :String
      {
         // Note that the bike facil line obscures the byway rating grayness.
         // This is fine: the bike map looks better like this, and users can
         // choose to disable the bike facil ornamentation.

         var bike_facil:String = '';
         var bike_facil_attr:Attribute = Byway.get_bike_facil_attr();
         if (bike_facil_attr !== null) {
            bike_facil = this.attribute_get_value(
               bike_facil_attr.value_internal_name,
               ''); // Facility_Icon_Base.key_no_facils);
         }
         else {
            // CURIOUS: What happens with a plus instead of a comma in m4?
            m4_WARNING2("There's no kind of bike facil attr for this branch. "
                        + "What kind of Cyclopath is this?!");
         }
         return bike_facil;
      }

      //
      public static function get_bike_facil_attr() :Attribute
      {
         var attr:Attribute;
         if (Byway.bike_facil_attr_ === undefined) {
            var attr_name:String = Byway.attr_name_facil_metc;
            attr = Attribute.all_named[attr_name];
            // If the MetC attribute is not defined, fall back on the
            // public value.
            // BUG nnnn: Should MetC branch show both, or otherwise indicate
            //           if the public basemap's value differs?
            if (attr === null) {
               //attr_name = '/byway/cycle_facil';
               attr_name = Byway.attr_name_facil_basemap;
               attr = Attribute.all_named[attr_name];
            }
            Byway.bike_facil_attr_ = attr;
            // It's up to the caller to care if attr is really set, but it
            // should no longer be undefined. (Note the null != undefined
            // is actually false, so use !== undefined).
            m4_ASSERT(Byway.bike_facil_attr_ !== undefined);
         }
         return Byway.bike_facil_attr_;
      }

      //
      public function get byway_cautionary() :String
      {
         var byway_caution:String = '';
         var cautionary_attr:Attribute = Byway.get_cautionary_attr();
         if (cautionary_attr !== null) {
            byway_caution = this.attribute_get_value(
               cautionary_attr.value_internal_name,
               ''); // Facility_Icon_Base.key_no_cautys);
         }
         else {
            m4_WARNING('byway_cautionary: missing cautionary attribute?');
         }
         return byway_caution;
      }

      //
      public static function get_cautionary_attr() :Attribute
      {
         var attr:Attribute;
         if (Byway.cautionary_attr_ === undefined) {
            var attr_name:String = Byway.attr_name_cautionary;
            attr = Attribute.all_named[attr_name];
            Byway.cautionary_attr_ = attr;
            m4_ASSERT(Byway.cautionary_attr_ !== undefined);
         }
         return Byway.cautionary_attr_;
      }

   }
}


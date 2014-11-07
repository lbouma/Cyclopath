/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Base class for map items which represent geographic objects.

package items {

   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.utils.getQualifiedClassName;
   import flash.utils.Dictionary;
   import mx.utils.ObjectUtil;

   import grax.Access_Level;
   import grax.Aggregator_Base;
   import items.feats.Geosummary;
   import items.feats.Region;
   import items.utils.Geofeature_Layer;
   import items.utils.Item_Type;
   import items.verts.Vertex;
   import utils.geom.Dual_Rect;
   import utils.geom.Geometry;
   import utils.geom.MOBRable_DR;
   import utils.misc.Collection;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Map_Label;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.misc.Strutil;
   import utils.rev_spec.*;
   import views.base.Map_Layer;
   import views.base.UI;
   import views.commands.Byway_Split;
   import views.commands.Command_Base;
   import views.commands.Vertex_Add;
   import views.commands.Vertex_Delete;
   import views.map_widgets.Item_Sprite;
   import views.map_widgets.Shadow_Sprite;
   import views.map_widgets.tools.Tool_Byway_Split;
   import views.map_widgets.tools.Tool_Vertex_Add;
   import views.ornaments.Selection;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Attachment;
   import views.panel_items.Panel_Item_Geofeature;
   import views.panel_items.Panel_Item_Versioned;
   import views.panel_settings.Panel_Settings;

   public class Geofeature extends Item_Watcher_Shim implements MOBRable_DR {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Geofeature');

      // *** Mandatory attributes

      public static const class_item_type:String = 'geofeature';
      public static const class_gwis_abbrev:String = 'ft';
      public static const class_item_type_id:int = Item_Type.GEOFEATURE;

      // Skipping (because this is an intermediate class):
      // public static const dpanel_class_static:Class = Panel_Item_Geofeature;

      // *** Other static variables

      // A lookup of Geofeatures by stack_id
      public static var all:Dictionary = new Dictionary();

      // Add this to the real Z value to get the Z we show to the user. Should
      // really be a const, but I [rp] can't figure out how to change it for
      // the subclasses.
      public static var Z_USER_OFFSET:int;

      // *** Const variables

      // A Geofeature's shadow width. This is currently the same for all types.
      public const shadow_width:Number = 1.5; // FIXME: magic number

      // *** Instance variables

      // The Item_Versioned base class used to derive from sprite but this
      // created lots of overhead and breaks (by lack of memory) when you
      // create lots of Link_Values. So instead, the sprite is just a member of
      // Geofeature.
      public var sprite:Item_Sprite;

      // The geofeature layer ID
      public var geofeature_layer_id:int;

      // The z-level of this item in the map layer
      // FIXME: Rename z-level?
      public var z_level:int;

      // Ornaments
      protected var orn_selection:views.ornaments.Selection;
      public var shadow:Shadow_Sprite; // outline of the Geofeature
      public var vertices:Array; // active vertices for when selected
      public var selected_vertices:Set_UUID; // currently selected vertices

      // Parallel arrays of x/y coordinate pairs. Coordinates are stored in
      // map space and manually converted during drawing to canvas space.
      // Relying on Flash (using the UIComponent.transform attribute) doesn't
      // seem to work.
      // BUG nnnn: Support polygons with multiple interior rings,
      //    I.e.,
      //       SELECT ST_NumInteriorRings(geometry)
      //       FROM geofeature WHERE stack_id = 1446204;
      //    shows that city-regions we imported from the data deli have
      //    multiple rings
      public var xs:Array;
      public var ys:Array;
      public var digest_geo:String; // digest of geometric data

      // Label parameters -- coordinates in canvas space.
      protected var label_x:Number;
      protected var label_y:Number;
      protected var label_rotation:Number;
      public var label:Map_Label; // label object
      public var labeled:Boolean; // feature served by a label, self or other

      // Static because this class (Sprite) captures clicks on specific items,
      // but double click could span two objects if user moves mouse.
      //protected static var mouse_click_1:MouseEvent;
      //protected static var mouse_click_2:MouseEvent;

      // This fcn. gets called when the map is panned
      public var on_pan:Function;

      // Geofeatures on the map are highlighted specially if there are
      // annotations or posts about the item.
      // BUG nnnn: Shade according to number of annotations or posts, so more
      //           talked-about items are visually identifiable.
      public var annotation_cnt:* = undefined;
      public var discussion_cnt:* = undefined;

      // When selected on the map, even though the item may belong to more than
      // one panel's feats_selected, there's a specific panel associated with a
      // selected item.
      public var selection_panel:Detail_Panel_Base = null;

      // Remember when we've added mouse listeners, so we know when we have to
      // add them again (for undo/redo, which deletes and discards items but
      // then sometimes resurrects them).
      public var moused:Boolean = false;

      // When looking at version history (a widget on the details panel), the
      // user can load/show/hide different versions of the item.
      public var version_history_filter:Boolean = false;

      // *** Constructor

      public function Geofeature(xml:XML=null,
                                 rev:utils.rev_spec.Base=null)
      {
         this.sprite = new Item_Sprite(this);

         // Wait to initialize vertices until vertices_activate.
         //  this.vertices = new Array();
         //  this.selected_vertices = new Set_UUID();

         this.xs = new Array();
         this.ys = new Array();

         super(xml, rev);

         // FIXME: If this is a new item, we should indicate lazy_loaded?
         //        Or when lazy-load is requested, then we know we're a client
         //        ID, because right now the stack ID is not set...
         this.links_lazy_loaded = false;
      }

      // *** Public Static methods

      //
      public static function cleanup_all() :void
      {
         // 2013.03.09: [lb] added this but it might end up being really slow.
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            // We'll reset Geofeature.all so don't bother deleting from it.
            var skip_delete:Boolean = true;
            for each (var geofeature:Geofeature in Geofeature.all) {
               geofeature.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Geofeature.all = new Dictionary();
      }

      // Create and execute a Command_Base deleting the selected non-endpoint
      // vertices. If no such vertices exist, do nothing.
      public static function vertex_selected_delete() :void
      {
         var i:int;
         var v_parents:Array = Vertex.selected_parents;
         var v_coord_is:Array = Vertex.selected_coord_indices;
         // This looksup the vertex count: allparents[gf.stack_id] := no. verts
         var all_parents:Dictionary = new Dictionary();

         // HACK: to prevent delete commands from being issued
         m4_ASSERT(G.map.rev_workcopy !== null);
         if (!(G.map.rev_workcopy !== null)
             || (!G.map.zoom_is_vector()
                 && !(G.map.selectedset.item_get_random() is Region))) {
            return;
         }

         for (i = 0; i < v_parents.length; i++) {
            if (v_parents[i].is_endpoint(v_coord_is[i])) {
               // endpoint vertex, remove
               v_parents.splice(i, 1);
               v_coord_is.splice(i, 1);
               i--;
            }
         }

         // count number of vertices to be deleted
         for (i = 0; i < v_parents.length; i++) {
            if (!(v_parents[i].stack_id in all_parents)) {
               all_parents[v_parents[i].stack_id] = 1;
            }
            else {
               all_parents[v_parents[i].stack_id] += 1;
            }
         }

         // Make sure we don't delete too many.
         var deleted_too_many:Boolean = false;
         var feat:Geofeature;
         var parent_obj:Object;
         for (parent_obj in all_parents) {
            i = int(parent_obj);
            feat = Geofeature.all[i];
            // 2013.07.01: Is this legit?
            m4_ASSERT(feat.hydrated);
            if ((feat.vertices.length - all_parents[i]) < feat.min_vertices) {
               deleted_too_many = true;
               break;
            }
         }

         if (!deleted_too_many) {
            if (v_parents.length > 0) {
               var cmd:Vertex_Delete;
               cmd = new Vertex_Delete(v_parents, v_coord_is);
               G.map.cm.do_(cmd);
               // If we're this far -- that the user is looking at and able to
               // delete an item's vertices -- it means the items being
               // manipulated are already hydrated.
               m4_ASSERT_SOFT(cmd.is_prepared !== null);
            }
         }
      }

      // *** Item Init/Update fcns.

      //
      override public function set deleted(d:Boolean) :void
      {
         // When deleted, move the item from the class .all lookup to the
         // map's deletedset lookup. Item_Versioned manages deletedset;
         // we manage our own class lookup.
         super.deleted = d;
         /*
         if (d) {
            delete Geofeature.all[this.stack_id];
         }
         else {
            // When setting not-deleted, do the opposite.
            if (this !== Geofeature.all[this.stack_id]) {
               if (this.stack_id in Geofeature.all) {
                  m4_WARNING2('set deleted: overwrite:',
                              Geofeature.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Geofeature.all[this.stack_id] = this;
            }
         }
         */
      }

      // ***

      // NOTE: See item_cleanup, which is kind of the opposite of this fcn.
      //       Ensure that we do the opposite things of what it does, so
      //       that objects can be reused, or deassociated and reassociated
      //       with other system objects.
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_VERBOSE('init_add:', this);
         super.init_add(item_agg, soft_add);

         if (!soft_add) {
            if (this !== Geofeature.all[this.stack_id]) {
               if (this.stack_id in Geofeature.all) {
                  m4_WARNING2('init_add: overwrite:',
                              Geofeature.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Geofeature.all[this.stack_id] = this;
            }
         }
         else {
            var master_item:Geofeature = Geofeature.all[this.stack_id];
            if (master_item !== null) {
               this.master_item = master_item;
               // Draw older versions one level lower...?
               this.z_level = master_item.z_level - 1;
               m4_DEBUG('init_add: master_item: set:', this);
               m4_DEBUG('init_add: this.z_level:', this.z_level);
            }
            else{
               m4_WARNING('init_add: master_item: none?', this);
            }
         }

         if (!this.moused) {
            if (this.mouse_enable) {
               if (this.master_item === null) {
                  // In V1, this class processed mousedown and mouseup events,
                  // but it ended up competing with (as opposed to coordinating
                  // with) the map's mouse handlers. (E.g., if you mousedown on
                  // a block, drag, and then mouseup, the map is panned, but
                  // the block is also selected; the correct behavior should
                  // be one or the other, and not both: i.e., just pan the
                  // map, don't also select an item.)  In V2, this class still
                  // process mouse events, but not unless told to do so by the
                  // map object.
                  // Coupling: This class knows too much! Even though the
                  //           Geofeature class is mostly a model class, it
                  //           does have draw() commands, knowledge of the
                  //           mouse, and some other viewy stuff.
                  //m4_DEBUG('init_add: adding mouse listeners:', this);
                  this.sprite.addEventListener(MouseEvent.MOUSE_OVER,
                     this.on_mouse_over, false, 0, true);
                  this.sprite.addEventListener(MouseEvent.MOUSE_OUT,
                     this.on_mouse_out, false, 0, true);
                  this.moused = true;
               }
               else {
                  // else, this.master_item !== null, so an old item version.
                  //       We show the route line but do not allow interaction.
                  m4_DEBUG('init_add: skipping mouse handlers: this:', this);
               }
            }
            else {
               // DEVS: Be more deliberate about making sure items are
               //       removed before re-adding.
               m4_WARNING('init_add: already this.moused');
            }
         }
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_VERBOSE('Updating Geofeature:', this);
         var feat:Geofeature = Geofeature.all[this.stack_id];
         if (feat !== null) {
            m4_VERBOSE(' >> existing:', existing);
            m4_VERBOSE(' >> feat:', feat);
            m4_ASSERT((existing === null) || (existing === feat));
            this.clone_item(feat); // Calls clone_update.
         }
         else {
            m4_WARNING('Geofeature not found: stack_id:', this.stack_id);
            m4_ASSERT_SOFT(false);
         }
         return feat;
      }

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         this.update_item_all_lookup(Geofeature, commit_info);
         super.update_item_committed(commit_info);
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         return (super.is_item_loaded(item_agg)
                 || (this.stack_id in Geofeature.all));
      }

      // *** Base class getters and setters

      // If we are part of a counterpart pair, return the union of our
      // bounding box and the counterpart's bounding box.
      override public function get bbox_map() :Rectangle
      {
         var r:Rectangle;

         r = this.bbox_map_get_justme();
         if (this.counterpart_gf !== null) {
            r = r.union(this.counterpart_gf.bbox_map_get_justme());
         }

         return r;
      }

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Geofeature.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Geofeature.all;
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         m4_ASSERT(false); // Abstract
         return false;
      }

      // True if object is not on the server, that is, items created by the
      // user in the local working copy that haven't been saved yet.
      override public function get fresh() :Boolean
      {
         // EXPLAIN: Item_Revisioned just tests stack_id < 0. Are we testing
         //          stack_id <= 0 because of the dummy Geofeatures we plop on
         //          the map while the user is holding the mouse down during an
         //          add-new-geofeature command operation?
         return (this.stack_id <= 0);
      }

      // The geofeature layer friendly name.
      public function get geofeature_layer_friendly() :String
      {
         return Conf.tile_skin.feat_pens[String(geofeature_layer_id)]
                                        ['friendly_name'];
      }

      //
      // Whether or not we've sent GWIS_Item_History_Get for this item.
      public function get has_history() :Boolean
      {
         // http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/
         //    specialTypes.html --> :void Special Type is same as undefined.
         //    E.g., !== void works like !== undefined.
         var has_history:Boolean = (
               (G.item_mgr.past_versions !== null)
            && (G.item_mgr.past_versions[this.stack_id] !== undefined)
            && (G.item_mgr.past_versions[this.stack_id].length > 0));
         m4_DEBUG('has_history: has_history:', has_history);
         if (has_history) {
            m4_DEBUG2('has_history: item_mgr.past_versions.length:',
                      G.item_mgr.past_versions[this.stack_id].length);
            has_history = false;
            // Skip the last record, which is the master feature.
            // And skip index=0, which shouldn't be populated.
            for (var i:int = 1;
                 i < G.item_mgr.past_versions[this.stack_id].length-1; i++) {
               if (G.item_mgr.past_versions[this.stack_id][i] !== undefined) {
                  m4_DEBUG('has_history: found old version at: i:', i);
                  has_history = false;
                  break;
               }
            }
         }
         return has_history;
      }

      //
      public function history_add_saved() :void
      {
         if (G.item_mgr.past_versions[this.stack_id] !== undefined) {
            var past_versions:Array;
            past_versions = G.item_mgr.past_versions[this.stack_id];
            m4_DEBUG('history_add_saved: past_versions:', past_versions);
            m4_DEBUG2('history_add_saved: past_versions.length:',
                      past_versions.length);
            m4_DEBUG('history_add_saved: this.version:', this.version);

            // The past_versions array is indexed by the version number,
            // so its [0] is empty, and its length is the number of item
            // versions + 1. When this fcn. is called, a new item version
            // was just saved, so the length and the no. of vers is ==,
            // and we're going to add that new version.
            if (past_versions.length == this.version) {
               // Clear the formerly latest version, which was edited and then
               // saved.
               // STYLE_GUIDE: This is an good example of assertion usage.
               m4_ASSERT_SOFT(past_versions[past_versions.length-1] == this);
               // Rather than: past_versions[past_versions.length-1] = null;
               delete past_versions[past_versions.length-1];
               // Extend the array with the same-said item.
               past_versions.length = this.version + 1;
               past_versions[this.version] = this;

               this.version_history_list_tickle(/*reset_history=*/true);
            }
            m4_ASSERT_ELSE_SOFT;
         }
         else {
            m4_TALKY('history_add_saved: user never historied:', this);
         }
      }

      //
      override public function get hydrated() :Boolean
      {
         var hydrated:Boolean = this.links_lazy_loaded;
         hydrated &&= super.hydrated;
         return hydrated;
      }

      // More than one Geofeature can be selected at a time, so check the
      // selectedset.
      override public function is_selected() :Boolean
      {
         // Being selected means the item is highlighted on the map.
         // It also implies that the item is part of the panel's selection set.
         // MAYBE: Checking a set for membership is slow; we could maybe just
         //        make an is_selected Boolean member? The only drawback from
         //        that is that then every item in memory has the new member,
         //        but only a few use it.
         var is_selected:Boolean = G.map.selectedset.is_member(this);
         if (is_selected) {
            m4_DEBUG('is_selected:', is_selected, '/', this);
         }
         else {
            m4_VERBOSE('is_selected:', is_selected, '/', this);
         }
         // NOTE: We cannot just use this.selection_panel and ignore
         //       G.map.selectedset; see comments in the else.
         if (is_selected) {
            m4_ASSERT(this.selection_panel !== null);
         }
         else {
            // We can be called via set_selected's set_selected_ensure_removed
            // after having being removed from G.map.selectedset, but before
            // we've reset the item's selection_panel, so the selection_panel
            // is not necessarily null.
            //  Not true: m4_ASSERT(this.selection_panel === null);
         }
         return is_selected;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         m4_TALKY4('set_selected: new s:', s, 
                   '/ cur s:', this.selected,
                   '/ nix:', nix,
                   '/ solo:', solo);
         m4_TALKY('set_selected: this:', this);

         var cur_selected:Boolean = this.selected;

         super.set_selected(s, nix, solo);

         if (s != cur_selected) {

            // If selecting, we see if the item can be added to the active
            // panel and use that panel, or we find another panel to use.
            // We also draw the item differently on the map (e.g., with a
            // purple outline to show that it's selected, and we draw its
            // vertices, etc.).
            //
            // If de-selecting the item, we remove all of its selected
            // ornamentation from the map, and we remove the item from the
            // map selection set, but we only remove the item logically from
            // the panel selection if the item belongs to the active panel
            // and nix is true (which happens if the user ctrl-clicks a
            // selected item, or if deleting the item, etc., but not simply
            // when changing side panel tabs).

            // We can always de-select an item, since we don't have to figure
            // out the appropriate panel to use (see this.selection_panel). But
            // if we're selecting an item, we have to check panels first.

            var okay_to_add_item:Boolean = false;

            if (s) {

               m4_ASSERT(this.selection_panel === null);

               var target_panel:Detail_Panel_Base = null;

               if (solo) {
                  okay_to_add_item = true;
               }
               else {
                  var curr_panel:Detail_Panel_Base;

                  //curr_panel = G.panel_mgr.effectively_active_panel;
                  curr_panel = G.panel_mgr.effectively_next_panel;
                  // All Panel_Item_Versioned panels are direct descendents of
                  // the Detail_Panel_Base, but the Route_List widgets live on
                  // sub-panels of Panel_Routes_Box, so for those panels, we
                  // need to make sure we're checking the parent.
                  if (curr_panel !== null) {
                     curr_panel = curr_panel.panel_owning_panel;
                  }
                  // Do we care about panel_close_pending?

                  // See if this item is compatible with the active panel,
                  // otherwise we need to find a different panel.
                  var is_compatible:Boolean = false;
                  if (curr_panel !== null) {
                     is_compatible = curr_panel.panel_supports_feat(this);
                  }

                  if ((is_compatible) || (G.map.selectedset.length == 0)) {
                     okay_to_add_item = true;
                     if (is_compatible) {
                        target_panel = curr_panel;
                        m4_TALKY2('set_selected: effectively_active_panel:',
                                  target_panel);
                     }
                     // else, we'll find an activate a different panel.
                  }
                  // else, !is_compatible, but user is holding ctrl-key
                  // (as indicated by !solo), so they're trying to add an item
                  // of a different type to the panel. This is a no-op/ignored.
                  if (!okay_to_add_item) {
                     m4_TALKY5('set_selected: not adding: is_compatible:',
                               is_compatible, '/ map no. selected:',
                               G.map.selectedset.length,
                               '/ effectively_active_panel:',
                               G.panel_mgr.effectively_active_panel);
                  }
               }

               if ((target_panel === null) && (okay_to_add_item)) {
                  var loose_selection_set:Boolean = false;
                  var skip_new:Boolean = false;
                  var feat_panel:Panel_Item_Geofeature;
                  feat_panel = this.panel_get_for_geofeatures(
                     new Set_UUID([this,]),
                     loose_selection_set/*=false*/,
                     skip_new/*=false*/);
                  target_panel = feat_panel;
                  m4_TALKY('set_selected: using feat_panel:', target_panel);
               }

               if ((target_panel !== null) && (okay_to_add_item)) {
                  this.set_selected_ensure_added(target_panel);
               }
            }
            else {
               // !s, so de-select.
               this.set_selected_ensure_removed(nix);
            }

            // Tell the view to react.
            // 2014.07.08: Currently, only the filter-by-what's-selected
            //             filter on the discussions list cares about this.
            m4_TALKY('set_selected: itemsSelectedChanged')
            G.map.dispatchEvent(new Event('itemsSelectedChanged'));

         } // end if: (s != cur_selected)
         else {
            // else, s == this.selected.
            m4_VERBOSE('set_selected: old == new: untouched: selected:', s);
         }
      }

      //
      protected function set_selected_ensure_added(
         target_panel:Detail_Panel_Base)
            :void
      {
         // The item wasn't added when we set added_item. Add it now.
         // Although it might already be related
         // (via reactivate_selection_set).
         target_panel.feats_selected.add(this);
         if (!Collection.array_in(this, target_panel.feats_ordered)) {
            target_panel.feats_ordered.push(this);
         }

         // Make sure the item is added to the map and maybe signal an event.
         if (!G.map.selectedset.is_member(this)) {
            m4_TALKY('set_selected_ensure_addd: adding to selectedset:', this);
            G.map.selectedset.add(this);
            m4_TALKY('set_selected_ensure_added: selectedsetChanged')
            G.map.dispatchEvent(new Event('selectedsetChanged'));
         }

         // Mark the panel dirty so it's get repopulate()d.
         var dirty:Boolean = true;
         //m4_DEBUG2('selected: added_item: effectively_active_panel:',
         //          G.panel_mgr.effectively_active_panel);
         m4_DEBUG2('selected: added_item: selection_panel = target_panel:',
                   target_panel);

         this.selection_panel = target_panel;

// MAYBE: In CcpV1, clicking row in Route_List loads and shows route in map
// (and selects it) but doesn't change to route details panel.
// In CcpV2, this switches to route details panel.
// Should we load panel and just make it a green tab until user views it?
// or is opening new tab totally cool?
// maybe this is good: we can get rid of 'details' button and the
// left-hand checkbox (that determines if the route is shown on the map,
// which is CcpV2 user can control by closing route details panel), so
// then we're just left with the 'look at' button (which should either be
// moved or just copied to the geofeature details panel, i.e.,
// 'look at feats_selected bbox'.
         G.panel_mgr.panel_activate(target_panel, dirty);

         // The selection ornament shows a highlight on selected gfs.
         if (this.use_ornament_selection) {
            this.orn_selection = new views.ornaments.Selection(this);
            G.map.orn_selection.add(this.orn_selection);
         }

         // If the user clicked a block, show its vertices.
         this.vertices_activate();

         // Send a log message.
         G.sl.event('ui/select',
                    {group: this.sel_group,
                     id: this.stack_id,
                     version: this.version});

         // Maybe remind the user to save.
         UI.save_remind_maybe();

         // Tell the highlight_manager to update.
         this.set_highlighted(true);

         if (!this.links_lazy_loaded) {
            G.app.callLater(G.item_mgr.link_values_lazy_load, [this,]);
         }

         this.set_selected_ensure_finalize(true);
      } // end of: set_selected_ensure_added

      //
      protected function set_selected_ensure_removed(nix:Boolean) :void
      {
         if (this.use_ornament_selection) {
            m4_ASSERT(this.orn_selection !== null);
            G.map.orn_selection.remove(this.orn_selection);
            this.orn_selection = null;
         }

         this.vertices_deactivate();

         this.highlighted = false;

         m4_VERBOSE3('set_selected_ensure_removed:',
                     'removing from panel and map selection sets:',
                     Strutil.snippet(this.name_));

         // Remove the item from the map's selection set.
         if (G.map.selectedset.is_member(this)) {
            m4_TALKY('set_selected_ensure_removed: selectedset.remove:', this)
            G.map.selectedset.remove(this);
            m4_TALKY('set_selected_ensure_removed: selectedsetChanged')
            G.map.dispatchEvent(new Event('selectedsetChanged'));
         }

         // And from the panel's.
         if (nix) {
            if (this.selection_panel !== null) {
               this.selection_panel.feats_selected.remove(this);
               m4_ASSERT(this.selection_panel.items_selected
                         === this.selection_panel.feats_selected);
               Collection.array_remove(this,
                                       this.selection_panel.feats_ordered);
               m4_DEBUG3('set_selected_ensure_removed:',
                         'del from feats_selected/feats_ordered:', this,
                         '/ len:', this.selection_panel.items_selected.length)
               if (this.selection_panel.close_when_emptied) {
                  if (this.selection_panel.items_selected.length == 0) {
                     m4_DEBUG2('set_selected_ensure_removed:',
                               'closing empty panel:', this.selection_panel);
                     //this.selection_panel.panel_close_pending = true;
                     this.selection_panel.close_panel();
                  }
                  else {
                     m4_DEBUG3('set_selected_ensure_removed:',
                               'selection_panel.items_selected:',
                               this.selection_panel.items_selected)
                  }
               }
            }
            else {
               m4_DEBUG('selected: del from has no this.selection_panel');
            }
         }

         // We nixxed ourselves from the panel's selection set so trigger
         // its repopulate().
         if ((nix) && (this.selection_panel !== null)) {
            m4_DEBUG2('set_selected_ensure_removed:',
                      'panels_mark_dirty: selection_panel');
            G.panel_mgr.panels_mark_dirty([this.selection_panel,]);
         }

         m4_DEBUG2('set_selected_ensure_removed:',
                   'panels_mark_dirty: selection_panel = null');
         this.selection_panel = null;

         m4_DEBUG3('set_selected_ensure_removed:',
                   'version_history_filter:',
                   this.version_history_filter);
         this.version_history_filter = false;

         this.set_selected_ensure_finalize(false, nix);
      } // end of: set_selected_ensure_removed

      //
      protected function set_selected_ensure_finalize(
         s:Boolean,
         nix:Boolean=false) :void
      {
         if (this.is_drawable) {
            this.draw();
         }

         // FIXME: Statewide UI: This is untested:
         if (this.rev_is_diffing) {
            var feat:Geofeature;
            feat = this.counterpart_untyped as Geofeature;
            if (feat !== null) {

               // Set our counterpart's selected same as ours.
               // Doing this callLater so that effectively_active_panel
               // is set correctly before doing this.
               // Not yet: feat.set_selected(s, nix);
               m4_DEBUG_CLLL('>callLater: setting counterpart selected');
               G.map.callLater(
                  function() :void { feat.set_selected(s, nix); });

            }
         }

         // Update the Item Details panel to reflect the new selected
         // set. Verify the active tool is still applicable to the
         // selected set.
         m4_DEBUG_CLLL('>callLater: G.map.tool_choose_useable');
         G.app.callLater(G.map.tool_choose_useable);
      }

      // *** Getters and setters

// FIXME: route reactions. from byway.as. should be same as region and
//        waypoint?
      //
      public function get comment_color() :int
      {
/*/ FIXME: route reactions
         if (this.rev_is_diffing) {
            return Conf.comment_color_diffing;
         }
         else {
            return Conf.comment_color;
         }
/*/
         if (G.map.rmode == Conf.map_mode_historic) {
            m4_ASSERT(this.rev_is_diffing);
            return Conf.comment_color_diffing;
         }
         else if (G.map.rmode == Conf.map_mode_feedback) {
            return Conf.comment_color_feedback;
         }
         else {
            m4_ASSURT(G.map.rmode == Conf.map_mode_normal);
            return Conf.comment_color;
         }
      }

      //
      public function get comment_width() :Number
      {
         return Math.min(G.map.zoom_level - Conf.raster_only_zoom + 1,
                         Conf.comment_width);
      }

      // ActionScript won't permit us to override a method and make it return
      // something more specific. So Geofeatures must override this function.
      public function get counterpart_gf() :Geofeature
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      //
      public function get draw_color() :int
      {
         var cpt:Geofeature = (this.counterpart_gf as Geofeature);

         if (G.app.mode === G.hist_mode) {
            m4_ASSERT(this.rev_is_diffing || this.rev_is_historic);
            if ((cpt !== null) && (this.digest_geo == cpt.digest_geo)) {
               return Conf.vgroup_static_color;
            }
            else if (this.is_vgroup_old) {
               if (cpt === null) {
                  return Conf.vgroup_old_color;
               }
               else {
                  return Conf.vgroup_move_old_color;
               }
            }
            else if (this.is_vgroup_new) {
               if (cpt === null) {
                  return Conf.vgroup_new_color;
               }
               else {
                  return Conf.vgroup_move_new_color;
               }
            }
            else {
               return Conf.vgroup_static_color;
            }
         }
         else if (G.map.rmode == Conf.map_mode_feedback) {
            return Conf.vgroup_static_color;
         }
         else {
            m4_ASSURT(G.map.rmode == Conf.map_mode_normal);
            return Conf.tile_skin.feat_pens[
               String(this.geofeature_layer_id)]['pen_color'];
         }
      }

      //
      public function get draw_width() :Number
      {
         return Conf.tile_skin.feat_pens[String(this.geofeature_layer_id)]
                        .tile_pens[String(G.map.zoom_level)]['pen_width'];
      }

      //
      // NOTE
      //      Kinda like but kinda opposite Item_Versioned.actionable_at_raster
      public function get drawable_at_zoom_level() :Boolean
      {
         return true;
      }

      //
      public function get highlighted() :Boolean
      {
         return this.is_highlighted();
      }

      //
      public function set highlighted(s:Boolean) :void
      {
         m4_DEBUG('set highlighted: s:', s, '/ this:', this.softstr);
         this.set_highlighted(s);
      }

      // True if this kind of object is selectable through the map interface.
      // Default implementation returns Geofeature's mouse_enable boolean.
      public function get is_clickable() :Boolean
      {
         // FIXME: route reactions...
         //        return this.mouse_enable;
         var is_clickable:Boolean = ((G.map.rmode != Conf.map_mode_feedback)
                                     && (this.mouse_enable));
         is_clickable &&= (this.master_item === null);
         return is_clickable;
      }

      // True if this feature is drawable. Drawable items should it be drawn at
      // the current zoom level.
      public function get is_drawable() :Boolean
      {
         var suc:Boolean = false;
         var cpt:Geofeature = this.counterpart_gf;
         // This fcn is called a lot! Even on VERBOSE it's too much output
         // when you're loading the zoomed out vector level.
         //m4_VERBOSE('is_drawable: cpt: ' + cpt);
         // FIXME: Cache calculated value and recompute only when dirty
         if ((cpt !== null)
               && (this.digest_geo == cpt.digest_geo)
               && (this.is_vgroup_old)
               && (G.map.diff_show != Conf.hb_old)) {
            ; // don't draw if there's no geo changes and I'm old
         }
         else if (
               ((this.is_vgroup_old) && (G.map.diff_show == Conf.hb_new))
            || ((this.is_vgroup_new) && (G.map.diff_show == Conf.hb_old))) {
            ; // don't draw when toggle is set to exclude
         }
         else {
            //m4_VERBOSE3('is_drawable:',
            //   '/ geofeature_layer_id:', this.geofeature_layer_id,
            //   '/ access_level_id:', this.access_level_id);
            // m4_DEBUG('this.deleted:', this.deleted);
            // m4_DEBUG('G.map.zoom_level:', G.map.zoom_level);
            // m4_DEBUG('Conf.draw_param:', Conf.draw_param);
            // m4_DEBUG2('this.drawable_at_zoom_level:',
            //           this.drawable_at_zoom_level);

            suc = (!this.deleted)
                  //&& (String(this.geofeature_layer_id)
                  //    in Conf.tile_skin.feat_pens)
                  //&& (String(G.map.zoom_level) in
                  //    Conf.tile_skin.feat_pens[
                  //      String(this.geofeature_layer_id)].tile_pens)
                  && (this.drawable_at_zoom_level)
                  && (!this.version_history_filter);
         }
         //m4_VERBOSE('is_drawable: suc:', suc, '/', this);
         return suc;
      }

      // True if this feature is labelable, i.e. it should be labeled at the
      // current zoom level.
      public function get is_labelable() :Boolean
      {
         // NOTE: this.is_drawable is false if zoom_level not in draw_param[]
         var skin_do_label:Boolean =
            (Conf.tile_skin.feat_pens[String(this.geofeature_layer_id)]
             .tile_pens[String(G.map.zoom_level)]['do_label']) as Boolean;
         //m4_DEBUG2('is_labelable: geofeature_layer_id:',
         //          this.geofeature_layer_id);
         //m4_DEBUG('is_labelable: is_drawable:', this.is_drawable);
         //m4_DEBUG('is_labelable: skin_do_label:', skin_do_label);
         //m4_DEBUG4('is_labelable: view_rect_keep.intersects_map_fgrect:',
         //          (G.map.view_rect_keep !== null) ?
         //            G.map.view_rect_keep.intersects_map_fgrect(this.bbox_map)
         //            : 'null');
         //m4_DEBUG2('is_labelable: !hidden_by_filter:',
         //          !this.hidden_by_filter());
         var is_labelable:Boolean
            = ((this.is_drawable)
               && (skin_do_label)
               && ((G.map.view_rect_keep === null)
                   || (G.map.view_rect_keep.intersects_map_fgrect(
                                                   this.bbox_map)))
               && (!this.hidden_by_filter())
               );
         //m4_DEBUG('is_labelable:', is_labelable, '/', this);
         return is_labelable;
      }

      // Return the text to use in Map_Label's for the feature
      public function get label_text() :String
      {
         return this.name_;
      }

      // Return the label size (Measured in points)
      public function get label_size() :Number
      {
         return Conf.tile_skin.feat_pens[String(this.geofeature_layer_id)]
                        .tile_pens[String(G.map.zoom_level)]['label_size'];
      }

      // Minimum required vertices to be valid.  When a user is deleting
      // vertices, the command is ignored if a delete would make the feature's
      // vertices go below this number.
      // NOTE: This is valid for points and byways.  Points can never have
      //       their vertex deleted because they only ever have one vertex.
      public function get min_vertices() :int
      {
         return 2;
      }

      // True if this item can be clicked (selected) in the map (for now,
      // Geofeatures, Regions, and Waypoints, but not Terrain).
      // FIXME: also depends on user's access level to item
      protected function get mouse_enable() :Boolean
      {
         var mouse_enable:Boolean = true;
         return mouse_enable;
      }

      // If true, vertices can be selected long-term; otherwise, they are
      // selected only between mouse-down and mouse-up. Again, should really
      // be a const.
      public function get persistent_vertex_selecting() :Boolean
      {
         return false;
      }

      // Geofeatures with the same selection group are selection-compatible --
      // they can be members of the same multiselection.
      public function get sel_group() :String
      {
         return getQualifiedClassName(this);
      }

      //
      public function get sprite_order() :int
      {
         var sprite_order:int = -1;
         try {
            sprite_order = (G.map.layers[this.zplus] as Map_Layer)
                           .getChildIndex(this.sprite);
         }
         catch (e:ArgumentError) {
            // Error #2025: The supplied DisplayObject must be a child of
            //              the caller.
            // 2014.08.19: Happening because of some weird delete problem??
            m4_WARNING('sprite_order: not on map', this);
         }
         m4_DEBUG('sprite_order:', sprite_order, '/', this);
         return sprite_order;
      }

      //
      public function set sprite_order(sprite_order:int) :void
      {
         m4_ASSURT(false);
      }

      // True if the feature uses the standard ornament selection
      public function get use_ornament_selection() :Boolean
      {
         return true;
      }

      // True if vertex adding is supported, add if the vertex add tool
      // should be enabled if this geofeature is selected.
      public function get vertex_add_enabled() :Boolean
      {
         return false;
      }

      // True if this kind of object can have its vertices edited.
      public function get vertex_editable() :Boolean
      {
         return false;
      }

      //
      //override public function get visible() :Boolean
      public function get visible() :Boolean
      {
         return this.sprite.visible;
      }

      //
      public function set visible(s:Boolean) :void
      {
         //m4_VERBOSE('set visible:', s, '/', this);
         //m4_TALKY2('set visible: version_history_filter:',
         //          this.version_history_filter);
         var tickle_version_history_list:Boolean = false;
         if (this.sprite.visible != s) {
            tickle_version_history_list = true;
         }
         this.sprite.visible = s;
         if (this.shadow !== null) {
            this.shadow.visible = s;
         }
         if (this.label !== null) {
            this.label.visible = s;
         }
         if (this.orn_selection !== null) {
            this.orn_selection.visible = s;
         }
         if (tickle_version_history_list) {
            m4_TALKY('set visible: version_history_list_tickle:', this);
            this.version_history_list_tickle();
         }

         this.draw_all();
      }

      // ***

      //
      public function version_history_list_tickle(reset_history:Boolean=false)
         :void
      {
         var feat_panel:Panel_Item_Geofeature;
         feat_panel = (this.selection_panel as Panel_Item_Geofeature);
         m4_TALKY('version_history_list_tickle: feat_panel:', feat_panel);

         if (feat_panel !== null) {

            // MAYBE/BUG nnnn: Keep a copy of the latest version of each edited
            // item, and add a new row to the version history widget when the
            // user starts editing the item. This is so the user could use the
            // revert command to undo changes, rather than using the cmd mgr's
            // undo or reset features. Basically, if (this.dirty), check the
            // length of the past_versions array, and add the edited item
            // as an unsaved version. But we'd have to clone the item before
            // it's edited -- maybe in Command_Base, if an item is not dirty,
            // maybe clone it there and modify G.item_mgr.past_versions from
            // Command_Base...
            //
            // For now, we just indicate that the latest item version is
            // being edited, and after saving the item, what was the latest
            // item is no longer in memory, so the user has to click Load
            // and then Revert To. We could avoid this is Command_Base cloned
            // unedited items before they were edited...

            feat_panel.version_history_list_tickle(reset_history);
         }
      }

      // ***

      //
      public function get zplus() :Number
      {
         // MAYBE: Override bridge level using gfl ID?
         //        CcpV1 did this, but it smells fishy...
         var dc:int = 0;
         // HACK: draw bike paths and sidewalks on top of other types.
         dc = (((this.geofeature_layer_id
                 == Geofeature_Layer.BYWAY_BIKE_TRAIL)
                || (this.geofeature_layer_id
                    == Geofeature_Layer.BYWAY_MAJOR_TRAIL))
               ? 99 : this.geofeature_layer_id);
         // EXPLAIN: This calculation:
         ////dc = (this.z_level + dc / 100.0);
         //dc = this.z_level + (dc / 100.0);

         // Argh, no hack, be predictable and just use the bridge level
         // (for byways, etc.) and for other classes use their indicated
         // z_level...
         dc = this.z_level;
         return dc;

         // FIXME: Is this better?
         ////dc = (
         ////   ((this.geofeature_layer_id == Draw_Class.BYWAY_BIKE_TRAIL)
         ////    || (this.geofeature_layer_id == Draw_Class.BYWAY_MAJOR_TRAIL))
         ////   ? 99 : 0);
         ////return (this.z_level + dc / 100.0);
         //return ((this.z_level + dc) / 100.0);
      }

      //
      public function get z_user() :int
      {
         return this.z_level + Geofeature.Z_USER_OFFSET;
      }

      //
      public function set z_user(z:int) :void
      {
         this.z_level = z - Geofeature.Z_USER_OFFSET;
      }

      // *** Base class overrides

      // NOTE: item_cleanup effectively removes an item from the map and from
      //       lookups (it disassociates the item from the rest of the system).
      //       See init_add and init_update, which should take care of undoing
      //       any actions taken herein, in case an item is later reassociated.
      //       See Command_Base commands' do_ and undo functions for good
      //       examples of this: commands remember items that have been cleaned
      //       up so that they can be reused, for when the user reverses a
      //       command.
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         m4_VERBOSE('item_cleanup:', this, '/ i:', i);

         var feat_panel:Panel_Item_Geofeature;
         feat_panel = (this.selection_panel as Panel_Item_Geofeature);
         m4_TALKY('item_cleanup: selection_panel: feat_panel:', feat_panel);

         super.item_cleanup(i, skip_delete);

         // EXPLAIN Why doesn't Geofeature check this.invalid like Attachment
         //         and Link_Value?

         if (this.label !== null) {
            // 2013.04.17: Bug nnnn: Routes don't have labels? I guess not...
            //             We should make labels for routes.
            // 2012.12.10: The last comment is wrong: the route object stores
            // the letter labels that sit atop the colorful route stop circles.
            try {
               m4_TALKY2('item_cleanup: removing map label:', this.label,
                         '/', this);
               G.map.feat_labels.removeChild(this.label);
            }
            catch (e:ArgumentError) {
               // No-op
            }
         }
         this.label = null;

         // CcpV1: G.map.shadows[this.zplus].removeChildAt(i);
         // MAYBE: I think the derived classes are also doing this self-same
         // thing, removing the shadow from the map lookup. Which is probably
         // why [lb] had to wrap this in a try/catch -- because Geofeature is
         // removing the shadow and then, e.g., Byway and Geosummary have
         // nothing to remove.
         if ((this.shadow) && (G.map.shadows[this.zplus] != undefined)) {
            try {
               G.map.shadows[this.zplus].removeChild(this.shadow);
            }
            catch (e:ArgumentError) {
               // No-op
            }
         }
         // Don't clear shadow, which is born in ctor and lives as old as us.
         // No: this.shadow = null;

         this.set_selected(false, /*nix=*/true);

         //// Remove link_values
         //var links:Set_UUID;
         //links = Link_Value.item_get_link_values(this);
         //for each (var o:Link_Value in links) {
         //   m4_DEBUG('item_cleanup: removing link');
         //   o.item_cleanup();
         //}

         if (this.moused) {
            //m4_DEBUG('item_cleanup: removing mouse listeners:', this);
            this.sprite.removeEventListener(MouseEvent.MOUSE_OVER,
                                            this.on_mouse_over);
            this.sprite.removeEventListener(MouseEvent.MOUSE_OUT,
                                            this.on_mouse_out);
            this.moused = false;
         }

         // Remove historic item versions.

         var past_versions:Array = G.item_mgr.past_versions[this.stack_id];
         // Delete past_versions now so we don't enter an infinite loop when
         // we call item_cleanup on any old versions.
         delete G.item_mgr.past_versions[this.stack_id];
         m4_TALKY('item_cleanup: past_versions:', past_versions);
         if (past_versions !== null) {
            for each (var other_version:Geofeature in past_versions) {
               if ((other_version !== null)
                   // 2014.08.20: Really weird problem: if you run across
                   // 'this' in past_versions and removeChild on its sprite,
                   // you'll sometimes randomly remove another geofeature's
                   // sprite instead! [lb] deleted E 24th St and for some
                   // reason W River Pkwy Trail's sprite was deleted, but
                   // just the main sprite, i.e., there was a white line
                   // but you'd see connectivity and highlights, but if
                   // you zoomed out, the white line would look just the
                   // same (e.g., if you zoomed way out, you'd still see
                   // it just the same), but changing the z-level or trying
                   // to delete the rogue road would throw an exception
                   // because the sprite is no longer part of G.map.layers.
                   // So check that we're not attacking ourselves.
                   && (other_version !== this)) {
                  try {
                     m4_TALKY2('item_cleanup: removeChild: other_version:',
                               other_version);
                     G.map.layers[other_version.zplus].removeChild(
                                             other_version.sprite);
                  }
                  catch (e:ArgumentError) {
                     // No-op
                  }
                  other_version.item_cleanup();
               }
            }
         }
         this.version_history_filter = false;
         if (feat_panel !== null) {
            feat_panel.version_history_list_tickle();
         }

         // Remove self from base class lookup.
         if (!skip_delete) {
            delete Geofeature.all[this.stack_id];
         }
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Geofeature = (to_other as Geofeature);
         super.clone_once(other);

         other.geofeature_layer_id = this.geofeature_layer_id;
         other.z_level = this.z_level;
         other.digest_geo = this.digest_geo;

         // Clear things we want clone_update to set.
         other.xs = null;
         other.ys = null;
         other.annotation_cnt = undefined;
         other.discussion_cnt = undefined;
      }

      //
      override protected function clone_update( // on-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Geofeature = (to_other as Geofeature);
         super.clone_update(other, newbie);
         if ((other.xs === null) || (other.xs.length == 0)) {
            //m4_DEBUG('clone_update: copying this.xs:', this.xs);
            other.xs = Collection.array_copy(this.xs);
         }
         if ((other.ys === null) || (other.ys.length == 0)) {
            //m4_DEBUG('clone_update: copying this.ys:', this.ys);
            other.ys = Collection.array_copy(this.ys);
         }
         // Skipping: label_x, label_y, label_rotation, label, labeled
         // Skipping: mouse_enable, on_pan
         // FIXME: Copy all attachment links, like notes and posts?
         // FIXME: Copy just basic attribute links, like one_way, etc.
         if (other.annotation_cnt === undefined) {
            other.annotation_cnt = this.annotation_cnt;
         }
         if (other.discussion_cnt === undefined) {
            other.discussion_cnt = this.discussion_cnt;
         }
         // Skipping: links_reqs_outstanding, links_lazy_loaded
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);

         if (gml !== null) {

            this.geofeature_layer_id = int(gml.@gflid);
            this.z_level = int(gml.@z);
            this.digest_geo = gml.@dg;

            if ('@nann' in gml) {
               this.annotation_cnt = int(gml.@nann);
            }
            if ('@ndis' in gml) {
               this.discussion_cnt = int(gml.@ndis);
            }
            // NOTE: Signalling event elsewhere.
            //       G.item_mgr.dispatchEvent(new Event('attcCountsLoaded'));

            // FIXME: Reimplement and replace
            //this.nthreads = gml.@nthreads;
            //this.np_new = gml.@np_new;
            //this.np_old = gml.@np_old;
            // with annotation_cnt, discussion_cnt
         }
         else {
            this.geofeature_layer_id = -1;
         }
      }

      // Return an XML element representing myself.
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         gml.@gflid = this.geofeature_layer_id;
         gml.@z = this.z_level;
         gml.appendChild(Geometry.coords_xys_to_string(this.xs, this.ys));
         return gml;
      }

      // *** Instance methods

      // Return map-space of my bounding box, without considering counterpair
      // pairs.
      //
      // NOTE: This loops through all vertices. You might think that's too
      // slow for a getter. For the time being, performance is fine. If this
      // later turns out to be not the case, the right place for the caching
      // logic is in Item_Base. There was a draft of this in r12601, but it
      // turned out to be unneeded so I removed it.
      protected function bbox_map_get_justme() :Rectangle
      {
         var i:int;
         var x_min:Number = Number.POSITIVE_INFINITY;
         var y_min:Number = Number.POSITIVE_INFINITY;
         var x_max:Number = Number.NEGATIVE_INFINITY;
         var y_max:Number = Number.NEGATIVE_INFINITY;

         for (i = 0; i < this.xs.length; i++) {
            x_min = Math.min(x_min, this.xs[i]);
            y_min = Math.min(y_min, this.ys[i]);
            x_max = Math.max(x_max, this.xs[i]);
            y_max = Math.max(y_max, this.ys[i]);
         }

         return new Rectangle(x_min, y_min, (x_max - x_min), (y_max - y_min));
      }

      // Draw myself
      public function draw(is_drawable:Object=null) :void
      {
         this.vertices_redraw();
         if (G.map.to_be_highlighted.indexOf(this.stack_id) > -1) {
            m4_DEBUG_CLLL('>callLater: this.set_highlighted');
            G.map.callLater(this.set_highlighted,
               [true, Conf.attachment_highlight,]);
            G.map.to_be_highlighted.splice(
               G.map.to_be_highlighted.indexOf(this.stack_id), 1);
         }
      }

      // Draw myself and all associated objects
      public function draw_all() :void
      {
         this.draw();
         this.label_reset();
         this.label_maybe();
      }

      //
      public function editor_show() :void
      {
         throw new Error('abstract');
      }

      //
      public function geofeature_added_to_map_layer() :void
      {
         var is_drawable:Boolean;
         if ((this.shadow !== null) && (this.shadow.mouseEnabled)) {
            //m4_DEBUG2('feat_added_to_map_lyr: sprite.hitArea:', this.shadow,
            //          '/ this:', this);
            this.sprite.hitArea = this.shadow;
         }
         // Get is_drawable just once, since it's a calculated value.
         is_drawable = this.is_drawable;
         this.visible = is_drawable && !(this.hidden_by_filter());
         m4_VERBOSE('geofeature_added_to_map_layer: visible:', this.visible);
         this.draw(is_drawable);
      }

      // This is called by the draw() functions to decide how to shade items
      // being diffed. If there are non-geometric changes to an item between
      // revisions, we want to highlight the item on the map to indicate to the
      // user that the item is changed.
      protected function has_non_geo_changes() :Boolean
      {
         var non_geo:Boolean = false;
         var lv:Link_Value = null;

         // FIXME: See comment in item_versioned.py; digest_nongeo is broken

         if (this.rev_is_diffing) {

            non_geo = ((this.is_vgroup_new || this.is_vgroup_old)
                       && (this.counterpart_untyped !== null)
                       && (this.digest_nongeo
                           != this.counterpart_untyped.digest_nongeo));

            // FIXME: Reimplement and replace
            //        with annotation_cnt, discussion_cnt
            /*
            if (!non_geo
                && (this.np_old >= 0)
                && (this.np_new != this.np_old)) {
               non_geo = true;
            }
            */

            if (!non_geo) {
               // If the geofeature's non-geometric values haven't changed,
               // check the links associated with this geofeature.
               for each (lv in Link_Value.item_get_link_values(this)) {
                  if ( // See if the link_value itself changed
                      (lv.counterpart_untyped === null
                        && (lv.is_vgroup_old || lv.is_vgroup_new))
                       // or if the attachment it references has changed
                      || lv.attachment_has_nongeo_changes) {
                     non_geo = true;
                     break;
                  }
               }
            }
         }

         return non_geo;
      }

      //
      public function hidden_by_filter() :Boolean
      {
         return false;
      }

      // A dangle is an endpoint with which no other geofeatures use except
      // this guy. The [i]ndex should be 0 or the last index.
      public function is_dangle(i:int) :Boolean
      {
         return false;
      }

      // Return true if the given index is that of an endpoint vertex, false
      // otherwise. Return false if my type has no notion of endpoint.
      public function is_endpoint(i:int) :Boolean
      {
         return false;
      }

      //
      public function is_highlighted(l:String=null) :Boolean
      {
         return G.map.highlight_manager.is_highlighted(this, l);
      }

      // Draw my label. Note that if a label already exists, it will be
      // orphaned -- this method does not remove it from the label layer.
      public function label_draw(halo_color:*=null) :void
      {
         var r:Rectangle;

         m4_TALKY('label_draw: label_text:', this.label_text, '/', this);

         this.label = new Map_Label(this.label_text,
                                    this.label_size,
                                    this.label_rotation,
                                    this.label_x,
                                    this.label_y,
                                    this,
                                    halo_color);

         var settings_panel:Panel_Settings = G.tabs.settings.settings_panel;
         if (this.rev_is_diffing && this.is_vgroup_static) {
            this.label.textColor = Conf.vgroup_static_label_color;
         }
         else if (settings_panel.settings_options.aerial_cbox.selected) {
            this.label.textColor = Conf.aerial_label_color;
         }

         m4_TALKY('label_draw: adding map label:', this.label, '/', this);
         G.map.feat_labels.addChild(this.label);

         // FIXME: This hack prevents Waypoint labels from being not drawn
         //        due to existing labels being in the way. However, what
         //        we really need is a smarter labeling algorithm; an
         //        incremental solution might be z-order priority of labels.
         if ((!(this is Geosummary))
             && (G.map.feat_labels.child_collides(this.label))) {
            //m4_DEBUG('label_draw: conflict detected:', this);
            this.label_reset();
         }
      }

      // Label myself if I need labeling, otherwise clear any leftover labels
      public function label_maybe() :void
      {
         if (this.is_labelable) {
            m4_TALKY('label_maybe: is_labelable:', this);
            if (this.label === null) {
               this.label_parms_compute();
               this.label_draw();
            }
         }
         else {
            m4_TALKY('label_maybe: not is_labelable:', this);
            this.label = null;
         }
      }

      // Compute label parameters
      protected function label_parms_compute() :void
      {
         m4_ERROR('label_parms_compute: not implemented for class:', this);
         //m4_ASSERT(false); // Abstract
      }

// BUG nnnn: Street labels cover one_way arrows
//           -- because both are drawn in the center of the byway segment.
// BUG nnnn: Street label and one_way arrow placement awkward
// Street labels and one_way arrows drawn in the center of individual
// segments, rather than center of collection of segments of similiar
// qualities, so the labels and arrows are drawn in the middle of segments,
// sometimes one on top of the other, without regard to adjacent segments.
// It looks also like some labels on drawn of one of their endpoints rather
// than the middle: this happens when the line segment has a break in the
// middle: the label algorithm computers the middle of each set of points, but
// what if one of the points is the middle of the whole segment? Then this
// algorithm fails, and the label gets centered one of the endpoints.
// Solution: (1) Make composite line segment of byways so intersections don't
// create problems for placing labels and arrows. (2) Use TextField's
// (Map_Label's) textWidth member to split the label at nodes: if the placement
// of label (ignore arrows for now) crosses node, use multiple TextFields to
// draw text that follows the street.
// that
      protected function label_parms_compute_line_segment() :void
      {
         var i:int;
         var dists:Array; // from the start point at each coordinate pair
         var dist_total:Number;
         var deltad:Number;

         // Compute cumulative distances along linestring
         dists = new Array(this.xs.length);
         dists[0] = 0.0;
         for (i = 1; i < this.xs.length; i++) {
            dists[i] = dists[i-1]
                       + Geometry.distance(this.xs[i-1], this.ys[i-1],
                                           this.xs[i], this.ys[i]);
         }

         // Locate midpoint segment
         dist_total = dists[dists.length-1];
         for (i = 0; i < dists.length - 1; i++) {
            if (dists[i+1] > dist_total/2) {
               break;
            }
         }
         // i now contains index of the point _beginning_ the segment which
         // contains the midpoint of the linestring.

         // Compute center of linestring
         deltad = dists[i+1] - dists[i];
         this.label_x = ((this.xs[i] * (dist_total/2 - dists[i])
                          + this.xs[i+1] * (dists[i+1] - dist_total/2))
                         / deltad);
         this.label_y = ((this.ys[i] * (dist_total/2 - dists[i])
                          + this.ys[i+1] * (dists[i+1] - dist_total/2))
                         / deltad);
         this.label_x = G.map.xform_x_map2cv(this.label_x);
         this.label_y = G.map.xform_y_map2cv(this.label_y);

         // Compute rotation angle
         // Negated to convert CCW to CW rotation
// 20111010: Use to get normal vector?
         this.label_rotation = -Math.atan2(this.ys[i] - this.ys[i+1],
                                           this.xs[i] - this.xs[i+1]);

         // Keep text upright
         if (this.label_rotation < -Math.PI/2) {
            this.label_rotation += Math.PI;
         }
         if (this.label_rotation > Math.PI/2) {
            this.label_rotation -= Math.PI;
         }
      }

      // Reset labeling state.
      public function label_reset() :void
      {
         m4_TALKY('label_reset:', this, '/ label:', this.label);
         if (this.label !== null) {
            // Remove label from map, if it's there.
            try {
               m4_TALKY2('label_reset: removing map label:', this.label,
                         '/', this);
               G.map.feat_labels.removeChild(this.label);
            }
            catch (e:ArgumentError) {
               // No-op
            }
            this.label = null;
         }
      }

      //
      // Really old comment from Route.as: this getter is very slow and should
      // not really be treated as an attribute, but caching the result is
      // currently problematic due to Dual_Rect bugs. [whatever that means?]
      public function get mobr_dr() :Dual_Rect
      {
         return Dual_Rect.mobr_dr_from_xys(this.xs, this.ys);
      }

      //
      public static function mobr_dr_union(feats:*) :Dual_Rect
      {
         var mobr_dr:Dual_Rect = null;
         for each (var fobj:Object in feats) {
            var feat:Geofeature = (fobj as Geofeature);
            if (feat !== null) {
               if ((feat.xs !== null) && (feat.ys !== null)) {
                  if (mobr_dr === null) {
                     mobr_dr = Dual_Rect.mobr_dr_from_xys(feat.xs, feat.ys);
                  }
                  else {
                     mobr_dr = mobr_dr.union(
                               Dual_Rect.mobr_dr_from_xys(feat.xs, feat.ys));
                  }
               }
               else {
                  m4_WARNING('mobr_dr_union: no feat.xs/.ys:', feat);
                  m4_ASSERT_SOFT(false);
               }
            }
            else {
               m4_WARNING('mobr_dr_union: not a feat:', fobj);
               m4_ASSERT_SOFT(false);
            }
         }
         if (mobr_dr === null) {
            // Return an uninitialzed Dual_Rect. We expect that callers will
            // call Dual_Rect.valid before doing anything with it.
            mobr_dr = new Dual_Rect();
         }
         return mobr_dr;
      }

      // Move the feature by (xdelta,ydelta) in canvas coordinates.
      public function move_cv(xdelta:Number, ydelta:Number) :void
      {
         var i:int;

         for (i = 0; i < this.xs.length; i++) {
            this.vertex_move(i, G.map.xform_xdelta_cv2map(xdelta),
                             G.map.xform_ydelta_cv2map(ydelta));
         }
      }

      //
      public function panel_get_for_geofeatures(
         feats_being_selected:*,
         loose_selection_set:Boolean=false,
         skip_new:Boolean=false)
            :Panel_Item_Geofeature
      {
         return Geofeature.panel_get_for_geofeatures_(
                  feats_being_selected,
                  loose_selection_set,
                  skip_new);
      }

      //
      protected static function panel_get_for_geofeatures_(
         feats_being_selected:*,
         loose_selection_set:Boolean=false,
         skip_new:Boolean=false)
            :Panel_Item_Geofeature
      {
         var feat_panel:Panel_Item_Geofeature = null;

         // The feats_being_selected collection should be a set.
         if (feats_being_selected is Array) {
            feats_being_selected = new Set_UUID(feats_being_selected);
         }
         else {
            m4_ASSERT(feats_being_selected is Set_UUID); 
         }

         // Get one of the feats to see what type it is, so we know which
         // panels to which it applies.
         m4_ASSERT(feats_being_selected.length > 0);
         var test_feat:Geofeature = (feats_being_selected.item_get_random()
                                     as Geofeature);
         m4_ASSERT(test_feat !== null);

         var ripe:Boolean = false;

         var shows_type:Boolean;

         // Try the active panel first.
         var curr_panel:Detail_Panel_Base;
         // MAYBE: Use test_feat.selection_panel instead??
         curr_panel = G.panel_mgr.effectively_next_panel;
         m4_DEBUG('gpfgfs: effectively_next_panel:', curr_panel);
         feat_panel = (curr_panel as Panel_Item_Geofeature);
         if (feat_panel !== null) {
            shows_type = (test_feat is feat_panel.shows_type);
            if (shows_type) {
               ripe = Geofeature.panel_ripe_for_geofeatures(
                  feat_panel, feats_being_selected, loose_selection_set);
            }
         }

         if (ripe) {
            m4_DEBUG('gpfgfs: ripe feat_panel/1:', feat_panel);
         }
         else {
            feat_panel = null;
            // Go through all side panels if the active panel was not hit.
            m4_TALKY('gpfgfs: searching side_panels');
            for each (var o:Object in G.panel_mgr.panel_lookup) {
               var feat_sidep:Panel_Item_Geofeature;
               feat_sidep = (o as Panel_Item_Geofeature);
               m4_TALKY(' .. feat_sidep:', feat_sidep);
               shows_type = ((feat_sidep !== null)
                             && (test_feat is feat_sidep.shows_type));
               if (shows_type) {
                  ripe = Geofeature.panel_ripe_for_geofeatures(
                     feat_sidep, feats_being_selected, loose_selection_set);
               }
               if (ripe) {
                  if ((!feat_sidep.panel_close_pending)
                      || (!loose_selection_set)) {
                     m4_DEBUG('gpfgfs: ripe feat_sidep/2:', feat_sidep);
                     feat_panel = feat_sidep;
                     feat_panel.panel_close_pending = false;
                     break;
                  }
                  else {
                     // A loose selection, which means other items might also
                     // be selected, and the panel is supposedly being closed,
                     // so we shouldn't assimilate it.
                     var not_loose:Boolean = false;
                     ripe = Geofeature.panel_ripe_for_geofeatures(
                        feat_sidep, feats_being_selected, not_loose);
                     if (ripe) {
                        m4_DEBUG('gpfgfs: ripe feat_sidep/3:', feat_sidep);
                        feat_panel = feat_sidep;
                        break;
                     }
                  }
               }
               if ((shows_type)
                   && (!G.tabs.settings.multiselections_cbox)) {
                  m4_DEBUG('gpfgfs: reusing typed feat_sidep:', feat_sidep);
                  feat_panel = feat_sidep;
                  var force_reset:Boolean = true;
                  feat_panel.panel_selection_clear(force_reset/*=true*/,
                                                   feats_being_selected);
                  break;
               }
               else {
                  m4_DEBUG2('gpfgfs: ignoring panel:',
                            ((feat_sidep !== null) ? feat_sidep : o));
               }
            }
            if (feat_panel === null) {
               if (!skip_new) {
                  // Get a new Geofeature panel.
                  m4_DEBUG('gpfgfs: test_feat:', test_feat);
                  feat_panel = (G.item_mgr.item_panel_create(test_feat)
                                as Panel_Item_Geofeature);
                  if (feat_panel !== null) {
                     // MAYBE: Call G.panel_mgr.panel_register(gf_panel); ??
                     G.panel_mgr.panel_register(feat_panel);
                     // Don't forget to set the selection set of panel_activate
                     // will try to close the panel right away... haha!
                     feat_panel.feats_selected = feats_being_selected;
                     m4_DEBUG('gpfgfs: created new feat_panel:', feat_panel);
                  }
                  // else, item_panel_create already soft-asserted.
               }
               else {
                  m4_DEBUG('gpfgfs: nothing found / skip_new');
               }
            }
            m4_ASSERT(!feat_panel.panel_close_pending);
         }

         return feat_panel;
      }

      //
      public static function panel_ripe_for_geofeatures(
         feat_panel_candidate:Panel_Item_Geofeature,
         feats_being_selected:Set_UUID,
         loose_selection_set:Boolean=false)
            :Boolean
      {
         var is_ripe:Boolean = true;

         // NOTE: Caller assures that panel supports this geofeature
         //       (see feat_panel_candidate.shows_type).

         m4_TALKY2('panel_ripe_for_geofeatures: checking candidate:',
                   feat_panel_candidate);

         m4_ASSERT(feat_panel_candidate !== null);

         // The panel might be empty, or might have been emptied and is about
         // to be closed. Perhaps we can salvage it.
         if (feat_panel_candidate.feats_selected.length == 0) {
            // The caller assures that the panel supports this panel type,
            // so reuse this panel.
            feat_panel_candidate.feats_selected = feats_being_selected;
         }
         else if (loose_selection_set) {
            for each (var feat:Geofeature in feats_being_selected) {
               if (!feat_panel_candidate.feats_selected.is_member(
                                                            feat)) {
                  is_ripe = false;
                  break;
               }
            }
         }
         else { // !loose_selection_set, so use equals, not subset.
            if (!feat_panel_candidate.feats_selected.equals(
                                       feats_being_selected)) {
               is_ripe = false;
            }
         }
         if (is_ripe) {
            feat_panel_candidate.panel_close_pending = false;
         }

         return is_ripe;
      }

      //
      public function set_highlighted(s:Boolean, l:String=null) :void
      {
         m4_DEBUG_CLLL('set_highlighted: <callLater: set_highlighted');
         G.map.highlight_manager.set_highlighted(this, s, l);
      }

      // *** Vertex methods

      // Create a vertex, can be overridden to provide custom vertices.
      // The returned vertex should have the given index, and have this
      // be the parent.
      public function vertex_create(index:int) :Vertex
      {
         return new Vertex(index, this);
      }

      // Remove the vertex at index j (bubbling the remaining vertices down).
      public function vertex_delete_at(j:int) :void
      {
         var i:int;

         if (this.vertices !== null) {
            this.vertex_uninit(this.vertices[j]);
            this.vertices.splice(j, 1);
            for (i = j; i < this.vertices.length; i++) {
               this.vertices[i].coord_index = i;
            }
         }
         else if (this.selected) {
            m4_WARNING('vertex_delete_at: no vertices: j:', j, '/', this);
         }
         this.xs.splice(j, 1);
         this.ys.splice(j, 1);
      }

      // Initialize the vertex at index i.
      public function vertex_init(i:int) :void
      {
         //m4_DEBUG('vertex_init: adding vertex: i:', i, '/', this);
         // For some reason, this.vertices[i] !== null returns true,
         // even after we've just call this.vertices = new Array(n);,
         // so [lb] guesses maybe it's undefined instead. Whatever.
         // Just try to make a Vertex first to make sure we don't
         // leave a phantom vertex on the map (i.e., if we already
         // created a Vertex, make sure we delete that earlier Vertex).
         var v:Vertex = this.vertices[i];
         if (v !== null) {
            m4_WARNING('vertex_init: already vertex at i:', i, '/ v:', v);
            // This calls: G.map.vertices.removeChild(v);
            this.vertex_uninit(v);
         }
         v = this.vertex_create(i);
         //m4_DEBUG('vertex_init: adding vertex: v:', v);
         this.vertices[i] = v;
         G.map.vertices.addChild(v);
         v.init();
         v.draw();
      }

      // Insert a new vertex at index j at the map coordinates (x,y).
      public function vertex_insert_at(j:int, x:Number, y:Number) :void
      {
         var i:int;

         this.xs.splice(j, 0, x);
         this.ys.splice(j, 0, y);
         //m4_DEBUG('vertex_insert_at: this.xs:', this.xs);
         //m4_DEBUG('vertex_insert_at: this.ys:', this.ys);
         if (this.vertices !== null) {
            this.vertices.splice(j, 0, null);
            this.vertex_init(j);
            for (i = j + 1; i < this.vertices.length; i++) {
               this.vertices[i].coord_index = i;
            }
         }
         this.draw_all();
      }

      // xdelta and ydelta are in map coordinates
      public function vertex_move(i:int, xdelta:Number, ydelta:Number) :void
      {
         var v:Vertex;

         if (this.vertices !== null) {
            v = this.vertices[i];
            v.x_map += xdelta;
            v.y_map += ydelta;
            v.draw();
         }
         else {
            m4_ASSERT_SOFT(!this.selected);
            this.xs[i] += xdelta;
            this.ys[i] += ydelta;
         }
      }

      // Return the index where a new vertex at (x,y) in map coordinates would
      // best fit; i.e., if it's inserted there that would be its index.
      // Return -1 if no possible fit exists. NOTE: Assumes internal vertex;
      // i.e., won't propose adding a new endpoint vertex.
      public function vertex_place_new(x:Number, y:Number) :int
      {
         var i:int;
         var dist:Number;
         var i_best:int;
         var dist_best:Number;

         m4_ASSERT(this.xs.length >= 2);

         dist_best = Infinity;
         for (i = 0; i < this.xs.length - 1; i++) {
            dist = Geometry.distance_point_line(x, y,
                                                this.xs[i], this.ys[i],
                                                this.xs[i+1], this.ys[i+1]);
            if (dist < dist_best) {
               i_best = i;
               dist_best = dist;
            }
         }

         if (dist_best >= G.map.xform_scalar_cv2map(this.draw_width / 2)) {
            return -1;
         }
         else {
            return i_best + 1;
         }
      }

      //
      public function vertex_uninit(v:Vertex) :void
      {
         //m4_DEBUG('vertex_uninit: removing vertex:', v);
         v.vertex_cleanup();
         G.map.vertices.removeChild(v);
      }

      // Called when this feature is selected.  It creates a Vertex for
      // each element in the xs and ys array, makes it visible, inits the
      // vertex, adds some default mouse listeners, and draws it.
      public function vertices_activate() :void
      {
         m4_DEBUG3('vertices_activate: vertex_editable:', this.vertex_editable,
                   '/ vertices.length:',
                   ((this.vertices !== null) ? this.vertices.length : 'null'));
         if (this.vertices === null) {
            var i:int = 0;
            if (this.vertex_editable) {
               this.selected_vertices = new Set_UUID();
               this.vertices = new Array(this.xs.length);
               for (i = 0; i < this.vertices.length; i++) {
                  this.vertex_init(i);
               }
            }
         }
         else {
            m4_TALKY('vertices_activate: redundant');
            m4_ASSERT(this.vertices.length == this.xs.length);
         }
      }

      // Called when this feature is no longer selected. It cleanups all
      // of the previously activated vertices.
      public function vertices_deactivate() :void
      {
         m4_DEBUG2('vertices_deactivate: len:',
                   ((this.vertices !== null) ? this.vertices.length : 'null'));

         var v:Vertex;
         for each (v in this.vertices) {
            this.vertex_uninit(v);
         }

         this.vertices = null;
         this.selected_vertices = null;
      }

      // Delete vertices at indices from i to j-1 inclusive; e.g., if i = 3
      // and j = 6, then vertices 3, 4, and 5 will be deleted.
      public function vertices_delete_at(i:int, j:int) :void
      {
         var k:int;

         // work downwards so bubbling works
         for (k = j-1; k >= i; k--) {
            this.vertex_delete_at(k);
         }
      }

      //
      public function vertices_redraw() :void
      {
         var v:Vertex;

         for each (v in this.vertices) {
            v.draw();
         }
      }

      //
      public function vertices_select_all() :void
      {
         //m4_DEBUG2('vertices_select_all: vertex setting selected true:',
         //          this.vertices);

         var v:Vertex;
         for each (v in this.vertices) {
            v.set_selected(true);
         }
      }

      // Does nothing if this geofeature is not selected
      public function vertices_select_none() :void
      {
         //m4_DEBUG2('vertices_select_none: vertex setting selected false:',
         //          this.selected_vertices);

         var v:Vertex;
         if (this.selected_vertices !== null) {
            for each (v in this.selected_vertices) {
               v.set_selected(false);
            }
            m4_ASSERT(this.selected_vertices.length == 0);
         }
      }

      // *** Mouse and Double click detector handlers

      //
      public function on_mouse_down(ev:MouseEvent) :void
      {
         // No-op; the child classes override.
      }

      // This fcn. is called by the Tool_Vertex_Add tool.
      public function on_mouse_up_vertex_add(ev:MouseEvent) :Boolean
      {
         var i:int;
         var x:Number;
         var y:Number;
         var processed:Boolean = false;
         m4_DEBUG3('on_mouse_up_vertex_add: this:', this,
                   '/ target:', ev.target,
                   '/ tool_cur:', G.map.tool_cur);
         m4_ASSERT(G.map.tool_is_active(Tool_Vertex_Add));
         if ((this.selected)
             && (this.vertex_add_enabled)) {
            x = G.map.xform_x_cv2map(ev.localX);
            y = G.map.xform_y_cv2map(ev.localY);
            i = this.vertex_place_new(x, y);
            if (i >= 0) {
               var cmd:Vertex_Add = new Vertex_Add(this, i, x, y);
               m4_DEBUG('on_mouse_up_vertex_add: new Vertex_Add:', cmd);
               G.map.cm.do_(cmd, this.on_vertex_add_done,
                                 this.on_vertex_add_fail);
               m4_DEBUG2('on_mouse_up_vertex_add: cmd.is_prepared:',
                         cmd.is_prepared, '/ cmd.vtx_index:', cmd.vtx_index);
               processed = true;

               // See comments in Byway_Vertex: basically, it might be nice to
               // not switch back to the pan-select tool ([lb] thinks that it's
               // more intuitive to have the user do it expressly), but other
               // tools (like the new-byway tool) switch back to pan-select
               // after being used. Also, the user cannot drag the new vertex
               // except with the pan-select tool.
               G.map.callLater(G.map.switch_to_pan);
            }
         }
         return processed;
      }

      //
      public function on_mouse_doubleclick(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         m4_DEBUG('on_mouse_doubleclick: this:', this, 'target:', ev.target);
         m4_VERBOSE('  ev:', ev);

         m4_ASSERT(processed == false); // We're called first for dblclk.

         // FIXME: This function probably belongs in Item_Manager, since we're
         //        dealing with a collection of Geofeatures.
         //    OR: it belongs in Tool_Pan_Select...

         var feat:Geofeature;
         if (G.map.selectedset.length > 0) {
            for each (feat in G.map.selectedset) {
               if (!G.item_mgr.vertices_selected) {
                  feat.vertices_select_all();
               }
               else {
                  feat.vertices_select_none();
               }
            }
            G.item_mgr.vertices_selected = !(G.item_mgr.vertices_selected);
            processed = true;
         }

         return processed;
      }

      // *** Mouse move/out/over/scroll handlers

      //
      public function on_mouse_out(ev:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_out: set_highlighted: this', this);
         this.set_highlighted(false, Conf.mouse_highlight);
      }

      //
      public function on_mouse_over(ev:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_over: set_highlighted:', this.softstr);
         this.set_highlighted(true, Conf.mouse_highlight);
      }

      // ***

      //
      protected function on_vertex_add_done(cmd:Command_Base) :void
      {
         // SOMETIMES: Tool_Byway_Split, Byway_Vertex_Move, Vertex_Move.
         m4_TALKY('on_vertex_add_done: this:', this);
         m4_TALKY('on_vertex_add_done: cmd:', cmd);
         //m4_DEBUG(Introspect.stack_trace());

         // FIXME: What happens if multiple Geofeatures are selected?

         // Not yet: this.vertices_select_none();

         var index:int = -1;
         var scmd:Byway_Split = (cmd as Byway_Split);
         var vcmd:Vertex_Add = (cmd as Vertex_Add);
         if (scmd !== null) {
            m4_TALKY('on_vertex_add_done: scmd:', scmd);
            index = scmd.spl_index;
m4_ASSERT(false);
         }
         else if (vcmd !== null) {
            m4_TALKY('on_vertex_add_done: vcmd:', vcmd);
            index = vcmd.vtx_index;
         }

         if (index != -1) {

            this.vertices_select_none();

            m4_TALKY('on_vertex_add_done: index:', index);
            m4_TALKY('on_vertex_add_done: vertices:', this.vertices);
            m4_TALKY2('on_vertex_add_done: vertices[index]:',
                      this.vertices[index]);

            m4_ASSERT((index >= 0) && (index < this.vertices.length));

            this.vertices[index].set_selected(true);

            m4_TALKY('on_vertex_add_done: G.map.tool_cur:', G.map.tool_cur);
            m4_TALKY2('on_vertex_add_done: G.map.tool_cur.dragged_object/1:',
                      G.map.tool_cur.dragged_object);

            G.map.tool_cur.dragged_object = this.vertices[index];

            m4_TALKY2('on_vertex_add_done: G.map.tool_cur.dragged_object/2:',
                      G.map.tool_cur.dragged_object);

            this.vertices[index].drag_start();

            if (scmd !== null) {
               m4_ASSERT_SOFT(false); // Unexpected.
               //// This is hacky: It splits the byway...
               //this.vertices[index].on_mouse_up();
            }

            if (G.map.tool_cur is Tool_Byway_Split) {
               // HACK!
               this.vertices[index].on_mouse_up(null, false);
            }

         }
         else {
// SOMETIMES: Byway_Vertex_Move or Vertex_Move
//            m4_WARNING('on_vertex_add_done: unknown cmd?:', cmd);
         }
      }

      //
      protected function on_vertex_add_fail(cmd:Command_Base) :void
      {
         m4_WARNING('on_vertex_add_fail: this:', this);
      }

   }
}


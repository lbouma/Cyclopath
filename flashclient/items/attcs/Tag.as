/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.attcs {

   import flash.utils.Dictionary;
   import mx.collections.ArrayCollection;

   import grax.Aggregator_Base;
   import items.Attachment;
   import items.Geofeature;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.Record_Base;
   //import items.feats.Branch;
   import items.feats.Byway;
   import items.feats.Region;
   //import items.feats.Terrain;
   import items.feats.Waypoint;
   import items.utils.Item_Type;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.panel_items.Panel_Item_Attachment;

   public class Tag extends Attachment {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Tag');

      // *** Mandatory attributes

      public static const class_item_type:String = 'tag';
      public static const class_gwis_abbrev:String = 'tag';
      public static const class_item_type_id:int = Item_Type.TAG;

      // *** Other class attributes

      // Lookup tags by name
      public static var all_named:Dictionary;
      // Lookup avoid-tags by name
      public static var avoid_named:Dictionary;

      // A lookup cache for tags by the number of times they've been applied to
      // a byway. A dictionary by type, then minimum count, then max count.
      // - e.g. access is all_by_feat_counted[type][min][max] = ...
      protected static var all_by_feat_counted:Dictionary = new Dictionary();

      // *** Instance variables

      // Routefinder preferences
      public var pref_generic:int = 0;
      public var pref_user:int = -1;
      protected var pref_user_old:int;
      [Bindable] public var pref_enabled:Boolean;
      protected var pref_enabled_old:Boolean;
      public var sort_index:int; // preserves order in Tag_Preference_Viewer

      // Point filter preferences
      [Bindable] public var filter_show_tag:Boolean = true;

      // *** Constructor

      public function Tag(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         var blurb_length:int = 30; // FIXME Magic number
         super(xml, rev, blurb_length);
      }

      // *** Static class methods

      public static function all_applied(feat_class:Class) :Array
      {
         var tstart:int = G.now();
         var min_to_matter:int = 1;
         var max_to_matter:int = -1; // -1 means disabled, or no max.
         if (!(feat_class in Tag.all_by_feat_counted)) {
            var result:Array = new Array();
            for each (var tag:Tag in Tag.all_named) {
               var count:int = tag.feat_links_count[feat_class];
               if ((count >= min_to_matter)
                   && ((max_to_matter == -1)
                       || (count <= max_to_matter))) {
                  result.push(tag);
               }
            }
            result.sortOn('text_');
            Tag.all_by_feat_counted[feat_class] = result;
            m4_DEBUG2('all_applied: feat_class:', feat_class,
                      '/ result.length:', result.length);
         }
         var all_applied:Array = Tag.all_by_feat_counted[feat_class];
         m4_DEBUG_TIME('Tag.all_applied'); // Uses tstart.
         return all_applied;
      }

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var tag:Tag in Tag.all_named) {
               tag.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Tag.all_named = new Dictionary();
         Tag.avoid_named = new Dictionary();
         // Do, e.g., Tag.all_by_feat_counted = new Dictionary();
         Tag.clear_applied_cache();
      }

      //
      public static function clear_applied_cache() :void
      {
         Tag.all_by_feat_counted = new Dictionary();
      }

      //
      // Return all tag names in a sorted array.
      public static function get tags_ordered_array() :Array
      {
         m4_DEBUG('tags_ordered_array: DEPRECATED');
         m4_ASSERT(false); // Can probably deleted this fcn.
         var a:Array = new Array();
         for (var k:String in Tag.all_named) {
            var t:Tag = Tag.all_named[k];
            if (t.fresh || t.feat_links_exist[Geofeature]) {
               a.push(k);
            }
         }
         a.sort();
         m4_DEBUG('tags_ordered_array: returning no.:', a.length);
         return a;
      }

      // Return tag objects which exist in the current map view. This considers
      // only points and regions, not byways. This is for the filter which
      // filters only points and regions and not byways. (And note that there
      // is no similar filter for byways -- it doesn't make sense really to
      // hide a subset of the byways in the viewport).
      // BUG nnnn/Low priority?: Highlight byways in viewport according to
      // some criteria, e.g., those with bike lanes, or those whose speed
      // limit is something, or those with a 'proposed' tag, etc. I.e., like
      // the filter-tags widget for regions and points, but rather than hide
      // matching items (regions and points), you highlight matching items
      // (byways).
      public static function get visible_tags_ordered_array() :Array
      {
         var visible_tags:Array = new Array();
         var tstart:int = G.now(); // For m4_DEBUG_TIME.
         // As mentioned above, this fcn just applies to waypoints and regions.
         if (false) {
            // Deprecated: See the else block. [lb] is keeping this code for
            // now for posterity: look how tedious it is to work with
            // link_values!
            var tag_names:Array = Tag.tags_ordered_array;
            //m4_DEBUG2('visible_tags_orderd: tags_ordered_array.len:',
            //          Tag.tags_ordered_array.length);
            var lookup_waypoints:Dictionary = Link_Value.lookup_get(Waypoint);
            var lookup_regions:Dictionary = Link_Value.lookup_get(Region);
            for (var i:int = 0; i < tag_names.length; i++) {
               // Waypoints are always visible, so we can just check that it's
               // in the lookup. We only check against the region lookup if the
               // user has turned on region visibility.
               if ((Tag.all_named[tag_names[i]].base_id in lookup_waypoints)
                   || ((Tag.all_named[tag_names[i]].base_id in lookup_regions)
                       && G.tabs.settings.regions_visible)) {
                  visible_tags.push(Tag.all_named[tag_names[i]]);
               }
            }
         }
         else {
            // Much easier method. Use the added-a-year-after-link_values tags.
            var visible_taggeds:Set_UUID = new Set_UUID();
            // New method: use items' tagged attribute.
            //m4_DEBUG2('visible_tags_orderd: Waypoint.all.len:',
            //          Waypoint.all.length);
            for each (var wpt:Waypoint in Waypoint.all) {
               //m4_DEBUG('visible_tags_orderd: wpt.tags:', wpt.tags);
               visible_taggeds.extend(wpt.tags);
            }
            if (G.tabs.settings.regions_visible) {
               //m4_DEBUG2('visible_tags_orderd: Region.all.len:',
               //          Region.all.length);
               for each (var reg:Region in Region.all) {
                  //m4_DEBUG('visible_tags_orderd: reg.tags:', reg.tags);
                  visible_taggeds.extend(reg.tags);
               }
            }
            var vis_tag_names:Array = visible_taggeds.as_Array();
            vis_tag_names.sort();
            m4_DEBUG('visible_tags_orderd: vis_tag_names:', vis_tag_names);
            for each (var tag_name:String in vis_tag_names) {
               visible_tags.push(Tag.all_named[tag_name]);
            }
         }
         m4_DEBUG2('visible_tags_orderd: visible_tags.len:',
                   visible_tags.length);
         m4_DEBUG_TIME('visible_tags_ordered_array');
         return visible_tags;
      }

      // *** Instance methods

      //
      override public function is_attachment_panel_set() :Boolean
      {
         // Not applicable, but called from Attachment set selected.
         //    m4_ASSERT(false);
         return false;
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Tag = (to_other as Tag);
         super.clone_once(other);
         //other.pref_generic = this.pref_generic;
         //other.pref_user = this.pref_user;
         //other.pref_user_old = this.pref_user_old;
         //other.pref_enabled = this.pref_enabled;
         //other.pref_enabled_old = this.pref_enabled_old;
         //other.sort_index = this.sort_index;
         //other.filter_show_tag = this.filter_show_tag;
         other.pref_generic = this.pref_generic;
         other.pref_user = this.pref_user;
         // if (this.pref_enabled) {
         //    other.pref_enabled = this.pref_enabled;
         // }
         // else {
         //    this.pref_enabled = (this.preference > 0);
         // }
         other.pref_enabled = this.pref_enabled;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Tag = (to_other as Tag);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            if (gml.@pref_generic.length() != 0) {
               this.pref_generic = int(gml.@pref_generic);
            }
            if (gml.@pref_user.length() != 0) {
               this.pref_user = int(gml.@pref_user);
            }
            if (gml.@pref_enabled.length() != 0) {
               this.pref_enabled = Boolean(int(gml.@pref_enabled));
            }
            else {
               this.pref_enabled = (this.preference > 0);
            }
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         gml.setName(Tag.class_item_type); // 'tag'
         gml.@name = this.text_;
         return gml;
      }

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         m4_ASSERT(i == -1);
         super.item_cleanup(i, skip_delete);
         if (!skip_delete) {
            delete Tag.all_named[this.text_];
            if (this.text_ in Tag.avoid_named) {
               delete Tag.avoid_named[this.text_];
            }
            // Since we're deleting a tag we might as well invalidate the lists
            // of tags-per-geofeature-type.
            Tag.clear_applied_cache();
         }
      }

      // *** Item Init/Update fcns.

      //
      override public function set deleted(d:Boolean) :void
      {
         // The Geofeatures_Attachment_Add command deletes new tags
         // on undo (so we don't send them to the server).
         super.deleted = d;
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(item_agg, soft_add);
         if (this !== Tag.all_named[this.text_]) {
            if (this.text_ in Tag.all_named) {
               m4_WARNING2('init_add: overwrite:',
                           Tag.all_named[this.text_]);
               m4_WARNING('               with:', this);
               m4_WARNING(Introspect.stack_trace());
            }
            Tag.all_named[this.text_] = this;
         }

         // Clear the list of applied tags for each item type, since we're
         // adding a new tag.
         Tag.clear_applied_cache();

         // NOTE: To see the generic rater's preferences, try
         /*
            SELECT * FROM _tg
            JOIN tag_preference AS tp
             ON ((tp.tag_stack_id = _tg.stk_id)
                 AND (tp.branch_id = _tg.brn_id))
            WHERE tp.username = '_r_generic';
         */
         // 2013.05.23: There are two such tags the generic rater 'avoid's:
         //              'prohibited' and 'closed'.
         //             SELECT * FROM tag JOIN item_versioned USING (system_id)
         //              WHERE stack_id IN (1408951,1451838);
         var use_generic_rater:Boolean = true;
         if (this.pref_get('avoid', use_generic_rater) == true) {
            // This is used by Byway to decide if it should draw a red line
            // through unbikeable streets. This should maybe be implemented in
            // a new way, so we can use Attributes, too, and so user can set:
            // currently, pref_get uses the generic user's tag_preference
            // config, which says the tags 'prohibited' or 'closed' match
            // 'avoid'; the user cannot override this.
            // m4_DEBUG('init_add: adding to avoid_named:', this.text_);
            Tag.avoid_named[this.text_] = this;
            // Redraw all byways with this tag to ensure red line is drawn.
            // NOTE: When the map is first loaded, tags are added before links,
            //       so this code should only run when the user adds a new tag
            //       of on working copy update.
            /* 2014.04.26: Can we replace items_for_attachment with gf.tags? /*
            for each (o in Link_Value.items_for_attachment(this, Byway)) {
               (o as Byway).draw();
            } */
            for each (var bway:Byway in Byway.all) {
               if (bway.tags.contains(this.text_)) {
                  bway.draw();
               }
            }
         }
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_ASSERT(existing === null);
         var tag:Tag = Tag.all_named[this.text_];
         if (tag !== null) {
            m4_VERBOSE('tag updated:', this);
            // clone will call clone_update and not clone_once because of tag.
            this.clone_item(tag);

            // Clear the list of applied tags for each item type... this might
            // not be necessary/efficient but it's thorough.
            Tag.clear_applied_cache();
         }
         // else, invalid or deleted but not in the lookup, so ignore
         else {
            m4_WARNING('init_update: called for new tag??:', this.toString());
            // EXPLAIN: Is it really okay to ignore this case?
            m4_ASSERT_SOFT(false);
         }
         return tag;
      }

      //
      override public function link_value_set(link_value:Link_Value,
                                              is_set:Boolean) :void
      {
         if (is_set) {
            m4_DEBUG('link_value_set: tags.add:', this.name_);
            link_value.feat.tags.add(this.name_);
         }
         else {
            m4_DEBUG('link_value_set: tags.remove:', this.name_);
            link_value.feat.tags.remove(this.name_);
         }
      }

      // *** Item Init/Update fcns.

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         // We don't have an 'all' lookup:
         //  No: this.update_item_all_lookup(Tag, commit_info);
         // Our arrays, Tag.all_named and avoid_named, are keyed by tag name.
         m4_ASSERT(Tag.all_named[this.text_] === this);
         if (this.text_ in Tag.avoid_named) {
            m4_ASSERT(Tag.avoid_named[this.text_] === this);
         }

         super.update_item_committed(commit_info);
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         // NOTE If the item's loaded, it's in Attachment.all, so the check on
         //      Tag.all_named is unnecessary.
         return (super.is_item_loaded(item_agg)
                 || this.text_ in Tag.all_named);
      }

      // *** Getters and setters

      //
      override public function get discardable() :Boolean
      {
         // All tags are always resident.
         // EXPLAIN: Don't we end up reloading tags when user logs on/off?
         //          Which is why this fcn. is called.
         //          And what about branch??
         //          FIXME: [lb] wonders if maybe we should discard tags...
         return false;
      }

      // True since Tags are meaningless unless attached to a Geofeature.
      override public function get is_link_parasite() :Boolean
      {
         return true;
      }

      // *** Base class getters and setters

      //
      override public function get attachment_panel() :Panel_Item_Attachment
      {
         // Not applicable, but called from Attachment set selected.
         //    m4_ASSERT(false); // Not applicable.
         return null;
      }

      //
      override public function set attachment_panel(
         attachment_panel:Panel_Item_Attachment)
            :void
      {
         m4_ASSERT(false); // Not called.
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Attachment.all;
      }

      // *** Preference-related methods

      //
      public function pref_get(key:String, generic:Boolean=false) :Boolean
      {
         var tpt_id:int = generic ? this.pref_generic : this.preference;
         return Conf.rf_tag_pref_codes[tpt_id] == key;
      }

      //
      public function pref_set(key:String) :void
      {
         var i:int = Conf.rf_tag_pref_codes.indexOf(key);
         m4_ASSERT((i > 0) && (i <= 3));
         this.pref_user = i;
         this.pref_enabled = true;

         G.sl.event('ui/tag/pref_set', {tag: this.text_, pref: key});
      }

      //
      public function pref_user_backup() :void
      {
         this.pref_user_old = this.pref_user;
         this.pref_enabled_old = this.pref_enabled;
      }

      //
      public function pref_user_default() :void
      {
         this.pref_user_restore();
         // If pref_generic is 0, don't need to set pref_user unless it is
         // already defined.
         if ((this.pref_generic > 0) || (this.pref_user > -1)) {
            this.pref_user = this.pref_generic;
         }
         this.pref_enabled = (this.preference > 0);
      }

      //
      public function pref_user_restore() :void
      {
         this.pref_user = this.pref_user_old;
         this.pref_enabled = this.pref_enabled_old;
      }

      // Routefinder preference (see Conf.rf_tag_pref_codes)
      public function get preference() :int
      {
         if (this.pref_user > -1) {
            return this.pref_user;
         }
         else {
            return this.pref_generic;
         }
      }

      //
      [Bindable] public function get pref_border_color() :uint
      {
         // EXPLAIN: Magic numbers
         if (!this.pref_valid) {
            // Return red
            return 0xff0000;
         }
         else {
            // Return a light grey with a hint of blue
            return 0xAAB3B3;
         }
      }

      // NOTE: This setter is necessary in order to use bindings with this
      //       function. If the setter doesn't exist, the compiler complains
      //       about binding to a read-only value; also, you can't mark both
      //       the getter and settable bindable, but rather just the getter.
      public function set pref_border_color(color:uint) :void
      {
         // No-op; for [Bindable]
      }

      // Whether the user preference has been changed or enabled/disabled
      public function get pref_user_dirty() :Boolean
      {
         return (((this.pref_user > -1)
                  && (this.pref_user != this.pref_user_old))
                 || (this.pref_enabled != this.pref_enabled_old));
      }

      // The tag is invalid if it is enabled in the routefinder but no
      // preference is set.
      public function get pref_valid() :Boolean
      {
         return (!((this.pref_enabled) && (this.preference == 0)));
      }

      // *** Developer methods

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' | bys: ' + this.feat_links_count[Byway]
                 + ' | gfs?: ' + this.feat_links_exist[Geofeature]
                 );
      }

   }
}


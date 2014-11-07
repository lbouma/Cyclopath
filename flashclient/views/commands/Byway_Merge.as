/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.utils.Dictionary;
   import mx.utils.UIDUtil;

   import grax.Dirty_Reason;
   import items.Attachment;
   import items.Link_Value;
   import items.attcs.Annotation;
   import items.attcs.Tag;
   import items.feats.Byway;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Byway_Merge extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Bway_M');

      // *** Instance variables

      protected var new_byway:Byway = null;
      protected var new_lvals:Array;
      protected var added_lvals:Boolean = false;

      // The order in which the byways were selected by the user, to determine
      // link_value assignmentship.
      protected var feats_ordered:Array;

      // *** Constructor

      // NOTE: merge_byways is strictly ordered; see Byway.mergeable_array.
      public function Byway_Merge(merge_byways:Array, feats_ordered:Array)
         :void
      {
         m4_TALKY('Byway_Merge: merge_byways:', merge_byways);
         m4_TALKY('Byway_Merge: feats_ordered:', feats_ordered);

         super(merge_byways, Dirty_Reason.item_data);

         this.feats_ordered = feats_ordered;
         m4_TALKY('Byway_Merge: merge_byways.length:', merge_byways.length);
         m4_TALKY('Byway_Merge: feats_ordered.length:', feats_ordered.length);
         m4_ASSERT(merge_byways.length == feats_ordered.length);

         var hydrated:Boolean = true;
         for each (var byway:Byway in merge_byways) {
            if (!byway.hydrated) {
               m4_ERROR('Unexpected: !byway.hydrated:', byway);
               hydrated = false;
               break;
            }
         }

         if (hydrated) {
            this.setup_merge_byway();
         }
      }

      // ***

      // Command_Base calls this fcn. after merge byways are lazy-loaded.
      // NOTE: You have to select byways to merge them, and selecting byways
      //       hydrates them, so we will always have setup in tha constructor.
      override protected function prepare_items_step_2() :void
      {
         if (this.new_byway === null) {
            m4_ASSERT(this.new_lvals === null);
            this.setup_merge_byway();
         }

         m4_ASSERT((this.new_byway !== null)
                   && (this.new_lvals !== null));

         // Call the parent last, after getting setup.
         super.prepare_items_step_2();
      }

      //
      protected function setup_merge_byway() :void
      {
         // CcpV1: The first byway in edit_items (so edit_items[0]) is the
         // target for merging. This means that all of the geometry and
         // Link_Values attached to edit_items[1..n] will be merged into
         // edit_items[0].
         // CcpV2: We create a new byway so that undo/redo is cleaner.
         // Also, we use this.feats_ordered[0] and the first byway, and
         // then walk feats_ordered and only copy link_values that are
         // not already set (so we merge all byways' link_values in the
         // order the byways were selected).

         m4_TALKY('setup_merge_byway: first_parent:', this.first_parent);
         m4_ASSERT(this.first_parent.hydrated);

         this.new_byway = (this.first_parent.clone_item() as Byway);
         this.new_lvals = new Array();

         // Assign an ID now, but wait to bless_new until do_.
         G.item_mgr.assign_id(this.new_byway);
         m4_TALKY('setup_merge_byway: new_byway:', this.new_byway);

         // Mark the new item dirty.
         this.new_byway.dirty_set(Dirty_Reason.item_data, true);

         this.new_byway.dirty_set(
            Dirty_Reason.item_rating,
            (this.first_parent.dirty_get(Dirty_Reason.item_rating)
             || (this.first_parent.user_rating >= 0)));

         var lv_new:Link_Value;
         var firstp_lvals:Set_UUID;
         firstp_lvals = Link_Value.item_get_link_values(this.first_parent);
         m4_TALKY(' .. firstp_lvals.len:', firstp_lvals.length);
         var lv_old:Link_Value;
         for each (lv_old in firstp_lvals) {
            lv_new = lv_old.clone_for_geofeature(this.new_byway);
            lv_new.dirty_set(Dirty_Reason.item_data, true);
            // Assign an ID now, but wait to bless_new until do_.
            G.item_mgr.assign_id(lv_new);
            // Remember the link for a later do_
            this.new_lvals.push(lv_new);
         }

         // MAYBE: Consume other link_values?
         for (var i:int = 1; i < this.feats_ordered.length; i++) {
            var next_byway:Byway = (this.feats_ordered[i] as Byway);
            m4_DEBUG(' ... next_byway:', next_byway);
            var segment_lvals:Set_UUID;
            segment_lvals = Link_Value.item_get_link_values(next_byway);
            m4_TALKY(' .. segment_lvals.len:', segment_lvals.length);
            var lv_seg:Link_Value;
            for each (lv_seg in segment_lvals) {
               var attc_type:Object = null;
               //var lhs_items:Array = Link_Value.attachments_for_item(
               //                        this, attc_type);
               var cur_lvals:Set_UUID;
               cur_lvals = Link_Value.item_get_link_values(this.new_byway);
               // MAYBE: This seems inefficient...
               var already_set:Boolean = false;
               for each (var lval:Link_Value in cur_lvals) {
                  if (lval.attc.stack_id == lv_seg.attc.stack_id) {
                     m4_DEBUG2('setup_merge_byway: already_set: lval.attc:',
                               lval.attc);
                     already_set = true;
                     break;
                  }
               }
               if (!already_set) {
                  m4_DEBUG2('setup_merge_byway: not already_set: lv_seg:',
                            lv_seg);
                  lv_new = lv_seg.clone_for_geofeature(this.new_byway);
                  lv_new.dirty_set(Dirty_Reason.item_data, true);
                  // Assign an ID now, but wait to bless_new until do_.
                  G.item_mgr.assign_id(lv_new);
                  // Remember the link for a later do_
                  this.new_lvals.push(lv_new);
               }
            }
         }

         // Fill is missing geometry, and consume link_values.
         this.new_byway.join_byways(this.edit_items);
      }

      // *** Getters/setters

      //
      override public function get descriptor() :String
      {
         return 'merge byways';
      }

      /*
      //
      public function get final_parent() :Byway
      {
         //return (this.edit_items[this.edit_items.length-1] as Byway);
         return (this.feats_ordered[this.feats_ordered.length-1] as Byway);
      }
      */

      //
      public function get first_parent() :Byway
      {
         //return (this.edit_items[0] as Byway);
         return (this.feats_ordered[0] as Byway);
      }

      // *** Instance methods

      //
      override public function prepare_command(callback_done:Function,
                                               callback_fail:Function,
                                               ...extra_items_arrays)
         :Boolean
      {
         m4_DEBUG('prepare_command: extra_items_arrays:', extra_items_arrays);
         m4_ASSERT(extra_items_arrays.length == 0);
         // Parent just checks this.edit_items, but we also want it to verify
         // the user can make the new link_values associated with the merge.
         return super.prepare_command(callback_done, callback_fail,
                                      [this.new_byway,], this.new_lvals);
      }

      // *** Do and Undo

      //
      override public function activate_panel_do_() :void
      {
         m4_TALKY('activate_panel_do_');
         m4_ASSERT(!this.skip_panel);
         this.panel_reset_maybe(this.edit_items);
         G.panel_mgr.effectively_active_panel = null;
      }

      //
      override public function activate_panel_undo() :void
      {
         m4_TALKY('activate_panel_undo');
         m4_ASSERT(!this.skip_panel);
         this.panel_reset_maybe(this.new_byway);
         G.panel_mgr.effectively_active_panel = null;
      }

      //
      override public function do_() :void
      {
         super.do_();

         m4_TALKY('undo: this.edit_items:', this.edit_items);
         m4_TALKY('undo: edit_items.length:', this.edit_items.length);

         // The edit_items array contains the byways that were merged.
         for each (var merged_byway:Byway in this.edit_items) {
            merged_byway.set_selected(false, /*nix=*/true);
            m4_ASSERT(!merged_byway.deleted);
            merged_byway.deleted = true;
            G.map.item_discard(merged_byway);
         }

         this.new_byway.deleted = false;
         G.map.item_discard(this.new_byway);

         G.map.items_add([this.new_byway,]);
         if (!this.added_lvals) {
            if (this.new_lvals.length > 0) {
               G.map.items_add(this.new_lvals.slice());
            }
            // else, no new_lvals, and items_add complains on empty array.
            this.added_lvals = true;
         }

         this.new_byway.set_selected(true);
         this.new_byway.draw_all();

         // Skipping: G.map.intersection_detector.nodes_rebuild();

         //?: G.panel_mgr.item_panels_mark_dirty(this.edit_items);
      }

      //
      override public function undo() :void
      {
         super.undo();

         m4_TALKY('undo: this.new_byway:', this.new_byway);
         m4_TALKY('undo: this.edit_items:', this.edit_items);
         m4_TALKY('undo: edit_items.length:', this.edit_items.length);

         this.new_byway.deleted = true;
         G.map.item_discard(this.new_byway);

         // for each (var new_lval:Link_Value in this.new_lvals) {
         //    G.map.item_discard(new_lval);
         // }

         var merged_byway:Byway;
         for each (merged_byway in this.edit_items) {
            m4_TALKY('undo: merged_byway:', merged_byway);
            m4_ASSERT(merged_byway.deleted);
            merged_byway.deleted = false;
         }

         // Make a copy of the Array since items_add mutates it.
         G.map.items_add(this.edit_items.slice());

         for each (merged_byway in this.edit_items) {
            merged_byway.set_selected(true);
            merged_byway.draw_all();
         }

         // Skipping: G.map.intersection_detector.nodes_rebuild();

         //?: G.panel_mgr.item_panels_mark_dirty(this.edit_items);
      }

   }
}


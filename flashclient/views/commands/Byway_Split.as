/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: This file, Byway_Split, and the file, Byway_Merge, need cleaning.

package views.commands {

   import flash.events.Event;

   import grax.Dirty_Reason;
   import items.Geofeature;
   import items.Item_User_Access;
   import items.Link_Value;
   import items.feats.Byway;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.map_widgets.Bubble_Node;
   import views.panel_items.Panel_Item_Byway;
   import views.panel_items.Panel_Item_Geofeature;

   public class Byway_Split extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Bway_Sp');

      // *** Instance variables

      public var spl_index:int;  // index of split vertex before split

      // In CcpV1, a split byway is comprised of the old byway and a new byway,
      // where the old byway has the split-from byway's stack ID but not all of
      // its vertices. In CcpV2, we dispose of the split-from byway and make
      // two new byway segments. This makes undo/redo/revert easier, and
      // conceptually it makes more sense, since a byway split in twain is
      // really two new byways.
      //
      // The lhs byway has the lower-numbered vertices of the split-from byway,
      // and the rhs byway has the higher-numbered vertices.
      public var byway_lhs:Byway = null;
      public var byway_rhs:Byway = null;

      // We also make two sets of copies of the parent's link_values.
      protected var lvals_lhs:Array;
      protected var lvals_rhs:Array;
      // protected var added_lvals:Boolean = false;

      // *** Constructor

      public function Byway_Split(parent:Geofeature,
                                  spl_index:int,
                                  skip_panel:Boolean) :void
      {
         m4_TALKY('Byway_Split: spl_index:', spl_index, '/ parent:', parent);

         super([parent,], Dirty_Reason.item_data);

         // EXPLAIN: What cmd. merges with Byway_Split? Just Vertex_Add?
         //          Always Vertex_Add?
         this.mergeable = true;

         this.spl_index = spl_index;

         this.skip_panel = skip_panel;

         if (parent.hydrated) {
            this.setup_split_byways();
         }
         else {
            m4_TALKY('Byway_Split: !prnt.hydrated: skppg: setup_split_byways');
         }
      }

      // ***

      // Command_Base calls this fcn. after parent byway is lazy-loaded.
      override protected function prepare_items_step_2() :void
      {
         // NOTE: We call super's fcn. _after_ setting ourself up.
         if (this.byway_lhs === null) {
            m4_ASSERT(   (this.byway_rhs === null)
                      && (this.lvals_lhs === null)
                      && (this.lvals_rhs === null));
            this.setup_split_byways();
         }

         m4_ASSERT(   (this.byway_lhs !== null)
                   && (this.byway_rhs !== null)
                   && (this.lvals_lhs !== null)
                   && (this.lvals_rhs !== null));

         this.check_perms_other.add(this.byway_lhs);
         this.check_perms_other.add(this.byway_rhs);
         var item:Item_User_Access;
         for each (item in this.lvals_lhs) {
            this.check_perms_lvals.add(item);
         }
         for each (item in this.lvals_rhs) {
            this.check_perms_lvals.add(item);
         }

         // Call the parent last, after getting setup.
         super.prepare_items_step_2();
      }

      //
      protected function setup_split_byways() :void
      {
         m4_TALKY('setup_split_byways: this.parent:', this.parent);
         //m4_TALKY('setup_split_byways: parent.xs:', this.parent.xs);
         //m4_TALKY('setup_split_byways: parent.ys:', this.parent.ys);
         m4_ASSERT(this.parent.hydrated);

         this.lvals_lhs = new Array();
         this.lvals_rhs = new Array();

         this.byway_lhs = this.setup_split_byways_one(this.lvals_lhs);
         this.byway_rhs = this.setup_split_byways_one(this.lvals_rhs);

         // Remove the tail of the 'lhs' split-into and the head of the 'rhs'.
         var num_vertices:int = this.parent.xs.length;
         m4_TALKY2('setup_split_byways: num_vertices:', num_vertices,
                   '/ this.spl_index:', this.spl_index);
         m4_TALKY('setup_split_byways/1: this.byway_lhs:', this.byway_lhs);
         m4_TALKY(' .. x_start:', this.byway_lhs.x_start);
         m4_TALKY(' .. y_start:', this.byway_lhs.y_start);
         m4_TALKY(' .. x_end:', this.byway_lhs.x_end);
         m4_TALKY(' .. y_end:', this.byway_lhs.y_end);
         m4_TALKY('setup_split_byways/1: this.byway_rhs:', this.byway_rhs);
         m4_TALKY(' .. x_start:', this.byway_rhs.x_start);
         m4_TALKY(' .. y_start:', this.byway_rhs.y_start);
         m4_TALKY(' .. x_end:', this.byway_rhs.x_end);
         m4_TALKY(' .. y_end:', this.byway_rhs.y_end);
         this.byway_lhs.vertices_delete_at(this.spl_index+1, num_vertices);
         this.byway_rhs.vertices_delete_at(0, this.spl_index);

         // See if there's a nearby intersection to snap-to.
         m4_TALKY('setup_split_byways/2: this.byway_lhs:', this.byway_lhs);
         m4_TALKY(' .. x_start:', this.byway_lhs.x_start);
         m4_TALKY(' .. y_start:', this.byway_lhs.y_start);
         m4_TALKY(' .. x_end:', this.byway_lhs.x_end);
         m4_TALKY(' .. y_end:', this.byway_lhs.y_end);
         m4_TALKY('setup_split_byways/2: this.byway_rhs:', this.byway_rhs);
         m4_TALKY(' .. x_start:', this.byway_rhs.x_start);
         m4_TALKY(' .. y_start:', this.byway_rhs.y_start);
         m4_TALKY(' .. x_end:', this.byway_rhs.x_end);
         m4_TALKY(' .. y_end:', this.byway_rhs.y_end);
         m4_ASSERT(this.byway_lhs.x_end == this.byway_rhs.x_start);
         m4_ASSERT(this.byway_lhs.y_end == this.byway_rhs.y_start);
         var bn:Bubble_Node =
            G.map.node_snapper.nearest(
               this.byway_rhs.x_start,
               this.byway_rhs.y_start,
               Conf.byway_equal_thresh);

         if (bn !== null) {
            // We found an existing node to use.
            this.byway_lhs.fin_node_id = bn.stack_id;
            this.byway_rhs.beg_node_id = bn.stack_id;
         }
         else {
            // There's not an existing node, so claim one.
            var new_node_client_id:int;
            new_node_client_id = G.item_mgr.assign_id_new();
            this.byway_lhs.fin_node_id = new_node_client_id;
            this.byway_rhs.beg_node_id = new_node_client_id;
         }
      }

      //
      protected function setup_split_byways_one(new_lvals:Array)
         :Byway
      {
         m4_TALKY('setup_split_byways_one: this.parent:', this.parent);

         var byway_new:Byway = (this.parent.clone_item() as Byway);

         m4_TALKY('setup_split_byways_one: byway_new-1:', byway_new);
         //m4_TALKY('setup_split_byways: byway_new.xs:', byway_new.xs);
         //m4_TALKY('setup_split_byways: byway_new.ys:', byway_new.ys);

         // CONFIRM: If you split a split without saving, you have a chain of
         // split stack IDs? Can you use this chain to find conflicts between
         // branches or revisions?
         if ((this.parent.fresh) && (this.parent.split_from_stack_id != 0)) {
            // The parent is a new split-into itself, so use its split-from
            // parent, e.g., think splitting one byway into three...
            byway_new.split_from_stack_id = this.parent.split_from_stack_id;
         }
         else if (this.parent.stack_id > 0) {
            // I.e., !this.parent.fresh and this.parent.stack_id != 0.
            byway_new.split_from_stack_id = this.parent.stack_id;
         }
         // else, we're splitting a fresh, unsaved byway, and the server
         // doesn't like it when the split_from_stack_id is a client ID.

         // Assign an ID now, but wait to bless_new until do_.
         G.item_mgr.assign_id(byway_new);
         m4_TALKY('setup_split_byways: byway_new-2:', byway_new);

         // Mark the item as dirty as possible.
         byway_new.dirty_set(Dirty_Reason.item_data, true);
         // If the user rated the parent and then split the byway, remember
         // that. Or if the parent has a user rating, use that.
         byway_new.dirty_set(
            Dirty_Reason.item_rating,
            (this.parent.dirty_get(Dirty_Reason.item_rating)
             || (this.parent.user_rating >= 0)));
         // FIXME: Should clone() do this instead?
         //        And are we missing any other dirty reasons?

         // Make new Link_Values for the new Byway; associated all the notes,
         // tags and attributes from the original Byway.
         //
         // CONFIRM: Does commit.py copy all link_values anyway?

         m4_TALKY('_spl_byways_one: parent.attrs:', this.parent.attrs);
         m4_TALKY('_spl_byways_one: parent.tags:', this.parent.tags);
         var unsplit_link_values:Set_UUID;
         unsplit_link_values = Link_Value.item_get_link_values(this.parent);

         m4_TALKY2('_spl_byways_one: unsplit_link_values.len:',
                   unsplit_link_values.length);
         var lv_old:Link_Value;
         for each (lv_old in unsplit_link_values) {
            var lv_new:Link_Value;
            lv_new = lv_old.clone_for_geofeature(byway_new);
            lv_new.dirty_set(Dirty_Reason.item_data, true);
            // Assign an ID now, but wait to bless_new until do_.
            G.item_mgr.assign_id(lv_new);
            m4_TALKY('_spl_byways_one: lv_new:', lv_new);
            // Remember the link for a later do_
            new_lvals.push(lv_new);
         }

         return byway_new;
      }

      // *** Getters/setters

      //
      public function get parent() :Byway
      {
         return (this.edit_items[0] as Byway);
      }

      //
      public function get split_node_id() :int
      {
         // The node stack ID is a new client stack ID if a new node was
         // created, or it's the node stack ID of an existing intersection.
         m4_ASSERT(this.byway_lhs.fin_node_id == this.byway_rhs.beg_node_id);
         return this.byway_rhs.beg_node_id;
      }

      // *** Instance methods

      //
      override public function activate_panel_do_() :void
      {
         m4_TALKY('activate_panel_do_');
         m4_ASSERT(!this.skip_panel);
         this.panel_reset_maybe(this.parent);
         G.panel_mgr.effectively_active_panel = null;
      }

      //
      override public function activate_panel_undo() :void
      {
         m4_TALKY('activate_panel_undo');
         m4_ASSERT(!this.skip_panel);
         this.panel_reset_maybe(this.byway_lhs, this.byway_rhs);
         G.panel_mgr.effectively_active_panel = null;
      }

      //
      override public function prepare_command(callback_done:Function,
                                               callback_fail:Function,
                                               ...extra_items_arrays)
         :Boolean
      {
         m4_TALKY('prepare_command: extra_items_arrays:', extra_items_arrays);
         m4_TALKY('prepare_command: this.byway_lhs:', this.byway_lhs);
         m4_TALKY('prepare_command: this.byway_rhs:', this.byway_rhs);
         m4_ASSERT(extra_items_arrays.length == 0);
         // Parent just checks this.edit_items, but we also want it to verify
         // the user can make the new link_values associated with the merge.
         return super.prepare_command(
            callback_done,
            callback_fail
            );
      }

      // *** Do and Undo

      //
      override public function do_() :void
      {
         m4_TALKY('do_: parent:', this.parent);
         m4_ASSERT(this.parent.hydrated);

         var first_do:Boolean = (this.undone === null);

         super.do_();

         // Remove the split-from byway.
         this.parent.set_selected(false);
         // Mark deleted.
         this.parent.deleted = true;
         // NOTE: This calls node_cleanup on parent.beg_/fin_node_id.
         G.map.item_discard(this.parent);

         this.byway_lhs.deleted = false;
         this.byway_rhs.deleted = false;
         // When we called super.prepare_command, it called items_add, but if
         // the user undoed, undo called item_discard.
         if (!first_do) {
            G.map.items_add([this.byway_lhs, this.byway_rhs,]);
         }
         // We only add link_values the first time (there's no need to discard
         // link_values from the map; discarding geofeatures is sufficient).
         //  if (!this.added_lvals) {
         //     m4_TALKY('do_: adding no. lvals_lhs:', this.lvals_lhs.length);
         //     if (this.lvals_lhs.length > 0) {
         //        G.map.items_add(this.lvals_lhs.slice());
         //     }
         //     m4_TALKY('do_: adding no. lvals_rhs:', this.lvals_rhs.length);
         //     if (this.lvals_rhs.length > 0) {
         //        G.map.items_add(this.lvals_rhs.slice());
         //     }
         //     this.added_lvals = true;
         //  }

         this.byway_lhs.set_selected(true);
         m4_TALKY('do_: this.byway_lhs:', this.byway_lhs);
         this.byway_rhs.set_selected(true);
         m4_TALKY('do_: this.byway_rhs:', this.byway_rhs);

         // Not needed: parent.draw_all();
         this.byway_lhs.draw_all();
         this.byway_rhs.draw_all();

         if (!this.skip_panel) {
            G.map.intersection_detector.nodes_rebuild();
         }
      }

      //
      override public function undo() :void
      {
         super.undo();

         //m4_TALKY('undo: parent:', this.parent);

         var split_byway:Byway;
         var discard_splits:Array = [this.byway_lhs, this.byway_rhs,];
         for each (split_byway in discard_splits) {
            m4_TALKY('undo: deleting split_byway:', split_byway);
            split_byway.deleted = true;
            G.map.item_discard(split_byway);
         }

         m4_ASSERT(this.parent.deleted);
         this.parent.deleted = false;
         G.map.items_add([this.parent,]);

         m4_TALKY('undo: selecting parent:', this.parent);
         this.parent.set_selected(true);
         this.parent.draw_all();

         if (!this.skip_panel) {
            G.map.intersection_detector.nodes_rebuild();
         }
      }

   }
}


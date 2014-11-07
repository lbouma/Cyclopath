/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.geom.Point;
   import flash.utils.Dictionary;
   import mx.controls.Alert;

   import grax.Dirty_Reason;
   import items.feats.Byway;
   import utils.geom.Geometry;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.panel_items.Panel_Item_Byway;

   public class Node_Endpoint_Build extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Nod_Bld');

      public static const SPLIT_BOTH_AT_X_INTERSECTION:int = 1;
      public static const SPLIT_SECOND_EXTEND_FIRST:int = 2;
      public static const SPLIT_FIRST_EXTEND_SECOND:int = 3;

      // *** Instance variables

      // The length upto which a byway is considered a 'short' byway (meters)
      // If the result of a byway split in the creation of an X intersection is
      // a byway of a length shorter than this length, it is deleted.
      protected var byway_short_length:int = Conf.nb_byway_short_length;

      protected var byway1:Byway;
      protected var byway2:Byway;
      protected var byway_delete_commands:Array;

      protected var intersection_pt:Point;
      protected var extend:int;

      // This command creates and uses a sequence of sub-commands.
      protected var cmd_stack:Array = null;
      protected var new_items:Array = null;
      protected var old_items:Array = null;

      protected var cmd_stack_reversed:Boolean = false;

      // *** Constructor

      public function Node_Endpoint_Build(
         byway1:Byway,
         byway2:Byway,
         x:Number,
         y:Number,
         extend:int) :void
      {
         super([byway1, byway2,], Dirty_Reason.item_data);

         this.byway1 = byway1;
         this.byway2 = byway2;
         this.intersection_pt = new Point(x, y);
         this.extend = extend;
      }

      // *** Instance methods

      override public function get descriptor() :String
      {
         return 'intersection builder a/k/a node_endpoint_build';
      }

      // ***

      // Command_Base calls this fcn. after parent byway is lazy-loaded.
      override protected function prepare_items_step_2() :void
      {
         // NOTE: We call super's fcn. _after_ setting ourself up.
         /* Don't call setup yet; we have to do_ the Vertex_Add command,
            so might as well wait for do_. It really doesn't matter so
            long as we only setup once.
         if (this.cmd_stack === null) {
            m4_ASSERT((this.new_items === null)
                      && (this.old_items === null));
            this.setup_split_byways();
         }

         m4_ASSERT((this.cmd_stack !== null)
                   && (this.new_items !== null)
                   && (this.old_items !== null));
         */

         // Call the parent last, after getting setup.
         super.prepare_items_step_2();
      }

      //
      protected function setup_split_byways() :void
      {
         m4_TALKY('setup_split_byways: this.byway1:', this.byway1);
         m4_TALKY('setup_split_byways: this.byway2:', this.byway2);

         // This fcn. is called once all items are hydrated.
         m4_ASSERT(this.byway1.hydrated);
         m4_ASSERT(this.byway2.hydrated);

         this.cmd_stack = new Array();
         this.new_items = new Array();
         this.old_items = new Array();

         switch (this.extend) {
            case Node_Endpoint_Build.SPLIT_BOTH_AT_X_INTERSECTION:
               // extend == 0: X: split both byways.
               this.byway_split(this.byway1);
               this.byway_split(this.byway2);
               break;
            case Node_Endpoint_Build.SPLIT_SECOND_EXTEND_FIRST:
               // extend == 1: T: split byway2, extend byway1.
               this.byway_split(this.byway2);
               this.byway_extend(this.byway1);
               break;
            case Node_Endpoint_Build.SPLIT_FIRST_EXTEND_SECOND:
               // extend == 2: T: split byway1, extend byway2.
               this.byway_split(this.byway1);
               this.byway_extend(this.byway2);
               break;
            default:
               m4_ASSERT(false);
         }

         this.short_byways_delete_maybe();
      }

      // ***

      // Creates a new vertex at the intersection point and splits the byway.
      protected function byway_split(byway_to_split:Byway) :void
      {
         var i:int;
         i = byway_to_split.vertex_place_new(this.intersection_pt.x,
                                             this.intersection_pt.y);

         if (i >= 0) {
            // Create a new vertex
            // NOTE: If we're here, user has editor access to byway, so this
            //       command is okay.
            var cmd_vertex_add:Vertex_Add;
            cmd_vertex_add =
               new Vertex_Add(byway_to_split,
                              i,
                              this.intersection_pt.x,
                              this.intersection_pt.y);
            // Since we're not calling G.map.cm.do_, we need to prepare the
            // command ourselves.
            cmd_vertex_add.prepare_command(null, null);
            // This fcn. is called once all items are hydrated.
            m4_ASSERT_SOFT(cmd_vertex_add.is_prepared !== null);

            if (cmd_vertex_add.is_prepared) {

               cmd_vertex_add.loose_selection_set = false;

               cmd_vertex_add.skip_panel = true;
               cmd_vertex_add.do_();
               this.cmd_stack.push(cmd_vertex_add);

               // Split the byway at the new vertex.
               //
               // NOTE: If we're here, we've already confirmed that the user
               //       can create new byways.
               //
               // But first, send a reference to the first cmd, so that each
               // command uses the same panel (so that all new byways are
               // selected when we're done).
               var skip_panel:Boolean = true;
               var cmd_byway_split:Byway_Split =
                  new Byway_Split(byway_to_split, i, skip_panel);

               // Since we're not calling G.map.cm.do_, not only do we call
               // prepare_command, but we also hack away on a setup fcn.,
               // so that cmd_byway_split.byway_new gets set.
               // Don't need?: cmd_byway_split.setup_split_byways();
               cmd_byway_split.prepare_command(null, null);

               m4_ASSERT_SOFT(cmd_byway_split.is_prepared !== null);
               if (cmd_byway_split.is_prepared) {
                  m4_TALKY2('byway_split: new_items.push: byway_lhs:',
                            cmd_byway_split.byway_lhs);
                  m4_TALKY2('byway_split: new_items.push: byway_rhs:',
                            cmd_byway_split.byway_rhs);
                  m4_TALKY2('byway_split: old_items.push: byway_to_split:',
                            byway_to_split);
                  this.new_items.push(cmd_byway_split.byway_lhs);
                  this.new_items.push(cmd_byway_split.byway_rhs);
                  this.old_items.push(byway_to_split);
                  // NOTE: Not calling G.map.cm.do_() with callbacks because
                  //       Tool_Node_Endpoint_Build already lazy-loaded the
                  //       byways being split. So we can call the command's
                  //       do_ directly.
                  cmd_byway_split.skip_panel = true;
                  cmd_byway_split.do_();
                  this.cmd_stack.push(cmd_byway_split);
               }
               else {
                  m4_WARNING2('byway_split: not prepared: cmd_byway_split:',
                              cmd_byway_split);
               }
            }
            else {
               m4_WARNING2('byway_split: not prepared: cmd_vertex_add:',
                           cmd_vertex_add);
            }
         }
      }

      // Extend byway to build a T intersection.
      protected function byway_extend(byway_to_ext:Byway) :void
      {
         var x:Number;
         var y:Number;
         var vert_i:int;
         var last:int = (byway_to_ext.xs.length - 1);
         var cmd_vertex_move:Vertex_Move;
         var till_here:Point = new Point();

         till_here.x = this.intersection_pt.x;
         till_here.y = this.intersection_pt.y;

         var dist_last:Number = Geometry.distance(byway_to_ext.xs[last],
                                                  byway_to_ext.ys[last],
                                                  till_here.x,
                                                  till_here.y);
         var dist_zero:Number = Geometry.distance(byway_to_ext.xs[0],
                                                  byway_to_ext.ys[0],
                                                  till_here.x,
                                                  till_here.y);
         if (dist_last < dist_zero) {
            x = byway_to_ext.xs[last];
            y = byway_to_ext.ys[last];
            vert_i = last;
         }
         else {
            x = byway_to_ext.xs[0];
            y = byway_to_ext.ys[0];
            vert_i = 0;
         }

         // Converting to canvas co-ords as that is what Vertex_Move expects.
         x = G.map.xform_x_map2cv(x);
         y = G.map.xform_y_map2cv(y);
         till_here.x = G.map.xform_x_map2cv(till_here.x);
         till_here.y = G.map.xform_y_map2cv(till_here.y);

         // We've already checked that the user has permissions to edit the
         // byway in question, so this call is okay without re-checking
         // permissions.
         m4_TALKY('byway_extend: new_items.push: byway_to_ext:', byway_to_ext);
         this.new_items.push(byway_to_ext);
         // Make sure we select this item for do and redo, since it's being
         // edited only, not created or deleted.
         m4_TALKY('byway_extend: old_items.push: byway_to_ext:', byway_to_ext);
         this.old_items.push(byway_to_ext);
         cmd_vertex_move = new Byway_Vertex_Move([byway_to_ext,],
                                                 [vert_i,],
                                                 (till_here.x - x),
                                                 (till_here.y - y));
         cmd_vertex_move.skip_panel = true;
         cmd_vertex_move.do_();
         this.cmd_stack.push(cmd_vertex_move);
      }

      // Counts the number of neighbors of the given byway at that node of the
      // byway which is != node_id.
      protected function other_neighbor_count(byway:Byway, node_id:int) :int
      {
         var count:int = 0;
         var other_nid:int = this.other_node_id(byway, node_id);
         var o:Object;

         if (other_nid in G.map.nodes_adjacent) {
            for each (o in G.map.nodes_adjacent[other_nid]) {
               count++;
            }
         }

         return count;
      }

      // Returns the id of that node of the given byway which is != node_id.
      protected function other_node_id(byway:Byway, node_id:int) :int
      {
         if (byway.beg_node_id == node_id) {
            return byway.fin_node_id;
         }
         else if (byway.fin_node_id == node_id) {
            return byway.beg_node_id;
         }
         else {
            return 0;
         }
      }

      // Delete short byways, if possible.
      protected function short_byways_delete_maybe() :void
      {
         var byways:Array = new Array();
         var intersection_node_id:int;

         var cmd:Command_Base;
         for each (cmd in this.cmd_stack) {
            var cmd_byway_split:Byway_Split;
            cmd_byway_split = (cmd as Byway_Split);
            if (cmd_byway_split !== null) {
               // 2013.08.01: [lb] finds it odd that we would want to bother
               //             with a byway we just deleted...
               //               byways.push(cmd_byway_split.parent);
               byways.push(cmd_byway_split.byway_lhs);
               byways.push(cmd_byway_split.byway_rhs);
               intersection_node_id = cmd_byway_split.split_node_id;
            }
         }

         var bway:Byway;
         for each (bway in byways) {

            if ((G.map.xform_scalar_map2cv(bway.length)
                 < this.byway_short_length)
                && (other_neighbor_count(bway, intersection_node_id) == 1)) {

               // We've already checked that the user can edit the byways in
               // question, so permissions are already okay on this operation.
               // FIXME: What if permissions change on the server? Notify the
               //        user on Working Copy Update, or notify user when they
               //        save and it fails?

               // We just created this item (it's fresh), so remove it from the
               // new_items list (and just forget about it).
               m4_DEBUG('short_byways_del_maybe: new_items.del: bway:', bway);
               this.new_items = Collection.array_remove(bway, this.new_items);

               var cmd_item_delete:Item_Delete;
               cmd_item_delete = new Item_Delete(new Set_UUID([bway,]));
               cmd_item_delete.skip_panel = true;
               cmd_item_delete.do_();
               this.cmd_stack.push(cmd_item_delete);
            }
         }
      }

      // ***

      //
      override public function activate_panel_do_() :void
      {
         m4_TALKY('activate_panel_do_');
         m4_ASSERT(!this.skip_panel);
         this.panel_reset_maybe(this.old_items);
         G.panel_mgr.effectively_active_panel = null;
      }

      //
      override public function activate_panel_undo() :void
      {
         m4_TALKY('activate_panel_undo');

         this.panel_reset_maybe(this.new_items);
         G.panel_mgr.effectively_active_panel = null;
      }

      //
      override public function prepare_command(callback_done:Function,
                                               callback_fail:Function,
                                               ...extra_items_arrays)
         :Boolean
      {
         var prepared:Boolean = false;
         m4_DEBUG('prepare_command: checking permissions');
         // Parent class checks user can edit selected byway, but we also need
         // to make sure user can create new byways.
         // Is this too kludgy? Ask the tool itself if the user can use it.
         var allowed:Boolean =
            G.map.tool_dict['tools_byway_create'].user_has_permissions;
         if (!allowed) {
            m4_ASSERT(false); // Map_Tool should be disabled
            Alert.show(
               'You do not have permission to create new blocks.',
               'Cannot create new block');
         }
         else {
            prepared = super.prepare_command.apply(this,
                                                   [callback_done,
                                                    callback_fail,
                                                    extra_items_arrays,]);
         }
         return prepared;
      }

      // *** Do and Undo

      //
      override public function do_() :void
      {
         var byway:Byway;

         var first_time:Boolean = (this.undone === null);
         if (first_time) {
            this.setup_split_byways();
         }

         super.do_();

         // [lb] thinks the Byway_Split commands take care of this
         // theoretically but in reality that's not the case (see comments
         // below) so just to be sure (this is hopefully redundant) cleanup.
         for each (byway in this.old_items) {
            m4_TALKY('do_: deleting old byway:', byway);
            byway.deleted = true;
            // NOTE: This calls node_cleanup on parent.beg_/fin_node_id.
            G.map.item_discard(byway);
         }

         m4_TALKY('do_: this.new_items.length:', this.new_items.length);

         if (this.cmd_stack_reversed) {
            this.cmd_stack.reverse();
            this.cmd_stack_reversed = false;
         }

         if (!first_time) {
            var cmd:Command_Base;
            for each (cmd in this.cmd_stack) {
               m4_TALKY('do_: do_ cmd:', cmd);
               cmd.do_();
            }
         }

         // [lb] thinks this code should be unneccessarryy because
         // the Byway_Split commands should set items selected, but
         // it for some reason doesn't work like it.
         for each (byway in this.new_items) {
            m4_TALKY('do_: selecting new byway:', byway);
            byway.deleted = false;
            G.map.items_add([byway,]);
            byway.set_selected(true);
            byway.draw_all();
         }

         G.map.intersection_detector.nodes_rebuild();
      }

      //
      override public function undo() :void
      {
         var byway:Byway;

         super.undo();

         m4_TALKY('undo: this.old_items.length:', this.old_items.length);

         m4_ASSERT(!this.cmd_stack_reversed);
         this.cmd_stack.reverse();
         this.cmd_stack_reversed = true;

         // Undo composite commands.
         var cmd:Command_Base;
         for each (cmd in this.cmd_stack) {
            m4_TALKY('undo: undo cmd:', cmd);
            cmd.undo();
         }

         for each (byway in this.new_items) {
            m4_TALKY('undo: deleting a new_items:', byway);
            byway.deleted = true;
            G.map.item_discard(byway);
         }

         // See comments in do_: the Byway_Split commands should really handle
         // this but just in case (because they are) not working correctly,
         // redundantly make sure byways are selected now.
         for each (byway in this.old_items) {
            m4_DEBUG('undo: selecting an old_items:', byway);
            byway.deleted = false;
            G.map.items_add([byway,]);
            byway.set_selected(true);
            byway.draw_all();
         }

         G.map.intersection_detector.nodes_rebuild();
      }

   }
}


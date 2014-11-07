/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.utils.Dictionary;

   import items.Geofeature;
   import items.feats.Byway;
   import utils.geom.Geometry;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import views.base.UI;
   import views.map_widgets.Bubble_Node;

   public class Byway_Vertex_Move extends Vertex_Move {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Bway_VM');

      // *** Instance variables

      protected var old_beg_node_ids:Dictionary;
      protected var old_fin_node_ids:Dictionary;

      protected var new_beg_node_ids:Dictionary;
      protected var new_fin_node_ids:Dictionary;

      protected var dangle_node_ids:Dictionary;

      // If the user drags an intersection, we don't want to inadvertently
      // change the selection set (by selecting all byways connected at that
      // intersection, since a user can drag an intersection with only one
      // of its roads selected).
      protected var selected_items:Array;

      // *** Constructor

      // (xdelta, ydelta) is canvas coordinates.
      public function Byway_Vertex_Move(byways:Array,
                                        vert_is:Array,
                                        xdelta:Number,
                                        ydelta:Number) :void
      {
         super(byways, vert_is, xdelta, ydelta);

         // The parent, Vertex_Move, says we can use any panel so long as all
         // byways are selected, regardless of other byways that might also be
         // selected.
         m4_ASSERT(this.loose_selection_set);

         this.old_beg_node_ids = new Dictionary();
         this.old_fin_node_ids = new Dictionary();

         this.new_beg_node_ids = new Dictionary();
         this.new_fin_node_ids = new Dictionary();

         this.dangle_node_ids = new Dictionary();

         this.selected_items = new Array();

         // Save old node id state, and prepare dangle node IDs lookup.
         for each (var byway:Byway in byways) {
            this.old_beg_node_ids[byway.stack_id] = byway.beg_node_id;
            this.old_fin_node_ids[byway.stack_id] = byway.fin_node_id;
            if (byway.selected) {
               this.selected_items.push(byway);
            }
            m4_ASSERT_SOFT(this.selected_items.length >= 1);
            this.dangle_node_ids[byway.beg_node_id] = 0;
            this.dangle_node_ids[byway.fin_node_id] = 0;
            m4_DEBUG('Byway_Vertex_Move: byway:', byway);
         }
         m4_DEBUG2('Byway_Vertex_Move: dangle_node_ids.len:',
                   Collection.dict_length(this.dangle_node_ids));
      }

      // *** Instance methods

      //
      // Command_Base.activate_appropriate_panel ensures the selection set
      // includes a command's edited items, but the Byway_Vertex_Move command
      // is special: it edits items without necessarily selecting them.
      override protected function get feats_to_select() :Array
      {
         return this.selected_items;
      }

      //
      override public function do_() :void
      {
         super.do_();
         this.inconsistent_loop_check_maybe();
      }

      //
      override public function undo() :void
      {
         super.undo();
         this.inconsistent_loop_check_maybe();
      }

      // ***

      //
      override public function merge_from(other:Command_Base) :Boolean
      {
         var merged_from:Boolean = false;

         var other_bvm:Byway_Vertex_Move = (other as Byway_Vertex_Move);

         if ((other_bvm !== null) && (super.merge_from(other_bvm))) {

            this.new_beg_node_ids = other_bvm.new_beg_node_ids;
            this.new_fin_node_ids = other_bvm.new_fin_node_ids;
            this.dangle_node_ids = Collection.dict_copy(
                                 other_bvm.dangle_node_ids);

            merged_from = true;
         }

         return merged_from;
      }

      //
      override protected function move_do(feat:Geofeature, i:int) :void
      {
         super.move_do(feat, i);

         var bway:Byway = (feat as Byway);
         m4_ASSERT(bway !== null);

         // we use old_x_node_ids as the current nodes, and new_x as the
         // next nodes; because of this, the first time through, the new_x
         // dictionary will be filled looked-up/new node ids
         if (this.vert_is[i] == 0) {
            m4_TALKY('move_do: vert_is[i] == 0');
            this.node_endpoint_update(bway,
                                      bway.beg_node_id,
                                      this.vert_is[i], /*start=*/true,
                                      this.old_beg_node_ids,
                                      this.new_beg_node_ids);
         }
         else if (this.vert_is[i] == (bway.xs.length - 1)) {
            m4_TALKY('move_do: vert_is[i] == bway.xs.length - 1');
            this.node_endpoint_update(bway,
                                      bway.fin_node_id,
                                      this.vert_is[i], /*start=*/false,
                                      this.old_fin_node_ids,
                                      this.new_fin_node_ids);
         }
         else {
            // EXPLAIN: This is not an endpoint being dragged?
            m4_TALKY('move_do: vert_is[i] is not an endpoint?');
         }

         G.map.intersection_detector.remove(bway);
         G.map.intersection_detector.insert(bway);
      }

      // Check for invalid loops on all Byways, only gripe once
      protected function inconsistent_loop_check_maybe() :void
      {
         var p:Byway;

         for each (p in this.edit_items) {
            if (this.inconsistent_loop_check(p)) {
               break; // only want 1 alert so end now
            }
         }
      }

      // Check if the byway is a loop. If not, pop-up a warning, but it's
      // unclear how to repair it so we do nothing but gripe.
      // Returns true if inconsistent.
      protected function inconsistent_loop_check(bway:Byway) :Boolean
      {
         var sx:Number = bway.xs[0];
         var sy:Number = bway.ys[0];

         var ex:Number = bway.xs[bway.xs.length - 1];
         var ey:Number = bway.ys[bway.xs.length - 1];

         if (bway.beg_node_id == bway.fin_node_id) {
            // we have a loop, check if it's inconsistent
            if (Geometry.distance(sx, sy, ex, ey) > Conf.byway_equal_thresh) {
               m4_WARNING('inconsistent_loop_check: bway:', bway);
               m4_WARNING2('inconsistent_loop_check: beg_node_id:',
                           bway.beg_node_id);
               m4_WARNING2('inconsistent_loop_check: fin_node_id:',
                           bway.fin_node_id);
               m4_ASSERT_SOFT(false);
// 2014.07.09: ARGHHHHHHHHHHHHH What can't I reproduce this predictably?
//
// I edited an existing byway, dragged it, maybe had done an Undo,
// and now both node ids are equal!
// In flashclient, search for stack ID: 1400010
// I thought maybe it had to do with disconnected byways... but cannot repro.
//
// || Jul-09 16:12:01  WARNING #Cmd_Bway_VM inconsistent_loop_check: beg_node_id: -10
// || Jul-09 16:12:01  WARNING #Cmd_Bway_VM inconsistent_loop_check: fin_node_id: -10

               // present a warning
               UI.gripe(
                  'Cyclopath was unable to perform this action '
                  + 'because of an internal inconsistency. '
                  + 'Either discard all changes and start over '
                  + '(recommended) or manually repair the intersection.');
               // FIXME Rn. id: stack_id
               G.sl.event('error/inconsistent_vertex',
                          {id: bway.stack_id,
                           version: bway.version,
                           beg_node: bway.beg_node_id,
                           fin_node: bway.fin_node_id,
                           start_x: sx,
                           start_y: sy,
                           end_x: ex,
                           end_y: ey});
               return true;
            }
         }
         return false;
      }

      //
      override protected function move_undo(feat:Geofeature, i:int) :void
      {
         super.move_undo(feat, i);

         var bway:Byway = (feat as Byway);
         m4_ASSERT(bway !== null);

         // we've swapped new and old because we're undoing also, since
         // old_x_node_ids will be used as next in node_endpoint_update(), we
         // won't generate a new node because the old nodes dicts were filled
         // at construction
         if (this.vert_is[i] == 0) {
            this.node_endpoint_update(bway,
                                      bway.beg_node_id,
                                      this.vert_is[i], /*start=*/true,
                                      this.new_beg_node_ids,
                                      this.old_beg_node_ids);
         }
         else if (this.vert_is[i] == (bway.xs.length - 1)) {
            this.node_endpoint_update(bway,
                                      bway.fin_node_id,
                                      this.vert_is[i], /*start=*/false,
                                      this.new_fin_node_ids,
                                      this.old_fin_node_ids);
         }
         // else, not an endpoint.

         G.map.intersection_detector.remove(bway);
         G.map.intersection_detector.insert(bway);
      }

      // Update the byway's node_id (either beg_node or fin_node) to reflect
      // movement changes. The node_id must be within current (current node
      // start for start/end). next is used to determine the next node to use,
      // if no node is present for the byway it will snap to a nearest node in
      // the map or create a new one.
      //
      // When performing move_do, current should be old_x_node_ids and next
      // should be new_x_node_ids. For an undo, these whould be swapped. x
      // is either start or end, depending on if node_id is equal to the
      // byway's beg_node_id or fin_node_id.
      protected function node_endpoint_update(
         byway:Byway,
         node_id:int,
         vertex_idx:int,
         start:Boolean,
         curr_node_ids:Dictionary,
         next_node_ids:Dictionary) :void
      {
         m4_TALKY8('node_endpoint_update: node_id:', node_id,
                   '/ vertex_idx:', vertex_idx,
                   '/ beg-dangle_nd:', this.dangle_node_ids[
                                          byway.beg_node_id],
                   '/ fin-dangle_nd:', this.dangle_node_ids[
                                          byway.fin_node_id],
                   '/ start:', start,
                   '/ xs.len:', byway.xs.length);
         m4_TALKY('node_endpoint_update: byway:', byway);

         m4_ASSERT(node_id == curr_node_ids[byway.stack_id]);

         var xy_index:int = (start ? 0 : (byway.xs.length - 1));

         // clean-up current node, only if the byway isn't a loop
         if (byway.beg_node_id != byway.fin_node_id) {
            m4_DEBUG('node_endpoint_update: node_cleanup: node_id:', node_id);
            G.map.node_cleanup(node_id, byway);
         }
         else {
            m4_ASSERT_SOFT((byway.beg_node_id == 0)
                        && (byway.fin_node_id == 0));
         }

         // determine next node to use
         if (!(byway.stack_id in next_node_ids)) {
            // don't have a next node, so pick one
            var xy_dist:Number;
            xy_dist = Geometry.distance(0, 0, this.xdelta, this.ydelta);
            // The byway_equal_thresh is, e.g., 0.1 meters.
            if (xy_dist > Conf.byway_equal_thresh) {
               // old node no longer valid
               var bn:Bubble_Node;
               bn = G.map.node_snapper.nearest(byway.xs[xy_index],
                                               byway.ys[xy_index],
                                               Conf.byway_equal_thresh);
               if (bn !== null) {
                  // We found a node to which we can snap.
                  m4_DEBUG('node_endpoint_update: snapping:', bn.stack_id);
                  node_id = bn.stack_id;
               }
               else {
                  // If the node is a dangle and also a client dangle (with a
                  // negative stack ID), we can keep using it. (Otherwise, for
                  // every mouse move, we'd claim a new client stack ID, which
                  // is not only annoying if you're OCD, but it also makes
                  // debugging a little harder, since ID numbers keep
                  // changing).
                  // NOTE: The geometry of a node endpoint is immutable,
                  //       i.e., they represent a fixed point in space.
                  //       This means that when, e.g., you drag a vertex,
                  //       you're created a new node ID (or snapping to
                  //       and using another node ID).
                  var vertex_is_dangle:Boolean = false;
                  vertex_is_dangle = byway.is_dangle(vertex_idx);
                  if ((node_id > 0) || (!vertex_is_dangle)) {
                     // This is either an existing endpoint or it's in use by
                     // one or more other byways. If it's an existing endpoint,
                     // we can't move it (since endpoint geometry is
                     // immutable); if it's in use by other byways, it's also
                     // immutable.
                     vertex_is_dangle = false;
                     var skip_dangle_computation:Boolean = false;
                     // NOTE: The byway's endpoint node IDs are the old IDs.
                     if (   (start)
                         && (this.dangle_node_ids[byway.beg_node_id] > 0)
                         && (this.dangle_node_ids[byway.beg_node_id]
                             != node_id)) {
                           m4_DEBUG('node_endpoint_update: beg dangle nid');
                           m4_ASSERT_SOFT(byway.fin_node_id
                              != this.dangle_node_ids[byway.beg_node_id]);
                           byway.beg_node_id = this.dangle_node_ids[
                                                   byway.beg_node_id];
                     }
                     else if (   (!start)
                              && (this.dangle_node_ids[byway.fin_node_id] > 0)
                              && (this.dangle_node_ids[byway.fin_node_id]
                                  != node_id)) {
                           m4_DEBUG('node_endpoint_update: fin dangle nid');
                           m4_ASSERT_SOFT(byway.beg_node_id
                              != this.dangle_node_ids[byway.fin_node_id]);
                           byway.fin_node_id = this.dangle_node_ids[
                                                   byway.fin_node_id];
                     }
                     else {
                        skip_dangle_computation = true;
                     }
                     if (!skip_dangle_computation) {
                        vertex_is_dangle = byway.is_dangle(vertex_idx);
                     }
                     m4_DEBUG5('node_endpoint_update: beg_node_id:',
                               byway.beg_node_id, '/ fin_node_id:',
                               byway.fin_node_id, '/ vertex_is_dangle:',
                               vertex_is_dangle, '/ skip_dangle_computation:',
                               skip_dangle_computation);
                     var dangle_lookup_id:int = 0;
                     if (start) {
                        dangle_lookup_id = byway.beg_node_id;
                     }
                     else {
                        dangle_lookup_id = byway.fin_node_id;
                     }
                     m4_ASSERT_SOFT(this.dangle_node_ids[dangle_lookup_id]
                                    !== null);
                     m4_ASSERT_SOFT(this.dangle_node_ids[dangle_lookup_id]
                                    !== undefined);
                     if (// If this is the first time this command has run,
                            (this.dangle_node_ids[dangle_lookup_id] == 0)
                         // or if dangle_node_id is node_id so not a dangle,
                         || (this.dangle_node_ids[dangle_lookup_id] == node_id)
                         // or if our old dangle ID is no longer a dangle.
                         || (!vertex_is_dangle)) {
                        // NOTE: This whole exercise is to make debugging
                        //       easier. We wouldn't exhaust the client ID
                        //       pool, but after a few minutes of editing and
                        //       dragging vertices around, if we didn't reuse
                        //       client IDs, our node IDs could be in the
                        //       thousands. And that just makes debugging (and
                        //       tracking, i.e., a new byway as you edit it)
                        //       more difficult.
                        this.dangle_node_ids[dangle_lookup_id]
                           = G.item_mgr.assign_id_new();
                     }
                     // else, dangle_node_id is 0, it's not node_id, or
                     // vertex is not a dangle, so we can keep using it.
                     m4_TALKY6('node_endpoint_update: new dangle_node_id:',
                               this.dangle_node_ids[dangle_lookup_id],
                               '/ dangle_lookup_id:', dangle_lookup_id,
                               '/ vertex_idx:', vertex_idx,
                               '/ node_id:', node_id,
                               '/ vertex_is_dangle:', vertex_is_dangle);
                     node_id = this.dangle_node_ids[dangle_lookup_id];
                     m4_ASSERT_SOFT(node_id != 0);
                  }
                  // else, node_id is a dangle, so we can keep using it.
                  m4_TALKY2('node_endpoint_update: new node client stack_id:',
                            node_id);
               }
            } // else keep node the same, since there's no node chg

            next_node_ids[byway.stack_id] = node_id;
         } // end: (!(byway.stack_id in next_node_ids)) {
         else {
            m4_DEBUG2('node_endpoint_update: next node ID for stack ID:',
                      next_node_ids[byway.stack_id]);
            node_id = next_node_ids[byway.stack_id];
            m4_ASSERT_SOFT(node_id != 0);
         }

         // init next node
         G.map.node_init(node_id,
                         byway.xs[xy_index],
                         byway.ys[xy_index],
                         byway);
         if (start) {
            byway.beg_node_id = node_id;
         }
         else {
            byway.fin_node_id = node_id;
         }
      }

   }
}


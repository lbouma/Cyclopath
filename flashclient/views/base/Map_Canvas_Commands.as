/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Part of the Map class hierarchy.

package views.base {

   import flash.events.Event;
   import flash.geom.Point;
   import flash.utils.Dictionary;
   import mx.collections.ArrayCollection;
   import mx.controls.Alert;

   import items.Geofeature;
   import items.feats.Byway;
   import utils.misc.Collection;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.map_widgets.Bubble_Node;
   import views.map_widgets.Intersection_Detector;
   import views.map_widgets.Items_Added_Listener;
   import views.map_widgets.Node_Snapper;

   public class Map_Canvas_Commands extends Map_Canvas_Items {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('MC_Commands');

      // *** Instance variables

      // The selectedset is 1 or more (or none) of the selected geofeatures on
      // the map. If none are selected, the user sees the Map Details (or
      // Branch Details) panel. If 1 or more are selected, they're the same
      // type of geofeature and we prepare the Detail Panel for that type of
      // geofeature.
      public var selectedset:Set_UUID;

      // FIXME: route reactions. [lb] is not sure about this...
      // FIXME: Statewide UI: See comments elsewhere about this.
      // public var selectedset_old:Set_UUID; // used to restore selections

      // EXPLAIN: Are these Item_Versioned listeners or Geofeature listeners?
      protected var items_added_listeners:Set_UUID;
      public var intersection_detector:Intersection_Detector;
      public var node_snapper:Node_Snapper;

      public var nodes_adjacent:Dictionary; // {node_stack_id: touching byways}

      // Additional variables used for highlighting
      public var bubble_nodes:Dictionary; // {node_stack_id: Bubble_Node, ...,}

      // *** Constructor

      public function Map_Canvas_Commands()
      {
         super();
         //
         this.items_added_listeners = new Set_UUID();
         // Node snapper
         m4_DEBUG('new Map_Canvas_Commands: new Node_Snapper');
         this.node_snapper = new Node_Snapper();
         this.items_added_listeners.add(this.node_snapper);
         // Intersection Detector
         this.intersection_detector = new Intersection_Detector();
         this.items_added_listeners.add(this.intersection_detector);

         G.app.addEventListener('modeChange', this.on_mode_change);
      }

      // *** Instance methods

      //
      public function notify_selectedset_change(added_item:Boolean,
                                                removed_item:Boolean) :void
      {
         m4_DEBUG('notify_selectedset_change: dispatch: selectionChanged');
         // Flex 3 has no logical XOR operator, so do something funny lookin'.
         m4_ASSURT(((added_item ? 1 : 0) + (removed_item ? 1 : 0)) == 1);
      }

      //
      protected function on_mode_change(ev:Event=null) :void
      {
         //m4_DEBUG('on_mode_change');
         // See also: geofeatures_redraw().
         this.selectedset_redraw();
      }

      // MAYBE: Hook the selectionChanged event and call this fcn.
      //
      public function selectedset_redraw() :void
      {
         //m4_DEBUG('selectedset_redraw');
         var gf:Geofeature;
         // This fcn. is called on a command redo and also by
         // Panel_Item_Attachment.delete_alert_handler. Ideally,
         // we'd only redraw affected geofeatures, but this is
         // easy and should be quick and painless.
         for each (gf in this.selectedset) {
            //m4_DEBUG('selectedset_redraw: gf:', gf);
            // MAYBE: This is a little hacky. Is there a better way?
            if (gf.selected) {
               gf.vertices_activate();
            }
            else {
               gf.vertices_deactivate();
            }
            gf.draw_all();
         }
      }

      // ***

      //
      override protected function discard_preserve() :void
      {
         // Backup the selected set.
         // FIXME: Statewide UI: Revisit this. See comments elsewhere.
         //? this.selectedset_old = this.selectedset.clone();

         super.discard_preserve();
      }

      //
      override protected function discard_reset() :void
      {
         this.nodes_adjacent = new Dictionary();
         this.bubble_nodes = new Dictionary();
         // Jingle the parent class.
         super.discard_reset();
      }

      //
      override public function items_add(
         new_items:Array,
         complete_now:Boolean=true,
         final_items:ArrayCollection=null)
            :Boolean
      {
         // The Map_Canvas_Items.items_add fcn. pops off of new_items;
         // we need a copy for items_add_finish.
         var new_items_copy:Array;
         if (complete_now) {
            new_items_copy = Collection.array_copy(new_items);
         }

         var tstart:int;
         var operation_complete:Boolean;
         operation_complete = super.items_add(new_items, complete_now,
                                              final_items);
         // HACK Alert: If complete_now is false, we assume the callee will
         //             call items_add_finish
         // We break early if G.gui_starved says so, so new_items might
         // still contain... new_items.
         if ((complete_now)
             && (new_items !== null)
             && (new_items.length != 0)) {
            m4_WARNING('items_add: new_items !empty: this:', this);
            m4_WARNING('stack_trace:', Introspect.stack_trace());
            // Do we care to do this?: new_items.length = 0;
         }

         if (complete_now) {
            if (new_items_copy.length > 0) {
               m4_ASSERT(operation_complete);
               // Be sure to let the fcn. know what item types we processed;
               // if they're byways, it'll rebuild map nodes (which takes a
               // while).
               this.items_add_finish(new_items_copy);
            }
            else {
               m4_WARNING('items_add: no new_items: this:', this);
               m4_WARNING('stack_trace:', Introspect.stack_trace());
            }
         }

         return operation_complete;
      }

      //
      public function items_add_finish(new_items:Array=null) :Boolean
      {
         var tstart:int = G.now();

         // Inform the items_added_listeners (currently just node_snapper
         // and intersection_detector) that new items were added. (They
         // really only care about Byways)
         var listener:Items_Added_Listener;
         for each (listener in this.items_added_listeners) {
            listener.on_items_added(new_items);
         }

         // This pretty much just times nodes_rebuild.
         m4_DEBUG_TIME('Items_Added_Listeners: on_items_added');

         var finished:Boolean = true;
         return finished;
      }

      // ***

      // Clear the map selection.
      override public function map_selection_clear() :void
      {
         m4_DEBUG('map_selection_clear');

         m4_ASSERT(G.item_mgr !== null);

         if (this.selectedset === null) {
            m4_VERBOSE('  resetting selectedset!');
            this.selectedset = new Set_UUID();
            // Skipping: G.map.notify_selectedset_change(false, false);
         }
         else if (this.selectedset.length > 0) {

            // Remember an item for later reference.
            // 2013.03.03: Dead code? What happened? This used to do something.
            //var an_item:Geofeature;
            //an_item = (this.selectedset.item_get_random() as Geofeature);

            // We can't safely add or remove from a Set while iterating,
            // so make a clone.
            var old:Set_UUID = this.selectedset.clone();

            for each (var feat:Geofeature in old) {
               m4_DEBUG('map_selection_clear: deselecting:', feat);
               // NOTE: If effectively_active_panel is the panel to which this
               //       geofeature belongs, it'll be removed from the panel's
               //       selection set; otherwise, it's just deselected (so the
               //       next time that the panel is shown, the item will be
               //       re-selected).
               feat.set_selected(false);
            }

            // Setting a selected item to false causes it to remove itself from
            // selectedset (see Geofeature.as), so check the set is emtpy now.
            m4_ASSERT(this.selectedset.length == 0);

            // 2013.03.09: Nothing hook the selectionChanged event.
            var added_item:Boolean = false;
            var removed_item:Boolean = true;
            this.notify_selectedset_change(added_item, removed_item);
         }
         if (G.item_mgr.active_route !== null) {
            m4_WARNING2('map_selection_clear: deselect active_route:',
                        G.item_mgr.active_route);
            G.item_mgr.active_route.set_selected(false, /*nix=*/false);
         }
      }

      // ***

      // Remove byway from node data structures associated with node
      // node_id, and clean up those data structures.
      public function node_cleanup(node_id:int, byway:Byway) :void
      {
         // Don't assert this because sometimes we want to remove the node
         // after the byway is torn down.
         //  m4_ASSERT((node_id == byway.beg_node_id)
         //            || (node_id == byway.fin_node_id));

         if (G.map.nodes_adjacent[node_id] === undefined) {
            return;
         }

         G.map.nodes_adjacent[node_id].remove(byway);

         if (G.map.nodes_adjacent[node_id].length == 0) {
            delete G.map.nodes_adjacent[node_id];
            G.map.node_snapper.remove(this.bubble_nodes[node_id]);
            delete this.bubble_nodes[node_id];
         }
         else {
            // redraw the (former) neighbors
            for each (byway in G.map.nodes_adjacent[node_id]) {
               if (byway.is_drawable) {
                  //m4_VERBOSE('node_cleanup: is_drawable: byway:', byway);
                  byway.draw();
               }
               else {
                  m4_DEBUG('node_cleanup: not drawing: byway', byway);
               }
            }
         }
      }

      // Initialize the data structures associated with node node_id and byway
      // byway, if initializion is required, and add byway to them. New node is
      // created at map coordinates (x,y). Parameter no_snap, which prevents
      // the new node from being added to the snapper, is provided so
      // bulk-loaded new features can defer this step.
      public function node_init(node_id:int,
                                x:Number,
                                y:Number,
                                byway:Byway,
                                no_snap:Boolean=false) :void
      {
         var x:Number;
         var y:Number;
         var bn:Bubble_Node;

         // Don't assert this because sometimes we want to create the node
         // before the byway is fully set up.
         //m4_ASSERT((node_id == byway.beg_node_id)
         //          || (node_id == byway.fin_node_id));

         // node_ids can be positive or negative. If they are negative, it
         // signals a new node (much like a fresh item_versioned) and a proper
         // node_id will be assigned to every connecting block when saved.
         m4_ASSERT(node_id != 0);

         if (!(node_id in G.map.nodes_adjacent)) {
            G.map.nodes_adjacent[node_id] = new Set_UUID();
            bn = new Bubble_Node(node_id, x, y);
            this.bubble_nodes[node_id] = bn;
            if (!no_snap) {
               m4_DEBUG('node_init: snap:', bn);
               // Useless: m4_DEBUG('node_init: snappr:', G.map.node_snapper);
               G.map.node_snapper.insert(bn);
            }
            else {
               m4_TALKY('node_init: nope:', bn);
            }
         }

         if (!(G.map.nodes_adjacent[node_id].is_member(byway))) {
            m4_VERBOSE2('node_init: adding to node_id:', node_id,
                        ' / byway:', byway);
            G.map.nodes_adjacent[node_id].add(byway);
         }
         // else, already added.
      }

      // ***

      // Snap the given canvas coordinates (x,y) to the nearest node, if one
      // exists within snap_radius pixels, otherwise return (x,y) unchanged.
      // Pass exclude through only if exclude's adjacent byways match
      // those in exclude_adj.
      public function snap_byway(x:Number,
                                 y:Number,
                                 snap_radius:Number,
                                 exclude:Bubble_Node=null,
                                 exclude_adj:Array=null) :Point
      {
         // if exclude is not null, set it to null if exclude_adj
         // is not equal to exclude's current adjacency set
         if (exclude !== null) {
            var adj:Set_UUID = this.nodes_adjacent[exclude.stack_id];

            // perform an inpromptu set/array equality check,
            // if the lengths are equal, the sets can only be equal if
            // every element in one is within the other
            if (adj.length == exclude_adj.length) {
               for each (var byway:Byway in exclude_adj) {
                  if (!adj.is_member(byway)) {
                     exclude = null;
                     break;
                  }
               }
            }
            else {
               exclude = null;
            }
         }

         var bbl_node:Bubble_Node =
            this.node_snapper.nearest(
               this.xform_x_cv2map(x),
               this.xform_y_cv2map(y),
               this.xform_scalar_cv2map(snap_radius),
               exclude);

         var the_pt:Point;
         if (bbl_node !== null) {
            // snap
            the_pt = new Point(this.xform_x_map2cv(bbl_node.b_x),
                               this.xform_y_map2cv(bbl_node.b_y));
            m4_TALKY('snap_byway: found snapping point');
         }
         else {
            // nothing to snap to
            the_pt = new Point(x, y);
            m4_TALKY('snap_byway: nothing of snapping interest');
         }

         return the_pt;
      }

      // ***

   }
}


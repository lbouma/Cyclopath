/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets {

   import flash.geom.Rectangle;

   import items.feats.Byway;
   import utils.geom.Geometry;
   import utils.misc.Logging;
   import utils.r_tree.R_Tree;

   public class Node_Snapper implements Items_Added_Listener {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('NodeSnapper');

      // *** Instance variables

      protected var r_tree:R_Tree;

      // *** Constructor

      public function Node_Snapper() :void
      {
         m4_DEBUG('new Node_Snapper: new R_Tree');
         this.r_tree = new R_Tree(2, 4);
      }

      // *** Event handlers

      // SIMILAR_TO: Intersection_Detector.on_items_added
      public function on_items_added(items_added:Array=null) :void
      {
         var do_rebuild:Boolean = false;
         if (items_added === null) {
            // See comments in Intersection_Detector:
            // Update_Viewport_Base.update_step_viewport_items calls us
            // without items_added to force a nodes_rebuild, but,
            // 1.) It may be redundant (Intersection_Dectector does the same);
            // and 2.) we also nodes_build when get checkout byways.
            //
            // BUG nnnn: nodes_build takes hundreds or thousands of
            //           milliseconds, so make sure we are not calling it
            //           redundantly. maybe track when Byway.all changes
            //           rather than just always redoing work when
            //           nodes_rebuild is called.
            //
            m4_TALKY('on_items_added: nothing to add');
         }
         else if (items_added.length > 0) {
            // CAVEAT: We expect the array to be item type homogeneous.
            m4_TALKY('on_items_added: items_added.len:', items_added.length);
            if (items_added[0] is Byway) {
               do_rebuild = true;
            }
         }
         else {
            m4_WARNING('on_items_added: empty items_added: unexpected');
         }
         if (do_rebuild) {
            m4_TALKY('on_items_added: calling nodes_rebuild');
            this.nodes_rebuild();
         }
      }

      // *** Instance methods

      //
      public function insert(bn:Bubble_Node) :void
      {
         this.r_tree.insert(bn);
      }

      //
      public function nodes_rebuild() :void
      {
         var b:Bubble_Node;
         var bubble_nodes:Array;
         var tstart:int = G.now();

         if (!G.map.zoom_is_vector()) {
            return;
         }

         bubble_nodes = Bubble_Node.all();
         this.r_tree.clear();
         //G.map.highlights.graphics.clear();
         //G.map.highlights.graphics.lineStyle(2, 0x00ff00);

         for each (b in bubble_nodes) {
            //G.map.highlights.graphics.drawCircle(G.map.xform_x_map2cv(b.b_x),
            //                                     G.map.xform_y_map2cv(b.b_y),
            //                                     2);
            this.r_tree.insert(b);
         }

         m4_DEBUG_TIME('Node_Snapper.nodes_rebuild');
      }

      // Return the Bubble_Node nearest to point (x,y), or null if none exists
      // within a radius of limit. If exclude is non-null, that Bubble_Node is
      // ignored when searching.
      public function nearest(x:Number,
                              y:Number,
                              limit:Number,
                              exclude:Bubble_Node=null) :Bubble_Node
      {
         var bubn:Bubble_Node;
         var bs:Array;
         var d:Number;
         var qrect:Rectangle;
         var winner:Bubble_Node = null;
         var d_max:Number = Infinity;

         qrect = new Rectangle(x - limit, y - limit, limit * 2, limit * 2);
         for each (bubn in this.r_tree.query(qrect)) {
            // Why [lb] doesn't like single char vars: it's unreadable,
            //                                     and it's unsearchable.
            //          d = Geometry.distance(x, y, b.b_x, b.b_y);
            d = Geometry.distance(x, y, bubn.b_x, bubn.b_y);
            m4_TALKY5('nearest: testing: d:', d,
                      '/ limit:', limit,
                      '/ d_max:', d_max,
                      '/ exclude:', exclude,
                      '/ bubn:', bubn);
            if ((d <= limit)
                && (d < d_max)
                && ((exclude === null)
                    // This is when it intersects with itself?
                    || (bubn !== exclude))) {
               winner = bubn;
               d_max = d;
               m4_TALKY('nearest: accepted: bubn:', bubn);
            }
            else {
               m4_TALKY('nearest: rejected: bubn:', bubn);
            }
         }

         m4_DEBUG('nearest: winner:', ((winner !== null) ? winner : 'null'));

         return winner;
      }

      //
      public function remove(bn:Bubble_Node) :void
      {
         this.r_tree.remove(bn);
      }

      // ***

      //
      public function toString() :String
      {
         // Without toString, stringification returns: "[object Node_Snapper]".
         var what_is:String =
            'Node_Snapper:'
            + 'r_tree: ' + this.r_tree
            ;
         return what_is;
      }

   }
}


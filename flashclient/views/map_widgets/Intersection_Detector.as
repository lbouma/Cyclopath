/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets {

   import flash.geom.Rectangle;

   import items.feats.Byway;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.r_tree.R_Tree;

   public class Intersection_Detector implements Items_Added_Listener {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Isect_Detect');

      // *** Instance variables

      protected var r_tree:R_Tree;

      // *** Constructor

      public function Intersection_Detector() :void
      {
         m4_DEBUG('new Intersection_Detector: new R_Tree');
         this.r_tree = new R_Tree(2, 4);
      }

      // *** Event handlers

      // SIMILAR_TO: Node_Snapper.on_items_added
      public function on_items_added(items_added:Array=null) :void
      {
         m4_DEBUG('on_items_added: items_added:', items_added);
         var o:Object;
         var cls:Class = null;
         // items_added is null if viewport update is forcing it.
         // FIXME: Update_Viewport_Base.update_step_viewport_items calls us
         //        without any items_added to force a nodes_rebuid: but isn't
         //        that redundant? I.e., didn't we just do that for the byways
         //        we received? Or is this because the user might have byways
         //        in their working copy? If the latter, why do we bother with
         //        nodes_rebuild in the byways checkout callback and not just
         //        wait for the viewport update to do it?
         //  ALSO: Is Node_Snapper also calling nodes_rebuild??
         var do_rebuild:Boolean = false;
         if (items_added === null) {
            do_rebuild = true;
         }
         else if (items_added.length > 0) {
            for each (o in items_added) {
               if (cls === null) {
                  cls = Introspect.get_constructor(this);
               }
               else {
                  // FIXME: If this doesn't fire, don't loop through array
                  m4_ASSERT(Introspect.get_constructor(this) == cls);
               }
               if (o is Byway) {
                  do_rebuild = true;
                  // FIXME We break on first byway since we knows there's at
                  //       least one new byway. But really, shouldn't the
                  //       Array be homogeneous?
                  break;
               }
               // 2013.06.11: We can always break because items_add is only
               // called with a homogeneous collection, right?
               break;
            }
         }
         else {
            m4_WARNING('on_items_added: empty items_added: unexpected');
         }
         if (do_rebuild) {
            this.nodes_rebuild();
         }
      }

      // *** Instance methods

      //
      public function insert(bway:Byway) :void
      {
         m4_TALKY('insert: bway:', bway);
         this.r_tree.insert(bway);
      }

      //
      public function nodes_rebuild() :void
      {
         var b:Byway;
         var tstart:int = G.now();
         var count:int = 0;

         if (G.map.zoom_is_vector()) {
            this.r_tree.clear();
            for each (b in Byway.all) {
               // FIXME: Byway.all may contain items not in the viewport
               //        but that are being saved or linked from a link_value
               //        being saved.
               // 2013.03.08: We should probably check that the Byway is
               //             not deleted...
               if (!b.deleted) {
                  this.r_tree.insert(b);
                  count++;
               }
            }
         }

         m4_DEBUG('nodes_rebuild: added:', count, 'nodes');
         m4_DEBUG_TIME('Intersection_Detector.nodes_rebuild');
      }

      // Return the Byways nearest to point (x,y), or null if none exist
      // within a radius of limit.
      public function nearest_many(x:Number, y:Number, limit:Number) :Array
      {
         var rect:Rectangle = new Rectangle(x - limit, y - limit,
                                            limit * 2, limit * 2);
         var items_intersect:Array = this.r_tree.query(rect);
         m4_TALKY('nearest_many: items_intersect:', items_intersect);
         return items_intersect;
      }

      //
      public function remove(bway:Byway) :void
      {
         m4_TALKY('remove: bway:', bway);
         this.r_tree.remove(bway);
      }

   }
}


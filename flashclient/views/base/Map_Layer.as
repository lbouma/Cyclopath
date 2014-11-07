/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Class representing one active layer of the map. An active layer is a layer
// which contain interactive or fetched map objects.

package views.base {

   import flash.geom.Rectangle;

   import items.Geofeature;
   import items.Item_Base;
   import items.feats.Byway;
   import utils.geom.Dual_Rect;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import views.map_widgets.Item_Sprite;

   public class Map_Layer extends Map_Layer_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Map_Layer');

      // *** Class attributes

      protected var map:Map_Canvas;

      // Magic number -2 means all done
      protected var discard_starting_index:int = -2;

      // To avoid starving the GUI.
      protected var last_redraw_i:int = -2;

      // *** Constructor

      public function Map_Layer(map:Map_Canvas_Base, zplus:Number)
      {
         super(zplus);
         this.map = (map as Map_Canvas);
      }

      // *** Static methods

      // Move the given feature, which is on an incorrect layer, to the
      // correct layer.
      public static function feature_relayer(gf:Geofeature,
                                             zplus_old:Number) :void
      {
         //m4_DEBUG2('feature_relayer: gf.z_level:', gf.z_level,
         //          '/ zplus_old:', zplus_old, '/ gf:', gf);
         G.map.layers[zplus_old].removeChild(gf.sprite);
         G.map.shadows[zplus_old].removeChild(gf.shadow);
         G.map.layers_add_maybe(gf);
         G.map.shadows[gf.zplus].addChild(gf.shadow);
         G.map.layers[gf.zplus].addChild(gf.sprite);
      }

      // *** Item management

      // Add a feature to the layer. If the feature has a shadow, add that to
      // the appropriate shadow layer at the same index.
      public function geofeature_add(gf:Geofeature) :void
      {
         m4_VERBOSE('geofeature_add: gf.z_level:', gf.z_level, '/ gf:', gf);
         m4_ASSERT(Conf.tile_skin !== null);
         m4_ASSERT(gf.z_level > 0); // gotta have a realistic Z value
         this.addChild(gf.sprite);
         if (gf.shadow !== null) {
            this.map.shadows[gf.zplus].addChild(gf.shadow);
         }
         gf.geofeature_added_to_map_layer();
      }

      // Discard a particular feature and its dependent objects.
      public function geofeature_discard(gf:Geofeature) :void
      {
         var i:int;
         try {
            i = this.getChildIndex(gf.sprite);
            m4_DEBUG('geofeature_discard: i:', i, '/ gf:', gf);
            gf.item_cleanup(i);
            this.removeChildAt(i);
         }
         catch (e:ArgumentError) {
            // No-op.
            // Error #2025: The supplied DisplayObject must be a child of the
            //              caller.
            m4_DEBUG('geofeature_discard: not a child:', gf);
         }
         catch (e:RangeError) {
            // RangeError: Error #2006: The supplied index is out of bounds.
            //  at flash.display::DisplayObjectContainer/getChildAt()
            // means this item was previously discarded.
            ; // pass
         }
      }

      // Discards features on this layer and dependent objects.
      //
      // - If rectangle r is null, that indicates a raster/vector transition.
      //   Discard all features except regions.
      //
      //   FIXME: The region exclusion is a hack to work around this meaning of
      //          r being null.
      //
      // - Otherwise, discard features which do not intersect r.
      //
      // - Exception: objects which are not discardable are never discarded.
      //
      // - Caveat: This fcn. can takes seconds to run if there are hundreds or
      //   thousands of items in the working copy, so it preemptively
      //   interrupts itself if it runs too long, so that the GUI can be
      //   responsive. The callee should check the return value; if it's false,
      //   the callee should callLater this function.
      public function sprite_items_discard(
         rect_keep:Dual_Rect,
         complete_now_tstart:int=0,
         complete_now:Boolean=false,
         item_types:Set=null) :Boolean
      {
         var discard_completed:Boolean = true;
         var discard_ct:int = 0;
         var item:Item_Base;
         var starting_index:int = -1;
         var tstart:int = G.now();

         //m4_DEBUG2('sprite_items_discard: rect_keep:',
         //          (rect_keep !== null) ? rect_keep.toString() : 'null');
         //m4_DEBUG('sprite_items_discard: item_types:', item_types);

         // Make sure not being called solo while processing multi-part
         m4_ASSERT((this.discard_starting_index == -2)
                   || (complete_now_tstart > 0));

         if (complete_now_tstart > 0) {
            if (this.discard_starting_index >= 0) {
               m4_VERBOSE('sprite_items_discard: Multi-parter: continue.');
               starting_index = this.discard_starting_index;
            }
            else if (this.discard_starting_index == -1) {
               m4_VERBOSE('sprite_items_discard: Multi-parter: complete.');
               m4_ASSERT(false); // unreachable
            }
            else {
               m4_ASSERT(this.discard_starting_index == -2);
               m4_VERBOSE('sprite_items_discard: Multi-parter: starting.');
               this.discard_starting_index = this.numChildren - 1;
               starting_index = this.discard_starting_index;
            }
         }
         else {
            starting_index = this.numChildren - 1;
         }

         // Iterate downwards so that indices later in the iteration are not
         // changed when features are removed (i.e., with removeChildAt(i)).
         for (var i:int = starting_index; i >= 0; i--) {
            item = (this.getChildAt(i) as Item_Sprite).item;
            //m4_DEBUG('sprite_items_discard: item:', item);
            if (item.discardable) {
               if ((rect_keep === null)
                   || (!rect_keep.intersects_map_fgrect(item.bbox_map))) {
                  if ((item_types === null)
                      || (item_types.contains(
                           Introspect.get_constructor(item)))) {
                     if (discard_ct == 0) {
                        m4_DEBUG2('sprite_items_discard: first sacrifice:',
                                  item);
                     }
                     //m4_DEBUG2('sprite_items_discard: discard: i:', i,
                     //          'item:', item);
                     item.item_cleanup(i);
                     try {
                        this.removeChildAt(i);
                        discard_ct++;
                     }
                     catch (e:RangeError) {
                        // 2014.07.16: [lb] edited a road and saved changes,
                        // and this fired sometime later (not sure after
                        // what)...
                        m4_ERROR2('EXPLAIN: supplied index oobounds: item:',
                                  item);
                        m4_ASSERT_SOFT(false);
                     }
                  }
                  else {
                     //m4_DEBUG2('sprite_items_discard: keep: get_cnstructor:',
                     //          Introspect.get_constructor(item));
                  }
               }
               else {
                  //m4_DEBUG('sprite_items_discard: keep: isects_map_fgrect');
               }
            }
            else {
               //m4_DEBUG2('sprite_items_discard: keep: !discardable',
               //          '/ i:', i, 'item:', item);
            }
            // Every 100th child(-kill), see if it's time to take a break (to
            // let the GUI refresh) (Note that our algorithm means the break
            // happens at the threshold, or 2x the threshold, or 3x, etc.)
            // FIXME: Above loop always loops over items we didn't delete the
            //        time before, which may or may not be costing us time each
            //        callLater. Design a better algorithm (use intermediate
            //        Array).
            if (   ((discard_ct % 100) == 0)
                && (!complete_now)
                && (G.gui_starved(complete_now_tstart)) ) {
               m4_DEBUG('sprite_items_discard: preemptively breaking!');
               this.discard_starting_index = i - 1;
               discard_completed = false;
               break;
            }
         }

         if ( (discard_completed) || (this.discard_starting_index == -1) ) {
            // Magic number -2 means all done
            this.discard_starting_index = -2;
            discard_completed = true;
         }

         if (discard_ct > 0) {
            m4_DEBUG2('sprite_items_discard / count:', discard_ct,
               '/ completed:', discard_completed);
         }

         m4_DEBUG_TIME('sprite_items_discard');

         return discard_completed;
      }

      // *** Draw methods

      // Redraw all the layer's features
      public function geofeatures_redraw() :Boolean
      {
         var redraw_finished:Boolean = true;

         var gf:Geofeature;
         var bway:Byway;
         var i:int;

         // Avoid GUI starvation.
         var tstart:int = G.now();

         m4_DEBUG('geofeatures_redraw');

         if (this.last_redraw_i == -2) {
            i = this.numChildren - 1;
            m4_DEBUG2('geofeatures_redraw: i:', i,
                      '/ numChildren:', this.numChildren);
         }
         else {
            i = this.last_redraw_i;
            this.last_redraw_i = -2;
            m4_DEBUG2('geofeatures_redraw: last_redraw_i:', this.last_redraw_i,
                      '/ numChildren:', this.numChildren);
         }

         // Iterate through all the geofeatures on the map and draw them if
         // visible, and clear all the node widgets.
         while (i >= 0) {

            gf = ((this.getChildAt(i) as Item_Sprite).item as Geofeature);

            // FIXME: this is kind of a hack.
            bway = (gf as Byway);
            if (bway !== null) {
               if (bway.node_widget_start !== null) {
                  bway.node_widget_start.graphics.clear();
               }
               if (bway.node_widget_end !== null) {
                  bway.node_widget_end.graphics.clear();
               }
            }

            // Check if the geofeature is drawable.
            if (gf.is_drawable) {
               // If gf is a Waypoint or Region, check with the filter.
               gf.visible = !(gf.hidden_by_filter());
               gf.draw();
            }
            else {
               gf.visible = false;
               gf.vertices_redraw();
            }

            // MAGIC_NUMBER: Some length of time wherein we won't update the
            //               client display, not even the throbberer!
            if ((G.now() - tstart) > 2548) {
               m4_WARNING3('Returning early to avoid starving during redraws:',
                           i, '/ of:', this.numChildren,
                           '/ G.now():', G.now(), '/ tstart:', tstart);
               if (i > 0) {
                  this.last_redraw_i = i - 1;
                  redraw_finished = false;
               }
               break;
            }

            i -= 1;
         }

         m4_DEBUG_TIME('Map_Layer.geofeatures_redraw');

         return redraw_finished;
      }

      // *** Label methods

      // Label all features which need labeling
      public function geofeatures_label() :void
      {
         // Milliseconds since epoch:
         var tstart:int = G.now();

         m4_VERBOSE('geofeatures_label: no.:', this.numChildren);

         for (var i:int = 0; i < this.numChildren; i++) {
            ((this.getChildAt(i) as Item_Sprite).item as Geofeature)
               .label_maybe();
            // Hack to ensure that labels aren't drawn by themselves if the
            // geofeature is not set to visible. If this isn't done, the
            // labels still get drawn, as they seem to be added after the
            // point is set to not visible.
            (this.getChildAt(i) as Item_Sprite).visible
               = (this.getChildAt(i) as Item_Sprite).visible;

            // If you load thousands of regions in a dev browser, you'll
            // hit the fifteen second flash timeout.
            if ((G.now() - tstart) > 5548) {
               m4_WARNING2('Returning early to avoid starving after relabels:',
                           i);
               break;
            }
         }
      }

      // Reset labeling state in all features. Orphans existing labels.
      public function labels_reset() :void
      {
         var i:int;
         for (i = this.numChildren - 1; i >= 0; i--) {
            ((this.getChildAt(i) as Item_Sprite).item as Geofeature)
               .label_reset();
         }
      }

   }
}


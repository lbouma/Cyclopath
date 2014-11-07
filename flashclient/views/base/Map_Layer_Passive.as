/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Class representing one _passive_ layer of the map. A passive layer is one
// containing only objects which are tied to and controlled by active objects.
//
// Additionally, objects on a passive map layer are inert with respect to the
// mouse, i.e. they cannot receive mouse events, and they do not prevent other
// objects which they cover from receiving mouse events.
//
// E.g., things like byway direction arrows, street labels, search location
// labels, etc.

package views.base {

   import flash.display.DisplayObject;
   import mx.core.UIComponent;

   import items.Geofeature;
   import items.Item_Versioned;
   import items.feats.Route;
   import utils.geom.Geometry;
   import utils.misc.Logging;
   import utils.misc.Map_Label;

   public class Map_Layer_Passive extends Map_Layer_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Map_Lyr_Pssv');

      // *** Constructor

      public function Map_Layer_Passive(zplus:Number)
      {
         super(zplus);

         // Both of these properties must be set to make children mouse-inert.
         this.mouseChildren = false;
         this.mouseEnabled = false;
      }

      // Instance methods

      // Return true if the given DisplayObject collides with an existing
      // DisplayObject, false otherwise.
      public function child_collides(
         c:DisplayObject,
         dbglog:Boolean=false)
            :Boolean
      {
         var collides:Boolean = false;
         if (c.visible) {
            collides = this.child_collides_(c, dbglog);
         }
         return collides;
      }

      // NOTE: This fcn. is part of an overall slow process!
      // BUG nnnn: Is there a way to speed up collision detection?
      //           Is the delay enough to care about?
      protected function child_collides_(
         c:DisplayObject,
         dbglog:Boolean=false)
            :Boolean
      {
         var collides:Boolean = false;

         var cl:Map_Label = (c as Map_Label);

         for (var i:int = 0; i < this.numChildren; i++) {
            var other:DisplayObject = this.getChildAt(i);
            if (c !== other) {
               var ol:Map_Label = (other as Map_Label);
               //m4_DEBUG('child_collides: ol:', ol);
               if ((cl !== null) && (ol !== null)) {
                  if (ol.visible) {
                     if (Geometry.aabb_intersects(cl.min_x, cl.max_x,
                                                       cl.min_y, cl.max_y,
                                                       ol.min_x, ol.max_x,
                                                       ol.min_y, ol.max_y)) {
                        if (Geometry.rect_intersects(cl.xs, cl.ys,
                                                     ol.xs, ol.ys)) {
                           // FIXME/BUG nnnn: This ranking of what geofeature's
                           // labels trump other feat's labels is hacked in.
                           if ((cl.item_owner is Route)
                               && (!(ol.item_owner is Route))) {
                              // cl collides with ol, but ol will not be drawn.
                              if (dbglog) {
                                 m4_DEBUG('child_collides: R-non-Rt: cl:', cl);
                                 m4_DEBUG('child_collides: R-non-Rt: ol:', ol);
                              }
                           }
                           else if ((!(cl.item_owner is Route))
                                    && (ol.item_owner is Route)) {
                              // Route trumps non-Route.
                              // BUG nnnn: Again, this is a hack. Because,
                              //           like, what about Track? Or Region?
                              collides = true;
                              if (dbglog) {
                                 m4_DEBUG('child_collides: Non-R-Rt: cl:', cl);
                                 m4_DEBUG('child_collides: Non-R-Rt: ol:', ol);
                              }
                              break;
                           }
                           else {
                              collides = true;
                              if (dbglog) {
                                 m4_DEBUG('child_collides: xsects: cl:', cl);
                                 m4_DEBUG('child_collides: xsects: ol:', ol);
                              }
                              break;
                           }
                        }
                        // else, rect does not intersect.
                     }
                     // else, aabb does not intersect.
                  }
                  // else, other is not visible, so ignore it.
               }
               else {
                  //m4_DEBUG('child_collides: other.visible:', other.visible);
                  if ((other.visible) && (c.hitTestObject(other))) {
                     collides = true;
                     if (dbglog) {
                        m4_DEBUG('child_collides: hits: c:', c);
                        m4_DEBUG('child_collides: hits: o:', other);
                     }
                     break;
                  }
               }
            }
         }
         return collides;
      }

   }
}


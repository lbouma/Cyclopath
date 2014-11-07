/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A Dual_Rect object is a simplified orthogonal rectangle. It's got four
// points, and pairs of points share the same x or y values (so it's an
// axis-aligned rect.; see http://en.wikipedia.org/wiki/Rectilinear_polygon).
// Also, it knows its coordinates in both canvas space and map space. In most
// cases (for Cyclopath, at least), the orthogonal rectangle represents a
// clipping region. For instance, PostGIS uses bboxes for first-round spatial
// matching, before resorting to more costly algorithms to determine spatial
// relationships.

// WARNING: The map coordinates are calculated from the canvas coordinates, so
// changing the transformation will invalidate the rectangle. Specifically,
// a Dual_Rect's map coordinates are only valid if the map's zoom level is the
// same as it was when that coordinates were created (however, a Dual_Rect's
// canvas coordinates are always valid, since they're based on the reference
// system, which is static).

// BUG 0050: Behavior in setting map_min_x, cv_min_x, etc. is currently
// inconsistent between map_* and cv_*: setting the top and left limits moves
// the rectangle, while setting bottom and right limits resizes it.

// PROPOSAL: Fix both of the above by (a) calculating the canvas coords based
// on the map ones and (b) storing min/max coordinates and calculating the
// height/width.

package utils.geom {

   import flash.geom.Rectangle;

   import utils.misc.Introspect;
   import utils.misc.Logging;

   public class Dual_Rect {

      protected static var log:Logging = Logging.get_logger('__Dual_Rect_');

      // *** Real attributes

      // Location of upper left corner of rect in canvas coords
      public var cv_min_x:Number;
      public var cv_min_y:Number;

      // Height and width of rect in canvas coords
      public var cv_width:Number;
      public var cv_height:Number;

      // *** Getters and setters for canvas coordinates
      // SEE WARNING ABOVE.

      // *** Constructor

      public function Dual_Rect() :void
      {
         // No-op
      }

      // *** Getters and setters

      // Location of center
      public function get cv_center_x() :Number
      {
         return this.cv_min_x + this.cv_width/2;
      }

      //
      public function get cv_center_y() :Number
      {
         return this.cv_min_y + this.cv_height/2;
      }

      // Location of lower right corner of rect
      public function get cv_max_x() :Number
      {
         return this.cv_min_x + this.cv_width;
      }

      //
      public function set cv_max_x(x:Number) :void
      {
         this.cv_width = x - this.cv_min_x;
      }

      //
      public function get cv_max_y() :Number
      {
         return this.cv_min_y + this.cv_height;
      }

      //
      public function set cv_max_y(y:Number) :void
      {
         this.cv_height = y - this.cv_min_y;
      }

      // Return the map bounds of myself in the format required for the GWIS
      // bbox parameter.
      public function get gwis_bbox_str() :String
      {
         var bbox_str:String = '';
         if (this.valid_map_min_max) {
            bbox_str =         this.map_min_x
                       + ',' + this.map_min_y
                       + ',' + this.map_max_x
                       + ',' + this.map_max_y;
         }
         else {
            m4_ERROR2('Unexpected: invalid map_min_max:',
                      this.toString());
            m4_ERROR2('Unexpected: map_x_at_canvas_origin:',
                      G.map.map_x_at_canvas_origin);
            m4_ERROR('Unexpected: zoom_level:', G.map.zoom_level);
            m4_DEBUG(Introspect.stack_trace());
         }
         return bbox_str;
      }

      // *** Getters and setters for map coordinates

      // SEE WARNING ABOVE.

      // Location of center
      public function get map_center_x() :Number
      {
         return G.map.xform_x_cv2map(this.cv_center_x);
      }

      //
      public function get map_center_y() :Number
      {
         return G.map.xform_y_cv2map(this.cv_center_y);
      }

      // Location of lower left corner
      public function get map_min_x() :Number
      {
         return G.map.xform_x_cv2map(this.cv_min_x);
      }

      //
      public function set map_min_x(x:Number) :void
      {
         this.cv_min_x = G.map.xform_x_map2cv(x);
      }

      //
      public function get map_min_y() :Number
      {
         return G.map.xform_y_cv2map(this.cv_max_y);
      }

      //
      public function set map_min_y(y:Number) :void
      {
         this.cv_max_y = G.map.xform_y_map2cv(y);
      }

      // Location of upper right corner
      public function get map_max_x() :Number
      {
         return G.map.xform_x_cv2map(this.cv_max_x);
      }

      //
      public function set map_max_x(x:Number) :void
      {
         this.cv_max_x = G.map.xform_x_map2cv(x);
      }

      //
      public function get map_max_y() :Number
      {
         return G.map.xform_y_cv2map(this.cv_min_y);
      }

      //
      public function set map_max_y(y:Number) :void
      {
         this.cv_min_y = G.map.xform_y_map2cv(y);
      }

      //
      public function get valid() :Boolean
      {
         return (   (!isNaN(this.cv_min_x))
                 && (!isNaN(this.cv_min_y))
                 && (!isNaN(this.cv_width))
                 && (!isNaN(this.cv_height))
                 && (isFinite(this.cv_min_x))
                 && (isFinite(this.cv_min_y))
                 && (isFinite(this.cv_width))
                 && (isFinite(this.cv_height)));
      }

      //
      public function set valid(valid:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get valid_map_min_max() :Boolean
      {
         return (   (!isNaN(this.map_min_x))
                 && (!isNaN(this.map_min_y))
                 && (!isNaN(this.map_max_x))
                 && (!isNaN(this.map_max_y))
                 //&& (isFinite(this.map_min_x))
                 //&& (isFinite(this.map_min_y))
                 //&& (isFinite(this.map_max_x))
                 //&& (isFinite(this.map_max_y))
                 );
      }

      //
      public function set valid_map_min_max(valid:Boolean) :void
      {
         m4_ASSERT(false);
      }

      // *** Other instance methods

      public function area() :Number
      {
         return (this.cv_width * this.cv_height);
      }

      // Return a rect like myself but expanded n pixels on each side.
      // FIXME This is an ackward name; perhaps expand? or grow? grow_by?
      public function buffer(n:Number) :Dual_Rect
      {
         var r:Dual_Rect = new Dual_Rect();
         r.moveto(this.cv_min_x - n, this.cv_min_y - n);
         r.expandto(this.cv_width + 2*n, this.cv_height + 2*n);
         return r;
      }

      // Return a copy of myself.
      public function clone() :Dual_Rect
      {
         return this.buffer(0);
      }

      // True if the rect contains the point, point is in canvas coords.
      public function contains_canvas_point(x:Number, y:Number) :Boolean
      {
         var contains_pt:Boolean = (
               this.cv_min_x <= x
            && this.cv_max_x >= x
            && this.cv_min_y <= y
            && this.cv_max_y >= y);
         m4_TALKY4('cntns_cv_pt: cv_min:', this.cv_min_x, ',', this.cv_min_y,
                                'cv_max:', this.cv_max_x, ',', this.cv_max_y,
                                 '/ x,y:', x, ',', y,
                                 '/ contains_pt:', contains_pt);
         return contains_pt;
      }

      // True if the rect contains the point, point is in map coords.
      public function contains_map_point(x:Number, y:Number) :Boolean
      {
         return this.contains_canvas_point(G.map.xform_x_map2cv(x),
                                           G.map.xform_y_map2cv(y));
      }

      // Return true if I am equal to the given rect, false otherwise. If r is
      // null, return false.
      // FIXME: This is not numerically reliable!
      public function eq(r:Dual_Rect) :Boolean
      {
         return (
            (r === this)
            || (r !== null
               && (   this.cv_min_x == r.cv_min_x
                   && this.cv_min_y == r.cv_min_y
                   && this.cv_width == r.cv_width
                   && this.cv_height == r.cv_height)));
      }

      // Set the rect size to x pixels wide and y tall, i.e. move the lower
      // right corner x pixels right and y pixels down (upper left unchanged).
      public function expandto(x:Number, y:Number) :void
      {
         this.cv_width = x;
         this.cv_height = y;
      }

      // Return the intersection of myself and r; if the intersection is
      // empty, return null. (In particular, if r is null, then return null.)
      public function intersection(r:Dual_Rect) :Dual_Rect
      {
         var p:Dual_Rect;

         if (!this.intersects(r)) {
            // intersection empty
            return null;
         }
         else {
            // intersection nonempty
            p = new Dual_Rect();
            p.cv_min_x = Math.max(this.cv_min_x, r.cv_min_x);
            p.cv_min_y = Math.max(this.cv_min_y, r.cv_min_y);
            p.cv_width = Math.min(this.cv_max_x, r.cv_max_x) - p.cv_min_x;
            p.cv_height = Math.min(this.cv_max_y, r.cv_max_y) - p.cv_min_y;
            return p;
         }
      }

      // Return true if I intersect r, false otherwise. In particular, return
      // false if r is null.
      public function intersects(r:Dual_Rect) :Boolean
      {
         return (r !== null
                 && this.cv_max_x > r.cv_min_x && this.cv_min_x < r.cv_max_x
                 && this.cv_max_y > r.cv_min_y && this.cv_min_y < r.cv_max_y);
      }

      // Return true if I intersect the map-space flash.geom.Rectangle r,
      // false otherwise.
      public function intersects_map_fgrect(r:Rectangle) :Boolean
      {
         var isects:Boolean =
               this.map_max_x > r.left
            && this.map_min_x < r.right
            && this.map_max_y > r.top
            && this.map_min_y < r.bottom;
         //m4_DEBUG('intersects_map_fgrect: isects:', isects);
         return isects;
      }

      // Compute a bbox from coordinate arrays.
      //
      // "Doesn't cache the rectangle to allow for asynchronous user vertex
      //  commands."
      public static function mobr_dr_from_xys(xs:Array, ys:Array) :Dual_Rect
      {
         // SYNC_ME: Dual_Rect.mobr_dr_from_xys / MOBR_DR_Array get mobr_dr.

         var dr:Dual_Rect = new Dual_Rect();

         // FIXME: Can't manipulate the attributes of dr directly because of
         //        buggy behavior -- see comments at top of Dual_Rect.as.
         var map_min_x:Number = Number.POSITIVE_INFINITY;
         var map_min_y:Number = Number.POSITIVE_INFINITY;
         var map_max_x:Number = Number.NEGATIVE_INFINITY;
         var map_max_y:Number = Number.NEGATIVE_INFINITY;

         var i:int;
         for (i = 0; i < xs.length; i++) {
            map_min_x = Math.min(map_min_x, xs[i]);
            map_min_y = Math.min(map_min_y, ys[i]);
            map_max_x = Math.max(map_max_x, xs[i]);
            map_max_y = Math.max(map_max_y, ys[i]);
         }

         // FIXME: order here is important for the same reason.
         dr.map_min_x = map_min_x; // left
         dr.map_max_y = map_max_y; // top
         dr.map_max_x = map_max_x; // right
         dr.map_min_y = map_min_y; // bottom

         return dr;
      }

      // Move x pixels right and y pixels down.
      public function move(x:Number, y:Number) :void
      {
         this.cv_min_x += x;
         this.cv_min_y += y;
      }

      // Move to x, y in canvas coordinates.
      public function moveto(x:Number, y:Number) :void
      {
         this.cv_min_x = x;
         this.cv_min_y = y;
      }

      // Return the union of myself and r; if r is null, return a copy of
      // myself. (Note: Strictly speaking, this does not return the union of
      // the two rectangles, but rather the smallest rectangle containing the
      // union. This is because the true union gets tricky to calculate and
      // use -- it's not a rectangle itself -- both here and in other parts of
      // the program.)
      public function union(r:Dual_Rect) :Dual_Rect
      {
         var p:Dual_Rect;

         if (r === null) {
            return this.clone();
         }
         else {
            p = new Dual_Rect();
            p.cv_min_x = Math.min(this.cv_min_x, r.cv_min_x);
            p.cv_min_y = Math.min(this.cv_min_y, r.cv_min_y);
            p.cv_width = Math.max(this.cv_max_x, r.cv_max_x) - p.cv_min_x;
            p.cv_height = Math.max(this.cv_max_y, r.cv_max_y) - p.cv_min_y;
            return p;
         }
      }

      // *** Developer methods

      // FIXME If not base class override, rename to_string
      public function toString() :String
      {
         return (     'x: ' + this.cv_min_x.toString()
                 + ' / y: ' + this.cv_min_y.toString()
                 + ' / w: ' + this.cv_width.toString()
                 + ' / h: ' + this.cv_height.toString()
                 + ' | map min: ' + this.map_min_x
                 + ', ' + this.map_min_y
                 + ' / map max: ' + this.map_max_x
                 + ', ' + this.map_max_y
                 );
      }

   }
}


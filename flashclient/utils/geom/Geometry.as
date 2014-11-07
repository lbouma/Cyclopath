/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.geom {

   import flash.geom.Point;
   import flash.geom.Rectangle;

   import utils.misc.Logging;

   public class Geometry {

      protected static var log:Logging = Logging.get_logger('__Geometry__');

      // *** Constructor

      public function Geometry() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class methods

      // Return true if the given axis-aligned bbox's intersect.
      // Each array (per coord) must be [min_coord, max_coord].
      public static function aabb_intersects(r1_min_x:Number,
                                             r1_max_x:Number,
                                             r1_min_y:Number,
                                             r1_max_y:Number,
                                             r2_min_x:Number,
                                             r2_max_x:Number,
                                             r2_min_y:Number,
                                             r2_max_y:Number) :Boolean
      {
         var x_overlap:Boolean
            = (    r1_min_x <= r2_min_x && r1_max_x >= r2_min_x)
               || (r2_min_x <= r1_min_x && r2_max_x >= r1_min_x);
         var y_overlap:Boolean
            = (    r1_min_y <= r2_min_y && r1_max_y >= r2_min_y)
               || (r2_min_y <= r1_min_y && r2_max_y >= r1_min_y);
         return x_overlap && y_overlap;
      }

      // Calculates the relative turn angle between the vector <x2, y2>
      // and <x1, y1>. This is different than the shortest angle between two
      // vectors in that this measures a full 360 degrees.
      //
      // A local orthonormal basis is used, where the y-axis is <x1, y1>.  The
      // relative angle of <x2, y2> is then measured as the ccw rotation from
      // the x-axis.  Thus 2 vectors pointint in the same direction would
      // return a value of 90.
      //
      // Return an angle from 0 to 360
      public static function ang_rel(x1:Number, y1:Number,
                                     x2:Number, y2:Number) :Number
      {
         // Calculate the length to normalize <x1, y1> and <y1, -x1>
         var l:Number = Geometry.distance(x1, y1, 0, 0);

         // to prevent divide-by-zero
         if (y1 != 0) {
            // Returns the absolute angle of the transformed vector <x2, y2>'
            // which is [[y1/l, x1/l][-x1/l, y1/l]]^-1 * <x2, y2>
            return Geometry.arctan(
                     l * x2 / y1 - x1 * (x1 * x2 + y1 * y2) / (l * y1),
                     (x1 * x2 + y1 * y2) / l);
         }
         else if (x1 > 0) {
            // The appropriate transform of <x2, y2> if y1 == 0 and x1 > 0
            return Geometry.arctan(-y2, x2);
         }
         else if (x1 < 0) {
            // The appropriate transform of <x2, y2> if y1 == 0 and x1 < 0
            return Geometry.arctan(y2, -x2);
         }

         m4_ASSERT(false);
         // Return statement to make the compiler happy.
         return 0;
      }

      // Essentially Math.atan2 except:
      // Return angle in degrees in range [0, 360).
      public static function arctan(x:Number, y:Number) :Number
      {
         var a:Number = Geometry.rad_to_degree(Math.atan2(y, x));
         if (a < 0) {
            return a + 360.0;
         }
         else {
            return a;
         }
      }

      // Return the length of <x,y> projected onto <axis_x, axis_y>.
      // axis_len must be the length of the axis (passed in to save work).
      public static function axis_project(axis_x:Number, axis_y:Number,
                                          axis_len:Number,
                                          x:Number, y:Number) :Number
      {
         return (x * axis_x + y * axis_y) / axis_len;
      }

      // Utility function for rect_intersects that returns true if the
      // two rectangles overlap on the axis.
      protected static function axis_test(axis_x:Number, axis_y:Number,
                                          r1_xs:Array, r1_ys:Array,
                                          r2_xs:Array, r2_ys:Array) :Boolean
      {
         // | axis |
         var a_len:Number = Math.sqrt(axis_x * axis_x + axis_y * axis_y);

         var i:int;
         var t:Number;
         var max_r1:Number = Geometry.axis_project(axis_x, axis_y, a_len,
                                                   r1_xs[0], r1_ys[0]);
         var max_r2:Number = Geometry.axis_project(axis_x, axis_y, a_len,
                                                   r2_xs[0], r2_ys[0]);
         var min_r1:Number = max_r1;
         var min_r2:Number = max_r2;

         for (i = 1; i < 4; i++) {
            t = Geometry.axis_project(axis_x, axis_y, a_len,
                                      r1_xs[i], r1_ys[i]);
            if (t > max_r1) {
               max_r1 = t;
            }
            if (t < min_r1) {
               min_r1 = t;
            }
         }

         for (i = 1; i < 4; i++) {
            t = Geometry.axis_project(axis_x, axis_y, a_len,
                                      r2_xs[i], r2_ys[i]);
            if (t > max_r2) {
               max_r2 = t;
            }
            if (t < min_r2) {
               min_r2 = t;
            }
         }

         if (min_r1 <= min_r2) {
            return max_r1 >= min_r2;
         }
         else {
            return max_r2 >= min_r1;
         }
      }

      // Convert a string of text coordinates to parallel arrays of (x,y)
      // coordinates. xs and ys should be empty Arrays.
      public static function coords_string_to_xys(s:String,
                                                  xs:Array,
                                                  ys:Array) :void
      {
         var i:int;
         var poslist:Array;

         // In PostGIS >= 1.4, it adds the 'L' after first pair to conform to
         // the 'standard'.
         //    E.g.,    old SVG-style, 1234.56 7890.12 3456.78 89.012 ...
         //    E.g., newish SVG-style, 1234.56 7890.12 L 3456.78 89.012 ...
         //    E.g., proper SVG-style, M 1234.56 7890.12 L 3456.78 89.012 ... Z

         // BUG nnnn: The server stores and sends polygons with multiple
         //           interior rings. We should support them! Until then,
         //           just strip the second and subsequent interior rings.
         // Too simple: s = s.replace('M ', ''); // Remove leading M.
         //             s = s.replace(' Z', ''); // Remove trailing Z.
         var first_em:int = s.indexOf('M');
         if (first_em != -1) {
            // MAGIC_NUMBER: Add one to go past the 'M'
            first_em += 1;
         }
         else {
            first_em = 0;
         }
         var first_zee:int = s.indexOf('Z');
         if (first_zee == -1) {
            first_zee = s.length;
         }
         s = s.replace('L', ' '); // Remove 'L' delimiter.
         var em_to_zee:String = s.substring(first_em, first_zee);
         m4_TALKY('coords_string_to_xys: em_to_zee:', em_to_zee);
         poslist = em_to_zee.split(' ');
         m4_TALKY('coords_string_to_xys: poslist.length:', poslist.length);
         m4_TALKY('coords_string_to_xys: poslist:', poslist);

         // FIXME: HACK: This has something to do with s being empty or only
         //        containing whitespace.
         if (poslist.length == 1) {
            // EXPLAIN: This special case smells fishy to [lb]. What's up?
            //m4_WARNING('coords_string_to_xys: 1-len: s:', s);
            //m4_WARNING('coords_string_to_xys: poslist[0]:', poslist[0]);
            m4_ASSERT_SOFT(poslist[0] == '');
            poslist = [];
         }
         else if (poslist.length == 0) {
            m4_WARNING('coords_string_to_xys: 0-len: s:', s);
            m4_ASSERT_SOFT(false);
         }
         else {
            var nanless:Array = new Array();
            for each (var numb:String in poslist) {
               if (numb) {
                  nanless.push(numb);
               }
               else {
                  m4_WARNING('coords_string_to_xys: passing on:', numb);
               }
            }
            poslist = nanless;
            m4_TALKY('coords_string_to_xys: nanless: poslist:', poslist);
         }

         m4_ASSERT(xs.length == 0);
         m4_ASSERT(ys.length == 0);
         if ((poslist.length % 2) != 0) {
            m4_ERROR2('coords_string_to_xys: odd len:', poslist.length,
                      '/ s:', s);
            poslist.length = poslist.length - 1;
         }

         for (i = 0; i < poslist.length; i += 2) {
            var new_x:Number = Number(poslist[i]);
            if (isNaN(new_x)) {
               m4_WARNING('poslist[i]:', poslist[i])
            }
            m4_ASSERT_SOFT(!isNaN(new_x));
            xs.push(new_x);
            // FIXME Malformed server resp. will crash client? (i.e., list of
            //       odd-numbered size where i+1 DNE) -- Since this data come
            //       from the Net, we should double-check for consistency and
            //       recover gracefully (the ASSERT above is not sufficient)
            var new_y:Number = Number(poslist[i+1]);
            if (isNaN(new_y)) {
               m4_WARNING('poslist[i+1]:', poslist[i+1])
            }
            m4_ASSERT_SOFT(!isNaN(new_y));
            ys.push(new_y);
         }
      }

      // Convert parallel arrays of (x,y) coordinates to a string of text
      // coordinates.
      public static function coords_xys_to_string(xs:Array, ys:Array) :String
      {
         var i:int;
         var poslist:Array = new Array();

         for (i = 0; i < xs.length; i++) {
            poslist.push(xs[i], ys[i]);
         }

         return poslist.join(' ');
      }

      // Converts degrees to radians, no normalization.
      public static function degree_to_rad(deg:Number) :Number
      {
         return deg * Math.PI / 180.0;
      }

      // Return the distance between two points.
      public static function distance(x1:Number, y1:Number,
                                      x2:Number, y2:Number) :Number
      {
         return Math.sqrt((x1-x2)*(x1-x2) + (y1-y2)*(y1-y2));
      }

      // Returns the longest leg of the right triangle formed between two
      // points, which are passed as four int coordinates.
      public static function distance_longest_leg(x1:int, y1:int,
                                                  x2:int, y2:int) :int
      {
         m4_ASSERT(false); // This fcn. isn't used.
                           // FIXME: Is this quicker than Geometry.distance()?
         var leg_x:int = Math.abs(x2 - x1);
         var leg_y:int = Math.abs(y2 - y1);
         return (leg_x < leg_y) ? leg_y : leg_x;
      }

      // Return an indicative distance of point from line segment. Sign
      // indicates the side and magnitude is an indication of the distance.
      public static function distance_indicative(start:Point,
                                                 end:Point,
                                                 p:Point) :Number
      {
         //m4_VERBOSE('distance_indicative');
         return ((end.y - start.y) * (start.x - p.x) -
                 (end.x - start.x) * (start.y - p.y));
      }

      // Return the distance between point (x,y) and line segment (xa,ya) to
      // (xb,yb). Returns NaN if a perpendicular from (x,y) to the line
      // falls outsite the line segment.
      //
      // Source:
      // http://www.topcoder.com/tc?module=Static&d1=tutorials&d2=geometry1
      public static function distance_point_line(x:Number, y:Number,
                                                 xa:Number, ya:Number,
                                                 xb:Number, yb:Number) :Number
      {
         var a:Point = new Point(xa, ya);  // 1st endpoint of line segment
         var b:Point = new Point(xb, yb);  // 2nd endpoint of line segment
         var c:Point = new Point(x, y);    // find distance to this point

         // check for non-perpendicularity
         if ((Geometry.dotx(a, b, c) < 0) || (Geometry.dotx(b, a, c) < 0)) {
            return NaN;
         }

         // distance to _line_ defined by segment
         return (Math.abs((xb-xa)*(ya-y) - (xa-x)*(yb-ya))
                 / Geometry.distance(xa, ya, xb, yb));
      }

      // Return the dot product: ab . bc
      public static function dotx(a:Point, b:Point, c:Point) :Number
      {
         var ab:Point = new Point(b.x - a.x, b.y - a.y);
         var ac:Point = new Point(c.x - a.x, c.y - a.y);
         return (ab.x * ac.x + ab.y * ac.y);
      }

      // Return the linear interpolation.
      public static function interpolate(x0:Number, y0:Number,
                                         x1:Number, y1:Number,
                                         x:Number) :Number
      {
         return y0 + (x - x0) * (y1 - y0) / (x1 - x0);
      }

      // Return intersection point of two lines.
      public static function intersection_lines(start1:Point,
                                                end1:Point,
                                                start2:Point,
                                                end2:Point) :Point
      {
         var result:Point = new Point();
         var u:Number;

         u = (((end2.x - start2.x) * (start1.y - start2.y)
               - (end2.y - start2.y) * (start1.x - start2.x))
              / ((end2.y - start2.y) * (end1.x - start1.x)
                 - (end2.x - start2.x) * (end1.y - start1.y)));

         result.x = start1.x + u * (end1.x - start1.x);
         result.y = start1.y + u * (end1.y - start1.y);

         return result;
      }

      // Return intersection point of two line segments.
      public static function intersection_segments(start1:Point,
                                                   end1:Point,
                                                   start2:Point,
                                                   end2:Point) :Point
      {
         m4_VERBOSE('intersection_segments');
         if (Geometry.opposite_side(start1, end1, start2, end2)
             && Geometry.opposite_side(start2, end2, start1, end1)) {
            return Geometry.intersection_lines(start1, end1, start2, end2);
         }

         return null;
      }

      // Return intersection point of a line and a segment.
      public static function intersection_line_seg(seg_start:Point,
                                                   seg_end:Point,
                                                   line_p1:Point,
                                                   line_p2:Point) :Point
      {
         m4_VERBOSE('intersection_line_seg');
         var pt:Point = null;
         if (Geometry.opposite_side(line_p1, line_p2, seg_start, seg_end)) {
            pt = Geometry.intersection_lines(line_p1, line_p2,
                                             seg_start, seg_end);
         }
         return pt;
      }

      //
      public static function line_offset_point(xy:Point,
                                               line_slope:Number,
                                               offset:Number) :Point
      {
         // Make the offset vector. If 0,0 is the origin and you want a
         // vector that is offset units long, y = mx + b where b = 0, so
         // y = mx. By the Pythagorean Th., offset = sqrt(x * x + y * y).
         // Or, offset = sqrt(x^2 + (m*x)^2)
         //            = sqrt(x^2 + (m^2)*(x^2))
         //            = sqrt(x^2*(1 + m^2))
         //     offset = x * sqrt(1 + m^2)
         // such that x = offset / sqrt(1 + m^2), and y = mx.
         // Then you can just add the offset vector to the point vector.
         if (line_slope == 0) {
            xy.x = offset;
            xy.y = 0;
         }
         else if (isNaN(line_slope)) {
            xy.x = 0;
            // FIXME: Using minus just to test something... really, we need to
            //        figure out the direction of the road and the side of the
            //        bike lane....
            xy.y = offset;
         }
         else {
            xy.x = offset / Math.sqrt(1 + line_slope * line_slope);
            xy.y = line_slope * xy.x;
         }
         return xy;
      }

      //
      public static function line_slope_perp(x1:Number, y1:Number,
                                             x2:Number, y2:Number) :Number
      {
         var m:Number = NaN;
         // FIXME: MAGIC NUMBERS: Precision!
         // FIXME: Is the signage herein correct?
         // FIXME: Signage depends on direction of edge, otherwise always same
         if (Math.abs(x2 - x1) < 0.01) {
            // Vertical, so perp is horizontal.
            m = 0;
            // FIXME: +/-0?
         }
         else if (Math.abs(y2 - y1) < 0.01) {
            // Horizontal, so perp is vertical.
            m = NaN;
            // FIXME: +/-NaN?
         }
         else {
            m = (y2 - y1) / (x2 - x1);
            m = (-1.0 / m);
         }
         return m
      }

      // See:
      //  http://flexdevtips.blogspot.com/2010/01/drawing-dashed-lines-and-cubic-curves.html
      //
      // "Calculates the point along the linear line at the given "time" t
      //  (between 0 and 1). Formula came from
      //   http://en.wikipedia.org/wiki/B%C3%A9zier_curve#Linear_B.C3.A9zier_curves
      //
      //  @param t the position along the line [0, 1]
      //  @param start the starting point
      //  @param end the end point"
      //
      // Was named getLinearValue. This is basically a m-value lookup.
      //
      // Wait, what about Point.interpolate(pt1:Point, pt2:Point, f:Number) ?
      /*
      public static function m_value_at(t:Number, start:Point, end:Point)
         :Point
      {
         t = Math.max(Math.min(t, 1.0), 0.0);
         var x:Number = start.x + (t * (end.x - start.x));
         var y:Number = start.y + (t * (end.y - start.y));
         return new Point(x, y);    
      }
      */

      // Expand the given rectangle to include the point. The point and
      // rectangle must be in the same coordinate system. Return the expanded
      // rect. If rect is null, return a new rectangle sized for the point.
      public static function merge_point(rect:Rectangle,
                                         mx:int, my:int) :Rectangle
      {
         if (rect === null) {
            // new rect
            rect = new Rectangle();
            rect.x = mx;
            rect.y = my;
            rect.width = 0;
            rect.height = 0;
         }
         else {
            // expand the rect
            if (mx < rect.x) {
               rect.width += (rect.x - mx);
               rect.x = mx;
            }
            else if (rect.right < mx) {
               rect.width += (mx - rect.right);
            }

            if (my < rect.y) {
               rect.height += (rect.y - my);
               rect.y = my;
            }
            else if (rect.bottom < my) {
               rect.height += (my - rect.bottom);
            }
         }
         return rect;
      }

      // MAYBE: This is from [ml]'s route sharing, but it was never used.
      public function miles_to_meters_str(len:String) :String
      {
         if ((len === null) || (len == '')) {
            return null;
         }
         else {
            return '' + (Number(len) * 1609.344);
         }
      }

      // Return true if two points are on the opposite sides of line from the
      // point 'start' to the point 'end'.
      public static function opposite_side(start:Point, end:Point,
                                           p1:Point, p2:Point) :Boolean
      {
         m4_VERBOSE('opposite_side');

         var side_p1:Number = Geometry.distance_indicative(start, end, p1);
         var side_p2:Number = Geometry.distance_indicative(start, end, p2);

         // If side_p1 and side_p2 are of the different sign then opp sides.
         if (side_p1 * side_p2 < 0) {
            return true;
         }

         return false;
      }

      // This fcn. was added for route manip.
      //
      // Compute the projected location of the point (px, py) onto the
      // line segment from (xa, ya) to (xb, yb).
      //
      // The point is stored in the result array, true is returned if the
      // projected point falls within the line segment's boundaries, and false
      // is returned otherwise. If false is returned, the result holds the
      // projected point on the line falling outside of the segment's edges.
      //
      public static function project(px:Number,
                                     py:Number,
                                     xa:Number,
                                     ya:Number,
                                     xb:Number,
                                     yb:Number,
                                     result:Array,
                                     tolerance:Number=0.0)
                                       :Boolean
      {
         var seg_len:Number = Geometry.distance(xa, ya, xb, yb);
         var scale:Number = ((xb - xa) * (px - xa) + (yb - ya) * (py - ya))
                            / (seg_len * seg_len);
         result[0] = xa + scale * (xb - xa);
         result[1] = ya + scale * (yb - ya);

         return ((scale >= -tolerance) && (scale <= (1.0 + tolerance)));
      }

      // Return true if the point p is inside the polygon (xs, ys).
      // http://en.wikipedia.org/wiki/Point_in_polygon#Ray_casting_algorithm
      public static function pt_in_poly(xs:Array, ys:Array, p:Point) :Boolean
      {
         m4_VERBOSE('pt_in_poly');

         var result:Boolean = false;
         var i:int;

         for (i = 0; i < xs.length - 1; i++) {
            if (Geometry.intersection_segments(
                              new Point(xs[i], ys[i]),
                              new Point(xs[i + 1], ys[i + 1]),
                              p,
                              new Point(Number.POSITIVE_INFINITY, p.y))
                !== null) {
               result = !result;
            }
         }

         return result;
      }

      // Converts radians to degrees, no normalization.
      public static function rad_to_degree(rad:Number) :Number
      {
         return rad * 180.0 / Math.PI;
      }

      // Use the separating axis theorem to test intersection between
      // the rectangles r1 and r2.  Return true if they intersect.
      //
      // The two arrays for each rectangle are the coordinates of the
      // four corners such that 0-1, 1-2, 2-3, and 3-0 form the edges.
      public static function rect_intersects(r1_xs:Array, r1_ys:Array,
                                             r2_xs:Array, r2_ys:Array) :Boolean
      {
         return (
               Geometry.axis_test(r1_xs[1] - r1_xs[0], r1_ys[1] - r1_ys[0],
                                  r1_xs, r1_ys, r2_xs, r2_ys)
            && Geometry.axis_test(r1_xs[3] - r1_xs[0], r1_ys[3] - r1_ys[0],
                                  r1_xs, r1_ys, r2_xs, r2_ys)
            && Geometry.axis_test(r2_xs[1] - r2_xs[0], r2_ys[1] - r2_ys[0],
                                  r1_xs, r1_ys, r2_xs, r2_ys)
            && Geometry.axis_test(r2_xs[3] - r2_xs[0], r2_ys[3] - r2_ys[0],
                                  r1_xs, r1_ys, r2_xs, r2_ys));
      }

      // Normalize the line segment [[x1, x2], [y1, y2]] to length l and
      // return the modified segment.
      public static function vector_normalized(xys:Array, l:Number) :Array
      {
         var x1:Number = xys[0][0];
         var y1:Number = xys[1][0];
         var x2:Number = xys[0][1];
         var y2:Number = xys[1][1];
         var len_factor:Number = l / Geometry.distance(x1, y1, x2, y2);

         return [[x1, x1 + (x2 - x1) * len_factor],
                 [y1, y1 + (y2 - y1) * len_factor]];
      }

   }
}


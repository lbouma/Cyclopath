/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Helpers for directly drawing on the canvas.

package views.base {

   import flash.display.*;
   import flash.display.Graphics;
   import flash.geom.*;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.text.TextLineMetrics;
   import mx.core.UIComponent;

   import utils.geom.Geometry;
   import utils.misc.Logging;

   // Not sure what to call this class. And 'Draw' is taken.
   public class Paint {

      protected static var log:Logging = Logging.get_logger('MC!PAINT');

      // *** Constructor

      //
      public static function arrow_draw(g:Graphics,
                                        sx:Number,
                                        sy:Number,
                                        ex:Number,
                                        ey:Number,
                                        tipsize:int,
                                        arrow_color:int,
                                        alpha:Number=1.0,
                                        skip_end:Number=0) :void
      {
         var dx:Number = ex - sx;
         var dy:Number = ey - sy;
         var d:Number = Geometry.distance(dx, dy, 0, 0);
         // normalize
         dx /= d;
         dy /= d;
         if (skip_end > d) {
            skip_end = d / 2;
         }
         var px:Number = ex - (dx * skip_end);
         var py:Number = ey - (dy * skip_end);
         Paint.arrow_tip_draw(g, px, py, dx, dy, tipsize, tipsize, arrow_color,
                              alpha);
         g.lineStyle(1.5, arrow_color, alpha);
         g.moveTo(sx, sy);
         g.lineTo(ex - dx * (skip_end + tipsize),
                  ey - dy * (skip_end + tipsize));
      }

      // Draws an arrow tip with its tip at (px, py) pointing in direction
      // (dx, dy) that is length long and width wide. dx and dy don't have to
      // be normalized before hand.
      //
      // NOTE: this is just the tip of an arrow, there is no tail included.
      //
      // WARNING: make sure to draw the tip before the line, or keep the tip
      // in a child sprite of the line, or the flash fill bug occurs.
      public static function arrow_tip_draw(g:Graphics,
                                            px:Number, py:Number,
                                            dx:Number, dy:Number,
                                            arrow_length:Number,
                                            arrow_width:Number,
                                            arrow_color:int,
                                            alpha:Number=1.0,
                                            sharp_corners:Boolean=true) :void
      {
         // normalize (dx, dy), just in case
         var d:Number = Geometry.distance(dx, dy, 0, 0);
         dx /= d;
         dy /= d;

         g.lineStyle(1, arrow_color, alpha, false, 'normal', 'none',
                     (sharp_corners ? 'miter' : 'round'));
         g.beginFill(arrow_color, alpha);
         g.moveTo(px, py);
         g.lineTo(px - (arrow_length * dx) - (arrow_width * dy) / 2,
                  py - (arrow_length * dy) + (arrow_width * dx) / 2);
         g.lineTo(px - (arrow_length * dx) + (arrow_width * dy) / 2,
                  py - (arrow_length * dy) - (arrow_width * dx) / 2);
         g.lineTo(px, py);
         g.endFill();
      }

      // Return the packed interpolation of two colors.
      public static function color_interpolate(r1:int, g1:int, b1:int,
                                               r2:int, g2:int, b2:int,
                                               min:Number, max:Number,
                                               value:Number) :int
      {
         m4_ASSERT(false); // This fcn. is not used by anyone. Not that it's
                           // broken, or anything...
         return ( // red:
                  (int(Geometry.interpolate(min, r1, max, r2, value)) << 16)
                  // green:
                + (int(Geometry.interpolate(min, g1, max, g2, value)) <<  8)
                  // blue:
                + (int(Geometry.interpolate(min, b1, max, b2, value))));
      }

      // Draw a line on the given Graphics object. xs and ys are in map
      // coordinates. This fcn. can also draw a line parallel to the one
      // specified by xs and ys by using the offset parameter.
      public static function line_draw(gr:Graphics,
                                       xs:Array,
                                       ys:Array,
                                       line_width:Number,
                                       line_color:int,
                                       // Note that alpha doesn't always work;
                                       // for Geofeature's set sprite.alpha
                                       // instead.
                                       alpha:Number=1.0,
                                       caps:Boolean=true,
                                       elbow_size:Number=0.0,
                                       offset:Number=0.0,
                                       // 2013.05.03: [lb] is hungry for more
                                       // opts. Should we make a sttgs Object?
                                       // Also, see [ml]'s line_draw_dashed....
                                       dashed:Boolean=false,
                                       nodash_color:*=null,
                                       dashon_interval:int=0,
                                       nodash_interval:int=0,
                                       interval_square:Boolean=false,
                                       skip_transform:Boolean=false) :void
      {
         var i:int;
         var x:Number;
         var y:Number;
         var ready:Boolean = false;
         var last_perp_slope:Number;
         var next_perp_slope:Number;
         var offset_pt1:Point = new Point();
         var offset_pt2:Point = new Point();
         var xb:Number;
         var yb:Number;
         var last_pt:Point;
         var next_pt:Point;
         var dash_open:Boolean = true;
         //var dash_tank:Number = dashon_interval;
         var dash_tank:Number = dashon_interval / 2.0;

         m4_ASSURT((!dashed) || (dashon_interval > 0));

         if (interval_square) {
            dashed = true;
            dashon_interval = line_width;
            // Okay, so it's not *quite* square.
            nodash_interval = int(line_width * 0.80);
            dash_tank = dashon_interval;
         }

         // MAYBE: Force-disable caps if dashed, since what's rendered looks
         // like chevrons, and we don't want to imply that there's something
         // directional happening.
         if ((dashed) && (caps)) {
            m4_WARNING('Cannot use dashed caps unless you fix directionality');
            caps = false;
         }

         var halfset:Number = offset / 2.0;

         m4_ASSERT(elbow_size == 0); // I don't think this is used...
         // elbows must be drawn first to avoid Flex fill bug
         if (elbow_size > 0) {
            gr.lineStyle(0, line_color);
            for (i = 0; i < xs.length; i++) {
               var xs_i:int = xs[i];
               var ys_i:int = ys[i];
               if (!skip_transform) {
                  xs_i = G.map.xform_x_map2cv(xs_i);
                  xs_i = G.map.xform_x_map2cv(ys_i);
               }
               gr.beginFill(line_color, alpha);
               gr.drawRect(xs_i - elbow_size/2,
                           ys_i - elbow_size/2,
                           elbow_size,
                           elbow_size);
               gr.endFill();
            }
         }

         gr.lineStyle(line_width, line_color, alpha, false, 'normal',
                      (caps ? 'round' : 'none'));

         x = xs[0];
         y = ys[0];
         if (!skip_transform) {
            x = G.map.xform_x_map2cv(x);
            y = G.map.xform_y_map2cv(y);
         }

         m4_VERBOSE2('G.map.xform_x_map2cv:',
                     '/ xs[0]:', xs[0], 'xy[0]:', ys[0], '/ x:', x, 'y:', y);

         // MAYBE: Offset does not work so well -- what we really want is to
         //        bisect the angle formed by three points (the last, current,
         //        and next points), rather than just moving perpendicular to
         //        the current point. This is because, where the line bends,
         //        the offset line ends up drawing over our normal line.
         // MAYBE: For the last comment to be implemented well, we might want
         //        to coalesce adjacent line segments so that, if there's an
         //        angle formed other than 180 degrees where two line segments
         //        meet, than we draw the offset line appropriately.
         if (offset != 0) {
            next_pt = Paint.line_draw_get_offset_beginning(
                        1, xs, ys, x, y, offset, halfset,
                        offset_pt1, offset_pt2,
                        last_perp_slope, next_perp_slope,
                        skip_transform);
         }
         else {
            next_pt = new Point(x, y);
         }

         gr.moveTo(next_pt.x, next_pt.y);
         last_pt = next_pt;

         for (i = 1; i < xs.length; i++) {

            x = xs[i];
            y = ys[i];
            if (!skip_transform) {
               x = G.map.xform_x_map2cv(x);
               y = G.map.xform_y_map2cv(y);
            }

            //m4_VERBOSE2('G.map.xform_x_map2cv:', '/ xs[i]:', xs[i],
            //            'xy[i]:', ys[i], '/ x:', x, 'y:', y);

            if (offset != 0) {
               next_pt = Paint.line_draw_get_offset_intermediate(
                           i+1, xs, ys, x, y, offset, halfset,
                           offset_pt1, offset_pt2,
                           last_perp_slope, next_perp_slope,
                           skip_transform);
            }
            else {
               next_pt = new Point(x, y);
            }

            if (!dashed) {
               gr.lineTo(next_pt.x, next_pt.y);
            }
            else {
               // If we're dashing and using a non-dash color, draw the
               // non-dash color first, rather than alternating between drawing
               // the dash color and non-dash color -- the latter doesn't work
               // well because interpolating x,y and how that translates to
               // pixel coordinates. We experience less noticeable artifacts if
               // we draw the non-dash color as the background.
               if (nodash_color !== null) {
                  // [lb] tried gr.lineGradientStyle(GradientType.LINEAR...)
                  // but the gradient looks too hippy and it is always the same
                  // direction, i.e., it doesn't change director for diagonal
                  // roads so it looks like background wallpaper bleeding
                  // through.
                  gr.lineStyle(line_width, nodash_color, alpha, false,
                               'normal', (caps ? 'round' : 'none'));
                  gr.lineTo(next_pt.x, next_pt.y);
                  gr.lineStyle(line_width, line_color, alpha, false,
                               'normal', (caps ? 'round' : 'none'));
                  gr.moveTo(last_pt.x, last_pt.y);
               }
               // MAYBE: Individual line segment's dashes look nice but
               //        they don't space automatically across intersections...
               //        so we might have to coalesce line segments? make a
               //        lookup of line segments that need the dashed ornament
               //        and then order them geometrically and then draw
               //        them... what a tedious solution....
               var dashing:Boolean = true;
               var dist_traveling:Number;
               var dist_remaining:Number;
               dist_traveling = Point.distance(last_pt, next_pt);
               dist_remaining = dist_traveling;
               if ((last_pt == next_pt) || (!dist_traveling)) {
                  m4_WARNING('line_draw: Ignoring last_pt == next_pt');
                  dashing = false;
               }
               while (dashing) {
                  if (dash_tank >= dist_remaining) {
                     // There's more dash than the dist. to the next point.
                     gr.lineTo(next_pt.x, next_pt.y);
                     dashing = false;
                     //
                     dash_tank -= dist_remaining;
                     dist_remaining = 0;
                  }
                  else {
                     var travel_to:Point;
                     // We'll complete the dash before getting to next point.
                     dist_remaining -= dash_tank;
                     // Find the next intermediate point. The closer f is to 0,
                     // the closer the result is to the second point.
                     var m_value:Number = dist_remaining / dist_traveling;

                     // MAYBE: Geometry.m_value_at returns a markedly different
                     //        answer than Point.interpolate. Why?!
                     // travel_to = Geometry.m_value_at(
                     //       m_value, last_pt, next_pt);
                     // m4_DEBUG2('line_draw: Geometry says: m_value:',
                     //           m_value, '/ travel_to:', String(travel_to));
                     travel_to = Point.interpolate(last_pt, next_pt, m_value);
                     // m4_DEBUG2('line_draw: Point says: m_value:', m_value,
                     //           '/ travel_to:', String(travel_to));

                     if (!dash_open) {
                        gr.moveTo(travel_to.x, travel_to.y);
                     }
                     else {
                        gr.lineTo(travel_to.x, travel_to.y);
                     }
                     //
                     dash_tank = 0;
                  }
                  if (!dash_tank) {
                     //dash_tank = dashon_interval;
                     dash_open = !dash_open;
                     if (dash_open) {
                        dash_tank = dashon_interval;
                     }
                     else {
                        dash_tank = nodash_interval;
                     }
                     //m4_DEBUG('line_draw: dash_tank:', dash_tank);
                  }
                  var use_color:int = line_color;
                  if ((!dash_open) && (nodash_color !== null)) {
                     use_color = nodash_color;
                  }

               } // while: dashing
            } // else: dashed

            last_perp_slope = next_perp_slope;
            last_pt = next_pt;
         }
      }

      //
      protected static function line_draw_get_offset_beginning(
         pt_i:int,
         xs:Array, ys:Array, x:Number, y:Number,
         offset:Number, halfset:Number,
         offset_pt1:Point, offset_pt2:Point,
         last_perp_slope:Number, next_perp_slope:Number,
         skip_transform:Boolean)
            :Point
      {
         var xb:Number = xs[pt_i];
         var yb:Number = ys[pt_i];
         if (!skip_transform) {
            xb = G.map.xform_x_map2cv(xb);
            yb = G.map.xform_y_map2cv(yb);
         }
         // MAYBE: Always use the point to the left?
         if (x <= xb) {
            last_perp_slope = Geometry.line_slope_perp(x, y, xb, yb);
         }
         else {
            last_perp_slope = Geometry.line_slope_perp(xb, yb, x, y);
         }
         Geometry.line_offset_point(offset_pt1, last_perp_slope, offset);
         //m4_VERBOSE2('Geometry.line_offset_point: x1:', offset_pt1.x,
         //            '/ y1:', offset_pt1.y);
         x += offset_pt1.x;
         y += offset_pt1.y;
         return new Point(x, y);
      }

      //
      protected static function line_draw_get_offset_intermediate(
         pt_i:int,
         xs:Array, ys:Array, x:Number, y:Number,
         offset:Number, halfset:Number,
         offset_pt1:Point, offset_pt2:Point,
         last_perp_slope:Number, next_perp_slope:Number,
         skip_transform:Boolean)
            :Point
      {
         var xb:Number;
         var yb:Number;
         if (pt_i < xs.length) {
            // FIXME: Store as next so you don't calculate each twice.
            xb = xs[pt_i];
            yb = ys[pt_i];
            if (!skip_transform) {
               xb = G.map.xform_x_map2cv(xb);
               yb = G.map.xform_y_map2cv(yb);
            }
            // Always use the point to the left?
            if (x <= xb) {
               next_perp_slope = Geometry.line_slope_perp(x, y, xb, yb);
            }
            else {
               next_perp_slope = Geometry.line_slope_perp(xb, yb, x, y);
            }
            Geometry.line_offset_point(offset_pt1, last_perp_slope,
                                       halfset);
            Geometry.line_offset_point(offset_pt2, next_perp_slope,
                                       halfset);
            //m4_DEBUG3('Geometry.line_offset_point: x+:',
            //          offset_pt1.x + offset_pt2.x,
            //          '/ y+:', offset_pt1.y + offset_pt2.y);
            x += offset_pt1.x + offset_pt2.x;
            y += offset_pt1.y + offset_pt2.y;
         }
         else {
            Geometry.line_offset_point(offset_pt1, last_perp_slope,
                                       offset);
            m4_VERBOSE2('Geometry.line_offset_point: xn:', offset_pt1.x,
                        '/ yn:', offset_pt1.y);
            x += offset_pt1.x;
            y += offset_pt1.y;
         }
         return new Point(x, y);
      }

      // Draw a dashed line on the given Graphics object from (cx1, cy1) to
      // (cx2, cy2). These points are in canvas coordinates.
      // 2013.03.04: This is so far just used on a route that's being edited.
      public static function line_draw_dashed(gr:Graphics,
                                              segment_len:Number,
                                              cx1:Number,
                                              cy1:Number,
                                              cx2:Number,
                                              cy2:Number,
                                              line_width:Number,
                                              line_color:int,
                                              alpha:Number=1.0,
                                              caps:Boolean=true) :void
      {
         var dx:Number = cx2 - cx1;
         var dy:Number = cy2 - cy1;

         var line_len:Number = Math.sqrt(dx * dx + dy * dy);
         // FIXME: MAGIC_NUMBER. This hould probably match Ccp's precision,
         //                      which is 0.01 (1 cm).
         if (line_len < 0.0001) {
            return; // don't draw a line that doesn't go anywhere
         }

         var segdx:Number = dx * segment_len / line_len;
         var segdy:Number = dy * segment_len / line_len;
         var dash_count:int = Math.floor(line_len / (2 * segment_len));

         var x:Number = cx1;
         var y:Number = cy1;
         var remainder:Number = line_len - (2 * segment_len * dash_count);

         gr.lineStyle(line_width, line_color, alpha, false, 'normal',
                      (caps ? 'round' : 'none'));

         gr.moveTo(x, y);
         //
         for (var i:int = 0; i < dash_count; i++) {
            //
            x += segdx;
            y += segdy;
            gr.lineTo(x, y);
            //
            x += segdx;
            y += segdy;
            gr.moveTo(x, y);
         }

         if (remainder >= segment_len) {
            x += segdx;
            y += segdy;
            gr.lineTo(x, y);
         }
         else {
            gr.lineTo(cx2, cy2);
         }
      }

      // This is a helper function used to display blocks of multi-line
      // text properly.  The resizing and measuring functions in Flex don't
      // allow for multi-line or don't update the required fields soon enough,
      // so we wrote our own to be used when we need the measurments asap.
      // Namely, this is necessary for the TextArea's in Route_Direction_Panel
      // to be resized each time.
      // Input:
      //          text      - The string to measure
      //          owner     - The UIComponent to grab text rendering properties
      //                      from. Generally, will be the component that holds
      //                      the measured text
      //          pen_width - The maximum width of a single line of text
      // Return the height that the component must be to display all of
      // the text.
      //
      // NOTE: This algorithm isn't perfect and there seem to be discrepencies
      // between the size reported by measureText() and how a component
      // naturally lays out its text.  Because of this, this method works
      // best with text around 1-4 lines long (beyond this and the height is
      // greater than needed by small amounts).
      public static function measure_text_height(text:String,
                                                 owner:UIComponent,
                                                 width:int) :int
      {
         var words:Array = text.split(' ');
         var word:String;
         var letters:Array;
         var letter:String;

         var curr_width:Number = 0;
         var m:TextLineMetrics = owner.measureText(' ');
         var space_width:Number = m.width + 1;
         var height:Number = m.height;

         // adjust width to give us some extra fudge space, an extra line
         // is nicer than chopped off text.
         width -= space_width;

         for each (word in words) {
            // measure the word
            m = owner.measureText(word);

            if (curr_width + m.width < width) {
               // The word fits on the line, so adjust our current position
               curr_width += m.width + space_width;
            }
            else if (m.width < width) {
               // The word can't fit on current line, so move down a line
               height += (m.height + m.leading);
               curr_width = m.width + space_width;
            }
            else {
               // The word can't fit on any line so start splitting the letters
               letters = word.split('');
               for each (letter in letters) {
                  m = owner.measureText(letter);
                  if (m.width + curr_width < width) {
                     // Still on the line, move the width over
                     curr_width += m.width;
                  }
                  else {
                     // Hit the end of a line, move down
                     height += (m.height + m.leading);
                     curr_width = m.width;
                  }
               }
               // Add a space at the end so that curr_width is correct for
               // the next word
               curr_width += space_width;
            }
         }

         return height;
      }

   }
}


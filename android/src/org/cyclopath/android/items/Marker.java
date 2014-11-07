/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Conf;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.util.PointD;

import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.util.FloatMath;

/**
 * Class that represents Markers that point to Geofeatures.
 * @author Fernando Torre
 */
public class Marker implements Feature {
   
   /** the geofeature that this marker points to */
   public Geofeature geo;
   /** the coordinates we are pointing to */
   private PointD target;
   /** the text that will go inside the marker */
   private String text;
   /** Whether this marker is currently pressed */
   public boolean pressed;
   /** computed marker height */
   public float height;
   /** computed marker width */
   public float width;
   
   /**
    * Constructs a Marker given the geofeature that it is pointing to and the
    * location where the tap occurred.
    * @param g
    * @param tap_location
    */
   public Marker(Geofeature g, PointD tap_location) {
      this.geo = g;
      this.pressed = false;
      
      // get marker text
      this.text = this.geo.getLabelText();
      if (this.text == null || this.text == "") {
         this.text =
            String.format(G.app_context.getString(R.string.direction_unnamed),
                          Conf.geofeature_layer_by_id.get(g.gfl_id));
      }
      if (text.length() > Constants.MAX_MARKER_LABEL_LEN) {
         this.text = this.text.substring(0, Constants.MAX_MARKER_LABEL_LEN - 2)
                     + "...";
      }
      this.text = this.text + " >";

      // calculate text bounds
      float density = G.app_context.getResources().getDisplayMetrics().density;
      Paint p = new Paint();
      p.setTextSize(Constants.MARKER_TEXT_SIZE * density);
      p.setTextAlign(Paint.Align.CENTER);
      p.setTypeface(Typeface.DEFAULT_BOLD);
      p.setAntiAlias(true);
      Rect r = new Rect();
      p.getTextBounds(this.text, 0, this.text.length(), r);
      this.height = Constants.MARKER_DEFAULT_HEIGHT * density;
      this.width =
            Math.max(Constants.MARKER_DEFAULT_WIDTH * density,
                     r.width()
                        + Constants.MARKER_DEFAULT_WIDTH_BUFFER * density);
      
      // get closest point in geometry to tap location
      double shortest_dist = -1;
      if (g.xys.size() == 1) {
         this.target = g.xys.get(0);
      } else {
         double dist;
         double seg_len;
         double scale;
         for (int i = 0; i < g.xys.size() - 1; i++) {
            PointD p1 = g.xys.get(i);
            PointD p2 = g.xys.get(i + 1);
            
            if (shortest_dist < 0) {
               shortest_dist = G.distance(p1, tap_location);
               this.target = p1;
            }
            seg_len = G.distance(p1, p2);
            scale = ((p2.x - p1.x) * (tap_location.x - p1.x)
                      + (p2.y - p1.y) * (tap_location.y - p1.y))
                    / (seg_len * seg_len);
            if (scale <= 0) {
               // get distance to start
               dist = G.distance(p1, tap_location);
               if (dist < shortest_dist) {
                  shortest_dist = dist;
                  this.target = p1;
               }
            } else if (scale >= 1) {
               // get distance to end
               dist = G.distance(p2, tap_location);
               if (dist < shortest_dist) {
                  shortest_dist = dist;
                  this.target = p2;
               }
            } else {
               // get distance to new point
               PointD result = new PointD(p1.x + scale * (p2.x - p1.x),
                     p1.y + scale * (p2.y - p1.y));
               dist = G.distance(result, tap_location);
               if (dist < shortest_dist) {
                  shortest_dist = dist;
                  this.target = result;
               }
            }
         }
      }
      
      
   }

   /** No-op */
   @Override
   public void cleanup() {}

   /**
    * Draws this marker on the map.
    */
   @Override
   public void draw() {

      int canvas_x = G.map.xform_x_map2cv(this.target.x);
      int canvas_y = G.map.xform_y_map2cv(this.target.y);
      
      this.drawMarkerBox(canvas_x, canvas_y,
                         this.height, this.width,
                         Constants.MARKER_BORDER_WIDTH, Color.BLACK);

      if (this.pressed) {
         this.drawMarkerBox(canvas_x, canvas_y,
                            this.height, this.width,
                            0, Color.DKGRAY);
      } else {
         this.drawMarkerBox(canvas_x, canvas_y,
                            this.height, this.width,
                            0, Color.WHITE);
      }

      // This is a hack, but it seems to work well for multiple font sizes.
      int fix =
         Math.round(FloatMath.ceil((Constants.MARKER_TEXT_SIZE/3+1)
               *G.app_context.getResources().getDisplayMetrics().density));
      G.map.drawLabel(canvas_x,
                      Math.round(canvas_y - Constants.MARKER_POINTER_HEIGHT
                                 - (height/2) + fix),
                      this.text, Constants.MARKER_TEXT_SIZE , 0);
   }
   
   /**
    * Draws the "dialog box" for this marker.
    * @param x
    * @param y
    * @param height
    * @param width
    * @param border_width
    * @param color
    */
   public void drawMarkerBox(int x, int y,
                             float height, float width,
                             int border_width, int color) {
      ArrayList<PointD> xys = new ArrayList<PointD>();
      xys.add(new PointD(x - (width / 2) - border_width,
                         y - Constants.MARKER_POINTER_HEIGHT
                           - height - border_width));
      xys.add(new PointD(x + (width / 2) + border_width,
                         y - Constants.MARKER_POINTER_HEIGHT
                           - height - border_width));
      xys.add(new PointD(x + (width / 2) + border_width,
                         y - Constants.MARKER_POINTER_HEIGHT + border_width));
      xys.add(new PointD(x + (Constants.MARKER_POINTER_WIDTH/2) + border_width,
                         y - Constants.MARKER_POINTER_HEIGHT + border_width));
      xys.add(new PointD(x,
                         y + border_width));
      xys.add(new PointD(x - (Constants.MARKER_POINTER_WIDTH/2) - border_width,
                         y - Constants.MARKER_POINTER_HEIGHT + border_width));
      xys.add(new PointD(x - (width / 2) - border_width,
                         y - Constants.MARKER_POINTER_HEIGHT + border_width));
      G.map.drawPolygonCanvas(xys, color);
   }

   /** No-op */
   @Override
   public void drawShadow() {}

   /**
    * Computes the bbox in map coordinates (only for the main marker box
    * rectangle)
    */
   @Override
   public RectF getBboxMap() {
      
      RectF bbox = new RectF();
      // Top and bottom are inverted, because canvas y coordinates are in
      // the opposite direction to map y coordinates
      bbox.top = (float) (this.target.y
            + G.map.xform_scalar_cv2map(Constants.MARKER_POINTER_HEIGHT));
      bbox.bottom = (float) (this.target.y
            + G.map.xform_scalar_cv2map(Math.round(
                  Constants.MARKER_POINTER_HEIGHT + this.height)));
      bbox.left = (float) (this.target.x
            - G.map.xform_scalar_cv2map(Math.round(this.width/2)));
      bbox.right = (float) (this.target.x
            + G.map.xform_scalar_cv2map(Math.round((this.width))/2));
      return bbox;
   }

   /** Returns the Map_Layer on which this object is drawn*/
   @Override
   public float getZplus() {
      return Constants.MAP_MARKER_LAYER;
   }

   @Override
   public boolean init() {
      return true;
   }

   @Override
   public boolean isDiscardable() {
      return true;
   }

}

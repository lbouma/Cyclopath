/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.Constants;

import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;

/**
 * This class represents labels used to identify features on the map.
 * @author Fernando Torre
 */
public class MapLabel implements Feature {
   
   /** paint properties for this label, including text size and color */
   private Paint p;
   /** label text */
   public String text;
   /** label rotation, in degrees */
   private float rotation;
   /** x position of label in map coordinates */
   private double x;
   /** y position of label in map coordinates */
   private double y;
   /** bounding box for this label */
   private RectF bbox;
   
   /**
    * Constructor
    * @param text label text
    * @param size label text size
    * @param rotation rotation of label in degrees
    * @param x x position of label in map coordinates
    * @param y y position of label in map coordinates
    */
   public MapLabel(String text, float size, float rotation,
                   double x, double y) {
      
      this.text = text;
      this.rotation = rotation;
      this.x = x;
      this.y = y;
      int cv_x = G.map.xform_x_map2cv(x);
      int cv_y = G.map.xform_y_map2cv(y);
      
      // used to get the bounding box of the label
      double cos_t = Math.cos(Math.toRadians(rotation));
      double sin_t = Math.sin(Math.toRadians(rotation));
      int wpad = Constants.MAP_LABEL_WIDTH_PADDING / 2;
      int hpad = Constants.MAP_LABEL_HEIGHT_PADDING / 2;
   
      this.p = new Paint();
      p.setStrokeWidth(Constants.LABEL_STROKE_WIDTH);
      p.setTextSize(size);
      p.setTextAlign(Paint.Align.CENTER);
      p.setTypeface(Typeface.DEFAULT_BOLD);
      p.setAntiAlias(true);
      Rect r = new Rect();
      p.getTextBounds(text, 0, text.length(), r);
      
      // Calculate the four corner's of my rotated bbox
      double r_width = r.width()/2.0 + wpad;
      double r_height = r.height()/2.0 + hpad;
      double[] xs = new double[]{
                     (cv_x + r_height * sin_t - r_width * cos_t),
                     (cv_x + r_height * sin_t + r_width * cos_t),
                     (cv_x - r_height * sin_t + r_width * cos_t),
                     (cv_x - r_height * sin_t - r_width * cos_t)};
   
      double[] ys = new double[]{
                     (cv_y - r_height * cos_t - r_width * sin_t),
                     (cv_y - r_height * cos_t + r_width * sin_t),
                     (cv_y + r_height * cos_t + r_width * sin_t),
                     (cv_y + r_height * cos_t - r_width * sin_t)};

      this.bbox = new RectF();
      this.bbox.top = Integer.MIN_VALUE;
      this.bbox.bottom = Integer.MAX_VALUE;
      this.bbox.right = Integer.MIN_VALUE;
      this.bbox.left = Integer.MAX_VALUE;
      for (int i = 0; i < xs.length; i++) {
         this.bbox.right =
            (float) Math.max(this.bbox.right,
                     G.map.xform_x_cv2map((int)Math.round(xs[i])));
         this.bbox.left =
               (float) Math.min(this.bbox.left,
                     G.map.xform_x_cv2map((int)Math.round(xs[i])));
         this.bbox.top =
               (float) Math.max(this.bbox.top,
                     G.map.xform_y_cv2map((int)Math.round(ys[i])));
         this.bbox.bottom =
               (float) Math.min(this.bbox.bottom,
                     G.map.xform_y_cv2map((int)Math.round(ys[i])));
      }
   }

   /**
    * Returns the bounding box for this label.
    */
   @Override
   public RectF getBboxMap() {
      return this.bbox;
   }

   /**
    * Returns z level of labels.
    */
   @Override
   public float getZplus() {
      return Constants.MAP_LABEL_LAYER;
   }

   /** No-op */
   @Override
   public void cleanup() {}

   /**
    * Draws the label;
    */
   @Override
   public void draw() {
      int cv_x = G.map.xform_x_map2cv(this.x);
      int cv_y = G.map.xform_y_map2cv(this.y);
      int textColor = Constants.LABEL_COLOR;
      if (G.aerialStateOn()) {
         textColor = Constants.AERIAL_LABEL_COLOR;
      }
      G.map.map_canvas.rotate(this.rotation, cv_x, cv_y);
      this.p.setColor(Constants.LABEL_HALO_COLOR);
      this.p.setStyle(Paint.Style.STROKE);
      G.map.map_canvas.drawText(this.text, cv_x, cv_y, this.p);
      this.p.setColor(textColor);
      this.p.setStyle(Paint.Style.FILL);
      G.map.map_canvas.drawText(this.text, cv_x, cv_y, this.p);
      G.map.map_canvas.rotate(-this.rotation, cv_x, cv_y);
   }

   /** No-op */
   @Override
   public void drawShadow() {}

   @Override
   public boolean init() {
      return true;
   }

   /**
    * Labels are discardable by default.
    */
   @Override
   public boolean isDiscardable() {
      return true;
   }

}

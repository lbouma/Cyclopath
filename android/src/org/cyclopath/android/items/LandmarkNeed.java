/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_LandmarkNeedGet;
import org.cyclopath.android.util.PointD;

import android.graphics.RectF;

/**
 * Landmark need item (a spot in the map where a landmark is needed).
 * @author Fernando Torre
 */
public class LandmarkNeed implements Feature {
   
   /** id of this landmark need */
   public int id;
   /** coordinates of this landmark need */
   public PointD coords;
   /** Current landmark need object */
   public static LandmarkNeed current_need;
   /** Current set of nearby landmarks (used to reduce server queries) */
   public static ArrayList<LandmarkNeed> nearby_landmarks;
   /** whether the landmark need is selected on the map */
   public boolean selected;

   /**
    * Constructor
    * @param id
    * @param coords
    */
   public LandmarkNeed(int id, PointD coords) {
      this.id = id;
      this.coords = coords;
      this.selected = false;
   }
   
   // *** Static methods
   
   /**
    * Fetch landmarks from the server.
    */
   public static void fetchLandmarks(PointD coords) {
      new GWIS_LandmarkNeedGet(coords).fetch();
   }
   
   /**
    * Find a nearby landmark need spot.
    * @param coords
    * @return
    */
   public static LandmarkNeed nearbyNeed(PointD coords) {
      for (LandmarkNeed ln : nearby_landmarks) {
         if (G.distance(ln.coords, coords) <
               Constants.LANDMARK_NEED_RADIUS * 2) {
            return ln;
         }
      }
      return null;
   }

   // *** Instance methods

   /** no-op */
   @Override
   public void cleanup() { }

   /** Draws circle indicating landmark need area */
   @Override
   public void draw() {
      int color;
      int border_color;
      if (this.selected) {
         color = Constants.LANDMARK_NEED_COLOR_SELECTED;
         border_color = Constants.LANDMARK_NEED_BORDER_COLOR_SELECTED;
      } else {
         color = Constants.LANDMARK_NEED_COLOR_UNSELECTED;
         border_color = Constants.LANDMARK_NEED_BORDER_COLOR_UNSELECTED;
      }
      float radius = Constants.LANDMARK_NEED_RADIUS * (float) G.map.getScale();
      G.map.drawCircle(G.map.xform_x_map2cv(coords.x),
                       G.map.xform_y_map2cv(coords.y),
                       radius,
                       Constants.ACCURACY_CIRCLE_STROKE_WIDTH,
                       color,
                       border_color);
   }

   /** no-op */
   @Override
   public void drawShadow() { }

   @Override
   public RectF getBboxMap() {
      return new RectF((float) this.coords.x - Constants.LANDMARK_NEED_RADIUS,
                       (float) this.coords.y + Constants.LANDMARK_NEED_RADIUS, 
                       (float) this.coords.x + Constants.LANDMARK_NEED_RADIUS,
                       (float) this.coords.y - Constants.LANDMARK_NEED_RADIUS);
   }

   @Override
   public float getZplus() {
      return Constants.LANDMARK_NEED_LAYER;
   }

   @Override
   public boolean init() {
      return true;
   }

   @Override
   public boolean isDiscardable() {
      return false;
   }
}

/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Enumeration;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_Checkout;
import org.cyclopath.android.gwis.QueryFilters;
import org.cyclopath.android.items.Byway;
import org.cyclopath.android.items.DirectionStep;
import org.cyclopath.android.items.Feature;
import org.cyclopath.android.items.Geofeature;
import org.cyclopath.android.items.Geopoint;
import org.cyclopath.android.items.MapPointer;
import org.cyclopath.android.items.MapLayer;
import org.cyclopath.android.items.Marker;
import org.cyclopath.android.items.Tile;
import org.cyclopath.android.util.Dual_Rect;
import org.cyclopath.android.util.PointD;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Point;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.location.Location;
import android.util.AttributeSet;
import android.util.FloatMath;
import android.util.Log;
import android.util.SparseArray;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.Button;

/**
 * Map surface which contains the canvas where the map is drawn. Some methods
 * in this class are originally based on the methods in
 * flashclient/Map_Canvas.as.
 * @author Fernando Torre
 * @author Phil Brown
 * @author Yanjie Liu
 */
public class MapSurface extends SurfaceView implements SurfaceHolder.Callback {
   
   /** thread in charge of drawing on the map canvas */
   private MapThread map_thread;
   /** canvas where map tiles and features are drawn on */
   public Canvas map_canvas;
   /** shows where the user is on the map as an arrow 
    * (or a question mark if the location is unknown)*/
   public MapPointer pointer;
   /** Handles touch events*/
   public GestureDetector tapManager;

   // Parameters to translate between map and canvas coordinates
   /** map x coordinate at the (0,0) canvas point*/
   protected double map_x_at_canvas_origin;
   /** map y coordinate at the (0,0) canvas point*/
   protected double map_y_at_canvas_origin;
   
   /** Map x to be set when the surface is created (or recreated). */
   public double new_map_x = Constants.MAP_CENTER_X;
   /** Map y to be set when the surface is created (or recreated). */
   public double new_map_y = Constants.MAP_CENTER_Y;
   /** x to pan to once view rect is ready */
   public double pan_zoom_later_x;
   /** y to pan to once view rect is ready */
   public double pan_zoom_later_y;
   /** zoom level to zoom to once view rect is ready */
   public int pan_zoom_later_zoom;
   /** whether we need to pan and zoom once view rect is ready */
   public boolean pan_zoom_later = false;
   /** map x coordinate for a long press */
   public double long_press_map_x;
   /** map y coordinate for a long press */
   public double long_press_map_y;
   
   /** Helps users find the map when map tiles are no longer visible*/
   public Button back_to_map;
   
   /** True if the user pans the map while tracking. This is
    * reset once the user presses the My Location button.*/
   protected static boolean has_panned = false;
   
   /** scale used for canvas matrix transformations */
   public float scale = 1;
   
   // Boxes defining fetch/discard behavior. See technical docs.
   /** Rect defining the current view of the map. */
   public Dual_Rect view_rect;
   /** Rect defining area where features where last fetched.*/
   public Dual_Rect resident_rect;
   
   /**  **/
   String[] feature_types_vector = new String[]{"waypoint",
                                                "terrain",
                                                "byway"};
   
   // Dragging variables
   /** true if a dragging operation is currently occurring */
   private boolean dragging;
   /** true if a dragging operation can begin */
   private boolean drag_start_valid;
   /** previous x coordinate during a drag operation */
   private float drag_last_x;
   /** previous y coordinate during a drag operation */
   private float drag_last_y;
   /** true if a pinch zooming operation is currently occurring */
   private boolean pinch_zooming;
   /** true if a pinch zooming operation can begin */
   private boolean pinch_zooming_valid;
   /** previous distance during a pinch zoom operation */
   private float old_distance;
   /** new distance during a pinch zoom operation */
   private float new_distance;
   
   /**
    * Constructor
    * @param context
    */
   public MapSurface(Context context) {
      super(context);
      getHolder().addCallback(this);
      tapManager = new GestureDetector(context, new GestureListener());
   }
   
   /**
    * Constructor
    * @param context
    * @param attrs
    */
   public MapSurface(Context context, AttributeSet attrs) {
      super(context, attrs);
      getHolder().addCallback(this);
      tapManager = new GestureDetector(context, new GestureListener());
   }

   // *** Other methods

   /**
    * If the user pans out of the view of the map, shows the "show map" button.
    */
   public void checkBounds(){
      if(this.view_rect.getMap_center_x() > Constants.MAP_RECT_RIGHT
          || this.view_rect.getMap_center_x() < Constants.MAP_RECT_LEFT
          || this.view_rect.getMap_center_y() > Constants.MAP_RECT_TOP
          || this.view_rect.getMap_center_y() < Constants.MAP_RECT_BOTTOM) {
         this.back_to_map.setEnabled(true);
         this.back_to_map.setVisibility(View.VISIBLE);
      }
      else{
         this.back_to_map.setEnabled(false);
         this.back_to_map.setVisibility(View.GONE);
      }
   }

   /**
    * Verifies if a feature collides with other features in its layer.
    * @param f Feature to check for collision
    * @return True if feature collides with at least one other feature in its
    * layer.
    */
   public boolean childCollides(Feature f) {
      for (Feature other: G.layers.get(f.getZplus()).children) {
         if (f != other) {
            // Intersects expects rect.top to be a smaller number than
            // rect.bottom because canvas coordinates begin on the upper right.
            // Therefore, we need to switch bottom and top.
            if (RectF.intersects(new RectF(f.getBboxMap().left,
                                           f.getBboxMap().bottom,
                                           f.getBboxMap().right,
                                           f.getBboxMap().top),
                                 new RectF(other.getBboxMap().left,
                                           other.getBboxMap().bottom,
                                           other.getBboxMap().right,
                                           other.getBboxMap().top)))  {
               return true;
            }
         }
      }
      return false;
   }

   /**
    * Performs a drag operation.
    * @param x_old previous x coordinate
    * @param y_old previous x coordinate
    * @param x_new new x coordinate
    * @param y_new new x coordinate
    */
   public void drag(int x_old, int y_old, int x_new, int y_new) {
      this.pan(x_new - x_old, y_new - y_old);
   }

   /**
    * Draws a circle on the map
    * @param x x position in canvas coordinates
    * @param y y position in canvas coordinates
    * @param radius radius of circle
    * @param stroke_width stroke width of circle
    * @param color fill color of circle
    */
   public void drawCircle(int x, int y,
                          float radius, float stroke_width,
                          int fillColor, int strokeColor) {
      Paint p = new Paint();
      p.setAntiAlias(true);
      p.setStrokeWidth(stroke_width);
      p.setColor(strokeColor);
      p.setStyle(Paint.Style.STROKE);
      this.map_canvas.drawCircle(x, y, radius, p);
      p.setColor(fillColor);
      p.setStyle(Paint.Style.FILL);
      this.map_canvas.drawCircle(x, y, radius, p);
   }

  /**
   * Draws a direction arrow (using canvas coordinates)
   * @param A point representing direction where arrow is coming from
   * @param B tip (end) of the arrow
   * @param fillColor fill color of triangle
   * @param borderColor border color of triangle 
   */
   public void drawDirection(Point A, Point B,
                             int fillColor, int borderColor) {
      // paint for triangle's border
      Paint p1 = new Paint();
      p1.setAntiAlias(true);
      p1.setColor(borderColor);
      p1.setStyle(Paint.Style.FILL_AND_STROKE);
      p1.setStrokeWidth(Constants.DIRECTION_ARROW_BORDER_STROKE_WIDTH);
      // paint for triangle's inner part
      Paint p2 = new Paint();
      p2.setAntiAlias(true);
      p2.setColor(fillColor);
      p2.setStyle(Paint.Style.FILL);
      
      // the height of the triangle
      double H = Constants.DIRECTION_ARROW_HEIGHT;
      // half width of the triangle
      double W = Constants.DIRECTION_ARROW_WIDTH;
      // triangle's angle
      double arrow_ang = Math.atan(W / H);
      // the length of the arrow
      double arrow_len = Math.sqrt(W * W + H * H);
      Point point1 = rotateVec(B, A, 
                               arrow_ang, arrow_len);
      Point point2 = rotateVec(B, A, 
                               -arrow_ang, arrow_len);
      
      Path triangle = new Path();
      triangle.moveTo(B.x, B.y);
      triangle.lineTo(B.x - point1.x, 
                      B.y - point1.y);
      triangle.lineTo(B.x - point2.x, 
                      B.y - point2.y);
      triangle.close();
      this.map_canvas.drawPath(triangle, p1);
      this.map_canvas.drawPath(triangle, p2);
   }

   /**
    * Draws direction arrows
    * @param xys Array of points in map coordinates
    * @param directions Route directions
    * @param selected_direction Currently selected direction, which will be
    *        colored differently
    * @param width Stroke width for border
    * @param color Fill color of polygon
    */
   public void drawDirections(ArrayList<PointD> xys,
                              ArrayList<DirectionStep> directions,
                              int selected_direction) {
      if (xys.isEmpty())
         return;
      
      Point A, B;
      PointD last;
      int j = 1;
       
      for (int i = 1; i < directions.size() - 1; i++) {
         last = new PointD(directions.get(i).start_point.x,
                           directions.get(i).start_point.y);
         while (j < xys.size()) {
            if((xys.get(j).x == last.x) && (xys.get(j).y == last.y))
               break;
            j++;
         }
         B = new Point(this.xform_x_map2cv(last.x),
                       this.xform_y_map2cv(last.y));
         A = new Point(this.xform_x_map2cv(xys.get(j - 1).x),
                       this.xform_y_map2cv(xys.get(j - 1).y));
         if (i == selected_direction) {
            this.drawDirection(A, B,
                               Constants.ROUTE_DIRECTION_COLOR,
                               Constants.ROUTE_BORDER_COLOR);
         } else {
            this.drawDirection(A, B,
                               Constants.ROUTE_COLOR,
                               Constants.ROUTE_BORDER_COLOR);
         }
      }
   }

   /**
    * Draws a label on the map.
    * @param x x position in canvas coordinates
    * @param y y position in canvas coordinates
    * @param text text of label
    * @param size text size
    * @param stroke_width border width
    */
   public void drawLabel(int x, int y, String text,
                         float size, float stroke_width) {
      Paint p = new Paint();
      p.setStrokeWidth(stroke_width);
      p.setTextSize(size * getResources().getDisplayMetrics().density);
      p.setTextAlign(Paint.Align.CENTER);
      p.setTypeface(Typeface.DEFAULT_BOLD);
      p.setAntiAlias(true);
      p.setColor(Color.WHITE);
      p.setStyle(Paint.Style.STROKE);
      this.map_canvas.drawText(text, x, y, p);
      p.setColor(Color.BLACK);
      p.setStyle(Paint.Style.FILL);
      this.map_canvas.drawText(text, x, y, p);
   }

   /**
    * Draws a line of points.
    * @param xys Array of points in map coordinates
    * @param width width of line
    * @param color color of line
    */
   public void drawLine(ArrayList<PointD> xys, float width, int color) {
      if (xys.isEmpty())
         return;
      
      Paint p = new Paint();
      p.setStrokeCap(Paint.Cap.ROUND);
      p.setAntiAlias(true);
      p.setColor(color);
      p.setStrokeWidth(width);
      int x1, y1;
      int x2, y2;
      x1 = this.xform_x_map2cv(xys.get(0).x);
      y1 = this.xform_y_map2cv(xys.get(0).y);
      for (int i = 1; i < xys.size(); i++) {
         x2 = this.xform_x_map2cv(xys.get(i).x);
         y2 = this.xform_y_map2cv(xys.get(i).y);
         this.map_canvas.drawLine(x1, y1, x2, y2, p);
         x1 = x2;
         y1 = y2;
      }
   }
   
   /**
    * Draws a polygon
    * @param xys Array of points in map coordinates
    * @param color fill color of polygon
    */
   public void drawPolygon(ArrayList<PointD> xys, int color) {
      ArrayList<PointD> canvas_xys = new ArrayList<PointD>();
      for (PointD p : xys) {
         canvas_xys.add(new PointD(this.xform_x_map2cv(p.x),
                                   this.xform_y_map2cv(p.y)));
      }
      this.drawPolygonCanvas(canvas_xys, color);
   }

   /**
    * Draws a polygon
    * @param xys Array of points in canvas coordinates
    * @param color fill color of polygon
    */
   public void drawPolygonCanvas(ArrayList<PointD> xys, int color) {
      if (xys.isEmpty())
         return;
      
      Path poly = new Path();
      Paint p = new Paint();
      p.setAntiAlias(true);
      p.setColor(color);
      p.setStyle(Paint.Style.FILL);
      poly.moveTo((float) xys.get(0).x, (float) xys.get(0).y);
      for (int i = 1; i < xys.size(); i++) {
         poly.lineTo((float) xys.get(i).x,
                     (float) xys.get(i).y);
      }
      poly.close();
      this.map_canvas.drawPath(poly, p);
   }

   /**
    *  Adds a particular feature to the map.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    * @param f feature to add
    */
   public void featureAdd(Feature f) {
      this.layersAddMaybe(f);
      G.layers.get(f.getZplus()).featureAdd(f);
   }
   
   /**
    *  Discards a particular feature from the map.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    * @param f feature to discard
    */
   public void featureDiscard(Feature f) {
      if (f != null) {
         if(G.layers.containsKey(f.getZplus())) {
            G.layers.get(f.getZplus()).featureDiscard(f);
         }
      }
   }

   /**
    *  Adds a list of features to the map.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    * @param feats collection of features to add
    */
   public void featuresAdd(Collection<Feature> feats) {
      for (Feature f : feats) {
         if (f.init())
            this.featureAdd(f);
      }
      this.featuresLabel();
   }
   
   /**
    * Deselects all geofeatures in the map.
    */
   public void featuresDeselect(){
      for (MapLayer l : this.getLayersOrdered()) {
         l.featuresDeselect();
      }
   }
   
   /**
    *  Discards map features not within the given rectangle.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    * @param r features inside r will not be discarded
    */
   public void featuresDiscard(Dual_Rect r) {
      for (MapLayer l : this.getLayersOrdered()) {
         l.featuresDiscard(r, false);
      }
   }
   
   /**
    * Discards all of the features in a particular map layer,
    * if the layer exists
    * Note: The naming format for this method was derived from the Flash client
    * coding format.
    * @param Z The Map_Layer z-level to discard
    */
   public void featuresDiscard(float z){
      if(G.layers.containsKey(z)){
         G.layers.get(z).featuresDiscard(null, true);
      }
   }

   /**
    * Fetches map features appropriate for this zoom level which intersect
    * include_rect but do not intersect exclude_rect (which may be null).
    */
   public void featuresFetch(Dual_Rect include_rect, Dual_Rect exclude_rect) {
      if (this.zoomIsVector(G.zoom_level)) {
         // Zoom level is above raster-only threshold -- fetch vectors.
         Dual_Rect r = null;
         if (this.zoomIsVector(G.zoom_level_previous)) {
            // Previous zoom level also above threshold, so exclude rect
            // contains vectors. Fetch only vectors outside it.
            if (!include_rect.eq(exclude_rect)) {
               r = exclude_rect;
            } else {
               // nothing to be fetched
               return;
            }
         }
         for (String ft: this.feature_types_vector) {
            QueryFilters qfs = new QueryFilters();
            qfs.include_rect = include_rect;
            qfs.exclude_rect = r;
            qfs.dont_load_feat_attcs = false;
            new GWIS_Checkout(ft, qfs).fetch();
         }
      } else if (!(this.zoomIsVector(G.zoom_level))
                 && this.zoomIsVector(G.zoom_level_previous)) {
         // Zoom level is at or below the raster-only threshold, so don't
         // fetch vectors. Furthermore, the previous zoom level was above
         // the threshold, so we must discard all existing vectors.
         this.featuresDiscard(null);
      }
   }

   /**
    * Labels all features.
    */
   public void featuresLabel() {
      for (MapLayer l : this.getLayersOrdered()) {
         l.featuresLabel();
      }
   }

   /**
    *  Redraws all the map features.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    */
   public void featuresRedraw() {
      for (MapLayer l : this.getLayersOrdered()) {
         if (l != null) {
            l.featuresRedraw();
         }
      }
   }
   
   /**
    *  Clears all labels and relabels the map.
    */
   public void featuresRelabel() {
      // Discard and recreate the label layer
      G.layers.put(
         Constants.MAP_LABEL_LAYER, new MapLayer(Constants.MAP_LABEL_LAYER));
      this.featuresLabel();
   }
   
   /**
    * Returns a Marker if one is being currently displayed and null
    * otherwise.
    * @return
    */
   public Marker getCurrentMarker() {
      if (G.layers.containsKey(Constants.MAP_MARKER_LAYER)) {
         ArrayList<Feature> children =
               G.layers.get(Constants.MAP_MARKER_LAYER).children;
         if (!children.isEmpty()) {
            return (Marker) children.get(0);
         }
      }
      return null;
   }
   
   /**
    * Returns the layer objects ordered by decreasing 'size'.
    * @return An ArrayList of Map Layers.
    */
   public ArrayList<MapLayer> getLayersOrdered() {
      ArrayList<Float> a = new ArrayList<Float>();
      ArrayList<MapLayer> results = new ArrayList<MapLayer>();
      for (Enumeration<Float> e = G.layers.keys(); e.hasMoreElements(); ) {
         a.add((Float) e.nextElement());
      }
      Collections.sort(a);
      
      for (Float i : a) {
         if (G.layers.get(i) != null)
            results.add(G.layers.get(i));
      }
      return results;
   }
   
   /**
    * Returns an ArrayList of Byways and Geopoints within a certain threshold
    * of pixels from the given map coordinates (sorted by distance to point).
    * @param p point in map coordinates
    * @param pixels pixel threshold
    * @return
    */
   public ArrayList<Geofeature> getNearbyGeofeatures(PointD p , int pixels) {
      ArrayList<Geofeature> feats = new ArrayList<Geofeature>();
      SparseArray<Double> distances = new SparseArray<Double>();
      boolean inserted;
      
      for (Enumeration<Float> e = G.layers.keys(); e.hasMoreElements(); ) {
         MapLayer layer = G.layers.get(e.nextElement());
         for (Feature f : layer.children) {
            if (Byway.class.isInstance(f)
                || Geopoint.class.isInstance(f)) {
               Geofeature g = (Geofeature) f;
               double dist = g.getDistanceFrom(p);
               distances.append(g.stack_id, dist);
               if (this.xform_scalar_map2cv(dist)
                     < pixels) {
                  inserted = false;
                  for (int i = 0; i < feats.size(); i++) {
                     if(distances.get(feats.get(0).stack_id) > dist) {
                        feats.add(i, g);
                        inserted = true;
                        break;
                     }
                  }
                  if (!inserted) {
                     feats.add(g);
                  }
               }
            }
         }
      }
      return feats;
   }

   /**
    * Returns the current map scale based on the zoom level.
    */
   public double getScale() {
      return Math.pow(2,G.zoom_level - 16);
   }

   /**
    * Move the map to the specified location.
    * @param loc The location to pan to.
    */
   public void goToLocation(Location loc) {
      PointD p = G.latlonToMap(loc);
      if (p != null) {
         this.goToLocation(p);
      }
   }
   
   /**
    * Move the map to the specified location.
    * @param p The point in map coordinates to pan to.
    */
   public void goToLocation(PointD p) {
      if (this.view_rect != null) {
         this.panto(this.xform_x_map2cv(p.x),this.xform_y_map2cv(p.y));
      }
   }
   
   /**
    * Handles mouse down event.
    * @param event touch event
    */
   public void handleMouseDown(MotionEvent event) {
      this.dragging = false;
      
      boolean handled = false;
      
      // For collision-related detection, we offset the mouse event's location
      // depending on how much the view rect has been offset. We don't do this
      // for normal drag and pinch operation because:
      // a) these operation depend on differences between values and not on
      // absolute values.
      // b) I [ft] actually tried to change it and interaction is a bit wonky.
      // 
      if (view_rect != null) {
         event.offsetLocation(view_rect.getCv_min_x(),
                              view_rect.getCv_min_y());
      }
      Marker current = this.getCurrentMarker();
      if (current != null) {
         if (current.getBboxMap().contains(
               (float) xform_x_cv2map(Math.round(event.getX())),
               (float) xform_y_cv2map(Math.round(event.getY())))) {
            current.pressed = true;
            this.redraw();
            handled = true;
         }
      }
      if (!handled) {
         // undo offset
         if (view_rect != null) {
            event.offsetLocation(-view_rect.getCv_min_x(),
                                 -view_rect.getCv_min_y());
         }
         this.drag_start_valid = true;
         this.drag_last_x = event.getX();
         this.drag_last_y = event.getY();
      }
   }
   
   /**
    * Handles what happens when a user slides finger (moves) across the screen.
    * @param event touch event
    */
   public void handleMouseMove(MotionEvent event) {
      if (this.dragging || this.drag_start_valid) {
         float x = event.getX() - this.drag_last_x;
         float y = event.getY() - this.drag_last_y;
         if (FloatMath.sqrt(x * x + y * y) < Constants.MIN_DRAG_DISTANCE) {
            return;
         }
         this.dragging = true;
         has_panned = true;
         this.drag_start_valid = false;
         this.drag(Math.round(this.drag_last_x),
                   Math.round((int) this.drag_last_y),
                   Math.round((int) event.getX()),
                   Math.round((int) event.getY()));
         this.drag_last_x = event.getX();
         this.drag_last_y = event.getY();
      } else if (this.pinch_zooming || this.pinch_zooming_valid) {
         this.pinch_zooming = true;
         this.pinch_zooming_valid = false;
         float x = event.getX(0) - event.getX(1);
         float y = event.getY(0) - event.getY(1);
         float scale = this.new_distance/this.old_distance;
         int new_zoom = G.zoom_level
                        + (int)Math.round(Math.log(scale)/Math.log(2));
         this.new_distance = FloatMath.sqrt(x * x + y * y);
         // Make sure that we don't zoom in or out too much or too little
         if (Math.abs(this.new_distance - this.old_distance)
               > Constants.MIN_PINCH_DISTANCE
             && new_zoom <= Constants.ZOOM_MAX
             && new_zoom >= Constants.ZOOM_MIN) {
            this.scale = scale;
            this.redraw();
         }
      }
   }

   /**
    * Handles what happens when a user lifts finger off the screen.
    * @param event touch event
    */
   public void handleMouseUp(MotionEvent event) {
      if (this.dragging || this.pinch_zooming) {
         if (this.pinch_zooming) {
            float scale = this.new_distance/this.old_distance;
            this.scale = 1;
            this.zoomto(G.zoom_level
                        + (int)Math.round(Math.log(scale)/Math.log(2)));
            this.redraw();
         }
         this.update();
      }
      
      Marker current = getCurrentMarker();
      if (current != null && !this.pinch_zooming) {
         current.pressed = false;
         this.redraw();
         event.offsetLocation(view_rect.getCv_min_x(),
                              view_rect.getCv_min_y());
         double map_x = xform_x_cv2map(Math.round(event.getX()));
         double map_y = xform_y_cv2map(Math.round(event.getY()));
         if (current.getBboxMap().contains((float)map_x, (float)map_y)) {
            // open item details panel
            Intent myIntent =
                  new Intent(getContext(), ItemDetailsActivity.class);
            myIntent.putExtra(Constants.STACK_ID_STR, current.geo.stack_id);
            getContext().startActivity(myIntent);
         }
      }
      
      this.drag_start_valid = false;
      this.dragging = false;
      this.pinch_zooming_valid = false;
      this.pinch_zooming = false;
   }

   /**
    * Handles mouse pointer down event (this is called only when a second
    * pointer touches the screen).
    * @param event touch event
    */
   public void handlePointerDown(MotionEvent event) {
      this.dragging = false;
      this.drag_start_valid = false;
      this.pinch_zooming = false;
      float x = event.getX(0) - event.getX(1);
      float y = event.getY(0) - event.getY(1);
      this.old_distance = FloatMath.sqrt(x * x + y * y);
      if (old_distance > Constants.MIN_PINCH_DISTANCE) {
         this.pinch_zooming_valid = true;
      }
   }

   /**
    *  Ensures that appropriate layers are available for Feature f.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    * @param f feature that may need a new layer
    */
   public void layersAddMaybe(Feature f) {
      if (!(G.layers.containsKey(f.getZplus()))) {
         G.layers.put(f.getZplus(), new MapLayer(f.getZplus()));
      }
   }

   /**
    * Returns true if layer f does not exist or has no features in it.
    */
   public boolean layerIsEmpty(float f) {
      if (!G.layers.containsKey(f)) {
         return true;
      } else {
         return G.layers.get(f).children.isEmpty();
      }
   }

   /**
    * Positions the map over f, and update. If zoom is 0, zoom in or
    * out to fit; otherwise, go to the given zoom.
    */
   public void lookAt(Feature f, int zoom) {
      int newzoom;
      float obj_height;
      float obj_width;
      float vp_height;
      float vp_width;

      // adjust required height and width slightly to give a margin
      obj_height = 1.10f * (f.getBboxMap().bottom - f.getBboxMap().top);
      obj_width = 1.10f * (f.getBboxMap().right - f.getBboxMap().left);

      // height and width of a maximally-zoomed-in viewport
      vp_height = (float) ((this.view_rect.getMap_max_y()
                              - this.view_rect.getMap_min_y())
                   * Math.pow(2, G.zoom_level - Constants.ZOOM_MAX));
      vp_width = (float) ((this.view_rect.getMap_max_x()
                              - this.view_rect.getMap_min_x())
                   * Math.pow(2, G.zoom_level - Constants.ZOOM_MAX));

      // Find the largest zoom level that fits the whole object.
      // NOTE from flashclient: This algorithm is numerically unrobust, but
      // it's not a very demanding application.
      if (zoom != 0) {
         newzoom = zoom;
      } else {
         newzoom = Constants.ZOOM_MAX;
         while (vp_height < obj_height || vp_width < obj_width) {
            newzoom--;
            vp_height *= 2;
            vp_width *= 2;
         }
      }
      has_panned = true;
      this.panto(this.xform_x_map2cv(f.getBboxMap().centerX()),
                 this.xform_y_map2cv(f.getBboxMap().centerY()));
      this.zoomto(newzoom);
      if (G.zoom_level_previous == G.zoom_level) {
         this.update();
      }
   }
   
   /**
    * Moves the map just enough to show the given Feature.
    * @param f
    */
   public void lookAtLazy(Feature f) {
      
      double pan_x;
      double pan_y;
      double margin = this.xform_scalar_cv2map(
            Math.round(Constants.LOOKAT_LAZY_MARGIN
               * getResources().getDisplayMetrics().density));
      // We add a bit of margin at the top to account for the title bar
      double margin_top = this.xform_scalar_cv2map(
            Math.round((Constants.LOOKAT_LAZY_MARGIN_TOP)
               * getResources().getDisplayMetrics().density));
      RectF bbox = f.getBboxMap();
      
      // Do we need to pan left or right?
      if (bbox.left - margin < this.view_rect.getMap_min_x()) {
         pan_x = this.view_rect.getMap_min_x() - (bbox.left - margin);
      } else if (bbox.right + margin > this.view_rect.getMap_max_x()) {
         pan_x = this.view_rect.getMap_max_x() - (bbox.right + margin);
      } else {
         pan_x = 0;
      }
      // Do we need to pan up or down?
      if (bbox.bottom - margin < this.view_rect.getMap_min_y()) {
         pan_y = (bbox.bottom - margin) - this.view_rect.getMap_min_y();
      } else if (bbox.top + margin_top > this.view_rect.getMap_max_y()) {
         pan_y = (bbox.top + margin_top) - this.view_rect.getMap_max_y();
      } else {
         pan_y = 0;
      }
      
      has_panned = true;
      this.pan(this.xform_scalar_map2cv(pan_x),
               this.xform_scalar_map2cv(pan_y));
      this.update();
   }

   /**
    * Draws all map layers.
    */
   @Override
   public void onDraw(Canvas canvas) {
      this.map_canvas = canvas;
      if (canvas != null) {
         this.update_draw_transform(canvas);
         canvas.drawColor(Constants.BACKGROUND);
         this.featuresRedraw();
      }
   }
   
   /**
    * Handles mouse (touch) events.
    */
   @Override
   public boolean onTouchEvent(MotionEvent event) {
      if (tapManager.onTouchEvent(event)){
         return true;
      }
      if (event.getAction() == MotionEvent.ACTION_DOWN) {
         this.handleMouseDown(event);
      } else if (event.getAction() == MotionEvent.ACTION_MOVE) {
         this.handleMouseMove(event);
      } else if (event.getAction() == MotionEvent.ACTION_UP
                 || (event.getAction() & MotionEvent.ACTION_MASK)
                     == MotionEvent.ACTION_POINTER_UP) {
         this.handleMouseUp(event);
      } else if ((event.getAction() & MotionEvent.ACTION_MASK)
                  == MotionEvent.ACTION_POINTER_DOWN) {
         this.handlePointerDown(event);
      }
      return true;
   }
   
   /**
    * Zooms in by one level.
    */
   public void onZoomIn() {
      this.zoomto(G.zoom_level + 1);
   }
   
   /**
    * Zooms out by one level.
    */
   public void onZoomOut() {
      this.zoomto(G.zoom_level - 1);
   }
   
   /**
    *  Pans the map the given number of pixels along each axis.
    * @param x number of pixels to pan on the x axis
    * @param y number of pixels to pan on the y axis
    */
   public void pan(int x, int y) {
      // as user drags the map in one direction, the view moves in the
      // opposite direction.
      this.view_rect.move(-x, -y);
      this.redraw();
      this.checkBounds();
   }

   /**
    *  Pans the map to the center of x and y using canvas coordinates.
    * @param x x coordinate of new center
    * @param y y coordinate of new center
    */
   public void panto(int x, int y) {
      this.pan(this.view_rect.getCv_center_x() - x,
               this.view_rect.getCv_center_y() - y);
      this.update();
   }

   /**
    * Requests a pan and zoom for when view rect is available once again.
    */
   public void panZoomLater(double x, double y, int zoom) {
      if (this.view_rect == null) {
         this.pan_zoom_later_x = x;
         this.pan_zoom_later_y = y;
         this.pan_zoom_later_zoom = zoom;
         this.pan_zoom_later = true;
      } else {
         this.panto(G.map.xform_x_map2cv(x), G.map.xform_y_map2cv(y));
         this.zoomto(zoom);
      }
   }
   
   /**
    * Redraws the map.
    */
   public void redraw() {
      if (this.map_thread != null) {
         this.map_thread.setDrawing(true);
      }
   }

   /**
    * Sets the origin of the map and center the view on the given coordinates.
    * @param x new map origin x coordinate
    * @param y new map origin y coordinate
    */
   public void reoriginate(double x, double y) {
      this.map_x_at_canvas_origin
         = x + this.xform_xdelta_cv2map(-this.getWidth()/2);
      this.map_y_at_canvas_origin
         = y + this.xform_ydelta_cv2map(-this.getHeight()/2);
      this.view_rect.moveto(0,0);
   }

   /**
    * Returns a point that rotates the line from A to B using A as the
    * origin. The new point is basically a replacement for B.
    * @param A starting point
    * @param B end point
    * @param ang rotating angle
    * @param newLen new length
    * @return point indicating new location for B
    */
   public Point rotateVec(Point A, Point B, double ang,
                          double newLen) {
      float px = A.x - B.x;
      float py = A.y - B.y;
      double vx = px * Math.cos(ang) - py * Math.sin(ang);
      double vy = px * Math.sin(ang) + py * Math.cos(ang);
      double d = Math.sqrt(vx * vx + vy * vy);
      vx = vx / d * newLen;
      vy = vy / d * newLen;
      return new Point(Math.round((float)vx),
                       Math.round((float)vy));
    }
   
   @Override
   public void surfaceChanged(SurfaceHolder holder, int format,
                              int width, int height) {
       // TODO Auto-generated method stub
   }

   /**
    * Initializes map when ready.
    */
   @Override
   public void surfaceCreated(SurfaceHolder holder) {
      if (this.view_rect == null) {
         this.view_rect = new Dual_Rect();
         this.view_rect_resize();
         this.reoriginate(this.new_map_x, this.new_map_y);
         this.zoomto(G.zoom_level);
      }
      map_thread = new MapThread(getHolder(), this);
      this.map_thread.setRunning(true);
      this.map_thread.start();
      if (this.pan_zoom_later) {
         this.panto(G.map.xform_x_map2cv(this.pan_zoom_later_x),
                    G.map.xform_y_map2cv(this.pan_zoom_later_y));
         this.zoomto(this.pan_zoom_later_zoom);
         this.pan_zoom_later = false;
      }
      setFocusable(true);
      this.update();
   }

   /**
    * Takes care of thread once we don't need to use it anymore.
    */
   @Override
   public void surfaceDestroyed(SurfaceHolder holder) {
      boolean retry = true;
      this.map_thread.setRunning(false);
      while (retry) {
          try {
              map_thread.join();
              retry = false;
          } catch (InterruptedException e) {
              // we will try it again and again...
          }
      }
      this.map_thread = null;
   }
   
   /** 
    * Removes all tiles.
    */
   protected void tilesClear() {
      G.layers.remove(Constants.TILE_LAYER);
      if (this.zoomIsVector(G.zoom_level)) {
         G.layers.remove(Constants.OLD_TILE_LAYER);
      }
   }
   
   /**
    * Fetches map tiles appropriate for this zoom level.
    * @param include_rect map rect for which to get tiles
    * @param exclude_rect map rect for which not to get tiles
    */
   public void tilesFetch(Dual_Rect include_rect, Dual_Rect exclude_rect) {
      if (this.zoomIsVector(G.zoom_level) && !G.aerialStateOn()) {
         this.redraw();
         return;
      }
      Tile t;
      int xi;
      int yi;
      int xmin_i = Tile.coord_to_tileindex(include_rect.getMap_min_x());
      int ymin_i = Tile.coord_to_tileindex(include_rect.getMap_min_y());
      int xmax_i = Tile.coord_to_tileindex(include_rect.getMap_max_x());
      int ymax_i = Tile.coord_to_tileindex(include_rect.getMap_max_y());
      
      for (xi = xmin_i; xi <= xmax_i; xi++) {
         for (yi = ymin_i; yi <= ymax_i; yi++) {
            t = new Tile(xi, yi,
                         (G.aerialStateOn()) ? "aerial" : "main");
            if (G.zoom_level != G.zoom_level_previous
                || !t.rect.intersects(exclude_rect)) {
               t.fetch_tile();
            }
         }
      }
   }
   
   /**
    * Refetches tiles.
    */
   public void tilesRefetch() {
      this.tilesClear();
      if (this.view_rect != null) {
         this.tilesFetch(this.view_rect, null);
      }
   }
   
   /**
    * Refetches aerial tiles.
    */
   public void tiles_refetch_aerial() {
      String aerial_layer_name = "";
      if (G.aerialStateOn()) {
         aerial_layer_name = Constants.PHOTO_LAYERS[G.aerial_state][0];
      }
      G.server_log.event("mobile/ui/aerial",
            new String[][]{{"status", G.aerialStateOn() ? "on" : "off"},
                           {"layer", aerial_layer_name}});
      this.tilesRefetch();
   }
   
   /**
    *  Updates the map and fetch required features.
    */
   public void update() {
      Dual_Rect rprime;
      Dual_Rect b_fetch = this.view_rect.buffer(Constants.FETCH_HYS);
      Dual_Rect d_discard = b_fetch.buffer(Constants.DISCARD_HYS);
      if (this.resident_rect != null) {
         this.resident_rect = this.resident_rect.intersection(d_discard);
      }
      rprime = b_fetch.union(this.resident_rect);
      this.featuresFetch(rprime, this.resident_rect);
      this.featuresDiscard(this.resident_rect);
      this.tilesFetch(rprime, this.resident_rect);
      this.resident_rect = rprime;
      G.zoom_level_previous = G.zoom_level;
      this.redraw();
   }
   
   /**
    *  Updates the transformation matrix used for drawing.
    */
   public void update_draw_transform(Canvas canvas) {
      Matrix m = new Matrix();
      m.setTranslate(-this.view_rect.getCv_min_x(),
                     -this.view_rect.getCv_min_y());
      m.postScale(scale, scale, this.getWidth()/2, this.getHeight()/2);
      canvas.setMatrix(m);
   }
   
   // Methods to transform between map and canvas space.

   /**
    * Resizes the view rectangle to be as big as the map surface.
    */
   public void view_rect_resize() {
      int centerx = this.view_rect.getCv_center_x();
      int centery = this.view_rect.getCv_center_y();
      this.view_rect.setCv_min_x(centerx - this.getWidth()/2);
      this.view_rect.setCv_max_x(centerx + this.getWidth()/2);
      this.view_rect.setCv_min_y(centery - this.getHeight()/2);
      this.view_rect.setCv_max_y(centery + this.getHeight()/2);
   }

   /** Translates x from map coordinate to canvas coordinate. */
   public int xform_x_map2cv(double x) {
      return (int) Math.round(
            (x - this.map_x_at_canvas_origin) * this.getScale());
   }
   /** Translates y from map coordinate to canvas coordinate. */
   public int xform_y_map2cv(double y) {
      return (int) Math.round(
            (y - this.map_y_at_canvas_origin) * -this.getScale());
   }
   /** Translates an x difference from map coordinate to canvas coordinate. */
   public int xform_xdelta_map2cv(double xdelta) {
      return (int) Math.round(xdelta * this.getScale());
   }
   /** Translates a y difference from map coordinate to canvas coordinate. */
   public int xform_ydelta_map2cv(double ydelta) {
      return (int) Math.round(ydelta * -this.getScale());
   }
   /** Translates a scalar from map coordinate to canvas coordinate. */
   public int xform_scalar_map2cv(double s) {
      return (int) Math.round(s * this.getScale());
   }
   /** Translates x from canvas coordinate to map coordinate. */
   public double xform_x_cv2map(int x) {
      return (this.map_x_at_canvas_origin + x/this.getScale());
   }
   /** Translates y from canvas coordinate to map coordinate. */
   public double xform_y_cv2map(int y) {
      return (this.map_y_at_canvas_origin - y/this.getScale());
   }
   /** Translates an x difference from canvas coordinate to map coordinate. */
   public double xform_xdelta_cv2map(int xdelta) {
      return (xdelta / this.getScale());
   }
   /** Translates a y difference from canvas coordinate to map coordinate. */
   public double xform_ydelta_cv2map(int ydelta) {
      return (ydelta / -this.getScale());
   }
   /** Translates a scalar from canvas coordinate to map coordinate. */
   public double xform_scalar_cv2map(int s) {
      return (s / this.getScale());
   }
   
   /**
    * Return true if the given zoom level is vector mode. If zoom level
    * is less than zero, use the current zoom level.
    */
   public boolean zoomIsVector(int zoom) {
      if (zoom < 0)
         zoom = G.zoom_level;
      return (zoom > Constants.ZOOM_RASTER_MAX);
   }

   /**
    *  Zooms to a specific zoom level. If the specified zoom level is not equal
    * to the current zoom level, zoom to level (with map center invariant),
    * update the map, and return true. Otherwise, do nothing and return false.
    *
    * If level is out of bounds, clamp it to the appropriate bound.
    * @param level map zoom level to zoom to
    * @return true if zoom was successful
    */
   public boolean zoomto(int level) {
      double cx;
      double cy;
      Tile t;
      
      // Clamp level if out of bounds
      if (level < Constants.ZOOM_MIN) {
         level = Constants.ZOOM_MIN;
      } else if (level > Constants.ZOOM_MAX) {
         level = Constants.ZOOM_MAX;
      }

      // Bail out if zoom would be a no-op.
      if (level == G.zoom_level) {
         return false;
      }

      // Save current tiles before discarding so that we can display their
      // scaled versions at the new zoom level.
      MapLayer tiles = G.layers.get(Constants.TILE_LAYER);
      MapLayer old_tiles = G.layers.get(Constants.TILE_LAYER);
      if (tiles != null) {
         if (!tiles.isEmpty()) {
            G.layers.put(Constants.OLD_TILE_LAYER, tiles);
         }
      }

      if (old_tiles != null) {
         for (int i = old_tiles.children.size()-1; i >= 0; i--) {
            t = (Tile)old_tiles.children.get(i);
            t.zoom_level = level;
         }
      }

      // Changing scale will invalidate the translation between map and
      // canvas coordinates, so we need to save and restore them.
      cx = this.view_rect.getMap_center_x();
      cy = this.view_rect.getMap_center_y();

      G.zoom_level = level;
      this.reoriginate(cx, cy);
      this.view_rect.setCv_min_x(this.xform_x_map2cv(cx) - this.getWidth()/2);
      this.view_rect.setCv_max_y(this.xform_y_map2cv(cy) + this.getHeight()/2);
      this.view_rect.setCv_max_x(this.xform_x_map2cv(cx) + this.getWidth()/2);
      this.view_rect.setCv_min_y(this.xform_y_map2cv(cy) - this.getHeight()/2);

      // Update the map.
      this.tilesClear();  // avoid momentary tile/region mismatch
      this.update();
      this.featuresRelabel();
      
      return true;
   }

   /**
    *  Inner thread class that handles drawing to the canvas
    */
   class MapThread extends Thread {
      
      private SurfaceHolder surface_holder;
      private MapSurface map_surface;
      /** The thread will run while this is true.*/
      private volatile boolean run = false;
      /** The thread will draw while this is true.*/
      private volatile boolean draw = false;
      
      public MapThread(SurfaceHolder sh, MapSurface ms) {
         this.surface_holder = sh;
         this.map_surface = ms;
      }
      
      public void setRunning(boolean running) {
         this.run = running;
      }
      
      public void setDrawing(boolean drawing) {
         this.draw = drawing;
      }
      
      /**
       * Starts the thread. The thread continues running, but only draws
       * whenever 'run' is set to true.
       */
      @SuppressLint("WrongCall")
      @Override
      public void run() {
         Canvas c;
         while (this.run){
            while (this.draw) {
               c = null;
               try {
                   c = surface_holder.lockCanvas(null);
                   this.setDrawing(false);
                   synchronized (surface_holder) {
                      map_surface.onDraw(c);
                   }
               } finally {
                   if (c != null) {
                      surface_holder.unlockCanvasAndPost(c);
                   }
               }
            }
            // This is supposed to reduce cpu usage. It also fixes a bug
            // in some devices where the app believes this thread is in an
            // infinite loop and crashes.
            try {
               Thread.sleep(1);
            } catch(InterruptedException e) {}
         }
      }
      
   }

   /**
    * Overrides touch gestures not handled by the default touch listener
    */
   private class GestureListener 
                 extends GestureDetector.SimpleOnGestureListener {
      /** Zooms in on double click*/
      @Override
      public boolean onDoubleTap(MotionEvent e) {
         zoomto(G.zoom_level + 1);
         //TODO: Center map on tap location
         return true;
      }
      
      /** Shows context menu on long press */
      @Override
      public void onLongPress(MotionEvent e) {
         e.offsetLocation(view_rect.getCv_min_x(), view_rect.getCv_min_y());
         if (Constants.DEBUG) {
            Log.i("Gestures", "Long Press");
         }
         long_press_map_x = xform_x_cv2map(Math.round(e.getX()));
         long_press_map_y = xform_y_cv2map(Math.round(e.getY()));

         Marker current = getCurrentMarker();
         if (current != null) {
            if (current.getBboxMap().contains((float) long_press_map_x,
                                              (float) long_press_map_y)) {
               return;
            }
         }
         G.map.showContextMenu();
      }
      
      @Override
      public boolean onSingleTapConfirmed(MotionEvent e) {
         // get nearby features
         e.offsetLocation(view_rect.getCv_min_x(), view_rect.getCv_min_y());
         double map_x = xform_x_cv2map(Math.round(e.getX()));
         double map_y = xform_y_cv2map(Math.round(e.getY()));
         
         Marker current = getCurrentMarker();
         if (current != null) {
            if (current.getBboxMap().contains((float)map_x, (float)map_y)) {
               return true;
            }
         }
         
         ArrayList<Geofeature> nearby_features = getNearbyGeofeatures(
                     new PointD(map_x, map_y),
                     Math.round(Constants.NEARBY_GEOFEATURE_PIXEL_DISTANCE *
                        getResources().getDisplayMetrics().density));
         featuresDeselect();
         G.map.featuresDiscard(Constants.MAP_MARKER_LAYER);
         // if more than 0, show context menu
         if (nearby_features.size() > 0) {
            // Create new marker
            Marker m = new Marker(nearby_features.get(0),
                                  new PointD(map_x, map_y));
            nearby_features.get(0).selected = true;
            G.map.featuresDiscard(m.getZplus());
            G.map.featureAdd(m);
            // move map to properly display marker
            G.map.lookAtLazy(m);
            return true;
         } else {
            return false;
         }
      }
   }
   
}

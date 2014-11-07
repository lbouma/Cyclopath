/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.util.PointD;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.graphics.RectF;
import android.location.Location;

/**
 * This is the pointer that shows the user's location and bearing.
 * @author Phil Brown
 * @author Fernando Torre
 */
public class MapPointer implements Feature {

   /** Map coordinates of the MapPointer*/
   private PointD coords;
   /** The image to draw*/
   private Bitmap image;
   /** Used for obtaining resources from res/drawable */
   private Context context;
   /** The angle between two points on the map*/
   private float bearing;
   /** The accuracy of the location fix, in meters */
   private float accuracy;
      
   /** Initialized the MapPointer object and sets coords to (0,0) so they are
    * not null. */
   public MapPointer(Context c){
     this.coords = new PointD(0, 0);
     this.context = c;
     this.bearing = 0;
     this.accuracy = 0;
     // default image
     this.setImage(R.drawable.map_pointer);
   }//MapPointer
   
   // *** Getters and setters
   
   /**
    * Sets the accuracy of the location fix, in meters.
    */
   public void setAccuracy(float accuracy) {
      this.accuracy = accuracy;
   }
   
   /** Gets the image resource id*/
   public Bitmap getImage(){
      return this.image;
   }//getImage
   
   /** Sets the bitmap image and scales it down.*/
   public void setImage(int res){
      this.image = BitmapFactory.decodeResource(context.getResources(), res);
   }//setImage
   
   /** Returns the current position*/
   public PointD getPosition(){
      return this.coords;
   }//getPosition
   
   /** Updates {@link #coords coords}
    * @param location where to draw the image */
   public void setPosition(Location location){
      if (location != null) {
         this.coords = G.latlonToMap(location);
      }
   }//setPosition

   /** Updates {@link #coords coords}
    * @param x The map x-coordinate for where to draw the image
    * @param y The map y-coordinate for where to draw the image */
   public void setPosition(float x, float y){
      this.coords = new PointD(x, y);
   }//setPosition

   /** Returns a rect object using {@link #coords coords} and the size of 
    * {@link #image image}*/
   @Override
   public RectF getBboxMap() {
      int half_h = this.image.getHeight()/2;
      int half_w = this.image.getWidth()/2;
      return new RectF((float) this.coords.x-half_w,
                       (float) this.coords.y+half_h, 
                       (float) this.coords.x+half_w,
                       (float) this.coords.y-half_h);
   }//getBboxMap

   /** Returns the Map_Layer on which this object is drawn*/
   @Override
   public float getZplus() {
      return Constants.MAP_POINTER_LAYER;
   }//getZplus

   /** Sets the user's bearing based on the current and previous locations. The
    * math is latitude and longitude bearing calculations.
    * @param one the user's previous location
    * @param two the user's current location */
   public void setBearing(Location one, Location two){
      if (one == null || two == null) {
         this.bearing = 0;
         return;
      }
      double lat1 = one.getLatitude();
      double lon1 = one.getLongitude();
      double lat2 = two.getLatitude();
      double lon2 = two.getLongitude();
      double deltaLon = lon2-lon1;
      double y = Math.sin(deltaLon) * Math.cos(lat2);
      double x = Math.cos(lat1)*Math.sin(lat2)
                 - Math.sin(lat1)*Math.cos(lat2)*Math.cos(deltaLon);
      this.bearing = (float) Math.toDegrees(Math.atan2(y, x));
   }//setBearing
   
   /**
    * Sets the bearing for the map pointer if it is different enough from the
    * previous bearing value.
    * @param bearing new bearing
    * @return true if the bearing was modified.
    */
   public boolean setBearing(float bearing) {
      if (Math.abs(this.bearing - bearing)
            > Constants.SIGNIFICANT_BEARING_DIFFERENCE) {
         this.bearing = bearing;
         return true;
      } else {
         return false;
      }
   }
   
   // *** Other methods

   /** No-op */
   @Override
   public void cleanup() {}

   /**
    * Rotates and draws the pointer
    */
   @Override
   public void draw() {
      if(this.coords == null){
         return; 
      } 
      if(this.image == null){
         setImage(R.drawable.map_pointer);
      }
      
      int x = G.map.xform_x_map2cv(this.coords.x);
      int y = G.map.xform_y_map2cv(this.coords.y);
      
      // Draw accuracy circle first.
      float radius = this.accuracy * (float) G.map.getScale();
      G.map.drawCircle(x, y, radius,
                       Constants.ACCURACY_CIRCLE_STROKE_WIDTH,
                       Constants.ACCURACY_CIRCLE_FILL_COLOR,
                       Constants.ACCURACY_CIRCLE_STROKE_COLOR);
      
      Matrix matrix = new Matrix();
      matrix.postRotate(this.bearing, (this.image.getWidth() / 2), 
                       (this.image.getHeight() / 2));
      matrix.postTranslate(x - (image.getWidth() / 2),
                           y - (image.getHeight() / 2)); 
      G.map.map_canvas.drawBitmap(this.image, matrix, null);
   }//draw

   /** No-op */
   @Override
   public void drawShadow() {}

   @Override
   public boolean init() {
      return true;
   }

   /** This feature cannot be discarded*/
   @Override
   public boolean isDiscardable() {
      return false;
   }//isDiscardable

}//MapPointer

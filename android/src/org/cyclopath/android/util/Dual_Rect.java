/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import org.cyclopath.android.G;

import android.graphics.RectF;

/**
 * A Dual_Rect object is an orthogonal rectangle which knows its coordinates
 * in both canvas space and map space. This class is a modified version of
 * flashclient/Dual_Rect.as.</br>
 * For canvas coordinates y increases from top to bottom and for
 * map coordinates y increases from bottom to top.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class Dual_Rect {
   
   /** location of left side in map coordinates */
   private double map_min_x;
   /** location of bottom side in map coordinates */
   private double map_min_y;
   /** location of right side in map coordinates */
   private double map_max_x;
   /** location of top side in map coordinates */
   private double map_max_y;
   
   /** Default Constructor */
   public Dual_Rect() {
      this.map_min_x = 0;
      this.map_min_y = 0;
      this.map_max_x = 0;
      this.map_max_y = 0;
   }

   /** Get location of left side in map coordinates. */
   public double getMap_min_x() {
      return this.map_min_x;
   }
   /** Set location of left side in map coordinates. */
   public void setMap_min_x(double x) {
      this.map_min_x = x;
   }
   /** Get location of bottom side in map coordinates. */
   public double getMap_min_y() {
      return this.map_min_y;
   }
   /** Set location of bottom side in map coordinates. */
   public void setMap_min_y(double y) {
      this.map_min_y = y;
   }
   
   /** Get location of right side in map coordinates. */
   public double getMap_max_x() {
      return this.map_max_x;
   }
   /** Set location of right side in map coordinates. */
   public void setMap_max_x(double x) {
      this.map_max_x = x;
   }
   /** Get location of top side in map coordinates. */
   public double getMap_max_y() {
      return this.map_max_y;
   }
   /** Set location of top side in map coordinates. */
   public void setMap_max_y(double y) {
      this.map_max_y = y;
   }
   
   /** Get width in map coordinates.*/
   public double getMapWidth() {
      return this.map_max_x - this.map_min_x;
   }
   /** Get height in map coordinates.*/
   public double getMapHeight() {
      return this.map_max_y - this.map_min_y;
   }
   
   /** Get location of center x in map coordinates.*/
   public double getMap_center_x() {
      return this.map_min_x + this.getMapWidth()/2;
   }
   /** Get location of center y in map coordinates.*/
   public double getMap_center_y() {
      return this.map_min_y + this.getMapHeight()/2;
   }

   /** Get location of left side in canvas coordinates. */
   public int getCv_min_x() {
      return G.map.xform_x_map2cv(this.map_min_x);
   }
   /** Set location of left side in canvas coordinates. */
   public void setCv_min_x(int x) {
      this.map_min_x = G.map.xform_x_cv2map(x);
   }
   /** Get location of top side in canvas coordinates. */
   public int getCv_min_y() {
      return G.map.xform_y_map2cv(this.map_max_y);
   }
   /** Set location of top side in canvas coordinates. */
   public void setCv_min_y(int y) {
      this.map_max_y = G.map.xform_y_cv2map(y);
   }
   
   /** Get location of right side in canvas coordinates. */
   public int getCv_max_x() {
      return G.map.xform_x_map2cv(this.map_max_x);
   }
   /** Set location of right side in canvas coordinates. */
   public void setCv_max_x(int x) {
      this.map_max_x = G.map.xform_x_cv2map(x);
   }
   /** Get location of bottom side in canvas coordinates. */
   public int getCv_max_y() {
      return G.map.xform_y_map2cv(this.map_min_y);
   }
   /** Set location of bottom side in canvas coordinates. */
   public void setCv_max_y(int y) {
      this.map_min_y = G.map.xform_y_cv2map(y);
   }
   
   /** Get width in canvas coordinates. */
   public int getCvWidth() {
      return this.getCv_max_x() - this.getCv_min_x();
   }
   /** Get height in canvas coordinates. */
   public int getCvHeight() {
      return this.getCv_max_y() - this.getCv_min_y();
   }
   
   /** Get location of center x in canvas coordinates. */
   public int getCv_center_x() {
      return this.getCv_min_x() + this.getCvWidth()/2;
   }
   /** Get location of center y in canvas coordinates. */
   public int getCv_center_y() {
      return this.getCv_min_y() + this.getCvHeight()/2;
   }
   
   
   // ** Other methods
   
   /** 
    * Checks if this rect contains point in map coordinates.
    * @param x x map coordinate of point.
    * @param y y map coordinate of point.
    * @return True if this rect contains the point.
    */
   public boolean contains_map_point(double x, double y) {
      return (this.map_min_x <= x && this.map_max_x >= x &&
              this.map_min_y <= y && this.map_max_y >= y);
   }
   
   /** 
    * Checks if this rect contains point in canvas coordinates.
    * @param x x canvas coordinate of point.
    * @param y y canvas coordinate of point.
    * @return True if this rect contains the point.
    */
   public boolean contains_canvas_point (int x, int y) {
      return this.contains_map_point(G.map.xform_x_cv2map(x),
                                     G.map.xform_y_cv2map(y));
   }
   
   /** 
    * Creates a copy of this rect but expanded on each side.
    * @param n number of pixels to extend this rect by.
    * @return rect like this one expanded by n pixels on each side.
    */
   public Dual_Rect buffer(int n) {
      Dual_Rect r = new Dual_Rect();
      r.setCv_min_x(this.getCv_min_x() - n);
      r.setCv_min_y(this.getCv_min_y() - n);
      r.setCv_max_x(this.getCv_max_x() + n);
      r.setCv_max_y(this.getCv_max_y() + n);
      return r;
   }
   
   /** 
    * Creates a copy of this rect.
    * @return copy of this rect
    */
   @Override
   public Dual_Rect clone() {
      return this.buffer(0);
   }

   /** 
    * Verifies if this rect is equal to another rect. </br>
    * FIXME (from Flash code): This method is not numerically reliable.
    * @param r rect to compare with
    * @return True if this rect is equal to the given rect, false
    * otherwise.
    */
   public boolean eq(Dual_Rect r) {
      return (r != null && (   this.getCv_min_x() == r.getCv_min_x()
                            && this.getCv_min_y()== r.getCv_min_y()
                            && this.getCv_max_x() == r.getCv_max_x()
                            && this.getCv_max_y() == r.getCv_max_y()));
   }

   /** 
    * Return the intersection of this rect with another rect.
    * @param r rect to intersect with this rect.
    * @return The intersection of this rect and r if it exists. Otherwise,
    * return null.
    */
   public Dual_Rect intersection(Dual_Rect r) {
      Dual_Rect p;
      
      if (!this.intersects(r)) {
         // intersection empty
         return null;
      } else {
         // intersection nonempty
         p = new Dual_Rect();
         p.setMap_min_x(Math.max(this.getMap_min_x(), r.getMap_min_x()));
         p.setMap_min_y(Math.max(this.getMap_min_y(), r.getMap_min_y()));
         p.setMap_max_x(Math.min(this.getMap_max_x(), r.getMap_max_x()));
         p.setMap_max_y(Math.min(this.getMap_max_y(), r.getMap_max_y()));
         return p;
      }
   }

   /** 
    * Checks whether this rect intersects another rect.
    * @param r rect to compare with this rect.
    * @return True if this rect intersects r, false otherwise.
    */
   public boolean intersects(Dual_Rect r) {
      return (r != null
              && this.getMap_max_x() > r.getMap_min_x()
              && this.getMap_min_x() < r.getMap_max_x()
              && this.getMap_max_y() > r.getMap_min_y()
              && this.getMap_min_y() < r.getMap_max_y());
   }
   
   /** 
    * Checks wheter this rect intersects with a regular map rectangle.
    * @param r rectangle in map coordinates to compare with this rect.
    * @return True if this rect intersects r, false otherwise.
    */
   public boolean interstects_map_rect(RectF r) {
      return (   this.map_max_x > r.left && this.map_min_x < r.right
              && this.map_max_y > r.top && this.map_min_y < r.bottom);
   }

   /** 
    * Moves this rect x pixels right and y pixels down.
    * @param x Number of pixels to move right (can be negative).
    * @param y Number of pixels to move down (can be negative).
    */
   public void move(int x, int y) {
      this.setCv_min_x(this.getCv_min_x() + x);
      this.setCv_min_y(this.getCv_min_y() + y);
      this.setCv_max_x(this.getCv_max_x() + x);
      this.setCv_max_y(this.getCv_max_y() + y);
   }

   /** 
    * Moves this rect to x,y in canvas coordinates.
    * @param x Location of x in canvas coordiantes.
    * @param y Location of y in canvas coordiantes.
    */
   public void moveto(int x, int y) {
      this.setCv_max_x(x + this.getCvWidth());
      this.setCv_max_y(y + this.getCvHeight());
      this.setCv_min_x(x);
      this.setCv_min_y(y);
   }

   /** 
    * Return the union of myself and r; if r is null, return a copy of
    * myself. (Note: Strictly speaking, this does not return the union of
    * the two rectangles, but rather the smallest rectangle containing the
    * union. This is because the true union gets tricky to calculate and
    * use -- it's not a rectangle itself -- both here and in other parts of
    * the program.)
    * @param r rect to join with this rect.
    * @return union of this rect and r.
    */
   public Dual_Rect union(Dual_Rect r) {
      Dual_Rect p;

      if (r == null) {
         return this.clone();
      } else {
         p = new Dual_Rect();
         p.setMap_min_x(Math.min(this.getMap_min_x(), r.getMap_min_x()));
         p.setMap_min_y(Math.min(this.getMap_min_y(), r.getMap_min_y()));
         p.setMap_max_x(Math.max(this.getMap_max_x(), r.getMap_max_x()));
         p.setMap_max_y(Math.max(this.getMap_max_y(), r.getMap_max_y()));
         return p;
      }
   }

   /** 
    * Return the map bounds of myself in the format required for the GWIS
    * bbox parameter.
    * @return string version of map bounds.
    */
   public String get_gwis_bbox_str()
   {
      return (        this.getMap_min_x() + "," + this.getMap_min_y()
              + "," + this.getMap_max_x() + "," + this.getMap_max_y());
   }

}

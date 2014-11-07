/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

/**
 * A bearing describes route directions in relation to the angles made by their
 * intersections.
 * @author Fernando Torre
 */
public class Bearing {
   
   /** The bearing's relative direction (left, right, etc.) */
   private String relative_direction;
   /** The bearing's compass direction (north, east, etc.) */
   private String compass_direction;
   /** The angle of the bearing */
   private int angle;
   /** The icon for the bearing */
   private int image_id;

   /**
    * Constructor.
    * @param r_dir relative direction
    * @param m_dir compass direction
    * @param angle angle
    * @param img icon
    */
   public Bearing(String r_dir, String c_dir, int angle, int img) {
      this.setRelativeDirection(r_dir);
      this.setCompassDirection(c_dir);
      this.setAngle(angle);
      this.setImageId(img);
   }
   
   // *** Setters and Getters
   
   public void setAngle(int angle) {
      this.angle = angle;
   }

   public int getAngle() {
      return angle;
   }

   public void setCompassDirection(String compass_direction) {
      this.compass_direction = compass_direction;
   }

   public String getCompassDirection() {
      return compass_direction;
   }

   public void setImageId(int img) {
      this.image_id = img;
   }

   public int getImageId() {
      return image_id;
   }

   public void setRelativeDirection(String relative_direction) {
      this.relative_direction = relative_direction;
   }

   public String getRelativeDirection() {
      return relative_direction;
   }
}

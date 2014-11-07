/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Conf;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.util.PointD;

/**
 * This class represents a direction in a route.
 * @author Fernando Torre
 */
public class DirectionStep {

   /** relative direction of turn */
   public int rel_direction;
   /** absolute direction of turn */
   public int abs_direction;
   /** Distance traveled this step */
   public float rel_distance;
   /** Name of path traveled this step */
   public String name;
   /** previous step */
   public DirectionStep previous;
   /** type of byway */
   public int type;
   /** map coordinates of where this direction starts. */
   public PointD start_point;
   /** Landmark for this step */
   public Geopoint landmark;
   /** Angle between initial direction when entering this step and landmark,
    * used for knowing whether the landmark is to the left or right, before
    * or after the intersection. */
   public double landmark_angle;

   /**
    * Constructor
    * @param rel_direction relative direction of turn
    * @param abs_direction absolute direction of turn
    * @param rel_distance distance traveled this step
    * @param name name of path traveled this step
    * @param prev previous direction
    * @param start_point map coordinates for this direction
    */
   public DirectionStep(int rel_direction, int abs_direction, 
                            float rel_distance, String name, 
                            DirectionStep prev, PointD start_point,
                            Geopoint landmark, double landmark_angle) {
      this.rel_direction = rel_direction;
      this.abs_direction = abs_direction;
      this.rel_distance = rel_distance;
      this.name = name;
      this.previous = prev;
      this.start_point = start_point;
      this.landmark = landmark;
      this.landmark_angle = landmark_angle;
   }

   /**
    * Total distance of route up to this direction.
    * @return total distance
    */
   public float getAbsDistance()  {
      if (previous != null)
         return previous.rel_distance + previous.getAbsDistance();
      else
         return 0;
   }

   /**
    * String version of distance for this direction.
    */
   public String getStepDistance() {
      if (this.isLast())
         return "--";
      return G.getFormattedLength(this.rel_distance);
   }

   /**
    * String version of total distance of route up to this direction
    */
   public String getTotalDistance() {
      return G.getFormattedLength(this.getAbsDistance());
   }

   /**
    * Returns true if this is the first direction.
    */
   public boolean isFirst() {
      return this.rel_direction == Constants.BEARINGS.length - 2;
   }

   /**
    * Returns true if this is the last direction.
    */
   public boolean isLast() {
      return this.rel_direction == Constants.BEARINGS.length - 1;
   }

   /**
    * Returns the direction text for this direction.
    */
   public String text() {
      String name =
         String.format(G.app_context.getString(R.string.direction_unnamed),
                       Conf.geofeature_layer_by_id.get(this.type));
      String pname;
      if (this.name != null && !this.name.equals("")) {
         name = this.name;
      }
      if (this.isLast()) {
         return String.format(G.app_context.getString(R.string.direction_end),
                              name.toUpperCase());
      }
      if (this.isFirst()) {
         return String.format(
               G.app_context.getString(R.string.direction_start),
               Constants.BEARINGS[this.abs_direction].getCompassDirection(),
               name.toUpperCase());
      }
      if (this.previous.name != null && !this.previous.name.equals("")) {
         pname = this.previous.name;
      } else {
         pname = String.format(
               G.app_context.getString(R.string.direction_unnamed),
               Conf.geofeature_layer_by_id.get(this.previous.type));
      }
      if (name == pname) {
         return String.format(
               G.app_context.getString(R.string.direction_continue),
               Constants.BEARINGS[this.abs_direction].getCompassDirection(),
               name.toUpperCase());
      }
      if (Constants.BEARINGS[this.rel_direction].getRelativeDirection().equals(
            G.app_context.getString(R.string.bearing_backward))) {
         return String.format(
               G.app_context.getString(R.string.direction_backward),
               Constants.BEARINGS[this.rel_direction].getRelativeDirection(),
               Constants.BEARINGS[this.abs_direction].getCompassDirection(),
               name.toUpperCase());
      }
      if (!Constants.BEARINGS[this.rel_direction].getRelativeDirection()
            .equals(G.app_context.getString(R.string.bearing_forward))) {
         if (this.landmark == null) {
            return String.format(
               G.app_context.getString(R.string.direction_forward),
               Constants.BEARINGS[this.rel_direction].getRelativeDirection(),
               Constants.BEARINGS[this.abs_direction].getCompassDirection(),
               name.toUpperCase());
         } else {
            String side =
                  (this.landmark_angle > 90
                   && this.landmark_angle < 270) ?
                           G.app_context.getString(R.string.bearing_left) :
                           G.app_context.getString(R.string.bearing_right);
            String when =
                  (this.landmark_angle > 0
                   && this.landmark_angle < 180) ?
                           G.app_context.getString(R.string.direction_before) :
                           G.app_context.getString(R.string.direction_after);
            return String.format(
               G.app_context.getString(R.string.direction_forward_landmark),
               Constants.BEARINGS[this.rel_direction].getRelativeDirection(),
               Constants.BEARINGS[this.abs_direction].getCompassDirection(),
               name.toUpperCase(),
               when,
               this.landmark.name,
               side);
         }
      }

      return String.format(
            G.app_context.getString(R.string.direction_changes),
            pname.toUpperCase(),
            name.toUpperCase());
   }
}

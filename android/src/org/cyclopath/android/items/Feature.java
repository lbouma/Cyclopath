/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import android.graphics.RectF;

/**
 * Interface for map features.
 * @author Fernando Torre
 * @author Phil Brown
 */
public interface Feature {
   
   /**
    * Cleans up the feature. For example, removes it from hashmaps and cleans
    * up any dependent features.
    */
   public void cleanup();
   
   /** Draws the feature.*/
   public abstract void draw();
   
   /** Draws the feature's shadow, if any.*/
   public void drawShadow();
   
   /** Gets the bounding box for this feature, in map coordinates.*/
   public abstract RectF getBboxMap();
   
   /** Return the z level for this feature. The z level is the position of a
    * feature with respect to other features on z axis. Features with a higher
    * z will be drawn on top of features with a lower z. */
   public abstract float getZplus();
   
   /**
    * Initializes the feature. For example, adds it to the corresponding
    * hashmaps and sets dependent features. Returns true if feature was
    * initialized correctly.
    */
   public boolean init();
   
   /**
    * Returns true if this feature can be discarded. If false, feature has to
    * be discarded manually.
    */
   public abstract boolean isDiscardable();
}

/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.conf;

/**
 * This class represents drawing parameters for a given draw class and zoom.
 * @author Fernando Torre
 */
public class ZoomParam {
   
   /** width of object lines */
   public float width;
   /** whether this object has a label */
   public boolean label;
   /** object label size */
   public float label_size;
   
   /**
    * Default constructor.
    */
   public ZoomParam() {
      width = 0;
      label = false;
      label_size = 0;
   }

}

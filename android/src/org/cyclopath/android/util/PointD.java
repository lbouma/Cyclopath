/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.util;

/**
 * This class represents a point using values of type double.
 * @author Fernando
 */
public class PointD {
   
   public double x;
   public double y;

   /**
    * Constructor
    */
   public PointD(double x, double y) {
      this.x = x;
      this.y = y;
   }
   
   @Override
   public String toString() {
      return "(" + this.x + ", " + this.y + ")";
   }
}

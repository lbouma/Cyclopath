/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Objects which live in both canvas and map space and have a minimum
// orthogonal bounding rectangle implement this.
//
// Note: This MOBR includes _only_ the mathematical abstraction of the
// object's geometry, not any on-screen adornments such as line width or
// labels.

package utils.geom {

   public interface MOBRable_DR
   {
      function get mobr_dr() :Dual_Rect;
   }

}


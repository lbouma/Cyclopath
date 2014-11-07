/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Objects which have a minimum orthogonal bounding box should implement this
// message. In particular, objects in an R-Tree implement this.

package utils.geom {

   import flash.geom.Rectangle;

   // EXPLAIN: What's MOBR stand for? Minimum Orthogonal Bounding Rectangle?
   public interface MOBRable
   {
      function get mobr() :Rectangle;
   }

}


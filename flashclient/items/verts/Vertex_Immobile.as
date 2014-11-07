/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// MAYBE: This file is not used. Delete it.

package items.verts {

   import items.Geofeature;

   public class Vertex_Immobile extends Vertex {

      // *** Constructor

      public function Vertex_Immobile(index:int, parent:Geofeature)
      {
         super(index, parent);
      }

      // *** Instance methods

      // No visualization.
      override public function draw() :void
      {
         // No-op
      }

      // No drag.
      override public function drag(xdelta:Number, ydelta:Number) :void
      {
         // No-op
      }

   }
}


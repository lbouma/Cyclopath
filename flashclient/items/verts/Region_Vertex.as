/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.verts {

   import flash.display.Graphics;
   import mx.utils.ColorUtil;

   import items.Geofeature;
   import views.commands.Vertex_Move;

   public class Region_Vertex extends Vertex {

      // *** Constructor

      public function Region_Vertex(index:int, parent:Geofeature)
      {
         super(index, parent);
      }

      // *** Instance methods

      //
      override public function drag(xdelta:Number, ydelta:Number) :void
      {
         // Make copies for two arrays for the Vertex_Move object to have.
         var drag_parents:Array = Vertex.selected_parents;
         var drag_indices:Array = Vertex.selected_coord_indices;
         var parent:Geofeature;
         var i:int;
         var j:int;

         // Make copies of the arrays now, since the two fcns.,
         // Vertex.selected_*, already make copies; we don't want to do
         // unnecessary.
         var drag_parents_copy:Array = Vertex.selected_parents;
         var drag_indices_copy:Array = Vertex.selected_coord_indices;

         // If we are the start or end vertex, bring the end or start vertex
         // along as well. For regions these are supposed to be the
         // same vertex.

         m4_ASSERT(this.selected);
         this.deselect_needed = false;

         for (i = 0; i < drag_parents_copy.length; i++) {
            parent = drag_parents_copy[i];
            j = drag_indices_copy[i];

            if (j == 0) {
               if (!parent.vertices[parent.xs.length - 1].selected) {
                  drag_parents.push(parent);
                  drag_indices.push(parent.xs.length - 1);
               }
            }
            else if (j == parent.xs.length - 1) {
               if (!parent.vertices[0].selected) {
                  drag_parents.push(parent);
                  drag_indices.push(0);
               }
            }
         }

         var cmd:Vertex_Move;
         cmd = new Vertex_Move(drag_parents, drag_indices, xdelta, ydelta);
         G.map.cm.do_(cmd);
         // The Vertex_Move command doesn't hydrate/lazy-load items, so
         // is_prepared is always non-null.
         m4_ASSERT_SOFT(cmd.is_prepared !== null);
      }

   }
}


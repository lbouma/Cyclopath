/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Dirty_Reason;
   import utils.misc.Logging;

   public class Vertex_Delete extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Vtx_Del');

      // *** Instance variables

      protected var indices:Array;  // indices of old vertices before deletion
      protected var xs_old:Array;   //    map xs of old vertices
      protected var ys_old:Array;   //    map ys of old vertices

      // *** Constructor

      public function Vertex_Delete(parents:Array, indices:Array) :void
      {
         var i:int;

         super(parents, Dirty_Reason.item_data);

         // We can use any panel that has all parents selected, even if other
         // items are also selected.
         this.loose_selection_set = true;

         this.indices = indices;
         this.xs_old = new Array(this.edit_items.length);
         this.ys_old = new Array(this.edit_items.length);
         for (i = 0; i < this.edit_items.length; i++) {
            this.xs_old[i] = this.edit_items[i].xs[this.indices[i]];
            this.ys_old[i] = this.edit_items[i].ys[this.indices[i]];
         }
      }

      // *** Instance methods

      //
      override public function do_() :void
      {
         var i:int;

         super.do_();

         // work downward so stored indices stay valid in the face of bubbling
         for (i = this.edit_items.length - 1; i >= 0; i--) {
            this.edit_items[i].vertex_delete_at(this.indices[i]);
            this.edit_items[i].draw_all();
         }
      }

      //
      override public function undo() :void
      {
         var i:int;

         super.undo();

         // work upward so stored indices stay valid in the face of bubbling
         for (i = 0; i < this.edit_items.length; i++) {
            this.edit_items[i].vertex_insert_at(this.indices[i],
                                           this.xs_old[i], this.ys_old[i]);
            this.edit_items[i].draw_all();
         }
      }

   }
}


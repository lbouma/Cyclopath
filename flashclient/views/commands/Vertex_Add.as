/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Dirty_Reason;
   import items.Geofeature;
   import utils.misc.Logging;

   public class Vertex_Add extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Vtx_Add');

      // *** Instance variables

      public var vtx_index:int;  // index of new vertex after insertion

      protected var x:Number;    // map x of new vertex
      protected var y:Number;    // map y of new vertex

      protected var merged_split:views.commands.Byway_Split;

      // *** Constructor

      // x,y in map coordinates
      public function Vertex_Add(parent:Geofeature,
                                 vtx_index:int,
                                 x:Number,
                                 y:Number) :void
      {
         super([parent,], Dirty_Reason.item_data);

         // This isn't technically true: this class is mergeable because it
         // consumes Vertex_Move cmds.
         this.mergeable = true;

         this.loose_selection_set = true;

         this.vtx_index = vtx_index;
         this.x = x;
         this.y = y;

         this.merged_split = null;
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         return 'add vertex';
      }

      // ***

      // This fcn. is called to merge a Vertex_Move command, after the user has
      // finished dragging the vertex around.
      override public function merge_from(other:Command_Base) :Boolean
      {
         var ovm:Vertex_Move = (other as Vertex_Move);
         var split:views.commands.Byway_Split
            = (other as views.commands.Byway_Split);

         // This check verifies that the move affected the vertex that this
         // command added.
         if ((ovm !== null)
             && (ovm.mergeable) //? what is this not true?
             && (ovm.edit_items.length == 1) //? what is this not true?
             //? etc.?
             && (ovm.edit_items[0] === this.edit_items[0])
             && (ovm.vert_is[0] === this.vtx_index)) {
            this.x += ovm.xdelta;
            this.y += ovm.ydelta;
            return true;
         }
         else {
            if ((split !== null)
                && (split.mergeable)
                && (split.spl_index === this.vtx_index)
                && (this.merged_split === null)) {
               this.merged_split = split;
               return true;
            }
            else {
               return false;
            }
         }
      }

      // ***

      //
      override public function do_() :void
      {
         super.do_();

         this.edit_items[0].vertex_insert_at(this.vtx_index, this.x, this.y);
         this.edit_items[0].draw_all();

         if (this.merged_split !== null) {
            this.merged_split.do_();
         }
      }

      //
      override public function undo() :void
      {
         // the split must be performed first
         if (this.merged_split !== null) {
            this.merged_split.undo();
         }
         super.undo();
         this.edit_items[0].vertex_delete_at(this.vtx_index);
         this.edit_items[0].draw_all();
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Dirty_Reason;
   import items.Geofeature;
   import utils.misc.Collection;
   import utils.misc.Logging;

   public class Vertex_Move extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Vtx_Mov');

      // *** Instance variables

      public var xdelta:Number;  // map coordinates
      public var ydelta:Number;  // map coordinates
      public var vert_is:Array;  // vertex indices

      // *** Constructor

      // (xdelta, ydelta) is canvas coordinates. feats is points, line segments
      // or polygons (homogeneous, and, i.e., Points, Byways or Regions).
      // BUG nnnn: Support for editing Terrain (and derive Terrain and Region
      //           from common Polygon or something base class).
      public function Vertex_Move(feats:Array,
                                  vert_is:Array,
                                  xdelta:Number,
                                  ydelta:Number) :void
      {
         m4_ASSERT(feats !== null);

         super(feats, Dirty_Reason.item_data);

         // This class is mergeable because it is consumed by a new Vertex_Add.
         this.mergeable = true;

         // This command can use any panel that at least has all feats
         // selected, but it doesn't care if there are other feats selected.
         this.loose_selection_set = true;
// BUG_FALL_2013: Select two vertices and drag an endpoint that's
//                not the shared endpoint, i.e., drag the end of 
//                one of the selected byways, and the other byway
//                is deselected.
// http://bugs.cyclopath.org/show_bug.cgi?id=2806
//                So loose_selection_set is not working right?

         this.vert_is = vert_is;
         this.xdelta = G.map.xform_xdelta_cv2map(xdelta);
         this.ydelta = G.map.xform_ydelta_cv2map(ydelta);
      }

      // *** Instance methods

      //
      override public function activate_panel_do_() :void
      {
         m4_TALKY('activate_panel_do_');
         // The first this command runs, we can keep the selection set active,
         // even if it contains geofeatures who's vertices are not being moved.
         // But if this is a do_ and an undo, we want to just select those
         // geofeatures whose vertices were moved.
         var loose_selection_set:Boolean = (this.undone === null);
         this.activate_appropriate_panel(loose_selection_set);
      }

      //
      override public function activate_panel_undo() :void
      {
         m4_TALKY('activate_panel_undo');
         var loose_selection_set:Boolean = false;
         this.activate_appropriate_panel(loose_selection_set/*=false*/);
      }

      //
      override public function get descriptor() :String
      {
         return 'vertex move';
      }

      //
      override public function do_() :void
      {
         var i:int;
         var feat:Geofeature;

         super.do_();

         for (i = 0; i < this.edit_items.length; i++) {
            feat = (this.edit_items[i] as Geofeature);
            this.move_do(feat, i);
            feat.draw_all();
         }
      }

      // NOTE: This might not precisely reconstruct the previous coordinates
      // of each point due to floating point error. However, it will get
      // plenty close, and as we reset the dirty flag, tiny geometry changes
      // won't leak into the database.
      override public function undo() :void
      {
         var i:int;
         var feat:Geofeature

         super.undo();

         // must proceed in reverse order so that existing byway intersections
         // are replaced in the order they were removed
         for (i = this.edit_items.length - 1; i >= 0; i--) {
            feat = (this.edit_items[i] as Geofeature);
            this.move_undo(feat, i);
            feat.draw_all();
         }
      }

      // ***

      //
      override public function merge_from(other:Command_Base) :Boolean
      {
         if ((other === null)
             || (!(this.mergeable))
             || (!(other.mergeable))
             || (!(other is Vertex_Move))
             || (!(Collection.array_eq(other.edit_items, this.edit_items)))
             || (!(Collection.array_eq(
                     (other as Vertex_Move).vert_is, this.vert_is)))) {
            return false;
         }

         // merge
         this.xdelta += (other as Vertex_Move).xdelta;
         this.ydelta += (other as Vertex_Move).ydelta;
         return true;
      }

      //
      protected function move_do(feat:Geofeature, i:int) :void
      {
         feat.vertex_move(this.vert_is[i], this.xdelta, this.ydelta);
      }

      //
      protected function move_undo(feat:Geofeature, i:int) :void
      {
         feat.vertex_move(this.vert_is[i], -this.xdelta, -this.ydelta);
      }

      //
      override protected function get prepares_items() :Boolean
      {
         return false;
      }

   }
}


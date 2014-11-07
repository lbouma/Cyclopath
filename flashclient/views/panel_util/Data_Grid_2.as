/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// http://cookbooks.adobe.com/post_How_to_change_datagrid_s_row_background_color_-12548.html

package views.panel_util {

   import mx.controls.DataGrid;
   import mx.controls.listClasses.ListBaseContentHolder;
   import mx.core.FlexShape;
   import flash.display.Graphics;
   import flash.display.Shape;
   import flash.display.Sprite;

   import utils.misc.Logging;
   import views.panel_discussions.Widget_Post_Renderer;

   public class Data_Grid_2 extends DataGrid {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('DtGrid_2');

      // *** Constructor

      public function Data_Grid_2()
      {
         super();
      }

      // ***

      /*
      //
      override protected function measure() :void
      {
         m4_DEBUG('measure: this.height: old:', this.height);
         super.measure();
         m4_DEBUG('measure: this.height: new:', this.height);
      }
      */

      /*
      //
      override protected function updateDisplayList(unscaledWidth:Number,
                                                    unscaledHeight:Number)
                                                    :void
      {
         m4_DEBUG('updateDisplayList: unscaledHeight: old:', unscaledHeight);
         super.updateDisplayList(unscaledWidth, unscaledHeight);
         m4_DEBUG('updateDisplayList: unscaledHeight: new:', unscaledHeight);
      }
      */

      //
      public function hack_height_reset(do_apply:Boolean=false) :int
      {
         var height_hack:int = 0;
         var num_rows:int = 0;
         var not_seen_holder:Boolean = true;
         m4_DEBUG('hack_height_reset: this.height:', this.height);
         for (var i:int = this.numChildren - 1; i >= 0; i--) {
            var contentHolder:ListBaseContentHolder = 
               (this.getChildAt(i) as ListBaseContentHolder);
            if (contentHolder !== null) {
               m4_DEBUG('hack_height_reset: list base: i:', i);
               m4_DEBUG(' .. contentHolder:', contentHolder);
               m4_DEBUG(' .. height:', contentHolder.height);
               height_hack = 0;
               for (var j:int = contentHolder.numChildren - 1; j >= 0; j--) {
                  var wpr:Widget_Post_Renderer = 
                     (contentHolder.getChildAt(j) as Widget_Post_Renderer);
                  if (wpr !== null) {
                     m4_DEBUG(' .. wpr.height:', wpr.height);
                     if (!isNaN(wpr.height)) {
                        height_hack += wpr.height;
                        num_rows += 1;
                     }
                  }
               }
               m4_DEBUG2('hack_height_reset: i:', i,
                         '/ pre-height_hack:', height_hack);
               if (height_hack > 0) {
                  // Usually this.height is set, but the rows are not
                  // populated.
                  if (num_rows > 1) {
                     height_hack += (4 * (num_rows - 1));
                  }
                  height_hack += 1;
                  if (do_apply) {
                     this.height = height_hack;
                     contentHolder.height = height_hack;
                  }
                  not_seen_holder = false;
               }
            }
            // else, may or may not_seen_holder, but no child's height is set.
         }
         //
         return height_hack;
      }

   }
}


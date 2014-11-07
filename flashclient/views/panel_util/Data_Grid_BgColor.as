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

   public class Data_Grid_BgColor extends DataGrid {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('DtGrid_BgCol');

      // *** Constructor

      public function Data_Grid_BgColor()
      {
         super();
      }

      // ***

      //
      override protected function drawRowBackground(s:Sprite,
                                                    rowIndex:int,
                                                    y:Number,
                                                    height:Number,
                                                    color:uint,
                                                    dataIndex:int)
                                                      :void
      {
         //m4_DEBUG('drawRowBackground: rowIdx:', rowIndex, '/ color:', color);

         super.drawRowBackground(s, rowIndex, y, height, color, dataIndex);

return;

// This isn't called when item is clicked...

         var contentHolder:ListBaseContentHolder
            = ListBaseContentHolder(s.parent);

         var background:Shape;
         if (rowIndex < s.numChildren) {
            background = Shape(s.getChildAt(rowIndex));
         }
         else {
            background = new FlexShape();
            background.name = "background";
            s.addChild(background);
         }

         background.y = y;

         // Height is usually as tall is the items in the row, but not if it
         // would extend below the bottom of listContent.
         var height:Number = Math.min(height, contentHolder.height - y);

         var g:Graphics = background.graphics;
         g.clear();

         var color2:uint;
         if (dataIndex < this.dataProvider.length) {
            if (this.dataProvider.getItemAt(dataIndex).color) {
               color2 = this.dataProvider.getItemAt(dataIndex).color;
               m4_DEBUG('drawRowBackground: color2/1:', color2);
            }
            else {
               color2 = color;
               m4_DEBUG('drawRowBackground: color2/2:', color2);
            }
         }
         else {
            m4_DEBUG('drawRowBackground: color2/1:', color2);
            color2 = color;
         }
         g.beginFill(color2, this.getStyle("backgroundAlpha"));
         g.drawRect(0, 0, contentHolder.width, height);
         g.endFill();
      }

   }
}


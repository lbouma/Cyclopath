/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.geom {

   import flash.display.Graphics;
   import mx.core.UIComponent;

   public class Circle extends UIComponent {

      // MAYBE: This class is not used by Cyclopath. Delete it?
      m4_ASSERT(false);

      //
      override protected function updateDisplayList(wd:Number, ht:Number) :void
      {
         var gr:Graphics = this.graphics;
         gr.clear();

         gr.lineStyle(1, 0x666666);
         gr.beginFill(0xeeeeee);

         gr.drawCircle(wd / 2 + 1, ht / 2 + 1, wd / 2);
      }

   }
}


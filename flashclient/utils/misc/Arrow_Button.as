/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class defines a button which looks like an arrow. It points up and
// relies on the rotation property to be pointed in the right direction.
// Since flex rotates around the upper left corner by default we override
// the rotation property and modify the transform matrix directly to rotate
// around the center.

package utils.misc {

   import flash.display.Graphics;
   import flash.geom.Matrix;
   import flash.events.MouseEvent;
   import mx.core.UIComponent;

   public class Arrow_Button extends UIComponent {

      protected var over:Boolean = false; // rollover state
      protected var matrix_done:Boolean = false;
      protected var _rotation:Number;

      public function Arrow_Button()
      {
         this.addEventListener(MouseEvent.MOUSE_OVER, this.mouse_over);
         this.addEventListener(MouseEvent.MOUSE_OUT, this.mouse_over);
         // FIXME: Do we need to call removeEventListener later?
      }

      override public function set rotation(r:Number) :void
      {
         this._rotation = 2 * Math.PI * (r / 360);
      }

      override public function get rotation() :Number
      {
         return this._rotation;
      }

      protected function mouse_over(event:MouseEvent) :void
      {
         this.over = (event.type == MouseEvent.MOUSE_OVER);
         this.invalidateDisplayList();
      }

      override protected function updateDisplayList(wd:Number, ht:Number) :void
      {
         if (!this.matrix_done) {
            // Ideally the transform matrix should be modified during init
            // but after the initial matrix has been set (for the concat step)
            var matrix:Matrix = new Matrix();
            matrix.translate(-wd / 2, -ht / 2);
            matrix.rotate(this._rotation);
            matrix.translate(wd / 2, ht / 2);
            matrix.concat(this.transform.matrix);
            this.transform.matrix = matrix;
            this.matrix_done = true;
         }

         var gr:Graphics = this.graphics;
         gr.clear();

         if (this.over) {
            gr.lineStyle(1, 0x0b333c);
            gr.beginFill(Conf.button_highlight);
         }
         else {
            gr.lineStyle(1, 0x0b333c);
            gr.beginFill(0xffffff);
         }
         gr.moveTo(0, ht);
         gr.lineTo(wd, ht);
         gr.lineTo(wd / 2, 0);
         gr.lineTo(0, ht);
      }

   }
}


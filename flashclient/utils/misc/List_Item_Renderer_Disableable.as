/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import mx.controls.listClasses.ListItemRenderer;

   public class List_Item_Renderer_Disableable extends ListItemRenderer {

      private var _enabled:Boolean = true;

      public function List_Item_Renderer_Disableable()
      {
         super();
      }

      //
      override public function set data(value:Object) :void
      {
         if ((value !== null)
             && (((value is XML) && (value.@enabled == 'false'))
                 || (value.enabled == false)
                 || (value.enabled == 'false'))) {
            this._enabled = false;
         }
         else {
            this._enabled = true;
         }
         super.data = value;
      }

      //
      override protected function updateDisplayList(unscaledWidth:Number,
                                                    unscaledHeight:Number)
                                                    :void
      {
         super.updateDisplayList(unscaledWidth, unscaledHeight);
         if (!this._enabled) {
            label.setColor(getStyle("disabledColor"));
         }
         else {
            label.setColor(getStyle("color"));
         }
      }

   }
}


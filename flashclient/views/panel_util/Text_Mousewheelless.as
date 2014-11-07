/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/*

CAVEAT: If you don't disable the mousewheel (scroll wheel),
        scrolling the mouse while its hovered over this Text
        causes the first line of the text to disappear (it's
        like there's a hidden newline after the text).

Thanks to Lars at Flexceptional for this solution.

http://flexceptional.blogspot.com/2011/03/flex-disable-mouse-wheel-scrolling-for.html

*/

package views.panel_util {

   import flash.events.Event;
   import flash.text.TextFieldAutoSize;
   import mx.controls.Text;
   import mx.events.FlexEvent;

   import utils.misc.Logging;

   public class Text_Mousewheelless extends Text {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Txt_Mswhllss');

      // ***

      //
      override protected function createChildren() :void
      {
         super.createChildren();

         // Get rid of unwanted scrolling. This needs to be done any time the
         // component is resized or the content changes.
         addEventListener(FlexEvent.UPDATE_COMPLETE,
                          this.updateCompleteHandler);
      }

      //
      private function updateCompleteHandler(event:Event) :void
      {
         this.textField.autoSize = TextFieldAutoSize.LEFT;
         var tempHeight:Number = this.textField.height;
         this.textField.autoSize = TextFieldAutoSize.NONE;
         this.textField.height = tempHeight + 20; // Padding 20px.
      }

   }
}


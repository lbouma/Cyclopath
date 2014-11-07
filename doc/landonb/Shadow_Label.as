/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Thanks to:
    http://www.psyked.co.uk/flex/embossed-shadowed-text-in-flex.htm
   */

/*

Add to your css:

Shadow_Label, Shadow_Button, Shadow_Text, Shadow_CheckBox
{
   shadowColor: #333333;
}

*/

package views.panel_util {

   import flash.filters.DropShadowFilter;
   import mx.controls.Label;

   import utils.misc.Logging;

   public class Shadow_Label extends Label {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#FdAwayablVB');

      // *** Instance variables

      [Inspectable(defaultValue=1)]
      public var shadowDistance:Number = 1;

      [Inspectable(defaultValue=45)]
      public var shadowAngle:Number = 45;

      [Inspectable(defaultValue=0x003333)]
      public var shadowColor:Number = 0x003333;

      [Inspectable(defaultValue=1)]
      public var shadowAlpha:Number = 1;

      [Inspectable(defaultValue=0)]
      public var shadowBlur:Number = 0;

      // ***

      public function Shadow_Label()
      {
         super();
      }

      // ***

      //
      override protected function updateDisplayList(unscaledWidth:Number,
                                                    unscaledHeight:Number)
         :void
      {
         super.updateDisplayList(unscaledWidth, unscaledHeight);
         if (getStyle("shadowDistance")) {
            shadowDistance = getStyle("shadowDistance");
         }
         if (getStyle("shadowAngle")) {
            shadowAngle = getStyle("shadowAngle");
         }
         if (getStyle("shadowColor")) {
            shadowColor = getStyle("shadowColor");
         }
         if (getStyle("shadowAlpha")) {
            shadowAlpha = getStyle("shadowAlpha");
         }
         if (getStyle("shadowBlur")) {
            shadowBlur = getStyle("shadowBlur");
         }
         textField.filters = [new DropShadowFilter(shadowDistance,
                                                   shadowAngle,
                                                   shadowColor,
                                                   shadowAlpha,
                                                   shadowBlur,
                                                   shadowBlur)];
      }

      //
      override protected function commitProperties() :void
      {
         super.commitProperties();
         textField.filters = [new DropShadowFilter(shadowDistance,
                                                   shadowAngle,
                                                   shadowColor,
                                                   shadowAlpha,
                                                   shadowBlur,
                                                   shadowBlur)];
      }

   }
}


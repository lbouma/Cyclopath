/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This is a half-assed implementation of a nullable NumericStepper (one that
// can represent the unknown value). It is half-assed for two reasons:
//
// 1. It restricts the range of valid values.
//
// 2. You cannot get to the unknown value by typing or by deleting the text.
//
// The latter happens because the baboons at Adobe made everything in
// NumericStepper private, so it's impossible to hook into anything. Perhaps
// the thing to do is simply copy and paste the NumericStepper.as file and
// hack it directly. Adobe, you suck. ([lb] notes that [rp] wrote this.)
//
// To use: set "minimum" to one step BELOW the minimum value. Values less than
// or equal to "minimum" will be used to represent unknown.

package utils.misc {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import mx.controls.NumericStepper;
   import mx.events.FlexEvent;

   public class NumericStepper_Nullable extends NumericStepper {

      // Class attributes.

      protected static var log:Logging = Logging.get_logger('NumericStp_N');

      // BUGBUG in FLEXFLEX: Maximum and minimum values cause weird behavior!
      //
      // Flex defaults the minimum and maximum value of new NumericSteppers to
      // 0 and 10, respectively, but the documentation doesn't mention what the
      // minimum or maximum valid values are.
      //
      // I [lb] first tried (-Number.MAX_VALUE + 1) and (Number.MAX_VALUE),
      // but these cause weird behavior. Trial and error led me to the
      // following acceptable limits (Firefox 3.6.14, Flash 10.1 r102,
      // Fedora Core 14):
      //
      // -4503599627370496 is minimum limit; the user can manually enter a
      //                   smaller number, but then weird behaviour happens.
      //  4503599627370496 is the maxmimum limit; the user can use the arrow
      //                   key to get to a bigger number, or they can manually
      //                   enter a larger number, but then weird things happen.
      //
      // Per weird behavior, sometimes, the stepper converts the ordinal to
      // scientific notation, e.g., -1.79769313486231e+308. Other times, the
      // arrow keys will increment or decrement the value by two, or they won't
      // do anything.
      public static const limit_min:Number = -4503599627370496;
      public static const limit_max:Number =  4503599627370496;

      // *** Instance variables

      protected var hider:Sprite;

      // *** Constructor

      public function NumericStepper_Nullable() :void
      {
         super();
         this.addEventListener(FlexEvent.CREATION_COMPLETE,
                               this.on_creation_complete, false, 0, true);
         this.addEventListener(FlexEvent.VALUE_COMMIT,
                               this.on_value_commit, false, 0, true);
      }

      // *** Getters/setter

      //
      public function get hide_needed() :Boolean
      {
         return this.hideable(this.value);
      }

      // *** Event handlers

      //
      public function on_creation_complete(ev:FlexEvent) :void
      {
         var gr:Graphics;

         this.hider = new Sprite();
         this.hider.x = 3;
         this.hider.y = 3;

         gr = this.hider.graphics;
         gr.clear();

         gr.beginFill(0xffffff);
         // FIXME: magic numbers...
         gr.drawRect(0, 0, this.width - 23, this.height - 6);
         gr.endFill();

         this.addChild(this.hider);

         this.hider.visible = this.hide_needed;
      }

      //
      public function on_value_commit(ev:FlexEvent) :void
      {
         if (this.hider !== null) {
            this.hider.visible = this.hide_needed;
         }
      }

      // *** Instance methods

      //
      protected function hideable(a:Number) :Boolean
      {
         return (a <= this.minimum);
      }

   }
}


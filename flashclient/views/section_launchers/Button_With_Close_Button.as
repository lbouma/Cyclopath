/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// The Button_With_Close_Button class overrides the (undocumented)
// ButtonBarButton, so that we can draw a *second* icon in the button!
// We float a close icon on top of the tab button. The user can click the close
// icon to close the ViewStack panel associated with the button. Pretty nifty!

package views.section_launchers {

   import flash.events.Event;
   import flash.events.MouseEvent;

   import mx.controls.buttonBarClasses.ButtonBarButton;
   import mx.controls.Button;

   import utils.misc.Logging;

   public class Button_With_Close_Button extends ButtonBarButton {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@BtnWClsBtn');

      // *** Class resources

      [Embed(source='/assets/img/icon_tab_close_circle_x.png')]
      protected static var icon_close_circle_x:Class;

      // *** Instance attributes

      protected var close_button:Button;

      // Of course, not all tab bar buttons are closeable. In fact, they
      // default to being permanent.
      [Bindable]
      public var closeable:Boolean = false;

      // To avoid coupling (let's be generic), if the close button is clicked,
      // we make the caller process it. If the button is clicked but not the
      // close button, the normal ButtonBarButton handles the click, which'll
      // activate the panel corresponding to the tab button.
      public var close_callback:Function;

      // *** Constructor

      public function Button_With_Close_Button()
      {
         super();
         m4_VERBOSE('ctor: event trace: new Button_With_Close_Button');
      }

      // *** Instance methods

      //
      // Triggered by invalidateDisplayList.
      override protected function updateDisplayList(
         unscaledWidth:Number, unscaledHeight:Number) :void
      {
         m4_VERBOSE('updateDisplayList: event trace: this:', this);
         // [lb] cannot get useHandCursor=false to work in Launchers.mxml on
         // init, but instead only after the first time the user clicks the
         // tab button. Here it works, though: you never see the hand-finger
         // cursor, only the normal mouse pointer.
         // MAYBE: Should we not use the hand and finger cursor?
         this.useHandCursor = false;
         super.updateDisplayList(unscaledWidth, unscaledHeight);
         if (this.closeable) {
            this.update_close_button();
         }
      }

      //
      protected function update_close_button() :void
      {
         if (this.close_button === null) {
            this.close_button = new Button();

            this.close_button.mouseChildren = true;
            this.close_button.mouseEnabled = true;
            this.close_button.enabled = true;
            this.close_button.buttonMode = true;
            this.close_button.useHandCursor = true;
            this.close_button.setStyle('icon',
               Button_With_Close_Button.icon_close_circle_x);

            this.addChildAt(this.close_button, this.numChildren);
         }
         else {
            this.setChildIndex(this.close_button, this.numChildren - 1);
         }

         // Move the close button to the upper-right corner of the tab bar btn.
         this.close_button.x = this.width; //  + 6;
         this.close_button.y = 0; // 6;
      }

      // NOTE: The base class also hooks mouseDownHandler and mouseUpHandler...
      //       but [lb] thinks we can get away with overriding clickHandler.
      //
      override protected function clickHandler(event:MouseEvent):void
      {
         // m4_VERBOSE('clickHandler: enabled:', this.enabled);
         // m4_VERBOSE('clickHandler: x:', event.stageX, '/ y:', event.stageY);
         if (this.closeable) {
            var is_hit:Boolean;
            is_hit = this.close_button.hitTestPoint(event.stageX,
                                                    event.stageY);
            if (is_hit) {
               m4_DEBUG('clickHandler: close icon clicked');
               // Don't let the normal ButtonBarButton process the click.
               event.stopImmediatePropagation();
               if (this.close_callback !== null) {
                  this.close_callback(this);
               }
               else {
                  m4_WARNING('Close button clicked but no handler.');
               }
            }
         }
         else {
            super.clickHandler(event);
         }
         return;
      }

   }
}


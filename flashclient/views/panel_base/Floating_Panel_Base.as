/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: Style: Alphabatize and categorize the fcns. below.

package views.panel_base {

   import flash.events.MouseEvent;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import mx.containers.HBox;
   import mx.containers.Panel;
   import mx.controls.Button;
   import mx.core.UIComponent;
   import mx.core.Application;
   import mx.effects.Resize;
   import mx.events.DragEvent;
   import mx.events.EffectEvent;
   import mx.events.TweenEvent;
   import mx.managers.CursorManager;

   import utils.misc.Logging;

   public class Floating_Panel_Base extends Panel {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('FloatingBase');

      // *** Class resources

      [Embed(source='/assets/img/cursor_resize_diag.png')]
      private static var Cursor_Resize_Class:Class;

      // MAYBE: MAGIC_NUMBERS: These are based on the the icon's width.
      //        [lb] tried percentHeight = 100, autoLayout = true, but hasn't
      //        tried getting the icon's width...
      private static var icon_width_title_bar:int = 7;
      private static var icon_width_resizer:int = 10;
      //private static var title_bar_padding_top:int = 7;

      // *** Instance variables

      [Bindable] public var enable_left_right:Boolean = false;
      [Bindable] public var enable_up_down:Boolean = false;
      [Bindable] public var enable_close:Boolean = true;
      [Bindable] public var enable_resize:Boolean = false;

      // EXPLAIN: Why did we localize a copy of title_bar?
      protected var title_bar:UIComponent;
      private var title_bar_buttons:HBox = new HBox();

      private var button_left_right:Button = new Button();
      private var button_up_down:Button = new Button();
      private var button_close:Button = new Button();
      private var button_resize:Button = new Button();

      private var cursor_resize:Number = 0;

      // We need one Resize motion for each type of animation.
      private var motion_shade_fwd:Resize = new Resize();
      private var motion_shade_rwd:Resize = new Resize();
      private var motion_left_right:Resize = new Resize();
      private var motion_left_right_reverse:Resize = new Resize();
      private var motion_up_down:Resize = new Resize();
      private var motion_up_down_reverse:Resize = new Resize();

      private var x_orig:Number;
      private var y_orig:Number;
      private var width_orig:Number;
      private var height_orig:Number;
      private var point_orig:Point = new Point();
      private var right_orig:Number;

      private var title_bar_ctrl_width:int = 0;

      private var _title_bar_height:int = 15;

      // *** Constructor

      public function Floating_Panel_Base()
      {
         super();
      }

      // *** Getters and setters

      //
      public function get title_bar_height() :int
      {
         return this._title_bar_height;
      }

      //
      public function set title_bar_height(height:int) :void
      {
         this._title_bar_height = height;
         this._init_motions();
      }

      // *** Instance methods

      //
      // MAYBE: MAGIC_NUMBERS: Move style values to CSS.
      override protected function createChildren() :void
      {
         var add_divider:Boolean = false;
         var do_add:Object = { do_add: add_divider };

         super.createChildren();

         this.title_bar = super.titleBar;

         // MAYBE: Move to CSS. But [lb] cannot get this to work:
         //          this.styleName = 'floatingToolPalette';
         this.setStyle('headerColors', [0xC3D1D9, 0xD2DCE2,]);
         //this.setStyle('borderColor', 0xD2DCE2);

         this.setStyle('headerHeight', title_bar_height);

         this.doubleClickEnabled = true;

         this.title_bar_buttons.setStyle('horizontalGap', 0);
         // DNW?: this.title_bar_buttons.setStyle('right', 0);

         this._title_bar_add_button(this.enable_left_right,
                                    this.button_left_right,
                                    'styleIconArrowRight',
                                    do_add);
         this._title_bar_add_button(this.enable_up_down,
                                    this.button_up_down,
                                    'styleIconArrowDown',
                                    do_add);
         this._title_bar_add_button(this.enable_close,
                                    this.button_close,
                                    'styleIconClose',
                                    do_add);

         this.title_bar_buttons.width = this.title_bar_ctrl_width;
         this.title_bar_buttons.height = 7;

         this.title_bar.addChild(this.title_bar_buttons);

         this.title_bar.setStyle('paddingTop', '10');

         if (this.enable_resize) {
            this.button_resize.width = Floating_Panel_Base.icon_width_resizer;
            this.button_resize.height = Floating_Panel_Base.icon_width_resizer;
            this.button_resize.styleName = 'styleIconResize';
            this.rawChildren.addChild(button_resize);
         }

         this._init_motions();
         this.init_position();
         this.position_children();
         this.add_listeners();

         if (this.enable_resize) {
            this.button_resize.y =
               this.unscaledHeight - button_resize.height - 1;
            this.button_resize.x =
               this.unscaledWidth - button_resize.width - 1;
         }
      }

      // Sets up the panel window animations
      private function _init_motions() :void
      {
         var motion:Resize;
         var motions:Array = [
            this.motion_shade_fwd,
            this.motion_shade_rwd,
            this.motion_left_right,
            this.motion_left_right_reverse,
            this.motion_up_down,
            this.motion_up_down_reverse
            ];
         for each (motion in motions) {
            motion.target = this;
            motion.duration = 300;
         }
         this.motion_shade_fwd.heightTo = title_bar_height;
         this.motion_shade_rwd.heightFrom = title_bar_height;
         this.motion_left_right.widthTo = 200; // FIXME: Make static attr
         this.motion_left_right_reverse.widthFrom = 200; // ^^^ or const
         this.motion_up_down.heightTo = title_bar_height;
         this.motion_up_down_reverse.heightFrom = title_bar_height;
      }

      // Adds the icons of the title bar
      protected function _title_bar_add_button(
         enable:Boolean,
         button:Button,
         style_name:String,
         do_add:Object) :void
      {
         if (enable) {
            _title_bar_add_divider(do_add);
            button.width = Floating_Panel_Base.icon_width_title_bar;
            button.height = Floating_Panel_Base.icon_width_title_bar;
            button.setStyle('horizontalGap', 0);
            button.styleName = style_name;
            this.title_bar_buttons.addChild(button);
            this.title_bar_ctrl_width +=
               Floating_Panel_Base.icon_width_title_bar;
         }
      }

      //
      protected function _title_bar_add_divider(do_add:Object) :void
      {
         if (do_add.do_add) {
            var divider:Button = new Button();
            // FIXME Magic number
            divider.width = 11;//icon_width_title_bar;//3;
            divider.height = Floating_Panel_Base.icon_width_title_bar;
            divider.setStyle('paddingLeft', 20);//0);
            divider.setStyle('paddingRight', 20);
            divider.styleName = 'styleIconDivider';
            this.title_bar_buttons.addChild(divider);
            // FIXME Magic number
            //this.title_bar_ctrl_width +=
            // Floating_Panel_Base.icon_width_title_bar;
            this.title_bar_ctrl_width += 11;
         }
         do_add.do_add = true;
      }

      //
      public function init_position() :void
      {
         this.x_orig = this.x;
         this.y_orig = this.y;
         this.width_orig = this.unscaledWidth;
         this.height_orig = this.unscaledHeight;

         this.motion_shade_fwd.heightFrom = this.height_orig;
         this.motion_shade_rwd.heightTo = this.height_orig;
         this.motion_left_right.widthFrom = this.width_orig;
         this.motion_left_right_reverse.widthTo = this.width_orig;
         this.motion_up_down.heightFrom = this.height_orig;
         this.motion_up_down.heightTo = this.height_orig;
      }

      //
      public function position_children() :void
      {
         // NOTE position_children is only called on init, so changing enable_*
         //      has not effect at runtime
         if (this.enable_left_right) {
            this.button_left_right.buttonMode = true;
            this.button_left_right.useHandCursor = true;
         }
         if (this.enable_up_down) {
            this.button_up_down.buttonMode = true;
            this.button_up_down.useHandCursor = true;
         }
         if (this.enable_close) {
            this.button_close.buttonMode = true;
            this.button_close.useHandCursor = true;
         }
         // FIXME Magic numbers
         this.title_bar_buttons.x =
            this.unscaledWidth - this.title_bar_ctrl_width - 7;
         this.title_bar_buttons.y = 3;

         if (this.enable_resize) {
            this.button_resize.y =
               this.unscaledHeight - button_resize.height - 1;
            this.button_resize.x =
               this.unscaledWidth - button_resize.width - 1;
         }
      }

      //
      override protected function updateDisplayList(
         unscaledWidth:Number, unscaledHeight:Number) :void
      {
         super.updateDisplayList(unscaledWidth, unscaledHeight);
         if (this.height_orig == 0) {
            this.init_position();
         }
         this.position_children();
      }

      //
      public function add_listeners() :void
      {
         this.addEventListener(
            MouseEvent.CLICK, handle_click_panel);
         // FIXME: Care about priority here? Search MOUSE_PRIORITY
         this.title_bar.addEventListener(
            MouseEvent.MOUSE_DOWN, handle_mouse_down_title_bar);
         this.title_bar.addEventListener(
            MouseEvent.DOUBLE_CLICK, handle_mouse_double_click_title_bar);

         if (this.enable_left_right) {
            this.button_left_right.addEventListener(
               MouseEvent.CLICK, handle_mouse_click_left_right_and_shade);
         }
         if (this.enable_up_down) {
            this.button_up_down.addEventListener(
               MouseEvent.CLICK, handle_mouse_click_up_down);
         }
         if (this.enable_close) {
            this.button_close.addEventListener(
               MouseEvent.CLICK, handle_mouse_click_close);
         }

         if (this.enable_resize) {
            this.button_resize.addEventListener(
               MouseEvent.MOUSE_OVER, handle_mouse_over_resize);
            this.button_resize.addEventListener(
               MouseEvent.MOUSE_OUT, handle_resize_out);
            this.button_resize.addEventListener(
               MouseEvent.MOUSE_DOWN, handle_mouse_down_resize);
         }
      }

      //
      public function handle_click_panel(event:MouseEvent) :void
      {
         this.title_bar.removeEventListener(
            MouseEvent.MOUSE_MOVE, handle_mouse_move_title_bar);
         this.parent.setChildIndex(this, this.parent.numChildren - 1);
         m4_DEBUG('handle_click_panel: calling check_panel_focus');
         this.check_panel_focus();
      }

      //
      public function handle_mouse_down_title_bar(event:MouseEvent) :void
      {
         this.title_bar.addEventListener(
            MouseEvent.MOUSE_MOVE, handle_mouse_move_title_bar);
      }

      //
      public function handle_mouse_move_title_bar(event:MouseEvent) :void
      {
         if (this.width < this.parent.width) {
            Application.application.parent.addEventListener(
               MouseEvent.MOUSE_UP, handle_drag_drop_title_bar);
            this.title_bar.addEventListener(
               DragEvent.DRAG_DROP, handle_drag_drop_title_bar);
            this.parent.setChildIndex(this, this.parent.numChildren - 1);
            m4_DEBUG('handle_mouse_move_title_bar: calling check_panel_focus');
            this.check_panel_focus();
            // Alpha looks kinda sketchy when dragging; don't do it
            //this.alpha = 0.67;
            this.startDrag(false, new Rectangle(0, 0,
               this.parent.width - this.width,
               this.parent.height - this.height));
         }
      }

      //
      public function handle_drag_drop_title_bar(event:MouseEvent) :void
      {
         this.title_bar.removeEventListener(
            MouseEvent.MOUSE_MOVE, handle_mouse_move_title_bar);
         this.alpha = 1.0;
         this.stopDrag();
      }

      //
      protected function check_panel_focus() :void
      {
         for (var i:int = 0; i < this.parent.numChildren; i++) {
            var child:UIComponent = UIComponent(this.parent.getChildAt(i));
            m4_DEBUG('check_panel_focus: child:', child);
            // MAGIC_NUMBER: Colors. It's view stuff in code...
            if (this.parent.getChildIndex(child)
                < this.parent.numChildren - 1) {
               // Can we add borderColor to floatingToolPalette
               // or make new CSS definition?
               child.setStyle('headerColors', [0xC3D1D9, 0xD2DCE2]);
               child.setStyle('borderColor', 0xD2DCE2);
            }
            else if (this.parent.getChildIndex(child)
                     == this.parent.numChildren - 1) {
               child.setStyle('headerColors', [0xC3D1D9, 0x5A788A]);
               child.setStyle('borderColor', 0x5A788A);
            }
         }
      }

      //
      public function handle_mouse_double_click_title_bar(
         event:MouseEvent) :void
      {
         // Remove the event which was set on the first click
         this.title_bar.removeEventListener(
            MouseEvent.MOUSE_MOVE, handle_mouse_move_title_bar);
         // And quit listening for resize activity
         // TODO Is this necessary? Seems weird here...
         //Application.application.parent.removeEventListener(
         //   MouseEvent.MOUSE_UP, handle_mouse_up_resize);
         this.shade_window(null, handle_effect_end_shade_reverse);
      }

      //
      public function shade_window(
         end_constrict_handler:Function,
         end_expand_handler:Function) :void
      {
         this.motion_shade_fwd.end();
         this.motion_shade_rwd.end();
         if (this.height == this.height_orig) {
            if (end_constrict_handler !== null) {
               this.motion_shade_fwd.addEventListener(
                  EffectEvent.EFFECT_END, end_constrict_handler);
            }
            this.motion_shade_fwd.play();
            this.button_resize.visible = false;
         }
         else {
            if (end_expand_handler !== null) {
               this.motion_shade_rwd.addEventListener(
                  EffectEvent.EFFECT_END, end_expand_handler);
            }
            this.motion_shade_rwd.play();
         }
      }

      //
      public function handle_effect_end_shade_reverse(event:EffectEvent) :void
      {
         this.motion_shade_rwd.removeEventListener(
            EffectEvent.EFFECT_END, handle_effect_end_shade_reverse);
         this.button_resize.visible = true;
         this.position_children();
      }

      //
      public function handle_mouse_click_left_right_and_shade(
         event:MouseEvent) :void
      {
         // First shade (vertical), then tighten (horizontal)
         if (this.height == this.height_orig) {
            // Window is in use and user wants it out of the way
            // Start by shading the window; on callback, tighten
            //this.button_resize.visible = false;
            this.shade_window(handle_end_shade_then_tighten, null);
         }
         else {
            this.motion_left_right.end();
            // Window is shaded, so window is either shaded or tightened
            if (this.width == this.width_orig) {
               // Window is shaded, so just tighten
               this.motion_left_right.addEventListener(
                  TweenEvent.TWEEN_UPDATE, handle_tween_update_tightening);
               this.motion_left_right.play();
            }
            else {
               // Window is tightened, so loosen and then unshade
               this.motion_left_right.addEventListener(
                  EffectEvent.EFFECT_END, handle_end_left_do_shade_reverse);
               this.motion_left_right_reverse.play();
            }
         }
      }

      //
      protected function handle_tween_update_tightening(event:TweenEvent)
         :void
      {
         this.motion_left_right.removeEventListener(
            TweenEvent.TWEEN_UPDATE, handle_tween_update_tightening);
      }

      //
      public function handle_end_shade_then_tighten(event:EffectEvent) :void
      {
         this.motion_shade_fwd.removeEventListener(
            EffectEvent.EFFECT_END, handle_end_shade_then_tighten);
         this.motion_left_right.end();
         // Window is newly shaded, so tighten
         //this.button_resize.visible = false;
         if (this.width == this.width_orig) {
            this.motion_left_right.addEventListener(
               EffectEvent.EFFECT_END, handle_end_right_do_position_children);
            this.motion_left_right.play();
         }
         // else, this just means the tighten width and user's width are same
      }

      //
      public function handle_end_right_do_position_children(
         event:EffectEvent) :void
      {
         this.motion_left_right.removeEventListener(
            EffectEvent.EFFECT_END, handle_end_right_do_position_children);
         this.position_children();
      }

      //
      public function handle_end_left_do_shade_reverse(event:EffectEvent) :void
      {
         this.motion_left_right.removeEventListener(
            EffectEvent.EFFECT_END, handle_end_left_do_shade_reverse);
         this.shade_window(null, handle_effect_end_shade_reverse);
      }

      //
      public function handle_mouse_click_left_right(event:MouseEvent) :void
      {
         return; // FIXME
      }

      //
      public function handle_mouse_click_up_down(event:MouseEvent) :void
      {
         return; // FIXME
      }

      //
      public function handle_mouse_click_close(event:MouseEvent) :void
      {
         this.removeEventListener(MouseEvent.CLICK, handle_click_panel);
         this.parent.removeChild(this);
      }

      //
      public function handle_mouse_over_resize(event:MouseEvent) :void
      {
         this.cursor_resize = CursorManager.setCursor(Cursor_Resize_Class);
      }

      //
      public function handle_resize_out(event:MouseEvent) :void
      {
         CursorManager.removeCursor(CursorManager.currentCursorID);
      }

      //
      public function handle_mouse_down_resize(event:MouseEvent) :void
      {
         Application.application.parent.addEventListener(
            MouseEvent.MOUSE_MOVE, handle_mouse_move_resize);
         Application.application.parent.addEventListener(
            MouseEvent.MOUSE_UP, handle_mouse_up_resize);
         this.button_resize.addEventListener(
            MouseEvent.MOUSE_OVER, handle_mouse_over_resize);
         this.handle_click_panel(event);
         this.cursor_resize = CursorManager.setCursor(Cursor_Resize_Class);
         this.point_orig.x = mouseX;
         this.point_orig.y = mouseY;
         this.point_orig = this.localToGlobal(point_orig);
      }

      //
      public function handle_mouse_move_resize(event:MouseEvent) :void
      {
         this.stopDragging();
         var xPlus:Number =
            Application.application.parent.mouseX - this.point_orig.x;
         var yPlus:Number =
            Application.application.parent.mouseY - this.point_orig.y;
         if (this.width_orig + xPlus > 140) {
            this.width = this.width_orig + xPlus;
         }
         if (this.height_orig + yPlus > 80) {
            this.height = this.height_orig + yPlus;
         }
         this.position_children();
      }

      //
      public function handle_mouse_up_resize(event:MouseEvent) :void
      {
         Application.application.parent.removeEventListener(
            MouseEvent.MOUSE_MOVE, handle_mouse_move_resize);
         Application.application.parent.removeEventListener(
            MouseEvent.MOUSE_UP, handle_mouse_up_resize);
         CursorManager.removeCursor(CursorManager.currentCursorID);
         this.button_resize.addEventListener(
            MouseEvent.MOUSE_OVER, handle_mouse_over_resize);
         this.init_position();
      }

   }
}


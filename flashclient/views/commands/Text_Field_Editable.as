/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.events.Event;
   import flash.events.FocusEvent;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.text.TextLineMetrics;
   import flash.utils.Timer;
   import mx.containers.Canvas;
   import mx.containers.VBox;
   import mx.controls.Label;
   import mx.controls.Text;
   import mx.controls.TextArea;
   import mx.controls.TextInput;
   import mx.core.UIComponent;
   import mx.effects.Fade;
   import mx.effects.Move;
   import mx.events.EffectEvent;
   import mx.events.ValidationResultEvent;
   import mx.validators.Validator;

   import items.Item_Base;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.base.App_Action;
   import views.commands.Command_Manager;

   public class Text_Field_Editable extends VBox {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_TxtFldE');

      // *** Instance variables

      protected var record_timer:Timer;

      // These are our component children;
      protected var canvas_highlight:Canvas;
      protected var box_highlight:VBox;
      [Bindable] public var editor:UIComponent;
      [Bindable] public var labeler:Label;
      protected var validator:Validator;

      protected var attr_name_:String;
      protected var use_html_:Boolean = false;
      protected var activated:Boolean = false;
      protected var edit_enabled_:Boolean = false;
      protected var use_label_toggle_:Boolean = false;

      protected var undo_focus_out:Boolean = false;

      // MAYBE: Rename from features: this is link_vales for text attributes
      //        (it's geofeatures or attachments for the item name control)...
      public var features:Set_UUID;

      protected var effect_fade_in:Fade;
      protected var effect_fade_out:Fade;
      protected var effect_timer:Timer;
      protected var next_fade:Fade;

      // For undo/redo to work properly, we need to remember the old value.
      protected var last_recorded_text:String = '';

      [Bindable] public var dirty_reason:int = 0;

      [Bindable] public var cmd_mgr_fcn:Function = null;

      // ***

      public function Text_Field_Editable()
      {
         this.record_timer = new Timer(Conf.text_edit_record_delay, 1);
         this.activated = false;
         this.use_html_ = false;
         this.features = new Set_UUID();

         // FIXME: The timing of the animation isn't quite right.
         var delay:Number = 4000.0;
         var repeatCount:int = 1;
         this.effect_timer = new Timer(delay, repeatCount);
      }

      //
      public function init(attr_name:String, multiline:Boolean) :void
      {
         this.attr_name_ = attr_name;

         m4_ASSERT(this.editor === null);
         if (multiline) {
            this.editor = new TextArea();
         }
         else {
            this.editor = new TextInput();
         }

         this.editor.percentWidth = 100;
         this.editor.percentHeight = 100;
         //

         this.box_highlight = new VBox();
         this.box_highlight.visible = true;
         this.box_highlight.percentWidth = 100;
         this.box_highlight.percentHeight = 100;
         // Don't need: backgroundAlpha

         this.canvas_highlight = new Canvas();
         this.canvas_highlight.visible = true;
         this.canvas_highlight.percentWidth = 100;
         this.canvas_highlight.percentHeight = 100;

         this.canvas_highlight.addChild(this.editor);
         this.canvas_highlight.addChild(this.box_highlight);
         this.addChild(this.canvas_highlight);

         this.labeler = new Label();
         this.labeler.visible = false;
         //this.labeler.setStyle('includeInLayout',
         //                      '{this.labeler.visible}');
         this.labeler.includeInLayout = false;
         // Nope: this.labeler.percentWidth = 100;
         this.labeler.percentHeight = 100;
         this.labeler.selectable = true;
         //
         this.labeler.doubleClickEnabled = true;
         this.labeler.toolTip = this.labeler_tool_tip;
         //
         // We expect the caller to set maxWidth but let's at least start
         // with something. And make it something nothing to so DEVs know
         // when they haven't set the width, since the control won't show
         // up.
         this.labeler.maxWidth = 0;
         this.labeler.truncateToFit = true;
         //
         this.labeler_init();
         this.addChild(this.labeler);

         this.editor.addEventListener(Event.CHANGE,
                                      this.on_text_input, false, 0, true);
         // BUG nnnn:/FIXME: If you click elsewhere in the app, we should
         // treat it as on_focusout. But currently to lose focus (and for the
         // edit control to turn back into a pumpkin/the label) you have to
         // press tab or you have to click another edit control that steals
         // focus. But clicking on empty space in the panel or on the map
         // doesn't hide the edit control, which it probably should.
         this.editor.addEventListener(
            FocusEvent.FOCUS_OUT, this.on_focusout, false, 0, true);
         this.labeler.addEventListener(
            MouseEvent.DOUBLE_CLICK, this.on_double_click, false, 0, true);
         this.record_timer.addEventListener(
            TimerEvent.TIMER, this.on_timer_record, false, 0, true);
         this.effect_timer.addEventListener(
            TimerEvent.TIMER, this.on_timer_effect, false, 0, true);

         this.validator = new Validator();
         this.validator.required = true;
         this.validator.source = this.editor;
         this.validator.property = 'text';
         this.validator.triggerEvent = Event.CHANGE;

         this.required = false;
         //m4_DEBUG('init: attr_name:', attr_name, '/ multiline:', multiline);
         this.edit_enabled = true;
         this.use_label_toggle = false;
      }

      // *** Get/set methods

      // FIXME: 2011.01.20 Let's see if this works...
      public function set attr_name(attr_name:String) :void
      {
         this.attr_name_ = attr_name;
      }

      //
      public function get edit_enabled() :Boolean
      {
         return this.edit_enabled_;
      }

      //
      public function set edit_enabled(s:Boolean) :void
      {
         m4_VERBOSE2('edit_enabled:', s,
                     '/ vis:', this.canvas_highlight.visible);
         this.edit_enabled_ = s;
         // Prevent editor from losing focus and changing back to label when
         // caller is just reassurting the obvious.
         var try_edit:Boolean = (s) && (this.canvas_highlight.visible);
         this.enable_and_label(try_edit);
      }

      //
      public function get required() :Boolean
      {
         return this.validator.enabled;
      }

      // Whether or not the field is required. If true, text is only recorded
      // if it is non-empty.
      public function set required(req:Boolean) :void
      {
         this.validator.enabled = req;
      }

      //
      public function show_name_reminder() :void
      {
         m4_VERBOSE('show_name_reminder');

         this.edit_enabled_ = true;
         var try_edit:Boolean = true;
         this.enable_and_label(try_edit);

         this.box_highlight.visible = true;
         this.box_highlight.includeInLayout = true;

         this.box_highlight.setStyle('borderStyle', 'solid');
         this.box_highlight.setStyle('borderThickness', 2);
         this.box_highlight.setStyle('borderColor', 0xFF0000);
         //this.box_highlight.setStyle('alpha', 0.0);

         // Note: We could use a state transition to animate, but this works
         //       well, and it isn't too confusing: slowly cycle between
         //       highlight and not to let user know to edit the text.

         var targets:Array = [this.box_highlight,];

         this.effect_fade_in = new Fade();
         this.effect_fade_in.targets = targets;
         this.effect_fade_in.duration = 1300;
         this.effect_fade_in.alphaFrom = 0.0;
         this.effect_fade_in.alphaTo = 0.25;

         this.effect_fade_out = new Fade();
         this.effect_fade_out.targets = targets;
         this.effect_fade_out.duration = 1300;
         this.effect_fade_out.alphaFrom = 0.25;
         this.effect_fade_out.alphaTo = 0.0;

         this.effect_fade_in.addEventListener(
            EffectEvent.EFFECT_END, this.on_effect_end_edit_box_fade);
         this.effect_fade_out.addEventListener(
            EffectEvent.EFFECT_END, this.on_effect_end_edit_box_fade);

         this.next_fade = this.effect_fade_in;
         this.effect_fade_out.end();
         this.effect_fade_out.play();
      }

      // After the window is heightened (unshaded), fades in the save box
      protected function on_effect_end_edit_box_fade(ev:EffectEvent) :void
      {
         m4_VERBOSE2('on_effect_end_edit_box_fade: ev:', ev,
                     '/ tgt:', ev.target);

         if (this.next_fade !== null) {
            if (ev.target === this.effect_fade_in) {
               this.next_fade = this.effect_fade_out;
            }
            else {
               m4_ASSERT(ev.target === this.effect_fade_out);
               this.next_fade = this.effect_fade_in;
            }
            this.effect_timer.reset();
            this.effect_timer.start();
            m4_VERBOSE2('_effect_end_edit_box_fade: next_fade:',
                        this.next_fade);
         }
         else {
            this.effect_edit_box_fade_cleanup();
         }
      }

      //
      protected function on_timer_effect(ev:TimerEvent) :void
      {
         m4_VERBOSE('on_timer_effect: this.next_fade:', this.next_fade);
         if (this.next_fade !== null) {
            this.next_fade.end();
            this.next_fade.play();
         }
         else {
            this.effect_edit_box_fade_cleanup();
         }
      }

      //
      protected function effect_edit_box_fade_cleanup() :void
      {
         m4_VERBOSE('effect_edit_box_fade_cleanup');

         this.box_highlight.visible = false;
         this.box_highlight.includeInLayout = false;

         if (this.effect_fade_in !== null) {
            this.effect_fade_in.removeEventListener(
               EffectEvent.EFFECT_END, this.on_effect_end_edit_box_fade);
         }
         if (this.effect_fade_out !== null) {
            this.effect_fade_out.removeEventListener(
               EffectEvent.EFFECT_END, this.on_effect_end_edit_box_fade);
         }
         this.effect_timer.stop();
         // meh: removeEventListener: this.on_timer_effect

         this.effect_fade_in = null;
         this.effect_fade_out = null;

         this.next_fade = null;
      }

      // ***

      //
      protected function get labeler_tool_tip() :String
      {
         // this.labeler.toolTip = 'Double-click here to edit this value.';
         // Since the text control truncates long names, put the whole name
         // in the toolTip.
         var labeler_tool_tip:String = '';
         if (this.text) {
            labeler_tool_tip = '"' + this.text + '". ';
            //if (this.edit_enabled) {
            //   labeler_tool_tip += ' ';
            //}
         }
         if (this.edit_enabled) {
            labeler_tool_tip += 'Double-click to edit the name.';
         }
         // COUPLING: This class isn't quite reusable, since it knows about map
         //           states. Oh well.
         else if (G.app.mode.is_allowed(App_Action.item_edit)) {
            labeler_tool_tip += 'This value cannot be edited.';
         }
         else if (!(G.map.rev_viewport is utils.rev_spec.Diff)) {
            // More coupling: Knowledge of where the editing_enabled widget is.
            labeler_tool_tip +=
               'To edit this value, click the "Editing" button above the map.';
         }
         return labeler_tool_tip;
      }

      //
      public function get stale() :Boolean
      {
         var vf:Item_Base;
         for each (vf in this.features) {
            if (this.text !== vf[this.attr_name_]) {
               return true;
            }
         }
         return false;
      }

      // Returns the text currently displaying in this editor.
      public function get text() :String
      {
         m4_ASSERT((this.editor is TextArea) || (this.editor is TextInput));
         var t:String;
         if (this.editor is TextArea) {
            t = (this.editor as TextArea).text;
         }
         else {
            t = (this.editor as TextInput).text;
         }

         if (t === null) {
            m4_ASSERT(this.use_html);
            if (this.editor is TextArea) {
               t = (this.editor as TextArea).htmlText;
            }
            else {
               t = (this.editor as TextInput).htmlText;
            }
         }
         return t;
      }

      // Sets the text to be displayed in this editor.
      public function set text(new_text:String) :void
      {
         var text_area:TextArea = (this.editor as TextArea);
         var text_iput:TextInput = (this.editor as TextInput);
         m4_ASSERT((text_area !== null) || (text_iput !== null));
         if (this.use_html) {
            if (text_area !== null) {
               text_area.htmlText = new_text;
            }
            else {
               text_iput.htmlText = new_text;
            }
         }
         else {
            if (text_area !== null) {
               text_area.text = new_text;
            }
            else {
               text_iput.text = new_text;
            }
         }

         // Reset scroll to left if TextInput; not applicable to TextArea.
         // See bug 1381.
         if (text_iput !== null) {
            text_iput.horizontalScrollPosition = 0;
         }

         this.validator.validate();

         if (!this.activated) {
            this.labeler.text = this.text;
            this.labeler.toolTip = this.labeler_tool_tip;

            this.last_recorded_text = this.text;
         }

         // Hmmm. Lowercase letters like 'p's are clipped.
         // Use TextLineMetrics to measure the height.
         if (text_iput !== null) {
            //
            var text_i:TextLineMetrics;
            text_i = text_iput.measureText(new_text);
            m4_TALKY('init: measureText: text_iput.text_i:', text_i.height);
            //
            var text_l:TextLineMetrics;
            text_l = this.labeler.measureText(new_text);
            m4_TALKY('init: measureText: labeler.text_l:', text_l.height);
            var new_height:int = Math.max(text_i.height, text_l.height) + 8;

            text_iput.height = new_height;
            this.labeler.height = new_height;

            m4_TALKY('init: measureText: text_iput.height:', text_iput.height);
            m4_TALKY('init: measureText: labeler.heigh:', this.labeler.height);
            m4_TALKY('init: measureText: this.height:', this.height);
         }

         this.effect_edit_box_fade_cleanup();
      }

      //
      public function get use_html() :Boolean
      {
         return this.use_html_;
      }

      //
      public function set use_html(s:Boolean) :void
      {
         var text_area:TextArea = (this.editor as TextArea);
         var text_iput:TextInput = (this.editor as TextInput);
         if (s !== this.use_html) {
            if (this.use_html) {
               var t:String;
               if (text_area !== null) {
                  t = text_area.text
               }
               else {
                  t = text_iput.text;
               }
               if (t === null) {
                  if (text_area !== null) {
                     text_area.text = text_area.htmlText;
                  }
                  else {
                     text_iput.text = text_iput.htmlText;
                  }
               }
               else {
                  if (text_area !== null) {
                     text_area.htmlText = null;
                  }
                  else {
                     text_iput.htmlText = null;
                  }
               }
               this.use_html_ = false;
            }
            else {
               if (text_area !== null) {
                  text_area.htmlText = text_area.text;
               }
               else {
                  text_iput.htmlText = text_iput.text;
               }
               this.use_html_ = true;
            }
         }
      }

      //
      public function get use_label_toggle() :Boolean
      {
         return this.use_label_toggle_;
      }

      //
      public function set use_label_toggle(s:Boolean) :void
      {
         this.use_label_toggle_ = s;
         this.enable_and_label();
      }

      // *** Instance Methods

      //
      protected function enable_and_label(try_edit:Boolean=false) :void
      {
         this.labeler.toolTip = this.labeler_tool_tip;
         // Toggle mousiness.
         if (this.edit_enabled_) {
            // this.mouseEnabled = true;
            // this.mouseChildren = true;
            this.labeler.doubleClickEnabled = true;
            this.editor.setStyle('borderStyle', 'inset');
         }
         else {
            // Don't disable the mouse: then nothing works, including toolTip
            // and selecting the label text.
            // this.mouseEnabled = false;
            // this.mouseChildren = false;
            this.labeler.doubleClickEnabled = false;
            this.editor.setStyle('borderStyle', 'none');
         }
         // Toggle labelness.
         var show_editor:Boolean = ((this.edit_enabled_)
                                    && ((this.activated)
                                        || (try_edit)
                                        || (!this.use_label_toggle_)));
         if (show_editor) {
            m4_VERBOSE('enable_and_label: editing');
            this.canvas_highlight.visible = true;
            this.canvas_highlight.includeInLayout = true;
            this.labeler.visible = false;
            this.labeler.includeInLayout = false;
         }
         else {
            m4_VERBOSE('enable_and_label: labeling');
            this.canvas_highlight.visible = false;
            this.canvas_highlight.includeInLayout = false;
            this.labeler.visible = true;
            this.labeler.includeInLayout = true;
            //
            this.effect_edit_box_fade_cleanup();
         }
      }

      //
      public function labeler_init() :void
      {
         var styles:Array = [
            'fontSize',
            'fontWeight',
            'textDecoration',
            ];
         for each (var style:String in styles) {
            this.labeler.setStyle(style, this.getStyle(style));
         }
         this.enable_and_label();
      }

      // Records the text into whatever the subclass wants. This will generally
      // be into a variable of a Geofeature using a custom Command_Base
      // corresponding to the subclass.
      public function record() :void
      {
         var valid:Boolean;

         if ((this.features.length == 0) || (!this.activated)) {
            return;
         }

         valid = ((!this.required)
                  || (this.validator.validate().type
                      == ValidationResultEvent.VALID));

         if (this.stale && valid) {

            var cmd:Command_Text_Edit;
            // This causes the editor to lose focus. Maybe because we mess
            // with the tool palette?
            cmd = new Command_Text_Edit(
                     /*targets=*/this.features.clone(),
                     /*attr_name=*/this.attr_name_,
                     /*text_new=*/this.text,
                     /*text_old=*/this.last_recorded_text,
                     /*dirty_reason=*/this.dirty_reason,
                     /*text_input=*/this)

            // C.f. views.panel_items.Widget_Name_Header.get_cmd_mgr
            //   && views.commands.Text_Field_Editable.record
            var cmd_mgr:Command_Manager = G.map.cm;
            if (this.cmd_mgr_fcn !== null) {
               cmd_mgr = (this.cmd_mgr_fcn() as Command_Manager);
            }
            m4_DEBUG('record: cmd:', cmd, '/ cm:', cmd_mgr);
            cmd_mgr.do_(cmd);

            // The item(s) whose text is being edited should be hydrated.
            m4_ASSERT_SOFT(cmd.is_prepared !== null);

            this.labeler.text = this.text;
            this.labeler.toolTip = this.labeler_tool_tip;

            this.undo_focus_out = true;

            this.last_recorded_text = this.text;
         }
         else {
            m4_DEBUG('record: stale:', this.stale, '/ valid:', valid);
         }

         if (this.record_timer.running) {
            this.record_timer.stop();
         }

         this.activated = false;
      }

      // *** Event methods

      //
      protected function on_double_click(ev:MouseEvent) :void
      {
         m4_VERBOSE('on_double_click');
         if (this.edit_enabled_ && this.use_label_toggle_) {
            m4_ASSERT(!this.canvas_highlight.visible);
            m4_ASSERT(this.labeler.visible);
            var try_edit:Boolean = true;
            this.enable_and_label(try_edit);
         }
      }

      //
      protected function on_focusout(ev:FocusEvent) :void
      {
         m4_VERBOSE2('on_focusout: undo_focus_out:', this.undo_focus_out,
                     '/ target:', ev.target);
         if (this.undo_focus_out) {
            if (ev.target !== this.editor) {
               m4_WARNING('on_focusout: unexpected target:', ev.target);
            }
            // Calling setFocus causes a select-all. Maybe there's a setting to
            // prevent this. Or maybe we just remember the user's current
            // selection slice and restore it after setFocus... which works,
            // even if it seems like a silly solution.
            var selectionBeginIndex:int;
            var selectionEndIndex:int;
            var ti:TextInput = (this.editor as TextInput);
            if (ti !== null) {
               //m4_DEBUG(' .. selBeginIndex/2:', ti.selectionBeginIndex);
               //m4_DEBUG(' .. selEndIndex/2:', ti.selectionEndIndex);
               selectionBeginIndex = ti.selectionBeginIndex;
               selectionEndIndex = ti.selectionEndIndex;
            }
            if (this.canvas_highlight.visible) {
               this.editor.setFocus();
            }
            if (ti !== null) {
               //m4_DEBUG(' .. selBeginIndex/3:', ti.selectionBeginIndex);
               //m4_DEBUG(' .. selEndIndex/3:', ti.selectionEndIndex);
               ti.selectionBeginIndex = selectionBeginIndex;
               ti.selectionEndIndex = selectionEndIndex;
            }
            // Doesn't stop the focusOut: ev.stopPropagation();
            this.undo_focus_out = false;
         }
         else {
            this.record();
            if (this.use_label_toggle_) {
               // Force the label to appear.
               this.use_label_toggle = this.use_label_toggle_;
            }
         }
      }

      //
      protected function on_text_input(ev:Event) :void
      {
         this.record_timer.reset();
         this.record_timer.start();
         this.activated = true;
      }

      //
      protected function on_timer_record(ev:TimerEvent) :void
      {
         this.record();
      }

   }
}


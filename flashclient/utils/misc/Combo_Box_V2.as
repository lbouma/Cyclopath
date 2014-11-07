/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.display.DisplayObject;
   import flash.events.KeyboardEvent;
   import flash.ui.Keyboard;
   import mx.events.DropdownEvent;
   import mx.events.FlexEvent;
   import mx.events.ListEvent;
   import mx.core.ClassFactory;
   import mx.controls.ComboBox;
   import mx.controls.TextInput;
   import mx.controls.listClasses.IListItemRenderer;
   import mx.controls.listClasses.ListItemRenderer;

   public class Combo_Box_V2 extends ComboBox {

      // *** Class attributes.

      protected static var log:Logging = Logging.get_logger('Combo_B_V2');

      public static const INDEX_VARIES:int = -2;

      // *** Instance members.

      // Dropdown list items can specify their icon class directly or use a
      // lookup function to return it. The latter is useful if you want to use
      // a different icon depending on if your list item is selected or not,
      // for example.
      private var _icon_function:Function = null;
      private var _icon_field:String = 'icon';

      // The client may choose whether to show just the icon or the icon and
      // its text (label) in textInput.
      private var _enable_text_field_label:Boolean = true;

      protected var item_click_handler_:Function = null;

      // The icons may be padded on the right to offset the text a bit
      [Bindable] public var padding_icon_right:Number = 0;
      // The icons may also be padded on the left.
      [Bindable] public var padding_icon_left:Number = 0;

      [Bindable] public var iconForVaries:Class = null;
      [Bindable] public var noOptionOption:String = null;

      [Bindable] public var dropDownKeyDown:Function = null;

      // The measured width is the width of the combobox control (not the
      // dropdown). It includes the width of the icon, any padding, the width
      // of the text if it's showing, and the width of the down arrow icon.
      private var _measured_width:Number = 0;
      private var _width_text_field_icon_and_label:Number = 0;
      private var _width_text_field_icon_only:Number = 0;

      // Create our own factory so we can set properties in our ctor.
      private var internal_dropdown_factory:ClassFactory =
                              new ClassFactory(List_Disableable);

      // The basic ComboBox class only shows icons in the dropdown, i.e., not
      // in the textInput. This is a handle to the icon we put to the left of
      // the textInput.
      private var display_icon_object:Object = null;

      public function Combo_Box_V2()
      {
         super();
         // "Setup the properties on the factory before init so that
         //  the dropdown will gracefully adopt them."
         this.set_dropdown_properties();
         this.dropdownFactory = this.internal_dropdown_factory;
         // Tell the dropdown to use our list item class which knows how to
         // show disabled list items.
         this.itemRenderer = new ClassFactory(List_Item_Renderer_Disableable);
         // Hook dropdown events.
         this.addEventListener(DropdownEvent.OPEN,
                               this.handle_on_dropdown_open);
      }

      // ***

      // This determines if the combobox control shows just the icon or the
      // icon and its label

      [Bindable] public function get enable_text_field_label() :Boolean
      {
         return this._enable_text_field_label;
      }

      //
      public function set enable_text_field_label(value:Boolean) :void
      {
         this._enable_text_field_label = value;
      }

      // The icon field is the name of the list item attribute that identifies
      // its icon's class

      [Bindable] public function get iconField() :String
      {
         return this._icon_field;
      }

      //
      public function set iconField(value:String) :void
      {
         this._icon_field = value;
         this.set_dropdown_properties();
      }

      // The icon function is used in lieu of the icon field to specify a
      // function that returns the list item's current icon class

      [Bindable] public function get iconFunction() :Function
      {
         return _icon_function;
      }

      //
      public function set iconFunction(value:Function) :void
      {
         _icon_function = value;
         this.set_dropdown_properties();
      }

      //
      [Bindable] public function get item_click_handler() :Function
      {
         return this.item_click_handler_;
      }

      //
      public function set item_click_handler(handler:Function) :void
      {
         m4_DEBUG2('set item_click_handler: handler:',
                   ((handler !== null) ? handler : 'null'));
         this.item_click_handler_ = handler;
         this.set_dropdown_properties();
      }

      //
      protected function set_dropdown_properties() :void
      {
         m4_DEBUG('set_dropdown_properties');
         this.internal_dropdown_factory.properties =
            { iconField: this._icon_field,
              iconFunction: this._icon_function,
              customClickHandler: this.item_click_handler_ };
      }

      // ***

      // Sets the measuredWidth of the component taking into account the width
      // of the textInput icon and the width of the down arrow icon.
      override public function set measuredWidth(value:Number) :void
      {
         if ( (this._measured_width == 0)
               && (value != 0) ) {
            var measured_width:Number =
               getStyle('cornerRadius')
               + this.padding_icon_left
               + this.padding_icon_right;
            if (this.display_icon_object !== null) {
               measured_width += DisplayObject(this.display_icon_object).width;
            }
            this._width_text_field_icon_and_label =
               measured_width + value;
            this._width_text_field_icon_only =
               measured_width + this.getStyle('arrowButtonWidth');
            if (this.enable_text_field_label) {
               measured_width += value;
            }
            else {
               measured_width += this.getStyle('arrowButtonWidth');
            }
            this._measured_width = measured_width;
            this.dropdownWidth = this._width_text_field_icon_and_label;
         }
         super.measuredWidth = this._measured_width;
      }

      // When the dropdown list item changes, this updates the textInput icon
      override public function set selectedIndex(value:int) :void
      {
         //m4_VERBOSE('selectedIndex: value:', value);
         super.selectedIndex = value;
         if (value != -1) {
            m4_ASSERT(value < dataProvider.length);
            this.show_icon();
            // NOTE This only works with XML dataProviders, not with inline
            //      <mx:Object> objects
            try {
               this.toolTip = dataProvider[value].@label;
            }
            catch (e:ReferenceError) {
               // This works without raising, even if label doesn't exist.
               this.toolTip = dataProvider[value].label;
            }
         }
         else {
            // Use the "Varies" icon if iconForVaries is set.
            var displayIcon:Class = this.item_to_icon(null);
            //m4_DEBUG2('selectedIndex: value:', value,
            //          '/ displayIcon:', displayIcon);
            if (displayIcon !== null) {
               this.show_icon(displayIcon);
            }
         }
      }

      // Sets the icon to the currently selected list item.
      private function show_icon(displayIcon:Class=null) :void
      {
         if (displayIcon === null) {
            displayIcon = this.item_to_icon(
               this.dataProvider[this.selectedIndex]);
         }

         if (getChildByName('display_icon_object')) {
            this.removeChild(getChildByName('display_icon_object'));
         }

         // Make sure there's an icon, otherwise bail
         if (!displayIcon) {
            // We're here if addChild hasn't been called.
            if (this.textInput !== null) {
               this.textInput.x = 0;
            }
            return;
         }

         // Create and add the new icon object
         this.display_icon_object = new displayIcon;
         this.display_icon_object.name = 'display_icon_object';
         this.addChild(DisplayObject(this.display_icon_object));

         // This is pre-Statewide UI:
         //   // Offset the left side based on the corner radius.
         //   DisplayObject(display_icon_object).x = getStyle('cornerRadius');
         // This is post-Statewide UI:
         // Offset the left side based on the specified left padding.
         DisplayObject(this.display_icon_object).x = this.padding_icon_left;

         // Offset the height of the icon to center it
         DisplayObject(this.display_icon_object).y =
            (this.height - DisplayObject(this.display_icon_object).height) / 2;

         // Make sure we're not being called before addChild's been called,
         // then set textInput based on client's configuration.
         if (this.textInput !== null) {
            if (this.enable_text_field_label) {
               // If you want to show the icon and the text in the text field,
               // move textInput to make room for the icon
               this.textInput.visible = true;
               // MAYBE: Statewide UI: We omitted cornerRadius above.
               //                      Should we also omit it here?
               this.textInput.x = DisplayObject(this.display_icon_object).width
                                  + getStyle('cornerRadius')
                                  + this.padding_icon_left;
            }
            else {
               // Otherwise, if you want to show only the icon, hide textInput
               this.textInput.visible = false;
            }
         }
      }

      // This is a hack to expose the protected textInput member so callers
      // can set the style of the button text independently of the dropdown
      // text.
      public function get textInput_() :TextInput
      {
         return this.textInput;
      }

      // ***

      // Returns the list item's icon, based on whether iconFunction or
      // iconClass is set.
      public function item_to_icon(data:Object) :Class
      {
         var icon_class:Class = null;
         if (data === null) {
            // See if the parent set iconForVaries.
            icon_class = this.iconForVaries;
         }
         else if (this.iconFunction !== null) {
            icon_class = this.iconFunction(data, true);
         }
         else {
            var iconClass:Class;
            var icon:*;
            if (data is XML) {
               try {
                  if (data[iconField].length() != 0) {
                     icon = String(data[iconField]);
                     if (icon !== null) {
                        // FIXME: Why not just call getDefByName direct?
                        icon_class =
                           Class(systemManager.getDefinitionByName(icon));
                        if (!icon_class) {
                           icon_class = document[icon];
                        }
                     }
                  }
               }
               catch (e:Error) { }
            }
            else if (data is Object) {
               try {
                  if (data[iconField] !== null) {
                     if (data[iconField] is Class) {
                        return data[iconField];
                     }
                     if (data[iconField] is String) {
                        icon_class = Class(
                           systemManager.getDefinitionByName(data[iconField]));
                        if (!icon_class) {
                           icon_class = document[data[iconField]];
                        }
                     }
                  }
               }
               catch (e:Error) { }
            }
         }
         return icon_class;
      }

      // ***

      // Returns true if the specified list item is disabled (and should be
      // grey-out and have it not respond to mouse and keyboard interaction)
      public function index_is_disabled(obj:Object) :Boolean
      {
         return ((obj !== null)
                  && (((obj is XML) && (obj.@enabled == 'false'))
                      || (obj.enabled == false)
                      || (obj.enabled == 'false')));
      }

      // Selects the next enabled list item. Useful for keyboard/accessibility
      // interface as well as resetting the control when the list items change
      // enabled status (such that current list item becomes disabled and a new
      // list item should be selected)
      public function select_next_enabled(forward:Boolean = true) :void
      {
         var next:int = this.selectedIndex;
         if (next == -1) {
            next = 0;
         }
         for (var i:int = 0; i < dataProvider.length; i++) {
            var obj:Object;
            next += forward ? 1 : -1;
            if (next >= dataProvider.length) {
               next = 0;
            }
            else if (next < 0) {
               next = dataProvider.length - 1;
            }
            obj = dataProvider[next];
            if (!index_is_disabled(obj)) {
               this.selectedIndex = next;
               break;
            }
            // else TESTME/FIXME What happens when all items are disabled?
         }
      }

      // ***

      //
      public function handle_on_dropdown_key_down(event:KeyboardEvent) :Boolean
      {
         var stop_prop_and_droll:Boolean = false;
         m4_DEBUG('_on_ddown_key_dwn: dropDownKeyDown:', this.dropDownKeyDown);
         if (this.dropDownKeyDown !== null) {
            stop_prop_and_droll = this.dropDownKeyDown(event);
         }
         // Return true if the caller (our List_Disableable dropdown) should
         // stop propagation of the key event.
         return stop_prop_and_droll;
      }

      // On dropdown Open, moves the dropdown left if it would otherwise be
      // clipped by the right-side of the viewport.
      public function handle_on_dropdown_open(event:DropdownEvent) :void
      {
         m4_DEBUG('handle_on_dropdown_open');

         // If the dropdown is off the right of the screen, send it back left
         // (but only if the dropdown is less wide than the parent)
         if ((this.dropdown.measuredWidth < this.dropdown.parent.width)
              && ((this.dropdown.x + this.dropdown.measuredWidth)
                  > this.dropdown.parent.width)) {
            // NOTE This doesn't work: this.dropdown.setStyle('right', 0);
            this.dropdown.x = this.dropdown.parent.width
                              - this.dropdown.measuredWidth;
         }
      }

   }
}


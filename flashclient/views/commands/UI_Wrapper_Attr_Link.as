/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.controls.ComboBox;
   import mx.core.UIComponent;

   import items.Item_User_Access;
   import items.Link_Value;
   import items.attcs.Attribute;
   import utils.misc.Combo_Box_V2;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   // This class wires UI controls for setting Link_Values. Note that, in
   // Cyclopath, links can connect any item with any other item (tags and
   // byways, annotations and waypoints, etc.), but the value of the link
   // only matters to attributes. So this class only pertains to linking
   // items with attributes.
   public class UI_Wrapper_Attr_Link extends UI_Wrapper {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Wrp_AtL');

      // *** Constructor

      public function UI_Wrapper_Attr_Link()
      {
         m4_ASSERT(false); // Never instantiated
      }

      // *** Static class methods

      // As stated above, this class only pertains to links to attributes.
      // The widget is the control being wired and wattr is the name of the
      // member that stores the control value. The callee also passes a
      // collection of items and the name of the attribute whose link values
      // we're editing.
      // 2012.08.15: Is this just for link_post-revision?
      public static function wrap(widget:UIComponent,
                                  wattr:String,
                                  feats:Set_UUID,
                                  attr:Attribute,
                                  value_type:String) :void
      {
         var f:Function;

         m4_ASSERT(feats.length > 0);

// FIXME_2013_06_11: [lb] is a little surprised to find this here: the widgets
//                   should control this, not us, right?
// EXPLAIN: What's up w/ can_edit??
         var can_edit:Boolean = true;
         if (!can_edit) {
            // FIXME: Does this work? Most widgets swap themselves for labels
            //        if non-editing mode...
            widget.enabled = false;
         }
         else {
            var cbox:ComboBox = (widget as ComboBox);
            var cbox2:Combo_Box_V2 = (widget as Combo_Box_V2);

            // Initialize the value of the control based on the value of the
            // existing link(s).
            var default_:* = undefined;
            var on_empty:* = undefined;
            if (cbox2 !== null) {
               m4_VERBOSE(' cbox2.noOptionOption:', cbox2.noOptionOption);
               on_empty = cbox2.noOptionOption;
            }

            m4_VERBOSE('wrap: feats.length:', feats.length);
            var consensus:* = Attribute.consensus(
                  feats, attr, default_, on_empty);
            m4_VERBOSE3('wrap: consensus:',
                        (consensus != undefined) ? consensus : '<undef>',
                        '/ attr:', attr);

            // FIXME: Can we make this Combo_Box_V2, so we can set textInput
            //        italic on -1?
            // m4_DEBUG('widget:', String(Introspect.get_constructor(widget)));
            if (cbox !== null) {
               if (consensus != undefined) {
                  G.combobox_code_set(cbox, consensus);
               }
               else {
                  // Is this right? Or selectedItem = null?
                  cbox.selectedIndex = -1;
               }
            }
            else {
               // ASSUMING: Stepper, or similar.
               widget[wattr] = consensus;
               m4_VERBOSE('wrap: widget[wattr]:', widget[wattr]);
            }

            var text_input:Text_Field_Editable;
            text_input = (widget as Text_Field_Editable);
            if (text_input === null) {
               // Set up the event listener. Each time the user fiddles with
               // the control, we create a new Command_Base object. The command
               // applies the change to the link, and can be used by the user
               // to undo the change.
               f = function(ev:Event) :void
               {
                  var value_new:*;
                  var cbox:ComboBox = (widget as ComboBox);
                  if (cbox !== null) {
                     //value_new = cbox.selectedItem.label;
                     value_new = cbox.selectedItem[wattr];
                  }
                  else {
                     value_new = widget[wattr];
                  }
                  m4_VERBOSE('wrap: f: value_new:', value_new);

                  var cmd:Attribute_Links_Edit;
                  cmd = new Attribute_Links_Edit(
                     attr, feats.clone(), value_new, value_type)
                  G.map.cm.do_(cmd);
                  // The item(s) whose attrs are being edited should be
                  // hydrated.
                  m4_ASSERT_SOFT(cmd.is_prepared !== null);
               }

               // Fire the nameless fcn. we just created whenever the user
               // interacts with the control.
               m4_VERBOSE('wrap: listener_set: ch-ch-ch-change');
               UI_Wrapper.listener_set('change', widget, f);
            }
            else {
               // Get link_values for commands that
               // Text_Field_Editable.record() makes.
               //
               // See some of the Command_Base classes' link_values_get_or_make
               // and link_value_to_edit which do something similar.
               var links:Set_UUID = new Set_UUID();
               var make_new_maybe:Boolean = true;
               for each (var item:Item_User_Access in feats) {
                  var link:Link_Value = 
                     Link_Value.items_get_link_value(
                           attr, item, make_new_maybe);
                  links.add(link);
               }
               m4_VERBOSE('wrap: text_input.features: links:', links);
               text_input.features = links;
            }
         }
      }

   }
}


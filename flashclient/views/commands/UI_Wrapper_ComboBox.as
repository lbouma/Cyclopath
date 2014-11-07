/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.controls.ComboBox;

   import utils.misc.Logging;
   import utils.misc.Objutil;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class UI_Wrapper_ComboBox extends UI_Wrapper {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Wrp_Cbo');

      // *** Constructor

      public function UI_Wrapper_ComboBox()
      {
         m4_ASSERT(false); // Never instantiated
      }

      // *** Static class methods

      //
      public static function wrap(cbox:ComboBox,
                                  targets:Set_UUID,
                                  property_name:String) :void
      {
         var f:Function;

         // Set widget value. If there's no consensus, shows '_Varies_'.
         var consensus:* = Objutil.consensus(targets, property_name);
         //m4_DEBUG('wrap: pname:', property_name, '/ consensus:', consensus);
         //m4_DEBUG('wrap: [property_name]:', targets.one()[property_name]);
         G.combobox_code_set(cbox, consensus);

         // Set up event listener.
         m4_ASSERT(targets.length > 0);

         f = function(ev:Event) :void
         {
            //m4_DEBUG('wrap: f:', cbox.selectedItem.id, '/', property_name);
            //m4_DEBUG('f: cbox.selectedItem.id:', cbox.selectedItem.id);
            //m4_DEBUG('f: property_name:', cbox.selectedItem[property_name]);
            var cmd:Command_Scalar_Edit;
            cmd = new Command_Scalar_Edit(
               targets.clone(), property_name, cbox.selectedItem.id);
            G.map.cm.do_(cmd);
            // The item(s) whose attributes are being edited are hydrated.
            m4_ASSERT_SOFT(cmd.is_prepared !== null);
         }
         UI_Wrapper.listener_set('change', cbox, f);
      }

   }
}


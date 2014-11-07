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

   // This class is like UI_Wrapper_ComboBox except that it manipulates an
   // attribute that's part of an object other than Item_Versioned.

   // It doesn't seem necessary that this derives from UI_Wrapper...

// FIXME: Do I need this class?

   public class UI_Wrapper_Group_Item_Access extends UI_Wrapper {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Wrp_CB2');

      // *** Constructor

      public function UI_Wrapper_Group_Item_Access()
      {
         m4_ASSERT(false); // Never instantiated
      }

      // *** Static class methods

      //
      public static function wrap(cbox:ComboBox,
                                  targets:Set_UUID,
                                  property_fcn:String,
                                  property_key:*) :void
      {
         var f:Function;

         m4_DEBUG('wrap:', targets);

         // Set widget value.
         // NOTE: The consensus returns an integer ID which is used to key into
         //       the ComboBox's dataProvider. The ID is really access_level_id
         //       but the ID is the same in the dataProvider collection.
         G.combobox_code_set(cbox, Objutil.consensus_fcn(targets,
                                                         property_fcn,
                                                         property_key));

         // Set up event listener.
         m4_ASSERT(targets.length > 0);

         f = function(ev:Event) :void
         {
            var cmd:Group_Item_Access_Edit;
            cmd = new Group_Item_Access_Edit(targets.clone(),
                                             property_fcn,
                                             property_key,
                                             cbox.selectedItem.id);
            G.map.cm.do_(cmd);
            // The item(s) whose gias are being edited should be hydrated.
            m4_ASSERT(cmd.is_prepared !== null);
         }

         UI_Wrapper.listener_set('change', cbox, f);
      }

   }
}


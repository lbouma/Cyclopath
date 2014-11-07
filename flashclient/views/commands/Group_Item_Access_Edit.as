/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Access_Level;
   import grax.Dirty_Reason;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Group_Item_Access_Edit extends Command_Scalar_Edit_2 {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_GrpACbx');

      // *** Constructor

      public function Group_Item_Access_Edit(targets:Set_UUID,
                                             property_fcn:String,
                                             property_key:*,
                                             value_new:*,
                                             reason:int=0)
      {
         if (reason == 0) {
            reason = Dirty_Reason.item_data;
         }
         super(targets, property_fcn, property_key, value_new, reason);
      }

      // *** Getters and setters

      // Only the owner of an item may edit its group access.
      override protected function get prepare_items_access_min() :int
      {
         m4_DEBUG('prepare_items_access_min: returning Access_Level.owner');
         // FIXME: Should this be Access_Level.arbiter ??
         return Access_Level.owner;
      }

      // This command only applies to existing items. See Group_Access_Create
      // for adding new Group_Item_Access items.
      override protected function get prepare_items_must_exist() :Boolean
      {
         m4_DEBUG('prepare_items_must_exist: return true');
         return true;
      }

   }
}


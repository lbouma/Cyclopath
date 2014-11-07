/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: Can probably delete this file.

package views.commands {

   import grax.Dirty_Reason;
   import items.Item_User_Access;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Group_Item_Access_Change extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Rt_AcCh');

      // *** Instance variables

      protected var old_style_change:int;
      protected var new_style_change:int;

      protected var was_dirty_item_schg:Boolean;

      protected var cmd_edit_name:Command_Scalar_Edit;

      // *** Constructor

      public function Group_Item_Access_Change(
//         rt:Route,
//         permission:int,
//         visibility:int,
//         name:String=null)
         // MAYBE: Make an Item_Ceil or Item_Class class?

// FIXME: Take multiple items instead
item:Item_User_Access,
// FIXME: do this instead:
//        edit_items:Array,

         new_style_change:int,
         new_item_name:String=null)
      {
         this.old_style_change = item.style_change;
         this.new_style_change = new_style_change;
         this.was_dirty_item_schg = item.dirty_get(Dirty_Reason.item_schg);

         if (new_item_name !== null) {
            this.cmd_edit_name = new Command_Scalar_Edit(
               new Set_UUID([item,]), 'name', new_item_name);
         }

         super([item], Dirty_Reason.item_data);
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         return 'changing access of route';
      }

      //
      override public function do_() :void
      {
         super.do_();

         m4_ASSURT(this.edit_items.length == 1);
         var item:Item_User_Access = this.edit_items[0];
         item.style_change = this.new_style_change;
         item.dirty_set(Dirty_Reason.item_schg, true);

         if (this.cmd_edit_name !== null) {
            this.cmd_edit_name.do_();
         }
      }

      //
      override public function undo() :void
      {
         super.undo();

         m4_ASSURT(this.edit_items.length == 1);
         var item:Item_User_Access = this.edit_items[0];
         item.style_change = old_style_change;
         item.dirty_set(Dirty_Reason.item_schg,
                        this.was_dirty_item_schg);

         if (this.cmd_edit_name !== null) {
            this.cmd_edit_name.undo();
         }
      }

   }
}


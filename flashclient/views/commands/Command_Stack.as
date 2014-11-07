/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Extends Stack, assumes that all items are Command_Base objects, and adds
   contains() method. */

package views.commands {

   import items.Item_Versioned;
   import utils.misc.Logging;
   import utils.misc.Stack;

   public dynamic class Command_Stack extends Stack {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Stack');

      // *** Constructor

      // Create a stack that can hold up to limit Command_Bases. Omit limit for
      // no limit.
      public function Command_Stack(limit:int = 0)
      {
         super(limit);
      }

      // *** Other methods

      // Tests the stack for the presence of item. This function is O(n^2).
      public function contains(item:Item_Versioned) :Boolean
      {
         var c:Command_Base;

         for each (c in this.data) {
            if (c.contains_item(item)) {
               return true;
            }
         }

         return false;
      }

      // Removes all commands that have item present in them.
      public function remove_feature(item:Item_Versioned) :int
      {
         var c:Command_Base;
         var num_removed:int = 0;
         var new_data:Array = new Array();

         for each (c in this.data) {
            if (!c.contains_item(item)) {
               new_data.push(c);
            }
            else {
               num_removed++;
            }
         }

         this.data = new_data;

         return num_removed;
      }

      // Return a list of the contents of the stack. READ-ONLY (used by
      // dirty_rect in Command_Manager.as).
      public function get as_list() :Array
      {
         return this.data;
      }

   }
}


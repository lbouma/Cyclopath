/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* A size-limited stack which holds anything. If the limit is exceeded, excess
   items are deleted from the bottom. More generic than original Stack
   used by the commands.Command_Manager */

package utils.misc {

   public dynamic class Stack {

      protected var data:Array;
      protected var limit:int = 0;

      // *** Constructor

      // Create a stack that can hold up to limit items. Omit limit for no
      // limit.
      public function Stack(limit:int = 0)
      {
         this.data = new Array();
         this.limit = limit;
      }

      // *** Getters and setters

      //
      public function as_array() :Array
      {
         return this.data;
      }

      //
      public function get length() :int
      {
         return this.data.length;
      }

      // *** Other methods

      // Remove all items from the stack.
      public function clear() :void
      {
         this.data.length = 0;
      }

      // Return true if the stack is empty, false otherwise.
      public function is_empty() :Boolean
      {
         return (this.data.length == 0);
      }

      // Return the item at the top of the stack, but don't remove it. If
      // the stack is empty, return null.
      public function peek() :*
      {
         if (this.is_empty()) {
            return null;
         }
         else {
            return this.data[this.data.length-1];
         }
      }

      // Pop an item. If the stack is empty, return null.
      public function pop() :*
      {
         if (this.is_empty()) {
            return null;
         }
         else {
            return this.data.pop();
         }
      }

      // Push an item.  Return the old last item in the stack if it was
      // removed because of stack size limits, null otherwise.
      public function push(c:*) :*
      {
         this.data.push(c);
         if ((this.limit > 0) && (this.data.length > this.limit)) {
            return this.data.shift();
         }
         else {
            return null;
         }
      }

      // ***

      //
      public function toString() :String
      {
         var str:String =
            'Cmd_Stk: size: ' + String(this.length)
            + '/ limit: ' + String(this.limit)
            + '/ cmds: ' + this.data
            ;
         return str;
      }

   }
}


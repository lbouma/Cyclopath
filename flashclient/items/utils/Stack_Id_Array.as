/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This class is an Array wrapper that knows how to call version_id_unhack. */

package items.utils {

   import items.Item_Revisioned;
   //import utils.misc.Logging;

   // NOTE: This class is dynamic because that's what you do when you extend
   //       Dictionary or Array.

   public dynamic class Stack_Id_Array extends Array {

      // *** Class attributes

      //protected static var log:Logging = Logging.get_logger('##StkIdArray');

      // ***

      public function Stack_Id_Array(...args)
      {
         // C.f. http://help.adobe.com/en_US/ActionScript/3.0_ProgrammingAS3
         //       /WS5b3ccc516d4fbf351e63e3d118a9b90204-7ee4.html
         if ((args.length == 1) && (args[0] is Number)) {
            var dlen:Number = args[0];
            var ulen:uint = dlen
            if (ulen != dlen) {
               throw new RangeError(
                  'Array index is not a 32-bit unsigned integer ('
                  + dlen + ')');
            }
            this.length = ulen;
         }
         else {
            if ((args.length == 1) && (args[0] is Stack_Id_Array)) {
               this.length = args[0].length;
               for (var ii:int = 0; ii < args[0].length; ii++) {
                  this.push(args[0][ii])
               }
            }
            else {
               this.length = args.length;
               for (var i:int = 0; i < args.length; i++) {
                  //this[i] = args[i];
                  // type check done in push()
                  this.push(args[i])
               }
            }
         }
      }

      // ***

      //
      AS3 override function concat(...args) :Array
      {
         // Caveat: You cannot up-cast this to Stack_Id_Array.
         m4_ASSURT(false);

         var new_arr:Stack_Id_Array = new Stack_Id_Array();
         for (var i:* in args) {
            // type check done in push()
            new_arr.push(args[i]);
         }
         return (super.concat.apply(this, new_arr));
      }

      //
      AS3 override function push(...args) :uint
      {
         for each (var stack_id:int in args) {
            super.push(Item_Revisioned.version_id_unhack(stack_id));
         }
         return this.length;
      }

      //
      AS3 override function splice(...args) :*
      {
         m4_ASSURT(false); // Not implemented.

         if (args.length > 2) {
            for (var i:int = 2; i < args.length; i++) {
               args.splice(i, 1);
            }
         }
         return (super.splice.apply(this, args));
      }

      //
      AS3 override function unshift(...args) :uint
      {
         m4_ASSURT(false); // Not implemented.

         for (var i:* in args) {
            args.unshift(i);
         }
         return (super.unshift.apply(this, args));
      }

      // ***
      //
      // C.f. utils.misc.Collection

      //
      public function array_concat(...args) :Stack_Id_Array
      {
         var new_arr:Stack_Id_Array = new Stack_Id_Array(this);
         for (var i:* in args) {
            new_arr.push(args[i]);
         }
         return new_arr;
      }

      //
      public function array_copy() :Stack_Id_Array
      {
         // This performs a shallow copy of a (it copies object references).
         var new_arr:Stack_Id_Array = new Stack_Id_Array(this);
         return new_arr;
      }

      // Return true if the items in the two arrays are equivalent and in the
      // same order, false otherwise.
      public static function array_eq(a:Stack_Id_Array, b:Stack_Id_Array)
         :Boolean
      {
         var equal:Boolean = true;

         if (a === null) {
            if (b !== null) {
               //m4_VERBOSE('array_eq: one is null: a:', a, '/ b:', b);
               equal = false;
            }
         }
         else if (a.length != b.length) {
            equal = false;
            //m4_VERBOSE('array_eq: diff. length:', a.length, '/', b.length);
         }
         else {
            for (var i:int = 0; i < a.length; i++) {
               if (a[i] !== b[i]) {
                  //m4_VERBOSE('array_eq: diff. i:', i, '/', a[i], '/', b[i]);
                  equal = false;
                  break;
               }
            }
         }

         return equal;
      }

      // Return true if item x is in array a, false otherwise.
      public function array_in(x:*) :Boolean
      {
         var i:int;

         for (i = 0; i < this.length; i++) {
            if (this[i] === x) {
               return true;
            }
         }
         return false;
      }

      // Return the index of the item, or -1.
      public function array_index(x:*) :int
      {
         var i:int;

         for (i = 0; i < this.length; i++) {
            if (this[i] === x) {
               break;
            }
         }
         if (i == this.length) {
            i = -1;
         }

         return i;
      }

      // Removes matching values from an Array, returning a new Array.
      // SIDE_EFFECT:
      //    1. All duplicate values will be removed. We use Set() to make the
      //       operation easier to code, so if you, e.g.,
      //          a = array_remove(3, [1,2,3,4,5,5,4,3,2,1]);
      //       you'll get something like [1,2,4,5].
      //    2. Order is not preserved. Like (1.), this is because we use Set().
      public function array_remove(x:*) :Array
      {
         //var intermediate:Set_UUID = new Set_UUID(this);
         //intermediate.remove(x);
         //return intermediate.as_Array();
         var new_arr:Stack_Id_Array = new Stack_Id_Array();
         for each (var o:Object in this) {
            if (o !== x) {
               new_arr.push(o);
            }
         }
         return new_arr;
      }

   }
}


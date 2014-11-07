/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A Collections class helper class

package utils.misc {

   import flash.utils.Dictionary;

   public class Collection {

      // *** Class attributes.

      protected static var log:Logging = Logging.get_logger('Collection');

      // *** Constructor

      //
      public function Collection() :void
      {
         m4_ASSERT(false); // Not instantiable

      }

      // *** Class methods

      //
      public static function array_copy(arr:*) :Array
      {
         // This performs a shallow copy of a (it copies object references).
         var new_arr:Array = null;
         if (arr !== null) {
            new_arr = new Array();
            new_arr = new_arr.concat(arr);
         }
         // else, we could set to new Array(), but... it's better to signal
         //       otherwise.
         return new_arr;
      }

      // Return true if the items in the two arrays are equivalent and in the
      // same order, false otherwise.
      public static function array_eq(a:Array, b:Array) :Boolean
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
      public static function array_in(x:*, a:Array) :Boolean
      {
         var i:int;

         for (i = 0; i < a.length; i++) {
            if (a[i] === x) {
               return true;
            }
         }
         return false;
      }

      // Return the index of the item, or -1.
      public static function array_index(x:*, a:Array) :int
      {
         var i:int;

         for (i = 0; i < a.length; i++) {
            if (a[i] === x) {
               break;
            }
         }
         if (i == a.length) {
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
      public static function array_remove(x:*, a:Array) :Array
      {
         //var intermediate:Set_UUID = new Set_UUID(a);
         //intermediate.remove(x);
         //return intermediate.as_Array();
         var new_arr:Array = new Array();
         for each (var o:Object in a) {
            if (o !== x) {
               new_arr.push(o);
            }
         }
         return new_arr;
      }

      //
      public static function dict_clone(dict:*) :Dictionary
      {
         return Collection.dict_copy(dict);
      }

      //
      public static function dict_copy(dict:*) :Dictionary
      {
         // This performs a shallow copy of dict (it copies object references).
         var new_dict:Dictionary = null;
         if (dict !== null) {
            new_dict = new Dictionary();
            // NOTE: Using for and not for-each to get keys, not values.
            for (var dict_key:Object in dict) {
               new_dict[dict_key] = dict[dict_key];
            }
         }
         // else, we could set to new Dictionary(), but... it's better to
         //       signal otherwise.
         return new_dict;
      }

      // Returns whether or not a Dictionary is empty
      public static function dict_is_empty(d:Dictionary) :Boolean
      {
         var empty:Boolean = true;
         for (var obj:Object in d) {
            // At least one key
            empty = false;
            break;
         }
         return empty;
      }

      // Returns the number of items in a Dictionary
      public static function dict_length(d:Dictionary) :int
      {
         var len:int = 0;
         for (var obj:Object in d) {
            // count keys
            len++;
         }
         return len;
      }

      // C.f. pyserver/util_/misc.py
      public static function dict_set_add(dict_list:Dictionary,
                                          dict_key:String,
                                          set_val:*,
                                          strict:Boolean=false) :void
      {
         if (!(dict_key in dict_list)) {
            //dict_list[dict_key] = new Set();
            dict_list[dict_key] = new Set_UUID();
         }
         else if (strict && (set_val in dict_list[dict_key])) {
            m4_WARNING2('dict_set_add: value exists: dict_list[dict_key]:',
                        dict_key, '/ value:', dict_list[dict_key]);
         }
         dict_list[dict_key].add(set_val);
      }

      // C.f. pyserver/util_/misc.py
      public static function dict_set_remove(dict_list:Dictionary,
                                             dict_key:String,
                                             set_val:*,
                                             strict:Boolean=false) :void
      {
         if (!(dict_key in dict_list)) {
            if (strict) {
               m4_WARNING2('dict_set_remove: dict_list missing dict_key:',
                           dict_key);
            }
         }
         else {
            if (!(set_val in dict_list[dict_key])) {
               if (strict) {
                  m4_WARNING2('dict_set_remove: dict_list[dict_key] missing:',
                              set_val, '/ the set:', dict_list[dict_key]);
               }
            }
            else {
               dict_list[dict_key].remove(set_val);
            }
         }
      }

      // Returns the values of a Dictionary as an Array
      public static function dict_values_as_array(d:Dictionary) :Array
      {
         var o:Object;
         var a:Array = new Array();
         for each (o in d) {
            a.push(o);
         }
         return a;
      }

      //
      public static function something_as_array(some_collection:*) :Array
      {
         var new_arr:Array = new Array();
         for each (var thing:* in some_collection) {
            new_arr.push(thing);
         }
         return new_arr;
      }

   }
}


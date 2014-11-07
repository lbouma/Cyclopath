/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A Set class.
//
// NOTE: Set is a Dictionary that maintains itself as this[x] = x. This means
//       that both types of for loops can be used (for-in and for-each).
//       The for-in will not have the proper types because it loops over the
//       stringified keys of the Set.  It is highly recommended to use
//       for-each for performance, and parity with Array.
//
//       for-in can be used if tampering is done with the value stored in
//       the Set for each key (i.e. see Update_Base).
//
// WARNING: While use of square brackets on Sets will compile, do not use
//          them. It will screw up the length value.
//
// WARNING: This class still have some weird shit going on so use with caution.
//          In particular, you can't put strings or ints in it (!!!), and
//          members are compared with the strict equality operator (===). [rp]
// 2010.09.01: Declaring this class dynamic should solve [rp]'s problem. [lb]
//
// NOTE: This class must be declared dynamic for the [] operator to work right.

package utils.misc {

   import flash.utils.Dictionary;

   // NOTE: This class is dynamic because that's what you do when you extend
   //       Dictionary or Array.

   public dynamic class Set extends Dictionary {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Set__');

      // *** Instance variables

      protected var length_:int;   // number of items in the set

      // *** Constructor

      public function Set(members:Array=null)
      {
         var o:Object;
         super();
         this.length_ = 0;
         if (members !== null) {
            for each (o in members) {
               this.add(o);
            }
         }
      }

      // *** Getters and setters

      //
      public function get empty() :Boolean
      {
         return (this.length_ == 0);
      }

      //
      public function get length() :int
      {
         return this.length_;
      }

      // *** Instance methods

      //
      public function add(x:*) :void
      {
         if (!(x in this)) {
            // Add an entry to the database.
            // NOTE: We used to not care about the value we set, so it used to
            //       be null. Now, it's set to the object itself, such that we
            //       can iterate over the Set using for-each, which is quicker
            //       and easier to work with than for-in-ing.
            this[x] = x;
            this.length_++;
         }
      }

      //
      /*
      public function add(x:Object) :void
      {
         var s:String;
         var o:*;
         if (x is String) {
            s = x as String;
            if (!(s in this)) {
               this[s] = 1;
               this.length_++;
            }
         }
         else {
            //o = x as *;
            o = x;
            if (!(o in this)) {
               this[o] = 1;
               this.length_++;
            }
         }
      }
      */

      //
      public function add_all(a:*) :void
      {
         var o:Object;
         if (a !== null) {
            for each (o in a) {
               this.add(o);
            }
         }
      }

      // Return an array containing my members.
      public function as_Array() :Array
      {
         var a:Array = new Array();
         var o:Object;
         for each (o in this) {
            a.push(o);
         }
         return a;
      }

      //
      public function clear() :void
      {
         var clone:Set = this.clone();
         var o:Object;
         for each (o in clone) {
            this.remove(o);
         }
      }

      // Return a shallow copy of myself.
      public function clone() :Set
      {
         var s:Set = new Set();
         var o:Object;
         for each (o in this) {
            s.add(o);
         }
         return s;
      }

      // Returns true if item is in the set.
      public function contains(item:Object) :Boolean
      {
         return this.is_member(item);
      }

      // Returns true if at all items in itms are in the set.
      public function contains_all(itms:*) :Boolean
      {
         var contains_all:Boolean = true;
         for each (var item:Object in itms) {
            if (!this.is_member(item)) {
               contains_all = false;
               break;
            }
         }
         return contains_all;
      }

      // Returns true if at least one item in itms is in the set.
      public function contains_any(itms:*) :Boolean
      {
         var contains_at_least_one:Boolean = false;
         for each (var item:Object in itms) {
            if (this.is_member(item)) {
               contains_at_least_one = true;
               break;
            }
         }
         return contains_at_least_one;
      }

      // NOTE: The name and info of this fcn. ripped off of Python's set().
      // "Return a new set with elements in either the set or other but not
      //  both."
      public function equals(other:Set) :Boolean
      {
         var is_equal:Boolean = (this.length == other.length);
         var o:Object;
         if (is_equal) {
            for each (o in this) {
               if (!(o in other)) {
                  // m4_DEBUG('equals: no: !(o in other):', o);
                  is_equal = false;
                  break;
               }
            }
         }
         if (is_equal) {
            for each (o in other) {
               if (!(o in this)) {
                  // m4_DEBUG('equals: no: !(o in this):', o);
                  is_equal = false;
                  break;
               }
            }
         }
         return is_equal;
      }

      // "Executes a test function on each item in the array until an item is
      //  reached that returns false for the specified function."
      // [C.f. Flex Array documentation.]
      public function every(callback:Function, thisObject:*=null) :Boolean
      {
         var result:Boolean = true;
         var o:Object;
         for each (o in this) {
            result = callback(o, this);
            if (!result) {
               break;
            }
         }
         return result;
      }

      // Returns true if item is in the set.
      public function is_member(item:Object) :Boolean
      {
         return (item in this);
      }

      // Return an arbitrary member of myself. Behavior undefined if I have no
      // members.
      public function item_get_random() :Object
      {
         var o:Object = null;
         if (this.length > 0) {
            for each (o in this) {
               break; // just grab the first one
            }
         }
         return o;
      }

      // If the Set has just zero or one member(s), returns null or the member.
      // If the Set contains two or more members, throws an error.
      public function one() :Object
      {
         //trace('Set: one: this.length:', this.length);
         m4_ASSERT(this.length < 2);
         return this.item_get_random();
      }

      //
      public function remove(x:*) :void
      {
         if (x in this) {
            this.length_--;
            delete this[x];
         }
      }

      //
      public function toString(use_newlines:Boolean=false) :String
      {
         var set_contents:String;
         if (this.empty) {
            set_contents = '(empty Set)';
         }
         else {
            set_contents = '';
            // NOTE: Not 'for each'
            for (var key:String in this) {
               if (set_contents != '') {
                  if (!use_newlines) {
                     set_contents += ', ';
                  }
                  else {
                     set_contents += '\n';
                  }
               }
               set_contents += key;
            }
         }
         return set_contents;
      }

   }
}


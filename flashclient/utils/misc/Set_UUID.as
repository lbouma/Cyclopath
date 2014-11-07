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
   import mx.utils.UIDUtil;

   // NOTE: This class is dynamic because that's what you do when you extend
   //       Dictionary or Array.

   public dynamic class Set_UUID extends Dictionary {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Set_UUID__');

      // *** Instance variables

      protected var length_:int;   // number of items in the set

      // *** Constructor

      public function Set_UUID(members:Array=null)
      {
         var obj:Object;
         super();
         this.length_ = 0;
         if (members !== null) {
            for each (obj in members) {
               this.add(obj);
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
      public function add(x:*) :String
      {
         // Flex is weird. If you getUID on an Array, the UID becomes part
         // of any 'for' or 'for each' loop. And -- to boot -- the Array
         // length remains unchanged. [lb] is surprised not to find this topic
         // Googleable, but cursory debugging showed it to be true.
         m4_ASSERT(!(x is Array));
         // The solution is probably to implement the IUID interface and
         // return one's own UID. See: mx_internal_uid.
// http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/mx/core/IUID.html

         var uuid:String = UIDUtil.getUID(x);
         if (!(uuid in this)) {
            // Add an entry to the database.
            // NOTE: We used to not care about the value we set, so it used to
            //       be null. Now, it's set to the object itself, such that we
            //       can iterate over the Set using for-each, which is quicker
            //       and easier to work with than for-in-ing.
            this[uuid] = x;
            this.length_++;
         }

         return uuid;
      }

      //
      /*
      public function add(x:Object) :void
      {
         var s:String;
         var obj:*;
         if (x is String) {
            s = x as String;
            if (!(s in this)) {
               this[s] = 1;
               this.length_++;
            }
         }
         else {
            //obj = x as *;
            obj = x;
            if (!(obj in this)) {
               this[obj] = 1;
               this.length_++;
            }
         }
      }
      */

      //
      public function add_all(a:*) :void
      {
         var obj:Object;
         if (a !== null) {
            for each (obj in a) {
               this.add(obj);
            }
         }
      }

      // Return an array containing my members.
      public function as_Array() :Array
      {
         var a:Array = new Array();
         var obj:Object;
         for each (obj in this) {
            a.push(obj);
         }
         return a;
      }

      //
      public function clear() :void
      {
         var clone:Set_UUID = this.clone();
         var obj:Object;
         for each (obj in clone) {
            this.remove(obj);
         }
      }

      // Return a shallow copy of myself.
      public function clone() :Set_UUID
      {
         var s:Set_UUID = new Set_UUID();
         var obj:Object;
         for each (obj in this) {
            s.add(obj);
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

      // How Python defines difference:
      //  "Return a new set with elements in the set that are not in others."
      public function difference(...others) :Set_UUID
      {
         var the_diff:Set_UUID = this.clone();
         var obj:Object;
         var another_set:Set_UUID;
         if (others[0] is Array) {
            m4_ASSERT(others.length == 1);
            others = others[0];
         }
         for each (another_set in others) {
            for each (obj in another_set) {
               the_diff.remove(obj);
            }
         }
         return the_diff;
      }

      // NOTE: The name and info of this fcn. ripped off of Python's set().
      // "Return a new set with elements in either the set or other but not
      //  both."
      public function equals(other:Set_UUID) :Boolean
      {
         var is_equal:Boolean = (this.length == other.length);
         var obj:Object;
         var uuid:String;
         if (is_equal) {
            for each (obj in this) {
               uuid = UIDUtil.getUID(obj);               
               if (!(uuid in other)) {
                  // m4_DEBUG('equals: no: !(obj in other):', obj);
                  is_equal = false;
                  break;
               }
            }
         }
         if (is_equal) {
            for each (obj in other) {
               uuid = UIDUtil.getUID(obj);               
               if (!(uuid in this)) {
                  // m4_DEBUG('equals: no: !(obj in this):', obj);
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
         var obj:Object;
         for each (obj in this) {
            result = callback(obj, this);
            if (!result) {
               break;
            }
         }
         return result;
      }

      //
      public function extend(a:*) :void
      {
         this.add_all(a);
      }

      // Returns true if item is in the set.
      public function is_member(item:Object) :Boolean
      {
         var uuid:String = UIDUtil.getUID(item);
         return (uuid in this);
      }

      // Return an arbitrary member of myself. Behavior undefined if I have no
      // members.
      public function item_get_random() :Object
      {
         var obj:Object = null;
         if (this.length > 0) {
            for each (obj in this) {
               break; // just grab the first one
            }
         }
         return obj;
      }

      // If the Set_UUID has just zero or one member(s), returns null or the
      // member. If the Set_UUID contains two or more members, throws an error.
      public function one() :Object
      {
         //trace('Set_UUID: one: this.length:', this.length);
         m4_ASSERT(this.length < 2);
         return this.item_get_random();
      }

      //
      public function remove(x:*) :void
      {
         var uuid:String = UIDUtil.getUID(x);
         if (uuid in this) {
            this.length_--;
            delete this[uuid];
         }
      }

      //
      public function toString(use_newlines:Boolean=false) :String
      {
         var key_uuid:String;
         var set_contents:String = '';
         // NOTE: Not 'for each'
         for (key_uuid in this) {
            if (set_contents != '') {
               if (!use_newlines) {
                  set_contents += ', ';
               }
               else {
                  set_contents += '\n';
               }
            }
            set_contents += this[key_uuid];
         }
         return set_contents;
      }

      //
      public function union(...others) :Set_UUID
      {
         var the_union:Set_UUID = this.clone();
         var obj:Object;
         var another_set:Set_UUID;
         if (others[0] is Array) {
            m4_ASSERT(others.length == 1);
            others = others[0];
         }
         for each (another_set in others) {
            for each (obj in another_set) {
               the_union.add(obj);
            }
         }
         return the_union;
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A wacky 2-level set-like structure.
//
// The wackiness is as follows: while members at the first level are compared
// using ===, members at the second level are compared as in Object, i.e.
// stringified and then compared with ==. Also, you can't store null as a
// second-level member.
//
// WARNING: Items, both top and second-level, are stored as keys to a
//          Dictionary, or as dynamic properties on an object. In either case
//          this means that they will be stringified and a for-in loop must
//          be used (instead of a for-each loop). This also restricts using
//          primitive ints as items since that confuses Flash's property
//          engine.
//
// FIXME: This class is generally bullshit [says rp] and should be replaced
//        with a "real" collection when possible (i.e., when ActionScript grows
//        a decent collections API to work from).

// BUG nnnn: Don't store Flash objects using toString... seems... dangerous,
// esp. since toString is a developer fcn. usually... that is, this class
// stringifies items when it keys them into the lookup; we should use IDs
// whenever possible, since stringification is prone to developer error,
// since toString() must guarantee uniqueness but we haven't ever evaluated
// our overrides to verify... unless [lb] is completely wrong about how Flex
// transforms an object into a Dictionary key.

package utils.misc {

   import flash.utils.Dictionary;

   // NOTE: This class is dynamic because that's what you do when you extend
   //       Dictionary or Array.

   public dynamic class Set2 extends Dictionary {

      // *** Instance variables

      protected var length_:int;   // number of items in the set

      // *** Constructor

      public function Set2()
      {
         super();
         this.length_ = 0;
      }

      // *** Getters and setters

      //
      public function get length() :int
      {
         return this.length_;
      }

      // *** Instance methods

      //
      public function add(x:Object, y:Object) :void
      {
         if (!(x in this)) {
            this[x] = new Object();
            this.length_++;
         }
         this[x][y] = 1;
      }

      // Return a shallow copy of myself.
      public function clone() :Set2
      {
         var s:Set2 = new Set2();
         var x:Object;
         var y:Object;

         for (x in this) {
            for (y in this[x]) {
               s.add(x, y);
            }
         }
         return s;
      }

      //
      public function is_member(x:Object, y:Object=null) :Boolean
      {
         return ((x in this) && (y === null || this[x].hasOwnProperty(y)));
      }

      //
      protected function level2_count(x:Object) :int
      {
         var i:int = 0;
         var o:Object;
         if (x in this) {
            for (o in this[x]) {
               i++;
            }
         }
         return i;
      }

      //
      public function remove(x:Object, y:Object=null) :void
      {
         if (x in this) {
            if (this[x].hasOwnProperty(y)) {
               delete this[x][y];
            }
            if (y === null || this.level2_count(x) == 0) {
               this.length_--;
               delete this[x];
            }
         }
      }

   }
}


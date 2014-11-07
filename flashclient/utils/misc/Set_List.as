/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A set of lists (well, a Set of Arrays).

package utils.misc {

   import flash.utils.Dictionary;

   // NOTE: This class is dynamic per extending Array or Dictionary.

   public dynamic class Set_List extends Dictionary {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('__Set_List__');

      // *** Instance variables

      // The length of the set list.
      protected var length_:int;

      // *** Constructor

      public function Set_List()
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
            this[x] = new Array();
            this.length_++;
         }
         this[x].push(y);
      }

      // Return a shallow copy of myself.
      public function clone() :Set_List
      {
         var x:Object;
         var s:Set_List;
         s = new Set_List();
         for (x in this) {
            s[x] = Collection.array_copy(this[x]);
         }
         return s;
      }

      //
      public function is_member(x:Object, y:Object=null) :Boolean
      {
         return ((x in this)
                 && ((y === null) || (Collection.array_in(y, this[x]))));
      }

      //
      protected function level2_count(x:Object) :int
      {
         var y:Object;
         var i:int = 0;
         if (x in this) {
            i = this[x].length;
         }
         return i;
      }

      //
      public function remove(x:Object, y:Object=null) :void
      {
         var new_arr:Array = new Array();
         if (x in this) {
            if (y !== null) {
               for each (var y_:Object in this[x]) {
                  if (y !== y_) {
                     new_arr.push(y_);
                  }
               }
            }
            if (new_arr.length > 0) {
               this[x] = new_arr;
            }
            else {
               this.length_--;
               delete this[x];
            }
         }
      }

   }
}


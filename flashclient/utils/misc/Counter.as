/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   public class Counter {

      protected var i:int;

      //
      public function Counter(i:int) :void
      {
         this.i = i;
      }

      //
      public function get value() :int
      {
         return this.i;
      }

      //
      public function inc() :int
      {
         this.i += 1;
         return this.i
      }

      //
      public function dec() :int
      {
         this.i -= 1;
         return this.i;
      }

   }
}


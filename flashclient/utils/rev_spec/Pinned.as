/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.rev_spec {

   public class Pinned extends Base {

      // *** Constructor

      public function Pinned() :void
      {
         super();
      }

      //
      override public function equals(rev:Base) :Boolean
      {
         var other:Pinned = (rev as Pinned);
         return (other !== null);
      }

   }
}


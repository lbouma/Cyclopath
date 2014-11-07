/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.rev_spec {

   public class Historic extends Pinned {

      // *** Public instance variable

      public var rid_old:int;

      // *** Constructor

      public function Historic(rid_old:int) :void
      {
         super();
         m4_ASSERT(rid_old > 0);
         this.rid_old = rid_old;
      }

      // *** Public instance methods

      //
      override public function equals(rev:Base) :Boolean
      {
         var other:Historic = (rev as Historic);
         return ((other !== null)
                 && (super.equals(other))
                 && (other.rid_old == this.rid_old));
      }

      //
      override public function toString() :String
      {
         return String(this.rid_old);
      }

      //
      override public function get friendly_name() :String
      {
         return String(this.toString() + ' [historic]');
      }

      //
      override public function get short_name() :String
      {
         var sname:String = 'h:' + String(this.rid_old);
         return sname;
      }

   }
}


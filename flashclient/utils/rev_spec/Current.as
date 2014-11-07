/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.rev_spec {

   public class Current extends Follow {

      // *** Constructor

      public function Current(rid_branch_head:int=-1) :void
      {
         super(rid_branch_head);
      }

      // *** Public instance methods

      //
      override public function equals(rev:Base) :Boolean
      {
         var other:Current = (rev as Current);
         return (other !== null);
      }

      //
      override public function toString() :String
      {
         m4_ASSERT(this.rid_branch_head == -1);
         return '';
      }

      //
      override public function get friendly_name() :String
      {
         m4_ASSERT(this.rid_branch_head == -1);
         return String(this.toString() + ' [current]');
      }

      //
      override public function get short_name() :String
      {
         var sname:String = 'cur';
         return sname;
      }

   }
}


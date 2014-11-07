/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.rev_spec {

   public class Follow extends Base {

      // *** Instance members

      public var rid_branch_head:int = -1;

      // Revision IDs -- working copy and branch head
      // See: http://wiki.grouplens.org/index.php/Cyclopath
      //              /Database_Model#Revision_Control_System
      // In Cyclopath V1, the branch head ID was known as rid_max, or the
      // 'Latest known revision ID'. In V2, we introduce a working copy ID,
      // so we can track changes to the server and present conflicts to the
      // user to resolve.
      public var rid_last_update:int = -1;

      // *** Constructor

      public function Follow(rid_branch_head:int) :void
      {
         super();
         m4_ASSERT((rid_branch_head == -1) || (rid_branch_head > 0));
         this.rid_branch_head = rid_branch_head;
         this.rid_last_update = rid_branch_head;
      }

      // *** Public instance methods

      //
      override public function equals(rev:Base) :Boolean
      {
         var other:Follow = (rev as Follow);
         return ((other !== null)
                 && (other.rid_branch_head == this.rid_branch_head)
                 && (other.rid_last_update == this.rid_last_update));
      }

      //
      override public function toString() :String
      {
         return (':' + this.rid_branch_head);
      }

      //
      override public function get friendly_name() :String
      {
         return String(this.toString() + ' [follow]');
      }

      //
      override public function get short_name() :String
      {
         var sname:String = 'f:' + String(this.rid_branch_head);
         return sname;
      }

   }
}


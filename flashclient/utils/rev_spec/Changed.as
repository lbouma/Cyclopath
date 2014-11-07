/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.rev_spec {

   public class Changed extends Current {

      // *** Instance variables

      //public var rid_last_update:int;

      // *** Constructor

      public function Changed(rid_branch_head:int, rid_last_update:int) :void
      {
         super(rid_branch_head);
         m4_ASSERT(rid_last_update > 0);
         this.rid_last_update = rid_last_update;
      }

      // *** Public instance methods

      //
      override public function equals(rev:Base) :Boolean
      {
         var other:Changed = (rev as Changed);
         return ((other !== null)
                 && (super.equals(other))
                 //&& (other.rid_last_update == this.rid_last_update)
                 );
      }

      //
      override public function toString() :String
      {
// FIXME: Update: send *all* changed items... no bbox
         var rid_grp:String = 'all';
         return (
            this.rid_last_update + ':' + this.rid_branch_head + ':' + rid_grp);
      }

      //
      override public function get friendly_name() :String
      {
         return String(this.toString() + ' [updates]');
      }

      //
      override public function get short_name() :String
      {
         var sname:String = 'chg:' + this.toString();
         return sname;
      }

   }
}


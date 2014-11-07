/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.rev_spec {

   // We maintain a Working revision so the user can edit the map in parallel
   // with other users. It starts out with the same theoretical rid as
   // Current(), but will trail the Branch Head revision as other users update
   // the map.

   public class Working extends Follow {

      // *** Constructor

      public function Working(rid_branch_head:int) :void
      {
         super(rid_branch_head);
      }

      // *** Public instance methods

      //
      override public function equals(rev:Base) :Boolean
      {
         var other:Working = (rev as Working);
         return ((other !== null)
                 && (super.equals(other)));
      }

      //
      override public function toString() :String
      {
         return String(this.rid_last_update);
      }

      //
      override public function get friendly_name() :String
      {
         var fname:String = this.toString();
         if (this.rid_last_update != this.rid_branch_head) {
            fname += ' (h:' + this.rid_branch_head + ')';
         }
         return (fname + ' [working]');
      }

      //
      override public function get short_name() :String
      {
         var sname:String = 'w:' + String(this.rid_last_update);
         if (this.rid_last_update != this.rid_branch_head) {
            sname += '(h:' + this.rid_branch_head + ')';
         }
         return sname;
      }

   }
}


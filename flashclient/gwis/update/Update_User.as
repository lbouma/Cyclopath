/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis.update {

   import flash.events.Event;

   import gwis.GWIS_Branch_Names_Get;
   import gwis.GWIS_Grac_Get;
   import utils.misc.Collection;
   import utils.misc.Logging;

   public class Update_User extends Update_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_User');

      public static const on_completion_event:String = 'updatedUser';

      // *** Constructor

      public function Update_User()
      {
         super();
      }

      // *** Init methods

      //
      override protected function init_update_steps() :void
      {
         // BUG nnnn: Here's maybe where we get a session ID??
         this.update_steps.push(this.update_step_group_membership);
         this.update_steps.push(this.update_step_branches);
      }

      // *** Internal interface, Update Steps

      //
      protected function update_step_group_membership() :void
      {
         m4_DEBUG('update_step_group_membership');
         var reqs:Array;
         var req:GWIS_Grac_Get;

         m4_ASSERT(Collection.dict_is_empty(G.grac.group_memberships));

         // If this is a Diff, we might send multiple requests; else, just one
         // EXPLAIN: We dropped group_memberships already, right?
         reqs = this.gwis_revs_get_grac('group_membership', 'user', G.grac);
         for each (req in reqs) {
            this.requests_add_request(req, this.on_process_user);
         }
      }

      //
      protected function update_step_branches() :void
      {
         m4_DEBUG('update_step_branches');
         var req:GWIS_Branch_Names_Get = new GWIS_Branch_Names_Get(this);
         this.requests_add_request(req, null); // this.on_process_branches);
      }

      // *** Internal interface, Helpers

      //
      protected function on_process_user() :void
      {
         m4_DEBUG('on_process_user');
         m4_ASSERT(G.user.private_group_id != 0);
         m4_ASSERT(!Collection.dict_is_empty(G.grac.group_memberships));

         m4_DEBUG('on_process_user: dispatchEvent: grac_gms_event');
         G.item_mgr.dispatchEvent(new Event('grac_gms_event'));

         this.map.update_branch();
      }

   }
}


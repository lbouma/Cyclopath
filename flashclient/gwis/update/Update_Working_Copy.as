/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: This class is not implemented. It's meant to run when the server says
//        a new revision is saved. We could update lots of things: the list of
//        tags, all items in the viewport, the list of attributes, the draw
//        config, the new_item_policy, etc., even check for branch conflicts.
//        Ug.

      // FIXME If we're updating the working revision of the map (see
      //       Update_Working_Copy), we should re-request the draw config,
      //       tag names, nips, and regions... and even re-check the dirtyset
      //       against the new_item_policy... or maybe we decide that you have
      //       to enter maintenance mode (take the site offline) to change the
      //       nips, so we can avoid having to deal with such a special case.

package gwis.update {

   import utils.misc.Logging;

   public class Update_Working_Copy extends Update_Supplemental {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_WorkCopy');

      public static const on_completion_event:String = 'updatedWorking';

      // *** Constructor

      public function Update_Working_Copy()
      {
         super();
      }

      // *** Init methods

      //
      override protected function init_update_steps() :void
      {
         // This fcn. is called after the user successfully saves items to the
         // database. We're suppose to, um, I can't remember. I think just ask
         // for any items that have changed since what revision we were on....
         // FIXME: Implement
         //
         // m4_ASSERT(false); // Not implemented
      }

// this.update_steps.push(this.update_step_new_item_policy);

// FIXME This whole class and all its fcns


// FIXME Mult. of these might be sent; mult. any GWIS_Base might be sent
//       Make Update_Base-type object for this and make cancelable
//       Is there some generic fcn. that can do this? You would have to
//       supply callbacks of some snorts, I guess, so maybe not totally
//       worth it?
// FIXME Fix this usage -- make cancelable like update, also, don't force
//       callees to use callLater?
// FIXME This whole fcn is whack

/*
      //
      public function update_attachments(rid_old:int,
                                                    rid_new:int) :void
      {
         this.debug_t0 = G.now();
         var rev:utils.rev_spec.Base = null;
         m4_DEBUG_CLLL('>callLater: update_attachments fired');
         m4_DEBUG2('update_attachments:',
                   '/ rid_old:', rid_old, '/ rid_new:', rid_new);
         m4_ASSERT(G.initialized);
         if (rid_old > 0 && rid_new > 0) {
            // Fetch attachments added since rid_old
            m4_ASSERT(rid_old != rid_new);
            m4_DEBUG('Fetching attachments between', rid_old, 'and', rid_new);
            rev = new utils.rev_spec.Diff(rid_old, rid_new)
                                       .clone(utils.rev_spec.Diff.NEW);
         }
      }
*/

/*
      //
public function update_working_copy() :void
      {
         m4_ASSERT(G.map.rev_workcopy.rid_branch_head
                   > G.map.rev_workcopy.rid_last_update);

G.tabs.changes_panel.refresh();
also get new discussions?
GWIS_GetConflicts(G.rid_working_copy, G.rid_branch_head, dirty_stack_ids);

// update_working_copy: on response, it items conflict, rather than ignoring,
// bump the dirty item's version and keep both items (so branch conflict is two
// items, two different versions), that is, if we even store the version number
this should refresh all lazy-load panels...

on response:
G.rid_working_copy_update = -1;

FIXME how does updating from the branch head and checking for conflicts related
to merging? When updating, the client ask for conflicts. When merging, the
server produces and stores conflicts. (So, an update stores the conflicts in
the client, and a merge stores the conflicts in the server.)
      }
*/

   }
}


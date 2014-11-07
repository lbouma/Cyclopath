/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.containers.TitleWindow;
   import mx.controls.Alert;
   import mx.managers.PopUpManager;

   import grax.Dirty_Reason;
   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Grac_Record;
   import items.Item_Revisioned;
   import items.Item_User_Access;
   import items.Link_Value;
   import items.feats.Byway;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.base.UI;
   import views.commands.Command_Manager;
   import views.map_components.Please_Wait_Popup;

   public class GWIS_Commit extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Commit');

      // *** Instance variables

      // Users of this class specific a callback fcn., but we also specify one:
      // so we can consume the client ID to permanent ID map that the server
      // returns on success.
      protected var callers_callback_okay:Function;
      protected var callers_callback_fail:Function;
      // MAYBE: This is redeundant because of GWIS_Base.caller_data now.
      protected var callers_payload:*;

      // The mapping of client IDs to stack IDs, populated on request success.
      public var client_id_map:Dictionary;

      // When silent is true, the 'Please Wait' dialogue is hidden
      public var silent:Boolean;

      public var changed_items:Set_UUID;

      public var for_dirty:int = 0;

      protected var new_rid_max:int = 0;

      protected var command_mgr:Command_Manager = null;

      // *** Constructor

      public function GWIS_Commit(
         changed_items:Set_UUID,
         changenote:String,
         silent:Boolean=true,
         callback_load:Function=null,
         callback_fail:Function=null,
         callback_payload:*=null,
         anon_coward:Boolean=false,
         restrict_dirty:*=null,
         alert_on_activity:Boolean=false,
         command_mgr:Command_Manager=null) :void
      {
         var item:Item_User_Access;
         var prepared:Boolean = true;

         // The GML document and its sections
         var doc:XML = this.doc_empty();
         var sub_doc:XML; // for temporary usage.

         // SYNC_ME: Search: Commit XMLs.
         var   ratings:XML = <ratings/>;   // byway_rating & byway_rating_event
         var  watchers:XML = <watchers/>;  // item_watcher
         var    items_:XML = <items/>;     // item_versioned classes
         var  accesses:XML = <accesses/>;  // group_item_access data
         var  schanges:XML = <schanges/>;  // style_changes
         var reminders:XML = <reminders/>; // ask_me_laters

         // Check that the user isn't banned
         m4_ASSERT(!G.user.is_full_banned);
         // NOTE: If G.user.is_banned, can only save ratings and watchers

         // On further thought, half-banning just seems silly. Who would use
         // the site if they could only save ratings or watch regions?
         // (V1 allows banned users to save private watch regions when the
         // system or user is under a ban. V2 does not allow any saving. User
         // should be notified (or not allowed to edit, period) if the system
         // or user is in a state of ban.)
         m4_ASSERT(!G.user.is_banned);

         // When saving the dirtyset, even if the user is logged in, they
         // sometimes have the option to save the items anonymously. Note that
         // saving anonymously is all or nothing, i.e., you can't select which
         // items to save anonymous (well, we could code that, but commit.py
         // would have to save two revisions, which seems tedious).
         if (anon_coward) {
            doc.@anon_coward = int(true);
         }

         if (alert_on_activity) {
            doc.@alert_on_activity = int(true)
         }

         this.command_mgr = command_mgr;

         if (restrict_dirty === null) {
            // Make sure we only send watchers on their own, i.e., not with
            // revisiony map saves, otherwise the server might scold us.
            //restrict_dirty =
            //   Dirty_Reason.all_reasons & ~Dirty_Reason.item_watcher;
            // 2013.10.05: On second thought, new geofeatures (including
            // new split-into byways) should be deferred until now to be
            // saved, otherwise we'd have to disable ratings and watcher
            // controls for new items.
            // FIXME: Re-enable item watching for new items (it's currently
            //        off, but item ratings work, so make watchers, too).
            restrict_dirty = Dirty_Reason.all_reasons;
         }

         // Check that the user is commiting a current working copy, and not an
         // historic checkout. This means the user has to update their working
         // copy if the branch head gets updated by another user. Also make
         // sure this fcn. isn't called if there are conflicts to resolve.
         m4_ASSERT(G.map.rev_workcopy !== null);
         m4_ASSERT(G.map.rev_workcopy.rid_last_update > 0);
         m4_ASSERT(G.map.rev_workcopy.rid_branch_head
                   >= G.map.rev_workcopy.rid_last_update);
         m4_ASSERT(G.item_mgr.active_branch !== null);
         // FIXME: This is firing: apparently you need a dialog or something to
         //        popup to warn the user...
         m4_ASSERT(G.item_mgr.active_branch.conflicts_resolved);
         m4_ASSERT(G.map.rev_workcopy.rid_branch_head
                   == G.map.rev_workcopy.rid_last_update);

         // The remote resource
         var url:String = (
            this.url_base('commit')
            + '&rev=' + G.map.rev_workcopy.toString()
            );

         // Revision and Branch ID.
         //doc.metadata.appendChild(
         //    <revision
         //       rev_id={G.map.rev_workcopy.toString()}
         //       branch_id={G.item_mgr.active_branch.stack_id}
         //       />);
         // NOTE: If another user saves at the same time, and if the server
         //       cannot figure out any conflicts, the save fails, the
         //       client is populated with the conflicts list, and the user
         //       is asked to resolve conflicts and save again.

         // Metadata: Add the changenote
         doc.metadata.appendChild(<changenote>{changenote}</changenote>);

         // MAGIC_NUMBER 16 converts to hex.
         m4_DEBUG2('GWIS_Commit: found no. changed:', changed_items.length,
                   '/ dirty: 0x' + int(restrict_dirty).toString(16));

         // Pre-process items: part 1.
         for each (item in changed_items) {
            // Hack to clean up fresh attachments that had their links
            // deleted. This only applies to attachments that need to be
            // linked to a feature, otherwise they get lost in the system
            // (so just Annotations and Tags, and not Attributes, Posts,
            // or Threads). Note: this only applies to fresh attachments:
            // the client cannot detect existing attachments that are
            // orphaned, since not all geofeatures and links are
            // necessarily in memory.
            if (item.fresh) {
               if (item.is_link_parasite) {
                  // The item an Annotation or Tag. Don't send it if all it's
                  // links are deleted.
                  var lvals:Set_UUID;
                  lvals = Link_Value.item_get_link_values(item.stack_id);
                  // lvals is null if the link_val was deleted from everything.
                  if ((lvals === null) || (lvals.length == 0)) {
                     m4_DEBUG('GWIS_Commit: no lvals for new item:', item);
                     item.deleted = true;
                     item.dirty_set(Dirty_Reason.item_data, false);
                     item.dirty_set(Dirty_Reason.item_data_oob, false);
                     item.dirty_set(Dirty_Reason.item_revisionless, false);
                  }
               }
            }
         }
         // Pre-process items: part 2.
         for each (item in changed_items) {
            if (item.fresh) {
               var lval:Link_Value = item as Link_Value;
               if ((lval !== null)
                   && (   ((lval.attc !== null)
                           && (lval.attc.fresh)
                           && (lval.attc.deleted))
                       || ((lval.item !== null)
                           && (lval.item.fresh)
                           && (lval.item.deleted)))) {
                  item.deleted = true;
                  item.dirty_set(Dirty_Reason.item_data, false);
                  item.dirty_set(Dirty_Reason.item_data_oob, false);
                  item.dirty_set(Dirty_Reason.item_revisionless, false);
                  m4_DEBUG('GWIS_Commit: abandoned link_value:', item);
               }
            }
         }

         // Loop through the dirty items and make the GML
         for each (item in changed_items) {

            // MAGIC_NUMBER 16 converts to hex.
            m4_DEBUG3('GWIS_Commit: dirty: 0x'
                      + item.get_dirty_reason().toString(16),
                      '/ item:', item);

            // Can't save diffed items.
            m4_ASSERT(item.is_vgroup_none);
            m4_ASSERT2(
               ((item.stack_id < 0)
                || ((item.stack_id > 0)
                    && ((item.stack_id & Item_Revisioned.MASK_ID_TAGS)
                        == 0))));

            // Every item being committed should be editable. Right?
            m4_ASSERT(item.can_edit);

            // Items that are deleted but also fresh (only in the working copy)
            // aren't sent to the server (because, from the branch head's
            // perspective, they don't exist).  Note that we're checking
            // deleted and fresh again since deleted may have just changed.
            if ((!(item.fresh && item.deleted)) && (!item.invalid)) {

               //m4_DEBUG('GWIS_Commit: so far so good');

               // Check every dirty item for item_watcher and item_read_event
               // dirtiness. Attcs and Feats are watch/readable; Links, Tiles
               // and GRACs are not.

               // Ratings. Ratings on byways which are deleted but also fresh
               // aren't sent to the server (because from the user perspective,
               // they don't exist).
               var bway:Byway = (item as Byway);
               if ((bway !== null) // null if not a Byway
                   && (restrict_dirty & Dirty_Reason.item_rating)
                   && (bway.dirty_get(Dirty_Reason.item_rating))) {
                  m4_TALKY('GWIS_Commit: rated: bway:', bway);
                  ratings.appendChild(bway.gml_get_item_rating());
                  this.for_dirty |= Dirty_Reason.item_rating;
               }
               // BUG nnnn: Ratings on any/all objects. Could just move
               // bway.user_rating to Item_Versioned but maybe ratings
               // are different concept based on geofeature type (like, a
               // waypoint cannot be rated 'impassable')?

               // Watchers. This is a tad hacky since Link_Value derives from
               // Item_User_Access and not Item_Watcher_Shim like Attachment
               // and Geofeature.

               if ((restrict_dirty & Dirty_Reason.item_watcher)
                   && (item.dirty_get(Dirty_Reason.item_watcher))) {
                  // We're kind of cheating and doing a non-revision commit.
                  // So we want to make sure this is just the private
                  // link_attr that is the item watcher.
                  m4_ASSERT(item is Link_Value);
                  watchers.appendChild(item.gml_produce());
                  this.for_dirty |= Dirty_Reason.item_watcher;
               }

               // Item Read Events.
               if ((restrict_dirty & Dirty_Reason.item_read_evt)
                   && (item.dirty_get(Dirty_Reason.item_read_evt))) {


// BUG_FALL_2013: See also FIXME_2013_06_11.
// FIXME_2013_06_11: Fix item read events.
// FIXME: Implement me

                  this.for_dirty |= Dirty_Reason.item_read_evt;
               }

               // Save Wiki items.
               var commit_item_data:Boolean = false;
               if ((restrict_dirty & Dirty_Reason.item_data)
                   && (item.dirty_get(Dirty_Reason.item_data))) {
                  this.for_dirty |= Dirty_Reason.item_data;
                  commit_item_data = true;
               }
               // Save threads and posts and their link_values and
               // other things that are Wiki items but that don't
               // need a changenote.
               if ((restrict_dirty & Dirty_Reason.item_data_oob)
                   && (item.dirty_get(Dirty_Reason.item_data_oob))) {
                  this.for_dirty |= Dirty_Reason.item_data_oob;
                  commit_item_data = true;
               }
               if ((restrict_dirty & Dirty_Reason.item_revisionless)
                   && (item.dirty_get(Dirty_Reason.item_revisionless))) {
                  this.for_dirty |= Dirty_Reason.item_revisionless;
                  commit_item_data = true;
               }
               if (commit_item_data) {
                  m4_DEBUG('GWIS_Commit: committing:', item);
                  items_.appendChild(item.gml_produce());
               }

               // MAYBE: flashclient sends both gia records and style changes,
               //        when it could just send style changes. On the plus
               //        side, pyserver audits our gia records, so we at least
               //        know what our working copy is thinking.

               // Style_Changes.
               // NOTE: We could send the style change inline with items,
               //       e.g., for new items, you'll see <items> xml as
               //       well as <schanges> xml, but for items not being edited,
               //       like when editing route permissions, we won't send
               //       <items>.
               var commit_item_schg:Boolean = false;
               if ((restrict_dirty & Dirty_Reason.item_schg)
                   && (item.dirty_get(Dirty_Reason.item_schg))) {
                  this.for_dirty |= Dirty_Reason.item_schg;
                  commit_item_schg = true;
               }
               if ((restrict_dirty & Dirty_Reason.item_schg_oob)
                   && (item.dirty_get(Dirty_Reason.item_schg_oob))) {
                  this.for_dirty |= Dirty_Reason.item_schg_oob;
                  commit_item_schg = true;
               }
               if (commit_item_schg) {
                  // 2013.07.18: SLOPPY: How we can be sending schange for a
                  //             freshie? Make a byway, delete it, make another
                  //             byway, then save. WireShark shows schange but
                  //             not item for the deleted byway.
                  // FIXED: The freshie was not being removed from dirtyset.
                  //m4_DEBUG('GWIS_Commit: gml_get_style_change: item:', item);
                  sub_doc = item.gml_get_style_change();
                  if (sub_doc !== null) {
                     schanges.appendChild(sub_doc);
                  }
                  else {
                     prepared = false;
                  }
                  //m4_DEBUG('GWIS_Commit: schanges.length:', schanges.length);
               }

               var commit_item_grac:Boolean = false;
               if ((restrict_dirty & Dirty_Reason.item_grac)
                   && (item.dirty_get(Dirty_Reason.item_grac))) {
                  // Group Access Control.
                  // This traverses an item's dirtyset_gia.
                  this.for_dirty |= Dirty_Reason.item_grac;
                  commit_item_grac = true;
               }
               if ((restrict_dirty & Dirty_Reason.item_grac_oob)
                   && (item.dirty_get(Dirty_Reason.item_grac_oob))) {
                  this.for_dirty |= Dirty_Reason.item_grac_oob;
                  commit_item_grac = true;
               }
               if (commit_item_grac) {
                  accesses.appendChild(item.gml_get_grac());
               }

               // Save item reminders.
               // BUG nnnn: Reimplement item_reminder for CcpV2.
               // FIXME: This is not tested in CcpV2 because it's used by the
               //        Ask_Me_Later_Popup which is used for route reactions.
               if ((restrict_dirty & Dirty_Reason.item_reminder)
                   && (item.dirty_get(Dirty_Reason.item_reminder))) {
                  // See item_watcher, which is similarly implemented: as link.
                  m4_ASSERT(item is Link_Value);
                  reminders.appendChild(item.gml_produce());
                  this.for_dirty |= Dirty_Reason.item_reminder;
               }

            } // if ((!(item.fresh && item.deleted)) && (!item.invalid))

         } // for each (item in changed_items)

         // SYNC_ME: Search: Commit XMLs.
         var sub_docs:Array = [ratings, watchers, items_, schanges, accesses,];
         for each (sub_doc in sub_docs) {
            if (sub_doc.children().length() > 0) {
               doc.appendChild(sub_doc);
            }
         }

         this.silent = silent;

         // Hold onto the list of items we're committing, so callers don't
         // have to.
         this.changed_items = changed_items;

         m4_ASSERT(callback_load !== null); // required
         this.callers_callback_okay = callback_load;
         this.callers_callback_fail = callback_fail;
         var our_callback_load:Function = basic_commit_load;
         var our_callback_fail:Function = basic_commit_fail;

         this.callers_payload = callback_payload;

         var throb:Boolean = true;
         var qfs:Query_Filters = null;
         var update_req:Update_Base = null;
         super(url, doc, throb, qfs, update_req,
               our_callback_load, our_callback_fail);

         this.popup_enabled = true;

         if (!prepared) {
            this.pre_canceled = true;
         }

         // BUG 2716: Don't refresh the map after save. Load just the IDs
         //           pyserver sends back. Or do a revision update. Or do
         //           neither, but change the saved items' client IDs into
         //           the specific stack IDs and make the user do an explicit
         //           revision Update.
         //           See: client_id_map.

      }

      // ***

      //
      override protected function error_present(text:String) :void
      {
         // FIXME: This only applies to revisioned items. For
         //        non-wiki/background saves, doesn't make sense to annouce the
         //        failure.
         Alert.show(text, 'Save failed');

// FIXME: here's where you want to populate the conflicts panel.
// BUG nnnn: Impl. conflicts panel. (and finish wiki page of remaining tasks)

      }

      //
      override public function fetch() :void
      {
         // Make the Popup. NOTE: Please_Wait_Popup's for PutItem should
         // *not* have a Cancel button, because that introduces a race
         // condition. If you cancel a PutItem, from the client, you can't
         // tell if it was canceled before the server completed the save or
         // after, so you can't tell if you need to refresh the map or not.
         if (!this.silent) {
            var popup_window:Please_Wait_Popup = new Please_Wait_Popup();
            UI.popup(popup_window);
            popup_window.init('Saving', 'Please wait.', this, false);
            this.gwis_active_alert = popup_window;
         }
         super.fetch();
      }

      //
      override public function is_trumped_by(update_class:Class) :Boolean
      {
         // FIXME: Not sure how the client handles this, but if user saves and
         //        then tries to log out quickly, we obviously want to wait on
         //        the commit and not cancel it. The request should be denied
         //        (user gets a dialog) or queued and processed after the
         //        commit response. Maybe in resultset_process: if success,
         //        kick the queued update, otherwise don't (i.e., don't log out
         //        if the save failed, tell the user instead and wait for
         //        further instructions).
         // FIXME: What isn't m4_WARNING logged? The devs should know.
         m4_ERROR('is_trumped_by: called during commit?')
         var is_trumped:Boolean = false;
         return is_trumped;
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         m4_DEBUG('items_save_send_resp: itemsCommitted');
         G.app.dispatchEvent(new Event('itemsCommitted'));
      }

      // ***

      // This is always called on commit success, whether or not the caller
      // specified a callback.
      protected function basic_commit_load(gwis_req:GWIS_Commit, rset:XML)
         :void
      {
         // <data 
         //    major="not_a_working_copy"
         //    gwis_version="3"
         //    semiprotect="0"
         //    rid_max="20159">
         //   <result>
         //     <id_map cli_id="-4" new_id="2643933"/>
         //     <id_map cli_id="-3" new_id="2643932"/>
         //   </result>
         // </data>

         m4_ASSURT(gwis_req === this);

         this.client_id_map = new Dictionary();

         m4_DEBUG('basic_commit_load: rset:', rset.toXMLString());

         m4_DEBUG2('basic_commit_load: rset.@rid_max:', rset.@rid_max,
                   '/ rid_branch_head:', G.map.rev_workcopy.rid_branch_head);
         this.new_rid_max = rset.@rid_max;

         var current_rev:utils.rev_spec.Base
            = new utils.rev_spec.Current();

         for each (var id_map:XML in rset..id_map) {

            m4_VERBOSE2('basic_commit_load: id_map:',
                        id_map.toXMLString());

            var cli_id:int = id_map.@cli_id;
            m4_ASSERT_SOFT(cli_id != 0);

            var new_id:int = id_map.@new_id;
            m4_ASSERT_SOFT(new_id > 0);

            var new_vers:int = id_map.@new_vers;
            m4_ASSERT_SOFT(new_vers > 0);

            var new_ssid:int = id_map.@new_ssid;
            m4_ASSERT_SOFT(new_ssid > 0);

            // These are just for byways. This is a little coupled but the
            // response doesn't indicate item_type, so deal with it.
            var beg_nid:int = id_map.@beg_nid;
            var fin_nid:int = id_map.@fin_nid;

            // 2013.12.20: Pyserver now returns the access_infer_id and
            // groups_access records, so that flashclient can be sure it's
            // using canon.
            m4_DEBUG('basic_commit_load: id_map.@acif:', id_map.@acif);
            var acif_id:int = -1;
            var new_gias:Array = null;
            if (id_map.@acif) {
               acif_id = id_map.@acif;
               new_gias = new Array();
               GWIS_Grac_Get.grac_resultset_process(
                  id_map, new_gias, current_rev);
            }
            m4_DEBUG('basic_commit_load: id_map.@alid:', id_map.@alid);
            var acl_id:int = -1;
            if (id_map.@alid) {
               acl_id = id_map.@alid;
            }

            // Make a specialized object to hold these vars.
            this.client_id_map[cli_id] = {
               cli_id: cli_id,
               new_id: new_id,
               new_vers: new_vers,
               new_ssid: new_ssid,
               beg_nid: beg_nid,
               fin_nid: fin_nid,
               acif_id: acif_id,
               new_gias: new_gias,
               acl_id: acl_id
               };
         } // end: for each (var id_map:XML in rset..id_map)

         m4_DEBUG2('basic_commit_load: client_id_map: cnt:',
                   this.client_id_map.length);
         for each (var climap_obj:Object in this.client_id_map) {
            GWIS_Commit.dump_climap(climap_obj);
         }

         // Pass the client ID map to the item mgr so it can update the
         // static class item lists, like Geofeature.all.
         //
         // This is a little different than Checkout, which does a convulated
         // dance: if the Checkout caller attached an Update_Base object, it
         // schedules a callback to process the results, so that the network
         // request can be completed (this is an old trick -- the network
         // request should only live as long as necessary to get the data,
         // and the network request should be completed before the data is
         // processed, so that you're not hogging network resources, or, in the
         // case of Flex, so you're not hogging the thread, since Update_Base
         // preempts itself if it runs for long, so that flashclient doesn't
         // appear unresponsive when processing lots of data; long sentence).
         //
         // Here, we just call the Item Mgr to handle the success of the
         // commit. It'll change client IDs to permanent IDs, unmark
         // Dirty_Reason, and update GIA records per style_change. Note that
         // we're not doing any view-related stuff here, like re-enabling the
         // save button, which is the responsibility of the caller's callback
         // fcn. (And, 2012.11.03: this solves the problem of re-loading the
         // entire map after a map edit! Hooray!! Quick Saver.)
         G.item_mgr.update_items_committed(this.client_id_map,
                                           this.command_mgr,
                                           gwis_req);

         // Now we're ready to call the caller's callback.
         this.callers_callback_okay(gwis_req, rset, this.callers_payload);

         //m4_ASSERT(this.new_rid_max > G.map.rev_workcopy.rid_branch_head);
         // Not all commits cause a new revision to be created, e.g., item
         // watchers.
         m4_ASSERT(this.new_rid_max >= G.map.rev_workcopy.rid_branch_head);

         m4_DEBUG('basic_commit_load: new_rid_max:', this.new_rid_max);
         m4_DEBUG2('basic_commit_load: G.map.rev_workcopy.rid_branch_head:',
                   G.map.rev_workcopy.rid_branch_head);

         if (this.new_rid_max == G.map.rev_workcopy.rid_branch_head) {
            m4_DEBUG('basic_commit_load: rev_workcopy unchanged');
         }
         else if (this.new_rid_max
                  == (G.map.rev_workcopy.rid_branch_head + 1)) {
            // What was just committed is all that's changed on the server,
            // so rather than reload the map, we'll cross our fingers and
            // hope that our working copy is good enough.
            m4_DEBUG('basic_commit_load: bumping rev_workcopy');
            G.map.rev_workcopy = new utils.rev_spec.Working(this.new_rid_max);
         }
         else {
            // Someone else saved a revision (and nothing conflicted during
            // commit), so we're missing items from intermediate revision(s).
            // Since flashclient doesn't handle 'update' like the route finder
            // or tilecache cache, we have to discard the map and start over.
            m4_DEBUG('basic_commit_load: discard_and_update');
            G.map.rev_loadnext = new utils.rev_spec.Current();
            G.map.discard_and_update();
         }
      }

      //
      protected function basic_commit_fail(gwis_req:GWIS_Commit, rset:XML)
         :void
      {
         if (this.callers_callback_fail !== null) {
            this.callers_callback_fail(gwis_req, rset, this.callers_payload);
         }
      }

      //
      public function success_acknowledged(button_clicked:uint) :void
      {
         // [lb] wired this fcn. for helping with G.map.rev_workcopy, but
         // we can reload the map while the alert is being shown, so there's
         // not really a need for this callback. But it's kind of nice to
         // finally know when the user dismisses the "save successful" dialog.

         m4_DEBUG2('success_acknowledged: button_clicked:', button_clicked,
                   '/ new_rid_max:', this.new_rid_max);

         this.new_rid_max = 0;
      }

      // ***

      //
      public static function dump_climap(climap_obj:Object) :void
      {
         if (climap_obj !== null) {
            m4_DEBUG9('dump_climap: climap_obj: cli_id:', climap_obj.cli_id,
                      '/ new_id:', climap_obj.new_id,
                      '/ new_vers:', climap_obj.new_vers,
                      '/ new_ssid:', climap_obj.new_ssid,
                      '/ beg_nid:', climap_obj.beg_nid,
                      '/ fin_nid:', climap_obj.fin_nid,
                      '/ acif_id:', climap_obj.acif_id,
                      '/ new_gias:', climap_obj.new_gias,
                      '/ acl_id:', climap_obj.acl_id);
         }
         else {
            m4_DEBUG('dump_climap: climap_obj: null');
         }
      }

   }
}


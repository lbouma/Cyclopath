/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import flash.events.Event;
   import flash.utils.getDefinitionByName;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Item_Base;
   import items.Item_Versioned;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class GWIS_Checkout_Base extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~Chkout_Base');

      // *** Instance attributes

      protected var item_type_:String = '';
      protected var attc_type_:String = '';
      protected var feat_type_:String = '';
      protected var lhs_stack_id_:int = 0;
      protected var rhs_stack_id_:int = 0;

      protected var rev:utils.rev_spec.Base;

      // FIXME: snr (search 'n' replace): viewport_include
      //protected var include_rect:Dual_Rect;
      //protected var exclude_rect:Dual_Rect;

      // When we receive XML, when hydrate the item objects. The objects may be
      // processed immediately, when the XML is received, or they might be
      // processed when the network layer signals completion, or they might be
      // passed to the callback, if one is set.
      //
      // CAVEAT: a/k/a DEVS PAY ATTENTION: This one is dangerous. resp_items is
      //         a collection of newly created items made when the response is
      //         received. But there might already be the same items in the
      //         system. Usually, you'll call G.map.items_add to update the
      //         resident item, and then you'll lookup the resident item and
      //         ignore the item in resp_items.
      public var resp_items:Array;
      //
      // Not all of the item XML is necessarily consumed by the item, so
      // remember the original XML for the callbacks.
      public var rset_deets:Array;

      // *** Constructor

      // Constructor
      public function GWIS_Checkout_Base(
         item_type:String,
         resp_items:Array=null,
         rev:utils.rev_spec.Base=null,
         query_filters:Query_Filters=null,
         update_req:Update_Base=null,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         var url:String = this.url_base('checkout');
         var doc:XML = this.doc_empty();

         this.item_type_ = item_type;

         if (resp_items === null) {
            resp_items = new Array();
         }
         this.resp_items = resp_items;

         // This might always be the same as G.map.rev, but we still make the
         // caller specify it.
         this.rev = rev;

         var throb:Boolean = true;
         super(url, doc, throb, query_filters, update_req,
               callback_load, callback_fail);
      }

      // *** Link Value-related Getters and setters

      // FIXME: Verify this is implemented in pyserver (it used to not
      //        be, so link_value queries would take longer and return
      //        rows for all attc and feat types).
      // FIXME: These seem awkward here... why's it not in query_filters?

      //
      public function get attc_type() :String
      {
         return this.attc_type_;
      }

      //
      public function set attc_type(attc_type:String) :void
      {
         this.attc_type_ = attc_type;
      }

      //
      public function get feat_type() :String
      {
         return this.feat_type_;
      }

      //
      public function set feat_type(feat_type:String) :void
      {
         this.feat_type_ = feat_type;
      }

      //
      public function get lhs_stack_id() :int
      {
         return this.lhs_stack_id_;
      }

      //
      public function set lhs_stack_id(lhs_stack_id:int) :void
      {
         this.lhs_stack_id_ = lhs_stack_id;
      }

      //
      public function get rhs_stack_id() :int
      {
         return this.rhs_stack_id_;
      }

      //
      public function set rhs_stack_id(rhs_stack_id:int) :void
      {
         this.rhs_stack_id_ = rhs_stack_id;
      }

      // *** Other Getters and setters

      // True since client can send more than one Checkout request as an
      // out-of-band request (e.g., for lazy loading link values).
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

      //
      override public function get cancelable() :Boolean
      {
         return true;
      }

      // ***

      //
      override public function equals(other:GWIS_Base) :Boolean
      {
         var equal:Boolean = false;
         var other_:GWIS_Checkout_Base = (other as GWIS_Checkout_Base);
         m4_ASSERT(this !== other_);
         equal = (   (super.equals(other_))
                  && (this.item_type_ == other_.item_type_)
                  && (this.attc_type_ == other_.attc_type_)
                  && (this.feat_type_ == other_.feat_type_)
                  && (this.lhs_stack_id_ == other_.lhs_stack_id_)
                  && (this.rhs_stack_id_ == other_.rhs_stack_id_)
                  && (this.rev.equals(other_.rev)));
         // Base class prints this and other_ so just print our equals.
         m4_VERBOSE('equals?:', equal);
         return equal;
      }

      // *** Instance methods

      // This fcn. enforces ordering of the URI kvps merely to make debugging
      // more pleasant.
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);
         url = '';
         if (this.item_type_ != '') {
            url += '&ityp=' + this.item_type_;
         }
         m4_ELSE_SERVED; // item_type is required.
         if (this.attc_type_ != '') {
            url += '&atyp=' + this.attc_type_;
         }
         if (this.feat_type_ != '') {
            url += '&ftyp=' + this.feat_type_;
         }
         if (this.lhs_stack_id_ != 0) {
            url += '&lhsd=' + this.lhs_stack_id_;
         }
         if (this.rhs_stack_id_ != 0) {
            url += '&rhsd=' + this.rhs_stack_id_;
         }
         if (this.rev !== null) {
            url += '&rev=' + this.rev;
         }
         m4_ASSERT(this.data !== null);
         return super.finalize(url);
      }

      // Parse the incoming Items.
      override protected function resultset_process(rset:XML) :void
      {
         // This fcn. creates a list of items and stores it at this.resp_items.
         // It's up to the callee's callback_load or the derivee's
         // result_process to process the results.

         var item_container:XML;
         var item_detail:XML;
         var item_type:String;
         var item_class:Class;
         var an_item:Item_Versioned;

         // Update max RID, which is the latest revision ID of the branch head.
         this.maxrid_process(rset);

         super.resultset_process(rset);

         m4_ASSERT(this.resp_items.length == 0);
         m4_ASSERT(this.rset_deets === null);
         this.rset_deets = new Array();

         m4_VERBOSE('resultset_process: this.item_type_:', this.item_type_);

         // Go through the item XML and hydrate objects.
         for each (item_container in rset.*) {
            // Items are grouped homogeneously in an outer container, i.e.,
            // <items ityp="byway"><byway name=...>[geometry]</byway> ...
            item_type = item_container.@ityp;
            // Note that this.item_type_, which is the item type of the
            // original request, won't necessarily match the <items> item_type,
            // e.g., the response for posts is followed by link_posts
            // containers.
            m4_VERBOSE('resultset_process: item_type:', item_type);
            // Get a handle to the item's class.
            item_class = Item_Base.item_get_class(item_type);
            m4_VERBOSE('resultset_process: item_class:', item_class);
            // Make the new items.
            //
            // NOTE We're not using callLater, so if processing a large XML
            //      file, and if the item_class constructor does a lot of
            //      processing, we face the risk of running uniterrupted too
            //      long and Flash killing the client.
            for each (item_detail in item_container.*) {
               // Make sure the item type is actually what we expect.
               m4_VERBOSE2('resultset_process: detail:',
                           item_detail.toXMLString());
               m4_VERBOSE('resultset_process: name:', item_detail.name());
               if (item_type == String(item_detail.name())) {
                  // Create a new Item and store in our temporary list.
                  // FIXME: Is this.rev guaranteed to be same as
                  //        <data rid_max ?
                  an_item = new item_class(item_detail);
                  an_item.set_revision(this.rev);
                  this.resp_items.push(an_item);
                  // To avoid item bloat, some details aren't loaded into the
                  // item. Remember the XML we just used in the same order as
                  // resp_items for the few callers that care.
                  this.rset_deets.push(item_detail);
               }
               else {
                  throw new Error('Unknown item type:', item_detail.name());
               }
            }
         }
      }

      // ***

      // This fcn. checks the branch head revision ID against the working copy
      // revision ID. If the working copy revision ID is not set, the app is
      // just starting up, so we set the working copy revision ID to the branch
      // head's revision ID and schedule a map update.
      //
      // If the working copy revision ID is set and the branch head reports a
      // more recent revision ID, we schedule a request to get those items that
      // have changes since the working copy was last updated. For the history
      // browser and discussions, we can load any new information. For items,
      // we can load items that aren't dirty in the working copy, but for dirty
      // items, we have to add them to the branch conflicts list so the user
      // can decide what to do.
      //
      // Regarding loading recent changes, we could instead bug the user
      // later if/when they try to save (asking them to please update their
      // working copy first). The user could also explicitly update from the
      // branch details panel. But in order to grab the latest Discussions, to
      // populate the Branch Conflicts automatically, and to update the history
      // browser, we choose to do it now. This is also more Web Two Point
      // Oh'ish: we should try to keep the map as current as possible without
      // requiring interaction from the user.
      //
      // NOTE Previously when the branch head revision ID changed, the code
      //      would grab the latest tags, so that the route finder could take
      //      advantage of them, and since tags were only grabbed once (on
      //      startup) and not when normally updating the map. And if the
      //      user was looking at the current state of the map, it was always
      //      the current state. There are at least two problems with this
      //      scheme: (1) If the user is editing an item that another just
      //      saved, the user's save fails (or there's a conflict and this
      //      user's changes overwrite the last user's changes without this
      //      user knowing there was a conflict); (2) If another user saves
      //      while this user is updating the map, the responses from the
      //      server might be from multiple revisions (since we send multiple
      //      requests when updating the map).
      //
// FIXME: I [lb] think this is a weird fcn. We shouldn't care about the
//        revision ID until trying to save our Working copy. Like, let's not
//        update the map until the user wants to update their working copy. Or
//        do it explicitly, AJAX-style. But don't do it passively like is
//        being done here...
      //
      protected function maxrid_process(rset:XML) :void
      {
         var maxrid_new:int = int(rset.@rid_max);
         m4_DEBUG2('maxrid_process: maxrid_new:', maxrid_new,
                   '/ this.rev:', this.rev);
         // For GWIS checkout requests, pyserver returns the cur. revision ID.
         // Other commands don't send it (so it's zero).
         // FIXME: Can we use item's trust_rid_latest? This feels inadequate.
         if (maxrid_new != 0) {
            m4_ASSERT(maxrid_new > 0);
            // See if we're changing revisions.
// FIXME: 2013.04.08: Now [lb] remembers why this should run just once: in case
//        another user saves a new revision while we're loading, we'll get
//        items from two different revisions...
            if (G.map.rev_loadnext !== null) {
               m4_ASSERT(G.map.rev_viewport === null);
               if (G.map.rev_loadnext is utils.rev_spec.Current) {
                  G.map.rev_workcopy = new utils.rev_spec.Working(maxrid_new);
                  m4_ASSERT_SOFT(this.rev is utils.rev_spec.Current);
                  m4_ASSERT(G.map.rev_viewport !== null);
                  m4_ASSERT(G.map.rev_mainline !== null);
                  m4_DEBUG2('maxrid_process: rev_viewport: new Working:',
                            G.map.rev_viewport.friendly_name);
               }
               else {
                  m4_DEBUG2('maxrid_process: rev_viewport: fr. rev_loadnext:',
                            G.map.rev_loadnext.friendly_name);
                  // Check that the maxrid_new is what we're expecting.
                  if (G.map.rev_loadnext is utils.rev_spec.Historic) {
                     m4_ASSERT(
                        (G.map.rev_loadnext as utils.rev_spec.Historic).rid_old
                        == (this.rev as utils.rev_spec.Historic).rid_old);
                  }
                  else if (G.map.rev_loadnext is utils.rev_spec.Working) {
                     m4_ASSERT(
                        (G.map.rev_loadnext as utils.rev_spec.Working)
                         .rid_last_update
                        == (this.rev as utils.rev_spec.Working)
                            .rid_last_update);
                  }
                  else {
                     m4_ASSERT(G.map.rev_loadnext is utils.rev_spec.Diff);
                     // MAYBE: Wait, what about asserting this.rev.rid_old,
                     //        rid_new, and group_ match their counterparts
                     //        in G.map.rev_loadnext?
                  }
                  G.map.rev_viewport = G.map.rev_loadnext;
               }

               this.rev = G.map.rev_viewport;

               // In CcpV1, we called on_resize to trigger a map refresh, but
               // the update object handles this today. But we still need to
               // call on_resize to position the map key lip and the invitation
               // bar. If we don't, the map key sits upper-left.
               //
               // MAYBE: It seems funny to always call on_resize (for every
               //        GWIS_Checkout_* request). But it doesn't hurt, unless
               //        it's costly -- though it doesn't seem like on_resize
               //        is an expensive fcn. to call.
               m4_DEBUG_CLLL('>callLater: map.on_resize [maxrid_process]');
               G.map.callLater(G.map.on_resize, [null]);
            }
            // See if the branch head revision ID has changed.
            else if ((G.map.rev_workcopy !== null)
                     && (G.map.rev_workcopy.rid_branch_head != maxrid_new)) {
               // Either we're loading for the first time and this is the first
               // time we're learning rid_max, or a new revision of the map has
               // been saved and we have to update our working copy.
               // FIXME: What happens with new items that were just saved? We
               //        discard them locally and load them from the server,
               //        right? (So not to worry about client (negative) IDs.)
               // FIXME: As the branch head advances, items that don't change
               //        will have rev = working of an old working revision. Is
               //        this okay? I think so... it's up to the server to tell
               //        us about conflicts, so I think trailing revs are okay.
               m4_DEBUG('New branch head revision: maxrid_new:', maxrid_new);
               m4_DEBUG2('G.map.rev_workcopy:',
                         G.map.rev_workcopy.friendly_name);
               m4_ASSERT(maxrid_new > G.map.rev_workcopy.rid_branch_head);
               m4_ASSERT(maxrid_new >= G.map.rev_mainline.rid_branch_head);
               if (maxrid_new > G.map.rev_mainline.rid_branch_head) {

                  /* BUGBUG_2014_JUNE:

                  1. If user editing map and another user saves the map:
                     a. alert user that the map was saved.
                        i. offer them a way to update items?
                     b. alert user if items they are editing were
                        themselves edited and saved by another user.
                  - We could maybe use the Pyserver_Message area to alert
                    the user.
                  - Should we request a list of edited item stack IDs from
                    the server? Or should we send a list of all IDs we have
                    loaded/edited and the server can just send back those
                    that have new versions?

                  */
                  // FIXME/BUG nnnn: Implement updating working copy to latest.
                  m4_WARNING('FIXME: New server rev was created:', maxrid_new);
                  m4_DEBUG2('maxrid_process_working: rev_mainline: Changed:',
                        G.map.rev_workcopy.rid_last_update, ':', maxrid_new);
                  G.map.rev_mainline = new utils.rev_spec.Changed(
                     G.map.rev_workcopy.rid_last_update, maxrid_new);

                  // BUGBUG_2014_JUNE/FIXME: This is not finished being testeded.
                  //                         Hence the debug_goodies check, so we
                  //                         can check in this code and keep our
                  //                         working diffs clean.
                  if (Conf_Instance.debug_goodies) {
                     // Show rev number, username, edit date, and hyperlink to
                     // Recent Changes.
                     var msg:String = 'Someone saved changes to the map.';
                     m4_DEBUG('maxrid_process: pyserver_message_text:', msg);
                     G.app.maintenance_msg_fake.pyserver_message_text
                        .htmlText = msg;
                     G.app.maintenance_msg_real.pyserver_message_text
                        .htmlText = msg;
                     if (G.app.mode === G.edit_mode) {
                        G.app.maintenance_msg_fake.component_fade_into(
                           /*is_later=*/false, /*force_show_message=*/false);
                     }
                  }

               }
               else {
                  m4_ASSERT(G.map.rev_mainline.rid_branch_head == maxrid_new);
                  m4_DEBUG2('maxrid_process_working: ignoring maxrid_new:',
                            maxrid_new);
               }
            }
            else {
               // else, rev_workcopy is null,
               //       meaning rev_viewport is Historic or Diff,
               //       or rid_branch_head == maxrid_new, so nothing changed.
               m4_DEBUG('maxrid_process: ignoring:', maxrid_new);
            }
         }
      }

      // ***

      //
      override public function toString() :String
      {
         var verbose:String;
         // Start with
         //   'gwis' + this.id + ':' + Introspect.get_constructor(this)
         // and the branch id.
         verbose = super.toString() + ' / b' + this.branch_id;
         if (this.item_type_) {
            verbose += ' / ' + this.item_type_;
         }
         if (this.attc_type_) {
            verbose += ' / at: ' + this.attc_type_;
         }
         if (this.feat_type_) {
            verbose += ' / ft: ' + this.feat_type_;
         }
         if (this.lhs_stack_id_) {
            verbose += ' / lhs: ' + this.lhs_stack_id_;
         }
         if (this.rhs_stack_id_) {
            verbose += ' / rhs: ' + this.rhs_stack_id_;
         }
         if (this.rev) {
            verbose += ' / r' + this.rev;
         }
         var qfs:String = this.query_filters.toString();
         if (qfs) {
            verbose += ' / qfs: ' + qfs;
         }
         return verbose;
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import flash.utils.Dictionary;

   import gwis.update.Update_Base;
   import gwis.update.Update_Branch;
   import gwis.update.Update_Out_Of_Band;
   import gwis.update.Update_Revision;
   import gwis.update.Update_Supplemental;
   import gwis.update.Update_User;
   import gwis.update.Update_Viewport_Items;
   import utils.misc.Collection;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.base.Map_Canvas;
   import views.base.Map_Canvas_Update;

   // This class handles interaction with Update_Base.
   
   // There are a handful of actions that cause interaction with the server.
   // Each action triggers one or more GWIS_Base requests. Some actions must be
   // handled consecutively, while other actions may be handled asynchronously.
   // 
   // Every action happens within some context. For example, if the user
   // just logged in or logged out, everything must be reloaded (expect
   // dirty items, if the user is logging in -- but even those dirtied items
   // access_level_ids need to be reloaded). But if the user is just panning
   // the map (or zooming in or out), than the context is just that the
   // viewport has changed.
   // 
   // The short list of contexts (and some examples): 
   //
   //  * User change          (user logs in; user logs out)
   //  * Branch change        (user changes branches; user creates new branch)
   //  * Revision change      (user saves items; user changes rev via histbrow)
   //  * Viewport change      (user pans map; user edits control panel prefs)
   //  * Working Copy change  (some other user saves to the branch head)
   //  * Nothing change       (user loads discussions, histbrow, OOB^ stuff)
   //
   // ^ OOB = Out-of-band, not to be confused w/ Pant's In-Band Registration.
   //   See also, https://secure.wikimedia.org/wikipedia/en/wiki/Out-of-band
   //   Changing users, revisions or the viewport are in-band updates, that
   //   is, those server requests cannot overlap. But there are some requests
   //   that can happen independently of other requests. An example of an
   //   out-of-band request is loading the history browser: it doesn't matter
   //   if the user changes revisions, or if the user is panning the map; we
   //   can send this request whenever we feel like it (although changing
   //   branches would cause this request to be canceled). As evidenced by the
   //   previous parenthetical thought, what's considered "in-band" includes
   //   panning and zooming the map, changing revisions, changing branches,
   //   and changing users. What's considered out-of-band is mostly details-
   //   panel-related actions, like loading discussions, loading the history
   //   browser, etc. Usually, in-band requests are only canceled if a similar
   //   in-band request is received (say the user wants to see page 2 of
   //   discussions, but then hits "next" to see page 3). But changing users,
   //   branches, or revisions sometimes affects these (but changing the
   //   viewport never should). For example, changing revisions doesn't affect
   //   loading the history browser, but changing branches or users does. Per
   //   discussions, changing users, branches or revisions causes the load
   //   request to be canceled because discussions are revisioned. It all
   //   depends on context.
   //
   // A detailed analysis of the contexts:
   // 
   // User Changes the Revision, Branch, or User
   //  * Trigggered by:
   //    - Historic Mode (user looks at old revision, does a diff, etc.)
   //    - Revert Action (user reverts a revision, which creates new revision)
   //    - Save Items (user saves items, which creates a new revision)
   //      - Ideally, we shouldn't reload the map from scratch, but we do
   //    - Reset Working Copy (user has made changes but decides to toss them)
   //      - Again, it might not be necessary to do a complete map reload
   //    - Branch or User Change
   //      - Changing Users or Branches could be considered separately, but
   //        changing revisions could mean the user has different group
   //        memberships or a different new item policy, so changing revisions
   //        always causes a complete reload, as do changing branches or users
   //  * What's fetched:
   //    - GrAC: Memberships
   //    - GrAC: New Item Policy
   //    - Branch-wide attachments (tags and attributes)
   //    - Items in the default or current viewport are refreshed (see next)
   // 
   // User Changes the Viewport
   //  * Trigggered by:
   //    - User pans the map
   //    - Indirectly by changing branches, revisions or users (see previous)
   //  * What's fetched:
   //    - Geofeatures and their Linked-Attachments w/in the Viewport
   //      - all geofeatures, and all attachments and links related to them
   //      - items we no longer need (are outside the viewport) are 
   //        discarded when the operation is complete
   //      - must be synchronized
   //        - only 1 update at a time
   //          - otherwise panning takes too long
   //          - when a new update action is received, this class cancels 
   //            the current update action, deletes any pending actions, and 
   //            creates a new action to execute when the canceled action is
   //            done canceling itself
   //        - responses are processed in a specific order
   //          - otherwise classes need to be smarter and handle items not yet
   //            resident in memory (currently, geofeatures and attachments
   //            must be loaded before link values)
   //    - Tiles w/in the Viewport
   //      - either raster (our jpeg) or aerial (someone else's png)
   //        - currently, we only keep one type (raster or aerial) but we
   //          might want to keep both, if we find toggling aerial is slow
   //
   // Users Opens a Lazy-Loaded Panel
   //  * Trigggered by:
   //    - User opens a details panel that we lazy load
   //      - Discussions, History Browser
   //      - Maybe group memberships if we don't always need them
   //      - Lazy loading lets us avoid loading things we don't need until the
   //        user wants to see or edit them
   //  * What's fetched:
   //    - Just what the user wants
   //      - A "page" of posts, a "page" of revisions, etc.
   //    - If the data is not specific to a revision, it does not have to be
   //      refreshed when the revision changes (namely, history browser data)
   //    - If the data is specific to a revision, it will have to be refreshed
   //      (e.g., posts and threads)

   // This class doesn't do the actual fetch. This class only coordinates
   // requests, so that other objects in the system don't have to worry about 
   // stepping on each others' toes (for instance, as the user pans, multiple
   // update requests are generated, and this class is smart enough to only
   // care about the latest request).
   //
   // This class uses helper classes -- Update_Base and its class hierarchy
   // -- to process the updates. The helper classes are smart enough to
   // synchronize requests within an update, whereas this class is smart enough
   // to synchronize and coordinate the updates themselves.

   public class Update_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Update_Mgr');

      // Classes that precede other classes in this array make requests of
      // the latter class obsolete. E.g., if the user logs in or out, a user
      // update is triggered, which causes any branch and revision updates
      // to be canceled.
      protected static const request_hier:Array = [
         Update_User,
         Update_Branch,
         Update_Revision
         // Update_Supplemental would come next, but it's special.
         ];

      // *** Class attributes

      // A pointer to the map using this manager.
      public var map:Map_Canvas;

      // In-band requests are Update_Base objects that can only be run after
      // other in-band requests have been completed, and they can only be run
      // one at a time. The dicts are keyed [Update_Base class] => Update_Base
      // instance.
      private var in_band_executing:Dictionary = new Dictionary();
      private var in_band_scheduled:Dictionary = new Dictionary();

      // Out-of-band requests can run in parallel with in-band and other
      // out-of-band request, but it depends on which update stage it is.
      // Some out-of-band requests can be overlapped, so we use a set, rather
      // than a dict. The Set is a collection of Update_Supplemental objects,
      // which represent out-of-band requests.
      private var oo_band_executing:Set_UUID = new Set_UUID();
      private var oo_band_scheduled:Set_UUID = new Set_UUID();

      // Both in-band and out-of-band requests are moved to the canceled queue
      // upon cancelation and are removed once cancelation in complete. This
      // lookup may contain any Update_Base-derived object.
      private var requests_canceled:Set_UUID = new Set_UUID();

      // *** Constructor

      public function Update_Manager(map:Map_Canvas_Update)
      {
         this.map = (map as Map_Canvas);
      }

      // *** 

      // Schedules a map update based on the class being passed in
      public function schedule_in_band(update_cls:Class) :void
      {
         m4_TALKY('========= Scheduling Update [schedule_in_band] =========');
         // Prevent premature updates during app initialization (see Bug #185).
         if (!(G.initialized)) {
            // MAYBE: Queue early requests instead?
            m4_TALKY(' .. called too early!'); // This always happens on boot.
            // After the app is done starting up, G.init() schedules a 
            // callLater on on_resize, so we'll get called again soon.
            // (This feels a little kludgy, but it's probably messy to have 
            // objects check G.initialized first. Also, we don't need to
            // worry about caching the update request; the first time we 
            // get called after initialization is complete, we'll know we 
            // have to fetch everything from the server.)
            // FIXME If the user goes to a lazy-load details panel before the
            //       app is initialized, then this might not actually work, and
            //       the user might be left with a blank panel.
         }
         // Make sure we have a working revision ID before doing most work
         else if ((update_cls !== Update_User)
                  && (update_cls !== Update_Branch) 
                  && (G.map.rev_viewport is utils.rev_spec.Current)) {
            // FIXME: Queue early requests instead?
            // 2013.04.08: On Historic checkout, these are both null.
            m4_DEBUG('schd_in_band: G.map.rev_loadnext:', G.map.rev_loadnext);
            m4_DEBUG('schd_in_band: G.map.rev_viewport:', G.map.rev_viewport);
            m4_DEBUG('schd_in_band: G.map.rev_workcopy:', G.map.rev_workcopy);
            m4_WARNING(' .. no working copy rid yet: update_cls:', update_cls);
            m4_ASSERT(false);
         }
         else {
            var update_obj:Update_Base;
            update_obj = new update_cls();
            update_obj.configure(this);
            var found_duplicate:Boolean;
            found_duplicate = this.schedule_request(update_obj);
            // MAYBE: Care about found_duplicate?
         }
      }

      //
      public function schedule_oo_band(gwis_req:GWIS_Base) :Boolean
      {
         var found_duplicate:Boolean = true;
         m4_TALKY('schedule_oo_band: gwis_req:', gwis_req);
         if (G.initialized) {
            var update_oob:Update_Out_Of_Band;
            update_oob = new Update_Out_Of_Band(gwis_req);
            update_oob.configure(this)
            found_duplicate = this.schedule_request(update_oob);
         }
         else {
            // 2014.09.09: [lb] seeing this in the flashclient assert log.
            m4_ASSERT_SOFT(false);
            G.sl.event('error/update_mgr/schedule_oo_band',
                       {gwis_req: gwis_req.toString()});
         }
         return found_duplicate;
      }

      //
      protected function find_similar(update_obj:Update_Base) :Array
      {
         var similar:Array = new Array();
         if (update_obj is Update_Supplemental) {
            this.find_similar_add(
                           update_obj, similar, this.oo_band_executing, true);
            this.find_similar_add(
                           update_obj, similar, this.oo_band_scheduled, false);
         }
         else {
// FIXME: Does panning viewport kill lazy-load for attrs OOB requests? Or are
//        they simply re-requested?
            this.find_similar_add(
                           update_obj, similar, this.in_band_executing, true);
            this.find_similar_add(
                           update_obj, similar, this.in_band_scheduled, false);
         }
         return similar;
      }

      //
      protected function find_similar_add(update_obj:Update_Base, 
                                          similar:Array,
                                          collection:*,
                                          is_executing:Boolean) :void
      {
         var update_oth:Update_Base;
         for each (update_oth in collection) {
            if (update_obj.is_similar(update_oth)) {
               similar.push([update_oth, collection, is_executing,]);
            }
         }
      }

      // If the request is the same as one already executing, ignore it. If
      // there's an update happening for the same class, cancel the existing
      // update and queue the new one. Otherwise, start the new request.
      protected function schedule_request(update_obj:Update_Base) :Boolean
      {
         m4_TALKY('schedule_request:', update_obj);
         var similar:Array = this.find_similar(update_obj);
         var found_duplicate:Boolean;
         found_duplicate = this.is_request_duplicate(update_obj, similar);
         if (!found_duplicate) {
            this.schedule_request_impl(update_obj, similar);
         }
         else {
            m4_TALKY(' >> found_duplicate: ignoring request');
         }
         return found_duplicate;
      }

      // Check if a similar update is already being processed.
      protected function is_request_duplicate(update_obj:Update_Base,
                                              similar:Array) :Boolean
      {
         m4_TALKY('is_request_duplicate: checking:', update_obj);
         var found_duplicate:Boolean = false;
         var tuple:Array;
         for each (tuple in similar) {
            var update_oth:Update_Base = tuple[0];
            m4_TALKY('is_request_duplicate: similar:', update_oth);
            if (update_oth.equals(update_obj)) {
               m4_WARNING3('is_request_duplicate: ignoring duplicate:',
                           update_obj.toString_Terse(),
                           '/ already:', update_oth.toString_Terse());
               // We should only ever find at most one duplicate request.
               m4_ASSERT(!found_duplicate);
               found_duplicate = true;
            }
            // else, we'll queue the request.
         }
         return found_duplicate;
      }

      //
      protected function schedule_request_impl(update_obj:Update_Base,
                                               similar:Array) :void
      {
         var begin_later:Boolean = false;
         // Cancel similar update if request cannot be overlapped with same.
         begin_later ||= this.cancel_similar(update_obj, similar);
         // Cancel requests that are obsoleted by this request. And check up
         // the hierarchy to see if this request must wait for other updates to
         // finish.
         begin_later ||= this.cancel_obsoleted(update_obj);
         if (!begin_later) {
            begin_later = this.is_request_deffered(update_obj);
         }
         if (update_obj is Update_Supplemental) {
            // An out-of-band, or supplemental, request.
            if (begin_later) {
               m4_DEBUG2('sched_req_imp: oo_band_scheduled: update_obj:',
                         update_obj);
               this.oo_band_scheduled.add(update_obj);
            }
            else {
               m4_DEBUG2('sched_req_imp: oo_band_executing: update_obj:',
                         update_obj);
               this.oo_band_executing.add(update_obj);
               update_obj.update_begin();
            }
         }
         else {
            var update_class:Class = Introspect.get_constructor(update_obj);
            if (begin_later) {
               m4_DEBUG2('sched_req_imp: in_band_scheduled:', update_class, 
                         '/', update_obj);
               this.in_band_scheduled[update_class] = update_obj;
            }
            else {
               m4_DEBUG2('sched_req_imp: in_band_executing:', update_class, 
                         '/', update_obj);
               this.in_band_executing[update_class] = update_obj;
               update_obj.update_begin();
            }
         }
         this.debug_print_queue_info();
      }

      // Cancel similar update if new request cannot be overlapped with same.
      protected function cancel_similar(update_obj:Update_Base,
                                        similar:Array) :Boolean
      {
         m4_TALKY2('cancel_similar: update_obj:', update_obj, 
                     '/ similars:', similar.length);
         var canceled_active:Boolean = false;
         var tuple:Array;
         for each (tuple in similar) {
            var update_oth:Update_Base = tuple[0];
            m4_TALKY('cnq_mayb: similar:', update_oth);
            m4_ASSERT(update_obj.allow_overlapped_requests  
                      == update_oth.allow_overlapped_requests);
            if (!update_obj.allow_overlapped_requests) {
               m4_ASSERT(!update_oth.canceled);
               m4_TALKY('cnq_mayb: cancelling similar request');
               var collection:* = tuple[1];
               var is_executing:Boolean = tuple[2];
               update_oth.canceled = true;
               if ((collection is Set) || (collection is Set_UUID)) {
                  collection.remove(update_oth);
               }
               else {
                  m4_ASSERT(collection is Dictionary);
                  delete collection[update_oth];
               }
               if (is_executing) {
                  this.requests_canceled.add(update_oth);
                  m4_TALKY2('reqs_canceld.len:',
                              this.requests_canceled.length);
                  canceled_active = true;
               }
            }
            else {
               // We should only ever find at most one request to cancel.
               m4_ASSERT(!canceled_active);
            }
         }
         this.debug_print_queue_info();
         return canceled_active;
      }

      // This fcn. is called by Update_Base after it's done with its
      // operation, which could be because it completed successfully or because
      // it was canceled. Ideally, to reduce coupling, this class should
      // register this fcn. as a callback, but now, it's hard-coded from
      // Update_Base.
      public function update_signal_complete(update_obj:Update_Base) :void
      {
         var update_class:Class = Introspect.get_constructor(update_obj);
         m4_INFO('update_signal_complete:', update_class, '/', update_obj);
         // The current request is complete; be done with it. It's either in-
         // or out-of-band and executing, or it's canceled. But we don't track
         // in-band executing objects. I don't know why; I guess why don't need
         // the information. So the best we can do is check the class, but 
         var doppelganger_count:int = 
            ((((update_class in this.in_band_executing)
               || (this.requests_canceled.is_member(update_obj))) ? 1 : 0)
             + ((this.oo_band_executing.is_member(update_obj)) ? 1 : 0));
         if (1 != doppelganger_count) {
            m4_TALKY2('in_band_executing:',
               ((update_class in this.in_band_executing) ? 'Y' : 'N'));
            m4_TALKY2('oo_band_executing:',
               (this.oo_band_executing.is_member(update_obj) ? 'Y' : 'N'));
            m4_TALKY2('requests_canceled:',
               (this.requests_canceled.is_member(update_obj) ? 'Y' : 'N'));
            m4_ASSERT(1 == doppelganger_count);
         }
         delete this.in_band_executing[update_class];
         this.oo_band_executing.remove(update_obj);
         if (this.requests_canceled.is_member(update_obj)) {
            this.requests_canceled.remove(update_obj);
            var update_oob:Update_Out_Of_Band;
            update_oob = (update_obj as Update_Out_Of_Band);
            if ((update_oob !== null) && (update_oob.gwis_req !== null)) {
               update_oob.gwis_req.on_cancel_cleanup();
            }
            // else, MAYBE: What about calling on_cancel_cleanup on the
            //              Update_* command that got trump-canceled?
         }
         this.debug_print_queue_info();
         // Start any additional update requests that are scheduled 
         var i:int = 0;
         for (i = 0; i < Update_Manager.request_hier.length; i++) {
            update_class = Update_Manager.request_hier[i];
            if (update_class in this.in_band_executing) {
               // There's still an in-band request executing, so no-op
               m4_DEBUG(' >> skipping next update: waiting on:', update_class);
               break;
            }
            else if (update_class in this.in_band_scheduled) {
               m4_DEBUG2(' >>  scheduling next update:', 
                         this.in_band_scheduled[update_class]);
               this.in_band_executing[update_class] 
                  = this.in_band_scheduled[update_class];
               delete this.in_band_scheduled[update_class];
               this.in_band_executing[update_class].update_begin();
               break;
            }
         }
         if (i == Update_Manager.request_hier.length) {
            // No more in-band requests, so try out-of-band. Since oob requests
            // can usually be run in parallel, go through all scheduled oob
            // requests and try to schedule each one of them.
            var oo_scheded:Set_UUID = this.oo_band_scheduled;
            this.oo_band_scheduled = new Set_UUID();
            var update_req:Update_Base;
            var found_duplicate:Boolean;
            for each (update_req in oo_scheded) {
               found_duplicate = this.schedule_request(update_req);
               // MAYBE: Care aboue found_duplicate?
            }
         }
         this.debug_print_queue_info();
      }

      // ***

      //
      public function active_update_get(update_class:Class) :Update_Base
      {
         m4_TALKY2('active_update_get: len', 
                   Collection.dict_length(this.in_band_executing));
         m4_ASSERT(Update_Viewport_Items == update_class); // all that's impl'd
         var in_progress:Update_Base = null;
         // NOTE: Assuming update_class always in this.in_band_executing.
         //       Or does this sometimes just return null?
         in_progress = this.in_band_executing[update_class];
         return in_progress;
      }

      //
      protected function cancel_obsoleted(update_obj:Update_Base) :Boolean
      {
         m4_TALKY('cancel_obsoleted: trump:', update_obj);
         this.debug_print_queue_info();
         // Cancel other requests of this type and of any type that follow it.
         var canceled_count:int = 0;
         if ((Collection.dict_length(this.in_band_executing) > 0) 
             || (Collection.dict_length(this.in_band_scheduled) > 0)) {
            var cls_idx:int = this.request_hier_idx(update_obj);
            m4_TALKY('  .. cls_idx:', cls_idx);
            // I.e., Update_User < Update_Revision < Update_Branch 
            //         < Update_Supplemental
            if (cls_idx < Update_Manager.request_hier.length) {
               var i:int;
               for (i = cls_idx; i < Update_Manager.request_hier.length; i++) {
                  var cls:Class = Update_Manager.request_hier[i];
                  m4_TALKY('  .. cls:', cls);
                  if (cls in this.in_band_executing) {
                     // Cancel a request that's currently executing
                     m4_TALKY('cancel_obsoleted: removing:', cls);
                     var like_update:Update_Base = this.in_band_executing[cls];
                     like_update.canceled = true;
                     delete this.in_band_executing[cls];
                     this.requests_canceled.add(like_update)
                     if (i == cls_idx) {
                        // We just canceled a request similar to this one, so
                        // wait until the canceled request is canceled.
                     }
                     canceled_count += 1;
                     this.debug_print_queue_info();
                  }
                  else {
                     m4_TALKY('cancel_obsoleted: skipping:', cls);
                  }
                  // Cancel any request that might be pending
                  delete this.in_band_scheduled[cls];
                  this.debug_print_queue_info();
               }
            }
            else {
               m4_TALKY(' >> skipping in band (> cls):', update_obj);
               m4_ASSERT(update_obj is Update_Supplemental);
            }
         }
         else {
            m4_TALKY(' >> skipping in band (none)');
         }
         // Cancel Supplemental requests specially
         var update_sup:Update_Supplemental;
         for each (update_sup in this.oo_band_executing) {
            if (update_sup.is_trumped_by(update_obj) 
                && (update_sup.cancelable)) {
               m4_TALKY(' >> removing oo_band_executing:', update_sup);
               this.oo_band_executing.remove(update_sup);
               update_sup.canceled = true;
               this.requests_canceled.add(update_sup);
               canceled_count += 1;
               this.debug_print_queue_info();
            }
            else {
               m4_VERBOSE2(' >> skipping oo_band_executing:', update_sup,
                           '/ cancelable:', update_sup.cancelable);
            }
            // else, request is not cancelable (e.g., revert), so let it
            // complete (and don't worry about it)
         }
         for each (update_sup in this.oo_band_scheduled) {
            if (update_sup.is_trumped_by(update_obj)) {
               m4_TALKY(' >> removing oo_band_scheduled:', update_sup);
               this.oo_band_scheduled.remove(update_sup);
               this.debug_print_queue_info();
               var update_oob:Update_Out_Of_Band;
               update_oob = (update_sup as Update_Out_Of_Band);
               if ((update_oob !== null) && (update_oob.gwis_req !== null)) {
                  update_oob.gwis_req.on_cancel_cleanup();
               }
               // else, MAYBE: What about calling on_cancel_cleanup on the
               //              Update_* command that got trump-canceled?
            }
            else {
               m4_TALKY(' >> skipping oo_band_scheduled:', update_sup);
            }
         }
         m4_TALKY(' >> canceled_count:', canceled_count);
         this.debug_print_queue_info();
         return (canceled_count > 0);
      }

      //
      protected function is_request_deffered(update_obj:Update_Base) :Boolean
      {
         // Check if a request of a superceeding type is executing.
         var is_deferred:Boolean = false;
         var cls_idx:int = this.request_hier_idx(update_obj);
         for (var i:int = cls_idx - 1; i >= 0; i--) {
            var cls:Class = Update_Manager.request_hier[i];
            if ((cls in this.in_band_executing) 
                || (cls in this.in_band_scheduled)) {
               is_deferred = true;
               break;
            }
         }
         m4_DEBUG2('is_request_deffered: is_deferred:', is_deferred,
                   '/ update_obj:', update_obj);
         return is_deferred;
      }

      //
      protected function request_hier_idx(update_obj:Update_Base) :int
      {
         var idx:int = -1;
         var update_cls:Class = Introspect.get_constructor(update_obj);
         // Find this class (maybe) in the list.
         for (idx = 0; idx < Update_Manager.request_hier.length; idx++) {
            if (update_cls == Update_Manager.request_hier[idx]) {
               break;
            }
         }
         return idx;
      }

      // ***

      //
      protected function debug_print_queue_info() :void
      {
         m4_TALKY6('update_queues:',
            'in/execg:', Collection.dict_length(this.in_band_executing),
            'in/sched:', Collection.dict_length(this.in_band_scheduled),
            'oo/execg:', this.oo_band_executing.length,
            'oo/sched:', this.oo_band_scheduled.length,
            'canceled:', this.requests_canceled.length);
      }

   }
}


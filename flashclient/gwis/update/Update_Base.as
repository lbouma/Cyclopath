/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class handles updating the map by fetching items from the server
// depending on the current viewport, zoom level, and revision.

package gwis.update {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.utils.UIDUtil;

   import grax.Grac_Manager;
   import gwis.GWIS_Base;
   import gwis.GWIS_Checkout_Versioned_Items;
   import gwis.GWIS_Grac_Get;
   import gwis.Update_Manager;
   import gwis.utils.Query_Filters;
   import items.feats.Branch;
   import items.feats.Byway;
   import items.feats.Waypoint;
   import items.utils.Item_Type;
   import items.utils.Tile;
   import utils.geom.Dual_Rect;
   import utils.misc.Collection;
   import utils.misc.Counter;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.base.Map_Canvas;
   import views.base.UI;

   public class Update_Base {

      // This class handles the sending of and the receiving and processing of
      // one or more GWIS_Base requests to perform a particular user operation,
      // like zooming or panning the map, or saving items, etc.
      //
      // This class uses callLater when processing a lot of information. One
      // reason is that the Flash client needs to remains responsive while the
      // user is waiting for something to happen (so the user can dink around
      // in the details panel while the map is loading, for example). Another
      // reason is that Flash will eventually bail if your script runs too long
      // uninterrupted (after a number of seconds, Flash just assumes the
      // script has gone bonkers and then halts it).

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Upd_Base');

      // Processing cancelations is complicated: there are lots of requests to
      // cancel, and canceling an update can leave us in a somewhat unknown
      // state, especially when cancelling viewport updates. Since most
      // cancelations are followed by another update request, this flag
      // helps to indicate the state of the machine.
      protected static var prior_update_canceled:Boolean = false;

      // *** Instance attributes

      //
      protected var results_preempted:Boolean = false;

      //
      public var mgr:Update_Manager;

      // Ptr to the map
      public var map:Map_Canvas;

      // Identifying characteristics of the update, common to each of the GWIS
      // commands we'll make
      protected var username:String;
      protected var branch:Branch;
      protected var rev:utils.rev_spec.Base;

      // If something triggers an update while one is already executing -- like
      // the user panning the map while the map is still loading -- we can
      // cancel the outstanding GWIS_Base requests and prepare for the next
      // update.  We use two booleans to track the state of the update.
      protected var canceled_:Boolean = false;
      protected var completed:Boolean = false;

      // Track the time it takes to run the update
      protected var debug_t0:int;

      // Though requests can overlap and be sent in parallel, we still organize
      // them into steps. This not only helps the developer understand what's
      // fetched during an update, but it also allows us to use callLater
      // so that we don't starve the client while performing an update.
      // (Though I'm not convinced it really takes the client all that long to
      // send all of the requests.)
      // FIXME: Remove update_steps?: unneccessarryy complexity?
      protected var update_steps:Array = new Array();
      protected var update_steps_total:int; // Initial # of stages

      // This class sends many requests in parallel, but processing responses
      // does not happen in parallel and instead happens in serial.
      //
      // To implement this behavior, we use a number of lookups. One lookup is
      // the master lookup, and then a bunch of other lookups handle each of
      // the intermediate item types (defined by the derived classes).
      //
      // resp_lookup maps a GWIS_Base request to a Set which is a lookup that
      // one of the derived classes declares.
      // WARNING: The Sets are hacked. Normally, a Set's key == its respective
      // values so that for-each can be used in member fcns. But in this class,
      // sometimes a Set's key === null, so some Set fcns. would behave weird.
      protected var resp_lookup_sets:Dictionary = new Dictionary();

      // We don't process any responses until we've sent all the requests
      protected var requests_all_sent:Boolean = false;

      // Each request blocks the update until a response is received. Some
      // derived classes define their own sets of callbacks, or they can use
      // the one declared here.
      protected var requests_send:Array = new Array();
      // When some responses come back, we want to do special processing (and
      // we don't want that code in the GWIS_Base class)
      protected var resp_callbacks:Dictionary = new Dictionary();
      // To run functions after processing responses, we use an additional
      // lookup.
      protected var resp_post_process:Array = new Array();

      // The work_queue is used in conjunction with the previous lookups
      // to handle sending requests, processing responses, and running helper
      // functions along the way. This lets us use callLater to avoid starving
      // the client, and it also lets us apply an order to how we do things.
      protected var work_queue_empty:Boolean = true;
      protected var work_queue_gwis:Array = new Array();
      protected var work_queue_fcn:Array = new Array();

      public var completion_event:String = '';

      // *** Constructor

      public function Update_Base()
      {
      }

      // ***

      //
      public function toString_Terse() :String
      {
         return String(this);
      }

      // ***

      //
      public function get allow_overlapped_requests() :Boolean
      {
         return false;
      }

      //
      public function set allow_overlapped_requests(allow_it:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get cancelable() :Boolean
      {
         return true;
      }

      //
      public function set cancelable(cancellable:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      public function is_similar(other:Update_Base) :Boolean
      {
         return (Introspect.get_constructor(this)
                 == Introspect.get_constructor(other));
      }

      // *** Initialization methods

      //
      protected function init_update_steps() :void
      {
         // A map update involves a lot of fetching of a lot of different
         // objects. We can send all the requests at once, but we sometimes
         // have to process the reponses in a strict order. Derived classes
         // should override this fcn. and populate this.update_states with one
         // or more function callbacks to send requests and to set up response
         // handlers. The callbacks are executed one after another, except for
         // a short callLater reprise between each one, so that we don't starve
         // the GUI.
         m4_ASSERT(false); // Abstract
      }

      // ***

      // *** Public Interface

      // **** Configure update request

      // Create and configure a Update_Base object based on its class.
      public function configure(mgr:Update_Manager) :void
      {
         this.mgr = mgr;
         this.map = this.mgr.map;
         //
         this.username = G.user.username;
         this.branch = G.item_mgr.active_branch;
         this.rev = this.map.rev_viewport;
         if (this.rev === null) {
            this.rev = this.map.rev_loadnext;
            m4_ASSERT(this.rev !== null);
         }

         m4_DEBUG('configure: Update_Base obj: rev:', this.rev.friendly_name);
      }

      // **** Check if duplicate request

      //
      public function equals(other:Update_Base) :Boolean
      {
         m4_ASSERT(this !== other);
         var equal:Boolean = false;
         // We assert that the two objects being compared are the same class.
         // This isn't really necessary (equals returns false), but I wouldn't
         // expect it, given how the code is coded.
         equal = (Introspect.get_constructor(this)
                  == Introspect.get_constructor(other));
         m4_ASSERT(equal); // same class
         equal = (equal
                  && (this.username == other.username)
                  && (this.branch == other.branch)
                  && (this.rev == other.rev));
         return equal;
      }

      // **** Cancel an Update

      //
      public function get canceled() :Boolean
      {
         return this.canceled_;
      }

      //
      public function set canceled(canceled:Boolean) :void
      {
         m4_ASSERT(canceled == true);
         m4_DEBUG('set canceled:', canceled);
         this.canceled_set();
      }

      // ***** Internal cancel fcn

      //
      protected function canceled_set() :void
      {
         if (!this.canceled_) {
            this.canceled_ = true;
            // Don't send any more GWIS_Base requests
            this.work_queue_gwis = new Array();
            // Don't process any more deferred functions
            this.work_queue_fcn = new Array();
            // Cancel the outstanding GWIS_Base commands
            var lookup_key:Object;
            for (lookup_key in this.resp_lookup_sets) {
               var req:GWIS_Base;
               req = (lookup_key as GWIS_Base);
               m4_DEBUG('canceling request:', req);
               req.cancel();
            }
            // NOTE We don't have to clear this.update_steps: that happens in
            //      this.update_begin_really()
            // NOTE We don't have to clear the other resp_* lookups; this is
            //      taken care of in gwis_complete_stages
         }
      }

      //
      protected function canceled_reset_lookups() :void
      {
         this.requests_send = new Array();
         this.resp_callbacks = new Dictionary();
         this.resp_post_process = new Array();
      }

      // **** Start an Update, Which Is callLatered Until It's Done

      // This fcn starts the timer, starts throbbering, and queues the callback
      public function update_begin() :void
      {
         m4_DEBUG('============ Scheduling Update [update_begin] ===========');
         m4_ASSERT(G.initialized);
         // Start the timer.
         this.debug_t0 = G.now();
         // Get the throbber going.
         if (this.use_throbberer()) {
            UI.throbberers_increment(this);
         }
         // Populate the list of functions we'll call.
         this.init_update_steps();
         this.update_steps_total = this.update_steps.length;
         // Trigger the start of many callbacks.
         m4_DEBUG_CLLL('>callLater: this.update_begin_really [update_begin]');
         this.map.callLater(this.update_begin_really);
      }

      //
      // Some things must be loaded in order, and when each of these ordered
      // things are loaded, they call this fcn. to tell use to keep going.
      public function update_nudge() :void
      {
         m4_DEBUG_CLLL('>callLater: gwis_complete_stages', '[update_nudge]');
         this.map.callLater(this.gwis_complete_stages);
      }

      // Callback fcn. to send GWIS_Base requests. Uses a work queue so can
      // call callLater frequently to avoid user interaction starvation.
      protected function update_begin_really() :void
      {
         var done:Boolean = false;
         m4_DEBUG_CLLL('<callLater: update_begin_really');
         m4_TALKY('      canceled:', this.canceled_);
         m4_TALKY('   stages left:', this.update_steps.length);
         if ((!this.canceled_) && (this.update_steps.length > 0)) {
            var current_step:int
               = this.update_steps_total - this.update_steps.length + 1;
            m4_TALKY('  current_step:', current_step);
            this.update_steps[0]();
            this.update_steps.shift();
            done = (this.update_steps.length == 0);
          }
         else {
            // All done!
            done = true;
         }
         if (done) {
            m4_DEBUG('update_begin_really: done sending requests');
            this.update_steps = null;
            this.requests_all_sent = true;
            // In practice, I've seen the Config request and even Terrain
            // returned while we're still sending GWIS_Base requests for the
            // update, so make sure we give the completion routine a kick, in
            // case some items are already queued for consumption.
            // NOTE I find this curious -- I wrote update_begin_really to use
            //      callLater to split up sending of GWIS_Base requests, but I
            //      really didn't expect it to have such a noticeable impact,
            //      i.e., between GWIS_Base requests, we are now processing
            //      GWIS replies.
            m4_TALKY('>callLater: gwis_complete_s [update_begin_really]');
            this.map.callLater(this.gwis_complete_stages);
         }
         else {
            m4_TALKY('>callLater: update_begin_re [update_begin_really]');
            this.map.callLater(this.update_begin_really);
         }
      }

      //
      protected function use_throbberer() :Boolean
      {
         return true;
      }

      // *** Register a Callback to Run If Response Received, or if Canceled

      // Each GWIS_Base object calls this function after it's received a
      // response from the server. We have to consume processes in order,
      // so we queue up the GWIS_Base request to be processed later.
      public function gwis_complete_schedule(
         req:GWIS_Base,
         req_success:Boolean,
         completion_routine:Function=null,
         completion_args:Array=null) :void
      {
         m4_DEBUG('gwis_complete_schedule:', req.toString());
         m4_DEBUG('   .. req.url_stripped:', req.url_stripped);
         // CAREFUL: If, while processing an Update, the update tries to queue
         //          an Update of the same type, the current update is canceled
         //          but not removed from the lookup, since cleaning up
         //          canceled requests comes later. So this fires:
         // What about Update_Supplemental?:
         //   m4_ASSERT_SOFT(req in this.resp_lookup_sets);
         m4_ASSERT(completion_args === null); // not used...
         // Get the group lookup, which is one of the resp_* lookups
         var group:Dictionary = this.resp_lookup_sets[req];
         // We no longer need the reference in resp_lookup
         delete this.resp_lookup_sets[req];
         // Replace the null ref. with the completion_routine pointer
         // (this is a Set but it's still a Dictionary -- yes, a hack!)

         m4_VERBOSE('gwis_complete_schedule: group:', group);
         if (group !== null) {
            m4_ASSERT(group[req] === null);
            if ((req_success)
                && (!this.canceled)
                && (completion_routine !== null)) {
               // This is cute: treating Set like a Dictionary; overwriting
               // null value with completion routine and arguments.
               m4_DEBUG2('Adding completion routine for request:',
                         req.toString());
               group[req] = [completion_routine, completion_args,];
            }
            else {
               m4_ASSERT((!req_success) || (completion_routine === null));
               m4_DEBUG('gwis_complete_schedule: deleting req:', req);
               m4_DEBUG(' / req_suc:', req_success);
               m4_DEBUG(' /  cncld?:', this.canceled);
               m4_DEBUG(' /    rtn?:', (completion_routine !== null));
               m4_DEBUG(' /   args?:', (completion_args !== null));
               // Remove the request from the Set. If group.empty, the Set is
               // complete. It'll get cleaned up in gwis_complete_resp.
               delete group[req];
            }
         }
         //else {
         //   m4_WARNING2('gwis_complete_schedule: group is null? req:',
         //               req.toString());
         //}
         // Trigger the completion routine
         m4_TALKY('>callLater: gwis_complete_stages', '[_same_]');
         m4_TALKY('gwis_complete_schedule: uuid:', UIDUtil.getUID(this));
         this.map.callLater(this.gwis_complete_stages);
      }

      // *** Derived Class Interface
      //    - These are helper functions that the derived classes use to
      //      register requests to send and functions to callback

      // **** Add GWIS_Base Request or Fcn, Processed In Order While Sending

      //
      protected function work_queue_add_unit(
         unit:Object,
         args:Array=null,
         insert_first:Boolean=false) :void
      {
         if ((unit is GWIS_Base) || (unit is Tile)) {
            m4_DEBUG('work_queue_add_unit/gwis:', unit, '/ args:', args);
            m4_ASSERT(args === null);
            m4_ASSERT(insert_first == false);
            this.work_queue_gwis.push(unit);
         }
         else if (unit is Function) {
            //m4_DEBUG2('work_queue_add_unit/fcn: from:',
            //          Introspect.stack_trace_caller());
            m4_DEBUG('work_queue_add_unit/fcn: args:', args);
            if (!insert_first) {
               this.work_queue_fcn.push([unit, args,]);
            }
            else {
               this.work_queue_fcn.unshift([unit, args,]);
            }
         }
         else {
            m4_ASSERT(false);
         }
         this.work_queue_empty = false;
         m4_TALKY('>callLater: work_queue_process [work_queue_add_unit]');
         // This fcn. gets called a lot per cycle, but only one callback is
         // scheduled, right?
         this.map.callLater(this.work_queue_process);
      }

      // **** Process one GWIS_Base Request or Callback Function

      //
      protected function gwis_results_process() :Boolean
      {
         //m4_ASSERT(false); // Abstract
         return false;
      }

      // **** Add a Function to Run After Processing All Responses

      //
      protected function requests_add_resp_post_process(
         fcn:Function, args:Array=null) :void
      {
         var fcn_arr:Array = new Array();
         var fcn_set:Dictionary = new Dictionary();
         fcn_arr.push(fcn);
         fcn_arr.push(args);
         fcn_set[fcn_arr] = fcn_arr;
         this.resp_post_process.push(fcn_set);
      }

      // *** Internal Processing Interface

      // **** Process one GWIS_Base Request or Callback Function

      //
      protected function work_queue_process() :void
      {
         var gwis_or_tile:Object;
         var fcn_arr:Array;
         m4_TALKY('<callLater: work_queue_process');
         if (this.work_queue_gwis.length > 0) {
            gwis_or_tile = this.work_queue_gwis.shift();
            //m4_DEBUG('work_queue_process: fetching:', gwis_or_tile);
            gwis_or_tile.fetch();
         }
         else if (this.work_queue_fcn.length > 0) {
            fcn_arr = this.work_queue_fcn.shift();
            //m4_DEBUG2('work_queue_process: functing:', fcn_arr.length,
            //   '/ fcn_arr[0]:', fcn_arr[0], '/ fcn_arr[1]:', fcn_arr[1]);
            var finished:Boolean = fcn_arr[0].apply(this.map, fcn_arr[1]);
            m4_DEBUG('work_queue_process: finished:', finished);
            if (finished === false) {
               this.work_queue_fcn.unshift(fcn_arr);
            }
         }
         else {
            m4_TALKY('work_queue_process: done');
            this.work_queue_empty = true;
         }
         if (this.work_queue_empty) {
            // Trigger the completion routine
            m4_TALKY('>callLater: gwis_complete_stages [work_queue_prc]');
            this.map.callLater(this.gwis_complete_stages);
         }
         else {
            // Trigger another callback to this method; we don't just process
            // the whole queue so that the GUI can update frequently
            m4_TALKY('>callLater: work_queue_process [work_queue_prc]');
            this.map.callLater(this.work_queue_process);
         }
      }

      // **** After Processing All GWIS_Base Requests and Related Functions,
      //     Call the Completion Functions and Finally Complete the Update

      //
      protected function gwis_complete_stages() :void
      {
         m4_TALKY('<callLater: gwis_complete_stages');
         m4_TALKY('_complete_stages: uuid:', UIDUtil.getUID(this));
         if (!this.requests_all_sent || !this.work_queue_empty) {
            m4_DEBUG('... Not READY!');
         }
         else if (this.completed) {
            // This shouldn't ever happen.
            m4_WARNING('... Already completed');
         }
         else {
            m4_TALKY('_complete_stages: Checking in-band signaling ===');
            this.results_preempted = false;
            if (this.canceled_) {
               this.canceled_reset_lookups();
            }
            if (this.requests_send.length != 0) {
               m4_TALKY3('_complete_stages: requests_send.length:',
                         this.requests_send.length,
                         '/', this.requests_send);
               this.requests_send = this.gwis_complete_resp(
                  this.requests_send);
            }
            else if (this.gwis_results_process()) {
               m4_DEBUG('_complete_stages: Derived class did something');
            }
            else if (this.resp_post_process.length != 0) {
               m4_TALKY3('_complete_stages: resp_post_process.length:',
                         this.resp_post_process.length,
                         '/', this.resp_post_process);
               this.resp_post_process = this.gwis_complete_resp(
                  this.resp_post_process);
            }
            else {
               m4_TALKY('_complete_stages: all done');
               if (!this.canceled) {
                  Update_Base.prior_update_canceled = false;
               }
               else {
                  Update_Base.prior_update_canceled = true;
               }
               // Set completed now so that update_signal_complete sees it.
               this.completed = true;
               // Let derived fcns. do any post-processing.
               this.update_signal_complete();
               // Signal the completion event, maybe.
               var completion_event:String
                  = Introspect.get_constructor(this).on_completion_event;
               if ((completion_event !== null)
                   && (completion_event != '')) {
                  m4_DEBUG2('_complete_stages: dispatchEvent:',
                            completion_event);
                  G.item_mgr.dispatchEvent(new Event(completion_event));
               }
               // Detach from the throbber.
               if (this.use_throbberer()) {
                  UI.throbberers_decrement(this);
               }
               // Set completed and show the time.
               m4_DEBUG2('_complete_stages:: =TIME= / update_*:',
                         (G.now() - this.debug_t0), 'ms');
            }
            if (this.results_preempted) {
               // The callback preemted itself, so call us back after feeding
               // the GUI some cycles.
               m4_TALKY('>callLater: gwis_complete_stages', '[_same_]');
               this.map.callLater(this.gwis_complete_stages);
            }
         }
      }

      // **** Process or Partially Process Results From GWIS_Base Response

      //
      protected function gwis_complete_resp(resp_lookup:Array)
         :Array
      {
         var fcn_arr:Array;
         var processed:Boolean = false;
         // The resp_lookup is an Array of Dictionary. Each successive
         // element, a Dictionary, cannot be completed until the one before
         // it. (Only Geofeatures have more than one Dictionary, so we can draw
         // the map terrain-first, followed by byways, waypoints, and then
         // link_value-attributes; there's only one Dictionary for Attachments
         // and Link_Values.) We cull Dictionariess as they're emptied, and we
         // use callLater (or at least tell the callee to callLater), so we
         // only need the first element (Dictionary) from the array.
         m4_DEBUG('gwis_complete_resp: len:', resp_lookup.length);
         // 2011.07.21: on_error handling leaves empty Set in
         //             gwis_complete_schedule
         // FIXME: Should gwis_complete_schedule set it null, or should we
         //        do it here? Doing it here for now since there's is where
         //        it's done in the for loop (which doesn't run because the
         //        Set is empty).
         if ((resp_lookup.length > 0)
             && ((resp_lookup[0] === null)
                 || (Collection.dict_is_empty(resp_lookup[0])))) {
            m4_DEBUG(' >> : resp_lookup[0] is empty');
            // The Set is empty. Remove it from the dictionary and
            // leave a null in its place so it gets removed.
            resp_lookup[0] = null;
            // Schedule a callback to clean this up
            this.results_preempted = true;
         }
         else if (resp_lookup.length > 0) {
            m4_ASSERT(resp_lookup[0] is Dictionary);
            m4_DEBUG2(' >> : resp_lookup[0].length',
                      Collection.dict_length(resp_lookup[0]));
            // Each of the entries in the Set evolves over time:
            //   it's null while the request is outstanding
            //   it's a completion routine Array once the response is received
            //   it's removed once the response is processed
            // We modify resp_lookup[0] on the fly, so make a shallow copy.
            var req_group:Dictionary = Collection.dict_copy(resp_lookup[0]);
            for (var lookup_key:* in req_group) {
            //for (var lookup_key:* in resp_lookup[0]) {
               // The entry is null until we receive a response from pyserver
               m4_VERBOSE4(' >> lookup_key:', lookup_key,
                  '/ lookup_key:', Introspect.get_constructor(lookup_key),
                  '/ resp_lookup[0]:', resp_lookup[0],
                  '/ entry:', resp_lookup[0][lookup_key]);
               m4_ASSERT((lookup_key is GWIS_Base) || (lookup_key is Array));
               if (resp_lookup[0][lookup_key] !== null) {
                  fcn_arr = resp_lookup[0][lookup_key];
                  m4_ASSERT(fcn_arr[0] is Function);
                  m4_ASSERT((fcn_arr[1] is Array) || (fcn_arr[1] === null));
                  // Call the registered processing routine (usually,
                  // G.map.items_add). If it returns false, it's run too
                  // long and we should keep it scheduled to run again next
                  // callLater.

                  try {
                     processed = fcn_arr[0].apply(this.map, fcn_arr[1]);
                  }
                  catch (e:Error) {
                     // HACK HACK HACK HACK HACK HACK HACK HACK HACK HACK HACK
                     // This makes it work on Flash Player 11 (non-debug)!
                     // HACK HACK HACK HACK HACK HACK HACK HACK HACK HACK HACK
                     //
                     // FIXME: Why is this happening and what data is missing?
                     //        Does checkout branch fail here?
                     //
                     m4_ERROR('gwis_complete_resp:', e.toString());
                     var stack:String = e.getStackTrace();
                     m4_ERROR('gwis_complete_resp: stack:', stack);
                     //
                     m4_ASSERT(false);
                  }

                  m4_DEBUG(' >> processed:', processed);
                  if (processed) {
                     // Cheat and do some more post-processing here, without
                     // callLater; these are lightweight fcns.

                     // m4_DEBUG('lookup_key:', lookup_key);
                     //   E.g., gwis1 [class GWIS_Grac_Get]
                     // m4_DEBUG('this.resp_callbacks:', this.resp_callbacks);
                     //   E.g., [object Dictionary]
                     // m4_DEBUG2('this.resp_callbacks[lookup_key]:',
                     //           this.resp_callbacks[lookup_key]);
                     //   E.g., function Function() {},
                     if (this.resp_callbacks[lookup_key] !== null) {
                        m4_VERBOSE('Not null');
                        for each (fcn_arr in this.resp_callbacks[lookup_key]) {
                           m4_DEBUG('Found resp_callback');
                           m4_ASSERT(fcn_arr[0] is Function);
                           m4_ASSERT((fcn_arr[1] is Array)
                                     || (fcn_arr[1] === null));
                           processed = fcn_arr[0].apply(this.map, fcn_arr[1]);
                        }
                        m4_VERBOSE('..deleting');
                        delete this.resp_callbacks[lookup_key];
                     }
                     //
                     m4_DEBUG('..Processed!');
                     // Remove from group resp_attcs/_feats/_links/_postp Set
                     m4_DEBUG('....removing:', lookup_key);
                     delete resp_lookup[0][lookup_key];
                     if (Collection.dict_is_empty(resp_lookup[0])) {
                        // The Set is empty. Remove it from the dictionary and
                        // leave a null in its place so it gets removed.
                        resp_lookup[0] = null;
                     }
                  }
                  // else, we'll leave the completion routine in the Set, so
                  // we can call it again next callLater

                  // Whether or not we're done processing the request, we need
                  // to tell the callee to call us again after feeding the GUI.
                  this.results_preempted = true;
                  break;
               }
               else {
                  m4_TALKY('..Still outstanding:', lookup_key);
               }
            }
         }
         // Clean the array of completed entries (indices we set to null)
         // (I think if we reverse-iterated through the array we could remove
         // entries inside the for-loop and wouldn't have to call this expunge
         // routine).
         var resp_arr:Array = this.gwis_complete_resp_cleanup(resp_lookup);
         return resp_arr;
      }

      // Given an array of items, removes those that are null and returns a new
      // Array
      protected function gwis_complete_resp_cleanup(resp_lookup:Array)
         :Array
      {
         var culled:Array = new Array();
         for (var i:int = 0; i < resp_lookup.length; i++) {
            if (resp_lookup[i] !== null) {
               m4_TALKY2('gwis_complete_resp_cleanup: keep:', resp_lookup[i],
                         '/ i:', i);
               culled.push(resp_lookup[i]);
            }
         }
         return culled;
      }

      //
      protected function update_signal_complete() :void
      {
         this.map.update_mgr.update_signal_complete(this);
      }

      // **** Add requests and work items to queues

      //
      protected function requests_add_request(
         req:GWIS_Base,
         callback_fcn:Function=null,
         callback_args:Array=null,
         new_set:Boolean=false) :void
      {
         var group:Dictionary;
         if (new_set || (this.requests_send.length == 0)) {
            group = new Dictionary();
            this.requests_send.push(group);
         }
         else {
            group = this.requests_send[this.requests_send.length - 1];
         }
         this.resp_lookup_sets[req] = group;
         group[req] = null;

         if (callback_fcn !== null) {
            if (!(req in this.resp_callbacks)) {
               this.resp_callbacks[req] = new Array();
            }
            m4_DEBUG('req:', req);
            // This is null
            //   m4_DEBUG('resp_callbacks[req]:', this.resp_callbacks[req]);
            // This is function Function() {}
            //   m4_DEBUG('callback_fcn:', callback_fcn);
            // m4_DEBUG('callback_args:', callback_args);
            this.resp_callbacks[req].push([callback_fcn, callback_args,]);
         }
         this.work_queue_add_unit(req);
         if (Logging.get_level_key('DEBUG') >= Update_Base.log.current_level) {
            m4_DEBUG('requests_add_request: req:', req);
            for each (var o1:Object in this.requests_send) {
               m4_DEBUG('                  qed cnt:', o1.length);
               for each (var o2:Object in o1) {
                  m4_DEBUG('                      qed:', o2);
               }
            }
         }

      }

      // **** Create one or more item requests for particular revision

//FIXME Who else should use this? Attribute, Post, Thread, Tag, Annotation?
//      Search?
      //
      protected function gwis_fetch_rev_create(
         item_types:Array,
         include_rect:Dual_Rect,
         exclude_rect:Dual_Rect,
         exclude_static:Boolean=false) :Array
      {
         var query_filters:Query_Filters = new Query_Filters();
         // MAYBE: Create our own query_filters, or should caller pass in, or
         //        should we clone a globle, shared query_filters?
         //var query_filters:Query_Filters = G.item_mgr.query_filters.clone();
         //m4_DEBUG2('gwis_fetch_rev_create: include_rect:',
         //   (include_rect !== null) ? include_rect.toString() : 'null');
         query_filters.include_rect = include_rect;
         query_filters.exclude_rect = exclude_rect;

         // MEH: Always load a lightweight list of attributes and tags. If we
         // could be selective, we'd really only load a few of 'em with the
         // viewport items, and we'd load all of them if/when the user selects
         // items on the map. But we need the one-way attribute and the closed
         // tag to render geofeatures on the map, so for now -- since we can't
         // be selective about what's loaded -- load 'em all. (At least these
         // are lightweight attachments, meaning, just a list of keys (tags)
         // or key-value pairs (attributes); if/when the user selects an item
         // on the map, we'll load the heavyweight items, meaning, we'd load
         // the actual link_values, stack IDs, permissions, etc.
         if (false) {
            query_filters.dont_load_feat_attcs = true;
         }

         var callback:Function = null;
         return Update_Base.gwis_fetch_rev_create_qf(
            item_types,
            this.rev,
            query_filters,
            /*callback_load=*/callback,
            /*callback_fail=*/null,
            /*update_req=*/this,
            exclude_static);
      }

      //
      public static function gwis_fetch_rev_create_qf(
         item_types:Array,
         rev:utils.rev_spec.Base,
         query_filters:Query_Filters,
         callback_load:Function=null,
         callback_fail:Function=null,
         update_req:Update_Base=null,
         exclude_static:Boolean=false) :Array
      {
         var req:GWIS_Checkout_Versioned_Items;
         //var item_type:String;
         var item_type:Object;
         var item_type_str:String;
         var rev_cur:utils.rev_spec.Base;
         var revs:Array;
         var resp_items:Array = null;
         var buddy_ct:Counter = null;
         var reqs:Array = new Array();
         var diff_type:int = utils.rev_spec.Diff.NONE;

         /* MAYBE: The DiffMode code in CcpV3 replaces this CcpV1 approach:
         if (rev is utils.rev_spec.Diff) {
            // Diff request -- need to issue three GWIS_Base requests for each
            // type
            var diffr:utils.rev_spec.Diff = (rev as utils.rev_spec.Diff);
            revs = [
               diffr.clone(utils.rev_spec.Diff.OLD),
               diffr.clone(utils.rev_spec.Diff.NEW)];
            // Route manip. adds exclude_static.
            //  diffr.clone(utils.rev_spec.Diff.STATIC)];
            if (!exclude_static) {
               revs.push(diffr.clone(utils.rev_spec.Diff.STATIC));
            }
         }
         else {
            // one request per type
            revs = [rev];
         }
         */
         // MAYBE: We could remove the silly Array and just use the item now.
         // MAYBE: Do we still need buddy counter in CcpV3?
         // One request per type.
         revs = [rev];

         for each (item_type in item_types) {
            var link_type_attc:String = null;
            var link_type_feat:String = null;
            if (item_type is Array) {
               var item_type_arr:Array = (item_type as Array);
               link_type_attc = item_type_arr[0];
               link_type_feat = item_type_arr[1];
               item_type_str = 'link_value';
            }
            else {
               m4_ASSERT(item_type is String);
               item_type_str = (item_type as String);
            }
            if (rev is utils.rev_spec.Diff) {
               resp_items = new Array();
               // Set the buddy count, which means we don't process any of
               // these request responses until all responses are received.
               buddy_ct = new Counter(revs.length); // i.e., revs.length == 3;
            }
            // Get link_value counts if the user is visualizing them.
            // And please excuse the hack, but hard-coding the class names
            // herein seems as good a place as any.
            // Note that dllc ==> do_load_lval_counts.
            const dllc_item_types:Set_UUID =
               new Set_UUID([Byway.class_item_type,
                             Waypoint.class_item_type,]);

            // MAYBE: Is this necessary since we're loading tags and attrs?
            //        We could just count those instead...
            if ((rev is utils.rev_spec.Follow)
                && (G.tabs.settings.links_visible)
                && (dllc_item_types.is_member(item_type_str))) {
               query_filters.do_load_lval_counts = true;
            }
            else {
               query_filters.do_load_lval_counts = false;
            }

            for each (rev_cur in revs) {
               if (Update_Viewport_Base.debug_disable_exclude_rect) {
                  // For debug purposes, developers can ignore the exclude rect
                  // (and fetch everything in include_rect).
                  query_filters.exclude_rect = null;
               }
               else if (query_filters.exclude_rect !== null) {
                  // Otherwise, we can try to save some time and reduce
                  // bandwidth by only requesting what we don't already have.
                  if (Update_Base.prior_update_canceled) {
                     // If the user canceled the last update operation, we
                     // can't use the previous resident rect, since it's not
                     // representive of the current state (we may have received
                     // new items for some of the item types since then).
                     if (rev is utils.rev_spec.Diff) {
                        diff_type = (rev_cur as utils.rev_spec.Diff).group_;
                     }
                     query_filters.exclude_rect =
                        Item_Type.resident_rect_get_exclude(
                           diff_type, item_type_str,
                           query_filters.include_rect);
                  }
                  // else, since the last update completed successfully, accept
                  // the exclude_rect as is.
               }
               req = new GWIS_Checkout_Versioned_Items(
                     item_type_str,
                     rev_cur,
                     buddy_ct,
                     query_filters,
                     update_req,
                     resp_items,
                     callback_load,
                     callback_fail);
               if (link_type_attc !== null) {
                  req.attc_type = link_type_attc;
               }
               if (link_type_feat !== null) {
                  req.feat_type = link_type_feat;
               }
               reqs.push(req);
            }
         }

         return reqs;
      }

      // C.f. gwis_fetch_rev_create
      protected function gwis_revs_get_grac(
         control_type:String,
         control_context:String,
         grac:Grac_Manager,
         exclude_static:Boolean=false) :Array
      {
         var req:GWIS_Grac_Get;
         var rev:utils.rev_spec.Base;
         var revs:Array;
         var resp_items:Array = null;
         var buddy_ct:Counter = null;
         var reqs:Array = new Array();

         if (this.rev is utils.rev_spec.Diff) {
            var diffr:utils.rev_spec.Diff = (this.rev as utils.rev_spec.Diff);
            // Diff request: issue three GWIS_Base requests, one for each type.
            revs = [
               diffr.clone(utils.rev_spec.Diff.OLD),
               diffr.clone(utils.rev_spec.Diff.NEW),];
            // Route manip. adds exclude_static.
            if (!exclude_static) {
               revs.push(diffr.clone(utils.rev_spec.Diff.STATIC));
            }
         }
         else {
            // one request per type
            revs = [this.rev,];
         }

         if (this.rev is utils.rev_spec.Diff) {
            resp_items = new Array();
            // Set the buddy count, which means we don't process any of
            // these request responses until all responses are received.
            buddy_ct = new Counter(revs.length); // i.e., revs.length == 3;
         }
         // Currently, this fcn. is just used to get
         // control_type='group_membership' and control_context='user'
         for each (rev in revs) {
            req = new GWIS_Grac_Get(this, control_type, control_context,
                                    rev, grac, resp_items, buddy_ct);
            reqs.push(req);
         }

        return reqs;
      }

   }
}


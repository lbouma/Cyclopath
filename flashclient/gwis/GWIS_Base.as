/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This file contains the GWIS_Base interface code.

package gwis {

   import flash.errors.IOError;
   import flash.events.Event;
   import flash.events.IEventDispatcher;
   import flash.events.IOErrorEvent;
   import flash.events.HTTPStatusEvent;
   import flash.events.SecurityErrorEvent;
   import flash.events.TimerEvent;
   import flash.net.URLLoader;
   import flash.net.URLRequest;
   import flash.net.URLRequestMethod;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import mx.controls.Alert;
   import mx.core.UIComponent;
   import mx.managers.PopUpManager;

   import grax.Deep_Link;
   import gwis.update.Update_Base;
   import gwis.update.Update_Branch;
   import gwis.update.Update_User;
   import gwis.utils.FileReference_Wrap;
   import gwis.utils.Query_Filters;
   import utils.misc.Delayed_Setter;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.base.UI;

   // NOTE: In pyserver, the equivalent GWIS source code is located under
   //       /gwis/command/*, unlike in flashclient, where it's /gwis/GWIS_*.

   public class GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GWIS_Base');

      // *** Class variables

      // The set of requests which failed but should be retried.
      protected static var retry_needed:Set_UUID = new Set_UUID();

      // True if we've griped about server maintenance since the last fetch().
      // This is here to avoid a flurry of stacked gripe windows, as requests
      // often are made in groups.
      protected static var maint_griped:Boolean;

      // Similar for griping about authfailban problems. Public so that
      // Delayed_Setter can access it.
      public static var authfailban_griped:Boolean;

      // This is a counter to give each request a unique ID.
      protected static var id_next:int = 1;

      // Use a Set rather than an Array so we can use "x in y".
      protected static const trumped_by_update_user_or_branch:Set_UUID
         = new Set_UUID([Update_User,
                         Update_Branch,
                         // no: Update_Revision
                         // no: Update_Supplemental
                         ]);

      protected static const trumped_by_update_user:Set_UUID
         = new Set_UUID([Update_User,
                         // no: Update_Branch
                         // no: Update_Revision
                         // no: Update_Supplemental
                         ]);

      protected static const trumped_by_nothing:Set_UUID = new Set_UUID();

      // *** Instance members

      protected var canceled_:Boolean = false;

      // URL request objects
      protected var more_url_:String;
      protected var req:URLRequest;
      protected var loader:URLLoader;

      // When the fetch started
      protected var start_time:int;

      // If true, the throbber should run while this request is outstanding.
      public var throb:Boolean;

      // So-called "Waiting" popup.
      // BUG nnnn: Says "Loading..." and use inline spinning icon in panels
      //           and don't use modal popup.
      public var popup_enabled:Boolean;
      public var gwis_active_alert:UIComponent;

      // Timer to go off when the request times out.
      public var timer:Timer;

      // Each request has its own id (used by developers to debug)
      protected var id:int;

      // Each request has its own XML payload
      protected var data:XML;

      // FIXME: Create Bug: Serialize; don't send mult unnecessary requests
      // A pointer to the Map Update object, which serializes GWIS requests.
      protected var update_req:Update_Base;

      public var query_filters:Query_Filters;

      // We store the branch_id in case another request changes branches before
      // this request completes.
      protected var branch_id:int = 0;

      // This class encourages use of the callback to handle processing of the
      // response. This reduces coupling. That is, keep your application logic
      // where it belongs (i.e., the network stack can unpack the GWIS
      // response, but further processing should be done in, e.g., the item
      // classes).
      protected var callback_load:Function;
      // NOTE: callback_fail is only on GWIS failure, not on network failure.
      protected var callback_fail:Function;
      public var caller_data:*;

      // For Commit, if there's a problem making the XML:
      protected var pre_canceled:Boolean = false;

      // A few commands work on existing items, and even fewer callers of those
      // commands would like to remember that collection of items.
      public var items_in_request:Dictionary = null;

      // *** Constructor

      // Subclasses will probably define a more complex constructor that
      // builds the URL. However, they must take care to call super() at the
      // *end* of that constructor (after they have built url and data).
      public function GWIS_Base(
         url:String,
         data:XML=null,
         throb:Boolean=true,
         query_filters:Query_Filters=null,
         update_req:Update_Base=null,
         callback_load:Function=null,
         callback_fail:Function=null,
         caller_data:*=null) :void
      {
         super();

         this.more_url_ = '';

         //this.more_url_ += '&v=' + Conf.gwis_version;
         this.more_url_ += '&gwv=' + Conf.gwis_version;
         //this.more_url_ += '&gwis_version=' + Conf.gwis_version;

         // NOTE: this.req gets overwrit in finalize.
         this.req = new URLRequest(url);
         this.data = data;
         this.id = id_next++;

         this.update_req = update_req;

         this.throb = throb;

         if (query_filters === null) {
            query_filters = new Query_Filters();
         }
         this.query_filters = query_filters;

         this.callback_load = callback_load;
         this.callback_fail = callback_fail;
         this.caller_data = caller_data;

         // The use of branch_id_to_load is a tab hacky, but it's the best
         // (laziest) way to communicate to GWIS that we're changing branches.
         // Otherwise, the active_branch should be set.
         this.branch_id = G.item_mgr.branch_id_to_load;
         if (G.item_mgr.active_branch !== null) {
            m4_ASSERT(this.branch_id == 0);
            this.branch_id = G.item_mgr.active_branch.stack_id;
         }
      }

      // ***

      //
      public function toString() :String
      {
         return ('gwis' + this.id + ' ' + Introspect.get_constructor(this));
      }

      //
      public function get gwis_id() :String
      {
         return 'gwis' + this.id;
      }

      // *** Static methods

      //
      public static function retry_all() :void
      {
         m4_DEBUG('retry_all');

         m4_ASSERT(false); // Deprecated. With the Update classes, this is too
                           // messy/hard. See: requests_add_request, which
                           // expects certain GWIS requests to be part of
                           // a list of requests that triggers something
                           // when they all complete, expect that the Update
                           // has already dealt with this command (which,
                           // incidentally, came back failed). It really
                           // feels like we shouldn't retry failed GWIS
                           // commands but should rather create new ones.

         var o:GWIS_Base;
         for each (o in GWIS_Base.retry_needed) {
            // 2013.05.12: Don't forget to call finalize again, so that the new
            // token is used -- otherwise we'll forever be in a cycle of
            // resending the old requests with the old, stale token. To test,
            // log in as a registered user with the 'remember me' button
            // checked. Clear tokens from the db: delete from user__token;
            // Refresh your browser. You'll will be prompted for a password.
            // Enter it, and the popup goes away for a sec. but reappears.
            // What's happening is the GWIS requests that get resent don't
            // have the correct token, so 'badtoken' is again received.
            // Call finalize, which resets this.req.data using creds_set.
            o.finalize();
            // Now we can send the GWIS request, which has the new token.
            o.fetch();
         }

         GWIS_Base.retry_needed = new Set_UUID();
      }

      // *** Event handlers

      //
      public function on_cancel_cleanup() :void
      {
         m4_DEBUG('on_cancel_cleanup:', this.toString());
         // Derived classes should handle, if they care.
      }

      //
      protected function on_complete(ev:Event) :void
      {
         // Strip the browid and sessid from the URL for pretty-printing.
         m4_DEBUG('on_complete:', this.toString());
         m4_DEBUG(' .. ', this.url_stripped);

         // bytesTotal is total no. of bytes in downloaded data, or 0 while
         // loading or if missing Content-Length header
         // 2013.04.08: this.loader.bytesTotal always seems to be zero....
         // bytesLoaded is no. bytes loaded thus far during the load operation
         m4_DEBUG3('^^^ duration:', (G.now() - this.start_time), 'ms for',
                   this.loader.bytesLoaded, 'bytes loaded (',
                   this.loader.bytesTotal, ' total)');

         this.cleanup();

         var processed_data:Boolean = false;
         processed_data = this.data_process(this.loader.data);

         // If !processed_data, server returned an error, and we alerted user
         if (!processed_data) {
            m4_WARNING2('on_complete: data_process failed: ev.type:', ev.type,
                        '/ :', ev.toString());
         }

         if (this.update_req !== null) {
            // If managed by Update_Base, say we're ready to be processed.
            m4_TALKY('on_complete: Calling gwis_complete_schedule');
            this.update_req.gwis_complete_schedule(
               this, processed_data, this.gwis_complete_callback, null);
         }
         // else, this command is not part of an update_* grouping,
         //       and the caller just called gwis_cmd.fetch() and not
         //       update_supplemental() to start this command.

         m4_TALKY('on_complete: done');
      }

      // Cleanup after IO errors on_io_error, on_security_error, and on_timeout
      protected function on_error_cleanup() :void
      {
         m4_WARNING('on_error_cleanup: this:', this.toString(), this.req.url);
         // Tell the owning Update_Base object that this network
         // request is complete (because it was canceled). We don't worry
         // about re-sending or re-starting the request: that's either the
         // responsibility of Update_Manager, or the responsibility of the
         // user.
         if (this.update_req !== null) {
            var req_success:Boolean = false;
            var callback:Function = null;
            // FIXME [aa] Resend the request? Force user to reload?
            m4_DEBUG('on_error_cleanup: Calling gwis_complete_schedule');
            this.update_req.gwis_complete_schedule(
               this, req_success, callback, null);
         }
         // See if the caller had set up a callback_fail handler.
         if (this.callback_fail !== null) {
            m4_DEBUG('on_error_cleanup: calling callback_fail');
            var rset:XML = null;
            this.callback_fail(this, rset);
         }
         // Cleanup the popup.
         this.active_alert_dismiss();
      }

      //
      protected function on_io_error(ev:IOErrorEvent) :void
      {
         this.cleanup();

         this.throbber_release();

         // 2012.08.16: The events named 'error/gwis/*' used to be (in CcpV1)
         //             named 'error/wfs/*', so just know that if you're ever
         //             digging through the flashclient event table.

         // FIXME: Really log an event? The log event is that the last request
         //        failed... which seems silly: pyserver should have already
         //        logged the failure.
         G.sl.event('error/gwis/io', {url: this.req.url, msg: ev.text});

         // BUG 2715: Better errors: IOErrorEvent only happens when the HTTP
         // response code says there was a problem and not when the actual
         // request fails (I know, I know, [lb] says, this is weird: why
         // doesn't Flex name the event HTTPErrorEvent? an IOErrorEvent
         // implies to me that a network problem occurred, not that a protocol
         // error happened...).
         //
         // Anyway, point is: If pyserver crashes but doesn't catch the error,
         // Apache (well, mod_python) returns a string containing the error
         // message, and our completion routine is called. If apache is
         // restarted while pyserver is handling a request, Apache just sends a
         // TCP/IP FIN/ACK with no data, and our completion route is called.
         // If pyserver responds with a HTTP response code that's not
         // HTTP_HAPPY, I mean, 200 OK, then Flex triggers the IOErrorEvent
         // callback. (And note the [lb] isn't sure what triggers the third
         // event, SecurityErrorEvent.)
         //
         // Here's the way it works: If pyserver runs into a problem with the
         // request (which is the client's fault), pyserver returns a
         // gwis_error xml packet, which flashclient handles normally.
         // But if pyserver crashes unexpectedly, a try/except block catches
         // the exception, logs an error, and returns 400 Bad Request
         // (HTTP_BAD_REQUEST). The definition of this error is "The request
         // could not be understood by the server due to malformed syntax. The
         // client SHOULD NOT repeat the request without modifications." This
         // is not quite what happened (pyserver crashed) but it's the closest
         // in meaning of any of the HTTP response codes
         // (http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html) and the
         // latter part of the definition -- SHOULD NOT repeat the request --
         // is at least Very True.
         //
         // Anyway, long story longer, HTTP_BAD_REQUEST is what ends up here,
         // as an IOErrorEvent. So IOErrorEvent means the request got to the
         // server and got a response, even though in most application
         // libraries, an I/O error usually means there was a network problem
         // and not a protocol error... but maybe that's just how URLRequest
         // runs.
         //
         // So in earlier versions (it now being 2012.08.16) this error was
         // wrong: it suggested that the user check their network connection.
         // But that's not going to help. What's going to help is us fixing
         // pyserver.
         //
         // NOTE: [lb] tested ev.text and ev.type (and tried ev.errorID, which
         //       is documented but doesn't compile).
         // text: "Error #2032: Stream Error. URL: http://ccpv2/gwis?rqst=..."
         // type: "ioError"
         m4_WARNING('on_io_error: text:', ev.text, 'type:', ev.type);

         this.alert_big_problem();

         // Let the derived classes cleanup.
         this.on_error_cleanup();
      }

      //
      protected function alert_big_problem() :void
      {
         var alert_name:String = 'Big problem.'
         var do_alert:Boolean = UI.throbber_error_register(alert_name);
         if (do_alert) {
            UI.alert_show_roomy(
               'The Cyclopath server had a Big Problem.\n\n'
               + 'Please do not worry: This is not your fault.\n\n'
               + 'We apologize for the inconvenience. Our developers have been'
               + ' notified of the problem. Please contact us at '
               + Conf.instance_info_email
               + ' if you would like more information.\n\n'
               + 'In the meantime, try not to do what you just did '
               + '(or email us and tell us what you just did '
               + 'and we will try to fix it sooner! =).',
               'Uh oh! Our Server Had a Problem!');
         }
      }

      // BUG 0340: In earlier testing this event didn't seem to give us
      //           anything worthwhile; however, it's active because it might
      //           give us a handle on the request disappearance bug.
      //protected function on_http_status(ev:HTTPStatusEvent) :void
      //{
      //   m4_DEBUG('HTTP Status event', ev.status, ':', this.toString());
      //}

      //
      // EXPLAIN: What triggers this?
      protected function on_security_error(ev:SecurityErrorEvent) :void
      {
         this.cleanup();
         this.throbber_release();
         throw new Error('Security error:\n\n' + ev.text);
         // Let the derived classes cleanup
         this.on_error_cleanup();
      }

      //
      protected function on_timeout(ev:TimerEvent) :void
      {
         m4_WARNING('GWIS_Base timeout:', this.toString(), this.req.url);
         // Tell the user
         var alert_name:String = 'Timedout.'
         var do_alert:Boolean = UI.throbber_error_register(alert_name);
         if (do_alert) {
            UI.alert_show_roomy(
               'The response from the server timed out. '
               + 'Please check your network connections.\n\n'
               + 'If this problem persists and other websites work okay, '
               + 'please contact us so we can look into the problem: '
               + 'send us an email at ' + Conf.instance_info_email + '.',
               'Timeout waiting for response');
         }
         // Log the timed-out event. NOTE If a log request times out, we
         // shouldn't be executing this code (see GWIS_Log_Put.as)!
         G.sl.event('error/gwis/timeout', {url: this.req.url});
         // Stop the throbber and cleanup
         this.cancel();
      }

      // *** Instance Methods

      //
      public function get allow_overlapped_requests() :Boolean
      {
         // If a cmd. can be run in parallel with similar requests, a derived
         // class should return true. E.g., on a paginated screen, doing a
         // one-page look-ahead so user doesn't have to wait when clicking Next
         return false;
      }

      //
      public function set allow_overlapped_requests(allow_it:Boolean) :void
      {
         m4_ASSERT(false);
      }

      // Cancel the request.
      public function cancel() :void
      {
         if (this.canceled_) {
            m4_DEBUG('Ignoring superfluous cancel request');
         }
         else {
            // Kinda hacky check to see if request is outstanding
            // FIXME Do we want to set a canceled_ flag or anything, so
            //       we don't process any results?
            m4_DEBUG('Canceling GWIS_Base command:', this);
            if ((this.timer !== null) && (this.timer.running)) {
               try {
                  this.loader.close();
                  this.cleanup();
                  this.throbber_release();
               }
               catch (e:IOError) {
                  // Error #2029: This URLStream object does not have an open
                  // stream. This happens when the a Popup is open and a
                  // request fails, because both the failed request and the
                  // cancel button call this.
                  //
                  // FIXME: I[rp]'d prefer to check if the loader hasn't
                  // already been closed (i.e., ask permission model),
                  // but I don't see a way to do that and don't feel like
                  // implementing it myself.
               }
            }
            // Call the cleanup handler, which notifies the owning GWIS_Update
            // object that this request is "complete" (here meaning,
            // "canceled"). We make the call here and not in the prior control
            // block because a GWIS_Base object can still be outstanding even
            // if no URLStream exists for it.
            this.on_error_cleanup();
            // All done
            this.canceled_ = true;
         }
      }

      //
      public function get cancelable() :Boolean
      {
         return false;
      }

      //
      public function set cancelable(cancellable:Boolean) :void
      {
         m4_ASSERT(false);
      }

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
         this.cancel();
      }

      //
      public function configure(update_req:Update_Base) :void
      {
         m4_DEBUG('configure: update_req:', update_req);
         this.update_req = update_req;
      }

      // Start a file download with FileReference_Wrap, and return the
      // FileReference_Wrap instance that is being used for this request.
      public function download_file(default_name:String=null)
         :FileReference_Wrap
      {
         var file_ref:FileReference_Wrap
            = new FileReference_Wrap(this, default_name);
         this.finalize();
         file_ref.download();
         return file_ref;
      }

      //
      public function get_req() :URLRequest
      {
         return this.req;
      }

      // This fcn. is called by the Update classes to discard requests that are
      // redundant. Derived classes should override as appropriate.
      public function equals(other:GWIS_Base) :Boolean
      {
         var equal:Boolean = false;
         m4_ASSERT(this !== other); // Should use ===, not this fcn., to test
         /* Because the finalize fcn. is called in fetch(), we can't simply
            compare url, more_url, and data. We have to return false here and
            rely on the derived classes to detect equality. */
         equal = (   (this.query_filters.equals(other.query_filters))
                  && (this.branch_id == other.branch_id)
                  && (this.canceled == other.canceled));
         // m4_VERBOSE('equals?', this, '/', other, '/', equal);
         m4_VERBOSE('equals?:', equal);
         m4_VERBOSE(' ..  this:', this);
         m4_VERBOSE(' .. other:', other);
         return equal;
      }

      // Begin the HTTP fetch. When the operation completes, the callback
      // method in a subclass calls the map object to add the new data. The
      // map object will not be notified if the request fails.
      public function fetch() :void
      {
         if (!this.pre_canceled) {
            this.fetch_impl();
         }
         else {
            this.cancel();
         }
      }

      //
      protected function fetch_impl(gwis_timeout:int=0) :void
      {
         GWIS_Base.maint_griped = false;
         this.finalize();
         this.loader = new URLLoader();

         // Configure event listeners.
         // CAVEAT: If pyserver crashes and Apache cleans up, Apache returns
         //         an empty response, so the Complete event gets called. The
         //         IOErrorEvent is used if pyserver catches an unexpected
         //         error and returns HTTP_BAD_REQUEST deliberately. Lastly,
         //         if there's a network error, we also get an empty response
         //         via the Complete event.
         this.loader.addEventListener(Event.COMPLETE,
                                      this.on_complete);
         // Pre-2010 NOTE: HTTPStatusEvent doesn't seem to work -- it gives a
         //                status of 0, not 200.
         //    this.loader.addEventListener(HTTPStatusEvent.HTTP_STATUS,
         //                                 this.on_http_status);
         this.loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,
                                      this.on_security_error);
         this.loader.addEventListener(IOErrorEvent.IO_ERROR,
                                      this.on_io_error);

         // Start timeout clock
         if (gwis_timeout == 0) {
            gwis_timeout = Conf_Instance.gwis_timeout;
         }
         this.timer = new Timer(gwis_timeout * 1000, 1);
         this.timer.addEventListener(TimerEvent.TIMER, this.on_timeout,
                                     false, 0, true);
         this.timer.start();

         // Initiate request.

         if (Logging.get_level_key('DEBUG') >= GWIS_Base.log.current_level) {
            m4_DEBUG('GWIS_Base fetch:', this.toString());
            m4_DEBUG('            url:', this.url_stripped);
            //m4_DEBUG('  >> payload:');
            //m4_DEBUG(this.data.toXMLString());
            var xml_string:String = this.data.toXMLString();
            for each (var xml_line:String in xml_string.split('\n')) {
               m4_DEBUG('        payload:', xml_line);
            }
         }

         this.start_time = G.now();
         this.loader.load(this.req);
         this.throbber_attach();
      }

      // Processes a GWIS_Base response packet. May return false if processing
      // is taking too long and we should use callLater to finish processing.
      public function gwis_complete_callback() :Boolean
      {
         // No-op; for descendants to use
         m4_VERBOSE('gwis_complete_callback');
         return true;
      }

      //
      public function is_similar(other:GWIS_Base) :Boolean
      {
         return (   Introspect.get_constructor(this)
                 == Introspect.get_constructor(other));
      }

      //
      public function is_trumped_by(update_class:Class) :Boolean
      {
         var is_trumped:Boolean = true;
         if ((this.trump_list.length > 0)
             && !(this.trump_list.is_member(update_class))) {
            is_trumped = false;
         }
         return is_trumped;
      }

      //
      protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_update_user_or_branch;
      }

      // Register an outstanding HTTP request with the throbber. The throbber
      // runs so long as one or more requests are being processed. Note that
      // some requests occur 'silently', i.e., they don't cause the throbber
      // to throb.
      public function throbber_attach() :void
      {
         if (this.throb) {
            UI.throbberers_increment(this);
         }
      }

      // De-register with the throbber, either because the HTTP was completed,
      // or because the request timed-out or failed due to another error.
      public function throbber_release() :void
      {
         if (this.throb) {
            //m4_DEBUG('==++== THROBBERS / throbber_release');
            UI.throbberers_decrement(this);
         }
      }

      //
      public function get url() :String
      {
         return this.req.url;
      }

      //
      public function get url_stripped() :String
      {
         var url_stripped:String = this.req.url;
         url_stripped = url_stripped.replace(/\&browid=([-0-9A-Z]+)/, '');
         url_stripped = url_stripped.replace(/\&sessid=([-0-9A-Z]+)/, '');
         return url_stripped;
      }

      // *** Other methods

      // Note: does _not_ stop the throbber.
      protected function cleanup() :void
      {
         m4_TALKY('cleanup:', this.toString());
         m4_TALKY(' .. ', this.url_stripped);
         // Manually remove listeners since they're not weak references.
         this.loader.removeEventListener(Event.COMPLETE, this.on_complete);
         // See NOTE above -- HTTPStatusEvent doesn't seem to work right.
         //    this.loader.removeEventListener(HTTPStatusEvent.HTTP_STATUS,
         //                                    this.on_http_status);
         this.loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,
                                         this.on_security_error);
         this.loader.removeEventListener(IOErrorEvent.IO_ERROR,
                                         this.on_io_error);
         if (this.timer !== null) {
            this.timer.stop();
            // NOTE: timer still uses a weak reference, so we don't remove the
            // listener.
            // NO: this.timer.removeEventListener(TimerEvent.TIMER,
            //                                    this.on_timeout);
            // NO: this.timer = null;
         }
         // Cleanup the popup.
         this.active_alert_dismiss();
      }

      //
      protected function creds_set() :void
      {
         m4_DEBUG('creds_set: G.user.token:', G.user.token);
         if (G.user.logged_in) {
            this.data.metadata.user
               = <user name={G.user.username} token={G.user.token} />;
         }
         else {
            delete this.data.metadata.user;
         }
      }

      // Parse the data blob. Pass it on for further processing if it smells
      // good; otherwise, throw an error.
      protected function data_process(data:*) :Boolean
      {
         var callback_fcn:Function;
         var processed_okay:Boolean = false;

         // DEVS: This is code to debug cross-domain developing
         //       (i.e., debugging flashclient using fdb on Windows).
         /*/
         var url_re:RegExp = /^http:\/\/huffy.cs.umn.edu:8081\/gwis\?rqst=checkout&ityp=link_value&atyp=annotation&rev=19169&brid=2421567&gwv=3&/;
         m4_DEBUG('HERE!!!!!!!!!!!!!!!!');
         //
         m4_DEBUG('data_process: this.req.url:', this.req.url);
         m4_DEBUG2(' >> type(this.req.url):',
                   Introspect.get_constructor(this.req.url));
         m4_DEBUG(' >> this.req.url.length:', this.req.url.length);
         //
         if (url_re.test(this.req.url)) {
            m4_DEBUG('data_process: break_here');
            G.break_here();
         }
         /*/

         // 2012.08.16: Seeing a weird error. I left an error message open for
         // a while. So maybe our internal request timeout fired, so an unknown
         // Flex timeout fired.
         // "TypeError: Error #1088: The markup in the document following the
         //                          root element must be well-formed."
         // We're probably not checking that data is actually set...
         var xml:XML = new XML();
         if (data !== null) {
            try {
               xml = new XML(data);
            }
            catch (e:TypeError) {
               // 2012.08.16: [lb] notes how weird this error is (and why it
               // shouldn't happen in practice). If pyserver doesn't handle the
               // apache request properly, e.g., if in gwis_mod_python.py we
               // just throw an assert, apache prints a MOD_PYTHON ERROR to
               // stdout, along with the pyserver stack trace, and that's
               // what's sent to flashclient. But flashclient sits on the
               // response, since there's no legit end-of-message; it's not
               // until our internal timer fires that we timeout and try to
               // process the message... and then we end up here, not with xml
               // data, but with a MOD_PYTHON ERROR message and a Python stack
               // trace (see gwis_mod_python.py for more notes and an example
               // of the error message that mod_python makes for us).
               //
               // Anyway, we shouldn't have to worry in practice: pyserver
               // catches all of its errors, so this case should never happen.
               m4_ERROR('data_process: TypeError:', e.toString());
               m4_ERROR('data_process: xml data:', data);
            }
         }
         else {
            m4_ERROR('data_process: data is null');
         }

         // MAGIC_NUMBER: 'data' is set by pyserver as the XML doc name.
         //m4_DEBUG('data_process: xml.name():', xml.name());
         if (xml.name() == 'data') {
            callback_fcn = this.callback_load;
            this.resultset_process(xml);
            this.throbber_release();
            processed_okay = true;
         }
         else {
            // Something went wrong.
            callback_fcn = this.callback_fail;
            this.data_process_error(data, xml);
         }
         // If the caller specified a callback fcn., callitback.
         if (callback_fcn !== null) {
            m4_DEBUG('data_process: calling callback_fcn: this:', this);
            callback_fcn(this, xml);
         }
         return processed_okay;
      }

      //
      protected function data_process_error(data:*, xml:XML) :void
      {
         m4_WARNING2('data_process_error: Server returned error: gwis:', this,
                     '/ tag:', xml.@tag, '/ data:', data);

         this.throbber_release();

         if (xml.name() == 'gwis_error') {
            switch (String(xml.@tag)) {
            case 'badtoken':
               // Bad token -- reauthenticate and try again.
               if (!(G.user.reauthenticating)) {
                  G.user.reauthenticate();
               }
               /* Note: this add() call used to be protected with an
                  'if (!(this is GWIS_Log_Put))'. This was removed with bug
                  1208, which reorganized logging. Michael's reasoning for
                  this was that previously (Apache access.log logging) the
                  log event was stored before entering Cyclopath code - and
                  thus shouldn't be repeated - but now it is stored inside
                  Cyclopath code, won't hit the database unless
                  authentication succeeds, and thus needs to be repeated. */
               GWIS_Base.retry_needed.add(this);
               break;
            case 'maint':
               // Server is in maintenance mode.
               if (!GWIS_Base.maint_griped) {
                  GWIS_Base.maint_griped = true;
                  UI.image_alert('Server is down for maintenance',
                                 Conf.maint_img_url);
               }
               break;
            case 'authfailban':
               // IP is banned due to excessive auth failures - pass
               // through the server's error message
               // COUPLING: Base class checking what type of derived class
               //           it is.
               if ((!authfailban_griped) || (this is GWIS_Handshake)) {
                  authfailban_griped = true;
                  Delayed_Setter.set(GWIS_Base,
                                     'authfailban_griped',
                                     false, 10);
                  try {
                     // FIXME: This hack keeps the app from locking up
                     // because the login window is not enabled.
                     m4_DEBUG('authfailban: setting login_window.enabled');
                     G.user.login_window.enabled = true;
                  }
                  catch (e:Error) {
                     // assume login window not present
                  }
                  // NOTE: Using xml.@msg instead of xml.text().
                  // MAYBE: Use UI.alert_show_roomy here?
                  Alert.show(xml.@msg, 'Error accessing server');
               }
               break;
            default:
               // GWIS_Error. Report it.
               // NOTE: Using xml.@msg, not xml.text().
               // 2014.05.07: Why are we logging back to the server the same
               //             error that it just sent us??
               //  ?? Don't do this: this.error_log(xml.@msg);
               this.error_present(xml.@msg);
            }
         }

         // BUG nnnn: Handle grac_error XML. (I.e., when a commit fails,
         //           pyserver sends a list of problems (and associated stack
         //           IDs, if the problems relate to items, so flashclient
         //           can help the user fix the problems). Usually, the
         //           problems are branch conflicts, since flashclient does
         //           a good job sending a proper request otherwise.)

         // 2012.08.18: The new 'gwis_fatal' error is reserved for programmer
         //             errors that pyserver caught but cannot recover from.
         //             And there's really nothing flashclient can do about
         //             it, either.
         else if (xml.name() == 'gwis_fatal') {
            // Yikes. pyserver hosed itself.
            this.alert_big_problem();
         }

         else {
            // Who knows. [rp]
            if (data.length > 0) {
               // 2012.08.16: [lb] This should never happen; pyserver catches
               //             all errors and sends back a gwis_error or
               //             gwis_fatal packet now, so this should only be
               //             caused by third-party software or hardware (i.e.,
               //             Apache or the Internet).
               // 2014.05.07: Don't log server errors back to server; seems
               //             redundant.
               //  Don't bother: this.error_log('Bad response: ' + data);
               this.error_present('Bad response from server:\n\n' + data);
            }
            else {
               // 2012.08.16: This is a network error, and not a Cyclopath
               // failure. If you restart Apache while a request is pending,
               // flashclient uses Event.COMPLETE and not
               // IOErrorEvent.IO_ERROR. And nowadays, pyserver catches
               // all of its error and makes a gwis_fatal packet so this case
               // should always mean that there was a network problem (usually
               // just a network disconnect on the server end of the link).
               // 2014.05.07: This also means that error_log probably fails,
               // since we're logging the error to the same server that did
               // not respond... unless the no-response was because pyserver
               // crashed... anyway, in either case, logging a server error
               // from the client seems silly, but this is old code:
               this.error_log('No response.');
               // BUG 2715: Better errors: 2012.08.16: We used to call
               // error_present() here, but that might print the URL to the
               // dialog... but the URL doesn't really matter for timeouts,
               // does it? All URLs should be timing out.
               var alert_name:String = 'No response.'
               var do_alert:Boolean = UI.throbber_error_register(alert_name);
               if (do_alert) {
                  UI.alert_show_roomy(
                     'We are sorry, but there was no response from the server.'
                     + '\n\n'
                     + 'Cyclopath did not get a response from our server.'
                     + '\n\n'
                     + 'This sometimes means there was a problem with your '
                     + 'network connection (e.g., your computer lost its '
                     + 'connection to the Internet), but it could also '
                     + "mean it's our fault (e.g., a sleepy graduate student "
                     + 'spilled coffee on the server).'
                     + '\n\n'
                     + 'Please feel free to check back later or email us at '
                     + Conf.instance_info_email
                     + ' and we will help you out.\n',
                     'Uh Oh!');
               }
            }
         }
      }

      //
      protected function doc_empty() :XML
      {
         return <data><metadata/></data>;
      }

      // Send a log event detailing a gwis error
      protected function error_log(error_text:String) :void
      {
         // BUG nnnn: Does m4_ERROR (and m4_WARNING?) send an error log msg to
         //           pyserver? We don't want to do that here since we're
         //           reporting a GWIS or network error, so either the error is
         //           already logged, or there's not way to tell pyserver.
         // MAYBE:
         //    m4_ERROR('error_log: url:', this.req.url, '/ msg:', error_text);
         G.sl.event('error/gwis/server', {url: this.req.url, msg: error_text});
      }

      // Deal with a GWIS_Base error.
      protected function error_present(error_msg:String) :void
      {
         // MAYBE: Bug 2715: Better errors: Use throbber_error_register here?
         //
         // 2012.08.16: It seems silly to print the URL to the error dialog --
         // unless we expect the user to send us this string. Otherwise, it's
         // confusing and meaningless.
         //
         // BUG nnnn: Better errors: For now, using a developer switch to
         // decide whether to show URL; but the real solution might be to
         // have a "Show request" button or something that shows the URL, so
         // the user can copy and paste the URL to an email that they send us.

         var do_alert:Boolean = UI.throbber_error_register(error_msg);
         if (do_alert) {
            var error_text:String = error_msg;
            if (Conf_Instance.debug_alert_show_url) {
               error_text += '\n\nThe URL that failed was: ' + this.req.url;
            }
            // MAYBE: Use UI.alert_show_roomy here?
            Alert.show(error_text, 'Uh Oh!');
         }

         // The code used to throw an error, but we can recover from the error
         // and handle it ourselves. No need to tell Flash.
         // NO: throw new Error('GWIS Error: ' + this.req.url + '\n' + text);
      }

      // Finalize the GWIS_Base request's URLRequest object
      public function finalize(url:String=null) :void
      {
         // The url parameter is only set by a derived class's override of this
         // fcn., so users should be able to call finalize() multiple times on
         // a request. Not that we reuse GWIS commands or would otherwise need
         // to call finalize() more than once on a command.
         
         if (url === null) {
            url = '';
         }

         if (this.branch_id != 0) {
            url += '&brid=' + this.branch_id;
         }

         if (this.query_filters !== null) {
            m4_VERBOSE2('finalize: adding query_filters',
                        '/ this.data:', this.data);
            url = this.query_filters.url_append_filters(url);
            this.query_filters.xml_append_filters(this.data);
         }
         else {
            m4_ASSERT(false); // this.query_filters always set, right?
         }

         var more_url:String = url + this.more_url;

         // Finally, add the browid and sessid.
         // DEVS: Always append these last. When you're debugging, WireShark
         //       truncates URIs in the simple display, so it requires more
         //       clicks to see the entire URI, so keep the important stuff
         //       at the start of it.
         // 2012.09.19: [lb] isn't sure when browid is null, but it's set
         // during User.startup(),
         if (G.browid !== null) {
            more_url += '&browid=' + G.browid;
         }
         // Bug NNNN: The session ID is assigned by the server.
         if (G.sessid !== null) {
            more_url += '&sessid=' + G.sessid;
         }

         if (this.data !== null) {
            // BUG 1656: FIXME: This is debugging code related to bug 1656.
            // Tell the server whether we think we're sending a POST body.
            more_url += '&body=yes';
            // FIXME: try/except for bug 1656, to see if we're killing the
            // body somehow in here.
            try {
               this.creds_set();
               this.req.method = URLRequestMethod.POST;
               this.req.contentType = 'text/xml';
               this.req.data = this.data.toXMLString();
            }
            catch (e:Error) {
               m4_DEBUG('finalize: e:', e, '/ url:', url);
               // report two ways in case GWIS_Log_Put is not working
               // don't assert because that could change behavior
               G.sl.event('error/bug1656/exception', { msg: e.message });
               (new GWIS_Null('error/bug1656/exception')).fetch();
               throw e;
            }
         }

         m4_ASSERT(((this.data === null) && (this.req.data === null))
                   || ((this.data !== null) && (this.req.data !== null)));
         m4_ASSERT(((this.data === null) && (this.req.data === null))
                   || ((this.data !== null) && (this.req.data.length > 0)));
         m4_ASSERT((this.data === null) || (this.req.method == 'POST'));

         this.req.url = this.req.url + more_url;
      }

      //
      protected function get more_url() :String
      {
         return this.more_url_;
      }

      //
      protected function set more_url(more_url:String) :void
      {
         m4_ASSERT(false);
      }

      // Process the incoming result set.
      protected function resultset_process(rset:XML) :void
      {
         var s:String;

         // Basic checks.
         this.resultset_process_check_semiprotected(rset);
         this.resultset_process_check_server_version(rset);

         // BUG nnnn: The import job gets the revision lock,
         // and then it maybe runs for a long time. Is there
         // a reasonable way to inform other users who might
         // be editing the map? We could show a general banner
         // message, or we could wait until the user starts
         // editing and then show a message, or wait until
         // they try to commit. Currently, commit tries for
         // over a minute before user is told they may have
         // to wait to save.
         //?: this.resultset_process_check_server_superbusy(rset);

         // Check if saving is restricted for user or IP.
         this.resultset_process_bans(rset);

         // Check for email bouncing.
         if (rset.@bouncing.length() != 0) {
            G.user.gripe_bouncing_maybe(rset.@bouncing);
         }

         //// Deep link, if any; authentication state is checked inside go().
         // Statewide UI/Cycloplan: This doesn't work because load_deep_link
         // often sends a GWIS request, but Update_Revision will throw it away.
         // What you really want is Deep_Link.LOGGED_IN.
         //G.deep_link.load_deep_link(Deep_Link.AUTHENTICATED);

         // Cleanup the popup.
         this.active_alert_dismiss();
      }

      //
      protected function resultset_process_check_semiprotected(rset:XML) :void
      {
         // Check semi-protected.
         if ((Number(rset.@semiprotect) != 0) && !(G.semiprotect_griped)) {
            G.semiprotect_griped = true;
            UI.alert_show_roomy(
               'Cyclopath is in semi-protection mode. Only anonymous '
               + 'users and accounts younger than '
               + Number(rset.@semiprotect)
               + ' hours old cannot save public changes. '
               + 'You can still experiment with the editing tools, but you '
               + 'will not be able to save your changes.\n\n'
               + 'If you are logged in, you can also save private changes, '
               + 'such as ratings.',
               'Semi-protection note');
         }
      }

      //
      protected function resultset_process_check_server_version(rset:XML) :void
      {
         // Check server version. The major version is a String.
         // FIXME: Can you really save your work if the server was upgraded, or
         //        will you just see this same error message again? 2012.08.16.
         // EXPLAIN: Route reacions adds a check on G.initialized, but [lb] is
         //          unsure why. Did [mm] find a bug?
         if ((rset.@major != G.version_major)
             && (!(G.version_griped))
             && (G.initialized)) {
            // 2012.08.16: Don't tell the user to save unless we know they have
            //             a dirty map.
            var alert_msg:String = '';
            var save_text:String = '';
            if (G.item_mgr.contains_dirty_any) {
               alert_msg = 'Please save changes and reload your Web browser.'
               save_text = 'Note: Your map has unsaved changes. '
                           + 'To keep your changes, save the map now, '
                           + 'before refreshing.\n\n';
            }
            else {
               alert_msg = 'Please reload your Web browser.'
            }
            UI.alert_show_roomy(
               //
               alert_msg + '\n\n'
               //
               + "We've upgraded Cyclopath. Please reload your Web "
               + 'browser to get the latest bug fixes and new features.\n\n'
               //
               + save_text
               //
               + "To reload, press the browser's Refresh button "
               + 'or type F5 in the browser window. If that does '
               + 'not work, exit the browser and restart it.\n\n'
               //
               + 'We apologize for the inconvenience, but we do this '
               + 'occasionally to keep the excellent new features flowing.\n\n'
               //
               + 'Client software version: ' + G.version_major + '\n'
               + 'Server software version: ' + rset.@major,
               //
               'Server has been upgraded');
            G.version_griped = true;
         }
      }

      //
      protected function resultset_process_bans(rset:XML) :void
      {
         var pu_u:String = null;
         var fl_u:String = null;
         var pu_i:String = null;
         var fl_i:String = null;

         // Check for banned state of user/ip.
         if (rset.bans !== null) {
            if (rset.bans.@public_user.length() != 0) {
               pu_u = rset.bans.@public_user;
            }
            if (rset.bans.@full_user.length() != 0) {
               fl_u = rset.bans.@full_user;
            }
            if (rset.bans.@public_ip.length() != 0) {
               pu_i = rset.bans.@public_ip;
            }
            if (rset.bans.@full_ip.length() != 0) {
               fl_i = rset.bans.@full_ip;
            }

            G.user.gripe_ban_maybe(pu_u, fl_u, pu_i, fl_i);
         }
         delete rset.bans;
      }

      // ***

      //
      protected function url_base(request:String) :String
      {
         return (G.url_base + Conf.gwis_url + 'rqst=' + request);
      }

      // ***

      //
      protected function active_alert_dismiss() :void
      {
         if (this.popup_enabled) {
            if (this.gwis_active_alert !== null) {
               PopUpManager.removePopUp(this.gwis_active_alert);
            }
            this.gwis_active_alert = null;
         }
      }

   }
}


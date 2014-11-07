/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Utility class that manages file downloads from the server.  It makes
// sure that only 1 download is executed at a time.

package gwis.utils {

   import flash.errors.IllegalOperationError;
   import flash.errors.MemoryError;
   import flash.events.DataEvent;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.HTTPStatusEvent;
   import flash.events.ProgressEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.FileReference;
   import flash.net.URLRequest;
   import mx.collections.ArrayCollection;
   import mx.controls.Alert;
   import mx.utils.ArrayUtil;
   import mx.utils.UIDUtil;

   import gwis.GWIS_Base;
   import utils.misc.Logging;

   // CAVEATS: Flex limits the FileReference object in a number of ways. First,
   // the browse, download and upload operations cannot be overlapped using
   // multiple object instances. As a result, this caches uses a static Array
   // to gait access to these operations. Second, the aforementioned
   // operations are subject to Flex's "User-initiated action requirements",
   // which means that we can only call said operations from a button press,
   // for instance. That is, somewhere in the call stack needs to be a callback
   // function related to something the user did explicitly, like a button
   // press, or ever a keypress. (I think the intent is that you can't load an
   // invisible SWF widget in a Web page and start uploading from and
   // downloading to a user's computer. You could trick them with a misleading
   // Alert dialog, though, so the users still need to be somewhat... alert.)
   // Oh, geez, another keeper I just learned: browse() and upload() have to
   // be called in the same callback stack. I tried populating FileReference
   // first with a 'Browse' button, and then having the user click 'Upload',
   // but this doesn't work... so what's the alternative? Call the load() fcn.
   // instead of upload() and just load locally, and then send the loaded data?
   // Seems ridiculously complicated. For now, the browse() and upload() are a
   // packaged pair.

   public class FileReference_Wrap {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('__File_Ref_W');

      // Flash only supports one upload or download at a time. So using static
      // vars here is totally acceptable. Toatse.

      // queued download requests, elements are FileReference_Wrap instances
      // EXPLAIN: When do downloads get overlapped??
      protected static var queue:Array = new Array();
      // The active download, or null is nothing active. This must be set to
      // keep the file ref and its wrapper from the garbage collector.
      protected static var active:FileReference_Wrap;

      // *** Instance variables

      protected var gwis_req:GWIS_Base;
      protected var default_name:String;

      public var file_ref:FileReference;

      protected static var fref_noop:int = 0x0;
      protected static var fref_browse:int = 0x1;
      protected static var fref_download:int = 0x2;
      protected static var fref_upload:int = 0x4;
      //
      protected var fref_action:int;

      protected var callback_okay:Function;
      protected var callback_fail:Function;
      protected var type_filters:Array;

      public var upload_resp:String;

      protected var event_listeners:Array;

      // *** Constructor

      public function FileReference_Wrap(gwis_req:GWIS_Base,
                                         default_name:String=null)
      {
         this.gwis_req = gwis_req;
         this.default_name = default_name;
      }

      // *** Instance methods

      //
      public function cancel() :void
      {
         var collection:ArrayCollection;
         var index:int;

         m4_DEBUG('on_filer_cancel');

         if (this.file_ref === null) {
            // remove it from the queue
            index = ArrayUtil.getItemIndex(this, FileReference_Wrap.queue);
            if (index >= 0) {
               collection = new ArrayCollection(FileReference_Wrap.queue);
               collection.removeItemAt(index);
            }
         }
         else {
            // the file is actually downloading
            this.file_ref.cancel();
            this.cleanup(false);
         }
      }

      // Stops the throbber, resets active, and starts the next operation.
      protected function cleanup(succeeded:Boolean,
                                 do_kick:Boolean=true,
                                 do_dethrob:Boolean=true) :void
      {
         m4_DEBUG('on_filer_cleanup');
         if (do_dethrob) {
            this.gwis_req.throbber_release();
         }
         m4_ASSERT(FileReference_Wrap.active !== null);
         var entry:FileReference_Wrap = FileReference_Wrap.active;
         for each (var edef:Array in entry.event_listeners) {
            m4_VERBOSE('Removing listener:', edef[0]);
            entry.file_ref.removeEventListener(edef[0], edef[1]);
         }
         entry.file_ref = null;
         FileReference_Wrap.active = null;
         if (do_kick) {
            FileReference_Wrap.filer_kick();
         }
         if (succeeded) {
            if (this.callback_okay !== null) {
               this.callback_okay(this);
            }
         }
         else {
            if (this.callback_fail !== null) {
               this.callback_fail(this);
            }
         }
      }

      // *** User interface (browse, download, upload)

      //
      public function browse_upload(callback_okay:Function=null,
                                    callback_fail:Function=null,
                                    type_filters:Array=null)
         :void
      {
         this.type_filters = type_filters;
         this.wrap_action(FileReference_Wrap.fref_browse, callback_okay,
                                                          callback_fail);
      }

      // Queue up a download request for the given request url.
      // The default_name is the name presented to the user in their file
      // browser window. If throb is true, the throbber will spin while the
      // file is downloading.
      //
      // Only one download can be active at a time. If a download is active,
      // this function will queue the given request until it can become the
      // active download.
      public function download(callback_okay:Function=null,
                               callback_fail:Function=null) :void
      {
         this.wrap_action(FileReference_Wrap.fref_download, callback_okay,
                                                            callback_fail);
      }

      //
      protected function wrap_action(fref_action:int,
                                     callback_okay:Function=null,
                                     callback_fail:Function=null) :void
      {
         this.fref_action = fref_action;
         this.callback_okay = callback_okay;
         this.callback_fail = callback_fail;
         FileReference_Wrap.queue.push(this);
         FileReference_Wrap.filer_kick();
      }

      // *** Static class methods

      // Pop's an entry off of the queue and begins downloading.
      // Does nothing if active isn't null, or if queue is empty.
      protected static function filer_kick() :void
      {
         // Only start downloading if active is null and a download is queued.
         if ((FileReference_Wrap.active === null)
             && (FileReference_Wrap.queue.length > 0)) {

            var entry:FileReference_Wrap = FileReference_Wrap.queue.shift();

            entry.file_ref = new FileReference();

            // Setup event listeners.
            // FIXME: I think we register these redundantly the second and
            //        subsequent times we use the FileReference... but I don't
            //        think it hurts.

            // Per-action events:
            // browse()  : Select, Cancel
            // download(): Open, Progress, Complete, Cancel, Select,
            //             SecurityError, IOError
            // upload()  : Open, Progress, Complete, uploadCompleteData,
            //             SecurityError, HTTPStatus, httpResponseStatus,
            //             IOError
            m4_ASSERT(entry.event_listeners === null);
            entry.event_listeners = [
               [ Event.SELECT,         entry.on_filer_selected ],
               [ Event.CANCEL,         entry.on_filer_cancel ],
               [ Event.COMPLETE,       entry.on_filer_complete ],
               [ ProgressEvent.PROGRESS, entry.on_filer_load_progress ],
               [ HTTPStatusEvent.HTTP_STATUS,
                                       entry.on_filer_http_status ],
               [ IOErrorEvent.IO_ERROR, entry.on_filer_error_io ],
               [ SecurityErrorEvent.SECURITY_ERROR,
                                       entry.on_filer_error_security ],
               [ Event.OPEN,           entry.on_filer_open ],
               [ DataEvent.UPLOAD_COMPLETE_DATA,
                                       entry.on_filer_upload_complete_data ]];
               // I don't think our Flex supports this:
               //[ HTTPStatusEvent.HTTP_RESPONSE_STATUS,
               //                        entry.on_filer_http_response_status ]
            for each (var edef:Array in entry.event_listeners) {
               m4_VERBOSE('Adding listener:', edef[0]);
               entry.file_ref.addEventListener(edef[0], edef[1]);//, false, 0, true);
            }

            FileReference_Wrap.active = entry;
            FileReference_Wrap.process_active();
         }
      }

      //
      protected static function process_active() :void
      {
         var entry:FileReference_Wrap = FileReference_Wrap.active;
         var file_ref:FileReference = entry.file_ref;

         // Show the browse dialog or start an upload or download.
         var errored:Boolean = true;
         var alerted:Boolean = false;
         try {
            // If it's an upload, show the file browser first.
            if (entry.fref_action == FileReference_Wrap.fref_browse) {
               var dialog_opened:Boolean;
               // This function _blocks_. The SELECT event is called after
               // we exit this call stack.
               dialog_opened = file_ref.browse(entry.type_filters);
               m4_DEBUG('filer_kick: browse: dialog opend:', dialog_opened);
               m4_ASSERT(dialog_opened);
               // Return from the call stack and call upload() from the
               // select handler.
            }
            else {
               entry.gwis_req.finalize();
               var req:URLRequest = entry.gwis_req.get_req();
               // Start throbbing and start the upload or download.
               entry.gwis_req.throbber_attach();
               if (entry.fref_action == FileReference_Wrap.fref_download) {
                  file_ref.download(req, entry.default_name);
                  m4_DEBUG2('filer_kick: download started on',
                            entry.default_name);
               }
               else if (entry.fref_action == FileReference_Wrap.fref_upload) {
                  var test_upload:Boolean = false;
                  m4_DEBUG('filer_kick: default_name', entry.default_name);
                  if (entry.default_name === null) {
                     entry.default_name = 'Filedata';
                  }
                  file_ref.upload(req, entry.default_name, test_upload);
                  m4_DEBUG('filer_kick: upload started');
               }
               else {
                  m4_ASSERT(false); // Invalid code path.
               }
            }
            errored = false;
         }
         catch (e:IllegalOperationError) {
            m4_DEBUG('filer_kick: IllegalOperationError:', e.toString());
            m4_INFO(
               'filer_kick: user\'s flash client\'s mms.cfg prohibits frs');
            alerted = true;
            Alert.show(
               "Your Web browser or the browser's Flash plugin is configured "
               + "to prohibit file transfers. Please edit your browser's "
               + "configuration or edit Flash preferences to allow file "
               + "tranfers.",
               'Unable to handle files.');
         }
         catch (e:SecurityError) {
            m4_WARNING('filer_kick: SecurityError:', e.toString());
         }
         catch (e:ArgumentError) {
            m4_WARNING('filer_kick: ArgumentError:', e.toString());
         }
         catch (e:MemoryError) {
            m4_WARNING('filer_kick: MemoryError:', e.toString());
         }
         catch (e:Error) {
            m4_WARNING('filer_kick: Error:', e.toString());
         }
         if (errored) {
            m4_WARNING('filer_kick: errored');
            if (!alerted) {
               Alert.show(
                  'An unknown error occurred. The Cyclopath Team has been '
                  + 'notified of the problem. We will fix it shortly. Sorry '
                  + 'for the inconvenience! Please email '
                  + Conf.instance_info_email
                  + ' if you would like more information or more help.',
                  'Unable to process file.');
            }
            // NOTE: cleanup recursively calls this fcn., which shouldn't be
            //       a problem unless you have lots and lots of queued
            //       FileReference requests, which is highly unlikely.
            entry.cleanup(false);
         }
      }

      // *** Event listeners

      //
      protected function on_filer_selected(event:Event) :void
      {
         var file_ref:FileReference = FileReference(event.target);
         m4_DEBUG('on_filer_selected: name:', file_ref.name);
         m4_ASSERT(file_ref === this.file_ref);
         m4_ASSERT(FileReference_Wrap.active == this);
         m4_DEBUG('  >> this.fref_action:', this.fref_action);
         if (this.fref_action == FileReference_Wrap.fref_browse) {
            this.fref_action = FileReference_Wrap.fref_upload;
            FileReference_Wrap.process_active();
         }
         else {
            m4_ASSERT(this.fref_action == FileReference_Wrap.fref_download);
         }
      }

      //
      protected function on_filer_cancel(event:Event) :void
      {
         m4_DEBUG('on_filer_cancel');
         var succeeded:Boolean = false;
         var do_kick:Boolean = true;
         var do_dethrob:Boolean = true;
         if (this.fref_action == FileReference_Wrap.fref_browse) {
            // Don't de-throb, since we haven't attached yet. This happens when
            // user closes the file browser.
            do_dethrob = false;
         }
         this.cleanup(succeeded, do_kick, do_dethrob);
      }

      //
      protected function on_filer_complete(event:Event) :void
      {
         m4_DEBUG('on_filer_complete');
         if (this.fref_action == FileReference_Wrap.fref_download) {
            this.cleanup(true);
         }
         else {
            m4_ASSERT(this.fref_action == FileReference_Wrap.fref_upload);
            // We'll wait for on_filer_upload_complete_data.
         }
      }

      //
      protected function on_filer_load_progress(event:ProgressEvent) :void
      {
         m4_DEBUG('on_filer_load_progress');

         // FIXME: Show progress? Or is throbber enough?

         var file_ref:FileReference = FileReference(event.target);
         // FIXME: is file_ref same as this.file_ref?
         m4_DEBUG('  >> file_ref:', file_ref);
         m4_DEBUG('  >> this.file_ref:', this.file_ref);
         // event.bytesTotal is 0 on download? Maybe server has to send
         // filesize explicitly....
         // 2012.03.22: Now I'm seeing bytesTotal less than bytesLoaded
         //             name: gwis / bytesLoaded: 659439 / bytesTotal: 28738
         m4_DEBUG3('  >> name:', file_ref.name,
                   '/ bytesLoaded:', event.bytesLoaded,
                   '/ bytesTotal:', event.bytesTotal);

         /*/
         var file:FileReference = FileReference(event.target);
         var percentLoaded:Number = event.bytesLoaded/event.bytesTotal*100;
         m4_DEBUG("loaded: " percentLoaded "%");
         ProgresBar.mode = ProgressBarMode.MANUAL;
         ProgresBar.minimum = 0;
         ProgresBar.maximum = 100;
         ProgresBar.setProgress(percentLoaded,100);
         /*/
      }

      //
      protected function on_filer_http_status(event:HTTPStatusEvent) :void
      {
         m4_DEBUG2('on_filer_http_status:', event.status,
                   ':', this.gwis_req.get_req().url);
      }

      //
      protected function on_filer_error_io(event:IOErrorEvent) :void
      {
         m4_WARNING2('on_filer_error_io:', event.text,
                     ':', this.gwis_req.get_req().url);
         // BUG 2715: Better errors: Don't ask the user to submit a bug report.
         //           We can log the error ourself, can't we?
         Alert.show(
            event.text + '\n\n'
            + this.gwis_req.get_req().url + '\n\n'
            + 'You may have found a bug. '
            + 'Please email ' + Conf.instance_info_email + ' for help.',
            'Unknown I/O error downloading file');
         this.cleanup(false);
      }

      //
      protected function on_filer_error_security(event:SecurityErrorEvent)
         :void
      {
         m4_WARNING2('on_filer_error_security:', event.text,
                     ':', this.gwis_req.get_req().url);
         // NOTE: We don't start a new download.
         //       EXPLAIN: Why? Because everthing will have same error?
         var succeeded:Boolean = false;
         var do_kick:Boolean = false;
         this.cleanup(succeeded, do_kick);
         throw new Error('Security error:\n\n' + event.text);
      }

      //
      protected function on_filer_open(event:Event) :void
      {
         m4_DEBUG('on_filer_open');
      }

      //
      protected function on_filer_upload_complete_data(event:DataEvent) :void
      {
         // This is the response from the server.
         m4_DEBUG2('on_filer_upload_complete_data:', event.text,
                   '/ length:', event.data.length);
         // Store the response so the caller can get at it.
         this.upload_resp = event.text;
         var succeeded:Boolean = true;
         this.cleanup(succeeded);
      }

      //
      protected function on_filer_http_response_status(event:HTTPStatusEvent)
         :void
      {
         m4_DEBUG('on_filer_http_response_status:', event.status);
      }

   }
}


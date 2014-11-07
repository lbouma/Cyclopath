/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: As this class is used to report errors to the server, ignore
// transport errors in order to to avoid a recursive error loop.

package gwis {

   import flash.events.IOErrorEvent;
   import flash.events.TimerEvent;

   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_Log_Put extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LOG');

      // *** Constructor

      public function GWIS_Log_Put(events:Array)
      {
         var o:Object;

         var url:String = this.url_base('log');
         var doc:XML = this.doc_empty();

         for each (o in events) {
            doc.appendChild(xml_get(o));
            // FIXME: debug code for bug 1656 - add asserts to URL
            // because we're sometimes losing the body
            if (o.facility == 'error/assert') {
               url += '&assert=' + encodeURI(o.params.message);
            }
         }

         var throb:Boolean = false;
         super(url, doc, throb);
      }

      // *** Instance methods

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

      //
      override protected function error_log(text:String) :void
      {
         // Do nothing, same reason as for error_present: we don't want to end
         // up self-looping.
      }

      //
      override protected function error_present(text:String) :void
      {
         // Do nothing. See on_timeout; override the base GWIS_Base fcn. so we
         // don't log an error of this error and end up in a loop.
      }

      //
      override protected function on_io_error(ev:IOErrorEvent) :void
      {
         this.cleanup();
         this.throbber_release();
      }

      //
      override protected function on_timeout(ev:TimerEvent) :void
      {
         // Overrides the base GWIS_Base fcn. so that we don't try logging an
         // error of a failed attempt to log an error, lest we end up in a
         // loop.
         m4_WARNING('WARNING: GWIS_Log_Put timeout: ' + this.toString());
         // Cancel the request and cleanup
         this.cancel();
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_nothing;
      }

      // Create an XML blob from an event Object as defined in Log_S
      protected function xml_get(ev:Object) :XML
      {
         var event:XML = <event facility={ev.facility}
                                timestamp={ev.timestamp} />;
         var key:Object;
         if (ev.params !== null) {
            // add in key-value pairs
            for (key in ev.params) {
               event.appendChild(<param key={key.toString()}>
                                    {ev.params[key].toString()}
                                 </param>);
            }
         }
         return event;
      }

   }
}

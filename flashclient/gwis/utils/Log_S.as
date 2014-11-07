/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This class facilitates logging events to the server. It's here in order to
   package up many log events into fewer server requests, to avoid
   overwhelming the client and server with HTTP traffic. */

package gwis.utils {

   import flash.events.TimerEvent;
   import flash.utils.Timer;

   import gwis.GWIS_Log_Put;
   import utils.misc.Logging;
   import utils.misc.Strutil;

   public class Log_S {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW//Log_S');

      // *** Instance variables

      // Each event element is an Object with the following properties:
      // {'facility':String, 'params':Object, 'timestamp':String}
      protected var events:Array;
      protected var timer:Timer;

      // *** Constructor

      public function Log_S() :void
      {
         this.events = new Array();
         this.timer = new Timer(Conf.gwis_log_pause_threshold, 1);
         this.timer.addEventListener(TimerEvent.TIMER, this.on_timeout,
                                     false, 0, true);
      }

      // *** Event handlers

      //
      public function on_timeout(ev:TimerEvent) :void
      {
         this.send();
      }

      // *** Other instance methods

      // Log an event with the given parameters, value is an object that's
      // interpreted as key-value pairs.  All values are converted to strings
      // via their toString() method. The kvp's should only contain data
      // about the event; use the facility to describe the event.
      //
      // Facility is a string containing hierarchical categorization
      // information, generally resembling a relative path: e.g., "ui/redo"
      //
      // If force_send is true, then all queued events (including this one)
      // will be sent immediately
      public function event(facility:String, value:Object=null,
                            force_send:Boolean=false) :void
      {
         var ev:Object = new Object();
         ev.facility = facility;
         ev.params = value;
         ev.timestamp = Strutil.now_str(true);

         this.events.push(ev);
         if ((this.events.length >= Conf.gwis_log_count_threshold)
             || (force_send)) {
            this.send();
         }
         else {
            this.timer.reset();
            this.timer.start();
         }
      }

      //
      protected function send() :void
      {
         if (this.events.length > 0) {
            (new GWIS_Log_Put(this.events)).fetch();
            this.events = new Array();
            this.timer.stop();
         }
         // else, don't send anything if no events
      }

   }
}


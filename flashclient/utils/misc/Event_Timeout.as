/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Provides a way to wait for a short time before responding to a mouse event.
// Use to mimick the wait for the second click of a double-click.

package utils.misc {

   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.utils.Timer;

   public class Event_Timeout extends Timer {

      // *** Class attributes.

      protected static var log:Logging = Logging.get_logger('Event_Timeou');

      // *** Instance members.

      protected var event:MouseEvent;
      protected var func:Function;

      // cf. the deprecated flash.utils function setTimeout().
      public function Event_Timeout(closure:Function,
                                    delay:Number,
                                    ev:MouseEvent)
      {
         super(delay, 1);
         this.func = closure;
         this.event = ev;
         this.addEventListener(TimerEvent.TIMER_COMPLETE, this.done);
         this.start();
         m4_ASSERT(false); // This class is not used.
      }

      // *** Instance methods.

      //
      public function done(timer_ev:TimerEvent) :void
      {
         this.func(event);
         // MAYBE: Is it necessary to remove the event listener?
         // this.removeEventListener(TimerEvent.TIMER_COMPLETE, this.done);
      }

   }
}


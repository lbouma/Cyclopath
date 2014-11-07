/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* A simple idle timout class. There are two basic intervals. When the warning
   interval elapses, warn_function is called; when the timeout interval
   elapses, timeout_function is called. The timeout interval should be longer
   than the warn interval.

   Important: Between the warn and timeout intervals, mouse and keyboard
   activity no longer reset the timer. If the timer needs to be reset during
   this time (e.g. the user clicked an "I'm still here" button), you have to
   do it manually. */

package utils.misc {

   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.utils.Timer;
   import mx.core.Application;

   public class Idle_Timeout {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Idle_Timeout');

      // *** Instance variables

      public var warn_seconds:int;
      public var timeout_seconds:int;

      public var warn_function:Function;
      public var timeout_function:Function;

      protected var timer:Timer;
      protected var warned:Boolean;

      // *** Contructor

      public function Idle_Timeout() :void
      {
         this.timer = new Timer(1000);
         Application.application.addEventListener(MouseEvent.MOUSE_MOVE,
                                                  this.on_activity,
                                                  false, 0, true);
         Application.application.addEventListener(KeyboardEvent.KEY_DOWN,
                                                  this.on_activity,
                                                  false, 0, true);
         this.timer.addEventListener(TimerEvent.TIMER,
                                     this.on_tick, false, 0, true);
      }

      // *** Getters and setters

      //
      public function get timeout_remaining() :int
      {
         return (timeout_seconds - this.timer.currentCount);
      }

      // *** Other methods

      //
      protected function on_activity(ev:Event) :void
      {
         // This is either a KeyboardEvent or a MouseEvent (mouse move)
         if (this.timer.running && !(this.warned)) {
            this.timer.reset();
            this.timer.start();
         }
      }

      //
      protected function on_tick(ev:TimerEvent) :void
      {
         //trace('on_tick', this.warned, this.timer.currentCount);
         if (this.timer.currentCount >= this.warn_seconds && !(this.warned)) {
            this.warn_function();
            this.warned = true;
         }
         if (this.timer.currentCount >= this.timeout_seconds) {
            this.timeout_function();
            this.stop();
         }
      }

      //
      public function reset() :void
      {
         this.stop();
         this.start();
      }

      //
      public function start() :void
      {
         this.warned = false;
         this.timer.reset();
         this.timer.start();
      }

      //
      public function stop() :void
      {
         this.timer.stop();
      }

   }
}


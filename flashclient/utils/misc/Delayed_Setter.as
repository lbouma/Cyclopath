/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class changes the value of an attribute after a specified time.
//
// WARNING: The desired attribute must be settable by this class (e.g, public)
// -- if not, the operation will silently fail, and the change will appear to
// have succeeded from within this class, but will have actually failed.

package utils.misc {

   import flash.events.Event;
   import flash.events.TimerEvent;
   import flash.utils.Timer;

   public class Delayed_Setter {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('U:Delayd_Str');

      // *** Instance variables

      protected var target_obj:Object;
      protected var target_attr:String;
      protected var value:*;
      protected var timer:Timer;

      // *** Constructor

      public function Delayed_Setter(target_obj:Object, target_attr:String,
                                     value:*, delay_seconds:Number)
      {
         this.target_obj = target_obj;
         this.target_attr = target_attr;
         this.value = value;

         this.timer = new Timer(delay_seconds * 1000, 1);
         // don't use weak reference so I stick around until the timer goes.
         this.timer.addEventListener(TimerEvent.TIMER, this.on_timer_expire);
         this.timer.start();
      }

      // *** Static class methods

      // This static function is present so that the rather awkward new-based
      // interface is not exposed to callers.
      public static function set(target_obj:Object,
                                 target_attr:String,
                                 value:*,
                                 delay_seconds:Number) :void
      {
         new Delayed_Setter(target_obj, target_attr, value, delay_seconds);
      }

      // *** Getters and setters

      //
      public function on_timer_expire(ev:Event) :void
      {
         this.target_obj[this.target_attr] = this.value;
         this.timer.removeEventListener(TimerEvent.TIMER,
                                        this.on_timer_expire);
         this.timer = null;
         m4_DEBUG('Delayed_Setter set ' + this.target_obj
                  + '.' + this.target_attr + ' = ' + value);
      }

   }
}


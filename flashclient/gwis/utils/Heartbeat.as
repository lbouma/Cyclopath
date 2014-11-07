/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* This class is just a timer that makes a Log_S.event() call at regular
   intervals, to let us know that the flashclient is open. */

package gwis.utils {

   import flash.events.TimerEvent;
   import flash.utils.Timer;

   import utils.misc.Logging;

   public class Heartbeat {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW//Hrtbeat');

      // *** Instance variables

      protected var _timer:Timer;

      // *** Constructor

      public function Heartbeat() :void
      {
         this._timer = new Timer(Conf.gwis_log_heartbeat_interval);
         this._timer.addEventListener(
            TimerEvent.TIMER, this.on_heartbeat, false, 0, true);
         this._timer.start();
      }

      // *** Event handlers

      //
      public function on_heartbeat(ev:TimerEvent) :void
      {
         // Don't sent heartbeats while reauthenticating, to avoid creating
         // hundreds of auth failures from an unattended Cyclopath that needs
         // reauthentication.
         if (!G.user.reauthenticating) {
            m4_DEBUG('on_heartbeat: sending heartbeat event');
            G.sl.event('misc/heartbeat', {});
         }
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_base {

   import flash.events.Event;
   import flash.events.TimerEvent;
   import flash.utils.Timer;
   import mx.events.FlexEvent;

   import utils.misc.Logging;

   public class Other_Delayed_Saver extends Detail_Panel_Widget {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@DelydSavBas');

      // *** Instance variables

      // So that the user can click the change button a few times to find the
      // option they want before we finally save. Pretty neat, eh?
      protected var delayed_save_timer:Timer;

      // MAGIC_NO.: How long's a good time to wait? 10 seconds? 5? 1.25?
      //protected var wait_normal:int = 5000;
      protected var wait_normal:int = 1500;
      protected var wait_longer:int = 6000;

      // This is the value the user always sees.
      protected var value_future:* = null;
      protected var value_current:* = null;

      protected var gwis_outstanding:Boolean = false;

      // *** Constructor

      public function Other_Delayed_Saver()
      {
         super();

      }

      // ***

      //
      override public function set detail_panel(dp:Detail_Panel_Base) :void
      {
         super.detail_panel = dp;

         this.dp.addEventListener(FlexEvent.HIDE, this.on_hide_event_,
                                  false, 0, true);
      }

      //
      protected function on_hide_event_(ev:FlexEvent) :void
      {
         m4_DEBUG('on_hide_event_');

         this.force_save_now();
      }

      //
      override protected function on_remove_event(ev:FlexEvent) :void
      {
         super.on_remove_event(ev);
         m4_DEBUG('on_remove_event');

         this.force_save_now();

         this.removeEventListener(FlexEvent.HIDE, this.on_hide_event_);
      }

      // ***

      //
      protected function do_delayed_save(ev:TimerEvent=null) :void
      {
         m4_DEBUG('do_delayed_save:', ev);

         if (this.delayed_save_timer !== null) {
            if (this.delayed_save_timer.running) {
               this.delayed_save_timer.stop();
            }
            this.delayed_save_timer.reset();
         }
         else {
            m4_WARNING('do_delayed_save: What? No timer?');
         }

         if (this.value_current == this.value_future) {
            m4_DEBUG('do_delayed_save: User cycled back to same setting; meh');
         }
         else {
            if (!this.gwis_outstanding) {
               this.do_delayed_save_do();
            }
            else {
               m4_WARNING('do_delayed_save: Waiting on previous GWIS_Commit');
               var backoff:Boolean = true;
               this.timer_reset(backoff);
            }
         }
      }

      //
      protected function do_delayed_save_do() :void
      {
         m4_ASSERT(false); // Children must handle.
      }

      //
      protected function force_save_now() :void
      {
         m4_DEBUG3('force_save_now: runnng:',
                   (this.delayed_save_timer !== null)
                   ? this.delayed_save_timer.running : 'null');

         if ((this.delayed_save_timer !== null)
             && (this.delayed_save_timer.running)) {
            this.do_delayed_save();
         }
      }

      // ***

      //
      override protected function repopulate() :void
      {
         super.repopulate();

         // Always stop the timer on repopulate? Hrmmm...
         if (this.delayed_save_timer !== null) {
            if (this.delayed_save_timer.running) {
               this.delayed_save_timer.stop();
            }
            this.delayed_save_timer.reset();
         }
      }

      //
      protected function timer_reset(backoff:Boolean=false) :void
      {
         var timeout:int = (!backoff) ? this.wait_normal : this.wait_longer;
         // Stop the timer, maybe, and restart the timer.
         if (this.delayed_save_timer === null) {
            var repeat_count:int = 1;
            this.delayed_save_timer = new Timer(timeout, repeat_count);
            this.delayed_save_timer.addEventListener(TimerEvent.TIMER,
                                                     this.do_delayed_save,
                                                     false, 0, true);
         }
         else if (this.delayed_save_timer.running) {
            this.delayed_save_timer.stop();
            this.delayed_save_timer.reset();
         }
         this.delayed_save_timer.start();
      }

      // ***

   }
}


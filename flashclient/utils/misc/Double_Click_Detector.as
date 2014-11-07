/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.geom.Point;
   import flash.utils.Timer;
   import mx.core.UIComponent;

   import utils.geom.Geometry;

   // This class helps mouse listeners detect single and double clicks. Flex
   // only supports one or the other -- each sprite may only listen on the
   // down/up/click events, or just the doubleclick event -- but this class
   // overcomes that constraint. See also UIComponent.doubleClickEnabled.

   // Down, up, click, down, up, click

   // BUG nnnn: Click on line segment, then double-click elsewhere:
   //           1. ok: if you double click on nothing, map recenters
   //           2. not ok: if you double click on another line segment,
   //                      the selected ones changes the vertex lock --
   //                      this should only happen if you double-click
   //                      selected, otherwise... probably recenter? or
   //                      do nothing? or select and vertex-lock the other
   //                      line segment?

   public class Double_Click_Detector extends Timer {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('2x_Detective');

      // For a double click to be a double click, both clicks must be
      // physically near each other, and both clicks must be received in rapid
      // succession.
      //
      // If two consecutive clicks are more than this many pixels apart, the
      // two clicks are not considered a double click.
      public static const pixel_drift_threshold:int = 13;
      //
      // If two consecutive clicks are not received within this many
      // milliseconds, the two clicks are not considered a double click.
      // FIXME: Can we lower this number? Maybe, like, 200?
      public static const double_click_time:Number = 400;

      // *** Instance attribute

      protected var callback_single_click:Function;
      protected var callback_double_click:Function;
      protected var callback_timeout:Function;

      protected var limit_time:int =
         Double_Click_Detector.pixel_drift_threshold;
      protected var limit_distance:Number =
         Double_Click_Detector.double_click_time;

      // Track whether or not we're in detective mode or not, i.e., watching
      // for double clicks. This affects how and when we process mouse events.

      public var detecting_:Boolean = false;

      //
      // NOTE: The following use MouseEvent's target, not currentTarget. The
      //       latter reflects the current mouse event, but we want to
      //       reference past events.

      public var event_1_down:MouseEvent = null; // Non-null if detecting
      public var event_1_up:MouseEvent = null; // Non-null if detecting
      public var event_2_down:MouseEvent = null; // Non-null if detecting
      public var event_2_up:MouseEvent = null; // Non-null if detecting

      public var clicked_once:Boolean = false;
      public var complete_first_click:Boolean = false;
      public var complete_double_click:Boolean = false;

      // *** Constructor

      public function Double_Click_Detector(
         callback_single_click:Function,
         callback_double_click:Function,
         callback_timeout:Function,
         limit_time:int=Double_Click_Detector.pixel_drift_threshold,
         limit_distance:Number=Double_Click_Detector.double_click_time)
      {
         //var delay_:Number =
         //   (delay != 0) ? delay : Double_Click_Detector.double_click_time;
         this.callback_single_click = callback_single_click;
         this.callback_double_click = callback_double_click;
         this.callback_timeout = callback_timeout;
         this.limit_time = limit_time;
         this.limit_distance = limit_distance;

         const repeatCount:int = 1;
         super(this.limit_time, repeatCount);

         this.addEventListener(TimerEvent.TIMER_COMPLETE,
                               this.on_timer_complete);
         // FIXME: Do we need to call this.removeEventListener later?
      }

      // *** Init methods

      //
      public function init_listeners(listen_to:UIComponent,
                                     priority:int=0) :void
      {
         const useCapture:Boolean = false;
         const useWeakReference:Boolean = true; // EXPLAIN (I always forget)

         // http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/events/EventDispatcher.html#addEventListener():
         //    useWeakReference:Boolean (default = false) -- Determines whether
         //    the reference to the listener is strong or weak. A strong
         //    reference (the default) prevents your listener from being
         //    garbage-collected. A weak reference does not.
         //    Class-level member functions are not subject to garbage
         //    collection, so you can set useWeakReference to true for
         //    class-level member functions without subjecting them to
         //    garbage collection. If you set useWeakReference to true
         //    for a listener that is a nested inner function, the function
         //    will be garbage-collected and no longer persistent. If you
         //    create references to the inner function (save it in another
         //    variable) then it is not garbage-collected and stays persistent.

         listen_to.addEventListener(MouseEvent.MOUSE_DOWN, this.on_mouse_down,
                                    useCapture, priority, useWeakReference);
         listen_to.addEventListener(MouseEvent.MOUSE_UP, this.on_mouse_up,
                                    useCapture, priority, useWeakReference);
         listen_to.addEventListener(MouseEvent.MOUSE_MOVE, this.on_mouse_move,
                                    useCapture, priority, useWeakReference);
         // Clients should only hook down and up. Leave click all to us.
         listen_to.addEventListener(MouseEvent.CLICK, this.on_mouse_click,
                                    useCapture, 0, useWeakReference);
         // FIXME: Do we need to call this.removeEventListener later?
      }

      // *** Helper methods

      // Make this a static fcn?
      protected function close_enough(ev1:MouseEvent, ev2:MouseEvent) :Boolean
      {
         var close_enough:Boolean = false;
         var click_distance:Number;
         if ((ev1 !== null) && (ev2 !== null)) {
            click_distance = Geometry.distance(ev1.stageX, ev1.stageY,
                                               ev2.stageX, ev2.stageY);
            m4_VERBOSE('close_enough: click_distance:', click_distance);
            close_enough =
               (click_distance < Double_Click_Detector.pixel_drift_threshold);
         }
         else {
            // 2013.05.03: Happened to [lb] while messing around with floating
            //             tool palette.
            m4_WARNING('close_enough: null?: ev1:', ev1, '/ ev2:', ev2);
            // MAYBE: Is there some cleanup we should do?
         }
         return close_enough;
      }

      //
      public function get detecting() :Boolean
      {
         return this.detecting_;
      }

      //
      public function detector_reset() :void
      {
         m4_VERBOSE('detector_reset');
         this.detecting_ = false;
         // Skipping: mouse events. We might need to cleanup in mouse up.
         this.clicked_once = false;
         this.complete_first_click = false;
         this.complete_double_click = false;
         this.reset();
      }

      //
      public function detector_init(ev_down:MouseEvent, ev_up:MouseEvent=null)
         :void
      {
         m4_VERBOSE('detector_init: ev_down:', ev_down, 'ev_up:', ev_up);

         this.detector_reset();

         this.detecting_ = true;

         this.event_1_down = ev_down;
         this.event_1_up = ev_up;
         this.event_2_down = null;
         this.event_2_up = null;

         // Start the timer, er, us.
         this.start();
      }

      //
      override public function stop() :void
      {
         super.stop();
      }

      // *** Click handlers, ordered by event sequence, i.e., up-down-click

      // Here we handle mouse clicks, both on the map canvas and on any items
      // that might be on the canvas.
      //
      // Two important notes:
      //
      //   (1) We process our own doubleclick events.
      //       Flex has a MouseEvent.DOUBLE_CLICK event, but it works
      //       exclusively of the other three related events, MOUSE_DOWN,
      //       MOUSE_UP, and MOUSE_CLICK. I.e., you either get down/up/click
      //       events, or you just get doubleclick events. We want both.
      //
      //   (2) We don't set event listeners on the Geofeature sprites. In V1,
      //       we did, but then the item being clicked and the map sometimes
      //       processed the same event (e.g. if you click an item and drag,
      //       the map is panned and then the object is selected, which is
      //       two responses when there should only be one (the map should be
      //       panned and the item should not be selected)). In V2, we let the
      //       map canvas process all mouse events. This makes it easier to
      //       coordinate behavior between the different things that are
      //       interested in clicks.

      // Mouse down event
      public function on_mouse_down(ev:MouseEvent) :void
      {
         var process_event_1_down:Boolean = false;

         // ev.target: main0.HDividedBox4.map_canvas.map or [obj. Item_Sprite,]
         m4_VERBOSE('on_mouse_down: target:', ev.target);
         m4_VERBOSE('  ev:', ev);

         if (!this.detecting) {
            // This is the "first" mouse down, so we don't know if the user
            // is about to drag, is going to double click, or whatever. Just
            // start the double click timer and wait for something to happen.
            m4_DEBUG('on_mouse_down: 1st mouse down: starting detector');
            m4_ASSERT(!this.clicked_once);
            this.detector_init(ev);
         }
         else {
            // This is the "second" mouse down since starting the timer.
            m4_ASSERT(this.event_2_down === null);

            if ((!this.clicked_once) || (!this.running)) {
               m4_WARNING2('on_mouse_down: unexpected:', '/ clicked_once:',
                           this.clicked_once, '/ running:', this.running);
               // Fired on [lb] 2014.09.16. Stack trace not much help, just
               // says on_mouse_down, the entry point, which is this fcn....
               // BUG nnnn: Perhaps this.detecting and this.clicked_once
               //          or maybe this.detecting and this.running
               //           and not being updated? Whatever the case,
               //           I didn't notice anything using the client
               //           and missed this error until I saw the logcheck
               //           email, so this could totally be a non-issue.
               m4_ASSERT_KNOWN((!this.clicked_once) && (!this.running));
               return;
            }

            this.event_2_down = ev;
            // Check how far the mouse moved between the first mouse up and the
            // second mouse down: if the user moved the mouse considerably, we
            // don't consider this a double click candidate. (A double click is
            // two clicks that occur close to one another, both spatially and
            // temporally. Note that we don't actually process the double click
            // until the mouse is released and we get the mouse up.)
            // Check the distance between clicks
            if (this.close_enough(ev, this.event_1_down)) {
               // Set a flag telling ourselves to process the double click in
               // mouse_up.
               m4_DEBUG('on_mouse_down: 2nd mouse down: double click!');
            }
            else {
               // The two clicks were far apart, so complete the first event
               // and start double click detection on the second.
               m4_DEBUG('on_mouse_down: 2nd mouse down far away: nothing.');
               // Set a flag. We'll handle this in on_mouse_click, unless
               // another mouse handlers gets to it sooner.
               this.complete_first_click = true;
            }
         }
      }

      // Mouse up event
      public function on_mouse_up(ev:MouseEvent) :void
      {
         m4_VERBOSE('on_mouse_up: target:', ev.target);
         m4_VERBOSE('  ev:', ev);

         // See that the event hasn't already been processed.
         if (this.detecting) {
            //
            if (this.clicked_once) {
               // Double click event. But if user dragged during the second
               // click, we don't want to treat this as a doubleclick.
               this.event_2_up = ev;
               if (this.close_enough(this.event_2_up, this.event_2_down)) {
                  m4_DEBUG('on_mouse_up: 2nd mouse up: double click is real');
                  this.complete_double_click = true;
               }
               else {
                  // FIXME: Decide what to do.
                  // Ignore the first event?
                  // Or not:
                  m4_DEBUG('on_mouse_up: 2nd mouse up: double click is fake');
                  this.complete_first_click = true;
               }
            }
            else {
               // This is just the first up after the first down.
               m4_DEBUG('on_mouse_up: 1st mouse up: waiting for next event');
               m4_ASSERT(this.event_2_down === null);
               this.event_1_up = ev;
               //
               //this.clicked_once = true;
               //m4_ASSERT(!this.running);
               //this.start();
               // wait for normal click event?
            }
         }
         // else, nothing to do
      }

      // Mouse click event (similar to -- but fires after -- mouse up).
      public function on_mouse_click(ev:MouseEvent) :void
      {
         m4_VERBOSE('on_mouse_click: target:', ev.target);
         m4_VERBOSE('  ev:', ev);
         //
         if (this.detecting) {
            if (this.complete_double_click) {
               // Hmpf. No one handled this event.
               m4_DEBUG('on_mouse_click: completing double click');
               m4_ASSERT(!this.complete_first_click);
               // NOTE: Does it matter which event we pass?
               //       Mouse down, up, or this one's click? First or second?
               //this.callback_double_click(this.event_2_down);
               this.callback_double_click(this.event_2_up);
               //this.callback_double_click(ev);
               this.detector_reset();
            }
            else if (this.complete_first_click) {
               // Hmpf. No one handled this event.
               m4_DEBUG('on_mouse_click: completing first click');
               // NOTE: Does it matter which event we pass?
               //       Mouse down, up, or this one's click?
               this.callback_single_click(this.event_1_up);
               // Double click was a fake, so restart the detector using the
               // second event.
               this.detector_init(this.event_2_down, this.event_2_up);
            }
            if (this.detecting) {
               if (!this.clicked_once) {
                  // First mouse-up, or 2d mouse-up after non-double-click evt.
                  m4_DEBUG('on_mouse_click: starting double click timer');
                  this.clicked_once = true;
                  // Not true: detector_init starting timer:
                  //    Wrong: m4_ASSERT(!this.running);
                  // HRMM: Restart the timer, or let it keep running?
                  this.reset();
                  this.start();
               }
               else {
                  m4_ASSERT(this.running)
               }
            }
         }
      }

      // If the mouse moves afar between clicks, cancel the double click and
      // process the first click as a single click.
      public function on_mouse_move(ev:MouseEvent) :void
      {
         //m4_VERBOSE('on_mouse_move');
         // FIXME: Is this an expensive fcn. to call often?
         if ((this.detecting)
             && (this.event_1_down !== null)
             && (this.event_2_down === null)
             && (this.clicked_once)) {
            // We're between clicks.
            m4_ASSERT(this.running);
            if (!this.close_enough(ev, this.event_1_down)) {
               // The cursor has strayed.
               m4_VERBOSE('on_mouse_move: finishing first click / resetting');
               this.callback_single_click(this.event_1_up);
               this.detector_reset();
            }
         }
      }

      //
      public function on_timer_complete(timer_ev:TimerEvent) :void
      {
         // If this fires, the user is still holding the mouse down.
         m4_VERBOSE('on_timer_complete');
         if (this.detecting) {
            if (!this.clicked_once) {
               // User single clicked and is still holding the mouse down
               m4_DEBUG('on_timer_complete: single click and hold');
               // LOST_IN_TIME: The callee ignores the two parms we pass it.
               this.callback_timeout(this.event_1_down, this.event_2_down);
            }
            else if (this.event_2_down !== null) {
               // User double clicked and is holding down the second click
               m4_DEBUG('on_timer_complete: double click and hold');
               // LOST_IN_TIME: The callee ignores the two parms we pass it.
               this.callback_timeout(this.event_1_down, this.event_2_down);
            }
            else {
               // User clicked once and hasn't clicked again, so act on
               // whatever they clicked upon.
               m4_DEBUG('on_timer_complete: single click after timeout');
               this.callback_single_click(this.event_1_up);
            }
            this.detector_reset();
         }
         m4_ASSERT_ELSE_SOFT;
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   // This class implements a throbber.

   // Set DEGREES_PER_TICK to slightly less than 360/BALL_COUNT and you will
   // get an effect of the ring rotating slowly counterclockwise while balls
   // grow rapidly in turn clockwise. Set DEGREES_PER_TICK to a small positive
   // or negative number to get a less busy ring that rotates clockwise or
   // counterclockwise, respectively.

   // You can also get an interesting effect by removing the Timer
   // infrastructure and instead using callLater(this.tick) in tick(). This
   // results in a rather spastic throbber that behaves differently at
   // different times.

   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.TimerEvent;
   import flash.geom.Matrix;
   import flash.utils.Timer;
   import mx.core.UIComponent;
   import mx.events.FlexEvent;

   public class Throbber extends UIComponent {

      // Class attributes.

      protected static var log:Logging = Logging.get_logger('Throbber');

      // *** Config

      //protected static const TIMER_INTERVAL:Number = (1000.0/24);
      protected static const TIMER_INTERVAL:Number = (1000.0/12);
      // NOTE There are 8 balls, so at 45 degrees, it doesn't look like the
      //      balls rotate; you just see the big ball go around. At other
      //      degrees, like 30 degrees, you'll see the whole Throbber rotate.
      protected static const DEGREES_PER_TICK:int = 30;
      protected static const BALL_COUNT:int = 8;
      protected static const BALL_RADIUS_SMALL:Number = 2;
      protected static const BALL_RADIUS_LARGE:Number = 3;
      protected static const CIRCLE_RADIUS:Number = 7.5;
      protected static const BALL_COLOR:int = 0x000000;

      // Fire a timer at intervals while the timer spins -- this is a
      // developer mechanism to track proper throbber usage; feel free to
      // remove this code at a later date if you think the throbber is solid
      protected static const SANITY_INTERVAL:Number = 1000.0 * 120;

      // *** Instance variables

      protected var timer:Timer;
      protected var sprite:Sprite;
      protected var stopped:Boolean = true;
      protected var stopping:Boolean = false;
      protected var sanity_timer:Timer;

      // *** Constructor

      public function Throbber()
      {
         super();

         // Make sure DEGREES_PER_TICK is cleanly divisible into 90, which is
         // the degrees at which the sprite appears to be at 12 o'clock high
         m4_ASSERT((90 % DEGREES_PER_TICK) == 0);

         this.timer = new Timer(TIMER_INTERVAL);
         this.timer.addEventListener(TimerEvent.TIMER,
                                     this.tick, false, 0, true);

         this.sanity_timer = new Timer(SANITY_INTERVAL);
         this.sanity_timer.addEventListener(TimerEvent.TIMER,
                                            this.sanity_check, false, 0, true);

         this.draw();
      }

      // *** Getters and setters

      //
      override public function get measuredHeight() :Number
      {
         return 2 * (CIRCLE_RADIUS + BALL_RADIUS_LARGE);
      }

      //
      override public function get measuredWidth() :Number
      {
         return this.measuredHeight;
      }

      // *** Public instance methods

      //
      public function play() :void
      {
         m4_TALKY('play: timer.running:', this.timer.running);
         // Start the throbber timer if it's not already started
         if (!this.timer.running) {
            // Draw the active sprite and start the throbber
            this.stopped = false;
            this.draw();

            // This is a hack: Hide the parent.
            // MAYBE: Find a different way to do this?
            this.parent.visible = true;

            this.timer.start();
         }
         // 2014.06.23: If user stops an operation but starts a new one before
         // the circle animation completes, be sure not to accidentally stop
         // the animation.
         this.stopping = false;
         // Reset the sanity_timer so it always measures from the last msg sent
         this.sanity_timer.reset();
         this.sanity_timer.start();
      }

      //
      public function stop() :void
      {
         m4_TALKY('stop: timer.running:', this.timer.running);
         // Note that we don't stop the timer here: we let the spinner
         // animation complete its circle and then we'll stop the timer.
         // I.e., to test if the throbberer is spinning, check
         //       this.timer.running and also this.stopping.
         if (this.timer.running) {
            // Tell the timer callback to stop as
            // soon as the throbber reaches 12 o'clock
            this.stopping = true;
            // Don't set the parent invisible here; we want the throbber to
            // return to 12 o'clock.
            // NO: this.parent.visible = false;
            // Log an event if the throbber runs for more than SANITY_INTERVAL
            // since the last HTTP request was sent
            if (this.sanity_timer.currentCount > 0) {
               // The sanity timer fired earlier, so log a final message
               G.sl.event('warning/ui/throbber/stopped',
                          { currentCount: this.sanity_timer.currentCount } );
            }
            this.sanity_timer.stop();
         }
      }

      // *** Protected instance methods

      // Draw myself. The Sprite child is a hack because I couldn't get
      // Matrix.translate() to work, and I need to rotate around the center of
      // the object, not the upper left corner.
      protected function draw() :void
      {
         var i:int;
         var x:Number;
         var y:Number;
         var r:Number;
         var gr:Graphics;

         // Clear the child container
         while (this.numChildren > 0) {
            this.removeChildAt(0);
         }

         this.sprite = new Sprite();
         this.sprite.x = CIRCLE_RADIUS + BALL_RADIUS_LARGE;
         this.sprite.y = this.sprite.x;
         this.addChild(this.sprite);

         gr = this.sprite.graphics;

         // If Throbbing, draw a large (3 pixel) semi-transparent circle
         if (!this.stopped) {
            gr.beginFill(BALL_COLOR, 0.8);
            gr.drawCircle(CIRCLE_RADIUS, 0, BALL_RADIUS_LARGE);
         }
         // Always draw a small (2 pixel) opaque circle, regardless of stopped
         gr.beginFill(BALL_COLOR, 1.0);
         gr.drawCircle(CIRCLE_RADIUS, 0, BALL_RADIUS_SMALL);

         // Draw all the other circles
         for (i = 1; i < BALL_COUNT; i++) {
            r = i * (2 * Math.PI / BALL_COUNT);
            x = Math.cos(r) * CIRCLE_RADIUS;
            y = Math.sin(r) * CIRCLE_RADIUS;
            gr.drawCircle(x, y, BALL_RADIUS_SMALL);
         }

         // Rotate the sprite so the large ball is at the first
         // position clockwise of the "top" of the circle
         this.sprite.rotation = -90 + DEGREES_PER_TICK;
      }

      //
      protected function reset_throbber() :void
      {
         // Stop both timers and draw the inactive sprite.
         this.timer.stop();
         this.stopped = true;
         this.stopping = false;
         this.draw();

         // This is a hack: Hide the parent.
         // MAYBE: Find a different way to do this?
         this.parent.visible = false;
      }

      // If the sanity_timer fires, log an event so us developers
      // know we have an endlessly spinning throbber somewhere
      protected function sanity_check(ev:TimerEvent) :void
      {
         // FIXME: This is an event we send to the server, but it's more like a
         //        warning, and we don't have a server process to check these.
         //        We should send emails to cyclopath-errs when this happens.
         G.sl.event('warning/ui/throbber/overdue',
                    {currentCount: this.sanity_timer.currentCount});
      }

      //
      protected function tick(ev:TimerEvent) :void
      {
         this.sprite.rotation += DEGREES_PER_TICK;
         m4_ASSERT((-180 < this.sprite.rotation)
                   && (this.sprite.rotation <= 180));
         if (this.stopping && (this.sprite.rotation == -90)) {
            this.reset_throbber();
         }
      }

   }
}


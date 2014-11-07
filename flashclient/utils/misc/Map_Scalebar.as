/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A widget that draws a map scalebar. To work correctly the Map_Scalebar must
// be named 'scale_bar' to be updated properly by Map_Canvas. There must also
// be two labels named scalebar_meter_label and scalebar_feet_label.

package utils.misc {

   import flash.display.Graphics;
   import flash.display.JointStyle;
   import flash.display.CapsStyle;
   import flash.display.LineScaleMode;
   import mx.controls.Label;
   import mx.controls.Spacer;
   import mx.core.UIComponent;

   public class Map_Scalebar extends UIComponent {

      protected static var log:Logging = Logging.get_logger('+Map_Scalbar');

      // Drawing parameters
      private var tick_height:int;
      private var target_width:int;

      public function Map_Scalebar()
      {
         this.tick_height = 8;
         this.target_width = 150;
      }

      public function update() :Boolean
      {
         var gr:Graphics = this.graphics;
         var meters_tick_x:int;
         var meters:int;
         var feet_tick_x:int;
         var feet:int;

         meters = meter_dist_get_nice(this.target_width / G.map.scale);
         meters_tick_x = G.map.scale * meters;

         feet = feet_dist_get_nice((this.target_width / G.map.scale)
                                   * 3.28083);
         feet_tick_x = (feet / 3.28083) * G.map.scale;

         // MAYBE: COUPLING: This is a utility class (we're in the utils.misc.*
         //                  package) but we're twiddling GUI components in
         //                  main.mxml (via G.app). [lb] says, "No bueno."
         //                  An easy fix is to move this to views.panel_util.*

         // Set the labels for the scale bar.  If either measurement is
         // underneath a threshold, show the label as feet or meters
         // instead of miles or kilometers.
         if (!is_under_meter_threshold(meters)) {
            G.app.scalebar_meters_label.text = ((meters/1000.0).toFixed(1)
                                                + ' km');
         }
         else {
            G.app.scalebar_meters_label.text = (meters).toFixed(0) + ' m';
         }

         if (!is_under_feet_threshold(feet)) {
            G.app.scalebar_feet_label.text = (feet/5280.0).toFixed(1) + ' mi';
         }
         else {
            G.app.scalebar_feet_label.text = (feet).toFixed(0) + ' ft';
         }

         gr.clear();

         // Draw the widget

         m4_DEBUG('update: redrawing map_scalebar');

         gr.lineStyle(3, 0x000000, 1.0, true,
                      LineScaleMode.NORMAL, CapsStyle.ROUND, JointStyle.ROUND);
         gr.moveTo(0, 0);
         gr.lineTo(0, this.tick_height);
         gr.moveTo(0, 0);
         gr.lineTo(meters_tick_x, 0);
         gr.lineTo(meters_tick_x, this.tick_height);

         gr.moveTo(0, 0);
         gr.lineTo(0, -this.tick_height);
         gr.moveTo(0, 0);
         gr.lineTo(feet_tick_x, 0);
         gr.lineTo(feet_tick_x, -this.tick_height);

         var finished:Boolean = true;
         return finished;
      }

      // FIXME Another example of style: short circuit returns
      protected function meter_dist_get_nice(d:Number) :Number
      {
         var meters:Number = 50.0;
         if (d >= 1000.0) {
            var t:int = d/1000;
            meters = t * 1000.0;
         }
         else if (d >= 500.0) {
            meters = 500.0;
         }
         else if (d >= 250.0) {
            meters = 250.0;
         }
         else if (d >= 100.0) {
            meters = 100.0;
         }
         return meters;
      }

      protected function feet_dist_get_nice(d:Number) :Number
      {
         var feet:Number = 100.0;
         if (d >= 5280.0) {
            var t:int = d/5280;
            feet = t * 5280.0;
         }
         else if (d >= 2640.0) {
            // Will be written as miles because it's above the threshold still.
            feet = 2640.0;
         }
         else if (d >= 1320.0) {
            // Will be written as miles because it's above the threshold still.
            feet = 1320.0;
         }
         else if (d >= 800.0) {
            feet = 800.0;
         }
         else if (d >= 400.0) {
            feet = 400.0;
         }
         else if (d >= 200.0) {
            feet = 200.0;
         }
         return feet;
      }

      protected function is_under_meter_threshold(d:Number) :Boolean
      {
         if (d < 1000.0) {
            return true;
         }
         return false;
      }

      protected function is_under_feet_threshold(d:Number) :Boolean
      {
         if (d < 1320.0) {
            return true;
         }
         return false;
      }

   }
}


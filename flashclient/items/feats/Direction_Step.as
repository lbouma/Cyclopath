/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.feats {

   import mx.core.UIComponent;

   import utils.misc.Logging;
   import utils.misc.Strutil;
   import utils.misc.Timeutil;
   import items.utils.Item_Type;
   import items.utils.Landmark;
   import views.base.Paint;

   public class Direction_Step {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Dir_Step');

      // *** Instance variables

      // The name of a single step, which could be the name of a byway or the
      // name of a transit facility (e.g., 'Bus 16').
      public var name:String;

      public var rel_distance:Number; // Distance traveled this step

      // The previous step.
      public var previous:Direction_Step;
      // The gfl_id of the last merged route_step, or -1 if route_stop.
      public var geofeature_layer_id:int;

      // Relative turning, no meaning for start/end.
      public var rel_direction:int;
      // Absolute direction.
      public var abs_direction:int;

      // FIXME: MAGIC_NUMBERS: Make a simple class for these values instead.
      // The stop_type is a value defined by Stop_Type.
      // Stop types:
      //   -1: alight
      //    0: not a transit stop
      //    1: transit board
      //    2: transit alight (WRONG!) it's -1...
      public var stop_type:int;

      public var beg_time:int;
      public var fin_time:int;
      
      // Landmarks experiment.
      public var landmarks:Array;
      // map coordinates of this step, so that we can take the user to it
      public var coords:Array;
      public var show_landmark_list:Boolean;
      public var route:Route;
      public var step_number:int;

      public function Direction_Step(rel_direction:int,
                                     abs_direction:int,
                                     rel_distance:Number,
                                     name:String,
                                     stop_type:int,
                                     beg_time:int,
                                     fin_time:int,
                                     prev:Direction_Step,
                                     // Landmarks experiment.
                                     coords:Array,
                                     landmarks:Array,
                                     r:Route,
                                     step_number:int,
                                     route_caller:String)
      {
         this.name = name;
         this.rel_distance = rel_distance;
         this.previous = prev;
         // Skipping: geofeature_layer_id.
         this.rel_direction = rel_direction;
         this.abs_direction = abs_direction;
         this.stop_type = stop_type;
         this.beg_time = beg_time;
         this.fin_time = fin_time;
         this.coords = coords;
         this.show_landmark_list = false;
         this.route = r;
         this.step_number = step_number;

         if ((isNaN(this.coords[0])) && (isNaN(this.coords[1]))) {
            // 2014.09.09: This is firing somewhat often.
            m4_ASSERT_SOFT(false);
            G.sl.event('error/dir_step/ctor',
                       {route_caller: route_caller,
                        route: this.route,
                        step_no: this.step_number});
         }

         // Landmarks experiment.
         var new_lmark:Landmark;
         if (landmarks === null) {
            this.landmarks = new Array();
            new_lmark = new Landmark(); // The "Other:" landmark.
            // [lb] apologizes for this kludge: the lmark knows its list posit.
            new_lmark.dstep_index = 0;
            this.landmarks.push(new_lmark);
         }
         else {
            this.landmarks = landmarks;
            var other_exists:Boolean = false;
            var l:Landmark;
            for each (l in this.landmarks) {
               if (l.item_type_id == Item_Type.LANDMARK_OTHER) {
                  other_exists = true;
                  break;
               }
            }
            this.show_landmark_list = true;
            if (!other_exists) {
               new_lmark = new Landmark(); // The "Other:" landmark.
               new_lmark.dstep_index = this.landmarks.length;
               this.landmarks.push(new_lmark);
            }
         }
      }

      // *** Distance methods

      //
      public function get abs_distance() :Number
      {
         if (previous !== null) {
            return previous.rel_distance + previous.abs_distance;
         }
         else {
            return 0;
         }
      }

      //
      public function get step_distance() :String
      {
         var the_dist:String;
         if (this.is_last || this.is_route_stop) {
            the_dist = '--';
         }
         else {
            var decimal_places:int = 2;
            var display_units:Boolean = false;
            the_dist = Strutil.meters_to_miles_pretty(
               this.rel_distance, decimal_places, display_units);
         }
         return the_dist;
      }

      //
      public function get time_str() :String
      {
         // If a bicycle facility, use the beggining time, otherwise, if this
         // is a transit facility, use the finishing time.
         var time:int = ((this.stop_type == 0) ? this.beg_time
                                               : this.fin_time);
         var time_s:String = (
            (time == -1) ? '--' : Timeutil.epoch_time_to_pretty_string(time));
         return time_s;
      }

      //
      public function get total_distance() :String
      {
         return Strutil.meters_to_miles_pretty(this.abs_distance, 2, false);
      }

      // *** Is First / Is Last

      //
      public function get is_last() :Boolean
      {
         // HACK. MAYBE: This is such bad code.
         // MAGIC_NUMBER: The 1st-to-last element of Conf.bearing is: 'End'.
         return this.rel_direction == (Conf.bearing.length - 1);
      }

      //
      public function get is_first() :Boolean
      {
         // HACK. MAYBE: This is such bad code.
         // MAGIC_NUMBER: The 2nd-to-last element of Conf.bearing is: 'Start'.
         return this.rel_direction == (Conf.bearing.length - 2);
      }

      //
      public function get is_route_stop() :Boolean
      {
         // A route_stop is a standard route_stop or a transit stop (which has
         // a separate designation so we can change its color and image).
         // HACK. MAYBE: This is such bad code: MAGIC_INDICES.
         // MAGIC_NUMBERS: The 3rd- and 4th-to-last elements of Conf.bearing:
         //                 'Transit stop' and 'Bicycle stop', respectively.
         return ((this.rel_direction == (Conf.bearing.length - 3))
                 || (this.rel_direction == (Conf.bearing.length - 4)));
      }

      // *** Textual methods

      //
      [Bindable] public function get directions_text_hyperlinked() :String
      {
         m4_TALKY('directions_text_hyperlinked: use_hyperlinks=true');
         return this.get_step_description(/*use_hyperlinks=*/true);
      }

      //
      public function set directions_text_hyperlinked(ignored:String) :void
      {
         m4_ASSERT(false); // Don't call on me.
      }

      //
      public function get_step_description(use_hyperlinks:Boolean=false)
         :String
      {
         var step_description:String = '';

         var name_:String;
         if (this.geofeature_layer_id > 0) {
            try {
               name_ = 'Unnamed '
                        + Conf.tile_skin.feat_pens
                          [String(this.geofeature_layer_id)]['friendly_name'];
            }
            catch (e:TypeError) {
               // Error #1010: A term is undefined and has no properties.
               m4_DEBUG('get text: gfl_lyr_id:', this.geofeature_layer_id);
               m4_ASSERT_SOFT(false); // DEVS should prevent this by making sure
                                      // Conf.tile_skin.feat_pens is complete.
               name_ = 'Unnamed something or other';
            }
         }
         else {
            name_ = 'Unitialized Direction_Step';
         }

         var pname:String;
         var pstep:Direction_Step = this.previous;

         if ((this.previous !== null) && (this.previous.is_route_stop)) {
            pstep = this.previous.previous;
         }

         if ((this.name !== null) && (this.name != '')) {
            name_ = this.name;
         }

         // MAYBE: Make the Hyper_Link optional?
         // FIXME: The Hyper_Link shows up on the printable cue sheet.
         //        While the underline and color look okay, the link
         //        takes the user to a broken page.
         // 2014.04.23: BUG nnnn/Directions Header Hyperlink:
         //    I [lb] am disabling the directions hyperlink per [ft]'s request.
         //    The second part of the landmarks experiment uses more colors, so
         //    let's not do this (now). [lb] wonders if maybe we'll like this
         //    feature in the future.
         //    ALSO: This is the only example in Cyclopath of using the link=
         //    TextEvent handler, which seems very useful, so keep this code.
         //    Even if it's falsed-out.

         // [ft] Setting to false for now until my experiment is done or we
         // figure out a better way to show this.
         // FIXME/BUG nnnn: 2014.06.27: Implement hyperlinked/highlighted
         //                 street names, so easier to read cue sheet. [lb]
         //var landmarks_experiment_override:Boolean = false;
         var landmarks_experiment_override:Boolean = true;

         if (!landmarks_experiment_override) {
            // MAGIC_NUMBERs from the Hyper_Link class and labelminor style.
            // NOTE: Why doesn't this work:
            //       <p style="text-decoration:underline;">
            //       </p>
            name_ =
               '<font color="#0000FF" style="text-decoration:underline;">'
               + '<u>'
               + '<a href="event:lookat">'
               + name_
               + '</a>'
               + '</u>'
               + '</font>'
               ;
         }

         // Special case for route stops.
         // FIXME: Replace stop_type MAGIC_NUMBERS with class.
         // FIXME: Before route sharing, we disinguished between busses and
         //        trains, e.g., "Board Bus" or "Get off Train". How come we
         //        stopped doing that?
         // BEGIN: Multimodal stops
         if (this.stop_type == -1) {
            step_description = 'Get off ' + name_;
         }
         else if (this.stop_type == 1) {
            step_description = 'Board ' + name_;
         }
         else if (this.is_last) {
            step_description = 'End at ' + name_;
         }
         else if (this.is_first) {
            step_description =
               'Start cycling '
               + Conf.bearing[this.abs_direction][Conf.c_name]
               + ' on ' + name_;
         }
         else if (this.is_route_stop) {
            step_description = 'Arrive at ' + name_;
         }
         // END: Multimodal stops / BEGIN: Normal bike route (routed_p1) stops.
         else {
            // Regular biking directions
            if (pstep.name !== null && pstep.name != '') {
               pname = pstep.name;
            }
            else {
               pname = 
                  'Unnamed '
                  + Conf.tile_skin.feat_pens
                     [String(pstep.geofeature_layer_id)]['friendly_name'];
            }

            if (name_ == pname) {
               step_description =
                  'Continue '
                  + Conf.bearing[this.abs_direction][Conf.c_name]
                  + ' on ' + name_;
            }

            if (Conf.bearing[this.rel_direction][Conf.r_name] != 'Forward') {
               var s:String =
                     Conf.bearing[this.rel_direction][Conf.r_name] + '/'
                     + Conf.bearing[this.abs_direction][Conf.c_name] + ' onto '
                     + name_;
               step_description = s;
            }
            else {
               step_description = pname + ' changes to ' + name_;
            }
         }

         // Landmarks experiment.
         if (this.landmarks !== null) {
            step_description += Landmark.generate_directions_str(
                       this.route, this.landmarks, use_hyperlinks);
         }

         return step_description;
      }

      //
      public function html_text(is_multimodal:Boolean) :String
      {
         var img:String = Conf.bearing[this.rel_direction][Conf.image];
         var first_col:String = (is_multimodal ? this.time_str
                                               : this.total_distance);
         var html_text:String =
              '<td align="center" class="normal">' + first_col + '</td>'
            + '<td align="center"><img width="25" height="25" src="'
               + img + '"></td>'
            + '<td class="normal">' + this.text + '</td>'
            + '<td align="center" class="normal">'
               + this.step_distance + "</td>";
         return html_text;
      }

      //
      public function measure_text_height(owner:UIComponent) :int
      {
         var height:int;
         height = Paint.measure_text_height(this.text, owner, owner.width);
         return height;
      }

      // Use [Bindable], lest: warning: unable to bind to property 'text' on
      // class 'items.feats::Direction_Step' (class is not an IEventDispatcher)
      [Bindable] public function get text() :String
      {
         return this.get_step_description(/*use_hyperlinks=*/false);
      }

      //
      public function set text(text:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function toString() :String
      {
         return this.text;
      }

   }
}


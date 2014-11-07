/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   import flash.utils.getQualifiedClassName;

   import items.feats.Route;
   import utils.geom.Geometry;
   import utils.misc.Collection;
   import utils.misc.Logging;

   public class Landmark {

      // *** Class variables

      protected static var log:Logging = Logging.get_logger('Landmark');

      // MAGIC_NUMBER: The April 2014 Landmarks experiment asks the user to
      //               look at and add landmarks to five routes.
      // SYNC_ME: pyserver/item/util/landmark.py::Landmark::experiment_count
      //     flashclient/items/utils/Landmark.as::Landmark::experiment_count
      public static const experiment_count:int = 15;

      // *** Instance variables

      public var name:String;
      public var xs:Array;
      public var ys:Array;
      public var item_id:int;
      public var item_type_id:int;

      public var dist:Number;
      public var angles:Array;
      public var display:Boolean;

      // To make the list entry component a little easier to code,
      // store the landmark's position in the parent list. This sort of
      // couples the landmark to the view, but at least the Landmark
      // doesn't manage or care about this value. Also, for this value
      // to make sense, it means there's a one-to-one relationship between
      // Route_Directions_Landmarks_Entry objects and Landmarks. Indeed,
      // each Route has a distinct set of Direction_Steps, each of which
      // has a distinct set of Landmarks.
      public var dstep_index:int = -1;
      
      public var rating:int = -1;
      public var moused_over:Boolean = false;

      // *** Constructor

      public function Landmark(xml:XML=null)
      {
         if (xml !== null) {
            this.xs = new Array();
            this.ys = new Array();
            this.name = xml.@name;
            this.item_id = xml.@item_id;
            this.item_type_id = xml.@type_id;
            Geometry.coords_string_to_xys(xml.text(), this.xs, this.ys);
            this.display = xml.@disp;
         }
         else {
            // Default to the "Other:" landmark (i.e., there aren't multiple
            // "other" types, there's just the one "Other:" type per direction
            // step that the user can fill in.
            this.name = '';
            this.item_id = -1;
            this.item_type_id = Item_Type.LANDMARK_OTHER;
            this.display = false;
         }
         this.dist = 0;
         this.angles = new Array();
      }

      // Getter for getting type of landmark
      public function get type_str():String
      {
         if (this.item_type_id == Item_Type.TAG) {
            return 'tag';
         }
         else if (this.item_type_id == Item_Type.BYWAY) {
            return 'block';
         }
         else if (this.item_type_id == Item_Type.LANDMARK_T) {
            return 'T intersection';
         }
         else if (this.item_type_id == Item_Type.LANDMARK_OTHER) {
            return 'other';
         }
         else if (this.item_type_id == Item_Type.WAYPOINT) {
            return 'waypoint';
         }
         else if (this.item_type_id == Item_Type.TERRAIN){
            return 'terrain';
         }
         else {
            return 'landmark';
         }
      }

      // Returns the snippet that will be added to the end of a direction
      // step in the cue sheet
      public static function generate_directions_str(route:Route,
                                                     landmarks:Array,
                                                     show_url:Boolean):String
      {
         if (!G.map.landmark_exp_validation_active) {
            show_url = false;
         }
         // MAYBE: Move this color to a config file or a stylesheet.
         // See also: BUG nnnn/Directions Header Hyperlink: We're starting to
         //    colorize the route directions header text, and this is one of
         //    a few places that helps build the colorful html text.
         var dir_str:String = '<font color=\'#0000AA\'>'; // Blue.

         var l:Landmark;
         var ang:Number;
         var tags:Array = new Array();
         var crossings:Array = new Array();
         var t_inter:Landmark;
         var other:Landmark;
         var pois_terrains:Array = new Array();

         // classify landmarks
         for each (l in landmarks) {
            // The server sends a list of landmarks it thinks will be useful
            // for each direction_step. For the static cue sheet, we can show
            // those suggestions that we're pretty confident will be useful,
            // like those about nearby waypoints, but we'll hide the rest,
            // like tags. For the editable cue sheet, we'll show the landmarks
            // as a list that the user can enable or disable using checkboxes.
            if ((!G.map.landmark_exp_validation_active)
                || (G.app.landmark_experiment_panel.active_route
                    !== route)) {
               // The route, and hence this landmark, is not part of the
               // experiment.
               if ((l.item_type_id == Item_Type.WAYPOINT)
                   // [lb] wonders: are we confident enough to include
                   //      a few others landmark types?
                   || (l.item_type_id == Item_Type.BYWAY)
                   || (l.item_type_id == Item_Type.LANDMARK_T)
                   ) {
                  l.display = true;
               }
            }
            // else, the landmark applies to a route in the experiment, so let
            //       the user enable the landmark him/herself.
            if (l.display) {
               if (l.item_type_id == Item_Type.TAG) {
                  tags.push(l);
               }
               else if (l.item_type_id == Item_Type.BYWAY) {
                  crossings.push(l);
               }
               else if (l.item_type_id == Item_Type.LANDMARK_T) {
                  t_inter = l;
               }
               else if (l.item_type_id == Item_Type.LANDMARK_OTHER) {
                  other = l;
               }
               else if ((l.item_type_id == Item_Type.WAYPOINT
                        || l.item_type_id == Item_Type.TERRAIN)) {
                  pois_terrains.push(l);
               }
            }
         }

         // add tags
         if (tags.length > 0) {
            dir_str += ' (<i>'
               + (show_url ? Landmark.generate_link(tags[0]) : tags[0].name);
            for (var i:int=1; i < tags.length; i++) {
               dir_str += '</i>, <i>'
                  + (show_url ? Landmark.generate_link(tags[i])
                              : tags[i].name);
            }
            dir_str += '</i>)';
         }

         // add T intersection information
         if (t_inter !== null) {
            // MAGIC_NUMBER: The href tag is so we can sneak a value into the
            //   TextFormat's url member. -1 indicates T-intersection remark.
            dir_str += Landmark.generate_color(t_inter,
               show_url ? " <a href='-1'>at the T</a>" : " at the T");
         }

         // major hwy crossings
         if (crossings.length > 0) {
            dir_str += ' after crossing '
               + (show_url ? Landmark.generate_link(crossings[0])
                           : crossings[0].name);
            for (var j:int=1; j < crossings.length; j++) {
               dir_str += ' and '
                 + (show_url ? Landmark.generate_link(crossings[j])
                             : crossings[j].name);
            }
         }

         // terrains and POIs
         // TODO: polygons that span more than one quadrant
         var l_before_left:Array = new Array();
         var l_before_right:Array = new Array();
         var l_after_left:Array = new Array();
         var l_after_right:Array = new Array();
         if (pois_terrains.length > 0) {
            var before:Boolean;
            var after:Boolean;
            var left:Boolean;
            var right:Boolean;
            for each (l in pois_terrains) {
               before = false;
               after = false;
               left = false;
               right = false;
               for each (ang in l.angles) {
                  if (ang > 0 && ang < 180) {
                     before = true;
                  }
                  else {
                     after = true;
                  }
                  if (ang > 90 && ang < 270) {
                     left = true;
                  }
                  else {
                     right = true;
                  }
               }
               if (before && left && !after && !right) {
                  l_before_left.push(l);
               }
               else if (before && right && !after && !left) {
                  l_before_right.push(l);
               }
               else if (after && left && !before && !right) {
                  l_after_left.push(l);
               }
               else if (after && right && !before && !left) {
                  l_after_right.push(l);
               }
            }

            // add text
            if (l_after_left.length > 0 || l_after_right.length > 0) {
               dir_str += ' after ';
               if (l_after_left.length > 0) {
                  dir_str +=
                     generate_landmark_namelist_str(l_after_left, show_url)
                     + ' on the left';
               }
               if (l_after_right.length > 0) {
                  if (l_after_left.length > 0) {
                     dir_str += ' and ';
                  }
                  dir_str +=
                     generate_landmark_namelist_str(l_after_right, show_url)
                     + ' on the right';
               }
            }

            if (l_before_left.length > 0 || l_before_right.length > 0) {
               if (l_after_left.length > 0 || l_after_right.length > 0) {
                  dir_str += ' and';
               }
               dir_str += ' before ';
               if (l_before_left.length > 0) {
                  dir_str +=
                     generate_landmark_namelist_str(l_before_left, show_url)
                     + ' on the left';
               }
               if (l_before_right.length > 0) {
                  if (l_before_left.length > 0) {
                     dir_str += ' and ';
                  }
                  dir_str +=
                     generate_landmark_namelist_str(l_before_right, show_url)
                     + ' on the right';
               }
            }
         }

         // add 'other' landmark
         if ((other !== null) && (other.name !== null) && (other.name != '')) {
            // MAGIC_NUMBER: The href tag is so we can sneak a value into the
            //   TextFormat's url member. -2 indicates this "other" landmark.
            dir_str += Landmark.generate_color(other,
               show_url ? " (<a href='-2'>" + other.name + '</a>)' :
                          (' (' + other.name + ')'));
         }

         return dir_str + '</font>';
      }

      // Merges landmarks into an "and" list.
      public static function generate_landmark_namelist_str(landmarks:Array,
                                                            show_url:Boolean)
         :String
      {
         if (landmarks.length == 0) {
            return '';
         }
         else if (landmarks.length == 1) {
            return show_url ? Landmark.generate_link(landmarks[0])
                            : landmarks[0].name;
         }
         else if (landmarks.length == 2) {
            return (show_url ? Landmark.generate_link(landmarks[0])
                             : landmarks[0].name)
               + ' and '
               + (show_url ? Landmark.generate_link(landmarks[1])
                           : landmarks[1].name);
         }
         else {
            var namelist:String;
            namelist = show_url ? Landmark.generate_link(landmarks[0])
                                : landmarks[0].name;
            for (var i:int=1; i < landmarks.length; i++) {
               namelist += ', ';
               if (i == landmarks.length - 1) {
                  namelist += 'and ';
               }
               namelist +=
                  show_url ? Landmark.generate_link(landmarks[i])
                             : landmarks[i].name;
            }
            return namelist;
         }
      }
      
      //
      public static function generate_color(landmark:Landmark,
                                            str:String) :String
      {
         if (landmark.moused_over) {
            return '<font color=\'#AA00AA\'>' + str + '</font>'; // Purple.
         }
         else if (landmark.rating == -1) {
            return '<font color=\'#0000AA\'>' + str + '</font>'; // Blue.
         }
         else if (landmark.rating == 1) {
            return '<font color=\'#00AA00\'>' + str + '</font>'; // Green.
         }
         else {
            return '<font color=\'#AA0000\'>' + str + '</font>'; // Red.
         }
      }

      //
      public static function generate_link(landmark:Landmark) :String
      {
         // MAGIC_NUMBER: The href tag is so we can sneak a value into the
         //   TextFormat's url member. -1 indicates T-intersection remark.
         var lmark_link:String;
         lmark_link = Landmark.generate_color(landmark,
            "<a href='" + landmark.item_id + "'>" + landmark.name + "</a>");
         m4_TALKY('generate_link: lmark_link:', lmark_link);
         return lmark_link;
      }

      //
      public function toString() :String
      {
         return (getQualifiedClassName(this)
                 + ' [ "' + this.name
                 + '" | xs.len:' + ((xs !== null) ? xs.length : 'null')
                 + ' | itm_id: ' + this.item_id
                 + ' | ityp: ' + this.item_type_id
                 + ' | dist: ' + this.dist
                 + ' | nangles: ' + ((this.angles !== null)
                                     ? this.angles.length : 'null')
                 + ' | display: ' + this.display
                 + ' | dstep_i: ' + this.dstep_index
                 + ' ]'
                 );
      }

   }
}


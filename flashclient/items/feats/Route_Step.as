/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.feats {

   import flash.display.Sprite;

   import items.Record_Base;
   import items.utils.Item_Type;
   import items.utils.Landmark;
   import items.utils.Travel_Mode;
   import utils.geom.Geometry;
   import utils.misc.Logging;

   public class Route_Step extends Record_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Route_Step');

      // *** Mandatory attributes

      public static const class_item_type:String = 'route_step';
      public static const class_gwis_abbrev:String = 'rs';
      public static const class_item_type_id:int = Item_Type.ROUTE_STEP;

      // *** Instance variables

      // For cycling steps.

      public var byway_name:String;
      public var byway_system_id:int;
      public var byway_stack_id:int;
      public var byway_version:int;

      public var byway_geofeature_layer_id:int;

      public var node_lhs_elevation_m:Number;
      public var node_rhs_elevation_m:Number;

      // For both cycling and transit steps.

      public var step_name:String;
      public var travel_mode:int;

      public var forward:Boolean;
      public var beg_node_id:int;
      public var fin_node_id:int;
      public var beg_time:int;
      public var fin_time:int;

      public var rating:Number;
      public var bonus_tagged:Boolean;
      public var penalty_tagged:Boolean;

// FIXME: route reactions.
      public var xs:Array;
      public var ys:Array;

      // The beg_index and fin_index are the indices used to access this
      // Route_Step's xs and ys from its owning Route. To fit with the
      // Geofeature paradigm of having a single block of coordinates, Route
      // merges each step's coordinates together, and the step's maintain
      // indices into that.
      public var beg_index:int; // inclusive
      public var fin_index:int; // exclusive

      // The step_length is computed at runtime.
      public var step_length:Number;

      // Landmarks experiment.
      public var landmarks:Array;

      // *** Constructor

      public function Route_Step(xml:XML=null)
      {
         super(xml);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Route_Step = (to_other as Route_Step);
         super.clone_once(other);
         m4_ASSERT(false); // Not implemented.
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Route_Step = (to_other as Route_Step);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         if (gml !== null) {

// FIXME: route reactions.
//            var xs:Array = new Array();
//            var ys:Array = new Array();
            this.xs = new Array();
            this.ys = new Array();

            // cycling
            // FIXME: Use this.byway_id instead?
            this.byway_system_id = int(gml.@byway_id);
            this.byway_stack_id = int(gml.@byway_stack_id);
            this.byway_version = int(gml.@byway_version);
            this.byway_geofeature_layer_id = int(gml.@gflid);
            this.node_lhs_elevation_m = Number(gml.@nel1);
            this.node_rhs_elevation_m = Number(gml.@nel2);
            // both
            this.step_name = gml.@step_name;
            this.beg_time = int(gml.@beg_time);
            this.fin_time = int(gml.@fin_time);
            this.travel_mode = int(gml.@travel_mode);
            this.rating = Number(gml.@rating);
            this.bonus_tagged = Boolean(int(gml.@bonus_tagged));
            this.penalty_tagged = Boolean(int(gml.@penalty_tagged));
            this.beg_node_id = int(gml.@nid1);
            this.fin_node_id = int(gml.@nid2);
            this.forward = Boolean(int(gml.@forward));

            // FIXME: Why doesn't pyserver send the step length?
//            this.step_length = Number(gml.@length);
            this.step_length = 0;
//            Geometry.coords_string_to_xys(gml.text(), xs, ys);
            Geometry.coords_string_to_xys(gml.text(), this.xs, this.ys);
            for (var i:int = 0; i < xs.length - 1; i++) {
               this.step_length += Geometry.distance(xs[i], ys[i],
                                                     xs[i + 1], ys[i + 1]);
            }

            // Landmarks experiment.
            if ('landmark' in gml) {
               var xml:XMLList = gml.landmark;
               var lmrk_xml:XML;
               this.landmarks = new Array();
               for each (lmrk_xml in xml) {
                  var new_lmark:Landmark = new Landmark(lmrk_xml)
                  new_lmark.dstep_index = this.landmarks.length;
                  this.landmarks.push(new_lmark);
               }
            }
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         m4_ASSERT(false); // See Route.gml_produce.
         return gml;
      }

      // ***

      //
      public function get grade() :Number
      {
         var grade_direction:Number = (this.forward) ? 1 : -1;
         // FIXME: This should be node_beg_elevation and node_end_elevation
         //        to match beg_node_id. or maybe node_beg_stack_id?
         var grade:Number = ((node_rhs_elevation_m - node_lhs_elevation_m)
                             * (grade_direction / step_length));

         return grade;
      }

      // *** Instance methods

      //
      // SIMILAR_TO: Byway.is_endpoint()
      public function is_endpoint(i:int) :Boolean
      {
         return ((i == this.beg_index) || (i == (this.fin_index - 1)));
      }

      // ***

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' | bway: ' + this.byway_name
                 + ' ' + this.byway_stack_id
                 + '.v' + this.byway_version + ' '
                 + ' | step_nom ' + this.step_name
                 + ' | txmode: ' + Travel_Mode.lookup[this.travel_mode]
                 + ' | fwd? ' + this.forward
                 + ' | beg_nid ' + this.beg_node_id
                 + ' | fin_nid ' + this.fin_node_id
                 + ' | beg_i ' + this.beg_index
                 + ' | fin_i ' + this.fin_index
                 + ' | xs.len ' + ((this.xs !== null)
                                   ? this.xs.length : 'none')
                 + ' | ys.len ' + ((this.ys !== null)
                                   ? this.ys.length : 'none')
                 + ' | step_len ' + this.step_length
                 + ' | lmks.len ' + ((this.landmarks !== null)
                                     ? this.landmarks.length : 'none')
                 );
      }

      // ***

   }
}


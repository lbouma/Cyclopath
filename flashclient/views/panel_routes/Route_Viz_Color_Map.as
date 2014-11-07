/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import items.feats.Route_Step;
   import items.utils.Geofeature_Layer;
   import items.utils.Travel_Mode;
   import utils.misc.Logging;

   public class Route_Viz_Color_Map {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@Rt_Viz_CMap');

      // *** Constructor

      public function Route_Viz_Color_Map() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class methods

      // Create a function to map labels to colors
      private static function color_for_label_func(colors:Array) :Function
      {
         function color_for_label(label:String) :int
         {
            var i:int;
            for (i = 0; i < colors.length; i++) {
               if (colors[i].label == label) {
                  return colors[i].hex;
               }
            }
            // if the label can't be found use default route color
            return Conf.route_color;
         }
         return color_for_label;
      }

      //
      public static function BYWAY_LAYER(step:Route_Step) :int
      {
         var color:int;
         var color_fcn:Function;
         color_fcn = color_for_label_func(Conf.byway_layer_route_colors);

         switch (step.byway_geofeature_layer_id) {
            case Geofeature_Layer.BYWAY_MAJOR_ROAD:
               color = color_fcn('Major Road');
               break;
            case Geofeature_Layer.BYWAY_MAJOR_TRAIL:
               color = color_fcn('Major Trail');
               break;
            case Geofeature_Layer.BYWAY_BIKE_TRAIL:
               color = color_fcn('Bike Trail');
               break;
            case Geofeature_Layer.BYWAY_SIDEWALK:
               color = color_fcn('Sidewalk');
               break;
            case Geofeature_Layer.BYWAY_LOCAL_ROAD:
               // Fall-through:
            default:
               color = color_fcn('Local Road');
               break;
         }

         return color;
      }

      //
      public static function BONUS_OR_PENALTY_TAGGED(step:Route_Step) :int
      {
         var c:Function
            = color_for_label_func(Conf.bonus_or_penalty_tagged_route_colors);

         if (step.bonus_tagged || step.penalty_tagged) {
            return c(  'Bonus/Penalty Tag'  );
         }
         else  {
            return c(  'Normal'             );
         }
      }

      //
      public static function DEFAULT(step:Route_Step) :int
      {
         return Conf.route_color;
      }

      //
      public static function GRADE(step:Route_Step) :int
      {
         // Calculate the type of slope from the grade of the byway
         // Ranges: Downhill Steep (..,-8] Moderate (-8,-4] Slight (-4,-1.5]
         //         Level (-1.5, 1.5)
         //         Uphill Slight [1.5,4) Moderate [4,8) Steep (8,..)
         // This is based off of the 0, 2, 6, 10 categorization found at
         // http://www.roberts-1.com/bikehudson/r/m/hilliness/index.htm
         // where those grades are approximate centers for our ranges.

         var grade:Number = 100 * step.grade;
         var c:Function = color_for_label_func(Conf.grade_route_colors);

         if (grade >= 8) {
            //return c('Steep Uphill');
            return c('Uphill');
         }
         else if (grade >= 4) {
            return c('Moderate Uphill');
         }
         else if (grade >= 1.5) {
            return c('Slight Uphill');
         }
         else if (grade > -1.5) {
            return c('Level');
         }
         else if (grade > -4) {
            return c('Slight Downhill');
         }
         else if (grade > -8) {
            return c('Moderate Downhill');
         }
         else {
            //return c('Steep Downhill');
            return c('Downhill');
         }
      }

      //
      public static function RATING(step:Route_Step) :int
      {
         var c:Function = color_for_label_func(Conf.rating_route_colors);

         if (step.rating < 2.5) {
            return c('Poor');
         }
         else if (step.rating < 3.5) {
            return c('Fair');
         }
         else if (step.rating < 4.5) {
            return c('Good');
         }
         else {
            return c('Excellent');
         }
      }

      // for multimodal routes
      // MAYBE: The uppercasing on the fcns in the file feels weird.
      public static function TRANSIT_TYPE(step:Route_Step) :int
      {
         var c:Function = color_for_label_func(Conf.travel_mode_route_colors);

         if (step.travel_mode == Travel_Mode.bicycle) {
            return c('Bicycle');
         }
         else {
            // MAYBE: Before route manip, we distinguished between trains and
            //        busses...
            return c('Bus/Train');
         }
      }

   }
}


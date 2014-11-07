/* Copyright (c) 2006-2010 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import mx.core.UIComponent
   import mx.validators.Validator;
   import mx.validators.ValidationResult;

   import utils.misc.Logging;

   public class Route_Stop_Validator extends Validator {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@Rt_Stop_V');

      // *** Instance methods

      //
      override protected function doValidation(src:Object) :Array
      {
         var rt_stop:Route_Stop = (src as Route_Stop);

         if (rt_stop.name_ == '') {
            return [new ValidationResult(true,
                                         '',
                                         'empty',
                                         'Address is required')];
         }
         if (isNaN(rt_stop.x_map) || isNaN(rt_stop.y_map)) {
            return [new ValidationResult(true,
                                         '',
                                         'geocode',
                                         'Address not found')];
         }

         return [];
      }
   }

}


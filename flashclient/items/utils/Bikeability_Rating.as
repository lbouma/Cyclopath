/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   import flash.utils.*;

   import utils.misc.Logging;

   public class Bikeability_Rating {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Bikeaby_Rat');

      // ***

      public static const BIKEABILITY_VARIES:int = -2;

      public static const BIKEABILITY_UNKNOWN:int = -1;

      //public static const BIKEABILITY_IMPASSABLE:int = 0;
      public static const BIKEABILITY_AVOID:int = 0;
      public static const BIKEABILITY_POOR:int = 1;
      public static const BIKEABILITY_FAIR:int = 2;
      public static const BIKEABILITY_GOOD:int = 3;
      public static const BIKEABILITY_EXCELLENT:int = 4;

      // ***

      // NOTE: This value is never referenced:
      public static const rating_max:Number = 4;

      // Key-value pairs for matching numeric ratings with text descriptors.
      // WARNING: This is not the only place in the application where this
      // mapping is stated. Words must follow rules for identifiers.
      public static const rating_names:Object =
         {
         //0: 'Impassable',
         0: 'Avoid',
         1: 'Poor',
         2: 'Fair',
         3: 'Good',
         4: 'Excellent'
         };

      // ***

      // Return a string representing the given rating, suitable for use in
      // identifiers. There is no 1-to-1 mapping between strings and ratings.
      public static function rating_number_to_token(rating:Number) :String
      {
         // NOTE: This fcn. is never called.
         if (rating < 0) {
            return 'unknown';
         }
         else {
            return Bikeability_Rating.rating_names[int(Math.round(rating))]
               .toLowerCase().replace(/\W+/g, '');
         }
      }

      // Return a human-readable string representing the given rating.
      public static function rating_number_to_words(rating:Number) :String
      {
         var use_your_words:String;
         if (rating == Bikeability_Rating.BIKEABILITY_VARIES) { // -2
            use_your_words = "Varies";
         }
         else if (rating == Bikeability_Rating.BIKEABILITY_UNKNOWN) { // -1
            use_your_words = "Don't know";
         }
         else {
            //m4_ASSURT((rating >= Bikeability_Rating.BIKEABILITY_IMPASSABLE)
            m4_ASSURT((rating >= Bikeability_Rating.BIKEABILITY_AVOID)
                  && (rating <= Bikeability_Rating.BIKEABILITY_EXCELLENT));
               //&& (rating <= (Bikeability_Rating.BIKEABILITY_EXCELLENT+1)));
            use_your_words =
               Bikeability_Rating.rating_names[int(Math.round(rating))];
         }
         return use_your_words;
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import mx.formatters.DateFormatter;
   import mx.utils.StringUtil;

   public class Timeutil {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('__Timeutil__');

      // http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3
      //                      /mx/formatters/DateFormatter.html#formatString
      protected static const date_fmttr:DateFormatter = new DateFormatter();
      //protected static const date_fmt_s:String = 'MMM-DD JJ:NN:SS';
      // EEEE, MMM. D, YYYY at L:NN:QQQ A
      //  = Tuesday, Sept. 8, 2005 at 1:26:012 PM
      // More brevity, e.g., "Mon, Jun 12 1:12 PM":
      protected static const date_fmt_s:String = 'EEE, MMM DD L:NN A';
      Timeutil.date_fmttr.formatString = date_fmt_s;

      public static const DAYS_PER_YEAR:Number = 365.25;
      public static const DAYS_PER_MONTH:Number = DAYS_PER_YEAR / 12.0; // 30.4
      public static const DAYS_PER_WEEK:Number = 7;
      public static const WEEKS_PER_YEAR:Number =   DAYS_PER_YEAR
                                                  / DAYS_PER_WEEK; // 52.2
      public static const WEEKS_PER_MONTH:Number =   DAYS_PER_MONTH
                                                   / DAYS_PER_WEEK; // 4.3
      public static const MONTHS_PER_YEAR:Number = 12;
      //
      public static const HOURS_PER_DAY:Number = 24;
      public static const MINUTES_PER_HOUR:Number = 60;
      public static const SECONDS_PER_MINUTE:Number = 60;
      public static const MILLISECONDS_PER_SECOND:Number = 1000;
      //
      public static const MSECS_PER_DAY:Number =
                                               Timeutil.MILLISECONDS_PER_SECOND
                                             * Timeutil.SECONDS_PER_MINUTE
                                             * Timeutil.MINUTES_PER_HOUR
                                             * Timeutil.HOURS_PER_DAY;
      public static const MSECS_PER_YEAR:Number =
                                               Timeutil.MSECS_PER_DAY
                                             * Timeutil.DAYS_PER_YEAR;

      protected static const recency_ranges:Array =
         [
            { msec_limit:   Timeutil.SECONDS_PER_MINUTE
                          * Timeutil.MILLISECONDS_PER_SECOND,
              adjustment: Timeutil.SECONDS_PER_MINUTE,
              new_units:  'secs' },
            { msec_limit:   Timeutil.MINUTES_PER_HOUR
                          * Timeutil.SECONDS_PER_MINUTE
                          * Timeutil.MILLISECONDS_PER_SECOND,
              adjustment: Timeutil.MINUTES_PER_HOUR,
              new_units:  'mins' },
            { msec_limit:   Timeutil.HOURS_PER_DAY
                          * Timeutil.MINUTES_PER_HOUR
                          * Timeutil.SECONDS_PER_MINUTE
                          * Timeutil.MILLISECONDS_PER_SECOND,
              adjustment: Timeutil.HOURS_PER_DAY,
              new_units:  'hrs' },
            { msec_limit:   Timeutil.DAYS_PER_WEEK
                          * Timeutil.HOURS_PER_DAY
                          * Timeutil.MINUTES_PER_HOUR
                          * Timeutil.SECONDS_PER_MINUTE
                          * Timeutil.MILLISECONDS_PER_SECOND,
              adjustment: Timeutil.DAYS_PER_WEEK,
              new_units:  'days' },
            { msec_limit:   Timeutil.WEEKS_PER_MONTH
                          * Timeutil.DAYS_PER_WEEK
                          * Timeutil.HOURS_PER_DAY
                          * Timeutil.MINUTES_PER_HOUR
                          * Timeutil.SECONDS_PER_MINUTE
                          * Timeutil.MILLISECONDS_PER_SECOND,
              adjustment: Timeutil.WEEKS_PER_MONTH,
              new_units:  'weeks' },
            { msec_limit: Timeutil.MSECS_PER_YEAR,
              adjustment: Timeutil.MONTHS_PER_YEAR,
              new_units:  'months' },
            { msec_limit: Number.POSITIVE_INFINITY,
              adjustment: Timeutil.MSECS_PER_YEAR,
              new_units:  'years' }
         ];

      // *** Constructor

      public function Timeutil() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Public static class methods

      //
      // MAYBE: This just prints time in minutes.
      //        Should we print hours for longer times?
      public static function total_time_to_pretty_string(
         total_time:Number, units:Boolean = true) :String
      {
         if (units) {
            return (int(total_time / 60) + 1).toString() + ' min';
         }
         else {
            return (int(total_time / 60) + 1).toString();
         }
      }

      //
      public static function epoch_time_to_pretty_string(time:int) :String
      {
         var timestr:String = new Date(time * 1000).toLocaleTimeString();
         timestr = timestr.slice(0, 5) + timestr.slice(8, 11); // exclude sec
         if (timestr.charAt(0) == '0') {
            timestr = timestr.slice(1, 9);
         }
         return timestr;
      }

      //
      public static function datetime_to_recency(secs_since_epoch:int) :String
      {
         // BUG nnnn: This fcn. assumes the timezone on the server and that on
         //           the client are the same, but this is not necessarily a
         //           valid assumption. (Are the TZs set according to the local
         //           machine, or are there CONFIG values? I think local
         //           machine.)
         var friendly_recency:String = null;
         var rightnows_date:Date = new Date();
         var msecs_elapsed:int = int(rightnows_date.time
               - (secs_since_epoch * Timeutil.MILLISECONDS_PER_SECOND));
         m4_VERBOSE2('datetime_to_recency: now:', rightnows_date,
                     '/ elp:', msecs_elapsed);
         if (msecs_elapsed == 0) {
            friendly_recency = "Never";
         }
         else {
            for each (var o:Object in Timeutil.recency_ranges) {
               m4_VERBOSE(' >> o:', o);
               if (msecs_elapsed < o.msec_limit) {
                  var timeval:int = int((msecs_elapsed / o.msec_limit)
                                        * o.adjustment);
                  var unitval:String;
                  if (timeval == 1) {
                     unitval = Inflector.singularize(o.new_units);
                  }
                  else {
                     unitval = o.new_units;
                  }
                  friendly_recency = StringUtil.substitute('{0} {1} ago',
                                                           timeval, unitval);
                  break;
               }
            }
         }
         m4_ASSERT(friendly_recency !== null);
         return friendly_recency;
      }

      //
      public static function datetime_to_friendlier(
         datetime:Object, date_fmt:String) :String
      {
         var friendly_date:String;
         if (date_fmt !== null) {
            Timeutil.date_fmttr.formatString = date_fmt;
         }
         else {
            Timeutil.date_fmttr.formatString = Timeutil.date_fmt_s;
         }
         friendly_date = Timeutil.date_fmttr.format(datetime);
         return friendly_date;
      }

      //
      public static function time_24_now() :String
      {
         var time_24_now:String;
         var rightnows_date:Date = new Date();
         // A  am/pm indicator.
         // L  Hour in am/pm (1-12).
         // N  Minute in hour.
         const date_fmt_s:String = 'L:NN A';
         Timeutil.date_fmttr.formatString = date_fmt_s;
         time_24_now = Timeutil.date_fmttr.format(rightnows_date);
         return time_24_now;
      }

   }
}


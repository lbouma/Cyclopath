/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* The Logging class is an implementation of Python's logging facility in Flex.
   Its output looks something like this:

      Feb-20 11:16:59     INFO gwis    Fetch: gwis8 http://localhost:8080/...
      Feb-20 11:17:00     INFO gwis    Total: gwis5 3427ms for 0 bytes
      Feb-20 11:17:02     INFO map     0 added, 204 skipped, 204 total features
 */

/* BUG nnnn: Allow developer-specific trace messages.
   Can probably just use m4 macros, e.g.,
     m4_DEBUG --> lb_DEBUG.
*/

package utils.misc {

   import flash.utils.Dictionary;
   import mx.formatters.DateFormatter;

   public class Logging {

      // *** Protected Static members

      //
      protected static var logging_level_default:String = 'INFO';

      // Class-wide lookup table; types of log messages are ordered by
      // severity so users can turn up and down the volume.
      // SYNC_ME: Search: LOGGING LEVELS.
      public static const lookup_obj:Array =
         [
            /* Out of bounds. */
            //{ e_key:  -1, e_val:  'invalid' },
            //{ e_key:   0, e_val:   'notset' },
            /* */
            { e_key:   0, e_val:    'NOTSET' },
            { e_key:   5, e_val:   'VERBOSE' },
            { e_key:   8, e_val:     'TALKY' },
            { e_key:  10, e_val:     'DEBUG' },
            { e_key:  20, e_val:      'INFO' },
            { e_key:  30, e_val:   'WARNING' },
            { e_key:  40, e_val:     'ERROR' },
            { e_key:  50, e_val:  'CRITICAL' }
         ];
      public static var lookup_key:Dictionary = new Dictionary();
      public static var lookup_val:Dictionary = new Dictionary();
      private static function hack_attack() :void
      {
         for each (var o:Object in lookup_obj) {
            //trace('hack_attack: e_key:', o.e_key, '/ e_val:', o.e_val);
            lookup_key[o.e_key] = o.e_val;
            lookup_val[o.e_val] = o.e_key;
         }
      }
      // The first time anyone loads this class, initialize the lookups.
      hack_attack();

      // Like Python's logging facility, you can have more than one logger,
      // each with a unique name, and you can tune each one separately. The
      // loggers are typically named using a dot-separated hierarchical name,
      // i.e., "a", "a.b", "a.b.c", etc.
      public static var loggers:Dictionary = new Dictionary();

      protected static var date_formatter:DateFormatter = new DateFormatter();
      protected static var _date_format_string:String = 'MMM-DD JJ:NN:SS';
      Logging.date_formatter.formatString = _date_format_string;
      protected static var _padded_len_date:int = _date_format_string.length;

      // Define column widths for the name and level
      protected static var _padded_len_name:int = 12;
      protected static var _padded_len_level:int = 8;
      // Define the width for the message -- for folks that like wide terminals
      // when tail'g the Flash log, we use a wide default.
      protected static var _padded_len_line_msg:int = 0; // 0: Disabled
      protected static var _padded_len_line_intro:int = _padded_len_date
                                                        + ' '.length
                                                        + _padded_len_name
                                                        + ' '.length
                                                        + _padded_len_level
                                                        + ' '.length;
      // If a message is longer than the msg width, we'll wrap it to the next
      // line, but we won't print the date, name and level again (we'll print
      // this many spaces instead) ALSO Add 2 spaces so it's indented a little.
      protected static var _padded_line_intro:String =
         Strutil.string_pad('', _padded_len_line_intro + 2, ' ', true);

      // The logging style version is 0: Off, 1: trace(), 2: formatted output.
      protected static var _logging_style_version:int = 2;

      protected static var nl_pat:RegExp = /[\n\r]/g;

      // *** Instance members

      protected var _name:String;
      protected var _name_padded:String;

      // The current log level. Only log messages with a severity equal to or
      // greater than this will be logged, and the rest will be ignored.
      //protected var _level:int = 30; // i.e., 'WARNING'
      protected var _level:int = lookup_val['WARNING'];

      // FIXME: Ideas from Python's logging:
      //        filename, filemode, format, datefmt, stream
      //        addLevelName, getLevelName, shutdown

      // *** Constructor

      // Creates a new Logging class.
      public function Logging(logger_name:String) :void
      {
         // Singleton fcn.
         this._name = logger_name;
         this._name_padded = Strutil.string_pad(
            logger_name, _padded_len_name, ' ', true);
         this._level = Logging.get_level_key(Logging.logging_level_default);
      }

      // *** Factory method

      //
      public static function get_logger(logger_name:String) :Logging
      {
         if (!(Logging.loggers.hasOwnProperty(logger_name))) {
            Logging.loggers[logger_name] = new Logging(logger_name);
         }
         return Logging.loggers[logger_name];
      }

      // *** Static class methods

      //
      public static function add_level_name(level_key:int,
                                            level_str:String) :void
      {
         Logging.lookup_key[level_key] = level_str;
         Logging.lookup_val[level_str] = level_key;
      }

      //
      public static function get_level_str(level_key:int) :String
      {
         return Logging.lookup_key[level_key];
      }

      //
      public static function get_level_key(level_str:String) :int
      {
         return Logging.lookup_val[level_str];
      }

      //
      public static function init_formatting(column_width:int = 0,
                                             style_version:int = 2) :void
      {
         Logging._padded_len_line_msg = column_width;
         Logging._logging_style_version = style_version;
      }

      // FIXME Implement Python's logging facility's disable(lvl)

      // *** Getters/Setters/Configurators

      // Returns the name of the logger
      public function get name() :String
      {
         return this._name;
      }

      // NOTE Python uses basicConfig(...) to configure the logger. For now, we
      //      only have one thing to set, so let's not implement basicConfig.

      // Returns the current log threshold
      public function get current_level() :int
      {
         return this._level;
      }

      // Sets the log threshold. Only messages with a level greater than or
      // equal to the log threshold will be logged; others will be tossed.
      public function set level(level:Object) :void
      {
         // trace('Logging: set level: to', level, 'on', this._name);
         var minimum_level:int;
         if (level is int) {
            minimum_level = (level as int);
         }
         else if (level is String) {
            minimum_level = Logging.get_level_key((level as String));
         }
         else {
            m4_ASSERT(false);
         }
         this._level = minimum_level;
      }

      // *** Convenience methods

      //
      public function verbose(...args) :void
      {
         this.log(Logging.get_level_key('VERBOSE'), args);
      }

      //
      public function talky(...args) :void
      {
         this.log(Logging.get_level_key('TALKY'), args);
      }

      //
      public function debug(...args) :void
      {
         this.log(Logging.get_level_key('DEBUG'), args);
      }

      //
      public function info(...args) :void
      {
         this.log(Logging.get_level_key('INFO'), args);
      }

      //
      public function warning(...args) :void
      {
         this.log(Logging.get_level_key('WARNING'), args);
      }

      //
      public function error(...args) :void
      {
         this.log(Logging.get_level_key('ERROR'), args);
      }

      //
      public function critical(...args) :void
      {
         this.log(Logging.get_level_key('CRITICAL'), args);
      }

      //
      public function exception(...args) :void
      {
         this.log(Logging.get_level_key('ERROR'), args);
      }

      // *** The log method
      public function log(level:Object, ...args) :void
      {
         if (Logging._logging_style_version == 1) {
            trace(args.join(' '));
         }
         else if (Logging._logging_style_version == 2) {
            // This lets you filter log messages at runtime, but the args
            // still get computed, so this doesn't have a performance benefit
            // like using m4 to omit log messages does.
            if (args[0] is Array) {
               args = args[0];
            }
            this.log_v2(level, args);
         }
         else {
            m4_ASSERT(Logging._logging_style_version == 0);
         }
      }

      //
      public function log_v2(level:Object, ...args) :void
      {
         // The level may be specified by its name or number
         if (level is String) {
            level = Logging.get_level_key((level as String));
         }
         if ((level as int) >= this._level) {
            var the_msg:String;
            var msg_lines:Array = new Array();
            // The args might be an array already if we got thunked to from
            // one of the convenience fcns.
            if (args[0] is Array) {
               args = args[0];
            }
            // Split longs line into multiple lines so they don't wrap and
            // stomp all over the pretty date, level, and name columns
            the_msg = args.join(' ');
            //the_msg = args.join(' ').replace(nl_pat, _padded_line_intro);
            while (the_msg.length > 0) {
               // (1) Newlines in the_msg mess things up, so look for them.
               //     If the trace message contains newlines, it's generally a
               //     Flash stacktrace, so let's not split it up further.
               var nl_idx:int = the_msg.search(Logging.nl_pat);
               // FIXME This isn't perfect; should probably not pad, just use
               //       existing newlines in the message...
               if (nl_idx != -1) {
                  msg_lines.push(the_msg);
                  the_msg = '';
               }
               //if ((nl_idx != -1) && (nl_idx <= _padded_len_line_msg)) {
               //   var short_len:int = nl_idx + 1;
               //   msg_lines.push(the_msg.substr(0, short_len));
               //   the_msg = the_msg.substr(short_len);
               //}
               else if (Logging._padded_len_line_msg > 0) {
                  msg_lines.push(
                     the_msg.substr(0, Logging._padded_len_line_msg));
                  the_msg = the_msg.substr(Logging._padded_len_line_msg);
               }
               else {
                  msg_lines.push(the_msg);
                  the_msg = '';
               }
            }
            // Iterate over the individual output lines
            for (var idx:int = 0; idx < msg_lines.length; idx++) {
               if (idx == 0) {
                  // Format data like Python's logging, like
                  //   'Feb-13 11:32:33 INFO   root: blah blah blah'
                  trace(Logging.date_formatter.format(
                        new Date()) + ' '
                        + Strutil.string_pad(
                                   Logging.get_level_str(level as int),
                                   _padded_len_level, ' ', false) + ' '
                        + this._name_padded + ' '
                        + msg_lines[idx]);
               }
               else {
                  // Subsequent line; format without the date, etc., e.g.,
                  //   '                             line2 line2 line2'
                  trace(_padded_line_intro + msg_lines[idx]);
               }
            } // for
         }
      }

   }
}


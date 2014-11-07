/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.utils.Dictionary;
   import mx.formatters.DateFormatter;
   import mx.utils.StringUtil;

   public class Strutil {

      // *** Class attributes

      // Creating the logger causes a problem on global$init because the
      // Logging class uses us....
      //   TypeError: Error #1009: Cannot access a property or method of a
      //   null object reference.
      // Cannot:
      //   protected static var log:Logging = Logging.get_logger('Strutil');

      // An array of uppercase letters
      public static const letters_uc:Array
         = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

      // *** Constructor

      public function Strutil() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Public static class methods

      //
      public static function as_hex(num:*) :String
      {
         var as_hex:String = 'null';
         if (num !== null) {
            try {
               // Note that numbers will be integerized, e.g.,
               // Strutil.as_hex(10.34) -> 0xa.
               as_hex = '0x' + num.toString(16);
            }
            catch (e:ArgumentError) {
               // E.g., Strutil.as_hex('zzz').
               //as_hex = 'n/a';
               as_hex = String(num);
            }
            catch (e:TypeError) {
               //as_hex = 'type?';
               as_hex = String(num);
            }
         }
         return as_hex;
      }

      // Capitalizes underscore delimited works,
      //    e.g., foo_bar => Foo_Bar
      //
      public static function capitalize_underscore_delimited(wrds:String)
         :String
      {
         var capped:String;
         capped = wrds.replace(
            /_./g, function(...m) : String
               { return m[0].toUpperCase()} );
         // I [lnb] couldn't get the regex to do the first char, so...
         capped = capped.substr(0, 1).toUpperCase() + capped.substr(1);
         return capped;
      }

      //
      // Given, e.g., "a.b.c.d", returns "d".
      public static function class_name_tail(instance_name:String,
                                             num_classes:int=1) :String
      {
         // See: http://help.adobe.com/en_US/FlashPlatform/reference/
         //         actionscript/3/String.html#lastIndexOf%28%29
         //var startIndex:int = 0x7FFFFFFF;
         var startIndex:int = instance_name.length + 1;
         while (num_classes > 0) {
            //startIndex = instance_name.lastIndexOf('.', startIndex);
            startIndex = instance_name.lastIndexOf('.', startIndex - 1);
            num_classes -= 1;
         }
         if (startIndex != -1) {
            instance_name = instance_name.substr(startIndex + 1);
         }
         return instance_name;
      }

      //
      public static function collapse_dict(collection:*,
                                           default_msg:String='',
                                           delimiter_str:String=', ')
         :String
      {
         var collapsed:String;
         var kvals:Array = new Array();

         var dict:Dictionary = (collection as Dictionary);
         if (dict !== null) {
            var key:String;
            var value:int;
            for (key in dict) {
               value = dict[key];
               // EXPLAIN: So, if value is an integer, put it in parantheses
               //          after the key, otherwise just compile list of keys?
               if (value > 1) {
                  kvals.push(key + ' (' + dict[key] + ')');
               }
               else {
                  kvals.push(key);
               }
            }
         }
         else {
            var obj:Object;
            for each (obj in collection) {
               kvals.push(obj.toString());
            }
         }

         collapsed = kvals.join(delimiter_str);

         if (collapsed == '') {
            collapsed = default_msg;
         }

         return collapsed;
      }

      // Compares two strings, ignoring case.
      public static function equals_ignore_case(s1:String, s2:String) :Boolean
      {
         return (s1.toLowerCase() == s2.toLowerCase());
      }

      //
      // Ideally, Flex's UIDUtil would let you try to make UUIDs from strings,
      // so we could just test the string that way, but, alas, UIDUtil only
      // makes UUIDs, so it's up to us to verify 'em.
      public static function is_uuid(maybe_uuid:String) :Boolean
      {
         // A UUID is a 16-octet (128-bit) number. In its canonical form ...
         // 8-4-4-4-12 for a total of 36 characters (32 alphanumeric characters
         // and four hyphens). For example:
         //   550e8400-e29b-41d4-a716-446655440000 
         // *[1]: https://en.wikipedia.org/wiki/Universally_unique_identifier
         var passed:Boolean;
         const num_octets_in_uuid:int = 32;
         const re:RegExp = new RegExp('^[-a-fA-F0-9]+$', 'i');
         const pattern:RegExp = /-/g;
         maybe_uuid = maybe_uuid.replace(pattern, '');
         passed = ((maybe_uuid.length == num_octets_in_uuid)
                   && (re.test(maybe_uuid)));
         //trace('is_uuid: is_uuid?:', passed, '/ ', maybe_uuid);
         return passed;
      }

      // Convert a length value (in meters) into an equivalent string, but
      // converted to miles.  If decimal is given, it's the number of decimal
      // points to use.  If units is true, then ' mi' is appended to the end
      // of the string.
      public static function meters_to_miles_pretty(length:Number,
                                                    decimal:int=2,
                                                    units:Boolean=true)
         :String
      {
         // .000621 is the conversion factor from meters to miles
         if (units) {
            return (length * .000621).toFixed(decimal) + ' mi';
         }
         else {
            return (length * .000621).toFixed(decimal);
         }
      }

      //
      public static function merge_names(names:Array) :String
      {
         var mult_names:Object = new Object();
         var names_with_c:Array = new Array();
         var name:String;

         for each (name in names) {
            if (name in mult_names) {
               mult_names[name]++;
            }
            else {
               mult_names[name] = 1;
            }
         }

         for (name in mult_names) {
            if (mult_names[name] > 1) {
               names_with_c.push(name + ' (' + mult_names[name] + ')');
            }
            else {
               names_with_c.push(name);
            }
         }

         return names_with_c.sort().join(', ');
      }

      // Return the time (down to seconds) as a formatted string:
      // YYYY-MM-DD HH:MM:SS
      // If tz is true, includes a (+/-)HH:MM timezone offset.
      public static function now_str(tz:Boolean) :String
      {
         var df:DateFormatter = new DateFormatter();
         var now:Date = new Date();

         var tz_hours:int = Math.abs(now.timezoneOffset) / 60;
         var tz_min:int = Math.abs(now.timezoneOffset) % 60;

         // negate hours because AS3 treats negative as later in day than UTC
         var tz_str:String = (now.timezoneOffset < 0 ? '+' : '-');
         df.formatString = 'YYYY-MM-DD JJ:NN:SS';

         if (!tz) {
            return df.format(now);
         }

         // else build up a timezone string
         if (tz_hours < 10) {
            tz_str += '0' + tz_hours; // pad to 2 digits
         }
         else {
            tz_str += '' + tz_hours; // already 2 digits
         }

         if (tz_min < 10) {
            tz_str += ':0' + tz_min;
         }
         else {
            tz_str += ':' + tz_min;
         }

         return df.format(now) + tz_str;
      }

      //
      public static function snippet(the_text:String,
                                     tease_len:int=20,
                                     reverse:Boolean=false) :String
      {
         var snippet:String = '[null]';
         if (the_text) {
            if (the_text.length > tease_len) {
               if (!reverse) {
                  the_text = the_text.substr(0, tease_len) + '...';
               }
               else {
                  the_text
                     = '...' + the_text.substr(the_text.length - tease_len);
               }
            }
            else {
               the_text = the_text;
            }
         }
         return the_text;
      }

      //
      public static function string_as_lines(str:String) :Array
      {
         var lfpos:int = str.indexOf("\n");
         var crpos:int = str.indexOf("\r");
         var linebreak:String
            = ((lfpos > -1 && crpos > -1) || crpos < 0) ? "\n" : "\r";

         var lines:Array = str.split(linebreak);
         for (var i:int = 0; i < lines.length; i++) {
            lines[i] = Strutil.strip_line_breaks(lines[i]);
         }

         return lines;
      }

      // Pads a string with the given char to the number of posits specified
      public static function string_pad(obj:Object,
                                        len:int,
                                        pad:String=' ',
                                        append:Boolean=true) :String
      {
         var ostr:String = obj.toString();
         var padding:String = '';
         var padded_string:String;
         for (var i:int = len; i > ostr.length; i--) {
            padding += pad;
         }
         if (append) {
            padded_string = ostr + padding;
         }
         else {
            padded_string = padding + ostr;
         }
         return padded_string;
      }

      // Returns the number as a string if a natural number (including 0),
      // otherwise returns the empty string
      public static function stringify_natural(number:int) :String
      {
         if (number < 0) {
            return '';
         }
         else {
            return String(number);
         }
      }

      //
      public static function strip_line_breaks(str:String) :String
      {
         return str.replace(/^[\n\r]*|[\n\r]*$/g, '');
      }

      //
      public static function strip_whitespace(str:String) :String
      {
         return StringUtil.trim(str);
      }

   }
}


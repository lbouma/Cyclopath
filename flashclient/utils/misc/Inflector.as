/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This file is courtesy Derek Wischusen
// http://www.flexonrails.net/samples/inflector_example/srcview/index.html

// NOTE This file is mostly unedited, so that it can be easily diffed against
//      any changes to the source.

/*
.,$s/^    \([a-zA-Z0-9_\{\}\[\]\\\/\*\']\)/   \1/gc
*/

package utils.misc {

   /**
     * The Inflector class provides static methods for generating
     * the plural or singular form of a given word.
     *
     * This class is essentially a direct port of the Inflector
     * class in Rails (www.rubyonrails.org).
   **/

   public class Inflector {

// FIXME No way! A static initializer!
//      static:{
//         Inflector.init();
//      }

      private static var plurals:Array =
      [
         [/$/, 's'],
         [/s$/i, 's'],
         [/(ax|test)is$/i, '$1es'],
         [/(octop|vir)us$/i, '$1i'],
         [/(alias|status)$/i, '$1es'],
         [/(bu)s$/i, '$1ses'],
         [/(buffal|tomat)o$/i, '$1oes'],
         [/([ti])um$/i, '$1a'],
         [/sis$/i, 'ses'],
         [/(?:([^f])fe|([lr])f)$/i, '$1$2ves'],
         [/(hive)$/i, '$1s'],
         [/([^aeiouy]|qu)y$/i, '$1ies'],
         [/(x|ch|ss|sh)$/i, '$1es'],
         [/(matr|vert|ind)ix|ex$/i, '$1ices'],
         [/([m|l])ouse$/i, '$1ice'],
         [/^(ox)$/i, '$1en'],
         [/(quiz)$/i, '$1zes'],
         // Added by [lb]:
         [/^is$/i, 'are'],
         [/^was$/i, 'were'],
         [/^this$/i, 'these'],
      ];

      private static var singulars:Array =
      [
         [/s$/i, ''],
         [/(n)ews$/i, '$1ews'],
         [/([ti])a$/i, '$1um'],
         [/((a)naly|(b)a|(d)iagno|(p)arenthe|(p)rogno|(s)ynop|(t)he)ses$/i, '$1$2sis'],
         [/(^analy)ses$/i, '$1sis'],
         [/([^f])ves$/i, '$1fe'],
         [/(hive)s$/i, '$1'],
         [/(tive)s$/i, '$1'],
         [/([lr])ves$/i, '$1f'],
         [/([^aeiouy]|qu)ies$/i, '$1y'],
         [/(s)eries$/i, '$1eries'],
         [/(m)ovies$/i, '$1ovie'],
         [/(x|ch|ss|sh)es$/i, '$1'],
         [/([m|l])ice$/i, '$1ouse'],
         [/(bus)es$/i, '$1'],
         [/(o)es$/i, '$1'],
         [/(shoe)s$/i, '$1'],
         [/(cris|ax|test)es$/i, '$1is'],
         [/(octop|vir)i$/i, '$1us'],
         [/(alias|status)es$/i, '$1'],
         [/^(ox)en/i, '$1'],
         [/(vert|ind)ices$/i, '$1ex'],
         [/(matr)ices$/i, '$1ix'],
         [/(quiz)zes$/i, '$1'],
         // Added by [lb]:
         [/^are$/i, 'is'],
         [/^were$/i, 'was'],
         [/^these$/i, 'this'],
      ];

      private static var irregulars:Array =
      [
         ['person', 'people'],
         ['man', 'men'],
         ['child', 'children'],
         ['sex', 'sexes'],
         ['move', 'moves'],
      ];

      private static var uncountable:Array =
      [
         'equipment',
         'information',
         'rice',
         'money',
         'species',
         'series',
         'fish',
         'sheep',
      ];

      //
      public static function pluralize(singular:String, conditional:Boolean)
         :String
      {
         if (!conditional || (uncountable.indexOf(singular) != -1)) {
            return singular;
         }
         var plural:String = new String();
         for each (var item:Array in plurals) {
            var p:String = singular.replace(item[0], item[1]);
            if (p != singular) {
               plural = p;
               // Don't break; the last pattern wins.
            }
         }
         return plural;
      }

      //
      public static function singularize(plural:String) :String
      {
         if (uncountable.indexOf(plural) != -1) {
            return plural;
         }
         var singular:String = new String();
         for each (var item:Array in singulars) {
            var s:String = plural.replace(item[0], item[1]);
            if (s != plural) {
               singular = s;
            }
         }
         return singular;
      }

      // NOTE This should be private, but it needs to be public so we can call
      //      it from the end of this file, outside the scope of the class.
      static public function init() :void
      {
         for each (var irr:Array in irregulars) {
            plurals[plurals.length] = [irr[0], irr[1]];
            singulars[singulars.length] = [irr[1], irr[0]];
         }
      }

   }

   // This is a cheap way for a static class to initialize itself.
   Inflector.init();

}


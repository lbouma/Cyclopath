/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */


package utils.misc {

   import flash.geom.ColorTransform;

   public class Color_Helper {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Color_Helper');

      // *** Constructor

      //
      public function Color_Helper() :void
      {
         m4_ASSERT(false);
      }

      // *** Static class methods

      // http://stackoverflow.com/questions/2258800/how-can-i-calculate-shades-of-a-given-hex-color-in-actionscript-3

      /**
        * Return a gradient given a color.
        *
        * @param color      Base color of the gradient.
        * @param intensity  Amount to shift secondary color.
        * @return An array with a length of two colors.
        */
      public static function makeGradient(color:uint, intensity:int = 20) :Array
      {
         var c:Object = hexToRGB(color);
         for (var key:String in c) {
            c[key] += intensity;
            c[key] = Math.min(c[key], 255); // -- make sure below 255
            c[key] = Math.max(c[key], 0);   // -- make sure above 0
         }
         return [color, RGBToHex(c),];
      }

      /**
        * Convert a uint (0x000000) to a color object.
        *
        * @param hex  Color.
        * @return Converted object {r:, g:, b:}
        */
      public static function hexToRGB(hex:uint):Object
      {
         var c:Object = {};

         c.a = hex >> 24 & 0xFF;
         c.r = hex >> 16 & 0xFF;
         c.g = hex >> 8 & 0xFF;
         c.b = hex & 0xFF;

         return c;
      }

      /**
        * Convert a color object to uint octal (0x000000).
        *
        * @param c  Color object {r:, g:, b:}.
        * @return Converted color uint (0x000000).
        */
      public static function RGBToHex(c:Object):uint
      {
         var ct:ColorTransform =
            new ColorTransform(0, 0, 0, 0, c.r, c.g, c.b, 100);
         return ct.color as uint
      }

      /**
        * Convert RGB bits to a hexcode
        *
        * @param r  Red bits
        * @param g  Green bits
        * @param b  Blue bits
        * @return A color as a uint
        */
      public static function convertToHex(r:uint, g:uint, b:uint):uint
      {
         var colorHexString:uint = (r << 16) | (g << 8) | b;
         return colorHexString;
      }

      /**
        * Get a series of complements of a given color.
        *
        * @param color   Color to get harmonies for
        * @param weight  Threshold to apply to color harmonies, 0 - 255
        */
      public static function getHarmonies(color:uint, weight:Number):Array
      {
         var red:uint = color >> 16;
         var green:uint = (color ^ (red << 16)) >> 8;
         var blue:uint = (color ^ (red << 16)) ^ (green << 8);

         var colorHarmonyArray:Array = new Array();
         //weight = red+green+blue/3;

         colorHarmonyArray.push(convertToHex(red, green, weight));
         colorHarmonyArray.push(convertToHex(red, weight, blue));
         colorHarmonyArray.push(convertToHex(weight, green, blue));
         colorHarmonyArray.push(convertToHex(red, weight, weight));
         colorHarmonyArray.push(convertToHex(weight, green, weight));
         colorHarmonyArray.push(convertToHex(weight, weight, blue));

         return colorHarmonyArray;
      }

      // Another solution to same.

      //
      public static function getBetweenColourByPercent(
         value:Number=0.5, // 0-1
         highColor:uint=0xFFFFFF,
         lowColor:uint=0x000000) :uint
      {
         var r:uint = highColor >> 16;
         var g:uint = highColor >> 8 & 0xFF;
         var b:uint = highColor & 0xFF;

         r += ((lowColor >> 16) - r) * value;
         g += ((lowColor >> 8 & 0xFF) - g) * value;
         b += ((lowColor & 0xFF) - b) * value;

         return (r << 16 | g << 8 | b);
      }

   }
}


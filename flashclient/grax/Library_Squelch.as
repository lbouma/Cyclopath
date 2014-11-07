/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   public class Library_Squelch {

      // *** Class attributes

      public static const squelch_undefined:int = 0;

      public static const squelch_show_in_library:int = 1;
      public static const squelch_searches_only:int = 2;
      public static const squelch_always_hide:int = 3;

      // *** Constructor

      public function Library_Squelch() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // ***

      //
      public static function is_defined(squelch:int) :Boolean
      {
         return ((squelch >= Library_Squelch.squelch_show_in_library)
                 && (squelch <= Library_Squelch.squelch_always_hide));
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// 2013.05.06: Deprecated. See assets/skin/skin_*.as.

package items.utils {

   // NOTE: This must be kept up to date with the draw_class database table!
   //       See also pyserver/draw_class.py

   public class Draw_Class {

      // *** Class variables

      // SYNC_ME: Search draw_class table.

      // Byway
      public static const SMALL:int = 11;
      public static const BIKE_TRAIL:int = 12;
      public static const MEDIUM:int = 21;
      public static const LARGE:int = 31;
      public static const SUPER:int = 41;

      // Terrain
      public static const OPEN_SPACE:int = 2;
      public static const WATER:int = 3;

      // Highlights
      public static const SHADOW:int = 1;
      public static const BACKGROUND:int = 4;

      // Other
      public static const WAYPOINT:int = 5;
      public static const WATCH_REGION:int = 6;
      public static const WORK_HINT:int = 7; // Obsolete
      public static const ROUTE:int = 8;
      public static const REGION:int = 9;

      // *** Constructor

      public function Draw_Class() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

   }
}


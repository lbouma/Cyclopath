/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   public class Watcher_Frequency {

      // *** Class attributes

      // SYNC_ME: Search: Watcher_Frequency IDs.
      public static const never:int = 0;
      public static const immediately:int = 1;
      public static const daily:int = 2;
      public static const weekly:int = 3;
      public static const nightly:int = 4;
      public static const morningly:int = 5;
      // This last item just always matches the index of the last real item.
      public static const infinitely:int = 5;

      public static var lookup:Array = new Array();

      // *** Constructor

      public function Watcher_Frequency() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class initialization

      //
      // FIXME: Does anyone use this lookup?
      public static function init_lookup() :void
      {
         // NOTE: Cannot use "Watcher_Frequency." since this fcn. gets called
         //       before the class is defined (well, while the class is
         //       defining itself.) E.g., Watcher_Frequency.lookup[n] throws
         //       this error:
         //         TypeError: Error #1009: Cannot access a property or method
         //                                 of a null object reference.
         // SYNC_ME: Search: Access Scope IDs.
         //
         lookup[never] = 'Never';
         //lookup[never] = 'Off';
         //
         //lookup[immediately] = 'Immediately';
         //lookup[immediately] = 'Soon';
         lookup[immediately] = 'Promptly';
         //lookup[immediately] = 'Right away';
         //lookup[immediately] = 'Immediately';
         //
         lookup[daily] = 'Daily';
         //lookup[daily] = "Day's End";
         //
         //lookup[weekly] = 'Weekly';
         //lookup[weekly] = "Week's End";
         lookup[weekly] = "Mondays";
         //
         lookup[nightly] = '6 PM CST';
         //
         lookup[morningly] = '6 AM CST';
      }

      // This feels like cheating. I love inline code!
      Watcher_Frequency.init_lookup();

      // *** Static class methods

      //
      public static function is_defined(scope:int) :Boolean
      {
         return ((scope >= Watcher_Frequency.never)
                 && (scope <= Watcher_Frequency.infinitely));
      }

   }
}


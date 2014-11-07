/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   public class Travel_Mode {

      // *** Class attributes

      // NOTE: Only 'bicycle' and 'transit' are implemented. The third one,
      // 'walking', could find a route with sidewalks and stairs. The last one,
      // 'autocar', could find a route with freeways. I'm not [lb isn't] really
      // sure how this all should be implemented. For one, users should be able
      // to combine modes: e.g., cyclocross racers would want a route with
      // bicycle and walking, since they don't mind dismounting their rigs.
      // This also doesn't consider mountain biking. That is, to the user,
      // transmit mode is one or more items from a single list of choices, but
      // to us, the developers, the choices are not homogenous; for instance,
      // transit requires us to search a Google Transit Feed Database, whereas
      // walking or autocarring requires us to look at special tags, and
      // mountain biking requires us to consider the byway type.
      //
      // 2014.04.18: The previous comment is accurate, and getting old. The
      // Travel_Mode is used differently depending on who's using it. To a
      // route, it indicates which route planner should be or was used to plan
      // the route. To a route_step, it indicates to which mode the edge
      // belongs. [lb] is somewhat uncomfortable with the double meaning on an
      // ethical level, I mean, on an aesthetic level, but not that uncomfy.

      // SYNC_ME: Search: Travel Mode IDs.
      public static const mode_undefined:int = 0;
      public static const bicycle:int = 1; // Personalized route or byway edge.
      public static const transit:int = 2; // Multimodal route or transit edge.
      public static const walking:int = 3; // Not/ever used.
      public static const autocar:int = 4; // Never/ot used.
      public static const wayward:int = 5; // Fast, static route planner.
      public static const classic:int = 6; // Old school CcpV1 planner.
      public static const mode_invalid:int = 7; // SYNC_ME: 1+ previous value.

      public static var lookup:Array = new Array();

      // FIXME: More data duplication. Maybe just create in init_lookup?
      public static var access_level_data_provider:Array =
         [
         // SYNC_ME: Search: Travel Mode IDs.
         // Skipping: { id: 0, label: 'Undefined'},
         { id: 1, label: 'Bicycle'},
         { id: 2, label: 'Transit'},
         { id: 3, label: 'Walking'},
         { id: 4, label: 'Autocar'},
         { id: 5, label: 'Wayward'},
         { id: 6, label: 'Classic'}
         // Skipping: { id: 7, label: 'Mode Invalid'},
         ];

      // *** Constructor

      public function Travel_Mode() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class initialization

      //
      // FIXME: Does anyone use this lookup?
      public static function init_lookup() :void
      {
         // NOTE: Cannot use "Travel_Mode." since this fcn. gets called before
         //       the class is defined (well, while the class is defining
         //       itself.) E.g., Travel_Mode.lookup[n] throws this error:
         //         TypeError: Error #1009: Cannot access a property or method
         //                                 of a null object reference.
         // SYNC_ME: Search: Travel Mode IDs.
         lookup[mode_undefined] = 'undefined';
         lookup[bicycle] = 'bicycle';
         lookup[transit] = 'transit';
         lookup[walking] = 'walking';
         lookup[autocar] = 'autocar';
         lookup[wayward] = 'wayward';
         lookup[classic] = 'classic';
         lookup[mode_invalid] = 'invalid';
      }

      // This feels like cheating. I love inline code!
      Travel_Mode.init_lookup();

      // *** Static class methods

      //
      public static function is_defined(mode:int) :Boolean
      {
         // SYNC_ME: Search: Travel Mode IDs.
         return ((mode > Travel_Mode.mode_undefined)
                 && (mode < Travel_Mode.mode_invalid));
      }

      // *** Convenience methods

      //
      public static function is_bicycle(mode:int) :Boolean
      {
         return (mode == Travel_Mode.bicycle);
      }

      //
      public static function is_transit(mode:int) :Boolean
      {
         return (mode == Travel_Mode.transit);
      }

      //
      public static function is_walking(mode:int) :Boolean
      {
         return (mode == Travel_Mode.walking);
      }

      //
      public static function is_autocar(mode:int) :Boolean
      {
         return (mode == Travel_Mode.autocar);
      }

      //
      public static function is_wayward(mode:int) :Boolean
      {
         return (mode == Travel_Mode.wayward);
      }

      //
      public static function is_classic(mode:int) :Boolean
      {
         return (mode == Travel_Mode.classic);
      }

   }
}


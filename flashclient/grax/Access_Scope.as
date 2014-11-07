/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   public class Access_Scope {

      // *** Class attributes

      // SYNC_ME: Search: Access Scope IDs.
      public static const scope_undefined:int = 0;
      public static const scope_private:int = 1;
      public static const scope_shared:int = 2;
      public static const scope_public:int = 3;

      public static var lookup:Array = new Array();

      // *** Constructor

      public function Access_Scope() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class initialization

      //
      // FIXME: Does anyone use this lookup?
      public static function init_lookup() :void
      {
         // NOTE: Cannot use "Access_Scope." since this fcn. gets called before
         //       the class is defined (well, while the class is defining
         //       itself.) E.g., Access_Scope.lookup[n] throws this error:
         //         TypeError: Error #1009: Cannot access a property or method
         //                                 of a null object reference.
         // SYNC_ME: Search: Access Scope IDs.
         lookup[scope_undefined] = 'Undefined';
         lookup[scope_private] = 'Private';
         lookup[scope_shared] = 'Shared';
         lookup[scope_public] = 'Public';
      }

      // This feels like cheating. I love inline code!
      Access_Scope.init_lookup();

      // *** Static class methods

      //
      public static function is_defined(scope:int) :Boolean
      {
         return ((scope >= Access_Scope.scope_public)
                 && (scope <= Access_Scope.scope_private));
      }

      // *** Convenience methods

      //
      public static function is_public(scope:int) :Boolean
      {
         // NOTE: Owner is the top scope, so no <=, just straight-up ==
         return (scope == Access_Scope.scope_public);
      }

      //
      public static function is_shared(scope:int) :Boolean
      {
         return (scope == Access_Scope.scope_shared);
      }

      //
      public static function is_private(scope:int) :Boolean
      {
         return (scope == Access_Scope.scope_private);
      }

   }
}


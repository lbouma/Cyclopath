/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   public class Access_Style {

      // *** Class attributes

      // SYNC_ME: Search: Access Style IDs.
      public static const nothingset:int = 0;
      public static const all_access:int = 1;
      public static const permissive:int = 2;
      public static const restricted:int = 3;
      // public static const _reserved1:int = 4;
      public static const pub_choice:int = 5;
      public static const usr_choice:int = 6;
      public static const usr_editor:int = 7;
      public static const pub_editor:int = 8;
      public static const all_denied:int = 9;

      public static var lookup:Array = new Array();

      // *** Constructor

      public function Access_Style() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class initialization

      //
      // FIXME: Does anyone use this lookup?
      public static function init_lookup() :void
      {
         // NOTE: Cannot use "Access_Style." since this fcn. gets called before
         //       the class is defined (well, while the class is defining
         //       itself.) E.g., Access_Style.lookup[n] throws this error:
         //         TypeError: Error #1009: Cannot access a property or method
         //                                 of a null object reference.
         // SYNC_ME: Search: Access Style IDs.
         lookup[nothingset] = 'NothingSet';
         lookup[all_access] = 'All_Access';
         lookup[permissive] = 'Permissive';
         lookup[restricted] = 'Restricted';
         // lookup[_reserved1] = '_Reserved1';
         lookup[pub_choice] = 'Pub_Choice';
         lookup[usr_choice] = 'Usr_Choice';
         lookup[usr_editor] = 'Usr_Editor';
         lookup[pub_editor] = 'Pub_Editor';
         lookup[all_denied] = 'All_Denied';
      }

      // This feels like cheating. I love inline code!
      Access_Style.init_lookup();

      // *** Static class methods

      //
      public static function is_defined(style:int) :Boolean
      {
         return ((style >= Access_Style.all_access)
                 && (style <= Access_Style.all_denied));
      }

   }
}


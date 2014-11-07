/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   public class Access_Infer {

      // *** Class attributes

      // SYNC_ME: Search: Access Infer IDs.
      public static const not_determined:int    = 0x00000000;
      //
      public static const acl_choice_mask:int   = 0x00000022;
      public static const restricted_mask:int   = 0x00000EE9;
      public static const permissible_mask:int  = 0x00000000;
      public static const acceptible_mask:int   = 0x0000FEEB;
      //
      public static const all_arbiter_mask:int  = 0x00001111;
      public static const all_denied_mask:int   = 0x00008888;
      public static const not_private_mask:int  = 0x00007770;
      public static const not_public_mask:int   = 0x00007707;
      public static const pub_stealth_mask:int  = 0x00000770;
      public static const pub_viewer_mask:int   = 0x00000070;
      //
      public static const usr_mask:int          = 0x0000000F;
      public static const usr_arbiter:int       = 0x00000001;
      public static const usr_editor:int        = 0x00000002;
      public static const usr_viewer:int        = 0x00000004;
      public static const usr_denied:int        = 0x00000008;
      //
      public static const pub_mask:int          = 0x000000F0;
      public static const pub_arbiter:int       = 0x00000010;
      public static const pub_editor:int        = 0x00000020;
      public static const pub_viewer:int        = 0x00000040;
      public static const pub_denied:int        = 0x00000080;
      //
      public static const stealth_mask:int      = 0x00000F00;
      public static const stealth_arbiter:int   = 0x00000100;
      public static const stealth_editor:int    = 0x00000200;
      public static const stealth_viewer:int    = 0x00000400;
      public static const stealth_denied:int    = 0x00000800;
      //
      public static const others_mask:int       = 0x0000F000;
      public static const others_arbiter:int    = 0x00001000;
      public static const others_editor:int     = 0x00002000;
      public static const others_viewer:int     = 0x00004000;
      public static const others_denied:int     = 0x00008000;
      //
      public static const sessid_mask:int       = 0x000F0000;
      public static const sessid_arbiter:int    = 0x00010000;
      public static const sessid_editor:int     = 0x00020000;
      public static const sessid_viewer:int     = 0x00040000;
      public static const sessid_denied:int     = 0x00080000;

      public static var lookup:Array = new Array();

      // *** Constructor

      public function Access_Infer() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class initialization

      //
      // FIXME: Does anyone use this lookup?
      public static function init_lookup() :void
      {
         // NOTE: Cannot use "Access_Infer." since this fcn. gets called before
         //       the class is defined (well, while the class is defining
         //       itself.) E.g., Access_Infer.lookup[n] throws this error:
         //         TypeError: Error #1009: Cannot access a property or method
         //                                 of a null object reference.
         // SYNC_ME: Search: Access Scope IDs.
         lookup[not_determined] = 'not_determined';
         lookup[usr_arbiter] = 'usr_arbiter';
         lookup[usr_editor] = 'usr_editor';
         lookup[usr_viewer] = 'usr_viewer';
         lookup[usr_denied] = 'usr_denied';
         lookup[pub_arbiter] = 'pub_arbiter';
         lookup[pub_editor] = 'pub_editor';
         lookup[pub_viewer] = 'pub_viewer';
         lookup[pub_denied] = 'pub_denied';
         lookup[stealth_arbiter] = 'stealth_arbiter';
         lookup[stealth_editor] = 'stealth_editor';
         lookup[stealth_viewer] = 'stealth_viewer';
         lookup[stealth_denied] = 'stealth_denied';
         lookup[others_arbiter] = 'others_arbiter';
         lookup[others_editor] = 'others_editor';
         lookup[others_viewer] = 'others_viewer';
         lookup[others_denied] = 'others_denied';
         lookup[sessid_arbiter] = 'sessid_arbiter';
         lookup[sessid_editor] = 'sessid_editor';
         lookup[sessid_viewer] = 'sessid_viewer';
         lookup[sessid_denied] = 'sessid_denied';
      }

      // This feels like cheating. I love inline code!
      Access_Infer.init_lookup();

      // *** Static class methods

      //
      public static function is_defined(scope:int) :Boolean
      {
         return (scope >= Access_Infer.not_determined);
      }

   }
}


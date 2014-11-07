/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   import flash.utils.Dictionary;

   import utils.misc.Logging;

   // NOTE: This class is different pyserver's, which has the dirty reasons
   //       none, auto, and user, and is used for a somewhat different purpose.

   public class Dirty_Reason {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Dirty_Reason');

      // ***

      // SYNC_ME: Search: Dirty Reasons.

      // NOTE: I tried setting these from lookup_obj, e.g.,
      //          public static var item_data:int = lookup_val['item_data'];
      //       but they all ended up being 0. So:
      //public static var invalid:uint = -1;
      //
      public static var       not_dirty:uint = 0;
      public static var     all_reasons:uint = 0xFFFFFFFF;

      // These are things semi-banned users can do.
      public static var  personlia_mask:uint = 0x000F0000;
      // These are things semi-banned users cannot do.
      public static var  notbanned_mask:uint = 0xFFF0FFFF;

      // *** Reasons that require a changenote.
      //
      public static var    mask_revisioned:uint = 0x0000FFEF;
      public static var          item_data:uint = 0x00000001;
      public static var          item_grac:uint = 0x00000002;
      public static var          item_schg:uint = 0x00000004;
      //
      // edit_auto and edit_user are for group item access records.
      // NOTE: edit_auto is not park of mask_revisioned.
      public static var          edit_auto:uint = 0x00000010;
      // BUG nnnn: edit_user is only used by Item_User_Access.groups_access_fcn
      //           which is for changing GIA policies. Otherwise, access style
      //           change and whatnot edit up as edit_auto changes, which are
      //           considered changeless, i.e., we don't bug the user to write
      //           a changenote to save edit_auto GrAC changes.
      public static var          edit_user:uint = 0x00000020;

      // *** Reasons that don't need a changenote.
      //
      public static var    mask_changeless:uint = 0xFFFF0010;
      //
      public static var        item_rating:uint = 0x00010000;
      // FIXME: Statewide UI: How do item_watcher work now?
      //        Maybe it's still useful since watchers are
      //        saved OOB (i.e., revisionless; immediately;
      //        not requiring user to save map).
      public static var       item_watcher:uint = 0x00020000;
      public static var      item_read_evt:uint = 0x00040000;
      public static var      item_reminder:uint = 0x00080000;
      //
      public static var      item_mask_oob:uint = 0x00700000;
      public static var      item_data_oob:uint = 0x00100000;
      public static var      item_grac_oob:uint = 0x00200000;
      public static var      item_schg_oob:uint = 0x00400000;

      // This is used by route. And threads and posts. (And tracks?)
      public static var  item_revisionless:uint = 0x01000000;

      public static const lookup_obj:Array =
         [
            // *** Out of bounds.
            //{ e_key:               -1, e_val:            'invalid' },
            { e_key:          not_dirty, e_val:          'not_dirty' },
            { e_key:        all_reasons, e_val:        'all_reasons' },
            // *** Reasons that require a changenote.
            { e_key:    mask_revisioned, e_val:    'mask_revisioned' },
            { e_key:          item_data, e_val:          'item_data' },
            { e_key:          item_grac, e_val:          'item_grac' },
            { e_key:          item_schg, e_val:          'item_schg' },
            // These apply just to Group_Item_Access
            { e_key:          edit_auto, e_val:          'edit_auto' },
            { e_key:          edit_user, e_val:          'edit_user' },
            // *** Reasons that don't need a changenote.
            { e_key:    mask_changeless, e_val:    'mask_changeless' },
            { e_key:        item_rating, e_val:        'item_rating' },
            { e_key:       item_watcher, e_val:       'item_watcher' },
            { e_key:      item_read_evt, e_val:      'item_read_evt' },
            { e_key:      item_reminder, e_val:      'item_reminder' },
            { e_key:      item_data_oob, e_val:      'item_data_oob' },
            { e_key:      item_grac_oob, e_val:      'item_grac_oob' },
            { e_key:      item_schg_oob, e_val:      'item_schg_oob' },
            { e_key:  item_revisionless, e_val:  'item_revisionless' },
         ];

      public static var lookup_key:Dictionary = new Dictionary();
      public static var lookup_val:Dictionary = new Dictionary();
      private static function hack_attack() :void
      {
         for each (var o:Object in lookup_obj) {
            m4_VERBOSE('hack_attack: e_key:', o.e_key, '/ e_val:', o.e_val);
            lookup_key[o.e_key] = o.e_val;
            lookup_val[o.e_val] = o.e_key;
         }
      }
      hack_attack();

      // *** Constructor

      public function Dirty_Reason() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // ***

   }
}


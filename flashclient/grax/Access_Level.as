/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   import utils.misc.Set_UUID;

   public class Access_Level {

      // *** Class attributes

      // SYNC_ME: Search: Access Level IDs.

      public static const invalid:int = -1;

      public static const owner:int   = 1;
      public static const arbiter:int = 2;
      public static const editor:int  = 3;
      public static const viewer:int  = 4;
      public static const client:int  = 5;
      public static const denied:int  = 6;

      public static var lookup:Array = new Array();

      // FIXME: More data duplication. Maybe just create in init_lookup?
      // SYNC_ME: Search: Access_Level.access_level_data_provider.
      public static var access_level_data_provider_arbiter:Array =
         [
         // Skipping: { id: -1, label: 'Invalid'},
         //{ id: 1, label: 'Owner'},
         //{ id: 2, label: 'Arbiter'},
         { id: 3, label: 'Editor'},
         { id: 4, label: 'Viewer'},
         // FIXME: Client needed for assigning perms to attributes?
         // Skipping: { id: 5, label: 'Client'},
         { id: 6, label: 'Denied'}
         ];

      // FIXME: More data duplication. Maybe just create in init_lookup?
      // SYNC_ME: Search: Access_Level.access_level_data_provider.
      public static var access_level_data_provider_owner:Array =
         [
         // Skipping: { id: -1, label: 'Invalid'},
         //{ id: 1, label: 'Owner'},
         { id: 2, label: 'Arbiter'},
         { id: 3, label: 'Editor'},
         { id: 4, label: 'Viewer'},
         // FIXME: Client needed for assigning perms to attributes?
         // Skipping: { id: 5, label: 'Client'},
         { id: 6, label: 'Denied'}
         ];


      /* HISTORY: Other ideas for names:

            Owner
            Superadmin
            Admin
            Manager
            Publisher
            Editor
            Author
            Contributor
            Viewer
            Denied
      */

      // *** Constructor

      public function Access_Level() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class initialization

      //
      // FIXME: Does anyone use this lookup?
      public static function init_lookup() :void
      {
         // NOTE: Cannot use "Access_Level." since this fcn. gets called before
         //       the class is defined (well, while the class is defining
         //       itself.) E.g., Access_Level.lookup[n] throws this error:
         //         TypeError: Error #1009: Cannot access a property or method
         //                                 of a null object reference.
         // SYNC_ME: Search: Access Level IDs.
         lookup[invalid] = 'Invalid';
         lookup[owner]   = 'Owner';
         lookup[arbiter] = 'Arbiter';
         lookup[editor]  = 'Editor';
         lookup[viewer]  = 'Viewer';
         lookup[client]  = 'Client';
         lookup[denied]  = 'Denied';
      }

      // This feels like cheating. I love inline code!
      Access_Level.init_lookup();

      // *** Static class methods

      //
      public static function best_of(levels:Array) :int
      {
         var level:int = Access_Level.denied;
         var walker:int = Access_Level.invalid;
         for each (walker in levels) {
            if (Access_Level.is_same_or_more_privileged(walker, level)) {
               level = walker;
               if (level == Access_Level.owner) {
                  break;
               }
            }
         }
         return level;
      }

      //
      public static function least_of(levels:Array,
                                      sel_items:Set_UUID // For debugging
         ) :int
      {
         var level:int = Access_Level.invalid;
         var walker:int = Access_Level.invalid;
         for each (walker in levels) {
            if (level == Access_Level.invalid) {
               if (Access_Level.is_valid(walker)) {
                  level = walker;
               }
               else {
                  // See: views/panel_items/Panel_Item_Versioned.mxml
                  // var acl_ids:Array = Objutil.values_collect(
                  //    this.items_selected, 'access_level_id');
                  m4_ASSERT_SOFT(false);
                  G.sl.event('error/access_level/least_of',
                             {walker: walker,
                              levels_len: levels.length,
                              levels_all: levels.toString(),
                              sel_items: sel_items.toString()});
               }
            }
            else if (Access_Level.is_same_or_less_privileged(walker, level)) {
               level = walker;
               if (level == Access_Level.denied) {
                  break;
               }
            }
         }
         if (level == Access_Level.invalid) {
            level = Access_Level.denied;
         }
         m4_ASSERT(Access_Level.is_valid(level));
         return level;
      }

      //
      public static function is_denied(level:int) :Boolean
      {
         m4_ASSERT(Access_Level.is_valid(level));
         return (level == Access_Level.denied);
      }

      //
      public static function is_same_or_less_privileged(candidate:int,
                                                        subject:int)
         :Boolean
      {
         m4_ASSERT(Access_Level.is_valid(candidate));
         m4_ASSERT(Access_Level.is_valid(subject));
         return (candidate >= subject);
      }

      //
      public static function is_same_or_more_privileged(candidate:int,
                                                        subject:int)
         :Boolean
      {
         m4_ASSERT(Access_Level.is_valid(candidate));
         m4_ASSERT(Access_Level.is_valid(subject));
         return (candidate <= subject);
      }

      //
      public static function is_valid(level:int) :Boolean
      {
         return ((level >= Access_Level.owner)
                 && (level <= Access_Level.denied));
      }

      // *** Convenience methods

      //
      public static function can_own(level:int) :Boolean
      {
         // NOTE: Owner is the top level, so no <=, just straight-up ==
         return (level == Access_Level.owner);
      }

      //
      public static function can_arbit(level:int) :Boolean
      {
         return ((Access_Level.is_valid(level))
                 && (level <= Access_Level.arbiter));
      }

      //
      public static function can_edit(level:int) :Boolean
      {
         return ((Access_Level.is_valid(level))
                 && (level <= Access_Level.editor));
      }

      // FIXME: The names of these are... misleading? Users can still view
      // items with client access. Users can discover things marked client, but
      // they should not see those items'

      //
      public static function can_view(level:int) :Boolean
      {
         return ((Access_Level.is_valid(level))
                 && (level <= Access_Level.viewer));
      }

      //
      public static function can_client(level:int) :Boolean
      {
         return ((Access_Level.is_valid(level))
                 && (level <= Access_Level.client));
      }

   }
}


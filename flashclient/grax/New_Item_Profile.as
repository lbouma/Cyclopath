/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   import items.Item_Base;
   import items.Item_User_Access;
   import items.utils.Item_Type;
   import utils.misc.Introspect;
   import utils.misc.Logging;

   public class New_Item_Profile {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('New_Item_Pro');

      // *** Mandatory attributes

      public static const class_item_type:String = 'new_item_profile';
      //public static const class_gwis_abbrev:String = 'new_item_profile';
      //public static const class_item_type_id:int =
      //                                            Item_Type.NEW_ITEM_PROFILE;

      // *** Instance variables

      protected var item_class_:Class = null;
      protected var item_type_id_:int = -1;
      public var item_layer:String = null; // Not implemented
      public var item_stack_id:int = 0; // Not implemented
      // FIXME This is named poorly, since min means better, 'cause lesser
      //       access ID have better access. Also, -1 is weird, though
      //       Access_Level.denied is wrong since it would apply to everyone.
      //       at_least_access_level_id
      public var min_access_id:int = -1;

      // *** Constructor

      //
      public function New_Item_Profile()
      {
         // no-op
      }

      // *** Getters and setters

      //
      public function get item_class() :Class
      {
         return this.item_class_;
      }

      //
      public function set item_class(item_class:Class) :void
      {
         m4_ASSERT(false); // Is this fcn. used?
         m4_VERBOSE('item_class [set]:', item_class);
         this.item_class_ = item_class;
         if (this.item_class_ !== null) {
            var item_type:String = Item_Base.item_get_type(this.item_class_);
            this.item_type_id_ = Item_Type.str_to_id(item_type);
            m4_ASSERT(Item_Type.is_id_valid(this.item_type_id_));
         }
         else {
            this.item_type_id_ = 0;
         }
      }

      //
      public function get item_type_id() :int
      {
         return this.item_type_id_;
      }

      //
      public function set item_type_id(item_type_id:int) :void
      {
         m4_VERBOSE('item_type_id [set]:', item_type_id);
         this.item_type_id_ = item_type_id;
         if (this.item_type_id_ != 0) {
            var item_type:String = Item_Type.id_to_str(this.item_type_id_);
            this.item_class_ = Item_Base.item_get_class(item_type);
            m4_ASSERT(this.item_class_ !== null);
         }
         else {
            this.item_class_ = null;
         }
      }

      // *** Public instance methods

      //
      public function get is_valid() :Boolean
      {
         return (this.item_class_ !== null);
      }

      //
      public function matches(item:Item_User_Access) :Boolean
      {
         var matches:Boolean = false;

         m4_ASSERT(item !== null);

         m4_ASSERT(this.item_class_ !== null);
         m4_ASSERT((this.item_layer === null)
                   || (this.item_layer == '')); // Not implemented

         // Check that item type matches and stack ID (if exists) matches
         if ( (Introspect.derives_from(item, this.item_class_))
             && ( (this.item_stack_id == 0)
                 || (item.stack_id == this.item_stack_id)) ) {
            // The item class and maybe the stack ID match. If the policy
            // specifies an access control level limit, check the user
            // passes.
            // NOTE: The access level check only applies to the attc and/or
            //       feat of an item being linked (so item is an attc or feat
            //       that already exists, and we're checking that the user has
            //       rights to create a link on this item).
            if (Access_Level.is_valid(this.min_access_id)) {
               if (Access_Level.is_same_or_more_privileged(
                     item.access_level_id, this.min_access_id)) {
                  m4_DEBUG('matches: linked attc or feat ok');
                  matches = true;
               }
               else {
                  m4_DEBUG3('matches: denied',
                            '/ item.access_level_id:', item.access_level_id,
                            '/ this.min_access_id:', this.min_access_id);
               }
            }
            else {
               m4_DEBUG('matches: item ok');
               matches = true;
            }
         }
         else {
            m4_TALKY9('matches: failed',
                      '/ item.ctor:', Introspect.get_constructor(item),
                      '/ this.item_class:', this.item_class_,
                      '/ item.class_item_type:', Item_Type.str_to_id(
                        Introspect.get_constructor(item).class_item_type),
                      '/ this.item_type_id:', this.item_type_id_,
                      '/ item.stack_id:', item.stack_id,
                      '/ this.item_stack_id:', this.item_stack_id
                      );
         }
         return matches;
      }

   }
}


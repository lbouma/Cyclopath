/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This is the base class for geowiki items, providing or abstracting
// common functionality between tiles, geofeatures, attachments and link
// values.

package items {

   import flash.geom.Rectangle;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;

   import grax.Aggregator_Base;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Strutil;

   public class Item_Base extends Record_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Base');

      // *** Instance variables

      // Items are uniquely identified by their stack ID, and IDs might be
      // unique across one or more of the derived class types.
      // NOTE: In pyserver, stack_id is defined in Item_Versioned, not here.
      public var stack_id:int;

      // *** Constructor

      public function Item_Base(xml:XML=null)
      {
         super(xml);
      }

      // *** Protected Static methods

      // *** Getters and setters

      // The bounding box of this Item, in map coordinates.
      //
      // See r12601 for caching logic that turned out to be unneeded.
      //
      // This fcn. is only implemented by Geofeature and Tile; it doesn't apply
      // to all of the derived classes.
      public function get bbox_map() :Rectangle
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      // Is the item wiki-deleted in the working copy?
      public function get deleted() :Boolean
      {
         return false;
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Item_Base = (to_other as Item_Base);
         super.clone_once(other);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Item_Base = (to_other as Item_Base);
         super.clone_update(other, newbie);
      }

      // Initialize support data structures. Do not assume that other features
      // you might be interested in are in them yet. Return true if successful
      // and false if not (i.e., I was a duplicate or should not be included
      // on the map for whatever reason).
      public function init_item(item_agg:Aggregator_Base,
                                soft_add:Boolean=false)
         :Item_Versioned
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      // Clean up any dependent features and otherwise prepare for removal.
      // The int, i, specifies the child index in the view control (for
      // sprites, like tiles and geofeatures).
      // NOTE: The child index is used by Byway, Geosummary, Region, Waypoint
      //       to clear themselves from G.map.shadows.
      public function item_cleanup(i:int=-1, skip_delete:Boolean=false) :void
      {
         // no-op
      }

      // *** Public Static methods

      // These methods return an item's class, either as a Class or a String

      // Returns the objects item type as a Class object. The item_type can be
      // an item instance or a String.
      // FIXME: Does this belong in Item_Type.as? Or Item_Manager.as?
      public static function item_get_class(item_type:Object) :Class
      {
         var item_class:Class = null;
         var items_item_type:String;
         if (item_type is Item_Base) {
            item_class = Introspect.get_constructor(item_type);
         }
         else if (item_type is String) {
            var item_type_str:String = (item_type as String);
            // SYNC_ME: Search items_packages.
            const items_packages:Array = ['items.feats.',
                                          'items.attcs.',
                                          'items.links.',
                                          'items.gracs.',
                                          'items.jobsq.',
                                          ];
            // The server uses lowercase underscore-delimited names, whereas we
            // use uppercase of the same (e.g., link_value => Link_Value)
            item_type_str
               = Strutil.capitalize_underscore_delimited(item_type_str);
            m4_VERBOSE('item_get_class: looking for:', item_type_str);
            for each (var package_name:String in items_packages) {
               try {
                  // First, try finding the object in one of the subpackages.
                  items_item_type = package_name + item_type_str;
                  m4_VERBOSE('item_get_class: trying:', items_item_type);
                  item_class = getDefinitionByName(items_item_type) as Class;
                  break;
               }
               catch (e:ReferenceError) {
                  // No-op. Try next package.
               }
            }
            if (item_class === null) {
               // If it wasn't found in a subpackage, try the items package.
               m4_VERBOSE('item_get_class: trying again:', item_type_str);
               // NOTE The server should only send certain items types;
               //      Branch_Conflict, Group_Revision, and Link_Value.
               if (!(
                     true
                     //|| ('Attachment' == item_type_str)
                     //|| ('Geofeature' == item_type_str)
                     || ('Link_Value' == item_type_str)
                     )) {
                  m4_WARNING('Unexpected item type:', item_type_str);
                  m4_ASSERT(false);
               }
               try {
                  items_item_type = 'items.' + item_type_str;
                  item_class = getDefinitionByName(items_item_type) as Class;
               }
               catch (e:ReferenceError) {
                  // If this error throws, e.g., "ReferenceError: Error #1065:
                  // Variable Work_Item is not defined", then you should check
                  // items_packages above and update init_GetDefinitionByName.
                  throw new Error('Unknown item_versioned type: ~'
                                  + items_item_type + '~ / ' + e.toString());
               }
            }
            m4_VERBOSE('item_get_class: item_class:', item_class);
            item_class = item_class as Class;
         }
         m4_ASSERT_ELSE;
         m4_VERBOSE('item_get_class: returning:', item_class);
         return item_class;
      }

      // Given an object, returns the lowercased item class name of the
      // object. The object can be an instance Object, an item Class, or a
      // String.
      // FIXME: Does this belong in Item_Type.as?
      public static function item_get_type(item:Object) :String
      {
         var item_type:String;
         var class_name:String;
         if (item is Item_Base) {
            // EXPLAIN: How come the item hierarchy doesn't define a const that
            // it sets to one of the values in Item_Type? Getting the classname
            // seems kludgy.
            class_name = getQualifiedClassName((item as Item_Base));
            m4_VERBOSE('class_name: --', class_name, '--');
            // E.g., 'item::Tag'
            item_type = class_name.substr(class_name.lastIndexOf(':') + 1);
            m4_VERBOSE3('item_get_type: item:', item,
                        ' / getQualifiedClassName:', class_name,
                        ' / item_type:', item_type);
            // FIXME: Can we just use class_item_type? (Though this code could
            //        maybe be moved Introspect.)
            m4_ASSERT_SOFT(Introspect.get_constructor(item).class_item_type
                           == item_type.toLowerCase());
         }
         else if (item is Class) {
            item_type = item.toString();
            m4_VERBOSE('Class.toString(): --', item_type, '--');
            // E.g., '[class region]'
            item_type = item_type.replace(/^ *\[class */, '');
            item_type = item_type.replace(/\] *$/, '');
            m4_VERBOSE2('item_get_type: item.class_item_type:',
                        item.class_item_type);
         }
         else if (item is String) {
            item_type = item as String;
         }
         m4_ASSERT_ELSE;
         // NOTE This function always lowercases the class name!
         //      This is so we're on par with pyserver.
         //      (e.g., Link_Value => link_value)
         item_type = item_type.toLowerCase();
         m4_VERBOSE('item_get_type:', item_type);
         return item_type;
      }

   }
}


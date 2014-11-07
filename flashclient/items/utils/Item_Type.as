/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   import flash.utils.Dictionary;

   import items.feats.Byway;
   import utils.geom.Dual_Rect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;

   public dynamic class Item_Type extends Dictionary
   {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Type');

      // This is a singleton class, and _instance is the one and only
      // instantiated object of it.
      private static var _instance:Item_Type = new Item_Type();

      // This class manages a lookup of the resident_rect for each item type.
      // Each rectangle describes the set of items for a particular type that
      // we've loaded from the database and currently have in memory.
      protected static var rect_preserve_lookup:Dictionary;

      // *** Instance variables

      // FIXME Fetch from database with GWIS_Base?
      protected var lookup_by_id:Array = null; // We'll init this later
      // If you copy the table from item_type.py, run this in VIM to make this
      // new table:
      //   .,$s/self._lookup_add( \?\([0-9]\+\), '\([^']\+\)')/public static const \U\2:int = \1;/gc
      // SYNC_ME: Search: Item_Type table.
      public static const ATTACHMENT:int = 1;
      public static const GEOFEATURE:int = 2;
      public static const LINK_VALUE:int = 3;
      public static const ANNOTATION:int = 4;
      public static const ATTRIBUTE:int = 5;
      public static const BRANCH:int = 6;
      public static const BYWAY:int = 7;
      public static const POST:int = 8;
      public static const REGION:int = 9;
      public static const ROUTE:int = 10;
      public static const TAG:int = 11;
      public static const TERRAIN:int = 12;
      public static const THREAD:int = 13;
      public static const WAYPOINT:int = 14;
      public static const WORKHINT:int = 15;
      public static const GROUP_MEMBERSHIP:int = 16;
      public static const NEW_ITEM_POLICY:int = 17;
      public static const GROUP:int = 18;
      public static const ROUTE_STEP:int = 19;
      public static const GROUP_REVISION:int = 20;
      public static const TRACK:int = 21;
      public static const TRACK_POINT:int = 22;
      public static const ADDY_COORDINATE:int = 23;
      public static const ADDY_GEOCODE:int = 24;
      public static const ITEM_NAME:int = 25;
      public static const GRAC_ERROR:int = 26;
      public static const WORK_ITEM:int = 27;
      public static const NONWIKI_ITEM:int = 28;
      public static const MERGE_JOB:int = 29;
      public static const ROUTE_ANALYSIS_JOB:int = 30;
      public static const JOB_BASE:int = 31;
      public static const WORK_ITEM_STEP:int = 32;
      public static const MERGE_JOB_DOWNLOAD:int = 33;
      public static const GROUP_ITEM_ACCESS:int = 34;
      // DEPRECATED: ITEM_WATCHER is replaced by private link_attributes.
      //  public static const ITEM_WATCHER:int = 35;
      //  public static const ITEM_WATCHER_CHANGE:int = 36;
      public static const ITEM_EVENT_ALERT:int = 37;
      // DEPRECATED: BYWAY_NODE is replaced by NODE_ENDPOINT.
      //  public static const BYWAY_NODE:int = 38;
      // DEPRECATED: ROUTE_WAYPOINT is renamed to ROUTE_STOP.
      //  public static const ROUTE_WAYPOINT:int = 39;
      public static const ROUTE_ANALYSIS_JOB_DOWNLOAD:int = 40;
      public static const BRANCH_CONFLICT:int = 41;
      public static const MERGE_EXPORT_JOB:int = 42;
      public static const MERGE_IMPORT_JOB:int = 43;
      public static const NODE_ENDPOINT:int = 44;
      public static const NODE_BYWAY:int = 45;
      public static const NODE_TRAVERSE:int = 46;
      public static const ROUTE_STOP:int = 47;
      // 2013.04.04: Let callers get basic item info (like access_style_id).
      // No: public static const ITEM_STACK:int = 48;
      // No: public static const ITEM_VERSIONED:int = 49;
      public static const ITEM_USER_ACCESS:int = 50;
      // No: public static const ITEM_USER_WATCHING:int = 51;
      public static const LINK_GEOFEATURE:int = 52;
      public static const CONFLATION_JOB:int = 53;
      public static const LINK_POST:int = 54;
      public static const LINK_ATTRIBUTE:int = 55;
      public static const LANDMARK:int = 56;
      public static const LANDMARK_T:int = 57;
      public static const LANDMARK_OTHER:int = 58;
      public static const ITEM_REVISIONLESS:int = 59;
      //
      // SYNC_ME: Don't forget to update the lookup immediately following:
      //
      // SYNC_ME: Search: Item_Type table.
      protected var lookup_by_str:Object = {
         'attachment': 1
         , 'geofeature': 2
         , 'link_value': 3
         , 'annotation': 4
         , 'attribute': 5
         , 'branch': 6
         , 'byway': 7
         , 'post': 8
         , 'region': 9
         , 'route': 10
         , 'tag': 11
         , 'terrain': 12
         , 'thread': 13
         , 'waypoint': 14
         , 'workhint': 15
         , 'group_membership': 16
         , 'new_item_policy': 17
         , 'group': 18
         , 'route_step': 19
         //, 'group_revision': 20
         , 'track': 21
         , 'track_point': 22
         , 'addy_coordinate': 23
         , 'addy_geocode': 24
         , 'item_name': 25
         , 'grac_error': 26
         , 'work_item': 27
         , 'nonwiki_item': 28
         , 'merge_job': 29
         , 'route_analysis_job': 30
         , 'job_base': 31
         , 'work_item_step': 32
         , 'merge_job_download': 33
         , 'group_item_access': 34
         // DEPRECATED: item_watcher is replaced by private link_attributes.
         //  , 'item_watcher': 35
         //  , 'item_watcher_change': 36
         , 'item_event_alert': 37
         // DEPRECATED: byway_node is replaced by node_endpoint.
         //  , 'byway_node': 38
         // DEPRECATED: route_waypoint is renamed to route_step.
         //  , 'route_waypoint': 39
         , 'route_analysis_job_download': 40
         , 'branch_conflict': 41
         , 'merge_export_job': 42
         , 'merge_import_job': 43
         , 'node_endpoint': 44
         , 'node_byway': 45
         , 'node_traverse': 46
         , 'route_step': 47
         // 2013.04.04: For fetching basic item info (like access_style_id).
         // No: , 'item_stack': 48
         // No: , 'item_versioned': 49
         , 'item_user_access': 50
         // No: , 'item_user_watching': 51
         , 'link_geofeature': 52
         , 'conflation_job': 53
         , 'link_post': 54
         , 'link_attribute': 55
         , 'landmark': 56
         , 'landmark_t': 57
         , 'landmark_other': 58
         , 'item_revisionless': 59
         };

      // *** Constructor

      public function Item_Type()
      {
         // Flex Singleton implemetation, from
         //   http://cookbooks.adobe.com/post_Singleton_Pattern-262.html
         if (_instance !== null) {
            throw new Error(
               "Singleton can only be accessed through Item_Type.instance");
         }
         else {
            this.initialize();
         }
      }

      // *** Singleton accessor

      //
      public static function get instance() :Item_Type
      {
         return _instance;
      }

      // *** Protected instance methods

      //
      protected function initialize() :void
      {
         // This class extends Dictionary and is dynamic, so we can add new
         // class members by setting them in the dictionary. That is, if we
         // set this['that'], than other classes can simply reference
         // this.that.
         m4_DEBUG('initialize()', this.lookup_by_str);
         m4_ASSERT(this.lookup_by_str !== null);
         m4_ASSERT(this.lookup_by_id === null);
         this.lookup_by_id = new Array();
         for (var attr:String in this.lookup_by_str) {
            m4_VERBOSE('attr:', attr, '/ value:', this.lookup_by_str[attr]);
            // Capitalize the attribute name?
// FIXME The static flag in the compiler makes this useless? YES!
            this[attr.toUpperCase()] = this.lookup_by_str[attr];
            this.lookup_by_id[this.lookup_by_str[attr]] = attr;
         }
      }

      // *** Conversion fcns: Database Item Type ID  <==> Item Type Name

      //
      public static function id_to_str(item_type:int) :String
      {
         m4_ASSERT(Item_Type.is_id_valid(item_type));
         var item_type_str:String = Item_Type.instance.lookup_by_id[item_type];
         m4_VERBOSE('id_to_str:', item_type, ' / ', item_type_str);
         return item_type_str;
      }

      //
      public static function str_to_id(item_type:String) :int
      {
         var item_type_id:int = Item_Type.instance.lookup_by_str[item_type];
         m4_VERBOSE('str_to_id:', item_type, ' / ', item_type_id);
         return item_type_id;
      }

      //
      public static function is_id_valid(item_type:int) :Boolean
      {
         return (item_type in Item_Type.instance.lookup_by_id);
      }

      // *** Resident Item Type rectangles

      // This is kind of a hack... but it's not. When updating the map, it
      // helps to know the rectangle defining the items we already have in
      // memory. Usually, this is the same as G.map.resident_rect (which is
      // really just a rectangle that's a little larger than G.map.view_rect,
      // since we fetch items in a little buffer zone outside of the what the
      // user sees).
      //
      // However, if the user pans the map while we're still updating the map
      // from a previous operation, some of our GWIS_Base requests will have
      // succeeded and some will still be outstanding. So resident_rect doesn't
      // accurately reflect the items we have in memory.
      //
      // We could just scrap the whole map and send new requests for every
      // item in the new view_rect, but this looks sloppy and amateurish. We
      // could also just ignore the last update operation, including its GWIS
      // responses, and just send a whole new set of requests. Or we could
      // maintain a set of rectangles, one for each item type, that represents
      // the resident_rect just for that item type. Ideally, I'd like to store
      // this value in the item type class, but the way the Item_Versioned
      // hierarchy works, we'd have to make static members in each of the
      // classes. Another option is to make a lookup in Update_Base. A
      // third option is to make the lookup here, which I [lb] choose to do
      // because, firstly, I don't want to clutter Update_Base class
      // anymore than it already is, and secondly, it makes this class kind
      // of a manager class for all of the item types, and I could see its
      // role as such growing in the future. (For instance, maybe all of the
      // 'public static all' members could be moved here; if we ever wanted to
      // store multiple branches in the working copy, we'd have to stop using
      // static.)

      // Given a lookup of resident rects, merge with our existing lookup. This
      // is useful during an update operation to keep track of items we've
      // loaded, so we can respond appropriately if the user pans the map while
      // we're still updating items.
      public static function resident_rects_merge(updated_rects:Dictionary)
         :void
      {
// FIXME revisit this fcn... seems silly; also, for or for each?
         for (var diff_type:String in updated_rects) {
            for (var item_type:String in updated_rects[diff_type]) {
               if (!(item_type in Item_Type.rect_preserve_lookup[diff_type])) {
                  Item_Type.rect_preserve_lookup[diff_type][item_type]
                     = new Set_UUID();
               }
// FIXME this seems really broken -- and overly complicated w/out 'nuf benefit
               Item_Type.rect_preserve_lookup[diff_type][item_type].add(
                  updated_rects[diff_type][item_type]);
            }
         }
      }

      // Resets resident_rect lookup after a successful update operation. At
      // this point, the collection of items in memory for every item type are
      // contained in the rectangle defined by G.map.resident_rect, so we no
      // longer need the contects of this lookup.
      public static function resident_rects_reset() :void
      {
         Item_Type.rect_preserve_lookup = new Dictionary();
         for each (var diff_type:int in [utils.rev_spec.Diff.NONE,
                                         utils.rev_spec.Diff.OLD,
                                         utils.rev_spec.Diff.NEW,
                                         utils.rev_spec.Diff.STATIC]) {
            Item_Type.rect_preserve_lookup[diff_type] = new Dictionary();
         }
      }

      // Given a rectangle we're going to use to fetch items, see if we've
      // already fetched some items contained within it. Return a rectangle
      // indicating those items we don't need to fetch.
      public static function resident_rect_get_exclude(diff_type:int,
         item_type:String, rect_fetch:Dual_Rect) :Dual_Rect
      {
         // NOTE/FIXME If the user pans multiple times during an update, we
         // might end up with multiple resident rectangles. However, the GWIS
         // checkout command only recognizes one exclude rectangle. We could
         // issue multiple calls on smaller rectangles, or we could just
         // re-request some items. In the interest of time, I'm just going to
         // find the largest resident rectangle and use that. This simply means
         // we'll request some items we already have. To really avoid this
         // (which just saves bandwidth and maybe a little user wait time) is
         // more complicated than seems worth the effort right now. The best
         // solution is probably to let the server accept multiple
         // exclude_rects.
         var exclude_rect:Dual_Rect = null;
         var largest_rect:Dual_Rect = null;
         if (item_type in Item_Type.rect_preserve_lookup[diff_type]) {
            // Find the resident rectangle that's the largest
            for each (var rect:Dual_Rect
                  in Item_Type.rect_preserve_lookup[diff_type][item_type]) {
               exclude_rect = rect.intersection(rect_fetch);
               if ( (largest_rect === null)
                   || (exclude_rect.area() > largest_rect.area()) ) {
                  largest_rect = exclude_rect;
               }
            }
         }
         return largest_rect;
      }

      // *** Class methods

      // Return true if all items in the given array are Byway objects, false
      // otherwise. Notably, if c is empty then false is returned.
      public static function byways_all(c:Array) :Boolean
      {
         var o:Object;
         if (c.length == 0)
            return false;

         for each (o in c) {
            if (!(o is Byway)) {
               return false;
            }
         }
         return true;
      }

   }
}


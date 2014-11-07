/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import flash.utils.Dictionary;
   import mx.utils.UIDUtil;

   import grax.Aggregator_Base;
   import items.attcs.Annotation;
   import items.attcs.Attribute;
   import items.attcs.Post;
   import items.attcs.Tag;
   import items.attcs.Thread;
   import items.feats.Route;
   import items.utils.Item_Type;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.misc.Strutil;
   import utils.rev_spec.*;
   //import views.panel_base.Detail_Panel_Base;

   public class Link_Value extends Item_User_Access {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Link_Value');

      // *** Mandatory attributes

      public static const class_item_type:String = 'link_value';
      public static const class_gwis_abbrev:String = 'lv';
      // class_item_type_id is only used by this class to set the lhs/rhs types
      public static const class_item_type_id:int = Item_Type.LINK_VALUE;

      // *** Other static variables

      // A lookup of Link_Values by stack_id
      public static var all:Dictionary = new Dictionary();

      // These lookups store Sets of Link_Value lookups. One is keyed by the
      // item's stack ID (which might be a geofeature or an attachment).  The
      // other is keyed by the item type (Byway, Tag, etc) and then the stack
      // ID (so the latter lookup is two dimensional). These are useful if you
      // have an item and want a Set of all of its links.
      //
      // Lookup links by linked attachment's or geofeature's stack ID
      protected static var stack_id_lookup:Dictionary = new Dictionary();
      // Lookup links by linked item's type and linked item's stack ID
      // FIXME: Should this be keyed by Item Type ID rather than its name?
      protected static var item_type_lookup:Dictionary = new Dictionary();

// FIXME: [lb] Check server SQL and make sure this is a quick query.
      // Link values missing one or both sides of the link, to be re-added,
      // when lazy loading is completed.
      public static var stranded_link_values:Set_UUID = new Set_UUID();

      // *** Instance variables

      // The two items being linked.
      // EXPLAIN: Can one expect these always to be hydrated objects?
      //          Or are just the stack IDs always set?
      //
      // The lhs item is always the Annotation, Attribute, or Post.
      public var attc:Attachment;
      // The rhs item is usually a geofeature but for link_post-revision, it's
      // an attribute (2012.08.15: Currently just /post/revision).
      // 2013.06.04: The new /item/alert_email links itself (attr) to any item.
      //             Well, it depends on what item details panels it's on, I
      //             guess [lb].
      protected var feat_:Geofeature;
      protected var attr_:Attribute;
      protected var thread_:Thread; // 2013.06.04: for thread /item/alert_email

      // MAYBE: Just call them lhs_item and rhs_item?
      // 2013.06.01: What about link_values to other attachments or even to
      //             other link_values? That way people could item-watch, e.g.,
      //             tags, or whatever.

      // The stack ID and types of the items being linked
      public var lhs_stack_id:int;
      public var rhs_stack_id:int;
      public var link_lhs_type_id:int;
      public var link_rhs_type_id:int;

      // The value of the link. Only one of these should be set.
      // FIXME: Does declaring these for every link_value bloat the client?
      public var value_boolean:* = null;
      public var value_integer:* = null;
      public var value_real:Number = NaN;
      public var value_text:String = null;
      public var value_binary:String = null;
      public var value_date:Date = null;

      // One of the linked items' name, if requested by query_filters
      // include_lhs_name or include_rhs_name.
      protected var lhs_name_:String = null;
      protected var rhs_name_:String = null;

      // The command_count tracks how many times the user has modified this
      // item in their working copy. Each count is associated with a
      // Command_Base object, so if the user undoes commands, this value gets
      // decremented.  The client uses it to see if fresh items can be deleted
      // from memory.
      public var command_count:int;

      // *** Constructor

      public function Link_Value(xml:XML=null,
                                 rev:utils.rev_spec.Base=null,
                                 lhs_item:Object=null, // attc
                                 rhs_item:Object=null) // feat or attr
      {
         // The xml should be null if lhs_item or rhs_item are not.
         m4_ASSERT((xml === null)
                   || ((lhs_item === null) && (rhs_item === null)));
         this.link_value_set(lhs_item, rhs_item);
         this.command_count = 0;
         super(xml, rev);
      }

      // *** Public static methods

      //
      public static function stranded_links_for_item(item:Item_User_Access)
         :Array
      {
         m4_ASSERT(false); // This code [probably] works, but's never called.

         var results:Array = new Array();
         var lv:Link_Value;

         for each (lv in Link_Value.stranded_link_values) {
            if (lv.rhs_stack_id == item.base_id) {
               results.push(lv);
            }
         }

         return results;
      }

      //
      public static function stranded_links_for_attc(at:Attachment) :Array
      {
         var results:Array = new Array();
         var lv:Link_Value;

         for each (lv in Link_Value.stranded_link_values) {
            if (lv.lhs_stack_id == at.base_id) {
               results.push(lv);
            }
         }

         return results;
      }

// FIXME attachments_for_item and items_for_attachment and markedly different
//       than item_get_link_values if how they use ID masks
      // Returns an array of all non-deleted attachments that reference the
      // geofeature. If diffing, returns the attachments referenced by
      // any geofeature with the base id of gf. It only returns one attachment
      // per base id, with priority to new -> old -> static.
      // FIXME: All callers seems to pass attc_type:Class => make 'em all use
      //        Item_Type.XYZ instead.
      //
      // FIXME: Do we need an attachments_for_attc? E.g., The item alerts
      //        for threads link a thread and an attribute (/item/alert_email).
      public static function attachments_for_item(
         item:Item_User_Access, attc_type:Object=null) :Array
      {
         return Link_Value.attachments_for_item_by_id(item.base_id, attc_type);
      }

      // Helper function for attachments_for_item. See notes above.
      // SIMILAR_TO: items_for_attachment_by_id
      // FIXME: All callers seem to pass attc_type:Class => make 'em all use
      //        Item_Type.XYZ instead.
      protected static function attachments_for_item_by_id(
         rhs_stack_id:int, attc_type:Object=null) :Array
      {
         var a:Array = new Array();
         // Grab the lookup for the specified attachment type
         var lookup:Dictionary = Link_Value.lookup_get(attc_type);
         var link:Link_Value;
         var attc:Attachment;
         // NOTE: V1 behavior is to ignore deleted attachments
         var ignore_deleted:Boolean = true;

         if (rhs_stack_id in lookup) {
            for each (link in lookup[rhs_stack_id]) {
               m4_VERBOSE('  link:', link, '/ attc:', link.attc);
               attc = Item_Revisioned.item_find_new_old_any(
                        link.attc, ignore_deleted) as Attachment;
               if (attc !== null) {
                  a.push(attc);
                  m4_VERBOSE('  Found attc:', attc);
               }
            }
         }
         // else, there are no attachments of the specified type attached to
         //       this geofeature

         m4_VERBOSE5('attachments_for_item_by_id',
                     '/ rhs_stack_id:', rhs_stack_id,
                     '/ attc_type:', attc_type,
                     '/ lookup[rhs_stack_id]:', lookup[rhs_stack_id],
                     '/ a:', a);

         return a;
      }

      // Returns an array of all non-deleted geofeatures that reference the
      // attachment.  If diffing, returns the geofeatures referenced by any
      // attachment with the base id of at. It only returns one geofeature per
      // base id, with priority to new -> old -> static.
      // FIXME: All callers seems to pass item_type:Class => make 'em all use
      //        Item_Type.XYZ instead.
      public static function items_for_attachment(
         at:Attachment,
         item_type:Object=null,
         link_gfs_only:Boolean=false) :Array
      {
         return Link_Value.items_for_attachment_by_id(
                  at.base_id, item_type, link_gfs_only);
      }

      // Helper function for items_for_attachment. See notes above.
      // SIMILAR_TO: attachments_for_item_by_id
      // FIXME: All callers seems to pass item_type:Class => make 'em all use
      //        Item_Type.XYZ instead.
      public static function items_for_attachment_by_id(
         lhs_stack_id:int,
         item_type:Object=null,
         link_gfs_only:Boolean=false) /* link_gfs_only is not used. */
            :Array
      {
         var a:Array = new Array();
         // Grab the lookup for the specified item type.
         var lookup:Dictionary = Link_Value.lookup_get(item_type);
         var link:Link_Value;
         var item:Item_User_Access;
         // NOTE: CcpV1 behavior is to ignore deleted attachments.
         var ignore_deleted:Boolean = true;

         if (lhs_stack_id in lookup) {
            for each (link in lookup[lhs_stack_id]) {
               m4_VERBOSE('  link:', link, '/ link.item:', link.item);

               // FIXME: If link.item is really link.attr, is this fcn. called?
               //        (I.e., post-revision lval)
               m4_ASSURT(link.item !== null);

               item = Item_Revisioned.item_find_new_old_any(
                        link.item, ignore_deleted) as Item_User_Access;
               if (item !== null) {
                  a.push(item);
                  m4_VERBOSE(' .. found item:', item);
               }
            }
         }
         // else, there are no geofeatures of the specified type attached to
         //       this attachment

         m4_VERBOSE5('items_for_attachment_by_id',
                     '/ lhs_stack_id:', lhs_stack_id,
                     '/ item_type:', item_type,
                     '/ lookup[lhs_stack_id]:', lookup[lhs_stack_id],
                     '/ a:', a);

         return a;
      }

      //
      public static function item_get_link_values(
         item:Object, filter_by_item_type:Object=null) :Set_UUID
      {
         m4_VERBOSE2('item_get_link_values: item:', item,
                     'filter_by_item_type:', filter_by_item_type);
         var stack_id:int = Item_Revisioned.item_get_stack_id(item);
         var lookup:Set_UUID;
         lookup = Link_Value.lookup_get(filter_by_item_type)[stack_id];
         if (lookup === null) {
            // No link values for this item.
            lookup = new Set_UUID();
         }
         return lookup;
      }

      // Returns the Link_Value that links feat and attc, or null if nothing
      // links them or if the link has been deleted by the client. If diffing,
      // returns the first link found between the base versions of feat and
      // attc.
      public static function items_get_link_value(
         attc:Attachment,
         item:Item_User_Access,
         make_new_maybe:Boolean=false) :Link_Value
      {
         var the_link:Link_Value;
         var lhs_type_str:String = Item_Base.item_get_type(attc);
         var lhs_type_id:int = Item_Type.str_to_id(lhs_type_str);

         // This fcn. only called for link_values to geofeatures and not for
         // link_value-revision items (whose rhs is an attribute, not
         // geofeature).
         m4_ASSURT(attc !== null);
         m4_ASSURT(item !== null);

         m4_VERBOSE8('items_get_link_value ',
                     '/ lhs_type_str:', lhs_type_str,
                     '/ lhs_type_id:', lhs_type_id,
                     '/ attc.base_id:', attc.base_id,
                     '/ item.base_id:', item.base_id,
                     '/ attc:', attc, '/ item:', item,
                     '/ attc.rev:', attc.revision,
                     '/ item.rev:', item.revision);

         // STILL_A_CONCERN?: FIXME_DIFFMODE: FIXME:
         // For all lookups, check this.rev and do not get counterpart's links.
         if ((lhs_type_id in Link_Value.item_type_lookup)
             && (item.base_id in Link_Value.item_type_lookup[lhs_type_id])) {
            for each (var link_trav:Link_Value in
                  Link_Value.item_type_lookup[lhs_type_id][item.base_id]) {
               if (link_trav.lhs_stack_id == attc.base_id) {
                  //m4_VERBOSE('items_get_link_value: found:', link_trav);
                  the_link = link_trav;
                  break;
               }
               //else {
               //   m4_VERBOSE('items_get_link_value: link_trav:', link_trav);
               //}
            }
         }

         if ((the_link === null) && (make_new_maybe)) {
            the_link = new Link_Value(null, null, attc, item);
            //m4_VERBOSE('items_get_link_value: new link:', the_link);
            // NOTE: Caller must make client ID for this link.
            // NOTE: Caller must set value_*, too.
         }

         return the_link;
      }

      // Given one or more attachments and one or more geofeatures, returns all
      // the links between the two sets. Used by concensus().
      //
      // 2013.06.04: Up until now, the fcn. tooks (attcs, feats), but really
      //             link_values can link attachments to attachments, too.
      public static function items_get_link_values(
         attcs:Set_UUID,
         itms:Set_UUID)
            :Set_UUID
      {
         var links:Set_UUID = new Set_UUID();

         m4_VERBOSE('items_get_link_values: attcs:', attcs, '/ itms:', itms);

         // This fcn. only called for link_values to geofeatures and not for
         // link_value-revision items (whose rhs is an attribute, not
         // geofeature).
         // 2013.06.04: [lb] added the widget_item_alert widget to
         // panel_item_thread, and it looks for links between threads
         // and the item alert attribute (so we don't just expect Geofeatures,
         // but Attachments as well).

         for each (var attc:Attachment in attcs) {
            m4_ASSURT(attc !== null);
            for each (var item:Item_User_Access in itms) {
               m4_ASSURT(item !== null);
               var link:Link_Value;
               link = Link_Value.items_get_link_value(attc, item);
               if (link !== null) {
                  links.add(link);
               }
            }
         }

         return links;
      }

      // Returns the appropriate links lookup given the specified item type.
      public static function lookup_get(filter_by_item_type:Object=null)
         :Dictionary
      {
         var the_lookup:Dictionary;
         m4_VERBOSE('lookup_get: filter_by_item_type:', filter_by_item_type);
         if (filter_by_item_type === null) {
            // Callee wants to find all linked items, not just those of a
            // specific type.
            the_lookup = Link_Value.stack_id_lookup;
         }
         else {
            var other_type_str:String;
            var other_type_id:int;
            other_type_str = Item_Base.item_get_type(filter_by_item_type);
            other_type_id = Item_Type.str_to_id(other_type_str);
            if (!(other_type_id in Link_Value.item_type_lookup)) {
               Link_Value.item_type_lookup[other_type_id] = new Dictionary();
               m4_VERBOSE('lookup_get: NEW:', other_type_id);
            }
            the_lookup = Link_Value.item_type_lookup[other_type_id];
         }
         m4_VERBOSE('lookup_get: the_lookup:', the_lookup.toString());
         return the_lookup;
      }

      //
      public static function lookups_reset() :void
      {
// FIXME: Should this be in or call cleanup_all ??
         Link_Value.item_type_lookup = new Dictionary();
// FIXME: This is what happens in cleanup_all:
         //Link_Value.all = new Dictionary();
         //Link_Value.stack_id_lookup = new Dictionary();
         //Link_Value.item_type_lookup = new Dictionary();
      }

      // *** Protected Static methods

      //
      protected static function items_get_from_double_lookup(
         lookup:Dictionary, inner_key:String, outer_key:String) :Set_UUID
      {
         var ivs:Set_UUID = new Set_UUID();
         if ((inner_key in lookup) && (outer_key in lookup[inner_key])) {
            ivs = lookup[inner_key][outer_key];
         }
         return ivs;
      }

      //
      protected static function item_put_in_single_lookup(lookup:Dictionary,
                                                          item_key:Object,
                                                          item:Item_Versioned)
                                                           :void
      {
         if (!(item_key in lookup)) {
            lookup[item_key] = new Set_UUID();
         }
         lookup[item_key].add(item);
      }

      //
      protected static function item_put_in_double_lookup(lookup:Dictionary,
                                                          inner_key:Object,
                                                          outer_key:Object,
                                                          item:Item_Versioned)
                                                           :void
      {
         if (!(inner_key in lookup)) {
            lookup[inner_key] = new Dictionary();
         }
         if (!(outer_key in lookup[inner_key])) {
            lookup[inner_key][outer_key] = new Set_UUID();
         }
         lookup[inner_key][outer_key].add(item);
      }

      /*/
      //
      protected static function lookups_put_item(item:Object,
         other_type_id:int, link_value:Link_Value) :void
      {
         m4_ASSERT(false); // FIXME: Delete this fcn.?
         var stack_id:int = Item_Revisioned.item_get_stack_id(stack_id);
         return lookups_put_item_by_id(stack_id, other_type_id, link_value);
      }
      /*/

      //
      protected static function lookups_put_item_by_id(
         stack_id:int, other_type_id:int, link_value:Link_Value) :void
      {
         m4_VERBOSE('lookups_put_item_by_id:', link_value);
         m4_VERBOSE3('lookups_put_item_by_id: stack_id:', stack_id,
                     ' / other_type_id:', other_type_id,
                     ' / link_value:', link_value);
         // Update stack_id_lookup
         Link_Value.item_put_in_single_lookup(
            Link_Value.stack_id_lookup,
            stack_id,      // e.g., some Geofeature's ID (or an Attribute's)
            link_value);   // e.g., add link to set of links for feat or attr
         // Update item_type_lookup
         Link_Value.item_put_in_double_lookup(
            Link_Value.item_type_lookup,
            other_type_id, // e.g., an attachment item type ID
            stack_id,      // e.g., some Geofeature's ID (or an Attribute's)
            link_value);   // e.g., add link to set of links
      }

      //
      protected static function lookups_remove_link_values(
         stack_id:int, other_type_id:int, link_value:Link_Value) :void
      {
         m4_VERBOSE5('lookups_remove_link_values:',
                     ' / link_value:', link_value,
                     ' / stack_id:', stack_id,
                     ' / other_type_id:', other_type_id,
                     ' / link_value:', link_value);
         // Remove link_value from Set() in item_type_lookup
         if (other_type_id in Link_Value.item_type_lookup) {
            if (stack_id in Link_Value.item_type_lookup[other_type_id]) {
               Link_Value.item_type_lookup[other_type_id][stack_id]
                                           .remove(link_value);
               if (Link_Value.item_type_lookup[other_type_id][stack_id]
                                               .length == 0) {
                  // Remove Set() from item_type_lookup
                  delete Link_Value.item_type_lookup[other_type_id][stack_id];
               }
            }
            if (Link_Value.item_type_lookup[other_type_id].length == 0) {
               // Remove Dictionary() from item_type_lookup
               delete Link_Value.item_type_lookup[other_type_id];
            }
         }
         // Remove link_value from Set() in stack_id_lookup
         if (stack_id in Link_Value.stack_id_lookup) {
            Link_Value.stack_id_lookup[stack_id].remove(link_value);
            if (Link_Value.stack_id_lookup[stack_id].length == 0) {
               // Remove Set() from stack_id_lookup
               delete Link_Value.stack_id_lookup[stack_id];
            }
         }
      }

      //
      public static function update_items_committed(client_id_map:Dictionary)
         :void
      {
         // Each link_value references the attachment and geofeature
         // objects, but they also store the stack_ids locally. Ug, this isn't
         // pretty: We have to loop over all link_values...
         var lval:Link_Value;
         for each (lval in Link_Value.all) {
            if (lval.lhs_stack_id in client_id_map) {
               lval.lhs_stack_id = client_id_map[lval.lhs_stack_id].new_id;
            }
            if (lval.rhs_stack_id in client_id_map) {
               lval.rhs_stack_id = client_id_map[lval.rhs_stack_id].new_id;
            }
         }
      }

      // *** The importantest getters and setters

      //
      public function get attr() :Attribute
      {
         return this.attr_;
      }

      //
      public function set attr(attr:Attribute) :void
      {
         this.attr_ = attr;
         this.feat_ = null;
         this.thread_ = null;
      }

      //
      public function get feat() :Geofeature
      {
         return this.feat_;
      }

      //
      public function set feat(feat:Geofeature) :void
      {
         this.attr_ = null;
         this.feat_ = feat;
         this.thread_ = null;
      }

      // ***

      //
      public function get item() :Item_User_Access
      {
         var item:Item_User_Access = null;
         if (this.feat_ !== null) {
            item = this.feat_;
         }
         else if (this.attr_ !== null) {
            item = this.attr_;
         }
         else if (this.thread_ !== null) {
            item = this.thread_;
         }
         // else, it's not set.
         return item;
      }

      //
      public function set item(item:Item_User_Access) :void
      {
         if (item is Geofeature) {
            this.feat_ = (item as Geofeature);
         }
         else if (item is Attribute) {
            this.attr_ = (item as Attribute);
         }
         else {
            m4_ASSERT(false);
         }
      }

      // ***

      //
      public function get attr_value_get() :*
      {
         var attr:Attribute = (this.attc as Attribute);
         var attr_value:* = (attr !== null) ? attr.value_get(this) : null;
         return attr_value;
      }

      //
      public function get thread() :Thread
      {
         return this.thread_;
      }

      //
      public function set thread(thread:Thread) :void
      {
         this.attr_ = null;
         this.feat_ = null;
         this.thread_ = thread;
      }

      // ***

      //
      public function get lhs_name() :String
      {
         var lhs_name:String;
         if (this.attc !== null) {
            lhs_name = this.attc.name_;
         }
         else {
            lhs_name = this.lhs_name_;
         }
         return lhs_name;
      }

      //
      public function set lhs_name(lhs_name:String) :void
      {
         this.lhs_name_ = lhs_name;
      }

      //
      public function get rhs_name() :String
      {
         var rhs_name:String;
         var item:Item_User_Access = this.item;
         if (item !== null) {
            rhs_name = item.name_;
         }
         else {
            rhs_name = this.rhs_name_;
         }
         return rhs_name;
      }

      //
      public function set rhs_name(rhs_name:String) :void
      {
         this.rhs_name_ = rhs_name;
      }

      // *** Getters and setters

      // Whether commands can act on this item at raster level.
      override public function get actionable_at_raster() :Boolean
      {
         var is_actionable:Boolean = false;
         // For a Link_Value, this depends on the linked geofeature.
         // FIXME: [lb] isn't convinced this is the appropriate behavior in V2.
         /*/ FIXME: Delete:
         if (this.rhs_stack_id in Geofeature.all) {
            return (Geofeature.all[this.rhs_stack_id] as Geofeature)
                     .actionable_at_raster;
         }
         /*/
         if (this.item !== null) {
            is_actionable = this.item.actionable_at_raster;
         }
         else {
            // This shouldn't be called for link_post-revision.
            m4_ASSERT_SOFT(this.attr === null);
            // Which means... that both this.item and this.attr are null?
            m4_ASSERT_SOFT(false);
         }
         return is_actionable;
      }

      //
      public function get attachment_has_nongeo_changes() :Boolean
      {
         var has_nongeo_changes:Boolean = false;

         var a_new:Attachment = null;
         var a_old:Attachment = null;
         var m_new:int = Item_Revisioned.MASK_NEW;
         var m_old:int = Item_Revisioned.MASK_OLD;

         if ((this.lhs_stack_id | m_new) in Attachment.all) {
            a_new = Attachment.all[this.lhs_stack_id | m_new]
                    as Attachment;
         }
         if ((this.lhs_stack_id | m_old) in Attachment.all) {
            a_old = Attachment.all[this.lhs_stack_id | m_old]
                    as Attachment;
         }

         // FIXME: [Histbrow] Make sure digest_nongeo still works
         if ((a_new !== null) && (a_old !== null)) {
            has_nongeo_changes = (a_new.digest_nongeo != a_old.digest_nongeo);
         }
         else if ((a_new !== null) && (a_old === null)) {
            has_nongeo_changes = true;
         }
         else if ((a_new === null) && (a_old !== null)) {
            has_nongeo_changes = true;
         }

         return has_nongeo_changes;
      }

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Link_Value.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Link_Value.all;
      }

      //
      // NOTE: This fcn. is a little couply: it ties the item classes to the
      //       view.
/*/ FIXME: Statewide UI: Delete this fcn., maybe make sure it doesn't matter...
      override public function get detail_panel() :Detail_Panel_Base
      {
         // No details panel specific to Link_Value objects (widgets, maybe).
         // Like set selected/visible, we assume they're asking for the
         // detail panel of the feature.
         // FIXME: What about Branch_Conflict?
         // EXPLAIN: Who calls this? Is this called for link_value-post, where
         //          this.attr is set but not this.feat?
         m4_WARNING('detail_panel: EXPLAIN: Who calls this fcn.?');
         m4_ASSURT((this.feat !== null) && (this.attr === null));
         return this.feat.detail_panel;
      }
/*/

      //
      override public function get discardable() :Boolean
      {
         var item:Item_Revisioned;
         var is_discardable:Boolean = super.discardable;
         // If the attachment is not discardable, neither is the link.

         if (is_discardable) {
            m4_VERBOSE('discardable: this.attc:', this.attc);
            item = Item_Revisioned.item_find_new_old_any(this.attc);
            // 2011.03.22: EXPLAIN: Tags and Attributes are not discardable, so
            //             we keep links around that we don't need?
            // 2013.03.08: Ignore Tags and Attributes, since those are not
            //             discardable. Otherwise, we'd keep links around we
            //             don't need.
            // FIXME: 2013.03.09: Are feats and attcs themselves discardable if
            //        they're hooked to a link_value that's not discardable?
            //        [lb] checked the geofeature class and it doesn't override
            //        discardable.
            //        But see also: Gefoeatures_Attachment_Add.contains_item
            //        which, if the command's edit_items is a link_value,
            //        checks if the link links to an attachment or
            //        geofeature... sheesh, that fcn. probably doesn't scale
            //        well.
            if ((item !== null)
                && (!(item is Tag))
                && (!(item is Attribute))) {
               is_discardable = item.discardable;
               m4_VERBOSE2(' .. found not-tag, not-attr attc:', item,
                           '/ discardable:', is_discardable);
            }
         }
         // If there's still a geofeature attached, the link stays.
         if (is_discardable) {
            // 2012.08.15: Is this ever this.attr? Maybe for lval post-rev?
            m4_ASSURT((this.item !== null) && (this.attr === null));
            item = Item_Revisioned.item_find_new_old_any(this.item);
            if (item !== null) {
               // NOTE: Not checking item.discardable. This is the V1 behavior.
               // FIXME: I [lb] still need convincing this is appropriate.
               is_discardable = false;
            }
         }
         return is_discardable;
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         var is_editable:Boolean = false;
         // For a Link_Value -- and like actionable_at_raster -- this depends
         // on the linked geofeature.
         // FIXME: [lb] isn't convinced this is the appropriate behavior in V2.
         if (this.item !== null) {
            is_editable = this.item.editable_at_current_zoom;
         }
         // else, see similar comment above, shouldn't be null or this.attr.
         m4_ASSERT_ELSE_SOFT; // What else is this link good for?!
         return is_editable;
      }

      //
//      public function get_gf_type() :String
      public function get gf_type() :String
      {
         var gf_type:String;
         if (this.link_rhs_type_id == Item_Type.BYWAY) {
            gf_type = 'byway';
         }
         else if (this.link_rhs_type_id == Item_Type.WAYPOINT) {
            gf_type = 'point';
         }
         else if (this.link_rhs_type_id == Item_Type.REGION) {
            gf_type = 'region';
         }
         else if (this.link_rhs_type_id == Item_Type.ROUTE) {
// FIXME: route reactions. link_route is new!
//        FIXME: probably need to add /post/route like /post/revision
// FIXME: Statewide UI: [lb] should figure out why /post/route is better than a
//        simple link_value and then maybe implement it and /post/revision.
            gf_type = 'route';
         }
/*/
//         else if (pg is Post_Revision) {
// FIXME: This isn't right, is it? lhs is attribute? rhs is... revision?
         else if (this.link_rhs_type_id == Item_Type.REVISION) {
            gf_type = 'revision';
         }
/*/
         else if (this.link_rhs_type_id == Item_Type.ATTRIBUTE) {
            var attr:Attribute = Attribute.all[this.rhs_stack_id];
            m4_ASSURT(attr !== null);
            // MAGIC_NUMBERs: Attribute names...
            if (attr.value_internal_name == '/post/revision') {
               gf_type = 'revision';
            }
            else if (attr.value_internal_name == '/post/route') {
               gf_type = 'route';
            }
            else if (attr.value_internal_name == '/item/alert_email') {
               gf_type = 'item_event_alert'; // Is this the right value?
               m4_ASSERT_SOFT(false); // This shouldn't happen; while
               // some link_values link post or thread as lhs to an
               // attribute as rhs, the alert_email uses the attr as
               // the lhs and the linkee (geofeature, thread, or route)
               // is the rhs...
            }
            else {
               m4_ASSERT_SOFT(false);
            }
         }
         else {
            m4_ASSERT_SOFT(false);
         }
         return gf_type;
      }

      //
      override public function is_selected() :Boolean
      {
         // Skipping:
         //    s = super.selected; // Abstract.
         // This should be fine: links are not selectable, per se.
         return false;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         // Skipping:
         //    super.set_selected(s, nix, solo);
         // which just loads access_style_id.
         // But you cannot edit a link_value's permissions in flashclient...

         // Currently, Command_Base sets items unselected that are part of
         // any command. We can ignore being set not selected, since we're
         // not ever set selected in the first place.

         /*
         if (this.rhs_stack_id in Geofeature.all) {
            Geofeature.all[this.rhs_stack_id].set_selected(s, nix, solo);
         }
         else if (this.lhs_stack_id in Attachment.all) {
            Attachment.all[this.lhs_stack_id].set_selected(s, nix, solo);
         }
         */

         if (s) {
            m4_WARNING('EXPLAIN: set_selected:', this);
         }
         // else, called via Command_Base to clear item selections.
      }

      //
      public function set visible(s:Boolean) :void
      {
         m4_ASSERT_SOFT(false); // Not supported.
      }

      // *** Public instance methods

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         m4_ASSERT(i == -1);
         m4_VERBOSE('item_cleanup:', this);
         super.item_cleanup(i, skip_delete);
         // NOTE: Mixing lhs and rhs:
         Link_Value.lookups_remove_link_values(
            this.lhs_stack_id, this.link_rhs_type_id, this);
         Link_Value.lookups_remove_link_values(
            this.rhs_stack_id, this.link_lhs_type_id, this);
         // FIXME: HACK: Attachment leaf classes are keyed twice: once for
         //        their own class, and once for their parent (Attachment)
         if (this.link_lhs_type_id != Item_Type.ATTACHMENT) {
            Link_Value.lookups_remove_link_values(this.rhs_stack_id,
                                                  Item_Type.ATTACHMENT,
                                                  this);
         }
         // Remove self from global lookup.
         if (!skip_delete) {
            delete Link_Value.all[this.stack_id];
            // MAYBE: What about the other three lookups? See cleanup_all.
         }
      }

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var link_value:Link_Value in Link_Value.all) {
               link_value.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Link_Value.all = new Dictionary();
         Link_Value.stack_id_lookup = new Dictionary();
         Link_Value.item_type_lookup = new Dictionary();
         Link_Value.stranded_link_values = new Set_UUID();
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Link_Value = (to_other as Link_Value);
         super.clone_once(other);

         other.attc = this.attc;
         other.feat = this.feat;
         other.attc = this.attr;
         other.lhs_stack_id = this.lhs_stack_id;
         other.rhs_stack_id = this.rhs_stack_id;
         other.lhs_stack_id = this.lhs_stack_id;
         other.link_rhs_type_id = this.link_lhs_type_id;
         other.value_boolean = this.value_boolean;
         other.value_integer = this.value_integer;
         other.value_real = this.value_real;
         other.value_text = this.value_text;
         other.value_binary = this.value_binary;
         other.value_date = this.value_date;
         other.lhs_name = this.lhs_name;
         other.rhs_name = this.rhs_name;
         // Skipping: command_count
      }

      // Makes a new copy of this Link_Value. The ID and version are not
      // copied, nor is the new item inserted into the map.
      public function clone_for_geofeature(feat:Geofeature) :Link_Value
      {
         m4_ASSURT(feat !== null);
         var other:Link_Value = new Link_Value(null, null, this.attc, feat);

         // NOTE: Skipping: G.map.items_add([other,]);
         // NOTE: We're not calling this.clone_once but rather the parent's,
         //       because the feat is not this.feat.
         super.clone_once(other);

         other.value_boolean = this.value_boolean;
         other.value_integer = this.value_integer;
         other.value_real = this.value_real;
         other.value_text = this.value_text;
         other.value_binary = this.value_binary;
         other.value_date = this.value_date;
         other.lhs_name = this.lhs_name;
         other.rhs_name = this.rhs_name;

         return other;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Link_Value = (to_other as Link_Value);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);

         this.value_boolean = null;
         this.value_integer = NaN;
         this.value_real = NaN;
         this.value_text = null;
         this.value_binary = null;
         this.value_date = null;

         this.lhs_name = null;
         this.rhs_name = null;

         if (gml !== null) {

            m4_VERBOSE('Link_Value: gml:', gml.toXMLString());
            // Skipping: this.attc and this.feat; they'll be set on init().
            this.lhs_stack_id = int(gml.@lhs_stack_id);
            this.rhs_stack_id = int(gml.@rhs_stack_id);
            this.link_lhs_type_id = int(gml.@link_lhs_type_id);
            this.link_rhs_type_id = int(gml.@link_rhs_type_id);
            m4_VERBOSE('this.link_lhs_type_id:', this.link_lhs_type_id);
            m4_VERBOSE('this.link_rhs_type_id:', this.link_rhs_type_id);
            // FIXME: Where's the place you tested attribute existence but not
            //        this way?
            if ('@value_boolean' in gml) {
               this.value_boolean = Boolean(int(gml.@value_boolean));
            }
            if ('@value_integer' in gml) {
               this.value_integer = int(gml.@value_integer);
            }
            if ('@value_real' in gml) {
               this.value_real = Number(gml.@value_real);
            }
            if ('@value_text' in gml) {
               this.value_text = gml.@value_text;
            }
            if ('@value_binary' in gml) {
               this.value_binary = gml.@value_binary;
            }
            if ('@value_date' in gml) {
               // FIXME: Converting Date is not tested
               this.value_date = (gml.@value_date as Date);
            }
            if ('@lhs_name' in gml) {
               this.lhs_name = gml.@lhs_name;
            }
            if ('@rhs_name' in gml) {
               this.rhs_name = gml.@rhs_name;
            }
            m4_VERBOSE('gml.link_lhs_type_id:', this.link_lhs_type_id);
            m4_VERBOSE('gml.link_rhs_type_id:', this.link_rhs_type_id);
         }
         else {
            if (this.attc !== null) {
               // We also expect this.feat or this.attr to be set; otherwise,
               // item_get_stack_id will raise.
               this.lhs_stack_id =
                  Item_Revisioned.item_get_stack_id(this.attc);
               // The link_value rhs is either a geofeature or an attribute.
               var rhs_item:Object;
               if (this.feat !== null) {
                  rhs_item = this.feat;
               }
               else if (this.attr !== null) {
                  rhs_item = this.attr;
               }
               else if (this.thread !== null) {
                  rhs_item = this.thread;
               }
               else {
                  m4_ASSURT(false);
               }
               this.rhs_stack_id = Item_Revisioned.item_get_stack_id(rhs_item);
            }
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         gml.setName(Link_Value.class_item_type); // 'link_value'

         // The base class sets 'name', which we don't want to send.
         delete gml.@name;

         // Stack IDs
         gml.@lhs_stack_id = this.lhs_stack_id;
         gml.@rhs_stack_id = this.rhs_stack_id;
         // Types
         gml.@link_lhs_type_id = this.link_lhs_type_id;
         gml.@link_rhs_type_id = this.link_rhs_type_id;
         // Values
         if (this.value_boolean !== null) {
            gml.@value_boolean = int(this.value_boolean);
         }
         if (!isNaN(this.value_integer)) {
            gml.@value_integer = this.value_integer;
         }
         if (!isNaN(this.value_real)) {
            gml.@value_real = this.value_real;
         }
         if (this.value_text !== null) {
            gml.@value_text = this.value_text;
         }
         if (this.value_binary !== null) {
            gml.@value_binary = this.value_binary;
         }
         if (this.value_date !== null) {
            gml.@value_date = this.value_date;
         }
         /* Nope:
         if (this.lhs_name !== null) {
            gml.@lhs_name = this.lhs_name;
         }
         if (this.rhs_name !== null) {
            gml.@rhs_name = this.rhs_name;
         }
         */

         return gml;
      }

      //
      public function link_value_set(
         attc:Object=null,
         feat_or_attr:Object=null) :void
      {
         // [lb]: I first tried loading links alongside attachments and
         // geofeatures. The attachment and geofeature would both register with
         // the link when they loaded, and only once both were loaded did the
         // link load itself. Nowadays, links aren't loaded until all the
         // attachments and geofeatures are.
         m4_DEBUG('link_value_set: attc:', attc);
         m4_DEBUG('link_value_set: feat_or_attr:', feat_or_attr);
         // Both attc and feat_or_attr are now when flashclient boots (see
         // init_GetDefinitionByName, which creates dummy objects of each
         // type).
         if (attc !== null) {
            m4_ASSERT(attc is Attachment);
            this.link_lhs_type_id = Introspect.get_constructor(attc)
                                                .class_item_type_id;
            m4_ASSURT(this.link_lhs_type_id != 0);
            this.attc = (attc as Attachment);

            //this.lhs_stack_id = Item_Revisioned.item_get_stack_id(attc);
/* FIXME_DIFFMODE: Why didn't Mikhil do this, too?: */
//            this.lhs_stack_id = this.attc.stack_id;
// [lb] Wonders if maybe we want the hacked stack ID? Or not??
//      Argh: TEXT_ME: Test diff mode more and see what's up...
            this.lhs_stack_id = this.attc.base_id;

            //this.attc_type = Item_Base.item_get_type(attc);

         }
         if (feat_or_attr !== null) {
            this.link_rhs_type_id = Introspect.get_constructor(feat_or_attr)
                                                         .class_item_type_id;
            m4_ASSURT(this.link_rhs_type_id != 0);
            // The Link_Post class can also link to revisions, so rhs is not
            // always a Geofeature, it could be an Attribute.
            if (feat_or_attr is Geofeature) {
               this.feat = (feat_or_attr as Geofeature);
            }
            else if (feat_or_attr is Attribute) {
               // 2012.08.15: A post can link to an attribute, /post/revision.
               m4_ASSURT(this.attc is Post);
               this.attr = (feat_or_attr as Attribute);
            }
            else if (feat_or_attr is Thread) {
               // 2013.06.04: Thread (and other items) can link to Attribute,
               //             /item/alert_email.
               m4_ASSURT(this.attc is Attribute);
               this.thread = (feat_or_attr as Thread);
            }
            else {
               m4_ASSERT(false);
            }
            // Note that this.item is whatever is set: feat, attr, or thread.
// FIXME_DIFFMODE: Another reason to test diff mode: Should we be using
//                 hacked stack ID or the base ID?
//            this.rhs_stack_id = this.item.stack_id;
            this.rhs_stack_id = this.item.base_id;
         }

         if (this.attc !== null) {
            // 2013.05.13: For fresh attributes, indicate they've been
            //             used now.
            this.attc.link_value_set(this, true);
         }

         // Update the link_value counts if this is a geofeature-linked
         // link_value.
         if ((this.attc !== null) && (this.feat !== null)) {
            // They do! So poke 'em and let 'em fix any broken links that
            // may have been created (for example, if the user selects a
            // byway on the map before the annotations are loaded, we need
            // to refresh the view).
            // NOTE: This is quite kludgy.
            // NOTE: This is also quite redundant: the server sends this?
            if (this.attc is Annotation) {
               // FIXME: Is this correct? I imagine the counts will get out of
               //        sync as the user works on the map. Not too big a
               //        deal....
               //this.feat.annotations_exist = true;
               this.feat.annotation_cnt += 1;
            }
            else if (this.attc is Post) {
               // FIXME: See previous note about annotation_cnt
               //this.feat.posts_exist = true;
               this.feat.discussion_cnt += 1;
            }
         }

         m4_DEBUG('link_value_set: done: this:', this);
      }

      // *** Item Init/Update fcns.

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         /*
         if (d) {
            delete Link_Value.all[this.stack_id];
         }
         else {
            if (this !== Link_Value.all[this.stack_id]) {
               if (this.stack_id in Link_Value.all) {
                  m4_WARNING2('set deleted: overwrite:',
                              Link_Value.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Link_Value.all[this.stack_id] = this;
            }
         }
         */
         // Skipping: stack_id_lookup.
         // Skipping: item_type_lookup.
         // Skipping: stranded_link_values.

         // Tell the attribute it may no longer be used.
         if (this.attc !== null) {
            this.attc.link_value_set(this, !d);
         }
      }

      // FIXME This fcn. violates the spirit of Item_Base.init_item(), which is
      //       not to assume anything else is available. Rather, this fcn.
      //       assumes the geofeature and the attachment are present. I wonder
      //       if fixing these would speed up loading flash (see also the wait
      //       in the Update classes)
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(item_agg, soft_add);
         // Always put the link in the stranded set at first, because
         // update_link_value_cache() only proceeds if it's in the stranded set
         m4_TALKY('init_add: stranded_link_values.add:', this);
         Link_Value.stranded_link_values.add(this);
         this.update_link_value_cache();
      }

      // Update the link value cache to contain this link value after
      // its attachment and feature have been filled-in.
      public function update_link_value_cache() :void
      {
         var attc:Attachment = Attachment.all[this.lhs_stack_id];
         var item:Item_User_Access = Geofeature.all[this.rhs_stack_id];
         if (item === null) {
            if (this.link_rhs_type_id == Item_Type.THREAD) {
               item = Attachment.all[this.rhs_stack_id];
               m4_DEBUG('update_link_value_cache: thread:', item);
            }
            else if (this.link_rhs_type_id == Item_Type.POST) {
               item = Attachment.all[this.rhs_stack_id];
               m4_DEBUG('update_link_value_cache: post:', item);
               m4_ASSERT_SOFT(false); // Does this happen?
            }
            else if (this.link_rhs_type_id == Item_Type.ATTRIBUTE) {
               item = Attribute.all[this.rhs_stack_id];
               m4_DEBUG('update_link_value_cache: attr:', item);
               // 2014.09.17: Happened to me, [lb]!
               //             Probably item watchers? Ratings? Does it matter?
               //m4_ASSERT_SOFT(false); // Does this happen?
            }
            else if (this.link_rhs_type_id == Item_Type.ROUTE) {
               item = Route.all[this.rhs_stack_id];
               m4_DEBUG('update_link_value_cache: route:', item);
               m4_ASSERT_SOFT(false); // Does this happen?
            }
            else {
               m4_DEBUG('update_link_value_cache: no item yet:', this);
            }
         }
         else {
            m4_DEBUG('update_link_value_cache: feat:', item);
         }

         if (   (attc !== null)
             && (item !== null)
             && (Link_Value.stranded_link_values.is_member(this))) {

// FIXME_DIFFMODE: [mm] calls item_find_new_old_any_id since lhs_stack_id is
// maybe hacked, but [lb] now stores unhacked lhs_stack_id... argh... so how
// do link_values work? you're going to need to specify counterpartness, or
// maybe just check this.rev?
// 2014.07.08: Per previous comments, see Item_Revisioned.MASK_OLD/MASK_NEW.
//             I [lb] think that when diffing tags and attributes we can
//             go with the lightweight values, but for annotations we'd
//             need historic link_values for historic notes... or maybe
//             we can load lightweight annotations and not worry about
//             link_values for historic or diff revisions.
            this.link_value_set(attc, item);

            // NOTE: We pass one link's stack ID and the other's type ID so we
            //       can lookup link_values by the type being linked.
            Link_Value.lookups_put_item_by_id(
               this.lhs_stack_id, this.link_rhs_type_id, this);
            // The server sends us actual attachments, and not the base class.
            m4_ASSERT(this.link_lhs_type_id != Item_Type.ATTACHMENT);
            Link_Value.lookups_put_item_by_id(
               this.rhs_stack_id, this.link_lhs_type_id, this);
            // Add self to our global 'all' lookup.

            // 2013.09.05: FIXED?: Is this the expectation?
            //             If not... what about references to
            //             the existing item? If not... shouldn't
            //             we use the existing item instead?
            //m4_ASSERT(Link_Value.all[this.stack_id] === null);
            var resident_item:Item_User_Access = Link_Value.all[this.stack_id];
            if (resident_item !== null) {
               // This happens from link_values_lazy_load_okay.
               if (this !== resident_item) {
                  m4_WARNING2('update_link_value_cache:          this:',
                     UIDUtil.getUID(this), '/', this);
                  m4_WARNING2('update_link_value_cache: resident_item:',
                     UIDUtil.getUID(resident_item), '/', resident_item);
                  // 2014.09.12: This happens a lot. But it seems to also just
                  // be duplicate data. So: [lb] is curious why this happens
                  // (we're getting a link_value that we already have), but
                  // I also know this isn't causing any problems... so, low
                  // priority FIXME: why are we lazy-loading the same
                  // information? Probably doesn't matter.. does it?
                  // FIXME2: Make special logging for special users, i.e.,
                  //         I [lb] don't know how to reproduce this issue,
                  //         but I know it happens a lot. Rather than get a
                  //         lot of emails about when anyone tickles this
                  //         error, only bother emailing when I tickle this
                  //         error.
                  if ((G.user.username in Conf_Instance.developer_usernames)
                      || (this.stack_id != resident_item.stack_id)
                      || (this.version != resident_item.version)) {
                     m4_ASSERT_SOFT(false); // Print a stack_trace.
                     G.sl.event('error/lval/update_lval_cache',
                        {link_value: this.toString(),
                         resident_item: resident_item.toString()});
                  }
               }
            }

            Link_Value.all[this.stack_id] = this;

            // Remove the link_value from the stranded set.
            Link_Value.stranded_link_values.remove(this);

            // Update Geofeature.attrs or Geofeature.tags, maybe.
            m4_TALKY('this.item:', this.item);
            // MAYBE: Maintaining attrs and tags is probably redundant:
            //        See: Tag and Attribute link_value_set().
            if ((this.attc !== null) && (this.item !== null)) {
               var attr:Attribute = (this.attc as Attribute);
               var tag:Tag = (this.attc as Tag);
               if (attr !== null) {
                  if (!this.deleted) {
                     var attr_val:* = attr.value_get(this);
                     this.item.attrs[attr.value_internal_name] = attr_val;
                     m4_TALKY(' attr.name_:', attr.name_);
                     m4_TALKY2(' attr.value_internal_name:',
                               attr.value_internal_name);
                     // FIXME_2013_06_11: Check that internal name exists?
                     m4_TALKY2('_lval_cache: feat.attrs[attr.val_int_name]:',
                               this.item.attrs[attr.value_internal_name]);
                  }
                  else if (attr.value_internal_name in this.item.attrs) {
                     delete this.item.attrs[attr.value_internal_name];
                  }
               }
               else if (tag !== null) {
                  if (!this.deleted) {
                     this.item.tags.add(tag.name_);
                  }
                  else {
                     this.item.tags.remove(tag.name_);
                  }
                  m4_TALKY('_lval_cache: tags:', this.item.tags);
               }
            }
            else {
               m4_TALKY('_lval_cache: attc and/or feat not set');
            }
         }
         else {
            // In CcpV1, this happens if the server sends links that reference
            // deleted attachments or geofeatures. It means that either or both
            // the items linked have been wiki-deleted. In CcpV2, this happens
            // to notes, whose link_values we get first, before fetching the
            // annotations themselves.
            // 2014.07.05: Also happens to posts linked to gfs not loaded
            //             (user can click the post attached place widget
            //             to zoom-to the geofeature).
            if (   (this.link_lhs_type_id != Item_Type.ANNOTATION)
                && (this.link_lhs_type_id != Item_Type.POST)
                // 2014.09.16: Also happens to fresh tags (e.g., open a byway
                // panel and add a new tag that's new to the byway and also a
                // new tag name).
                && (this.link_lhs_type_id != Item_Type.TAG)
                // This is for the item-event-alert watcher attribute:
                && (this.link_lhs_type_id != Item_Type.ATTRIBUTE)) {
                m4_WARNING2('Missing link: cannot add:',
                            this.toString_Verbose());
                m4_WARNING2('lhs_stack_id in Attachment.all:',
                            (this.lhs_stack_id in Attachment.all));
                m4_WARNING2('rhs_stack_id in Geofeature.all:',
                            (this.rhs_stack_id in Geofeature.all));
                m4_WARNING2('rhs_stack_id in Attachment.all:',
                            (this.rhs_stack_id in Attachment.all));
                m4_WARNING2('Link_Value.stranded_link_values.is_member(this):',
                            Link_Value.stranded_link_values.is_member(this));
                m4_WARNING(Introspect.stack_trace());
            }
         }
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_ASSERT(existing === null);
         var link:Link_Value = Link_Value.all[this.stack_id];
         if (link !== null) {
            m4_DEBUG('init_update: Updating Link_Value: this:', this);
            m4_DEBUG('init_update: Updating Link_Value: link:', link);

// FIXME_2013_06_11: Revisit init_update and clone and clone_update and lvals.
// This happens when you edit an item's link_value but we're not updating the
// item.
// FIXME_DIFFMODE: [mm] comments this out. [lb] thinks clone_item is okay.
            this.clone_item(link);

// Will this rewire the geofeature's attrs and tags?
            // Re-add to lookups.
            m4_DEBUG('init_update: stranded_link_values.add: link:', link);
            Link_Value.stranded_link_values.add(link);
            link.update_link_value_cache();
         }
         else {

            // FIXME: Here is a scenario where this happens: Detach a place
            //        from a note and then undo the what was just done using
            //        the "Undo" button. The system tries to add the link-value
            //        that was deleted back to the map. This gets interpreted
            //        as an update, since its stack_id > 0, but it doesn't find
            //        the link-value in the lookup, since it was once removed
            //        from it.
            //
            //        If this is a legitimate scenario, we must add the
            //        link-value to the look-up at this stage and perhaps,
            //        rework the m4_ASSERT_SOFT? One way to do this is to
            //        make sure that link_value.deleted = true here -- this
            //        will force the caller to first re-add the link-value to
            //        the map, and then set its deleted = false, which seems
            //        resonable. ([mm] 2013.04.10)
            //
            // m4_ASSERT_SOFT(false);
            m4_ASSERT_SOFT(this.deleted);

            // Re-add to lookups.
            m4_DEBUG('init_update: stranded_link_values.add: this:', this);
            Link_Value.stranded_link_values.add(this);
            this.update_link_value_cache();
         }
         return link;
      }

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         this.update_item_all_lookup(Link_Value, commit_info);
         super.update_item_committed(commit_info);
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         return (super.is_item_loaded(item_agg)
                 || (this.stack_id in Link_Value.all));
      }

      // *** Developer methods

      //
      override public function toString() :String
      {
         var attc_name:String =
            (this.attc !== null) ? Strutil.snippet(this.attc.name_) : 'null';
         var item_name:String =
            (this.item !== null) ? Strutil.snippet(this.item.name_) : 'null';
         var attr:Attribute = (this.attc as Attribute);
         var attr_value:* = (attr !== null)
                            ? ('/ val: ' + attr.value_get(this)) : '';
         return (super.toString()
                 + ' / attc: ' + this.lhs_stack_id + ' (' + attc_name + ')'
                 + ' / item: ' + this.rhs_stack_id + ' (' + item_name + ')'
                 + attr_value);
      }

      //
      override public function toString_Verbose() :String
      {
         return (super.toString_Verbose()
                 + ' | lhs: ' + this.lhs_stack_id
                 + ', typ: '  + this.link_lhs_type_id
                 + ', atc: '  + this.attc
                 + ' | rhs: ' + this.rhs_stack_id
                 + ', typ: '  + this.link_rhs_type_id
                 + ', itm: '  + this.item
                 + ' | bol: ' + this.value_boolean
                 + ', int: '  + this.value_integer
                 + ', rel: '  + this.value_real
                 + ', txt: '  + this.value_text
                 + ', bny: '  + this.value_binary
                 + ', dat: '  + this.value_date
                 + ', lnm: '  + this.lhs_name
                 + ', rnm: '  + this.rhs_name
                 );
      }

      //
      /*
      We shouldn't import child classes:
      import items.links;
      public static function printlu() :void
      {
         var lv:*;
         for (var stack_id:* in Link_Value.stack_id_lookup) {
            m4_DEBUG('s', stack_id);
            for each (lv in Link_Value.stack_id_lookup[stack_id].as_Array()) {
               // FIXME: Coupling: Referencing a child class.
               if (lv is Link_Geofeature) {
                  if ((lv as Link_Geofeature).attc is Annotation) {
                     m4_DEBUG3('  LG', (lv as Link_Geofeature).stack_id,
                               (lv as Link_Geofeature).attc,
                               (lv as Link_Geofeature).feat);
                  }
               }
               else if (lv is Link_Value) {
                  if ((lv as Link_Value).attc is Annotation) {
                     m4_DEBUG3('  LV', (lv as Link_Value).stack_id,
                               (lv as Link_Value).attc,
                               (lv as Link_Value).feat);
                  }
               }
            }
            m4_INFO('\n');
         }
      }
      */

      //
      public static function printl() :void
      {
         for (var stack_id:* in Link_Value.all) {
            m4_DEBUG('s', stack_id, '/', Link_Value.all[stack_id]);
            m4_DEBUG('\n');
         }
      }

   }
}


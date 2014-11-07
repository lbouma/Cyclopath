/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import grax.Aggregator_Base;
   import grax.Dirty_Reason;
   import gwis.GWIS_Commit;
   import items.attcs.*;
   import items.feats.*;
   import items.gracs.*;
   import items.jobsq.*;
   import items.links.*;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Strutil;
   import utils.rev_spec.*;
   import views.panel_items.Panel_Item_Versioned;

   public class Item_Versioned extends Item_Revisioned
   {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Versnd');

      // *** Mandatory attributes

      // At runtime, an object instance doesn't know its class name. To help
      // with our factory functions, which create items based on XML input, we
      // cheat: We attach the class name to the class definition. (But see also
      // getQualifiedClassName, which is used in item_get_type.)
      // - These values are always lowercase, in the server and in the client.
      // - Derived classes must define these three variables.
      // The first value, class_item_type, is the class name.
      public static const class_item_type:String = 'item_versioned';
      // The second value, class_gwis_abbrev, is an abbreviated name for GWIS.
      //   public static const class_gwis_abbrev:String = 'iv';
      // The third value is the item type ID. This is used just by Link_Value.
      //  public static const class_item_type_id:String =
      //    Item_Type.ITEM_VERSIONED;
      //
      // Derived classes must indicate the Detail_Panel_Base class. E.g.,
      //  public static const dpanel_class_static:Class = Panel_Item_Versioned;

      // *** Other static variables

      // Hack to overcome getDefinitionByName limitation
      //
      // Even though we import items.*.* above, getDefinitionByName doesn't
      // know about those classes unless at least one of them has been
      // instantiated. So we dance a little dance, and hack a little hack,
      // and force-load the items.attcs/feats/gracs.* modules when this class
      // is first loaded. This lets other packages use getDefinitionByName to
      // make new items based on XML strings. This boolean simply records if
      // we've done the hack or not.
      protected static var inited_GetDefinitionByName:Boolean = false;

      // *** Instance variables

      // Values from the database

      // The system_id can be used to test if two items w/ the same stack_id
      // are truly the same item. This is useful because comparing versions
      // can't tell you uniqueness, since the client's working copy diverges
      // from the server's mailine.
      public var system_id:int;

      // The branch ID is important, since we implement stacked branching.
      public var branch_id:int;

      // NOTE The stack_id is defined by Item_Base.

      // The version is what's stored in the database. When a user edits an
      // item locally, we don't bump this number, since we want the server to
      // know which item version we edited.
      // NOTE In V1, to detect concurrent saves, the working copy doesn't
      //      increment version so that, when it updates the map, it can detect
      //      items that other users have saved. With the introduction of
      //      system_id, however, we could bump version and nullify system_id
      //      to indicate a dirty item. Either way, this decision doesn't seem
      //      to make much difference.
      public var version:uint;

      // NOTE The server doesn't send us deleted items. So Item_Versioned
      //      doesn't have a deleted Boolean like you'll find in the database.
      //      However, if the user deletes an item in his or her working copy,
      //      then we need to tell the server to delete that item. For this
      //      task, we implement a getter and setter for deleted, below.

      // The name_ is the name or description of the item. Uses a trailing
      // underscore so not to conflict with reserved name.
      [Bindable] public var name_:String

      public var item_stack:Item_Stack;
      // This is our calculated access_infer_id. See item_stack.access_infer_id
      // for the latest value that the server sent us.
      public var latest_infer_id:* = null;

      // *** Constructor

      public function Item_Versioned(xml:XML=null,
                                     rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
         // No: this.revisioned_id_init(this.stack_id);
         //  wait for set_revision instead.
      }

      // *** Protected methods

      // The clone function copies everything except unique identifiers,
      // such as the stack ID and version.
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Item_Versioned = (to_other as Item_Versioned);
         super.clone_once(other);

         // The clone_once() fcn. is called to make new items from existing
         // items, but it's very deliberate. When an item is first created,
         // it's usually hydrated via gml_consume. Once it's in the system,
         // if we lazy-load data, link route steps and route stops, we'll
         // clone_update(), or if we pan the map back to where a user has
         // already seen and edited, we'll clone_update() and not overwrite any
         // data the user may have edited. This fcn., clone_once(), is used
         // internally to make item copies, like when switching item versions
         // or when cloning an item to make a private copy. I.e., not called
         // very often. (See: commands.Item_Reversion.)

         // The other item -- the clone -- was just created so its unique IDs
         // won't exist. Depending on what's going on -- cloning to make a
         // private item copy, or cloning to swap item versions -- the caller
         // might call clone_id next, as we don't copy unique identifiers here.

         m4_TALKY('clone_once: this.name_:', this.name_, '/ other:', other);
         other.name_ = this.name_;

         other.digest_nongeo = this.digest_nongeo;

         // Remember the item_stackamo.
         if (this.item_stack !== null) {
            other.item_stack = this.item_stack.clone_item(other.item_stack);
         }
         // else, when cloning items like split-byways that the user has not
         //       ever selected and lazy-loaded, the item_stack may not be set.
      }

      //
      override public function clone_id(to_other:Record_Base) :void
      {
         var other:Item_Versioned = (to_other as Item_Versioned);
         // Not calling: super.clone_id (raises).

         // NOTE: This fcn. not really used: it's called to support
         //       Route Feedback Drag, to keep a copy of the original
         //       route in Route.fresh_route. But Route Feedback Drag
         //       is currently disabled.

         other.system_id = this.system_id;
         other.branch_id = this.branch_id;
         other.stack_id = this.stack_id;
         other.version = this.version;

         if (this.item_stack !== null) {
            this.item_stack.clone_id(other.item_stack);
         }
         m4_ASSERT_ELSE_SOFT;
      }

      //
      override protected function clone_update( // on-op (no-op but see cmment)
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Item_Versioned = (to_other as Item_Versioned);
         super.clone_update(other, newbie);

         // This fcn., clone_update, is called when we've checkedout items
         // from the server that are not new to flashclient. For example,
         // a user edits an item and later pans away from the edit, but
         // while we discard other, unedited items, we keep the edited item;
         // so when the user later pans back, we'll fetch all items in the
         // viewport, and when this same item is received from the server,
         // rather than calling clone_once, we'll call clone_update. For
         // most items, clone_update is a no-op: we already have the data
         // that we need, and if any attributes are different, it's because the
         // user changed them and a save is pending (so we don't want to lose
         // the user's pending changes by consuming the server's values). But
         // for items for which we lazy-load data -- like, lazy-loading route
         // steps for a route -- we'll call clone_update and we'll fill in
         // attributes with the data we're receiving that we didn't get on the
         // "lightweight" item checkout.
         // 2014.06.26: We'll also call this fcn. via commands.Item_Reversion.
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            // FIXME: 2012.05.04: I [lb] don't think pyserver sends system_id.
            this.system_id = int(gml.@syid);
            this.branch_id = int(gml.@brid);
            this.stack_id = int(gml.@stid);
            this.version = uint(gml.@v);
            // Skipping: deleted (server doesn't send; we have getter instead)
            this.name_ = gml.@name;
            // Skipping: valid_start_rid and valid_until_rid
            this.digest_nongeo = gml.@dng;
            m4_ASSERT((this.stack_id & Item_Revisioned.MASK_ID_TAGS) == 0);
            // Pickup the item_stack table values maybe.
            this.item_stack = new Item_Stack(this, gml);
            if (this.item_stack.informationless) {
               this.item_stack = null;
            }
         }
         else {
            // This item was internally-created and will be assigned these IDs
            // by the Item_Manager or by some other means, perhaps even clone.
            this.system_id = 0;
            this.branch_id = 0;
            this.stack_id = 0;
            this.version = 0;
            // Skipping: name_
            // Skipping: digest_nongeo
         }
      }

      // Return an XML element representing myself.
      override public function gml_produce() :XML
      {
         // FIXME: Revisit this: I'm not sure yet if the server will find
         //        system_id useful, or if stack_id and version will suffice.
         // FIXME: I don't think items need either system ID or branch ID
         //        ...okay, except for conflicts, yes. but not system_id.
         //system_id={this.system_id}
         //branch_id={this.branch_id}
         var gml:XML = <item />;
         gml.@stid = this.stack_id
         gml.@v = this.version
         // null must not be sent as "null"
         if (this.name_ !== null) {
            gml.@name = this.name_;
         }
         gml.@del = int(this.deleted);
         if (this.item_stack !== null) {
            this.item_stack.gml_append(gml);
         }
         return gml;
      }

      // *** Getters and setters

      // Indicates whether commands can act (call do_()) on this item at a
      // raster level. Most geographic features can only be edited in vector
      // mode, but branches, regions and routes can be edited at any zoom
      // level. Attachments are generally editable at any zoom level, too.
      // NOTE: Kinda like but kinda opposite Geofeature.drawable_at_zoom_level
      // FIXME: This is a class thingy, not an instance thingy
      // See also: editable_at_current_zoom
      public function get actionable_at_raster() :Boolean
      {
         return false;
      }

      //
      override public function get deleted() :Boolean
      {
         var deleted_:Boolean = false;
         if (G.item_mgr !== null) {
            // The deletedset used to be a set of items but a set stringifies
            // the item first, which is inefficient (maybe), but more
            // importantly it's prone to error if we're not careful about our
            // toString() fcns. So it's better to use stack IDs. And then
            // we might as well just use the built-in Dictionary.
            deleted_ = ((this.stack_id in G.item_mgr.deletedset)
                        || (this.stack_id in G.item_mgr.donedeleted));
         }
         return deleted_;
      }

      // Adds/removes this feature from the deleted set, it does NOT
      // handle discarding it from the map or from the client.
      //
      // CALLERS: You'll want to call this.dirty_set(Dirty_Reason.item_data)
      //          on your own.....
      public function set deleted(d:Boolean) :void
      {
         //m4_DEBUG('deleted: this:', this);
         if (d != this.deleted) {
            m4_ASSURT(this.stack_id != 0);
            if (d) {
               if (this !== G.item_mgr.deletedset[this.stack_id]) {
                  if (this.stack_id in G.item_mgr.deletedset) {
                     m4_WARNING2('set deleted: overwrite:',
                                 G.item_mgr.deletedset[this.stack_id]);
                     m4_WARNING('               with:', this);
                     m4_WARNING(Introspect.stack_trace());
                  }
                  G.item_mgr.deletedset[this.stack_id] = this;
               }
               this.set_selected(false, /*nix=*/true);
            }
            else {
               delete G.item_mgr.deletedset[this.stack_id];
            }
         }
      }

      //
      override public function get dirty() :Boolean
      {
         return this.dirty_get(null);
      }

      //
      override public function dirty_set(reason:uint, d:Boolean) :void
      {
         super.dirty_set(reason, d);
         if (reason != Dirty_Reason.not_dirty) {
            m4_DEBUG('dirty_set: reset reversion_version');
            this.reversion_version = 0;
            m4_ASSERT_SOFT(this.master_item === null);
         }
         m4_TALKY('dirty_set: dispatchEvt: itemReversionReset');
         this.dispatchEvent(new Event('itemReversionReset'));
      }

      //
      override public function get discardable() :Boolean
      {
         var is_discardable:Boolean = true;
         // If the item is dirty or part of a command, it cannot be deleted.
         if (this.selected
             || this.dirty
             // This next fcn. is costly. Check every single command to see if
             // this item is discardable. If there are a lot of commands, we'll
             // be checking them over and over and over again for all of the
             // items we're discarding...
             || G.map.cm.is_feature_present(this)) {
            is_discardable = false;
         }
         return is_discardable;
      }

      // Indicates if this item is editable at the map's current zoom level.
      // NOTE: This tightly couples this class to Map_Canvas... oh, well....
      // See also: actionable_at_raster
      public function get editable_at_current_zoom() :Boolean
      {
         m4_ASSERT_SOFT(false); // Abstract
         return false;
      }

      //
      // FIXME Rather than use item_get_type, make this fcn. work more like
      //       the previous function, detail_panel(), which gets the item's
      //       constructor. I.e., by default, use the internal type name,
      //       this.constructor.class_item_type. But for some types (like
      //       Byway, which goes by the friendly name, "Block"), define a new
      //       static member, this.constructor.item_type_name_friendly
      public function get friendly_name() :String
      {
         // Our item types are lowercase to match the server, so we just
         // uppercase the first character to make it pretty for the user.
         var item_type:String = Item_Base.item_get_type(this);
         return item_type.substr(0, 1).toUpperCase()
                + item_type.substr(1).toLowerCase()
      }

      //
      public function get is_basemap_item() :Boolean
      {
         return (this.branch_id == Branch.ID_PUBLIC_BASEMAP);
      }

      // Returns true if this item is useless unless linked to another item.
      // This is used when commiting to filter out orphaned notes and tags.
      public function get is_link_parasite() :Boolean
      {
         return false;
      }

      // Geofeatures and Attachments can be selected and override this
      // function. Tiles and Link Values cannot be selected.
      //
      public function get selected() :Boolean
      {
         return this.is_selected();
      }

      //
      public function set selected(s:Boolean) :void
      {
         // Callers should really use set_selected, so that nix can be used.
         m4_ASSERT(false); // Abstract.
      }

      //
      public function is_selected() :Boolean
      {
         m4_ASSERT(false); // Abstract.
         return false;
      }

      //
      public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         m4_ASSERT(false); // Abstract.
      }

      // *** Item_Stack shims

      // NOTE: See Item_User_Access for access_style_id. We can't define it
      //       here because New_Item_Policy defines a same-named attribute.
      //       And New_Item_Policy derives from Grac_Record which derives from
      //       us, Item_Versioned. Also, access_style_id is more of an
      //       Item_User_Access attribute, even if Item_Stack is higher up the
      //       chain. (Also also, we'll keep stealth_secret with
      //       access_style_id, since it, too, is an accessy-thing (and you
      //       don't need a UUID to GrAC records, do you?).)

      //
      public function get cloned_from_id() :int
      {
         var cloned_from_id:int;
         if (this.item_stack !== null) {
            cloned_from_id = this.item_stack.cloned_from_id;
         }
         return cloned_from_id;
      }

      //
      public function set cloned_from_id(cloned_from_id:int) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get created_date() :String
      {
         var created_date:String = null;
         if (this.item_stack !== null) {
            created_date = this.item_stack.created_date;
         }
         return created_date;
      }

      //
      public function set created_date(created_date:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get created_user() :String
      {
         var created_user:String = null;
         if (this.item_stack !== null) {
            created_user = this.item_stack.created_user;
         }
         return created_user;
      }

      //
      public function set created_user(created_user:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get edited_date() :String
      {
         var edited_date:String;
         if (this.item_stack !== null) {
            edited_date = this.item_stack.edited_date;
         }
         return edited_date;
      }

      //
      public function set edited_date(edited_date:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get edited_user() :String
      {
         var edited_user:String;
         if (this.item_stack !== null) {
            edited_user = this.item_stack.edited_user;
         }
         return edited_user;
      }

      //
      public function set edited_user(edited_user:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get edited_note() :String
      {
         var edited_note:String;
         if (this.item_stack !== null) {
            edited_note = this.item_stack.edited_note;
         }
         return edited_note;
      }

      //
      public function set edited_note(edited_note:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get edited_addr() :String
      {
         var edited_addr:String;
         if (this.item_stack !== null) {
            edited_addr = this.item_stack.edited_addr;
         }
         return edited_addr;
      }

      //
      public function set edited_addr(edited_addr:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get edited_host() :String
      {
         var edited_host:String;
         if (this.item_stack !== null) {
            edited_host = this.item_stack.edited_host;
         }
         return edited_host;
      }

      //
      public function set edited_host(edited_host:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get edited_what() :String
      {
         var edited_what:String;
         if (this.item_stack !== null) {
            edited_what = this.item_stack.edited_what;
         }
         return edited_what;
      }

      //
      public function set edited_what(edited_what:String) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get master_item() :*
      {
         var master_item:* = null;
         if (this.item_stack !== null) {
            master_item = this.item_stack.master_item;
         }
         return master_item;
      }

      //
      public function set master_item(master_item:*) :void
      {
         if (this.item_stack !== null) {
            this.item_stack.master_item = master_item;
         }
         else if (master_item > 0) {
            this.item_stack = new Item_Stack(this, /*gml=*/null);
            this.item_stack.master_item = master_item;
         }
         // else, master_item == 0, so don't care.
      }

      //
      public function get reversion_version() :int
      {
         var reversion_version:int = 0;
         if (this.item_stack !== null) {
            reversion_version = this.item_stack.reversion_version;
         }
         return reversion_version;
      }

      //
      public function set reversion_version(reversion_version:int) :void
      {
         if (this.item_stack !== null) {
            this.item_stack.reversion_version = reversion_version;
         }
         else if (reversion_version > 0) {
            this.item_stack = new Item_Stack(this, /*gml=*/null);
            this.item_stack.reversion_version = reversion_version;
         }
         // else, reversion_version == 0, so don't care.
      }

      //
      // FIXME: Use this instead of sending to ctor?
      override public function set_revision(rev:utils.rev_spec.Base) :void
      {
         super.set_revision(rev);

         // 2013.05.15 [mm] moved this from the constructor to here because
         // this is where this.rev is set (above line). [mm] wonders if this is
         // the correct place for this line or should it be in Item_Revisioned.
         // It was, after all, originally in Item_Versioned's constructor, so
         // retaining it within the same class for now.
         // 
         // Init. the Revisioned item's stack ID, which is the same as the
         // stack_id, possibly with a bitmask applied (if rev is a Diff).
         this.revisioned_id_init(this.stack_id);
      }

      // *** Item Init/Update fcns.

      //
      // The items_add fcn. calls init_item.
      override public function init_item(item_agg:Aggregator_Base,
                                         soft_add:Boolean=false)
         :Item_Versioned
      {
         var updated_item:Item_Versioned = null;
         // Always add item if not in class lookup or if stack id is 0.
         // NOTE: An item that is deleted... will be init_add'ed. Hrm.?
         //       (E.g., undo a command that made a new item, then redo it.)
         if ((!this.is_item_loaded(item_agg))
             || (this.invalid)
             || (soft_add)) {
            m4_VERBOSE('Adding new item:', this);
            this.init_add(item_agg, soft_add);
         }
         else {
            m4_VERBOSE('Updating old item:', this);
            // If the server sends us an item we already know about, we have to
            // check: (a) has our copy (the working copy) changed, (b) has the
            // mainline copy changed, and (c) have both changed. If just (a),
            // ignore the new item; if (b), overwrite the old item; and if (c),
            // add both to branch conflicts.
            updated_item = this.init_update(null, item_agg);
         }
         return updated_item;
      }

      // Derived functions add new items to the aggregator of their choice.
      // EXPLAIN: What's the remove equivalent of init_add?
      //          See: item_cleanup. And: item_discard. And: items_add.
      //
      protected function init_add(item_agg:Aggregator_Base,
                                  soft_add:Boolean=false) :void
      {
         // No-op.
         // NOTE: (this.stack_id == 0) for Geosummary.
      }

      // This fcn. is called when the server sends us information about an item
      // we already know about. Since our local copy is the "working copy", we
      // should respect any changes the user has made to the item and not
      // overwrite them with anything from the mainline.
      // NOTE The object executing this fcn. is the new object we just got from
      //      the server. If this item is newer than the one we have, we
      //      replace the one we have; if it's older, we keep the one we have;
      //      if both are newer, we keep both and create a branch conflict so
      //      the user can resolve the issue. (Also, if both are the same,
      //      we just ignore this item; this might happen while the user is
      //      panning and zooming, [lb] guesses.)
      protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned

      {
         // No-op
         // FIXME: V1 style was to copy server item into working copy. With
         //        grac and the like, would it be easier (and safer, since
         //        items are more complicated now), to just replace the item?
         //        Or are there things pointing into the Dictionary whose
         //        object links we'd break? Like, active_attachment?
         //        If the latter is a problem, maybe cloning is easier. In
         //        either case, we have to update permissions and group
         //        accesses.
         // 2013.03.09: Each item class has an 'all' Dictionary, and there's
         //             also G.item_mgr.deletedset. To support update right,
         //             we probably need to find the existing item and call
         //             its clone(), so that we don't break existing references
         //             to the item. E.g., Link_Value has a reference to the
         //             attc and feat object. So find and update the existing
         //             object in memory rather than creating a new one and
         //             deleting the old.

         m4_ASSERT(false); // Does anything not call clone() and short-circuit?
         return null;
      }

      //
      public function update_item_committed(commit_info:Object) :void
      {
         m4_DEBUG2('update_item_committed: dirty_reason: 0x',
                   this.dirty_reason.toString(16), '/', this);
         GWIS_Commit.dump_climap(commit_info);

         var original_dirty:uint = this.dirty_reason;

         if (commit_info !== null) {
            if (this.stack_id < 0) {
               m4_ASSERT_SOFT(!(this.stack_id in G.item_mgr.deletedset));
               m4_ASSERT_SOFT(!(this.stack_id in G.item_mgr.donedeleted));
               this.stack_id = commit_info.new_id;
            }
            else {
               // This item existed prior to being saved.
               m4_ASSERT_SOFT(this.stack_id == commit_info.new_id);
            }
            m4_ASSERT_SOFT(commit_info.new_ssid > 0);
            // Not true when just changing an item's permissions:
            //   m4_ASSERT_SOFT(commit_info.new_ssid > this.system_id);
            this.system_id = commit_info.new_ssid;
         }
         else {
            // Otherwise, this is a deleted freshie, so it wasn't sent to
            // the server during commit (and now we're just cleaning it up,
            // and discarding its command).
            m4_ASSERT(this.stack_id in G.item_mgr.deletedset);
         }

         if (this.stack_id in G.item_mgr.deletedset) {
            // Not true for deleted freshies: m4_ASSURT(this.stack_id > 0);
            // EXPLAIN: The item is deleted now, right? But it's still
            //          part of the item_class.all lookups?
            // MAYBE: Anything else to do? Oh, well, we discard_and_update
            //        currently... so this can be sloppy.
            // Add to one...
            G.item_mgr.donedeleted[this.stack_id] = this;
            // ... and delete from t'other.
            delete G.item_mgr.deletedset[this.stack_id];
         }

         if (this.dirty_get(Dirty_Reason.item_data)) {
            m4_DEBUG('update_item_committed: Dirty_Reason.item_data');
            this.dirty_set(Dirty_Reason.item_data, false);

            // Bump the version. Elsewhere, we switch the client ID with the
            // permanent ID, and here, we bump the version. This all assumes
            // that we assume our local working copy data is good -- but
            // currently, we reload the whole map; a less disruptive approach
            // would be to just reload items that were saved; the least
            // disruptive approach is to keep the same item in memory and hope
            // our working matches the new version that was saved to the
            // database.

            if (commit_info !== null) {
               this.version += 1;
               if (this.version == commit_info.new_vers) {
                  m4_DEBUG('upd_itm_cmmttd: data: new version:', this.version);
               }
               else {
                  // The assumption is that all Dirty_Reason.item_data reasons
                  // mean the version increases. But maybe the code behaves
                  // differently, either because that assumption is wrong, or
                  // because the code is wrong. Like, are there other items,
                  // like work_items, whose version maybe does not increase?
                  // Fortunately, the server is the ultimate source.
                  // NOTE: We shouldn't have to worry about acl_grouping:
                  //       that's nothing flashclient cares about.
                  m4_WARNING2('upd_itm_cmmttd: data: unexpected version:',
                     commit_info.new_vers, '/ expected:', this.version);
                  this.version = commit_info.new_vers;
               }
            }
         }

         if (this.dirty_get(Dirty_Reason.item_revisionless)) {
            m4_DEBUG('update_item_committed: Dirty_Reason.item_revisionless');
            this.dirty_set(Dirty_Reason.item_revisionless, false);
            if (commit_info !== null) {
               this.version += 1;
               if (this.version == commit_info.new_vers) {
                  m4_DEBUG2('upd_itm_cmmttd: route: new version:',
                            this.version);
               }
               else {
                  m4_WARNING2('upd_itm_cmmttd: route: unexpected version:',
                     commit_info.new_vers, '/ expected:', this.version);
                  this.version = commit_info.new_vers;
               }
            }
         }

         // EXPLAIN: What about item_data_oob?
         //          Looks like Thread takes care of it?

         if (this.dirty_get(Dirty_Reason.item_watcher)) {
            m4_DEBUG('update_item_committed: Dirty_Reason.item_watcher');
            this.dirty_set(Dirty_Reason.item_data, false);
            if (commit_info !== null) {
               this.version += 1;
               if (this.version == commit_info.new_vers) {
                  m4_DEBUG2('upd_itm_cmmttd: item_watcher: new version:',
                            this.version);
               }
               else {
                  m4_WARNING2('upd_itm_cmmttd: item_watcher: unexpctd vers:',
                     commit_info.new_vers, '/ expected:', this.version);
                  this.version = commit_info.new_vers;
               }
            }
         }

         if (this.dirty_get(Dirty_Reason.item_schg)) {
            m4_DEBUG('update_item_committed: Dirty_Reason.item_schg');
            this.dirty_set(Dirty_Reason.item_schg, false);
         }
         if (this.dirty_get(Dirty_Reason.item_schg_oob)) {
            m4_DEBUG('update_item_committed: Dirty_Reason.item_schg_oob');
            this.dirty_set(Dirty_Reason.item_schg_oob, false);
         }
         if (this.dirty_get(Dirty_Reason.item_data_oob)) {
            m4_DEBUG('update_item_committed: Dirty_Reason.item_data_oob');
            this.dirty_set(Dirty_Reason.item_data_oob, false);
            if (commit_info !== null) {
               this.version += 1;
               m4_DEBUG('update_item_committed: new version:', this.version);
            }
         }

         if (this.dirty_reason) {
            // MAGIC_NUMBER: Use 16 to convert to hex.
            m4_WARNING2('update_item_committed: dirty?:',
                        Strutil.as_hex(this.dirty_reason), '/', this);
         }

         // Just to be sure, pyserver commit always returns new access_infer_id
         // and groups_access records.
         if (commit_info !== null) {

            if (commit_info.acif_id) {

               m4_DEBUG('update_item_committed: acif_id', commit_info.acif_id);
               if (this.item_stack !== null) {
                  this.item_stack.access_infer_id = commit_info.acif_id;
               }
               else {
                  // This happens for, e.g., /item/alert_email link_values,
                  // which we checked out without getting the item_stack.
                  // Should we bother adding the item_stack? We don't have
                  // enough information to build it properly, so probably
                  // don't bother adding the item_stack.
                  //
                  // 2014.09.14: This also happens for items the user has
                  // edited but hasn't ever selected, e.g., drag a byway
                  // endpoint to the middle of another byway and use the
                  // create intersection tool and then save: you'll get
                  // commit info for items the client hasn't completely
                  // loaded because they were never selected and their
                  // panels were never opened.
               }
               // SOMETHING SOMETHING SOMETHING... consume GIA records from
               //                     server after commit and stealth create
               for each (var gia:Group_Item_Access in commit_info.new_gias) {
                  m4_DEBUG('update_item_committed: gia', gia);
                  if (gia.item === null) {
                     m4_ASSERT_SOFT(false);
                     gia.item = (this as Item_User_Access);
                  }
                  else {
                     m4_ASSERT(gia.item === this);
                  }
                  var updated_gia:Group_Item_Access;
                  updated_gia = (gia.init_item(G.grac) as Group_Item_Access);
               }

               // Force the item to recalculate its own perception of the same.
               this.latest_infer_id = null;
            }
            m4_ASSERT_ELSE_SOFT; // !commit_info.acif_id

            if (this.version != commit_info.new_vers) {
               m4_DEBUG('update_item_committed: version:', this.version);
               m4_DEBUG('update_item_committed: commit_info.new_vers:',
                        commit_info.new_vers);
               m4_ASSERT_SOFT((this.version + 1) == commit_info.new_vers);
               this.version = commit_info.new_vers;
               // We're deliberate about += 1, above. But when we split byways,
               // we send in the commit and receive associated items, like
               // Link_Value, that we didn't set dirty on.
               m4_ASSERT_SOFT(original_dirty == Dirty_Reason.not_dirty);
            }
         }

      }

      //
      public function update_item_all_lookup(item_class:Class,
                                             commit_info:Object) :void
      {
         if (commit_info !== null) {
            var permanent_id:int = commit_info.new_id;
            m4_ASSERT(permanent_id > 0);
            if (this.stack_id in item_class.all) {
               if (this.stack_id < 0) {
                  delete item_class.all[this.stack_id];
                  item_class.all[permanent_id] = this;
               }
            }
            else {
               // I.e., in G.item_mgr.deletedset or G.item_mgr.donedeleted.
               m4_ASSERT(this.deleted);
            }
            // FIXME: Should we not store in all at all if item is,
            //        e.g., out of the viewport?
         }
         // else, we're cleaning up a deleted freshie.
      }

      // Given an item aggregator, returns whether or not the item is present
      // in the aggregator.
      // FIXME: This fcn., and all of its overrides, just check stack_id.
      //        What about diff revs (i.e., what about the stack ID bit mask)?
      protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         // Subclasses should check their own lookups to see if the item
         // exists, since we don't maintain a lookup of existing items.
         // We do, however, know if the item is new (invalid) or deleted.
         // Otherwise, "this" doesn't exist if the server just told us 'bout it
         return (this.invalid || G.item_mgr.is_item_deleted(this.stack_id));
      }

      // *** Developer methods

      //
      override public function toString() :String
      {
         var item_name:String = Strutil.snippet(this.name_);
         var flags:String =
                   (this.deleted ? '+DEL' : '')
                 + (this.invalid ? '-VLD' : '')
                 + (this.dirty   ? '+DTY' : '')
                 + (this.fresh   ? '+FRH' : '');
         var rev_detail:String =
            ((this.rev !== null)
               ? ('@' + this.rev.short_name)
               : ('@?'));
         return ('"' + item_name + '" ['
                 + super.toString()
                 + ':' + this.stack_id + '.' + this.version
                 + flags
                 + '/' + this.system_id + '-b' + this.branch_id
                 + '/' + rev_detail
                 + ']');
      }

      //
      override public function toString_Terse() :String
      {
         return (this.friendly_name // friendly class name, that is.
                 + ':' + this.stack_id + '.' + this.version
                 + (this.deleted ? 'x' : '')
                 + (this.invalid ? '!' : '')
                 + (this.dirty   ? '$' : '')
                 + (this.fresh   ? ')' : '')
                 + ' "' + Strutil.snippet(this.name_) + '"');
      }

      // *** Flex Trickery

      // MAYBE: Can we move this to Item_Manager or something?
      //        It seems silly that the base class is calling out
      //        its descendants.

      // For the factory fcn., item_get_class, to work, we load the factory
      // classes explicitly. We can't just: import items.attcs.*, etc. Why?
      // getDefinitionByName fails on names of objects that have never been
      // created in the system, so for it to work, we have to trick it into
      // believing.

      //
      public static function init_GetDefinitionByName() :void
      {
         if (!Item_Versioned.inited_GetDefinitionByName) {
            m4_DEBUG('init_GetDefinitionByName: making new objects!');
            // Avoid a feedback loop: set the flag true before triggering loads
            Item_Versioned.inited_GetDefinitionByName = true;
            // NOTE To test this fcn., avoid the loop and just make the items,
            //      e.g., var object_01:Annotation = new Annotation();
            //            var object_02:Attribute = ...
            // SYNC_ME: This lookup matches the classes found in the packages,
            //          items.attcs, items.feats, items.gracs, and items.jobsq.
            for each (var item_class:Class in [
                  //
                  // From items.attcs:
                  //
                  Annotation
                  , Attribute
                  , Post
                  , Tag
                  , Thread
                  //
                  // From items.feats:
                  //
                  , Branch
                  , Byway
                  //, Direction_Step // Ctor takes args, so cannot load. Need?
                  , Geosummary // just a support class in feats?
                  , Region
                  , Route
                  , Route_Step
                  , Terrain
                  , Track
                  , Track_Point
                  , Waypoint
                  //
                  // From items.gracs:
                  //
                  , Group
                  , Group_Item_Access
                  , Group_Membership
                  , Group_Revision
                  , New_Item_Policy
                  //
                  // From items.links:
                  //
                  , Branch_Conflict
                  // , Link_Attribute  // In pyserver, but not in flashclient
                  , Link_Post
                  , Link_Geofeature // otherwise GWIS_Checkout_Base.resultset_process ... 
                  // , Link_Tag        // In pyserver, but not in flashclient
                  // , Tag_Counts      // In pyserver, but not in flashclient
                  //
                  // From elsewhere: these don't all derive from Item_Versioned
                  // but they still use item_get_class....
                  //
                  // From items.jobsq:
                  //
                  , Conflation_Job
                  , Merge_Export_Job
                  , Merge_Import_Job
                  //, Merge_Job
                  , Route_Analysis_Job
                  , Work_Item
                  // , Work_Item_Step
                  ]) {
               m4_DEBUG(' ... ', item_class);
               var item:Record_Base = new item_class();
            }
            /* If you had non-item classes, import the package above and add
               the classes here.

            for each (var obj_class:Class in [
                  __Your_Nonitem_Class__,
                  ]) {
               m4_DEBUG(' ... ', obj_class);
               var obj:Object = new obj_class();
            }
            */
         }
      }

   }

   // Init the def'n lookup!
   Item_Versioned.init_GetDefinitionByName();

}


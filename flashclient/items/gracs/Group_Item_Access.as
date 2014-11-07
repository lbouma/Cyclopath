/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.gracs {

   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   import grax.Access_Level;
   import grax.Aggregator_Base;
   import grax.Dirty_Reason;
   // [lb] thinks its backwards to include the Item_Manager, since it should be
   //      managing us, but it doesn't include us.
   import grax.Item_Manager;
   import items.Grac_Record;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Grpa_Change_Event;
   import items.utils.Item_Type;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   // This class, Group_Item_Access, and User_Item_Access are very much
   // related. User_Item_Access is the user's composite access to an item.
   // It maintains a collection of objects of this class. This class merely
   // stores the group ID and access level ID of one of the group_item_access
   // records.

   public class Group_Item_Access extends Grac_Record {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Grp_Itm_Acss');

      // *** Mandatory attributes

      public static const class_item_type:String = 'group_item_access';
      public static const class_gwis_abbrev:String = 'gia';
      public static const class_item_type_id:int = Item_Type.GROUP_ITEM_ACCESS;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:* = null;

      // *** Member variables

      // The crux-meat of this class is the group_id and its access_level.
      //[Bindable] public var stack_id:int;
      //[Bindable] public var version:int;
      //[Bindable] public var item_id:int;
      [Bindable] public var group_id:int;
      //[Bindable] public var branch_id:int;

      [Bindable] public var access_level_id:int = Access_Level.invalid;

      // This class will lookup the actual objects as appropriate.
      public var item:Item_User_Access;
      /*[Bindable]*/
      public var group:Group;

      // *** Constructor

      //public function Group_Item_Access(item:Item_User_Access, group_id:int,
      //                                  access_level_id:int)
      public function Group_Item_Access(xml:XML=null,
                                        rev:utils.rev_spec.Base=null)
      {
         //var xml:XML = null; // Ignored
         //// FIXME: What about rev?
         //super(xml);
         super(xml, rev);

         /*/
         this.item = item;
         this.group_id = group_id;
         this.access_level_id = access_level_id;
         // FIXME: It's safe to assume the groups array exists, right?
         //        No: we can get nip before group_mmbrship. Currently,
         //        this is just for processing the nip to see what tools
         //        the user can use, so if this.group is null, no biggie.
         //m4_ASSERT(G.grac.groups.length > 0);
         m4_DEBUG2('Group_Item_Access: group_id:', group_id,
                   '/ acl:', access_level_id);
         this.group = G.grac.group_find_or_add(group_id);
         m4_DEBUG('Group_Item_Access: found group:', this.group);
         /*/
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Group_Item_Access = (to_other as Group_Item_Access);
         super.clone_once(other);
         other.group_id = this.group_id;
         other.access_level_id = this.access_level_id;
         m4_ASSERT((!other.system_id)
                   && (!other.branch_id)
                   && (!other.stack_id)
                   //&& (!other.item_id)
                   && (!other.version));
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Group_Item_Access = (to_other as Group_Item_Access);
         super.clone_update(other, newbie);
         //m4_ASSERT(other.item_id == this.item_id);
         m4_ASSERT(other.system_id == this.system_id);
         m4_ASSERT(other.branch_id == this.branch_id);
         m4_ASSERT(other.stack_id == this.stack_id);
         m4_ASSERT(other.version == this.version);
      }

      // Use contents of XML element to init myself.
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {

            // base class has these?
            this.stack_id = int(gml.@stid);
            this.version = int(gml.@v);
            this.branch_id = int(gml.@brid);

            //this.item_id = int(gml.@item_id);
            this.group_id = int(gml.@gpid);
            this.access_level_id = int(gml.@alid);

            m4_DEBUG7('gml_consume: Group_Item_Access:',
                      '/ stack_id:', this.stack_id,
                      '/ group_id:', this.group_id,
                      '/ branch_id:', this.branch_id,
                      '/ acl:', this.access_level_id,
                      '/ cli_id:', gml.@cli_id,
                      '/ new_id:', gml.@new_id);
                      //'/ item_id:', this.item_id,

            // FIXME: How do you find the item? The request contained a stack
            //        ID...
            //        using Geofeature for now, which means this.item is null
            //        for Attachments (not that I think we get grpa for
            //        attachments currently...).
            // MAYBE: Every <gia /> record in the <access_control> document
            //        specifies the same stack_id and version, i.e., that of
            //        the item we lazy-loaded, or that of the committed item
            //        under the <id_map> document... so we could specify the
            //        stack ID and version of the item as an <access_control>
            //        tag, rather than having every GIA record contain it
            //        (both in the GML, and in the object, here).

            // See: GWIS_Grac_Get, called by, e.g., GWIS_Commit, which calls
            //      new grac_class (dynamically creating this object) and
            //      then our Record_Base ctor calls gml_consume, and we end
            //      up here.

            // Find item in Geofeature.all, Attachment.all, or Link_Value.all.
            this.item = (G.item_mgr.item_here_there_anywhere(this.stack_id)
                         as Item_User_Access);
            if (this.item === null) {
               if (this.stack_id != gml.@cli_id) {
                  m4_DEBUG('gml_consume: item might be fresh; trying cli ID');
                  // NOTE: This finds deleted items, too. We'll go through the
                  //       normal update motions, but the item (and its gia
                  //       records, etc) will soon be removed from the lookups.
                  this.item = (
                     G.item_mgr.item_here_there_anywhere(gml.@cli_id)
                     as Item_User_Access);
                  // 2014.09.14: If you drag a vertex to a byway and create
                  // an intersection and save, you won't have loaded the
                  // byway that was split, but their information in included
                  // in the commit response. The caller, GWIS_Commit, will
                  // build a list of these reponses -- including making new
                  // Group_Item_Access objects -- but they won't be consumed
                  // (or [lb] thinks not) so it should be fine if the client ID
                  // was not found because flashclient did not send it and
                  // pyserver created it for the split byways.
                  //  Not alwyas the case: m4_ASSERT_SOFT(this.item !== null);
               }
               else {

                  m4_ERROR2('gml_consume: item not found: client/stack id:',
                            this.stack_id);
                  m4_ASSERT_SOFT(false);
               }
            }
            m4_DEBUG('gml_consume: found item:', this.item);

            // EXPLAIN: What's this.group for the Stealth-Secret and Session ID
            //          Groups?
            this.group = G.grac.group_find_or_add(this.group_id);
            m4_DEBUG('gml_consume: found group:', this.group);
         }
      }

      // Return an XML element representing myself.
      override public function gml_produce() :XML
      {
         // FIXME: I think Item_User_Access sends the grpa records.... see
         //        GWIS_Commit.as.
         m4_ASSERT(false);
         var gml:XML = <group_item_access />;
         return gml;
      }

      // ***

      // Called when we receive new records from the server.
      override public function init_item(item_agg:Aggregator_Base,
                                         soft_add:Boolean=false)
         :Item_Versioned
      {
         // Not calling: super.init_item.

         if (this.item !== null) {
            // FIXME: Where can we reset groups_access? When we send the grac
            //        req, or when we get the resp?
            this.item.groups_access[this.group_id] = this;
            this.item.latest_infer_id = null;
            m4_DEBUG('init: item.groups_access: grpa:', this);
         }
         else {
            m4_WARNING('init: no item for grpa:', this);
         }

         // FIXME: We're not lazy loading grpa for the active branch....
         // FIXME: What about for new items? Do they generate events? Or
         //        editing existing grpa records for an item?
         m4_DEBUG('init: gwis_complete_cllbck:', Grpa_Change_Event.EVENT_TYPE);
         G.item_mgr.dispatchEvent(new Grpa_Change_Event(this.stack_id));

         // The item classes return a ref to the item if it was updated,
         // but we treat gia records as new and don't update existing ones,
         // we replace them.
         var updated_item:Item_Versioned = null;
         return updated_item;
      }

      //
      public function update_item_committed_gia() :void
      {
         var undirtied:Boolean = false;
         // EXPLAIN: The item uses Dirty_Reason.item_grac but the GIA records
         //          use edit_auto and edit_user?
         if (this.dirty_get(Dirty_Reason.edit_auto)) {
            this.dirty_set(Dirty_Reason.edit_auto, false);
            undirtied = true;
         }
         if (this.dirty_get(Dirty_Reason.edit_user)) {
            this.dirty_set(Dirty_Reason.edit_user, false);
            undirtied = true;
         }
         if (!undirtied) {
            m4_WARNING2('update_item_committed: grps not dirty:',
                        this.toString());
         }
         m4_ASSERT(!this.dirty);
      }

      // Skipping:
      //    override public function set deleted
      //    override protected function init_add
      //    override protected function init_update

      // *** Getters and setters

      override public function get friendly_name() :String
      {
         // FIXME: Always show the Group ID to the user if the group isn't
         //        named?? Why is a group not named? Only if it's zero, as
         //        in the object isn't set?
         return (this.group.name_)
                  ? this.group.name_
                    : ('[Unnamed Group (ID: ' + this.group.stack_id + ')]');
      }

      // *** Instance methods

      //
      override public function dirtyset_add(reason:uint) :void
      {
         m4_DEBUG('dirtyset_add: reason:', reason, '/ this:', this);

         // Don't call super, which adds us to the map's dirtyset.
         // We only want to be a part of the item's dirtyset_gia.
         //  No: super.dirtyset_add(reason);

         // Is this too coupled? Hey, Item, we're just gonna mess with you....
         //  Add to the accesses list.
         this.item.dirtyset_gia.add(this);

         // Mark the item as dirty, too.
         var items_reason:uint = 0;
         if (reason == Dirty_Reason.edit_auto) {
            items_reason = Dirty_Reason.item_grac_oob;
         }
         else if (reason == Dirty_Reason.edit_user) {
            items_reason = Dirty_Reason.item_grac;
         }
         else {
            m4_ERROR('dirtyset_add: unexpected reason:', reason);
            m4_DEBUG('stack:', Introspect.stack_trace());
            m4_ASSERT(false);
         }
         this.item.dirtyset_add(items_reason);
      }

      //
      override public function dirtyset_del(reason:uint) :void
      {
         m4_VERBOSE('dirtyset_del: reason:', reason, '/ this:', this);
         m4_ASSERT(Boolean(reason & (Dirty_Reason.edit_auto
                                     | Dirty_Reason.edit_user)));
         this.item.dirtyset_gia.remove(this);
         // If we just emptied the dirty grac list, unset the dirty grac reason
         if (this.item.dirtyset_gia.length == 0) {
            m4_VERBOSE(' .. also this.item.dirtyset_del: reason:', reason);
            var items_reasons:uint = (Dirty_Reason.item_grac_oob
                                      | Dirty_Reason.item_grac);
            this.item.dirtyset_del(items_reasons);
         }
         super.dirtyset_del(reason);
      }

      // *** Developer methods

      override public function toString() :String
      {
         var rev_detail:String =
            ((this.rev !== null)
               ? ('@' + this.rev.short_name)
               : ('@?'));
         var the_string:String =
              //super.toString()
              getQualifiedClassName(this)
              + ' | rev: ' + rev_detail
              + ' / grp_id: ' + this.group_id
              + ' / acl_id: ' + this.access_level_id
              //
              + ' / grp.nom: '
              + ((this.group !== null) ? this.group.name_ : 'null')
              + ' / grp.sid: '
              + ((this.group !== null) ? this.group.stack_id : 'null')
              + ' / grp.scp: '
              + ((this.group !== null) ? this.group.access_scope.substr(0,3)
                                         : 'null')
              //+ ' | dsc: ' + this.group.description
              //
              + ' / itm: '
              + ((this.item !== null) ? this.item.name_ : 'null')
              + ' | sid: '
              + ((this.item !== null) ? this.item.stack_id : 'null')
              ;
          return the_string;
      }

   }
}


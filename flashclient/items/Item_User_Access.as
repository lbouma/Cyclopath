/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import flash.utils.Dictionary;

   import grax.Access_Infer;
   import grax.Access_Level;
   import grax.Access_Style;
   import grax.Aggregator_Base;
   import grax.Dirty_Reason;
   import grax.Library_Squelch;
   import gwis.GWIS_Grac_Get;
   import gwis.utils.Query_Filters;
   import items.attcs.Attribute;
   import items.attcs.Tag;
   import items.gracs.Group_Item_Access;
   import items.gracs.New_Item_Policy;
   import utils.misc.Collection;
   import utils.misc.Counter;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.misc.Strutil;
   import utils.rev_spec.*;

   public class Item_User_Access extends Item_Versioned {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Itm_Usr_Acc');

      public static const class_item_type:String = 'item_user_access';

      // *** Instance variables

      // As access levels are not assigned directly to users but instead to
      // groups, the user is granted the best access level associated with any
      // of the groups to which the user belongs.

      public var access_level_id:int;
      // HINT: See Item_Stack for access_infer_id.

      // 2012.10.05: Permissions State Change Request.
      // MAYBE: Liteweight item classes: Move this to an Item_Manager lookup.
      public var style_change_:int;

      // ITEM_BLOAT: Consider adding two ints to the item class hierarychy,
      //             assuming 10,000 geofeatures are in the viewport:
      //             Two ints is 2 words, times 10,000 items is 156.25 Kb.
      //             (10,000 * 1024 / 1024 / (32 * 2))
      // MAYBE: Move groups_access to, maybe, Item_Stack, so we only use space
      //        for those few items for which we'll hydrate groups_access.
      // MAYBE: Audit the item class hierarchy and see if other attributes can
      //        be consolidated outside the item classes, too.
      //
      // If the user owns an item, the user needs to know the access that each
      // group has to the item. Also, if the user creates an item, this gets
      // created according to the new item policy; and unless the user owns the
      // newly-created item, the user cannot edit this list.
      //
      //   E.g., this.groups_access[group_id] = Access_Level.viewer
      //
      //protected var groups_access:Dictionary = new Dictionary();
      //
      //   E.g., this.groups_access[group_id] = Group_Item_Access;
      //

      // MAYBE: Item bloat: This could be a part of Item_Stack, since
      //        we only lazy-load groups_access when user selects an
      //        item.
      public var groups_access:Dictionary;
      public var dirtyset_gia:Set_UUID;

      // 2013.06.08: [lb] moved attrs, tags fr. Geofeature to Item_User_Access.
      //             Since you should be able to tag and attr anything, really.
      //             And we have way more Geofeatures in memory than other
      //             items, so this shouldn't have a huge memory impact.
      public var attrs:Dictionary;
      public var tags:Set_UUID;
      // NOTE: this.attrs and this.tags are lightweight link_values.
      //       To save tags and attrs, you need to use Link_Value's
      //       stack_id_lookup or item_type_lookup.
      // HRMMM: Do we really need the heavyweight link_value details?
      //        Could we save attrs and tags by keys and values only, and
      //        the server would be responsible for fiddling with the actual
      //        link_value -- though maybe we need the link_value because we
      //        need to send the version to check for conflicts? Or does
      //        sending our revision accomplish that, so we don't need to send
      //        version numbers, or even system IDs? Pyserver just needs to
      //        compare the client's last_update_rid to every saved item's
      //        valid_start_rid...
      //
      public var links_reqs_outstanding:int = 0;
      protected var links_lazy_loaded_:Boolean = false;

      // *** Constructor

      public function Item_User_Access(
         xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         // Mark the Access_Level invalid; it'll get set if/when super loads
         // the xml.
         this.access_level_id = Access_Level.invalid;
         this.groups_access = new Dictionary();
         this.dirtyset_gia = new Set_UUID();

         if (xml === null) {
            // This is a local item.
            this.attrs = new Dictionary();
            this.tags = new Set_UUID();
         }

         super(xml, rev);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Item_User_Access = (to_other as Item_User_Access);
         super.clone_once(other);

         other.attrs = null;
         other.tags = null;
      }

      //
      override protected function clone_update( // on-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Item_User_Access = (to_other as Item_User_Access);
         super.clone_update(other, newbie);

         // Sometimes update access_level_id: we're called from init_update,
         // and if the user just logged on and they were previously anonymous,
         // and if the user is a basemap owner, they might get, e.g., the
         // public branch record again with better access.
         //  m4_ASSERT((!other.access_level_id)
         //            || (!this.access_level_id)
         //            || (other.access_level_id == this.access_level_id));
         if (!newbie) {
            other.access_level_id = this.access_level_id;
            // other.style_change = this.style_change;
         }
         // else, leave it empty so grac_mgr will figure it out.
         //    other.access_level_id = Access_Level.invalid;
         //    other.style_change = Access_Infer.not_determined;
         //
         // FIXME/MAYBE: Should we reset groups_access, or others?
         //this.groups_access = new Dictionary();
         //this.dirtyset_gia...

         if (other.attrs === null) {
            // See comments in Route.as; not using ObjectUtil.copy().
            //other.attrs = ObjectUtil.copy(this.attrs) as Dictionary;
            m4_DEBUG2('clone_update: update .attrs: other.attrs:', other.attrs,
                      '/ this.attrs:', this.attrs);
            // We don't need, like, Collection.dict_copy, do we?
            other.attrs = this.attrs;
         }
         if (other.tags === null) {
            other.tags = this.tags.clone();
         }
         // NOTE: Not signalling event.
         //       G.item_mgr.dispatchEvent(new Event('attcCountsLoaded'));
      }

      //
      // Use contents of XML element to init myself.
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.access_level_id = int(gml.@alid);
            // Only deep-link uses the real item type id, so avoid item bloat.
            // Skipping: this.real_item_type_id = int(gml.@rtyp);
            // ABOUT: groups_access: These are lazy-loaded with GWIS_Grac_Get.

            // See Query_Filters.dont_load_feat_attcs: this is almost always
            // set, except for Routes and when lazy-loading Item_Stack (the
            // Link_Values for items are also lazy-loaded, but attrs and tags
            // don't apply to links).
            //
            // MAYBE: [lb] put attrs and tags in a base class for Attachment
            // and Geofeature, but they are also shared by Link_Value. Does
            // this cause any memory bloat?

            // The server always tries to send attrs, so we always reset it.
            this.attrs = new Dictionary();
            if ('a' in gml.attrs) {
               for each (var attr:XML in gml.attrs.a) {
                  m4_VERBOSE(' .. attr.@k:', attr.@k, '/ attr.@v:', attr.@v);
                  // 2013.05.02. [lb] likes to point out things, including:
                  // this is the only place in the code where there's
                  // ".attrs[", meaning, the lightweight lookup isn't being
                  // used by flashclient. At least not yet... funny, I guess
                  // the only basemap ornament is the one-way arrow, and
                  // one_way is part of byway. But in the Metc branch, we
                  // highlight byways with the /metc_bikeways/bike_facil
                  // attribute. So really this is the first real reason
                  // flashclient needs the lightweight lookup, otherwise
                  // it could just get by with not caring about attributes
                  // until the user selects an item on the map.
                  // See attribute_get_value, where this is used.
                  //
                  // NOTE: Stringify-the XML, otherise querying on the key as a
                  //       string later will return null.
                  //        Bad: this.attrs[attr.@k] = attr.@v;
                  this.attrs[String(attr.@k)] = attr.@v;
               }
               if (!(Collection.dict_is_empty(this.attrs))) {
                  // NOTE: Not calling attributesLoaded, because these are
                  // light. That event means we also have link_value stack IDs.
                  m4_VERBOSE('gml_consume: loaded attrs:', this.attrs);
               }
            }

            // The server always tries to send tags, so we always reset it.
            this.tags = new Set_UUID();
            if ('t' in gml.tags) {
               for each (var tag:XML in gml.tags.t) {
                  // 2013.05.23: Oy, see 'splanation above, need to
                  //             String()ify, otherwise, e.g.,
                  //             this.tags['blah'] doesn't work.
                  // EXPLAINED: tag.text.ctor: [class XMLList]
                  //             m4_DEBUG2('tag.text.ctor:',
                  //                Introspect.get_constructor(tag.text));
                  //            Oh, oops, but, what? this is also an XMLList:
                  //             m4_DEBUG2('tag.text.ctor:',
                  //                Introspect.get_constructor(tag.text()));
                  //
                  // FIXME: Are we missing other cases where this is
                  // happening??  Maybe, like, the draw config GWIS, or any
                  // other collections sent from pyserver? Mostly, we don't use
                  // GML as keys to collections, but maybe we do?
                  //
                  // NO: this.tags.add(tag.text());
                  this.tags.add(String(tag.text()));
               }
               if (this.tags.length > 0) {
                  // NOTE: Not call'g tagsLoaded. See notes w/ attributesLoaded
                  m4_VERBOSE('gml_consume: loaded tags:', this.tags);
               }
            }
         }
         else {
            // Mark the access level invalid, rather than denied, to indicate
            // that this item hasn't had its permissions set.
            this.access_level_id = Access_Level.invalid;
            // Skipping: groups_access (see GWIS_Grac_Get).
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         // Skipping: this.access_level_id

         // See also gml_get_style_change() for style_change XML.
         if ((this.style_change)
             && (!this.dirty_get(Dirty_Reason.item_schg))
             && (!this.dirty_get(Dirty_Reason.item_schg_oob))) {
            m4_ASSERT2(
               Boolean(this.style_change & Access_Infer.acl_choice_mask)
               || Boolean(this.style_change & Access_Infer.restricted_mask));
            // 2013.06.02: Haha, another reason [lb] loves asserts, this fired
            // after saving new alert_email link_value, which tells me that
            // update_item_committed isn't resetting this.style_change when
            // it resets Dirty_Reason.item_schg and item_schg_oob.
            m4_ASSERT(false); // This really shouldn't happen...
                              // mark the item dirty instead.
            gml.@schg = this.style_change
         }

         // See gml_get_grac() for groups_access XML.

         return gml;
      }

      // Return an XML element representing group access permissions.
      public function gml_get_grac() :XML
      {
         var item_doc:XML = <item stid={this.stack_id} />;
         for each (var grpa:Group_Item_Access in this.dirtyset_gia) {
            var gia_doc:XML =
               <gia
                  gpid={grpa.group_id}
                  alid={grpa.access_level_id}
                  />;
            item_doc.appendChild(gia_doc);
         }
         return item_doc;
      }

      //
      public function gml_get_style_change() :XML
      {
         // We generally send this.syle_change to change the access
         // permissions, but for more fine-tuned changes, we can send actual
         // GIA records (see: gml_get_grac).
         // This is called because Dirty_Reason.item_schg/oob is set, so we
         // expect the value to actually be set.
         var item_doc:XML = null;
         if (!(Boolean(this.style_change & Access_Infer.acl_choice_mask)
               || Boolean(this.style_change & Access_Infer.restricted_mask))) {
            m4_WARNING('gml_get_style_change: unexpected style_change:', this);
         }
         else {
            item_doc =
               <item
                  stid={this.stack_id}
                  schg={this.style_change}
                  />;
         }
         return item_doc;
      }

      // ***

      //
      override public function dirtyset_add(reason:uint) :void
      {
         //m4_DEBUG('dirtyset_add: reason:', reason, '/ this:', this);
         super.dirtyset_add(reason);
      }

      //
      override public function dirtyset_del(reason:uint) :void
      {
         m4_VERBOSE('dirtyset_del: reason:', reason, '/ this:', this);
         m4_VERBOSE(' .. this.dirtyset_gia.length:', this.dirtyset_gia.length);
         m4_VERBOSE2('reason & Dirty_Reason.item_grac:',
                     reason & Dirty_Reason.item_grac);
         if (reason & (Dirty_Reason.item_grac | Dirty_Reason.item_grac_oob)) {
            var grpa:Group_Item_Access;
            for each (grpa in this.dirtyset_gia) {
               m4_DEBUG(' .. grpa:', grpa);
               grpa.dirty_set(
                  (Dirty_Reason.edit_auto
                   | Dirty_Reason.edit_user),
                  false);
            }
         }
         super.dirtyset_del(reason);
      }

      override public function init_item(item_agg:Aggregator_Base,
                                         soft_add:Boolean=false)
         :Item_Versioned
      {
         var updated_item:Item_Versioned = super.init_item(item_agg, soft_add);
         if (soft_add) {
            // Old versions use the same link_values as the current version...
            // also, we're not adding the item to the map... so we shouldn't
            // add its old links...
            // MAYBE: An item's version history does not allow reverting
            //        link_values... so, what? do you have to open the note
            //        and revert/delete that? We could allow reverting an item
            //        to include its link_values... but it's probably a better
            //        model to leave that to the revision revert command.
            this.links_lazy_loaded_ = true;
         }
         return updated_item;
      }

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         //m4_DEBUG('item_cleanup:', this, '/ i:', i);
         // Call the base class, which doesn't do anything.
         super.item_cleanup(i, skip_delete);

         // Don't unset dirty: When a user deletes an item, we remove it from
         // the map but keep it internal so we can save its deletion. Note that
         // this check is pretty silly: it was originally writ to alert the dev
         // if s/he was accidentally trying to remove an edited item, but if
         // the user is discarding the whole map and reloading it, of course
         // there will be edited items we're removing. In that case, the var,
         // skip_delete, will be set (which means to skip deleting the item
         // from the Item_Class.all lookup, since we're about to reset the
         // whole Dictionary, i.e., it means we're cleaning up all items).
         m4_ASSERT_SOFT((!this.dirty_get())
                        || (this.fresh)
                        || (this.stack_id == 0)
                        || (this.stack_id in G.item_mgr.deletedset)
                        // Skipping: G.item_mgr.donedeleted
                        || (skip_delete)
                        || (G.map.user_loggingin)
                        // via G.app.discard_alert_handler:
                        || (G.map.branch_changed)
                        );
      }

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         var grpa:Group_Item_Access;

         var dirty_grac:int = Dirty_Reason.item_grac
                            | Dirty_Reason.item_grac_oob;

         // GIA records (complicated).
         if (this.dirty_get(dirty_grac)) {
            for each (grpa in this.dirtyset_gia) {
               grpa.update_item_committed_gia();
            }
            this.dirty_set(dirty_grac, false);
         }
         if (commit_info !== null) {
            if (commit_info.acl_id > 0) {
               this.access_level_id = commit_info.acl_id;
               var acl_id:int = Access_Level.denied;
               for each (grpa in this.groups_access) {
                  m4_TALKY('update_item_committed: grpa:', grpa);
                  acl_id = Math.min(acl_id, grpa.access_level_id);
               }
               m4_TALKY('update_item_committed: acl_id:', acl_id);
               m4_TALKY2('update_item_committed: access_level_id:',
                         this.access_level_id);
               m4_ASSERT_SOFT(Access_Level.is_valid(acl_id));
               m4_ASSERT_SOFT((Collection.dict_length(this.groups_access) == 0)
                              || (acl_id == this.access_level_id));
            }
            else {
               // !commit_info.acl_id
               // 2014.09.09: [lb] is guessing not all commits return the
               //             access_level_id... but what kind of commits
               //             would those be? (I.e., EXPLAIN.)
               m4_ASSERT_SOFT(false);
               G.sl.event('error/iua/update_item_committed/no_acl',
                          {item: this.toString()});
            }
         }
         else if (!this.deleted) {
            m4_ASSERT_SOFT(false);
            G.sl.event('error/iua/update_item_committed/no_cinfo',
                       {item: this.toString()});
         }

         m4_DEBUG('update_item_committed: commit_info:', commit_info);

         // FIXME: When saving a new link-value, e.g. attaching existing note
         // to new feature, this assertion fails after the commit (which
         // succeeds). The issue is that this.dirty_get(Dirty_Reason.item_grac)
         // returns false and so the loop inside the above it doesn't
         // run. this.dirtyset_gia is left populated and hence...  Either
         // this.dirty_get(Dirty_Reason.item_grac) should have returned
         // true, or this.dirtyset_gia shouldn't have been populated in the
         // first place. Or, the assert represents a wrong assumption. ([mm]
         // 2013.04.10)
         //
         // FIXME: On further investigation, this is what is happening:
         // 
         // 1. When a new link_value is created,
         //    Item_User_Access::init_permissions() is called, which in turn
         //    calls Item_User_Access::group_access_add_or_update().
         // 2. Item_User_Access::group_access_add_or_update() doesn't find the
         //    specified group_id in this.group_accesses and hence, creates a
         //    new one called grpa.
         // 3. It calls grpa.dirtyset_add(Dirty_Reason.item_grac).
         // 4. Group_Item_Access::dirtyset_add() adds itself to the parent
         //    item's (i.e. the link_value's) dirtyset_gia but doesn't
         //    add itself to the collection of objects to be sent to the
         //    server. This seems inconsistent. Either both should happen or
         //    neither. So, what's the right behaviour?
         //
         // ([mm] 2013.04.10)
         //
         m4_ASSERT(this.dirtyset_gia.length == 0);

         // Access_Style change (simple).
         if ((this.dirty_get(Dirty_Reason.item_schg))
             || (this.dirty_get(Dirty_Reason.item_schg_oob))) {

            // We saved the GIA changes, so no need to be dirty...
            // (note that we never set Dirty_Reason.item_grac so the GIA
            // records were not set on commit, since we used style_change).
            this.dirtyset_gia = new Set_UUID();

            // Now that we know that the commit was successful, update our GrAC
            // and GIA records to reflect the new reality.

            m4_DEBUG('  >> groups_access:', this.groups_access);

            // All done; no longer dirty.
            // NOTE: Skipping set style_change, which changes state from init
            //       to final but understand how to go back. So just avoid it.
            this.style_change_ = Access_Infer.not_determined;
            this.dirty_set(Dirty_Reason.item_schg, false);
            this.dirty_set(Dirty_Reason.item_schg_oob, false);
         }
         else {
            m4_ASSERT(this.dirtyset_gia.length == 0);
         }

         super.update_item_committed(commit_info);
      }

      // ***

      // FIXME [aa] I'm not that stoked about this impl.
      /*/
      protected function attribute_get_link_value(attr_name:String) :Link_Value
      {
         var lv:Link_Value;
         var the_link_value:Link_Value = null;
         for (lv in Link_Value.item_get_link_values(this, Attribute)) {
            if (lv.attc.value_type == attr_name) {
               the_link_value = lv;
               break;
            }
         }
         return the_link_value;
      }
      /*/

      //
      protected function attribute_get_value(attr_name:String,
                                             default_:*=undefined) :*
      {
         var the_value:* = default_;

         // Look first in the lightweight collection before digging into the
         // link_values.

         // Old comment: New Byways (created in working copy by user with map
         //              tool) do not have this.attrs.
         // TESTME: Create a new byway and change its attributes. Any problems?
         if (attr_name in this.attrs) {
            the_value = this.attrs[attr_name];
            m4_VERBOSE2('attribute_get_value: attr_name:', attr_name,
                        '/ the_value:', the_value, '/ feat:', this);
         }
         else if (attr_name in Attribute.all_named) {
            var attr:Attribute;
            var link:Link_Value;
            m4_VERBOSE('attribute_get_value: all_named:', attr, '/', this);
            attr = Attribute.all_named[attr_name];
            link = Link_Value.items_get_link_value(attr, this);
            if (link !== null) {
               m4_VERBOSE('attribute_get_value:', attr, '/ this:', this);
               the_value = attr.value_get(link);
            }
         }
         else {
            m4_VERBOSE('attribute_get_value: not fnd:', attr_name, '/', this);
         }
         return the_value;
      }

      /*/
      //
      protected function attribute_set_value_integer(attr_name:String,
                                                     value_integer:int) :Object
      {
         m4_ASSERT(false);
         var lv:Link_Value;
         var value_integer = int.MIN_VALUE;
         lv = attribute_get_link_value(attr_name);
         // FIXME create new if one doesn't exist? Should go through a command
         //       instead... is this fcn. still useful? I can't see it...
         if (lv !== null) {
            lv.value_integer = value_integer;
         }
      }
      /*/

      //
      protected function get_new_gia_for_group(group_id:int) :Group_Item_Access
      {
         var grpa:Group_Item_Access;
         if (group_id in this.groups_access) {
            grpa = this.groups_access[group_id];
            m4_DEBUG2('get_new_gia_for_group: found for group id:', group_id,
                      '/ grpa:', grpa);
            // NOTE: We're intentionally not touching access_level_id.
         }
         else {
            grpa = new Group_Item_Access();
            grpa.item = this;
            grpa.access_level_id = Access_Level.denied;
            grpa.group_id = group_id;
            grpa.group = G.grac.group_find_or_add(group_id);
            m4_ASSERT_SOFT(grpa.group !== null);
            m4_DEBUG2('get_new_gia_for_group: new for group id:', group_id,
                      '/ grpa:', grpa);
         }
         return grpa;
      }

      //
      // 2013.03.40: [lb] finally fixed deep-links in CcpV2.
      //
      // E.g., these all get the same route.
      // Note that 'type' is optional, but highly recommended; if it's not
      // used, the returned item's object is Item_User_Access, which might
      // cause problems... unless the code is smart enough and has enough
      // information from the XML to deduce the item type and create an
      // object of the actual derived type.
      //
      // http://ccpv3/#get?link=e3a9a9f7-0d8e-8e47-332d-1a42232350b8
      // http://ccpv3/#get?link=1584955
      // http://ccpv3/#get?type=route&link=e3a9a9f7-0d8e-8e47-332d-1a42232350b8
      // http://ccpv3/#get?type=route&link=1584955
      //
      public function get_stealth_secret_web_link() :String
      {
         var web_link:String = '';
         if (this.item_stack !== null) {
            if (this.item_stack.stealth_secret) {
               //
               if (web_link) {
                  web_link += '&';
               }
               web_link += 'type='
                  + Introspect.get_constructor(this).class_item_type;
               //
               if (web_link) {
                  web_link += '&';
               }
               web_link += 'link=' + this.item_stack.stealth_secret;
               //
               // If the user is an arbiter, but anonymous users cannot
               // access the Web link, we want to use the private deep
               // link.

               m4_DEBUG4('get_stealth_secret_web_link: access_infer_id:',
                         Strutil.as_hex(this.access_infer_id),
                         '/ pub_stl_msk:',
                         Strutil.as_hex(Access_Infer.pub_stealth_mask));
               if (!(this.access_infer_id & Access_Infer.pub_stealth_mask)) {
                  web_link = G.url_base + '#private?' + web_link;
               }
               else {
                  web_link = G.url_base + '#get?' + web_link;
               }
            }
            // else, this item hasn't had its stealth secret created.
         }
         else {
            m4_WARNING('no item_stack, so no stealth secret?:', this);
         }
         return web_link;
      }

      //
      public function has_tag(tag:String) :Boolean
      {
         var has_tag:Boolean = false;
         if (this.tags.is_member(tag)) {
            has_tag = true;
         }
         // MAYBE: On checkout, we always get this.tags. We only get the
         // heavyweight tags when the user views an item's details, and
         // when the user adds tags. So maybe when a new tag is added, we
         // should use this.tags (or maybe we already do that, but until that's
         // confirmed, we go through the heavyweight lookup). I.e., confirm
         // that this.tags is always current and then delete this else if:
         else if (tag in Tag.all_named) {
            var s:Set_UUID = new Set_UUID(
               Link_Value.attachments_for_item(this, Tag));
            if (s.is_member(Tag.all_named[tag])) {
               has_tag = true;
            }
         }
         return has_tag;
      }

      //
      public function get links_lazy_loaded() :Boolean
      {
         return this.fresh || this.links_lazy_loaded_;
      }

      //
      public function set links_lazy_loaded(lazy_loaded:Boolean) :void
      {
         this.links_lazy_loaded_ = lazy_loaded;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         // NOTE: Not calling super.selected.

         // The access_style only applies to the latest version of an item,
         // i.e., rev_spec.Current and rev_spec.Working.
         if ((!Access_Style.is_defined(this.access_style_id))
             && (!this.fresh)
             && (this.stack_id != 0) // stack_id is 0 for new dummy items.
             && (this.rev is utils.rev_spec.Follow)) {
            if (s) {
               m4_DEBUG_CLLL('>callLater: access_style_lazy_load');
               G.app.callLater(G.item_mgr.access_style_lazy_load, [this,]);
            }
         }
         else {
            m4_DEBUG('set selected: access_style okay or n/a: this:', this);
         }
      }

      // *** Group Access helpers

      //
      public function fetch_item_gia(
         get_okay:Function,
         get_fail:Function)
            :void
      {
         m4_DEBUG('fetch_item_gia:', this);

         // The Grac_Get command expects an item lookup, which we willfully
         var items_lookup:Dictionary = new Dictionary();
         items_lookup[this.stack_id] = this;

         // See if we've already loaded the GIA records.
         if (Collection.dict_length(this.groups_access) > 0) {
            m4_DEBUG('fetch_item_gia: reset groups_access:', this);
            this.groups_access = new Dictionary();
         }

         var rev:utils.rev_spec.Base = new utils.rev_spec.Current();
         var qfs:Query_Filters = new Query_Filters();
         qfs.only_stack_ids.push(this.stack_id);
         var resp_items:Array = null;
         var buddy_ct:Counter = null

         // DEVS: Test fetching GIA records:
         //   ./ccp.py -U landonb --no-password \
         //    -r -t group_item_access -x item -I 2538545

         var grac_req:GWIS_Grac_Get = new GWIS_Grac_Get(
            null, 'group_item_access', 'item', rev, G.grac,
            resp_items, buddy_ct, qfs, get_okay, get_fail);

         grac_req.items_in_request = items_lookup;

         var found_duplicate:Boolean;
         found_duplicate = G.map.update_supplemental(grac_req);
         if (found_duplicate) {
            // 2014.09.25: On production, fired once.
            //             FIXME: Probably not really a problem?
            //                    The user just clicked once, then elsewhere,
            //                    then clicked again before the first request
            //                    completed?
            m4_ASSERT_SOFT(!found_duplicate);
            G.sl.event('error/fetch_item_gia/dupl_gwis', {item: this});
         }
      }

      //
      protected function group_access_add_or_update(
         group_id:int,
         access_level_id:int,
         dirty_reason:int=0, // Dirty_Reason.not_dirty
         only_use_if_better:Boolean=false)
            :void
      {
         var grpa:Group_Item_Access = null;
         m4_DEBUG2('group_access_add_or_update: group_id', group_id,
                   '/ acl:', access_level_id);
         m4_ASSERT(group_id != 0);
         if (group_id in this.groups_access) {
            if ((!only_use_if_better)
                || (Access_Level.is_same_or_more_privileged(
                     access_level_id,
                     this.groups_access[group_id].access_level_id))) {
               // maybe if we update from mainline after user edited item?
               grpa = this.groups_access[group_id];
               grpa.access_level_id = access_level_id;
               m4_DEBUG('  >> updated:', grpa);
            }
         }
         else {
            //grpa = new Group_Item_Access(this, group_id, access_level_id);
            grpa = new Group_Item_Access();
            //grpa.item_id = this.system_id;
            grpa.group_id = group_id;
            grpa.access_level_id = access_level_id;
            grpa.item = this;
            grpa.group = G.grac.group_find_or_add(group_id);
            this.groups_access[grpa.group_id] = grpa;
            m4_DEBUG('group_access_add_or_update: groups_access: grpa:', grpa);
         }
         if (grpa !== null) {
            m4_DEBUG('  >> added or updated grpa; so kicking stuff.');
            this.latest_infer_id = null;
            m4_DEBUG2('group_access_add_or_update: latest_infer_id:',
                      this.latest_infer_id, '/', this);
            // This sets this item's Dirty_Reason.item_grac.
            // We'll clear it and our GIA records' same in
            // update_item_committed.
            grpa.dirty_set(dirty_reason, true);
            this.get_access_infer();
         }
      }

      //
      // Callback for views.commands.UI_Wrapper_Group_Item_Access.wrap.
      // Called when user edits an item's access from the details panel.
      // 2014.06: [lb] updated this to work with fixes to Command_Scalar_Edit_2
      //          but I'm pretty sure this fcn. is broken. It's only used by
      //          the GIA widget, which was never released (the level of
      //          permissions it implements is useful just for managing
      //          branch membership and roles, which can be done w/ ccp.py).
      public function groups_access_fcn(
         group_id_:*,
         access_level_id_:*=null,
         do_or_undo:*=null) :*
      {
         var group_id:int = int(group_id_);
         var access_level_id:int;
         if (access_level_id_ === null) {
            access_level_id = Access_Level.invalid;
         }
         else {
            access_level_id = int(access_level_id_);
         }
         //var the_level:int = Access_Level.invalid;
         // MAGIC NUMBER. -1 tells combobox_code_set to say 'Varies'.
         var the_level:int = -1;
         // If the caller sends an invalid Access_Level, it's just a sneaky way
         // to say we should delete the Group_Item_Access object. NOTE: This
         // only happens for group_ids that were not already set for this
         // object (i.e., the Group_Item_Access object is new to the user's
         // working copy (a/k/a, fresh)).
         if (do_or_undo !== null) {
            // A 'set' operation
            // NOTE: Not setting the_level.
            if (!Access_Level.is_valid(access_level_id)) {
               if ((group_id in this.groups_access)
                   && (this.groups_access.fresh)) {
                  delete this.groups_access[group_id];
               }
            }
            m4_DEBUG('calling group_access_add_or_update: edit_user');
            this.group_access_add_or_update(group_id, access_level_id,
                                            Dirty_Reason.edit_user);
            // Skipping: G.item_mgr.dispatchEvent(new Event('grpaChange'));
         }
         else {
            // A 'get' operation
            if (group_id in this.groups_access) {
               the_level = this.groups_access[group_id].access_level_id;
            }
            m4_DEBUG2('groups_access_fcn: get: group_id:', group_id,
                      '/ the_level:', the_level);
         }
         return the_level;
      }

      // After creating a new item for the working copy, we need to apply
      // permissions and create group accesses per the user's new item policy.
      //
      // NOTE: The server does not send the complete new item policy list. It
      //       only sends those that affect the current user. So the group
      //       access list we create here may be incomplete, and the server may
      //       create additional group accesses. Consequently, on fresh items,
      //       we might not indicate the true scope; after saving, the server
      //       will send us the true scope.
      // NOTE: For existing items, the client lazy-loads group accesses when
      //       the user selects an item and navigates to its permissions
      //       panel. For new items, we create the group accesses ourselves.
      // NOTE: Even if the user doesn't change the group accesses on new
      //       items, we still save them to the server. We could choose to
      //       only send group accesses that the user changes, but it
      //       doesn't hurt to send them to the server; if anything, this
      //       acts as a self-check: as developers, we can be more confident
      //       that the client and the server are both implementing permissions
      //       correctly.
      // FIXME: Per last comment, make sure to set dirty flag on group accesses
      // FIXME: If the NIP changes after an item has been created but
      //        before's it's been saved: create a branch conflict.
      //        Not to worry for now, since NIP won't change (or won't
      //        change often) for branches. If we make a client panel for
      //        editing the NIP, we'll want to make sure we catch conflicts.
      // FIXME: Should the client request new item permissions from the server?
      //        This could help address conflicts, and then we wouldn't need
      //        this init_permissions fcn., would we? Consider new GWIS
      //        command, possibly named: Commit_Allowed, Permissions_Get,
      //                                 Grac_Bless, Bless or New_Item_Bless.
      //
      public function init_permissions(groups_rights:Array) :void
      {
         var rights:New_Item_Policy;

         m4_ASSERT(Collection.dict_is_empty(this.groups_access));

         m4_VERBOSE('init_permissions: this:', this);
         m4_VERBOSE('init_permissins: access_level_id:', this.access_level_id);
         m4_ASSERT(this.access_level_id == Access_Level.invalid);

         // Start by denying access to the item. We'll upgrade the user's
         // access as we process the new item policies.
         this.access_level_id = Access_Level.denied;

         m4_DEBUG('init_permissions: this:', this);

         // Loop through the matching new item policies and make sure all the
         // records agree. At this point, we don't expect to see "all_denied".
         var the_style:int = Access_Style.nothingset;
         for each (rights in groups_rights) {
            m4_DEBUG('init_permissions: rights:', rights);
            m4_DEBUG('  >> G.user.private_group_id:', G.user.private_group_id);
            m4_DEBUG('  >> rights.group_id:', rights.group_id);
            m4_DEBUG('  >> rights.access_style_id:', rights.access_style_id);

            m4_ASSURT(rights.group_id != 0);
            m4_ASSURT(Access_Style.is_defined(rights.access_style_id));
            m4_ASSURT(rights.access_style_id != Access_Style.all_denied);
            /* This happens if there's a row following a similar row. I.e.,
               for testing, you can override a previous record by inserting
               a later one (well, one with a larger rank). So maybe we
               shouldn't assert otherwise.
            if (the_style != Access_Style.nothingset) {
               m4_ASSURT(rights.access_style_id == the_style);
            }
            */
            the_style = rights.access_style_id;
         }

         m4_DEBUG('init_permissions: the_style:', the_style);
         this.access_style_id = the_style;

         // STYLE_GUIDE: What happens when Dictionary key does not exist:
         //  var t_int:int = some_dictionary[item_type];
         //  var t_star:* = some_dictionary[item_type];
         //  m4_ASSERT((!t_int)
         //            && (t_int == 0));
         //  m4_ASSERT((!t_star)
         //            && (t_star === undefined)
         //            && (t_star === null)
         //            && (t_star !== null)
         //            && (isNaN(t_star)));
         var item_type:Class = Introspect.get_constructor(this);
         var desired_style:* = G.grac.sticky_choice_by_type[item_type];
         this.init_gia_from_access_style(desired_style);
      }

      //
      protected function init_gia_from_access_style(desired_style:*) :void
      {
         m4_TALKY('init_gia_from_access_style: desired_style:', desired_style);
         // Reset the GIA records according to the new style.
         var group_id:int = int(null);
         if (this.access_style_id == Access_Style.permissive) {
            // It's expected that we're dealing with a real user.
            m4_ASSURT(G.user.logged_in);
            // Give the user owner access to the item.
            this.access_level_id = Access_Level.owner;
            group_id = G.user.private_group_id;
         }
         else if (this.access_style_id == Access_Style.restricted) {
            // Give the user arbiter access to the item.
            this.access_level_id = Access_Level.arbiter;
            if (G.user.logged_in) {
               group_id = G.user.private_group_id;
            }
            else {
               // No session in client: group_id = G.user.session_group_id;
               // Can we just not use a GIA record at all?
               ; // No-op; leave group set to NaN.
            }
         }
         else {
            this.access_level_id = Access_Level.editor;
            // See if the user has a choice regarding item access.

            if ((this.access_style_id == Access_Style.usr_choice)
                || (this.access_style_id == Access_Style.pub_choice)) {
               if (desired_style == Access_Infer.usr_editor) {
                  m4_ASSERT(G.user.logged_in);
                  group_id = G.user.private_group_id;
                  this.style_change_ = Access_Infer.usr_editor;
                  G.grac.user_set_style.add(this);
                  //this.dirty_set(Dirty_Reason.item_schg, true);
               }
               else if (desired_style == Access_Infer.pub_editor) {
                  group_id = G.grac.public_group_id;
                  this.style_change_ = Access_Infer.pub_editor;
                  G.grac.user_set_style.add(this);
                  //this.dirty_set(Dirty_Reason.item_schg, true);
               }
               else {
                  m4_ASSERT(desired_style === undefined);
                  if (G.user.logged_in) {
                     group_id = G.user.private_group_id;
                     // This should go with the suggestion of the access_style.
                     // No?: this.style_change_ = Access_Infer.usr_editor;
                     if (this.access_style_id == Access_Style.usr_choice) {
                        this.style_change_ = Access_Infer.usr_editor;
                     }
                     else {
                        m4_ASSERT(this.access_style_id
                                  == Access_Style.pub_choice);
                        this.style_change_ = Access_Infer.pub_editor;
                     }
                  }
                  else {
                     // Otherwise, can't 'usr_editor', so 'pub_editor'.
                     group_id = G.grac.public_group_id;
                     this.style_change_ = Access_Infer.pub_editor;
                  }
                  //this.dirty_set(Dirty_Reason.item_schg_oob, true);
               }
               this.dirty_set(Dirty_Reason.item_schg_oob, true);
            }
            else if (this.access_style_id == Access_Style.pub_editor) {
               group_id = G.grac.public_group_id;
               this.style_change_ = Access_Infer.pub_editor;
               this.dirty_set(Dirty_Reason.item_schg_oob, true);
            }
            else if (this.access_style_id == Access_Style.usr_editor) {
               m4_ASSURT(G.user.logged_in);
               group_id = G.user.private_group_id;
               this.style_change_ = Access_Infer.usr_editor;
               this.dirty_set(Dirty_Reason.item_schg_oob, true);
            }
            else {
               m4_ASSURT(false);
            }
         }

         // Make just one groups_access record.
         m4_ASSERT(Collection.dict_is_empty(this.groups_access));
         if (group_id) {
            // Don't mark the item as gia dirty, too, or we'll send both GIA
            // and schange records, and then pyserver will yell at us.
            //   var dirty_reason:int = Dirty_Reason.edit_auto;
            var dirty_reason:int = Dirty_Reason.not_dirty;
            this.group_access_add_or_update(group_id,
                                            this.access_level_id,
                                            dirty_reason,
                                            true);
         }

         this.get_access_infer();
      }

      // *** Item_Stack shims

      // NOTE: Even though item_stack is part of/parent of item_versioned, we
      //       define access_style_id and stealth_secret here, since they're
      //       accessy things and so we don't cause problems for Grac_Record
      //       classes. We also need an access_infer_id shim to help us suss
      //       out an item's visibilities.

      //
      public function get access_infer_id() :int
      {
         var latest_infer_id:int;
         var access_infer_id:int;
         m4_VERBOSE('get access_infer_id: calling get_access_infer');
         latest_infer_id = this.get_access_infer();
         if (this.item_stack !== null) {
            access_infer_id = this.item_stack.access_infer_id;
            if (access_infer_id != latest_infer_id) {
               m4_WARNING5('get access_infer_id: diffs:',
                           ' server access_infer_id:',
                           Strutil.as_hex(access_infer_id),
                           '/ client latest_infer_id:',
                           Strutil.as_hex(latest_infer_id));
            }
         }
         return latest_infer_id;
      }

      //
      public function set access_infer_id(access_scope_id:int) :void
      {
         // None may set this calculated value.
         m4_ASSERT(false);
      }

      //
      public function get access_style_id() :int
      {
         var access_style_id:int = Access_Style.nothingset;
         if (this.item_stack !== null) {
            access_style_id = this.item_stack.access_style_id;
         }
         return access_style_id;
      }

      //
      public function set access_style_id(access_style_id:int) :void
      {
         if (this.item_stack === null) {
            this.item_stack = new Item_Stack(this);
         }
         this.item_stack.access_style_id = access_style_id;
         m4_DEBUG('set access_style_id:', this.item_stack.access_style_id);
      }

      // ***

      //
      public function get fbilty_pub_libr_squel() :int
      {
         var fbilty_pub_libr_squel:int = Library_Squelch.squelch_undefined;
         if (this.item_stack !== null) {
            fbilty_pub_libr_squel = this.item_stack.fbilty_pub_libr_squel;
         }
         return fbilty_pub_libr_squel;
      }

      //
      public function set fbilty_pub_libr_squel(fbilty_pub_libr_squel:int)
         :void
      {
         if (this.item_stack === null) {
            this.item_stack = new Item_Stack(this);
         }
         this.item_stack.fbilty_pub_libr_squel = fbilty_pub_libr_squel;
         m4_DEBUG2('set fbilty_pub_libr_squel:',
                   this.item_stack.fbilty_pub_libr_squel);
      }

      //
      public function get fbilty_usr_histy_show() :Boolean
      {
         var fbilty_usr_histy_show:Boolean = false;
         if (this.item_stack !== null) {
            fbilty_usr_histy_show = this.item_stack.fbilty_usr_histy_show;
         }
         return fbilty_usr_histy_show;
      }

      //
      public function set fbilty_usr_histy_show(fbilty_usr_histy_show:Boolean)
         :void
      {
         if (this.item_stack === null) {
            this.item_stack = new Item_Stack(this);
         }
         this.item_stack.fbilty_usr_histy_show = fbilty_usr_histy_show;
         m4_DEBUG2('set fbilty_usr_histy_show:',
                   this.item_stack.fbilty_usr_histy_show);
      }

      //
      public function get fbilty_usr_libr_squel() :int
      {
         var fbilty_usr_libr_squel:int = Library_Squelch.squelch_undefined;
         if (this.item_stack !== null) {
            fbilty_usr_libr_squel = this.item_stack.fbilty_usr_libr_squel;
         }
         return fbilty_usr_libr_squel;
      }

      //
      public function set fbilty_usr_libr_squel(fbilty_usr_libr_squel:int)
         :void
      {
         if (this.item_stack === null) {
            this.item_stack = new Item_Stack(this);
         }
         this.item_stack.fbilty_usr_libr_squel = fbilty_usr_libr_squel;
         m4_DEBUG2('set fbilty_usr_libr_squel:',
                   this.item_stack.fbilty_usr_libr_squel);
      }

      // ***

      //
      public function get stealth_secret() :String
      {
         var stealth_secret:String = null;
         if (this.item_stack !== null) {
            stealth_secret = this.item_stack.stealth_secret;
         }
         return stealth_secret;
      }

      //
      public function set stealth_secret(stealth_secret:String) :void
      {
         m4_ASSERT(!this.stealth_secret);
         if (this.item_stack === null) {
            this.item_stack = new Item_Stack(this);
         }
         this.item_stack.stealth_secret = stealth_secret;
      }

      //
      public function get style_change() :int
      {
         return this.style_change_;
      }

      //
      public function set style_change(style_change:int) :void
      {
         var was_style_change:int = this.style_change;
         this.style_change_ = style_change;
         m4_DEBUG('set style_change:', this.style_change);
         if (was_style_change != this.style_change) {
            m4_ASSERT((this.access_style_id == Access_Style.usr_choice)
                      || (this.access_style_id == Access_Style.pub_choice));
            m4_ASSERT((this.style_change == Access_Infer.usr_editor)
                      || (this.style_change == Access_Infer.pub_editor));
            this.groups_access = new Dictionary();
            this.latest_infer_id = null;
            m4_DEBUG2('set style_change: latest_infer_id:',
                      this.latest_infer_id, '/', this);
            this.init_gia_from_access_style(this.style_change);
         }
      }

      // *** Permissions convenience fcns.

      // CODE_COUSINS: pyserver/item/group_item_access.py
      //               flashclient/item/Item_User_Access.as

      //
      public function get is_access_valid() :Boolean
      {
         return Access_Level.is_valid(this.access_level_id);
      }

      //
      public function get can_own() :Boolean
      {
         return Access_Level.can_own(this.access_level_id);
      }

      //
      public function get can_arbit() :Boolean
      {
         return Access_Level.can_arbit(this.access_level_id);
      }

      //
      public function get can_edit() :Boolean
      {
         return Access_Level.can_edit(this.access_level_id);
      }

      //
      public function get can_view() :Boolean
      {
         return Access_Level.can_view(this.access_level_id);
      }

      //
      public function get can_client() :Boolean
      {
         return Access_Level.can_client(this.access_level_id);
      }

      // *** Access Scope fcns.

      //
      protected function get_access_infer() :int
      {
         //m4_DEBUG2('_access_infr: latest_infer_id:', this.latest_infer_id,
         //          '/', this);
         if ((this.latest_infer_id === null) && (G.user !== null)) {
            this.latest_infer_id = this.get_access_infer_impl();
            //m4_DEBUG2('get_access_infer: latest_infer_id:',
            //          this.latest_infer_id, '/', this);
         }
         return this.latest_infer_id;
      }

      // See flashclient.get_access_infer / pyserver.get_access_infer.
      //
      protected function get_access_infer_impl() :int
      {
         var latest_infer_id_:int = Access_Infer.not_determined // I.e., 0.

         var private_group_id:int = G.user.private_group_id;
         var public_group_id:int = G.grac.public_group_id;
         var session_group_id:int = G.grac.session_group_id;
         var stealth_group_id:int = G.grac.stealth_group_id;

         if (!(Collection.dict_is_empty(this.groups_access))) {
            m4_DEBUG('get_access_infer_: this.groups_access...');
            for each (var grpa:Group_Item_Access in this.groups_access) {
               m4_DEBUG(' .. : grpa:', grpa);
               // Check for user's private group.
               if (grpa.group_id == private_group_id) {
                  if (Access_Level.can_arbit(grpa.access_level_id)) {
                     latest_infer_id_ |= Access_Infer.usr_arbiter;
                  }
                  else if (Access_Level.can_edit(grpa.access_level_id)) {
                     latest_infer_id_ |= Access_Infer.usr_editor;
                  }
                  // else if (Access_Level.can_edit(grpa.access_level_id)) {
                  //    latest_infer_id_ |= Access_Infer.usr_viewer;
                  // }
                  // else {
                  //    m4_ASSERT(grpa.access_level_id == Access_Level.denied);
                  // }
               }
               // Check for the public group.
               else if (grpa.group_id == public_group_id) {
                  if (Access_Level.can_edit(grpa.access_level_id)) {
                     m4_ASSERT(!Access_Level.can_arbit(grpa.access_level_id));
                     latest_infer_id_ |= Access_Infer.pub_editor;
                  }
                  else if (Access_Level.can_client(grpa.access_level_id)) {
                     // NOTE: Using can_client and not just can_view.
                     latest_infer_id_ |= Access_Infer.pub_viewer;
                  }
                  else {
                     m4_ASSERT(grpa.access_level_id == Access_Level.denied);
                  }
               }
               // Check Session ID Group.
               else if (grpa.group_id == session_group_id) {
                  if (Access_Level.can_arbit(grpa.access_level_id)) {
                     latest_infer_id_ |= Access_Infer.sessid_arbiter;
                  }
                  else if (Access_Level.can_edit(grpa.access_level_id)) {
                     m4_ASSERT(!Access_Level.can_arbit(grpa.access_level_id));
                     latest_infer_id_ |= Access_Infer.sessid_editor;
                  }
                  else if (Access_Level.can_client(grpa.access_level_id)) {
                     // NOTE: Using can_client and not just can_view.
                     latest_infer_id_ |= Access_Infer.sessid_viewer;
                  }
                  else {
                     m4_ASSERT(grpa.access_level_id == Access_Level.denied);
                  }
               }
               // Check Stealth-Secret Group.
               else if (grpa.group_id == stealth_group_id) {
                  if (Access_Level.can_edit(grpa.access_level_id)) {
                     // The stealth group is never granted arbiter access.
                     m4_ASSERT(!Access_Level.can_arbit(grpa.access_level_id));
                     latest_infer_id_ |= Access_Infer.stealth_editor;
                  }
                  else if (Access_Level.can_client(grpa.access_level_id)) {
                     // NOTE: Using can_client and not just can_view.
                     latest_infer_id_ |= Access_Infer.stealth_viewer;
                  }
                  else {
                     m4_ASSERT(grpa.access_level_id == Access_Level.denied);
                  }
               }
               // For branches and other items with permissive access, check
               // for other users' access.
               else {
                  if (Access_Level.can_arbit(grpa.access_level_id)) {
                     latest_infer_id_ |= Access_Infer.others_arbiter;
                  }
                  else if (Access_Level.can_edit(grpa.access_level_id)) {
                     latest_infer_id_ |= Access_Infer.others_editor;
                  }
                  else if (Access_Level.can_client(grpa.access_level_id)) {
                     latest_infer_id_ |= Access_Infer.others_viewer;
                  }
                  else {
                     m4_ASSERT(grpa.access_level_id == Access_Level.denied);
                  }
               }
               /* The session group's ID is unknown to us...
               */
            } // for each ... in this.groups_access
         }
         else if (this.item_stack !== null) {
            m4_DEBUG('get_access_infer_: this.item_stack...');
            latest_infer_id_ = this.item_stack.access_infer_id;
         }
         else {
            m4_DEBUG('_access_infer_: access_style:', this.access_style_id);
            // This is the case for items for which we didn't get either
            // groups_access (the user hasn't selected the item; we only get
            // GIA records when we lazy-load an item's complete deets) or
            // access_infer_id (which the server only sends if we specify
            // include_item_stack, which we only do for some item types,
            // like route (for the route library, so we can highlight entries
            // according to their permissions and shareability)).
            if ((this.access_style_id == Access_Style.permissive)
                || (this.access_style_id == Access_Style.restricted)) {
               // If we can arbit the item, it's private or shared. Assume
               // shared, since we can't be sure without GIA records. But
               // if we're just an editor or viewer, then we also know the
               // item is merely being shared.
               //latest_infer_id_ = Access_Infer.others_editor;
               latest_infer_id_ = Access_Infer.not_determined;
            }
            else if ((this.access_style_id == Access_Style.usr_choice)
                     || (this.access_style_id == Access_Style.pub_choice)) {
               if (this.style_change_ == Access_Infer.usr_editor) {
                  m4_ASSERT((this.fresh) || (this.invalid));
                  // NOTE: This is an unsaved item, so item can't be shared
                  //       (i.e., no need to check for Web link).
                  latest_infer_id_ = Access_Infer.usr_arbiter;
               }
               else if (this.style_change_ == Access_Infer.pub_editor) {
                  m4_ASSERT(this.fresh);
                  latest_infer_id_ = Access_Infer.pub_editor;
               }
               else {
                  // This is an item from the server, but it saved
                  // access_style_id as whatever the value from new_item_policy
                  // was at the time the item was saved... so we don't know
                  // what choice the user made. Assume shared, I guess...
                  m4_ASSERT(!this.fresh);
                  //latest_infer_id_ = Access_Infer.others_editor;
                  latest_infer_id_ = Access_Infer.not_determined;
               }
            }
            else if (this.access_style_id == Access_Style.usr_editor) {
               // MAYBE: We're ignoring sharing via Web link...
               //        but maybe you can't Web link this type of item?
               //        Or do we add the Web link access widget?? Argh.
               latest_infer_id_ = Access_Infer.usr_editor;
            }
            else if (this.access_style_id == Access_Style.pub_editor) {
               latest_infer_id_ = Access_Infer.pub_editor;
            }
            else if (this.access_style_id == Access_Style.all_denied) {
               // Server scripts make records marked all_denied so assume
               // public.
               latest_infer_id_ = Access_Infer.pub_editor;
            }
            else {
               m4_ASSERT(this.access_style_id == Access_Style.nothingset);
               //latest_infer_id_ = Access_Infer.pub_editor;
               latest_infer_id_ = Access_Infer.not_determined;
            }
         }

         m4_DEBUG2('get_access_infer_: latest_infer_id_:',
                   Strutil.as_hex(latest_infer_id_));

         return latest_infer_id_;
      }

      //
      [Bindable] public function get is_public() :Boolean
      {
         // This is probably sufficient:
         //   return (this.access_infer_id == Access_Infer.pub_editor);
         // Or we could overengineer
         return ((this.access_infer_id & Access_Infer.pub_editor)
                 && (!(this.access_infer_id & Access_Infer.all_arbiter_mask)));
      }

      //
      public function set is_public(enable:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      [Bindable] public function get is_shared() :Boolean
      {
         // NOTE: This is a loose interpretation of shared: it means the item
         //       is arbited by some user, but it doesn't indicate if that user
         //       is this user or not.
         return (
            (Boolean(this.access_infer_id & Access_Infer.usr_arbiter)
             || Boolean(this.access_infer_id & Access_Infer.usr_editor))
            && Boolean(this.access_infer_id & Access_Infer.not_private_mask));
      }

      //
      public function set is_shared(enable:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      [Bindable] public function get is_private() :Boolean
      {
         // NOTE: This is a strict interpretation of private: it means public
         //       and stealth don't have access. So it's not very fine grained.
         return (((this.access_infer_id & Access_Infer.usr_arbiter)
                  || (this.access_infer_id & Access_Infer.usr_editor))
                 && (!(this.access_infer_id & Access_Infer.not_private_mask)));
      }

      //
      public function set is_private(enable:Boolean) :void
      {
         m4_ASSERT(false);
      }

      // *** Developer methods

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' / ' + 'AcL ' + this.access_level_id
                 + ' / ' + 'Sty ' + this.access_style_id
                 // this.latest_infer_id is null until this.access_infer_id is
                 // called but the latter can't call String(this) if it's here.
                 + ' / ' + 'Nfr ' + Strutil.as_hex(this.latest_infer_id)
                 //+ ' / ' + '_Nfr ' + Strutil.as_hex(this.access_infer_id)
                 + (this.style_change ? (' / Chg ' + this.style_change)
                                      : '')
                 );
      }

   }
}


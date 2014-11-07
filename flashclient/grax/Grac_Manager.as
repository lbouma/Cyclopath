/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package grax {

   import flash.events.Event;
   import flash.utils.Dictionary;

   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.gracs.Group;
   import items.gracs.Group_Membership;
   import items.gracs.New_Item_Policy;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   // This classes manages the group access control items for the user.
   // These are Item_Versioned objects like Group_, Group_Membership, and
   // New_Item_Policy.

   public class Grac_Manager extends Aggregator_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('GRAC________');

      // *** Member variables

      // This object represents a collection of Group Access items for a
      // particular context. The client always requests the context for
      // the user, so we know what creation rights the user has. The client
      // sometimes requests the other contexts, like requesting the new item
      // policies for the branch. Note that the context implies what's savable,
      // too. That is, you wouldn't save a user's new item policies, but you
      // would save a branch's.
      //
      // The set of contexts is ['user', 'branch', 'group', 'item'].
      // See the Wiki for more deets.

      protected var context:String;

      // The stack IDs of every Group Membership, Group, and New Item Policy
      // are stored in a handy lookup.
      // FIXME: See client_id_map: If we save GrAC from flashclient, will need
      //        to update client IDs to permanent IDs after commit, or we have
      //        to reload GrAC records.
      public var all:Dictionary = new Dictionary();

      // Following are collections to store each of the grac items for this
      // context.

      // A lookup of the user's group memberships.
      public var group_memberships:Dictionary = new Dictionary();
      // A lookup of groups, but not necessary the user's.
      public var groups:Dictionary = new Dictionary();
      public var public_group_id:int = 0;
      public var session_group_id:int = 0;
      public var stealth_group_id:int = 0;
      protected var shared_groups:Dictionary = new Dictionary();

      protected var new_item_policies:Array = new Array();
      protected var new_item_policies_sorted:Boolean = false;

      // A list of new items on which the user has explicitly set style_change.
      //
      // This is mostly used by the view but there's not a good global object
      // in the view for this lookup. Also, the sticky_choice_by_type lookup
      // affects an item's permissions, and we might as well apply the default
      // choice when items are created, as opposed to having Widget_Gia_Sharing
      // do it.
      public var user_set_style:Set_UUID = new Set_UUID();
      // User's default access_style for new items w/ usr_choice or pub_choice.
      public var sticky_choice_by_type:Dictionary = new Dictionary();
      // 
      // For usages, see Item_User_Access.init_permissions(groups_rights)
      //             and Widget_Gia_Sharing.

      // *** Constructor

      public function Grac_Manager(context:String)
      {
         super();
         // FIXME: Is this the right way to deal w/ context?
         this.context = context;
         m4_ASSERT(this.context == 'user'); // Nothing else is implemented...
         var reset_group_memberships:Boolean = true;
         this.reset_grac_mgr(reset_group_memberships);

         G.item_mgr.addEventListener(
            'itemsCommitted', this.on_items_committed, false, 0, true);
         // These are redundant. revisionChange probably comes/should come 1st.
         G.item_mgr.addEventListener(
            'revisionChange', this.on_revision_change, false, 0, true);
         G.item_mgr.addEventListener(
            'updatedRevision', this.on_updated_revision, false, 0, true);
      }

      // ***

      //
      public function reset_grac_mgr(reset_group_memberships:Boolean=true)
         :void
      {
         m4_DEBUG('reset_grac_mgr: zapping grac fr. local working copy');
         // ??: this.context = '';
         this.all = new Dictionary();
         // Group Memberships are only reset and refetched when changing users.
         if (reset_group_memberships) {
            this.group_memberships = new Dictionary();
            this.groups = new Dictionary();
            this.public_group_id = 0;
            m4_DEBUG('  >> resetting session_group_id');
            this.session_group_id = 0;
            m4_DEBUG('  >> resetting stealth_group_id');
            this.stealth_group_id = 0;
            this.shared_groups = new Dictionary();
         }
         else {
            // Since we're keeping group_memberships, put them back in all.
            var membership:Group_Membership;
            for each (membership in this.group_memberships) {
               m4_DEBUG('reset_grac_mgr: re-adding membership:', membership);
               this.all[membership.stack_id] = membership;
            }
         }
         this.new_item_policies = new Array();
         this.new_item_policies_sorted = false;
      }

      // ***

      // When the user wants to create an item, feed it to this fcn. to see
      // if the user has the necessary rights to create the item. We could
      // implement this in reverse -- that is, check that the user has
      // permission to create an item before creating it -- but we'd still have
      // to check everything about the item-to-be, so might as well do it here.
      // The callee should make sure not to add new items to the map or any
      // other collections unless this function blesses the new item.
      public function bless_new(item:Item_User_Access,
                                bless_test:Boolean=false)
                                 :Item_User_Access
      {
         m4_DEBUG('bless_new: examining item');
         var blessed:Item_User_Access = null;
         var groups_rights:Array = this.create_rights_get(item);
         if (groups_rights.length > 0) {
            blessed = item;
            blessed.init_permissions(groups_rights);
            m4_DEBUG('bless_new: blessing okayed!', item);
            // When the item was created, its GIA permissions were created and
            // marked dirty, and this in turn marked the item dirty. So now the
            // item is part of the dirtyset, but we might not want that.
            if (bless_test) {
               m4_DEBUG('bless_new: clearing dirtiness');
               // Simple way:
               //    item.dirty_set(Dirty_Reason.mask_revisioned, false);
               item.item_cleanup();
               // Not anymore: m4_ASSERT(item.dirtyset_gia.length == 0);
               // The item_cleanup fcn. just removes the item from the map and
               // from the class lookups. But the item is still dirty, so the
               // caller will clean up further. I.e., we can't set unset dirty,
               // since a newly deleted item still has to be saved to the
               // server.
            }
         }
         else {
            m4_DEBUG('bless_new: blessing denied!', item);
         }
         return blessed;
      }

      // This fcn. determines the user's creation rights on a new item. Since
      // users can belong to more the one group, we might have more than one
      // policy to consider for the given targets. The callee passes the new
      // item the users wishes to create, and we pass back a collection of
      // rights.
      protected function create_rights_get(new_item:Item_User_Access)
         :Array
      {
         m4_DEBUG('create_rights_get: new_item:', new_item);

         var groups_rights:Array = new Array();

         // Make sure the list is sorted
         this.new_item_policies_sort();

         // Iterate through the list to determine the user's rights
         for (var i:int = 0; i < this.new_item_policies.length; i++) {
            
            var policy:New_Item_Policy = this.new_item_policies[i];
            m4_DEBUG('$ checking policy:', policy.name_);
            m4_DEBUG('$  /', policy.to_string_part_i());
            m4_DEBUG('$  /', policy.to_string_part_ii());

            // Some things are unexpected.
            m4_ASSERT(policy.access_style_id != Access_Style.all_access);
            m4_ASSERT(Access_Style.is_defined(policy.access_style_id));

            // If the policy matches the targets, collect the rights
            if (policy.matches_targets(new_item)) {

               // Only add the policy to the list if the user is allowed to
               // create items.
               if (policy.access_style_id == Access_Style.all_denied) {
                  m4_DEBUG('  - no creation rights, or super_acl defined');
               }
               else {
                  var push_policy:Boolean = true;
                  // The New Item Policy has short-circuit records for special
                  // Link Values, like those to private item watchers. We need
                  // those records to know that non-logged in users cannot
                  // create item watchers, and it's here we find those policies
                  if (!G.user.logged_in) {
                     if ((policy.access_style_id == Access_Style.permissive)
                         || (policy.access_style_id == Access_Style.restricted)
                         || (policy.access_style_id == Access_Style.usr_editor)
                         ) {
                        m4_DEBUG('  - no: need user:', policy.access_style_id);
                        push_policy = false;
                        // But we'll still short-circuit, if stop_on_match.
                     }
                     else if (
                        (policy.access_style_id == Access_Style.pub_choice)
                         || (policy.access_style_id == Access_Style.usr_choice)
                         ) {
                        // Force the access_style_id; there's only one choice.
                        // FIXME: Is this okay??
                        //policy.access_style_id == Access_Style.pub_editor;
                        ;
                     }
                     else {
                        m4_ASSERT(policy.access_style_id
                                  == Access_Style.pub_editor);
                     }
                  }

                  if (push_policy) {
                     m4_DEBUG('  - create ok: astyl:', policy.access_style_id);
                     groups_rights.push(policy);
                  }
               }

               // If the policy is a short-circuit, we're done
               if (policy.stop_on_match) {
                  m4_DEBUG('  short-circuiting!');
                  break;
               }
            }
         }

         return groups_rights;
      }

      //
      public function group_find_or_add(group_id:int, group:Group=null) :Group
      {
         m4_DEBUG2('group_find_or_add: group_id:', group_id,
                   '/ group:', ((group !== null) ? group.toString() : 'null'));
         var the_group:Group = null;
         m4_ASSERT(group_id != 0);
         if (!(group_id in this.groups)) {
            if (group !== null) {
               this.groups[group_id] = group;
               the_group = this.groups[group_id];
               m4_DEBUG('  >> added the_group:', the_group);
            }
            else {
               m4_WARNING('group_find_or_add: group not specified');
            }
         }
         else {
            the_group = this.groups[group_id];
            m4_DEBUG('  >> found the_group:', the_group);
         }
         return the_group;
      }

      // FIXME: Respek changes in branch head revision.
      // FIXME: Fcn. name is misleading: not creating new Group in database,
      //        just creating new group in client based on existing group in
      //        database.
      public function group_find_or_create(group_id:int,
                                           group_version:int=-1,
                                           group_name:String=null,
                                           group_desc:String=null,
                                           group_scope:int=0) :Group
      {
         m4_ASSERT(false); // Unused
         m4_DEBUG3('group_find_or_create: group_id:', group_id,
                   '/ version', group_version, '/ name', group_name,
                   '/ desc', group_desc, '/ scope', group_scope);
         if (!(group_id in this.groups)) {
            m4_ASSERT(group_version >= 0);
            var grp:Group = new Group();
            // FIXME: Soooo hacky.
            grp.stack_id = group_id;
            grp.version = group_version;
            grp.name_ = group_name;
            grp.description = group_desc;
            grp.access_scope_id = group_scope;
            this.groups[group_id] = grp;
         }
         return this.groups[group_id];
      }

      //
      public function group_membership_register(membership:Group_Membership)
         :void
      {
         m4_DEBUG2('group_membership_register:', membership,
                   '/ context:', this.context);

         // The server add fakes group_memberships for the Stealth-Secret and
         // Session ID Groups, so we can learn their group stack_ids. But we
         // don't store these fake memberships.

         if (membership.stack_id > 0) {
            m4_ASSERT(!(membership.stack_id in this.all));
            m4_ASSERT(!(membership.stack_id in this.group_memberships));
            this.group_memberships[membership.stack_id] = membership;

            // Add the policy to the grac's 'all' lookup
            this.all[membership.stack_id] = membership;
         }
         // else, fake group_membership for either stealth or session.

         // Remember special Group IDs.

         if (membership.group.is_private) {
            if (this.context == 'user') {
               m4_ASSERT(G.grac === this);
               // If the user loads Ccps while logged out and then logs in,
               // G.user.private_group_id is set to the anonymous user's
               // private group ID. I'm not sure this matters..., or that
               // we need to distinguish that in the code.
               m4_DEBUG2('  >> G.user.private_group_id:',
                         G.user.private_group_id);
               m4_DEBUG2('  >> membership.group.stack_id:',
                         membership.group.stack_id);
               m4_DEBUG2('  >> setting private_group_id:',
                         membership.group.stack_id);
               G.user.private_group_id = membership.group.stack_id;
            }
            m4_ASSERT_ELSE; // no other context implemented... currently
         }
         else if (membership.group.is_public) {
            // MAGIC_NUMBERNAME: See the database and pyserver code...
            if (membership.group.name_ == 'All Users') {
               m4_ASSERT_SOFT(this.public_group_id == 0);
               m4_DEBUG2('  >> setting public_group_id:',
                         membership.group.stack_id);
               this.public_group_id = membership.group.stack_id;
            }
            // MAGIC_NUMBERNAME: See the database and pyserver code...
            else if (membership.group.name_ == 'Session ID Group') {
               m4_ASSERT_SOFT(this.session_group_id == 0);
               m4_DEBUG2('  >> setting session_group_id:',
                         membership.group.stack_id);
               this.session_group_id = membership.group.stack_id;
            }
            // MAGIC_NUMBERNAME: See the database and pyserver code...
            else if (membership.group.name_ == 'Stealth-Secret Group') {
               m4_ASSERT_SOFT(this.stealth_group_id == 0);
               m4_DEBUG2('  >> setting stealth_group_id:',
                         membership.group.stack_id);
               this.stealth_group_id = membership.group.stack_id;
            }
            else {
               m4_ERROR2('group_membership_register: unexpected public mmb.:',
                         membership);
               m4_ASSERT_SOFT(false);
            }
         }
         // MAYBE: Use, i.e., internal_name or system_id for special groups?
         // ccpv3=> select stack_id,name from group_ where access_scope_id = 2;
         //  stack_id |            name             
         // ----------+-----------------------------
         //   2421568 | Basemap Owners
         //   2426597 | Basemap Arbiters
         //   2426598 | Basemap Editors
         //   2436806 | Metc Bikeways 2012 Owners
         //   2436807 | Metc Bikeways 2012 Arbiters
         //   2436808 | Metc Bikeways 2012 Editors
         //   2436847 | Stealth-Secret Group         -- now access_scope_id = 3
         //   2436848 | Session ID Group             -- now access_scope_id = 3
         else {
            m4_ASSERT(membership.group.is_shared);
            // [lb]'s database has mult., same-named shared groups...
            // FIXME: Re-implement this assert:
            // m4_ASSERT(!(membership.group.name_ in this.shared_groups));
            if (membership.group.name_ in this.shared_groups) {
               m4_WARNING2('Overwriting shared group:', membership.group.name_,
                           '/ stack_id:', membership.group.stack_id);
            }
            this.shared_groups[membership.group.name_] = membership.group;
            // Skipping: this.session_group_id
         }
      }

      // ***

      // This function is used when updating from the server to store the new
      // item policies.
      public function new_item_policy_register(policy:New_Item_Policy) :void
      {
         // 2013.05.30: This is kind of hacky, but it has to happen; so maybe
         // it's just a matter of where's the best place to do this? If we did
         // this later, we could make the widgets indicate, e.g., Hey, user, if
         // you logged on, you could make this new item private. But whatever,
         // for now this is easier: if the user is not logged in, decide for
         // them an answer to a tough question, to usr_editor or to pub_editor?
         if ((!G.user.logged_in)
             && ((policy.access_style_id == Access_Style.pub_choice)
                 || (policy.access_style_id == Access_Style.usr_choice))) {
            m4_DEBUG('nip_register: forcing pub_editor:', policy.name_);
            policy.access_style_id == Access_Style.pub_editor;
         }

         m4_ASSERT(!(policy.stack_id in this.all));
         this.new_item_policies.push(policy);
         this.new_item_policies_sorted = false;

         // Add the policy to the grac's 'all' lookup
         this.all[policy.stack_id] = policy;
      }

      //
      protected function new_item_policies_sort() :void
      {
         if (!this.new_item_policies_sorted) {
            this.new_item_policies.sortOn('processing_order', Array.NUMERIC);
            this.new_item_policies_sorted = true;
         }
      }

      // ***

      // Adds a list of group access items.
      // This is called from GWIS_Grac_Get, which has a handle to Grac_Manager.
      // NOTE: This just adds GIA records, not items. Items are loaded via
      //       Map_Canvas_Items.items_add (which also calls item.init()).
      public function items_add(new_items:Array, complete_now:Boolean=true)
         :Boolean
      {
         var operation_complete:Boolean = true;

         var tstart:int = G.now(); // for m4_DEBUG_TIME.

         m4_INFO('items_add: consuming', new_items.length, 'items');

         // Unlike Map_Canvas_Items.items_add, this fcn. processes everything
         // at once. We shouldn't need the complexity of the callLater
         // implementation, or we should share this fcn. w/ Map_Canvas_Items.
         m4_ASSERT(complete_now);

         for each (var item:Item_Versioned in new_items) {
            item.init_item(this);
         }

         m4_DEBUG_TIME('Grac_Manager.items_add');

         // Ahem! Clear the array; the caller expects it empty if we say the
         // operation is complete
         new_items.length = 0;

         return operation_complete;
      }

      //
      public function prepare_item(
         item:Item_User_Access,
         access_min:int=-1, // MAGIC NO.: Access_Level.invalid
         must_exist:Boolean=false) :Boolean
      {
         m4_DEBUG2('prepare_item:', item, '/ access_min:', access_min,
                   '/ must_exist:', must_exist);
         var prepared:Boolean = true;
         if (!Access_Level.is_valid(access_min)) {
            access_min = Access_Level.editor;
         }
         // FIXME: Is this fcn. ever called twice on the same item as it's
         //        being created? Would that mean prepare_new is called first,
         //        and then prepare_existing? That would be weird.
         if ((item.invalid) || (!item.is_access_valid)) {
            m4_ASSERT(!must_exist); // This fcn. shouldn't be called otherwise.
            prepared = this.prepare_new(item);
         }
         // Always make sure user has minimum access required, regardless of
         // new or not
         //else {
         if (prepared) {
            prepared = this.prepare_existing(item, access_min);
         }
         //}
         return prepared;
      }

      // Assign an id and bless the new item. If the item cannot be created
      // then an alert is shown and false is returned.
      //
      // Returns true if the item is successfully prepared and can be created.
      protected function prepare_new(item:Item_User_Access) :Boolean
      {
         var permitted:Boolean = false;

         m4_ASSERT(item.invalid || item.fresh);
         if (item.invalid) {
            G.item_mgr.assign_id(item);
         }

         m4_DEBUG('prepare_new:', item);

         if (item) {
            permitted = (this.bless_new(item) !== null);
            if (!permitted) {
               // FIXME: Do this?
               //        item.stack_id = 0;
               m4_WARNING('prepare_new: Denied!', item);
            }
            else {
               // If a user can create an item, they better be able to edit it!
               m4_ASSERT(item.can_edit);
            }
         }
         m4_ASSERT_ELSE; // item.invalid would've thrown null error, right?

         return permitted;
      }

      // Check that the user is allowed to edit the existing item. If the item
      // cannot be updated, then an alert is shown and false is returned.
      //
      // Returns true if the item is successfully prepared and can be updated.
      protected function prepare_existing(item:Item_User_Access,
                                          access_min:int) :Boolean
      {
         var permitted:Boolean = false;

         m4_ASSERT(!item.invalid);

         m4_DEBUG('prepare_existing:', item);

         // Check that access is viewer, editor, or owner. A min access of
         // invalid or denied does not make sense, does it.
         // 2013.05.24: The new /byway/cycle_facil says client... ha.
         //             I [lb] think client access is okay -- the nip will
         //             be consulted and further verification will happen.
         //m4_ASSERT(Access_Level.can_view(access_min));
         m4_ASSERT(Access_Level.can_client(access_min));

         //permitted = item.can_edit;
         permitted = Access_Level.is_same_or_more_privileged(
                        item.access_level_id, access_min);
         if (!permitted) {
            m4_WARNING('prepare_existng: Denied!', item, '(', access_min, ')');
         }

         return permitted;
      }

      // ***

      //
      protected function on_items_committed(event:Event=null) :void
      {
         m4_DEBUG('on_items_committed');
         this.user_set_style = new Set_UUID();
         this.sticky_choice_by_type = new Dictionary();
      }

      //
      protected function on_revision_change(event:Event=null) :void
      {
         m4_DEBUG('on_revision_change');
         this.user_set_style = new Set_UUID();
         this.sticky_choice_by_type = new Dictionary();
      }

      //
      protected function on_updated_revision(event:Event=null) :void
      {
         m4_DEBUG('on_updated_revision');
         this.user_set_style = new Set_UUID();
         this.sticky_choice_by_type = new Dictionary();
      }

      // ***

   }
}


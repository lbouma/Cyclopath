/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.gracs {

   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   import grax.Access_Level;
   import grax.Access_Style;
   import grax.Aggregator_Base;
   import grax.Grac_Manager;
   import grax.New_Item_Profile;
   import items.Grac_Record;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   // CODE_COUSINS: flashclient/items/gracs/New_Item_Policy.py
   //               pyserver/item/grac/new_item_policy.py

   public class New_Item_Policy extends Grac_Record {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#New_Itm_Pol');

      // *** Mandatory attributes

      public static const class_item_type:String = 'new_item_policy';
      public static const class_gwis_abbrev:String = 'nip';
      public static const class_item_type_id:int = Item_Type.NEW_ITEM_POLICY;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:* = null;

      // *** Instance variables

      // Policies are processed in order.
      public var processing_order:int = 0;

      // The branch owner can specify that processing stops on certain matches.
      public var stop_on_match:Boolean = true;

      // Policies apply to users that belong to the specified group.
      public var group_id:int = 0;

      // The target item is the type of item in question. If it's a link, the
      // policy can also specify the profile of the two items being linked.
      protected var target_item:New_Item_Profile = new New_Item_Profile();
      // The left and right targets are used for link_value policies.
      protected var target_left:New_Item_Profile = new New_Item_Profile();
      protected var target_right:New_Item_Profile = new New_Item_Profile();

//      public var new_item_rights:New_Item_Rights = new New_Item_Rights();
      public var access_style_id:int = Access_Style.nothingset;
      public var super_acl:int = Access_Level.invalid;

      // *** Constructor

      public function New_Item_Policy(xml:XML=null,
                                      rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Public interface

      //
      public function matches_targets(new_item:Item_User_Access) :Boolean
      {
         var does_match:Boolean = false;
         var link:Link_Value;
         if (this.target_item.matches(new_item)) {
            // There's not a strict rule that left is attc and right is feat
            // -- in fact, you could specify a policy for linking two attcs
            // (though the client only supports links btw. attcs and feats).
            if (!(new_item is Link_Value)) {
               // This policy does not apply to links.
               m4_ASSERT(!(this.target_left.is_valid));
               m4_ASSERT(!(this.target_right.is_valid));
               m4_DEBUG('matches_targets: ok: item not a link');
               does_match = true;
            }
            else {
               // This policy applies to links.
               link = (new_item as Link_Value);
               // FIXME/BUG nnnn: create_allowed_get(Link_Value)
               //  The new_item_policy's link_value records specify
               //  lhs and rhs item types, and sometimes even stack
               //  IDs, so the create_allowed_get mechanism doesn't
               //  work -- we would have to have it check more
               //  specific dummy Link_Values...
               //   FIXME: Search: create_allowed_get Link_Value.
               // So, for now, we always expect a fully hydrated Link_Value.
               // 2013.06.03: Don't forget link.attr, e.g., for link_revision.
               //  m4_ASSERT((link.attc !== null) && (link.feat !== null));
               var lhs_item:Item_User_Access;
               var rhs_item:Item_User_Access;
               lhs_item = link.attc;
               // Get the link.feat, link.attr, or link.thread.
               rhs_item = link.item;
               m4_ASSERT((lhs_item !== null) && (rhs_item !== null));
               if ((this.target_left.is_valid)
                   && (this.target_right.is_valid)) {
                  // If we're called from on_process_new_item_policy,
                  // which calls bless_new on a bunch of dummy items,
                  // this Link_Value won't have an attc or feat.
                  /*
                  if ((lhs_item === null)
                      && (rhs_item === null)) {
                     // The best we can do is assume the best case, which is
                     // that the left and right min access is not denied.
                     if ((Access_Level.is_same_or_more_privileged(
                           this.target_left.min_access_id,
                           Access_Level.client))
                         && (Access_Level.is_same_or_more_privileged(
                           this.target_right.min_access_id,
                           Access_Level.client))) {
                        m4_DEBUG('matches_targets: fudged ok: no attc, feat');
                        does_match = true;
                     }
                     else {
                        m4_DEBUG('matches_targets: NO: fudged: no attc, feat');
                     }
                  }
                  else
                  */
                  if (((this.target_left.matches(lhs_item))
                       && (this.target_right.matches(rhs_item)))
                      || ((this.target_left.matches(rhs_item))
                          && (this.target_right.matches(lhs_item)))) {
                     m4_DEBUG('matches_targets: ok: both targets match');
                     does_match = true;
                  }
                  else {
                     m4_DEBUG('matches_targets: NO: neither left nor right');
                  }
               }
               else if (this.target_left.is_valid) {
                  if ((this.target_left.matches(lhs_item))
                      || (this.target_left.matches(rhs_item))) {
                     m4_DEBUG('matches_targets: ok: left target matches');
                     does_match = true;
                  }
                  else {
                     m4_DEBUG('matches_targets: NO: not left');
                  }
               }
               else if (this.target_right.is_valid) {
                  if ((this.target_right.matches(lhs_item))
                      || (this.target_right.matches(rhs_item))) {
                     m4_DEBUG('matches_targets: ok: right target matches');
                     does_match = true;
                  }
                  else {
                     m4_DEBUG('matches_targets: NO: not right');
                  }
               }
               else {
                  // Both target_left and target_right are null
                  m4_DEBUG('matches_targets: link: targets are both null');
                  does_match = true;
               }
            }
         }
         return does_match;
      }

      // ***

      //
      override protected function get class_item_lookup() :Dictionary
      {
         m4_ASSERT(false); // Not called. Grac_mgr manages new_item_policies.
         return G.grac.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         m4_ASSERT(false); // Not called.
         return G.grac.all;
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         var grac:Grac_Manager = (item_agg as Grac_Manager);
         m4_ASSERT(grac !== null);
// FIXME: Don't need this fcn: move to parent
         return (super.is_item_loaded(grac)
                 || this.stack_id in grac.all);
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         m4_ASSERT(false); // Not supported from flashclient.
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_VERBOSE('init_add:', this);
         var grac:Grac_Manager = (item_agg as Grac_Manager);
         m4_ASSERT(grac !== null);
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(grac, soft_add);
         grac.new_item_policy_register(this);
      }

      //
      // FIXME Fcn. not very class-esque. Looks just like the one in
      //       Group_Membership.
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_ASSERT(existing === null);
         var policy:New_Item_Policy;
         policy = (item_agg as Grac_Manager).all[this.stack_id];
         if (policy !== null) {
            m4_DEBUG('Updating Policy:', policy);
            this.clone_item(policy);
         }
         else {
            // FIXME I think the else is okay -- it means item is deleted or
            //       invalid in working copy. Though maybe that means this --
            //       the else clause -- is where we make the conflict items!
            m4_DEBUG('Skipping Policy update:', this);
            m4_ASSERT_SOFT(false);
         }
         return policy;
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:New_Item_Policy = (to_other as New_Item_Policy);
         super.clone_once(other);
         other.group_id = this.group_id;
         other.target_item.item_type_id = this.target_item.item_type_id;
         other.target_item.item_layer = this.target_item.item_layer;
         other.target_left.item_type_id = this.target_left.item_type_id;
         other.target_left.item_stack_id = this.target_left.item_stack_id;
         other.target_left.min_access_id = this.target_left.min_access_id;
         other.target_right.item_type_id = this.target_right.item_type_id;
         other.target_right.item_stack_id = this.target_right.item_stack_id;
         other.target_right.min_access_id = this.target_right.min_access_id;
         other.processing_order = this.processing_order;
         other.stop_on_match = this.stop_on_match;

//         other.new_item_rights.group_id
//            = this.new_item_rights.group_id;
//         other.new_item_rights.nip_style
//            = this.new_item_rights.nip_style;
//         other.new_item_rights.super_acl
//            = this.new_item_rights.super_acl;
         other.access_style_id = this.access_style_id;
         other.super_acl = this.super_acl;

      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:New_Item_Policy = (to_other as New_Item_Policy);
         super.clone_update(other, newbie);
      }

      // Use contents of XML element to init myself.
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.group_id = int(gml.@gpid);
            this.target_item.item_type_id = int(gml.@target_item_type_id);
            this.target_item.item_layer = gml.@target_item_layer;
            this.target_left.item_type_id = int(gml.@link_left_type_id);
            this.target_left.item_stack_id = int(gml.@link_left_stack_id);
            this.target_left.min_access_id = int(gml.@link_left_min_access_id);
            this.target_right.item_type_id = int(gml.@link_right_type_id);
            this.target_right.item_stack_id = int(gml.@link_right_stack_id);
            this.target_right.min_access_id
               = int(gml.@link_right_min_access_id);
            this.processing_order = int(gml.@processing_order);
            this.stop_on_match = Boolean(int(gml.@stop_on_match));
//            this.new_item_rights.group_id
//               = int(gml.@gpid);
//            // MAYBE: Really store this in New_Item_Rights? This is different
//            // than pyserver.
//            this.new_item_rights.nip_style = gml.@nip_style;
//            this.new_item_rights.super_acl = gml.@super_acl;
            this.access_style_id = int(gml.@access_style_id);
            this.super_acl = int(gml.@super_acl);
         }
         else {
            this.name_ = 'NIP Description';
            // Set anything else?
         }
         m4_DEBUG('gml_consume:', super.toString());
         m4_DEBUG('  ', this.toString());
      }

      // Return an XML element representing myself.
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         gml.setName(New_Item_Policy.class_item_type); // 'new_item_policy'
         gml.@gpid = int(this.group_id);
         gml.@target_item_type_id = int(this.target_item.item_type_id);
         gml.@target_item_layer = this.target_item.item_layer;
         gml.@link_left_type_id = int(this.target_left.item_type_id);
         gml.@link_left_stack_id = int(this.target_left.item_stack_id);
         gml.@link_left_min_access_id = int(this.target_left.min_access_id);
         gml.@link_right_type_id = int(this.target_right.item_type_id);
         gml.@link_right_stack_id = int(this.target_right.item_stack_id);
         gml.@link_right_min_access_id = int(this.target_right.min_access_id);
         gml.@processing_order = int(this.processing_order);
         gml.@stop_on_match = int(this.stop_on_match);
//         // MAYBE: Why are these in new_item_rights? In pyserver, nip_style
//         //        and super_acl are in new_item_policy.
//         gml.@nip_style = this.new_item_rights.nip_style;
//         gml.@super_acl = int(this.new_item_rights.super_acl);
         gml.@access_style_id = int(this.access_style_id);
         gml.@super_acl = int(this.super_acl);
         return gml;
      }

      // *** Developer methods

      // Both AutoComplete logs and Logging.debug use this fcn. to produce a
      // friendly name for the item
      override public function toString() :String
      {
         return (''//super.toString()
                 + this.to_string_part_i()
                 + ', '
                 + this.to_string_part_ii()
            );
      }

      public function to_string_part_i() :String
      {
         return (    'gid ' + this.group_id
                 + ', typ ' + this.target_item.item_type_id
                     + ' ('
                     + (Item_Type.is_id_valid(this.target_item.item_type_id)
                        ? Item_Type.id_to_str(this.target_item.item_type_id)
                          : '-')
                     + ')'
                 + ', lyr'
                     + ' ('
                     + (this.target_item.item_layer
                        ? this.target_item.item_layer
                          : '-')
                     + ')'
                 + ', ord ' + this.processing_order
                 + ', stop ' + (this.stop_on_match ? 't' : 'f')
            );
      }

      public function to_string_part_ii() :String
      {
         return (
                     'sty ' + this.access_style_id
                 + ', spr ' + this.super_acl
                 + ', ltd ' + this.target_left.item_type_id
                 + ', lsd ' + this.target_left.item_stack_id
                 + ', lad ' + this.target_left.min_access_id
                 + ', rtd ' + this.target_right.item_type_id
                 + ', rsd ' + this.target_right.item_stack_id
                 + ', rad ' + this.target_right.min_access_id
            );
      }

   }
}


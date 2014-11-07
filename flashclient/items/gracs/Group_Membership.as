/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.gracs {

   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   import grax.Aggregator_Base;
   import grax.Grac_Manager;
   import items.Grac_Record;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class Group_Membership extends Grac_Record {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Grp_Mmbrshp');

      // *** Mandatory attributes

      public static const class_item_type:String = 'group_membership';
      public static const class_gwis_abbrev:String = 'gmp';
      public static const class_item_type_id:int = Item_Type.GROUP_MEMBERSHIP;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:* = null;

      // *** Instance variables

      // NOTE For user and group, we redundantly store the ID and name of each.
      public var username:String;
      public var group:Group;
      public var access_level_id:int;
      public var opt_out:Boolean;

      // *** Constructor

      public function Group_Membership(xml:XML=null,
                                       rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Group_Membership = (to_other as Group_Membership);
         super.clone_once(other);
         other.username = this.username;
         other.access_level_id = this.access_level_id;
         other.opt_out = this.opt_out;
         // MAYBE: Clone the group?
         //other.group = this.group;
         other.group = (this.group.clone_item(other.group) as Group);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Group_Membership = (to_other as Group_Membership);
         super.clone_update(other, newbie);
      }

      //
      // Use contents of XML element to init myself.
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.username = gml.@username;
            this.access_level_id = gml.@alid;
            this.opt_out = Boolean(int(gml.@opt_out));
            // NOTE: Server sends group info along w/ mmbrship. This is a
            //       shortcut so we don't have to implement fetching Group
            //       data until we implement managing groups in the client.
            // FIXME: This is a little hacky: Group has a gml_consume fcn.!
            this.group = new Group();
            // FIXME: Soooo hacky.
            this.group.stack_id = int(gml.@gpid);
            this.group.version = int(gml.@group_version);
            this.group.name_ = gml.@group_name;
            this.group.description = gml.@group_desc;
            this.group.access_scope_id = int(gml.@group_scope);
            // FIXME: Need to update Group_Memberships when branch head
            //        revision changes
            m4_ASSERT(!(this.group in G.grac.groups));
         }
         else {
            this.opt_out = false;
         }
      }

      // Return an XML element representing myself.
      override public function gml_produce() :XML
      {
         var gml:XML = <group_membership />;
         gml.@username = this.username;
         gml.@gpid = int(this.group.stack_id);
         gml.@alid = int(this.access_level_id);
         gml.@opt_out = int(this.opt_out);
         return gml;
      }

      // ***

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         m4_ASSERT(false); // FIXME: flashclient Sharing widget doesn't do
                           //        'permissive' access_style yet....
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_VERBOSE('init_add:', this);
         var grac:Grac_Manager = (item_agg as Grac_Manager);
         m4_ASSERT(grac !== null);
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(grac, soft_add); // This is ... a no-op.
         m4_DEBUG('init_add:', this);
         grac.group_membership_register(this);
         //
         this.group = G.grac.group_find_or_add(this.group.stack_id,
                                               this.group);
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         // NOTE: Not calling: super.init_update(existing, item_agg);
         m4_ASSERT(existing === null);
         var group_membership:Group_Membership;
         group_membership = (item_agg as Grac_Manager).all[this.stack_id];
         if (group_membership !== null) {
            m4_DEBUG('Updating Group Membership:', group_membership);
            this.clone_item(group_membership);
         }
         else {
            m4_DEBUG('Skipping Group Membership update:', this);
            m4_ASSERT_SOFT(false);
         }
         return group_membership;
      }

      // ***

      //
      override public function toString() :String
      {
         return (//getQualifiedClassName(this)
                 super.toString()
                 + ' / unom: ' + this.username
                 + ' / opto: ' + this.opt_out
                 + ' / acl: ' + this.access_level_id
                 + ' / gp_sid: ' + this.group.stack_id
                 + ' / gp_nom: ' + this.group.name_
                 + ' / gp_dsc: ' + this.group.description
                 + ' / gp_scp: ' + this.group.access_scope);
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.gracs {

   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   import grax.Aggregator_Base;
   import items.Grac_Record;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   // CODE_COUSINS: flashclient/items/gracs/Group_Revision.py
   //               pyserver/item/grac/group_revision.py

// FIXME: Delete this class?
//        Or implement in place of whatever handles revision_get?
// See: Panel_Recent_Changes, which has an XML list of group_revision data from
// the server. It could use that list to make a bunch of these types of items.
// See also: Geosummary, which is the Geofeature and sprite representation of
// the bbox or geomsummary of the group_revision.

   public class Group_Revision extends Grac_Record {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Group_Rev');

      // *** Mandatory attributes

      public static const class_item_type:String = 'group_revision';
      public static const class_gwis_abbrev:String = 'grev';
      public static const class_item_type_id:int = Item_Type.GROUP_REVISION;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:* = null;

      // *** Instance variables

      //
      public var group_id:int = 0;
      // in Item_Versioned: public var branch_id:int = 0;
      public var revision_id:int = 0;
      public var visible_items:int = 0;
      public var is_revertable:Boolean = false;
      // FIXME?:
      public var bbox:String;
      public var geosummary:String;
      //public var geometry = elem.get('geometry')

      // *** Constructor

      public function Group_Revision(xml:XML=null,
                                     rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
         //m4_ASSERT(false); // FIXME: Delete this class? Or implement it? Hrm...
      }

      // ***

      //
      // FIXME: Consolidate class_item_lookup fcns in Item_Manager or GRAC?
      override protected function get class_item_lookup() :Dictionary
      {
         // This fcn. is only called by get counterpart_untyped(), which is
         // used when Diffing. GRAC items currently don't support diffing.
         m4_ASSERT(false);
         //return Group_Revision.all;
         return null;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         m4_ASSERT(false); // Not called.
         //return Group_Revision.all;
         return null;
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         m4_ASSERT(false);
         return false;
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_ASSERT(false);
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(item_agg, soft_add);
      }

      //
      // FIXME Fcn. not very class-esque. Looks just like the one in
      //       Group_Membership.
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_ASSERT(false);
         return null;
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Group_Revision = (to_other as Group_Revision);
         super.clone_once(other);
         other.group_id = this.group_id;
         // in Item_Versioned: branch_id
         other.revision_id = this.revision_id;
         other.visible_items = this.visible_items;
         other.is_revertable = this.is_revertable;
         // FIXME?:
         other.bbox = this.bbox;
         other.geosummary = this.geosummary;
         //other.geometry = this.geometry;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Group_Revision = (to_other as Group_Revision);
         super.clone_update(other, newbie);
      }

      // Use contents of XML element to init myself.
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.group_id = int(gml.@gpid);
            // in Item_Versioned: branch_id
            this.revision_id = int(gml.@revision_id);
            this.visible_items = int(gml.@visible_items);
            this.is_revertable = Boolean(int(gml.@is_revertable));
            // FIXME?:
            this.bbox = gml.@bbox;
            this.geosummary = gml.@geosummary;
            //this.geometry = gml.@geometry;

            this.name_ = 'Group_Revision ' + String(this.revision_id);
         }
         else {
            this.name_ = 'Invalid Group_Revision';
            // Set anything else?
         }
         m4_DEBUG('gml_consume:', super.toString());
         m4_DEBUG('  ', this.toString());
      }

      // Return an XML element representing myself.
      override public function gml_produce() :XML
      {
         m4_ASSERT(false);
         return null;
      }

   }
}


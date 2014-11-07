/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import flash.utils.Dictionary;

   import grax.Aggregator_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class Nonwiki_Item extends Item_Watcher_Shim {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Nonwiki_Itm');

      // *** Mandatory attributes

      public static const class_item_type:String = 'nonwiki_item';
      public static const class_gwis_abbrev:String = 'nwki';
      public static const class_item_type_id:int = Item_Type.NONWIKI_ITEM;

      // *** Other static variables

      // NOTE: If we implement an all lookup, search all GWIS callbacks, like
      //        views/panel_branch/Widget_Analysis_List.consume_work_items,
      //       and replace their usages of gwis_req.resp_items with lookups
      //       into this lookup.
      //public static var all:Dictionary = new Dictionary();

      // *** Constructor

      public function Nonwiki_Item(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         // Nonwiki Items are revision from rid 1 through rid_inf.
         // NOTE: We allow callers to specify rev so that these classes
         //       parallel the rest of the item classes. Also, this means
         //       G.grac.bless_new continues to work the same for Nonwiki_items
         //       as for Nonnonwiki_Items.
         m4_ASSURT((rev === null) || (rev is utils.rev_spec.Current));
         rev = new utils.rev_spec.Current();
         super(xml, rev);
      }

      // ***

      ////
      //public static function cleanup_all() :void
      //{
      //   if (Conf_Instance.recursive_item_cleanup) {
      //      for each (var nonwiki_item:Nonwiki_Item in Nonwiki_Item.all) {
      //         nonwiki_item.item_cleanup();
      //      }
      //      m4_ASSERT(Nonwiki_Item.all.length == 0);
      //   }
      //   //
      //   Nonwiki_Item.all = new Dictionary();
      //}

      // *** Getters and setters

      ////
      //override protected function get class_item_lookup() :Dictionary
      //{
      //   return Nonwiki_Item.all;
      //}

      // This fcn. would be used to update access_style_id but we don't let
      // users change permissions on nonwiki items. Nor do we have a nonwiki
      // item details panel -- these all live in a list on the Cycloplan
      // panels.
      //public static function get_class_item_lookup() :Dictionary
      //{
      //   return Nonwiki_Item.all;
      //}

      //
      override public function get actionable_at_raster() :Boolean
      {
         m4_DEBUG('actionable_at_raster: always true');
         m4_ASSERT(false);
         return true;
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         m4_ASSERT(false);
      }

      // Nonwiki_Items are always editable, at any zoom level.
      override public function get editable_at_current_zoom() :Boolean
      {
         m4_ASSERT(false);
         return true;
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         m4_ASSERT(false);
         return false;
      }

      //
      override public function get is_revisionless() :Boolean
      {
         return true;
      }

      //
      override public function is_selected() :Boolean
      {
         m4_ASSERT(false);
         return false;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         super.set_selected(s, nix, solo);
         m4_VERBOSE('set_selected: s:', s, '/ nix:', nix);
         m4_ASSERT(false); // Not actually called.../doesn't make sense.
      }

      //
      //[Bindable] public function get text_() :String
      //{
      //   return this.name_ + '';
      //}

      //
      //public function set text_(s:String) :void
      //{
      //   this.name_ = s;
      //   this.blurb_init();
      //}

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Nonwiki_Item = (to_other as Nonwiki_Item);
         super.clone_once(other);
         m4_ASSERT(false); // Not implemented...
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Nonwiki_Item = (to_other as Nonwiki_Item);
         super.clone_update(other, newbie);
         m4_ASSERT(false); // Not implemented...
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         // Nothing to see here
         super.gml_consume(gml);
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

   }
}


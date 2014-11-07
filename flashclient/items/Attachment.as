/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import flash.utils.Dictionary;
   import mx.utils.ObjectUtil;

   import grax.Aggregator_Base;
   import items.feats.Byway;
   import items.feats.Region;
   import items.feats.Terrain;
   import items.feats.Waypoint;
   import items.utils.Item_Type;
   import utils.misc.Collection;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Attachment;
   import views.panel_items.Panel_Item_Versioned;

   public class Attachment extends Item_Watcher_Shim {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Attachment');

      // *** Mandatory attributes

      public static const class_item_type:String = 'attachment';
      public static const class_gwis_abbrev:String = 'attc';
      public static const class_item_type_id:int = Item_Type.ATTACHMENT;

      // *** Other static variables

      // This is a lookup of all attachments by stack_id. We use the stack id
      // and not the system id so we can match items from the server which may
      // differ in version.
      public static var all:Dictionary = new Dictionary();

      // *** Instance variables

      // The Panel_Item_Attachment panel.
      // The derived classes declare the derived class of this.
      //  protected var attachment_panel_:Panel_Item_Attachment;

      // Attachments are descriptive, textual, non-geometric details about some
      // other item, generally a Geofeature. The meat of the attachment is
      // stored in Item_Versioned.name_, like a tag's name or an attachment's
      // comments. The blurb and blurb_title are compact representations of
      // that meat.
      [Bindable] public var blurb_title:String; // first line of blurb (to nl)
      [Bindable] public var blurb:String; // super.name_, up to blurb_length
      protected var blurb_length:int; // maximum length of the blurb

      // Some attachments know how many geofeatures to which they're linked.
      // E.g., in the route-finding dialog, alongside each tag is the number of
      // byways to which is applies.
      public var feat_links_count:Dictionary = new Dictionary();

      // When drawing the map, some geofeatures are highlighted specially
      // depending on the types of attachments attached to them. This is
      // currently true for Annotations and Posts.
      public var feat_links_exist:Dictionary = new Dictionary();

      // *** Constructor

      public function Attachment(xml:XML=null,
                                 rev:utils.rev_spec.Base=null,
                                 len:int=256)
      {
         for each (var feat_type:Class in
                   [Byway, Waypoint, Region, Terrain,]) {
            this.feat_links_exist[feat_type] = false;
         }
         this.blurb_length = len;
         super(xml, rev);
      }

      // *** Public Static methods

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var attachment:Attachment in Attachment.all) {
               attachment.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Attachment.all = new Dictionary();
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Attachment = (to_other as Attachment);
         super.clone_once(other);

         // Clear things that we want set in clone_update, which'll
         // be called next.
         other.feat_links_count = null;
         other.feat_links_exist = null;
      }

      //
      override protected function clone_update( // on-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Attachment = (to_other as Attachment);
         super.clone_update(other, newbie);

         //var lookup_key:Object;
         //var feat_class:Class;
         if ((other.feat_links_count === null)
             || (Collection.dict_is_empty(other.feat_links_count))) {
            // See comments in Route.as; not using ObjectUtil.copy().
            other.feat_links_count = Collection.dict_copy(
                                       this.feat_links_count);
            // The following is a non-destructive deep copy-ish operation.
            // That is, we're not emptying the existing Dictionaries.
            // other.feat_links_count = new Dictionary();
            // for (lookup_key in this.feat_links_count) {
            //    feat_class = (lookup_key as Class);
            //    other.feat_links_count[feat_class]
            //       = this.feat_links_count[feat_class];
            // }
         }
         if ((other.feat_links_exist === null)
             || (Collection.dict_is_empty(other.feat_links_exist))) {
            // See comments in Route.as; not using ObjectUtil.copy().
            other.feat_links_exist = Collection.dict_copy(
                                       this.feat_links_exist);
            // other.feat_links_exist = new Dictionary();
            // for (lookup_key in this.feat_links_exist) {
            //    feat_class = (lookup_key as Class);
            //    other.feat_links_exist[feat_class]
            //       = this.feat_links_exist[feat_class];
            // }
         }

         this.blurb_init();
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         const feat_types:Array = [Byway, Waypoint, Region, Terrain,];
         super.gml_consume(gml);
         if (gml !== null) {
            this.feat_links_exist[Geofeature] = false;
            for each (var feat_type:Class in feat_types) {
               // MAGIC NAME: The gml names is, e.g., count_byways, so include
               //             the 's'.
               var xml_attr:String = '@count_' +
                  Introspect.class_name(feat_type, true).toLowerCase() + 's';
               //m4_VERBOSE('gml_consume: xml_attr:', xml_attr);
               this.feat_links_count[feat_type] = int(gml[xml_attr]);
               this.feat_links_exist[feat_type] =
                  (this.feat_links_count[feat_type] > 0);
               // Also set [Geofeature] key in feat_links_exist
               if (this.feat_links_exist[feat_type]) {
                  this.feat_links_exist[Geofeature] = true;
               }
            }
         }
         // Set the attachment blurb, based on its name.
         //
         // NOTE I tried calling this:
         //
         //         this.text_ = this.name_;
         //
         //      But it's a no-op. Apparently, for getters and setters, when
         //      you set a value, Flash first calls the getter and compares it
         //      to want you want to set the value to. If they're one and the
         //      same, Flash doesn't bother calling your setter!
         //
         //      So we use a helper fcn. to config the blurb.
         this.blurb_init();
      }

      // *** Getters and setters

      //
      public function get attachment_panel() :Panel_Item_Attachment
      {
         m4_ASSERT(false); // Abstract.
         return null;
      }

      //
      public function set attachment_panel(
         attachment_panel:Panel_Item_Attachment)
            :void
      {
         m4_ASSERT(false); // Abstract/not called.
      }

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Attachment.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Attachment.all;
      }

      // Attachments are always editable, at any zoom level.
      override public function get editable_at_current_zoom() :Boolean
      {
         return true;
      }

      // Selected is used when the user selects the item in the map, which, for
      // attachments, generally happens from the Geofeature details panel,
      // i.e., when the user clicks the "more" button for a note.

      // Only one Attachment can be selected at once, so just check with the
      // Item_Manager. We also run a few asserts to verify our other logic.
      //
      override public function is_selected() :Boolean
      {
         var is_selected:Boolean = false;
         // COUPLING: But who cares. Or is this totally acceptable? In
         // MVC, the model usually doesn't know or care about the view.
         // But, here, we check the view to know if we're selected. But
         // what is 'selected'? It's a view concept, not a model concept
         // -- an item is considered selected if its panel is the active
         // side_panel. So this is an absolutely good place for this code.
         var attc_panel:Panel_Item_Attachment;
         attc_panel = G.panel_mgr.effectively_active_panel
                      as Panel_Item_Attachment;
         if (attc_panel !== null) {
            // Check that the attachment panel exists first. If we called
            // this.attachment_panel we'd inadvertently create a new panel
            // that we might not need.
            if (this.is_attachment_panel_set()) {
               if (attc_panel === this.attachment_panel) {
                  m4_ASSERT(this.attachment_panel.attc === this);
                  is_selected = true;
               }
               // else, another item's attachment panel is active.
            }
            // else, we've just been created, and no one has asked for our
            //       panel yet, so we don't have a panel, and we're not going
            //       to create one.
         }
         // else, not a Panel_Item_Attachment, so this attc not selected.
         return is_selected;
      }

      // When an Attachment is being edited, we highlight all the
      // geofeatures to which it is attached. (And note that 'highlight'
      // means something other than 'select' -- e.g., you might have a
      // bunch of selected items on the map, and rolling over one of the
      // notes in the note widget highlights all of the items on the map
      // that have that note applied, but the selection remains the same.)
      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         super.set_selected(s, nix, solo);

         m4_VERBOSE('set_selected: s:', s, '/ nix:', nix);

         var active_panel:Detail_Panel_Base;
         active_panel = G.panel_mgr.effectively_active_panel;

         m4_DEBUG3('set selected: active_panel:',
                   ((active_panel !== null)
                    ? active_panel.class_name_tail : 'null'));
         m4_DEBUG3('set selected: active_panel:',
                   ((this.attachment_panel !== null)
                    ? this.attachment_panel.class_name_tail : 'null'));

         if (s) {
            // There's nothing to do here; derived classes do all the work.
            // Also, the way the code works, if we're being marked selected,
            // our panel is either already the effectively_active_panel, or
            // its the geofeature panel that owns the control that references
            // this attachment.
            // This assert is pretty pointless...
            m4_ASSERT_SOFT((!this.is_attachment_panel_set())
                           || (active_panel === null)
                           || (active_panel === this.attachment_panel)
                           );
                      // If the active_panel is Geofeature and we're selecting
                      // an Attachment, we'll inadvertently remove the
                      // geofeature from the attachment panel?
                      //   || (active_panel is Panel_Item_Geofeature)
            G.sl.event('ui/select/attachment', {ssid: this.system_id});
         }
         else {
            // Being deselected.
            // We're also triggered by 'undo', if you undo making a
            // new attachment, we'll set selected = false... so item panel
            // might not be active, but item should be undirty fresh.
         }
      }

      //
      // EXPLAINED: This is 'text_' and not just 'text' because many MXML
      // components already have a 'text' attribute. So we make ours unique.
      [Bindable] public function get text_() :String
      {
         return this.name_ + '';
      }

      // Sets the blurb, which is the name of the item or a truncated version
      // of it with post-fixed ellipses.
      public function set text_(s:String) :void
      {
         this.name_ = s;
         this.blurb_init();
      }

      // *** Instance methods

      //
      protected function blurb_init() :void
      {
         if (this.name_ === null) {
            this.blurb_title = '';
            this.blurb = '';
         }
         else {
            // The blurb title is just the first line of text.
            this.blurb_title = this.name_.replace(/(\r.*$)/s, '');
            // The blurb is a (possibly) truncated snippet of the text.
            if (this.name_.length < this.blurb_length) {
               this.blurb = this.name_;
            }
            else {
               this.blurb = this.name_.substr(0, this.blurb_length) + ' ...';
            }
         }
      }

      //
      public function is_attachment_panel_set() :Boolean
      {
         m4_ASSERT(false); // Abstract.
         return false;
      }

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         m4_VERBOSE('item_cleanup:', this, '/ i:', i);
         m4_ASSERT(i == -1);

         super.item_cleanup(i, skip_delete);

         //// Remove link_values
         //var links:Set_UUID;
         //links = Link_Value.item_get_link_values(this);
         //for each (var o:Link_Value in links) {
         //   m4_DEBUG('item_cleanup: removing link');
         //   o.item_cleanup();
         //}

         // Remove self
         if (!skip_delete) {
            delete Attachment.all[this.stack_id];
         }
      }

      //
      [Bindable] public function get link_count_byway() :int
      {
         return this.feat_links_count[Byway];
      }

      // The set is necessary to make the get bindable.
      // But don't call this fcn.
      public function set link_count_byway(ignored:int) :void
      {
         m4_ASSERT(false);
      }

      //
      public function link_value_set(link_value:Link_Value, is_set:Boolean)
         :void
      {
         ; // No-op.
      }

      /*
      //
      //[Bindable]
      public function get link_count_post() :int
      {
         return this.feat_links_count[Post];
      }
      */

      //
      public function prepare_and_activate_panel() :void
      {
         m4_DEBUG('prep_n_activate_panel: attachment:', this);

         // Its panel. This might already be a panel with a tab in the
         // side_panel_tabs, or it might be a newly created panel.
         var attc_panel:Panel_Item_Attachment = this.attachment_panel;
         m4_DEBUG('prep_n_activate_panel: attc_panel:', attc_panel);
         m4_ASSERT(attc_panel !== null);

         var dpanel:Detail_Panel_Base = G.panel_mgr.effectively_active_panel;
         m4_DEBUG('prep_n_activate_panel: dpanel:', dpanel);

         if (dpanel === null) {
            m4_WARNING('WARNING?: effectively_active_panel: null');
         }
         else {
            // Clear the active panel before deselecting, otherwise any
            // geofeatures that are selected will think they're being
            // removed from the panel.
            var force_reset:Boolean = false;
            dpanel.panel_selection_clear(force_reset/*=false*/);
         }

         // Wire the annotation and make its panel the active panel.
         G.panel_mgr.panel_activate(attc_panel)
      }

      // *** Item Init/Update fcns.

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         /*
         if (d) {
            delete Attachment.all[this.stack_id];
         }
         else {
            if (this !== Attachment.all[this.stack_id]) {
               if (this.stack_id in Attachment.all) {
                  m4_WARNING2('set deleted: overwrite:',
                              Attachment.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Attachment.all[this.stack_id] = this;
            }
         }
         */
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         //m4_VERBOSE('init_add:', this);
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(item_agg, soft_add);
         if (this !== Attachment.all[this.stack_id]) {
            if (this.stack_id in Attachment.all) {
               m4_WARNING2('init_add: overwrite:',
                           Attachment.all[this.stack_id]);
               m4_WARNING('               with:', this);
               m4_WARNING(Introspect.stack_trace());
            }
            // BUG nnnn: Move all 'all' to item mgr.
            Attachment.all[this.stack_id] = this;
         }
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_VERBOSE('init_update:', this);
         var lookup_key:Object;
         var feat_class:Class;
         // This would fail for Tag.as but tags are only checked out when the
         // branch changes. Tags use Tag.all_names, not Attachment.all... but
         // maybe we should just stick tags in Attachment.all, anyway?
         var attc:Attachment = Attachment.all[this.stack_id];
         if (attc !== null) {
            // BUG nnnn: I [lb] made a new note and attached items, then
            // deleted, undid all the way, then redid until before delete, then
            // deleted again...
            // 2014.04.25: How old is last Bug nnnn? Yanjie may have fixed it.
            if ((existing !== null) && (existing !== attc)) {
               m4_ERROR('init_update: confliction: existing:', existing);
               m4_ERROR('init_update: confliction: attc:', attc);
            }
            m4_ASSERT((existing === null) || (existing === attc));
            // clone_item will call clone_update and not clone_once because of attc.
            this.clone_item(attc);
            /*
            super.init_update(attc, item_agg);
            // The following is a non-destructive deep copy-ish operation.
            // That is, we're not emptying the existing Dictionaries.
            for (lookup_key in this.feat_links_count) {
               feat_class = (lookup_key as Class);
               attc.feat_links_count[feat_class]
                  = this.feat_links_count[feat_class];
            }
            for (lookup_key in this.feat_links_exist) {
               feat_class = (lookup_key as Class);
               attc.feat_links_exist[feat_class]
                  = this.feat_links_exist[feat_class];
            }
            */
         }
         else {
            m4_WARNING('init_update: item not found in Attachment.all:', this);
            m4_ASSERT_SOFT(false);
         }
         return attc;
      }

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         this.update_item_all_lookup(Attachment, commit_info);
         super.update_item_committed(commit_info);
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         return ((super.is_item_loaded(item_agg))
                 || (this.stack_id in Attachment.all));
      }

   }
}


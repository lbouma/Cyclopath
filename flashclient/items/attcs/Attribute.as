/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.attcs {

   import flash.utils.Dictionary;
   import mx.collections.ArrayCollection;

   import grax.Aggregator_Base;
   import items.Attachment;
   import items.Item_Revisioned;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Objutil;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.panel_items.Panel_Item_Attachment;
   import views.panel_items.Panel_Item_Attribute;

   public class Attribute extends Attachment {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Attribute');

      // *** Reasonable defaults (MAGIC Numbers)

      // NOTE: If we don't specify these, the stepper is very wide when it's
      //       rendered and causes the side panel to show a horizontal
      //       scrollbar.
      //       FIXME: Can you set a maxWidth instead?

      protected static const integer_value_minimum:Number = -1;
      protected static const integer_value_maximum:Number = 1000;
      protected static const integer_value_stepsize:Number = 1;

      // *** Mandatory attributes

      public static const class_item_type:String = 'attribute';
      public static const class_gwis_abbrev:String = 'attr';
      public static const class_item_type_id:int = Item_Type.ATTRIBUTE;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Attribute;

      // *** Other static variables

      // Attributes can have the same names, so these are stored by ID
      public static var all:Dictionary = new Dictionary();

      // However, certain "special" Attributes have internal names which
      // the client knows about, like one_way, and other basic Byway
      // attributes.
      public static var all_named:Dictionary;

      // NOTE We use two lookups -- whose orders deliberatly coincide -- to
      //      maintain a list of acceptable value types. If you ever get
      //      ambitious, consider writing a wrapper around the second lookup so
      //      you can do away with the first (the wrapper class would override
      //      Array's indexOf function to handle an array of objects).
      //      See also Item_Versioned.as; there's a similar dual-lookup there.
      //      By the way, we need the latter lookup to implement our dropdown
      //      control: the id represents the dropdown index, which we use to
      //      get at the label. The database itself just stores the string.
      protected static var values_valid_types_names:Array =
         [
         'integer',
         'text',
         'boolean',
         'real/float',
         //'date',
         //'binary',
         ];
      // BUG 2416: Figure out and implement remaining value types.
      public static var values_valid_types_lookup:Array =
         [
         // SYNC_ME: Search: Link_Value table.
         { id: 0, label: 'integer'},
         { id: 1, label: 'text'},
         { id: 2, label: 'boolean'},
         { id: 3, label: 'real'},
         //{ id: 4, label: 'date'},
         //{ id: 5, label: 'binary'},
         ];

      // By design, attributes can be linked to any other item in the system,
      // but for now they can only apply to geofeatures. This lookup indicates
      // to what items an attribute can be applied.
      public static var applies_to_items_lookup:Array =
         [
         // SYNC_ME: Search: Item_Type table.
         //    NOTE: Leaving things commented-out just for reference
         //    NOTE: Not ordered by id but by weigthedness, i.e., what's going
         //          to be used more goes up top.
         { id:  2, label: 'all item types'}, // i.e., 'geofeatures'
         { id:  7, label: 'blocks'},
         { id: 14, label: 'points'}, // i.e., 'waypoints'
         { id:  9, label: 'regions'},
         //{ id:  1, label: 'attachment'},
         //{ id:  3, label: 'link_value'},
         //{ id:  4, label: 'annotation'},
         //{ id:  5, label: 'attribute'},
         //{ id:  6, label: 'maps'}, // i.e., 'branches'
         //{ id:  7, label: 'byway'},
         //{ id:  8, label: 'posts'},
         //{ id: 10, label: 'routes'},
         //{ id: 11, label: 'tags'},
         { id: 12, label: 'terrain'},
         //{ id: 13, label: 'thread'},
         //{ id: 15, label: 'workhint'},
         //{ id: 16, label: 'group_membership'},
         //{ id: 17, label: 'new_item_policy'},
         //{ id: 18, label: 'group'},
         //{ id: 19, label: 'route_step'},
         ////{ id: 20, label: 'group_revision'},
         //{ id: 21, label: 'track'},
         //{ id: 22, label: 'track_point'},
         //{ id: 23, label: 'addy_coordinate'},
         //{ id: 24, label: 'addy_geocode'},
         //{ id: 25, label: 'item_name'},
         //{ id: 26, label: 'grac_error'},
         //{ id: 27, label: 'work_item'},
         //{ id: 28, label: 'nonwiki_item'},
         //{ id: 29, label: 'merge_job'},
         //{ id: 30, label: 'route_analysis_job'},
         //{ id: 31, label: 'job_base'},
         //{ id: 32, label: 'work_item_step'},
         //{ id: 33, label: 'merge_job_download'},
         //{ id: 34, label: 'group_item_access'},
         //// DEPREACTED: item_watcher is replaced by private link_attributes.
         ////  { id: 35, label: 'item_watcher'},
         ////  { id: 36, label: 'item_watcher_change'},
         //{ id: 37, label: 'item_event_alert'},
         //// DEPRECATED: byway_node is replaced by node_endpoint.
         ////  { id: 38, label: 'byway_node'},
         //// DEPRECATED: route_waypoint is renamed to route_stop.
         ////  { id: 39, label: 'route_waypoint'},
         //{ id: 40, label: 'route_analysis_job_download'},
         //{ id: 41, label: 'branch_conflict'},
         //{ id: 42, label: 'merge_export_job'},
         //{ id: 43, label: 'merge_import_job'},
         //{ id: 44, label: 'node_endpoint'},
         //{ id: 45, label: 'node_byway'},
         //{ id: 46, label: 'node_traverse'},
         //{ id: 47, label: 'route_stop'},
         //// 2013.04.04: For fetching basic item info (like access_style_id).
         //// No: { id: 48, label: 'item_stack'},
         //// No: { id: 49, label: 'item_versioned'},
         //{ id: 50, label: 'item_user_access'},
         //// No: { id: 51, label: 'item_user_watching'},
         //{ id: 52, label: 'link_geofeature'},
         //{ id: 53, label: 'conflation_job'},
         //{ id: 54, label: 'link_post'},
         //{ id: 55, label: 'link_attribute'},
         //{ id: 56, label: 'landmark'},
         //{ id: 57, label: 'landmark_t'},
         //{ id: 58, label: 'landmark_other'},
         //{ id: 59, label: 'item_revisionless'},
         ]; //

      // *** Instance variables

      // The Panel_Item_Attribute panel.
      protected var attribute_panel_:Panel_Item_Attribute;

      [Bindable] public var value_internal_name:String;
      [Bindable] public var spf_field_name:String;
      // The Link_Value member holding our data, i.e., 'value_boolean',
      // 'value_integer', etc.
      protected var value_type_:String;
      protected var value_type_id_:int;
      [Bindable] public var value_hints:String;
      [Bindable] public var value_units:String;
      // The following restraints apply to numerical values
      [Bindable] public var value_minimum:Number = NaN;
      [Bindable] public var value_maximum:Number = NaN;
      [Bindable] public var value_stepsize:Number = NaN; // Applies to integer
      // Users can set the ordering of the Attributes in the display
      [Bindable] public var gui_sortrank_:int;
      // The user can choose that the attribute apply to all item types, or
      // just to a specific item type (i.e., all of the original attributes
      // only apply to byways, like one way, shoulder width, etc.)
      [Bindable] public var applies_to_type_id:int;
      // The client can be coded to display a custom control for certain
      // attributes (by "can be coded", I mean by a developer, not by an
      // end-user). In the beginning, most attributes use a standard stepper
      // control, but the one_way control is custom-coded.
      [Bindable] public var uses_custom_control:Boolean;
      // BUG 2409: value_restraints isn't well-defined; what exactly is it?
      [Bindable] public var value_restraints:String;
      [Bindable] public var allow_multiple_values:Boolean;

      // The user is not allowed to change the value_type or applies_to_type_id
      // once the attribute is saved or has been used at least once.
      public var not_so_fresh:Boolean = false;

      // *** Constructor

      public function Attribute(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
         m4_DEBUG('ctor:', this.toString_Verbose());
      }

      // *** Instance methods

      //
      override public function is_attachment_panel_set() :Boolean
      {
         return (this.attribute_panel_ !== null);
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Attribute = (to_other as Attribute);
         super.clone_once(other);
         // Skipping: attribute_panel_
         other.value_internal_name = this.value_internal_name;
         other.spf_field_name = this.spf_field_name;
         // other.value_type_ = this.value_type_;
         // other.value_type_id_ = this.value_type_id_;
         other.value_type = this.value_type;
         other.value_hints = this.value_hints;
         other.value_units = this.value_units;
         other.value_minimum = this.value_minimum;
         other.value_maximum = this.value_maximum;
         other.value_stepsize = this.value_stepsize;
         other.gui_sortrank_ = this.gui_sortrank_;
         other.applies_to_type_id = this.applies_to_type_id;
         other.uses_custom_control = this.uses_custom_control;
         other.value_restraints = this.value_restraints;
         other.allow_multiple_values = this.allow_multiple_values;
         // Skipping: other.not_so_fresh = this.not_so_fresh;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Attribute = (to_other as Attribute);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            m4_VERBOSE('gml_consume: gml:', gml);
            this.value_internal_name = gml.@value_internal_name;
            this.spf_field_name = gml.@spf_field_name;
            this.value_type = gml.@value_type; // This throws on bad type
            m4_VERBOSE('gml_consume: this.value_type:', this.value_type);
            this.value_hints = gml.@value_hints;
            this.value_units = gml.@value_units;
            // FIXME: These are not always specified. Is there a way to see if
            //        they exist in the XML or not?
            this.value_minimum = int(gml.@value_minimum);
            this.value_maximum = int(gml.@value_maximum);
            this.value_stepsize = int(gml.@value_stepsize);
            this.gui_sortrank = int(gml.@gui_sortrank);
            this.applies_to_type_id = int(gml.@applies_to_type_id);
            this.uses_custom_control = Boolean(int(gml.@uses_custom_control));
            this.value_restraints = gml.@value_restraints;
            // FIXME Why the name change? Choose one...
            this.allow_multiple_values = Boolean(int(gml.@multiple_allowed));
            if ((this.value_minimum == 0)
                && (this.value_maximum == 0)
                && (this.value_stepsize == 0)) {
               //this.value_minimum = Attribute.integer_value_minimum;
               //this.value_maximum = Attribute.integer_value_maximum;
               //this.value_stepsize = Attribute.integer_value_stepsize;
               this.value_minimum = NaN;
               this.value_maximum = NaN;
               this.value_stepsize = NaN;
            }
         }
         else {
            m4_VERBOSE('gml_consume: defaults');
            // BUG 2418: Display tip in edit control if it's == ''. When user
            //           clicks in edit control, clear it. Don't store tip as
            //           actual value.
            this.name_ = ''; // BUG 2418: 'Enter name here'
            this.value_internal_name = null;
            this.spf_field_name = null;
            this.value_type = 'integer';
            this.value_hints = ''; // BUG 2418: 'Describe field/attribute here'
            this.value_units = ''; // BUG 2418: 'E.g., 'feet', 'lanes', etc.'
            this.value_minimum = Attribute.integer_value_minimum;
            this.value_maximum = Attribute.integer_value_maximum;
            this.value_stepsize = Attribute.integer_value_stepsize;

//FIXME:
            //this.gui_sortrank =                 FIXME Must be unique? Set it?
            //                                    FIXME: Do not enforce unique,
            //                                           allow same values...

//FIXME:
         //this.applies_to_type_id = Item_Type.str_to_id('geofeature');
// FIXME: This doesn't work?:
         this.applies_to_type_id = Item_Type.str_to_id('byway');

            this.uses_custom_control = false;
            this.value_restraints = null;
            this.allow_multiple_values = false;
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();

         gml.setName(Attribute.class_item_type); // 'attribute'
         // NO: gml.@value_internal_name = this.value_internal_name;
         gml.@spf_field_name = this.spf_field_name;
         gml.@value_type = this.value_type;
         gml.@value_hints = this.value_hints;
         gml.@value_units = this.value_units;
         gml.@value_minimum = int(this.value_minimum);
         gml.@value_maximum = int(this.value_maximum);
         gml.@value_stepsize = int(this.value_stepsize);
         gml.@gui_sortrank = int(this.gui_sortrank);
         gml.@applies_to_type_id = int(this.applies_to_type_id);
         // No: gml.@uses_custom_control = int(this.uses_custom_control);
         gml.@value_restraints = this.value_restraints;
         gml.@multiple_allowed = int(this.allow_multiple_values);
         return gml;
      }

      //
      // SIMILAR_TO: Tag.as
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         m4_ASSERT(i == -1);
         super.item_cleanup(i, skip_delete);
         if (!skip_delete) {
// FIXME If removing from all_named, need to reinsert; see Map_Canvas reset
            delete Attribute.all[this.stack_id];
            delete Attribute.all_named[this.value_internal_name];
         }
      }

      //
      public function value_get(lv:Link_Value) :*
      {
         return lv['value_' + this.value_type];
      }

      //
      public function value_set(lv:Link_Value, value:*) :void
      {
         lv['value_' + this.value_type] = value;
         // 2013.05.28: Also update the feature's attrs.
         //             This is a little hacky/forceful.
         if (lv.feat !== null) {
            m4_DEBUG3('value_set: update .attrs: feat:', lv.feat.name_,
                      '/ attr:', this.value_internal_name,
                      '/ value:', value);
            lv.feat.attrs[this.value_internal_name] = value;
         }
      }

      // *** Item Init/Update fcns.

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         /*
         if (d) {
            delete Attribute.all[this.stack_id];
         }
         else {
            if (this !== Attribute.all[this.stack_id]) {
               if (this.stack_id in Attribute.all) {
                  m4_WARNING2('set deleted: overwrite:',
                              Attribute.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Attribute.all[this.stack_id] = this;
            }
         }
         */
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_VERBOSE('init_add:', this);
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(item_agg, soft_add);
         if (this !== Attribute.all[this.stack_id]) {
            if (this.stack_id in Attribute.all) {
               m4_WARNING2('init_add: overwrite:',
                           Attribute.all[this.stack_id]);
               m4_WARNING('               with:', this);
               m4_WARNING(Introspect.stack_trace());
            }
            Attribute.all[this.stack_id] = this;
         }
         if ((this.value_internal_name !== null)
             && (this.value_internal_name != '')) {
            //m4_DEBUG('init_add:', this);
            Attribute.all_named[this.value_internal_name] = this;
         }
// FIXME Redraw one-ways?
/*/
         if (this.pref_get('avoid', true) == true) {
            for each (b in Link_Value.items_for_attachment(this, Byway)) {
               b.draw();
            }
         }
/*/
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         // NOTE: Not calling: super.init_update(existing, item_agg);
         m4_ASSERT(existing === null);
         var attr:Attribute = Attribute.all[this.stack_id];
         if (attr !== null) {
            m4_VERBOSE('Updating Attribute:', this);
            // This item is also in the parent's lookup.
            m4_ASSERT(this.stack_id in Attachment.all);
            // "Clone" the attribute: apply the new variables from the server,
            // in this, to the variables in our existing item, attr, so we
            // don't have to rewire the lookups. Note that we don't updating
            // anything that hasn't changed; this won't touch edited values.
            // clone will call clone_update and not clone_once because of attr.
            this.clone_item(attr);
         }
         else {
            // else, invalid or deleted but not in the lookup, so ignore
            m4_ASSERT_SOFT(false);
         }
         return attr;
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         // NOTE If the item's loaded, it's in Attachment.all, so the check on
         //      Attribute.all and Attribute.all_named is unnecessary.
         return (super.is_item_loaded(item_agg)
                 || this.stack_id in Attribute.all
                 || this.value_internal_name in Attribute.all_named);
      }

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         this.update_item_all_lookup(Attribute, commit_info);
         super.update_item_committed(commit_info);
      }

      // *** Base class getters and setters

      //
      override public function get actionable_at_raster() :Boolean
      {
         return true;
      }

      //
      override public function get attachment_panel() :Panel_Item_Attachment
      {
         return attribute_panel;
      }

      //
      override public function set attachment_panel(
         attachment_panel:Panel_Item_Attachment)
            :void
      {
         m4_ASSERT(false); // Not called.
         this.attribute_panel = (attachment_panel as Panel_Item_Attribute);
      }

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Attribute.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Attribute.all;
      }

      //
      override public function get discardable() :Boolean
      {
         // All attribute definitions are always resident.
         return false;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         // This is called from Geofeatures_Attachment_Add.undo to
         // "cleanup the no-longer wanted attachment", when setting
         // selected = false during undo... but Attachment.selected
         // is pretty much a no-op, so none of this matters.
         //   m4_WARNING('set selected: no one calls this, do they?');
         //   m4_WARNING(Introspect.stack_trace());
         super.set_selected(s, nix, solo);
      }

      //
      override public function link_value_set(link_value:Link_Value,
                                              is_set:Boolean) :void
      {
         // Skipping: super.link_value_set(link_value);
         if (this.fresh) {
            if (is_set) {
               this.not_so_fresh = true;
            }
            else {
               // Reset the value if no not-deleted links exist.
               var gfs:Array = Link_Value.items_for_attachment_by_id(
                                                      this.stack_id);
               this.not_so_fresh = Boolean(gfs.length > 0);
            }
         }

         if (link_value.feat !== null) {
            if (is_set) {
               //m4_DEBUG(' attr.name_:', this.name_);
               //m4_DEBUG2(' this.value_internal_name:',
               //          this.value_internal_name);
               //m4_DEBUG2(' link_value.feat:',
               //          link_value.feat);
               //m4_DEBUG2(' link_value.feat.attrs:',
               //          link_value.feat.attrs);
               var attr_val:* = this.value_get(link_value);
               //m4_DEBUG(' attr_val:', attr_val);
               link_value.feat.attrs[this.value_internal_name] = attr_val;
               //m4_DEBUG2('_lval_cache: link_value.feat.attrs[]:',
               //          link_value.feat.attrs[this.value_internal_name]);
            }
            else if (this.value_internal_name in link_value.feat.attrs) {
               delete link_value.feat.attrs[this.value_internal_name];
            }
         }
         else {
            m4_DEBUG('link_value_set: link_value:', link_value);
            m4_ASSERT_SOFT(   (link_value.attr !== null)
                           || (link_value.thread !== null));
         }
      }

      // *** Getters and setters

      //
      public function get attribute_panel() :Panel_Item_Attribute
      {
         if (this.attribute_panel_ === null) {
            this.attribute_panel_ = (G.item_mgr.item_panel_create(this)
                                     as Panel_Item_Attribute);
            this.attribute_panel_.attribute = this;
         }
         return this.attribute_panel_;
      }

      //
      public function set attribute_panel(attribute_panel:Panel_Item_Attribute)
         :void
      {
         if (this.attribute_panel_ !== null) {
            this.attribute_panel_.attribute = null;
         }
         this.attribute_panel_ = attribute_panel;
         if (this.attribute_panel_ !== null) {
            this.attribute_panel_.attribute = this;
         }
      }

      //
      public function get gui_sortrank() :int
      {
         return this.gui_sortrank_;
      }

      // FIXME: Rename in sql/pyserver/flashclient, to sortweight
      public function set gui_sortrank(new_sortrank:int) :void
      {
         this.gui_sortrank_ = new_sortrank;
         // MAYBE: +/- keys seem silly because of private attrs.
         //        What you really want is a weight, not a rank.
         // MAYBE: Do we need to care that it's >= 1?
         //        Seems like it shouldn't matter.
         if (this.gui_sortrank_ < 1) {
            this.gui_sortrank_ = 99; // Rank it low...
         }
      }

      //
      [Bindable] public function get value_type() :String
      {
         m4_VERBOSE2('get value_type:', this.value_type_id_,
                     '/', this.value_type_);
         return this.value_type_;
      }

      //
      public function set value_type(type_str:String) :void
      {
         this.value_type_ = type_str;
         this.value_type_id_ = Attribute.values_valid_types_names
                                 .indexOf(type_str);
         m4_ASSERT(this.value_type_id_ != -1);
         m4_VERBOSE2('set value_type:', this.value_type_id_,
                     '/', this.value_type_);
      }

      //
      [Bindable] public function get value_type_id() :int
      {
         m4_VERBOSE2('get value_type_id:', this.value_type_id_,
                     '/', this.value_type_);
         return this.value_type_id_;
      }

      //
      public function set value_type_id(idx:int) :void
      {
         this.value_type_id_ = idx;
         this.value_type_ = Attribute.values_valid_types_names[idx];
         m4_VERBOSE2('set value_type_id:', this.value_type_id_,
                     '/', this.value_type_);
      }

      // *** Static class methods

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var attribute:Attribute in Attribute.all) {
               attribute.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Attribute.all = new Dictionary();
         Attribute.all_named = new Dictionary();
      }

      // NOTE: The consensus here is the links' value_*, not the attribute
      //       definition name.
      // SIMILAR_TO: Objutil.consensus
      public static function consensus(itms:*, // Set, Set_UUID, Dictionary...
                                       attr:Attribute,
                                       default_:*=undefined,
                                       on_empty:*=undefined) :*
      {
         // This fcn. used to just get all the link_values between the set of
         // items and the attribute, but then we miss any items whose
         // link_values have not been loaded -- so really we want to iterate
         // through the collection of items and check for a link_value or for
         // its attrs collection.
         var consensus:* = on_empty;
         var item:Item_User_Access;
         //m4_DEBUG('consensus: checking this many itms:', itms.length);
         var is_first:Boolean = true;
         for each (item in itms) {
            if (is_first) {
               consensus = Attribute.consensus_one(
                     item, attr, default_, on_empty);
               //m4_DEBUG(' .. first item value:', consensus);
               is_first = false;
            }
            else {
               var next_val:* = Attribute.consensus_one(
                           item, attr, default_, on_empty);
               if (next_val != consensus) {
                  //m4_DEBUG(' .. different item value:', next_val);
                  consensus = default_;
                  break;
               }
            }
         }
         //m4_DEBUG('consensus: returning:', consensus);
         return consensus;
      }

      //
      protected static function consensus_one(item:Item_User_Access,
                                              attr:Attribute,
                                              default_:*=undefined,
                                              on_empty:*=undefined) :*
      {
         //m4_DEBUG('consensus_one: item:', item);
         m4_ASSERT(item !== null);

         var consensus:* = default_;

         var attrs:Set_UUID = new Set_UUID([attr,]);
         var itms:Set_UUID = new Set_UUID([item,]);
         var lval_set:Set_UUID = Link_Value.items_get_link_values(attrs, itms);
         //m4_DEBUG('consensus_one: lval_set:', lval_set);
         //m4_DEBUG('consensus_one: lval_set.length:', lval_set.length);
         var links:Array = lval_set.as_Array();
         //m4_DEBUG('consensus_one: links:', links);
         //m4_DEBUG('consensus_one: links.length:', links.length);

         if (links.length > 0) {

            //m4_DEBUG('consensus_one: links:', links);
            //m4_DEBUG('consensus_one: links.length:', links.length);

            if ((links.length > 1) && (!attr.allow_multiple_values)) {
               m4_WARNING2('consensus_one: Unexpected: mult. links:', links,
                           '/ attr:', attr, '/ item:', item);
            }

            // for each (var link:Link_Value in links) {
            //    if (link.is_vgroup_new || link.is_vgroup_old) {
            //       m4_DEBUG7('consensus_one: attr:', attr, '/ link:', link,
            //                 '/ attr.diff_group:', attr.diff_group,
            //                 '/ attr.is_vgroup_new:', attr.is_vgroup_new,
            //                 '/ attr.is_vgroup_old:', attr.is_vgroup_old,
            //                 '/ link.diff_group:', link.diff_group,
            //                 '/ link.is_vgroup_new:', link.is_vgroup_new,
            //                 '/ link.is_vgroup_old:', link.is_vgroup_old);
            //    }
            // }
            //m4_DEBUG('consensus_one:', lval_set);

            consensus = Item_Revisioned.consensus(
               lval_set, 'attr_value_get', default_, on_empty);

         } // end if (links.length > 0)
         else if (attr.value_internal_name in item.attrs) {
            consensus = item.attrs[attr.value_internal_name];
            //m4_DEBUG('consensus_one: from item.attrs:', consensus);
         }
         else {
            consensus = on_empty;
            //m4_DEBUG('consensus_one: on_empty:', consensus);
         }

         return consensus;
      }

      // *** Developer methods

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' / aka: ' + value_internal_name
                 + ' / vtyp: ' + this.value_type);
      }

      //
      override public function toString_Verbose() :String
      {
         return (super.toString_Verbose()
                 + ' | aka: ' + value_internal_name
                 + ' | type: ' + this.value_type
                 + ' | mult: ' + this.allow_multiple_values
                 + ' | rstrs: ' + this.value_restraints
                 + ' / min:max:step ' + this.value_minimum + ':'
                                      + this.value_maximum + ':'
                                      + this.value_stepsize
                 );
      }

   }
}


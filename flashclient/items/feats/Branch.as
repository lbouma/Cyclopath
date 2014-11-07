/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A Branch is a collection of geofeatures and attachments, possibly duplicated
// from another branch, that can be manipulated independently of other
// branches. In other words, changes to items in one branch do not affect the
// same items in other branches, but rather create alternate versions of said
// items.

package items.feats {

   import flash.utils.Dictionary;

   import grax.Aggregator_Base;
   import items.Geofeature;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Branch_Conflicts;
   import items.utils.Geofeature_Layer;
   import items.utils.Item_Type;
   import utils.geom.Dual_Rect;
   import utils.geom.Geometry;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_branch.Panel_Item_Branch;

   // Branch derives from Geofeature. As a collection of geofeatures,
   // so you could consider that a branch is a sum of all its geofeatures'
   // geometries. Not that it's implemented that way....
   //
   // FIXME: Would it make sense just to derive from Item_Versioned?
   //        In pyserver, branch derives from item_user_watching....

   public class Branch extends Geofeature {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Branch');

      // *** Mandatory attributes

      public static const class_item_type:String = 'branch';
      public static const class_gwis_abbrev:String = 'branch';
      public static const class_item_type_id:int = Item_Type.BRANCH;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Branch;

      // The Panel_Item_Branch panel.
      protected var branch_panel_:Panel_Item_Branch;

      // SYNC_ME: Search geofeature_layer table.
      public static const geofeature_layer_types:Array = [
         //Geofeature_Layer.BRANCH_DEFAULT,
         ];

      // *** Other static variables

      // The ID of the Public Basemap. We eventually get this from the server.
      public static var ID_PUBLIC_BASEMAP:int = 0;

      // FIXME: Implement any of these?

      // A lookup of branches in the branch hierarchy.
      //protected static var branch_stack:Array;

      // A tree lookup of all branches.
      // Branch.branch_tree[grand_parent_id][parent_id][child_id]
      //protected static var branch_tree:Array;

      // *** Instance variables

      // Values from the server
      public var parent_id:int;
      public var last_merge_rid:int;
      // The server sends us conflicts_resolved, but since we also maintain a
      // list of conflicts, we make this protected and use a getter/setter to
      // expose the value to other objects.
      protected var conflicts_resolved_:Boolean = true;

      // 2013.05.11: [lb] adding is_public_basemap. GWIS_Branch_Names_Get
      //             has been using it, and we have a fcn. that computes it,
      //             but this class hasn't been consuming it from gml... so now
      //             we do (and maybe we want to compare what the server says
      //             and what our getter computes?).
      public var gml_is_public_basemap:Boolean = false;

      // A collection of item conflicts
      protected var conflicts:Branch_Conflicts;

      // FIXME: Implement any of these?

      // A handle to the parent branch, whose items we inherit.
      public var parent:Branch;

      // A handle to any children branches.
      public var children:Array;

      // The revision when this branch was branched
      //public var revision_created:int;

      // *** Constructor

      public function Branch(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
         // This is kludgy:
         this.geofeature_layer_id = Geofeature_Layer.BRANCH_DEFAULT;
         this.z_level = 134; // SYNC_ME: pyserver/item/feat/branch.py
                             //          branch.Geofeature_Layer.Z_DEFAULT
         this.conflicts = new Branch_Conflicts();
      }

      // *** Base class getters and setters

      //
      override public function get actionable_at_raster() :Boolean
      {
         return true;
      }

      //
      public function get counterpart() :Branch
      {
         return (this.counterpart_untyped as Branch);
      }

      //
      override public function get counterpart_gf() :Geofeature
      {
         return this.counterpart;
      }

      // "Don't tase me, bro!" Don't let 'em boot us from Map_Layer or
      // Map_Canvas. That should only happen when the user changes branches.
      override public function get discardable() :Boolean
      {
         // FIXME: Should really check to see if this branch is part of the
         //        active_branch_ hierarchy. (I.e., client could load all
         //        branches for a detail_panel, and we'd want to be sure to
         //        clear 'em.) Currently, branches get cleared only when user
         //        changes branches.
         return false;
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         return true;
      }

      //
      override public function get friendly_name() :String
      {
         return 'Map Branch';
         //return 'Map: ' + this.name_;
      }

      //
      override public function get is_drawable() :Boolean
      {
         return false;
      }

      //
      override public function get is_clickable() :Boolean
      {
         return false;
      }

      //
      override public function is_selected() :Boolean
      {
         // Is this fcn. ever called? Seems weird.
         m4_ASSERT(false);
         //
         // Otherwise, we could do what Attachment does, e.g., c.f.,
         var is_selected:Boolean = false;
         var branch_panel:Panel_Item_Branch;
         branch_panel = G.panel_mgr.effectively_active_panel
                        as Panel_Item_Branch;
         if (branch_panel !== null) {
            // Check that the attachment panel exists first. If we called
            // this.attachment_panel we'd inadvertently create a new panel
            // that we might not need.
            if (this.is_branch_panel_set()) {
               if (branch_panel === this.branch_panel) {
                  m4_ASSERT(this.branch_panel.branch === this);
                  is_selected = true;
               }
            }
         }
         // else, not a Panel_Item_Branch, so this branch not selected.
         return is_selected;
      }

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         // This fcn. is probably never called?
         m4_DEBUG('item_cleanup');
         super.item_cleanup(i, skip_delete);
         // MAYBE: Reset: Branch.ID_PUBLIC_BASEMAP = 0;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         // The branch item is special... see Item_Manager.active_branch.
         // But we're called on cleanup, i.e., when logging in, and also
         // when Panel_Item_Branch is activated, because
         // reactivate_selection_set calls item.set_selected(true).
         ; // no-op
      }

      //
      override public function get trust_rid_latest() :Boolean
      {
         return true;
      }

      // *** Getters and setters

      //
      [Bindable] public function get branch_list_label() :String
      {
         var list_label:String = this.name_;
         if ((G.item_mgr.active_branch !== null)
             && (this.stack_id == G.item_mgr.active_branch.stack_id)) {
            list_label += ' (Active)';
         }
         m4_VERBOSE('branch_list_label:', list_label);
         return list_label;
      }

      //
      public function set branch_list_label(label:String) :void
      {
         // No-op; for [Bindable]
      }

      //
      public function get branch_panel() :Panel_Item_Branch
      {
         if (this.branch_panel_ === null) {
            this.branch_panel_ = (G.item_mgr.item_panel_create(this)
                                 as Panel_Item_Branch);
            this.branch_panel_.branch = this;
         }
         return this.branch_panel_;
      }

      //
      public function set branch_panel(branch_panel:Panel_Item_Branch) :void
      {
         if (this.branch_panel_ !== null) {
            this.branch_panel_.branch = null;
         }
         this.branch_panel_ = branch_panel;
         if (this.branch_panel_ !== null) {
            this.branch_panel_.branch = this;
         }
      }

      // Returns false is conflicts exist that the user needs to resolve before
      // being allowed to commit.
      [Bindable] public function get conflicts_resolved() :Boolean
      {
         m4_ASSERT(this.conflicts.length == 0);
         return conflicts_resolved_;
      }

      //
      // FIXME: Does this apply to baseline v. mainline, or is this working
      //        copy v. baseline, eh?
      public function set conflicts_resolved(resolved:Boolean) :void
      {
         //m4_ASSERT(false); // Not used; implemented for [Bindable].
         /*/
         if (resolved) {
            m4_ASSERT(this.conflicts.length == 0);
         }
         else {
            m4_ASSERT(this.conflicts.length > 0);
         }
         /*/
         this.conflicts_resolved_ = resolved;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         // This is called when updating access_style_id. What would we return?
         // Maybe make our own lookup?
         m4_WARNING('get_class_item_lookup: code !tested bc. no branch perms');
         var fake_lookup:Dictionary = new Dictionary();
         var active_branch:Branch = G.item_mgr.active_branch;
         fake_lookup[active_branch.stack_id] = active_branch;
         return fake_lookup;
      }

      //
      public function get is_public_basemap() :Boolean
      {
         return (this.stack_id == Branch.ID_PUBLIC_BASEMAP);
      }

      //
      public function set is_public_basemap(is_public_basemap:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      override public function get mobr_dr() :Dual_Rect
      {
         m4_ASSERT(false); // This fcn. isn't called, is it?
                           // See: Geofeature.mobr_dr_union
                           //  and Dual_Rect.mobr_dr_from_xys.
         // C.f. Region.mobr_dr.
         return Dual_Rect.mobr_dr_from_xys(this.xs, this.ys);
      }

      // *** Base class overrides

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Branch = (to_other as Branch);
         super.clone_once(other);
         m4_ASSERT_SOFT(false); // Never called, right?
         other.parent_id = this.parent_id;
         other.last_merge_rid = this.last_merge_rid;
         other.conflicts_resolved_ = this.conflicts_resolved_;
         other.gml_is_public_basemap = this.gml_is_public_basemap;
      }

      //
      override public function clone_id(to_other:Record_Base) :void
      {
         m4_ASSERT_SOFT(false); // Never called, right?
         //other.branch_id = this.branch_id;
      }

      //
      override protected function clone_update( // on-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Branch = (to_other as Branch);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            // NOTE The call to super() consumed the branch's stack_id and
            //      name_.
            this.parent_id = int(gml.@parent_id);
            this.last_merge_rid = int(gml.@last_merge_rid);
            this.conflicts_resolved_ = Boolean(int(gml.@conflicts_resolved));
            this.gml_is_public_basemap = Boolean(int(gml.@is_public_basemap));

            // Get branch.coverage_area, which, like most geometry, is sent
            // in the text portion of the XML element.
            // Not there: this.coverage_area = gml.@coverage_area;
            Geometry.coords_string_to_xys(gml.external.text(),
                                          this.xs, this.ys);
            if ((this.xs.length > 0) && (this.ys.length > 0)) {
               m4_DEBUG('gml_consum: new branch: got geom:', this.toString());
               // close rings
               this.xs.push(this.xs[0]);
               this.ys.push(this.ys[0]);
            }
            else {
               m4_WARNING('gml_consum: new branch: no geom:', this.toString());
            }

            // See if this is the basemap.
            // 2013.05.13: I [lb] think sending is_public_basemap via GML must
            // be recent. Otherwise, why is is_public_basemap a fcn. that
            // checks Branch.ID_PUBLIC_BASEMAP? I'm guessing flashclient used
            // to ask for the basemap stack ID from the key_value_pair table,
            // and then eventually pyserver added the is_public_basemap bool.
            if (this.gml_is_public_basemap) {
               m4_ASSERT(this.parent_id == 0);
               if (Branch.ID_PUBLIC_BASEMAP == 0) {
                  Branch.ID_PUBLIC_BASEMAP = this.stack_id;
               }
               else {
                  m4_ASSERT(Branch.ID_PUBLIC_BASEMAP == this.stack_id);
               }
            }
         }
         else {
            this.parent_id = 0;
            this.last_merge_rid = 0;
            this.conflicts_resolved_ = true;
            this.gml_is_public_basemap = false;
         }
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         m4_ASSERT(false); // Not gonna happen.
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_DEBUG('Adding Branch:', this);
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(item_agg, soft_add);
         // init_add is really only called on startup, and it loads the list of
         // branches the user can see. The branch items, however, are not
         // guaranteed to be completely hydrated, since we only need the name
         // and stack_id to populate the branch list.
         this.init_check_branch_id_to_load(this);
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         // NOTE: Not calling: super.init_update(existing, item_agg);
         m4_DEBUG('Updating Branch:', this);
         // Fetch the branch from the lookup.
         var branch:Branch = Geofeature.all[this.stack_id];
         if (branch !== null) {
            m4_ASSERT(existing === null);
            m4_ASSERT((existing === null) || (existing === branch));

            // Let the parent twiddle things first.
            // clone will call clone_update and not clone_once because branch.
            this.clone_item(branch);

            // Set the active_branch, maybe.
            this.init_check_branch_id_to_load(branch);
         }
         else {
            m4_ASSERT_SOFT(false);
         }
         return branch;
      }

      // *** Instance methods

      //
      protected function init_check_branch_id_to_load(branch:Branch) :void
      {
         m4_DEBUG2('init_check_branch_id_to_load: stk id to load:',
                   G.item_mgr.branch_id_to_load);
         m4_DEBUG2('init_check_branch_id_to_load:  active_branch:',
                   G.item_mgr.active_branch);
         m4_DEBUG('init_check_branch_id_to_load:      new branch:', branch);

         m4_DEBUG('init_check_branch_id_to_load: new active_branch:', branch);

         // Oy! So hilarious. 2013.09.21: [lb] forgot about this problem:
         // trying to use a 'set' function when the object is the same
         // is ignored by Flex. But we want to make sure to signal
         // branchChange and to update the user's branch grpa records.
         if (G.item_mgr.active_branch === branch) {
            m4_DEBUG(' .. sneakily clearing active_branch_');
            G.item_mgr.active_branch_ = null;
         }

         G.item_mgr.active_branch = branch;
      }

      // C.f., Attachment.is_attachment_panel_set.
      public function is_branch_panel_set() :Boolean
      {
         return (this.branch_panel_ !== null);
      }

   }
}


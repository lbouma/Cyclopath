/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_base {

   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.utils.getQualifiedClassName;
   import mx.containers.VBox;
   import mx.controls.VScrollBar;
   import mx.controls.scrollClasses.ScrollBar;
   import mx.core.Container;
   import mx.events.FlexEvent;
   import mx.events.ResizeEvent;
   import mx.utils.ObjectProxy;

   import grax.Dirty_Reason;
   import items.Geofeature;
   import items.Item_Base;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.misc.Strutil;
   import views.panel_base.Detail_Panel_Base;

   // This class is Bindable so objects can watch instances of this
   // class for changes.
   //
   // This class is dynamic so objects can reference attributes using the []
   // operator.
   //
   // MAYBE: Both [Bindable] and dynamic are new to CcpV2: test without either
   //        and verify they're both necessary. Or don't care, and just keep.
   // DEV_NOTE: Class-level Bindable means _all_ getters/setters and attributes
   //           are implicitly bindable! We might not want to do this...
   [Bindable] public dynamic class Detail_Panel_Base extends VBox {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@DtlPnl_Base');

      // *** Instance variables

      // MXML "States"
      //
      // States are useful for creating different views based on the same
      // underlying code. However, Flex only lets you define one <mx:states>
      // container, so it's not immediately useful for a class hierarchy, since
      // each derived class ideally wants its own state. To work around this,
      // we declare some names that derived classes can use to make an array of
      // <mx:State> objects, which we'll add to <mx:states> at runtime.
      //
      // Derived classes should make an array named 'new_states' that contains
      // an mx:State container. Intermediate classes should name the state
      // 'state_base', and leaf classes should name the state 'state_default'.
      // (If we had a third tier of derived classes, we'd need a third state.)

      public const panel_base_state:String = 'state_base';
      public const panel_default_state:String = 'state_default';

      // The names that descendant classes should use for their State Array,
      // which depends on their depth in the class hierarchy.
      // DEVS: If you make a derived class that's even deeper than
      //       state_default (i.e., a third tier descendant, or greater), add
      //       more elements (names) to this lookup.
      protected var panel_states_array:Array =
         [                       // Assuming this class is the 1st generation:
         'new_states',           // 2d gen
         // DEVS: If you had a third tier descendant, add, e.g.,
         // 'new_states_3rd_gen' // 3d gen
                                 // ... add more here as needed ...
         ];

      // Some panels contain one or more other panels. See: register_widgets.
      protected var panel_children:Set_UUID = new Set_UUID();

      // I [lb] cannot determine a way to ask Flex the state of our component,
      // and we need to know when the component is done being created. So we
      // track it ourselves.
      public var creation_completed:Boolean = false;

      // The one or more selected items applicable to this panel. Could be one
      // or more geofeatures (byways, waypoints, regions), or one route, or an
      // attachment, or a branch, or a thread or post, or nothing for the
      // search panel, latest activity, and sew awn.
      protected var items_selected_:Set_UUID = null;
      // Each panel might also relate to a selected set of geofeatures on the
      // map.
      protected var feats_selected_:Set_UUID = null;
      public var feats_ordered_:Array = new Array();

      // In CcpV1, dirty_reasons is a Set. In CcpV2, we retrograde and use a
      // bitmask (which is technically faster and uses less memory, not that
      // either of those matter here, but it makes programming easier, too.)
      // Was: protected var dirty_reasons:Set_UUID = new Set_UUID();
      protected var dirty_reasons:uint = Dirty_Reason.not_dirty;

      // If on_panel_show is called before on_creation_complete, we have to
      // remember to really call it when we're ready.
      protected var on_show_pending:Boolean = false;

      public var panel_close_pending:Boolean = false;

      // Historically (and somewhat currently), we update UI elements when data
      // changes, regardless of whether that UI element is showing. But as
      // Cyclopath has grown in complexity, and to try to bootstrap as quickly
      // as possible, we're now trying to update UI elements only when they're
      // visible. Using is_showing helps us accomplish that.
      public var is_showing_:Boolean = false;

      // If you use ViewStack, you have to set children components' heights
      // deliberately (our Bug 2778). Here we track whether or not we've at
      // least set the height deliberately the first time.
      // FIXME: On bootstrap, the first time you look at any Item Details
      //        panel (branch or selected item), the height isn't getting
      //        corrected until you make another item selection.
      protected var items_panel_height_set:Boolean = false;

      // Warning: Class already marked [Bindable]; property-level [Bindable]
      //          is redundant and will be ignored.
      // so, skipping: [Bindable]
      //
      // This var stops Flex from yapping when you set MXML to this.parent.
      // E.g., "warning: unable to bind to property 'parent' on class
      //                 'views.panel_routes::Route_Stop_Entry'"
      protected var parent_proxy:ObjectProxy;

      // 2013.07.22: As each panel is activated, it remembers the panel that
      //             was active before it.
      public var panel_stack_prev:Detail_Panel_Base;
      public var panel_stack_next:Detail_Panel_Base;

      // *** Constructor

      public function Detail_Panel_Base()
      {
         super();

         // Hook startup events so out custom controls can do their thang.
         this.addEventListener(FlexEvent.PREINITIALIZE,
                               this.on_preinitialize, false, 0, true);
         this.addEventListener(FlexEvent.INITIALIZE,
                               this.on_initialize, false, 0, true);
         this.addEventListener(FlexEvent.CREATION_COMPLETE,
                               this.on_creation_complete, false, 0, true);

         this.add_listeners_show_and_hide();

         // 2013.02.25: Catch removed events so we can removeEventListeners.
         this.addEventListener(FlexEvent.REMOVE,
                               this.on_remove_event, false, 0, true);

         // So we can add paddingRight if the scroll bar is showing.
         if (this.has_auto_scroll_bar_policy()) {
            this.addEventListener(Event.ADDED,
                                  this.on_added_event, false, 0, true);
            this.addEventListener(Event.REMOVED,
                                  this.on_removed_event, false, 0, true);
         }

         // Mark the panel dirty so it gets redrawn the first time it's shown.
         m4_VERBOSE2('Detail_Panel_Base: dirty_set: Dirty_Reason.item_data:',
                     this);
         this.dirty_set(Dirty_Reason.item_data);

         // Derived classes set the button text (via the panel title) but we've
         // got a fcn. wired to set the button toolTip (via the panel toolTip).
         this.set_panel_tool_tip();
      }

      // *** Instance functions

      // I [lb] can't figure out how to define and access static class
      // attributes for the MXML files that derive from this class, so we use
      // instance methods herein where we might have otherwise chosen to use
      // class attributes.

      // *** Getters and Setters

      // Child classes should override this function to take care of any
      // cleanup and prevent closing (if necessary). E.g., the discussions
      // panel can prevent closing if there are dirty changes.
      public function get can_close(): Boolean
      {
         return true;
      }

      //
      public function get class_name_snip() :String
      {
         // Returns the last part of the really long instance name.
         //return Strutil.snippet(String(this),
         return Strutil.snippet(String(super.toString()),
                                /*tease_len=*/35,
                                /*reverse=*/true);
      }

      //
      public function get class_name_tail() :String
      {
         // Given, e.g., "a.b.c.d", returns "d".
         //return Strutil.class_name_tail(String(this));
         var num_classes:int = 3;
         return Strutil.class_name_tail(super.toString(), num_classes);
      }

      // By default, panels are not closeable and should appear in order in the
      // ViewStack in main.mxml. For panels created on the fly (via user
      // interaction), like the settings and item panels, these are put last in
      // the list of tabs and are closeable (there's a cute little close icon
      // on the tab). This behavior is like the tabs in a Web browser.
      // BUG nnnn: Allow user to drag-n-move the on-demand closeable tabs.
      //           E.g., think of a Web browser with multiple tabs open.
      public function get closeable() :Boolean
      {
         return false;
      }
// FIXME_2013_06_11
// FIXME/BUG nnnn: We need a similar fcn. to indicate if a panel is dirty
//        (i.e., its items_selected is dirty)
//        so user has to decide to save or discard to close panel.

      // Some panels don't have any items_selected or feats_selected, but
      // for those that do, we want to close the panel if it's got nothing
      // selected (otherwise we just show a pointless, empty panel...).
      public function get close_when_emptied() :Boolean
      {
         return false;
      }

      //
      public function get feats_ordered() :Array
      {
         return this.feats_ordered_;
      }

      //
      public function set feats_ordered(feats_ordered:Array) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get feats_selected() :Set_UUID
      {
         if (this.feats_selected_ === null) {
            this.feats_selected_ = new Set_UUID();
            m4_DEBUG('get feats_selected: was null: this:', this);
         }
         else {
            m4_DEBUG3('get feats_selected: for:', this,
                      '/ cnt:', this.feats_selected_.length,
                      '/ sel', this.feats_selected_.toString());
         }
         return this.feats_selected_;
      }

      //
      public function set feats_selected(feats_selected:Set_UUID) :void
      {
         this.feats_selected_ = feats_selected;
      }

// FIXME: route reactions.
      // A link to help on this panel (if null or empty, the help link is
      // hidden).
      // FIXME: [lb] has hard-coded URLs in the Hyper_Link widgets, but
      //        using this fcn. seems like a better idea. So find all ye
      //        Hyper_Links and fix.
      public function get help_url() :String
      {
         return null;
      }

      //
      public function get is_showing() :Boolean
      {
         // On get new Route, this.panel_owning_panel is null.
         //  panel_activate_impl: ...ame.side_panel.Panel_Item_Route3986
         //  panel_show: active: panel: Panel_Item_Route_Details4156
         //                      parent: null
         //              next: panel: Panel_Item_Route3986
         //                      parent: Panel_Item_Route3986
         // TypeError: Error #1009:
         //    Cannot access a property or method of a null object reference.
         // ... because of this.panel_owning_panel ....
         return ((this.panel_owning_panel !== null)
                 && (this.panel_owning_panel.is_showing_));
      }

      //
      public function set is_showing(is_showing:Boolean) :void
      {
         this.panel_owning_panel.is_showing_ = is_showing;
      }

      //
      public function get items_selected() :Set_UUID
      {
         /*/
         if (this.items_selected_ !== null) {
            m4_DEBUG4('get items_selected:',
                      'this:', this.class_name_tail,
                      '/ cnt:', this.items_selected_.length,
                      '/ sel:', this.items_selected_.toString(true));
         }
         else {
            m4_DEBUG2('get items_selected: is null: this:',
                      this.class_name_tail);
         }
         /*/
         return this.items_selected_;
      }

      //
      public function set items_selected(items_selected:Set_UUID) :void
      {
         //m4_DEBUG2('set items_selected: items_selected_:',
         //          this.items_selected_);
         //m4_DEBUG2('set items_selected: items_selected_.length:',
         //          this.items_selected_.length);
         //m4_DEBUG2('set items_selected: items_selected:',
         //          this.items_selected);
         //m4_DEBUG2('set items_selected: items_selected.length:',
         //          this.items_selected.length);

         if (G.panel_mgr.effectively_active_panel === this) {
            if (this.items_selected_ !== null) {
               var items_to_deselect:Set_UUID =
                  this.items_selected_.difference(items_selected);
               //m4_DEBUG2('set items_selected: _to_deselect: len:',
               //          items_to_deselect.length, '/', items_to_deselect);
               for each (var item:Item_User_Access in items_to_deselect) {
                  item.set_selected(false, /*nix=*/true);
               }
            }
         }

         this.items_selected_ = items_selected;

         /*/
         if (this.items_selected_ !== null) {
            m4_DEBUG4('set items_selected:',
                      'this:', this.class_name_tail,
                      '/ cnt:', this.items_selected_.length,
                      '/ sel:', this.items_selected_.toString(true));
         }
         else {
            m4_DEBUG2('set items_selected: to null: this:',
                      this.class_name_tail);
         }
         /*/
      }

      // If the Detail_Panel_Base object is a container of other such objects
      // (i.e., the parent is essentially a tab bar and a ViewStack), we return
      // the selected child. Otherwise, we return the panel itself, since it's
      // not a container but is the actual panel.
      public function get panel_active_child() :Detail_Panel_Base
      {
         // By default, the panel that you see is the panel that you get. But
         // some panels are really containers of multiple panels (i.e., using
         // a TabButtonBar), so if you get a panel from the side_panel
         // ViewStack, you'll want to ask it what panel is really showing, so
         // the Panel_Manager can manage it.
         var sub_panel:Detail_Panel_Base = this;
         return sub_panel;
      }

      //
      public function set panel_active_child(sub_panel:Detail_Panel_Base) :void
      {
         // Unless a base class overrides this fcn., the panel does not have
         // tabs of its own, so the sub_panel should be the panel itself.
         m4_ASSERT(sub_panel === this);
      }

      // This gets the first-level descendant panel of the ViewStack container.
      // This might be 'this', or it might be a parent of this, depending on if
      // the panel has tabs of its own.
      public function get panel_owning_panel() :Detail_Panel_Base
      {
         return this;
      }

      //
      public function set panel_owning_panel(dpanel:Detail_Panel_Base) :void
      {
         m4_ASSERT(false);
      }

      // The item panels override this fcn. to indicate what type of item they
      // represent. This completes a circular reference with Item_Versioned et
      // al's dpanel_class_static that Item_Manager uses to make this panel.
      public function get shows_type() :Class
      {
         m4_ASSERT(false); // Abstract
         return Item_Base;
      }

      //
      public function get vertical_scrollbar_target() :Container
      {
         return this;
      }

      // *** Simpler helper fcns.

      //
      public function attachment_highlights_update() :Array
      {
         var to_h:Array = new Array();
         return to_h;
      }

      //
      public function close_cleanup(was_active:Boolean) :void
      {
         m4_DEBUG('close_cleanup: was_active:', was_active);
      }

      //
      public function close_panel() :void
      {
         try {
            var idx:int = G.app.side_panel.getChildIndex(this);
            m4_DEBUG('close_panel: idx:', idx);
            G.app.side_panel_tabs.close_panel_at_index(idx);
         }
         catch (e:ArgumentError) {
            m4_WARNING('close_panel: not in side_panel:', this);
            m4_WARNING(Introspect.stack_trace());
         }
      }

      //
      public function dirty_set(reason:uint) :void
      {
         m4_VERBOSE2('dirty_set:', Dirty_Reason.lookup_key[reason],
                     '/', this);
         m4_ASSERT(reason != 0); // Unexpected.
         this.dirty_reasons |= reason;
         // Cheat and mark our child widgets as dirty, for the same dirty
         // reason as the parent.
         // MAYBE: Rather than using dirty, widgets could listen on events
         //        and update when certain events fire.
         //        See: selectionChanged
         for each (var child:Detail_Panel_Base in this.panel_children) {
            // Wrong: child.dirty_reasons |= reason;
            child.dirty_set(reason);
         }
      }

      //
      public function is_dirty() :Boolean
      {
         var is_dirty:Boolean = (this.dirty_reasons != Dirty_Reason.not_dirty);
         if (!is_dirty) {
            for each (var child:Detail_Panel_Base in this.panel_children) {
               is_dirty = child.is_dirty();
               if (is_dirty) {
                  break;
               }
            }
         }
         return is_dirty;
      }

      // This fcn. is called from Launcher's remove_child, after a panel is
      // removed from the side panel tabs.
      public function panel_stack_removed_child() :void
      {
         m4_DEBUG('panel_stack_removed_child: this:', this);
         this.panel_selection_clear();
         this.panel_stack_unwire();
         // MAYBE: The remaining code smells ripe for a Panel_Manager fcn.
         G.panel_mgr.panel_lookup.remove(this);
         if (G.panel_mgr.effectively_active_panel === this) {
            m4_DEBUG2('pnl_stk_remvd_child: effectively_active_panel is this:',
                      this);
            G.panel_mgr.effectively_active_panel = null;
         }
         if (G.panel_mgr.activate_panel_next === this) {
            m4_DEBUG2('pnl_stk_remvd_child: activate_panel_next is this:',
                      this);
            G.panel_mgr.activate_panel_next = null;
         }
      }

      //
      public function panel_stack_unwire() :void
      {
         // Rewire the doubly-linked panel pointers.
         var new_prev:Detail_Panel_Base = this.panel_stack_prev;
         var new_next:Detail_Panel_Base = this.panel_stack_next;
         if (new_prev !== null) {
            new_prev.panel_stack_next = new_next;
         }
         if (new_next !== null) {
            new_next.panel_stack_prev = new_prev;
         }
         // No, need by panel_activate: this.panel_stack_prev = null;
         // No, need by panel_activate: this.panel_stack_next = null;
         m4_DEBUG('panel_stack_unwire: this:', this);
         m4_DEBUG('panel_stack_unwire: panel_stack_prev:', new_prev);
         m4_DEBUG('panel_stack_unwire: panel_stack_next:', new_next);
         //m4_ASSERT(this !== new_prev);
         //m4_ASSERT(this !== new_next);
         //m4_ASSERT((new_prev === null)
         //          || (new_next === null)
         //          || (new_prev !== new_next));
         if (G.panel_mgr.panel_stack_prev_eap === this) {
            m4_DEBUG('panel_stack_unwire: panel_stack_prev_eap:', new_prev);
            G.panel_mgr.panel_stack_prev_eap = new_prev;
         }
         this.panel_close_pending = false;
      }

      //
      public function panel_supports_feat(feat:Geofeature) :Boolean
      {
         // This fcn. is called when the user selects a geofeature on the map.
         // The geofeature is trying to determine if it can add itself to the
         // current panel, or if it must activate another or open a new panel.
         return false;
      }

      // Disables multi-select for geopoints unless the two are a counterpart
      // pair which is being diffed.      
      protected function panel_supports_feat_impl(feat:Geofeature,
                                                  multi_okay:Boolean)
         :Boolean
      {
         m4_ASSERT(feat !== null);
         var is_compatible:Boolean = (feat is this.shows_type);
         if (is_compatible) {
            if ((multi_okay) || (this.feats_selected.length == 1)) {
               // If nothing is selected, we're okay, or if the item is already
               // selected.
               if (!(this.feats_selected.is_member(feat))) {
                  if (this.feats_selected.length > 0) {
                     // Check that we're not diffing, or that the other item is
                     // this item's counterpart.
                     var rand:Geofeature =
                        (this.feats_selected.item_get_random() as Geofeature);
                     is_compatible = ((!feat.rev_is_diffing
                                       && !rand.rev_is_diffing)
                                      || (feat.counterpart_gf === rand));
                  }
                  // else, feats_selected.length == 0, so is_compatible.
               }
               // else, feats_selected.is_member(feat), so is_compatible.
            }
            else { // !multi_okay, and no. selected is 0, or 2 or more.
               is_compatible = (this.feats_selected.length == 0);
            }
         }
         m4_DEBUG5('panel_supports_feat_impl',
                   '/ multi_okay:', multi_okay,
                   '/ shows_type:', (feat is this.shows_type),
                   '/ no. sel.:', this.feats_selected.length,
                   '/ compat?:', is_compatible, '/', this);
         return is_compatible;
      }

      //
      public function panel_selection_clear(
         force_reset:Boolean=false,
         dont_deselect:*=null)
            :void
      {
         m4_DEBUG('panel_selection_clear: this:', this);

         var item:Item_Versioned;
         
         // dont_deselect is used when recycling a panel for one geofeature of
         // a selection set, so that we don't deselect any selected vertices
         // (since, e.g., this happens when you have multiple items selected
         // but drag a vertex: the details panel switches to the one byway...).
         m4_ASSERT((dont_deselect === null) || (force_reset));

         // The caller may pass either a single item or a set of items.
         if ((dont_deselect !== null) && (dont_deselect is Item_Versioned)) {
            dont_deselect = new Set_UUID([dont_deselect,]);
         }

//fixme: this only removes from this panel if this panel is the active panel...
         // Clear the map selections. This may or may not already be done.
         if (this.items_selected !== this.feats_selected) {
            for each (var feat:Geofeature in this.feats_selected) {
               if ((dont_deselect === null)
                   || (!dont_deselect.is_member(item))) {
                  m4_DEBUG('panel_selection_clear: feat:', feat);
                  feat.set_selected(false);
               }
               else {
                  m4_DEBUG('panel_selection_clear: skipping feat:', feat);
               }
            }
            // m4_DEBUG('panel_selection_clear: clearing feats_selected');
            // NO: this.feats_selected = null;
         }
         // Clear the item selections. This is also probably previously done.
         for each (item in this.items_selected) {
            if ((dont_deselect === null)
                || (!dont_deselect.is_member(item))) {
               var panel_selected_item:Boolean = false;
               if (this.items_selected.is_member(item)) {
                  panel_selected_item = true;
               }
               else if (this.items_selected !== this.feats_selected) {
                  if (this.feats_selected.is_member(item)) {
                     panel_selected_item = true;
                  }
               }
               if (panel_selected_item) {
                  m4_DEBUG('panel_selection_clear: item:', item);
                  item.set_selected(false);
               }
               else {
                  // This happens if you're switching from the routes_panel to
                  // a specific route details panel: you don't want to
                  // accidentally remove the route from the details panel when
                  // you really mean to remove if from the routes_panel.
                  m4_DEBUG2('panel_selection_clear: item in another panel:',
                            item);
               }
            }
            else {
               m4_DEBUG('panel_selection_clear: skipping item:', item);
            }
         }
         // m4_DEBUG('panel_selection_clear: clearing items_selected');
         // NO: this.items_selected = null;
         if (force_reset) {
            m4_DEBUG('panel_selection_clear: force_reset');
            this.items_selected = new Set_UUID();
            if (this.items_selected !== this.feats_selected) {
               this.feats_selected = new Set_UUID();
            }
            this.feats_ordered_ = new Array();
            if (dont_deselect !== null) {
               for each (item in dont_deselect) {
                  this.items_selected.add(item);
                  if (item is Geofeature) {
                     // feats_selected === item_selected, so just repopulate
                     // the selected-in-order array.
                     this.feats_ordered_.push(item);
                  }
               }
            }
            m4_DEBUG('panel_selection_clear: resetting panel_close_pending');
            this.panel_close_pending = false;
         }
      }

      //
      protected function items_reselect_all() :void
      {
         if (this.items_selected !== this.feats_selected) {
            for each (var feat:Geofeature in this.feats_selected) {
               feat.set_selected(true);
            }
         }
         for each (var item:Item_Versioned in this.items_selected) {
            item.set_selected(true);
         }
      }

      //
      protected function mark_dirty_and_show_maybe() :void
      {
         // MAYBE: This fcn. should be used by more widgets.
         this.dirty_set(Dirty_Reason.item_data);
         // 2013.04.07: Is this working-as-designed (WADDing)? There was an old
         // comment that maybe is_showing is true for panels that aren't
         // (showing), meaning we're just doing a little unnecessary work.
         if (this.is_showing) {
            m4_DEBUG('mark_dirty_and_show_maybe: Y:', this);
            this.repopulate_self_and_children();
         }
         else {
            // else, we're not showing, so don't bother updating now.
            m4_DEBUG('mark_dirty_and_show_maybe: N:', this);
         }
      }

      //
      public function panel_title_get() :String
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      //
      public function panel_toolTip_get() :String
      {
         return '';
      }

      //
      public function reactivate_selection_set() :void
      {
         // No: This clears from panel, not just map:
         //       G.map.map_selection_clear();

         var item:Item_Versioned;
         // Because m4 only removes newlines on commas, this is not (m4_)DEBUG7
         m4_DEBUG5('reactivate_selection_set: items:',
                   (this.items_selected !== null)
                     ? this.items_selected.length : 'null',
                   '/ feats:', (this.feats_selected !== null)
                               ? ((this.items_selected !== this.feats_selected)
                                  ? this.feats_selected.length : 'same')
                               : 'null');
         for each (item in this.items_selected) {
            item.set_selected(true);
         }
         if (this.items_selected !== this.feats_selected) {
            var feat:Geofeature;
            for each (feat in this.feats_selected) {
               feat.set_selected(true);
            }
         }

         // Tickle Widget_Attachment_Place_Box.reapply_attachment_mode.
         m4_DEBUG('reactivate_selection_set: activatePanel');
         this.dispatchEvent(new Event('activatePanel'));
      }

      //
      // FIXME: Rename register_widgets -> register_child_panels
      protected function register_widgets(panel_children:Array) :void
      {
         this.register_widgets_impl(panel_children, this);
      }

      //
      protected function register_widgets_impl(
         add_children:Array,
         detail_panel:Detail_Panel_Base)
            :void
      {
         // Not true anymore: m4_ASSERT(detail_panel !== null);
         if (this.panel_children.length > 0) {
            m4_DEBUG2('register_widgets: adding cnt.:', add_children.length,
                      '/ existing cnt.:', this.panel_children.length);
         }
         else {
            m4_DEBUG('register_widgets: starting cnt.:', add_children.length);
         }
         if (add_children.length == 0) {
            m4_DEBUG('register_widgets_impl: nothing to add?');
            //m4_WARNING(Introspect.stack_trace());
         }
         // Feels funny to reference a derived class, but it works.
         for each (var child:Detail_Panel_Widget in add_children) {
            //m4_VERBOSE(' .. child:', child);
            //m4_VERBOSE(' .. detail_panel:', detail_panel);
            // Mark the child dirty so it knows to redraw.
            child.dirty_set(Dirty_Reason.item_data);
            // See the detail panel of the child to our detail panel.
            child.detail_panel = detail_panel;
            // Finally, remember this child.
            //m4_VERBOSE('register_widgets_impl: child:', child);
            //m4_VERBOSE('register_widgets_impl: this.panel_children:',
            //           this.panel_children);
            this.panel_children.add(child);
         }
      }

      //
      public function deregister_widget(widget:Detail_Panel_Widget) :void
      {
         this.panel_children.remove(widget);
      }

      //
      protected function set_panel_tool_tip() :void
      {
         this.toolTip = this.panel_toolTip_get();
         m4_VERBOSE('set_panel_tool_tip:', this.toolTip);
      }

      // *** The hide/show/repopulate fcns.

      //
      protected function add_listeners_show_and_hide(just_kidding:*=null) :void
      {
         // We shouldn't have to worry about resize events, at least not now.
         // MAYBE: Many classes override on_resize: does not hooking the real
         //        event cause components not to get resized?
         // this.addEventListener(ResizeEvent.RESIZE, this.on_resize,
         //                       false, 0, true);
         if ((just_kidding === null) || (!just_kidding)) {
            this.addEventListener(FlexEvent.SHOW,
                                  this.on_show_event, false, 0, true);
            this.addEventListener(FlexEvent.HIDE,
                                  this.on_hide_event, false, 0, true);
         }
      }

      //
      // FIXME: Probably audit all Detail_Panel_Base classes' repopulate()s and
      //        figure out which ones need to override this fcn...
      protected function depopulate() :void
      {
         // Derived classes can overrive depopulate() if they care if
         // items_selected is empty, otherwise we just call repopulate.
         m4_VERBOSE('depopulate: repopulate');
         this.repopulate();
      }

      // Called when this Detail_Panel_Base is no longer current. Subclasses
      // should call this _after_ they do their thing. WARNING: Called in
      // response to another selection event that puts up a new panel, so don't
      // rely on the selectedset to give you the needed data (it should be
      // saved in on_panel_show() instead).
      public function on_panel_hide() :void
      {
         m4_VERBOSE2('on_panel_hide: this:', this,
                     '/ showing:', this.is_showing);

         // 2013.02.28: This is an old comment. CcpV3 revamps on_panel_hide.
         //             But what's Bug 1878?
         //             "Previously, this was needed because of so-called
         //             'odd behaviors' with panels keeping focus. Now, with
         //             multiple groups it causes further problems when one
         //             group's panel requests a focus and the odd behaviors
         //             could not be verified. See BUG 1878."
         // NOTE: We don't touch items_selected, which is independent of
         //       on_panel_show and on_panel_hide.

         var force_reset:Boolean = false;
         this.panel_selection_clear(force_reset/*=false*/);

         // The is_showing attribute is similar to comparing
         // this === G.app.side_panel.selectedChild, but the
         // latter refers to the actual GUI panel, and this
         // refers to our on_panel_show and on_panel_hide,
         // which are called near the time of the view
         // changing, but are not guaranteed to happen in
         // the same frame. [lb] thinks they happen after
         // the view actually changes. So we might actually
         // cause flicker or a quick redraw...
         this.is_showing = false;

         // MAYBE: Bother calling this.depopulate_self_and_children()?
      }

      // Called when a panel is activated by the user and is being made
      // visible. We only do work if the panel is marked dirty.
      public function on_panel_show() :void
      {
         var child:Detail_Panel_Base;
         // Only show if creationComplete has been triggered, otherwise our
         // children components don't exist yet.
         m4_VERBOSE3('on_panel_show: this:', this,
                     '/ creation_completed:', this.creation_completed,
                     '/ showing:', this.is_showing);
         if (!this.creation_completed) {
            // If creationComplete hasn't been called, we can't fiddle with our
            // components. This happens, e.g., the first time any item is
            // selected on the map, since Flash doesn't create UI components
            // until they're needed (or if we force Flash to create UI
            // components early, which we don't). So just remember to call this
            // function when creationComplete is eventually signaled.
            m4_VERBOSE2('on_panel_show: EARLY:', getQualifiedClassName(this),
                        '/', this.id);
            this.on_show_pending = true;
         }
         else {
            this.is_showing = true;

            // FIXME: [mm] finds: Panel_Manager::set effectively_active_panel()
            //        does this. In fact, it calls reactivate_selection_set()
            //        which is remarkably similar to items_reselect_all()!
            //        Redundant code alert!!
            //  this.items_reselect_all();

            this.repopulate_self_and_children();
         }
      }

      // This implements the on_panel_show function. Derived classes should
      // override this. The on_panel_show fcn., in this class, only thunks to
      // this function if CREATION_COMPLETE has been indicated.
      //
      // NOTE: Derived classes should avoid using this fcn. as the update()
      //       fcn. That is: if nothing has changed, don't re-draw everything.
      //       (This fcn. gets called whenever the panel is displayed, so if
      //       the user is just clicking around the tabs, don't waste the
      //       resources.)
      //

      //
      protected function repopulate() :void
      {
         // NOTE: We could poke our custom components, i.e.,
         //    for each (var child:Detail_Panel_Base in this.panel_children) {
         //       child.repopulate();
         //    }
         //       but instead we don't. The on_panel_show fcn. will call
         //       each child's on_panel_show fcn., and on_panel_show will
         //       call repopulate if it sees that the child is marked dirty.
         m4_DEBUG('repopulate: doing nothing');
      }

      //
      protected function unpopulate() :void
      {
         m4_DEBUG('unpopulate: doing nothing');
      }

      // *** Event handlers

      // Before we let Flash initialize the component, do a little dance and
      // hack in some additional <state>s. Once one class puts <state></state>
      // in its MXML, no descendants can do the same, because their definition
      // just replaces the parent's. Instead, children put their states in an
      // Array, which we, as the smart parent, add to our states collection.
      // Note that this only solves the problem for one layer of children; if a
      // child's child wanted to add its own additional states, we'd have to
      // come up with a unique name for their Array, and so on, for every
      // additional generation in the class hierarchy.
      protected function on_preinitialize(event:FlexEvent) :void
      {
         var state_array_name:String;
         m4_VERBOSE('on_preinitz:', getQualifiedClassName(this), '/', this.id);
         // Look for, e.g., this.new_states...
         for each (state_array_name in panel_states_array) {
            //m4_VERBOSE('on_preinitialize: looking for:', state_array_name);
            if ((this.hasOwnProperty(state_array_name))
                && (this[state_array_name] !== null)) {
               //m4_VERBOSE('on_preinitialize: found', this[state_array_name]);
               m4_VERBOSE('on_preinitialize: found state:', state_array_name);
               this.states = this.states.concat(this[state_array_name]);
            }
         }
         this.removeEventListener(FlexEvent.PREINITIALIZE,
                                  this.on_preinitialize);
      }

      //
      protected function on_initialize(event:FlexEvent) :void
      {
         m4_ASSERT(G.item_mgr !== null);

         this.parent_proxy = new ObjectProxy(this.parent);

         // BUG nnnn: MEMORY_USAGE: Add a question about removeEventListener
         // to the much bigger question of how and if we should manage memory
         // better in flashclient.
         this.removeEventListener(FlexEvent.INITIALIZE, this.on_initialize);
      }

      // Listen for Flash to tell us it's created our child components,
      // lest we play with them before they exist (via creationComplete).
      protected function on_creation_complete(event:FlexEvent) :void
      {
         m4_TALKY('creatn_compl:', getQualifiedClassName(this));
         // We only get called once per object lifetime.
         m4_ASSERT(!this.creation_completed);
         // I expected to find a parent attribute, maybe in UIComponent, that
         // indicates if creation is complete, but I couldn't find one. So we
         // maintain our own. [lb]
         this.creation_completed = true;
         // If on_panel_show was called while we were being created, we bailed
         // earlier, so call it again.
         if (this.on_show_pending) {
            m4_ASSERT(G.map !== null);
            // Schedule a call to on_panel_show.
            m4_DEBUG('on_creation_complete: on_show_pending:', this);
            m4_DEBUG_CLLL('>callLater: on_creation_complete: on_panel_show');
            G.map.callLater(this.on_panel_show);
            this.on_show_pending = false;
         }
         this.removeEventListener(FlexEvent.CREATION_COMPLETE,
                                  this.on_creation_complete);
         // HMPF: [lb] wanted to call change_state from here, but
         //       trying to use this.hasState() first results in:
         //       ReferenceError: Error #1069: Property hasState not found...
         //       So instead we have to call it from the derived classes.
         this.on_resize(null);
      }

      //
      protected function on_remove_event(event:FlexEvent) :void
      {
         m4_DEBUG('on_remove_event: this:', this);
         m4_DEBUG('on_remove_event: target:', event.target);

         this.removeEventListener(FlexEvent.PREINITIALIZE,
                                  this.on_preinitialize);
         this.removeEventListener(FlexEvent.INITIALIZE,
                                  this.on_initialize);
         this.removeEventListener(FlexEvent.CREATION_COMPLETE,
                                  this.on_creation_complete);
         // Skipping:
         // this.removeEventListener(ResizeEvent.RESIZE, this.on_resize,
         //                          false, 0, true);
         this.removeEventListener(FlexEvent.SHOW,
                                  this.on_show_event);
         this.removeEventListener(FlexEvent.HIDE,
                                  this.on_hide_event);

         this.removeEventListener(FlexEvent.REMOVE,
                                  this.on_remove_event);

         this.removeEventListener(Event.ADDED,
                                  this.on_added_event);
         this.removeEventListener(Event.REMOVED,
                                  this.on_removed_event);
      }

      // This isn't actually wired via addEventListener. We just call it
      // directly.
      public function on_resize(event:ResizeEvent=null) :void
      {
         m4_VERBOSE('on_resize: Doing nothing.');
      }

      // *** Startup and Show method thunks

      //
      protected function on_hide_event(event:FlexEvent) :void
      {
         m4_VERBOSE2('on_hide_event: this:', this,
                     '/ showing:', this.is_showing);

         // There's two ways we get to this fcn. Obviously, our panel is being
         // closed. But it could be something we initiated (say, the user
         // clicked on empty map space, so we cleared the selection and told
         // Panel_Manager to show a different panel) or it could be something
         // we're just now learning about (say, the user clicked a different
         // tab bar button in side_panel).

         if (G.panel_mgr.effectively_active_panel === this) {

            m4_DEBUG2('on_hide_event: was effectively_active_panel:',
               G.panel_mgr.effectively_active_panel, '/ now: (always) null');

            G.panel_mgr.effectively_active_panel = null;

            this.panel_selection_clear(/*force_reset=*/false);

            this.on_panel_hide();
         }
         else {
            // MAYBE: Should Widget override, or doesn't it come through here?
            m4_DEBUG('on_hide_event: not effectively_active_panel:', this);
         }

         this.is_showing = false;

         // MAYBE: Bother calling this.depopulate_self_and_children()?
      }

      //
      public function on_show_event(event:FlexEvent=null) :void
      {
         m4_TALKY2('on_show_event: this:', this,
                   '/ creation_completed:', this.creation_completed);
         // This assumes Detail_Panel_Widget::on_show_event is never called.
         if (G.panel_mgr.effectively_active_panel !== this) {
            m4_DEBUG5(
               'on_show_event (panel_show): was effectively_active_panel:',
               ((G.panel_mgr.effectively_active_panel !== null)
                ? G.panel_mgr.effectively_active_panel: 'null'),
                '/ now:', this);
            G.panel_mgr.effectively_active_panel = this;
            this.on_panel_show();
         }
         if (!this.items_panel_height_set) {
            var dummy_event:ResizeEvent = null;
            this.on_resize(dummy_event);
            this.items_panel_height_set = true;
         }
         this.is_showing = true;
         // 2013.03.20: Don't forget to repopulate if the panel is dirty
         // (this is comparable to what on_panel_show does).
         this.repopulate_self_and_children();
      }

      //
      protected function repopulate_self_and_children() :void
      {
         this.repopulate_self_maybe();
         var child:Detail_Panel_Base;
         for each (child in this.panel_children) {
            child.repopulate_self_and_children();
         }
      }

      //
      protected function repopulate_self_maybe() :void
      {
         if (this.dirty_reasons != Dirty_Reason.not_dirty) {
            m4_VERBOSE2('repopulate_self_maybe: this:', this,
                        '/ dirty_reasons:', this.dirty_reasons);
            this.dirty_reasons = Dirty_Reason.not_dirty;
            if ((this.items_selected !== null)
                && (this.items_selected.length > 0)) {
               // m4_DEBUG('repopulate_self_maybe: repopulate');
               this.repopulate();
            }
            else {
               // m4_DEBUG('repopulate_self_maybe: depopulate');
               // This just calls repopulate() unless overriden.
               this.depopulate();
            }
         }
         else {
            m4_VERBOSE2('repopulate_self_maybe: this:', this,
                        '/ dirty_reasons:', this.dirty_reasons);
         }
      }

/*/ FIXME: Statewide UI: Move toggle_enabled code to repopulate.
      protected function toggle_enabled_impl() :void
      {
         // In V1, this fcn. used to toggle mouseEnabled and mouseChildren,
         // enabling them if utils.rev_spec.Working and G.map.zoom_is_vector,
         // and disabling them otherwise. But this is really confusing, as the
         // user's mouse all of sudden stops doing anything useful, yet we
         // never tell the user why, and the controls in the panel still look
         // like they should be useable. So now, we don't do anything
         // here. Descendants should disable individual controls as
         // appropriate, but let's not touch the mouse.

         // FIXME: Do the Diff panels need this code after all?
         if ((G.map.rev_viewport is utils.rev_spec.Working)
             && G.map.zoom_is_vector()) {
            this.mouseEnabled = true;
            this.mouseChildren = true;
         }
         else {
            this.mouseEnabled = false;
            this.mouseChildren = false;
         }

         for each (var child:Detail_Panel_Base in this.panel_children) {
            child.toggle_enabled();
         }
      }
/*/

      // *** VerticalScrollBar helpers

      //
      protected function has_auto_scroll_bar_policy() :Boolean
      {
         return false;
      }

      //
      public function has_VerticalScrollBar() :Boolean
      {
         var target:Container = this.vertical_scrollbar_target
         return Detail_Panel_Base.has_VerticalScrollBar_(target);
      }

      //
      public static function has_VerticalScrollBar_(target:Container) :Boolean
      {
         var vsb_active:Boolean = true;
         if ((target === null)
             || (target.verticalScrollBar === null)
             || (target.verticalScrollBar.visible == false)) {
            vsb_active = false;
         }
         return vsb_active;
      }

      //
      // Scroll position, not to be confused with poll position.
      public function get vsb_scroll_position() :int
      {
         // Oops, what I really wanted was the dropdown's y compared to
         // the scrolling container, how dingus [lb]!
         // See: Widget_Bike_Facility.on_mode_change...bike_facil_button.
         m4_ASSERT(false); // Not used; not tested.

         var scroll_posit:int = 0;
         if (this.has_VerticalScrollBar()) {
            scroll_posit =
               this.vertical_scrollbar_target.verticalScrollPosition;
         }
         m4_DEBUG('vsb_scroll_position: scroll_posit:', scroll_posit);
         return scroll_posit;
      }

      //
      // NOTE: This fcn. could be used for ViewStack children that have scroll
      //       bar issues, but it's tricky to use -- if we hook added, when
      //       the scroll bar is being added, it hasn't been sized, so its
      //       width is 0. For now, hard-coding 16 (where needed) as the scroll
      //       bar width... but maybe this fcn.'ll be useful someday.
      public function get vsb_width() :int
      {
         var target:Container = this.vertical_scrollbar_target
         return Detail_Panel_Base.get_vsb_width_(target);
      }

      //
      public function set vsb_width(ignored:int) :void
      {
         m4_ASSERT(false);
      }

      //
      public static function get_vsb_width_(target:Container) :int
      {
         var vsb_width:int = 0;
         if (Detail_Panel_Base.has_VerticalScrollBar_(target)) {
            vsb_width = target.verticalScrollBar.width;
         }
         m4_DEBUG('vsb_width:', vsb_width);
         return vsb_width;
      }

      // ***

      // C.f. above.

      //
      public static function has_HorizontalScrollBar_(target:Container) :Boolean
      {
         var hsb_active:Boolean = true;
         if ((target === null)
             || (target.horizontalScrollBar === null)
             || (target.horizontalScrollBar.visible == false)) {
            hsb_active = false;
         }
         return hsb_active;
      }

      //
      public static function get_hsb_height_(target:Container) :int
      {
         var hsb_height:int = 0;
         if (Detail_Panel_Base.has_HorizontalScrollBar_(target)) {
            hsb_height = target.horizontalScrollBar.height;
         }
         m4_DEBUG('hsb_height:', hsb_height);
         return hsb_height;
      }

      // ***

      //
      public function on_added_event(event:Event) :void
      {
         // m4_VERBOSE('on_added_event: event.target:', event.target);
         this.on_added_or_removed_event(event, true);
      }

      //
      public function on_removed_event(event:Event) :void
      {
         // m4_VERBOSE('on_removed_event: event.target:', event.target);
         this.on_added_or_removed_event(event, false);
      }

      //
      public function on_added_or_removed_event(event:Event, added:Boolean)
         :void
      {
         if (event.target is VScrollBar) {
            m4_VERBOSE2('_added_or_removed: target.parent:',
                        event.target.parent);
            if (event.target.parent === this.vertical_scrollbar_target) {
               var paddingRight:int = this.getStyle('paddingRight');
               // One solution is to see if the scroll bar is a child and has
               // width, but when being added, it doesn't have a width yet. So
               // we base the decision on the added param, and not showing.
               var scrollbar_showing:Boolean = this.has_VerticalScrollBar();
               m4_VERBOSE(' .. paddingRight:', paddingRight);
               m4_VERBOSE(' .. added:', added);
               m4_VERBOSE(' .. scrollbar_showing:', scrollbar_showing);
               // Nope: this.on_vertical_scrollbar_changed(scrollbar_showing);
               this.on_vertical_scrollbar_changed(added);
            }
         }
      }

      //
      protected function on_vertical_scrollbar_changed(added:Boolean) :void
      {
         m4_VERBOSE('on_vertical_scrollbar_changed: added:', added);
         if (added) {
            this.vertical_scrollbar_target.setStyle('paddingRight', 8);
         }
         else {
            this.vertical_scrollbar_target.setStyle('paddingRight', 0);
         }
      }

      /*/ NOTE: [mm] had simultaneously found this solution to the scrollbar
                     problem:
      // Adjust paddingRight depending on whether scrollbar is visible.
      // Solution adapted from http://www.nbilyk.com/flex-scrollpolicy-bug
      override public function validateSize(recursive:Boolean = false) :void
      {
         super.validateSize(recursive);
         if (!initialized) {
            return;
         }
         if (this.height < this.measuredHeight) {
            this.setStyle('paddingRight', G.app.pad);
         }
         else {
            this.setStyle('paddingRight', 0);
         }
      }
      /*/

      // *** State change handlers

      //
      public function change_state(new_state:String) :void
      {
         if ((this.currentState != new_state)
             || ((this.currentState === null)
                 && (new_state == ''))) {
            m4_DEBUG5('changing state: to:',
                      (new_state !== null) ? new_state : 'null',
                      '/ from:', (this.currentState !== null)
                                 ? this.currentState : 'null',
                      '/ this:', this);
            // this.currentState = new_state;
            // MAYBE: Set this.transitions and play 'em.
            var playTransition:Boolean = false;
            this.setCurrentState(new_state, playTransition);
         }
      }

      //
      protected function on_enter_state_base() :void
      {
         // No-op.
         m4_DEBUG('Entering state base!');
      }

      //
      protected function on_enter_state_default() :void
      {
         // No-op, and currently, no class overrides this method.
         m4_DEBUG('on_enter_state_default: entering state: default');
      }

      // ***

      //
      override public function toString() :String
      {
         //return (super.toString()
         //return (this.class_name_snip
         //        + getQualifiedClassName(this)
         return (this.class_name_tail
                 + ' / no. sel: '
                    + ((this.items_selected_ !== null)
                       ? this.items_selected_.length : 'null')
                 + ((this.is_showing_) ? ' / is showing' : '')
                 + ((this.on_show_pending) ? ' / show pending' : '')
                 + ((this.panel_close_pending) ? ' / close pending' : '')
                 );
      }

      //
      public function toString_Terse() :String
      {
         return (Strutil.class_name_tail(super.toString())
                 + ((this.is_showing_) ? ' is_showg' : '')
                 + ((this.on_show_pending) ? ' show_pendg' : '')
                 + ((this.panel_close_pending) ? ' close_pendg' : '')
                 + ' ' + ((this.items_selected_ !== null)
                          ? this.items_selected_.length : 'none')
                         + ' selected'
                 );
      }

   }
}


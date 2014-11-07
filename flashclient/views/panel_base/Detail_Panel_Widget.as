/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_base {

   import flash.utils.getQualifiedClassName;
   import mx.core.Container;
   import mx.events.FlexEvent;

   import items.Item_User_Access;
   import items.Item_Versioned;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Detail_Panel_Widget extends Detail_Panel_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@DtlPnl_Wdgt');

      // *** Instance variables

      // This is the panel the created us and added us to its, er, panel
      protected var dp:Detail_Panel_Base;

      // *** Constructor

      public function Detail_Panel_Widget()
      {
         super();
      }

      // *** Getters/Setters

      // The panel that creates us and adds us has to tell us who it is.
      public function get detail_panel() :Detail_Panel_Base
      {
         return this.dp;
      }

      //
      public function set detail_panel(dp:Detail_Panel_Base) :void
      {
         m4_VERBOSE('detail_panel: init dp for:', getQualifiedClassName(this));
         this.dp = dp;
         for each (var child:Detail_Panel_Widget in this.panel_children) {
            child.detail_panel = dp;
         }
      }

      //
      override public function get feats_ordered() :Array
      {
         return this.dp.feats_ordered;
      }

      //
      override public function set feats_ordered(feats_ordered:Array) :void
      {
         m4_ASSERT(false);
      }

      //
      override public function get feats_selected() :Set_UUID
      {
         var feats_selected:Set_UUID;
         if (this.dp !== null) {
            m4_VERBOSE('feats_selected: deferring to this.dp:', this.dp);
            feats_selected = this.dp.feats_selected;
         }
         else {
            m4_WARNING('feats_selected: no dp, returning empty Set');
            feats_selected = new Set_UUID();
         }
         return feats_selected;
      }

      //
      override public function set feats_selected(feats_selected:Set_UUID)
         :void
      {
         // This is only called from on_remove_event.
         m4_ASSERT(feats_selected === null);
      }

      //
      override public function get items_selected() :Set_UUID
      {
         // Widgets are nested, so climb, climb, climb until we find the actual
         // Detail_Panel_Base that's not a widget.
         var items_selected:Set_UUID;
         if (this.dp !== null) {
            m4_VERBOSE('items_selected: deferring to this.dp:', this.dp);
            items_selected = this.dp.items_selected;
         }
         else {
            m4_WARNING('items_selected: no dp, returning empty Set');
            items_selected = new Set_UUID();
         }
         return items_selected;
      }

      //
      override public function set items_selected(items_selected:Set_UUID)
         :void
      {
         // This is only called from on_remove_event.
         m4_ASSERT(items_selected === null);
      }

      //
      override public function get panel_active_child() :Detail_Panel_Base
      {
         // A widget should be getting asked what the active sub panel is,
         // since a widget belongs to a panel; wrong direction of inquiry.
         m4_ASSERT(false);
         return null;
      }

      //
      override public function get panel_owning_panel() :Detail_Panel_Base
      {
         var owning_panel:Detail_Panel_Base = null;
         if (this.dp !== null) {
            m4_ASSERT(this.dp === this.dp.panel_owning_panel);
            owning_panel = this.dp.panel_owning_panel;
         }
         else {
            m4_ASSERT_SOFT(false);
         }
         return owning_panel;
      }

      // *** Instance methods

      //
      override protected function add_listeners_show_and_hide(
         just_kidding:*=null) :void
      {
         // Unlike Detail_Panel_Base, widgets don't normal listen on show and
         // hide, since there are a lot of them and most don't need it. Most
         // widgets listen on specific item changes or other events, but don't
         // tend to care when they're shown or hidds.
         if (just_kidding === null) {
            just_kidding = true;
         }
         super.add_listeners_show_and_hide(just_kidding);
      }

      //
      override public function dirty_set(reason:uint) :void
      {
         super.dirty_set(reason);
         for each (var child:Detail_Panel_Widget in this.panel_children) {
            child.dirty_set(reason);
         }
      }

      //
      override public function is_dirty() :Boolean
      {
         var is_dirty:Boolean = super.is_dirty();
         if (!is_dirty) {
            for each (var child:Detail_Panel_Widget in this.panel_children) {
               is_dirty = child.is_dirty();
               if (is_dirty) {
                  break;
               }
            }
         }
         return is_dirty;
      }

      //
      override public function panel_selection_clear(
         force_reset:Boolean=false,
         dont_deselect:*=null)
            :void
      {
         // No-op.
      }

      //
      override protected function items_reselect_all() :void
      {
         // No-op.
      }

      //
      protected function on_entry_tooltip_shown() :void
      {
         var item:Item_User_Access = (this.data as Item_User_Access);
         // FIXME Should this (and others) just send system_id?
         G.sl.event('ui/container/item_detail/tooltip_shown',
                    {stack_id: item.stack_id, version: item.version});
      }

      //
      override protected function on_remove_event(ev:FlexEvent) :void
      {
         super.on_remove_event(ev);
         // If we're a registered widget, make it not so.
         this.dp.deregister_widget(this);
      }

      //
      override public function panel_title_get() :String
      {
         // NOTE: This is the title of the owning, first-level panel, and not
         //       of the tab-of-tabs panel.
         m4_WARNING('panel_title_get: being called on a widget?');
         var panel_title:String = '';
         if (this.dp !== null) {
            panel_title = this.dp.panel_title_get();
         }
         else {
            m4_WARNING('panel_title_get: ... and no dp in sight!');
         }
         return panel_title;
      }

      //
      override protected function register_widgets(panel_children:Array) :void
      {
         // NOTE: Not calling super.register_widgets(panel_children);
         // Not so anymore: m4_ASSERT(this.dp !== null);
         this.register_widgets_impl(panel_children, this.dp);
      }

      //
      override protected function set_panel_tool_tip() :void
      {
         // No-op.
      }

      // *** The hide/show/repopulate fcns.

      //
      override public function on_panel_hide() :void
      {
         // The on_panel_hide is called for the Detail_Panel_Base or its first
         // active Detail_Panel_Widget child (i.e., sub-panel tab).
         super.on_panel_hide();
      }

      //
      override public function on_panel_show() :void
      {
         super.on_panel_show();
      }

      //
      override protected function repopulate() :void
      {
         // No-op
         m4_VERBOSE('repopulate: doing nothing');
      }

      // ***

      //
      override protected function on_hide_event(ev:FlexEvent) :void
      {
         m4_ASSERT(false); // Unexpected.
      }

      //
      override public function on_show_event(ev:FlexEvent=null) :void
      {
         m4_ASSERT(false); // Unexpected.
      }

      // ***

   }
}


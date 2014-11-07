/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class manages the main.mxml's
//   side_panel (ViewStack); and
//   side_panel_tabs (Launchers, a ToggleButtonBar).
// It works with the Item_Manager and the Map to handle
// changing panels which also includes changing the map
// selection (in CcpV3, each panel has its own selected
// items set). Selected item sets are like Web browser
// tabs in a sense... oh, bug idea!:
// BUG nnnn: Add a lock-viewport button to item panels
//           so users can lock the viewport to each
//           selected items set.

package views.base {

   import flash.display.DisplayObject;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.utils.Dictionary;
   import mx.containers.VBox;
   import mx.containers.ViewStack;
   import mx.controls.Alert;
   import mx.controls.Button;
   import mx.controls.TabBar;
   import mx.core.UIComponent;
   import mx.core.Container;
   import mx.events.IndexChangedEvent;

   import grax.Dirty_Reason;
   import items.Item_Versioned;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_base.Detail_Panel_Widget;
   import views.panel_items.Panel_Item_Versioned;

   public class Panel_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Panel_Mgr');

      // Our own collection of panels.
      // Currently, this collection is just used to set all panels dirty for
      // certain operations.
      public var panel_lookup:Set_UUID = new Set_UUID();

      // A plethora of stimuli may request that panels be dirtied and updated,
      // but we use callLater to defer updating until the end of the Flex
      // execution cycle. We use this variable to keep track of when an update
      // has been requested, so we don't unnecessarily call callLater tooMuch.
      public var activate_panel_next:Detail_Panel_Base = null;
      // We also maintain a handle on the active panel, even if it's not really
      // active yet. This is because we can't rely on the ViewStack -- when a
      // piece of code chooses to make a panel active, Flex doesn't make it
      // active until we complete our current frame, but we often make
      // decisions in code about the active panel before we end the frame that
      // changed the active_panel. So the panel is, like, *effectively* active.
      protected var effectively_active_panel_:Detail_Panel_Base = null;
      public var panel_stack_prev_eap:Detail_Panel_Base = null;

      // A debug var:
      protected var activate_panel_called_cnt:int = 0;

      public var layout_theme:String = 'layout_mm';

      // *** Constructor

      //
      public function Panel_Manager() :void
      {
         // This class requires that the Item_Manager be created first.
         m4_DEBUG('Welcome to the Panel_Manager!');
      }

      // REMINDER: G.app.side_panel is a ViewStack that holds the panels. It
      // starts out with panels with permanent tab buttons, and then we
      // dynamically add and remove panels as necessary.

      // *** Basic fcns.

      //
      public function change_layout_theme(layout_name:String) :void
      {
         m4_DEBUG('change_layout_theme: layout_name:', layout_name);
         this.layout_theme = layout_name;
         m4_DEBUG('change_layout_theme: panels_mark_dirty');
         this.panels_mark_dirty();
      }

      // Called when the user clicks one of the side panel tabs. See
      // side_panel_tabs (Launchers.mxml) and side_panel (ViewStack).
      public function on_side_panel_change(ev:IndexChangedEvent) :void
      {
         // FIXME: Test and verify this is only called when user clicks tab or
         //        uses <Tab>, else change comments herein.
         // m4_DEBUG('on_side_panel_change: ev:', ev, '/', ev.target);
         m4_DEBUG('on_side_panel_change:', ev.target);
         m4_TALKY2('on_side_panel_change: side_panel.numChildren:',
                   G.app.side_panel.numChildren);
         m4_TALKY2('on_side_panel_change: side_panel_tabs.numChildren:',
                   G.app.side_panel_tabs.numChildren);
         m4_TALKY2('on_side_panel_change: side_panel_tabs.selectedIndex:',
                   G.app.side_panel_tabs.selectedIndex);

         // FIXME: [mm] wonders what we do this item_panel?
         var item_panel:Panel_Item_Versioned = (this.active_parent
                                                as Panel_Item_Versioned);
         // [lb] doubts this'll happen because Detail_Panel_Base.on_show_event
         //      updates this just before code gets here.

         // This fcn is called after the outgoing Detail_Panel_Base gets
         // its on_hide_event (after panel_show is called (which is called
         // because of panel_activate)) but before the next panel gets its
         // on_show_event. We're also called if the user clicks a tab button
         // in the tab bar. So we can be triggered by our own code because
         // the user did something on the map, or we can be triggered by Flex
         // because the user clicked a tab bar button.

         // Update some generic, panelly things.
         this.update_bg_and_title();
         // Hide the tab highlight since the user explicitly changed tabs.
         // 2013.02.28: This behavior is disabled... at least for now.
         //    this.tab_highlight_set(ev.newIndex, false);
         //    this.tab_highlight_set(ev.oldIndex, false);
      }

      // *** Tabby methods

      // Return the Button instance that's the tab header at the given index
      // within the side panel tab bar
      //public function tab_button_get(index:int, tabbar:TabBar=null) :Button
      // MAYBE: [lb] would like to see this fcn. protected.
      public function tab_button_get(index_or_panel:*) :Button
      {
         m4_ASSERT(false); // Deprecated. See comments elsewhere.

         var tab_button:Button = null;
         var tab_index:int = this.tab_index_get(index_or_panel);
         if (tab_index != -1) {
            tab_button = G.app.side_panel_tabs.getChildAt(tab_index) as Button;
         }
         else {
            m4_WARNING('tab_button_get: not found:', index_or_panel);
         }
         return tab_button;
      }

      // STYLE_GUIDE: This fcn. used to support indices, but those
      // MAGIC_NUMBERs are tied to the GUI, so use the actual object
      // reference instead, otherwise your code is tightly coupled to
      // the GUI layout.
      public function tab_index_get(index_or_panel:*) :int
      {
         var tab_index:int = -1;
         if (index_or_panel is Detail_Panel_Base) {
            // We want the side_panel_tabs tab index, so make sure we're got
            // the first-level child of the side_panel ViewStack.
            var dpanel:Detail_Panel_Base = index_or_panel.panel_owning_panel;
            if (G.app.side_panel.contains(dpanel)) {
               tab_index = G.app.side_panel.getChildIndex(dpanel);
               m4_DEBUG('tab_index_get: tab_index:', tab_index);
            }
            else {
               m4_DEBUG('tab_index_get: panel not in ViewStack:', dpanel);
            }
         }
         else if (index_or_panel !== null) {
            // This path is deprecated. Enough with the MAGIC_NUMBERs.
            // Let's refer to objects properly by their handles.
            m4_ASSERT(false);
            tab_index = (index_or_panel as int);
         }
         return tab_index;
      }

      // Highlights a tab that isn't the tab of the active panel. This is used
      // to indicate to the user, e.g., that they can click the Item Details
      // tab to see info. about the item they just selected.
      //
      // 2013.02.28: Statewide UI: This fcn. now deprecated. Let's keep the
      //             code, though. We might one day want to reimplement
      //             something like this (that is, some way to indicate
      //             changes to a panel in another tab).
      protected function tab_highlight_set(index_or_panel:*,
                                           value:Boolean) :void
      {
         m4_ASSERT(false); // See comment above. Saving code, but deprecated.

         m4_DEBUG2('tab_highlight_set: index_or_panel:', index_or_panel,
                   'value:', value);
         var tabbar:TabBar = null;
         // Decode this first fcn. param
         var tab_index:int = this.tab_index_get(index_or_panel);
         //
         if (tab_index >= 0) {
            // Highlight the appropriate tab.
            var colors:Array;
            if (value) {
               colors = [Conf.save_button_fill_light,
                         Conf.save_button_fill_dark,];
            }
            else {
               colors = [Conf.button_fill_light, Conf.button_fill_dark];
            }
            this.tab_button_get(tab_index).setStyle('fillColors', colors);
         }
      }

      // *** Update meta-stuff

      //
      public function update_bg_and_title() :void
      {
         m4_DEBUG_CLLL('<callLater?: this.update_bg_and_title');
         // DEPRECATED: Statewide UI: No more weird tab highlights.
         //             But keeping the code, lest we find a new need for 'em.
         //  this.update_panel_background_color();
         this.update_panel_title();
      }

      //
      protected function update_panel_background_color() :void
      {
         m4_ASSERT(false); // Deprecated. See comments elsewhere.

         var sel_index:int = G.app.side_panel_tabs.selectedIndex;
         var pnl:UIComponent = null;
         var bg_color:uint = 0xffffff;
         // m4_DEBUG('update_panel_background_color: sel_index:', sel_index);
         // Set the side panel background color.
         if (G.app.side_panel.selectedChild !== null
             && G.app.side_panel.selectedChild.numChildren > 0) {
            pnl = G.app.side_panel.selectedChild.getChildAt(0) as UIComponent;
         }
         if ((pnl !== null) && (pnl.getStyle("backgroundColor"))) {
            bg_color = pnl.getStyle("backgroundColor");
         }
         G.app.side_panel_frame.setStyle('backgroundColor', bg_color);
         G.app.item_navver.setStyle('backgroundColor', bg_color);
         if (sel_index != -1) {
            this.tab_button_get(sel_index).setStyle(
               'fillColors', [bg_color, bg_color]);
         }
      }

      //
      public function update_panel_title() :void
      {
         // Update the side panel title. Note that we use the owning panel. If
         // the active_panel is the tab of a tab, when this fcn. is called,
         // the widget's this.dp may not be set (e.g., Panel_Item_Route uses
         // states, and the state change hasn't completed, so the detail_panel
         // isn't wired to the widget). Also, the widget's title isn't what we
         // want (and this.active_panel might be a widget, i.e., a tab of a
         // tab), so the safest thing to do (e.g., to avoid null object
         // reference) is to use the active_parent, which doesn't involve
         // widget math.
         var active_parent:Detail_Panel_Base = this.active_parent;
         if (active_parent !== null) {
            m4_DEBUG('update_panel_title: active_parent:', active_parent);
            var panel_title:String = active_parent.panel_title_get();
            m4_DEBUG(' >> panel_title:', panel_title);
            G.app.item_navver.nav_panel_title.htmlText = panel_title;
         }

         // NOTE: Never happens: nav_help_jumper.visible = false;
         G.app.item_navver.nav_help_jumper.visible = true;
      }

      // *** Panel magic

      // Return the active normal panel (and by active, we mean the panel
      // that's on top of all the rest and interacting with the user; it's the
      // one with the focus that hides all the other panels, i.e., not
      // necessarily effectively_active_panel).
      [Bindable] protected function get active_panel() :Detail_Panel_Base
      {
         var panel_or_ctr:Detail_Panel_Base;
         panel_or_ctr = (G.app.side_panel.selectedChild as Detail_Panel_Base);
         if (panel_or_ctr === null) {
            // If the user clicks a tab while the map is initially loading, we
            // have not loaded that panel yet.
            //? m4_ASSERT(G.app.side_panel.numChildren == 0);
            // 2013.02.28: Does this ever happen?
            // Seems to happen if you're opening/closing panels quickly...
            m4_WARNING('get active_panel: nothing active yet');
         }
         else {
            // See if the panel is a panel container or just a panel. A panel
            // container is usually a tab control of panels, so you click a
            // tab bar button in the side_panel_tabs which corresponds to
            // either a panel or to a panel of panels. We need this two level
            // obfuscation so that code can activate a panel in a container
            // panel, and we'll activate the tab bar button and the top-level
            // ViewStack side_panel panel, and then we'll tell the panel to go
            // to the correct sub-tab.
            m4_DEBUG('get active_panel: panel_or_ctr:', panel_or_ctr);
            panel_or_ctr = panel_or_ctr.panel_active_child;
            m4_DEBUG2('get active_panel: panel_or_ctr.panel_active_child:',
                      panel_or_ctr);
            // We've got a handle to the Detail_Panel_Base that a user would
            // send to panel_activate (i.e., you never activate panel
            // containers, or, if you did, if would default to the first tab
            // child panel).
            //
            // Not true: m4_ASSERT(panel_or_ctr !== null);
         }
         return panel_or_ctr;
      }

      //
      protected function set active_panel(panel:Detail_Panel_Base) :void
      {
         m4_ASSERT(false);
      }

      //
      [Bindable] protected function get active_parent() :Detail_Panel_Base
      {
         var dpanel:Detail_Panel_Base;
         dpanel = (G.app.side_panel.selectedChild as Detail_Panel_Base);
         m4_ASSERT((dpanel === null) || (!(dpanel is Detail_Panel_Widget)));
         return dpanel;
      }

      //
      protected function set active_parent(panel:Detail_Panel_Base) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get effectively_active_panel() :Detail_Panel_Base
      {
         return this.effectively_active_panel_;
      }

      //
      public function get effectively_next_panel() :Detail_Panel_Base
      {
         var curr_panel:Detail_Panel_Base = null;
         if (G.panel_mgr.activate_panel_next !== null) {
            curr_panel = G.panel_mgr.activate_panel_next;
         }
         else if ((G.panel_mgr.effectively_active_panel !== null)
             && (!G.panel_mgr.effectively_active_panel.panel_close_pending)) {
            curr_panel = G.panel_mgr.effectively_active_panel;
         }
         return curr_panel;
      }

      //
      public function set effectively_active_panel(dpanel:Detail_Panel_Base)
            :void
      {
         var old_panel:Detail_Panel_Base = null;
         if (this.effectively_active_panel_ !== dpanel) {
            old_panel = this.effectively_active_panel_;

            // Sometimes we set effectively_active_panel to null before setting
            // it to the next panel, e.g., when the user makes a new item
            // selection on the map, if we didn't clear the panel, the item
            // would try to add itself to the active panel's selection set. At
            // other times, though, we'll just change from one panel to the
            // next, e.g., when the user clicks a side panel tab.
            if (dpanel !== null) {
               dpanel.panel_stack_unwire();
               // The last time we activated an eap, we remembered it, so that
               // after it's been set null, when the next panel is finally
               // specified, we can go back to the former eap and updates its
               // doubly-linked pointers.
               if ((this.panel_stack_prev_eap !== null)
                   && (this.panel_stack_prev_eap !== dpanel)) {
                  // This is the last effectively_active_panel_. We may have
                  // since set effectively_active_panel_ to null, and now
                  // we're setting it to the new panel.
                  m4_DEBUG2('set eap: panel_stack_prev:',
                            this.panel_stack_prev_eap);
                  m4_DEBUG('set eap: panel_stack_next:', dpanel);
                  this.panel_stack_prev_eap.panel_stack_next = dpanel;
                  dpanel.panel_stack_prev = this.panel_stack_prev_eap;
                  dpanel.panel_stack_next = null;
               }
            }

            this.effectively_active_panel_ = dpanel;

            if (old_panel !== null) {
               m4_DEBUG3(
                  'set effectively_active_panel: panel_selection_clear:',
                  old_panel);
               var force_reset:Boolean = false;
               old_panel.panel_selection_clear(force_reset/*=false*/);
               //old_panel.panel_stack_unwire();
            }
         }

         if (this.effectively_active_panel_ === null) {
            // Already done: G.map.map_selection_clear();
            m4_DEBUG('set effectively_active_panel: attachment_mode_stop');
            var skip_tool_change:Boolean = true;
            G.map.attachment_mode_stop(skip_tool_change/*=true*/);
         }
         else {
            this.panel_stack_prev_eap = this.effectively_active_panel_;
            m4_DEBUG3(
               'set effectively_active_panel: reactivate_selection_set:',
               this.effectively_active_panel_);
            this.effectively_active_panel_.reactivate_selection_set();
         }
      }

      // This is for non-multi-select, i.e., look for zero or one panel that
      // supports this item type.
      //
      // SIMILAR: find_supporting_panel and get geofeature_panel.
      public function find_supporting_panel(item:Item_Versioned)
         :Panel_Item_Versioned
      {
         var item_panel:Panel_Item_Versioned = null;
         m4_DEBUG('find_supporting_panel: item:', item);
         for each (var o:Object in this.panel_lookup) {
            var item_sidep:Panel_Item_Versioned;
            item_sidep = (o as Panel_Item_Versioned);
            m4_DEBUG('find_supporting_panel: item_sidep:', item_sidep);
            if ((item_sidep !== null)
                && (item is item_sidep.shows_type)) {
               m4_DEBUG2('find_supporting_panel: found accepting: item_sidep:',
                         item_sidep);
               item_panel = item_sidep;
               break;
            }
         }
         return item_panel;
      }

      //
      public function panel_activate(dpanel:Detail_Panel_Base,
                                     dirty:Boolean=true) :Boolean
      {
         var activated:Boolean = false;

         m4_DEBUG('panel_activate: dpanel:', dpanel, '/ dirty:', dirty);
         m4_ASSERT((G.app !== null) && (G.map !== null));

         var parent_panel:Detail_Panel_Base = dpanel.panel_owning_panel;
         m4_DEBUG('panel_activate: parent_panel:', parent_panel);
         m4_ASSERT_SOFT(parent_panel !== null);

         // First check that the first-level ViewStack panel is really part of
         // the ViewStack.
         try {
            var just_testing_idx:int;
            just_testing_idx = G.app.side_panel.getChildIndex(parent_panel);
            m4_ASSERT(just_testing_idx >= 0);
            // This panel is already part of the ViewStack. Moving along...
         }
         catch (e:ArgumentError) {
            // The panel is not part of the ViewStack. I.e.,
            //    "ArgumentError: Error #2025: The supplied DisplayObject must
            //                                 be a child of the caller.
            m4_DEBUG('panel_activate: addChild:', parent_panel);
            G.app.side_panel.addChild(parent_panel);
            // Panel is removed by Launchers.on_close_button_clicked, which
            // triggers on_remove_event. The button is only shown if closeable.
         }

         if ((dpanel.close_when_emptied)
             && ((dpanel.items_selected === null)
                 || (dpanel.items_selected.length == 0))) {
            m4_WARNING('panel_activate: dpanel already empty?:', dpanel);
            dpanel.panel_close_pending = true;
            //? dirty = true;
         }

         // Mark dirty if panel should be updated the next time it's displayed.
         if (dirty) {
            m4_DEBUG('panel_activate: dirty: dpanel:', dpanel);
            var schedule_activate:Boolean = false;
            m4_DEBUG('panel_activate: panels_mark_dirty:', dpanel);
            this.panels_mark_dirty([dpanel,],
                                   Dirty_Reason.item_data,
                                   schedule_activate);
         }

         // If the panel is dirty or not the active panel, (re)show it.
         if ((dirty) || (dpanel !== this.active_panel)) {
            if (dpanel === this.effectively_active_panel) {
               if (this.activate_panel_next === null) {
                  // This means Flex hasn't physically switched panels yet.
                  // So active_panel will be effectively_active_panel in the
                  // next frame.
                  m4_DEBUG('pnlact: already eff_act_pan: dpanel:', dpanel);
                  if (!dirty) {
                     dpanel.reactivate_selection_set();
                     dpanel = null;
                  }
               }
               else if (this.activate_panel_next === dpanel) {
                  // No need to call callLater again.
                  m4_DEBUG('pnlact: eap and activate_panel_next:', dpanel);
                  dpanel = null;
               }
               else {
                  m4_DEBUG2('pnlact: not activate_panel_next:', dpanel,
                            '/ next:', this.activate_panel_next);
               }
            }
            // else, dpanel is not effectively_active_panel; we'll sched it.
            if (dpanel !== null) {
               this.activate_panel_called_cnt++;
               if (this.activate_panel_next === dpanel) {
                  m4_DEBUG2('panel_activate: already activate_panel_next:',
                            dpanel);
               }
               else if (this.activate_panel_next !== null) {
                  // Do we care?
                  m4_DEBUG2('panel_activate: overwriting next: was:',
                            this.activate_panel_next);
               }
               m4_DEBUG2('panel_activate: setting activate_panel_next:',
                         dpanel);
               this.activate_panel_next = dpanel;
               // EXPLAIN: Why is this a callLater? Because we only want to
               // call it once per change, but it's called from a bunch of
               // places?
               m4_DEBUG_CLLL('>callLater: panel_activate: panel_activate_imp');
               G.map.callLater(this.panel_activate_impl);

               activated = true;
            }
            // else, dpanel is null, so we decided to no-op.
         }
         else if (dpanel !== this.effectively_active_panel) {
            // Do we care?
            m4_DEBUG3('panel_activate: is active_panel but not eff_act_pan:',
                      this.effectively_active_panel,
                      '/ dpanel:', dpanel);
         }
         else {
            // The dpanel is active_panel and also effectively_active_panel.
            if (this.activate_panel_next === dpanel) {
               m4_WARNING2('panel_activate: already eap, active, and next:',
                            dpanel);
               this.activate_panel_next = null;
            }
            else if (this.activate_panel_next !== dpanel) {
               // This happens on some commands which empty the panel selection
               // and then rebuild it.
               m4_WARNING2('panel_activate: already eap, active / not next:',
                            dpanel);
               this.activate_panel_next = null;
            }
            else {
               // this.activate_panel_next is null.
               m4_DEBUG2('panel_activate: already eap and active_panel:',
                         dpanel);
            }
         }

         return activated;
      }

      //
      protected function panel_activate_impl() :void
      {
         m4_DEBUG_CLLL('<callLater: panel_activate_impl');
         m4_DEBUG2('panel_activate_impl: activate_panel_called_cnt:',
                   this.activate_panel_called_cnt);
         this.activate_panel_called_cnt = 0;
         var dpanel:Detail_Panel_Base = this.activate_panel_next;
         while ((dpanel !== null) && (dpanel.panel_close_pending)) {
            m4_DEBUG('pnlacti: close_pending: dpanel:', dpanel);
            dpanel = dpanel.panel_stack_prev;
            m4_DEBUG2('pnlacti: close_pending: dpanel.panel_stack_prev:',
                      (dpanel !== null) ? dpanel.panel_stack_prev : 'null');
            // Cyclopath has three side panel tabs that never close.
            // So we should always find a non-closing dpanel.
         }
         if (dpanel !== null) {
            m4_DEBUG(' >> panel_activate_impl: panel_show:', dpanel);
            this.panel_show(dpanel);
         }
         else {
            // else, more than one callLater was scheduled.
            m4_DEBUG('panel_activate_impl: panel_next already processed');
         }
         // Wait until now to clear activate_panel_next.
         this.activate_panel_next = null;
      }

      //
      protected function panel_show(next_panel:Detail_Panel_Base) :void
      {
         // Find the effectively active panel. We say "effectively"
         // because there's the panel that corresponds to the side_panel_tabs
         // control, but in the ViewStack, the panel might contain additional
         // panels, i.e., tabs within tabs. So this is either the first-level
         // child of the side_panel ViewStack or it's one of those children.
         var next_parent:Detail_Panel_Base = next_panel.panel_owning_panel;
         var active_panel:Detail_Panel_Base = this.active_panel;
         var active_parent:Detail_Panel_Base = null;
         if (active_panel !== null) {
            active_parent = active_panel.panel_owning_panel;
         }
         m4_DEBUG4('panel_show (on_show_event): active: panel:',
            (active_panel !== null) ? active_panel.class_name_tail : 'null',
            '/ parent:',
            (active_parent !== null) ? active_parent.class_name_tail : 'null');
         m4_DEBUG4('panel_show:   next: panel:',
            (next_panel !== null) ? next_panel.class_name_tail : 'null',
            '/ parent:',
            (next_parent !== null) ? next_parent.class_name_tail : 'null');

         if ((active_panel !== null) && (active_panel !== next_panel)) {
            // Tell the panel it's being hidden. It might already know this.
            // But this ensures that it deselects its selected items set.
            active_panel.on_panel_hide();
            active_panel = null;
         }

         /*/
         // If the parents differ, change side_panel_tabs.
         var tab_index:int = this.tab_index_get(next_parent);
         m4_ASSERT(tab_index >= 0);
         if (tab_index != G.app.side_panel.selectedIndex) {
            // EXPLAIN: Does Flex update selectedIndex now, or after our frame
            //          completes?
            m4_DEBUG3('panel_show: before: selected idx:',
                      G.app.side_panel.selectedIndex,
                      '/', G.app.side_panel.selectedChild);
            G.app.side_panel.selectedIndex = tab_index;
            m4_DEBUG3('panel_show: after: selected idx:',
                      G.app.side_panel.selectedIndex,
                      '/', G.app.side_panel.selectedChild);
         }
         /*/
         // This is probably not necessary:
         m4_DEBUG('panel_show: selectedChild = next_parent:', next_parent);
         G.app.side_panel.selectedChild = next_parent;

         // Tell the parent to change its tab, too, maybe.
         if ((next_panel !== next_parent)
             && (next_panel !== next_parent.panel_active_child)) {
            m4_DEBUG('panel_active_child:', next_parent.panel_active_child);
            next_parent.panel_active_child = next_panel;
         }

         // Update the shared title control that sits atop the ViewStack.
         // NOTE: We just set G.app.side_panel.selectedIndex, which changes
         //       this.active_panel, but our active_panel might be a
         //       Detail_Panel_Widget that isn't wired to its owning
         //       Detail_Panel_Base yet (i.e., its this.dp isn't set).
         this.update_bg_and_title();

         // Always de-collapse the side_panel.
         if (!G.app.left_panel.visible) {
            G.app.left_panel.visible = true;
         }

         // Update the editing tools. The user's access didn't change,
         // so UI won't call our update_access() fcn. like it sometimes does.
         var access_changed:Boolean = false;
         UI.editing_tools_update(access_changed);

         m4_DEBUG2('panel_show: was effectively_active_panel:',
                   this.effectively_active_panel);
         m4_DEBUG('panel_show: next_parent:', next_parent);

         this.effectively_active_panel = next_parent;

         // Make sure to call the parent so it can repopulate, too.
         // This just updates the tab of the panel, if tabbed:
         //   next_panel.on_panel_show();
         next_parent.on_panel_show();

         // See BUG 2088: If we don't bring focus to the Attachment panel,
         // TabNavigator's keyDownHandler throws a null reference exception.
         // 2013.02.21: We no longer use a TabNavigator, but this action is
         // still nice.
         next_panel.setFocus();

         // NOTE: active_parent now points to the last panel that was showing.
         if ((active_parent !== null) && (active_parent.panel_close_pending)) {
            m4_DEBUG('panel_show: removing side panel tab button');
            // Remove the last parent from the side panel tabs, which calls
            // active_parent.panel_stack_removed_child().
            G.app.side_panel_tabs.remove_child(active_parent);
         }
      }

      // ***

      //
      public function item_panels_mark_dirty(itms_array_or_class:*) :void
      {
         if (itms_array_or_class is Array) {
            this.item_panels_mark_dirty_items(itms_array_or_class as Array);
         }
         else {
            m4_ASSERT(itms_array_or_class is Class);
            this.item_panels_mark_dirty_class(itms_array_or_class as Class);
         }
      }

      //
      protected function item_panels_mark_dirty_class(cls:Class) :void
      {
         var dirty_panels:Array = new Array();
         var idx:int = G.app.side_panel.numChildren - 1;
         m4_DEBUG2('item_panels_mark_dirty_class: cls:', cls,
                   '/ idx:', idx);
         while (idx >= 0) {
            var dpanel:Detail_Panel_Base = null;
            dpanel = (G.app.side_panel.getChildAt(idx) as Detail_Panel_Base);
            // Everything's a dpanel except for the fake vertical line VBox.
            if (dpanel !== null) {
               m4_VERBOSE(' .. dpanel:', dpanel);
               m4_ASSERT(dpanel !== null);
               if (dpanel is cls) {
                  m4_VERBOSE(' ...... adding: dpanel:', dpanel);
                  dirty_panels.push(dpanel);
               }
            }
            idx -= 1;
         }
         if (dirty_panels.length > 0) {
            m4_DEBUG2('item_panels_mark_dirty_class: panels_mark_dirty:',
                      dirty_panels);
            this.panels_mark_dirty(dirty_panels);
         }
         else {
            // 2013.03.06: Do we ever get here with items that have no panels?
            // m4_ASSERT(dirty_panels.length > 0);
            m4_WARNING('item_panels_mark_dirty_class: nothing found');
         }
      }

      //
      protected function item_panels_mark_dirty_items(itms:Array) :void
      {
         var dirty_panels:Set_UUID = new Set_UUID();
         var idx:int = G.app.side_panel.numChildren - 1;
         m4_DEBUG2('item_panels_mark_dirty_items: itms.length:', itms.length,
                   '/ idx:', idx);
         while (idx >= 0) {
            var item_panel:Panel_Item_Versioned = null;
            item_panel = (G.app.side_panel.getChildAt(idx)
                          as Panel_Item_Versioned);
            m4_VERBOSE(' .. item_panel:', item_panel);
            if (item_panel !== null) {
               // MAYBE: Using contains_any might not scale well...
               m4_VERBOSE(' .... items_selected:', item_panel.items_selected);
               m4_VERBOSE(' .... feats_selected:', item_panel.feats_selected);
               if ((item_panel.items_selected.contains_any(itms))
                   || ((item_panel.items_selected
                        !== item_panel.feats_selected)
                       && (item_panel.feats_selected.contains_any(itms)))) {
                  m4_VERBOSE(' ...... adding: item_panel:', item_panel);
                  dirty_panels.add(item_panel);
               }
            }
            idx -= 1;
         }
         if (dirty_panels.length > 0) {
            m4_DEBUG2('item_panels_mark_dirty_items: panels_mark_dirty:',
                      dirty_panels);
            this.panels_mark_dirty(dirty_panels.as_Array());
         }
         else {
            // 2013.03.06: Do we ever get here with items that have no panels?
            // m4_ASSERT(dirty_panels.length > 0);
            // 2014.08.19: This happens when you delete an item.
            if (itms.length == 1) {
               var item:Item_Versioned = (itms[0] as Item_Versioned);
               if (!item.deleted) {
                  m4_WARNING('item_panels_mark_dirty_items: !deleted:', item);
               }
               // else, item was deleted, so panel was closed.
            }
            else {
               m4_WARNING('item_panels_mark_dirty_items: nothing found');
            }
         }
      }

      // Updates panels to reflect changes in the item or items it's showing.
      // FIXME: Do: public function panels_mark_dirty(dirty_panels:Array) :void
      // NOTE: I tried "dirty_reason:int=Dirty_Reason.item_data" but got:
      // Error: Parameter initializer unknown or is not a compile-time constant
      public function panels_mark_dirty(
         dirty_panels_arr:Array=null,
         //dirty_reason:int=Dirty_Reason.item_data)
         dirty_reason:int=0,
         schedule_activate:Boolean=true)
            :void
      {
         if (dirty_reason == 0) {
            dirty_reason = Dirty_Reason.item_data;
         }
         m4_DEBUG3('panels_mark_dirty: reasons:',
                   Dirty_Reason.lookup_key[dirty_reason],
                   '/ schedule_activate:', schedule_activate);

         var dirty_panels:Set_UUID;
         if ((dirty_panels_arr === null) || (dirty_panels_arr.length == 0)) {
            // This path is just used to tell the side panels to update
            // themselves the next time they are displayed. It's really just a
            // cheap way (for the programmer) to make sure the panel views are
            // current.
            m4_ASSERT((dirty_reason == Dirty_Reason.item_data)
                      || (dirty_reason == Dirty_Reason.item_grac)
                      //?|| (dirty_reason == Dirty_Reason.item_schg)
                      );
            // Also, the length is never 0, the arr is just null.
            // 2013.03.06: Asserting on tag delete.
            // 2014.07.21: Fixed maybe? [lb] tested deleting tags w/ no prob.
            m4_ASSERT_SOFT(dirty_panels_arr === null);
            dirty_panels = this.panel_lookup;
         }
         else {
            dirty_panels = new Set_UUID(dirty_panels_arr);
         }

         var panel:Detail_Panel_Base;
         for each (panel in dirty_panels) {
            if (panel !== null) {
               panel.dirty_set(dirty_reason);
            }
            // else, the item type's get detail_panel() returned null
         }

         // If the current panel is dirty, schedule an update
         //if (this.active_panel.dirty_get()) {
         //   var dirty:Boolean = true;
         //   this.panel_activate(this.active_panel, dirty);
         //}
         // We're called from main.mxml before G.map is set, so...
         if (schedule_activate && (G.map !== null)) {
            if ((this.active_panel !== null)
                && (this.activate_panel_next === null)
                && (this.effectively_active_panel !== null)) {
               m4_DEBUG('panels_mark_dirty: active_panel:', this.active_panel);
               this.panel_activate(this.active_panel,
                                   this.active_panel.is_dirty());
            }
            else {
               m4_TALKY2('panels_mark_dirty: active_panel:',
                         this.active_panel);
               m4_TALKY2('panels_mark_dirty: activate_panel_next:',
                         this.activate_panel_next);
               m4_TALKY2('panels_mark_dirty: effectively_active_panel:',
                         this.effectively_active_panel);
            }
         }
      }

      //
      public function panel_register(panel:Detail_Panel_Base) :void
      {
         m4_DEBUG('panel_register: setting dirty:', panel);
         // Mark the panel dirty so it gets redrawn when first displayed.
         panel.dirty_set(Dirty_Reason.item_data);
         this.panel_lookup.add(panel);
      }

      //
      public function is_panel_registered(panel:Detail_Panel_Base) :Boolean
      {
         var is_registered:Boolean =
            ((panel !== null) && (this.panel_lookup.is_member(panel)));
         m4_DEBUG('is_panel_registered:', is_registered, '/ panel:', panel);
         return is_registered;
      }

      // Updates all of the panels and resets the user's permissions to each
      // control. Some controls and enabled or disabled, and some controls are
      // edit controls or just plain labels, depending on the user's access and
      // whether the revision is Working or not.
      public function update_access() :void
      {
         m4_DEBUG('update_access');
         // Marks all of the panels dirty.
         // We could instead signal an event, but we already have a lookup of
         // panels, so no need to complicate the panel code.
         m4_DEBUG2('update_access: panels_mark_dirty: null');
         this.panels_mark_dirty(null, Dirty_Reason.item_grac);
      }

   }
}


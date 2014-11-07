/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* Base class for Command_Bases. */

/* This is the base class of the views.commands package. Most of the classes
   that make up this package manage a user's interaction while editing the
   map or editing data via the panels. The classes handle UI interactions,
   updating items appropriately (so they can later be saved by the user),
   and most commands support undo and redo. */

package views.commands {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   import grax.Access_Level;
   import items.Attachment;
   import items.Geofeature;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.attcs.Annotation;
   import items.attcs.Attribute;
   import items.attcs.Post;
   import items.attcs.Tag;
   import items.attcs.Thread;
   import utils.misc.Collection;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Versioned;

   public class Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Base');

      // *** Instance variables

      // Center of viewport when the command was issued [READ-ONLY]
      // This is intended to approximate the geographic location of commands,
      // even when they do have a geographic element (such as annotations).
      public var map_x:int;
      public var map_y:int;

      // If true, Command_Base can be merged with other commands.
      // See: function merge_from.
      public var mergeable:Boolean = false;

      // This is public so views.commands.Command_Manager can get at it.
      // This is a collection of one or more new and/or existing items being
      // acted upon by this command.
      public var edit_items:Array;

      protected var new_dirty_reason:int;
      protected var old_dirty_reasons:Dictionary;

      // This flag indicates if the items in the command are ready to be
      // performed upon
      protected var is_prepared_:* = null;

      // The undone flag is null until the first do_, and then it's false.
      // It's true after the first undo. And then it just toggles back and
      // forth.
      protected var undone:* = null;

      protected var callback_done:Function = null;
      protected var callback_fail:Function = null;

      protected var check_perms_on:Set_UUID = new Set_UUID();
      protected var check_perms_other:Set_UUID = new Set_UUID();
      protected var check_perms_lvals:Set_UUID = new Set_UUID();

      // Some commands' panel's selection set should exactly contain the
      // same items being edited, but some commands don't care. E.g., if
      // you have two or more byways selected, the user should be able to
      // drag a byway vertex without affecting the selection set, and the
      // user should be able to undo and redo similarly -- and if the user
      // adds or removes other byways from the panel's selection set, undo
      // and redo should still use the same panel and the currect selection
      // set. However, if the user changes an attribute for a collection of
      // selected items, if the user changes the selection set and then does
      // undo or redo, we should update the panel's selection set to reflect
      // exactly those items whose link_values were edited.
      //
      // A command whose edit_items can be a subset of a panel's items_selected
      // should specify loose_selection_set, otherwise, most panels use the
      // default, which is a strict association.
      public var loose_selection_set:Boolean = false;

      // When making an 'X' intersection, two Byway_Split commands are used
      // (one on each of two byways), so some commands need to be run twice.
      // Which means each command's do_() competes for the active panel and
      // determining what's selected (see activate_panel_do_). In that
      // circumstance, it's easist just to remember not to do panel stuff for
      // the lesser panels, and to let the master command (command wrapper)
      // handle activate_panel_do_ and activate_panel_undo.
      public var skip_panel:Boolean = false;

      // *** Constructor

      // Every command has an array of items, edit_items, that
      // represents the items affected by this Command_Base. The reason
      // is a Dirty_Reason int.
      // SYNC_ME: These names match some GML names in GWIS_Commit.as.
      // SYNC_ME: These names match those in commit.py.
      // FIXME This is not an exhaustive list. Also, m4_ASSERT it's
      //       a known string, and not a typo or something new
      public function Command_Base(edit_items:Array, reason:int)
      {
         m4_DEBUG2('Command_Base: no. edit_items:', edit_items.length,
                   '/', this);

         this.edit_items = edit_items;
         this.new_dirty_reason = reason;
         this.old_dirty_reasons = new Dictionary();

         for each (var item:Item_Versioned in this.edit_items) {
            this.old_dirty_reasons[item.stack_id] = item.get_dirty_reason();
         }

         this.map_x = G.map.view_rect.map_center_x;
         this.map_y = G.map.view_rect.map_center_y;

         // BUG nnnn: For each non-dirty item in edit_items, make a clone.
         //           Make the clone the item for the saved version in
         //           G.item_mgr.past_versions, and make the edited item
         //           the latest, unsaved version.
      }

      // *** Instance methods

      //
      public function activate_appropriate_panel(loose_selection_set:*=null)
         :void
      {
         var item_panel:Panel_Item_Versioned;

         var items_sel:Set_UUID = new Set_UUID();
         var feats_sel:Set_UUID = new Set_UUID();

         // For feat.get_panel_for_multiple|single_items.
         var skip_new:Boolean = false;

         if (loose_selection_set === null) {
            loose_selection_set = this.loose_selection_set;
         }

         var rand_item:Item_Versioned = (this.edit_items[0] as Item_Versioned);
         m4_ASSERT(rand_item !== null);
         // But first, see if the command pertains to link_values.
         var rand_link:Link_Value = (rand_item as Link_Value);

         if (rand_link !== null) {
            if ((rand_link.attc is Annotation)
                || (rand_link.attc is Post)
                || (rand_link.attc is Thread)) {
               // Just use the attachment panel.
               for each (var lv1:Link_Value in this.edit_items) {
                  items_sel.add(lv1.attc); // Should all be same attc.
               }
               m4_ASSERT(items_sel.length == 1);
               item_panel = (items_sel.one() as Attachment).attachment_panel;
               m4_DEBUG('activate_appropr_pnl: lval attc panel:', item_panel);
               // leaving: feats_sel = new Set_UUID();
            }
            else if ((rand_link.attc is Attribute)
                     || (rand_link.attc is Tag)) {
               // Try to find the geofeature panel with this items selected,
               // otherwise make a new panel.
               var rand_feat:Geofeature = null;
               for each (var lv2:Link_Value in this.edit_items) {
                  if (rand_feat === null) {
                     rand_feat = lv2.feat;
                  }
                  feats_sel.add(lv2.feat);
               }
               m4_ASSERT(!loose_selection_set); // Never for lval cmds.
               item_panel = rand_feat.panel_get_for_geofeatures(
                  feats_sel, loose_selection_set, skip_new/*=false*/);
               m4_DEBUG('activate_appropr_pnl: lval feat panel:', item_panel);
               items_sel = feats_sel;
            }
            else {
               m4_ASSERT(false);
            }
            // MAYBE: Highlight the widget and value that changed?
         }
         else if (rand_item is Attachment) {
            m4_ASSERT(this.edit_items.length == 1);
            // Maybe get a new panel for the attachment, or maybe get the
            // existing panel, if one already lives in the side_panel_tabs.
            items_sel.add(rand_item);
            item_panel = (rand_item as Attachment).attachment_panel;
            // leaving: feats_sel = new Set_UUID();
         }
         else if (rand_item is Geofeature) {
            // Some commands really have two different sets of features:
            // on do, one is deleted and another is created, and on undo,
            // the reverse happens (think byway merge, byway split, etc.).
            // Those commands override activate_panel_(un)do(_). For
            // commands that operate on a Geofeature without deleting
            // it, like vertex move, we can just do the same thing for
            // do_ and undo, which is to just find a panel that either
            // has a subset of the geofeatures selected, or all of the
            // geofeatures selected.
            // 
            // The Vertex_Move command edits features that are part of the
            // intersection being dragged but that aren't necessarily selected,
            // so we have to be discerning.
            // Nope: feats_sel = new Set_UUID(this.edit_items);
            feats_sel = new Set_UUID(this.feats_to_select);
            item_panel = (rand_item as Geofeature).panel_get_for_geofeatures(
               feats_sel, loose_selection_set, skip_new/*=false*/);
            items_sel = feats_sel;
         }
         else {
            m4_ASSERT(false);
         }
         m4_DEBUG('activate_appropriate_panel: item_panel/1:', item_panel);
         m4_DEBUG('activate_appropriate_panel: items_sel:', items_sel);
         m4_DEBUG('activate_appropriate_panel: feats_sel:', feats_sel);

         var next_panel:Detail_Panel_Base = null;

         m4_ASSERT(item_panel !== null);
         m4_DEBUG('activate_appropriate_panel: item_panel/2:', item_panel);

         // Change the selection set.
         item_panel.items_selected = items_sel;
         if (item_panel.items_selected !== item_panel.feats_selected) {
            item_panel.feats_selected = feats_sel;
         }
         // Panel_Manager will set items' and feats' selected.

         next_panel = item_panel;

         // This is some silly checking to make sure we don't clear the
         // effectively_active_panel if next_panel is going to be that panel.
         // By which we mean, clear the active panel if it's not the panel we
         // want, and then activate the next_panel and its selection set,
         // otherwise all that's already done.

         // The Attribute_Links_Edit command causes the attribute list to
         // flicker... not setting the panel dirty and forcing it to reactivate
         // seems to do the work.
         var activated:Boolean = false;
         var panel_dirty:Boolean = true;
         activated = G.panel_mgr.panel_activate(next_panel, panel_dirty);

         if (!activated) {
            next_panel.reactivate_selection_set();
         }
      }

      //
      public function activate_panel_do_() :void
      {
         m4_TALKY('activate_panel_do_');
         this.activate_appropriate_panel();
      }

      //
      public function activate_panel_undo() :void
      {
         m4_TALKY('activate_panel_undo');
         this.activate_appropriate_panel();
      }

      //
      protected function get all_selected() :Boolean
      {
         var all_selected:Boolean = true;
         for each (var item:Item_Versioned in this.edit_items) {
            if (!item.selected) {
               all_selected = false;
               break;
            }
         }
         m4_TALKY('all_selected:', all_selected);
         return all_selected;
      }

      //
      public function get always_recalculate_cnt() :Boolean
      {
         return false;
      }

      //
      public function contains_item(item:Item_Versioned) :Boolean
      {
         return Collection.array_in(item, this.edit_items);
      }

      //
      protected function panel_ready(dpanel:Detail_Panel_Base) :void
      {
         m4_ASSERT(dpanel !== null);

         // Probably, this isn't necessary:
         //G.map.map_selection_clear();
         //dpanel.panel_selection_clear();
         G.panel_mgr.effectively_active_panel = null;

         var activated:Boolean = false;
         var panel_dirty:Boolean = false;
         activated = G.panel_mgr.panel_activate(dpanel, panel_dirty);
         if (!activated) {
            dpanel.reactivate_selection_set();
         }
      }

      // If any of the items in items_array are part of the active panel,
      // the active panel is emptied of items so it can be reused. This
      // function is called at the start of some do_ and undo commands,
      // before selecting items.
      protected function panel_reset_maybe(...items_array) :void
      {
         if (items_array[0] is Array) {
            m4_ASSERT(items_array.length == 1);
            items_array = items_array[0];
         }
         var is_active:Boolean = false;
         for each (var item:Item_Versioned in items_array) {
            if (item.selected) {
               is_active = true;
               break;
            }
         }
         if (is_active) {
            var active_panel:Detail_Panel_Base;
            active_panel = G.panel_mgr.effectively_active_panel;
            m4_DEBUG('panel_reset_maybe: calling panel_selection_clear');
            var force_reset:Boolean = true;
            active_panel.panel_selection_clear(force_reset/*=true*/);
            // Unset close pending because we want to reuse this panel.
            active_panel.panel_close_pending = false;
         }
      }

      // ***

      // Attempt to merge other into myself: update myself to include the
      // combined effects of itself and myself. On success, return true; on
      // failure, return false (and myself is unchanged).
      public function merge_from(other:Command_Base) :Boolean
      {
         return false;
      }

      //
      protected function on_links_loaded(event:Event) :void
      {
         m4_TALKY('on_links_loaded/linksLoaded');
         var all_links_loaded:Boolean = true;
         m4_TALKY2('on_links_loaded: this.check_perms_on.length:',
                   this.check_perms_on.length);
         m4_ASSERT(this.check_perms_on.length > 0);
         var item:Item_User_Access;
         for each (item in this.check_perms_on) {
            if (!(item.hydrated)) {
               m4_TALKY('on_links_loaded: at least waiting on: item:', item);
               all_links_loaded = false;
               break;
            }
         }
         if (all_links_loaded) {
            m4_TALKY('on_links_loaded: removin linksLoaded lstnr');
            G.item_mgr.removeEventListener('linksLoaded',
                                           this.on_links_loaded);
            this.prepare_items_step_2();
         }
      }

      // After a command is created and populated with new and existing items
      // on which to behave, but before the command is processed, we need to
      // verify that the user has the rights to create and update
      // said new and existing items. If the item is new, we also take this
      // opportunity to assign a new ID (see G.grac_mgr.prepare_item).
      // FYI: For help on ..., search Flex docs for "the ... (rest) parameter"
      public function prepare_command(callback_done:Function,
                                      callback_fail:Function,
                                      ...extra_items_arrays) :Boolean
      {
         //m4_DEBUG('prepare_command:', this);
         //m4_DEBUG('  extra_items_arrays.length:', extra_items_arrays.length);

         if (callback_done !== null) {
            m4_ASSERT(callback_fail !== null);
            this.callback_done = callback_done;
            this.callback_fail = callback_fail;
         }

         m4_ASSERT_SOFT(!this.is_prepared);

         // Prepare the items, but only for "real" commands, e.g.,
         // Vertex_Move is created once for each mouse move (or so)
         // and is replaced on mouse up by Vertex_Add. If we call this
         // block for each Vertex_Move, the user's mouse move experience
         // is very jerky.
         if (this.prepares_items) {
            // Use .apply, which calls the function with the first parameter as
            // the value of "this". The second parameter is an array that will
            // be expanded to be passed as if it were a normal argument list.
            //   Wrong:  this.prepare_items_step_1(extra_items_arrays);
            m4_TALKY2('prepare_command: extra_items_arrays:',
                      extra_items_arrays);
            this.prepare_items_step_1.apply(this, extra_items_arrays);
         }
         else {
            m4_TALKY('prepare_command: is_prepared=true');
            this.is_prepared = true;
            if (this.callback_done !== null) {
               this.callback_done(this);
            }
         }

         m4_TALKY('prepare_command: is_prepared:', this.is_prepared);
         return this.is_prepared;
      }

      //
      protected function prepare_items_step_1(...extra_items_arrays) :void
      {
         m4_TALKY2('prepare_items_step_1: this.edit_items:',
                   this.edit_items);
         m4_TALKY2('prepare_items_step_1: extra_items_arrays:',
                   extra_items_arrays);
         // Make a copy of the edit_items since we extend it with the
         // (rest). This makes the for-each loop easier to implement
         // (we deal w/ just one array, not many arrays).
         var items_arrays:Array = new Array(this.edit_items);
         // See if the derived class has overridden and passed additional
         // parameters.
         if (extra_items_arrays.length > 0) {
            items_arrays = items_arrays.concat(extra_items_arrays);
         }
         m4_TALKY('prepare_items_step_1: no. items:', items_arrays.length);
         m4_TALKY('prepare_items_step_1: items_arrays:', items_arrays);
         // We need to go through the arrays lists twice: once to see if we
         // need to lazy-load items, and then a second time to verify the user
         // has access permissions on each item.
         var lazy_loading:Boolean = false;
         for each (var arr:Array in items_arrays) {
            m4_TALKY('prepare_items_step_1: checking outer arr:', arr);
            m4_TALKY('prepare_items_step_1: typeof:', typeof(arr));
            if (arr !== null) {
               var item:Item_User_Access;
               for each (item in arr) {
                  if (item !== null) {
                     m4_TALKY('prepare_items_step_1: arr item:', item);
                     this.check_perms_on.add(item);
                     if (item is Link_Value) {
                        this.check_perms_lvals.add(item);
                     }
                     else {
                        this.check_perms_other.add(item);
                     }
                     if (!item.invalid && !item.hydrated) {
                        m4_TALKY('prepare_items_step_1: lazy-loading:', item);
                        if (!lazy_loading) {
                           lazy_loading = true;
                           m4_TALKY('prpr_itms_step_1: addn linksLoadd lstnr');
                           G.item_mgr.addEventListener('linksLoaded',
                                                       this.on_links_loaded);
                        }
                        G.app.callLater(G.item_mgr.link_values_lazy_load,
                                        [item,]);
                     }
                  }
               } // end: for each (item in arr)
            } // end: if (arr !== null)
         }
         if (!lazy_loading) {
            this.prepare_items_step_2();
         }
      }

      //
      protected function prepare_items_step_2() :void
      {
         m4_TALKY('prepare_items_step_2: this:', this);
         m4_TALKY(' .. check_perms_on.len:', this.check_perms_on.length);
         m4_TALKY(' .. chk_perms_other.len:', this.check_perms_other.length);
         m4_TALKY(' .. chk_perms_lvals.len:', this.check_perms_lvals.length);

         // Process geofeatures and attachments before link_values, otherwise
         // the link_values will complain about missing linked items.
         var check_perms_set:Set_UUID;
         for each (check_perms_set in [this.check_perms_other,
                                       this.check_perms_lvals,]) {

            var item:Item_User_Access;
            for each (item in check_perms_set) {

               m4_TALKY('prepare_items_step_2: checking item:', item);

            // [lb] is less cool with this... because it causes panel change.
            //// Clear highlights, etc., since we might be about to change the 
            //// item's stack ID from 0 to a valid client ID.
            //item.set_selected(false, /*nix=*/true);
            // Also remove item from lookups, since prepare_item might change
            // its stack_id.
               if (item.stack_id == 0) {
                  item.set_selected(false, /*nix=*/true);
                  G.map.item_discard(item);
               }

               // FIXME: Instead of G...., item.prepare_for_command() ?
               //        (in Item_User_Access.as)
               this.is_prepared = G.grac.prepare_item(
                                       item,
                                       this.prepare_items_access_min,
                                       this.prepare_items_must_exist);
               m4_TALKY('prepare_items_step_2: is_prepared', this.is_prepared);
               if (!this.is_prepared) {
                  // An error dialog is queued to be displayed. Just bail.
                  break;
               }
               //m4_TALKY('prepare_command: adding item:', item);
               // This is, uh, maybe required. Most items are already added.
               // This does nothing if they are.
               G.map.items_add([item,]);

            } // for each item

         } // for each check_perms_arr

         if (this.callback_done !== null) {
            m4_ASSERT(this.callback_fail !== null);
            if (this.is_prepared) {
               this.callback_done(this);
            }
            else {
               this.callback_fail(this);
            }
         }
      }
// FIXME: After a Working Copy Update, if user permissions have changed, how do
//        we go about re-checking all the commands? Can we mark them all
//        !is_prepared and then, on do/undo/redo, check is_prepared and
//        recalculate if not? What do we do with some commands in the stack?
//        Or maybe a Working Copy Update invalidates commands whose items have
//        changed, so this doesn't even matter?

      //
      protected function get prepares_items() :Boolean
      {
         return true;
      }

      //
      protected function get feats_to_select() :Array
      {
         return this.edit_items;
      }

      // *** Do and undo

      // Subclasses should call super.do_() first.
      public function do_() :void
      {
         if (!this.undone) {
            m4_DEBUG('do_: init:', this);
         }
         else {
            m4_DEBUG('do_: redo:', this);
         }

         m4_ASSERT(this.undone !== false);

         if (!this.skip_panel) {
            this.activate_panel_do_();
         }

         var item:Item_Versioned;
         for each (item in this.edit_items) {
            m4_DEBUG2('do_: new_dirty_reason:',
                      this.new_dirty_reason, '/ item:', item);
            item.dirty_set(this.new_dirty_reason, true);
         }

         this.undone = false;
      }

      // Subclasses should call super.undo() first.
      public function undo() :void
      {
         m4_DEBUG('undo: this:', this);

         m4_ASSERT(!this.undone);

         if (!this.skip_panel) {
            this.activate_panel_undo();
         }

         var item:Item_Versioned;
         for each (item in this.edit_items) {
            m4_DEBUG2('undo: old_dirty_reason:',
                      this.old_dirty_reasons[item.stack_id], '/ item:', item);
            item.dirty_set(this.old_dirty_reasons[item.stack_id], true);
         }

         this.undone = true;
      }

      // *** Getters and setters

      // Returns a friendly name describing the operation so we can tell the
      // user what's on the command stack (i.e., as a toolTip when the user
      // hovers the mouse over the Undo button). This should be overridden by
      // subclasses so that the descriptor is more specific. The string follows
      // one of the two verbs, "Undo " or "Redo ".
      public function get descriptor() :String
      {
         return getQualifiedClassName(this);
      }

      //
      public function get is_prepared() :*
      {
         return this.is_prepared_;
      }

      //
      public function set is_prepared(is_prepared:*) :void
      {
         this.is_prepared_ = is_prepared;
      }

// FIXME: How does this relate to Map_Tool.useable?
//        How does this relate to Grac? Do we have to check perms here?
//          Maybe for links, since Map_Tool.useable can't check 'em;
//          also, Map_Tool.useable doesn't apply to existing items, just to
//          creating new items...
//
      // Whether or not this command is do-able, undo-able, or redo-able,
      // based on the current map state.
      public function get performable() :Boolean
      {
         var item:Item_Versioned = (this.edit_items[0] as Item_Versioned);
         m4_TALKY('performable: this:', this);
         m4_TALKY('performable: item:', item);
         m4_TALKY('performable: this.edit_items:', this.edit_items);
         m4_TALKY('performable: edit_items.length:', this.edit_items.length);
         m4_DEBUG4('performable: item:', item.toString(),
                   '/ rev:', G.map.rev_viewport,
                   '/ at raster:', item.actionable_at_raster,
                   '/ is vector:', G.map.zoom_is_vector());
         return ((G.map.rev_viewport is utils.rev_spec.Working)
                 // 2013.04.16: If we don't allow a command because
                 // we're zoomed out and !item.actionable_at_raster,
                 // we might assert in do or undo, even though the
                 // panel is showing the item (i.e., zoom out with
                 // an item selected, and then edit its attributes
                 // or something). It seems silly to deselect if a
                 // user zooms out. It also seems silly to disable
                 // the editing controls. So ignore this:
                 // && (item.actionable_at_raster
                 //     || G.map.zoom_is_vector())
                 );
      }

      // When preparing a command, the system checks to determine if the user
      // has appropriate permissions. By default, users must have editor access
      // or better to edit items.
      protected function get prepare_items_access_min() :int
      {
         return Access_Level.editor;
      }

      // Some commands only work on existing items, like rating and watching.
      // Lots of commands, though, create new items. This function returns true
      // if the command only works on existing items, or false if the command
      // makes new items.
      protected function get prepare_items_must_exist() :Boolean
      {
         return false;
      }

   }
}


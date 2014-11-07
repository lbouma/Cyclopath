/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This is the Command_Base manager. Command_Bases can be done, undone, and
// redone. This class manages them.

package views.commands {

   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.geom.Rectangle;
   import flash.utils.getQualifiedClassName;
   import mx.controls.Alert;
   import mx.utils.UIDUtil;

   import items.Attachment;
   import items.Geofeature;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.links.Link_Geofeature;
   import utils.geom.Geometry;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;
   import views.base.UI;
   import views.panel_base.Detail_Panel_Base;

   public class Command_Manager extends EventDispatcher {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Mgr');

      // *** Instance variables

      protected var _drect:Rectangle; // region enclosing approx. changes
      protected var min_dirty_rect:Rectangle; // minimum sized dirty region
      protected var compute_dirty:Boolean;

      public var undos:Command_Stack;
      public var redos:Command_Stack;

      // How many unsaved changes are outstanding, i.e. how long would the
      // undo stack be if it were of unlimited length.
      public var unsaved_change_ct:int = 0;

      protected var caller_callback_wait:Boolean = false;
      protected var caller_callback_done:Function = null;
      protected var caller_callback_fail:Function = null;

      // *** Constructor

      public function Command_Manager()
      {
         this.undos = new Command_Stack(Conf.undo_stack_depth);
         this.redos = new Command_Stack();
      }

      // *** Instance methods

      // *** Getters and setters

      // The rectangle enclosing the map locations of every command that is in
      // the undo stack (or was pushed off the back if Conf.undo_stack_depth
      // is greater than 0). Return null if unsaved_change_ct == 0.
      public function get dirty_rect() :Rectangle
      {
         var c:Command_Base;

         if (this._drect === null) {
            if (this.unsaved_change_ct > 0) {
               this._drect = (this.min_dirty_rect === null
                              ? null : this.min_dirty_rect.clone());
               for each (c in this.undos.as_list) {
                  this._drect = Geometry.merge_point(this._drect,
                                                     c.map_x, c.map_y);
               }
            } // else: we want to return null, so don't change anything
         }

         return this._drect;
      }

      // Textual description of the top of the redo stack
      public function get redo_descriptor() :String
      {
         if (this.redoable()) {
            return 'Redo ' + this.redos.peek().descriptor;
         }
         else {
            return 'Nothing to redo';
         }
      }

      //
      public function get redo_length() :int
      {
         return this.redos.length;
      }

      // True if the redo stack is not empty
      public function get redos_present() :Boolean
      {
         return (!this.redos.is_empty());
      }

      // Textual description of the top of the undo stack
      public function get undo_descriptor() :String
      {
         if (this.undoable()) {
            return 'Undo ' + this.undos.peek().descriptor + '.';
         }
         else {
            return 'Nothing to undo.';
         }
      }

      //
      public function get undo_length() :int
      {
         return this.undos.length;
      }

      // True if the undo stack is not empty
      public function get undos_present() :Boolean
      {
         return (!this.undos.is_empty());
      }

      // *** Other methods

      // Clear the undo/redo information of all information, or
      // a specific feature.
      public function clear(item:Item_Versioned=null) :void
      {
         // NOTE: This fcn. is only called via Item_Manager's
         //       update_items_committed. It's really just used
         //       for debugging, to check that everything was
         //       processed.

         var num_removed:int = 0;
         if (item === null) {
            m4_DEBUG('clear: no item specified; clearing all undos and redos');
            this.undos.clear();
            this.redos.clear();
            num_removed = this.unsaved_change_ct;
         }
         else {
            m4_DEBUG('clear: removing item from undos:', item);
            //m4_DEBUG(' >> uuid: item:', UIDUtil.getUID(item));
            num_removed = this.undos.remove_feature(item);
            this.redos.remove_feature(item);
         }

         this.unsaved_change_ct -= num_removed;

         m4_DEBUG2('clear: num_removed:', num_removed,
                   'unsaved_change_ct:', this.unsaved_change_ct);
         if (this.unsaved_change_ct == 0) {
            this._drect = null;
            this.min_dirty_rect = null; // reset this region, too
            UI.curr_sv_remind_dist = Conf.save_reminder_distance;
         }

         if (item === null) {
            UI.editing_tools_update();
         }
      }

      // Do the command.
      public function do_(cmd:Command_Base,
                          callback_done:Function=null,
                          callback_fail:Function=null) :void
      {
         // BUG nnnn: There's probably a less obnoxious way to handle when the
         // user tries a second command while we're still lazy loading items
         // for the first command. For now, just pop up an intrusive, ugly
         // alert.
         if (this.caller_callback_wait) {
            cmd.is_prepared = false;
            m4_WARNING('do_: still waiting on caller_callback_wait');
            m4_ASSERT_SOFT(false);
            //Alert.show('Please wait for the previous command to complete.');
            Alert.show('Please wait for the item to finish loading.');
         }
         else {
            if (!cmd.is_prepared) { // false or null
               if (callback_done !== null) {
                  m4_ASSERT(callback_fail !== null);
                  this.caller_callback_done = callback_done;
                  this.caller_callback_fail = callback_fail;
               }
               m4_DEBUG('do_: prepare_command: cmd:', cmd);
               cmd.prepare_command(this.do_prepare_command_done,
                                   this.do_prepare_command_fail);
            }
            else {
               m4_WARNING('do_: cmd.is_prepared already true');
            }
            if (cmd.is_prepared === null) {
               // cmd.is_prepared remains null if the command needs to do some
               // stuff, like lazyload item link_values. It'll call us back
               // when it's done.
               m4_DEBUG2('do_: set caller_callback_wait=true:',
                         this.caller_callback_wait);
               this.caller_callback_wait = true;
            }
            // else {
            //    // Otherwise is_prepared is false if the user does not have
            //    // permissions to perform the command; else it's true if the
            //    // command was performed successfully.
            //    // The this.do_prepare_command_done or _fail callback was
            //    // called and do_first_do was called if the former.
            //    // Nope: this.do_first_do(cmd);
            // }
         }
      }

      //
      protected function do_first_do(cmd:Command_Base) :void
      {
         if (cmd.is_prepared) {
            var prev_cmd:Command_Base = this.undos.peek();
            m4_ASSERT(cmd.performable);
            cmd.do_();
            this.redos.clear();
            // If the last command was a vertex merge command, we don't add it
            // to the undos command stack, since the command was auto-generated
            // by the system in addition to the command the user really
            // executed.
            if ((prev_cmd === null) || (!prev_cmd.merge_from(cmd))) {
               this.unsaved_change_ct++;
               m4_VERBOSE('do_: unsaved_change_ct++', this.unsaved_change_ct);
               m4_DEBUG('do_first_do: undo_push: cmd:', cmd);
               this.undo_push(cmd);
            }
            this._drect = null;
            if (cmd.always_recalculate_cnt) {
               // For Item_Delete, when have to walk the undo stack and
               // recalculate G.map.cm.unsaved_change_ct, in case the deleted
               // item had fresh attachments. This is because users can, e.g.,
               // create a byway, edit an attribute, and then delete the byway:
               // there are three commands in the stack, but there's nothing to
               // save.
               this.unsaved_cnt_recalculate();
            }
            UI.editing_tools_update();
            if (this.caller_callback_done !== null) {
               this.caller_callback_done(cmd);
            }
         }
         else {
            if (this.caller_callback_fail !== null) {
               this.caller_callback_fail(cmd);
            }

            // Command cannot be run because of access level constraints
            Alert.show('You do not have permission to perform this action.',
                       'Cannot perform ' + cmd.descriptor);
         }
      }

      //
      protected function do_prepare_command_done(cmd:Command_Base) :void
      {
         m4_DEBUG('do_prepare_command_done: do_first_do: cmd:', cmd);
         m4_DEBUG('do_prepare_command_done: caller_callback_wait=false');
         this.caller_callback_wait = false;
         this.do_first_do(cmd);
      }

      //
      protected function do_prepare_command_fail(cmd:Command_Base) :void
      {
         m4_WARNING('do_prepare_command_fail: cmd:', cmd);
         m4_DEBUG('do_prepare_command_fail: caller_callback_wait=false');
         this.caller_callback_wait = false;
         if (this.caller_callback_fail !== null) {
            this.caller_callback_fail(cmd);
         }
      }

      // Indicate that the command stream has reached a conceptual division
      // point. Calling this method multiple times without any intervening
      // commands is the same as calling it once.
      public function done() :void
      {
         if (!(this.undos.is_empty())) {
            this.undos.peek().mergeable = false;
         }
      }

      // Checks to see if the given Item_Versioned is present in the
      // undo or redo stacks
      public function is_feature_present(item:Item_Versioned) :Boolean
      {
         // MAYBE: Make an Item_Versioned attribute or a dedicated lookup
         //        so we don't have to iterate over the redo/undo stacks.
         //        But not many people, and it'll only get slow the more
         //        you've edited before you save...
         // NOTE: An undo or redo contains an item if that item is edited,
         //       or if the edited item is a link_value and the item is
         //       attached to the link_value (i.e., as lhs or rhs).
         // FIXME: This fcn. could be really, really slow, if there are lots of
         //        edits.
         //        2013.03.09: You could make a Set() of stack_ids from all of
         //        the commands and just check that for each item. Might save
         //        some time... O(n^2) to O(lg n)? [lb] just guessing. But
         //        let's not worry about editing performance right now.
         return ((this.undos.contains(item)) || (this.redos.contains(item)));
      }

      // Redo the last undone command.
      public function redo() :Boolean
      {
         var is_prepared:Boolean = false;
         var cmd:Command_Base = this.redos.peek();
         if (cmd !== null) {
            m4_ASSERT(cmd.performable);
            if (!cmd.is_prepared) {
               m4_ASSERT(false); // Does this happen? Will this happen?
               cmd.prepare_command(null, null);
            }
            if (cmd.is_prepared) {
               this.redos.pop();
               cmd.do_();
               this.unsaved_change_ct++;
               m4_DEBUG('redo: unsaved_change_ct++:', this.unsaved_change_ct);
               m4_DEBUG('redo: undo_push: cmd:', cmd);
               G.sl.event('trace/cmd_mgr/unsaved_change_ct',
                          {action: 'redo',
                           unsaved_change_ct: this.unsaved_change_ct,
                           cmd: cmd});
               this.undo_push(cmd);
               this._drect = null;
               if (cmd.always_recalculate_cnt) {
                  this.unsaved_cnt_recalculate();
               }
               UI.editing_tools_update();

               // I think the Command_Base class handle this
               //G.panel_mgr.panels_mark_dirty();

               // FIXME: Should this only get called when geofeature is edited
               //        (i.e., don't call for most attachments, but do call
               //        when it affects highlights, like notes and byway
               //        type... and rating?).
               G.map.selectedset_redraw();

               G.sl.event('ui/redo', {cmd: getQualifiedClassName(cmd)});
            }
            is_prepared = cmd.is_prepared;
         }
         m4_ASSERT_ELSE_SOFT();
         return is_prepared;
      }

      // Return true if at least one redoable command exists and is
      // performable, false otherwise.
      public function redoable() :Boolean
      {
         return ((!this.redos.is_empty())
                 && (this.redos.peek().performable));
      }

      // Undo the most recent command
      public function undo() :Boolean
      {
         var cmd:Command_Base = this.undos.peek();
         m4_ASSERT(cmd.performable);
         if (!cmd.is_prepared) {
            m4_ASSERT_SOFT(false); // Does this happen? Will this happen?
            cmd.prepare_command(null, null);
         }
         if (cmd.is_prepared) {
            this.undos.pop();
            cmd.undo();
            this.unsaved_change_ct--;
            m4_DEBUG('undo: unsaved_change_ct--:', this.unsaved_change_ct);
            G.sl.event('trace/cmd_mgr/unsaved_change_ct',
                       {action: 'undo',
                        unsaved_change_ct: this.unsaved_change_ct,
                        cmd: cmd});
            this.redos.push(cmd);
            this._drect = null;
            m4_DEBUG('undo: caller_callback_wait=false');
            this.caller_callback_wait = false;

// BUG_FALL_2013: TEST: Create Waypoint. Close panel. Click undo.
// FIXME: THIS IS WRONG. Create Waypoint. Close panel. Click undo.
//        The old panel is shown... Should we animate and show panel and then
//        dissolve it??
//            this.reactivate_selection_set(cmd);

            if (cmd.always_recalculate_cnt) {
               // See comments above. If we undo a delete command, we have to
               // recalculate the commands in the stack that would really be
               // saved.
               this.unsaved_cnt_recalculate();
            }

            var access_changed:Boolean = true;
            UI.editing_tools_update(access_changed);

            // FIXME: 2011.04.01: Is this okay here? If so, remove same call
            //        from commands.*s' undo() fcns.
            // FIXME: Is the Text Edit comment still valid?
            // [lb] thinks the Command_Base class handles this.
            //G.panel_mgr.panels_mark_dirty();

            G.sl.event('ui/undo', {cmd: getQualifiedClassName(cmd)});

            m4_DEBUG('undo: dispatchEvent: commandStackChanged');
            this.dispatchEvent(new Event('commandStackChanged'));
         }
         return (cmd.is_prepared);
      }

      // This is called by Route to undo all route edits. We don't currently
      // offer this for the map: if the user wants to undo all map edits,
      // they either have to click undo however many times, or they have to
      // discard all items and reload the map.
      // MAYBE?: Add an Undo All option to the floating editing palette?
      public function undo_all() :void
      {
         while (this.undoable()) {
            this.undo();
         }
      }

      // Utility function to push a command on the undo stack, and
      // update min_dirty_rect if a command was removed, too.
      protected function undo_push(cmd:Command_Base) :void
      {
         var old_cmd:Command_Base = this.undos.push(cmd);
         if (old_cmd !== null) {
            // the command can't be undone, so save it in min_dirty_rect
            this.min_dirty_rect = Geometry.merge_point(
               this.min_dirty_rect, old_cmd.map_x, old_cmd.map_y);
         }
      }

      // Return true if at least one undoable command exists and is
      // performable, false otherwise.
      public function undoable() :Boolean
      {
         // FIXME Does this mean if the user zooms out, they may not be able to
         //       perform an undo until they zoom back in?
         return ((!this.undos.is_empty()) && (this.undos.peek().performable));
      }

      //
      public function unsaved_cnt_recalculate() :void
      {
         var new_cnt:int = 0;

         for each (var cmd:Command_Base in this.undos.as_list) {
            var count_it:Boolean = false;
            for each (var obj:Object in cmd.edit_items) {
               var item:Item_Versioned = (obj as Item_Versioned);
               var attc:Attachment = (item as Attachment);
               var feat:Geofeature = (item as Geofeature);
               var lval:Link_Value = (item as Link_Value);
               if (attc !== null) {
                  var links:Set_UUID = Link_Value.item_get_link_values(attc);
                  // For editable attachments, there's just one geofeature,
                  // one one link.
                  m4_ASSERT_SOFT(links.length == 1);
                  var link_gf:Link_Geofeature;
                  for each (var lv:Link_Value in links) {
                     link_gf = (lv as Link_Geofeature);
                  }
                  if ((attc.fresh && attc.deleted)
                      || (link_gf.feat.fresh && link_gf.feat.deleted)) { 
                     m4_DEBUG2('unsaved_cnt_recalculate: fresh-n-del: attc:',
                               attc);
                  }
                  else {
                     count_it = true;
                     break; // Continue with the next command.
                  }
               }
               else if (feat !== null) {
                  if (feat.fresh && feat.deleted) {
                     m4_DEBUG2('unsaved_cnt_recalculate: fresh-n-del: feat:',
                               feat);
                  }
                  else {
                     count_it = true;
                     break; // Continue with the next command.
                  }
               }
               else if (lval !== null) {
                  if ((lval.fresh && lval.deleted)
                      || (lval.attc.fresh && lval.attc.deleted)
                      || (lval.feat.fresh && lval.feat.deleted)) {
                     m4_DEBUG2('unsaved_cnt_recalculate: fresh-n-del: lval:',
                               lval);
                  }
                  else {
                     count_it = true;
                     break; // Continue with the next command.
                  }
               }
               else if (item !== null) {
                  m4_WARNING2('unsaved_cnt_recalculate: unknown item:', item,
                              '/ cmd:', cmd);
               }
               else {
                  m4_WARNING2('unsaved_cnt_recalculate: unknown object:', obj,
                              '/ cmd:', cmd);
               }
            } // end: for each item in cmd.edit_items
            if (count_it) {
               new_cnt += 1;
            }
         }

         m4_DEBUG2('unsaved_cnt_recalculate: old_cnt:', this.unsaved_change_ct,
                   '/ new unsaved_change_ct:', new_cnt);

         // See if we transitioning to or from 0 logical changes, so we can
         // disable or enable the save map button.
         if ((int(this.unsaved_change_ct == 0))
             ^ (int(new_cnt == 0))) {
            UI.editing_tools_update();
         }

         this.unsaved_change_ct = new_cnt;

         G.sl.event('trace/cmd_mgr/unsaved_change_ct',
                    {action: 'recalc',
                     unsaved_change_ct: this.unsaved_change_ct,
                     cmd: cmd});
      }

      // ***

      //
      override public function toString() :String
      {
         var str:String =
            'Cmd_Mgr: ' + super.toString()
            + ' / unsaved_chg_ct: ' + String(this.unsaved_change_ct)
            + ' / cllr_cb_wait?: ' + String(this.caller_callback_wait)
            + ' / cllbks?: ' + String((this.caller_callback_done !== null)
                                      || (this.caller_callback_fail !== null))
            + ' / cllr_cb_wait?: ' + String(this.caller_callback_wait)
            + ' / _drect: ' + ((this._drect === null)
                               ? 'null' : String(this._drect))
            + ' / min_dty_rct: ' + ((this.min_dirty_rect === null)
                                    ? 'null' : String(this.min_dirty_rect))
            + ' / comp_dty?: ' + String(this.compute_dirty)
            + ' / undos: ' + this.undos
            + ' / redos: ' + this.redos
            ;
         return str;
      }

   }
}


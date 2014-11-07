/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This command merges an array of Route_Segments into the new geometry
// for an existing route.

package views.commands {

   import flash.events.Event;

   import grax.Dirty_Reason;
   import items.Geofeature;
   import items.Link_Value;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Item_Reversion extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Reversn');

      // *** Instance variables

      protected var system_item:Geofeature;
      protected var old_item:Geofeature;
      protected var new_item:Geofeature;

      // MAYBE/BUG nnnn: We're only getting the geofeature's versions
      // and showing them in the item history widget, but we could also
      // get a list of link_value changes, e.g., show a list of
      // geofeature and link_values changes intertwined chronologically.
      // We could show, e.g., "Date a/b/c, User Xyz Changed layer type
      // from 'Bike Trail' to 'Major Trail', or, e.g., "Data d/e/f,
      // User Lmn Removed Tag 'Bike Lane'", etc.
      //
      // We could also support restoring the item to its state at a
      // specific change if we had a revision ID and wanted to go
      // through the hassle of checking out the link_values for
      // annotations, attributes, and tags, and also fetching
      // annotations (we already have attributes and tags loaded).
      // Then we could make a list of Link_Values for the old item
      // and show them when the user chooses to view an historic
      // state of the item, and we could replace an item's link_values
      // with those from an old state if the user wanted to revert the
      // item (which gets tricky: we'd have to mark any link_values deleted
      // that don't exist at the old state, and we'd have to manage each
      // version's set of link_values specially, i.e., we can't add old
      // link_values to the map because the link_value lookups use an item's
      // stack ID, so we'd need something to complement
      // Item_Manager.past_versions (past_versions_lvals?).
      //
      // Not implemented: protected var old_lvals:Set_UUID;
      // Not implemented: protected var new_lvals:Set_UUID;

      // *** Constructor

      public function Item_Reversion(system_item:Geofeature,
                                     version_item:Geofeature,
                                     reason:int)
      {
         m4_ASSERT(reason != 0);
         m4_ASSERT_SOFT(system_item.can_edit);
         m4_ASSERT_SOFT(system_item.stack_id == version_item.stack_id);
         m4_ASSERT_SOFT(system_item.version >= version_item.version);

         this.system_item = system_item;

         this.old_item = (system_item.clone_item() as Geofeature);
         this.new_item = (version_item.clone_item() as Geofeature);

         super([this.system_item,], reason);
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         // The toolTip when user hovers over the Undo or Redo button
         // and we're that command on the stack.
         return 'restore item to another version';
      }

      //
      override public function do_() :void
      {
         super.do_();

         m4_DEBUG('do_: before:', this.system_item);

         this.new_item.clone_once_pub(this.system_item);
         // Whatever: newbie is only used once: so Item_User_Access doesn't
         //                                        set access_level_id.
         this.new_item.clone_update_pub(this.system_item, /*newbie=*/true);
         // NOTE: We don't touch link_values.

         m4_DEBUG('do_: reversion_version:', this.new_item.reversion_version);

         m4_DEBUG('do_: after:', this.system_item);

         if (this.system_item.is_drawable) {
            this.system_item.draw();
         }

         m4_TALKY('do_: dispatchEvt: itemReversionReset');
         this.system_item.dispatchEvent(new Event('itemReversionReset'));
      }

      //
      override public function undo() :void
      {
         super.undo();

         m4_DEBUG('undo: before:', this.system_item);

         this.old_item.clone_once_pub(this.system_item);
         this.old_item.clone_update_pub(this.system_item, /*newbie=*/true);

         m4_DEBUG('undo: reversion_version:', this.new_item.reversion_version);

         m4_DEBUG('undo: after:', this.system_item);

         if (this.system_item.is_drawable) {
            this.system_item.draw();
         }

         m4_TALKY('undo: dispatchEvt: itemReversionReset');
         this.system_item.dispatchEvent(new Event('itemReversionReset'));
      }

      // ***

   }
}


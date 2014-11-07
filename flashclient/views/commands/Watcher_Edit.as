/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Access_Level;
   import grax.Dirty_Reason;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

// FIXME: This class!

// FIXME: Statewide UI: How does this command work?
//        In CcpV1, watchers are saved OOB/immediately,
//        so the watcher action should not be part of undo/redo.

// EXPLAIN: How does this command relate to 
//             Attribute_Links_Edit and UI_Wrapper_Attr_Link?

   public class Watcher_Edit extends Command_Scalar_Edit {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Watcher');

      // *** Constructor

      public function Watcher_Edit(targets:Set_UUID, value_new:*)
      {
// FIXME: Statewide UI: This might be broken:
         super(targets, 'watcher_freq', value_new,
               Dirty_Reason.item_watcher);
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         return 'toggle item watching';
      }

      //
      override public function do_() :void
      {
         super.do_();
         this.on_watcher_edit();
      }

      //
      protected function on_watcher_edit() :void
      {
         var item:Item_Watcher_Shim = this.edit_items[0] as Item_Watcher_Shim;
         var feat:Geofeature = this.edit_items[0] as Geofeature;

         // FIXME: EXPLAIN: V1 code drew the Region on watcher toggle
         if (feat !== null) {
            feat.draw_all();
         }
      }

      // Since we're not really editing the Byway, the user doesn't need editor
      // access to the Byway. They just need to be able to see it.
      override protected function get prepare_items_access_min() :int
      {
         //return Access_Level.viewer;
         return Access_Level.client;
      }

      // Rating only applies to existing items, so it wouldn't make sense if
      // this command dealt with new (invalid) objects.
      override protected function get prepare_items_must_exist() :Boolean
      {
         return true;
      }

      //
      override public function undo() :void
      {
         super.undo();
         this.on_watcher_edit();
      }

   }
}


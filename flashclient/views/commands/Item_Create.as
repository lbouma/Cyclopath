/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.utils.getQualifiedClassName;

   import grax.Dirty_Reason;
   import items.Item_Versioned;
   import utils.misc.Logging;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Versioned;

   public class Item_Create extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Item_Cr');

      // *** Constructor

      public function Item_Create(item:Item_Versioned)
      {
         var i:int;
         super([item,], Dirty_Reason.item_data);
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         return 'create new item';
      }

      //
      override public function do_() :void
      {
         super.do_();

         var item:Item_Versioned;
         m4_ASSERT(this.edit_items.length == 1);
         item = (this.edit_items[0] as Item_Versioned);
         m4_TALKY('do_: item:', item);
         m4_ASSERT(!item.invalid);

         item.deleted = false;
         // On undo, we G.map.item_discard, so we always items_add on do_.
         G.map.items_add([item,]);

         m4_TALKY('do_: selecting item:', item);
         item.set_selected(true, /*nix=*/false, /*solo=*/true);

         // See Attribute_Create.do_ and Geofeature_Create.do_ for activating
         // the item's panel (which isn't abstracted in Panel_Item_Versioned,
         // otherwise we'd do it here).
      }

      //
      override public function undo() :void
      {
         super.undo();

         var item:Item_Versioned;
         item = (this.edit_items[0] as Item_Versioned);
         m4_TALKY('undo: item:', item);

         var item_panel:Panel_Item_Versioned;
         if (item.selected) {
            item_panel = (G.panel_mgr.effectively_active_panel
                          as Panel_Item_Versioned);
            var force_reset:Boolean = true;
            item_panel.panel_selection_clear(force_reset/*=true*/);
            // item_panel.panel_close_pending = false;
         }

         item.deleted = true;
         G.map.item_discard(item);
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Dirty_Reason;
   import items.Attachment;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.feats.Byway;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.base.UI;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Versioned;

// FIXME_2013_06_11: On item delete, do different things depending
//                   on item type. This should solve problem with
//                   the save button not disabling when you delete,
//                   e.g., a new note, because the link_values are
//                   still dirty and still hanging around.
// FIXME: Derive separately for item types so
//        we can fix, e.g., links and whatnots.
   public class Item_Delete extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Item_De');

      // *** Instance variables

      protected var deleted_old:Array;

      // *** Constructor

      // gs is the set of all items to be removed from the map
      public function Item_Delete(gs:Set_UUID)
      {
         var o:Object;

         super(gs.as_Array(), Dirty_Reason.item_data);

         this.deleted_old = new Array();
         for each (o in this.edit_items) {
            this.deleted_old.push((o as Item_Versioned).deleted);
         }
      }

      // *** Instance methods

      //
      override public function get always_recalculate_cnt() :Boolean
      {
         return true;
      }

      //
      override public function get descriptor() :String
      {
         return 'delete item';
      }

      //
      override public function do_() :void
      {
         super.do_();

         for each (var o:Object in this.edit_items) {
            var item:Item_Versioned = (o as Item_Versioned);
            item.deleted = true;
            G.map.item_discard(item);
            if (item is Byway) {
               G.map.intersection_detector.remove(item as Byway);
            }
            m4_DEBUG('do_: item:', item);
         }

// BUG_FALL_2013: TESTME:
// 1. If you delete a new note, disable Save Map.
// 2. If you attach places, delete, then undo, you have to
//    undo all the way, then redo, to get the attached links
//    back.

         //G.map.node_snapper.nodes_rebuild(); // Commented-out in V1, too.

         this.item_panels_mark_dirty();
      }

      //
      override public function undo() :void
      {
         super.undo();

         var i:int = 0;
         var toadd:Array = new Array();
         for each (var item:Item_Versioned in this.edit_items) {
            item.deleted = this.deleted_old[i];
            if (!item.deleted) {
               toadd.push(item);
            }
            i++;

            m4_DEBUG('undo: item:', item);
         }

         G.map.items_add(toadd);

         //G.map.node_snapper.nodes_rebuild(); // Commented-out in V1, too.

         this.item_panels_mark_dirty();
      }

      //
      protected function item_panels_mark_dirty() :void
      {
         var lval:Link_Value = (this.edit_items[0] as Link_Value);
         if (lval !== null) {
            // This is a lazy hack to redraw any and all geofeature panels,
            // since we don't have a lookup of link_values to widgets (so
            // we don't easily know what widget to redraw; so we just redraw
            // the whole panel).
            G.panel_mgr.item_panels_mark_dirty(Panel_Item_Versioned);
         }
         else {
            G.panel_mgr.item_panels_mark_dirty(this.edit_items);
         }
      }

   }
}


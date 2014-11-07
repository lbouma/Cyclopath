/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import items.Geofeature;
   import items.Item_Versioned;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;
   import views.panel_items.Panel_Item_Geofeature;

   public class Geofeature_Create extends Item_Create {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Geof_Cr');

      // *** Constructor

      public function Geofeature_Create(feat:Geofeature)
      {
         super(feat);
      }

      // *** Public interface

      //
      override public function get descriptor() :String
      {
         return 'create new geofeature';
      }

      // ***

      //
      override public function activate_panel_do_() :void
      {
         m4_TALKY('activate_panel_do_');
         // On first do, new geofeature panel is already active, but on
         // undo-redo, it might not be.
         var feat:Geofeature;
         feat = (this.edit_items[0] as Geofeature);
         var loose_selection_set:Boolean = false;
         var skip_new:Boolean = false;
         var feat_panel:Panel_Item_Geofeature;
         feat_panel = feat.panel_get_for_geofeatures(
            new Set_UUID([feat,]),
            loose_selection_set/*=false*/,
            skip_new/*=false*/);
         m4_DEBUG('activate_panel_do_: panel_activate:', feat_panel);
         G.panel_mgr.panel_activate(feat_panel);
      }

      //
      override public function activate_panel_undo() :void
      {
         m4_TALKY('activate_panel_undo');
         // Nothing to do: feat.set_selected(false) will cause panel to close.
      }

      //
      override public function do_() :void
      {
         super.do_();

         var feat:Geofeature;
         m4_ASSERT(this.edit_items.length == 1);
         feat = (this.edit_items[0] as Geofeature);
         m4_ASSERT(feat.selected);

         feat.draw_all();

         G.map.intersection_detector.nodes_rebuild();
      }

      //
      override public function undo() :void
      {
         super.undo();

         var feat:Geofeature;
         m4_ASSERT(this.edit_items.length == 1);
         feat = (this.edit_items[0] as Geofeature);
         m4_ASSERT(!feat.selected);

         G.map.intersection_detector.nodes_rebuild();
      }

   }
}


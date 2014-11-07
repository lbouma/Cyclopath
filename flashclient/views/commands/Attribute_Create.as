/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import items.attcs.Attribute;
   import utils.misc.Logging;
   import views.panel_items.Panel_Item_Versioned;

   public class Attribute_Create extends Item_Create {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Attr_Cr');

      // *** Constructor

      public function Attribute_Create(attr:Attribute)
      {
         super(attr);
      }

      // *** Public interface

      //
      override public function get descriptor() :String
      {
         return 'create new attribute';
      }

      // ***

      //
      override public function activate_panel_do_() :void
      {
         m4_TALKY('activate_panel_do_');
         var attr:Attribute = (this.edit_items[0] as Attribute);
         //G.panel_mgr.panel_activate(attr.attribute_panel);
         attr.prepare_and_activate_panel();
      }

      //
      override public function activate_panel_undo() :void
      {
         m4_TALKY('activate_panel_undo');
         var attr:Attribute = (this.edit_items[0] as Attribute);
         attr.attribute_panel.close_panel();

         // Go back to the branch panel, where the Create New Attribute is?
         G.panel_mgr.panel_activate(G.item_mgr.active_branch.branch_panel);
      }

      //
      override public function do_() :void
      {
         super.do_();
         // We don't have to set the new attribute selected, since we called
         // prepare_and_activate_panel in activate_panel_do_.
         var attr:Attribute = (this.edit_items[0] as Attribute);
         m4_ASSERT(attr.selected);
      }

      //
      override public function undo() :void
      {
         super.undo();
         // In activate_panel_undo, we closed the panel.
         var attr:Attribute = (this.edit_items[0] as Attribute);
         m4_ASSERT(!attr.selected);
      }

   }
}


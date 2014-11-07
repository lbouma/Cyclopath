/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_items {

   import flash.utils.getQualifiedClassName;
   import mx.core.Container;
   import mx.events.FlexEvent;

   import items.Attachment;
   import utils.misc.Logging;
   import views.panel_base.Detail_Panel_Widget;

   public class Widget_Attachment_Base extends Detail_Panel_Widget {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@WdgAttcBas');

      // *** Instance variables

      // *** Constructor

      public function Widget_Attachment_Base()
      {
         super();
      }

      // ***

      //
      protected function get attachment_panel() :Panel_Item_Attachment
      {
         // This class used to cheat:
         //
         //   // Get the active panel, which isn't necessarily an item panel.
         //   var active_panel:Detail_Panel_Base;
         //   active_panel = G.panel_mgr.effectively_active_panel;
         //   m4_ASSERT(active_panel !== null);
         //   var annotation_panel:Panel_Item_Annotation;
         //   annotation_panel = (active_panel as Panel_Item_Annotation);
         //   return annotation_panel;
         //
         // But we can do better than that. Kind of.
         //
         // This class is used by Threads and Posts, but sometimes directly and
         // sometimes once removed.
         var apanel:Panel_Item_Attachment = null;
         var parent_o:Object = this.parentDocument;
         while (parent_o !== null) {
            apanel = (parent_o as Panel_Item_Attachment);
            if (apanel !== null) {
               m4_DEBUG('attachment_panel: apanel:', apanel);
               break;
            }
            else {
               m4_DEBUG('attachment_panel: not parent_o:', parent_o);
               parent_o = parent_o.parentDocument;
            }
         }
         return apanel;
      }

      //
      protected function get panel_attachment() :Attachment
      {
         var apanel:Panel_Item_Attachment = this.attachment_panel;
         return apanel.attachment;
      }

      // ***

   }
}


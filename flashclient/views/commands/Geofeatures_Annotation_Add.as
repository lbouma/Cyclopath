/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import items.Item_User_Access;
   import items.Link_Value;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   // MAYBE: Can we combine this class with Geoeature_Attachment_Add?

// 2013.12.11: This class is not being used.

   public class Geofeatures_Annotation_Add extends Geofeatures_Attachment_Add {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Gf_Note');

      // *** Constructor

      //
      public function Geofeatures_Annotation_Add(
         feats:Set_UUID,
         annot:Annotation,
         placebox:Widget_Attachment_Place_Box=null)
      {
         var feats_del:Set_UUID = null;
         super(feats, feats_del, annot, placebox);

// 2013.12.11: This class is not being used.
         m4_ASSERT(false); // Obsolete?
      }

      // *** Getters and Setters

      //
      override public function get descriptor() :String
      {
         return 'add/update notes';
      }

      // *** Instance methods: Protected interface

      override protected function link_value_to_edit(attc:Attachment,
                                                     item:Item_User_Access)
                                                      :Link_Value
      {
         var link_value:Link_Value;
         var make_new_maybe:Boolean = true;
         link_value = Link_Value.items_get_link_value(attc, item,
                                                      make_new_maybe);
         return link_value;
      }

      // *** Public interface

      //
      override public function do_() :void
      {
         super.do_();
         // It's not enough to just select the attachment:
         //  Not enough: this.attc.set_selected(true);
         // We have to manage the panel_mgr and side_panel; defer to the attc.
      }

      // EXPLAIN: Skipping undo?

   }
}


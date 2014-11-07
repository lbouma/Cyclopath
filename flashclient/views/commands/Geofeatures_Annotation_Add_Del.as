/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.utils.Dictionary;

   import items.Attachment;
   import items.Geofeature;
   import items.Item_Base;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.attcs.Annotation;
   import items.links.Link_Geofeature;
   import items.links.Link_Post;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.panel_items.Widget_Attachment_Place_Box;

   // MAYBE: Can we combine this class with Geoeature_Attachment_Add?

   public class Geofeatures_Annotation_Add_Del
                extends Geofeatures_Attachment_Add {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Gf_N_AD');

      // *** Constructor

      //
      public function Geofeatures_Annotation_Add_Del(
         annot:Annotation,
         feats_add:Set_UUID,
         feats_del:Set_UUID,
         placebox_or_link_class:*=null)
      {
         super(feats_add, feats_del, annot, placebox_or_link_class);
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
         var link_gf:Link_Geofeature;
         link_gf = (Link_Value.items_get_link_value(attc, item)
                    as Link_Geofeature);
         if (link_gf === null) {
            var link_class:Class;
            if (this.placebox_or_link_class is Widget_Attachment_Place_Box) {
               m4_DEBUG2('link_value_to_edit: link_value_class:',
                         this.placebox_or_link_class.link_value_class);
               link_class = Item_Base.item_get_class(
                     this.placebox_or_link_class.link_value_class);
            }
            else {
               link_class = this.placebox_or_link_class;
            }
            m4_ASSERT((link_class == Link_Post)
                      || (link_class == Link_Geofeature));
            // I.e., new Link_Post or new Link_Geofeature.
            link_gf = new link_class(null, null, attc, item);
         }
         return link_gf;
      }

   }
}


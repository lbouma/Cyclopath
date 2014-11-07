/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.attcs {

   import flash.utils.Dictionary;

   import grax.Aggregator_Base;
   import items.Attachment;
   import items.Item_Revisioned;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.panel_items.Panel_Item_Annotation;
   import views.panel_items.Panel_Item_Attachment;

   public class Annotation extends Attachment {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Annotation');

      // *** Mandatory attributes

      public static const class_item_type:String = 'annotation';
      public static const class_gwis_abbrev:String = 'anno';
      public static const class_item_type_id:int = Item_Type.ANNOTATION;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Annotation;

      // *** Instance variables

      // The Panel_Item_Annotation panel.
      protected var annotation_panel_:Panel_Item_Annotation;

      // For this.comments, set getter and setter below.

      // *** Constructor

      public function Annotation(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Annotation = (to_other as Annotation);
         super.clone_once(other);
         // Skipping: annotation_panel_
         // Skip?: comments (which is just this.text_ (this.name_))
         other.comments = this.comments;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Annotation = (to_other as Annotation);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.comments = gml.@comments;
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         gml.setName(Annotation.class_item_type); // 'annotation'
         gml.@comments = this.comments;
         return gml;
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         // Annotation doesn't have it's own lookup; call parent which gets the
         // existing item from Attachment.all.
         return super.init_update(existing, item_agg);
      }

      // *** Base class getters and setters

      //
      override public function get actionable_at_raster() :Boolean
      {
         return true;
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         if ((d) && (this.annotation_panel_ !== null)) {
            this.annotation_panel_.close_panel();
         }
      }

      //
      override public function get discardable() :Boolean
      {
         var o:Object;
         var link:Link_Value;
         var links:Array = new Array();
         var b_id:int;

         var is_discardable:Boolean = super.discardable;

         // Geofeature doesn't override discarable, because it doesn't care if
         // any attachments are in memory. Attachments, however, care if any
         // geofeatures are in memory.

         if (is_discardable) {
            // Gather every in-client (working copy) byway link_value that is
            // attached to me.
            // 2013.03.08: Why restrict just to Byway?
            //  for each (link in Link_Value.item_get_link_values(this, Byway))
            for each (link in Link_Value.item_get_link_values(this)) {
               links.push(link);
            }
            // Include deleted geofeature annotation links.
            for each (o in G.item_mgr.deletedset) {
               if ((o is Link_Value)
                   && ((o as Link_Value).lhs_stack_id == this.base_id)) {
                  links.push(o as Link_Value);
               }
            }
            // I can't be discarded if there's a linked geofeature in client
            // memory.
// FIXME: Should thread/post behave similarly?
            for each (link in links) {
               m4_ASSERT(link.lhs_stack_id == this.base_id);
               // NOTE: id_exists just checks feat via item_find_new_old_any.
               if (Item_Revisioned.id_exists(link.feat)) {
                  is_discardable = false;
                  break;
               }
            }
         }

         return is_discardable;
      }

      //
      override public function get friendly_name() :String
      {
         return 'Note';
      }

      //
      override public function is_attachment_panel_set() :Boolean
      {
         return (this.annotation_panel_ !== null);
      }

      // True since Annotations are meaningless unless attached to a
      // Geofeature.
      override public function get is_link_parasite() :Boolean
      {
         return true;
      }

      // *** Getters and setters

      //
      public function get annotation_panel() :Panel_Item_Annotation
      {
         if (this.annotation_panel_ === null) {
            this.annotation_panel_ = (G.item_mgr.item_panel_create(this)
                                      as Panel_Item_Annotation);
            m4_ASSERT(!this.annotation_panel.creation_completed);
            this.annotation_panel_.attachment = this;
         }
         return this.annotation_panel_;
      }

      //
      public function set annotation_panel(
         annotation_panel:Panel_Item_Annotation)
            :void
      {
         if (this.annotation_panel_ !== null) {
            this.annotation_panel_.attachment = null;
         }
         this.annotation_panel_ = annotation_panel;
         if (this.annotation_panel_ !== null) {
            this.annotation_panel_.attachment = this;
         }
      }

      //
      override public function get attachment_panel() :Panel_Item_Attachment
      {
         return annotation_panel;
      }

      //
      override public function set attachment_panel(
         attachment_panel:Panel_Item_Attachment)
            :void
      {
         m4_ASSERT(false); // Not called.
         this.annotation_panel = (attachment_panel as Panel_Item_Annotation);
      }

      //
      [Bindable] public function get comments() :String
      {
         return this.text_;
      }

      //
      public function set comments(comments:String) :void
      {
         this.text_ = comments;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Attachment.all;
      }

      // *** Developer methods

      // Skipping: toString. this.comments is just this.name_, so just super().

   }
}


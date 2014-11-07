/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import mx.controls.Alert;

   import items.Attachment;
   import items.Geofeature;
   import items.Item_User_Access;
   import items.Link_Value;
   import items.attcs.Tag;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_items.Panel_Item_Geofeature;

   public class Geofeatures_Tag_Add extends Geofeatures_Attachment_Add {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Gf_Tag');

      // *** Constructor

      //
      public function Geofeatures_Tag_Add(feats:Set_UUID, tag:Tag)
      {
         var feats_del:Set_UUID = null;
         super(feats, feats_del, tag);
      }

      // *** Getters and Setters

      //
      override public function get descriptor() :String
      {
         return 'add/update tags';
      }

      // *** Protected interface

      override protected function attachment_lookup(supplied:Attachment)
         :Attachment
      {
         // See if a tag w/ the same name already exists and return that,
         // otherwise return the tag the user supplied when they created this
         // command. This prevents duplicate tags (tags with the same name as
         // existing tags) from being created.
         return ((supplied.text_ in Tag.all_named)
                 ? Tag.all_named[supplied.text_] : supplied);
      }

      //
      override protected function link_value_to_edit(attc:Attachment,
                                                     item:Item_User_Access)
                                                      :Link_Value
      {
         // If the feature is already tagged, don't add a new link. So return
         // null, as opposed to Attribute_Links_Edit, which returns the
         // existing link, or Geofeatures_Annotation_Add, which always returns
         // a new link. This is because tag links don't have any value, whereas
         // attribute links have value, e.g., attr.value_integer.
         //
         // FIXME: Update to last statement of previous note: While it is true
         // that tag-links don't have any value (none of the value_* are
         // populated for the Link_Value object), the server expects it. It
         // raises a GWIS_Error if none of the value_* are supplied. This
         // could be solved in three ways:
         //
         //   1. Modify the server code to relax this restiction if the
         //      link_value supplied is linking a geofeature to a tag or an
         //      annotation. To do this, the server must make a DB call to
         //      establish whether the stack_id (lhs_ or rhs_) in the
         //      link_value supplied to it belongs to a tag or an annotation.
         //
         //   2. Send a placeholder value for one of the value_* for
         //      Link_Value objects depicting tag and annotation attachments
         //      to keep the server happy. This means that the server does not
         //      have to make any DB calls to verify that the stack_id
         //      referred to in the link_value belongs to a tag or an
         //      annotation.
         //
         //   3. Modify the server to relax the restriction for all types of
         //      link_values (not recommended).
         //
         // The chosen solution is (2) because it saves the extra DB cycle. It
         // sets a placeholder value for link_value.value_boolean = true
         // meaning that the attachment is attached to the feature.
         var link_value:Link_Value = null;
         if (!item.has_tag(attc.text_)) {
            link_value = new Link_Value(null, null, attc, item);
            // 2012.08.14: During development, someone hacked this is to trick
            //             commit, I think, but this should be fixed, so don't.
            //             OLD HACK: link_value.value_boolean = true;
         }
         return link_value;
         // SIMILAR_TO: Attribute_Links_Edit.link_value_to_edit.
         // SIX_ONE_HALF_DOZ'THER:
         //    Geofeature.has_tag is similar to but uses different algorithm
         //    than Attribute_Links_Edit.link_value_to_edit, which uses:
         //       var link:Link_Value
         //          = Link_Value.items_get_link_value(attc, item);
         // BUG NNNN: Analyze both algorithms, decide if one is better than the
         //           other, then find 'n replace all.
      }

      // *** Public interface

      // Whether or not this command is do-able, undo-able, or redo-able,
      // based on the current map state.
      override public function get performable() :Boolean
      {
         // This command is not performable if there are no links.
         // FIXME Why doesn't this apply to all attachments?
         return ((this.edit_items.length > 0) && (super.performable));
      }

      // *** Do_ and undo

      //
      override public function do_() :void
      {
         super.do_();
         // In the event we added a new tag to the system, make sure it gets
         // reflected in the Control Panel list. Also mark the geofeature panel
         // dirty.
         G.panel_mgr.panels_mark_dirty([G.tabs.settings.settings_panel,]);
         // The edit_items collection is a list of Link_Values, but we don't
         // have a lookup of links to panels. And it doesn't make sense to
         // make one; it's easier just to mark all geofeature panels dirty,
         // which repopulate the tag widget.
         //  G.panel_mgr.item_panels_mark_dirty(this.edit_items);
         G.panel_mgr.item_panels_mark_dirty(Panel_Item_Geofeature);
      }

      //
      override public function undo() :void
      {
         super.undo();
         // Force widget_tag_list to repopulate.
         for each (var lval:Link_Value in this.edit_items) {
            var item_panel:Detail_Panel_Base;
            var loose_selection_set:Boolean = false;
            var skip_new:Boolean = false;
            item_panel = lval.feat.panel_get_for_geofeatures(
               new Set_UUID([lval.feat,]), loose_selection_set, skip_new);
            item_panel.panel_item_details.widget_tag_list.force_repopulate
               = true;
         }
      }

   }
}


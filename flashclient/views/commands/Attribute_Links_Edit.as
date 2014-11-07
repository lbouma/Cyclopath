/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import items.Attachment;
   import items.Geofeature;
   import items.Item_User_Access;
   import items.Link_Value;
   import items.attcs.Attribute;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   // This class is used by UI_Wrapper_Attr_Link to edit Attribute link
   // values. Remember that any two items can be linked, but the properties of
   // the link value (other than the two items being linked) only matter to
   // items linked to attributes, hence, this is the only class that actuals
   // edits the values of links (the other class create or delete links, but
   // they don't care about the link values).
   public class Attribute_Links_Edit extends Geofeatures_Attachment_Add {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Attr_Lk');

      // SIMILAR_TO: Some of this code is similar to Command_Scalar_Edit. This
      //             class also smells of Panel_Item_Geofeature and
      //             Geofeatures_Annotation_Add.

      // *** Instance variables

      protected var attr:Attribute;    // The attribute definition, used to
                                       //   determine the type of the value
      protected var value_new:*;       // The new link_value value
      protected var values_old:Array;  // An array of old values (one for each
                                       //   item being linked to the
                                       //   attribute), used to undo the
                                       //   command

      // *** Constructor

      //
      public function Attribute_Links_Edit(
         attr:Attribute,
         the_items:Set_UUID,
         value_new:*,
         value_type:String=null) // FIXME: value_type is not used? If this is
                                 //        just a link_post-revision, it's
                                 //        value_integer, for the revision ID.
      {
         var lv:Link_Value;

         this.attr = attr;
         m4_ASSERT(!this.attr.invalid);

         // Init. the base class, which finds or creates links for every
         // item-attribute pair.
         var feats_del:Set_UUID = null;
         super(the_items, feats_del, this.attr);

         this.value_new = value_new;

         // Remember the old values so we can undo.
         this.values_old = new Array();
         for each (lv in this.edit_items) {
            // NOTE: I [lb] can't get a definitive answer from the Flex docs,
            //       but "for each" on an array should return the items in
            //       order, right? 'Cause the order in values_old must match.
            m4_DEBUG('ctor: storing old value:', this.attr.value_get(lv));
            this.values_old.push(this.attr.value_get(lv));
         }
      }

      // *** Getters and Setters

      //
      override public function get descriptor() :String
      {
         return 'add/update attribute values';
      }

      // *** Protected interface

      //
      protected function alter(i:int, from:*, to:*) :void
      {
         // NOTE: Ignoring variable 'from' (except for asserts).
         var lv:Link_Value = (this.edit_items[i] as Link_Value);
         m4_DEBUG2('alter: value_get:', this.attr.value_get(lv),
                   '/ to:', to, '/ from:', from);
         m4_ASSERT((isNaN(this.attr.value_get(lv)) && isNaN(from))
                   || (this.attr.value_get(lv) == from));
         this.attr.value_set(lv, to);
         if (lv.feat !== null) {
            lv.feat.draw_all();
         }
         else {
            // FIXME Developer ASSERT vs. Production ASSERTs?
            m4_ASSERT(false);
         }
      }

      //
      override protected function attachment_lookup(supplied:Attachment)
         :Attachment
      {
         // Attributes enforce a strictly-unique name policy; furthermore,
         // unlike the Geofeatures_Tag_Add command, the attribute should exist
         // before this command is called -- we don't automatically add new
         // attributes along w/ this command, because we need the user to
         // configure the new attribute first. Note that we took care of this
         // requirement in the constructor; here we can just return our
         // attribute.
         // FIXME: This performs the same actions as Geofeatures_Attachment_Add
         //        but if we get rid of the override, we lose this comment.
         return supplied;
      }

      //
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
         var i:int;
         super.do_();
         for (i = 0; i < this.edit_items.length; i++) {
            m4_DEBUG2('do_: alter: i:', i, '/ from:', this.values_old[i],
                      '/ to:', this.value_new);
            this.alter(i, this.values_old[i], this.value_new);
         }
// FIXME/BUG nnnn: When changing one_way, redraw the byway.
      }

      //
      override public function undo() :void
      {
         var i:int;
         super.undo();
         for (i = 0; i < this.edit_items.length; i++) {
            m4_DEBUG2('undo: alter: i:', i, '/ from:', this.value_new,
                      '/ to:', this.values_old[i]);
            this.alter(i, this.value_new, this.values_old[i]);
         }
      }

   }
}


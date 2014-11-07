/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: Clean up this file

package views.commands {

   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   import grax.Access_Level;
   import grax.Dirty_Reason;
   import items.Attachment;
   import items.Geofeature;
   import items.Item_User_Access;
   import items.Item_Versioned;
   import items.Link_Value;
   import utils.misc.Logging;
   import utils.misc.Introspect;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   // This class is just an intermediate class; it's not directly instantiated.
   // NOTE Geofeatures_Attachment_Add is a little bit of a misnomer -- this
   //      class can be used to add new attachments, but it also adds new and
   //      updates existing link values. Also, the only new attachments it
   //      supports are tags and annotations; when used with attributes, the
   //      attribute must have already been added to the system.
   public class Geofeatures_Attachment_Add extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Gf_Attc');

      // *** Instance variables

      // The base class maintains the list of items affected by this command
      // (that is, super.feats is a list of link_values). Here, we maintain the
      // set of geofeatures and the attachment being linked.
      protected var feats:Set_UUID;          // One or more Geofeatures
      protected var attc:Attachment;         // One Attachment
      protected var attc_dirty_old:Boolean;  // If dirty before we dirtied it
      protected var attc_dirty_new:Boolean;  // True if attc must be dirty

      protected var attc_ok:Boolean; // True if attachment is prepared ok

      protected var feat_class:Class = null;

      // This is Widget_Attachment_Place_Box or Link_Post or Link_Geofeature.
      protected var placebox_or_link_class:*;

      protected var deleted_feats:Dictionary;
      //protected var add_old:Dictionary; // FIXME: Not used.

      // *** Constructor

      // This class can sometimes automatically handle the addition of fresh,
      // new attachments. That is, for new tags and annotations, there's no
      // need for an Attachment_Create command; this is because tags and
      // annotations are always linked to one or more geofeatures (if they're
      // not, they're considered orphans, and the system ignores orphans).
      // For attributes, however, it's a different story -- an attribute can
      // exist independently of whether or not it's applied to any items. This
      // class also handles finding exising links or creating new ones, as
      // appropriate.
      //
      // NOTE: feats should be a new Set just for this class's use.
      public function Geofeatures_Attachment_Add(
         feats_add:Set_UUID,
         feats_del:Set_UUID,
         attc:Attachment,
         placebox_or_link_class:*=null)
      {
         var feats:Set_UUID;
         if (feats_del !== null) {
            feats = feats_add.clone();
            feats.add_all(feats_del.as_Array());
         }
         else {
            feats = feats_add;
         }

         this.deleted_feats = new Dictionary();
         for each (var f_d:Geofeature in feats_del) {
            this.deleted_feats[f_d.stack_id] = f_d;
         }
         //this.add_old = new Dictionary();
         //for each (var f_a:Geofeature in feats_add) {
         //   this.add_old[f_a.stack_id] = f_a;
         //}

         if (attc.invalid) {
            // This is the first time we've seen the Attachment in the system,
            // so do an attachment lookup to check for duplicates (or other
            // any other rules that subclasses might apply). This is currently
            // only in use with tags.
            //
            // Note that Geofeatures_Tag_Add doesn't check for duplicates
            //  but defers to this logic.
            var compare_attc:Attachment = this.attachment_lookup(attc);
            if (compare_attc !== attc) {
               attc = compare_attc;
               // Don't replace with another invalid attachment.
               // FIXME: is this necessary, or does it just limit behavior?
               m4_ASSERT(!attc.invalid);
            }
         }

         // We only force an attachment to be dirty if it started as invalid
         // (i.e. this command is the creator).
         this.attc_dirty_new = attc.invalid;

         // We must first prepare the attachment. This is an unfortunate
         // place but we need the attachment to be valid before we can create
         // Link_Values attached to it. We remember if preparing failed so
         // we can fail gracefully in prepare_command as expected.
         // 2013.05.24: The new /byway/cycle_facil attribute has client access,
         //             which seems perfectly reasonable. We'll see what the
         //             pyserver commit operation says later....
         //this.attc_ok = G.grac.prepare_item(attc, Access_Level.viewer);
// EXPLAIN: Has attc been added to any lookups yet? This changes its stack_id.
         this.attc_ok = G.grac.prepare_item(attc, Access_Level.client);

         this.placebox_or_link_class = placebox_or_link_class;

         // The parent wants an Array of items, so we make or get links for
         // attc and each of the items in feats. The links may or may not
         // already exist.
         //
         // NOTE: link_values_get_or_make is only called if attc_ok is true
         var links:Array =
            ((!this.attc_ok) ? [] : this.link_values_get_or_make(attc, feats));
         super(links, Dirty_Reason.item_data);
         this.feats = feats;
         this.attc = attc;

         // Remember if the attachment exists and is dirty so, if the user
         // undoes this command, we make sure to make sure the attachment
         // is still marked dirty (because of an earlier command).
         this.attc_dirty_old = this.attc.dirty;

         var rand_feat:Geofeature = (this.feats.item_get_random()
                                     as Geofeature);
         this.feat_class = Introspect.get_constructor(rand_feat);
         m4_TALKY('ctor: this.feat_class:', this.feat_class);
      }

      // *** Getters and Setters

      //
      override public function get descriptor() :String
      {
         m4_WARNING('descriptor: no override:', getQualifiedClassName(this));
         return 'add attachment';
      }

      // *** Instance methods

      // Return the attachment the user supplied when they created this
      // command. For Annotations, this is the desired behavior, but for some
      // Attachments, like Tags, we want to prevent duplicates from being
      // created.
      //
      // NOTE: This is called before the constructor has completed, so
      //   subclasses must be careful with what they depend on.
      protected function attachment_lookup(supplied:Attachment) :Attachment
      {
         return supplied;
      }

      //
      override public function contains_item(item:Item_Versioned) :Boolean
      {
         // We're called whenever the 
         return ((item === this.attc) // the Attachment
                 || super.contains_item(item) // the Link_Values
                 || this.feats.is_member(item)); // the Geofeatures
      }

      //
      private function link_values_get_or_make(attc:Attachment, feats:Set_UUID)
         :Array
      {
         var link:Link_Value;
         var links:Array = new Array();
         var feat:Geofeature;
         for each (feat in feats) {
            // Look for an existing link, or create one.
            link = this.link_value_to_edit(attc, feat);
            if (link !== null) {
               links.push(link);
            }
            // else, in the case of Tags, the link already exists, so
            //       we don't need to add a new one.
         }
         return links;
      }

      //
      protected function link_value_to_edit(attc:Attachment,
                                            item:Item_User_Access)
                                             :Link_Value
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      //
      override public function prepare_command(callback_done:Function,
                                               callback_fail:Function,
                                               ...extra_items_arrays)
         :Boolean
      {
         var prepared:Boolean = false;
         // The attachment had to be prepared in the constructor before
         // the Link_Values were created, but if that failed we need to
         // correctly report failure here.
         if (this.attc_ok) {
            prepared = super.prepare_command.apply(this,
                                                   [callback_done,
                                                    callback_fail,
                                                    extra_items_arrays,]);
         }
         else {
            // 2013.07.02: [lb] is confused about this. So this, like, never
            // happens?
            m4_WARNING('prepare_command: not attc_ok?: this.attc:', this.attc);
         }
         return prepared;
      }

      // *** Do and Undo methods

      //
      override public function do_() :void
      {
         var link:Link_Value;

         // Attachment was prepared by the constructor, and if it had failed
         // the Command_Manager should have ignored the command.
         m4_ASSERT(!this.attc.invalid);

         // If needed, add the attachment to the map before adding the links.
         if (this.attc_dirty_new) {
            m4_TALKY('do_: add: this.attc:', this.attc);
            this.attc.deleted = false;
            G.map.items_add([this.attc,]);
            this.attc.dirty_set(Dirty_Reason.item_data, true);

            // MAYBE: What about making entries for the other feat types?
            //        Or maybe 'null' should be the way to go...
            this.attc.feat_links_count[this.feat_class] = 0;
         }

         this.attc.feat_links_count[this.feat_class] += this.edit_items.length;
         m4_TALKY2('do_: this.attc.feat_links_count:',
                   this.attc.feat_links_count[this.feat_class]);

         // Add the link_value(s) we created in the constructor to the dirtyset
         super.do_();

         for each (link in this.edit_items) {
            // Keep track of how many commands this link is associated with. If
            // the user undoes the command and the count hits 0, we can delete
            // the link.
            // FIXME Do we delete the Attachment if it was fresh and is no
            //       longer attached?
            link.command_count += 1;
         }

// FIXME This doesn't work for Attribute_Links_Edit,
//       which doesn't update the link value until after it
//       calls super.do_()
/*
         G.map.items_add(this.edit_items.slice());
         for each (link in this.edit_items) {
            Geofeature.all[link.rhs_stack_id].draw();
         }
*/

         var to_add:Array = new Array();
         for each (link in this.edit_items) {

            if (link.rhs_stack_id in this.deleted_feats) {
               m4_TALKY('do_: delete link:', link);
               link.deleted = true;
               G.map.item_discard(link);
            }
            else {
               m4_TALKY('do_: add link:', link);
               link.deleted = false;
               // Maybe just do this for fresh items?
               to_add.push(link);
               //if (link.fresh) {
               //   to_add.push(link);
               //}
            }
//// 2013.04.11: Failing on new tag for geofeature without tags...
//m4_DEBUG('link:', link);
//m4_DEBUG('link.rhs_stack_id:', link.rhs_stack_id);
//m4_DEBUG('Geofeature.all[link.rhs_stack_id]:', Geofeature.all[link.rhs_stack_id]);
//            Geofeature.all[link.rhs_stack_id].draw();
         }

         if (to_add.length > 0) {
            m4_TALKY('do_: add: to_add:', to_add);
            G.map.items_add(to_add);
         }

         for each (var item_obj:Object in this.edit_items) {
            link = (item_obj as Link_Value);
            if (link !== null) {
               var feat:Geofeature = Geofeature.all[link.rhs_stack_id];
               if (feat !== null) {
                  feat.draw();
               }
               else {
                  m4_WARNING('do_: rhs not in Geofeature.all: link:', link);
               }
            }
            else {
               m4_WARNING('do_: not a Geofeature:', item_obj);
            }
         }
      }

      //
      override public function undo() :void
      {
         var link:Link_Value;

         super.undo();

         this.attc.dirty_set(Dirty_Reason.item_data, this.attc_dirty_old);

         var to_add:Array = new Array();
         for each (link in this.edit_items) {

            link.command_count -= 1;

            if (link.rhs_stack_id in this.deleted_feats) {
               m4_TALKY('undo: add link:', link);
               link.deleted = false;
               to_add.push(link);
            }
            else if (link.fresh) {
               // Ideally, we should delete the Link_Value
               // Discard the Link_Value if we created it; if we were simply
               // updating an existing link, we don't want to discard it
               if (link.command_count == 0) {
                  // The link is new and no longer associated w/ any commands,
                  // so we can whack it.
                  link.deleted = true;
                  G.map.item_discard(link);
               }
               else {
                  // This smells funny to [lb]... as does link.command_count.
                  m4_WARNING('EXPLAIN: undo: link still in cmd?:', link);
               }
            }
            // else, link already exists and is not fresh, so don't delete it.

            // In any case, make sure we re-draw the feat associated w/ it
//            Geofeature.all[link.rhs_stack_id].draw_all();

            // FIXME: update geofeature's tracking of whether or not it
            // has attachments for rendering
         }

         if (to_add.length > 0) {
            m4_TALKY('undo: add: to_add:', to_add);
            G.map.items_add(to_add);
         }

         this.attc.feat_links_count[this.feat_class] -= this.edit_items.length;
         m4_TALKY2('undo: this.attc.feat_links_count:',
                   this.attc.feat_links_count[this.feat_class]);

         // Cleanup the no-longer wanted attachment.
         // FIXME This might cause Attribute Details to close unexpectedly
         this.attc.set_selected(false, /*nix=*/true);
         if ((this.attc.fresh)
             && (Link_Value.items_for_attachment(this.attc).length == 0)) {
            this.attc.deleted = true;
            G.map.item_discard(this.attc);
         }

         for each (link in this.edit_items) {
            Geofeature.all[link.rhs_stack_id].draw();
         }
      }

   }
}


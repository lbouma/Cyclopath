/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.attcs {

   import flash.utils.Dictionary;

   import grax.Aggregator_Base;
   import items.Attachment;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.panel_items.Panel_Item_Attachment;

   public class Post extends Attachment {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Post');

      // *** Mandatory attributes

      public static const class_item_type:String = 'post';
      public static const class_gwis_abbrev:String = 'post';
      public static const class_item_type_id:int = Item_Type.POST;

      // *** Other static variables

      // *** Instance variables

      public var parent_thread:Thread;

      public var unread:Boolean;
      public var body:String;

      // FIXME: This is Very Dangerous!
      // // BUG 2717: FIXME: Don't do this:
      // public var notify_users:Array;
      // public var notify_purpose:String;

      // This is for route reactions.
      // MAYBE: Make polarity a private link_value attribute, like watchers.
      public var polarity:int; // like = +1, dislike = -1, none = 0.

      // If this is a dummy post...
      public var first_post:Boolean = false;
      public var reply_post:Boolean = false;

      // *** Constructor

      public function Post(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // ***

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' | body: ' + this.body
                 + ' | polarity: ' + this.polarity
                 );
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Post = (to_other as Post);
         super.clone_once(other);
         //other.unread = this.unread;
         other.body = this.body;
         other.polarity = this.polarity;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Post = (to_other as Post);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.body = gml.@body;
            this.polarity = int(gml.@polarity);
            m4_ASSERT(!(G.item_mgr.saving_discussion));

            // NOTE: This makes us the last post in the ordered list.
            //       So here's to hoping the server sends 'em in order! ;)
            // This would be nice, but this fcn. is called before the callback
            // for the GWIS command, so let's wait 'til then to finish wiring.
            //   m4_ASSERT(this.parent_thread !== null);
            //   this.parent_thread.register_post(this);
         }
         else {
            // This happens for new Post(), when user is make a new one.
            this.polarity = 0; // Neutral unless explicitly stated.
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         var username:String;

         gml.setName(Post.class_item_type); // 'post'

         gml.@thread_stack_id = this.parent_thread.stack_id;

         // Bug 2743 - Database: Some post.body being stored as 'null'.
         if (this.body !== null) {
            gml.@body = this.body;
         }

         gml.@polarity = this.polarity;

         return gml;
      }

      //
      /*/
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         super.init_add(item_agg, soft_add);
         m4_ASSERT_SOFT(!soft_add);
         if (this !== Post.all[this.stack_id]) {
            if (this.stack_id in Post.all) {
               m4_WARNING2('init_add: overwrite:',
                           Post.all[this.stack_id]);
               m4_WARNING('               with:', this);
               m4_WARNING(Introspect.stack_trace());
            }
            Post.all[this.stack_id] = this;
         }
      }
      /*/

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         // NOTE: Not calling: super.init_update(existing, item_agg);
         m4_ASSERT(existing === null);
         var post:Post = Attachment.all[this.stack_id];
         if (post !== null) {
            m4_VERBOSE('Updating Post:', this);
            // clone will call clone_update and not clone_once because of post.
            this.clone_item(post);
         }
         else {
            // else, invalid or deleted but not in the lookup, so ignore
            m4_ASSERT_SOFT(false);
         }
         return post;
      }

      //
      override public function is_attachment_panel_set() :Boolean
      {
         // Not applicable, but shouldn't matter.
         return false;
      }

      //
      override public function get is_revisionless() :Boolean
      {
         return true;
      }

      // ***

      //
      override public function get attachment_panel() :Panel_Item_Attachment
      {
         // Not applicable, but doesn't matter.
         //    m4_ASSERT(false); // Not applicable.
         return null;
      }

      //
      override public function set attachment_panel(
         attachment_panel:Panel_Item_Attachment)
            :void
      {
         m4_ASSERT(false); // Not called.
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Attachment.all;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         m4_WARNING('set selected: no one calls this, do they?');
         m4_WARNING(Introspect.stack_trace());
         super.set_selected(s, nix, solo);
      }

   }
}


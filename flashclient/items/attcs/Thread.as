/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.attcs {

   import flash.utils.Dictionary;

   import grax.Aggregator_Base;
   import items.Attachment;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.panel_discussions.Panel_Item_Thread;
   import views.panel_items.Panel_Item_Attachment;

   public class Thread extends Attachment {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Thread');

      // *** Mandatory attributes

      public static const class_item_type:String = 'thread';
      public static const class_gwis_abbrev:String = 'thread';
      public static const class_item_type_id:int = Item_Type.THREAD;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Thread;

      // *** Instance variables

      // The Panel_Item_Thread panel.
      protected var thread_panel_:Panel_Item_Thread;

      public var count_posts_total:int;
      public var count_posts_unread:int;
      public var last_post_username:String;
      public var last_post_timestamp:String;
      public var last_post_body:String;

      // The thread type and polarity (avg. user route rating) were added circa
      // 2012 for route reactions.
      //
      // The thread type is either 'general' or 'reaction'. Threads and posts
      // about a route (a route reaction) are 'reaction'-type threads; threads
      // and posts about all of item types (byways, waypoints, regions, etc.)
      // are 'general'-type threads.
      public var ttype:String;
      //
      // The polarity is the avg. thumbs-up- or thumbs-down-ness of a
      // 'reaction'-type thread (where each thread post holds an individual
      // user's route rating).
      public var likes:int;
      public var dislikes:int;
      public var comments:int;

      // References to the posts within this thread.
      public var psids:Dictionary = new Dictionary();
      public var posts:Array = new Array();

      // *** Constructor

      public function Thread(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // ***

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' / total: ' + String(this.count_posts_total)
                 + ' / unread: ' + String(this.count_posts_unread)
                 + ' / ' + this.last_post_username
                 + ' / ' + this.last_post_timestamp
                 //+ ', body: ' + this.last_post_body
                 );
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Thread = (to_other as Thread);
         m4_DEBUG('clone_once: this:', this);
         m4_DEBUG('clone_once: other:', other);
         super.clone_once(other);
         // Skipping: thread_panel_
         other.count_posts_total = this.count_posts_total;
         other.count_posts_unread = this.count_posts_unread;
         other.last_post_username = this.last_post_username;
         other.last_post_timestamp = this.last_post_timestamp;
         other.last_post_body = this.last_post_body;
         other.ttype = this.ttype;
         other.likes = this.likes;
         other.dislikes = this.dislikes;
         other.comments = this.comments;
         //other.psids = Collection.dict_copy(this.psids);
         //other.posts = Collection.array_copy(this.posts);

      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Thread = (to_other as Thread);
         super.clone_update(other, newbie);
         m4_DEBUG('clone_update: this:', this);
         m4_DEBUG('clone_update: other:', other);
         other.count_posts_total = this.count_posts_total;
         other.count_posts_unread = this.count_posts_unread;
         other.last_post_username = this.last_post_username;
         other.last_post_timestamp = this.last_post_timestamp;
         other.last_post_body = this.last_post_body;
         other.ttype = this.ttype;
         other.likes = this.likes;
         other.dislikes = this.dislikes;
         other.comments = this.comments;
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         this.psids = new Dictionary();
         this.posts = new Array();
         if (gml !== null) {
            // NOTE: Either total and read is set, or just matched.
            this.count_posts_total = int(gml.@count_posts_total);
            var count_posts_read:int = int(gml.@count_posts_read);
            this.count_posts_unread =
               this.count_posts_total - count_posts_read;
            this.last_post_username = gml.@last_post_username;
            this.last_post_body = gml.@last_post_body;
            this.last_post_timestamp = gml.@last_post_timestamp;
            // Route reactions: add thread-type and thread-polarity.
            this.ttype = gml.@ttype;
            // Skipping: this.thread_type_id = gml.@thread_type_id;
            this.likes = int(gml.@likes);
            this.dislikes = int(gml.@dislikes);
            this.comments = int(gml.@comments);
            m4_DEBUG('gml_consume: has gml:', this);
         }
         else {
            this.ttype = 'general'; // General thread unless over-written.
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         gml.setName(Thread.class_item_type); // 'thread'
         gml.@ttype = this.ttype;
         return gml;
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         // NOTE: Not calling: super.init_update(existing, item_agg);
         m4_ASSERT(existing === null);
         var thread:Thread = Attachment.all[this.stack_id];
         if (thread !== null) {
            m4_VERBOSE('Updating Thread:', this);
            // clone will call clone_update and not clone_once because thread.
            this.clone_item(thread);
         }
         else {
            // else, invalid or deleted but not in the lookup, so ignore.
            // Asserting here, to understand/explain if this'll really happen.
            m4_ASSERT_SOFT(false);
         }
         return thread;
      }

      //
      override public function is_attachment_panel_set() :Boolean
      {
         return (this.thread_panel_ !== null);
      }

      //
      public function register_post(post:Post) :void
      {
         if (post.parent_thread === null) {
            post.parent_thread = this;
            this.psids[post.stack_id] = post;
            this.posts.push(post);
         }
         else {
            m4_ASSERT_SOFT(post.parent_thread === this);
            m4_ASSERT_SOFT(post.stack_id in this.psids);
            m4_ASSERT_SOFT(Collection.array_in(post, this.posts));
         }
      }

      // *** Getters and setters

      //
      public function get active_post() :Post
      {
         var active_post:Post = null;
         if (this.posts.length > 0) {
            active_post = this.posts[this.posts.length - 1];
         }
         return active_post;
      }

      //
      public function set active_post(post:Post) :void
      {
         m4_WARNING('What does this mean??');
      }

      //
      override public function get friendly_name() :String
      {
         return 'Topic';
      }

      //
      override public function get is_revisionless() :Boolean
      {
         return true;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         // This is called when you make a new discussion.
         m4_DEBUG('set selected: access_level_id:', this.access_level_id);
         super.set_selected(s, nix, solo);
      }

      //
      public function get thread_panel() :Panel_Item_Thread
      {
         if (this.thread_panel_ === null) {
            // 2013.05.30: That accessing this variable causes the panel to be
            // created makes some bugs sooo confusing. E.g., a call to
            // print the panel causes the panel to be created (so if you're
            // curious if the panel is null, you've already messed up!).
            // Talk about Schrodinger's cat!
            this.thread_panel_ = (G.item_mgr.item_panel_create(this)
                                 as Panel_Item_Thread);
            this.thread_panel_.thread = this;
         }
         return this.thread_panel_;
      }

      //
      public function set thread_panel(thread_panel:Panel_Item_Thread) :void
      {
         if (this.thread_panel_ !== null) {
            this.thread_panel_.thread = null;
         }
         this.thread_panel_ = thread_panel;
         if (this.thread_panel_ !== null) {
            this.thread_panel_.thread = this;
         }
      }

      // *** Base class getters and setters

      //
      override public function get attachment_panel() :Panel_Item_Attachment
      {
         return thread_panel;
      }

      //
      override public function set attachment_panel(
         attachment_panel:Panel_Item_Attachment)
            :void
      {
         m4_ASSERT(false); // Not called.
         this.thread_panel = (thread_panel as Panel_Item_Thread);
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Attachment.all;
      }

   }
}


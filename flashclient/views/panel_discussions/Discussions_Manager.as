/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class manages the so-called 'Side Panel'.

package views.panel_discussions {

   import flash.events.Event;
   import mx.controls.Alert;

   import grax.Access_Level;
   import grax.Dirty_Reason;
   import gwis.GWIS_Checkout_Base;
   import gwis.GWIS_Checkout_Versioned_Items;
   import gwis.GWIS_Commit;
   import gwis.GWIS_Item_Read_Event_Put;
   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.attcs.Post;
   import items.attcs.Thread;
   import items.links.Link_Geofeature;
   import utils.misc.Counter;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.misc.Timeutil;
   import utils.rev_spec.*;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_routes.Panel_Item_Route;

   public class Discussions_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Discuss_Mgr');

      // *** Instance attributes

      public var post_auto_attach:Boolean;
      public var post_sid_auto_select:int;

      // *** Constructor

      //
      public function Discussions_Manager() :void
      {
         m4_DEBUG('Welcome to the Discussions_Manager!');

         // NOTE: Unlike some of the other *_Manager classes, we don't create
         //       and manage any panels in this class itself. See the
         //       panel_activity package.

         G.panel_mgr.panel_register(G.tabs.discuss_panel);
         // G.panel_mgr.panel_register(G.tabs.reactions_panel);
      }

      // *** Discussions panel

      //
      public function discussions_panel_update(
         thread:Thread=null,
         activate_panel:Boolean=false)
            :void
      {
         var panel:Detail_Panel_Base;
         var heading:String;

         m4_DEBUG('discussions_panel_update: thread:', thread);

         m4_ASSERT(G.app !== null);

         if (G.app !== null) {
            if (thread !== null) {

               // EXPLAIN: What's this do?:
               if (thread.stack_id > 0) {
                  thread.thread_panel.reset_panel();
               }

               if (G.tabs.activity.activities !== null) {
                  // Show the Panel_Item_Thread panel, which shows the post
                  // list.
                  G.panel_mgr.panel_activate(thread.thread_panel);
               }
               else {
                  m4_DEBUG('EARLY: discussions_panel_update (1)');
               }
            }
            else if (G.tabs.activity.activities !== null) {
               // Show the Latest_Activity_Panels panel, which shows the thread
               // list.
               if (activate_panel) {
                  G.panel_mgr.panel_activate(G.tabs.activity.activities);
                  // What about G.tabs.activity.activities.general?
               }
            }
            else {
               m4_DEBUG('EARLY: discussions_panel_update (2)');
            }

            // FIXME: route reactions addthis. But we're not switching panels
            //        correctly in the new Statewide interface...
            //  if ((G.tabs.changes_panel === null)
            //      && (G.tabs.activities !== null)) {
            //     G.tabs.changes_panel = G.tabs.activities.changes;
            //  }

            G.panel_mgr.update_bg_and_title();

            // Olde behaviour:
            //  if (force_refresh) {
            //     var update_paginator_count:Boolean = force_refresh;
            //     G.tabs.discuss_panel.fetch_list(update_paginator_count);
            // //  G.tabs.reactions_panel.fetch_list(update_paginator_count);
            //  }

         }
      }

      //
      public function thread_open(thread:Thread) :void
      {
         if (G.user.logged_in) {
            m4_TALKY('thread_open: thread:', thread);
            var gwis_cmd:GWIS_Item_Read_Event_Put;
            gwis_cmd = new GWIS_Item_Read_Event_Put([thread.system_id,]);
            var found_duplicate:Boolean;
            found_duplicate = G.map.update_supplemental(gwis_cmd);
            m4_ASSERT_SOFT(!found_duplicate);
         }
         this.discussions_panel_update(thread, /*activate_panel=*/true);
         thread.count_posts_unread = 0;
      }

      //
      // NOTE: This file is coupled funny: it handles both thread-posts and
      //       route-reactions. Which are both types of discussions, so it
      //       smells like we could decouple this code and use polymorphism
      //       and a class hierarchy to do this. But we only have one
      //       Discussions_Manager... so for now we'll just use at least
      //       different entry points (i.e., two different fcns. instead of
      //       if/elsing one bigger fcn.).

      //
      public function route_reaction_commit(the_thread:Thread,
                                            anon_coward:Boolean=false) :void
      {
         this.discussion_commit(
            the_thread,
            anon_coward,
            this.route_reaction_commit_load,
            this.route_reaction_commit_fail);
      }

      //
      public function thread_post_commit(the_thread:Thread,
                                         callback_payload:*=null) :void
      {
         // MAYBE: BUG nnnn: Option to commit anonymously, even if logged in.
         var anon_coward:Boolean = false;

         if (G.item_mgr.contains_dirty_revisioned) {
// BUG_FALL_2013: Make sure this doesn't happen before user writes revision
//                feedback -- or allow it for revision feedback, which should
//                not matter for a post about an existing revision...
            Alert.show(
               'Please save your map change before saving new posts, '
               + 'in case your new post talks about new or changed items.',
               'Please save the map before posting',
               Alert.OK);
         }
         else {
            this.discussion_commit(
               the_thread,
               anon_coward,
               this.thread_post_commit_load,
               this.thread_post_commit_fail,
               callback_payload);
         }
      }

      //
      protected function discussion_commit(the_thread:Thread,
                                           anon_coward:Boolean,
                                           callback_load:Function,
                                           callback_fail:Function,
                                           callback_payload:*=null)
                                             :void
      {
         var changedset:Set_UUID = new Set_UUID();
         var tpanel:Panel_Item_Thread = (the_thread.thread_panel
                                         as Panel_Item_Thread);
         var changenote:String;

         m4_ASSERT(!(G.item_mgr.saving_discussion));

         m4_DEBUG2('discussion_commit: the_thread.active_post:',
                   the_thread.active_post);
         m4_DEBUG2('discussion_commit: the_thread.posts.length:',
                   the_thread.posts.length);

         if (the_thread.fresh) {
            // New thread and post.
            the_thread.dirty_set(Dirty_Reason.item_data_oob, true);
            changedset.add(the_thread);
            changenote = "New thread: " + the_thread.name_;
         }
         else {
            changenote = "New post in thread: " + the_thread.name_;
         }

         // Just the new post.
         if (the_thread.active_post.invalid) {
            if (the_thread.active_post.stack_id == 0) {
               // EXPLAIN: What's going on here?
               G.item_mgr.assign_id(the_thread.active_post);
               m4_DEBUG2('discussion_commit: assigned id: active_post:',
                         the_thread.active_post);
            }
            else {
               m4_DEBUG2('discussion_commit: id already assignd: active_post:',
                         the_thread.active_post);
            }
         }

         // VERIFY: route reactions. [lb] is just guessing:
         // We're always creating a new post.
         m4_ASSERT_SOFT(the_thread.active_post.stack_id < 0);

         the_thread.active_post.dirty_set(Dirty_Reason.item_data_oob, true);
         //G.grac.prepare_item(the_thread.active_post, Access_Level.viewer);
         G.grac.prepare_item(the_thread.active_post, Access_Level.client);
         m4_DEBUG('discussion_commit: prepared the_thread:', the_thread);

         // Already done?: G.map.items_add([the_thread,]);

         changedset.add(the_thread.active_post);

         var link_gf:Link_Geofeature;
         for each (link_gf in tpanel.post_geos_dirty) {
            var lhs_item:Object = the_thread.active_post;
            var rhs_item:Object = null; // Retain rhs_item.
            link_gf.link_value_set(lhs_item, rhs_item);
            link_gf.dirty_set(Dirty_Reason.item_data_oob, true);
            //G.grac.prepare_item(link_gf, Access_Level.viewer);
            G.grac.prepare_item(link_gf, Access_Level.client);
            m4_DEBUG('discussion_commit: prepared link_gf:', link_gf);

            G.map.items_add([link_gf,]);

            changedset.add(link_gf);
         }

// FIXME_2013_06_11: This guy: so silly:
         G.item_mgr.saving_discussion = true;

         var my_payload:Object = {
            'thread': the_thread,
            'caller': callback_payload
         };

         var gwis_cmd:GWIS_Commit;
         gwis_cmd = new GWIS_Commit(
            changedset,
            changenote,
            /*be_silent=*/false,
            callback_load,
            callback_fail,
            /*callback_payload=*/my_payload,
            /*anon_coward=*/false,
            // So that we don't save map items -- i.e., Very Important.
            /*restrict_dirty=*/Dirty_Reason.item_mask_oob,
            /*alert_on_activity=*/false,
            /*command_mgr=*/null);

         gwis_cmd.fetch();
      }

      // ***

      //
      protected function thread_post_commit_load(gwis_req:GWIS_Commit,
                                                 rset:XML,
                                                 payload:*=null)
         :void
      {

         // FIXME: This little block is just debug code for [lb].
         m4_ASSERT(gwis_req.changed_items.length > 0);
         var thread:Thread;
         var post:Post;
         var link_gf_cnt:int = 0;
         for each (var o:Object in gwis_req.changed_items) {
            if (o is Thread) {
               m4_ASSERT(thread === null);
               thread = (o as Thread);
            }
            else if (o is Post) {
               m4_ASSERT(post === null);
               post = (o as Post);
            }
            else {
               m4_ASSERT(o is Link_Geofeature);
               link_gf_cnt++;
            }
         }

         m4_DEBUG('thread_post_commit_load: payload.thread:', payload.thread);
         m4_DEBUG('thread_post_commit_load: thread:', thread);
         m4_DEBUG('thread_post_commit_load: post:', post);
         m4_DEBUG('thread_post_commit_load: link_gf_cnt:', link_gf_cnt);

      // FIXME/VERIFY: When we save the post, do we clone it to a new item
      // or do we accidentally use one of the special global Posts?

         m4_DEBUG2('thread_post_commit_load: payload.thread.posts[0]:',
                   payload.thread.posts[0]);
         m4_DEBUG2('thread_post_commit_load: payload.thread.posts[-1]:',
                   payload.thread.posts[payload.thread.posts.length - 1]);

         // GWIS_Commit processes gwis_req.client_id_map, so:
         if (thread !== null) {
            m4_ASSERT(thread.stack_id > 0);
            m4_ASSERT(thread === payload.thread);
         }

         // We just saved a new post and maybe a new thread, as well, so,
         // when the thread details panel is closed, we'll want to know to
         // reload the thread list.
         // FIXME: This variable is not used.
         payload.thread.thread_panel.thread_or_post_saved = true;

         this.thread_post_commit_cleanup(payload);

         this.thread_open(payload.thread);

         // FIXME_2013_06_11
         m4_DEBUG2('thread_post_commit_load: Refresh on more posts?:',
                   payload.thread.thread_panel);
         // Here's a cheat
         payload.thread.thread_panel.fetched_posts = false;
         m4_DEBUG('thread_post_commit_load: panels_mark_dirty: thread_panel');
         G.panel_mgr.panels_mark_dirty([payload.thread.thread_panel,]);

         // See instead Panel_Item_Thread.reset_panel().
         //  payload.thread.thread_panel.dirty_post = false;

         payload.thread.thread_panel.placebox.mark_for_reinit();

         payload.thread.thread_panel.post_editing_inactive(post);
         // If a new thread, add to the discussion list.
         if (payload.thread.posts.length == 1) {
            payload.thread.count_posts_total = 1;
            payload.thread.count_posts_unread = 0;
            payload.thread.last_post_username = G.user.username;
            payload.thread.last_post_timestamp = Timeutil.time_24_now();
            if (post !== null) {
               payload.thread.last_post_body = post.body;
            }
            m4_ASSERT_ELSE_SOFT;
            // Hook the Tab_Discussions_Posts.
            //    G.tabs.activity.activities.general
            //    === G.tabs.discuss_panel
            G.tabs.discuss_panel.add_new_thread(payload.thread);
         }
      }

      //
      protected function thread_post_commit_fail(gwis_req:GWIS_Commit,
                                                 rset:XML,
                                                 payload:*=null)
         :void
      {
         var the_thread:Thread = payload.thread;
         m4_ASSERT(the_thread !== null);

         m4_DEBUG('thread_post_commit_fail: the_thread:', the_thread);
         m4_DEBUG('   ... the_thread.fresh:', the_thread.fresh);

         this.thread_post_commit_cleanup(payload);

         // BUG nnnn/FIXME: Test this. Boot flashclient, kill the server, then
         // trying saving 1) a new thread and 2) a new post in an existing
         // thread. There are new items that are dirty and G.map.items_add
         // was called on them just before the commit so maybe extra goodness
         // has to happen here.
      }

      //
      protected function thread_post_commit_cleanup(payload:*=null) :void
      {
         m4_DEBUG('thread_post_commit_cleanup');

         m4_ASSERT(payload !== null);

         var the_thread:Thread = payload.thread;
         m4_ASSERT(the_thread !== null);

         // If the request failed, make sure to mark the post and thread
         // not-dirty, otherwise we'll keep complaining to the user that they
         // have unsaved map changes.

         m4_ASSURT(the_thread.active_post !== null);
         the_thread.active_post.dirty_set(Dirty_Reason.item_data_oob, false);

         //the_thread.active_post = null;

         the_thread.dirty_set(Dirty_Reason.item_data_oob, false);

         var tpanel:Panel_Item_Thread = the_thread.thread_panel;
         if (tpanel !== null) {
            var link_gf:Link_Geofeature;
            for each (link_gf in tpanel.post_geos_dirty) {
               link_gf.dirty_set(Dirty_Reason.item_data_oob, false);
            }
         }

         // NOTE: Coupling. We expect the payload to be a Widget_Post_Renderer.
         // NOTE: The pointer to the post_renderer used to be stored herein,
         //       but what happens if we get a duplicate request while one is
         //       still pending? We'd overwrite the pointer, that's what. So
         //       now it's stored for us as whatever data in the GWIS_Commit.
         var wpr:Widget_Post_Renderer;
         wpr = (payload.caller as Widget_Post_Renderer);
         if (wpr !== null) {
            wpr.post_btn_enable_maybe();
         }

         m4_ASSERT(G.item_mgr.saving_discussion);
         G.item_mgr.saving_discussion = false;
      }

      // ***

      //
      protected function route_reaction_commit_load(gwis_req:GWIS_Commit,
                                                    rset:XML,
                                                    payload:*=null)
         :void
      {
         m4_ASSERT(payload !== null);

         var the_thread:Thread = payload.thread;
         m4_ASSERT(the_thread !== null);

         // Two kinds of reaction posts can be saved:
         //
         // 1. Posts with no body (only like/dislike).
         //    Keep the objects around for saving comment.
         // 2. Posts with a body (with/without like/dislike).
         //    Switch to thank-you mode.

         // PROBLY: Coupling. The Panel should addEventListener instead of us
         //         twiddling it. Or the caller should register the
         //         Panel_Item_Route and we can use its items_selected.

         // VERIFY: Statewide UI: Can we still use active_route here?
         // VERIFY: Statewide UI: Can we still use route_panel here?
         var route_panel:Panel_Item_Route
            = G.item_mgr.active_route.route_panel;

         var reaction_panel:Route_Reaction = null;
         if (route_panel !== null) {
            reaction_panel = route_panel.widget_feedback.route_reaction;
            m4_ASSERT(reaction_panel !== null);
         }
         else {
            // This probably doesn't happen...
            m4_WARNING('route_reaction_commit_load: no tab_route_details??');
         }

         if (the_thread.active_post.body === null) {
            // Only like/dislike was saved.
            if (route_panel !== null) {
               reaction_panel.active_post.stack_id
                  = gwis_req.client_id_map[the_thread.active_post.stack_id]
                    .new_id;
               reaction_panel.active_post.parent_thread.stack_id
                  = gwis_req.client_id_map[the_thread.stack_id]
                    .new_id;
               reaction_panel.active_post.version = 1;

               // Increment counts.
               if (reaction_panel.like.selected) {
                  G.map.likes_visible += 1;
               }
               if (reaction_panel.dislike.selected) {
                  G.map.dislikes_visible += 1;
               }
            }
         }
         else {
            m4_ASSURT(the_thread.active_post.body != '');
            // Comment was saved.
            if (route_panel !== null) {
               // Change the route reaction widget to the thank state.

// BUG_FALL_2013: Route Reactions. FIXME: Reimplement route reactions.
               if (Conf_Instance.debug_goodies) {
                  reaction_panel.currentState = 'thank'; // 'input' or 'thank'.
               }
               // MAYBE: reaction_panel.change_state('thank');
               //        (reac has to derive from Detail_Panel_Base first)
               // Increment count.
               G.map.comments_visible += 1;
            }
         }

         // Reset.
         //this.discussions_panel_update();
         //reaction_panel.my_reaction_thread = G.item_mgr.active_thread;
         reaction_panel.my_reaction_thread = the_thread;
         this.thread_post_commit_cleanup(payload);
      }

      //
      protected function route_reaction_commit_fail(gwis_req:GWIS_Commit,
                                                    rset:XML, payload:*=null)
         :void
      {
         m4_DEBUG('route_reaction_commit_fail');
         this.thread_post_commit_cleanup(payload);
      }

      // *** Deep Link callbacks

      //
      public function deep_link_discussion(deep_link_params:Object) :void
      {
         // Test it!:
// http://greatermn.cyclopath.org/#discussion?thread_id=4099711&post_id=4099712

         m4_ASSERT_SOFT(deep_link_params.thread_id !== null);

         if (deep_link_params.thread_id) {

            if (deep_link_params.post_id !== null) {
               // lame hack...:
               this.post_sid_auto_select = deep_link_params.post_sid;
            }

            var gwis_checkout:GWIS_Checkout_Base = null;
            var rev_cur:utils.rev_spec.Base = new utils.rev_spec.Current();
            var buddy_ct:Counter = null;
            var qfs:Query_Filters = new Query_Filters();
            //qfs.include_item_stack = true;
            qfs.only_stack_ids.push(deep_link_params.thread_id);
            var update_req:Update_Base = null;
            var resp_items:Array = null; // This is for diffing.
            var callback_load:Function = this.checkout_thread_load;
            var callback_fail:Function = this.checkout_thread_fail;

            gwis_checkout = new GWIS_Checkout_Versioned_Items(
               Thread.class_item_type, rev_cur, buddy_ct, qfs,
               update_req, resp_items, callback_load, callback_fail);

            var found_duplicate:Boolean;
            found_duplicate = G.map.update_supplemental(gwis_checkout);
            m4_ASSERT_SOFT(!found_duplicate);
         }
      }

      //
      protected function checkout_thread_fail(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         m4_WARNING('checkout_thread_fail');
      }

      //
      protected function checkout_thread_load(
         gwis_req:GWIS_Checkout_Base, xml:XML) :void
      {
         if (gwis_req.resp_items.length > 0) {

            m4_ASSERT_SOFT(gwis_req.resp_items.length == 1);

            var thread:Thread = gwis_req.resp_items[0];

            m4_DEBUG('checkout_thread_load: thread:', thread);

            G.map.items_add([thread,]);

            G.panel_mgr.panels_mark_dirty([thread.thread_panel,]);

            this.thread_open(thread);
         }
         m4_ASSERT_ELSE_SOFT;
      }

   }
}


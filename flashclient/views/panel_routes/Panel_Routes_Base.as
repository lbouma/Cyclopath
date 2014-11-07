/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.utils.getQualifiedClassName;
   import mx.collections.ArrayCollection;
   import mx.controls.Button;
   import mx.core.Container;
   import mx.events.FlexEvent;

   import gwis.GWIS_Checkout_Base;
   import gwis.GWIS_Checkout_Count;
   import gwis.GWIS_Checkout_Versioned_Items;
   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.feats.Route;
   import utils.misc.Counter;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.panel_base.Detail_Panel_Base;
   import views.panel_base.Detail_Panel_Widget;
   import views.panel_routes.Route_List;
   import views.panel_routes.Route_List_Entry;
   import views.panel_routes.Route_List_Key;
   import views.panel_util.Paginator_Widget;

   public class Panel_Routes_Base extends Detail_Panel_Widget {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@PnlRtesBase');

      // Nice and tacky. This base class is shared by somewhat similar looking
      // panels, so why not manage this feature at the class level.
      // FIXME: Just make a shared widget and get rid of duplicate code. DRY.
      [Bindable] public static var hide_routes_on_panel_closed:Boolean = true;
      [Bindable] public static var recalculate_routes_on_fetch:Boolean = false;

      protected static var uncheck_on_panel_close_label:String =
         //"Hide route when its panel closes";
         //"Hide route on panel close";
         //"Hide route when panel closed";
         //"Remove route from map on panel close";
         //"Hide route when you close its panel";
         //"Hide route when its panel is closed";
         //"Hide route when panel closed";
         //"Hide when panel closed";
         "Closing panel hides route";

      protected static var recalculate_routes_on_fetch_label:String =
         //"Auto-fix stale routes";
         "Repair broken routes";

      // *** Instance variables

      protected var outstanding_cmd:GWIS_Checkout_Base;
      protected var outstanding_cnt:GWIS_Checkout_Base;

      // This flag is set to tell the widget to reload the route_list.
      protected var force_fetch_list_next:Boolean;

      protected var query_filters:Query_Filters = null;

      protected var route_list_routes:ArrayCollection = new ArrayCollection();

      // *** Constructor

      public function Panel_Routes_Base()
      {
         super();
      }

      // ***

      //
      override protected function on_initialize(ev:FlexEvent) :void
      {
         m4_DEBUG('logged_in prob: on_init');

         super.on_initialize(ev);

         this.register_widgets([
            this.get_route_list_key(),
            ]);

         this.route_list_pager.records_per_page
            = Conf.search_num_results_show;
         this.route_list_pager.list_control_callback
            = this.list_control_callback;

         m4_DEBUG('on_initialize: addEventListener: branchChange');
         G.item_mgr.addEventListener('branchChange',
                                     this.on_active_branch_change);

         this.on_active_branch_change();
      }

      //
      override protected function on_hide_event(ev:FlexEvent) :void
      {
         // No-op. And don't call super(), which throws.
      }

      //
      override public function on_show_event(ev:FlexEvent=null) :void
      {
         m4_DEBUG2('on_show_event: this:', this,
                   '/ creation_completed:', this.creation_completed);
         // Not calling super.on_show_event.

// NOT BEING CALLED... not for repopulate, and not for on_panel_show...
         m4_DEBUG2('on_show_event: this.visible:', this.visible,
                   '/force_fetch_list_next: ', this.force_fetch_list_next);

// FIXME: If first page of results and routes viewed recently,
//        reload this list?

// In Route Library, reload page every ten minutes to see if
// others have shared? Or make command to check results and
// load recent ones?
//
// BUG nnnn: Revision List, Discussions, etc., need lightweight
//           way to periodically check for new list items, and
//           to insert them in the heads of the lists if the
//           lists are active and the first paginator of
//           results is showing.

         if ((this.force_fetch_list_next) && (this.visible)) {
            this.force_fetch_list_next = false;
            this.fetch_list();
         }

         var arr:Array = this.on_filter_cbox_changed();
      }

      // ***

      // NOTE: For widgets, repopulate and depopulate are not automatically
      //       called. Neither is on_panel_show, which doesn't propagate.
      //       We could have the panel signal an event, and then we could just
      //       listen on the panel, or we could listen to the flex hide and
      //       show events, which makes sense, since we just want to check
      //       a bool to see if we have to fix the list of route results.

      //
      override protected function add_listeners_show_and_hide(
         just_kidding:*=null) :void
      {
         m4_DEBUG('add_listeners_show_and_hide: this:', this);
         // Unlike Detail_Panel_Base, widgets don't normally listen on show and
         // hide, since there are a lot of them and most don't need it. Most
         // widgets listen on specific item changes or other events, but don't
         // tend to care when they're shown or hidds.
         just_kidding = false;
         super.add_listeners_show_and_hide(just_kidding);
      }

      //
      public function force_fetch_list_next_maybe(force:Boolean=false)
         :void
      {
         m4_DEBUG3('force_fetch_list_next_maybe: current_page_number:',
                   this.route_list_pager.current_page_number,
                   '/ visible:', this.visible);
         if ((force) || (this.route_list_pager.current_page_number == 1)) {
            if (G.panel_mgr.effectively_active_panel === G.app.routes_panel) {
               this.fetch_list();
               var arr:Array = this.on_filter_cbox_changed();
            }
            else {
               this.force_fetch_list_next = true;
               if (this.visible) {
                  this.repopulate();
               }
            }
         }
      }

      //
      override protected function has_auto_scroll_bar_policy() :Boolean
      {
         return true;
      }

      //
      protected function list_control_callback() :void
      {
         m4_ASSERT(false); // Abstract.
      }

      //
      protected function on_active_branch_change(event:Event=null) :void
      {
         m4_DEBUG('on_active_branch_change');
         this.reset_route_list();
      }

      //
      protected function on_added_renderer_maybe(ev:Event) :void
      {
         // m4_DEBUG('on_added_renderer_maybe: target:', ev.target);
         var renderer:Route_List_Entry = (ev.target as Route_List_Entry);
         if (renderer !== null) {
            // m4_DEBUG('  .. setting renderer.detail_panel:', this.dp);
            // Note: Route_List_Entry can also use its this.parentDocument.
            renderer.detail_panel = this.dp;
         }
      }

      //
      public function on_filter_cbox_changed(
         at_least_one_checked:Boolean=false)
            :Array
      {
         var arr:Array = null;

         if (at_least_one_checked) {
            this.get_uncheck_all_btn().enabled = true;
         }
         else {
            arr = this.count_checked_unchecked();
            this.get_uncheck_all_btn().enabled = (arr[0] > 0);
         }

         return arr;
      }

      //
      protected function on_uncheck_on_panel_close_click(event:MouseEvent)
         :void
      {
         m4_DEBUG2('on_uncheck_on_panel_close_click: selected:',
                   event.target.selected);
         Panel_Routes_Base.hide_routes_on_panel_closed = event.target.selected;
      }

      //
      protected function on_recalculate_routes_on_fetch_click(event:MouseEvent)
         :void
      {
         m4_DEBUG2('on_recalculate_routes_on_fetch_click: selected:',
                   event.target.selected);
         Panel_Routes_Base.recalculate_routes_on_fetch = event.target.selected;
      }

      // ***

      //
      protected function count_checked_unchecked() :Array
      {
         var num_checked:int = 0;
         var num_unchecked:int = 0;

         var route_list:Route_List = this.get_route_list_widget();
         if ((route_list !== null) && (route_list.dataProvider !== null)) {
            var num_renderers:int = 0;
            num_renderers = route_list.dataProvider.length;
            m4_DEBUG2('count_checked_unchecked: num_renderers:',
                      num_renderers);
            for (var i:int = 0; i < num_renderers; i++) {
               // The Flex DataGrid reuses item renderers by using as many
               // as the user can see, so it's wrong to ask route_list_entry
               // e.g., route_list.dataProvider.indexToItemRenderer(i) does
               // not work (and not that it returns null for list entries
               // that are clipped, but it seems to return null for all
               // entries!). So instead we just get the route and use its
               // knowledge of the checkbox state. Silly!
               //renderer = this.indexToItemRenderer(i) as Route_List_Entry;
               var route:Route = (route_list.dataProvider[i] as Route);
               m4_DEBUG('count_checked_unchecked: route:', route);
               if (route.filter_show_route) {
                  num_checked += 1;
               }
               else {
                  num_unchecked += 1;
               }
            }
         }
         else {
            m4_DEBUG('count_checked_unchecked: no route_list');
         }

         m4_DEBUG2('count_checked_unchecked: num_checked:', num_checked,
                   '/ num_unchecked:', num_unchecked);

         return [num_checked, num_unchecked,];
      }

      // ***

      //
      override public function get panel_owning_panel() :Detail_Panel_Base
      {
         // We belong to a container panel (i.e., tab bar and ViewStack).
         //
         // DEVS: [lb] has seen the flex compiler baulk here, complaining:
         //             "Error: Implicit coercion of a value of type
         //              views.panel_routes:Panel_Routes_Box to an
         //              unrelated type mx.core:Container."
         //       But if you run make a second time, it should work.
         return G.app.routes_panel;
      }

      //
      public function get_route_list_key() :Route_List_Key
      {
         m4_ASSERT(false); // Abstract.
         return null;
      }

      //
      public function get_route_list_widget() :Route_List
      {
         m4_ASSERT(false); // Abstract.
         return null;
      }

      //
      public function get_uncheck_all_btn() :Button
      {
         m4_ASSERT(false); // Abstract.
         return null;
      }

      //
      public function get route_list_pager() :Paginator_Widget
      {
         m4_ASSERT(false); // Abstract.
         return null;
      }

      //
      public function set route_list_pager(pager:Paginator_Widget) :void
      {
         m4_ASSERT(false); // Not called.
      }

      // ***

      //
      public function fetch_list() :void
      {
         m4_ASSERT(false); // Abstract.
      }

      //
      public function fetch_list_really(qfs:Query_Filters) :void
      {
         this.route_list_pager.configure_query_filters(qfs);
         m4_DEBUG('fetch_list_really: pagin_total:', qfs.pagin_total);
         m4_DEBUG('fetch_list_really: pagin_count:', qfs.pagin_count);
         m4_DEBUG('fetch_list_really: pagin_offset:', qfs.pagin_offset);

         // Don't bother loading, i.e., tags and notes for routes.
         // FIXME/BUG nnnn: Allow notes and tags on routes?
         qfs.dont_load_feat_attcs = true;
         //? qfs.skip_tag_counts = true;
         qfs.include_item_aux = false;

         // MAYBE: Include the item_stack, so we get access_style_id and
         //        stealth_secret.
         qfs.include_item_stack = true;

         var item_type_str:String = Route.class_item_type; // I.e., 'route'.
         // We don't do historic routes.
         var rev_cur:utils.rev_spec.Base = new utils.rev_spec.Current();
         var buddy_ct:Counter = null;
         var update_req:Update_Base = null;
         var resp_items:Array = null; // This is for diffing.
         var callback_load:Function = this.route_results_load;
         var callback_fail:Function = this.route_results_fail;

         var gwis_cmd:GWIS_Checkout_Versioned_Items;
         gwis_cmd = new GWIS_Checkout_Versioned_Items(
               item_type_str, rev_cur, buddy_ct, qfs, update_req,
               resp_items, callback_load, callback_fail);

         // Uncomment the following code if a progress bar should be used
         //var gwis_active_alert:Please_Wait_Popup;
         //gwis_active_alert = new Please_Wait_Popup();
         //
         //UI.popup(gwis_active_alert, 'b_cancel');
         //gwis_active_alert.init('Searching routes', 'Please wait.',
         //                      gwis_cmd, true);
         //gwis_cmd.gwis_active_alert = gwis_active_alert;
         //gwis_active_alert.gwis_active = gwis_cmd;

         if (this.outstanding_cmd !== null) {
            this.outstanding_cmd.cancel();
            this.outstanding_cmd = null;
         }

         var found_duplicate:Boolean;
         found_duplicate = G.map.update_supplemental(gwis_cmd);
         if (!found_duplicate) {
            m4_DEBUG('fetch_list_really: outstanding_cmd:', gwis_cmd);
            this.outstanding_cmd = gwis_cmd;
         }
         else {
            m4_WARNING('fetch_list_really: found_duplicate:', gwis_cmd);
            m4_ASSERT_SOFT(false);
         }

         // MAYBE: See also the latest activity and discussions panels,
         //        which employ fetch_list(update_paginator_count). Here,
         //        we check a copy of the old query_filters to see if anything
         //        changed. Maybe we can replace update_paginator_count with
         //        that approach.
         //
         // If the query is new or we haven't fetched the complete query count,
         // do that.
         if ((this.query_filters === null)
             || (!this.query_filters.equals(qfs))) {
            this.fetch_count_really(qfs);
         }
      }

      //
      public function fetch_count_really(qfs:Query_Filters) :void
      {
         m4_DEBUG('fetch_count_really: qfs:', qfs);

         this.query_filters = qfs;

         // Since we're using pageination (OFFSET and COUNT), the total
         // count must be fetched by a separate query and doesn't specify
         // offset or count.
         qfs = this.query_filters.clone()
         qfs.pagin_count = 0;
         qfs.pagin_offset = 0;
         qfs.pagin_total = true;
         qfs.include_item_stack = false;
         //
         var item_type_str:String = Route.class_item_type; // I.e., 'route'.
         var callback_load:Function = this.search_counts_load;
         var callback_fail:Function = this.search_counts_fail;
         var gwis_cmd:GWIS_Checkout_Count = new GWIS_Checkout_Count(
            item_type_str, this.route_list_pager, qfs,
            callback_load, callback_fail);

         if (this.outstanding_cnt !== null) {
            this.outstanding_cnt.cancel();
            this.outstanding_cnt = null;
         }
         var found_duplicate:Boolean;
         found_duplicate = G.map.update_supplemental(gwis_cmd);
         if (!found_duplicate) {
            this.outstanding_cnt = gwis_cmd;
         }
         else {
            m4_ASSERT_SOFT(false);
         }
      }

      //
      // MAYBE: If on_active_branch_change event works, remove call to
      //        reset_route_list from Map_Canvas_Items and make this
      //        fcn protected.
      public function reset_route_list() :void
      {
         m4_DEBUG('reset_route_list');
         // In CcpV1, we call G.map.item_discard(route), but what if the
         // route panel is open, or what if the route is in another route
         // list. In CcpV3, we discard the route only if it's not in any
         // route list, nor attached to any panel, so therefore no longer
         // useable... well, the route could be reuseable if the user is
         // using the Paginator, because the user could return to the page
         // with the route and select it.
         // No: Remove the route from the map/memory.
         //   for each (var route:Route in this.route_list_routes) {
         //      G.map.item_discard(route);
         //   }
         // Because: The Route_List_Entry will detach itself from the Route,
         //          and the Route might choose to remove itself from the map.
         this.route_list_pager.records_total_count = 0;
         this.rte_results_load(new ArrayCollection());
      }

      //
      protected function rte_results_load(rte_results:ArrayCollection) :void
      {
         //m4_DEBUG2('rte_results_load: route_list_routes: rte_results:',
         //          rte_results.length);

         this.route_list_routes = rte_results;
         //m4_DEBUG2('rte_results_load: this.route_list_routes:',
         //          this.toString_dataProvider());

         //this.get_route_list_widget().dataProvider = this.route_list_routes;
         this.get_route_list_widget().update_route_list(
                                 this.route_list_routes);

         // We set the scroll here and not in the class itself because there's
         // a FIXME in get_route_list_widget.update. For now, just reset the
         // scroll when we get a new list of results from the server. This is
         // so, e.g., when the user clicks a paginator arrow, the scroll moves
         // to the top of the new list of items.
         this.get_route_list_widget().verticalScrollPosition = 0;

         m4_DEBUG('rte_results_load: update_pagination_text');
         //this.route_list_pager.p_collect = this.route_list_routes;
         this.route_list_pager.p_collect =
            this.get_route_list_widget().dataProvider;
         //this.route_list_pager.records_total_count =
         //   this.route_list_routes.length;
         // Kick the paginator so it refreshes.
         this.route_list_pager.update_pagination_text();

         var arr:Array = this.on_filter_cbox_changed();
      }

      //
      protected function route_results_load(
         gwis_req:GWIS_Checkout_Base,
         xml:XML) :void
      {
         m4_DEBUG2('route_results_load: gwis_req.resp_items.len:',
                   gwis_req.resp_items.length);
         // GWIS_Checkout_Base doesn't pre-process the items, so see if the
         // Route doesn't already exist. Note that this updates the route
         // if it's in memory, via init_update, which should be an effective
         // noop (i.e., we won't clobber any data... except maybe the route
         // name if it was updated by another user in parallel).
         var rts_results:ArrayCollection = new ArrayCollection();
         // BUG nnnn: Branch Conflicts: If the user edits the route locally...
         //   does this mean we'll clobber the local copy? Maybe we shouldn't
         //   call items_add...
         //   G.map.items_add(gwis_req.resp_items,
         //                   /*complete_now=*/true,
         //                   /*final_items=*/rts_results);
         for each (var route:Route in gwis_req.resp_items) {
            var use_rte:Route = Route.all[route.stack_id];
            if (use_rte === null) {
               use_rte = route;
            }
            else {
               m4_DEBUG('route_results_load: existing route:', use_rte);
            }
            rts_results.addItem(use_rte);
         }
         this.rte_results_load(rts_results);
         this.outstanding_cmd = null;
      }

      //
      protected function route_results_fail(
         gwis_req:GWIS_Checkout_Base,
         xml:XML) :void
      {
         m4_WARNING('route_results_fail: checkout failed');
         // FIXME: Do anything special?
         this.outstanding_cmd = null;
      }

      //
      protected function search_counts_load(
         gwis_req:GWIS_Checkout_Base,
         xml:XML) :void
      {
         this.outstanding_cnt = null;
      }

      //
      protected function search_counts_fail(
         gwis_req:GWIS_Checkout_Base,
         xml:XML) :void
      {
         m4_WARNING('search_counts_fail: counts failed');
         this.outstanding_cnt = null;
      }

      // ***

      //
      protected function toString_dataProvider() :String
      {
         var route_sids:String = '';
         for each (var route:Route in this.route_list_routes) {
            if (route_sids != '') {
               route_sids += ', ';
            }
            route_sids += String(route.stack_id);
         }
         return route_sids;
      }

      // ***

   }
}


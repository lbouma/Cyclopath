/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_Checkout;
import org.cyclopath.android.gwis.GWIS_CheckoutCallback;
import org.cyclopath.android.gwis.GWIS_RouteGetCallback;
import org.cyclopath.android.gwis.GWIS_RouteGetSaved;
import org.cyclopath.android.gwis.QueryFilters;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.Route;

import android.content.Context;
import android.os.Bundle;
import android.view.View;
import android.view.View.OnClickListener;
import android.view.inputmethod.InputMethodManager;
import android.widget.AbsListView;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.ListView;
import android.widget.TabHost;
import android.widget.TextView;
import android.widget.AbsListView.OnScrollListener;
import android.widget.TabHost.OnTabChangeListener;

/**
 * Activity that allows users to search the Route Library.
 * @author Fernando Torre
 */
public class RouteLibrary extends BaseListActivity
                          implements GWIS_CheckoutCallback,
                                     GWIS_RouteGetCallback,
                                     OnTabChangeListener,
                                     OnScrollListener {
   
   /** current offset for search results */
   private int offset;
   /** references to tabs */
   private TabHost tabs;
   /** array of current routes listed */
   private ArrayList<Route> current_routes;
   /** adapter being used to connect list of routes to the list items in the
    * layout */
   private RouteListAdapter current_adapter;
   /** Whether additional routes have been requested when reaching the end of
    * the list */
   private boolean additional_routes_requested = false;
   
   // *** Listeners

   /**
    * Called when the activity is first created.
    */
   @Override
   public void onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState);
      setContentView(R.layout.route_library_main);

      this.offset = 0;
      this.current_routes = new ArrayList<Route>();
      
      // Set tabs up.
      this.tabs = (TabHost)findViewById(android.R.id.tabhost);
      this.tabs.setup();
      TabHost.TabSpec spec1 =
         this.tabs.newTabSpec("my_routes")
                  .setContent(R.id.dummy_text)
                  .setIndicator("My routes");
      this.tabs.addTab(spec1);
      TabHost.TabSpec spec2 =
         this.tabs.newTabSpec("other_routes")
                  .setContent(R.id.dummy_text)
                  .setIndicator("Others' routes");
      this.tabs.addTab(spec2);

      // Show public routes by default.
      this.tabs.setCurrentTab(1);
      // If the user is logged in, show user routes.
      if (G.user.isLoggedIn()) {
         // It is necessary to go to the second tab and then the first tab.
         // Otherwise, Android pops up the soft keyboard and it is impossible
         // to remove for some reason.
         this.tabs.setCurrentTab(0);
      }

      tabs.setOnTabChangedListener(this);
      
      // Hack to ensure that the search text field is not selected by default,
      // which results in the soft keyboard being opened when the activity
      // starts.
      TextView temp = (TextView) findViewById(R.id.dummy_text);
      temp.setFocusable(true);
      temp.setFocusableInTouchMode(true);
      temp.requestFocus();
      
      ((ListView) findViewById(android.R.id.list)).setOnScrollListener(this);
      
      findViewById(R.id.route_library_search_btn)
         .setOnClickListener(new OnClickListener(){
         @Override
         public void onClick(View v) {
            submit_query();
            ((ImageButton) findViewById(R.id.route_library_clear_btn))
               .setVisibility(View.VISIBLE);
         }
      });
      
      findViewById(R.id.route_library_clear_btn)
         .setOnClickListener(new OnClickListener(){
         @Override
         public void onClick(View v) {
            ((EditText) findViewById(R.id.route_library_search_field))
               .setText("");
            ((ImageButton) findViewById(R.id.route_library_clear_btn))
               .setVisibility(View.GONE);
            submit_query();
         }
      });

      this.submit_query();
   }

   /**
    * Retrieve a route when a user clicks on it.
    */
   @Override
   protected void onListItemClick (ListView l, View v, int position, long id) {
      Route r = (Route)l.getItemAtPosition(position);
      new GWIS_RouteGetSaved(r.stack_id,
                             "android_top",
                             false,
                             true,
                             this).fetch();
   }

   /**
    * If the user reaches the end of the list and has not yet requested more
    * routes, request the additional routes.
    */
   @Override
   public void onScroll(AbsListView view, int firstVisibleItem,
                        int visibleItemCount, int totalItemCount) {
      if (firstVisibleItem + visibleItemCount >= totalItemCount
            && visibleItemCount < totalItemCount
            && totalItemCount > 0
            && !this.additional_routes_requested) {
         this.submit_query(this.offset + 1);
         this.additional_routes_requested = true;
      }
   }

   /** Method required when implementing OnScrollListener. Currently no-op.*/
   @Override
   public void onScrollStateChanged(AbsListView view, int scrollState) { }

   /**
    * Resubmits the request for routes whenever the user switches tabs.
    */
   @Override
   public void onTabChanged(String tabId) {
      this.submit_query();
      updateResultsText();
   }
   
   // *** Other Methods

   /**
    * After a route has been retrieved, sets it as the active route and exits
    * the Route Library.
    */
   @Override
   public void handleGWIS_RouteGetComplete(Route r) {
      G.setActiveRoute(r);
      finish();
   }

   /**
    * Handles the list of routes that is retrieved from the server.
    */
   @Override
   public void handleGWIS_CheckoutComplete(
                                 ArrayList<ItemUserAccess> feats) {
      
      ArrayList<Route> routes = new ArrayList<Route>();
      for (ItemUserAccess f:feats) {
         if (f.getClass().getName().equals(Route.class.getName())) {
            routes.add((Route)f);
         }
      }
      
      if (this.offset > 0) {
         this.current_routes.addAll(routes);
         if (!routes.isEmpty()) {
            this.additional_routes_requested = false;
         }
      } else {
         this.current_routes = routes;
         this.current_adapter =
            new RouteListAdapter(this, this.current_routes);
         setListAdapter(this.current_adapter);
         this.additional_routes_requested = false;
      }
      this.current_adapter.notifyDataSetChanged();
      updateResultsText();
   }

   /**
    * Submits a request for routes with no offset.
    */
   public void submit_query() {
      this.submit_query(0);
   }

   /**
    * Submits a request for routes.
    * @param query_offset
    */
   public void submit_query(int query_offset) {
      this.offset = query_offset;
      QueryFilters qfs = new QueryFilters();
      qfs.filter_by_text_smart =
            ((TextView)findViewById(R.id.route_library_search_field))
               .getText().toString().trim();
      qfs.pagin_count = Constants.SEARCH_NUM_RESULTS_SHOW;
      qfs.pagin_offset = query_offset;
      qfs.dont_load_feat_attcs = true;
      qfs.include_item_aux = false;
      qfs.include_item_stack = true;
      if (this.tabs.getCurrentTab() == 0) {
         if (!G.user.isLoggedIn()) {
            this.handleGWIS_CheckoutComplete(
                  new ArrayList<ItemUserAccess>());
            return;
         }
         qfs.filter_by_creator_include = G.user.getName();
      } else {
         qfs.filter_by_creator_exclude = G.user.getName();
      }

      InputMethodManager inputManager =
         (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
      if (this.getCurrentFocus() != null) {
         inputManager.hideSoftInputFromWindow(
            this.getCurrentFocus().getWindowToken(),
            InputMethodManager.HIDE_NOT_ALWAYS);
      }
      
      new GWIS_Checkout("route", qfs, this,
            this.getResources().getString(
                  R.string.route_library_searching_title),
            this.getResources().getString(
                  R.string.route_library_searching_message)).fetch();
   }

   /**
    * Updates the text right above the results list.
    */
   public void updateResultsText() {
      String query =
         ((TextView)findViewById(R.id.route_library_search_field))
            .getText().toString();
      String results_txt;
      if (this.current_routes.isEmpty()) {
         results_txt =
            getResources().getString(R.string.route_library_no_results);
      } else if (query.equals("")) {
         results_txt =
            getResources().getString(R.string.route_library_all_results);
      } else {
         results_txt =
            getResources().getString(R.string.route_library_results_for)
            + " "
            + query;
      }
      ((TextView)findViewById(R.id.route_library_results_text))
         .setText(results_txt);
   }

}

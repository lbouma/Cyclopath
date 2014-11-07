/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.items.Route;
import org.w3c.dom.Document;

/**
 * This GWIS class handles getting saved routes. This class is based in part on
 * flashclient/GWIS_GetRoute_Saved.as.
 * @author Phil Brown
 */
public class GWIS_RouteGetSaved extends GWIS {
   // *** Instance variables
      
   /** Callback function called once the request results have been processed. */
   protected GWIS_RouteGetCallback callback;
   /** Route id*/
   protected int route_id;
   /** where this route request came from (phone, flash client,
    * html widget, etc)*/
   protected String source;
   /** as gpx tag*/
   protected boolean as_gpx;
   /** flag to check whether the current route is still valid */
   protected boolean check_invalid;

   public GWIS_RouteGetSaved(int route_id, String source,
                               boolean as_gpx, boolean check_invalid,
                               GWIS_RouteGetCallback callback) {
      super("route_get", "", true, null,
            G.app_context.getResources().getString(
                  R.string.route_get_saved_loading_title),
            G.app_context.getResources().getString(
                  R.string.route_get_saved_loading_message));
      this.query_filters = new QueryFilters();
      this.query_filters.include_item_stack = true;
      this.query_filters.include_item_aux = true;
      this.route_id = route_id;
      this.source = source;
      this.as_gpx = as_gpx;
      this.check_invalid = check_invalid;
      this.callback = callback;
      try {
          this.url += "&rt_sid=" + route_id
                   + "&source=" + URLEncoder.encode(source,"UTF-8")
                   + "&asgpx=" + (as_gpx ? 1 : 0)
                   + "&checkinvalid=" + (check_invalid ? 1 : 0);
      } catch(UnsupportedEncodingException e) {
         // FIXME: better error handling
         e.printStackTrace();
      }
   }//GWIS_Route_Get_Saved
   
   // *** Instance methods
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_RouteGetSaved g = new GWIS_RouteGetSaved(this.route_id,
                                                        this.source,
                                                        this.as_gpx,
                                                        this.check_invalid,
                                                        this.callback);
      g.retrying = true;
      return g;
   }//clone

   /**
    * Shows error to user.
    * @param text error text
    */
   @Override
   protected void errorPresent(String text) {
      G.showAlert(text,
          G.app_context.getResources().getString(R.string.route_finder_error));
   }//errorPresent

   /**
    *  Calls the method that is in charge of handling the saved route's 
    *  retrieval.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      Route r = new Route(rset.getElementsByTagName("route").item(0));
      this.callback.handleGWIS_RouteGetComplete(r);
   }//processResultset

}//GWIS_Route_Get_Saved

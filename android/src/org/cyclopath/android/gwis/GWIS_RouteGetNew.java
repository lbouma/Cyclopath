/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.items.Route;
import org.cyclopath.android.util.Address;
import org.w3c.dom.Document;

/**
 * This GWIS class handles route finding. This class is based in part on
 * flashclient/GWIS_GetRoute.as.
 * @author Fernando Torre
 */
public class GWIS_RouteGetNew extends GWIS {

   // *** Instance variables
   
   /** Callback function called once the request results have been processed.*/
   protected GWIS_RouteGetCallback callback;
   /** starting address */
   protected Address from_addr;
   /** destination address */
   protected Address to_addr;
   /** where this route request came from (phone, flash client,
    * html widget, etc) */
   protected String source;
   /** XML String with user route finding preferences */
   protected String preferences_xml;

   // *** Constructor

   /**
    * Constructs a route request.
    * @param from_addr the starting address
    * @param to_addr the destination address
    * @param source where this route request came from (phone, flash client,
    *               html widget, etc)
    * @param preferences_xml XML String with user route finding preferences
    * @param as_gpx FIXME
    * @param callback function to be called once the route request has been
    *                 processed
    */
   public GWIS_RouteGetNew(Address from_addr,
                         Address to_addr,
                         String source,
                         String preferences_xml,
                         GWIS_RouteGetCallback callback) {
      super("route_get", "", true, null,
            G.app_context.getResources().getString(
                  R.string.route_finder_progress_dialog_title),
            G.app_context.getResources().getString(
                  R.string.route_finder_progress_dialog_content));
      
      this.query_filters = new QueryFilters();
      this.query_filters.include_item_stack = true;

      this.callback = callback;
      this.from_addr = from_addr;
      this.to_addr = to_addr;
      this.source = source;
      this.preferences_xml = preferences_xml;
      
      try {
         url += "&beg_addr="
               + URLEncoder.encode(from_addr.text,"UTF-8")
               + "&beg_ptx="
               + URLEncoder.encode(Double.toString(from_addr.x),"UTF-8")
               + "&beg_pty="
               + URLEncoder.encode(Double.toString(from_addr.y),"UTF-8")
               + "&fin_addr="
               + URLEncoder.encode(to_addr.text,"UTF-8")
               + "&fin_ptx="
               + URLEncoder.encode(Double.toString(to_addr.x),"UTF-8")
               + "&fin_pty="
               + URLEncoder.encode(Double.toString(to_addr.y),"UTF-8")
               + "&travel_mode=bicycle"
               + "&source="
               + URLEncoder.encode(source,"UTF-8")
               + "&asgpx=false";
      } catch (UnsupportedEncodingException e) {
         // FIXME: better error handling
         e.printStackTrace();
      }
      this.data = preferences_xml;
   }

   // *** Instance methods
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_RouteGetNew g = new GWIS_RouteGetNew(this.from_addr,
                                            this.to_addr,
                                            this.source,
                                            this.preferences_xml,
                                            this.callback);
      g.retrying = true;
      return g;
   }

   /**
    * Shows error to user.
    * @param text error text
    */
   @Override
   protected void errorPresent(String text) {
      G.showAlert(text,
          G.app_context.getResources().getString(R.string.route_finder_error));
   }

   /**
    *  Calls the method that is in charge of handling the route request
    *  completion.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      Route r = new Route(rset.getElementsByTagName("route").item(0));
      this.callback.handleGWIS_RouteGetComplete(r);
   }

}

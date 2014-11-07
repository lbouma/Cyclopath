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
 * This GWIS class handles getting shared routes by their hashcode. This class 
 * is based in part on flashclient/GWIS_GetRoute_ByHash.as.
 * @author Phil Brown
 */
public class GWIS_RouteGetByHash extends GWIS {
   // *** Instance variables
      
   /** Callback function called once the request results have been processed. */
   protected GWIS_RouteGetCallback callback;
   /** Link hash id of the route*/
   protected String hash_id;
   /** where this route request came from (phone, flash client,
    * html widget, etc) */
   protected String source;
   
   public GWIS_RouteGetByHash(String hash_id, String source, 
                               GWIS_RouteGetCallback callback){
      super("route_get");
      this.query_filters = new QueryFilters();
      this.query_filters.include_item_stack = true;
      this.hash_id = hash_id;
      this.source = source;
      this.callback = callback;
      try {
         url += "&hashid=" + URLEncoder.encode(hash_id,"UTF-8")
                + "&source=" + URLEncoder.encode(""+source,"UTF-8")
                + "&checkinvalid=1"
                + "&asgpx=0";
      } catch(UnsupportedEncodingException e) {
         // FIXME: better error handling
         e.printStackTrace();
      }
   }//GWIS_Route_Get_By_Hash
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_RouteGetByHash g = new GWIS_RouteGetByHash(this.hash_id, 
                                                            this.source,
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
    *  Calls the method that is in charge of handling the received route.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      Route r = new Route(rset.getElementsByTagName("route").item(0));
      this.callback.handleGWIS_RouteGetComplete(r);
   }//processResultset

}//GWIS_Route_Get_By_Hash

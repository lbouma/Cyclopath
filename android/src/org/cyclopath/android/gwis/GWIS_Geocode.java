/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import java.net.URLEncoder;
import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.w3c.dom.Document;

/**
 * This GWIS class handles user geocoding. This class is originally based on
 * flashclient/WFS_Geocode.as.
 * @author Fernando Torre
 */
public class GWIS_Geocode extends GWIS {

   // *** Instance variables
   
   /** Callback function called once the request results have been processed. */
   protected GWIS_GeocodeCallback callback;

   // *** Constructor

   /**
    * Constructs a new geocode request.
    * @param addrs List of addresses to geocode
    * @param callback function to be called once the geocode request has been
    *                 processed
    */
   public GWIS_Geocode(ArrayList<String> addrs,
                       GWIS_GeocodeCallback callback) {
      super("geocode", "", true, null,
            G.app_context.getResources().getString(
                  R.string.route_finder_progress_dialog_title),
            G.app_context.getResources().getString(
                  R.string.route_finder_progress_dialog_content));

      this.callback = callback;
      
      // add addresses to XML
      StringBuilder xml_data = new StringBuilder("<addrs>");
      for (String addr : addrs) {
         xml_data.append("<addr addr_line=\"" 
// [lb] is guessing...
                         + URLEncoder.encode(addr)
                         + "\" />");
      }
      xml_data.append("</addrs>");

      this.data = xml_data.toString();
   }

   // *** Instance methods

   /**
    * Shows error to user.
    * @param text error text
    */
   @Override
   protected void errorPresent(String text) {
      G.showAlert(text,
           G.app_context.getResources().getString(R.string.gwis_geocode_fail));
   }

   /**
    *  Calls the method that is in charge of handling the geocoding
    *  completion.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      this.callback.handleGWIS_GeocodeComplete(rset);
   }

}

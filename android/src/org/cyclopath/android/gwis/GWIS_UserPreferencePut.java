/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.w3c.dom.Document;

import android.util.Log;

/**
 * This GWIS class handles saving user prefernces on the server. This class is
 * originally based on flashclient/WFS_PutPreference.as.
 * @author Fernando Torre
 */
public class GWIS_UserPreferencePut extends GWIS {

   // *** Constructor
   
   protected String prefs_xml;

   /**
    * Constructs a user preference save request.
    * @param prefs_xml XML String with user preferences to be saved.
    */
   public GWIS_UserPreferencePut(String prefs_xml) {
      super("user_preference_put");
      
      this.prefs_xml = prefs_xml;
      this.data = prefs_xml;
   }
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_UserPreferencePut g =
         new GWIS_UserPreferencePut(this.prefs_xml);
      g.retrying = true;
      return g;
   }

   /**
    * Shows error to user.
    * @param text error text
    */
   @Override
   protected void errorPresent(String text) {
      //FIXME
      G.showAlert(
            G.app_context.getResources().getString(
                     R.string.gwis_preference_put_fail)
               + text,
            G.app_context.getResources().getString(R.string.error));
   }

   /**
    *  Processes the results. For now, lets the parent class handle the result
    *  processing and simply logs that the save request was succesful.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      if (Constants.DEBUG) {
         Log.d("debug","user preference saved successfully");
      }
   }
}

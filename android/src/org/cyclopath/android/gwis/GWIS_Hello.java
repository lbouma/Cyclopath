/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.w3c.dom.Document;
import org.w3c.dom.Node;

/**
 * This GWIS class handles user login. This class is originally based on
 * flashclient/WFS_Hello.as.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class GWIS_Hello extends GWIS {

   // *** Instance variables

   protected String username;
   protected String password;
   /** True if the user's login information should be saved. */
   protected boolean rememberme;
   /** Callback function called once the request results have been processed. */
   protected GWIS_HelloCallback callback;

   // *** Constructor

   /**
    * Constructs a new login request.
    */
   public GWIS_Hello(String username,
                     String password,
                     boolean rememberme,
                     GWIS_HelloCallback callback) {
      super("user_hello");

      this.username = username;
      this.password = password;
      this.rememberme = rememberme;
      this.callback = callback;
   }

   // *** Instance methods
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_Hello g = new GWIS_Hello(this.username,
                                    this.password,
                                    this.rememberme,
                                    this.callback);
      g.retrying = true;
      return g;
   }

   /**
    * Prepare metadata containing user credentials.
    * @return XML string with user credentials
    */
   @Override
   protected String getCredentialsXML() {
      return "<user name=\""
             + this.username
             + "\" pass=\""
             + this.password
             + "\" />";
   }

   /**
    * Shows error to user.
    * @param text error text
    */
   @Override
   protected void errorPresent(String text) {
      G.showAlert(text,
                  G.app_context.getResources().getString(
                        R.string.gwis_hello_login_fail));
   }

   /**
    *  Processes the incoming result set. The presence of a result set tells
    * us that login was successful.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      String token = rset.getElementsByTagName("token")
                         .item(0).getFirstChild().getNodeValue();
      Node preferences = rset.getElementsByTagName("preferences").item(0);
      this.callback.handleGWIS_HelloComplete(this.username,
                                             token,
                                             preferences,
                                             this.rememberme);
   }

}

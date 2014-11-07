/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import org.w3c.dom.Node;

/**
 * A callback interface for handling user login.
 * @author Fernando Torre
 * @author Phil Brown
 */
public interface GWIS_HelloCallback {

   /**
    * This method is called once a user login request has been processed.
    */
   public void handleGWIS_HelloComplete(String username,
                                        String token,
                                        Node preferences,
                                        boolean rememberme);
   
}

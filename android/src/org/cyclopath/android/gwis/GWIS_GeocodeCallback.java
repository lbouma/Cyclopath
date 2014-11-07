/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import org.w3c.dom.Document;

/**
 * A callback interface for handling geocoding.
 * @author Fernando Torre
 */
public interface GWIS_GeocodeCallback {

   /**
    * This method is called once a geocode request has been processed.
    */
   public void handleGWIS_GeocodeComplete(Document results);
   
}

/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import org.w3c.dom.Document;

/**
 * A callback interface for handling landmark trial information.
 * @author Fernando Torre
 */
public interface GWIS_LandmarkTrialGetCallback {

   /**
    * This method is called once landmark trial information has been retrieved.
    */
   public void handleGWIS_LandmarkTrialGetComplete(Document results);
   
}

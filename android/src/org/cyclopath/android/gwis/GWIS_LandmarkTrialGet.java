/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import org.w3c.dom.Document;

/**
 * Gets a trial condition for this user for the landmarks experiment
 * @author Fernando Torre
 */
public class GWIS_LandmarkTrialGet extends GWIS {
   
   /** callback to handle trial information */
   public GWIS_LandmarkTrialGetCallback callback;
   /** trial for which to get information */
   public int trial_num;

   /**
    * Constructor
    */
   public GWIS_LandmarkTrialGet(GWIS_LandmarkTrialGetCallback callback) {
      this(-1, callback);
   }

   /**
    * Constructor
    */
   public GWIS_LandmarkTrialGet(int trial_num,
                                GWIS_LandmarkTrialGetCallback callback) {
      super("landmark_trial_get");
      this.trial_num = trial_num;
      this.callback = callback;
      if (trial_num > 0) {
         this.url += "&trial_num=" + trial_num;
      }
   }

   @Override
   public GWIS clone() {
      GWIS_LandmarkTrialGet g = new GWIS_LandmarkTrialGet(this.trial_num,
                                                          this.callback);
      g.retrying = true;
      return g;
   }
   
   /**
    * Sets the global landmark condition.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      if (this.callback != null) {
         this.callback.handleGWIS_LandmarkTrialGetComplete(rset);
      }
   }

}

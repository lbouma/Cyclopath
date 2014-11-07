/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

/**
 * Updates the current trial with the id of the corresponding track.
 * @author Fernando Torre
 */
public class GWIS_LandmarkTrialPut extends GWIS {

   /**
    * Constructor
    */
   public GWIS_LandmarkTrialPut(int track_id, int trial_num) {
      super("landmark_trial_put");
      this.url += "&trial_num=" + trial_num;
      this.url += "&tid=" + track_id;
   }

}

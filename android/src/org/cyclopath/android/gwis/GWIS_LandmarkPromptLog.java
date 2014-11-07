/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import org.cyclopath.android.items.LandmarkNeed;

/**
 * Logs a landmark prompt.
 * @author Fernando Torre
 */
public class GWIS_LandmarkPromptLog extends GWIS {

   /**
    * Constructor
    */
   public GWIS_LandmarkPromptLog(int prompt_num, LandmarkNeed ln,
                                 int trial_num) {
      super("landmark_prompt_log");
      this.url += "&trial_num=" + trial_num;
      this.url += "&p_num=" + prompt_num;
      this.url += "&nid=" + ln.id;
   }

}

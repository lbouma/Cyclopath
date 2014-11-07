/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.TrackingService;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.items.LandmarkNeed;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.NodeList;

/**
 * Gets nearby nodes with landmark needs.
 * @author Fernando Torre
 */
public class GWIS_LandmarkNeedGet extends GWIS {

   /**
    * Constructor
    */
   public GWIS_LandmarkNeedGet(PointD coords) {
      super("landmark_need_get");
      this.url += "&x=" + coords.x;
      this.url += "&y=" + coords.y;
   }

   /**
    * Sets the global list of nearby landmark needs.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      
      LandmarkNeed.nearby_landmarks = new ArrayList<LandmarkNeed>();
      NodeList needs = rset.getElementsByTagName("need");
      NamedNodeMap atts;
      for (int i = 0; i < needs.getLength(); i++) {
         atts = needs.item(i).getAttributes();
         int need_id = XmlUtils.getInt(atts, "nid", -1);
         if (need_id >= 0) {
            PointD p = G.coordsStringToPoint(
                  XmlUtils.getString(atts, "geometry", "")).get(0);
            LandmarkNeed ln = new LandmarkNeed(need_id, p);
            LandmarkNeed.nearby_landmarks.add(ln);
         }
      }
      TrackingService.next_need_request_dist = Constants.LANDMARK_NEED_RADIUS;
   }

}

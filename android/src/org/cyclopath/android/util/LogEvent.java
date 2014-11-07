/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;

/**
 * This class represents a log event containing a hash map of key value pairs
 * with log information.
 * @author Fernando Torre
 */
public class LogEvent {

   /** string containing hierarchical categorization information, generally
    * resembling a relative path: e.g., "ui/redo" */
   public String facility;
   /** data about the event in key value pairs */
   public HashMap<String, String> params;
   /** timestamp for when the event was recorded */
   public Date timestamp;
   
   /**
    * Constructor.
    * @param facility name of event
    * @param params data of event
    */
   public LogEvent(String facility, String[][] params) {
      this.facility = facility;
      this.timestamp = new Date();
      this.params = new HashMap<String, String>();
      for (int i = 0; i < params.length; i++) {
         if (params[i].length == 2) {
            this.params.put(params[i][0], params[i][1]);
         }
      }
   }
   
   // *** Instance methods
   
   /**
    * Returns an XML version of this log event.
    * @return String containing XML data for this event
    */
   public String as_xml() {
      StringBuilder result = new StringBuilder();
      SimpleDateFormat sdf =
         new SimpleDateFormat("yyyy-MM-dd HH:mm:ssZ");
      result.append("<event facility=\"" + this.facility
                    + "\" timestamp=\"" + sdf.format(this.timestamp) + "\">");
      if (this.params != null) {
         // add in key-value pairs
         for (String key : this.params.keySet()) {
            if (this.params.get(key) == null) {
               continue;
            }
            try {
               result.append("<param key=\"" + key + "\">"
                             + URLEncoder.encode(this.params.get(key),"UTF-8")
                             + "</param>");
            } catch (UnsupportedEncodingException e) {
               e.printStackTrace();
            }
         }
      }
      result.append("</event>");
      return result.toString();
   }
}

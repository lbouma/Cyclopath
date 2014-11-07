/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.util.ArrayList;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.util.LogEvent;

import android.util.Log;

/**
 * This GWIS class handles sending log information to the server.
 * @author Fernando Torre
 */
public class GWIS_Log extends GWIS {

   private ArrayList<LogEvent> events;
   
   // *** Constructor

   /**
    * Constructs a new log request.
    */
   public GWIS_Log(ArrayList<LogEvent> events) {
      super("log");
      this.events = events;
      
      StringBuilder events_xml = new StringBuilder();

      for (LogEvent ev : events) {
         events_xml.append(ev.as_xml());
         // FIXME: debug code for bug 1656 - add asserts to URL
         // because we're sometimes losing the body
         if (ev.facility == "error/assert") {
            try {
               this.url += "&assert="
                        + URLEncoder.encode(ev.params.get("message"),"UTF-8");
            } catch (UnsupportedEncodingException e) {
               e.printStackTrace();
            }
         }
      }
      this.data = events_xml.toString();
   }

   // *** Instance methods
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_Log g = new GWIS_Log(this.events);
      g.retrying = true;
      return g;
   }

   /**
    * Overrides GWIS function so that we don't try logging an error 
    * of a failed attempt to log an error, lest we end up in a loop. 
    */
   @Override
   protected void onIOError(IOException e) {
      if (Constants.DEBUG) {
         Log.e("error","Error getting XML");
      }
      e.printStackTrace();
      // Add to retry list if one of the logs is a build info log. We don't
      // want to do this for every log because then we might have a sudden
      // surge of logs to send (e.g. when a user has been tracking GPS
      // coordinates somewhere without access to the internet).
      for (LogEvent event : events) {
         if (event.facility.equals("mobile/build_info")) {
            retry_needed.add(this.clone());
            break;
         }
      }
      this.cancelRequest();
      this.throbberRelease();
   }

   /**
    * Overrides GWIS function so that we don't try logging an error 
    * of a failed attempt to log an error, lest we end up in a loop. 
    */
   @Override
   protected void onTimeout() {
      if (Constants.DEBUG) {
         Log.d("gwis", "WARNING: GWIS_Log timeout: gwis" + id + " " + url);
      }
      cancelRequest();
   }

   /**
    * Overrides GWIS function so that we don't try logging an error 
    * of a failed attempt to log an error, lest we end up in a loop. 
    */
   @Override
   protected void errorPresent(String text) {
      // Do nothing.
   }

   /**
    * Overrides GWIS function so that we don't try logging an error 
    * of a failed attempt to log an error, lest we end up in a loop. 
    */
   @Override
   protected void errorLog(String text) {
      // Do nothing.
   }
   
   /**
    * Overrides GWIS method because we don't care what the server returns.
    */
   @Override
   protected boolean processData(String data) {
      super.processData(data);
      this.throbberRelease();
      return true;
   }

}

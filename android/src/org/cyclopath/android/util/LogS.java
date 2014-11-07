/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import java.util.ArrayList;
import java.util.Timer;
import java.util.TimerTask;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_Log;

import android.content.Context;
import android.os.Handler;
import android.os.Message;

/**
 * This class sends log events in batches to avoid sending to many server
 * requests.
 * @author Fernando Torre
 */
public class LogS {
   
   /** List of log events */
   protected ArrayList<LogEvent> events;
   /** Timer for scheduling server requests */
   protected Timer timer;
   /** context for this instance */
   protected Context context;

   /**
    * This handler receives and handles messages from the thread that
    * communicates with the server.
    */
   protected Handler mHandler = new Handler() {
      @Override
      public void handleMessage(Message msg) {
         // Let the main thread handle the results.
         send();
      }
   };
   
   /**
    * Constructor.
    */
   public LogS(Context context) {
      this.events = new ArrayList<LogEvent>();
      this.context = context;
      timer = new Timer();
   }

   // *** Instance methods

   /**
    * Log an event with the given parameters.
    * @param facility name of the event
    * @param value data for the event
    */
   public void event(String facility, String[][] value) {
      this.event(facility, value, false);
   }

   /**
    * Log an event with the given parameters.
    * @param facility name of the event
    * @param value data for the event
    * @param force_send If true, all queued events including this one will be
    * sent immediately.
    */
   public void event(String facility, String[][] value,
                     boolean force_send) {
      LogEvent ev = new LogEvent(facility, value);

      this.events.add(ev);
      if (this.events.size() >= Constants.GWIS_LOG_COUNT_THRESHOLD || force_send) {
         this.send();
      } else {
         this.timer.cancel();
         this.timer = new Timer();
         timer.schedule(new TimeoutTask(),
                        Constants.GWIS_LOG_PAUSE_THRESHOLD*1000);
      }
   }
   
   /**
    * Sends a log request to the server.
    */
   protected void send() {
      if (this.events.size() == 0)
         return; // don't send any events

      new GWIS_Log(this.events).fetch();
      this.events = new ArrayList<LogEvent>();
      this.timer.cancel();
   }
   
   // *** Private classes
   
   /**
    * Task that gets called when a timeout occurs and log events are ready to
    * be sent.
    */
   private class TimeoutTask extends TimerTask  {
      @Override
      public void run () {
         Message msg = Message.obtain();
         msg.setTarget(mHandler);
         msg.sendToTarget();
      }
    }
}

/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.net;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.Timer;
import java.util.TimerTask;

import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.StatusLine;
import org.apache.http.client.HttpClient;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.DefaultHttpClient;
import org.cyclopath.android.conf.Constants;
import org.json.JSONException;
import org.json.JSONObject;

import android.os.Handler;
import android.os.Message;
import android.util.Log;

/**
 * Handles link shortening requests using the bit.ly API
 * @author Phil Brown
 */
public class LinkShortener extends Thread {
   /** The callback that is run after the results have been processed*/
   private LinkShortenerCallback callback;
   /** The original URL to-be-shortened*/         
   private String long_URL;
   /** The shortened URL*/
   private String short_URL;
   /** When the fetch started */
   private long start_time;
   /** Timer to go off when the request times out. */
   private Timer timer;
   /** request URL */
   private String url;
   /** Tag for error logging*/
   private static final String TAG = "Link Shortnener";

   /**
    * This handler receives and handles messages from the thread that
    * communicates with the server.
    */
   protected Handler mHandler = new Handler() {
      @Override
      public void handleMessage(Message msg) {
      switch (msg.what) {
         case (Constants.BITLY_OK):
            // Let the main thread handle the results.
            handleResults(msg.obj.toString());
            break;
         default:
            //handle a bitly error
            handleError(msg.obj.toString());
            break;
         }
      }
   };//mHandler
   
   /**
    * Constructor
    * @param long_URL the URL to-be-shortened
    * @param callback the callback function to be called after the results
    * have been processed
    */
   public LinkShortener(String long_URL, LinkShortenerCallback callback) {
      this.long_URL = long_URL;
      this.callback = callback;
   }//LinkShortener
   
   /**
    * Prepares the request
    */
   public void fetch(){
      // Start timeout clock
      timer = new Timer();
      timer.schedule(new TimeoutTask(), Constants.NETWORK_TIMEOUT*1000);
      
      // Initiate request
      if (Constants.DEBUG) {
         Log.d(TAG,"fetch:" + this.toString() + " " + this.url);
      }
      this.start_time = System.currentTimeMillis();
      // FIXME: It would be cool if we had just one value in constants
      // with %s or something similar where we could fill in the login,
      // api, and long url values.
      this.url = Constants.BITLY_URL_BASE_START
                 + Constants.BITLY_LOGIN
                 + Constants.BITLY_APIKEY
                 + Constants.BITLY_URL_LONGURL + long_URL;
      this.start();
   }//fetch
   
   /**
    * Handles Bit.ly errors by canceling the TimerTask, interrupting the I/O
    * stream, and continuing the route share process using the original,
    * unshortened URL.
    * @param error_message The reason for the error
    */
   private void handleError(String error_message) {
      timer.cancel();
      interrupt();
      if (Constants.DEBUG) {
         Log.d(TAG,"fetch failed:" + this.toString() + " " + this.url);
      }
      this.callback.handleLinkShortenerComplete(long_URL);
   }//handleError
   
   /**
    * This method is called when a server request completes and a JSON response
    * needs to be processed.
    * @param json response from the server
    */
   public void handleResults(String json) {
      if (Constants.DEBUG) {
         Log.d(TAG, "URL shortener complete:"
                        + this.toString() + "/" + this.url);
         Log.d(TAG, "^^^ duration:"
               + (System.currentTimeMillis() - this.start_time) + "ms");
         Log.d(TAG, "JSON response: " + json);
      }
      try {
         JSONObject results = new JSONObject(json);
         JSONObject data = new JSONObject(results.getString("data"));
         this.short_URL = (String) data.get("url");
         if (Constants.DEBUG) {
            Log.i(TAG, "data: " + short_URL);
         }
      } catch (JSONException e) {
         if (Constants.DEBUG) {
            Log.i(TAG, "Json Error");
            e.printStackTrace();
         }
      }
      this.callback.handleLinkShortenerComplete(short_URL);
   }//handleResults
   
   /**
    * Make the URL request in a separate thread
    */
   @Override
   public void run(){
      StringBuilder builder = new StringBuilder();
      if (Constants.DEBUG) {
         Log.d(TAG,"data: " + builder.toString());
      }
      HttpClient client = new DefaultHttpClient();
      HttpGet httpGet = new HttpGet(this.url);
      try {
         HttpResponse response = client.execute(httpGet);
         StatusLine statusLine = response.getStatusLine();
         int statusCode = statusLine.getStatusCode();
         String reason = statusLine.getReasonPhrase();
         if (statusCode == 200) {
            HttpEntity entity = response.getEntity();
            InputStream content = entity.getContent();
            BufferedReader reader = 
                            new BufferedReader(new InputStreamReader(content));
            String line;
            while ((line = reader.readLine()) != null) {
               builder.append(line);
            }
            Message msg = Message.obtain();
            msg.what = Constants.BITLY_OK;
            msg.obj = builder.toString();
            msg.setTarget(this.mHandler);
            if (!this.isInterrupted()) {
               msg.sendToTarget();
            }
         } else {
            Message msg = Message.obtain();
            msg.what = Constants.BITLY_ERROR;
            msg.obj = reason;
            msg.setTarget(this.mHandler);
            msg.sendToTarget();
         }
      } catch (Exception e) {
         Message msg = Message.obtain();
         msg.what = Constants.BITLY_ERROR;
         msg.obj = e;
         msg.setTarget(this.mHandler);
         msg.sendToTarget();
      }
      this.timer.cancel();
   }//run

   /**
    * Task that gets called when a timeout occurs
    */
   private class TimeoutTask extends TimerTask  {
      @Override
      public void run () {
         Message msg = Message.obtain();
         msg.what = Constants.HANDLE_TIMEOUT;
         msg.setTarget(mHandler);
         msg.sendToTarget();
      }
   }//TimeoutTaks
   
}//LinkShortener

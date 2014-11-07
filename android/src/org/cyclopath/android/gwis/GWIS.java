/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.io.StringReader;
import java.lang.ref.WeakReference;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLDecoder;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.Timer;
import java.util.TimerTask;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Conf;
import org.cyclopath.android.conf.Constants;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;

import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.util.SparseArray;

/**
 * This class contains the GWIS interface code. This class is originally based
 * on flashclient/GWIS.as.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class GWIS extends Thread
                  implements GWIS_ValueMapGetCallback {

   // *** Instance variables

   /** request URL */
   protected String url;
   /** request command */
   protected String request;

   /** When the fetch started */
   protected long start_time;

   /** The set of requests which failed but should be retried. */
   protected static LinkedHashSet<GWIS> retry_needed =
      new LinkedHashSet<GWIS>();

   /** True if we've griped about server maintenance since the last fetch().
    * This is here to avoid a flurry of stacked gripe windows, as requests
    * often are made in groups.
    */
   protected static boolean maint_griped;

   /** Similar for griping about authfailban problems. Public so that
    * Delayed_Setter can access it. FIXME: No Delayed Setter
    */
   public static boolean authfailban_griped;

   /** This is a counter to give each request a unique ID. */
   protected static int id_next = 1;

   /** If true, the throbber should run while this request is outstanding. */
   protected boolean throb;

   /** Timer to go off when the request times out. */
   protected Timer timer;

   /** Each request has its own id (used by developers to debug). */
   protected int id;

   /** Each request has its own XML payload. */
   protected String data;
   
   /** whether this request is being retried */
   public boolean retrying = false;
   
   /** Title to show in progress bar */
   private String popup_title;
   /** Message to show in progress bar */
   private String popup_msg;
   
   /** Filters to use in query */
   public QueryFilters query_filters;
   
   /**
    * This handler receives and handles messages from the thread that
    * communicates with the server.
    */
   protected static SparseArray<GWISHandler> handlers =
         new SparseArray<GWISHandler>();
   
   /**
    * A handler for this class that uses weak references to avoid memory
    * leaks.
    * @author Fernando
    *
    */
   protected static class GWISHandler extends Handler {
      
      /** Reference to GWIS class */
      private WeakReference<GWIS> ref;

      /**
       * Constructor
       * @param gwis
       */
      public GWISHandler(GWIS gwis) {
         this.ref = new WeakReference<GWIS>(gwis);
      }

      /**
       * Forwards the message to the GWIS class.
       */
      @Override
      public void handleMessage(Message msg) {
         GWIS gwis = this.ref.get();
         if (gwis != null) {
            gwis.handleMessage(msg);
         }
      }
   }

   

   // *** Constructors
   
   /**
    * Simple GWIS constructor called by subclasses.
    */
   public GWIS(String request) {
      this(request, "", true, null);
   }

   /**
    * Constructor for GWIS request without popup.
    * @param request type of request
    * @param data xml data, if any
    * @param throb whether the throbber should run
    * @param query_filters filters for this request
    */
   public GWIS(String request, String data, boolean throb,
               QueryFilters query_filters) {
      this(request, data, throb, query_filters, "", "");
   }
   
   /**
    * Constructor for GWIS request with popup.
    * @param request type of request
    * @param data xml data, if any
    * @param throb whether the throbber should run
    * @param query_filters filters for this request
    * @param popup_title title of popup
    * @param popup_msg message of popup
    */
   public GWIS(String request, String data, boolean throb,
               QueryFilters query_filters,
               String popup_title,
               String popup_msg) {
      this.url = this.urlBase(request);
      this.request = request;
      this.data = data;
      this.throb = throb;
      this.id = id_next++;
      if (query_filters == null) {
         this.query_filters = new QueryFilters();
      } else {
         this.query_filters = query_filters;
      }
      this.popup_title = popup_title;
      this.popup_msg = popup_msg;
      GWIS.handlers.put(this.id, new GWISHandler(this));
   }

   // *** Static methods

   /**
    * Retries all GWIS calls that need to be retried.
    */
   public static void retryAll() {
      Iterator<GWIS> i = retry_needed.iterator();
      while (i.hasNext()) {
         i.next().fetch();
      }
      retry_needed = new LinkedHashSet<GWIS>();
   }

   // *** Other Methods
   
   /**
    *  Cancels the request.
    */
   public void cancelRequest() {
      this.timer.cancel();
      this.throbberRelease();
      this.interrupt();
      this.onErrorCleanup();
   }
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS g = new GWIS("", this.data, this.throb, this.query_filters,
                        this.popup_title, this.popup_msg);
      g.url = this.url;
      g.retrying = true;
      return g;
   }

   /**
    * Logs the error.
    */
   protected void errorLog(String text) {
      G.server_log.event("mobile/error/gwis/server",
            new String[][]{{"url", this.url}, {"msg", text}});
   }
   
   /**
    * Shows error to user.
    * @param text error text
    */
   protected void errorPresent(String text) {
      G.showAlert(text
                 + G.app_context.getString(R.string.gwis_error_present)
                 + this.url,
                 G.app_context.getString(R.string.error));
   }

   /**
    *  Begins the HTTP fetch. When the operation completes, the callback
    * method in a subclass calls the map object to add the new data.
    */
   public void fetch() {
      
      if (!G.isConnected()) {
         if (!this.retrying) {
            G.showToast(G.app_context.getResources().getString(
                  R.string.network_error_toast));
         }
         return;
      }

      if (!Conf.config_fetched
            && !GWIS_ValueMapGet.class.isInstance(this)
            && !GWIS_Log.class.isInstance(this)) {
         new GWIS_ValueMapGet(this).fetch();
         boolean add_retry = true;
         for (GWIS g : retry_needed) {
            if (g.id == this.id) {
               add_retry = false;
               break;
            }
         }
         if (add_retry) {
            retry_needed.add(this.clone());
         }
         return;
      }
      
      if (!this.retrying && !this.popup_msg.equals("")) {
         G.showProgressDialog(this.popup_title, this.popup_msg);
      }
      
      GWIS.maint_griped = false;
      this.finalize_request();

      // Start timeout clock
      timer = new Timer();
      timer.schedule(new TimeoutTask(this.id), Constants.NETWORK_TIMEOUT);

      // Initiate request
      if (Constants.DEBUG) {
         Log.d("gwis","GWIS fetch:" + this.toString() + " " + this.url);
      }
      this.start_time = System.currentTimeMillis();
      this.start();
      this.throbberAttach();
   }

   /**
    *  Finalizes the GWIS request's data XML and url.
    */
   protected void finalize_request() {
      if (this.data != null) {
         this.data = "<data><metadata>"
            + this.getCredentialsXML()
            + "<device is_mobile=\"True\" />"
            + "</metadata>"
            + this.query_filters.getFiltersXML()
            + this.data
            + "</data>";
      }
      
      this.url = this.query_filters.url_append_filters(this.url);

      if (G.browid != null) {
         this.url += "&browid=" + G.browid;
      }
      this.url += "&sessid=" + G.sessid;
      this.url += "&android=true";
   }
   
   /**
    * Prepare metadata containing user credentials.
    * @return XML string with user credentials
    */
   protected String getCredentialsXML() {
      if (G.user.isLoggedIn()) {
         return "<user name=\"" + G.user.getName()
            + "\" token=\"" + G.user.getToken() + "\" />";
      } else {
         return "";
      }
   }

   /**
    * Returns the url for this request.
    * @return url string
    */
   public String getUrl() {
      return this.url;
   }

   /**
    * Actually perform the fetch once we have the config loaded.
    */
   @Override
   public void handleGWIS_ValueMapGetCallback() {
      this.fetch();
   }

   /**
    * Handles thread messages
    * @param msg
    */
   public void handleMessage(Message msg) {
       switch (msg.what) {
          case (Constants.GWIS_HANDLE_LOAD):
             // Let the main thread handle the results.
             handleResults(msg.obj.toString());
             break;
          case (Constants.GWIS_ERROR):
             // Display Alert to user. Cannot be done from non-UI thread.
             G.showAlert(msg.obj.toString(),
                    G.app_context.getResources().getString(R.string.error));
             break;
          case (Constants.GWIS_HANDLE_TIMEOUT):
             onTimeout();
             break;
          case (Constants.GWIS_IO_ERROR):
             onIOError((IOException) msg.obj);
             break;
       }
       GWIS.handlers.remove(this.id);
   }

   /**
    * This method is called when a server request completes and an XML response
    * needs to be processed.
    * @param xml response from the server
    */
   public void handleResults(String xml) {
      if (Constants.DEBUG) {
         Log.d("gwis","GWIS complete:" + this.toString() + "/" + this.url);
         Log.d("gwis","^^^ duration:"
               + (System.currentTimeMillis() - this.start_time) + "ms");
      }
      this.processData(xml);
   }
   
   /**
    *  Cleanup after IO errors
    */
   protected void onErrorCleanup() {
      if (!this.popup_msg.equals("")) {
         G.dismissProgressDialog();
      }
   }
   
   /**
    * Handles IO error
    * @param e IO exception
    */
   protected void onIOError(IOException e) {
      if (Constants.DEBUG) {
         Log.e("error","Error getting XML");
      }
      if (!this.retrying) {
         G.showToast(G.app_context.getResources().getString(
               R.string.network_error_toast));
      }
      e.printStackTrace();
      this.cancelRequest();
      G.server_log.event("mobile/error/gwis/io",
                 new String[][]{{"url", this.url}, {"msg", e.getMessage()}});
      this.throbberRelease();
   }
   
   /**
    * Handles server request timeouts.
    */
   protected void onTimeout() {
      if (Constants.DEBUG) {
         Log.d("gwis", "WARNING: GWIS timeout: gwis" + id + " " + url);
      }
      cancelRequest();
      // Tell the user
      G.showToast(G.app_context.getResources().getString(
            R.string.gwis_timeout_title));
      G.server_log.event("mobile/error/gwis/timeout",
                  new String[][]{{"url", this.url}});
   }

   /**
    * Processes the data received from the server. Specifically, it handles the
    * cases when something went wrong.
    * @param data Data received from server.
    * @return True if there were no problems, false otherwise.
    */
   protected boolean processData(String data) {
      boolean processed_data = false;
      if (Constants.DEBUG) {
         Log.d("gwis", "received data: " + data);
      }
      // FIXME: Hack to handle carriage returns in notes. I [ft] am not sure
      // what would be the best way to handle this.
      data = data.replace("&#13;", "%0A");
      DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
      DocumentBuilder builder;
      try {
         builder = factory.newDocumentBuilder();
         Document dom = builder.parse(new InputSource(new StringReader(data)));
         Element root = dom.getDocumentElement();
         String name = root.getNodeName();
         Node n = root.getFirstChild();
         if (name.equals("data")) {
            // Good results. Process it.
            
            // check android_version
            String android_version = root.getAttribute("gwis_version").trim();
            if (!android_version.equals("")) {
               SharedPreferences.Editor user_settings_editor =
                  G.cookie_anon.edit();
               user_settings_editor.putString(Constants.LATEST_VERSION,
                                              android_version);
               user_settings_editor.commit();
            }
            if(G.checkForMandatoryUpdate()) {
               return false;
            }
            this.processResultset(dom);
            this.throbberRelease();
            processed_data = true;
         } else if (name.equals("gwis_error")) {
            // Report error
            String message = "";
            if (root.hasAttribute("msg")) {
               message = root.getAttribute("msg");
            }
            errorLog(URLDecoder.decode(message,"UTF-8"));
            this.onErrorCleanup();
            errorPresent(URLDecoder.decode(message,"UTF-8"));
         } else if (!(this instanceof GWIS_Log)){
            // Something went wrong.
            this.throbberRelease();
            String message = "";
            if (root.hasAttribute("msg")) {
               message = root.getAttribute("msg");
            } else if (n != null){
               message = n.getNodeValue();
            }
            if (name.equals("gwis_error")) {
               String tag = root.getAttribute("tag");
               if (tag.equals("badtoken")) {
                  // Bad token -- reauthenticate and try again.
                  if (!(G.user.reauthenticating)) {
                     G.user.reauthenticate();
                  }
                  retry_needed.add(this.clone());
               } else if (tag.equals("maint")) {
                  // Server is in maintenance mode.
                  if (!GWIS.maint_griped) {
                     GWIS.maint_griped = true;
                     G.showAlert(G.app_context.getResources().getString(
                                             R.string.gwis_server_maintenance),
                                 G.app_context.getResources().getString(
                                             R.string.error));
                  }
               } else if (tag.equals("authfailban")) {
                  // IP is banned due to excessive auth failures - pass
                  // through the server's error message
                  if (!authfailban_griped
                      || (this.getClass().getName().equals(
                                                GWIS_Hello.class.getName()))) {
                     authfailban_griped = true;
                     // FIXME:
                     //Delayed_Setter.set(GWIS, 'authfailban_griped', false, 10);
                     G.showAlert(message,
                                 G.app_context.getResources().getString(
                                       R.string.error));
                  }
               } else {
                  // Report error
                  errorLog(URLDecoder.decode(message,"UTF-8"));
                  this.onErrorCleanup();
                  errorPresent(URLDecoder.decode(message,"UTF-8"));
               }
            }
            else {
               // Who knows
               if (root.hasAttribute("msg")) {
                  errorLog("Bad response: " + root.getAttribute("msg"));
               } else {
                  errorLog("Bad response: " + data);
               }
               this.onErrorCleanup();
               errorPresent(G.app_context.getResources().getString(
                                                    R.string.gwis_bad_response)
                            + data);
            }
         }
      } catch (SAXException e) {
         e.printStackTrace();
      } catch (IOException e) {
         e.printStackTrace();
      } catch (ParserConfigurationException e) {
         e.printStackTrace();
      }
      return processed_data;
   }
   
   /**
    * Keeps track of most current revision id.
    * @param maxrid_new New revision id.
    */
   protected void processMaxrid(int maxrid_new) {
      if (maxrid_new > G.max_rid) {
         G.max_rid = maxrid_new;
      }
   }

   /**
    *  Processes the incoming result set.
    * @param rset document representing the results
    */
   protected void processResultset(Document rset) {
      String str;
   
      String pu_u = "";
      String fl_u = "";
      String pu_i = "";
      String fl_i = "";
      

      if (!this.popup_msg.equals("")) {
         G.dismissProgressDialog();
      }

      Element root = rset.getDocumentElement();
      
      // Update max RID, which is the latest revision ID of the branch head.
      String max_rid = root.getAttribute("rid_max").trim();
      if (max_rid.length() > 0)
         this.processMaxrid(Integer.parseInt(max_rid));
   
      // check semi-protected
      String semi = root.getAttribute("semiprotect").trim();
      int semi_protected = 0;
      if (semi.length() > 0) {
         semi_protected = Integer.parseInt(semi);
      }
      if (semi_protected != 0 && !G.semiprotect_griped) {
         G.semiprotect_griped = true;
         int note_part_a = R.string.gwis_semi_protection_part_a;
         int note_part_b = R.string.gwis_semi_protection_part_b;
         int alert_title = R.string.gwis_semi_protection;
         G.showAlert(G.app_context.getResources().getString(note_part_a)
                     + semi_protected
                     + G.app_context.getResources().getString(note_part_b),
                     G.app_context.getResources().getString(alert_title));
      }

      // check for banned state of user/ip
      NodeList bans = root.getElementsByTagName("bans");
      if (bans.getLength() > 0) {
         Node b = bans.item(0);
         str = b.getAttributes().getNamedItem("public_user").getNodeValue();
         if (str.length() > 0) {
            pu_u = str;
         }
         str = b.getAttributes().getNamedItem("full_user").getNodeValue();
         if (str.length() > 0) {
            fl_u = str;
         }
         str = b.getAttributes().getNamedItem("public_ip").getNodeValue();
         if (str.length() > 0) {
            pu_i = str;
         }
         str = b.getAttributes().getNamedItem("full_ip").getNodeValue();
         if (str.length() > 0) {
            fl_i = str;
         }
         G.user.gripeBanMaybe(pu_u, fl_u, pu_i, fl_i);
      }
   }

   /**
    * Starts the thread that handles server communication.
    */
   @Override
   public void run() {
      try {
         URL u = new URL(this.url);
         HttpURLConnection connection =
            (HttpURLConnection) u.openConnection();
         connection.setDoInput(true);
         connection.setDoOutput(true);
         if (Constants.DEBUG) {
            Log.d("gwis","data: " + this.data);
         }
         if (this.data != null && !this.data.equals("")) {
            connection.setRequestProperty("Content-Type","text/xml");
            PrintWriter pw = new PrintWriter(connection.getOutputStream());
            pw.write(this.data);
            pw.close();
         }
         connection.connect();
         InputStream input = connection.getInputStream();
         StringBuffer result = new StringBuffer();
         BufferedReader reader =
            new BufferedReader(new InputStreamReader(input));
         String line;
         while ((line = reader.readLine()) != null) {
             result.append(line);
         }
         connection.disconnect();
         
         // Send message to the main thread so that the main thread can take
         // care of handling the results.
         Message msg = Message.obtain();
         msg.what = Constants.GWIS_HANDLE_LOAD;
         msg.obj = result.toString();
         msg.setTarget(GWIS.handlers.get(this.id));
         if (!this.isInterrupted()) {
            msg.sendToTarget();
         }
      } catch (IOException e) {
         Message msg = Message.obtain();
         msg.what = Constants.GWIS_IO_ERROR;
         msg.obj = e;
         msg.setTarget(GWIS.handlers.get(this.id));
         if (msg.getTarget() != null) {
            msg.sendToTarget();
         }
      }
      this.timer.cancel();
   }
   
   /**
    * Show an alert with no title.
    * @param txt alert message
    */
   public void showAlert(String txt) {
      G.showAlert(txt, "");
   }

   /**
    *  Registers an outstanding HTTP request with the throbber. The throbber 
    * runs so long as one or more requests are being processed. Note that 
    * some requests occur 'silently', i.e., they don't cause the throbber 
    * to throb.
    */
   public void throbberAttach() {
      if (this.throb) {
         G.incrementThrobber();
      }
   }

   /**
    *  De-registers with the throbber, either because the HTTP was completed, 
    * or because the request timed-out or failed due to another error.
    */
   public void throbberRelease() {
      if (this.throb) {
         G.decrementThrobber();
         this.throb = false;
      }
   }

   /**
    * Returns a string version of this gwis request.
    */
   @Override
   public String toString() {
      return ("gwis" + this.id); // + ' ' + this.req.url);
   }

   /**
    * Construct a complete url based on a request.
    * @param request
    * @return a string representation of the url
    */
   protected String urlBase(String request)
   {
      return (Constants.SERVER_URL + Constants.GWIS_URL
              + "rqst=" + request);
   }
   
   // *** Private classes
   
   /**
    * Task that gets called when a timeout occurs
    */
   private class TimeoutTask extends TimerTask  {
      private int gwis_id;
      
      public TimeoutTask(int gwis_id) {
         this.gwis_id = gwis_id;
      }
      
      @Override
      public void run () {
         Message msg = Message.obtain();
         msg.what = Constants.GWIS_HANDLE_TIMEOUT;
         msg.setTarget(GWIS.handlers.get(this.gwis_id));
         if (msg.getTarget() != null) {
            msg.sendToTarget();
         }
      }
    }

}

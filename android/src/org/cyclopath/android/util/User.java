/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import java.util.UUID;

import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.FactoryConfigurationError;
import javax.xml.parsers.ParserConfigurationException;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_UserPreferencePut;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Message;

/**
 * Class that represents a Cyclopath user.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class User {

   /** username for logged in user. */
   private String username;
   /** Token used for authentication once the user is logged in. */
   private String token;
   /** Whether the user is logged in */
   private boolean logged_in;
   
   /** Route-finding priority */
   public float rf_priority = Constants.RF_PRIORITY_DEFAULT;
   /** Previous route-finding priority */
   public float rf_priority_old;
   
   /** Flag to say whether or not user login information should be saved. */
   public boolean rememberme;
   
   /** This is set to true if the server has informed us that previously
    * valid credentials are no longer valid. */
   public boolean reauthenticating = false;
   
   // Strings storing the expiration date of the different types of bans
   // If null, then there is no ban for that type.
   /** expiration date for public user ban */
   public String public_user_ban = null;
   /** expiration date for full user ban */
   public String full_user_ban = null;
   /** expiration date for public ip ban */
   public String public_ip_ban = null;
   /** expiration date for full ip ban */
   public String full_ip_ban = null;
   
   // *** Constructors
   
   /**
    * Default constructor
    */
   public User() {
      this.username = "";
   }
   
   /**
    * Constructor
    * @param name username
    */
   public User(String name) {
      this.username = name;
   }
   
   // *** Getters and Setters
   
   /**
    * Sets the username.
    * @param name username
    */
   public void setName(String name) {
      this.username = name;
   }
   
   /**
    * Gets the username.
    * @return username
    */
   public String getName() {
      if (this.username == null) {
         return "";
      }
      return this.username;
   }
   
   /**
    * Sets the user's token for authentication.
    * @param token token string
    */
   public void setToken(String token) {
      this.token = token;
   }
   
   /**
    * Gets the user's token.
    * @return token string
    */
   public String getToken() {
      return this.token;
   }
   
   /**
    * Sets whether the user is logged in or not.
    * @param logged
    */
   public void setLoggedIn(boolean logged) {
      this.logged_in = logged;
   }
   
   // *** Other methods
   
   /**
    *  Completes the login process.
    * @param username
    * @param token
    * @param preferences document node containing user preferences stored on the
    * server
    * @param rememberme whether the user's login information should be
    * remembered
    */
   public void finishLogin(String username,
                           String token,
                           Node preferences,
                           boolean rememberme) {
   
      this.username = username;
      this.token = token;
      this.logged_in = true;
      String priority = "";
      
      SharedPreferences.Editor editor = G.cookie.edit();
   
      // FIXME: bug 2067
      /*viz_index = Integer.parseInt((preferences
                                    .getAttributes()
                                    .getNamedItem("route_viz")
                                    .getNodeValue()).trim()) - 1;
      
      // Old cookies may be missing route_viz - so only try to
      // look up in the table if viz_index smells good. Also, we assign
      // directly to the real variable (bypassing the setter) because this
      // shouldn't generate a PutPreference request.
      if (viz_index >= 0)
         this._route_viz = Conf.route_vizs[viz_index];*/
      
      Node priority_node =
         preferences.getAttributes()
                    .getNamedItem(Constants.PREFERENCE_RF_PRIORITY);
      if (priority_node != null) {
         priority = priority_node.getNodeValue();
      }
   
      if (priority.length() > 0) {
         this.rf_priority = Float.parseFloat(priority);
      } else {
         this.rf_priority = Constants.RF_PRIORITY_DEFAULT;
      }
   
      //if (!this.reauthenticating) {
         // FIXME: bug 2073: needed once we let users make edits or see
         // private objects.
         //G.map.discardAndUpdate(true);
      //}
   
      this.reauthenticating = false;
      this.rememberme = rememberme;
      if (rememberme) {
         editor.putString(Constants.COOKIE_USERNAME, this.username);
         // FIXME: bug 2067
         //editor.putInt("route_viz", this.route_viz.id_);
         editor.putFloat(Constants.COOKIE_RF_PRIORITY,
                         (float) this.rf_priority);
         editor.putString(Constants.COOKIE_TOKEN, this.token);
      } else {
         editor.clear();
      }
      // Commit the edits!
      editor.commit();
   }

   /**
    * Shows ban warning to user.
    * @param public_user
    * @param full_user
    * @param public_ip
    * @param full_ip
    */
   public void gripeBanMaybe(String public_user,
                               String full_user,
                               String public_ip,
                               String full_ip) {
   
      // 0 = no change, 1 = new ban, -1 = ban removed
      int pu_user_sw = 0;
      int fl_user_sw = 0;
      int pu_ip_sw = 0;
      int fl_ip_sw = 0;
   
      String topic = "";
      String bans = "";
      String gone = "";
   
      // TODO: Is the String value null or empty?
      if (this.public_user_ban != null && public_user == null)
         pu_user_sw = -1;
      else if (this.public_user_ban != public_user)
         pu_user_sw = 1;
            
      if (this.full_user_ban != null && full_user == null)
         fl_user_sw = -1;
      else if (this.full_user_ban != full_user)
         fl_user_sw = 1;
      
      if (this.public_ip_ban != null && public_ip == null)
         pu_ip_sw = -1;
      else if (this.public_ip_ban != public_ip)
         pu_ip_sw = 1;
      
      if (this.full_ip_ban != null && full_ip == null)
         fl_ip_sw = -1;
      else if (this.full_ip_ban != full_ip)
         fl_ip_sw = 1;
   
      if (pu_user_sw != 0 || fl_user_sw != 0 || pu_ip_sw != 0 
          || fl_ip_sw != 0) {
         // the ban state of this user has changed, so create gripe msg
         if (pu_user_sw == 1 || fl_user_sw == 1)
            topic += G.app_context.getString(R.string.account_hold);
         if (pu_ip_sw == 1 || fl_ip_sw == 1)
            topic += G.app_context.getString(R.string.device_hold);
   
         if (pu_user_sw == -1 || fl_user_sw == -1)
            topic += G.app_context.getString(R.string.account_hold_removed);
         if (pu_ip_sw == -1 || fl_ip_sw == -1)
            topic += G.app_context.getString(R.string.device_hold_removed);
   
         if (pu_user_sw == 1) {
            bans += String.format(
                        G.app_context.getString(
                              R.string.public_account_hold_expires),
                        public_user);
            this.public_user_ban = public_user;
         } else if (pu_user_sw == -1) {
            gone += String.format(
                  G.app_context.getString(
                        R.string.public_account_hold_expired),
                  this.public_user_ban);
            this.public_user_ban = null;
         }
   
         if (fl_user_sw == 1) {
            bans += String.format(
                        G.app_context.getString(
                              R.string.full_account_hold_expires),
                        full_user);
            this.full_user_ban = full_user;
         } else if (fl_user_sw == -1) {
            gone += String.format(
                  G.app_context.getString(R.string.full_account_hold_expired),
                  this.full_user_ban);
            this.full_user_ban = null;
         }
   
         if (pu_ip_sw == 1) {
            bans += String.format(
                        G.app_context.getString(
                              R.string.public_device_hold_expires),
                        public_ip);
            this.public_ip_ban = public_ip;
         } else if (pu_ip_sw == -1) {
            gone += String.format(
                        G.app_context.getString(
                              R.string.public_device_hold_expired),
                        this.public_ip_ban);
            this.public_ip_ban = null;
         }
   
         if (fl_ip_sw == 1) {
            bans += String.format(
                        G.app_context.getString(
                              R.string.full_device_hold_expires),
                        full_ip);
            this.full_ip_ban = full_ip;
         } else if (fl_ip_sw == -1) {
            gone += String.format(
                        G.app_context.getString(
                              R.string.full_device_hold_expired),
                        this.full_ip_ban);
            this.full_ip_ban = null;
         }
   
         // Actually show the pop-up
         G.showBanWarning(topic, bans, gone);
      }
   }

   /**
    * Checks whether the current user or device has any bans.
    */
   public boolean isBanned() {
      return (this.public_user_ban != null
              || this.public_ip_ban != null
              || this.isFullBanned());
   }

   /**
    * Checks whether the current user or device is fully banned.
    */
   public boolean isFullBanned() {
      return (this.full_user_ban != null || this.full_ip_ban != null);
   }

   /**
    * Checks whether the user is logged in or not.
    * @return True if the user is logged in, false otherwise.
    */
   public boolean isLoggedIn() {
      return this.logged_in;
   }
   
   /**
    * Checks whether the current user login information is being remembered.
    */
   public boolean isRememberingme() {
      return G.cookie.contains(Constants.COOKIE_USERNAME);
   }

   // FIXME: bug 2067
   /*public function set route_viz(v:Route_Viz) :void
   {
      var route_id:int
         = (Route.route_active === null) ? -1 : Route.route_active.id_;
      this._route_viz = v;
      if (this.logged_in)
         this.route_viz_update();
   
      if (Route.route_active !== null)
         (Route.route_active.detail_panel as Route_Details_Panel)
            .viz_selector.refresh()
   
      G.sl.event('exp/route_viz/set', {route: route_id, viz: v.id_});
   }*/
   
   // FIXME: bug 2067
   /*public function get route_viz() :Route_Viz
   {
      return this._route_viz;
   }*/
   
   /**
    * Logs the user out, clearing the login cookie for that user.
    */
   public void logout() {
      this.reauthenticating = false;
      this.logged_in = false;
      this.username = null;
      this.token = null;
      this.rememberme = false;
   
      this.public_user_ban = null;
      this.full_user_ban = null;
      this.public_ip_ban = null;
      this.full_ip_ban = null;
   
      SharedPreferences.Editor editor = G.cookie.edit();
      editor.clear().commit();
      // FIXME: bug 2073: needed once we let users make edits or see
      // private objects.
      //G.map.discardAndUpdate(true);
      this.rf_priority = G.cookie_anon.getFloat(Constants.COOKIE_RF_PRIORITY,
                                                Constants.RF_PRIORITY_DEFAULT);
      // FIXME: bug 2067
      //this.route_viz = Route_Viz.random();
   }

   // FIXME: bug 2067
   /*public function set route_viz(v:Route_Viz) :void
   {
      var route_id:int
         = (Route.route_active === null) ? -1 : Route.route_active.id_;
      this._route_viz = v;
      if (this.logged_in)
         this.route_viz_update();
   
      if (Route.route_active !== null)
         (Route.route_active.detail_panel as Route_Details_Panel)
            .viz_selector.refresh()
   
      G.sl.event('exp/route_viz/set', {route: route_id, viz: v.id_});
   }*/
   
   // FIXME: bug 2067
   /*public function get route_viz() :Route_Viz
   {
      return this._route_viz;
   }*/
   
   /**
    * Opens the login window to allow the user to re-authenticate.
    */
   public void reauthenticate() {
      if (G.base_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.BASE_REAUTHENTICATE;
         msg.setTarget(G.base_handler);
         msg.sendToTarget();
      }
   }

   /**
    * Backs up all route finding preferences.
    */
   public void rfPrefsBackup() {
      this.rf_priority_old = this.rf_priority;
      
      // FIXME: bug 2125
      /*var t:Tag;
      for each (t in G.map.tags_geo([G.map.BYWAYS]))
         t.user_pref_backup();*/
   }
   
   /**
    * Sets route finding preferences to defaults.
    */
   public void rfPrefsDefault() {
      this.rf_priority = Constants.RF_PRIORITY_DEFAULT;
      
      // FIXME: bug 2125
      /*var t:Tag;
      for each (t in G.map.tags_geo([G.map.BYWAYS]))
         t.user_pref_default();*/
   }
   
   /**
    *  Restores all route finding preferences.
    */
   public void rfPrefsRestore() {
      this.rf_priority = this.rf_priority_old;
      
      // FIXME: bug 2125
      /*var t:Tag;
      for each (t in G.map.tags_geo([G.map.BYWAYS]))
         t.user_pref_restore();*/
   }
   
   /**
    *  Saves route finding preferences via cookies/WFS (if needed)
    * @param context
    */
   public void rfPrefsSave(Context context) {
      SharedPreferences.Editor editor;
      
      if (!this.logged_in) {
         editor = G.cookie_anon.edit();
         editor.putFloat(Constants.COOKIE_RF_PRIORITY,
                         (float) this.rf_priority);
      } else {
         editor = G.cookie.edit();
         if (this.rememberme) {
            editor.putFloat(Constants.COOKIE_RF_PRIORITY,
                            (float) this.rf_priority);
         }
         String prefs = this.rfPrefsXml(true);
         if (!prefs.equals("<preferences />")) {
            new GWIS_UserPreferencePut(prefs).fetch();
         }
      }
      editor.commit();
   }
   
   /**
    * Returns an XML string with all of the user's preferences.
    * @return
    */
   public String rfPrefsXml() {
      return rfPrefsXml(false);
   }


   /**
    *  Returns routefinding preferences as XML.
    *  returned.
    * @param changes_only If set to true, only the preferences that have changed
    *                     since the last pref save are returned
    */
   public String rfPrefsXml(boolean changes_only) {
      
      StringBuilder prefs = new StringBuilder("<preferences");
      
      if (!changes_only || this.rfPriorityDirty()) {
         prefs.append(" rf_priority=\"")
              .append(this.rf_priority)
              .append("\"");
      }
      
      prefs.append(" />");

      // FIXME: bug 2125
      /*var prefs:XML = <preferences/>
      var t:Tag;
      var k:String;

      if (!changes_only || this.rf_priority_dirty)
         prefs.@rf_priority = this.rf_priority;

      // If tags are not yet loaded for some reason (such as when Deep
      // Linking), tell server to use defaults
      if (!changes_only && (G.map.tags === null || G.map.tags_geo([G.map.BYWAYS]).length == 0))
         prefs.@use_defaults = 'true';

      for each (t in G.map.tags_geo([G.map.BYWAYS])) {
         if ((!changes_only && t.pref_enabled && t.preference > 0)
             || (changes_only && t.user_pref_dirty)) {

            // Preference
            k = Conf.rf_tag_pref_codes[t.preference];
            if (prefs.@[k].length() > 0)
               prefs.@[k] += ',';
            prefs.@[k] += t.id_;

            // Enable state
            if (changes_only) {
               k = t.pref_enabled ? 'enabled' : 'disabled';
               if (prefs.@[k].length() > 0)
                  prefs.@[k] += ',';
               prefs.@[k] += t.id_;
            }
         }
      }*/
      return prefs.toString();
   }

   /**
    * Checks whether there is a new route finding priority being used.
    */
   public boolean rfPriorityDirty() {
      return this.rf_priority != this.rf_priority_old;
   }

   /**
    * Initialize the user using 'cookie' information, if any.
    */
   public void startup() {
      String username = G.cookie.getString(Constants.COOKIE_USERNAME, null);
      String token = G.cookie.getString(Constants.COOKIE_TOKEN, null);
      Element prefs = null;
   
      // Create an anonymous tracking cookie if one does not already exist;
      // this cookie should not ever be cleared.
      if (G.cookie_anon.getString(Constants.COOKIE_BROWID, null) == null) {
         SharedPreferences.Editor editor = G.cookie_anon.edit();
         editor.putString(Constants.COOKIE_BROWID,
                          UUID.randomUUID().toString());
         editor.commit();
      }
      G.browid =
         UUID.fromString(G.cookie_anon.getString(Constants.COOKIE_BROWID, ""));
   
      if (username != null && token != null) {
         // found a cookie; use those creds
         try {
            Document doc = DocumentBuilderFactory.newInstance()
                                                 .newDocumentBuilder()
                                                 .newDocument();
            prefs = doc.createElement("prefs");
            // FIXME: bug 2067
            //prefs.setAttribute("route_viz",
            //      Integer.toString(G.cookie.getInt("route_viz", -1)));
            prefs.setAttribute(Constants.PREFERENCE_RF_PRIORITY,
                 Float.toString(G.cookie.getFloat(Constants.COOKIE_RF_PRIORITY,
                                 (float) this.rf_priority)));
            this.finishLogin(username, token, prefs, true);
         } catch (ParserConfigurationException e) {
            e.printStackTrace();
         } catch (FactoryConfigurationError e) {
            e.printStackTrace();
         }
      } else {
         this.logout();
      }
   }

   // FIXME: bug 2067
   public void updateRouteViz() {
      /*var prefs:XML = <preferences/>;
      prefs.@viz_id = G.user.route_viz.id_;
   
      m4_ASSERT(this.logged_in);
      if (this.rememberme)
         G.fcookies.set('route_viz', this.route_viz.id_ );
   
      new WFS_PutPreference(prefs).fetch();*/
   }
}

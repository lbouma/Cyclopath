/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.Hashtable;
import java.util.Set;
import java.util.UUID;

import junit.framework.Assert;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.db.CyclopathDbAdapter;
import org.cyclopath.android.gwis.GWIS_Commit;
import org.cyclopath.android.items.Byway;
import org.cyclopath.android.items.Feature;
import org.cyclopath.android.items.Geofeature;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.MapLayer;
import org.cyclopath.android.items.Route;
import org.cyclopath.android.items.Track;
import org.cyclopath.android.util.LogS;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.TrackDeletionHandler;
import org.cyclopath.android.util.User;

import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.SharedPreferences;
import android.content.SharedPreferences.Editor;
import android.hardware.SensorManager;
import android.location.Location;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.provider.Settings;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.method.LinkMovementMethod;
import android.text.style.ForegroundColorSpan;
import android.text.style.URLSpan;
import android.util.Log;
import android.widget.TextView;

/**
 * Some global methods and variables.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class G {

   /** Reference to global map object.*/
   public static MapSurface map;
   
   /** Landmarks experiment condition */
   public static String landmark_condition = Constants.LANDMARK_CONDITION_NONE;
   /** Landmarks Experiment */
   public static boolean LANDMARKS_EXP_ON = false;
   
   /** Holds the current active recording track */
   public static Track current_track;
   /** Holds the current selected track*/
   public static Track selected_track;
   
   /** Used for confirming deletions of tracks*/
   public static Track track_to_delete;
   /** Used for confirming deletions of tracks*/
   public static TrackDeletionHandler track_deletion_handler;
   /** Used for handling progress dialog cancellations */
   public static DialogInterface.OnCancelListener cancel_handler;
   
   /** What aerial tile is active. If -1, no aerial tiles are being shown.*/
   public static int aerial_state = -1;
   /** current map zoom level */
   public static int zoom_level = Constants.MAP_ZOOM;
   /** previous map zoom level */
   public static int zoom_level_previous = Constants.MAP_ZOOM;
   
   /** Reference to user */
   public static User user;
   
   /** Latest known revision ID */
   public static int max_rid = 0;

   /** Cookie object for logged-in user */
   public static SharedPreferences cookie;
   /** Cookie object for anonymous tracking */
   public static SharedPreferences cookie_anon;
   /** Cookie object for autocomplete addresses */
   public static SharedPreferences autocomplete;

   /** UUID for this browser profile, so we can anonymously track folks. */
   public static UUID browid = null;
   /** Random ID for this *instance* of the app, so we can detect if
    * the user is running multiple clients and to track sessions better */
   public static UUID sessid = UUID.randomUUID();
   
   /** Whether Cyclopath is in semi-protected mode. */
   public static boolean semiprotect_griped = false;
   
   /** The listener for requests that must be handled by the main activity */
   public static Handler cyclopath_handler = null;
   /** The listener for requests that must be handled by the track manager */
   public static Handler track_manager_handler = null;
   /** Handler for active activity (mostly handles opening dialogs) */
   public static Handler base_handler = null;
   /** The listener for requests that must be handled by the item details
    * activity */
   public static Handler attachment_UI_handler = null;
   /** How many data requests have been created since the last idle */
   protected static int requests_created = 0;
   /** How many data requests have been completed since the last idle */
   protected static int requests_completed = 0;

   /** Layers containing map data */
   public static Hashtable<Float, MapLayer> layers;
   /** Used to discard duplicates **/
   public static Hashtable<Integer, Geofeature> vectors_old_all;
   /** Used to know which byways are touching each other **/
   public static Hashtable<Integer, Set<Byway>> nodes_adjacent;
   /** Active route on map */
   public static Route active_route;
   /** SQLite database */
   public static CyclopathDbAdapter db;
   
   /** the last best location retrieved from a location provider. */
   public static Location last_location;

   /** manages logs and sends them to the server */
   public static LogS server_log;
   /** Whether the app has attempted to save unsaved tracks during this
    * session. */
   public static boolean track_save_attempted = false;
   /** Whether tags have been loaded */
   public static boolean tags_loaded = false;
   /** Whether the status of the landmarks experiment has been loaded */
   public static boolean exp_active_loaded = false;
   
   /** Contains the context associated with the Cyclopath application
    * This is meant to be used in non-activites where alternative solutions are
    * unavailable (for example, when locale or user settings are fetched).
    * It cannot be used for UI-related actions. */
   public static Context app_context;

   // *** Static methods
   
   /**
    * Returns true if aerial tiles are currently activated.
    */
   public static boolean aerialStateOn() {
      return aerial_state >= 0;
   }
   
   /**
    * Returns an index into the Constants.BEARINGS angle classification array
    * based on the angle (0 to 360 degrees).
    */
   public static int angle_class_id(double angle) {
      Assert.assertTrue(angle < 360 && angle >= 0);
      for (int i = 0; i < Constants.BEARINGS.length; i++)
         if (angle < Constants.BEARINGS[i].getAngle())
            return i;
      Assert.fail();
      return 0;
   }

   /**
    * Returns an index into the Constants.BEARINGS angle classification array
    * based on the angle formed by (0,0) to (xdelta,ydelta).
    */
   public static int angle_class_idx(PointD delta) {
      return G.angle_class_id(G.arctan(delta.x, delta.y));
   }

   /**
    *  Calculates the relative turn angle between the vector <x2, y2> 
    * and <x1, y1>. This is different than the shortest angle between two
    * vectors in that this measures a full 360 degrees.
    *
    * A local orthonormal basis is used, where the y-axis is <x1, y1>.  The
    * relative angle of <x2, y2> is then measured as the ccw rotation from
    * the x-axis.  Thus 2 vectors pointing in the same direction would
    * return a value of 90.
    * 
    * Returns an angle from 0 to 360
    */
   public static double ang_rel(PointD p1,
                                PointD p2) {
      // Calculate the length to normalize <x1, y1> and <y1, -x1>
      double l = G.distance(p1.x, p1.y, 0, 0);
   
      // to prevent divide-by-zero
      if (p1.y != 0) {
         // Returns the absolute angle of the transformed vector <x2, y2>'
         // which is [[y1/l, x1/l][-x1/l, y1/l]]^-1 * <x2, y2>
         return G.arctan(l * p2.x / p1.y
                          - p1.x * (p1.x * p2.x + p1.y * p2.y) / (l * p1.y),
                         (p1.x * p2.x + p1.y * p2.y) / l);
      } else if (p1.x > 0) 
         // The appropriate transform of <x2, y2> if y1 == 0 and x1 > 0
         return G.arctan(-p2.y, p2.x);
      else if (p1.x < 0)
         // The appropriate transform of <x2, y2> if y1 == 0 and x1 < 0
         return G.arctan(p2.y, -p2.x);
      Assert.fail();
      // Return statement to make the compiler happy.
      return 0;
   }

   /**
    *  Essentially {@link Math.atan2} except:
    * Returns angle in degrees in range [0, 360).
    */
   public static double arctan(double x, double y) {
      double a = rad_to_degree(Math.atan2(y, x));
      if (a < 0)
         return a + 360.0;
      else
         return a;
   }

   /**
    * Returns the better location between loc1 and loc2.
    */
   public static Location betterLocation(Location loc1, Location loc2) {
      // If one is null, return the other. If both are null, null is returned.
      if (loc1 == null) {
         return loc2;
      } else if (loc2 == null) {
         return loc1;
      }
      
      long timeDelta = loc1.getTime() - loc2.getTime();
      
      // If one location is significantly newer, return that location.
      if (timeDelta > Constants.LOCATION_SIGNIFICANT_TIME_DIF) {
         // loc1 is significantly newer
         return loc1;
      } else if (timeDelta < -Constants.LOCATION_SIGNIFICANT_TIME_DIF) {
         // loc2 is significantly newer
         return loc2;
      }
   
      int accuracyDelta = (int) (loc1.getAccuracy() - loc2.getAccuracy());
      
      // If one location is significantly more accurate, return that location.
      if (accuracyDelta <  -Constants.LOCATION_SIGNIFICANT_ACCURACY_DIF) {
         // loc1 is significantly more accurate
         return loc1;
      } else if (accuracyDelta >  Constants.LOCATION_SIGNIFICANT_ACCURACY_DIF) {
         // loc2 is significantly more accurate
         return loc2;
      }
      
      // If we get here it means that both locations are recent and of similar
      // accuracy. Therefore, we just pick the newer one.
      
      if (timeDelta > 0) {
         return loc1;
      } else {
         return loc2;
      }
   }
   
   /**
    * Converts a text view into a working link.
    * @param text textview to convert
    * @param linkUrl URL that the text will link to
    * @param linkName text visible to users
    * @param color color of the link
    */
   public static void buildURLLink(TextView text, String linkUrl,
                                   String linkName, int color) {
      SpannableString str = SpannableString.valueOf(linkName);
      str.setSpan(new URLSpan(linkUrl), 0, linkName.length(),
          Spannable.SPAN_INCLUSIVE_EXCLUSIVE);
      str.setSpan(new ForegroundColorSpan(0xff99ccff), 0, linkName.length(),
          Spannable.SPAN_INCLUSIVE_EXCLUSIVE);
      text.setText(str);
      text.setMovementMethod(LinkMovementMethod.getInstance());
   }
   
   /**
    * Checks if a required update is available and forces the user to update
    * or exit the application.
    */
   public static boolean checkForMandatoryUpdate(){
      int latest_version = Integer.parseInt(
            G.cookie_anon.getString(Constants.LATEST_VERSION, "1"));
      int local_version = Constants.gwis_version;
      if (latest_version <= local_version) {
         return false;
      }
      if (base_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.BASE_UPDATE_NEEDED;
         msg.setTarget(base_handler);
         msg.sendToTarget();
      }
      return true;
   }

   /**
    *  Convert a string of text coordinates to an array of points
    * @param s string of coordinates to convert
    * @return List of points
    */
   public static ArrayList<PointD> coordsStringToPoint(String s) {
      String[] poslist = s.split(" ");
      ArrayList<PointD> points = new ArrayList<PointD>();

      Assert.assertTrue((poslist.length % 2) == 0); // even no. of elements

      for (int i = 0; i < poslist.length; i += 2) {
         points.add(new PointD(Double.parseDouble(poslist[i]),
                               Double.parseDouble(poslist[i + 1])));
      }
      return points;
   }
   
   /**
    * Converts a GPS location into a Point of map coordinates.
    * @param location GPS location with latitude and longitude
    * @return Point of location in map coordinates
    */
   public static PointD latlonToMap(Location location) {
      return latlonToMap(location.getLatitude(), location.getLongitude());
   }

   /**
    * Converts a GPS location into a Point of map coordinates. This is some
    * complicated math!
    * This method is based on an implementation by Steven Dutch at
    * <a href="http://www.uwgb.edu/dutchs/usefuldata/ConvertUTMNoOZ.HTM">
    * http://www.uwgb.edu/dutchs/usefuldata/ConvertUTMNoOZ.HTM</a>
    */
   public static PointD latlonToMap(double lat, double lon) {
      double a = 6378137.0;  //equatorial radius, meters.
      double f = 1/298.2572236; //polar flattening.
      double k0 = 0.9996; //scale on central meridian
      double b = a*(1-f); //polar axis.
      double e = Math.sqrt(1 - (b/a)*(b/a)); //eccentricity
      if(lat < -90 || lat > 90
         || lon < -180 || lon > 180) {
         return null;
      }
      //Convert latitude to radians
      double phi = Math.toRadians(lat);
      int utmz = 15;
      int zcm = 3 + 6*(utmz-1) - 180; //Central meridian of zone
      //Calculate Intermediate Terms
      double esq = (1 - (b/a)*(b/a)); //e squared for use in expansions
      double e0sq = e*e/(1-e*e); // e0 squared - always even powers
      double N = a/Math.sqrt(1-Math.pow(e*Math.sin(phi),2));
      double T = Math.pow(Math.tan(phi),2);
      double C = e0sq*Math.pow(Math.cos(phi),2);
      double A = Math.toRadians((lon-zcm))*Math.cos(phi);
      //Calculate M
      double M = phi*(1 - esq*(1.0/4 + esq*(3.0/64 + 5*esq/256)));
      M = M - Math.sin(2*phi)*(esq*(3.0/8 + esq*(3.0/32 + 45*esq/1024)));
      M = M + Math.sin(4*phi)*(esq*esq*(15.0/256 + esq*45/1024));
      M = M - Math.sin(6*phi)*(esq*esq*esq*(35.0/3072));
      M = M*a; //Arc length along standard meridian
      //Calculate UTM Values
      double x =
         k0*N*A*(1 + A*A*((1-T+C)/6
                 + A*A*(5 - 18*T + T*T + 72*C -58*e0sq)/120));
      x = x + 500000; //Easting standard 
      double y =
         k0*(M + N*Math.tan(phi)*(A*A*(1.0/2 + A*A*((5 - T + 9*C + 4*C*C)/24
             + A*A*(61 - 58*T + T*T + 600*C - 330*e0sq)/720)))); //Northing
      if (y < 0) {
         y = 10000000 + y;
      }
      // Return result up to three decimal points
      float dec = 1000;
      return new PointD((Math.round(x*dec))/dec, (Math.round(y*dec))/dec);
   }
   
   /**
    * Converts a Point of map coordinates into a GPS location. This is some
    * complicated math!
    * This method is based on an implementation by Steven Dutch at
    * <a href="http://www.uwgb.edu/dutchs/usefuldata/ConvertUTMNoOZ.HTM">
    * http://www.uwgb.edu/dutchs/usefuldata/ConvertUTMNoOZ.HTM</a>
    * @param Point of location in map coordinates
    * @return array of doubles with latitude and longitude
    */
   public static double[] mapToLatLon(PointD p) {
      //Convert UTM Coordinates to Geographic
      double a = 6378137.0; //equatorial radius, meters.
      double f = 1/298.2572236; //polar flattening.
      double k0 = 0.9996; //scale on central meridian
      double b = a*(1-f); //polar axis.
      double e = Math.sqrt(1 - (b/a)*(b/a)); //eccentricity
      double esq = (1 - (b/a)*(b/a)); //e squared for use in expansions
      double e0sq = e*e/(1-e*e); // e0 squared - always even powers
      
      if (p.x < 160000 || p.x > 840000) {
         Log.i("gps", "Outside permissible range of easting values \n" +
         		       "Results may be unreliable \n Use with caution");
      } 
      if (p.y < 0) {
         Log.i("gps", "Negative values not allowed \n Results may be" +
         		       "unreliable \n Use with caution");
      }
      if (p.y > 10000000) {
         Log.i("gps", "Northing may not exceed 10,000,000 \n Results may be" +
         		       "unreliable \n Use with caution");
      }
      int utmz = 15;
      double zcm = 3 + 6*(utmz-1) - 180; //Central meridian of zone
      double e1 = (1 - Math.sqrt(1 - e*e))/
                  (1 + Math.sqrt(1 - e*e)); //Called e1 in USGS PP 1395 also
      //In case origin other than zerolat - not needed for standard UTM
      double M0 = 0;
      double M = M0 + ((float)p.y)/k0; //Arc length along standard meridian.
      double mu = M/(a*(1 - esq*(1.0/4 + esq*(3.0/64 + 5*esq/256))));
      double phi1 = mu + e1*(3.0/2 - 27*e1*e1/32)*Math.sin(2*mu)
            + e1*e1*(21.0/16 -55*e1*e1/32)*Math.sin(4*mu); //Footprint Latitude
      phi1 = phi1
           + e1*e1*e1*(Math.sin(6*mu)*151.0/96 + e1*Math.sin(8*mu)*1097.0/512);
      double C1 = e0sq*Math.pow(Math.cos(phi1),2);
      double T1 = Math.pow(Math.tan(phi1),2);
      double N1 = a/Math.sqrt(1-Math.pow(e*Math.sin(phi1),2));
      double R1 = N1*(1-e*e)/(1-Math.pow(e*Math.sin(phi1),2));
      double D = ((float)(p.x-500000))/(N1*k0);
      double phi = (D*D)*(1.0/2-D*D*(5 + 3*T1 + 10*C1 - 4*C1*C1 - 9*e0sq)/24);
      phi = phi + Math.pow(D,6)*
                  (61 + 90*T1 + 298*C1 + 45*T1*T1 -252*e0sq - 3*C1*C1)/720;
      phi = phi1 - (N1*Math.tan(phi1)/R1)*phi;
               
      // Latitude
      double latitude = Math.floor(Math.toDegrees(1000000*phi))/1000000;
         
      // Longitude
      double lng =
         D*(1 + D*D*((-1 -2*T1 -C1)/6
              + D*D*(5 - 2*C1 + 28*T1 - 3*C1*C1 +8*e0sq + 24*T1*T1)/120))
            /Math.cos(phi1);
      double lngd = zcm + Math.toDegrees(lng);
      double longitude = Math.floor(1000000*lngd)/1000000;

      return new double[] {latitude, longitude};
   }

   /**
    * Called to get the current location. If the last location recorded is
    * null or is too old, then there is no current location and null is
    * returned.
    * @return Current Location
    */
   public static Location currentLocation() {
      // FIXME: This code does not handle well cases where there is still a
      // location from cell towers. Locations become stale anyway after a
      // short time, so maybe this block is not needed.
      /*LocationManager lm = (LocationManager) 
                            context.getSystemService(Context.LOCATION_SERVICE);
      WifiManager wm = (WifiManager) 
                            context.getSystemService(Context.WIFI_SERVICE);
      if (!lm.isProviderEnabled(LocationManager.GPS_PROVIDER) && 
          !lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)){
         return null;
      }
      if (!lm.isProviderEnabled(LocationManager.GPS_PROVIDER) &&
           lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) &&
           !wm.isWifiEnabled()){
         return null;
      }*/
      if (G.last_location == null) {
         return null;
      } else if ((G.last_location.getTime() - System.currentTimeMillis())
                  < Constants.LOCATION_SIGNIFICANT_TIME_DIF) {
         return G.last_location;
      } else {
         return null;
      }
   }//current_location

   /**
    * Dismisses the current progress dialog.
    */
   public static void dismissProgressDialog() {
      if (G.base_handler != null) {
           Message msg = Message.obtain();
           msg.what = Constants.BASE_DISMISS_PROGESS_DIALOG;
           msg.setTarget(G.base_handler);
           msg.sendToTarget();
        }
   }

   /**
    *  Returns the distance between two points.
    */
   public static double distance(double x1, double y1, double x2, double y2) {
      return Math.sqrt((x1-x2)*(x1-x2) + (y1-y2)*(y1-y2));
   }

   /**
    *  Returns the distance between two points.
    */
   public static double distance(PointD p1, PointD p2) {
      return Math.sqrt((p1.x-p2.x)*(p1.x-p2.x) + (p1.y-p2.y)*(p1.y-p2.y));
   }

   /**
    *  Returns the distance between a point and a line segment.
    */
   public static double distancePointToLine(PointD p, PointD l1, PointD l2) {
      double length_squared = (l1.x-l2.x)*(l1.x-l2.x) + (l1.y-l2.y)*(l1.y-l2.y);
      if (length_squared == 0) {
         return G.distance(p,l1);
      }
      double t = (((p.x-l1.x) * (l2.x-l1.x) + (p.y-l1.y) * (l2.y-l1.y))
                 / length_squared);
      if (t < 0) {
         return G.distance(p,l1);
      }
      if (t > 1){
         return G.distance(p,l2);
      }
      return G.distance(p, new PointD(l1.x + t * (l2.x-l1.x),
                                      l1.y + t * (l2.y-l1.y)));
   }
   
   /**
    * Decrements the number of requests that require the throbber to run and
    * notifies the listener.
    */
   public static void decrementThrobber() {
      requests_completed++;
      if (requests_created == requests_completed) {
         // Finished everything we started; return to idle state
         requests_created = 0;
         requests_completed = 0;
      }
      if (cyclopath_handler != null) {
         notifyThrobberHandler();
      }
   }
   
   public static String getFormattedLength(double length) {
      return getFormattedLength(length, 2, true);
   }

   /**
    * Convert a length value (in meters) into an equivalent string, but
    * converted to miles (or yards if small enough).
    * @param length length in meters
    * @param decimal how many decimal points to use
    * @param units whether to append miles or yards unit
    */
   public static String getFormattedLength(double length, 
                                           int decimal,
                                           boolean units) {
      DecimalFormat dformat = new DecimalFormat("0.0");
      dformat.setMaximumFractionDigits(decimal);
      dformat.setMinimumFractionDigits(decimal);
      double miles = length * Constants.MILES_PER_METER;
      if (miles < 0.1) {
         // convert to yards if less than half a mile
         if (units)
            dformat.setPositiveSuffix("yds");
         // Don't show decimal units for yards, which are always rounded.
         dformat.setMaximumFractionDigits(0);
         dformat.setMinimumFractionDigits(0);
         return dformat.format(Math.round(miles * Constants.YARDS_PER_MILE));
      } else {
         if (units)
            dformat.setPositiveSuffix("mi");
         return dformat.format(miles);
      }
   }

   /**
    * Calculates orientation based on acceleration and magnetic field values
    * obtained from sensors.
    * @return null if there is no valid result and orientation float otherwise
    */
   public static Float getOrientation(float[] accelerationValues,
                                      float[] magneticFieldValues) {
      float[] R = new float[16];
      float[] orientationValues = new float[3];

      if (!SensorManager.getRotationMatrix (R, null, accelerationValues,
                                            magneticFieldValues)) {
         return null;
      }
      SensorManager.getOrientation (R, orientationValues);
      return (float)Math.toDegrees (orientationValues[0]);
   }
   
   /**
    * Returns a new, fresh id for new features.
    * @return next id in the sequence
    */
   public static int idNew() {
      int last_id = G.cookie_anon.getInt(Constants.COOKIE_FRESH_ID, 0) - 1;
      Editor editor = G.cookie_anon.edit();
      editor.putInt(Constants.COOKIE_FRESH_ID, last_id);
      editor.commit();
      return last_id;
   }

   /**
    * Increments the number of requests that require the throbber to run and
    * notifies the listener.
    */
   public static void incrementThrobber() {
      requests_created++;
      if (cyclopath_handler != null) {
         notifyThrobberHandler();
      }
   }


   /**
    * Check if the device has a network connection.
    * @return true if it has a network connection.
    */
   public static boolean isConnected(){
      ConnectivityManager cm = (ConnectivityManager)
                    app_context.getSystemService(Context.CONNECTIVITY_SERVICE);
      NetworkInfo info = cm.getActiveNetworkInfo();
      if (info == null) {
         return false;
      } else {
         return info.isConnected();
      }
   }
   
   /**
    * Returns true if the current landmark experiment condition is for a
    * high number of prompts.
    */
   public static boolean isLandmarkConditionHigh() {
      return G.landmark_condition
            == Constants.LANDMARK_CONDITION_NOW_HIGH
          || G.landmark_condition
               == Constants.LANDMARK_CONDITION_LATER_HIGH;
   }

   /**
    * Returns true if the current landmark experiment condition is for
    * entering landmarks later.
    */
   public static boolean isLandmarkConditionLater() {
      return G.landmark_condition
            == Constants.LANDMARK_CONDITION_LATER_HIGH
          || G.landmark_condition
               == Constants.LANDMARK_CONDITION_LATER_LOW;
   }

   /**
    * Returns true if the current landmark experiment condition is for a
    * low number of prompts.
    */
   public static boolean isLandmarkConditionLow() {
      return G.landmark_condition
            == Constants.LANDMARK_CONDITION_NOW_LOW
          || G.landmark_condition
               == Constants.LANDMARK_CONDITION_LATER_LOW;
   }

   /**
    * Returns true if the current landmark experiment condition is for
    * entering landmarks at the moment.
    */
   public static boolean isLandmarkConditionNow() {
      return G.landmark_condition.equals(Constants.LANDMARK_CONDITION_NOW_HIGH)
          || G.landmark_condition.equals(Constants.LANDMARK_CONDITION_NOW_LOW);
   }
   
   public static void logBuildInfo() {
      server_log.event("mobile/build_info",
            new String[][]{{"board", Build.BOARD},
                           {"brand", Build.BRAND},
                           {"device", Build.DEVICE},
                           {"fingerprint", Build.FINGERPRINT},
                           {"id", Build.ID},
                           {"model", Build.MODEL},
                           {"product", Build.PRODUCT},
                           {"tags", Build.TAGS},
                           {"incremental", Build.VERSION.INCREMENTAL},
                           {"release", Build.VERSION.RELEASE},
                           {"sdk", Build.VERSION.SDK},
                           {"device-id", Settings.Secure.getString(
                                             app_context.getContentResolver(),
                                             Settings.Secure.ANDROID_ID)}},
                           true);
   }
   
   /**
    * Notifies the registered handler of a change in throbber count.
    */
   public static void notifyThrobberHandler() {
      if (cyclopath_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.THROBBER_CHANGED;
         msg.setTarget(cyclopath_handler);
         msg.sendToTarget();
      }
   }
   
   /**
    *  Converts radians to degrees, no normalization.
    */
   public static double rad_to_degree(double rad) {
      return (rad * 180.0 / Math.PI);
   }
   
   /**
    * This method attempts to save local tracks that have not been saved on
    * the server.
    * @param context
    */
   public static void saveUnsavedTracks(Context context) {
      track_save_attempted = true;
      ArrayList<Track> unsaved_tracks = G.db.getUnsavedTrackList();
      ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
      for (Track item : unsaved_tracks) {
         items.add(G.db.getTrack(item.stack_id));
      }
      if (items.size() > 0) {
         GWIS_Commit g = new GWIS_Commit(items);
         g.retrying = true;
         g.fetch();
      }
   }

   /**
    * Makes a route the active route on the map and moves the view to the route.
    */
   public static void setActiveRoute(Route r) {
      if (r == null) {
         active_route = null;
      } else if (r.getBboxMap() == null){
         active_route = null;
      } else {
         if (layers.get(r.getZplus())!= null) {
            layers.get(r.getZplus()).children = new ArrayList<Feature>();
         }
         // FIXME: bug 2067
         //G.sl.event("exp/route_viz/route", new String[][]{{"route", Long.toString(r.id)}, 
         //                                   "viz": G.user.route_viz.id_}});
         
         map.featureAdd(r);
         map.lookAt(r, 0);
         active_route = r;
         active_route.selected_direction = 0;
      }
   }

   /**
    * Show an alert with a title and a message, with any mailto links enabled.
    * @param text alert message
    * @param title alert title
    */
   public static void showAlert(String text, String title) {
      showAlert(text, title, android.R.drawable.ic_dialog_alert);
   }

   /**
    * Show an alert with a title and a message, with any mailto links enabled.
    * @param txt alert message
    * @param title alert title
    * @param iconId alert icon
    */
   public static void showAlert(String text, String title, int iconId) {
      //FIXME: At some point, it seems iconId was removed from the code.
      if (base_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.BASE_SHOW_ALERT;
         Bundle bundle = new Bundle();
         bundle.putString(Constants.ALERT_TITLE, title);
         bundle.putString(Constants.ALERT_MESSAGE, text);
         msg.setData(bundle);
         msg.setTarget(base_handler);
         msg.sendToTarget();
      }
   }
   
   /**
    * Shows a warning concerning holds on a user's account or computer/device.
    * @param topic message about types of holds
    * @param bans new holds
    * @param removed holds that have been removed
    * @param context
    */
   public static void showBanWarning(String topic, String bans,
                                     String removed) {
      
      String title =
         app_context.getResources().getString(R.string.account_holds_title);

      if (bans == null || bans.equals("")) {
         bans =
            app_context.getResources().getString(R.string.account_no_holds);
      }
      if (removed == null || removed.equals("")) {
         removed =
            app_context.getResources().getString(R.string.account_no_holds);
      }

      String message = String.format(
          app_context.getResources().getString(R.string.account_holds_message),
          topic, bans, removed);
      
      showAlert(message, title);
   }
   
   /**
    * Shows an indeterminate progress dialog with the given title and text.
    * @param title
    * @param text
    */
   public static void showProgressDialog(String title, String text) {
      showProgressDialog(title, text, true);
   }
   
   /**
    * Shows a progress dialog with the given title and text.
    * @param title
    * @param text
    * @param indeterminate
    */
   public static void showProgressDialog(String title, String text,
                                         boolean indeterminate) {
      if (base_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.BASE_SHOW_PROGESS_DIALOG;
         Bundle bundle = new Bundle();
         bundle.putString(Constants.ALERT_TITLE, title);
         bundle.putString(Constants.ALERT_MESSAGE, text);
         bundle.putBoolean(Constants.DIALOG_INDETERMINATE, indeterminate);
         msg.setData(bundle);
         msg.setTarget(base_handler);
         msg.sendToTarget();
      }
   }
   
   /**
    * Tells the current activity to show a toast message with the given text.
    * @param text
    */
   public static void showToast(String text) {
      if (base_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.BASE_SHOW_TOAST;
         Bundle bundle = new Bundle();
         bundle.putString(Constants.TOAST_MESSAGE, text);
         msg.setData(bundle);
         msg.setTarget(base_handler);
         msg.sendToTarget();
      }
   }
   
   /** Constructs a popup window verifying whether or not the user wants to
    * delete the track. 
    * @param track The track pending confirmation
    * @param context The context of the activity it is called from */
   public static void trackDeletionHandle(
         Track track, Context context, TrackDeletionHandler delete_handler){
      G.track_to_delete = track;
      G.track_deletion_handler = delete_handler;
      String message = 
         context.getResources().getString(R.string.track_confirm_del_message);
      String title = 
         context.getResources().getString(R.string.track_confirm_del_title);
      title = title + " \"" + track.name + "\"?";
      new AlertDialog.Builder(context).setMessage(message).setTitle(title)
            .setNegativeButton("No", new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton){}
            })
            .setPositiveButton("Yes", new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton){
                  if (G.selected_track != null) {
                     if (G.selected_track.equals(G.track_to_delete)) {
                        G.map.featureDiscard(G.selected_track);
                        G.selected_track = null;
                        G.map.redraw();
                     }
                  }
                  // delete from local db
                  G.db.deleteTrack(G.track_to_delete);
                  // handler manages deleting from server (we need a context
                  // object for that)
                  G.track_deletion_handler.deleteTrack(G.track_to_delete);
               }
            }).show();
   }
   
   /**
    * Updates the progress for a progress dialog.
    * @param title
    * @param text
    * @param progress
    */
   public static void updateProgressDialog(String title, String text,
                                           int progress) {
      if (G.base_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.BASE_UPDATE_PROGESS_DIALOG;
         Bundle bundle = new Bundle();
         bundle.putString(Constants.ALERT_TITLE, title);
         bundle.putString(Constants.ALERT_MESSAGE, text);
         bundle.putInt(Constants.DIALOG_PROGRESS, progress);
         msg.setData(bundle);
         msg.setTarget(G.base_handler);
         msg.sendToTarget();
      }
   }

   /**
    * Returns true if there is a current location and it is in or near the
    * current available map. This is used to keep users trying out the app
    * from other cities to get auto-panned to empty map locations.
    */
   public static boolean withinBounds() {
      if (G.currentLocation() == null) {
         return false;
      } else if (G.currentLocation().getLatitude()
                     < (Constants.MAP_LATLON_BOTTOM_EDGE
                           - Constants.MAP_LATLON_BUFFER)
              || G.currentLocation().getLatitude()
                     > (Constants.MAP_LATLON_TOP_EDGE
                           + Constants.MAP_LATLON_BUFFER)
              || G.currentLocation().getLongitude()
                     < (Constants.MAP_LATLON_LEFT_EDGE
                           - Constants.MAP_LATLON_BUFFER)
              || G.currentLocation().getLongitude()
                     > (Constants.MAP_LATLON_RIGHT_EDGE
                           + Constants.MAP_LATLON_BUFFER)) {
         return false;
      } else {
         return true;
      }
   }
}

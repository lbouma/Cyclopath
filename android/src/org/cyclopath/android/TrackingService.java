/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;
import java.util.Date;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_LandmarkPromptLog;
import org.cyclopath.android.items.LandmarkNeed;
import org.cyclopath.android.items.Track;
import org.cyclopath.android.items.TrackPoint;
import org.cyclopath.android.util.PointD;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.location.LocationProvider;
import android.media.AudioManager;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.IBinder;
import android.os.Message;
import android.os.Vibrator;
import android.util.Log;

/**
 * Background service that handles recording tracks.
 * FIXME: This is not urgent, but there is some common code in the location
 * status listeners that could be merged.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class TrackingService extends Service implements LocationListener,
                                                        SensorEventListener {

   /** manager for status bar notifications */
   private NotificationManager notification_manager;
   /** ID for tracking notification */
   protected static final int TRACKING_NOTIFICATION_ID = 1;
   /** ID for tracking notification */
   protected static final int LANDMARK_NOTIFICATION_ID = 2;
   /** manager for location updates */
   private LocationManager locationManager;
   /** location where the last set of landmark needs was requested */
   private PointD last_need_request_coords;
   /** Distance the user must travel before new landmark needs are fetched */
   public static double next_need_request_dist =
         Constants.FIRST_LANDMARK_NEED_DISTANCE;
   /** number of times the user has received landmark prompts for this trial */
   private int num_prompts = 0;

   /** Manager for listening to sensor updates */
   private SensorManager mSensorManager;
   /** accelerometer sensor (used for calculating orientation)*/
   private Sensor accelerometerSensor;
   /** magnetic field sensor (used for calculating orientation)*/
   private Sensor magneticFieldSensor;
   /** temperature sensor */
   private Sensor temperatureSensor;
   /** acceleration values returned by the accelerometer sensor */
   private float[] accelerationValues;
   /** magnetic field values returned by the magnetic field sensor */
   private float[] magneticFieldValues;
   
   /** current orientation */
   private Float orientation;
   /** current temperature */
   private Float temperature;
   /** last orientation time (used for identifying stale values)*/
   private Date last_orientation;
   /** last temperature time (used for identifying stale values) */
   private Date last_temperature;

   /**
    * Handles sensor accuracy changes. Required method, but not used for now.
    */
   @Override
   public void onAccuracyChanged(Sensor sensor, int accuracy) {
      // do nothing
   }

   /**
    * Required method, but not used by us for now.
    */
   @Override
   public IBinder onBind(Intent intent) {
      return null;
   }

   /**
    * Sets up the notification and location managers.
    */
   @Override
   public void onCreate() {
      super.onCreate();
      this.notification_manager =
         (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);

      // register for location updates
      this.locationManager = 
         (LocationManager) this.getSystemService(Context.LOCATION_SERVICE);
      locationManager.requestLocationUpdates(
            LocationManager.GPS_PROVIDER,
            Constants.SERVICE_GPS_TIME_BETWEEN_UPDATES,
            Constants.MIN_DISTANCE_BETWEEN_UPDATES, this);
      this.accelerationValues = new float[3];
      this.magneticFieldValues = new float[3];
      this.mSensorManager =
         (SensorManager)getSystemService(Activity.SENSOR_SERVICE);
      this.accelerometerSensor =
         this.mSensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
      this.magneticFieldSensor =
         this.mSensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD);
      this.temperatureSensor =
         this.mSensorManager.getDefaultSensor(Sensor.TYPE_TEMPERATURE);
      mSensorManager.registerListener(this, accelerometerSensor,
                                      SensorManager.SENSOR_DELAY_UI);
      mSensorManager.registerListener(this, magneticFieldSensor,
                                      SensorManager.SENSOR_DELAY_UI);
      mSensorManager.registerListener(this, temperatureSensor,
                                      SensorManager.SENSOR_DELAY_UI);
   }
   
   /**
    * Cleanup.
    */
   @Override
   public void onDestroy() {
      super.onDestroy();
      this.locationManager.removeUpdates(this);
      this.notification_manager.cancel(TRACKING_NOTIFICATION_ID);
      this.notification_manager.cancel(LANDMARK_NOTIFICATION_ID);
   }

   /**
    * Updates the track when a new location comes in.
    */
   @Override
   public void onLocationChanged(Location location) {
      if (Constants.DEBUG) {
         Log.d("location", "service location changed");
      }
      // Stop the service if there is no current track being recorded.
      if (G.current_track == null) {
         this.stopSelf();
         return;
      }
      // This hack fixes the strange bug 2031
      location.setTime(System.currentTimeMillis());
      
      if ((this.accelerometerSensor == null
            || this.magneticFieldSensor == null)) {
         G.map.pointer.setBearing(G.last_location, location);
      }
      
      // If more than 1 hour has passed since the last point, stop recording
      // and ask user to save or discard track.
      if (G.current_track.points != null) {
         long last_time = G.current_track.points.get(
               G.current_track.points.size()-1).getTimestamp().getTime();
         if (System.currentTimeMillis() - last_time >
               Constants.STALE_RECORDING_THRESHOLD) {
            if (G.cyclopath_handler != null) {
               Message msg = Message.obtain();
               msg.what = Constants.SHOW_STALE_TRACK_DIALOG;
               msg.setTarget(G.cyclopath_handler);
               msg.sendToTarget();
            }
            return;
         }
      }
      
      // if the location is better than the previous one, update our current
      // location
      G.last_location = G.betterLocation(G.last_location, location);
      this.resetStaleSensorValues();
      TrackPoint tp = new TrackPoint(G.last_location, this.orientation,
                                     this.temperature);
      if (G.current_track.add(tp)) {
         G.db.addTrackPoint(tp, G.current_track.stack_id);
         G.map.pointer.setPosition(G.last_location);
         G.map.pointer.setAccuracy(G.last_location.getAccuracy());
         G.map.redraw();
      }
      if(!MapSurface.has_panned){
         G.map.goToLocation(G.last_location);
      }

      G.server_log.event("mobile/location",
         new String[][]{{"longitude",
                         Double.toString(G.last_location.getLongitude())},
                        {"latitude",
                         Double.toString(G.last_location.getLatitude())},
                        {"source",
                         G.last_location.getProvider()},
                        {"accuracy",
                         Double.toString(G.last_location.getAccuracy())}});
      
      // ** Landmarks Experiment
      
      if (G.cookie.getLong(Constants.LANDMARKS_EXP_AGREE, 0)
            > (new Date()).getTime()
          && G.LANDMARKS_EXP_ON
          && G.landmark_condition != Constants.LANDMARK_CONDITION_NONE
          && G.landmark_condition != Constants.LANDMARK_CONDITION_NOUSR) {
         PointD mapcoords = G.latlonToMap(location);
         if (this.last_need_request_coords == null) {
            // Don't request right away
            this.last_need_request_coords = mapcoords;
         } else if (
               G.distance(this.last_need_request_coords, mapcoords)
                  > next_need_request_dist) {
            this.fetch_landmarks(mapcoords);
         }
         
         int max_prompts = 3;
         if (G.isLandmarkConditionHigh()) {
            max_prompts = 6;
         }
         
         if (LandmarkNeed.current_need == null
               && this.num_prompts < max_prompts) {
            // Check if we are near a landmark need spot and prompt the user.
            LandmarkNeed need = LandmarkNeed.nearbyNeed(mapcoords);
            if (need != null) {
               next_need_request_dist =
                     Constants.NEXT_LANDMARK_NEED_DISTANCE;
               LandmarkNeed.current_need = need;
               this.showPrompt();
               G.map.featureAdd(need);
               new GWIS_LandmarkPromptLog(
                  this.num_prompts, need, G.current_track.trial_num).fetch();
               this.num_prompts++;
            }
         } else if (LandmarkNeed.current_need != null) {
            // Check if we are no longer near landmark and hide prompt.
            if (G.distance(mapcoords,
                           LandmarkNeed.current_need.coords) >
                  Constants.LANDMARK_NEED_TOO_FAR_DISTANCE) {
               this.hidePrompt();
               LandmarkNeed.current_need = null;
               LandmarkNeed.nearby_landmarks = new ArrayList<LandmarkNeed>();
               G.map.featuresDiscard(Constants.LANDMARK_NEED_LAYER);
            }
         }
      }
   }
   
   /**
    * Called when the location provider is disabled.
    * @param provider Location Provider
    */
   @Override
   public void onProviderDisabled(String provider) {
      if (Constants.DEBUG) {
         Log.d("gps","location provider disabled: " + provider);
      }
   }

   /**
    * Called when the location provider is enabled.
    * @param provider Location Provider
    */
   @Override
   public void onProviderEnabled(String provider) {
      if (Constants.DEBUG) {
         Log.d("gps","location provider enabled: " + provider);
      }
   }

   /**
    * Stores new sensor values.
    */
   @Override
   public void onSensorChanged(SensorEvent event) {
      switch (event.sensor.getType ()){
         case Sensor.TYPE_ACCELEROMETER:
            accelerationValues = event.values.clone();
            break;
         case Sensor.TYPE_MAGNETIC_FIELD:
            magneticFieldValues = event.values.clone();
            break;
         case Sensor.TYPE_TEMPERATURE:
            this.temperature = event.values[0];
            this.last_temperature = new Date();
            break;
      }
      this.orientation =
         G.getOrientation(accelerationValues, magneticFieldValues);
      this.last_orientation = new Date();
   }

   /**
    * Starts recording a track.
    */
   @Override
   public int onStartCommand(Intent intent, int flags, int startId) {
      this.showNotification();
      
      if (intent == null) {
         this.stopSelf();
      }

      if (G.layers.containsKey(Constants.TRACK_LAYER)) {
         G.map.featuresDiscard(Constants.TRACK_LAYER);
      }
      G.current_track = new Track(G.user.getName());
      G.current_track.recording = true;
      G.current_track.name = "";
      if (G.cookie.getLong(Constants.LANDMARKS_EXP_AGREE, 0)
            > (new Date()).getTime()
            && G.LANDMARKS_EXP_ON) {
         LandmarkNeed.nearby_landmarks = new ArrayList<LandmarkNeed>();
      }
      G.current_track.date = new Date();
      G.current_track.trial_num = intent.getIntExtra("trial_num", -1);
      G.db.addTrack(G.current_track);
      G.map.featureAdd(G.current_track);

      Location loc = G.currentLocation();
      if (loc != null) {
         G.map.goToLocation(loc);
         
         TrackPoint tp =
            new TrackPoint(loc, this.orientation, this.temperature);
         G.current_track.add(tp);
         G.db.addTrackPoint(tp, G.current_track.stack_id);
         G.map.redraw();
      }

      return START_STICKY;
   }

   /**
    * Called when the location provider status changes.
    */
   @Override
   public void onStatusChanged(String provider, int status, Bundle extras) {
      if (Constants.DEBUG) {
         Log.d("gps","status changed for provider: " + provider);
         switch (status) {
         case LocationProvider.AVAILABLE:
            Log.d("gps","AVAILABLE");
            break;
         case LocationProvider.OUT_OF_SERVICE:
            Log.d("gps","OUT_OF_SERVICE");
            break;
         case LocationProvider.TEMPORARILY_UNAVAILABLE:
            Log.d("gps","TEMPORARILY_UNAVAILABLE");
            break;
         }
      }
   }

   /**
    * Fetches a set of landmark needs near the current location.
    * @param coords
    * @param time
    */
   public void fetch_landmarks(PointD coords) {
      LandmarkNeed.fetchLandmarks(coords);
      this.last_need_request_coords = coords;
      // If we don't find anything, then we will just query again until
      // we do. If a landmark need is found, this number is changed
      // to a higher one in order to space out prompts.
      next_need_request_dist = 0;
   }

   /**
    * Cancels the notification and sends a message to hide the prompt.
    */
   public void hidePrompt() {
      this.notification_manager.cancel(LANDMARK_NOTIFICATION_ID);
      Cyclopath.landmark_editing_mode_now = false;
      if (G.cyclopath_handler != null) {
         Message msg = Message.obtain();
         msg.what = Constants.HIDE_LANDMARK_PROMPT;
         msg.setTarget(G.cyclopath_handler);
         msg.sendToTarget();
         msg = Message.obtain();
         msg.what = Constants.REFRESH_LANDMARK_EXPERIMENT;
         msg.setTarget(G.cyclopath_handler);
         msg.sendToTarget();
      }
   }
   
   /**
    * Resets sensor values if they are too old.
    */
   public void resetStaleSensorValues() {
      long currentTime = new Date().getTime();
      if (this.last_orientation != null) {
         if (currentTime - this.last_orientation.getTime()
               > Constants.STALE_SENSOR_TIMEOUT) {
            this.orientation = null;
         }
      }
      if (this.last_temperature != null) {
         if (currentTime - this.last_temperature.getTime()
               > Constants.STALE_SENSOR_TIMEOUT) {
            this.temperature = null;
         }
      }
   }

   /**
    * Show a notification while we are close to a landmark need.
    */
   private void showLandmarkNotification() {
      String text = getResources().getString(R.string.experiment_notif_title);
      Notification notification = new Notification(R.drawable.ic_notification,
                                                   text,
                                                   System.currentTimeMillis());
      notification.flags = Notification.FLAG_ONGOING_EVENT;
      
      String contentTitle = getString(R.string.experiment_notif_title);
      String contentText;
      if (G.isLandmarkConditionNow()) {
         contentText =
               getResources().getString(R.string.experiment_notif_now);
      } else {
         contentText =
               getResources().getString(R.string.experiment_notif_later);
      }
      Intent notificationIntent = new Intent(this, Cyclopath.class);
      notificationIntent.setAction(Constants.ACTION_SHOW_LANDMARK_NEED);
      PendingIntent contentIntent =
         PendingIntent.getActivity(this, 0, notificationIntent, 0);
      notification.setLatestEventInfo(getApplicationContext(), contentTitle,
                                      contentText, contentIntent);
      
      this.notification_manager.notify(LANDMARK_NOTIFICATION_ID, notification);
   }

   /**
    * Show a notification while this service is running.
    */
   private void showNotification() {
      String text = getString(R.string.track_notification_text);
      Notification notification = new Notification(R.drawable.ic_notification, text,
                                                   System.currentTimeMillis());
      notification.flags = Notification.FLAG_ONGOING_EVENT;
      
      String contentTitle = getString(R.string.app_name);
      String contentText = getString(R.string.track_notification_content_text);
      Intent notificationIntent = new Intent(this, Cyclopath.class);
      notificationIntent.setAction(Constants.ACTION_SHOW_TRACK_END);
      PendingIntent contentIntent =
         PendingIntent.getActivity(this, 0, notificationIntent, 0);

      notification.setLatestEventInfo(getApplicationContext(), contentTitle,
                                      contentText, contentIntent);
      
      this.notification_manager.notify(TRACKING_NOTIFICATION_ID, notification);
   }

   /**
    * Shows a landmark need prompt and notifies the user.
    */
   public void showPrompt() {
      AudioManager audio =
            (AudioManager) getSystemService(Context.AUDIO_SERVICE);
      int currentVolume =
            audio.getStreamVolume(AudioManager.STREAM_RING);
      Vibrator vib = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
      vib.vibrate(Constants.LANDMARK_VIBRATE_PATTERN, -1);
      if (currentVolume > 0) {
         Uri notification = RingtoneManager.getDefaultUri(
               RingtoneManager.TYPE_NOTIFICATION);
         Ringtone r = RingtoneManager.getRingtone(
               getApplicationContext(), notification);
         r.play();
      }
      this.showLandmarkNotification();
   }

}

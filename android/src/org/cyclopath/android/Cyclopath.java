/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Date;
import java.util.Map;

import org.cyclopath.android.conf.Conf;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.gwis.GWIS_Checkout;
import org.cyclopath.android.gwis.GWIS_CheckoutCallback;
import org.cyclopath.android.gwis.GWIS_Commit;
import org.cyclopath.android.gwis.GWIS_LandmarkExpActiveGet;
import org.cyclopath.android.gwis.GWIS_LandmarkTrialGet;
import org.cyclopath.android.gwis.GWIS_LandmarkTrialGetCallback;
import org.cyclopath.android.gwis.GWIS_RouteGetCallback;
import org.cyclopath.android.gwis.GWIS_RouteGetByHash;
import org.cyclopath.android.gwis.GWIS_ValueMapGet;
import org.cyclopath.android.gwis.QueryFilters;
import org.cyclopath.android.items.ConflationJob;
import org.cyclopath.android.items.DirectionStep;
import org.cyclopath.android.items.Feature;
import org.cyclopath.android.items.Geopoint;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.LandmarkNeed;
import org.cyclopath.android.items.MapPointer;
import org.cyclopath.android.items.Route;
import org.cyclopath.android.items.Tile;
import org.cyclopath.android.items.Track;
import org.cyclopath.android.items.TrackPoint;
import org.cyclopath.android.util.ChangeLog;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.TrackDeletionHandler;
import org.cyclopath.android.util.TrackExporter;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.NodeList;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.NotificationManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager.NameNotFoundException;
import android.graphics.drawable.AnimationDrawable;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.location.GpsStatus;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.location.LocationProvider;
import android.net.Uri;
import android.os.Bundle;
import android.os.Message;
import android.provider.Settings;
import android.text.Html;
import android.util.Log;
import android.view.ContextMenu;
import android.view.ContextMenu.ContextMenuInfo;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.View.OnClickListener;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.RelativeLayout;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.ZoomControls;

/**
 * Main Class for Cyclopath Mobile. <br>
 * Grouplens Research<br>
 * University of Minnesota
 * @author Phil Brown
 * @author Fernando Torre
 */
public class Cyclopath extends BaseActivity
                       implements LocationListener,
                                  GpsStatus.Listener,
                                  OnClickListener,
                                  TrackDeletionHandler,
                                  GWIS_RouteGetCallback,
                                  SensorEventListener,
                                  GWIS_CheckoutCallback,
                                  DialogInterface.OnClickListener,
                                  GWIS_LandmarkTrialGetCallback {
   
   /** True if the app is currently tracking GPS coordinates. 
    * Used for various features, including menu configuration.*/
   public boolean is_recording;
   /** This is used to avoid opening multiple dialogs asking the user
    * if they want to save a track. */
   public boolean stop_recording_msg_sent = false;
   
   /** Mapping of user preferences. This is derived from the XML file.*/
   protected Map<String,Boolean> saved_user_settings;
   /** Provides editing capabilities for the user settings file.*/
   protected SharedPreferences.Editor user_settings_editor;
   
   /** Provides access to location services.*/
   protected LocationManager locationManager;
   
   /** Throbber animation */
   protected AnimationDrawable throbber_anim;
   
   /** Button used to open the context menu*/
   private ImageButton contextButton;
   /** View containing directions*/
   private View directionsView;
   /** If using version 3.0 or higher, this will invoke the method
    * invalidateOptionsMenu() from Activity. */
   private static Method nullifyOptionsMenu;
   
   /** Landmarks Experiment prompt */
   AlertDialog landmark_prompt;

   /** Manager for listening to sensor updates */
   private SensorManager mSensorManager;
   /** accelerometer sensor (used for calculating orientation)*/
   private Sensor accelerometerSensor;
   /** magnetic field sensor (used for calculating orientation)*/
   private Sensor magneticFieldSensor;
   /** acceleration values returned by the accelerometer sensor */
   private float[] accelerationValues;
   /** magnetic field values returned by the magnetic field sensor */
   private float[] magneticFieldValues;
   
   /** Constant meaning that GPS location is required for some action. */
   protected static final int GPS_REQUIRED = 1;
   /** Constant meaning that GPS location is required specifically for track
    * recording. */
   protected static final int GPS_REQUIRED_RECORDING = 2;
   /** Constant meaning that Network location is required for some action. */
   protected static final int NETWORK_REQUIRED = 3;
   /** Constant meaning that both GPS and Network locations are required for
    * some action. */
   protected static final int ANY_REQUIRED = 4;
   /** Constant meaning that a track is to be discarded */
   protected static final int DISCARD = 0;
   /** Constant meaning that a track is to be saved */
   protected static final int SAVE = 1;

   // *** Request Codes (alphabetical)

   /** Request code for directions list activity */
   private static final int DIRECTION_ACTIVITY_REQUEST_CODE = 0;
   /** Request code for login activity */
   private static final int LOGIN_ACTIVITY_REQUEST_CODE = 1;
   /** Location Settings Activity Request Code for enabling GPS while 
    * recording */
   private static final int LOCATION_SETTINGS_REQUEST_CODE_MID = 2;
   /** Location Settings Activity Request Code for enabling GPS before 
    * recording */
   private static final int LOCATION_SETTINGS_REQUEST_CODE_START = 3;
   /** Track Editor Activity Request Code */
   private static final int TRACK_EDITOR_REQUEST_CODE = 4;
   /** Track Manager Activity Request Code */
   private static final int TRACK_MANAGER_REQUEST_CODE = 5;
   /** Request code for forcing the user to agree to terms of service */
   public static final int USER_MUST_AGREE = 6;
   /** Request code for viewing landmarks trial information */
   public static final int TRIAL_VIEW_CODE = 7;

   /** whether we are currently adding a landmark in the "now" condition */
   public static boolean landmark_editing_mode_now = false;
   /** whether we are currently adding landmarks in the "later" condition */
   public static boolean landmark_editing_mode_later = false;
   /** landmark trial to be retrieved */
   public static int trial_num_toget = -1;
   /** Landmark prompts currently being displayed */
   public static ArrayList<LandmarkNeed> current_prompts;
   /** Landmark prompt currently selected */
   public static int selected_prompt = -1;
   /** Landmark trial mode - before agreeing to the experiment */
   public static final int LANDMARK_MODE_INTRO = 0;
   /** Landmark trial mode - while recording a track */
   public static final int LANDMARK_MODE_RECORD = 1;
   /** Landmark trial mode - while viewing a prompt (now condition) */
   public static final int LANDMARK_MODE_ADD_NOW = 2;
   /** Landmark trial mode - while viewing prompts (later condition) */
   public static final int LANDMARK_MODE_ADD_LATER = 3;

   /**
    * This handler receives and handles messages from other threads.
    */
   @Override
   public void handleMessage(Message msg) {
       switch (msg.what) {
          case (Constants.THROBBER_CHANGED):
             this.updateThrobber();
             break;
          case (Constants.REFRESH_NEEDED):
             this.refetchMissingTiles();
             break;
          case (Constants.SAVE_FORCE_CLOSED_TRACK):
             this.saveForcedClosedTrack();
             break;
          case (Constants.SHOW_STALE_TRACK_DIALOG):
             this.stop_recording_msg_sent = true;
             this.showSaveStaleTrackDialog();
             break;
          case (Constants.STOP_RECORDING):
             if (msg.arg1 == SAVE)
                this.stopRecording(true);
             else
                this.stopRecording(false);
             break;
          case (Constants.CONFLATION_COMPLETE):
             this.refreshButtons();
             break;
          case (Constants.HIDE_LANDMARK_PROMPT):
             this.hideLandmarkPrompt();
             break;
          case (Constants.REFRESH_LANDMARK_EXPERIMENT):
             this.refreshLandmarksExperiment();
             break;
       }
   } 

   // *** Static methods
   
   /**
    * As soon as the class is loaded, populate the fields used for
    * compatibility with the appropriate values.
    */
   static {
      initCompatibility();
   };
   
   /**
    * Populates the fields used for compatibility with the appropriate values
    * using reflection.
    */
   private static void initCompatibility() {
     try {
        nullifyOptionsMenu = 
               Activity.class.getMethod("invalidateOptionsMenu");
     } catch (SecurityException e) {
         e.printStackTrace();
     } catch (NoSuchMethodException e) {
         e.printStackTrace();
     }
   }//initCompatibility
   
   /**
    * Causes the activity to call onPrepareOptionsMenu() the next time the menu
    * is opened.
    */
   private void invalidateOptionsMenu() {
      if(nullifyOptionsMenu == null) {
         return; 
      }
      try {
         if (Constants.DEBUG) {
            Log.i("cyclopath", "handling reflection of invalidateOptionsMenu");
         }
         nullifyOptionsMenu.invoke(this);
      } catch (IllegalArgumentException e) {
         e.printStackTrace();
      } catch (IllegalAccessException e) {
         e.printStackTrace();
      } catch (InvocationTargetException e) {
         e.printStackTrace();
      } 
   }//invalidateOptionsMenu
   
   // *** Listeners
    
   /**
    * This method is called when this activity returns to the surface.
    * @param requestCode Integer provided when calling the activity 
    * from this class
    * @param resultCode Integer value set by the called activity that 
    * is used to determine the state of the finished activity
    * @param data The intent returned by the popped activity
    */
   @Override
   public void onActivityResult(int requestCode,
                                int resultCode,
                                Intent data) {
      if (requestCode == TRACK_MANAGER_REQUEST_CODE
          || requestCode == TRACK_EDITOR_REQUEST_CODE) {
         this.refreshButtons();
      } else if (requestCode == LOCATION_SETTINGS_REQUEST_CODE_START) {
         startRecording(-1);
      } else if (requestCode == LOCATION_SETTINGS_REQUEST_CODE_MID) {
        if (this.is_recording && !locationManager.isProviderEnabled(
                 LocationManager.GPS_PROVIDER)) {
          checkLocationServices(GPS_REQUIRED_RECORDING);
        }
      } else if(requestCode == LOGIN_ACTIVITY_REQUEST_CODE) {
         if(resultCode == Activity.RESULT_OK) {
            this.setLoggedInTitle(true);
            G.saveUnsavedTracks(this);
         }
      } else if (requestCode == DIRECTION_ACTIVITY_REQUEST_CODE) {
         if(resultCode == Activity.RESULT_OK) {
            MapSurface.has_panned = true;
            G.map.panZoomLater(data.getDoubleExtra(Constants.DIRECTIONS_POINT_X,
                                                  G.map.new_map_x),
                               data.getDoubleExtra(Constants.DIRECTIONS_POINT_Y,
                                                  G.map.new_map_y),
                               Math.max(Constants.DIRECTIONS_ZOOM_LEVEL,
                                        G.zoom_level));
         }
      } else if (requestCode == USER_MUST_AGREE) {
         if (!G.cookie_anon.getBoolean(Constants.COOKIE_HAS_AGREED_TO_TERMS, 
                                       false)) {
            finish();
         }
      } else if (requestCode == TRIAL_VIEW_CODE) {
         if (G.user.isLoggedIn()) {
            new GWIS_LandmarkTrialGet(trial_num_toget, this).fetch();
         }
      }
   }//onActivityResult
   
   /** Anonymous implementation of OnClickListener for zoom outs.*/
   private OnClickListener zoomOutListener = new OnClickListener() {
      @Override
      public void onClick(View v) {
         G.map.onZoomOut();
      }
   };
   
   /** Anonymous implementation of OnClickListener for zoom ins.*/
   private OnClickListener zoomInListener = new OnClickListener() {
      @Override
      public void onClick(View v) {
         G.map.onZoomIn();
      }
   };
   
   /**
    * Handles sensor accuracy changes. Required method, but not used for now.
    */
   @Override
   public void onAccuracyChanged(Sensor sensor, int accuracy) {
      // do nothing
   }

   /**
    * Set the title and inflate the context menu
    */
   @Override
   public void onCreateContextMenu(ContextMenu menu, View v,
                                   ContextMenuInfo menuInfo) {
      super.onCreateContextMenu(menu, v, menuInfo);
      menu.setHeaderTitle(getString(R.string.menu));
      MenuInflater inflater = getMenuInflater();
      if (v == G.map) {
         inflater.inflate(R.menu.map_context_menu, menu);
         if (G.LANDMARKS_EXP_ON
             && (landmark_editing_mode_now
                 || landmark_editing_mode_later)) {
            menu.removeItem(R.id.route_to_here);
            menu.removeItem(R.id.route_from_here);
         } else {
            menu.removeItem(R.id.submit_point);
         }
      } else if (G.active_route == null) {
         inflater.inflate(R.menu.track_menu, menu);
         if ((G.user.isLoggedIn() && G.selected_track.hasOwner()) 
             || !G.user.isLoggedIn()) {
            menu.removeItem(R.id.add_track_owner);
         }
         if (!Constants.DEBUG) {
            menu.removeItem(R.id.conflate_track);
         }
      } else if (G.selected_track == null) {
         inflater.inflate(R.menu.route_menu, menu);
      } else {
         menu.setHeaderTitle(getString(R.string.context_menu_title));
         inflater.inflate(R.menu.context_menu, menu);
         if ((G.user.isLoggedIn() && G.selected_track.hasOwner()) 
              || !G.user.isLoggedIn()) {
            menu.findItem(R.id.tracks)
                .getSubMenu()
                .removeItem(R.id.add_track_owner);
         }
         if (!Constants.DEBUG) {
            menu.removeItem(R.id.conflate_track);
         }
      }
   }//onCreateContextMenu
   
   /**
    * Perform actions based on which context menu item is selected.
    */
   @Override
   public boolean onContextItemSelected(MenuItem item) {
      Intent intent;
      switch (item.getItemId()) {
      case R.id.view_track_details:
         intent = new Intent(this, TrackDetailsActivity.class);
         intent.putExtra(Constants.STACK_ID_STR, G.selected_track.stack_id);
         startActivity(intent);
         return true;
      case R.id.delete_track:
         G.trackDeletionHandle(G.selected_track, this, this);
         return true;
      case R.id.add_track_owner:
         G.selected_track.owner = G.user.getName();
         ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
         items.add(G.selected_track);
         new GWIS_Commit(items,
                         getResources().getString(
                               R.string.track_put_progress_dialog_title),
                         getResources().getString(
                               R.string.track_put_progress_dialog_content),
                         null).fetch();
         return true;
      case R.id.show_track:
         G.map.lookAt(G.selected_track, 0);
         return true;
      case R.id.save_track_gpx:
         new TrackExporter(G.selected_track, this).exportGPX();
         return true;
      case R.id.conflate_track:
         new ConflationJob(G.selected_track.stack_id).runJob();
         return true;
      case R.id.show_route:
         G.map.lookAt(G.active_route, 0);
         return true;
      case R.id.show_directions:
         intent = new Intent(this, DirectionsActivity.class);
         startActivityForResult(intent, DIRECTION_ACTIVITY_REQUEST_CODE);
         return true;
      case R.id.share_route:
         G.active_route.shareRoute();
         return true;
      case R.id.route_to_here:
         intent = new Intent(this, FindRouteActivity.class);
         intent.putExtra(Constants.FINDROUTE_ACTION,
                            Constants.FINDROUTE_ROUTE_TO_ACTION);
         intent.putExtra("x", G.map.long_press_map_x);
         intent.putExtra("y", G.map.long_press_map_y);
         startActivity(intent);
         return true;
      case R.id.route_from_here:
         intent = new Intent(this, FindRouteActivity.class);
         intent.putExtra(Constants.FINDROUTE_ACTION,
                              Constants.FINDROUTE_ROUTE_FROM_ACTION);
         intent.putExtra("x", G.map.long_press_map_x);
         intent.putExtra("y", G.map.long_press_map_y);
         startActivity(intent);
         return true;
      case R.id.submit_point:
         intent = new Intent(this, ItemDetailsActivity.class);
         intent.putExtra(Constants.EDIT_MODE, true);
         Geopoint g = new Geopoint(G.map.long_press_map_x,
                                   G.map.long_press_map_y);
         g.init();
         intent.putExtra(Constants.STACK_ID_STR, g.stack_id);
         startActivity(intent);
      default:
         return super.onContextItemSelected(item);
      }
   }//onContextItemSelected

   /**
    * Handles clicks.
    */
   @Override
   public void onClick(View v) {
      Intent intent;
      if (v == findViewById(R.id.directions_btn)) {
         intent = new Intent(this, DirectionsActivity.class);
         startActivityForResult(intent, DIRECTION_ACTIVITY_REQUEST_CODE);
      } else if (v == findViewById(R.id.context_button)) {
         v.showContextMenu();
      } else if (v == findViewById(R.id.prev_direction)) {
         if (G.active_route.selected_direction > 0) {
            G.active_route.selected_direction--;
         }
         this.updateDirection();
      } else if (v == findViewById(R.id.next_direction)) {
         if (G.active_route.selected_direction
               < G.active_route.directions.size() - 1) {
            G.active_route.selected_direction++;
         }
         this.updateDirection();
      } else if (v == findViewById(R.id.direction_text)) {
         this.updateDirection();
      } else if (v == findViewById(R.id.experiment_help_btn)) {
         startActivity(new Intent(this, ExperimentAgreement.class));
      } else if (v == findViewById(R.id.experiment_no_btn)) {
         SharedPreferences.Editor editor = G.cookie.edit();
         editor.putBoolean(Constants.LANDMARKS_EXP_SHOW, false);
         editor.commit();
         this.setLandmarksExperimentVisible(false);
      } else if (v == findViewById(R.id.experiment_stop_btn)) {
         // While recording a track
         this.stopRecording(true);
      } else if (v == findViewById(R.id.experiment_landmark_done_btn)) {
         // While adding a landmark (now condition)
         landmark_editing_mode_now = false;
         this.setLandmarkExperimentMode(LANDMARK_MODE_RECORD);
         G.map.featuresDiscard(Constants.LANDMARK_NEED_LAYER);
      } else if (v == findViewById(R.id.experiment_landmark_done_later_btn)) {
         // While adding a landmark (later condition)
         landmark_editing_mode_later = false;
         this.setLandmarksExperimentVisible(false);
         G.map.featuresDiscard(Constants.LANDMARK_NEED_LAYER);
         if (!this.is_recording) {
            G.map.featureDiscard(G.current_track);
            G.current_track = null;
         }
         G.map.featureDiscard(G.selected_track);
         G.selected_track = null;
         this.refreshButtons();
         current_prompts = null;
         selected_prompt = -1;
      } else if (v == findViewById(R.id.experiment_prompt_text)) {
         G.map.lookAt(current_prompts.get(selected_prompt), 0);
      } else if (v == findViewById(R.id.prev_direction_landmark)) {
         if (selected_prompt > 0) {
            selected_prompt --;
            this.updatePrompt(true);
         }
      } else if (v == findViewById(R.id.next_direction_landmark)) {
         if (selected_prompt < current_prompts.size() - 1) {
            selected_prompt ++;
            this.updatePrompt(true);
         }
      }
   }//onClick
   
   /**
    * Handles clicks within landmark prompt dialog.
    */
   @Override
   public void onClick(DialogInterface dialog, int whichButton) {
      LandmarkNeed ln = LandmarkNeed.current_need;
      G.map.lookAt(ln, 0);
      landmark_editing_mode_now = true;
      this.setLandmarkExperimentMode(LANDMARK_MODE_ADD_NOW);
   }

   /**
    * Called when the activity is first created, and does the following:<br>
    * - Makes available the values stored in res/values<br>
    * - Sets the location provider as GPS<br>
    * - Sets the content view to the custom Cyclopath map.<br>
    * - Generates a log file for writing GPS points.<br>
    * - Gets GPS points saved from previous session.<br>
    * @see org.cyclopath.android.MapSurface
    * @param saveInstanceState saved information from the last time this
    * activity was run.
    */
   @Override
   public void onCreate(Bundle in_state) {
      super.onCreate(in_state);

      // If an update is required, be sure the user has updated.
      G.checkForMandatoryUpdate();
      
      Boolean has_agreed =
         G.cookie_anon.getBoolean(Constants.COOKIE_HAS_AGREED_TO_TERMS, false);
      
      if (!has_agreed) {
         Intent intent = new Intent(this, UserAgreement.class);
         startActivityForResult(intent, USER_MUST_AGREE);
      }
      
      // show map
      setContentView(R.layout.main);
      
      // make the map canvas more easily accessible
      G.map = (MapSurface) findViewById(R.id.map_canvas);
      // retrieve bundle information
      if (in_state != null) {
         G.map.new_map_x = in_state.getDouble("map_center_x");
         G.map.new_map_y = in_state.getDouble("map_center_y");
      }
      
      this.setLoggedInTitle(false);
      
      this.user_settings_editor = G.cookie_anon.edit();
      
      this.is_recording =
         G.cookie_anon.getBoolean(Constants.COOKIE_IS_RECORDING, false);

      // Landmarks Experiment
      findViewById(R.id.experiment_help_btn).setOnClickListener(this);
      findViewById(R.id.experiment_no_btn).setOnClickListener(this);
      findViewById(R.id.experiment_stop_btn).setOnClickListener(this);
      findViewById(R.id.experiment_landmark_done_btn)
         .setOnClickListener(this);
      findViewById(R.id.experiment_landmark_done_later_btn)
         .setOnClickListener(this);
      findViewById(R.id.experiment_prompt_text).setOnClickListener(this);
      findViewById(R.id.prev_direction_landmark).setOnClickListener(this);
      findViewById(R.id.next_direction_landmark).setOnClickListener(this);
      
      ZoomControls zoom = (ZoomControls)findViewById(R.id.zoomcontrols);
      zoom.setOnZoomInClickListener(this.zoomInListener);
      zoom.setOnZoomOutClickListener(this.zoomOutListener);
      
      // Set up throbber.
      ImageView throbberImage = (ImageView) findViewById(R.id.throbber_view);
      throbberImage.setBackgroundResource(R.anim.throbber_anim);
      throbber_anim = (AnimationDrawable) throbberImage.getBackground();
      G.cyclopath_handler = new CyclopathHandler(this);
      this.updateThrobber();
      
      // Set up direction buttons
      findViewById(R.id.directions_btn).setOnClickListener(this);
      findViewById(R.id.direction_text).setOnClickListener(this);
      findViewById(R.id.prev_direction).setOnClickListener(this);
      findViewById(R.id.next_direction).setOnClickListener(this);

      this.directionsView = findViewById(R.id.directions_panel);
      
      // Set up back_to_map button
      G.map.back_to_map = (Button) findViewById(R.id.back_to_map_btn);
      G.map.back_to_map.setOnClickListener(new OnClickListener(){
         @Override
         public void onClick(View v) {
            G.map.panto(G.map.xform_x_map2cv(Constants.MAP_CENTER_X), 
                        G.map.xform_y_map2cv(Constants.MAP_CENTER_Y));
            G.map.update();
            G.map.back_to_map.setVisibility(View.GONE);
            G.map.back_to_map.setEnabled(false);
         }
      });
      
      // Set up context button
      contextButton = (ImageButton) findViewById(R.id.context_button);
      registerForContextMenu(contextButton);
      registerForContextMenu(G.map);
      contextButton.setOnClickListener(this);

      // If we came from the tracking notification, show the track
      if (getIntent().getAction().equals(Constants.ACTION_SHOW_TRACK_END)) {
         if (G.current_track == null) {
            // This happens when the main activity was force closed, but the
            // service notification was never removed.
            NotificationManager notification_manager = (NotificationManager)
                  getSystemService(Context.NOTIFICATION_SERVICE);
            notification_manager.cancel(
                  TrackingService.TRACKING_NOTIFICATION_ID);
         } else {
            this.showTrackEnd();
         }
      } else if (getIntent().getAction().equals(
            Constants.ACTION_SHOW_LANDMARK_NEED)
                 && G.LANDMARKS_EXP_ON
                 && G.isLandmarkConditionNow()) {
         this.showLandmarkPrompt();
      } else if (getIntent().getAction().equals(
            Constants.ACTION_VIEW)) {
         this.viewHandle();
      }

      this.accelerationValues = new float[3];
      this.magneticFieldValues = new float[3];
      this.mSensorManager =
         (SensorManager)getSystemService(Activity.SENSOR_SERVICE);
      this.accelerometerSensor =
         this.mSensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
      this.magneticFieldSensor =
         this.mSensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD);

      if (!G.track_save_attempted) {
         G.saveUnsavedTracks(this);
      }
      
      // If there is an unsaved track, ask the user if they want to save it.
      Track track = G.db.getForceClosedTrack();
      if (G.current_track == null
          && track != null) {
         this.is_recording = false;
         if (track.points.isEmpty()) {
            G.db.deleteTrack(track);
         } else {
            this.showSaveForceClosedTrackDialog();
         }
      }
      
      // Display "What's new" dialog if needed.
      ChangeLog cl = new ChangeLog(this);
      if (cl.firstRun() && has_agreed) {
         AlertDialog log_dialog = cl.getLogDialog();
         if (log_dialog != null) {
            log_dialog.show();
         }
      }
      
      this.stop_recording_msg_sent = false;
   }//onCreate

   /** 
    * Resume Cyclopath Activity {@link Activity}
    */
   @Override
   public void onResume() {
      super.onResume();
      
      // register for location updates
      this.registerLocationManager();

      if (!Conf.config_fetched) {
         new GWIS_ValueMapGet().fetch();
      }
      if (!G.exp_active_loaded) {
         new GWIS_LandmarkExpActiveGet().fetch();
      }
      if (!G.tags_loaded) {
         new GWIS_Checkout("tag", new QueryFilters(), this).fetch();
      }
      
      if (this.is_recording) {
         checkLocationServices(GPS_REQUIRED_RECORDING);
      }
      this.refreshButtons();
      invalidateOptionsMenu();
      mSensorManager.registerListener(this, accelerometerSensor,
                                      SensorManager.SENSOR_DELAY_UI);
      mSensorManager.registerListener(this, magneticFieldSensor,
                                      SensorManager.SENSOR_DELAY_UI);
      setLoggedInTitle(false);
      
      this.refetchMissingTiles();
      
      //Initialize the map pointer
      G.map.pointer = new MapPointer(this);
      G.map.pointer.setImage(R.drawable.map_pointer);
      G.map.pointer.setPosition(G.currentLocation());
      G.map.featureAdd(G.map.pointer);
      G.map.featuresRelabel();
      G.map.redraw();
      
      this.refreshLandmarksExperiment();
   }//onStart
   
   /**
    * Pause activiy. This method does the following:<br>
    * - Writes user settings back to {@link #user_settings user_settings} using
    * {@link #user_settings_editor user_settings_editor}
    */
   @Override
   public void onPause(){
      super.onPause();
      user_settings_editor.putBoolean(Constants.COOKIE_IS_RECORDING,
                                      this.is_recording);
      user_settings_editor.commit();
      this.mSensorManager.unregisterListener(this);
      G.map.featureDiscard(G.map.pointer);
      this.locationManager.removeUpdates(this);
   }//onStop

   /**
    * Called when activity is destroyed (not only when the activity is no
    * longer in the activity stack, but also when rotating the device)
    */
   @Override
   public void onDestroy(){
      super.onDestroy();
      G.cyclopath_handler = null;
   }

   /**
    * Creates Main Menu
    * @param menu from res/menu/main.xml
    * @return true so the menu will still work
    */
   @Override
   //Menu Events
   public boolean onCreateOptionsMenu(Menu menu) {
      super.onCreateOptionsMenu(menu);
      if (!G.LANDMARKS_EXP_ON) {
         menu.removeItem(R.id.help);
      }
      this.getMenuInflater().inflate(R.menu.main_menu, menu);
      return true;
   }//onCreateOptionsMenu

    /** Called when the GPS status has changed.
     * @param event Event that causes the status to change
     */
   @Override
   public void onGpsStatusChanged(int event) {
      this.registerLocationManager();
      if (Constants.DEBUG) {
         Log.d("gps","gps status changed");
         switch (event) {
            case GpsStatus.GPS_EVENT_FIRST_FIX:
               Log.d("gps","GPS_EVENT_FIRST_FIX");
               break;
            case GpsStatus.GPS_EVENT_SATELLITE_STATUS:
               Log.d("gps","GPS_EVENT_SATELLITE_STATUS");
               break;
            case GpsStatus.GPS_EVENT_STARTED:
               Log.d("gps","GPS_EVENT_STARTED");
               break;
            case GpsStatus.GPS_EVENT_STOPPED:
               Log.d("gps","GPS_EVENT_STOPPED");
               break;
         }
      }
   }//onGpsStatusChanged
   
   /**
    * Handles hardware search key. On pressing this key, the find route
    * activity opens.
    */
   @Override
   public boolean onKeyDown(int keyCode, KeyEvent event) {
      if (keyCode == KeyEvent.KEYCODE_SEARCH) {
         Intent intent = new Intent(this, FindRouteActivity.class);
         startActivity(intent);
      }
      return super.onKeyDown(keyCode, event);
   }//onKeyDown

   /**
    * Called when the location provider is aware that the current location is
    * different from the last one. Then it does the following:<br>
    * - Saves location to
    * {@link #saved_session_geopoints saved_session_geopoints} <br>
    * - Writes location to {@link #gps_log gps_log}
    * @param location New Location
    */
   @Override
   public void onLocationChanged(Location location) {
      if (Constants.DEBUG) {
         Log.d("location", "location changed");
      }
      
      if (this.is_recording) {
         return;
      }
      
      // This hack fixes the strange bug 2031
      location.setTime(System.currentTimeMillis());
      
      if ((this.accelerometerSensor == null
            || this.magneticFieldSensor == null)) {
         G.map.pointer.setBearing(G.last_location, location);
      }
      
      // if the location is better than the previous one, update our current
      // location
      G.last_location = G.betterLocation(G.last_location, location);
      
      G.map.pointer.setPosition(G.last_location);
      G.map.pointer.setAccuracy(G.last_location.getAccuracy());
      G.map.redraw();

      // If this is recording, the tracking service
      // will perform the logging.
      G.server_log.event("mobile/location",
         new String[][]{{"longitude",
                         Double.toString(G.last_location.getLongitude())},
                        {"latitude",
                         Double.toString(G.last_location.getLatitude())},
                        {"source",
                         G.last_location.getProvider()},
                        {"accuracy",
                         Double.toString(G.last_location.getAccuracy())}});
      if (!G.withinBounds()) {
         ((TextView) findViewById(R.id.warning_too_far))
            .setVisibility(View.VISIBLE);
      } else {
         ((TextView) findViewById(R.id.warning_too_far))
            .setVisibility(View.GONE);
         if (!MapSurface.has_panned) {
            G.map.goToLocation(G.last_location);
         }
      }
   }//onLocationChaned

   /**
    * This method is called when restarting an open activity with a new
    * intent. Currently, this happens when opening the app through a
    * notification.
    */
   @Override
   public void onNewIntent(Intent intent) {
      setIntent(intent);
      // If we came from the tracking notification, show the track
      if (getIntent().getAction().equals(Constants.ACTION_SHOW_TRACK_END)) {
         this.showTrackEnd();
      } else if (getIntent().getAction().equals(
                  Constants.ACTION_SHOW_LANDMARK_NEED)
                 && G.LANDMARKS_EXP_ON
                 && G.isLandmarkConditionNow()) {
         this.showLandmarkPrompt();
      } else if (getIntent().getAction().equals(
            Constants.ACTION_VIEW)){
         this.viewHandle();
      }
   }

   /**
    * Called when a menu button is pressed. Based on which button is pressed,
    * either a method will be called or some commands will be run. For instance,
    * 'My Location' pans the map to the current location. 'start_record' begins
    * recording GPS locations, and 'stop_record' stops the recording.
    * @param item The button item selected
    * @return true so the menu will still work
    * @see Settings
    */
   @Override
   public boolean onOptionsItemSelected(MenuItem item) {
      if (item.getGroupId() == R.id.tile_options) {
         // aerial tiles
         if (item.getItemId() == G.aerial_state) {
            return true;
         }
         G.aerial_state = item.getItemId();
         item.setChecked(true);
         G.map.tiles_refetch_aerial();
         return true;
      }
      switch (item.getItemId()) {
         case R.id.login: {
            if (G.user.isLoggedIn()) {
               // TODO: In the future, once users can save stuff, make sure
               // to warn users if they have unsaved changes before they log
               // out.
               G.user.logout();
               this.setLoggedInTitle(true);
               this.clearMap();
            } else {
               Intent intent = new Intent(this, LoginActivity.class);
               startActivityForResult(intent, LOGIN_ACTIVITY_REQUEST_CODE);
            }
            invalidateOptionsMenu();
            return true;
         }
         case R.id.manage_tracks: {
            //start Track Manager activity
            startActivityForResult(new Intent(this, TrackManager.class), 
                                   TRACK_MANAGER_REQUEST_CODE);
            return true;
         }
         case R.id.route_library: {
            //start Route Library activity
            startActivity(new Intent(this, RouteLibrary.class));
            return true;
         }
         case R.id.my_location: {
            //Pan map canvas to location
            Location loc = G.currentLocation();
            if (loc == null) {
               return false;
            }
            MapSurface.has_panned = false;
            G.map.goToLocation(loc);
            G.map.pointer.setPosition(loc);
            G.map.redraw();
            return true;
         }
         case R.id.start_record: {
            if (G.LANDMARKS_EXP_ON) {
               G.landmark_condition = Constants.LANDMARK_CONDITION_NONE;
            }
            startRecording(-1);
            return true;
         }
         case R.id.stop_record: {
            stopRecording(true);
            return true;
         }
         case R.id.find_route: {
            Intent intent = new Intent(this, FindRouteActivity.class);
            startActivity(intent);
            return true;
         }
         case R.id.clear_map: {
            // clear routes and tracks
            this.clearMap();
            invalidateOptionsMenu();
            return true;
         }
         case R.id.about: {
            this.handleAbout();
            return true;
         }
         case R.id.help: {
            startActivity(new Intent(this, ExperimentAgreement.class));
            return true;
         }
      }
      return false;
   }//onOptionsItemSelected

   /**
    * This method is called before
    * {@link #onCreateOptionsMenu(Menu) onCreateOptionsMenu} to make changes
    * to the displayed menu, based on the boolean value
    * {@link #is_recording is_recording}.
    * @param menu The menu that is being changed
    * @return true so the menu will still work
    */
   @Override
   public boolean onPrepareOptionsMenu(Menu menu) {
      //If currently recording, disable and hide the record button, enable and 
      //show the stop button. Otherwise, disable and hide the stop button and
      // enable and show the start button
      menu.findItem(R.id.start_record).setEnabled(!this.is_recording
                                                   && G.withinBounds())
                                      .setVisible(!this.is_recording);
      menu.findItem(R.id.stop_record).setEnabled(this.is_recording)
                                     .setVisible(this.is_recording);
      menu.findItem(R.id.clear_map).setEnabled(
            G.selected_track != null
            || G.active_route != null
            || !G.map.layerIsEmpty(Constants.TRACK_LAYER));
      menu.findItem(R.id.my_location)
          .setEnabled(G.withinBounds());
      if (G.user.isLoggedIn()) {
         menu.findItem(R.id.login).setTitle(R.string.logout);
      }
      else {
         menu.findItem(R.id.login).setTitle(R.string.login);
      }
      if (menu.findItem(R.id.aerial_tiles).getSubMenu().size() == 0) {
         // Populate submenu for aerial tiles.
         menu.findItem(R.id.aerial_tiles)
                        .getSubMenu()
                        .add(R.id.tile_options, -1, Menu.NONE,
                             R.string.aerial_off)
                        .setChecked(!G.aerialStateOn());
         for (int i = 0; i < Constants.PHOTO_LAYERS.length; i++) {
            menu.findItem(R.id.aerial_tiles)
                           .getSubMenu()
                           .add(R.id.tile_options, i, Menu.NONE,
                                Constants.PHOTO_LAYERS[i][1])
                           .setChecked(G.aerial_state == i);
         }
         menu.findItem(R.id.aerial_tiles)
                        .getSubMenu()
                        .setGroupCheckable(R.id.tile_options, true, true);
      }
      
      return super.onPrepareOptionsMenu(menu);
   }//onPrepareOptionsMenu
      
   /**
    * Called when the location provider is disabled
    * @param provider Location Provider
    */
   @Override
   public void onProviderDisabled(String provider) {
      if (this.is_recording) {
         checkLocationServices(GPS_REQUIRED_RECORDING);
      }
      if (Constants.DEBUG) {
         Log.d("gps","location provider disabled: " + provider);
      }
   }//onProviderDisabled

   /**
    * Called when the location provider is enabled
    * @param provider Location Provider
    */
   @Override
   public void onProviderEnabled(String provider) {
      this.registerLocationManager();
      if (Constants.DEBUG) {
         Log.d("gps","gps provider enabled: " + provider);
      }
   }//onProviderEnabled
   
   /**
    * Called when the activity is about to be stopped in order to allow saving
    * state information for the app.
    */
   @Override
   protected void onSaveInstanceState(Bundle out_state) {
      super.onSaveInstanceState(out_state);
      if (G.map.view_rect != null) {
         out_state.putDouble("map_center_x", G.map.view_rect.getMap_center_x());
         out_state.putDouble("map_center_y", G.map.view_rect.getMap_center_y());
      } else {
         out_state.putDouble("map_center_x", G.map.new_map_x);
         out_state.putDouble("map_center_y", G.map.new_map_y);
      }
   }

   /**
    * Updates the map pointer's orientation based on new sensor values.
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
      }
      Float o = G.getOrientation(accelerationValues, magneticFieldValues);
      if (o != null) {
         if (G.map.pointer.setBearing(o)) {
            G.map.redraw();
         }
      }
   }

   /**
    * Called when the location provider status changes.
    * @param provider Location Provider
    * @param extras
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
   }//onStatusChanged

   /**
    * Starts or stops the throbber whenever the number of requests that require
    * the throbber to run changes.
    */
   public void updateThrobber() {
      ImageView throbberImage = (ImageView) findViewById(R.id.throbber_view);
      if (G.requests_created == 0) {
         throbberImage.setVisibility(View.INVISIBLE);
         throbber_anim.stop();
      } else {
         throbberImage.setVisibility(View.VISIBLE);
         throbber_anim.start();
      }
   }//onThrobberChanged

   // *** Other methods

   /**
    * Creates an alert message allowing a user to update Location settings to
    * enable GPS.
    * @param message The message that shows why, or for which process, GPS is
    * necessary.
    */
   public boolean checkLocationServices(int required){
      String title = "";
      String message = "";
      boolean gps_required = false;
      String positive_btn =
         getResources().getString(R.string.location_services_enable_btn);
      String negative_btn =
         getResources().getString(R.string.location_services_cancel_btn);
      if (required == GPS_REQUIRED) {
         title = getResources().getString(R.string.gps_default_title);
         message = getResources().getString(R.string.gps_required_default);
         gps_required = true;
      } else if (required == GPS_REQUIRED_RECORDING){
         title = getResources().getString(R.string.gps_default_title);
         message =
            getResources().getString(R.string.gps_required_for_recording);
         if (this.is_recording) {
            message = getResources().getString(
                  R.string.gps_disabled_while_recording_message);
            negative_btn =
               getResources().getString(R.string.location_services_save_btn);
         }
         gps_required = true;
      } else if (required == ANY_REQUIRED) {
         title = getResources()
                     .getString(R.string.location_provider_required_title);
         message = getResources()
                     .getString(R.string.location_provider_required_message);
      }
      if ((gps_required &&
           !locationManager.isProviderEnabled(
                 LocationManager.GPS_PROVIDER))
          || (!gps_required &&
              !locationManager.isProviderEnabled(
                    LocationManager.NETWORK_PROVIDER))) {
         new AlertDialog.Builder(this)
            .setMessage(message)
            .setTitle(title)
            .setNegativeButton(negative_btn,
                               new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton){
                 if (is_recording) {
                   stopRecording(true);
                 }
                 dialog.dismiss();
               }
            })
            .setPositiveButton(positive_btn,
                              new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton){
                  int request;
                  if (is_recording) {
                     request = LOCATION_SETTINGS_REQUEST_CODE_MID;
                  } else {
                     request = LOCATION_SETTINGS_REQUEST_CODE_START;
                  }
                  startActivityForResult(
                        (new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)),
                        request);
                  dialog.dismiss();
               }
            }).show();
         return false;
      }
      return true;
   }//checkLocationServices
   
   /**
    * Clears routes and tracks from the map.
    */
   public void clearMap() {
      G.map.featureDiscard(G.active_route);
      G.active_route = null;
      if (!this.is_recording) {
         G.map.featureDiscard(G.current_track);
         G.current_track = null;
      }
      G.map.featuresDiscard(Constants.TRACK_LAYER);
      G.selected_track = null;
      if (!this.is_recording) {
         G.map.featuresDiscard(Constants.TRACK_RECORDING_LAYER);
      }
      this.refreshButtons();
      G.map.redraw();
   }
   
   /** Handles deleting a track.
    * @param track Track object that is selected. Can be null.*/
   @Override
   public void deleteTrack(Track track) {
      // delete on server
      track.deleted = true;
      ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
      items.add(track);
      new GWIS_Commit(items,"","", null).fetch();
      G.map.redraw();
      this.refreshButtons();
      Toast.makeText(this, getString(R.string.track_deleted),
                     Toast.LENGTH_SHORT).show();
   }

   /**
    * Shows the "about this app" dialog
    */
   public void handleAbout(){
      LayoutInflater li = LayoutInflater.from(this);
      View view = li.inflate(R.layout.about, null);
      AlertDialog.Builder builder = new AlertDialog.Builder(this);
      builder.setView(view);
      builder.setIcon(R.drawable.ic_dialog);
      final AlertDialog dialog = builder.create();
      dialog.show();
      
      TextView app_version = 
            (TextView) dialog.findViewById(R.id.about_version);
      Button user_agreement = 
            (Button) dialog.findViewById(R.id.terms_of_service);
      try {
         app_version.setText(getPackageManager()
                             .getPackageInfo(getPackageName(), 0)
                             .versionName);
      } catch (NameNotFoundException e) {
         /* This statement should never be reached.*/
         Log.d("manifest", "version name not found");
      }
      user_agreement.setOnClickListener(new OnClickListener(){
         @Override
         public void onClick(View v) {
            Intent intent = new Intent(getApplicationContext(), 
                                       UserAgreement.class);
            startActivity(intent);
            dialog.dismiss();
         }
      }); 
   }//handleAbout
   
   /**
    * Handle retrieved tags and tracks.
    */
   @Override
   public void handleGWIS_CheckoutComplete(ArrayList<ItemUserAccess> items) {
      if (items.get(0).getItemTypeId() == ItemType.TRACK) {
         Track t = (Track) items.get(0);
         G.map.featureDiscard(G.selected_track);
         G.selected_track = t;
         G.map.featureAdd(G.selected_track);
         G.map.lookAt(G.selected_track, 0);
      } else {
         G.tags_loaded = true;
      }
   }

   /**
    * Handles landmark trial information.
    */
   @Override
   public void handleGWIS_LandmarkTrialGetComplete(Document results) {
   
      NodeList conditions = results.getElementsByTagName("lmrk_trial");
      NamedNodeMap atts = conditions.item(0).getAttributes();
      int trial_num = XmlUtils.getInt(atts, "trial_num", -1);
   
      if (trial_num >= 0) {
         // New trial
         G.landmark_condition = atts.getNamedItem("cond").getNodeValue();
         this.startRecording(trial_num);
         this.setLandmarkExperimentMode(LANDMARK_MODE_RECORD);
         G.server_log.event("mobile/landmarks",
               new String[][]{{"trial_start",
                               "t"}});
      } else {
         // Old trial. View track and prompts on map.
         String condition = atts.getNamedItem("cond").getNodeValue();
         if (condition.equals("later")) {
            // request track
            TrackManager.submitGetTrackQuery(
                  XmlUtils.getInt(atts, "tid", -1), this);
            // populate prompt locations on the map
            NodeList prompts = results.getElementsByTagName("prompt");
            NamedNodeMap patts;
            current_prompts = new ArrayList<LandmarkNeed>();
            for (int i=0; i < prompts.getLength(); i++) {
               patts = prompts.item(i).getAttributes();
               PointD p = G.coordsStringToPoint(
                     XmlUtils.getString(patts, "geometry", "")).get(0);
               LandmarkNeed ln =
                     new LandmarkNeed(XmlUtils.getInt(atts, "nid", -1), p);
               current_prompts.add(ln);
               G.map.featureAdd(ln);
            }
            selected_prompt = 0;
            this.updatePrompt(false);
            landmark_editing_mode_later = true;
            this.refreshLandmarksExperiment();
         }
      }
   }

   /**
    * Handles route requests that are created through shared links
    */
   @Override
   public void handleGWIS_RouteGetComplete(Route r) {
      G.setActiveRoute(r);
      this.refreshButtons();
   }//handleGWIS_RouteGetComplete

   /**
    * Hides the notification in the status bar regarding landmark need.
    */
   public void hideLandmarkNeedNotification() {
      NotificationManager notif_manager = 
         (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
      notif_manager.cancel(TrackingService.LANDMARK_NOTIFICATION_ID);
   }

   /**
    * Hides the landmark prompt currently being displayed, if any.
    */
   public void hideLandmarkPrompt() {
      if (this.landmark_prompt != null) {
         this.landmark_prompt.hide();
      }
   }

   /**
    * Refetches tiles that were not previously loaded (usually because of
    * connection problems).
    */
   public void refetchMissingTiles() {
      if (G.layers.get(Constants.TILE_LAYER) != null) {
         ArrayList<Feature> tiles =
               G.layers.get(Constants.TILE_LAYER).children;
         for (int i = tiles.size()-1; i >= 0; i--) {
            Tile t = (Tile) tiles.get(i);
            if (t.image == null) {
               t.fetch_tile();
            }
         }
      }
   }

   public void refreshButtons() {
      // context button
      if (G.selected_track != null
          || G.active_route != null) {
         this.contextButton.setVisibility(View.VISIBLE);
         this.contextButton.setEnabled(true);
      } else {
         this.contextButton.setVisibility(View.GONE);
         this.contextButton.setEnabled(false);
      }
      // directions button
      if (G.active_route != null) {
         if(G.active_route.directions != null
               && !G.active_route.directions.isEmpty()){
            findViewById(R.id.next_direction).setEnabled(true);
            findViewById(R.id.prev_direction).setEnabled(true);
            if (G.active_route.selected_direction == 0) {
               findViewById(R.id.prev_direction).setEnabled(false);
            }
            if (G.active_route.selected_direction
                  == G.active_route.directions.size() - 1) {
               findViewById(R.id.next_direction).setEnabled(false);
            }
            DirectionAdapter.setViewValues(
                  G.active_route.directions.get(
                        G.active_route.selected_direction),
                  (ImageView) findViewById(R.id.direction_img),
                  (TextView)  findViewById(R.id.direction_text),
                  (TextView)  findViewById(R.id.direction_distance));
            this.directionsView.setEnabled(true);
            this.directionsView.setVisibility(View.VISIBLE);
         } else {
            this.directionsView.setEnabled(false);
            this.directionsView.setVisibility(View.GONE);
         }
      } else {
         this.directionsView.setEnabled(false);
         this.directionsView.setVisibility(View.GONE);
      }
   }
   
   /**
    * Refreshes the landmarks experiment bar at the bottom.
    */
   public void refreshLandmarksExperiment() {
      if (G.LANDMARKS_EXP_ON) {
         if (landmark_editing_mode_now) {
            this.setLandmarkExperimentMode(LANDMARK_MODE_ADD_NOW);
         } else if (landmark_editing_mode_later) {
            this.setLandmarkExperimentMode(LANDMARK_MODE_ADD_LATER);
         } else if (this.is_recording
               && G.landmark_condition != Constants.LANDMARK_CONDITION_NONE
               && G.landmark_condition != Constants.LANDMARK_CONDITION_NOUSR) {
            this.setLandmarkExperimentMode(LANDMARK_MODE_RECORD);
         } else if (G.cookie.getBoolean(Constants.LANDMARKS_EXP_SHOW, true)) {
            this.setLandmarkExperimentMode(LANDMARK_MODE_INTRO);
         } else {
            this.setLandmarksExperimentVisible(false);
         }
      } else {
         this.setLandmarksExperimentVisible(false);
      }
   }
   
   /**
    * Registers location manager for location updates.
    */
   public void registerLocationManager() {
      this.locationManager = 
         (LocationManager) this.getSystemService(Context.LOCATION_SERVICE);
      
      if (this.locationManager.isProviderEnabled(
            LocationManager.NETWORK_PROVIDER)) {
         this.locationManager.requestLocationUpdates(
               LocationManager.NETWORK_PROVIDER,
               Constants.MAIN_NETWORK_TIME_BETWEEN_UPDATES,
               Constants.MIN_DISTANCE_BETWEEN_UPDATES, this);
      }
      if (this.locationManager.isProviderEnabled(
            LocationManager.GPS_PROVIDER)) {
         this.locationManager.requestLocationUpdates(
               LocationManager.GPS_PROVIDER,
               Constants.MAIN_GPS_TIME_BETWEEN_UPDATES,
               Constants.MIN_DISTANCE_BETWEEN_UPDATES, this);
      }
   }
   
   /**
    * Opens a track that was force closed for saving.
    */
   public void saveForcedClosedTrack() {
      Track t = G.db.getForceClosedTrack();
      G.current_track = t;
      G.map.featureAdd(t);
      G.map.redraw();
      t.date = t.points.get(t.points.size()-1).getTimestamp();
      Intent editor_intent = new Intent(this, TrackDetailsActivity.class);
      editor_intent.putExtra(Constants.EDIT_MODE, true);
      editor_intent.putExtra(Constants.STACK_ID_STR, t.stack_id);
      editor_intent.putExtra(Constants.TRACK_IS_NEW, true);
      startActivityForResult(editor_intent,
                             TRACK_EDITOR_REQUEST_CODE);
   }
   
   /**
    * Changes the bottom landmarks experiment bar depending on what mode
    * the user is in.
    */
   public void setLandmarkExperimentMode(int mode) {
      this.setLandmarksExperimentVisible(true);
      //landmark_editing_mode = editing;
      findViewById(R.id.experiment_panel_intro_mode).setVisibility(View.GONE);
      findViewById(R.id.experiment_panel_record_mode).setVisibility(View.GONE);
      findViewById(R.id.experiment_panel_now_mode).setVisibility(View.GONE);
      findViewById(R.id.experiment_panel_later_mode).setVisibility(View.GONE);
      switch (mode) {
         case (LANDMARK_MODE_INTRO):
            findViewById(R.id.experiment_panel_intro_mode)
               .setVisibility(View.VISIBLE);
            break;
         case (LANDMARK_MODE_RECORD):
            // set appropriate text
            TextView t = (TextView) findViewById(
                  R.id.experiment_panel_record_text);
            if (G.isLandmarkConditionNow()) {
               t.setText(Html.fromHtml(
                     this.getResources().getString(
                           R.string.experiment_instructions_now)));
            } else {
               t.setText(Html.fromHtml(
                     this.getResources().getString(
                           R.string.experiment_instructions_later)));
            }
            findViewById(R.id.experiment_panel_record_mode)
               .setVisibility(View.VISIBLE);
            break;
         case (LANDMARK_MODE_ADD_NOW):
            findViewById(R.id.experiment_panel_now_mode)
               .setVisibility(View.VISIBLE);
            break;
         case (LANDMARK_MODE_ADD_LATER):
            findViewById(R.id.experiment_panel_later_mode)
               .setVisibility(View.VISIBLE);
            break;
      }
   }

   /**
    * Shows or hides the Landmarks Experiment bar.
    * @param visible
    */
   public void setLandmarksExperimentVisible(boolean visible) {
      RelativeLayout.LayoutParams zoomParams =
            (RelativeLayout.LayoutParams)
               findViewById(R.id.zoomcontrols).getLayoutParams();
      RelativeLayout.LayoutParams contextParams =
            (RelativeLayout.LayoutParams)
            findViewById(R.id.context_button).getLayoutParams();
      if (visible) {
         findViewById(R.id.experiment_panel).setVisibility(View.VISIBLE);
         zoomParams.addRule(RelativeLayout.ALIGN_PARENT_BOTTOM, 0);
         zoomParams.addRule(RelativeLayout.ABOVE, R.id.experiment_panel);
         contextParams.addRule(RelativeLayout.ALIGN_PARENT_BOTTOM, 0);
         contextParams.addRule(RelativeLayout.ABOVE, R.id.experiment_panel);
      } else {
         findViewById(R.id.experiment_panel).setVisibility(View.GONE);
         zoomParams.addRule(RelativeLayout.ALIGN_PARENT_BOTTOM, 1);
         contextParams.addRule(RelativeLayout.ALIGN_PARENT_BOTTOM, 1);
      }
      findViewById(R.id.zoomcontrols).setLayoutParams(zoomParams);
      findViewById(R.id.context_button).setLayoutParams(contextParams);
   }

   /**
    * Sets the title of the application depending on whether the user is
    * logged in or not.
    */
   public void setLoggedInTitle(boolean showToast) {
      String toast_msg;
      int duration = Toast.LENGTH_SHORT;

      if (G.user.isLoggedIn()) {
         setTitle(getResources().getString(R.string.logged_in_title)
                  + " "
                  + G.user.getName());
         toast_msg = getResources().getString(R.string.logged_in_toast)
                     + " " + G.user.getName() + ".";
      } else {
         setTitle(getResources().getString(R.string.logged_out_title));
         toast_msg = getResources().getString(R.string.logged_out_toast);
      }
      if (showToast) {
         Toast.makeText(this, toast_msg, duration).show();
      }
   }//setLoggedInTitle
   
   /**
    * Shows the prompt for the current landmark need.
    * @param id
    */
   public void showLandmarkPrompt() {
      G.server_log.event("mobile/landmarks",
            new String[][]{{"prompt_show",
                            "t"}});
      this.landmark_prompt = 
         new AlertDialog.Builder(this).setMessage(
            getResources().getString(R.string.experiment_prompt_text))
                                      .setTitle(
            getResources().getString(R.string.experiment_prompt_title))
            .setNegativeButton(getResources().getString(
                                 R.string.experiment_prompt_no),
                               new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton) {
                  hideLandmarkNeedNotification();
               }
            })
            .setPositiveButton(getResources().getString(
                                 R.string.experiment_prompt_yes),
                               new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton) {
                  LandmarkNeed ln = LandmarkNeed.current_need;
                  if (ln != null) {
                     G.map.lookAt(ln, 0);
                     landmark_editing_mode_now = true;
                     setLandmarkExperimentMode(LANDMARK_MODE_ADD_NOW);
                  }
               }
            }).create();
      this.landmark_prompt.show();
   }

   /*
    * Show dialog for saving track if the app was force closed.
    */
   public void showSaveForceClosedTrackDialog() {
      String message = 
         getResources().getString(R.string.track_forced_close_message);
      String title = 
         getResources().getString(R.string.track_forced_close_title);
      String save = getResources().getString(R.string.save);
      String discard = getResources().getString(R.string.discard);
      new AlertDialog.Builder(this).setMessage(message).setTitle(title)
         .setNegativeButton(discard, new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton) {
               G.db.deleteTrack(G.db.getForceClosedTrack());
            }})
         .setPositiveButton(save, new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton) {
               if (G.cyclopath_handler != null) {
                  Message msg = Message.obtain();
                  msg.what = Constants.SAVE_FORCE_CLOSED_TRACK;
                  msg.setTarget(G.cyclopath_handler);
                  msg.sendToTarget();
               }
            }}).show();
   }
   
   /*
    * Show dialog for saving stale track.
    */
   public void showSaveStaleTrackDialog() {
      String message = getResources().getString(R.string.track_stale_message);
      String title = getResources().getString(R.string.track_stale_title);
      String save = getResources().getString(R.string.save);
      String discard = getResources().getString(R.string.discard);
      new AlertDialog.Builder(this).setMessage(message).setTitle(title)
         .setNegativeButton(discard, new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton) {
               if (G.cyclopath_handler != null) {
                  Message msg = Message.obtain();
                  msg.what = Constants.STOP_RECORDING;
                  msg.arg1 = DISCARD;
                  msg.setTarget(G.cyclopath_handler);
                  msg.sendToTarget();
               }
            }})
         .setPositiveButton(save, new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton) {
               if (G.cyclopath_handler != null) {
                  Message msg = Message.obtain();
                  msg.what = Constants.STOP_RECORDING;
                  msg.arg1 = SAVE;
                  msg.setTarget(G.cyclopath_handler);
                  msg.sendToTarget();
               }
            }}).show();
   }
   
   /**
    * Shows the end of a track when entering this activity.
    */
   public void showTrackEnd() {
      MapSurface.has_panned = false;
      if (G.current_track == null) {
         return;
      }
      int size = G.current_track.points.size();
      if (size > 0) {
         TrackPoint last_point = G.current_track.getTrackPoint(size - 1);
         G.map.panZoomLater(last_point.x, last_point.y, G.zoom_level);
      }
   }//showTrackEnd

   /**
    * Start recording tracks.
    */
   public void startRecording(int trial_num) {
      boolean ready = checkLocationServices(GPS_REQUIRED_RECORDING);
      if (ready) {
         // send landmarks trial request
         if (G.LANDMARKS_EXP_ON
               && G.landmark_condition == Constants.LANDMARK_CONDITION_NONE
               && G.user.isLoggedIn()
               && G.cookie.getLong(Constants.LANDMARKS_EXP_AGREE, 0)
                  > (new Date()).getTime()) {
            new GWIS_LandmarkTrialGet(this).fetch();
         } else {
            // clear tracks
            G.map.featuresDiscard(Constants.TRACK_LAYER);
            G.map.redraw();
            this.is_recording = true;
            invalidateOptionsMenu();
            MapSurface.has_panned = false;
            Intent intent = new Intent(this, TrackingService.class);
            intent.putExtra("trial_num", trial_num);
            startService(intent);
            Toast.makeText(this,
                           R.string.track_notification_text,
                           Toast.LENGTH_SHORT).show();
         }
      }
   }//startRecording
   
   /**
    * Stop recording tracks
    */
   public void stopRecording(boolean save) {
      if (G.LANDMARKS_EXP_ON) {
         this.setLandmarksExperimentVisible(false);
         this.hideLandmarkPrompt();
      }
      Intent intent = new Intent(this, TrackingService.class);
      stopService(intent);
      this.is_recording = false;
      invalidateOptionsMenu();
      if (G.current_track == null){
         return;
      }
      if (G.current_track.points.size() < 2 || !save) {
         G.map.featureDiscard(G.current_track);
         // Set to false after discarding. Otherwise, discard doesn't work.
         G.current_track.recording = false;
         G.db.deleteTrack(G.current_track);
         if (G.current_track.points.size() < 2) {
            G.current_track = null;
            Toast.makeText(this,
                           getResources().getString(R.string.track_too_short),
                           Toast.LENGTH_SHORT).show();
         }
         G.landmark_condition = Constants.LANDMARK_CONDITION_NONE;
         return;
      } else {
         G.current_track.date = new Date();
         Intent editor_intent = new Intent(this, TrackDetailsActivity.class);
         editor_intent.putExtra(Constants.TRACK_IS_NEW, true);
         editor_intent.putExtra(Constants.EDIT_MODE, true);
         editor_intent.putExtra(Constants.STACK_ID_STR,
                                G.current_track.stack_id);
         startActivityForResult(editor_intent,
                                TRACK_EDITOR_REQUEST_CODE);
      }
   }//stopRecording
   
   /**
    * Updates the current direction and pans the map its location.
    */
   public void updateDirection() {
      this.refreshButtons();
      MapSurface.has_panned = true;
      DirectionStep step =
         G.active_route.directions.get(G.active_route.selected_direction);
      G.map.panto(G.map.xform_x_map2cv(step.start_point.x),
                  G.map.xform_y_map2cv(step.start_point.y));
      G.map.zoomto(Math.max(Constants.DIRECTIONS_ZOOM_LEVEL,
                            G.zoom_level));
   }

   /**
    * Handles what happens when a different prompt is selected.
    */
   public void updatePrompt(boolean lookat) {
      for (int i = 0; i < current_prompts.size(); i++) {
         if (i == selected_prompt) {
            current_prompts.get(i).selected = true;
         } else {
            current_prompts.get(i).selected = false;
         }
      }
      if (lookat) {
         G.map.lookAt(current_prompts.get(selected_prompt), 0);
      }
      ((TextView)findViewById(R.id.experiment_prompt_text)).setText(
            String.format(this.getResources().getString(
                             R.string.experiment_prompt_bar_text),
                          selected_prompt + 1,
                          current_prompts.size()));
   }
   
   /**
    * Shows a feature shared by email. Or, if a link is opened without a 
    * shared feature (such as a link to magic.cyclopath.org, simply open the
    * map.
    */
   public void viewHandle() {
      Uri uri = getIntent().getData();
      String url = uri.getFragment();
      if (url == null) {
         return;
      }
      String[] params = url.split("=");
      if (params.length > 1) {
         if (params[0].equals("route_shared?id")) {
            String hash_id = params[params.length-1];
            new GWIS_RouteGetByHash(hash_id, "android_top", 
                                       this).fetch();
         } else if (params[0].equals("landmarks?trial")) {
            G.server_log.event("mobile/landmarks",
                  new String[][]{{"deeplink_open",
                                  "t"}});
            trial_num_toget = Integer.valueOf(params[1]);
            if (!G.user.isLoggedIn()) {
               Intent intent = new Intent(this, LoginActivity.class);
               startActivityForResult(intent, TRIAL_VIEW_CODE);
            } else {
               new GWIS_LandmarkTrialGet(trial_num_toget, this).fetch();
            }
         }
      }
   }

}//Cyclopath

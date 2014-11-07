/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.conf;

import java.text.SimpleDateFormat;
import java.util.TimeZone;
import java.util.regex.Pattern;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.util.Bearing;

import android.annotation.SuppressLint;
import android.graphics.Color;

/**
 * Configurations and defaults.
 * @author Fernando Torre
 * @author Phil Brown
 * @author Yanjie Liu
 */
public class Constants {
      
   /**
    * Current gwis protocol version of this client (If this is different than
    * the server value, an update is required to continue using the
    * application.
    */
   public static int gwis_version = 3;
   
   // ********** Instance-specific config variables
   // TODO: move to another file?

   /** The name of this instance.*/
   //public static String INSTANCE_NAME = "minnesota";
   public static String INSTANCE_NAME = "minnesota-2500677-bikeways";
   
   // Defaults for these map parameters.
   /** the default zoom */
   public static int MAP_ZOOM = 10;
   /** the x coordinate for the map's starting position (in map coordinates) */
   public static int MAP_CENTER_X = 485572;
   /** the y coordinate for the map's starting position (in map coordinates) */
   public static int MAP_CENTER_Y = 4979716;
   /** Approximate left edge of the Minnesota map in lat/long coordinates*/
   public static double MAP_LATLON_LEFT_EDGE = -97.2;
   /** Approximate right edge of the Minnesota map in lat/long coordinates*/
   public static double MAP_LATLON_RIGHT_EDGE = -89.2;
   /** Approximate top edge of the Minnesota map in lat/long coordinates*/
   public static double MAP_LATLON_TOP_EDGE = 49.3;
   /** Approximate bottom edge of the Minnesota map in lat/long coordinates*/
   public static double MAP_LATLON_BOTTOM_EDGE = 43.3;
   /** Approximate right edge of the Minnesota map in map coordinates*/
   public static int MAP_RECT_RIGHT = 630861;
   /** Approximate left edge of the Minnesota map in map coordinates*/
   public static int MAP_RECT_LEFT = 321554;
   /** Approximate top edge of the Minnesota map in map coordinates*/
   public static int MAP_RECT_TOP = 5462365;
   /** Approximate bottom edge of the Minnesota map in map coordinates*/
   public static int MAP_RECT_BOTTOM = 4796480;
   /** Distance in lat/lon used as a buffer around map limits. */
   public static double MAP_LATLON_BUFFER = 0.5;
   
   /** Photo layers available for aerial viewing */
   public static final String[][] PHOTO_LAYERS = new String[][] {
         {"met10",   "2010 Color High-Res"}, // Twin Cities
         {"fsa2010", "2010 Color Low-Res"},  // State-wide
         {"fsa2009", "2009 Color Low-Res"},  // State-wide
         {"fsa2008", "2008 Color Low-Res"},  // State-wide
         {"msp2006", "2006 Color High-Res"}, // Twin Cities
         {"metro",   "2004 Color High-Res"}, // Twin Cities
         {"fsa",     "2003 Color Low-Res"},  // State-wide
         {"bw2000",  "2000 B&W Medium-Res"}, // Twin Cities
         {"bw1997",  "1997 B&W Medium-Res"}, // Twin Cities
         {"doq",     "1991-92 B&W Low-Res"}  // ???
         };
   
   /** spatial reference system ID for this map (used when requesting tiles)*/
   public static int SRID = 26915;
   
   // ********** Standard config variables
   
   // *** URLs
   
   /** URL for general Cyclopath services */
   public static final String GWIS_URL = "/gwis?";
   /** URL for Cyclopath tiles service */
   public static final String WMS_URL_CYCLOPATH = "/tilec?";
   /** server url */
   public static final String SERVER_URL = CONFIG.SERVER_URL;
   /** URL for aerial tiles service */
   public static String WMS_URL_AERIAL
                              = "http://geoint.lmic.state.mn.us/cgi-bin/wms?";
   /** URL for creating user accounts */
   public static String CREATE_ACCOUNT_URL =
      "http://cyclopath.org/mediawiki/index.php?title=Special:UserLogin&type=signup";
   /** URL for users to retrieve their passwords */
   public static String FORGOT_PASSWORD_URL =
      "http://cyclopath.org/wiki/Forgot_Password";
   /** Uri used to launch the Android Market with a search for Cyclopath */
   public static final String MARKET_DETAILS = 
      "market://details?id=org.cyclopath.android";
   /** URL for the Cyclopath User Agreement*/
   public static final String AGREEMENT_URL =
      "http://cyclopath.org/wiki/User_Agreement";
   /** Base URL for making bit.ly requests*/
   public static final String BITLY_URL_BASE_START = 
	   "http://api.bit.ly/v3/shorten?";
   /** login for making bit.ly requests*/
   public static String BITLY_LOGIN = CONFIG.BITLY_LOGIN;
   /** api key for making bit.ly requests*/
   public static String BITLY_APIKEY = CONFIG.BITLY_APIKEY;
   /** End of base URL for making bit.ly requests*/
   public static final String BITLY_URL_LONGURL = "&longUrl=";
   /** color for URL links */
   public static final int URL_LINK_COLOR = 0xff99ccff;
   
   // *** Map browsing
   
   /** maximum zoom level for the map */
   public static final int ZOOM_MAX = 19;
   /** minimum zoom level for the map */
   public static final int ZOOM_MIN = 5;
   /** maximum raster zoom level for the map */
   public static final int ZOOM_RASTER_MAX = 15;
   /** Zoom levels for route directions */
   public static final int DIRECTIONS_ZOOM_LEVEL = 14;
   /** Zoom levels for staring to show direction arrows */
   public static final int DIRECTION_ARROWS_ZOOM_LEVEL = 16;
   /** minimum distance needed for a drag operation to work */
   public static final int MIN_DRAG_DISTANCE = 5;
   /** minimum distance needed for a pinch operation to work */
   public static final int MIN_PINCH_DISTANCE = 10;
   // These define fetch and discard behavior. Units: pixels.
   // These small values are to prevent unnecessary fetches with the small pans
   // that occur incidentally. Note: no idea why this is called hysteresis, but
   // that is how it appears in http://cyclopath.org/wiki/Tech:Data_Transport.
   /** fetch hysteresis */
   public static final int FETCH_HYS = 12;
   /** discard hysteresis */
   public static final int DISCARD_HYS = 12;
   /** max distance in pixels where a geofeature is considered to be nearby */
   public static final int NEARBY_GEOFEATURE_PIXEL_DISTANCE = 30;
   /** When moving the view just enough to show a geofeature, the
    * margin we want on the target border */
   public static final int LOOKAT_LAZY_MARGIN = 20;
   /** The top margin is a bit higher to account for the title bar */
   public static final int LOOKAT_LAZY_MARGIN_TOP = 40;
   
   /** Height and width of tiles in pixels (must match server config)*/
   public static final int TILE_SIZE = 256;
   
   // *** GPS and Network
   
   /** Minimum time between updates for the network location listener in the
    * main activity. */
   public static final int MAIN_NETWORK_TIME_BETWEEN_UPDATES = 1000 * 1;
   /** Minimum time between updates for the GPS location listener in the
    * main activity. */
   public static final int MAIN_GPS_TIME_BETWEEN_UPDATES = 1000 * 10;
   /** Minimum time between updates for the GPS location listener in the
    * tracking service. */
   public static final int SERVICE_GPS_TIME_BETWEEN_UPDATES = 1000 * 1;
   /** Minimum distance between updates for location listeners (in meters) */
   public static final int MIN_DISTANCE_BETWEEN_UPDATES = 1;
   /** The minimum amount of time needed to say that a location is not too old
    * or significantly newer than another location. */
   public static final int LOCATION_SIGNIFICANT_TIME_DIF = 1000 * 60 * 2;
   /** The minimum difference in accuracy (in meters) needed to say that a
    * location is significantly more accurate than another one. */
   public static final int LOCATION_SIGNIFICANT_ACCURACY_DIF = 100;
   /** Threshold at which we consider a track to be stale. */
   public static final int STALE_RECORDING_THRESHOLD = 1000 * 60 * 60;
   
   // *** DEBUG
   
   /** Debugging */
   public static final boolean DEBUG = CONFIG.DEBUG;
   
   // *** Colors & Drawing
   
   /** background color */
   public static final int BACKGROUND = 0xFFD6C5B4;
   /** Radius of track points*/
   public static final float TRACK_POINT_RADIUS = 4;
   /** Radius of track point shadow*/
   public static final float TRACK_POINT_SHADOW_RADIUS = 6;
   /** Color of track start point*/
   public static final int TRACK_START_COLOR = 0xFF009900;
   /** Color of track endpoint*/
   public static final int TRACK_END_COLOR = 0xFFDD0800;
   /** Color of track point border*/
   public static final int TRACK_POINT_BORDER_COLOR = Color.BLACK;
   /** Color of Tracks being recorded*/
   public static final int TRACK_RECORDING_COLOR = 0xFFDD0800;
   /** Color of Tracks*/
   public static final int TRACK_COLOR = 0xFF009900;
   /** Paint Stroke Width for tracks*/
   public static final float TRACK_WIDTH = 2;
   /** Border width for track */
   public static final float TRACK_BORDER_WIDTH = 1;
   /** Fill color for route */
   public static final int ROUTE_COLOR = 0xFF86d0c7;
   /** Border color for route */
   public static final int ROUTE_BORDER_COLOR = 0xff0000ff;
   /** Width for route */
   public static final int ROUTE_WIDTH = 6;
   /** Border width for route */
   public static final int ROUTE_BORDER_WIDTH = 3;
   /** stroke width for a circle on a route */
   public static final int ROUTE_CIRCLE_STROKE_WIDTH = 4;
   /** radius for a circle on a route */
   public static final int ROUTE_CIRCLE_RADIUS = 5;
   /** color of the start point circle on a route */
   public static final int ROUTE_START_COLOR = 0xFF00bb00;
   /** color of the end point circle on a route */
   public static final int ROUTE_END_COLOR = 0xFFff0000;
   /** color of a direction point on a route */
   public static final int ROUTE_DIRECTION_COLOR = Color.YELLOW;
   /** size of labels on routes */
   public static final float ROUTE_LABEL_SIZE = 15;
   /** with of text borders for labels on routes */
   public static final float ROUTE_LABEL_STROKE_WIDTH = 2;
   /** Stroke width for direction arrow border */
   public static final float DIRECTION_ARROW_BORDER_STROKE_WIDTH = 3;
   /** Half width of direction arrow */
   public static final float DIRECTION_ARROW_WIDTH = 10;
   /** Height of direction arrow */
   public static final float DIRECTION_ARROW_HEIGHT = 24;
   /** number of pixels to add to the width of a label */
   public static final int MAP_LABEL_WIDTH_PADDING = 10;
   /** number of pixels to add to the height of a label */
   public static final int MAP_LABEL_HEIGHT_PADDING = 4;
   /** Maximum number of characters displayable in a label for a point.
    *  If larger, it's shortened and shows '...' */
   public static final int MAX_POINT_LABEL_LEN = 25;
   /** Maximum number of characters displayable in a label for a marker.
    *  If larger, it's shortened and shows '...' */
   public static final int MAX_MARKER_LABEL_LEN = 25;
   /** increase in label size on Android to make labels easier to read */
   public static final int LABEL_SIZE_ANDROID_ADJUSTMENT = 3;
   /** width of geofeature shadows */
   public static final float SHADOW_WIDTH = 1.5f;
   /** color that indicates that a user has rated a byway */
   public static final int USER_RATED_SHADOW_COLOR = 0xFFf2f22a;
   /** color that indicates that a user has not rated a byway */
   public static final int UNRATED_SHADOW_COLOR = 0xFFFFFFFF;
   /** color of label text */
   public static final int LABEL_COLOR = 0xFF444444;
   /** width of label halo */
   public static final int LABEL_STROKE_WIDTH = 2;
   /** color of label text whenever aerial tiles are being used */
   public static final int AERIAL_LABEL_COLOR = 0xFF666666;
   /** color of halo around label */
   public static int LABEL_HALO_COLOR = BACKGROUND;
   /** colors indicating the rating for a byway */
   public static final int[] RATING_COLORS_GENERIC = { 0xFFceb29f,
                                                       0xFFb5947d,
                                                       0xFF96776b,
                                                       0xFF725a49,
                                                       0xFF423327 };
   /** color of geofeature highlights */
   public static final int HIGHTLIGHT_COLOR = 0xff00ff44;
   /** font size of text in markers */
   public static final int MARKER_TEXT_SIZE = 20;
   /** default width of markers in pixels */
   public static final int MARKER_DEFAULT_WIDTH = 40;
   /** default width buffer of markers in pixels */
   public static final int MARKER_DEFAULT_WIDTH_BUFFER = 20;
   /** default height of markers in pixels */
   public static final int MARKER_DEFAULT_HEIGHT = 30;
   /** width of marker border */
   public static final int MARKER_BORDER_WIDTH = 2;
   /** width of pointer section of the marker */
   public static final int MARKER_POINTER_WIDTH = 20;
   /** height of pointer section of the marker */
   public static final int MARKER_POINTER_HEIGHT = 20;
   
   // z values for layers
   /** Layer for old tiles used for quick zooming effect */
   public static final float OLD_TILE_LAYER = 0;
   /** Layer for current tiles */
   public static final float TILE_LAYER = 1;
   /**  MAGIC_NUMBER: 160 is route z-level. */
   /**  MAGIC_NUMBER: 160 is route z-level. */
   public static final float ROUTE_LAYER = 160;
   /** Layer for landmark need prompts */
   public static final float LANDMARK_NEED_LAYER = 170;
   /** Layer for tracks */
   public static final float TRACK_LAYER = 200;
   /** Layer for tracks */
   public static final float TRACK_RECORDING_LAYER = 250;
   /** Layer for the map pointer*/
   public static final float MAP_LABEL_LAYER = 910;
   /** Layer for the map pointer*/
   public static final float MAP_POINTER_LAYER = 950;
   /** Layer for the map pointer*/
   public static final float MAP_MARKER_LAYER = 960;
   
   // *** GWIS
   
   /** Timeout for GWIS calls. */
   public static final int NETWORK_TIMEOUT = 30*1000;
   /** Number of seconds to wait before sending log events in order to send
    * them as batches. */
   public static final int GWIS_LOG_PAUSE_THRESHOLD = 3;
   /** Maximum number of log events to send together in a batch. */
   public static final int GWIS_LOG_COUNT_THRESHOLD = 64;
   /** Time between progress requests. */
   public static final int PROGRESS_REQUEST_WAIT_TIME = 1*1000;

   // *** Handler constants
   
   /** Signals the handler to handle the completion of the loading of items. */
   public static final int GWIS_HANDLE_LOAD = 1;
   /** Signals the handler to display an error. */
   public static final int GWIS_ERROR = 2;
   /** Signals the handler to handle a timeout. */
   public static final int GWIS_HANDLE_TIMEOUT = 3;
   /** Signals the handler to handle a timeout. */
   public static final int HANDLE_TIMEOUT = 3;
   /** Signals the handler to handle an io error. */
   public static final int GWIS_IO_ERROR = 4;
   /** Signals the handler to handle a throbber count changed. */
   public static final int THROBBER_CHANGED = 5;
   /** Signals the handler to handle the completion of the loading of items. */
   public static final int BITLY_OK = 6;
   /** Signals the handler to handle an error not documented in the bit.ly API
    * documentation (http://code.google.com/p/bitly-api/wiki/ApiDocumentation)
    */
   public static final int BITLY_ERROR = 7;
   /** Singals the handler to refresh tiles. */
   public static final int REFRESH_NEEDED = 8;
   /** Signals the base handler to require the user to update the app. */
   public static final int BASE_UPDATE_NEEDED = 9;
   /** Signals the base handler to show an alert dialog. */
   public static final int BASE_SHOW_ALERT = 10;
   /** Signals the base handler to require the user to reauthenticate. */
   public static final int BASE_REAUTHENTICATE = 11;
   /** Signals the base handler to show a progress dialog. */
   public static final int BASE_SHOW_PROGESS_DIALOG = 12;
   /** Signals the base handler to dismiss a progress dialog. */
   public static final int BASE_DISMISS_PROGESS_DIALOG = 13;
   /** Signals the base handler to show the chooser for handling route
    * sharing. */
   public static final int BASE_SHOW_SHARE_ROUTE_CHOOSER = 14;
   /** Signals the main activity to show the stale track dialog. */
   public static final int SHOW_STALE_TRACK_DIALOG = 15;
   /** Signals the main activity to show the save track dialog. */
   public static final int SAVE_FORCE_CLOSED_TRACK = 16;
   /** Signals the main activity to stop recording. */
   public static final int STOP_RECORDING = 17;
   /** Signals the base handler to update a progress dialog. */
   public static final int BASE_UPDATE_PROGESS_DIALOG = 18;
   /** Signals the handler that conflation is complete. */
   public static final int CONFLATION_COMPLETE = 19;
   /** Signals the handler that attachments (notes or tags) have been
    * loaded. */
   public static final int ATTACHMENT_LOAD_COMPLETE = 20;
   /** Signals the base handler to show a toast message. */
   public static final int BASE_SHOW_TOAST = 21;
   /** Signals handler to show landmark need prompt. */
   public static final int SHOW_LANDMARK_PROMPT = 22;
   /** Signals handler to hide landmark need prompt. */
   public static final int HIDE_LANDMARK_PROMPT = 23;
   /** Singals handler to refresh landmarks experiment bar */
   public static final int REFRESH_LANDMARK_EXPERIMENT = 24;

   // *** Route finding
   
   /** The default value for the route priority slider. */
   public static final float RF_PRIORITY_DEFAULT = 0.5f;
   /** Maximum number of addresses to store for use in autocomplete box. */
   public static final int MAX_AUTOCOMPLETE_ADDRESSES = 100;
   /** Percentage of addresses to keep when removing addresses in order to stay
    * under the limit. */
   public static final float PERCENT_TO_KEEP_AUTOCOMPLETE_ADDRESSES = 0.8f;
   /** x location of a direction - string for use when sharing data through
    * intents */
   public static final String DIRECTIONS_POINT_X = "point_x";
   /** y location of a direction - string for use when sharing data through
    * intents */
   public static final String DIRECTIONS_POINT_Y = "point_y";
   /** addresses to choose from - string for use when sharing data through
    * intents */
   public static final String CHOOSE_ADDRESSES = "addresses";
   /** texts returned by server for addresses to choose from - string for use
    * when sharing data through intents */
   public static final String CHOOSE_TEXTS = "texts";
   /** number of search results to show in route library */
   public static final int SEARCH_NUM_RESULTS_SHOW = 20;

   // Direction parameters
   /** Minimum length between vertices in a block to generate a direction
    *  vector for computing turn angles */
   public static final int ROUTE_STEP_DIR_LENGTH = 5;
   /** Byways, with the same name, that are shorter than this distance
    *  will be merged in the directions, no matter what the turn angle is. */
   public static final int DIR_MERGE_LENGTH = 100;
   /** Byways, with the same name, that turn less than this angle(in degrees)
    * will be merged in the directions, no matter what its length is. */
   public static final int DIR_MERGE_ANGLE = 30;
   /** Yard per mile used for showing yards instead of miles when mile number
    * is too small. */
   public static final int YARDS_PER_MILE = 1760;
   /** Miles per meter. */
   public static final double MILES_PER_METER = 0.000621;

   /** Static list of bearings. */
   public static Bearing[] BEARINGS;
   /** Static list of rating names. */
   public static String[] RATING_NAMES;
   
   // *** User preferences and Cookie strings

   /** name of cookie file */
   public static final String USER_COOKIE = "cp_cookie";
   /** name of anonymous cookie file */
   public static final String USER_COOKIE_ANON = "cp_cookie_anon";
   /** name of storage file for old addresses (for use in route finder
    * autocomplete box) */
   public static final String AUTOCOMPLETE_COOKIE = "autocomplete";
   /** string for accessing username in cookie */
   public static final String COOKIE_USERNAME = "username";
   /** string for accessing token in cookie */
   public static final String COOKIE_TOKEN = "token";
   /** string for accessing route finding priority in cookie */
   public static final String COOKIE_RF_PRIORITY = "rf_priority";
   /** string for accessing browser id in cookie */
   public static final String COOKIE_BROWID = "browid";
   /** string for accessing recording flag in cookie */
   public static final String COOKIE_IS_RECORDING = "is_recording";
   /** string for accessing route finding priority in preferences xml */
   public static final String PREFERENCE_RF_PRIORITY = "rf_priority";
   /** string for accessing state of the find route checkbox in cookie */
   public static final String COOKIE_FIND_ROUTE_REMEMBER_CHECKED
      = "find_route_remember_settings";
   /** Cookie tag for the latest android app version*/
   public static final String LATEST_VERSION = "android_version";
   /** Used to access whether or not the user has agreed to the terms of
    * service. */
   public static final String COOKIE_HAS_AGREED_TO_TERMS = "user_agreement";
   /**  */
   public static final String COOKIE_TRACKS_WITHOUT_ACCOUNT_MESSAGE =
      "track_without_account_message";
   /** Used for temprorary ids for new items. */
   public static final String COOKIE_FRESH_ID = "fresh_id";
   
   // ** Map Pointer
   
   /** Color of map pointer accuracy circle border */
   public static final int ACCURACY_CIRCLE_STROKE_COLOR = 0x66000000;
   /** Color of map pointer accuracy circle */
   public static final int ACCURACY_CIRCLE_FILL_COLOR = 0x22000000;
   /** With of map pointer accuracy circle line */
   public static final float ACCURACY_CIRCLE_STROKE_WIDTH = 2.0f;
   
   // *** Date Formats
   
   /** date format used by the server in XMLs. */
   public static final String SERVER_DATE_FORMAT = "yyyy-MM-dd HH:mm:ss";
   /** date format used by tracks on Android*/
   public static final String TRACK_DATE_FORMAT = "yyyy/MM/dd HH:mm:ss";
   /** date format for GPX */
   @SuppressLint("SimpleDateFormat")
   public static final SimpleDateFormat GPX_TIMESTAMP_FORMAT =
      new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
   static {
      GPX_TIMESTAMP_FORMAT.setTimeZone(TimeZone.getTimeZone("UTC"));
   }
   
   // *** Intent strings
   
   /** track id - string for use when sharing data through intents */
   public static final String TRACK_ID_STR = "track_id";
   /** stack id - string for use when sharing data through intents */
   public static final String STACK_ID_STR = "stack_id";
   /** note comments - string for use when sharing data through intents */
   public static final String NOTE_CONTENTS_STR = "note_contents";
   /** name for alert dialog title when passing information to handler in a
    * bundle */
   public static final String ALERT_TITLE = "alert_title";
   /** name for alert dialog message when passing information to handler in
    * a bundle */
   public static final String ALERT_MESSAGE = "alert_message";
   /** name for toast message when passing information to handler in
    * a bundle */
   public static final String TOAST_MESSAGE = "toast_message";
   /** name for alert dialog icon id when passing information to handler
    * in a bundle */
   public static final String ALERT_ICON = "alert_icon";
   /** name for progress for a progress dialog when passing information to
    * handler in a bundle */
   public static final String DIALOG_PROGRESS = "progress";
   /** name for whether a progress dialog is indeterminate when passing
    * information to handler in a bundle */
   public static final String DIALOG_INDETERMINATE = "indeterminate";
   /** url for route sharing used when passing information to handler
    * in a bundle */
   public static final String ROUTE_URL = "url";
   /** string for use when sharing whether a track is new through intents */
   public static final String TRACK_IS_NEW = "is_new";
   /** used to tell an activity whether to start in edit mode. */
   public static final String EDIT_MODE = "edit_mode";
   /** used to tell an activity whether tags were fetched. */
   public static final String TAGS_FETCHED = "tags_fetched";
   /** used to tell an activity whether notes were fetched. */
   public static final String NOTES_FETCHED = "notes_fetched";
   
   // *** Other constants
   
   /** Intent action for showing the end point of a track. */
   public static final String ACTION_SHOW_TRACK_END =
      "org.cyclopath.android.SHOW_TRACK_END";
   /** Intent action for showing landmark need prompt. */
   public static final String ACTION_SHOW_LANDMARK_NEED =
         "org.cyclopath.android.SHOW_LANDMARK_NEED";
   /** sensor values are considered stale after this time */
   public static final int STALE_SENSOR_TIMEOUT = 1000 * 10; // ten seconds
   /** A new bearing value must be different from the previous value by at
    * least this much to be considered significant. */
   public static final int SIGNIFICANT_BEARING_DIFFERENCE = 30;
   /** Type code for tracks that corresponds to the track type code on the
    * server database. */
   public static final int TYPE_CODE_TRACK = 2;
   /** Used to reference trackListItem Parcelable ArrayList in TrackManager*/
   public static final String TRACK_LIST = "server_track_list";
   /** Intent action for showing a shared track from a provided uri */
   public static final String ACTION_VIEW =
      "android.intent.action.VIEW";
   /** Used to tell the route finder if a special action should be completed */
   public static final String FINDROUTE_ACTION = "action";
   /** Tells the route finder to route to a custom location */
   public static final String FINDROUTE_ROUTE_TO_ACTION = "route-to";
   /** Tells the route finder to route from a custom location */
   public static final String FINDROUTE_ROUTE_FROM_ACTION = "route-from";
   /** Chars that are not allowed in file names (basically chars that are not
    * in the given set) */
   public static final Pattern PROHIBITED_CHARS =
      Pattern.compile("[^ A-Za-z0-9_.()-]+");
   /** Directory for storing items exported from Cyclopath. */
   public static final String CP_DIRECTORY = "/cyclopath/tracks";
   /** generic name for tracks */
   public static final String GENERIC_TRACK_NAME = "cyclopath_track";
   /** color of track date in track description */
   public static final int TRACK_DATE_COLOR = 0xFF696969;
   /** color of track duration (time) in track description */
   public static final int TRACK_DURATION_COLOR = 0xFF00FFFF;
   /** color of track length (distance) in track description */
   public static final int TRACK_LENGTH_COLOR = 0xFF00FFFF;
   /** color of track average speed in track description */
   public static final int TRACK_AVG_SPEED_COLOR = 0xFFFFFFFF;
   /** font size for track date, duration, and length in Track Details */
   public static final int TRACK_DETAILS_FONT_SIZE = 18;
   
   // *** Landmarks Trial

   /** Whether the user agreed to the landmarks experiment. */
   public static final String LANDMARKS_EXP_AGREE = "landmarks_agree";
   /** Whether the landmarks experiment bar should be shown in the map. */
   public static final String LANDMARKS_EXP_SHOW = "landmarks_show";
   public static final String LANDMARK_CONDITION_NONE = "none";
   public static final String LANDMARK_CONDITION_NOUSR = "no-usr";
   public static final String LANDMARK_CONDITION_NOW_LOW = "now-low";
   public static final String LANDMARK_CONDITION_NOW_HIGH = "now-high";
   public static final String LANDMARK_CONDITION_LATER_LOW = "later-low";
   public static final String LANDMARK_CONDITION_LATER_HIGH = "later-high";
   public static final int LANDMARK_NEED_RADIUS = 50;
   public static final int FIRST_LANDMARK_NEED_DISTANCE = 100;
   public static final int NEXT_LANDMARK_NEED_DISTANCE = 500;
   public static final int LANDMARK_NEED_TOO_FAR_DISTANCE = 100;
   public static final int LANDMARK_NEED_COLOR_SELECTED = 0x44FF0000;
   public static final int LANDMARK_NEED_BORDER_COLOR_SELECTED = 0xFF000000;
   public static final int LANDMARK_NEED_COLOR_UNSELECTED = 0x22666666;
   public static final int LANDMARK_NEED_BORDER_COLOR_UNSELECTED = 0x66000000;
   /** for how long the user will agree to participate (14 days in ms) */
   public static final int LANDMARK_AGREEMENT_DURATION =
         14 * 24 * 60 * 60 * 1000;
   public static final long[] LANDMARK_VIBRATE_PATTERN =
      {0, 200, 100, 200, 100, 3000};
   
   
   /**
    * Initialize constants that depend on Resources
    */
   public static void init() {
      BEARINGS = new Bearing[]{
         new Bearing(G.app_context.getString(R.string.bearing_right),
                     G.app_context.getString(R.string.bearing_e),
                     50, R.drawable.right),
         new Bearing(G.app_context.getString(R.string.bearing_slight_right),
                     G.app_context.getString(R.string.bearing_ne),
                     80, R.drawable.right),
         new Bearing(G.app_context.getString(R.string.bearing_forward),
                     G.app_context.getString(R.string.bearing_n),
                     100, R.drawable.up),
         new Bearing(G.app_context.getString(R.string.bearing_slight_left),
                     G.app_context.getString(R.string.bearing_nw),
                     130, R.drawable.left),
         new Bearing(G.app_context.getString(R.string.bearing_left),
                     G.app_context.getString(R.string.bearing_w),
                     190, R.drawable.left),
         new Bearing(G.app_context.getString(R.string.bearing_sharp_left),
                     G.app_context.getString(R.string.bearing_sw),
                     250, R.drawable.left),
         new Bearing(G.app_context.getString(R.string.bearing_backward),
                     G.app_context.getString(R.string.bearing_s),
                     290, R.drawable.down),
         new Bearing(G.app_context.getString(R.string.bearing_sharp_right),
                     G.app_context.getString(R.string.bearing_se),
                     350, R.drawable.right),
         new Bearing(G.app_context.getString(R.string.bearing_right),
                     G.app_context.getString(R.string.bearing_e),
                     360, R.drawable.right),
         // Don't reorder these:
         // Also, note neg. angles, this 
         // lets angle classification work.
         new Bearing(G.app_context.getString(R.string.bearing_start),
                     G.app_context.getString(R.string.bearing_start),
                     -1, R.drawable.start),
         new Bearing(G.app_context.getString(R.string.bearing_end),
                     G.app_context.getString(R.string.bearing_end),
                     -1, R.drawable.end)};
      
      RATING_NAMES = new String[]
         {G.app_context.getString(R.string.rating_impassable),
          G.app_context.getString(R.string.rating_poor),
          G.app_context.getString(R.string.rating_fair),
          G.app_context.getString(R.string.rating_good),
          G.app_context.getString(R.string.rating_excellent)
         };
   }
}

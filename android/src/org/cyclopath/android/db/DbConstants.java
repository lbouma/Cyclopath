/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.db;

/**
 * Database-related constants.
 * @author Fernando Torre
 */
public class DbConstants {

   /** Name of the SQLite database */
   public static final String DATABASE_NAME = "cyclopath_db";
   
   // track table
   public static final String TRACK_TABLE = "track";
   public static final String TRACK_STACKID = "stack_id";
   public static final String TRACK_ID = "_id";
   public static final String TRACK_NAME = "name";
   public static final String TRACK_OWNER = "owner";
   public static final String TRACK_NOTES = "notes";
   public static final String TRACK_CREATED = "created";
   public static final String TRACK_ACCESSED = "accessed";
   public static final String TRACK_SERVERID = "server_id";
   public static final String TRACK_VERSION = "version";
   public static final String TRACK_LENGTH = "length";
   public static final String TRACK_RECORDING = "recording";
   public static final String TRACK_TRIAL_NUM = "trial_num";
   
   // trackpoint table
   public static final String TRACKPOINT_TABLE = "trackpoint";
   public static final String TRACKPOINT_ID = "_id";
   public static final String TRACKPOINT_TRACKID = "track_id";
   public static final String TRACKPOINT_X = "x";
   public static final String TRACKPOINT_Y = "y";
   public static final String TRACKPOINT_TIMESTAMP = "timestamp";
   public static final String TRACKPOINT_ORIENTATION = "orientation";
   public static final String TRACKPOINT_TEMPERATURE = "temperature";
   public static final String TRACKPOINT_ALTITUDE = "altitude";
   public static final String TRACKPOINT_BEARING = "bearing";
   public static final String TRACKPOINT_SPEED = "speed";
   
   // triggers
   public static final String DELETE_TRACKPOINTS_TRIGGER =
         "delete_trackpoints_with_track";
}

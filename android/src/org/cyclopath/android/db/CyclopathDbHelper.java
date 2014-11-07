/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.db;

import java.util.Date;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

/**
 * This class handles database creation and management.
 * @author Fernando Torre
 */
public class CyclopathDbHelper extends SQLiteOpenHelper {

   /** Current version of the database (used for upgrades) */
   private static final int DATABASE_VERSION = 7;

   /**
    * Constructor
    * @param context
    */
   public CyclopathDbHelper(Context context) {
      super(context, DbConstants.DATABASE_NAME, null, DATABASE_VERSION);
   }

   /**
    * Creates the required database tables.
    */
   @Override
   public void onCreate(SQLiteDatabase db) {
      // Create track table.
      db.execSQL("CREATE TABLE " + DbConstants.TRACK_TABLE
                 + " (" + DbConstants.TRACK_STACKID
                 + " INTEGER PRIMARY KEY NOT NULL,"
                 + DbConstants.TRACK_NAME + " TEXT NOT NULL,"
                 + DbConstants.TRACK_OWNER + " TEXT,"
                 + DbConstants.TRACK_NOTES + " TEXT,"
                 + DbConstants.TRACK_CREATED + " INTEGER,"
                 + DbConstants.TRACK_ACCESSED + " INTEGER,"
                 + DbConstants.TRACK_VERSION + " INTEGER NOT NULL,"
                 + DbConstants.TRACK_LENGTH + " DOUBLE,"
                 + DbConstants.TRACK_RECORDING + " INTEGER DEFAULT 0,"
                 + DbConstants.TRACK_TRIAL_NUM + " INTEGER DEFAULT -1);");
      // Create trackpoint table.
      db.execSQL("CREATE TABLE " + DbConstants.TRACKPOINT_TABLE
                 + " (" + DbConstants.TRACKPOINT_ID
                 + " INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,"
                 + DbConstants.TRACKPOINT_TRACKID + " INTEGER NOT NULL,"
                 + DbConstants.TRACKPOINT_X + " FLOAT NOT NULL,"
                 + DbConstants.TRACKPOINT_Y + " FLOAT NOT NULL,"
                 + DbConstants.TRACKPOINT_TIMESTAMP + " INTEGER NOT NULL,"
                 + DbConstants.TRACKPOINT_ALTITUDE + " FLOAT,"
                 + DbConstants.TRACKPOINT_BEARING + " FLOAT,"
                 + DbConstants.TRACKPOINT_SPEED + " FLOAT,"
                 + DbConstants.TRACKPOINT_ORIENTATION + " FLOAT,"
                 + DbConstants.TRACKPOINT_TEMPERATURE + " FLOAT)");
      // Create trigger for deleting trackpoints tied to tracks.
      db.execSQL("CREATE TRIGGER " + DbConstants.DELETE_TRACKPOINTS_TRIGGER
                 + " BEFORE DELETE ON " + DbConstants.TRACK_TABLE
                 + " FOR EACH ROW BEGIN"
                 + " DELETE FROM " + DbConstants.TRACKPOINT_TABLE
                 + " WHERE " + DbConstants.TRACKPOINT_TABLE
                 + "." + DbConstants.TRACKPOINT_TRACKID
                 + " = OLD." + DbConstants.TRACK_STACKID + ";"
                 + " END;");
   }

   /**
    * Upgrades the database.
    * For now this just drops everything and starts fresh. The actual method
    * will depend on future databases changes we make.
    */
   @Override
   public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
      if (oldVersion < 2) {
         // Add length column to Track table.
         db.execSQL("ALTER TABLE " + DbConstants.TRACK_TABLE
                    + " ADD COLUMN " + DbConstants.TRACK_LENGTH + " DOUBLE;");
         // Calculate length for each existing track.
         Cursor tracks = db.query(DbConstants.TRACK_TABLE,
                                  new String[] {DbConstants.TRACK_ID},
                                  null, null, null, null, null);
         tracks.moveToFirst();
         Cursor points;
         while (!tracks.isAfterLast()) {
            int id =
               tracks.getInt(tracks.getColumnIndex(DbConstants.TRACK_ID));
            // get point x's and y's
            points = db.query(DbConstants.TRACKPOINT_TABLE,
                              new String[] {DbConstants.TRACKPOINT_X,
                                            DbConstants.TRACKPOINT_Y},
                                 DbConstants.TRACKPOINT_TRACKID + "=" + id,
                                 null, null, null, null);
            // calculate track length
            double len = 0;
            points.moveToFirst();
            int last_x =
               points.getInt(points.getColumnIndex(DbConstants.TRACKPOINT_X));
            int last_y =
               points.getInt(points.getColumnIndex(DbConstants.TRACKPOINT_Y));
            int x;
            int y;
            points.moveToNext();
            while (!points.isAfterLast()) {
               x = points.getInt(
                     points.getColumnIndex(DbConstants.TRACKPOINT_X));
               y = points.getInt(
                     points.getColumnIndex(DbConstants.TRACKPOINT_Y));
               len = len + Math.sqrt((x-last_x)*(x-last_x)
                                      + (y-last_y)*(y-last_y));
               last_x = x;
               last_y = y;
               points.moveToNext();
            }
            points.close();
            // update track length for current track
            ContentValues updateValues = new ContentValues();
            updateValues.put(DbConstants.TRACK_LENGTH, len);
            db.update(DbConstants.TRACK_TABLE,
                      updateValues,
                      DbConstants.TRACK_ID + "=" + id,
                      null);
            tracks.moveToNext();
         }
         tracks.close();
      }
      if (oldVersion < 3) {
         // Apparently, SQLite does not require changing the column type, as
         // data types aren't rigid.
      }
      if (oldVersion < 4) {
         // Add accessed column to tracks
         db.execSQL("ALTER TABLE " + DbConstants.TRACK_TABLE
               + " ADD COLUMN " + DbConstants.TRACK_ACCESSED
               + " INTEGER NOT NULL DEFAULT 0;");
         ContentValues updateValues = new ContentValues();
         updateValues.put(DbConstants.TRACK_ACCESSED, (new Date()).getTime());
         db.update(DbConstants.TRACK_TABLE, updateValues, null, null);
      }
      if (oldVersion < 5) {
         // Make stack id the primary column
         // delete trigger
         db.execSQL("DROP TRIGGER " + DbConstants.DELETE_TRACKPOINTS_TRIGGER);
         // create new temporary table table
         db.execSQL("CREATE TABLE " + DbConstants.TRACK_TABLE + "_temp"
               + " (" + DbConstants.TRACK_STACKID
               + " INTEGER PRIMARY KEY NOT NULL,"
               + DbConstants.TRACK_NAME + " TEXT NOT NULL,"
               + DbConstants.TRACK_OWNER + " TEXT,"
               + DbConstants.TRACK_NOTES + " TEXT,"
               + DbConstants.TRACK_CREATED + " INTEGER,"
               + DbConstants.TRACK_ACCESSED + " INTEGER,"
               + DbConstants.TRACK_VERSION + " INTEGER NOT NULL,"
               + DbConstants.TRACK_LENGTH + " DOUBLE,"
               + DbConstants.TRACK_RECORDING + " INTEGER DEFAULT 0);");
         // copy old table to temp table, choosing correct id value
         db.execSQL("INSERT INTO " + DbConstants.TRACK_TABLE + "_temp"
               + " (" + DbConstants.TRACK_STACKID + ","
               + DbConstants.TRACK_NAME + ","
               + DbConstants.TRACK_OWNER + ","
               + DbConstants.TRACK_NOTES + ","
               + DbConstants.TRACK_CREATED + ","
               + DbConstants.TRACK_ACCESSED + ","
               + DbConstants.TRACK_VERSION + ","
               + DbConstants.TRACK_LENGTH + ") "
               + "SELECT"
               + " CASE WHEN " + DbConstants.TRACK_SERVERID + " > 0"
               + " THEN " + DbConstants.TRACK_SERVERID
               + " ELSE " + DbConstants.TRACK_ID
               + " END, "
               + DbConstants.TRACK_NAME + ","
               + DbConstants.TRACK_OWNER + ","
               + DbConstants.TRACK_NOTES + ","
               + DbConstants.TRACK_CREATED + ","
               + DbConstants.TRACK_ACCESSED + ","
               + DbConstants.TRACK_VERSION + ","
               + DbConstants.TRACK_LENGTH
               + " FROM " + DbConstants.TRACK_TABLE);
         // update track points to point to new id value.
         db.execSQL("UPDATE " + DbConstants.TRACKPOINT_TABLE
               + " SET " + DbConstants.TRACKPOINT_TRACKID
               + "=(SELECT " + DbConstants.TRACK_SERVERID
                  + " FROM " + DbConstants.TRACK_TABLE
                  + " WHERE " + DbConstants.TRACK_TABLE
                        + "." + DbConstants.TRACK_ID
                        + "=" + DbConstants.TRACKPOINT_TABLE
                        + "." + DbConstants.TRACKPOINT_TRACKID
                  + ")"
               + " WHERE (SELECT " + DbConstants.TRACK_SERVERID
                  + " FROM " + DbConstants.TRACK_TABLE
                  + " WHERE " + DbConstants.TRACK_TABLE
                        + "." + DbConstants.TRACK_ID
                        + "=" + DbConstants.TRACKPOINT_TABLE
                        + "." + DbConstants.TRACKPOINT_TRACKID
                  + ") > 0;");
         // Drop old track table
         db.execSQL("DROP TABLE " + DbConstants.TRACK_TABLE);
         // Rename new track table
         db.execSQL("ALTER TABLE " + DbConstants.TRACK_TABLE + "_temp"
               + " RENAME TO " + DbConstants.TRACK_TABLE);
         // recreate trigger
         db.execSQL("CREATE TRIGGER " + DbConstants.DELETE_TRACKPOINTS_TRIGGER
               + " BEFORE DELETE ON " + DbConstants.TRACK_TABLE
               + " FOR EACH ROW BEGIN"
               + " DELETE FROM " + DbConstants.TRACKPOINT_TABLE
               + " WHERE " + DbConstants.TRACKPOINT_TABLE
               + "." + DbConstants.TRACKPOINT_TRACKID
               + " = OLD." + DbConstants.TRACK_STACKID + ";"
               + " END;");
      }
      if (oldVersion < 7) {
         // Version 6 did not properly update the database tables.
         if (!this.existsColumnInTable(db, DbConstants.TRACK_TABLE,
                                       DbConstants.TRACK_TRIAL_NUM)) {
            // Add trial num column to Track table.
            db.execSQL("ALTER TABLE " + DbConstants.TRACK_TABLE
                    + " ADD COLUMN "
                    + DbConstants.TRACK_TRIAL_NUM + " INTEGER DEFAULT -1;");
         }
      }
   }
   
   /**
    * Helper method for checking if a column exists in a table.
    * @param db
    * @param table
    * @param column
    * @return
    */
   private boolean existsColumnInTable(SQLiteDatabase db,
                                       String table,
                                       String column) {
      try {
         Cursor cur  =
               db.rawQuery("SELECT * FROM " + table + " LIMIT 0", null);
         if(cur.getColumnIndex(column) != -1)
            return true;
         else
            return false;
      } catch (Exception Exp) {
         return false;
      }
  }

}

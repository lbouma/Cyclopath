/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.db;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;

import org.cyclopath.android.G;
import org.cyclopath.android.items.Track;
import org.cyclopath.android.items.TrackPoint;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.SQLException;
import android.database.sqlite.SQLiteDatabase;

/**
 * This class handles database actions such as adding and retrieving tracks.
 * @author Fernando Torre
 */
public class CyclopathDbAdapter {
   
   private Context context;
   /** the actual database */
   private SQLiteDatabase database;
   /** the database helper class */
   private CyclopathDbHelper dbHelper;

   /**
    * Constructor
    * @param context
    */
   public CyclopathDbAdapter(Context context) {
      this.context = context;
   }
   
   // *** Main database methods

   /**
    * Opens the database and makes it available for writing.
    */
   public CyclopathDbAdapter open() throws SQLException {
      this.dbHelper = new CyclopathDbHelper(context);
      this.database = dbHelper.getWritableDatabase();
      return this;
   }

   /**
    * Closes the database.
    */
   public void close() {
      this.dbHelper.close();
   }

   // *** Other methods
   
   /**
    * Adds a new track to the db.
    */
   public void addTrack(Track track) {
      this.database.beginTransaction();
      try {
         // add track
         ContentValues initialValues = new ContentValues();
         initialValues.put(DbConstants.TRACK_NAME, track.name);
         initialValues.put(DbConstants.TRACK_OWNER, track.owner);
         initialValues.put(DbConstants.TRACK_NOTES, track.comments);
         initialValues.put(DbConstants.TRACK_CREATED, track.date.getTime());
         initialValues.put(DbConstants.TRACK_STACKID, track.stack_id);
         initialValues.put(DbConstants.TRACK_VERSION, track.version);
         initialValues.put(DbConstants.TRACK_LENGTH, track.length);
         initialValues.put(DbConstants.TRACK_RECORDING, track.recording);
         initialValues.put(DbConstants.TRACK_ACCESSED, (new Date()).getTime());
         initialValues.put(DbConstants.TRACK_TRIAL_NUM, track.trial_num);
         this.database.insert(DbConstants.TRACK_TABLE, null, initialValues);
         
         // add points
         for (TrackPoint p : track.getTrackPoints()) {
            this.addTrackPoint(p, track.stack_id);
         }
         this.database.setTransactionSuccessful();
      } finally {
         this.database.endTransaction();
      }
   }
   
   /**
    * Adds a track point to a track in the db.
    */
   public void addTrackPoint(TrackPoint tp, int track_id) {
      this.database.beginTransaction();
      try {
         ContentValues initialValues = new ContentValues();
         initialValues.put(DbConstants.TRACKPOINT_TRACKID, track_id);
         initialValues.put(DbConstants.TRACKPOINT_X, tp.x);
         initialValues.put(DbConstants.TRACKPOINT_Y, tp.y);
         initialValues.put(DbConstants.TRACKPOINT_TIMESTAMP,
                           tp.getTimestamp().getTime());
         initialValues.put(DbConstants.TRACKPOINT_ORIENTATION, tp.orientation);
         initialValues.put(DbConstants.TRACKPOINT_TEMPERATURE, tp.temperature);
         initialValues.put(DbConstants.TRACKPOINT_ALTITUDE, tp.altitude);
         initialValues.put(DbConstants.TRACKPOINT_BEARING, tp.bearing);
         initialValues.put(DbConstants.TRACKPOINT_SPEED, tp.speed);
         this.database.insert(
               DbConstants.TRACKPOINT_TABLE, null, initialValues);
         this.database.setTransactionSuccessful();
      } finally {
         this.database.endTransaction();
      }
   }

   /**
    * Deletes from database tracks that have not been accessed in the last
    * three months.
    */
   public int deleteOldServerTracks() {
      Calendar c = Calendar.getInstance(); 
      c.setTime(new Date()); 
      c.add(Calendar.MONTH, -3);
      
      return this.database.delete(DbConstants.TRACK_TABLE,
                             DbConstants.TRACK_STACKID + ">0 AND " 
                             + DbConstants.TRACK_OWNER + " IS NOT NULL AND "
                             + DbConstants.TRACK_ACCESSED
                             + " < " + c.getTime().getTime(),
                             null);
   }

   /**
    * Deletes track from database.
    */
   public boolean deleteTrack(Track track) {
      return this.database.delete(DbConstants.TRACK_TABLE,
                             DbConstants.TRACK_STACKID + "=" + track.stack_id,
                             null) > 0;
   }

   /**
    * Deletes track from database.
    */
   public boolean deleteTrack(int track_id) {
      return this.database.delete(DbConstants.TRACK_TABLE,
                             DbConstants.TRACK_STACKID + "=" + track_id,
                             null) > 0;
   }

   /**
    * Deletes from database tracks that are already on the server.
    */
   public int deleteServerTracks() {
      return this.database.delete(DbConstants.TRACK_TABLE,
                             DbConstants.TRACK_STACKID + ">0 AND " 
                             + DbConstants.TRACK_OWNER + " IS NOT NULL",
                             null);
   }

   /**
    * Returns a Cursor over the list of all tracks in the database that the
    * current user has access to.
    * 
    * @return Cursor over all tracks
    */
   public Cursor fetchAllTracks() {
      String username = G.user.getName() == null ? "" : G.user.getName();
      return this.database.query(DbConstants.TRACK_TABLE,
                            new String[] {DbConstants.TRACK_STACKID,
                                          DbConstants.TRACK_NAME},
                            DbConstants.TRACK_OWNER + "=? OR "
                            + DbConstants.TRACK_OWNER + " IS NULL",
                            new String[] {username},
                            null, null, null);
   }
   
   /**
    * Returns the track that was being recorded when the app was force
    * closed.
    */
   public Track getForceClosedTrack() {
      Cursor cur =
            this.database.query(DbConstants.TRACK_TABLE,
                                new String[] {DbConstants.TRACK_STACKID},
                                              DbConstants.TRACK_RECORDING
                                              + "= 1",
                                null, null, null, null);
      if (cur == null)
         return null;
      cur.moveToFirst();
      if (cur.isAfterLast()) {
         cur.close();
         return null;
      }
      int stack_id = cur.getInt(cur.getColumnIndex(DbConstants.TRACK_STACKID));
      return this.getTrack(stack_id);
   }
   
   /**
    * Gets track with given stack id.
    * @param stack_id the track id
    */
   public Track getTrack(int stack_id) {
      Cursor cur =
         this.database.query(DbConstants.TRACK_TABLE,
                        new String[] {DbConstants.TRACK_STACKID,
                                      DbConstants.TRACK_NAME,
                                      DbConstants.TRACK_OWNER,
                                      DbConstants.TRACK_NOTES,
                                      DbConstants.TRACK_CREATED,
                                      DbConstants.TRACK_VERSION,
                                      DbConstants.TRACK_LENGTH,
                                      DbConstants.TRACK_RECORDING,
                                      DbConstants.TRACK_TRIAL_NUM},
                                      DbConstants.TRACK_STACKID
                                      + "=" + stack_id,
                        null, null, null, null);
      
      if (cur == null)
         return null;
      cur.moveToFirst();
      if (cur.isAfterLast()) {
         cur.close();
         return null;
      }
      Track t = new Track(
         cur.getString(cur.getColumnIndex(DbConstants.TRACK_NAME)),
         cur.getString(cur.getColumnIndex(DbConstants.TRACK_OWNER)),
         null,
         cur.getString(cur.getColumnIndex(DbConstants.TRACK_NOTES)),
         new Date(cur.getLong(cur.getColumnIndex(DbConstants.TRACK_CREATED))),
         cur.getInt(cur.getColumnIndex(DbConstants.TRACK_RECORDING)) == 1);
      
      t.stack_id = cur.getInt(cur.getColumnIndex(DbConstants.TRACK_STACKID));
      t.version = cur.getInt(cur.getColumnIndex(DbConstants.TRACK_VERSION));
      t.length = cur.getDouble(cur.getColumnIndex(DbConstants.TRACK_LENGTH));
      t.trial_num =
            cur.getInt(cur.getColumnIndex(DbConstants.TRACK_TRIAL_NUM));
      if (t.stack_id > 0) {
         t.fresh = false;
      }
      cur.close();
      
      // get points
      cur = this.database.query(DbConstants.TRACKPOINT_TABLE,
                           new String[] {DbConstants.TRACKPOINT_X,
                                         DbConstants.TRACKPOINT_Y,
                                         DbConstants.TRACKPOINT_TIMESTAMP,
                                         DbConstants.TRACKPOINT_ORIENTATION,
                                         DbConstants.TRACKPOINT_TEMPERATURE,
                                         DbConstants.TRACKPOINT_ALTITUDE,
                                         DbConstants.TRACKPOINT_BEARING,
                                         DbConstants.TRACKPOINT_SPEED},
                           DbConstants.TRACKPOINT_TRACKID + "=" + t.stack_id,
                           null, null, null, null);
      
      if (cur != null) {
         TrackPoint tp;
         cur.moveToFirst();
         while (!cur.isAfterLast()) {
            tp = new TrackPoint(cur.getFloat(
                 cur.getColumnIndex(DbConstants.TRACKPOINT_X)),
                 cur.getFloat(cur.getColumnIndex(DbConstants.TRACKPOINT_Y)),
                 new Date(cur.getLong(cur.getColumnIndex(
                       DbConstants.TRACKPOINT_TIMESTAMP))));
            int index = cur.getColumnIndex(DbConstants.TRACKPOINT_ORIENTATION);
            if (!cur.isNull(index)) {
               tp.orientation = cur.getFloat(index);
            }
            index = cur.getColumnIndex(DbConstants.TRACKPOINT_TEMPERATURE);
            if (!cur.isNull(index)) {
               tp.temperature = cur.getFloat(index);
            }
            index = cur.getColumnIndex(DbConstants.TRACKPOINT_ALTITUDE);
            if (!cur.isNull(index)) {
               tp.altitude = cur.getDouble(index);
            }
            index = cur.getColumnIndex(DbConstants.TRACKPOINT_BEARING);
            if (!cur.isNull(index)) {
               tp.bearing = cur.getFloat(index);
            }
            index = cur.getColumnIndex(DbConstants.TRACKPOINT_SPEED);
            if (!cur.isNull(index)) {
               tp.speed = cur.getFloat(index);
            }
            t.add(tp);
            cur.moveToNext();
         }
      }
      cur.close();

      ContentValues updateValues = new ContentValues();
      updateValues.put(DbConstants.TRACK_ACCESSED, (new Date()).getTime());
      this.database.update(DbConstants.TRACK_TABLE,
                           updateValues,
                           DbConstants.TRACK_STACKID + "=" + t.stack_id,
                           null);
      return t;
   }

   /**
    * Updates track (non-geometric changes)
    */
   public boolean updateTrack(Track track) {
      return this.updateTrack(track, track.stack_id);
   }

   /**
    * Updates track (non-geometric changes)
    */
   public boolean updateTrack(Track track, int stack_id) {
      this.database.beginTransaction();
      boolean result;
      try {
         ContentValues updateValues = new ContentValues();
         updateValues.put(DbConstants.TRACKPOINT_TRACKID, track.stack_id);
         this.database.update(DbConstants.TRACKPOINT_TABLE,
                              updateValues,
                              DbConstants.TRACKPOINT_TRACKID + "=" + stack_id,
                              null);
         updateValues = new ContentValues();
         updateValues.put(DbConstants.TRACK_NAME, track.name);
         updateValues.put(DbConstants.TRACK_OWNER, track.owner);
         updateValues.put(DbConstants.TRACK_NOTES, track.comments);
         updateValues.put(DbConstants.TRACK_STACKID, track.stack_id);
         updateValues.put(DbConstants.TRACK_VERSION, track.version);
         updateValues.put(DbConstants.TRACK_RECORDING, track.recording);
         updateValues.put(DbConstants.TRACK_LENGTH, track.length);
         updateValues.put(DbConstants.TRACK_TRIAL_NUM, track.trial_num);
         updateValues.put(DbConstants.TRACK_ACCESSED, (new Date()).getTime());
         result = this.database.update(DbConstants.TRACK_TABLE,
                                updateValues,
                                DbConstants.TRACK_STACKID + "=" + stack_id,
                                null) > 0;
         this.database.setTransactionSuccessful();
      } finally {
         this.database.endTransaction();
      }
      return result;
   }
   
   /**
    * Updates only the stack id of a track
    * @param old_id
    * @param new_id
    * @return
    */
   public boolean updateTrackId(int old_id, int new_id) {
      ContentValues updateValues = new ContentValues();
      updateValues.put(DbConstants.TRACKPOINT_TRACKID, new_id);
      this.database.update(DbConstants.TRACKPOINT_TABLE,
                           updateValues,
                           DbConstants.TRACKPOINT_TRACKID + "=" + old_id,
                           null);
      updateValues = new ContentValues();
      updateValues.put(DbConstants.TRACK_ACCESSED, (new Date()).getTime());
      updateValues.put(DbConstants.TRACK_STACKID, new_id);
      return this.database.update(DbConstants.TRACK_TABLE,
                             updateValues,
                             DbConstants.TRACK_STACKID + "=" + old_id,
                             null) > 0;
   }
   
   /**
    * Returns the list of anonymous tracks in the database.
    */
   public ArrayList<Track> getAnonTrackList() {
      return getLocalTrackList(false, true);
   }
   
   /**
    * Gets the list of tracks that are not fetched form the server (anonymous
    * and unsaved).
    */
   public ArrayList<Track> getLocalTrackList() {
      return getLocalTrackList(false, false);
   }

   /**
    * Gets the list of tracks that are not fetched form the server (anonymous
    * and unsaved).
    */
   public ArrayList<Track> getLocalTrackList(boolean onlyUnsaved,
                                                     boolean onlyAnon) {
      ArrayList<Track> results = new ArrayList<Track>();
      
      // If the user is logged in, local tracks include tracks that are owned
      // by the user and not on the server.
      // If unsaved is true, make sure the anonymous tracks fetched are tracks
      // that have not been saved on the server.
      String where_query =
         (G.user.isLoggedIn() && !onlyAnon ? 
               ("(" + DbConstants.TRACK_STACKID + "<=0 AND "
               + DbConstants.TRACK_OWNER + "=?) OR ") : "")
         + "(" + (onlyUnsaved ? (DbConstants.TRACK_STACKID + "<=0 AND ") : "")
         + DbConstants.TRACK_OWNER + " IS NULL)";

      String[] where_args = {};
      if (G.user.isLoggedIn() && !onlyAnon) {
         where_args = new String[]{G.user.getName()};
      }
      
      Cursor cur = database.query(DbConstants.TRACK_TABLE,
                            new String[] {DbConstants.TRACK_STACKID,
                                          DbConstants.TRACK_NAME,
                                          DbConstants.TRACK_OWNER,
                                          DbConstants.TRACK_CREATED,
                                          DbConstants.TRACK_LENGTH},
                            where_query,
                            where_args,
                            null, null, null);
      
      if (cur == null)
         return results;
      Track item;
      cur.moveToFirst();
      ArrayList<Integer> to_delete = new ArrayList<Integer>();
      while (!cur.isAfterLast()) {
         int track_id =
               cur.getInt(cur.getColumnIndex(DbConstants.TRACK_STACKID));
         // get track duration from first and last track points
         // points for this track, ordered by time
         Cursor pcur = database.query(DbConstants.TRACKPOINT_TABLE,
                              new String[] {DbConstants.TRACKPOINT_TIMESTAMP},
                              DbConstants.TRACKPOINT_TRACKID + "=" + track_id,
                              null, null, null,
                              DbConstants.TRACKPOINT_TIMESTAMP);
         long time_duration = 0;
         if (pcur.getCount() > 0) {
            pcur.moveToFirst();
            Date d1 = new Date(pcur.getLong(pcur.getColumnIndex(
                                          DbConstants.TRACKPOINT_TIMESTAMP)));
            pcur.moveToLast();
            Date d2 = new Date(pcur.getLong(pcur.getColumnIndex(
                                          DbConstants.TRACKPOINT_TIMESTAMP)));
            time_duration = d2.getTime() - d1.getTime();
         }
         pcur.close();
         
         double len =
               cur.getDouble(cur.getColumnIndex(DbConstants.TRACK_LENGTH));
         if (len == 0) {
            // Delete tracks with no length
            to_delete.add(track_id);
         } else {
            item = new Track(
                  track_id,
                  cur.getString(cur.getColumnIndex(DbConstants.TRACK_NAME)),
                  cur.getString(cur.getColumnIndex(DbConstants.TRACK_OWNER)),
                  new Date(cur.getLong(cur.getColumnIndex(
                                          DbConstants.TRACK_CREATED))),
                  time_duration,
                  len);
            results.add(item);
         }
         cur.moveToNext();
      }
      cur.close();
      for (Integer tid : to_delete) {
         this.deleteTrack(tid);
      }
      return results;
   }
   
   /**
    * Returns the list of unsaved tracks in the database.
    */
   public ArrayList<Track> getUnsavedTrackList() {
      Track t = this.getForceClosedTrack();
      ArrayList<Track> tracks = getLocalTrackList(true, false);
      if (t != null) {
         tracks.remove(t);
      }
      return tracks;
   }
}

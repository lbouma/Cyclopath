/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android;

import java.util.ArrayList;
import java.util.Date;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_Commit;
import org.cyclopath.android.gwis.GWIS_LandmarkTrialPut;
import org.cyclopath.android.items.Annotation;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.LinkValue;
import org.cyclopath.android.items.Track;

import android.os.Bundle;
import android.util.SparseIntArray;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Activity for viewing or editing track details.
 * @author Fernando Torre
 */
public class TrackDetailsActivity extends ItemDetailsActivity {
   
   /** Whether this is a new track that was just recorded and has still not
    * been saved. */
   private boolean is_new;
   
   @Override
   public void onCreate(Bundle savedInstanceState) {
      this.is_new = getIntent().getBooleanExtra(Constants.TRACK_IS_NEW, false);
      super.onCreate(savedInstanceState);
   }

   // *********** Other methods
   
   /**
    * Creates a TextView for this Activity with the given String and color.
    * @param str
    * @param color
    * @return
    */
   public TextView createTextView(String str, int color) {
      TextView text = new TextView(this);
      text.setText(str);
      text.setPadding(15, 0, 0, 0);
      text.setTextColor(color);
      text.setTextSize(Constants.TRACK_DETAILS_FONT_SIZE);
      return text;
   }

   /**
    * Discards a track from the map and local db if it was a new track.
    */
   @Override
   public void discardCleanup() {
      super.discardCleanup();
      Track t = (Track) this.geo;
      if (t.fresh) {
         // new track that was not saved, delete
         G.map.featuresDiscard(t.getZplus());
         G.db.deleteTrack(t);
         G.current_track = null;
      }
   }

   /**
    * Returns a list of notes that also includes any notes that were saved
    * to the local database.
    */
   @Override
   public ArrayList<Annotation> getNoteArray() {
      ArrayList<Annotation> note_array = super.getNoteArray();
      Track t = (Track) this.geo;
      if (note_array.size() == 0 && t.comments != null && t.comments != "") {
         Annotation annot = new Annotation(t.comments);
         this.geo.notes.put(annot.stack_id, annot);
         LinkValue link = new LinkValue(t, annot);
         this.geo.links.put(link.stack_id, link);
         note_array.add(annot);
      }
      t.comments = null;
      return note_array;
   }

   /**
    * Updates a saved track or lets the user know if the track was
    * temporarily saved locally only.
    */
   @Override
   public void handleGWIS_CommitCallback(SparseIntArray id_map) {
      Track t = (Track) this.geo;
      if (id_map == null && t.fresh) {
         Toast.makeText(this, getString(R.string.gwis_new_track_save_later),
               Toast.LENGTH_SHORT).show();
         G.landmark_condition = Constants.LANDMARK_CONDITION_NONE;
         this.cleanupAndFinish();
      } else if (id_map != null) {
         int new_id = id_map.get(this.geo.stack_id);
         if (new_id > 0) {
            int old_id = this.geo.stack_id;
            if (this.geo.dirty || this.geo.fresh) {
               this.geo.stack_id = new_id;
               this.geo.version++;
            }
            // delete comments, as they are now stored in the server as
            // attachments
            t.comments = null;
            G.db.updateTrack(t, old_id);
            // show toast
            Toast.makeText(this,
                  this.getResources().getString(R.string.item_saved),
                  Toast.LENGTH_SHORT).show();
            if (G.LANDMARKS_EXP_ON
                  && G.cookie.getLong(Constants.LANDMARKS_EXP_AGREE, 0)
                     > (new Date()).getTime()
                  && t.trial_num > 0) {
               new GWIS_LandmarkTrialPut(t.stack_id, t.trial_num).fetch();
            }
            G.landmark_condition = Constants.LANDMARK_CONDITION_NONE;
            this.cleanupAndFinish();
         }
      }
   }

   /**
    * Aside from the normal initialization done by the parent Activity, also
    * populates Track-specific items.
    */
   @Override
   public void init() {
      super.init();
      Track t = (Track) this.geo;
      if (this.is_new) {
         // we might be dealing with a track that was never saved
         t.fresh = true;
      }
      
      // set hint for track title
      EditText name_edit = (EditText) findViewById(R.id.item_name);
      if (this.editing_mode) {
         name_edit.setHint(t.getFormattedDate());
         if (t.name.equals("")) {
            t.name = t.getFormattedDate();
         }
         name_edit.setText(t.name);
         name_edit.setSelectAllOnFocus(true);
      }
      
      // hide tags
      ((LinearLayout) findViewById(R.id.item_tags_group))
         .setVisibility(View.GONE);
      
      // misc track details
      LinearLayout box =
         (LinearLayout) findViewById(R.id.item_misc);
      box.removeAllViews();
      LinearLayout linear = new LinearLayout(this);
      linear.setOrientation(LinearLayout.HORIZONTAL);
      box.addView(this.createTextView(t.getFormattedDate(),
                                      Constants.TRACK_DATE_COLOR));
      linear.addView(this.createTextView(t.getFormattedDuration(),
                                         Constants.TRACK_DURATION_COLOR));
      linear.addView(this.createTextView(G.getFormattedLength(t.length),
                                         Constants.TRACK_LENGTH_COLOR));
      linear.addView(this.createTextView(t.getFormattedAvgSpeed(),
                                         Constants.TRACK_AVG_SPEED_COLOR));
      box.addView(linear);
   }
   
   /**
    * 
    */
   @Override
   public void save() {
      ArrayList<ItemUserAccess> items = this.getDirtyItems();
      if (items.size() == 0) {
         Toast.makeText(
               this,
               this.getResources().getString(R.string.item_nothing_to_save),
               Toast.LENGTH_SHORT).show();
         finish();
         return;
      }
      if (G.user.isBanned()) {
         G.showAlert(
               this.getResources().getString(R.string.saving_ban_msg),
               this.getResources().getString(R.string.saving_ban_title));
      } else {
         Track t = (Track) this.geo;
         // in case the user changes during recording
         t.owner = G.user.getName();
         EditText name_edit = (EditText) findViewById(R.id.item_name);
         if (t.name == null) {
            t.name = name_edit.getHint().toString();
         } else if (t.name.length() == 0) {
            t.name = name_edit.getHint().toString();
         }
         for (int i = 0; i < this.geo.notes.size(); i++) {
            Annotation annot = this.geo.notes.valueAt(i);
            t.comments = t.comments + annot.toString();
         }
         if (t.stack_id <= 0) {
            // Fix for corrupted tracks where the version was updated but not
            // the id.
            t.version = 0;
         }
         if (t.fresh) {
            // new track
            // remove from previous layer
            G.map.featuresDiscard(t.getZplus());
            t.recording = false;
            // remove any other visible tracks
            G.map.featuresDiscard(Constants.TRACK_LAYER);
            G.selected_track = t;
            G.current_track = null;
            G.map.featureAdd(t);
         }
         saveToServer(items);
      }
   }//save

   /**
    * Save the track to the server.
    */
   @Override
   public void saveToServer(ArrayList<ItemUserAccess> items) {
      new GWIS_Commit(items,
            getResources().getString(
                  R.string.track_put_progress_dialog_title),
            getResources().getString(
                  R.string.track_put_progress_dialog_content),
            this).fetch();
   }

   /**
    * Tracks are not always on the map already, so we get it from the local
    * db.
    */
   @Override
   public void setGeoFeature(int stack_id) {
      this.geo = null;
      if (!this.is_new) {
         this.geo = TrackManager.selected_track;
      }
      if (this.geo == null) {
         this.geo = G.db.getTrack(stack_id);
      }
   }
}

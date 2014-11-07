/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android;

import java.util.ArrayList;
import java.util.Collections;

import org.cyclopath.android.conf.Conf;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.gwis.GWIS_Checkout;
import org.cyclopath.android.gwis.GWIS_Commit;
import org.cyclopath.android.gwis.GWIS_CommitCallback;
import org.cyclopath.android.gwis.QueryFilters;
import org.cyclopath.android.items.Annotation;
import org.cyclopath.android.items.Attachment;
import org.cyclopath.android.items.Byway;
import org.cyclopath.android.items.Geofeature;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.LinkValue;
import org.cyclopath.android.items.Tag;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Message;
import android.util.SparseArray;
import android.util.SparseIntArray;
import android.view.ContextMenu;
import android.view.KeyEvent;
import android.view.MenuItem;
import android.view.View;
import android.view.ContextMenu.ContextMenuInfo;
import android.view.View.OnClickListener;
import android.view.View.OnLongClickListener;
import android.view.Window;
import android.widget.ArrayAdapter;
import android.widget.AutoCompleteTextView;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.RatingBar;
import android.widget.RatingBar.OnRatingBarChangeListener;
import android.widget.RelativeLayout;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Activity for viewing or editing item details.
 * @author Fernando Torre
 */
public class ItemDetailsActivity extends BaseActivity
                                 implements OnRatingBarChangeListener,
                                            OnClickListener,
                                            OnLongClickListener,
                                            GWIS_CommitCallback {
   
   /** the feature for which details are being shown or edited */
   public Geofeature geo;
   /** whether we are editing the current geofeature */
   public boolean editing_mode;
   /** Original geofeature name */
   public String orig_name;
   
   /** Request code for editing this item (used when returning from the edit
    * activity) */
   private final int EDIT_ITEM_REQUEST_CODE = 0;
   /** Request code for editing a note (used when returning from the edit
    * activity) */
   private final int EDIT_NOTE_REQUEST_CODE = 1;
   /** size of tag font */
   public static float TAG_TEXT_SIZE = 20;
   /** size of note font */
   public static float NOTE_TEXT_SIZE = 15;
   
   // ************ Main Activity Events
   
   /**
    * 
    */
   @Override
   protected void onActivityResult(int requestCode,
                                   int resultCode,
                                   Intent data){
      if (requestCode == EDIT_ITEM_REQUEST_CODE) {
         // re-populate interface
         G.attachment_UI_handler = new CyclopathHandler(this);
         this.geo.resetAttachments();
         this.init();
      } else if (requestCode == EDIT_NOTE_REQUEST_CODE) {
         // We handle the changes in note content in this activity because
         // fetching the geofeature in NoteAcitivity is a bit troublesome,
         // because tracks are fetched from the local database and not from
         // the list of map features.
         if (resultCode == Activity.RESULT_OK) {
            String new_content =
                  data.getStringExtra(Constants.NOTE_CONTENTS_STR);
            int note_id = data.getIntExtra(Constants.STACK_ID_STR, 0);
            if (this.geo.notes.get(note_id) != null) {
               Annotation annot = this.geo.notes.get(note_id);
               if (!new_content.equals(annot.name)) {
                  annot.name = new_content;
                  annot.dirty = true;
                  this.updateNoteViews();
               }
            } else {
               Annotation annot = new Annotation(new_content);
               LinkValue link = new LinkValue(this.geo, annot);
               this.geo.notes.put(annot.stack_id, annot);
               this.geo.links.put(link.stack_id, link);
               this.updateNoteViews();
            }
         }
      }
   }

   /**
    * Handle button and list item clicks.
    */
   @Override
   public void onClick(View v) {
      if (v == this.findViewById(R.id.edit_btn)) {
         // Start edit activity
         Intent myIntent = new Intent(this, this.getClass());
         myIntent.putExtra(Constants.STACK_ID_STR, this.geo.stack_id);
         myIntent.putExtra(Constants.EDIT_MODE, true);
         startActivityForResult(myIntent, EDIT_ITEM_REQUEST_CODE);
      } else if (v == this.findViewById(R.id.save_btn)) {
         // Save changes (maybe)
         this.save();
      } else if (v == this.findViewById(R.id.discard_btn)) {
         // Discard changes (shows confirmation dialog)
         if (!this.isDirty()) {
            finish();
         } else {
            this.showDiscardMessage();
         }
      } else if (v == this.findViewById(R.id.tag_edit_btn)) {
         // create new tag and link value and add both to geo
         AutoCompleteTextView tag_edit_box =
               (AutoCompleteTextView) this.findViewById(R.id.tag_edit);
         String tag_str = tag_edit_box.getText().toString();
         if (tag_str.length() > 2) {
            Tag t = new Tag(tag_str);
            LinkValue link = new LinkValue(this.geo, t);
            this.geo.links.put(link.stack_id, link);
            this.geo.tags.put(t.stack_id, t);
            this.updateTagViews();
            tag_edit_box.setText("");
            Toast.makeText(
                  this,
                  String.format(
                        this.getResources().getString(R.string.item_tag_added),
                        tag_str),
                  Toast.LENGTH_SHORT).show();
         }
      } else if (v == this.findViewById(R.id.note_edit_btn)) {
         // create new note and link value and add both to geo
         EditText note_edit_box = 
               (EditText) this.findViewById(R.id.note_edit);
         String note_str = note_edit_box.getText().toString();
         if (note_str.length() > 2) {
            Annotation annot = new Annotation(note_str);
            LinkValue link = new LinkValue(this.geo, annot);
            this.geo.links.put(link.stack_id, link);
            this.geo.notes.put(annot.stack_id, annot);
            this.updateNoteViews();
            note_edit_box.setText("");
            Toast.makeText(
                  this,
                  this.getResources().getString(R.string.item_note_added),
                  Toast.LENGTH_SHORT).show();
         }
      } else if (v.getTag().equals(ItemType.ANNOTATION)) {
         // Show the note details
         Annotation annot = this.geo.notes.get(v.getId());
         Intent myIntent = new Intent(this, NoteActivity.class);
         myIntent.putExtra(Constants.NOTE_CONTENTS_STR, annot.name);
         myIntent.putExtra(Constants.STACK_ID_STR, annot.stack_id);
         myIntent.putExtra(Constants.EDIT_MODE, this.editing_mode);
         startActivityForResult(myIntent, EDIT_NOTE_REQUEST_CODE);
      }
   }

   /**
    * Handle context menu selections.
    */
   @Override
   public boolean onContextItemSelected(MenuItem item) {
      if (item.getTitle().equals(
            this.getResources().getString(R.string.item_delete))) {
         // Delete the selected attachment (basically, delete its link value)
         for (int i = 0; i < this.geo.links.size(); i++) {
            LinkValue link = this.geo.links.valueAt(i);
            if (link.lhs_stack_id == item.getItemId()) {
               link.deleted = true;
            }
         }
         this.updateTagViews();
         this.updateNoteViews();
         return true;
      }
      return false;
   }

   /**
    * Sets the geofeature and the layout specific for its type.
    */
   @Override
   public void onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState);
      G.attachment_UI_handler = new CyclopathHandler(this);
      int stack_id = getIntent().getIntExtra(Constants.STACK_ID_STR, -1);
      this.editing_mode =
            getIntent().getBooleanExtra(Constants.EDIT_MODE, false);
      this.requestWindowFeature(Window.FEATURE_NO_TITLE);
      setContentView(R.layout.item_details);
      // get the geofeature with this stack id
      this.setGeoFeature(stack_id);
      // populate the layout based on the geofeature
      this.init();
   }
   
   /**
    * Create the context menu (currently only used for deleting attachments).
    */
   @Override
   public void onCreateContextMenu(ContextMenu menu, View v,
                                   ContextMenuInfo menuInfo) {
      super.onCreateContextMenu(menu, v, menuInfo);
      menu.setHeaderTitle(getString(R.string.menu));
      menu.add(1, v.getId(), 0,
               this.getResources().getString(R.string.item_delete));
   }

   /**
    * Intercepts the "BACK" event so that we can show a discard confirmation
    * dialog.
    */
   @Override
   public boolean onKeyDown(int keyCode, KeyEvent event) {
      if (keyCode == KeyEvent.KEYCODE_BACK
          && this.isDirty()
          && this.editing_mode) {
         showDiscardMessage();
         return true;
      } else {
         return super.onKeyDown(keyCode, event);
      }
   }

   /**
    * Shows the context menu for an attachment after a long press.
    */
   @Override
   public boolean onLongClick(View v) {
      if (!this.editing_mode) {
         return false;
      }
      if (v.getTag().equals(ItemType.TAG)
          || v.getTag().equals(ItemType.ANNOTATION)) {
         this.registerForContextMenu(v);
         v.showContextMenu();
         return true;
      }
      return false;
   }

   /**
    * Handles changes to the rating of a Byway
    */
   @Override
   public void onRatingChanged(RatingBar bar, float rating, boolean fromUser) {
      Byway b = (Byway) this.geo;
      this.updateRatingsText(rating);
      new GWIS_Commit(b.stack_id, b.user_rating).fetch();
   }

   /**
    * Sets the global handler when this activity is started.
    */
   @Override
   public void onStart() {
      super.onStart();
      G.attachment_UI_handler = new CyclopathHandler(this);
   }
   
   // *********** Other methods
   
   /**
    * Set results information and finish the activity.
    */
   public void cleanupAndFinish() {
      Intent intent = new Intent();
      if (getParent() == null) {
         setResult(Activity.RESULT_OK, intent);
      } else {
         getParent().setResult(Activity.RESULT_OK, intent);
      }
      finish();
   }

   /**
    * Creates a TextView for the given note.
    */
   public TextView createNoteView(Annotation annot) {
      TextView text = this.createTextView(annot, NOTE_TEXT_SIZE);
      text.setOnClickListener(this);
      return text;
   }

   /**
    * Creates a TextView for the given tag.
    */
   public TextView createTagView(Tag tag) {
      TextView text = this.createTextView(tag, TAG_TEXT_SIZE);
      text.setTypeface(text.getTypeface(), Typeface.ITALIC);
      return text;
   }
   
   /**
    * Helper method for creating an attachment TextView.
    */
   public TextView createTextView(Attachment att, float text_size) {
      TextView text = new TextView(this);
      text.setPadding(10, 10, 0, 10);
      text.setTextSize(text_size);
      text.setOnLongClickListener(this);
      text.setId(att.stack_id);
      text.setTag(att.getItemTypeId());
      text.setText(att.toString());
      return text;
   }

   /**
    * If the geofeature is dirty, we reset the attachments. Currently, no
    * other changes are made to the geofeature itself that need to be reset.
    */
   public void discardCleanup() {
      if (this.isDirty()) {
         this.geo.name = this.orig_name;
         this.geo.dirty = false;
         this.geo.resetAttachments();
      }
      if (this.geo.fresh) {
         G.map.featureDiscard(this.geo);
         G.vectors_old_all.remove(this.geo.stack_id);
      }
   }

   /**
    * Returns a list of dirty items that need to be saved.
    */
   public ArrayList<ItemUserAccess> getDirtyItems() {
      ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
      if (!this.editing_mode) {
         return items;
      }
      
      EditText name_edit = (EditText) findViewById(R.id.item_name);
      if (!name_edit.getText().toString().equals(this.geo.name)) {
         this.geo.name = name_edit.getText().toString();
         this.geo.dirty = true;
         items.add(this.geo);
      } else if (this.geo.fresh || this.geo.dirty) {
         items.add(this.geo);
      }
      this.getDirtyItemsHelper(items, this.geo.links);
      this.getDirtyItemsHelper(items, this.geo.notes);
      this.getDirtyItemsHelper(items, this.geo.tags);
      return items;
   }
   
   /**
    * Adds dirty items in the SparseArray to the given ArrayList.
    */
   public <T> void getDirtyItemsHelper(ArrayList<ItemUserAccess> list,
                                       SparseArray<T> items) {
      for (int i = 0; i < items.size(); i++) {
         ItemUserAccess item = (ItemUserAccess) items.valueAt(i);
         if (item.deleted || item.dirty || item.fresh) {
            list.add(item);
         }
      }
   }

   /**
    * Returns an ArrayList containing the notes attached to the current
    * geofeature.
    */
   public ArrayList<Annotation> getNoteArray() {
      ArrayList<Annotation> note_array = new ArrayList<Annotation>();
      for (int i = 0; i < this.geo.links.size(); i++) {
         LinkValue link = this.geo.links.valueAt(i);
         if (!link.deleted
             && this.geo.notes.get(link.lhs_stack_id) != null) {
            note_array.add(this.geo.notes.get(link.lhs_stack_id));
         }
      }
      return note_array;
   }

   /**
    * Returns an ArrayList containing the tags attached to the current
    * geofeature. The list is sorted alphabetically.
    */
   public ArrayList<Tag> getTagsArray() {
      ArrayList<Tag> tag_array = new ArrayList<Tag>();
      for (int i = 0; i < this.geo.links.size(); i++) {
         LinkValue link = this.geo.links.valueAt(i);
         if (!link.deleted
             && this.geo.tags.get(link.lhs_stack_id) != null) {
            tag_array.add(this.geo.tags.get(link.lhs_stack_id));
         }
      }
      Collections.sort(tag_array);
      return tag_array;
   }

   /**
    * Updates the views when tags or notes are fetched from a GWIS thread.
    */
   @Override
   public void handleMessage(Message msg) {
      switch (msg.what) {
      case (Constants.ATTACHMENT_LOAD_COMPLETE):
         Bundle data = msg.getData();
         boolean tags_fetched = data.getBoolean(Constants.TAGS_FETCHED);
         boolean notes_fetched = data.getBoolean(Constants.NOTES_FETCHED);
         if (tags_fetched) {
            this.updateTagViews();
         }
         if (notes_fetched) {
            this.updateNoteViews();
         }
         break;
      }
   }

   /**
    * Updates the geofeature after it has been saved.
    */
   @Override
   public void handleGWIS_CommitCallback(SparseIntArray id_map) {
      if (id_map == null) {
         return;
      }
      
      if (Cyclopath.landmark_editing_mode_now) {
         G.server_log.event("mobile/landmarks",
               new String[][]{{"landmark_edit", "now"},
                 {"stack_id", String.valueOf(id_map.get(this.geo.stack_id))}});
      } else if (Cyclopath.landmark_editing_mode_later) {
         G.server_log.event("mobile/landmarks",
               new String[][]{{"landmark_edit", "later"},
                 {"stack_id", String.valueOf(id_map.get(this.geo.stack_id))}});
      }
      
      if (this.geo.dirty && id_map.get(this.geo.stack_id) != 0) {
         this.geo.version++;
         this.geo.dirty = false;
      }
      // update list of all tags
      new GWIS_Checkout("tag", new QueryFilters()).fetch();
      // show toast
      Toast.makeText(this,
                     this.getResources().getString(R.string.item_saved),
                     Toast.LENGTH_SHORT).show();
      // The Activity that called this one will request updated versions of
      // the attachments and  link values.
      this.cleanupAndFinish();
   }

   /**
    * Initializes and populates the layout.
    */
   public void init() {
      
      // init header
      TextView title = (TextView) findViewById(R.id.item_details_title);
      ImageButton edit_btn = (ImageButton) findViewById(R.id.edit_btn);
      EditText name_edit = (EditText) findViewById(R.id.item_name);
      title.setTypeface(title.getTypeface(), Typeface.NORMAL);
      if (!this.editing_mode) {
         String title_str = this.geo.name;
         if (title_str == null || title_str == "") {
            title_str = 
               String.format(this.getResources()
                                 .getString(R.string.direction_unnamed),
                             Conf.geofeature_layer_by_id.get(this.geo.gfl_id));
            title.setTypeface(title.getTypeface(), Typeface.ITALIC);
         }
         title.setText(title_str);
         edit_btn.setOnClickListener(this);
      } else {
         title.setText(
               this.getResources().getString(R.string.item_details_name));
         edit_btn.setVisibility(View.GONE);
         name_edit.setVisibility(View.VISIBLE);
         name_edit.setText(this.geo.name);
         this.orig_name = this.geo.name;
      }
      
      // init ratings
      if (Byway.class.isInstance(geo) && !this.editing_mode) {
         Byway b = (Byway) geo;
         RatingBar ratings = (RatingBar) findViewById(R.id.item_rating);
         TextView description =
               (TextView) findViewById(R.id.item_rating_description);
         TextView estimated =
               (TextView) findViewById(R.id.item_rating_estimated);
         ratings.setVisibility(View.VISIBLE);
         description.setVisibility(View.VISIBLE);
         estimated.setVisibility(View.VISIBLE);
         ratings.setRating(b.user_rating + 1);
         ((TextView) findViewById(R.id.item_rating_title)).setVisibility(
                                                               View.VISIBLE);
         this.updateRatingsText(b.user_rating + 1);
         estimated.setText(
            this.getResources().getString(R.string.item_details_ratings_est)
            + " " + Constants.RATING_NAMES[Math.round(b.generic_rating)]);
         ratings.setOnRatingBarChangeListener(this);
         if (!G.user.isLoggedIn()) {
            ratings.setEnabled(false);
         }
      }
      
      // init tags section
      this.updateTagViews();
      if (this.editing_mode) {
         RelativeLayout tags_new =
               (RelativeLayout) this.findViewById(R.id.item_tags_new);
         tags_new.setVisibility(View.VISIBLE);
         ((Button) findViewById(R.id.tag_edit_btn)).setOnClickListener(this);
         
         // populate autocomplete
         AutoCompleteTextView tag_edit_box =
               (AutoCompleteTextView) this.findViewById(R.id.tag_edit);
         ArrayList<String> all_tags = new ArrayList<String>();
         for (Tag t : Tag.all.values()) {
            all_tags.add(t.name);
         }
         ArrayAdapter<String> autocomplete_adapter =
               new ArrayAdapter<String>(
                     this,
                     android.R.layout.simple_dropdown_item_1line,
                     all_tags);
         tag_edit_box.setAdapter(autocomplete_adapter);
      }

      // init notes section
      this.updateNoteViews();
      if (this.editing_mode) {
         RelativeLayout notes_new =
               (RelativeLayout) this.findViewById(R.id.item_notes_new);
         notes_new.setVisibility(View.VISIBLE);
         ((Button) findViewById(R.id.note_edit_btn)).setOnClickListener(this);
      }
      // request link values
      this.geo.populateAttachments();
      
      // init bottom buttons
      if (this.editing_mode) {
         LinearLayout bottom =
               (LinearLayout) this.findViewById(R.id.bottom_btns);
         Button save_btn = (Button) findViewById(R.id.save_btn);
         Button discard_btn = (Button) findViewById(R.id.discard_btn);
         bottom.setVisibility(View.VISIBLE);
         save_btn.setOnClickListener(this);
         discard_btn.setOnClickListener(this);
      }
   }

   /**
    * Returns true if this geofeature or any of its attachments have been
    * edited.
    */
   public boolean isDirty() {
      return this.getDirtyItems().size() > 0;
   }

   /**
    * Begins the save process by checking if there is anything to save and
    * if the user is allowed to save.
    */
   public void save() {
      if (!this.isDirty()) {
         Toast.makeText(
               this,
               this.getResources().getString(R.string.item_nothing_to_save),
               Toast.LENGTH_SHORT).show();
         finish();
      } else {
         if (G.user.isBanned()) {
            G.showAlert(
                  this.getResources().getString(R.string.saving_ban_msg),
                  this.getResources().getString(R.string.saving_ban_title));
         } else {
            this.saveToServer(this.getDirtyItems());
         }
      }
   }

   /**
    * Save items to server.
    */
   public void saveToServer(ArrayList<ItemUserAccess> items) {
      new GWIS_Commit(
            items,
            this.getResources().getString(R.string.item_saving_title),
            this.getResources().getString(R.string.item_saving_msg),
            this).fetch();
   }

   /**
    * Find this geofeature in the global set of geofeatures currently in the
    * map.
    * @param stack_id
    */
   public void setGeoFeature(int stack_id) {
      this.geo = G.vectors_old_all.get(stack_id);
   }

   /**
    * Show confirmation dialog for discarding changes.
    */
   public void showDiscardMessage() {
      String message =
            this.getResources().getString(R.string.item_discard_msg);
      String title =
            this.getResources().getString(R.string.item_discard_title);
      new AlertDialog.Builder(this).setMessage(message).setTitle(title)
         .setNegativeButton(
               this.getResources().getString(R.string.item_discard_cancel),
               new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton){}
            })
         .setPositiveButton(
               this.getResources().getString(R.string.item_discard),
               new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton){
               discardCleanup();
               finish();
            }}).show();
   }

   /**
    * Updates the list of notes.
    */
   public void updateNoteViews() {
      LinearLayout notes_list =
            (LinearLayout) findViewById(R.id.item_notes_list);
      TextView notes_text = (TextView) findViewById(R.id.item_notes_text);
      
      ArrayList<Annotation> note_array = this.getNoteArray();
      
      if (!this.geo.notes_fetched) {
         notes_text.setText(
               getResources().getString(R.string.item_details_loading));
         notes_text.setVisibility(View.VISIBLE);
         notes_list.setVisibility(View.GONE);
      } else if (note_array.size() == 0) {
         if (this.editing_mode) {
            notes_text.setVisibility(View.GONE);
         } else {
            notes_text.setText(
                  getResources().getString(R.string.item_details_none));
            notes_text.setVisibility(View.VISIBLE);
         }
         notes_list.setVisibility(View.GONE);
      } else {
         notes_list.removeAllViews();
         for (Annotation annot : note_array) {
            notes_list.addView(this.createNoteView(annot));
         }
         notes_list.setVisibility(View.VISIBLE);
         notes_text.setVisibility(View.GONE);
      }
   }

   /**
    * Update the text below the ratings widget whenever a new rating is
    * selected.
    */
   public void updateRatingsText(float rating) {
      Byway b = (Byway) this.geo;
      b.user_rating = Math.round(rating - 1);
      TextView description =
            (TextView) findViewById(R.id.item_rating_description);
      if (!G.user.isLoggedIn()) {
         description.setText(getResources().getString(R.string.ratings_login));
      } else if (b.user_rating < 0) {
         description.setText(
            getResources().getString(R.string.rating_unknown));
      } else {
         description.setText(
            Constants.RATING_NAMES[Math.round(b.user_rating)]);
      }
   }

   /**
    * Updates the list of tags.
    */
   public void updateTagViews() {
      TextView tags_light = (TextView) this.findViewById(R.id.item_tags_text);
      LinearLayout tags_list =
            (LinearLayout) this.findViewById(R.id.item_tags_list);
      tags_list.setVisibility(View.GONE);
      
      ArrayList<Tag> tag_array = this.getTagsArray();
      
      if (!this.geo.tags_fetched) {
         tags_light.setText(
               getResources().getString(R.string.item_details_loading));
      } else if (tag_array.size() == 0) {
         if (this.editing_mode) {
            tags_light.setVisibility(View.GONE);
         } else {
            tags_light.setText(
               getResources().getString(R.string.item_details_none));
         }
      } else {
         if(!this.editing_mode) {
            StringBuilder tags = new StringBuilder();
            for (Tag tag : tag_array) {
               if (tags.length() > 0) {
                  tags.append(", ");
               }
               tags.append(tag.name);
            }
            tags_light.setText(tags);
         } else {
            tags_list.removeAllViews();
            for (Tag t : tag_array) {
               tags_list.addView(this.createTagView(t));
            }
            tags_list.setVisibility(View.VISIBLE);
            tags_light.setVisibility(View.GONE);
         }
      }
   }
}

/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android;

import org.cyclopath.android.conf.Constants;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.View.OnClickListener;
import android.view.Window;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Activity for viewing or editing note contents.
 * @author Fernando Torre
 */
public class NoteActivity extends BaseActivity
                          implements OnClickListener {

   /** Stack id of the current note */
   int note_id;
   /** Whether we are editing the note or not */
   boolean editing_mode;
   /** old note contents */
   String old_contents;

   /**
    * Sets the layout to show note contents.
    */
   @Override
   public void onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState);
      this.old_contents =
            getIntent().getStringExtra(Constants.NOTE_CONTENTS_STR);
      if (this.old_contents == null) {
         this.old_contents = "";
      }
      this.note_id = getIntent().getIntExtra(Constants.STACK_ID_STR, 0);
      this.editing_mode =
            getIntent().getBooleanExtra(Constants.EDIT_MODE, false);
      this.requestWindowFeature(Window.FEATURE_NO_TITLE);
      setContentView(R.layout.note_details);

      TextView content = (TextView) findViewById(R.id.note_contents);
      EditText content_edit = (EditText) findViewById(R.id.note_contents_edit);
      // set text
      if (!this.editing_mode) {
         content.setText(this.old_contents);
      } else {
         content.setVisibility(View.GONE);
         content_edit.setVisibility(View.VISIBLE);
         content_edit.setText(this.old_contents);
      }
      
      // set buttons
      if (this.editing_mode) {
         LinearLayout buttons =
               (LinearLayout) this.findViewById(R.id.bottom_btns);
         buttons.setVisibility(View.VISIBLE);
         Button discard_btn = (Button) this.findViewById(R.id.discard_btn);
         Button done_btn = (Button) this.findViewById(R.id.done_btn);
         discard_btn.setOnClickListener(this);
         done_btn.setOnClickListener(this);
      }
   }

   /**
    * Handles discarding or sending back changes to note.
    */
   @Override
   public void onClick(View v) {
      EditText content_edit =
            (EditText) findViewById(R.id.note_contents_edit);
      if (v == this.findViewById(R.id.discard_btn)) {
         if (this.isDirty()) {
            this.showDiscardMessage();
         } else {
            finish();
         }
      } else if (v == this.findViewById(R.id.done_btn)) {
         Intent intent = new Intent();
         intent.putExtra(Constants.STACK_ID_STR, this.note_id);
         intent.putExtra(Constants.NOTE_CONTENTS_STR,
                         content_edit.getText().toString());
         if (getParent() == null) {
            setResult(Activity.RESULT_OK, intent);
         } else {
            getParent().setResult(Activity.RESULT_OK, intent);
         }
         finish();
      }
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
    * Returns true if this note is different than before.
    * @return
    */
   public boolean isDirty() {
      EditText content_edit =
            (EditText) findViewById(R.id.note_contents_edit);
      return !this.old_contents.equals(content_edit.getText().toString());
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
               finish();
            }}).show();
   }
}

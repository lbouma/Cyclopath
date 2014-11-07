/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import android.app.Dialog;
import android.app.ListActivity;
import android.os.Bundle;
import android.os.Message;

/**
 * This class and BaseActivity are tied together by Base.java. They act
 * as base classes for activities that handle dialogs and alerts.
 * @author Fernando Torre
 */
public class BaseListActivity extends ListActivity {

   /**
    * The base object tied to this class.
    */
   public Base base = new Base(this);

   /**
    * Creates and restores activity.
    */
   @Override
   public void onCreate(Bundle in_state) {
      super.onCreate(in_state);
      base.onCreate(in_state);
   }
   
   /**
    * Called when a new dialog is created.
    */
   @Override
   public Dialog onCreateDialog(int id) {
      return base.onCreateDialog(id, this);
   }

   /**
    * Called when the activity is no longer active.
    */
   @Override
   public void onPause() {
      super.onPause();
      base.onPause();
   }
   
   /**
    * Called before a dialog is opened.
    */
   @Override
   public void onPrepareDialog(int id, Dialog dialog) {
      base.onPrepareDialog(id, dialog);
   }

   /**
    * Called when the activity becomes active.
    */
   @Override
   public void onResume() {
      super.onResume();
      base.onResume();
   }
   
   /**
    * Called when the activity is about to be stopped in order to allow saving
    * state information for the app.
    */
   @Override
   protected void onSaveInstanceState(Bundle out_state) {
      super.onSaveInstanceState(out_state);
      base.onSaveInstanceState(out_state);
   }
   
   /**
    * Shows an alert with a title and a message, with any mailto links enabled.
    * @param txt alert message
    * @param title alert title
    */
   public void showAlert(String txt, String title) {
      base.showAlert(txt, title);
   }
   
   /**
    * Shows an alert with a title and a message, with any mailto links enabled.
    * @param txt alert message
    * @param title alert title
    * @param iconId alert icon
    */
   public void showAlert(String txt, String title, int iconId) {
      base.showAlert(txt, title, iconId);
   }

   /**
    * Activites can implement this to handle Activity-specific messages.
    */
   public void handleMessage(Message msg) {
      // No-op
   }
}

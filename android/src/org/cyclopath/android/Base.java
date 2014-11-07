/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import org.cyclopath.android.conf.Constants;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.app.ProgressDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.res.Resources;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.text.SpannableString;
import android.text.method.LinkMovementMethod;
import android.text.util.Linkify;
import android.widget.TextView;
import android.widget.Toast;

/**
 * This class ties BaseActivity and BaseListActivity together. It is basically
 * a way to get around Java's restriction of multiple inheritance, since I
 * want classes that extend both types of activities to share this code.
 * @author Fernando Torre
 */
public class Base {
   
   /** identifier for update dialogs */
   public static final int UPDATE_DIALOG = 1;
   /** identifier for alert dialogs */
   public static final int ALERT_DIALOG = 2;
   /** Activity that this class is attached to */
   public Activity act;
   /** Dialog text to be used for next dialog */
   private String temp_txt;
   /** Dialog title to be used for next dialog */
   private String temp_title;
   /** Dialog icon to be used for next dialog */
   private int temp_icon;
   /** progress dialog used for long operations */
   protected ProgressDialog progress_dialog;
   /** common alert dialog */
   protected AlertDialog alert_dialog;
   /** alert dialog title*/
   private String dialog_title;
   /** alert dialog message*/
   private String dialog_message;
   /** whether an active progress dialog shows indeterminate progress */
   private boolean dialog_indeterminate;
   /** progress percentage of current progress dialog */
   private int dialog_progress;
   
   /**
    * Constructor
    * @param act Activity that this class is attached to.
    */
   public Base(Activity act) {
      this.act = act;
      this.temp_txt = "";
      this.temp_title = "";
      this.temp_icon = android.R.drawable.ic_dialog_alert;
   }
   
   /**
    * This handler receives and handles messages from threads that want to
    * display dialogs.
    */
   protected Handler baseHandler = new Handler() {
      @Override
      public void handleMessage(Message msg) {
         switch (msg.what) {
         case (Constants.BASE_UPDATE_NEEDED):
            requestUpdate();
            break;
         case (Constants.BASE_SHOW_ALERT):
            showAlert(msg.getData().getString(Constants.ALERT_MESSAGE),
                      msg.getData().getString(Constants.ALERT_TITLE),
                      msg.getData().getInt(Constants.ALERT_ICON,
                                        android.R.drawable.ic_dialog_alert));
            break;
         case (Constants.BASE_SHOW_TOAST):
            showToast(msg.getData().getString(Constants.TOAST_MESSAGE));
            break;
         case (Constants.BASE_REAUTHENTICATE):
            showReauthenticationDialog();
            break;
         case (Constants.BASE_SHOW_PROGESS_DIALOG):
            createProgressDialog(
                  msg.getData().getString(Constants.ALERT_TITLE),
                  msg.getData().getString(Constants.ALERT_MESSAGE),
                  msg.getData().getBoolean(Constants.DIALOG_INDETERMINATE,
                                           true),
                  0);
            break;
         case (Constants.BASE_DISMISS_PROGESS_DIALOG):
            if (progress_dialog != null) {
               progress_dialog.dismiss();
               progress_dialog = null;
            }
            break;
         case (Constants.BASE_UPDATE_PROGESS_DIALOG):
            if (progress_dialog != null) {
               dialog_title = msg.getData().getString(Constants.ALERT_TITLE);
               dialog_message =
                  msg.getData().getString(Constants.ALERT_MESSAGE);
               int progress = msg.getData().getInt(Constants.DIALOG_PROGRESS);
               progress_dialog.setTitle(dialog_title);
               progress_dialog.setMessage(dialog_message);
               progress_dialog.setProgress(progress);
            }
            break;
         case (Constants.BASE_SHOW_SHARE_ROUTE_CHOOSER):
            showRouteSharingChooser(
                  msg.getData().getString(Constants.ROUTE_URL));
            break;
         }
      }
   };
   
   /**
    * Creates a new progress dialog.
    * @param title
    * @param message
    * @param indeterminate If false, progress percentage is shown.
    * @param progress
    */
   public void createProgressDialog(String title, String message,
                                    boolean indeterminate, int progress) {
      if (title == null) {
         return;
      }
      this.dialog_title = title;
      this.dialog_message = message;
      this.dialog_indeterminate = indeterminate;
      this.dialog_progress = progress;
      this.progress_dialog = new ProgressDialog(this.act);
      this.progress_dialog.setTitle(this.dialog_title);
      this.progress_dialog.setMessage(this.dialog_message);
      this.progress_dialog.setIndeterminate(this.dialog_indeterminate);
      this.progress_dialog.setCancelable(true);
      if (!this.dialog_indeterminate) {
         this.progress_dialog.setProgressStyle(
               ProgressDialog.STYLE_HORIZONTAL);
      }
      if (G.cancel_handler != null) {
         this.progress_dialog.setOnCancelListener(G.cancel_handler);
      }
      this.progress_dialog.show();
   }
   
   /**
    * Restores any active dialog that was being displayed before.
    */
   public void onCreate(Bundle in_state) {
      if (in_state != null) {
         createProgressDialog(in_state.getString("dialog_title"),
                              in_state.getString("dialog_message"),
                              in_state.getBoolean("dialog_indeterminate"),
                              in_state.getInt("dialog_progress"));
      }
   }
   
   /**
    * Creates dialog to be displayed.
    * @param id
    * @param context
    * @return
    */
   public Dialog onCreateDialog(int id, final Context context) {
      Dialog dialog;
      switch(id) {
      case UPDATE_DIALOG:
         dialog = new AlertDialog.Builder(context)
         .setTitle(context.getResources().getString(
               R.string.update_required_title))
         .setMessage(context.getResources().getString(
               R.string.update_required_text))
         .setNegativeButton(context.getResources().getString(
                               R.string.update_required_exit_btn),
                            new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton){
               System.runFinalizersOnExit(true);
               System.exit(0);
            }
         })
         .setPositiveButton(context.getResources().getString(
                               R.string.update_required_btn),
                            new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int whichButton){
               Intent updateIntent =
                  new Intent(Intent.ACTION_VIEW, 
                             Uri.parse(Constants.MARKET_DETAILS));
               context.startActivity(updateIntent);
            }
         }).setCancelable(false).create();
          break;
      case ALERT_DIALOG:
         final SpannableString message = new SpannableString(this.temp_txt);
         // Linkify mailto links
         Linkify.addLinks(message, Linkify.EMAIL_ADDRESSES);
         dialog = new AlertDialog.Builder(context)
            .setMessage(message)
            .setTitle(this.temp_title)
            .setIcon(this.temp_icon)
            .setCancelable(false)
            .setNeutralButton("OK", new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int id) {
                  dialog.dismiss();
               }
            }).create();
         this.alert_dialog = (AlertDialog) dialog;
         break;
      default:
          dialog = null;
      }
      return dialog;
   }
   
   /**
    * Removes this instance as the global handler if the activity is paused.
    */
   public void onPause() {
      if (G.base_handler == this.baseHandler) {
         G.base_handler = null;
      }
   }

   /**
    * Updates previously existing dialogs.
    * @param id
    * @param dialog
    */
   public void onPrepareDialog(int id, Dialog dialog) {
      switch(id) {
      case ALERT_DIALOG:
         final SpannableString message = new SpannableString(this.temp_txt);
         // Linkify mailto links
         Linkify.addLinks(message, Linkify.EMAIL_ADDRESSES);
         dialog.setTitle(this.temp_title);
         ((AlertDialog) dialog).setMessage(message);
         ((AlertDialog) dialog).setIcon(this.temp_icon);
         break;
      }
   }
   
   /**
    * Sets this instance as the global handler if the activity is active.
    */
   public void onResume() {
      G.base_handler = this.baseHandler;
   }

   /**
    * Called when the activity is about to be stopped in order to allow saving
    * state information for the app.
    */
   protected void onSaveInstanceState(Bundle out_state) {
      if (progress_dialog != null) {
         out_state.putString("dialog_title", this.dialog_title);
         out_state.putString("dialog_message", this.dialog_message);
         out_state.putBoolean("dialog_indeterminate",
                              this.dialog_indeterminate);
         out_state.putInt("dialog_progress", this.dialog_progress);
      }
   }

   /**
    * Shows the reauthentication activity.
    */
   public void showReauthenticationDialog() {
      Intent intent = new Intent(this.act, LoginActivity.class);
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      this.act.startActivity(intent);
   }
   
   /**
    * Shows dialog for sharing a route
    */
   public void showRouteSharingChooser(String url) {
      Intent shareIntent = new Intent(android.content.Intent.ACTION_SEND);
      shareIntent.setType("text/plain");
      String name;
      Resources res = G.app_context.getResources();
      if(G.user.isLoggedIn()) {
         name = G.user.getName();
      }
      else {
         name = res.getString(R.string.route_share_default_user);
      }
      String body = res.getString(R.string.route_share_text) + url;
      shareIntent.putExtra(android.content.Intent.EXTRA_SUBJECT,
      name + " " + res.getString(R.string.route_share_subject));
      shareIntent.putExtra(android.content.Intent.EXTRA_TEXT, body);
      this.act.startActivity(Intent.createChooser(shareIntent,
            res.getString(R.string.route_share_mail_chooser_title)));
   }
   
   /**
    * Shows the dialog that requires users to update their application.
    */
   public void requestUpdate() {
      if (G.base_handler != this.baseHandler) {
         return;
      }
      this.act.showDialog(UPDATE_DIALOG);
   }
   
   /**
    * Shows an alert with a title and a message, with any mailto links enabled.
    * @param txt alert message
    * @param title alert title
    */
   public void showAlert(String txt, String title) {
      this.showAlert(txt, title, android.R.drawable.ic_dialog_alert);
   }

   /**
    * Shows an alert with a title and a message, with any mailto links enabled.
    * @param txt alert message
    * @param title alert title
    * @param iconId alert icon
    */
   public void showAlert(String txt, String title, int iconId) {
      this.temp_txt = txt;
      this.temp_title = title;
      this.temp_icon = iconId;
      this.act.showDialog(ALERT_DIALOG);

      TextView msg =
         (TextView) this.alert_dialog.findViewById(android.R.id.message);
      msg.setMovementMethod(LinkMovementMethod.getInstance());
   }
   
   /**
    * Shows a toast message.
    * @param txt
    */
   public void showToast(String txt) {
      Toast.makeText(this.act, txt, Toast.LENGTH_SHORT).show();
   }
}

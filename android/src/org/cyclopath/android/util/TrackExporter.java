/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.util;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.regex.Pattern;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.items.Track;

import android.app.Activity;
import android.app.ProgressDialog;
import android.content.Context;
import android.os.Environment;
import android.util.Log;

/**
 * Exports tracks to external storage.
 * @author Fernando Torre
 */
public class TrackExporter {
   
   /** track to be exported */
   private Track track;
   /** context for this action */
   private Context context;
   /** saving progress dialog */
   private ProgressDialog progress_dialog;
   /** contains any error that might have occurred during track export */
   private String error;
   /** contains the path and name of file saved */
   private String filename;
   
   /**
    * Constructor.
    */
   public TrackExporter(Track t, Context context) {
      this.track = t;
      this.context = context;
   }

   /**
    * Begins a thread that exports a track as GPX.
    */
   public void exportGPX() {
      this.error = null;
      this.progress_dialog = ProgressDialog.show(this.context,
         G.app_context.getResources().getString(R.string.export_track_title),
         G.app_context.getResources().getString(R.string.export_track_msg),
         true);

      Thread t = new Thread() {
         @Override
         public void run() {
            writeGPX();
         }
      };
      t.start();
   }

   /**
    * Writes a track to external storage as GPX.
    */
   public void writeGPX() {
      File gpxfile = null;
      this.filename = "";
      try {
         File dir = new File (Environment.getExternalStorageDirectory()
                    + Constants.CP_DIRECTORY);
         dir.mkdirs();
         
         String state = Environment.getExternalStorageState();
         if (state.equals(Environment.MEDIA_MOUNTED)) {
            if (dir.canWrite()){
               // replace backslashes with underscores
               String name = Pattern.compile("[/:]")
                                    .matcher(this.track.name)
                                    .replaceAll("_");
               // remove unwanted chars
               name = Constants.PROHIBITED_CHARS.matcher(name)
                                                .replaceAll("");
               if (name.length() == 0) {
                  // Use generic name if needed
                  name = Constants.GENERIC_TRACK_NAME;
               }
               
               gpxfile = new File(dir, name + ".gpx");
               // if the file exists, modify the name to make it unique
               int num = 1;
               while (gpxfile.exists()) {
                  gpxfile = new File(dir, name + " (" + num++ + ").gpx");
               }
               
               FileWriter gpxwriter = new FileWriter(gpxfile);
               BufferedWriter out = new BufferedWriter(gpxwriter);
               out.write(this.track.asGPX());
               out.close();
            }
         } else if (state.equals(Environment.MEDIA_SHARED)) {
            this.error = G.app_context.getResources().getString(
                           R.string.track_export_fail_media_shared);
         } else {
            this.error = G.app_context.getResources().getString(
                           R.string.track_export_fail);
         }
      } catch (IOException e) {
         Log.e("error", "Could not write file " + e.getMessage());
         this.error = G.app_context.getResources().getString(
               R.string.track_export_io_fail);
      }
      if (gpxfile != null) {
         filename = gpxfile.getName();
      }
      
      progress_dialog.dismiss();
      
      if (this.context instanceof Activity) {
         ((Activity) this.context).runOnUiThread(new Runnable() {
            @Override
            public void run() {
               if (error != null) {
                  G.showAlert(error,
                              G.app_context.getResources().getString(
                                    R.string.track_export_fail));
               } else {
                  G.showAlert(G.app_context.getResources().getString(
                                    R.string.track_exported_msg)
                                 + Constants.CP_DIRECTORY + "/" + filename,
                              G.app_context.getResources().getString(
                                    R.string.track_exported_title),
                              android.R.drawable.ic_dialog_info);

                  G.server_log.event("mobile/ui/export_track",
                        new String[][]{{"id",
                                        Integer.toString(track.stack_id)}});
               }
            }
         });
      }
   }
}

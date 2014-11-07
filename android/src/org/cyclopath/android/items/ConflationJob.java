/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.Timer;
import java.util.TimerTask;

import android.content.DialogInterface;
import android.content.DialogInterface.OnCancelListener;
import android.os.Handler;
import android.os.Message;
import android.util.SparseIntArray;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.AccessInfer;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.gwis.GWIS_Checkout;
import org.cyclopath.android.gwis.GWIS_CheckoutCallback;
import org.cyclopath.android.gwis.GWIS_CommitCallback;
import org.cyclopath.android.gwis.GWIS_Commit;
import org.cyclopath.android.gwis.QueryFilters;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;

/**
 * This class represents a track conflation job.
 * @author Fernando
 */
public class ConflationJob extends ItemUserAccess
                           implements GWIS_CommitCallback,
                                      GWIS_CheckoutCallback,
                                      OnCancelListener{
   
   /** The id of the track to conflate */
   public int track_id;
   /** The conflated ride */
   public Route route;
   
   /** The job action */
   public String job_act;
   /** Number of stages in this job */
   public int num_stages;
   /** The number of the stage we are in now */
   public int stage_num;
   /** The name of the stage we are in now */
   public String stage_name;
   /** Message describing the current job state */
   public String stage_msg;
   /** The current stage's progress */
   public int stage_progress;
   /** The job's status text */
   public String status_text;
   /** The job's status code */
   public int status_code;
   /** Whether the job has completed */
   public boolean job_finished;
   
   /** Whether we should continue to send progress requests */
   public boolean get_progress;
   
   /**
    * This handler receives and handles messages from the thread that
    * communicates with the server.
    */
   protected static ConflationHandler mHandler;

   /**
    * Handler for this class that uses weak references to avoid memory leaks.
    */
   protected static class ConflationHandler extends Handler {
      
      /** Weak reference to ConflationJob class */
      private WeakReference<ConflationJob> ref;

      /**
       * Constructor
       * @param job
       */
      public ConflationHandler(ConflationJob job) {
         this.ref = new WeakReference<ConflationJob>(job);
      }

      /**
       * Forwards the message to the ConflationJob class, if it exists.
       */
      @Override
      public void handleMessage(Message msg) {
         ConflationJob job = this.ref.get();
         if (job != null) {
            job.handleMessage(msg);
         }
      }
   }

   /**
   * Constructor using XML data.
   * @param root
   */
   public ConflationJob(Node root) {
      super(root);
      this.gmlConsume(root);
   }
   
   /**
    * Constructor using id of track to be conflated.
    * @param track_id
    */
   public ConflationJob(int track_id) {
      super(null);
      this.track_id = track_id;
      this.job_act = "create";
      this.get_progress = true;
      ConflationJob.mHandler = new ConflationHandler(this);
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.CONFLATION_JOB;
   }

   /**
    * Returns the access style for this item.
    */
   @Override
   public int getStyleId() {
      return AccessInfer.usr_editor;
   }

   /**
    * Populates this ConflationJob from an XML
    * @param root
    */
   @Override
   public void gmlConsume(Node root) {
      if (root != null) {
         NamedNodeMap atts = root.getAttributes();
         this.stack_id = XmlUtils.getInt(atts, "stid", this.stack_id);
         this.stage_name = XmlUtils.getString(atts, "stage_name", null);
         this.stage_msg = XmlUtils.getString(atts, "job_stage_msg", null);
         this.stage_progress = XmlUtils.getInt(atts, "stage_progress", 0);
         this.status_text = XmlUtils.getString(atts, "status_text", null);
         this.num_stages = XmlUtils.getInt(atts, "num_stages", 0);
         this.stage_num = XmlUtils.getInt(atts, "stage_num", 0);
         this.status_code = XmlUtils.getInt(atts, "status_code", 0);
         this.job_finished = XmlUtils.getInt(atts, "job_finished", 0) == 1;
         if (root.getChildNodes().getLength() > 1) {
            this.route = new Route(root.getChildNodes().item(1));
         }
      }
   }

   /**
    * Returns an XML String representing this ConflationJob.
    */
   @Override
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      document.renameNode(root, null, "conflation_job");
      root.removeAttribute("name");
      root.setAttribute("job_act", this.job_act);
      root.setAttribute("email_on_finish", "0");
      root.setAttribute("track_id", Integer.toString(this.track_id));
      return document;
   }
   
   /**
    * If progress is complete, download the ride.
    * If we have downloaded the ride, show it.
    * If progress is incomplete, update the progress dialog and schedule
    * another progress request.
    */
   @Override
   public void handleGWIS_CheckoutComplete(ArrayList<ItemUserAccess> feats) {
      if (feats.get(0).getClass().getName().equals(
            ConflationJob.class.getName())) {
         ConflationJob job = (ConflationJob)feats.get(0);
         if (job.job_finished && job.status_code == 2) {
            // We failed. Show error message and dismiss progress dialog.
            G.dismissProgressDialog();
            if (job.stage_msg != null) {
               G.showAlert(job.stage_msg,
                           G.app_context.getResources().getString(
                                 R.string.track_conflate_error));
            }
            return;
         }
         if (job.route != null) {
            G.dismissProgressDialog();
            G.setActiveRoute(job.route);
            // Notify handlers of conflation completion.
            if (G.cyclopath_handler != null) {
               Message msg = Message.obtain();
               msg.what = Constants.CONFLATION_COMPLETE;
               msg.setTarget(G.cyclopath_handler);
               msg.sendToTarget();
            }
            if (G.track_manager_handler != null) {
               Message msg = Message.obtain();
               msg.what = Constants.CONFLATION_COMPLETE;
               msg.setTarget(G.track_manager_handler);
               msg.sendToTarget();
            }
            return;
         }
         // update progress dialog
         if (job.stage_num > 2) {
            // We want to keep the progress at 100% after the conflation stage.
            job.stage_progress = 100;
         }
         if (!job.job_finished) {
            G.updateProgressDialog(
                  G.app_context.getString(
                        R.string.track_conflate_progress_dialog_title),
                  job.stage_name,
                  job.stage_progress);
            if (this.get_progress) {
               new Timer().schedule(new ProgressRequestTask(),
                                    Constants.PROGRESS_REQUEST_WAIT_TIME);
            }
         } else {
            // do download if job is complete
            G.cancel_handler = null;
            QueryFilters qfs = new QueryFilters();
            qfs.only_stack_ids = new int[]{this.stack_id};
            qfs.include_item_aux = true;
            GWIS_Checkout gwis_request =
               new GWIS_Checkout("conflation_job", qfs, this);
            gwis_request.fetch();
         }
      }
   }

   /**
    * Stores the new id for the job and schedules a progress request.
    */
   @Override
   public void handleGWIS_CommitCallback(SparseIntArray id_map) {
      // get job id
      if (id_map != null) {
         this.stack_id = id_map.get(this.stack_id);
         new Timer().schedule(new ProgressRequestTask(),
                              Constants.PROGRESS_REQUEST_WAIT_TIME);
      }
   }

   /**
    * Handles messages from conflation thread.
    * @param msg
    */
   public void handleMessage(Message msg) {
       switch (msg.what) {
          case (Constants.HANDLE_TIMEOUT):
             sendProgressRequest();
             break;
       }
   }

   @Override
   /**
    * Stops sending progress requests if the dialog was canceled.
    */
   public void onCancel(DialogInterface dialog) {
      G.cancel_handler = null;
      this.get_progress = false;
   }

   /**
    * Begins the conflation request.
    */
   public void runJob() {
      // start progress dialog
      G.cancel_handler = this;
      G.showProgressDialog(
            G.app_context.getString(
                  R.string.track_conflate_progress_dialog_title),
            G.app_context.getString(
                  R.string.track_conflate_progress_dialog_content),
            false);
      // send initial request
      ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
      items.add(this);
      new GWIS_Commit(items, "", "", this).fetch();
   }

   /**
    * Send a progress request
    */
   public void sendProgressRequest() {
      QueryFilters qfs = new QueryFilters();
      qfs.only_stack_ids = new int[]{this.stack_id};
      GWIS_Checkout gwis_request =
         new GWIS_Checkout("conflation_job", qfs, this);
      gwis_request.fetch();
   }

   /**
    * Task that sends the signal for sending a progress request.
    */
   private class ProgressRequestTask extends TimerTask  {
      @Override
      public void run () {
         Message msg = Message.obtain();
         msg.what = Constants.HANDLE_TIMEOUT;
         msg.setTarget(ConflationJob.mHandler);
         msg.sendToTarget();
      }
    }
}

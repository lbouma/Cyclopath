/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.Date;

import org.cyclopath.android.conf.Constants;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.view.View;
import android.view.View.OnClickListener;

/**
 * Agreement screen for Landmarks Experiment.
 * @author Fernando Torre
 */
public class ExperimentAgreement extends BaseActivity
                                 implements OnClickListener {

   /**
    * Goes back to the main map after returning from the login activity.
    */
   @Override
   protected void onActivityResult(int requestCode,
                                   int resultCode,
                                   Intent data) {
      if (G.user.isLoggedIn()) {
         this.setAgree(true);
         this.finish();
      }
   }

   /**
    * Sets layout and listeners.
    */
   @Override
   public void onCreate(Bundle savedInstanceState){
      super.onCreate(savedInstanceState);
      setContentView(R.layout.experiment_agreement);
      findViewById(R.id.agree_button).setOnClickListener(this);
      findViewById(R.id.cancel_button).setOnClickListener(this);
      G.server_log.event("mobile/landmarks",
            new String[][]{{"agreement_view",
                            "t"}});
   }//onCreate

   /**
    * Handles button clicks.
    */
   @Override
   public void onClick(View v) {
      if (v == findViewById(R.id.agree_button)) {
         if (G.user.isLoggedIn()) {
            this.setAgree(true);
            this.finish();
         } else {
            Intent intent = new Intent(this, LoginActivity.class);
            startActivityForResult(intent, 0);
         }
      } else {
         this.setAgree(false);
         this.finish();
      }
   }

   /**
    * Sets the expiration date on the user's agreement to participate in
    * the landmarks experiment.
    */
   public void setAgree(boolean agreed) {
      SharedPreferences.Editor editor = G.cookie.edit();
      if (agreed) {
         editor.putLong(Constants.LANDMARKS_EXP_AGREE,
            (new Date()).getTime() + (Constants.LANDMARK_AGREEMENT_DURATION));
         editor.putBoolean(Constants.LANDMARKS_EXP_SHOW, false);
         G.server_log.event("mobile/landmarks",
               new String[][]{{"agreement_agree",
                               "t"}});
      } else {
         editor.putLong(Constants.LANDMARKS_EXP_AGREE, 0);
         G.server_log.event("mobile/landmarks",
               new String[][]{{"agreement_agree",
                               "f"}});
      }
      editor.commit();
   }
   
}//UserAgreement

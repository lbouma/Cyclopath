/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import org.cyclopath.android.conf.Constants;

import android.content.SharedPreferences.Editor;
import android.os.Bundle;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.method.LinkMovementMethod;
import android.text.style.URLSpan;
import android.view.View;
import android.view.View.OnClickListener;
import android.widget.Button;
import android.widget.TextView;

/**
 * This activity displays basic terms of service, with a link to the Cyclopath
 * user agreement. If the user has not yet agreed to these terms, it also
 * displays a button for the user to agree.
 * @author Phil Brown
 * @author Fernando Torre
 */
public class UserAgreement extends BaseActivity {
   
   @Override
   public void onCreate(Bundle savedInstanceState){
      super.onCreate(savedInstanceState);
      setContentView(R.layout.user_agreement);
      final Button agree = (Button) findViewById(R.id.agree_button);
      TextView terms_link = (TextView) findViewById(R.id.terms_link);
      
      String agree1 = getResources().getString(R.string.agreement_end1) + " ";
      String agree2 = getResources().getString(R.string.agreement_end2);
      SpannableString str = SpannableString.valueOf(agree1 + agree2);
      str.setSpan(new URLSpan(Constants.AGREEMENT_URL),
                  agree1.length(), str.length() -1,
                  Spannable.SPAN_INCLUSIVE_EXCLUSIVE);
      terms_link.setText(str);
      terms_link.setMovementMethod(LinkMovementMethod.getInstance());
      
      if(G.cookie_anon.getBoolean(Constants.COOKIE_HAS_AGREED_TO_TERMS,
                                  false)) {
         agree.setVisibility(View.GONE);
         agree.setEnabled(false);
      } 
      else {
         agree.setOnClickListener(new OnClickListener(){
            @Override
            public void onClick(View v) {
               agree.setText(getResources().getString(
                     R.string.user_agreement_starting_cyclopath));
               Editor editor = G.cookie_anon.edit();
               editor.putBoolean(Constants.COOKIE_HAS_AGREED_TO_TERMS, true);
               editor.commit();
               finish();
            }
         });
      }
   }//onCreate
   
}//UserAgreement

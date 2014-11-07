/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.util.Address;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.View.OnClickListener;
import android.view.View.OnKeyListener;
import android.view.ViewGroup;
import android.widget.AutoCompleteTextView;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.TextView;

/**
 * Activity that allows a user to choose from a list of addresses for
 * disambiguation.
 * @author Fernando Torre
 */
public class AddressChooseActivity extends BaseActivity
                                   implements OnKeyListener, OnClickListener {
   
   /** list of lists of radio buttons. Each inner list has the radio buttons
    * for one radio button group. */
   private ArrayList<ArrayList<RadioButton>> address_radio_btns;
   /** List of radio button groups. */
   private ArrayList<RadioGroup> address_radio_groups;
   /** List of autocomplete boxes. */
   private ArrayList<AutoCompleteTextView> address_edit_texts;
   /** List of addresses for disambiguation */
   private ArrayList<Address> addrs;

   // *** Listeners

   /**
    * Handles clicks.
    */
   @Override
   public void onClick(View v) {
      if (v == findViewById(R.id.address_choose_route_finder_btn)) {
         this.submit();
      }
   }

   /**
    * Creates and initialize address disambiguation window.
    */
   @Override
   public void onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState);
      
      setContentView(R.layout.address_choose);
      
      // get list of addresses and texts from parcel
      this.addrs =
         getIntent().getParcelableArrayListExtra(Constants.CHOOSE_ADDRESSES);
      ArrayList<String> texts =
         getIntent().getStringArrayListExtra(Constants.CHOOSE_TEXTS);
      
      this.address_radio_btns = new ArrayList<ArrayList<RadioButton>>();
      this.address_radio_groups = new ArrayList<RadioGroup>();
      this.address_edit_texts = new ArrayList<AutoCompleteTextView>();
      
      // Initialize layout based on number of addresses and options per address.
      LinearLayout box =
         (LinearLayout) findViewById(R.id.address_choose_main_box);
      for (int i = 0; i < this.addrs.size(); i++) {
         // For each address, initialize radio buttons for each choice and a
         // final radio button for text input.
         ArrayList<RadioButton> new_btns = new ArrayList<RadioButton>();
         Address addr = this.addrs.get(i);

         // Add text with instructions.
         TextView text = new TextView(this);
         text.setText(texts.get(i));
         box.addView(text);
         
         // Add radio buttons
         LinearLayout.LayoutParams params = new RadioGroup.LayoutParams (
               RadioGroup.LayoutParams.FILL_PARENT,
               RadioGroup.LayoutParams.WRAP_CONTENT);
         RadioGroup address_group = new RadioGroup(this);
         for (int k = 0; k < addr.addr_choices.size(); k++) {
            RadioButton option = new RadioButton(this);
            option.setText(addr.addr_choices.get(k).text);
            address_group.addView(option, k, params);
            option.setChecked(k == 0);
            new_btns.add(option);
         }
         RadioButton option = new RadioButton(this);
         option.setText(R.string.address_choose_other);
         address_group.addView(option, addr.addr_choices.size(), params);
         new_btns.add(option);
         box.addView(address_group);
         
         // add and initialize autocomplete
         AutoCompleteTextView other_text = new AutoCompleteTextView(this);
         other_text.setText(addr.text);
         box.addView(other_text, params);
         other_text.setOnKeyListener(this);
         
         // add hit count text if present
         if (addr.hit_count_text.length() > 0) {
            text = new TextView(this);
            text.setText(addr.hit_count_text);
            box.addView(text);
         }
         
         this.address_radio_groups.add(address_group);
         this.address_radio_btns.add(new_btns);
         this.address_edit_texts.add(other_text);
      }
      
      // dummy textview to take focus way from edittext.
      ViewGroup.LayoutParams params = new ViewGroup.LayoutParams (1,1);
      TextView dummy = new TextView(this);
      box.addView(dummy, 0, params);
      dummy.setFocusable(true);
      dummy.setFocusableInTouchMode(true);

      findViewById(R.id.address_choose_route_finder_btn)
         .setOnClickListener(this);
   }

   /**
    * Intercepts key event in order to change the selected radio button to
    * 'other' if the user starts editing the text.
    */
   @Override
   public boolean onKey(View v, int keyCode, KeyEvent event) {
      if (v instanceof AutoCompleteTextView) {
         for (int i = 0 ; i < this.address_edit_texts.size(); i++) {
            if (this.address_edit_texts.get(i) == v) {
               ArrayList<RadioButton> btns = this.address_radio_btns.get(i);
               btns.get(btns.size() - 1).setChecked(true);
               break;
            }
         }
      }
      return false;
   }

   // *** Other methods

   /**
    * Validate and send results back to appropriate handler.
    */
   public void submit() {
      
      ArrayList<Address> new_addresses = new ArrayList<Address>();
      
      // Add selected addresses to list
      for (int i = 0; i < this.addrs.size(); i++) {
         ArrayList<RadioButton> btns = this.address_radio_btns.get(i);
         for (int j = 0; j < btns.size(); j++) {
            if (btns.get(j).isChecked()) {
               if (j == btns.size() - 1) {
                  // Other
                  AutoCompleteTextView input = this.address_edit_texts.get(i);
                  // validate input
                  if (input.getText().length() == 0) {
                     showAlert(
                        this.getResources().getString(
                              R.string.route_finder_other_not_validated),
                        this.getResources().getString(R.string.error));
                     return;
                  }
                  new_addresses.add(new Address(input.getText().toString()));
               } else {
                  // selection
                  Address a = this.addrs.get(i).addr_choices.get(j);
                  a.geocoded = true;
                  new_addresses.add(a);
               }
               break;
            }
         }
      }
      
      // return to previous activity with results
      Intent data = new Intent();
      data.putParcelableArrayListExtra(Constants.CHOOSE_ADDRESSES,
                                       new_addresses);
      if (getParent() == null) {
         setResult(Activity.RESULT_OK, data);
      } else {
         getParent().setResult(Activity.RESULT_OK, data);
      }
      finish();
   }}

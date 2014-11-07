/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_Geocode;
import org.cyclopath.android.gwis.GWIS_GeocodeCallback;
import org.cyclopath.android.gwis.GWIS_RouteGetCallback;
import org.cyclopath.android.gwis.GWIS_RouteGetNew;
import org.cyclopath.android.items.Route;
import org.cyclopath.android.util.Address;
import org.cyclopath.android.util.PointD;
import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.SharedPreferences.Editor;
import android.content.res.Configuration;
import android.os.Bundle;
import android.view.View;
import android.view.View.OnClickListener;
import android.widget.ArrayAdapter;
import android.widget.AutoCompleteTextView;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.SeekBar;
import android.widget.SeekBar.OnSeekBarChangeListener;

/**
 * Activity that allows users to request routes. This class was based in part
 * on methods in flashclient/Route_Finder_UI.as
 * @author Fernando Torre
 * @author Phil Brown
 */
public class FindRouteActivity extends BaseActivity
                               implements OnClickListener,
                                          OnSeekBarChangeListener,
                                          GWIS_GeocodeCallback,
                                          GWIS_RouteGetCallback {
   
   /** starting address */
   public Address from_addr;
   /** destination address */
   public Address to_addr;
   /** Input view for starting address */
   private AutoCompleteTextView auto_complete_from;
   /** Input view for destination address */
   private AutoCompleteTextView auto_complete_to;
   /** what special action, if any, was requested by the intent */
   private String action;
   
   /** Request code used when calling the Address choosing activity */
   private static final int ADDRESS_CHOOSE_REQUEST_CODE = 1;
   
   // *** Listeners

   /**
    * Handles the results from the address choosing activity.
    */
   @Override
   protected void onActivityResult(int requestCode,
                                   int resultCode,
                                   Intent data) {
      if (resultCode == Activity.RESULT_OK) {
         if (requestCode == ADDRESS_CHOOSE_REQUEST_CODE) {
            // Processes the results of disambiguation.
            this.finishAddressChoose(data);
         }
      }
   }

   /**
    * Processes user clicks.
    */
   @Override
   public void onClick(View v) {
      if (v == findViewById(R.id.route_finder_btn)) {
         submit();
      }
   }

   /**
    * Sets up the FindRoute Activity.
    */
   @Override
   public void onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState);
      setContentView(R.layout.findroute);
      Intent intent = this.getIntent();
      double x_coord = intent.getDoubleExtra("x", Constants.MAP_CENTER_X);
      double y_coord = intent.getDoubleExtra("y", Constants.MAP_CENTER_Y);
      this.action = intent.getStringExtra(Constants.FINDROUTE_ACTION);
      
      // Set up button listener
      Button button = (Button)findViewById(R.id.route_finder_btn);
      button.setOnClickListener(this);
      
      clearGeocoded();
      
      // Set the priority slider's value and listener
      SeekBar slider = ((SeekBar) findViewById(R.id.route_finder_slider));
      slider.setProgress(Math.round(G.user.rf_priority * 8));
      slider.setOnSeekBarChangeListener(this);
      G.user.rfPrefsBackup();
      
      boolean checked =
         G.cookie_anon.getBoolean(Constants.COOKIE_FIND_ROUTE_REMEMBER_CHECKED,
                                  false);
      ((CheckBox)findViewById(R.id.route_finder_remember)).setChecked(checked);
      
      // Populate autocomplete
      Map<String, ?> map = G.autocomplete.getAll();

      // Delete old addresses if more than the max
      if (map.size() > Constants.MAX_AUTOCOMPLETE_ADDRESSES) {
         int new_amount = Math.round(Constants.MAX_AUTOCOMPLETE_ADDRESSES
                           * Constants.PERCENT_TO_KEEP_AUTOCOMPLETE_ADDRESSES);
         ArrayList<Map.Entry<String,?>> list =
            new ArrayList<Map.Entry<String,?>>(map.entrySet());
         
         // comparator for sorting from oldest to newest
         Comparator<Map.Entry<String,?>> comparator =
            new Comparator<Map.Entry<String,?>>() {
            @Override
            public int compare(Entry<String, ?> o1, Entry<String, ?> o2) {
               return o1.getValue().toString()
                        .compareTo(o2.getValue().toString());
            }
         };
         Collections.sort(list, comparator);

         SharedPreferences.Editor editor = G.autocomplete.edit();
         // remove oldest entries
         for (int i = 0; i < map.size() - new_amount; i++) {
            editor.remove(list.get(i).getKey());
         }
         editor.commit();
      }
      Set<String> auto_addresses = (Set<String>)map.keySet();

      // Create and set adapters for autocomplete.
      ArrayAdapter<String> adapter =
         new ArrayAdapter<String>(this,
                                  android.R.layout.simple_dropdown_item_1line,
                                  auto_addresses.toArray(new String[0]));
      this.auto_complete_from =
         (AutoCompleteTextView)findViewById(R.id.route_finder_from_box);
      this.auto_complete_to =
         (AutoCompleteTextView)findViewById(R.id.route_finder_to_box);
      this.auto_complete_from.setAdapter(adapter);
      this.auto_complete_to.setAdapter(adapter);
      
      //If the user's current location is known, display hint
      if (G.withinBounds()){
         this.auto_complete_from.setHint(
               getResources().getString(R.string.current_location));
      }
      
      if (this.action != null) {
         if (this.action.equals(Constants.FINDROUTE_ROUTE_FROM_ACTION)) {
            this.from_addr.x = x_coord;
            this.from_addr.y = y_coord;
            this.from_addr.geocoded = true;
            this.from_addr.text = getString(R.string.custom_location);
            this.auto_complete_from.setText(
                  getString(R.string.custom_location));
         } else if(this.action.equals(Constants.FINDROUTE_ROUTE_TO_ACTION)) {
            this.to_addr.x = x_coord;
            this.to_addr.y = y_coord;
            this.to_addr.geocoded = true;
            this.to_addr.text = getString(R.string.custom_location);
            this.auto_complete_to.setText(
                  getString(R.string.custom_location));
         }
      }
   }
   
   /** Handle screen rotations*/
   @Override
   public void onConfigurationChanged(Configuration newConfig) {
      super.onConfigurationChanged(newConfig);
   }

   /**
    * Called whenever the priority slider is changed.
    */
   @Override
   public void onProgressChanged(SeekBar seekBar,
                                 int progress,
                                 boolean fromUser) {
      G.user.rf_priority = progress / 8.0f;
   }

   /**
    * Method required by OnSeekBarChangeListener, but not used in this class.
    */
   @Override
   public void onStartTrackingTouch(SeekBar seekBar) { }

   /**
    * Method required by OnSeekBarChangeListener, but not used in this class.
    */
   @Override
   public void onStopTrackingTouch(SeekBar seekBar) { }
   
   // *** Other methods

   /**
    * Clears addresses.
    */
   public void clearGeocoded() {
      from_addr = new Address();
      to_addr = new Address();
   }

   /**
    *  Start a GetRoute request.
    */
   public void findRouteStart() {
      if (this.from_addr.text
               .equalsIgnoreCase(getString(R.string.current_location))) {
         this.from_addr.text = getString(R.string.custom_location);
      }
      new GWIS_RouteGetNew(this.from_addr,
                         this.to_addr,
                         "android_top",
                         G.user.rfPrefsXml(),
                         this).fetch();
   }

   /**
    * Handles the disambiguation results.
    * @param data Intent with results from disambiguation
    */
   public void finishAddressChoose(Intent data) {
      
      ArrayList<Address> addrs =
         data.getParcelableArrayListExtra(Constants.CHOOSE_ADDRESSES);
      ArrayList<String> gc_args = new ArrayList<String>();
      
      // There might be one or two addresses in the ArrayList.
      if (!from_addr.geocoded) {
         from_addr = addrs.get(0);
      }
      if (!to_addr.geocoded) {
         if (addrs.size() > 1) {
            to_addr = addrs.get(1);
         } else {
            to_addr = addrs.get(0);
         }
      }
      
      if (!from_addr.geocoded) {
         // we still need to geocode the from address
         this.auto_complete_from.setText(from_addr.text);
         gc_args.add(from_addr.text);
      }
      if (!to_addr.geocoded) {
         // we still need to geocode the to address
         this.auto_complete_to.setText(to_addr.text);
         gc_args.add(to_addr.text);
      }
      
      // If there are geocoding arguments, proceed to geocoding. Otherwise,
      // start the route finding request.
      if (gc_args.size() > 0) {
         new GWIS_Geocode(gc_args, this).fetch();
      }
      else {
         this.findRouteStart();
      }
   }

   /**
    * Handles the results of geocoding.
    * @param results Document object with geocoding results
    */
   @Override
   public void handleGWIS_GeocodeComplete(Document results) {
      ArrayList<Address> addrs = this.parseAddresses(results);
   
      // Figure out what's been geocoded.
      if (!from_addr.geocoded) {
         // from was geocoded -- always first if present
         from_addr = addrs.get(0);
      }
      if (!to_addr.geocoded) {
         if (addrs.size() == 1) {
            // just to was geocoded
            to_addr = addrs.get(0);
         }
         else {
            // from was geocoded also
            to_addr = addrs.get(1);
         }
      }
   
      // Respond to geocoding results.
      if (from_addr.geocoded && to_addr.geocoded) {
         // unambiguous geocodes -- proceed to route finding
         this.findRouteStart();
      }
      else {
         // ambiguous geocodes -- show disambiguation dialog
         Intent intent = new Intent(this, AddressChooseActivity.class);
         ArrayList<String> choose_texts = new ArrayList<String>();
         ArrayList<Address> addresses = new ArrayList<Address>();
         if (!from_addr.geocoded) {
            addresses.add(from_addr);
            choose_texts.add(
                  getResources().getString(R.string.address_choose_starting));
         }
         if (!to_addr.geocoded) {
            addresses.add(to_addr);
            choose_texts.add(
                  getResources().getString(R.string.address_choose_ending));
         }
         intent.putParcelableArrayListExtra(Constants.CHOOSE_ADDRESSES,
                                            addresses);
         intent.putStringArrayListExtra(Constants.CHOOSE_TEXTS, choose_texts);
         startActivityForResult(intent, ADDRESS_CHOOSE_REQUEST_CODE);
      }
      
   }

   /**
    * Handles route finding results
    */
   @Override
   public void handleGWIS_RouteGetComplete(Route r) {
      
      // Save address for autocomplete use
      SharedPreferences.Editor editor = G.autocomplete.edit();
      if (!this.from_addr.text
               .equalsIgnoreCase(getString(R.string.current_location)) 
         && !this.from_addr.text.equals(getString(R.string.custom_location))) {
         editor.putLong(from_addr.text, System.currentTimeMillis());
      }
      if (!this.to_addr.text.equals(getString(R.string.custom_location))){
         editor.putLong(to_addr.text, System.currentTimeMillis());
      }
      editor.commit();
      
      boolean checked =
         ((CheckBox) findViewById(R.id.route_finder_remember)).isChecked();
      
      // Save preferences if checkbox is checked
      if (checked) {
         G.user.rfPrefsSave(this);
      } else {
         G.user.rfPrefsRestore();
      }
      
      // Save checkbox state too.
      Editor settings_editor = G.cookie_anon.edit();
      settings_editor.putBoolean(Constants.COOKIE_FIND_ROUTE_REMEMBER_CHECKED,
                                 checked);
      settings_editor.commit();
      
      // Add the new route to the map.
      G.setActiveRoute(r);
      finish();
   }

   /**
    * Parse a list of addresses from a Document object.
    * @param doc Document with Address list information
    * @return ArrayList of addresses
    */
   public ArrayList<Address> parseAddresses(Document doc) {
      ArrayList<Address> result = new ArrayList<Address>();
      NodeList main_addrs = doc.getDocumentElement().getChildNodes();
      
      for (int i = 0; i < main_addrs.getLength(); i++) {
         Node current_address = main_addrs.item(i);
         if (current_address.getNodeName().equalsIgnoreCase("addr")) {
            // process current address object
            Address addr = new Address();
            NodeList choice_addrs = current_address.getChildNodes();
            for (int j = 0; j < choice_addrs.getLength(); j++) {
               Node current_choice = choice_addrs.item(j);
               if (current_choice.getNodeName().equalsIgnoreCase("addr")) {
                  // parse current Address choice (which is an address itself)
                  Address choice = new Address();
                  NamedNodeMap atts = current_choice.getAttributes();
                  choice.x = (atts.getNamedItem("x") == null) ? 0 :
                     Float.parseFloat(atts.getNamedItem("x").getNodeValue());
                  choice.y = (atts.getNamedItem("y") == null) ? 0 :
                     Float.parseFloat(atts.getNamedItem("y").getNodeValue());
                  choice.width = (atts.getNamedItem("w") == null) ? 0 :
                     Float.parseFloat(atts.getNamedItem("w").getNodeValue());
                  choice.height = (atts.getNamedItem("h") == null) ? 0 :
                     Float.parseFloat(atts.getNamedItem("h").getNodeValue());
                  choice.is_map_object =
                     (atts.getNamedItem("is_map_object") == null) ? false :
                     (atts.getNamedItem("is_map_object").getNodeValue()
                                                        .equals("1"));
                  choice.text = (atts.getNamedItem("text") == null) ? "" :
                     atts.getNamedItem("text").getNodeValue();
                  addr.addr_choices.add(choice);
               }
            }
            if (addr.addr_choices.size() == 1) {
               // One address found, no choices needed (only one choice means
               // that it is the address we want)
               addr.addr_choices.get(0).geocoded = true;
               result.add(addr.addr_choices.get(0));
            } else if (addr.addr_choices.size() > 1) {
               // More than one choice, we need to keep them all and get
               // main address information.
               NamedNodeMap addr_atts = current_address.getAttributes();
               addr.hit_count_text =
                  (addr_atts.getNamedItem("hit_count_text") == null) ? "" :
                     addr_atts.getNamedItem("hit_count_text").getNodeValue();
               addr.text = (addr_atts.getNamedItem("text") == null) ? "" :
                  addr_atts.getNamedItem("text").getNodeValue();
               addr.is_map_object =
                  (addr_atts.getNamedItem("is_map_object") == null) ? false :
                  (addr_atts.getNamedItem("is_map_object").getNodeValue()
                                                          .equals("1"));
               result.add(addr);
            }
         }
      }
      return result;
   }

   /**
    * Starts a GetGeocode request.
    */
   public void routeGeocodeStart() {
      ArrayList<String> gc_args = new ArrayList<String>();
      if (this.action != null) {
         if (this.action.equals(Constants.FINDROUTE_ROUTE_FROM_ACTION)
             && !this.auto_complete_from.getText().toString().equalsIgnoreCase(
                     getResources().getString(R.string.custom_location))) {
            this.from_addr.geocoded = false;
         } else if (this.action.equals(Constants.FINDROUTE_ROUTE_TO_ACTION)
             && !this.auto_complete_to.getText().toString().equalsIgnoreCase(
                     getResources().getString(R.string.custom_location))) {
            this.to_addr.geocoded = false;
         }
      }
      if (!this.from_addr.geocoded) {
         gc_args.add(this.auto_complete_from.getText().toString());
      }
      if (!this.to_addr.geocoded) {
         gc_args.add(this.auto_complete_to.getText().toString());
      }
      if (this.from_addr.geocoded && this.to_addr.geocoded) {
         // proceed to route finding
         this.findRouteStart();
      } else {
         new GWIS_Geocode(gc_args, this).fetch();
      }
   }

   /**
    * If the from and to addresses are valid, begins route finding process.
    */
   public void submit() {
      String from_addr_string = this.auto_complete_from.getText().toString();
      String to_addr_string = this.auto_complete_to.getText().toString();
      String hint_string =
         (this.auto_complete_from.getHint() == null) ? "" :
            this.auto_complete_from.getHint().toString();
      if ((hint_string.equals(
            getResources().getString(R.string.current_location))
           && from_addr_string.length() == 0)
          || from_addr_string.equalsIgnoreCase(
                getResources().getString(R.string.current_location))) {
         if (G.currentLocation() == null) {
            showAlert(this.getResources().getString(
                           R.string.route_finder_location_not_available),
                        this.getResources().getString(R.string.error));
            return;
         }
         // If no from address is entered and a location is available, use
         // current location
         PointD p = G.latlonToMap(G.currentLocation());
         this.from_addr.x = p.x;
         this.from_addr.y = p.y;
         this.from_addr.geocoded = true;
         this.from_addr.text = hint_string;
         this.auto_complete_from.setText(hint_string);
      } else if (from_addr_string.length() == 0) {
         showAlert(this.getResources().getString(
                        R.string.route_finder_from_not_validated),
                     this.getResources().getString(R.string.error));
         return;
      }
      if (to_addr_string.length() == 0) {
         showAlert(this.getResources()
                         .getString(R.string.route_finder_to_not_validated),
                     this.getResources().getString(R.string.error));
         return;
      }
      G.server_log.event("mobile/ui/container/route_finder/submit",
                         new String[][]{{"status", "ok"}});
      
      this.routeGeocodeStart();
   }
}

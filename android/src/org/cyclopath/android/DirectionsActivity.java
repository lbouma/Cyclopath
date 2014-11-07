/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.text.DecimalFormat;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.items.DirectionStep;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.view.View.OnClickListener;
import android.widget.ListView;
import android.widget.TextView;

/**
 * Activity that allows the user to view directions (cue sheet) for a route.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class DirectionsActivity extends BaseListActivity
                                implements OnClickListener {

   // *** Listeners

   /**
    * Handles clicks
    */
   @Override
   public void onClick(View v) {
      if (v == findViewById(R.id.directions_back_to_map_btn)) {
         // Go back to map
         finish();
      }
   }

   /**
    * Initializes the cue sheet.
    */
   @Override
   public void onCreate(Bundle savedInstanceState) {
       super.onCreate(savedInstanceState);
       
       setContentView(R.layout.directions);
       setListAdapter(new DirectionAdapter(this, G.active_route.directions));
       findViewById(R.id.directions_back_to_map_btn).setOnClickListener(this);
       TextView fromAddr = (TextView) findViewById(R.id.starting_address);
       fromAddr.setText(" " + G.active_route.from_canaddr);
       TextView toAddr = (TextView) findViewById(R.id.destination_address);
       toAddr.setText(" " + G.active_route.to_canaddr);
       TextView length = (TextView) findViewById(R.id.route_length);
       float miles = (float) (G.active_route.length/1609.344);
       DecimalFormat numFormat = new DecimalFormat("#.##");
       length.setText(" " + Float.valueOf(numFormat.format(miles)) + " mi");
   }

   /**
    * Handles list item clicks. Specifically, goes back to the map and shows
    * the selected direction.
    */
   @Override
   protected void onListItemClick (ListView l, View v, int position, long id) {
      DirectionStep direction = (DirectionStep)l.getItemAtPosition(position);
      // By setting this, the next time the route is drawn it will include the
      // direction drawing.
      G.active_route.selected_direction = position;
      Intent intent = new Intent();
      intent.putExtra(Constants.DIRECTIONS_POINT_X, direction.start_point.x);
      intent.putExtra(Constants.DIRECTIONS_POINT_Y, direction.start_point.y);
      if (getParent() == null) {
         setResult(Activity.RESULT_OK, intent);
      } else {
         getParent().setResult(Activity.RESULT_OK, intent);
      }
      finish();
   }
}

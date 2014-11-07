/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.items.DirectionStep;

import android.content.Context;
import android.text.Html;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.ImageView;
import android.widget.TextView;

/**
 * Adapter that binds direction steps to the directions list view.
 * @author Fernando Torre
 */
public class DirectionAdapter extends ArrayAdapter<DirectionStep> {

   /** List of directions */
   private ArrayList<DirectionStep> directions;
   /** context in order to allow access to resources and system services */
   private Context context;
   
   /**
    * Constructor.
    * @param context
    * @param directions list of directions
    */
   public DirectionAdapter(Context context,
         ArrayList<DirectionStep> directions) {
      super(context, 0, directions);
      this.directions = directions;
      this.context = context;
   }

   /**
    * Returns populated view for this direction.
    */
   @Override
   public View getView(int position, View convertView, ViewGroup parent) {
      View v = convertView;
      if (v == null) {
         LayoutInflater vi =
            (LayoutInflater)context.getSystemService(
                                             Context.LAYOUT_INFLATER_SERVICE);
         v = vi.inflate(R.layout.direction_item, null);
      }
      DirectionStep step = this.directions.get(position);
      setViewValues(step,
                    (ImageView) v.findViewById(R.id.direction_img),
                    (TextView) v.findViewById(R.id.direction_text),
                    (TextView) v.findViewById(R.id.direction_distance));
      return v;
   }
   
   /**
    * Populates the given views with the direction step information.
    * @param step the direction step used to populate the view
    * @param image view that will hold the direction icon
    * @param text text view that will show the direction text
    * @param distance text view that will show the direction distance
    */
   public static void setViewValues(DirectionStep step, ImageView image,
                                    TextView text, TextView distance) {

      if (step != null) {
         image.setImageResource(
                  Constants.BEARINGS[step.rel_direction].getImageId());
         try {
            text.setText(Html.fromHtml(step.text()));
         } catch (NullPointerException e) {
            if (Constants.DEBUG) { 
               Log.e("Route Step Error", "No Direction Text");
            }
         }
         distance.setText(step.getStepDistance());
      }
   }

}

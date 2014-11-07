/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;

import org.cyclopath.android.items.Route;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.TextView;

/**
 * Adapter for showing the Route information in the Route Library
 * @author Fernando Torre
 */
public class RouteListAdapter extends ArrayAdapter<Route> {

   /** List of Routes */
   private ArrayList<Route> routes;
   /** context in order to allow access to resources and system services */
   private Context context;

   /**
    * Constructor.
    * @param context
    * @param routes list of Routes
    */
   public RouteListAdapter(Context context, ArrayList<Route> routes) {
      super(context, 0, routes);
      this.routes = routes;
      this.context = context;
   }//RouteListAdapter

   /**
    * Returns populated view for this Route.
    */
   @Override
   public View getView(int position, View convertView, ViewGroup parent) {
      View v = convertView;
      if (v == null) {
         LayoutInflater vi = 
               (LayoutInflater)context.getSystemService(
                                       Context.LAYOUT_INFLATER_SERVICE);
         v = vi.inflate(R.layout.route_list_item, null);
      }
      Route list_item = this.routes.get(position);
      if (list_item != null) {
         TextView name = (TextView) v.findViewById(R.id.route_item_name);
         TextView start_end = (TextView) v.findViewById(R.id.route_start_end);
         TextView length = (TextView) v.findViewById(R.id.route_item_length);
         name.setText(list_item.name);
         length.setText(G.getFormattedLength(list_item.length));
         start_end.setText(list_item.from_canaddr + " to "
                           + list_item.to_canaddr);
      }
      return v;
   }//getView
}//RouteListAdapter

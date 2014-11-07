/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;

import org.cyclopath.android.items.Track;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.TextView;

/**
 * Adapter for showing the Track information in the Track Manager
 * @author Phil Brown
 */
public class TrackListAdapter extends ArrayAdapter<Track> {
   /** List of Tracks */
   private ArrayList<Track> tracks;
   /** context in order to allow access to resources and system services */
   private Context context;

   /**
    * Constructor.
    * @param context
    * @param tracks list of Tracks
    */
   public TrackListAdapter(Context context, ArrayList<Track> tracks) {
      super(context, 0, tracks);
      this.tracks = tracks;
      this.context = context;
   }//TrackListAdapter

   /**
    * Returns populated view for this Track.
    */
   @Override
   public View getView(int position, View convertView, ViewGroup parent) {
      View v = convertView;
      if (v == null) {
         LayoutInflater vi = 
               (LayoutInflater)context.getSystemService(
                                       Context.LAYOUT_INFLATER_SERVICE);
         v = vi.inflate(R.layout.track_list_item, null);
      }
      Track list_item = this.tracks.get(position);
      if (list_item != null) {
         TextView name = (TextView) v.findViewById(R.id.track_list_textview);
         TextView date = (TextView) v.findViewById(R.id.track_item_date);
         TextView duration = (TextView) v.findViewById(R.id.track_item_duration);
         TextView length = (TextView) v.findViewById(R.id.track_item_length);
         name.setText(list_item.toString());
         date.setText(list_item.getFormattedDate());
         duration.setText(list_item.getFormattedDuration());
         length.setText(G.getFormattedLength(list_item.length));
         Track t = G.db.getTrack(list_item.stack_id);
         // If a track is in the local db and has an owner then the snippet
         // about the track not having an owner remains invisible.
         if (t != null) {
            if (G.user.isLoggedIn() && !t.hasOwner()) {
               v.findViewById(R.id.track_item_no_owner)
                .setVisibility(View.VISIBLE);
            }
         }
      }
      return v;
   }//getView
}//TrackListAdapter

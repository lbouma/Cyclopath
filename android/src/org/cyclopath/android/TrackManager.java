/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;

import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS_Checkout;
import org.cyclopath.android.gwis.GWIS_CheckoutCallback;
import org.cyclopath.android.gwis.GWIS_Commit;
import org.cyclopath.android.gwis.GWIS_CommitCallback;
import org.cyclopath.android.gwis.QueryFilters;
import org.cyclopath.android.items.ConflationJob;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.Track;
import org.cyclopath.android.util.TrackDeletionHandler;
import org.cyclopath.android.util.TrackExporter;
import org.cyclopath.android.TrackListAdapter;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences.Editor;
import android.os.Bundle;
import android.os.Message;
import android.util.SparseIntArray;
import android.view.ContextMenu;
import android.view.ContextMenu.ContextMenuInfo;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.view.View;
import android.widget.AbsListView.OnScrollListener;
import android.widget.AdapterView.AdapterContextMenuInfo;
import android.widget.AbsListView;
import android.widget.AdapterView;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Generates a ListView of all the track names for the user to select.
 * On a long click, the context menu provides some options for handling
 * the track. On a short click, the track is shown on the map.
 * @author Phil Brown
 * @author Fernando Torre
 */
public class TrackManager extends BaseListActivity
                          implements TrackDeletionHandler,
                                     GWIS_CheckoutCallback,
                                     GWIS_CommitCallback,
                                     OnScrollListener {
   
   /** current offset for search results */
   private int offset;
   /** the list of tracks */
   private ArrayList<Track> track_list;
   /** adapter being used to connect list of tracks to the list items in the
    * layout */
   private TrackListAdapter current_adapter;
   /** action to perform once a track has been retrieved */
   private int action = -1;
   /** Request code for track edit activity */
   private final int TRACK_EDIT_REQUEST_CODE = 0;
   /** Whether additional tracks have been requested when reaching the end of
    * the list */
   private boolean additional_tracks_requested = false;
   /** Fetched track that will be saved to the local db. */
   public static Track selected_track;
   /** Track that will be shown once conflation is done. */
   private Track track_to_show;
   
   /**
    * This handler receives and handles messages from other threads.
    */
   protected CyclopathHandler mHandler = new CyclopathHandler(this);
   
   // *** Listeners
    
   /**
    * Refreshes the track list after editing a track (to keep names updated).
    */
   @Override
   protected void onActivityResult(int requestCode,
                                   int resultCode,
                                   Intent data){
      if (requestCode == this.TRACK_EDIT_REQUEST_CODE
          && resultCode == Activity.RESULT_OK) {
         Track t =
            G.db.getTrack(data.getIntExtra(Constants.TRACK_ID_STR, -1));
         if (t != null) {
            for (Track ti: this.track_list) {
               if (ti.stack_id == t.stack_id) {
                  ti.name = t.name;
                  break;
               }
            }
         }
         this.current_adapter.notifyDataSetChanged();
      }
   }//onActivityResult
   
   /**
    * Creates the context menu for this activity
    */
   @Override
   public void onCreateContextMenu(ContextMenu menu, View v,
         ContextMenuInfo menuInfo) {
      super.onCreateContextMenu(menu, v, menuInfo);
      menu.setHeaderTitle(
            getResources().getString(R.string.track_context_menu_header));
      MenuInflater inflater = getMenuInflater();
      inflater.inflate(R.menu.track_menu, menu);

      // Remove add track to account option if the track is already owned.
      AdapterView.AdapterContextMenuInfo info =
              (AdapterView.AdapterContextMenuInfo) menuInfo;
      Track t_item =
         (Track) getListAdapter().getItem(info.position);
      Track t = G.db.getTrack(t_item.stack_id);
      if (t == null) {
         menu.removeItem(R.id.add_track_owner);
      } else if (t.hasOwner() || !G.user.isLoggedIn()) {
         menu.removeItem(R.id.add_track_owner);
      }
      if (!Constants.DEBUG) {
         menu.removeItem(R.id.conflate_track);
      }
      
   }//onCreateContextMenu
      
   /**
    * Perform actions based on which context menu item is selected.
    */
   @Override
   public boolean onContextItemSelected(MenuItem item) {
      AdapterContextMenuInfo info =
         (AdapterContextMenuInfo) item.getMenuInfo();

      Track t_item =
         (Track) getListAdapter().getItem(info.position);
      
      // Get the track from the local db. If it is not in the local db, the
      // actions is deferred until we have retrieved the track.
      Track t = G.db.getTrack(t_item.stack_id);
      this.action = item.getItemId();
      if (t == null) {
         submitGetTrackQuery(t_item.stack_id, this);
      } else if (t.version < t_item.version) {
         submitGetTrackQuery(t_item.stack_id, this);
      } else {
         selected_track = t;
         this.handleAction(t);
      }
      return true;
   }//onContextItemSelected

   
   /**
    * Runs when the Activity is first created
    */
   @Override
   public void onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState);
      setContentView(R.layout.track_list);

      G.track_manager_handler = this.mHandler;
      this.offset = 0;
      this.track_list = new ArrayList<Track>();
      if (savedInstanceState != null) {
         if (savedInstanceState.containsKey(Constants.TRACK_LIST)){
            this.track_list = 
               savedInstanceState.getParcelableArrayList(Constants.TRACK_LIST);
         }
         else {
            this.submitGetTrackListQuery(this.offset);
         }
      }
      else {
         this.submitGetTrackListQuery(this.offset);
      }
      this.initList();

      ListView lv = getListView();
      lv.setTextFilterEnabled(true);
      registerForContextMenu(lv);
      
      ((ListView) findViewById(android.R.id.list)).setOnScrollListener(this);
   }//onCreate
   

   @Override
   /**
    * Unsets the global handler when this activity is destroyed.
    */
   public void onDestroy(){
      super.onDestroy();
      G.track_manager_handler = null;
   }

   /**
    * Handles list item clicks.
    */
   @Override
   protected void onListItemClick(ListView l, View v, int position, long id) {
      super.onListItemClick(l, v, position, id);
      
      Track item = ((Track) l.getItemAtPosition(position));
      Track t = G.db.getTrack(item.stack_id);
      this.action = R.id.show_track;
      if (t == null) {
         submitGetTrackQuery(item.stack_id, this);
      } else if (t.version < item.version) {
         submitGetTrackQuery(item.stack_id, this);
      } else {
         selected_track = t;
         showTrack(t);
      }
   }//onListItem
   
   /**
    * Called when the activity is about to be stopped (such as when the user 
    * rotates the device)in order to allow saving state information for the app.
    */
   @Override
   protected void onSaveInstanceState(Bundle state) {
      super.onSaveInstanceState(state);
      state.putParcelableArrayList(Constants.TRACK_LIST,
                                   this.track_list);
   }//onSavedInstanceState

   /**
    * If the user reaches the end of the list, request additional tracks.
    */
   @Override
   public void onScroll(AbsListView view, int firstVisibleItem,
                        int visibleItemCount, int totalItemCount) {
      if (firstVisibleItem + visibleItemCount >= totalItemCount
            && visibleItemCount < totalItemCount
            && totalItemCount > 0
            && !this.additional_tracks_requested) {
         this.submitGetTrackListQuery(this.offset + 1);
         this.additional_tracks_requested = true;
      }
   }

   /** Method required when implementing OnScrollListener. Currently no-op.*/
   @Override
   public void onScrollStateChanged(AbsListView view, int scrollState) { }

   // *** Instance Methods

   /**
    * Associates all available anonymous tracks with the current logged in
    * user.
    */
   public void addAnonTracksToAccount() {
      for (Track item : this.track_list) {
         if (!item.owner.equals(G.user.getName())) {
            this.addTrackToAccount(G.db.getTrack(item.stack_id));
         }
      }
   }
   
   /**
    * Associates the track with the given id with the current logged in user.
    */
   public void addTrackToAccount(Track t) {
      t.owner = G.user.getName();
      ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
      items.add(t);
      new GWIS_Commit(items, "", "", this).fetch();
   }

   /** Handles deleting a track.
    * @param track Track object that is selected
    */
   @Override
   public void deleteTrack(Track track) {
      // delete on server
      track.deleted = true;
      ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
      items.add(track);
      new GWIS_Commit(items, "", "", null).fetch();
      this.current_adapter.remove(track);
      selected_track = null;
      this.current_adapter.notifyDataSetChanged();
      Toast.makeText(this, getString(R.string.track_deleted),
                     Toast.LENGTH_SHORT).show();
   }//handleConfirm

   /**
    * Sets the list adapter using a cursor to the tracks in the database.
    */
   public void initList() {
      if (this.track_list == null) {
         this.track_list = G.db.getLocalTrackList();
      }
      // If there are tracks with no owner, ask users if they want to add
      // these tracks to their accounts.
      if (G.user.isLoggedIn() && this.track_list.size() > 0
            && !G.cookie.getBoolean(
                  Constants.COOKIE_TRACKS_WITHOUT_ACCOUNT_MESSAGE, false)) {
         Editor e = G.cookie.edit();
         e.putBoolean(Constants.COOKIE_TRACKS_WITHOUT_ACCOUNT_MESSAGE, true);
         e.commit();
         TextView v = new TextView(this);
         v.setText(getResources().getString(R.string.track_no_owner_message));
         v.setTextSize(14);
         v.setPadding(10, 0, 10, 0);

         new AlertDialog.Builder(this)
            .setTitle(getResources().getString(R.string.track_no_owner_title))
            .setView(v)
            .setNegativeButton((getResources().getString(
                                 R.string.track_no_owner_do_nothing)),
                               new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton){
                  // Do nothing
               }
            })
            .setPositiveButton((getResources().getString(
                                 R.string.track_no_owner_add_all)),
                               new DialogInterface.OnClickListener() {
               @Override
               public void onClick(DialogInterface dialog, int whichButton){
                  addAnonTracksToAccount();
               }
            }).show();
      }
      Collections.sort(this.track_list, new Comparator<Track>() {
         @Override
         public int compare(Track t1, Track t2) {
             return t2.date.compareTo(t1.date);
         }
      });
      this.current_adapter = new TrackListAdapter(this, this.track_list);
      setListAdapter(this.current_adapter);
   }//fillList

   /**
    * Handles a track action.
    * @param track track to be interacted with.
    */
   public void handleAction(Track track) {
      switch (this.action) {
      case R.id.show_track:
         showTrack(track);
         break;
      case R.id.view_track_details:
         viewTrackDetails(track);
         break;
      case R.id.delete_track:
         G.trackDeletionHandle(track, this, this);
         break;
      case R.id.add_track_owner:
         addTrackToAccount(track);
         break;
      case R.id.save_track_gpx:
         new TrackExporter(track, this).exportGPX();
         break;
      case R.id.conflate_track:
         this.track_to_show = track;
         new ConflationJob(track.stack_id).runJob();
         break;
      }
      action = -1;
   }//handleAction

   /**
    * Updates the track list once the user track list has been fetched from
    * the server.
    * If receiving a single track with a pending action, adds the track to the
    * local db and handles the pending action.
    */
   @Override
   public void handleGWIS_CheckoutComplete (
                           ArrayList<ItemUserAccess> feats) {
      if (this.action != -1 && feats.size() == 1) {
         // single track
         if (feats.get(0).getClass().getName().equals(Track.class.getName())) {
            selected_track = (Track)feats.get(0);
            new Thread(new Runnable() {  
               @Override
               public void run() {  
                  G.db.addTrack(selected_track);
                  return;
               }  
            }).start(); 
            this.handleAction(selected_track);
         }
      } else {
         int list_length = this.track_list.size();
         for (ItemUserAccess f:feats) {
            if (f.getClass().getName().equals(Track.class.getName())) {
               Track temp = (Track) f;
               if (temp.length > 0) {
                  this.track_list.add(temp);
               }
            }
         }
         if (this.track_list.size() > list_length) {
            this.additional_tracks_requested = false;
         }
         Collections.sort(this.track_list, new Comparator<Track>() {
            @Override
            public int compare(Track t1, Track t2) {
                return t2.date.compareTo(t1.date);
            }
         });
         this.current_adapter.notifyDataSetChanged();
         TextView msg = (TextView) findViewById(R.id.tracks_msg);
         if (this.track_list.size() >= 1) {
            msg.setVisibility(View.GONE);
         } else {
            msg.setText(this.getResources().getString(
                  R.string.tracklist_empty));
         }
      }
   }//handleGWIS_TrackListGetComplete

   /**
    * Refreshes the list after a track save request.
    */
   @Override
   public void handleGWIS_CommitCallback(SparseIntArray id_map) {
      if (id_map != null) {
         this.current_adapter.notifyDataSetChanged();
      }
   }

   /**
    * Shows conflated track once conflation is done.
    */
   @Override
   public void handleMessage(Message msg) {
      switch (msg.what) {
      case (Constants.CONFLATION_COMPLETE):
         this.showTrack(this.track_to_show);
         break;
      }
   }

   /**
    * Shows the selected track on the map.
    * @param track
    */
   public void showTrack(Track track) {
      G.map.featureDiscard(G.selected_track);
      G.selected_track = track;
      G.map.featureAdd(G.selected_track);
      G.map.lookAt(G.selected_track, 0);
      finish();
   }//showTrack
   
   /**
    * Submits the GWIS query for getting the track with the given id.
    * @param id
    */
   public static void submitGetTrackQuery(int id,
                                          GWIS_CheckoutCallback callback) {
      QueryFilters qfs = new QueryFilters();
      qfs.dont_load_feat_attcs = false;
      qfs.include_item_stack = true;
      qfs.include_item_aux = true;
      qfs.only_stack_ids = new int[]{id};

      GWIS_Checkout gwis_request =
         new GWIS_Checkout("track", qfs, callback,
            G.app_context.getResources().getString(
                  R.string.track_get_progress_dialog_title),
                  G.app_context.getResources().getString(
                  R.string.tracklist_get_progress_dialog_content));
      gwis_request.error_title =
            G.app_context.getResources().getString(R.string.track_get_error);
      gwis_request.fetch();
   }
   
   /**
    * Submits the GWIS query for getting the list of tracks with the given
    * offset.
    * @param offset
    */
   public void submitGetTrackListQuery(int offset) {
      this.offset = offset;
      QueryFilters qfs = new QueryFilters();
      qfs.pagin_count = Constants.SEARCH_NUM_RESULTS_SHOW;
      qfs.pagin_offset = offset;
      qfs.dont_load_feat_attcs = true;
      qfs.include_item_aux = false;
      qfs.include_item_stack = true;
      qfs.filter_by_creator_include = G.user.getName();

      GWIS_Checkout gwis_request =
         new GWIS_Checkout("track", qfs, this,
            this.getResources().getString(
                  R.string.tracklist_get_progress_dialog_title),
            this.getResources().getString(
                  R.string.tracklist_get_progress_dialog_content));
      gwis_request.error_title =
              getResources().getString(R.string.tracklist_get_error);
      gwis_request.fetch();
   }

   /**
    * Opens the Track Details activity
    * @param track
    */
   private void viewTrackDetails(Track track) {
      Intent myIntent = new Intent();
      myIntent = new Intent(this, TrackDetailsActivity.class);
      myIntent.putExtra(Constants.STACK_ID_STR, track.stack_id);
      startActivity(myIntent);
   }
   
}//TrackManager

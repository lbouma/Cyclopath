/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.gwis;

import java.util.ArrayList;
import java.util.Date;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.Track;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.NodeList;

import android.util.SparseIntArray;

/**
 * Send a GWIS request saving items.
 * @author Fernando Torre
 */
public class GWIS_Commit extends GWIS {
   
   /** items to be saved */
   private ArrayList<ItemUserAccess> changed_items;
   /** commit message */
   private String changenote;
   /** callback */
   public GWIS_CommitCallback callback;

   // *** Constructor

   /**
    * Constructs a commit request.
    */
   public GWIS_Commit(ArrayList<ItemUserAccess> changed_items) {
      this(changed_items, "", "", null);
   }

   /**
    * Constructs a commit request for rating changes.
    */
   public GWIS_Commit(int stack_id, int rating) {
      super("commit");
      
      this.data = "<ratings> <rating stack_id=\"" + stack_id
                  + "\" value=\"" + rating + "\"/> </ratings>";
   }

   /**
    * Constructs a commit request.
    */
   public GWIS_Commit(ArrayList<ItemUserAccess> changed_items,
                      String dialog_title,
                      String dialog_message,
                      GWIS_CommitCallback callback) {
      this(changed_items, G.app_context.getResources()
                           .getString(R.string.commit_message),
           dialog_title, dialog_message, callback);
   }
   
   /**
    * Constructs a commit request.
    */
   public GWIS_Commit(ArrayList<ItemUserAccess> changed_items,
                      String changenote,
                      String dialog_title,
                      String dialog_message,
                      GWIS_CommitCallback callback) {
      super("commit", "", true, null, dialog_title, dialog_message);
      this.changed_items = changed_items;
      this.changenote = changenote;
      this.callback = callback;
      
      // FIXME: Make better when I implement saving other types of stuff.
      this.data = "<items>";
      for (ItemUserAccess item: this.changed_items) {
         this.data += XmlUtils.documentToString(item.gmlProduce());
      }
      this.data +=  "</items>";
      /*this.data +=  "<schanges>";
      for (ItemUserAccess item: this.changed_items) {
         if (item.fresh) {
            this.data += "<item stid=\"" + item.stack_id
                         + "\" schg=\"" + item.getStyleId() + "\"/>";
         }
      }
      this.data +=  "</schanges>";*/
   }
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_Commit g = new GWIS_Commit(this.changed_items, this.changenote,
                                      "", "", this.callback);
      g.retrying = true;
      return g;
   }

   /**
    * Shows error to user.
    * @param text error text
    */
   @Override
   protected void errorPresent(String text) {
      G.showAlert(text, G.app_context.getResources().getString(
                        R.string.commit_error));
   }
   
   /**
    * Calls the callback with a null result if there was an error.
    */
   @Override
   protected void onErrorCleanup() {
      super.onErrorCleanup();
      if (this.callback != null)
         this.callback.handleGWIS_CommitCallback(null);
   }

   /**
    *  Processes the results. Constructs the id map to be sent to the
    *  callback.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);
      
      // get new ids
      // <data major="not_a_working_copy" gwis_version="3" semiprotect="0">
      //   <result>
      //     <id_map cli_id="-4" new_id="2643933"/>
      //     <id_map cli_id="-3" new_id="2643932"/>
      //   </result>
      // </data>
      
      SparseIntArray id_map = new SparseIntArray();
      NodeList results = rset.getElementsByTagName("id_map");
      for (int i = 0; i < results.getLength(); i++) {
         NamedNodeMap atts = results.item(i).getAttributes();
         id_map.append(XmlUtils.getInt(atts, "cli_id", 0),
                       XmlUtils.getInt(atts, "new_id", 0));
      }
      
      if (this.callback != null) {
         this.callback.handleGWIS_CommitCallback(id_map);
      } else if (this.changed_items != null) {
         int new_id;
         for (ItemUserAccess item : this.changed_items) {
            new_id = id_map.get(item.stack_id);
            G.db.updateTrackId(item.stack_id, new_id);
            
            if (Track.class.isInstance(item)) {
               Track t = (Track) item;
               if (G.LANDMARKS_EXP_ON
                     && G.cookie.getLong(Constants.LANDMARKS_EXP_AGREE, 0)
                        > (new Date()).getTime()
                     && t.trial_num > 0) {
                  new GWIS_LandmarkTrialPut(new_id, t.trial_num).fetch();
               }
            }
         }
      }
   }
}

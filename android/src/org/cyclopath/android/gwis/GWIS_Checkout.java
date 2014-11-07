/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.gwis;

import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.items.Annotation;
import org.cyclopath.android.items.ConflationJob;
import org.cyclopath.android.items.ItemUserAccess;
import org.cyclopath.android.items.LinkValue;
import org.cyclopath.android.items.Route;
import org.cyclopath.android.items.Tag;
import org.cyclopath.android.items.Terrain;
import org.cyclopath.android.items.Byway;
import org.cyclopath.android.items.Feature;
import org.cyclopath.android.items.Geopoint;
import org.cyclopath.android.items.Track;
import org.w3c.dom.Document;
import org.w3c.dom.NodeList;

/**
 * This GWIS class handles getting features from the server.
 * @author Fernando Torre
 */
public class GWIS_Checkout extends GWIS {
   
   /** Type of feature being fetched */
   public String item_type;
   /** Method to be called once features are fetched. */
   public GWIS_CheckoutCallback callback;
   
   // not used for now
   public String attc_type = "";
   public String feat_type = "";
   public int lhs_stack_id = 0;
   public int rhs_stack_id = 0;
   
   /** Title to use for dialog in case of error */
   public String error_title;

   // *** Constructor
   
   /**
   * Constructs a checkout request without a callback.
   */
  public GWIS_Checkout(String item_type,
                       QueryFilters query_filters) {
     this(item_type, query_filters, null);
  }
   
   /**
   * Constructs a checkout request with a callback.
   */
  public GWIS_Checkout(String item_type,
                       QueryFilters query_filters,
                       GWIS_CheckoutCallback callback) {
     this(item_type, query_filters, callback, "", "");
  }

   /**
    * Constructs a checkout request with a callback and popup message.
    */
   public GWIS_Checkout(String item_type,
                        QueryFilters query_filters,
                        GWIS_CheckoutCallback callback,
                        String popup_title,
                        String popup_msg) {
      super("checkout", "", true, query_filters, popup_title, popup_msg);
      this.item_type = item_type;
      this.callback = callback;
   }
   
   /**
    * Returns a copy of this GWIS request.
    */
   @Override
   public GWIS clone() {
      GWIS_Checkout g = new GWIS_Checkout(this.item_type,
                                          this.query_filters,
                                          this.callback);
      g.retrying = true;
      return g;
   }

   /**
    * Shows error to user.
    * @param text error text
    */
   @Override
   protected void errorPresent(String text) {
      if (this.error_title != null) {
         G.showAlert(text, this.error_title);
      }
   }
   
   @Override
   protected void finalize_request() {
      super.finalize_request();
      if (!this.item_type.equals("")) {
         this.url += "&ityp=" + this.item_type;
      }
      if (!this.attc_type.equals("")) {
         this.url += "&atyp=" + this.attc_type;
      }
      if (!this.feat_type.equals("")) {
         this.url += "&ftyp=" + this.feat_type;
      }
      if (this.lhs_stack_id != 0) {
         this.url += "&lhsd=" + this.lhs_stack_id;
      }
      if (this.rhs_stack_id != 0) {
         this.url += "&rhsd=" + this.rhs_stack_id;
      }
   }

   /**
    * Adds fetched features to the map or sends them to the callback
    * function.
    */
   @Override
   protected void processResultset(Document rset) {
      super.processResultset(rset);

      ArrayList<ItemUserAccess> items = new ArrayList<ItemUserAccess>();
      ArrayList<Feature> feats = new ArrayList<Feature>();

      NodeList nodes;
      if (G.map.zoomIsVector(G.zoom_level)) {
         nodes = rset.getElementsByTagName("terrain");
         for (int i = 0; i < nodes.getLength(); i++) {
            feats.add(new Terrain(nodes.item(i)));
         }
         nodes = rset.getElementsByTagName("byway");
         for (int i = 0; i < nodes.getLength(); i++) {
            feats.add(new Byway(nodes.item(i)));
         }
         nodes = rset.getElementsByTagName("waypoint");
         for (int i = 0; i < nodes.getLength(); i++) {
            feats.add(new Geopoint(nodes.item(i)));
         }
      }
      nodes = rset.getElementsByTagName("route");
      for (int i = 0; i < nodes.getLength(); i++) {
         feats.add(new Route(nodes.item(i)));
      }
      nodes = rset.getElementsByTagName("track");
      for (int i = 0; i < nodes.getLength(); i++) {
         feats.add(new Track(nodes.item(i)));
      }
      nodes = rset.getElementsByTagName("conflation_job");
      for (int i = 0; i < nodes.getLength(); i++) {
         items.add(new ConflationJob(nodes.item(i)));
      }
      nodes = rset.getElementsByTagName("annotation");
      for (int i = 0; i < nodes.getLength(); i++) {
         items.add(new Annotation(nodes.item(i)));
      }
      nodes = rset.getElementsByTagName("tag");
      for (int i = 0; i < nodes.getLength(); i++) {
         items.add(new Tag(nodes.item(i)));
      }
      nodes = rset.getElementsByTagName("link_value");
      for (int i = 0; i < nodes.getLength(); i++) {
         items.add(new LinkValue(nodes.item(i)));
      }
      
      if (callback == null) {
         G.map.featuresAdd(feats);
      } else {
         for (Feature f : feats) {
            items.add((ItemUserAccess) f);
         }
         this.callback.handleGWIS_CheckoutComplete(items);
      }
   }
   
}

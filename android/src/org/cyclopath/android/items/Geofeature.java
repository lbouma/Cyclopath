/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.Conf;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.DrawClass;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.gwis.GWIS_Checkout;
import org.cyclopath.android.gwis.GWIS_CheckoutCallback;
import org.cyclopath.android.gwis.QueryFilters;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import android.graphics.RectF;
import android.os.Bundle;
import android.os.Message;
import android.util.SparseArray;

/**
 * Class that represents versioned geofeatures. Based in part on
 * flashclient/Geofeature.as
 * @author Fernando Torre
 *
 */
public abstract class Geofeature extends ItemUserAccess
                                 implements Feature,
                                            GWIS_CheckoutCallback {
   
   // *** Static variables

   /** Add this to the real Z value to get the Z we show to the user. */
   public static int Z_USER_OFFSET;

   // *** Instance variables

   /** Geofeature layer ID */
   public int gfl_id;
   /** Feature z level */
   public int z;
   /** Map label for this geofeature **/
   public MapLabel label;

   /** Array of map coordinates for this feature */
   public ArrayList<PointD> xys;
   /** bounding box for this geofeature */
   public RectF bbox;
   /** whether the feature has been selected on the map */
   public boolean selected;
   
   /** lightweight tags */
   public ArrayList<String> tags_light;
   /** LinkValues for this geofeature */
   public SparseArray<LinkValue> links;
   /** Notes for this geofeature */
   public SparseArray<Annotation> notes;
   /** Tags for this geofeature */
   public SparseArray<Tag> tags;
   /** Whether notes have been fetched for this geofeature */
   public boolean notes_fetched;
   /** Whether tags have been fetched for this geofeature */
   public boolean tags_fetched;
   
   /**
    * Constructor
    * @param root Node with Geofeature data
    */
   public Geofeature(Node root)
   {
      super(root);
      this.gfl_id = 0;
      this.xys = new ArrayList<PointD>();
      this.selected = false;
      this.tags_light = new ArrayList<String>();
      this.tags_fetched = false;
      this.notes_fetched = false;
      this.links = new SparseArray<LinkValue>();
      this.notes = new SparseArray<Annotation>();
      this.tags = new SparseArray<Tag>();
   }

   // *** Getters and setters

   /**
    * Calculates and returns the bounding box for this geofeature.
    */
   @Override
   public RectF getBboxMap() {
      return this.bbox;
   }
   
   /**
    * Returns the shortest distance from point p to this geofeature. Uses
    * map coordinates.
    */
   public double getDistanceFrom(PointD p) {
      double new_dist;
      if (this.xys.size() == 0) {
         return -1;
      } else if (this.xys.size() == 1) {
         return G.distance(p, this.xys.get(0));
      }
      double result =
            G.distancePointToLine(p, this.xys.get(0), this.xys.get(1));
      for (int n = 1; n < this.xys.size() - 1; n++) {
         new_dist =
               G.distancePointToLine(p, this.xys.get(n), this.xys.get(n+1));
         if (new_dist < result) {
            result = new_dist;
         }
      }
      return result;
   }
   
   /**
    * Returns the draw class for this geofeature
    * @return
    */
   public int getDrawClassId() {
      return Conf.draw_class_by_gfl.get(this.gfl_id);
   }

   /**
    * Returns this geofeature's drawing color
    */
   public int getDrawColor() {
      if (!selected) {
         return Conf.draw_param.get(this.getDrawClassId()).color;
      } else {
         return Constants.HIGHTLIGHT_COLOR;
      }
   }

   /**
    * Returns this geofeature's drawing width
    */
   public float getDrawWidth() {
      return Conf.draw_param.get(this.getDrawClassId())
                            .zoom_params.get(G.zoom_level)
                            .width;
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.GEOFEATURE;
   }

   /**
    * Return the label size (Measured in points)
    */
   public float getLabelSize() {
      return Conf.draw_param.get(this.getDrawClassId())
                            .zoom_params.get(G.zoom_level)
                            .label_size
             + Constants.LABEL_SIZE_ANDROID_ADJUSTMENT;
   }

   /**
    * Returns the text to use in labels for the geofeature.
    * @return
    */
   public String getLabelText() {
      return this.name;
   }

   /**
    * Returns the color for this geofeature's shadow.
    * @return
    */
   public int getShadowColor() {
      return Conf.draw_param.get(DrawClass.SHADOW).color;
   }

   /**
    * Returns the width for this geofeature's shadow.
    * @return
    */
   public float getShadowWidth() {
      return Constants.SHADOW_WIDTH;
   }
   
   /**
    * Returns the modified z level for this geofeature.
    */
   @Override
   public float getZplus() {
      // NOTE - hack: draw bike paths and sidewalks on top of other types.
      int dc = (this.getDrawClassId() == DrawClass.BIKETRAIL
                    ? 99 : this.getDrawClassId());
      return (this.z + dc / 100f);
   }

   /**
    * Returns the z level that is presented to the user.
    */
   public int getZ_user() {
      return this.z + Z_USER_OFFSET;
   }

   // *** Other methods
   
   /**
    * Calculates the bounding box for this geofeature.
    */
   public void calculateBbox() {
      if (this.xys.size() == 0) {
         this.bbox = null;
      } else {
         PointD first = new PointD(this.xys.get(0).x,
                                   this.xys.get(0).y);
         this.bbox = new RectF((float)first.x, (float)first.y,
                               (float)first.x, (float)first.y);
         for (PointD p: this.xys) {
            // Max and min are inverted, because canvas y coordinates are in
            // the opposite direction to map y coordinates
            this.bbox.bottom = Math.max(bbox.bottom, (float) p.y);
            this.bbox.top = Math.min(bbox.top, (float) p.y);
            this.bbox.left = Math.min(bbox.left, (float) p.x);
            this.bbox.right = Math.max(bbox.right, (float) p.x);
         }
      }
   }

   /**
    * Cleans up this geofeature by removing its label from the map and removing
    * the feature from the vectors hashmap.
    */
   @Override
   public void cleanup() {
      G.map.featureDiscard(this.label);
      this.label = null;
      G.vectors_old_all.remove(this.stack_id);
   }
   
   /** No-op. Descendants can override if they wish. */
   @Override
   public void drawShadow() {}
   
   /**
    * Populates this Geofeature from an XML
    * @param root
    */
   @Override
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      NamedNodeMap atts = root.getAttributes();
      
      this.gfl_id = XmlUtils.getInt(atts, "gflid", 0);
      this.z = XmlUtils.getInt(atts, "z", 0);
      
      // add tags
      NodeList child_nodes = root.getChildNodes();
      for (int i = 0; i < child_nodes.getLength(); i++) {
         Node n = child_nodes.item(i);
         if (n.getNodeName().equals("tags")) {
            NodeList n_child_nodes = n.getChildNodes();
            for (int j = 0; j < n_child_nodes.getLength(); j++) {
               Node t = n_child_nodes.item(j);
               if (t.getNodeName().equals("t")) {
                  this.tags_light.add(t.getFirstChild().getNodeValue());
               }
            }
         }
      }
   }

   @Override
   /**
    * Returns an XML String representing this Geofeature.
    */
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      document.renameNode(root, null, "geofeature");
      root.setAttribute("gflid", Integer.toString(this.gfl_id));
      root.setAttribute("z", Integer.toString(this.z));
      
      StringBuilder coords = new StringBuilder();
      for (PointD p : this.xys) {
         if(coords.length() > 0) {
            coords.append(" ");
         }
         coords.append(p.x + " " + p.y);
      }
      root.setTextContent(coords.toString());
      return document;
   }

   /**
    * Handles fetched LinkValues and Attachments.
    */
   @Override
   public void handleGWIS_CheckoutComplete(ArrayList<ItemUserAccess> items) {
      ArrayList<Integer> notes_to_fetch = new ArrayList<Integer>();
      ArrayList<Integer> tags_to_fetch = new ArrayList<Integer>();
      
      // process received items
      for (ItemUserAccess item : items) {
         if (LinkValue.class.isInstance(item)) {
            LinkValue link = (LinkValue) item;
            if (link.link_lhs_type_id == 4) {
               notes_to_fetch.add(link.lhs_stack_id);
               this.links.put(link.stack_id, link);
            } else if (link.link_lhs_type_id == 11) {
               if (Tag.all_id.get(link.lhs_stack_id) != null) {
                  Tag t = Tag.all_id.get(link.lhs_stack_id);
                  this.tags.put(t.stack_id, t);
               } else {
                  tags_to_fetch.add(link.lhs_stack_id);
               }
               this.links.put(link.stack_id, link);
            }
         } else if (Annotation.class.isInstance(item)) {
            // update notes list
            Annotation annot = (Annotation) item;
            this.notes.put(annot.stack_id, annot);
            this.notes_fetched = true;
         } else if (Tag.class.isInstance(item)) {
            // update tags
            Tag t = (Tag) item;
            this.tags.put(t.stack_id, t);
            this.tags_fetched = true;
         }
      }
      
      if (!this.tags_fetched && !this.notes_fetched) {
         if (notes_to_fetch.isEmpty()) {
            this.notes_fetched = true;
         }
         if (tags_to_fetch.isEmpty()) {
            this.tags_fetched = true;
         }
      }
      
      if (!notes_to_fetch.isEmpty() && !this.notes_fetched) {
         // get annotations
         QueryFilters qfs = new QueryFilters();
         qfs.only_stack_ids = new int[notes_to_fetch.size()];
         for (int i=0; i < qfs.only_stack_ids.length; i++) {
            qfs.only_stack_ids[i] = notes_to_fetch.get(i).intValue();
         }
         GWIS_Checkout request = new GWIS_Checkout("annotation", qfs, this);
         request.fetch();
      }
      if (!tags_to_fetch.isEmpty() && !this.tags_fetched) {
         // get tags
         QueryFilters qfs = new QueryFilters();
         qfs.only_stack_ids = new int[tags_to_fetch.size()];
         for (int i=0; i < qfs.only_stack_ids.length; i++) {
            qfs.only_stack_ids[i] = tags_to_fetch.get(i).intValue();
         }
         GWIS_Checkout request = new GWIS_Checkout("tag", qfs, this);
         request.fetch();
      }
      
      if (notes_fetched || tags_fetched) {
         // send message to handler for any updates to UI
         if (G.attachment_UI_handler != null) {
            Message msg = Message.obtain();
            msg.what = Constants.ATTACHMENT_LOAD_COMPLETE;
            Bundle data = new Bundle();
            data.putBoolean(Constants.TAGS_FETCHED, this.tags_fetched);
            data.putBoolean(Constants.NOTES_FETCHED, this.notes_fetched);
            msg.setData(data);
            msg.setTarget(G.attachment_UI_handler);
            msg.sendToTarget();
         }
      }
   }

   /**
    * Initializes this feature by adding it to the vectors hashmap. Returns
    * false if the feature is already in the hashmap.
    */
   @Override
   public boolean init() {
      if (G.vectors_old_all.containsKey(this.stack_id)) {
         return false;
      } else {
         G.vectors_old_all.put((int)this.stack_id, this);
         return true;
      }
   }

   /**
    *  True if this feature is drawable, i.e. should it be drawn at the current
    *  zoom level?
    */
   public boolean isDrawable() {
      return true;
   }

   /**
    *  True if object is not on the server, i.e. created by the user and not
    *  yet saved
    */
   public boolean isFresh() {
      return (this.stack_id <= 0);
   }

   /**
    *  True if this feature is labelable, i.e. should it be labeled at the
    *  current zoom level?
    */
   public boolean isLabelable() {
      return this.isDrawable() &&
             Conf.draw_param.get(this.getDrawClassId())
                            .zoom_params.get(G.zoom_level)
                            .label;
   }
   
   /**
    * REturns true if this geofeature is selected on the map.
    */
   public boolean isSelected() {
      return this.selected;
   }

   /**
    * Creates the appropriate label for this feature.
    * @return new map label or null if no map label was created.
    */
   public MapLabel labelCreate() {
      return null;
   }

   /**
    * Labels this geofeature if it is labelable and the label does not collide
    * with other labels being displayed.
    */
   public void labelMaybe() {
      if (this.isLabelable()) {
         // compute, create Map Label, and add to layer
         this.label = this.labelCreate();
         if (this.label != null && !G.map.childCollides(this.label)) {
            G.map.featureAdd(this.label);
         } else {
            this.label = null;
         }
      }
   }

   /**
    * Requests the attachments for this geofeature.
    */
   public void populateAttachments() {
      if (this.stack_id > 0) {
         QueryFilters qfs = new QueryFilters();
         qfs.dont_load_feat_attcs = true;
         qfs.only_rhs_stack_ids = new int[]{this.stack_id};
         GWIS_Checkout request = new GWIS_Checkout("link_value", qfs, this);
         request.fetch();
      } else {
         this.tags_fetched = true;
         this.notes_fetched = true;
         if (G.attachment_UI_handler != null) {
            Message msg = Message.obtain();
            msg.what = Constants.ATTACHMENT_LOAD_COMPLETE;
            Bundle data = new Bundle();
            data.putBoolean(Constants.TAGS_FETCHED, this.tags_fetched);
            data.putBoolean(Constants.NOTES_FETCHED, this.notes_fetched);
            msg.setData(data);
            msg.setTarget(G.attachment_UI_handler);
            msg.sendToTarget();
         }
      }
   }

   /**
    * Clears the attachment for this geofeature.
    */
   public void resetAttachments() {
      this.links = new SparseArray<LinkValue>();
      this.notes = new SparseArray<Annotation>();
      this.tags = new SparseArray<Tag>();
      this.notes_fetched = false;
      this.tags_fetched = false;
   }
}

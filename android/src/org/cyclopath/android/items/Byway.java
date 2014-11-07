/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import java.util.ArrayList;
import java.util.HashSet;

import junit.framework.Assert;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.util.PointD;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;

import android.graphics.Color;

/**
 * This class represents byways on the map.
 * @author Fernando Torre
 */
public class Byway extends Geofeature {
   
   /** rating for this byway if it has not been rating by the logged-in user */
   public float generic_rating;
   /** byway rating for logged-in user */
   public int user_rating;
   /** 0: two-way, -1 or 1: one-way */
   public int one_way;
   /** id for the starting node */
   public int start_node_id;
   /** elevation at the starting node */
   public float start_node_elevation;
   /** id for the end node */
   public int end_node_id;
   /** elevation at the end node */
   public float end_node_elevation;
   /** used to maintain private user data */
   public boolean user_rating_update;
   /** length of this byway in meters */
   protected float map_length;

   /**
    * Constructor
    * @param root
    */
   public Byway(Node root) {
      super(root);

      if (root == null) {
         // FIXME: some magic defaults
         this.user_rating = -1;
         this.one_way = 0;
         this.gfl_id = 11;
         this.z = 134;
         this.generic_rating = 2;
         this.start_node_id = G.idNew();
         this.end_node_id = G.idNew();
      } else {
         this.gmlConsume(root);
      }
      this.map_length_update();
      this.calculateBbox();
   }
   
   /**
    * Returns the color of this byway, which depends on the rating for
    * this byway.
    */
   @Override
   public int getDrawColor() {
      if (!selected) {
         return Constants.RATING_COLORS_GENERIC[Math.round(this.getRating())];
      } else {
         return super.getDrawColor();
      }
   }

   /**
    * Returns the rating for this byway.
    * @return
    */
   public float getRating() {
      if (this.user_rating >= 0)
         return this.user_rating;
      else
         return this.generic_rating;
   }

   /**
    * Returns the color for this byway's shadow, which depends on the rating.
    */
   @Override
   public int getShadowColor() {
      if (this.user_rating < 0) {
         return Constants.UNRATED_SHADOW_COLOR;
      } else {
         return Constants.USER_RATED_SHADOW_COLOR;
      }
   }
   
   /**
    * Returns a drawing width adjustment depending on the zoom level.
    * @return
    */
   public int getWidthAdjustment() {
      if (G.zoom_level > 15)
          return -5;
      else if (G.zoom_level == 15)
          return -3;
      else
          return -1;
   }

   /**
    * Cleans up the nodes associated with this byway before discarding it.
    */
   @Override
   public synchronized void cleanup() {
      super.cleanup();
      // Remove myself from byway adjacency map
      this.nodeCleanup(this.start_node_id);
      if (this.start_node_id != this.end_node_id)
         this.nodeCleanup(this.end_node_id);
   }

   /**
    * Draws byway.
    */
   @Override
   public void draw() {
      
      G.map.drawLine(this.xys,
            this.getDrawWidth() + this.getWidthAdjustment(),
            this.getDrawColor());
      
      
      if (this.hasAvoidedTag()) {
         G.map.drawLine(this.xys, 1f,
                     Color.RED);
      }
      this.drawNode(this.start_node_id);
      this.drawNode(this.end_node_id);
   }
   
   /**
    * Draws a byway's node, which takes into account z levels of connecting
    * nodes.
    * @param nid
    */
   public synchronized void drawNode(int nid) {
      
      // if no adjacent blocks, don't draw anything.
      if (G.nodes_adjacent.get(nid).size() == 1)
         return;

      Byway z_max_b = null;
      synchronized(G.nodes_adjacent) {
         for (Byway b: G.nodes_adjacent.get(nid)) {
            if (z_max_b == null) {
               z_max_b = b;
            } else if (b.z > z_max_b.z) {
               G.map.drawLine(z_max_b.exit_vector(nid),
                     z_max_b.getDrawWidth() + this.getWidthAdjustment(),
                     z_max_b.getDrawColor());
               z_max_b = b;
            } else {
               G.map.drawLine(b.exit_vector(nid),
                             b.getDrawWidth() + this.getWidthAdjustment(),
                             b.getDrawColor());
            }
         }
      }
      G.map.drawLine(z_max_b.exit_vector(nid),
                     z_max_b.getDrawWidth() + this.getWidthAdjustment(),
                     z_max_b.getDrawColor());
   }

   /**
    * Draws the shadow for this byway.
    */
   @Override
   public void drawShadow() {
      G.map.drawLine(this.xys,
                     this.getDrawWidth()
                        + this.getShadowWidth() * 2
                        + this.getWidthAdjustment(),
                     this.getShadowColor());
   }

   /**
    * Returns an array of two points representing a line segment where (x1,y1)
    * is the map coordinates of node nid, and (x2,y2) are the coordinates of
    * the penultimate vertex on that end of the byway.
    * @param nid node id
    * @return Array list containing two points.
    */
   public ArrayList<PointD> exit_vector(int nid) {
      ArrayList<PointD> result = new ArrayList<PointD>();
      if (nid == this.start_node_id) {
         result.add(new PointD(this.xys.get(0).x, this.xys.get(0).y));
         result.add(new PointD(this.xys.get(1).x, this.xys.get(1).y));
      } else {
         Assert.assertTrue(nid == this.end_node_id);
         result.add(new PointD(this.xys.get(this.xys.size()-1).x,
                               this.xys.get(this.xys.size()-1).y));
         result.add(new PointD(this.xys.get(this.xys.size()-2).x,
                               this.xys.get(this.xys.size()-2).y));
      }
      return result;
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.BYWAY;
   }

   @Override
   /**
    * Populates this Byway from an XML
    * @param root
    */
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      this.xys = G.coordsStringToPoint(root.getFirstChild().getNodeValue());
      NamedNodeMap atts = root.getAttributes();
   
      this.one_way = XmlUtils.getInt(atts, "onew", 0);
      this.generic_rating = XmlUtils.getFloat(atts, "grat", 2f);
      this.user_rating = Math.round(XmlUtils.getFloat(atts, "urat", -1f));
      this.start_node_id = XmlUtils.getInt(atts, "nid1", G.idNew());
      this.start_node_elevation = XmlUtils.getFloat(atts, "nel1", 0f);
      this.end_node_id = XmlUtils.getInt(atts, "nid2", G.idNew());
      this.end_node_elevation = XmlUtils.getFloat(atts, "nel2", 0f);
   }

   @Override
   /**
    * Returns an XML String representing this Byway.
    */
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      document.renameNode(root, null, "byway");
      root.setAttribute("onew", Integer.toString(this.one_way));
      
      return document;
   }

   /**
    * In this class, init() adds byway to the global byway adjacency map.
    */
   @Override
   public synchronized boolean init() {
      if (!(super.init())) {
         Byway old_b = (Byway) G.vectors_old_all.get(this.stack_id);

         if (old_b != null && old_b.user_rating_update) {
            // update the old byway's rating
            Assert.assertTrue(G.user.isLoggedIn());
            old_b.user_rating = this.user_rating;
            old_b.user_rating_update = false;
            G.map.redraw();
         }
         return false;
      }

      // TODO
      //G.map.direction_arrows.addChild(this.arrows);
      
      synchronized(G.nodes_adjacent) {
         if (!G.nodes_adjacent.containsKey(this.start_node_id)) {
            G.nodes_adjacent.put(this.start_node_id, new HashSet<Byway>());
         }
         G.nodes_adjacent.get(this.start_node_id).add(this);
         
         if (!G.nodes_adjacent.containsKey(this.end_node_id)) {
            G.nodes_adjacent.put(this.end_node_id, new HashSet<Byway>());
         }
         G.nodes_adjacent.get(this.end_node_id).add(this);
      }

      return true;
   }
   
   /**
    * Returns true if this byway has one of the tags that we mark as avoid by
    * default.
    * FIXME: Flashclient gets this information from the server and so should
    * we.
    */
   public boolean hasAvoidedTag() {
      for (String t : this.tags_light) {
         if (t.equalsIgnoreCase("avoid")
             || t.equalsIgnoreCase("prohibited")
             || t.equalsIgnoreCase("closed")) {
            return true;
         }
      }
      return false;
   }

   /**
    * Byways are discardable by default.
    */
   @Override
   public boolean isDiscardable() {
      return true;
   }
   
   /**
    * Creates the appropriate label for this byway.
    */
   @Override
   public MapLabel labelCreate() {
      if (this.getLabelText() == null)
         return null;
   
      // Compute cumulative distances along linestring
      float[] dists = new float[this.xys.size()];
      dists[0] = 0f;
      int i;
      for (i = 1; i < this.xys.size(); i++) {
         dists[i] = (float) (dists[i-1]
                       + G.distance(this.xys.get(i-1).x, this.xys.get(i-1).y,
                                    this.xys.get(i).x, this.xys.get(i).y));
      }
   
      // Locate midpoint segment
      float dist_total = dists[dists.length-1];
      for (i = 0; i < dists.length - 1; i++)
         if (dists[i+1] > dist_total/2)
            break;
      // i now contains index of the point _beginning_ the segment which
      // contains the midpoint of the linestring.
   
      // Compute center of linestring
      float deltad = dists[i+1] - dists[i];
      double label_x = (this.xys.get(i).x * (dist_total/2 - dists[i])
                       + this.xys.get(i+1).x * (dists[i+1] - dist_total/2))
                      / deltad;
      double label_y = (this.xys.get(i).y * (dist_total/2 - dists[i])
                       + this.xys.get(i+1).y * (dists[i+1] - dist_total/2))
                      / deltad;
   
      // Compute rotation angle
      // Negated to convert CCW to CW rotation
      float label_rotation =
         (float) -Math.atan2(this.xys.get(i).y - this.xys.get(i+1).y,
                             this.xys.get(i).x - this.xys.get(i+1).x);
   
      // Keep text upright
      if (label_rotation < -Math.PI/2)
         label_rotation += Math.PI;
      if (label_rotation > Math.PI/2)
         label_rotation -= Math.PI;
   
      MapLabel label = new MapLabel(this.getLabelText(), this.getLabelSize(),
                                    (float) Math.toDegrees(label_rotation),
                                    label_x, label_y);
      return label;
   }

   /**
    * Recompute map_length based on my coordinates
    */
   public void map_length_update() {
      this.map_length = 0;
      for (int i = 0; i < this.xys.size() - 1; i++) {
         this.map_length += G.distance(this.xys.get(i).x, this.xys.get(i).y,
                                   this.xys.get(i+1).x, this.xys.get(i+1).y);
      }
   }
   
   /**
    * Remove byway from node data structures associated with node
    * node_id, and clean up those data structures.
    * @param node_id
    */
   public synchronized void nodeCleanup(int node_id) {
      if (!G.nodes_adjacent.containsKey(node_id)) {
         return;
      }
      
      G.nodes_adjacent.get(node_id).remove(this);

      if (G.nodes_adjacent.get(node_id).isEmpty()) {
         G.nodes_adjacent.remove(node_id);
      }
   }
}

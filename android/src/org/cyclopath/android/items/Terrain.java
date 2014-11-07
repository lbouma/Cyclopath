/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.util.PointD;
import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

/**
 * This class represents terrains on the map, which are area
 * features that give context to the map.
 * @author Fernando Torre
 */
public class Terrain extends Geofeature {
   
   /** Coordinate array for internal rings */
   public ArrayList<ArrayList<PointD>> internal_xys;

   /**
    * Constructor
    * @param root
    */
   public Terrain(Node root) {
      super(root);
      
      this.internal_xys = new ArrayList<ArrayList<PointD>>();

      if (root != null) {
         this.gmlConsume(root);
      }
      this.calculateBbox();
   }

   // *** Other methods

   /**
    * Draws the terrain.
    */
   @Override
   public void draw() {
      // Draw external ring
      if (G.aerialStateOn()) {
         G.map.drawLine(this.xys, 2, this.getDrawColor());
      } else {
         G.map.drawPolygon(this.xys, this.getDrawColor());
      }

      // Draw internal rings
      for (ArrayList<PointD> pts: this.internal_xys) {
         if (G.aerialStateOn()) {
            G.map.drawLine(pts, 2, this.getDrawColor());
         } else {
            G.map.drawPolygon(pts, this.getDrawColor());
         }
      }
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.TERRAIN;
   }

   @Override
   /**
    * Populates this Terrain from an XML
    * @param root
    */
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      NodeList childnodes = root.getChildNodes();
      for (int i = 0; i < childnodes.getLength(); i++) {
         if (childnodes.item(i).getNodeName().equals("external")) {
            this.xys =
               G.coordsStringToPoint(childnodes.item(i).getFirstChild()
                                                       .getNodeValue());
         } else if (childnodes.item(i).getNodeName().equals("internal")) {
            this.internal_xys.add(
                  G.coordsStringToPoint(childnodes.item(i).getFirstChild()
                                                          .getNodeValue()));
         }
      }
   }

   @Override
   /**
    * Returns an XML String representing this Terrain.
    */
   public Document gmlProduce() {
      // TODO: Not implementing until we need this.
      throw new UnsupportedOperationException();
   }

   /**
    * Terrains are always discardable.
    */
   @Override
   public boolean isDiscardable() {
      return true;
   }
}

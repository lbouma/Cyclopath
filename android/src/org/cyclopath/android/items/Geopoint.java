/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.util.PointD;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;

/**
 * This class represents points on the map.
 * @author Fernando Torre
 */
public class Geopoint extends Geofeature {
   
   /**
    * Constructor.
    * @param root
    */
   public Geopoint(Node root) {
      super(root);

      if (root == null) {
         this.gfl_id = 103;
         this.name =
            G.app_context.getResources().getString(R.string.new_point_name);
      } else {
         this.gmlConsume(root);
      }
      this.calculateBbox();
   }
   
   /**
    * Constructor for new point at the given coordinates.
    * @param x
    * @param y
    */
   public Geopoint(double x, double y) {
      this(null);
      this.xys.add(new PointD(x, y));
   }
   
   // *** Getters and Setters

   /**
    * Returns the label text for this point. Shortens long names using '...'.
    */
   @Override
   public String getLabelText() {
      if (this.name.length() > Constants.MAX_POINT_LABEL_LEN) {
         return
            this.name.substring(0, Constants.MAX_POINT_LABEL_LEN - 3) + "...";
      } else
         return this.name;
   }

   /**
    * Draws the point.
    */
   @Override
   public void draw() {
   
      if (this.isDrawable()) {
         
         G.map.drawCircle(G.map.xform_x_map2cv(this.xys.get(0).x),
               G.map.xform_y_map2cv(this.xys.get(0).y),
               this.getDrawWidth() / 2, this.getShadowWidth(),
               this.getDrawColor(), this.getShadowColor());
      }  
   }

   @Override
   /**
    * Populates this Byway from an XML
    * @param root
    */
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      this.xys = G.coordsStringToPoint(root.getFirstChild().getNodeValue());
   }

   /**
    * Returns an XML String representing this Geopoint.
    */
   @Override
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      
      document.renameNode(root, null, "waypoint");
      
      return document;
   }

   /**
    * Geopoints are discardable by default.
    */
   @Override
   public boolean isDiscardable() {
      return true;
   }

   /**
    * Creates the appropriate label for this geopoint.
    */
   @Override
   public MapLabel labelCreate() {
      float radius = this.getDrawWidth() / 2;

      double label_x = this.xys.get(0).x
                    + G.map.xform_scalar_cv2map(Math.round(radius - 1));
      double label_y = this.xys.get(0).y
                    + G.map.xform_scalar_cv2map(Math.round(2 * radius + 1));

      MapLabel label = new MapLabel(this.getLabelText(), this.getLabelSize(),
                                    0, label_x, label_y);
      return label;
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.WAYPOINT;
   }
   
}

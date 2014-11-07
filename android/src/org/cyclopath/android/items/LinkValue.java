/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;

/**
 * This class represents relationships between attachments and geofeatures.
 * @author Fernando Torre
 */
public class LinkValue extends ItemUserAccess {
   
   /** Attachment referred to by this LinkValue */
   public Attachment attc;
   /** Geofeature referred to by this LinkValue */
   public Geofeature feat;

   // The stack ID and types of the items being linked
   /** stack id of the attachment */
   public int lhs_stack_id;
   /** stack id of the geofeature */
   public int rhs_stack_id;
   /** type id of the attachment */
   public int link_lhs_type_id;
   /** type id of the geofeature */
   public int link_rhs_type_id;
   
   /**
    * Constructor from XML data
    * @param root
    */
   public LinkValue(Node root) {
      super(root);
      this.gmlConsume(root);
   }

   /**
    * Constructor for linking a geofeature and an attachment
    * @param geo
    * @param attc
    */
   public LinkValue(Geofeature geo, Attachment attc) {
      super(null);
      this.feat = geo;
      this.attc = attc;
      this.lhs_stack_id = attc.stack_id;
      this.link_rhs_type_id = geo.getItemTypeId();
      this.rhs_stack_id = geo.stack_id;
      this.link_lhs_type_id = attc.getItemTypeId();
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.LINK_VALUE;
   }

   /**
    * Populates the stack ids of the linked items.
    */
   @Override
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      NamedNodeMap atts = root.getAttributes();
      this.lhs_stack_id = XmlUtils.getInt(atts, "lhs_stack_id", 0);
      this.rhs_stack_id = XmlUtils.getInt(atts, "rhs_stack_id", 0);
      this.link_lhs_type_id = XmlUtils.getInt(atts, "link_lhs_type_id", 0);
      this.link_rhs_type_id = XmlUtils.getInt(atts, "link_rhs_type_id", 0);
   }

   /**
    * Returns an XML String representing this LinkValue.
    */
   @Override
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      document.renameNode(root, null, "link_value");
      root.removeAttribute("name");

      // Stack IDs
      root.setAttribute("lhs_stack_id", Integer.toString(this.lhs_stack_id));
      root.setAttribute("rhs_stack_id", Integer.toString(this.rhs_stack_id));
      // Types
      root.setAttribute("link_lhs_type_id",
                        Integer.toString(this.link_lhs_type_id));
      root.setAttribute("link_rhs_type_id",
                        Integer.toString(this.link_rhs_type_id));
      return document;
   }
}

/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.AccessInfer;
import org.cyclopath.android.conf.ItemType;
import org.cyclopath.android.util.XmlUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;

/**
 * Incomplete class. Will improve when working on editing features.
 * @author Fernando
 */

public abstract class ItemUserAccess {
   
   /** Feature id */
   public int stack_id;
   /** Feature version */
   public int version;
   /** Feature name */
   public String name;
   /** Whether this item has been deleted */
   public boolean deleted;
   /** Whether this item is new (not on the server) */
   public boolean fresh;
   /** Whether this item has been modified */
   public boolean dirty;

   /**
    * Constructor from XML data.
    * @param root
    */
   public ItemUserAccess(Node root) {
      if (root == null) {
         this.fresh = true;
         this.stack_id = G.idNew();
         this.version = 0;
      } else {
         this.fresh = false;
      }
      this.dirty = false;
      this.deleted = false;
   }
   
   /**
    * Returns the type id for this item.
    */
   public int getItemTypeId() {
      return ItemType.ITEM_USER_ACCESS;
   }

   /**
    * Returns the access style for this item.
    */
   public int getStyleId() {
      return AccessInfer.pub_editor;
   }

   /**
    * Populates this Item from an XML.
    * @param root
    */
   public void gmlConsume(Node root) {
      NamedNodeMap atts = root.getAttributes();
      this.stack_id = XmlUtils.getInt(atts, "stid", 0);
      this.version = XmlUtils.getInt(atts, "v", 0);
      this.name = XmlUtils.getString(atts, "name", null);
   }

   /**
    * Returns an XML Document representing this Item.
    */
   public Document gmlProduce() {
      
      DocumentBuilderFactory documentBuilderFactory =
            DocumentBuilderFactory.newInstance();
      try {
         DocumentBuilder documentBuilder =
               documentBuilderFactory.newDocumentBuilder();
         Document document = documentBuilder.newDocument();
         
         Element root = document.createElement("itemuseraccess");
         root.setAttribute("stid", Integer.toString(this.stack_id));
         root.setAttribute("v", Integer.toString(this.version));
         root.setAttribute("name", this.name);
         root.setAttribute("del", this.deleted ? "1" : "0");
         if (this.fresh) {
            root.setAttribute("schg", Integer.toString(this.getStyleId()));
         }
         root.setIdAttribute("stid", true);
         document.appendChild(root);
         return document;
      } catch (ParserConfigurationException e) {
         e.printStackTrace();
         return null;
      }
   }
}

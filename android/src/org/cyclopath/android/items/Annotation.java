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
 * This class represents notes.
 * @author Fernando Torre
 */
public class Annotation extends Attachment {
   
   /**
    * Constructor from XML data
    * @param root
    */
   public Annotation(Node root) {
      super(root);
   }
   
   /**
    * Constructor for empty note
    */
   public Annotation() {
      super(null);
   }

   /**
    * Constructor for note with given text
    * @param text
    */
   public Annotation(String text) {
      super(null);
      this.name = text;
   }
   
   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.ANNOTATION;
   }

   /**
    * Sets name to contain actual comments.
    */
   @Override
   public void gmlConsume(Node root) {
      super.gmlConsume(root);
      NamedNodeMap atts = root.getAttributes();
      this.name = XmlUtils.getString(atts, "comments", null);
   }

   /**
    * Returns an XML String representing this note.
    */
   @Override
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      document.renameNode(root, null, "annotation");
      root.setAttribute("comments", this.name);
      return document;
   }
}

/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import java.util.HashMap;

import org.cyclopath.android.conf.ItemType;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;

import android.util.SparseArray;

/**
 * This class represents tags.
 * @author Fernando Torre
 */
public class Tag extends Attachment
                 implements Comparable<Tag> {

   /** A static list of all tags searchable by tag text */
   public static HashMap<String, Tag> all;
   /** A static list of all tags searchable by stack id */
   public static SparseArray<Tag> all_id;

   /**
    * Constructor from XML data
    * @param root
    */
   public Tag(Node root) {
      super(root);
      all.put(this.name, this);
      all_id.put(this.stack_id, this);
   }

   /**
    * Constructor for new tag with given text
    * @param text
    */
   public Tag(String text) {
      super(null);
      this.name = text;
      if (all.containsKey(this.name)) {
         this.stack_id = all.get(this.name).stack_id;
         this.fresh = false;
      } else {
         all.put(this.name, this);
         all_id.put(this.stack_id, this);
      }
   }

   /**
    * Compare operation for sorting tags alphabetically
    */
   @Override
   public int compareTo(Tag t) {
      return this.name.compareTo(t.name);
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.TAG;
   }

   /**
    * Returns an XML String representing this Tag.
    */
   @Override
   public Document gmlProduce() {
      Document document = super.gmlProduce();
      Element root = document.getElementById(Integer.toString(this.stack_id));
      document.renameNode(root, null, "tag");
      return document;
   }

   /**
    * Returns a string version of this tag (its name)
    */
   @Override
   public String toString() {
      return this.name;
   }
}

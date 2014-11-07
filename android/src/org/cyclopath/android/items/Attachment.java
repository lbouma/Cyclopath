/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.items;

import org.cyclopath.android.conf.ItemType;
import org.w3c.dom.Node;

/**
 * This class represents attachments (tags and notes for now).
 * @author Fernando Torre
 */
public abstract class Attachment extends ItemUserAccess {
   
   /**
    * Constructor
    * @param root
    */
   public Attachment(Node root) {
      super(root);
      if (root != null) {
         this.gmlConsume(root);
      }
   }

   /**
    * Returns the type id for this item.
    */
   @Override
   public int getItemTypeId() {
      return ItemType.ATTACHMENT;
   }

   /**
    * Returns the (possibly shortened) text of this annotation.
    */
   @Override
   public String toString() {
      if (this.name.length() > 100) {
         return this.name.substring(0, 97) + "...";
      } else {
         return this.name;
      }
   }
}

/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android.gwis;

import org.cyclopath.android.conf.Conf;
import org.w3c.dom.Document;

/**
 * This GWIS class handles getting the config.
 * @author Fernando Torre
 */
public class GWIS_ValueMapGet extends GWIS {
   
   /** Method to call upon completion, if any */
   private GWIS_ValueMapGetCallback callback;

   /**
    * Constructor
    */
   public GWIS_ValueMapGet() {
      this(null);
   }
   
   /**
    * Constructor
    */
   public GWIS_ValueMapGet(GWIS_ValueMapGetCallback callback) {
      super("item_draw_class_get");
      this.callback = callback;
   }
   
   @Override
   /**
    * Initializes Conf using the results.
    */
   protected void processResultset(Document rset) {
      Conf.importXml(rset);
      if (this.callback != null) {
         this.callback.handleGWIS_ValueMapGetCallback();
      }
      GWIS.retryAll();
   }
}

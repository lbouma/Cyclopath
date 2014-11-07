/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */
package org.cyclopath.android;

import java.lang.ref.WeakReference;

import android.os.Handler;
import android.os.Message;

/**
 * This class implements a Handler that uses weak references to Activities
 * in order to avoid memory leaks.
 * @author Fernando Torre
 */
public class CyclopathHandler extends Handler {
   
   /** Weak reference to BaseActivity */
   private WeakReference<BaseActivity> ref;
   /** Weak reference to BaseListActivity */
   private WeakReference<BaseListActivity> reflist;

   /**
    * Constructor for normal Activities
    * @param activity
    */
   public CyclopathHandler(BaseActivity activity) {
      this.ref = new WeakReference<BaseActivity>(activity);
   }

   /**
    * Constructor for list Activities
    * @param activity
    */
   public CyclopathHandler(BaseListActivity activity) {
      this.reflist = new WeakReference<BaseListActivity>(activity);
   }

   /**
    * Handles a message by sending it to the corresponding Activity, if it
    * still exists.
    */
   @Override
   public void handleMessage(Message msg) {
      if (this.ref != null) {
         BaseActivity activity = this.ref.get();
         if (activity != null) {
            activity.handleMessage(msg);
         }
      }
      if (this.reflist != null) {
         BaseListActivity listactivity = this.reflist.get();
         if (listactivity != null) {
            listactivity.handleMessage(msg);
         }
      }
   }

}

/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.net;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.gwis.GWIS;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.os.Message;

/**
 * Handles network (wifi/cellular) changes by redrawing the map
 * @author Phil Brown
 */
public class NetworkListener extends BroadcastReceiver {

   @Override
   public void onReceive(Context context, Intent intent) {
      if (G.isConnected() &&
          intent.getAction().equals(ConnectivityManager.CONNECTIVITY_ACTION)) {
         if (G.cyclopath_handler != null) {
            Message msg = Message.obtain();
            msg.what = Constants.REFRESH_NEEDED;
            msg.setTarget(G.cyclopath_handler);
            msg.sendToTarget();
         }
         GWIS.retryAll();
      }
   }//onReceive

}//NetworkListener

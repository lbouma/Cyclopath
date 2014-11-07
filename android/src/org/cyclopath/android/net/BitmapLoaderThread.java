/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.net;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;




import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Log;

/**
 * A thread that downloads a bitmap and then sends it to the callback method.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class BitmapLoaderThread extends Thread {
   
   private String src;
   BitmapLoadCallback callback;
   
   /**
    * Constructor
    * @param src url for the bitmap
    * @param callback callback that will be called when this thread ends.
    */
   public BitmapLoaderThread(String src, BitmapLoadCallback callback) {
      this.src = src;
      this.callback = callback;
   }
   
   /**
    * Main thread method. Downloads a bitmap from a url.
    */
   @Override
   public void run() {
      try {
         URL url = new URL(this.src);
         HttpURLConnection connection =
            (HttpURLConnection) url.openConnection();
         connection.setDoInput(true);
         int tries = 5;
         // Try up to five times
         while (tries > 0) {
            try {
               connection.connect();
               break;
            } catch (IOException e) {
               tries--;
            }
         }
         
         InputStream input = connection.getInputStream();
         Bitmap b = BitmapFactory.decodeStream(input);
         connection.disconnect();
         this.callback.handleBitmapLoad(b);
      } catch (IOException e) {
         Log.e("error","Error getting bitmap");
         e.printStackTrace();
         this.callback.handleBitmapLoad(null);
      }
   }
}

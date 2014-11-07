/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.net;

import android.graphics.Bitmap;

/**
 * An interface for classes that can handle a bitmap download.
 * @author Fernando Torre
 * @author Phil Brown
 */
public interface BitmapLoadCallback {

   /**
    * This method is called once a bitmap has been downloaded.
    * @param b the downloaded bitmap
    */
   public void handleBitmapLoad(Bitmap b);
}

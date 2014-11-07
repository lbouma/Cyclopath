/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.conf;

import android.util.SparseArray;


/**
 * This class represents drawing parameters for a given draw class.
 * @author Fernando Torre
 */
public class DrawParam {

   /** color for this draw class */
   public int color;
   /** Contains other drawing parameters which depend on the zoom level. */
   public SparseArray<ZoomParam> zoom_params;
   
   /**
    * Default constructor.
    */
   public DrawParam() {
      color = 0;
      zoom_params = new SparseArray<ZoomParam>();
   }
}

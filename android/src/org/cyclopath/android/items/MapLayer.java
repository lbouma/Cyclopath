/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;


import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.util.Dual_Rect;

import android.util.Log;

/**
 * Class representing one active layer of the map. An active layer is a layer
 * which contains interactive or fetched map objects. This class is originally
 * based on flashclient/Map_Layer.as.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class MapLayer {
   
   /** z level of this layer */
   public float zplus;
   
   /** vector of features in this layer.*/
   public ArrayList<Feature> children;
   
   /**
    * Constructor
    * @param zplus z level of layer.
    */
   public MapLayer(float zplus) {
      this.zplus = zplus;
      this.children = new ArrayList<Feature>();
   }
   
   // *** Instance methods

   /**
    *  Add a feature to the layer.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    * @param f feature to be added.
    */
   public void featureAdd(Feature f) {
      this.children.add(f);
      G.map.redraw();
   }

   /**
    *  Discard a particular feature.
    *  Note: The naming format for this method was derived from the Flash client
    *  code.
    * @param f feature to be discarded.
    */
   public synchronized void featureDiscard(Feature f) {
      children.remove(f);
      G.map.redraw();
   }
   
   /**
    * Deselects all geofeatures in this layer.
    */
   public void featuresDeselect() {
      for (Feature f: this.children) {
         if (Geofeature.class.isInstance(f)) {
            ((Geofeature) f).selected = false;
         }
      }
      G.map.redraw();
   }
   
   /**
    *  Discard all features in this layer.
    *  Note: The naming format for this method was derived from the Flash
    *  client code.
    * @param r only features outside of r will be discarded.
    */
   public synchronized void featuresDiscard(Dual_Rect r, boolean force) {
      for (int i = children.size()-1; i >= 0; i--) {
         if (children.get(i).isDiscardable() || force) {
            if (r == null || children.get(i).getBboxMap() == null) {
               children.get(i).cleanup();
               children.remove(i);
            } else if (!r.interstects_map_rect(children.get(i)
                                                       .getBboxMap())) {
               children.get(i).cleanup();
               children.remove(i);
            } 
         }
      }//TODO: I got a null pointer error here
      G.map.redraw();
   }
   
   /**
    * Labels all features in this layer.
    */
   public void featuresLabel() {
      for(int i = 0; i < children.size(); i++){
         if (children.get(i) instanceof Geofeature) {
            ((Geofeature) children.get(i)).labelMaybe();
         }
      }
   }

   /**
    *  Redraw all features in this layer.
    *  Note: The naming format for this method was derived from the Flash
    *  client code.
    */
   public synchronized void featuresRedraw() {
      try {
         for (int i = children.size()-1; i >= 0; i--) {
            children.get(i).drawShadow();
         }
         for (int i = children.size()-1; i >= 0; i--) {
            children.get(i).draw();
         }
      } catch (ArrayIndexOutOfBoundsException e) {
         // I believe I fixed this error in bug 2076, but added this
         // try catch segment in case it happens again.
         if (Constants.DEBUG) {
            Log.d("debug","Sychronization error!");
         }
         e.printStackTrace();
      } catch (NullPointerException e) {
         if (Constants.DEBUG) {
            // We ran into this null pointer error. Adding debug info for
            // if it happens again, so that we now what layer was
            // responsible. This seems like we are adding a null item to a
            // layer or making it null without removing it from the layer.
            Log.d("debug","null pointer exception error!");
            Log.d("debug","This happened in layer: " + this.zplus);
         }
         e.printStackTrace();
      }
   }
   
   /**
    * Check if this layer is empty.
    * @return true if there are no objects in this layer.
    */
   public boolean isEmpty() {
      return (this.children.isEmpty());
   }
   
   /**
    * Returns concatenated string of features in this layer.
    */
   @Override
   public String toString(){
      if (children.size() == 0) {
         return "";
      }
      StringBuilder f = new StringBuilder(children.get(0).toString());
      for(int i = 1; i < children.size(); i++){
         f.append(", " + children.get(i).toString());
      }
      return f.toString();
   }
}

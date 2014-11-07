/* Copyright (c) 2006-2011 Regents of the University of Minnesota.
 * For licensing terms, see the file LICENSE.
 */

package org.cyclopath.android.items;

import java.util.ArrayList;

import org.cyclopath.android.G;
import org.cyclopath.android.R;
import org.cyclopath.android.conf.Constants;
import org.cyclopath.android.net.BitmapLoadCallback;
import org.cyclopath.android.net.BitmapLoaderThread;
import org.cyclopath.android.util.Dual_Rect;

import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.util.Log;

/**
 * A map image Tile. This class is originally based on flashclient/Tile.as.
 * @author Fernando Torre
 * @author Phil Brown
 */
public class Tile implements Feature,
                             BitmapLoadCallback {
   
   /** this tile's rectangle's coordinates */
   public Dual_Rect rect;
   /** tile image */
   public Bitmap image;
   /** tile zoom level */
   public int zoom_level;
   /** readable tile name */
   protected String tilename;
   /** tile's source url */
   protected String url;
   /** tile index x */
   protected int xi;
   /** tile index y */
   protected int yi;
   /** tile class (to differentiate between aerial and normal tiles) */
   protected String tclass;
   /** bounding box in map coordinates */
   protected RectF bbox_map;

   /**
    * Constructs a tile.
    * @param xi tile index x
    * @param yi tile index y
    * @param tclass class of tiles
    */
   public Tile(int xi, int yi, String tclass) {
      
      String layer_name;
      String image_format;
      String wms_url;
      
      this.xi = xi;
      this.yi = yi;
      this.tclass = tclass;
      this.zoom_level = G.zoom_level;
      
      if (tclass.equals("aerial")) {
         layer_name = Constants.PHOTO_LAYERS[G.aerial_state][0];
         image_format = "image/jpeg";
         wms_url = Constants.WMS_URL_AERIAL;
      } else {
         layer_name = Constants.INSTANCE_NAME;
         image_format = "image/png";
         wms_url = Constants.SERVER_URL + Constants.WMS_URL_CYCLOPATH;
      }
      
      this.url = (wms_url
                  + "&SERVICE=WMS"
                  + "&VERSION=1.1.1"
                  + "&REQUEST=GetMap"
                  + "&LAYERS=" + layer_name
                  + "&SRS=EPSG:" + Constants.SRID
                  + "&BBOX=" + Tile.tileindex_to_coord(xi)
                  + "," + Tile.tileindex_to_coord(yi)
                  + "," + Tile.tileindex_to_coord(xi + 1)
                  + "," + Tile.tileindex_to_coord(yi + 1)
                  + "&WIDTH=" + Constants.TILE_SIZE
                  + "&HEIGHT=" + Constants.TILE_SIZE
                  + "&FORMAT=" + image_format);
      
      if (Constants.DEBUG) {
         Log.d("tiles", this.url);
      }
      
      // friendly tile name for log
      this.tilename = (this.tclass
                       + "," + layer_name
                       + "," + this.zoom_level
                       + "," + this.xi
                       + "," + this.yi);
      
      this.rect = new Dual_Rect();

      this.rect.setMap_min_x(Tile.tileindex_to_coord(xi));
      this.rect.setMap_max_y(Tile.tileindex_to_coord(yi + 1));
      this.rect.setMap_max_x((float) (this.rect.getMap_min_x()
                             + G.map.xform_scalar_cv2map(Constants.TILE_SIZE)));
      this.rect.setMap_min_y((float) (this.rect.getMap_max_y()
                             - G.map.xform_scalar_cv2map(Constants.TILE_SIZE)));
      this.bbox_map = this.bbox_map_compute();
   }
   
   // *** Static methods
   
   /**
    *  Returns the tile index containing coordinate c at the current zoom
    *  level. See the technical documentation for more information.
    *  @param c coordinate
    *  @return tile index
    */
   public static int coord_to_tileindex(double c) {
      return (int) Math.round(Math.floor(c/meters_per_tile()));
   }
   
   /**
    *  Returns the width of a tile in degrees.
    */
   public static double meters_per_tile() {
      return (Constants.TILE_SIZE/G.map.getScale());
   }
   
   /**
    * Returns the coordinate of the smaller edge of the tile with index i.
    * @param i tile index
    */
   public static double tileindex_to_coord(int i) {
      return (i * meters_per_tile());
   }
   
   // *** Other methods
   
   /**
    * Computes the bounding rectangle for this tile.
    * @return bounding rectangle
    */
   public RectF bbox_map_compute() {
      return new RectF((float) this.rect.getMap_min_x(),
                       (float) this.rect.getMap_min_y(),
                       (float) (this.rect.getMap_min_x()
                                + this.rect.getMapWidth()),
                       (float) (this.rect.getMap_min_y()
                                + this.rect.getMapHeight()));
   }

   /** No-op */
   @Override
   public void cleanup() {}

   /**
    * Draws the tile on the map canvas.
    */
   @Override
   public void draw() {
      if (this.zoom_level == G.zoom_level) {
         if (this.image != null){
            G.map.map_canvas.drawBitmap(
            this.image, null,
            new Rect(this.rect.getCv_min_x(),
                     this.rect.getCv_min_y(),
                     this.rect.getCv_max_x(),
                     this.rect.getCv_max_y()),
                  null);
         } else if (this.image == null) {
            // draw default image
            Paint p = new Paint();
            p.setAntiAlias(true);
            p.setColor(Constants.BACKGROUND);
            p.setStyle(Paint.Style.FILL);
            G.map.map_canvas.drawRect(new Rect(this.rect.getCv_min_x(),
                                               this.rect.getCv_min_y(),
                                               this.rect.getCv_max_x(),
                                               this.rect.getCv_max_y()), p);
            p.setColor(Color.BLACK);
            p.setStyle(Paint.Style.STROKE);
            G.map.map_canvas.drawText(
                  G.app_context.getString(R.string.cannot_retrieve_tile),
                  this.rect.getCv_min_x() + 5,
                  (this.rect.getCv_min_y() + this.rect.getCv_max_y())/2,
                  p);
         }
      }
   }

   /** No-op */
   @Override
   public void drawShadow() {}

   /**
    * Starts a thread that fetches the tile image from its url.
    */
   public void fetch_tile() {
      BitmapLoaderThread loader = new BitmapLoaderThread(this.url, this);
      loader.start();
   }
   
   /**
    * Gets the bounding box for this tile.
    */
   @Override
   public RectF getBboxMap() {
      return this.bbox_map;
   }
   
   /**
    * Return z level of tiles.
    */
   @Override
   public float getZplus() {
      return Constants.TILE_LAYER;
   }

   /**
    * This method is called once a tile image has been downloaded.
    * @param b the downloaded bitmap
    */
   @Override
   public void handleBitmapLoad(Bitmap b) {
      this.image = b;
      if (G.layers.get(this.getZplus()) != null) {
         ArrayList<Feature> children = G.layers.get(this.getZplus()).children;
         if (children != null) {
            if (children.contains(this)) {
               G.map.redraw();
               return;
            }
         }
      }
      G.map.featureAdd(this);
   }

   @Override
   public boolean init() {
      return true;
   }

   /**
    * Returns true, since tiles are always discardable.
    */
   @Override
   public boolean isDiscardable() {
      return true;
   }

   /** Returns the name of the tile. */
   @Override
   public String toString(){
	   return tilename;
   }
   
}

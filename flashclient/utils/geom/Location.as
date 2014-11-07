/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Location is used for displaying locations (either addresses or points)
// on the map.

package utils.geom {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import mx.controls.Alert;

   import utils.misc.Collection;
   import utils.misc.Map_Label;

   public class Location extends Sprite implements MOBRable_DR {

      protected var minx:Number;
      protected var miny:Number;
      protected var maxx:Number;
      protected var maxy:Number;
      protected var dr:Dual_Rect;
      protected var locs:Array;

      // *** Constructor

      // locs is an array of arrays, each containing five items:
      //    [0] the x coordinate
      //    [1] the y coordinate
      //    [2] width
      //    [3] height
      //    [4] address/point name
      //    [5] gc_fulfiller
      //    [6] gc_confidence
      // FIXME: The array 'locs' should probably be turned into an array of
      // objects.
      public function Location(locs:Array)
      {
         super();
         this.locs = Collection.array_copy(locs);
         draw();
      }

      // *** Public instance methods

      //
      public function draw() :void
      {
         var gr:Graphics = this.graphics;
         var startx:Number;
         var starty:Number;
         var label:Map_Label;
         var loc:Array;

         var x:Number;
         var y:Number;
         var w:Number;
         var h:Number;
         var addy_or_point_name:String;
         var gc_fulfiller:String;
         var gc_confidence:Number;

         this.minx = Number.POSITIVE_INFINITY;
         this.miny = Number.POSITIVE_INFINITY;
         this.maxx = Number.NEGATIVE_INFINITY;
         this.maxy = Number.NEGATIVE_INFINITY;

         gr.clear();
         while (this.numChildren > 0) {
            this.removeChildAt(0);
         }

         for each (loc in this.locs) {
            x = Number(loc[0]);
            y = Number(loc[1]);
            w = (loc[2] === null) ? 0 : Number(loc[2]);
            h = (loc[3] === null) ? 0 : Number(loc[3]);
            addy_or_point_name = loc[4];
            gc_fulfiller = loc[5];
            gc_confidence = (loc[6] === null) ? 0 : Number(loc[6]);

            startx = G.map.xform_x_map2cv(x);
            starty = G.map.xform_y_map2cv(y);

            gr.beginFill(0x00bb00);
            gr.lineStyle(2, 0x000000);
            gr.drawCircle(startx, starty, 8);
            gr.endFill();

            if ((gc_fulfiller != 'ccp_gf') && (gc_fulfiller != 'ccp_pt')) {
               // An external geocode result.
               label = new Map_Label(
                  addy_or_point_name, 15, 0, startx-2, starty-24);
               this.addChild(label);
            }
            // else, presumably, there's a map item associated with this
            // region, waypoint, terrain, or byway...

            this.minx = Math.min(this.minx, x - w / 2);
            this.miny = Math.min(this.miny, y - h / 2);
            this.maxx = Math.max(this.maxx, x + w / 2);
            this.maxy = Math.max(this.maxy, y + h / 2);
         }

         this.dr = new Dual_Rect();
         this.dr.map_min_x = this.minx; // left
         this.dr.map_max_y = this.maxy; // top
         this.dr.map_max_x = this.maxx; // right
         this.dr.map_min_y = this.miny; // bottom
      }

      //
      public function get mobr_dr() :Dual_Rect
      {
         return dr;
      }

   }
}


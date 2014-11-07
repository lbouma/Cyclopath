/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// A Basemap Polygon is an area feature which gives context to the map.

package items.feats {

   import flash.display.Graphics;
   import flash.utils.Dictionary;
   import mx.utils.ObjectUtil;

   import items.Geofeature;
   import items.Record_Base;
   import items.utils.Geofeature_Layer;
   import items.utils.Item_Type;
   import utils.geom.Geometry;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Objutil;
   import utils.rev_spec.*;
   import views.base.UI;

   public class Terrain extends Geofeature {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Terrain');

      // *** Mandatory attributes

      public static const class_item_type:String = 'terrain';
      public static const class_gwis_abbrev:String = 'trrn';
      public static const class_item_type_id:int = Item_Type.TERRAIN;

      // The Class of the details panel used to show info about this item.
      // Which doesn't exist for Terrain... yet...?
      //public static const dpanel_class_static:Class = Panel_Item_Terrain;

      // SYNC_ME: Search geofeature_layer table.
      public static const geofeature_layer_types:Array = [
         Geofeature_Layer.TERRAIN_OPENSPACE,
         Geofeature_Layer.TERRAIN_WATER,
         ];

      // *** Other static variables

      protected static var DUMMY:Terrain = new Terrain();

      // *** Instance variables

      // Coordinate arrays for internal rings
      protected var internal_xs:Array = null;
      protected var internal_ys:Array = null;

      // *** Constructor

      public function Terrain(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         // BUG nnnn: Editable Terrain.
         super(xml, rev);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Terrain = (to_other as Terrain);
         super.clone_once(other);
         if (this.internal_xs !== null) {
            other.internal_xs = Collection.array_copy(this.internal_xs);
         }
         if (this.internal_ys !== null) {
            other.internal_ys = Collection.array_copy(this.internal_ys);
         }
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Terrain = (to_other as Terrain);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            Geometry.coords_string_to_xys(gml.external.text(),
                                          this.xs, this.ys);
            // Silly, non-standard XMLList, and your length() fcn.
            //m4_DEBUG('gml.internal.length():', gml.internal.length());
            this.internal_xs = new Array();
            this.internal_ys = new Array();
            for each (var e:XML in gml.internal) {
               var xs_tmp:Array = new Array();
               var ys_tmp:Array = new Array();
               Geometry.coords_string_to_xys(e.text(), xs_tmp, ys_tmp);
               this.internal_xs.push(xs_tmp);
               this.internal_ys.push(ys_tmp);
            }
         }
      }

      // BUG 694: Editable terrain. Implement gml_produce.

      // ***

      //
      override public function draw(is_drawable:Object=null) :void
      {
         var gr:Graphics = this.sprite.graphics;
         var x:Number;
         var y:Number;
         var i:int;
         var j:int;

         super.draw();

         gr.clear();
         // No way to turn off line drawing?

         if (G.map.aerial_enabled) {
            gr.lineStyle(2, this.draw_color);
         }
         else {
            gr.lineStyle(0, this.draw_color);
            gr.beginFill(this.draw_color);
         }

         // Draw external ring
         x = G.map.xform_x_map2cv(xs[0]);
         y = G.map.xform_y_map2cv(ys[0]);
         gr.moveTo(x, y);
         for (i = xs.length - 1; i >= 0; i--) {
            x = G.map.xform_x_map2cv(xs[i]);
            y = G.map.xform_y_map2cv(ys[i]);
            gr.lineTo(x, y);
         }

         // Draw internal rings
         if ((this.internal_xs !== null)
             && (this.internal_ys !== null)) {
            for (i = 0; i < internal_xs.length; i++) {
               x = G.map.xform_x_map2cv(internal_xs[i][0]);
               y = G.map.xform_y_map2cv(internal_ys[i][0]);
               gr.moveTo(x, y);
               for (j = internal_xs[i].length - 1; j >= 0; j--) {
                  x = G.map.xform_x_map2cv(internal_xs[i][j]);
                  y = G.map.xform_y_map2cv(internal_ys[i][j]);
                  gr.lineTo(x, y);
               }
            }
         }

         gr.endFill();
      }

      // ***

      //
      override public function get actionable_at_raster() :Boolean
      {
         return true;
      }

      //
      public function get counterpart() :Terrain
      {
         var c:Terrain = (this.counterpart_untyped as Terrain);
         return Objutil.null_replace(c, DUMMY);
      }

      //
      override public function get counterpart_gf() :Geofeature
      {
         return this.counterpart;
      }

      //
      override public function get drawable_at_zoom_level() :Boolean
      {
         return G.map.zoom_is_vector();
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         return G.map.zoom_is_vector();
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Geofeature.all;
      }

      //
      override public function get is_clickable() :Boolean
      {
         return false;
      }

      //
      override protected function label_parms_compute() :void
      {
         // No-op
      }

      //
      override protected function get mouse_enable() :Boolean
      {
         var mouse_enable:Boolean = false;
         return mouse_enable;
      }

      // FIXME: 2011.03.10 [lb] Copied this fcn. over. So there are more that
      //        are missed: compare against Region.as, since they're
      //        practically identical classes.
      //
      override public function get vertex_add_enabled() :Boolean
      {
         return true;
      }

      // *** Developer methods

      //
      /* This is really verbose.
      override public function toString() :String
      {
         return (super.toString()
                 + ' | internal_xs: ' + this.internal_xs
                 + ' | internal_ys: ' + this.internal_ys
                 );
      }
      */

   }
}


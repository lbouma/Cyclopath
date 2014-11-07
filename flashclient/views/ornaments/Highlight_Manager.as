/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.ornaments {

   import flash.display.Sprite;
   import flash.utils.Dictionary;
   import flash.display.Graphics;

   import items.Geofeature;
   import items.feats.Region;
   import items.feats.Waypoint;
   import utils.misc.Logging;
   import utils.misc.Set2;
   import views.base.Paint;

   public class Highlight_Manager extends Sprite {

      protected var layers:Dictionary;
      protected var feature_sprites:Dictionary;

      public var highlightedset:Set2;

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('HighlightMan');

      // *** Constructor

      public function Highlight_Manager()
      {
         super();

         this.highlightedset = new Set2();
         this.layers = new Dictionary();
         this.feature_sprites = new Dictionary();
      }

      // *** Layer management functions

      //
      public function init_layer_properties() :void
      {
         this.set_layer_properties(Conf.path_highlight,
                                   Conf.path_highlight_color,
                                   false);
         this.set_layer_properties(Conf.mouse_highlight,
                                   Conf.mouse_highlight_color,
                                   false);
         this.set_layer_properties(Conf.attachment_highlight,
                                   Conf.attc_highlight_color,
                                   false);
         this.set_layer_properties(Conf.attachment_hover_highlight,
                                   Conf.attc_hover_highlight_color,
                                   false);
         this.set_layer_properties(Conf.resolver_highlight,
                                   Conf.resolver_highlight_color,
                                   false);
      }

      // Sets the given layers color and visibility.
      // If layer doesn't exist, a new layer is created.
      public function set_layer_properties(layer:String,
                                           color:int, visible:Boolean) :void
      {
         if (!(layer in this.layers)) {
            this.layers[layer] = new Layer();
            this.addChild(this.layers[layer]);
            m4_DEBUG('set_layer_properties: new layer:', layer);
         }

         if (this.layers[layer].color != color) {
            this.layers[layer].color = color;
            // TODO: re-render highlights for this layer
         }

         this.layers[layer].visible = visible;
      }

      // Getters and setters for a layer color.  If the layer isn't present
      // for a get, Conf.route_color is returned.  If it isn't present for a
      // set, a new layer is created with the color and visible = true.
      public function get_layer_color(layer:String) :int
      {
         if (layer in this.layers) {
            return this.layers[layer].color;
         }
         return Conf.route_color;
      }

      //
      public function set_layer_color(layer:String, color:int) :void
      {
         if (layer in this.layers) {
            this.set_layer_properties(layer, color,
                                      this.layers[layer].visible);
         }
         else {
            this.set_layer_properties(layer, color, true);
         }
      }

      // Getters and setters for layer visibility.  If the layer isn't present,
      // true is returned for a get.  If a layer isn't present for a set,
      // a new layer is created with the given visibility and a color of
      // Conf.route_color.
      public function is_layer_visible(layer:String) :Boolean
      {
         if (layer in this.layers) {
            return this.layers[layer].visible;
         }
         return true;
      }

      //
      public function set_layer_visible(layer:String, visible:Boolean) :void
      {
         if (layer in this.layers)
            this.set_layer_properties(layer, this.layers[layer].color,
                                      visible);
         else
            this.set_layer_properties(layer, Conf.route_color, visible);
      }


      // *** Geofeature highlight functions

      //
      public function is_highlighted(f:Geofeature, l:String=null) :Boolean
      {
         return this.highlightedset.is_member(f, l);
      }

      // Sets the highlight state for the given geofeature and layer.
      // If layer doesn't exist and h is true, a new layer is created
      // with default color.
      // If l is null, then all layers previously created are affected by h.
      public function set_highlighted(f:Geofeature,
                                      h:Boolean,
                                      l:String=null) :void
      {
         m4_TALKY('set_highlighted: h:', h, '/ l:', l, '/ f:', f);
         if (l === null) {
            var layer:String;
            for (layer in this.layers) {
               this.set_highlighted(f, h, layer);
            }
         }
         else if (h != is_highlighted(f, l)) {
            if (h) {
               this.highlightedset.add(f, l);
               m4_ASSERT(this.is_highlighted(f, l));
               if (!(l in this.layers)) {
                  this.set_layer_properties(l, Conf.route_color, true);
               }
               if (!(f.stack_id in this.feature_sprites)) {
                  this.feature_sprites[f.stack_id] = new Dictionary();
               }
               this.feature_sprites[f.stack_id][l] = new Sprite();
               this.layers[l].addChild(this.feature_sprites[f.stack_id][l]);
               this.render_highlight(f, l);
            }
            else {
               this.highlightedset.remove(f, l);
               m4_ASSERT(!this.is_highlighted(f, l));
               if (f.stack_id in this.feature_sprites) {
                  try {
                     this.layers[l].removeChild(
                        this.feature_sprites[f.stack_id][l]);
                     delete this.feature_sprites[f.stack_id][l];
                  }
                  catch (e:TypeError) {
                     // TypeError: Error #2007: Parameter child must be
                     //                         non-null.
                     m4_WARNING('set_highlighted: not a child:', f.toString());
                  }
                  if (!this.is_highlighted(f)) {
                     delete this.feature_sprites[f.stack_id];
                  }
               }
            }
         }
      }

      //
      public function layer_count(l:String=null) :int
      {
         var c:int = 0;
         var o:Object;

         if (l === null) {
            return this.highlightedset.length;
         }
         else {
            for (o in this.highlightedset) {
               if (this.highlightedset.is_member(o, l)) {
                   c++;
               }
            }
            return c;
         }
      }

      // Renders a highlight. If l is null, then all highlights are
      // re-rendered, otherwise, just the highlight for the given layer.
      public function render_highlight(feat:Geofeature,
                                       layer:String=null) :void
      {
         if (feat !== null) {
            if (layer === null) {
               var layer_name:String;
               // This seems costly: aren't Geofeatures just in one layer?
               for (layer_name in this.layers) {
                  if (this.is_highlighted(feat, layer_name)) {
                     var layer_lookup:Dictionary;
                     layer_lookup = this.feature_sprites[feat.stack_id];
                     if (layer_lookup !== null) {
                        var feat_sprite:Sprite = layer_lookup[layer_name];
                        if (feat_sprite !== null) {
                           this.render_highlight_geom(
                              feat_sprite.graphics,
                              feat, this.layers[layer_name].color);
                        }
                        else {
                           m4_WARNING2('BUG nnnn: no feat_sprite: feat:',
                                       feat.toString());
                        }
                     }
                     else {
                        // BUG nnnn: This happens when you deeplink to a map
                        // item. The item is not selected, and when you click
                        // on it, bam, this happens.
                        // Now what happens is the item details panel loads,
                        // but nothing is selected on the map. When you click
                        // the item who's panel you're viewing, the item is
                        // selected on the map and a new details panel opens.
                        // So obviously there's a disconnect somewhere...
                        // it might just be the panel, or maybe there are two
                        // items in the system?
                        m4_WARNING2('BUG nnnn: no layer_lookup: feat:',
                                    feat.toString());
                     }
                  }
               }
            }
            else if (this.is_highlighted(feat, layer)) {
               this.render_highlight_geom(
                  this.feature_sprites[feat.stack_id][layer].graphics,
                  feat, this.layers[layer].color);
            }
         }
         else {
            m4_WARNING('render_highlight: your feat is null?');
         }
      }

      //
      protected function render_highlight_geom(g:Graphics,
                                               f:Geofeature,
                                               layer_color:int) :void
      {
         var draw_width:Number;

         g.clear();

         //m4_DEBUG('node_cleanup: calling is_drawable');
         if (f.is_drawable) {
            draw_width = f.draw_width;
         }
         else {
            draw_width = 1;
         }

         if (f is Waypoint) {
            g.beginFill(layer_color, Conf.highlight_alpha);
            g.drawCircle((f as Waypoint).x_cv, (f as Waypoint).y_cv,
                         draw_width / 2);
            g.endFill();
         }
         else {
            Paint.line_draw(g, f.xs, f.ys, draw_width,
                            layer_color, Conf.highlight_alpha);
         }

         // FIXME: hack, this should be in Region
         if (f is Region) {
            (f as Region).crosshairs_draw(g, true, false);
         }
      }

   }
}

// *** Inline helper class

import flash.display.Sprite;

class Layer extends Sprite
{
   public var color:int;
}


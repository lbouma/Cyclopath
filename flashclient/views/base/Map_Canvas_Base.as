/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Part of the Map class hierarchy.
//
// The Map class base class implements the very most abstract functionality.

package views.base {

   import flash.utils.Dictionary;
   import mx.core.UIComponent;

   import items.Geofeature;
   import utils.misc.Logging;
   import utils.misc.Set2;
   import views.ornaments.Group_Selection;
   import views.ornaments.Highlight_Manager;

   public class Map_Canvas_Base extends UIComponent {

      // *** Class variables

      protected static var log:Logging = Logging.get_logger('MC_Base!');

      // *** Instance variables

      // Layers containing the actual map data
      public var layers:Dictionary;
      public var shadows:Dictionary;

      public var orn_selection:Group_Selection;

      // Additional variables and layers used for highlighting
      public var highlight_manager:Highlight_Manager;
      public var highlights:Map_Layer_Passive;
      public var higherlights:Map_Layer_Passive; // Higher than highlights! :)
      public var to_be_highlighted:Array;

      // Used on discard_and_update
      //protected var action_user:Boolean;
      //protected var user_change:Boolean;
      public var user_loggingin:* = null;
      public var user_loggedout:* = null;
      public var branch_changed:* = null;

      // *** Constructor

      public function Map_Canvas_Base()
      {
         super();

         // These tweaks improve performance
         this.opaqueBackground = Conf.background_color;
         this.cacheAsBitmap = true;

         // For layer highlights/shadows
         //this.orn_selection = new Group_Selection();
         this.to_be_highlighted = new Array();
      }

      // *** Instance methods

      // Replace child c with new child cnew. Return cnew.
      public function child_replace(c:UIComponent,
                                    cnew:UIComponent) :UIComponent
      {
         var i:int = this.getChildIndex(c);
         this.removeChildAt(i);
         this.addChildAt(cnew, i);
         return cnew;
      }

      // Discard the current state of the map and re-update.  Depending
      // on the value of user_change, this performs slightly different actions.
      //
      // When not logged in and logging in, dirty changes are preserved and
      // private changes are fetched. In other cases (i.e., logging out),
      // everything is reset.
      //
      // Because this function updates the map, any user status or map
      // revision/mode changes should be made before executing this cmd, or
      // dirty items should be retained.
      public function discard_and_update(user_loggingin:Boolean=false,
                                         user_loggedout:Boolean=false,
                                         branch_changed:Boolean=false) :void
      {
         m4_DEBUG3('discard_and_update: user_loggingin:', user_loggingin,
                                     '/ user_loggedout:', user_loggedout,
                                     '/ branch_changed:', branch_changed);
         this.user_loggingin = user_loggingin;
         this.user_loggedout = user_loggedout;
         this.branch_changed = branch_changed;
         this.discard_preserve();
         this.discard_reset();
         this.discard_restore();
         this.discard_update();
         m4_DEBUG('discard_and_update: Done!');
         this.user_loggingin = null;
         this.user_loggedout = null;
         this.branch_changed = null;
      }

      //
      protected function discard_preserve() :void
      {
         // no-op
      }

      //
      protected function discard_reset() :void
      {
         m4_DEBUG('discard_reset');

         this.highlights_clear();

         // EXPLAIN: Does this remove all of the item sprites? Meaning,
         //          Geofeature's item_cleanup() gets called?
         while (this.numChildren > 0) {
            this.removeChildAt(0);
         }

         this.layers = new Dictionary();
         this.shadows = new Dictionary();

         // Set up highlights

         this.highlights = new Map_Layer_Passive(930);
         this.orn_selection = new Group_Selection();
         this.highlights.addChild(this.orn_selection);
         // NOTE: We let Map_Canvas_Items call
         //        this.layer_add_child(this.highlights)
         //       so that sprites are layered correctly.

         this.highlight_manager = new Highlight_Manager();
         this.highlight_manager.init_layer_properties();
         // FIXME: Parent class Map_Canvas_Item adds this.orn_selection next,
         //        which used to happen before adding this.highlight_manager.
         //        Make sure everything still works ok.
         // Initialize highlights
         this.highlights.addChild(this.highlight_manager);

         // Set up higherlights

         this.higherlights = new Map_Layer_Passive(950);
         // NOTE: We let Map_Canvas_Items call
         //        this.layer_add_child(this.higherlights)
         //       so that sprites are layered correctly.
      }

      //
      protected function discard_restore() :void
      {
         // no-op
      }

      //
      protected function discard_update() :void
      {
         // no-op
      }

      //
      public function highlights_clear(layer:String=null) :void
      {
         var old:Set2;
         var f:Object;

         //m4_DEBUG('highlights_clear: layer:', layer);

         if (this.highlight_manager === null) {
            return;
         }
         else {
            old = this.highlight_manager.highlightedset.clone();
            for (f in old) {
               (f as Geofeature).set_highlighted(false, layer);
            }
            m4_ASSERT(this.highlight_manager.layer_count(layer) == 0);
         }
      }

      // addChild() the given layer in its proper place, ordering by zplus
      // with the following rules. Map_Layer_Passives compare only the integer
      // portion of zplus, while Map_Layers compare using the full quantity.
      // This is because all shadows of Geofeatures with the same Z value
      // should be drawn below all Geofeatures with that Z value, but
      // Map_Layers have meaningful order below the Z level, for aesthetic
      // reasons (i.e., bigger roads should always be drawn on top of smaller
      // ones or the intersections look funny).
      protected function layer_add_child(layer:Map_Layer_Base) :void
      {
         var i:int;
         var other:Map_Layer_Base;
         var other_z:Number;
         var layer_z:Number;

         layer_z = (layer is Map_Layer) ? layer.zplus : int(layer.zplus);

         // Skip layers that should be under this one, i.e. those with smaller
         // zplus values.
         m4_ASSERT((layer is Map_Layer_Passive) || (layer is Map_Layer));
         for (i = 0; i < this.numChildren; i++) {
            other = (this.getChildAt(i) as Map_Layer_Base);
            // EXPLAIN: new to route manip: Why would other be null?
            if (other !== null) {
               m4_ASSERT((other is Map_Layer) || (other is Map_Layer_Passive));
               other_z = (other is Map_Layer) ? other.zplus : int(other.zplus);
               if (layer_z <= other_z) {
                  m4_DEBUG2('layer_add_child: layer_z:', layer_z,
                            '/ other_z:', other_z);
                  break;
               }
            }
            // else, non-Map_Layer sprite, like this.vertices and sel_resolver.
         }

         m4_DEBUG2('layer_add_child layer:', layer,
                   '/ i:', i, '/ numChildren:', this.numChildren);
         this.addChildAt(layer, i);
      }

      // Ensure that appropriate layers are available for Geofeature gf.
      public function layers_add_maybe(gf:Geofeature) :void
      {
         m4_DEBUG('layers_add_maybe: gf:', gf)

         var l:Map_Layer_Base;

         if (!(gf.zplus in this.layers)) {

            m4_DEBUG('layers_add_maybe: new Map_Layer: gf.zplus:', gf.zplus)

            // Add one layer to contain interactive objects.
            l = new Map_Layer(this, gf.zplus);
            this.layers[gf.zplus] = l;
            this.layer_add_child(l);

            // Add another layer to hold inert, static objects.
            l = new Map_Layer_Passive(gf.zplus);
            m4_ASSERT(!(gf.zplus in this.shadows));
            this.shadows[gf.zplus] = l;
            this.layer_add_child(l);
         }
      }

      // The layer objects ordered by decreasing 'size'. Allow me to note here
      // that ActionScript's collections are absurdly bad. [rp]
      public function get layers_ordered() :Array
      {
         var a:Array = new Array();
         var k:String; // keys of dictionaries are Strings, like it or not
         var i:int;
         var tstart:int = G.now();
         // FIXME: Should we cache the array we create?
         for (k in this.layers) {
            a.push(k);
         }
         a.sort(Array.DESCENDING | Array.NUMERIC);
         for (i = 0; i < a.length; i++) {
            a[i] = this.layers[Number(a[i])];
         }
         m4_DEBUG_TIME('Map_Canvas.layers_ordered');
         return a;
      }

      // VOODOO ALERT: This method is overridden because the default
      // implementation doesn't properly measure our size (it stays zero). The
      // parent container won't do any clipping if it doesn't think that any
      // is necessary, so we reimplement this method to bind our size
      // permanently to that of our parent (which is always equal). This
      // convinces Flash that we require clipping (which we do). We do this
      // hack because it is harder, and not necessary in this context, to
      // determine our 'true' dimensions. Many thanks to Ely Greenfield for
      // the tip [rp].
      // Formerly: http://www.quietlyscheming.com
      //             /blog/2006/06/28/new-flex-component-randomwalk
      override protected function measure() :void
      {
         // 2013.05.22: [lb] had been ignoring and finally looked into a
         // problem with tiles and items not loading when you go fullscreen,
         // for the right-hand side and bottom-butt part of the viewport, past
         // something like 1000x1000 pixels. I originally tried setting
         // measuredHeight and 'tother to G.app's width and height rather than
         // this.parent's -- which works, but when you zoom in and out, the
         // center keeps changing (because of all the x,y component-to-map
         // translations, i.e., xform_x_map2cv et al).
         // 2013.05.24: See: Map_Canvas_Viewport.view_rect_resize. The problem
         // was it was using its this.parent -- the new G.app.map_canvas_print
         // wrapper for the print-to-pdf feature -- and not G.app.map_canvas.
         this.measuredHeight = this.parent.height;
         this.measuredWidth = this.parent.width;
      }

      //
      public function startup() :void
      {
         // no-op
      }

   }
}


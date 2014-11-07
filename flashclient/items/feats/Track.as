/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.feats {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import mx.core.IToolTip;
   import mx.managers.ToolTipManager;
   import mx.utils.ObjectUtil;
   import mx.utils.StringUtil;

   import grax.Aggregator_Base;
   import items.Geofeature;
   import items.Item_Versioned;
   import items.Record_Base;
   import items.utils.Geofeature_Layer;
   import items.utils.Item_Type;
   import utils.geom.Dual_Rect;
   import utils.geom.MOBRable_DR;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Map_Label;
   import utils.rev_spec.*;
   import views.base.Map_Layer;
   import views.base.Paint;
   import views.panel_routes.Panel_Item_Track;

   public class Track extends Geofeature {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Track');

      // *** Mandatory attributes

      public static const class_item_type:String = 'track';
      public static const class_gwis_abbrev:String = 'tr';
      public static const class_item_type_id:int = Item_Type.TRACK;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Track;

      // SYNC_ME: Search geofeature_layer table.
      public static const geofeature_layer_types:Array = [
         Geofeature_Layer.TRACK_DEFAULT,
         ];

      // *** Instance variables
      public var owner:String;
      public var date:String;
      public var duration:String;
      public var start_timestamp:String;
      public var end_timestamp:String;
      public var length:Number;
      public var deleted_:Boolean;

      public var trpoints_:Array;
      public var labels:Array;

      protected var filter_show_:Boolean;

      // Landmark experiment prompts
      public var prompts:Array = new Array();

      // *** Constructor

      public function Track(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         this.geofeature_layer_id = Geofeature_Layer.TRACK_DEFAULT;
         // EXPLAIN: MAGIC_NUMBER: 170 is where in the layering?
         //          We really need an enum class for all the z-levels...
         this.z_level = 170; // SYNC_ME: pyserver/item/feat/track.py
                             //          track.Geofeature_Layer.Z_DEFAULT
         this.labels = new Array();
         super(xml, rev);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Track = (to_other as Track);
         super.clone_once(other);

         other.owner = this.owner;
         other.length = this.length;
         other.duration = this.duration;
         other.date = this.date;

         if ((this.trpoints !== null)
             && (this.trpoints.length > 0)) {
            other.trpoints = Collection.array_copy(this.trpoints);
         }
         other.filter_show_ = this.filter_show_;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Track = (to_other as Track);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         m4_DEBUG('gml_consume: gml?:', (gml !== null));
         super.gml_consume(gml);
         if (gml !== null) {
            this.owner = gml.@crby;
            this.name_ = gml.@name;
            this.length = gml.@length;
            this.start_timestamp = gml.@started;
            this.end_timestamp = gml.@created;
            this.geofeature_layer_id = Geofeature_Layer.TRACK_DEFAULT;
            this.z_level = 170; // EXPLAIN: See above: MAGIC_NUMBER.

            this.duration = '' // FIXME

            if ('tpoint' in gml) {
               var trpt:Track_Point;
               this.trpoints = new Array();

               this.compute_xys(gml.tpoint, this.trpoints, this.xs, this.ys);

               m4_DEBUG('gml_consume: num trpoints:', this.trpoints.length);
               if (this.trpoints.length == 0) {
                  m4_WARNING('gml_consume: no trpoints:', gml.track_point);
               }
            }
         }
      }

      // ***

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Geofeature.all;
      }

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         if (i == -1) {
            try {
               i = (G.map.layers[this.zplus] as Map_Layer).getChildIndex(
                                                             this.sprite);
            }
            catch (e:TypeError) {
               // No-op
            }
         }

         var label:Map_Label;
         for each (label in this.labels) {
            if (label.parent === G.map.feat_labels) {
               G.map.feat_labels.removeChild(label);
            }
            else {
               m4_DEBUG('item_cleanup: EXPLAIN: Why label missing?:', label);
               m4_DEBUG(' .. parent:', label.parent);
            }
         }
         this.sprite.removeEventListener(MouseEvent.MOUSE_OVER,
                                         this.on_mouse_over);
         this.sprite.removeEventListener(MouseEvent.MOUSE_OUT,
                                        this.on_mouse_out);

         super.item_cleanup(i);
      }

      //
      override public function init_item(item_agg:Aggregator_Base,
                                         soft_add:Boolean=false)
         :Item_Versioned
      {
         var updated_item:Item_Versioned = super.init_item(item_agg, soft_add);

         if (updated_item === null) {
            if (this.master_item === null) {
               this.sprite.addEventListener(MouseEvent.MOUSE_OVER,
                              this.on_mouse_over, false, 0, true);
               this.sprite.addEventListener(MouseEvent.MOUSE_OUT,
                              this.on_mouse_out, false, 0, true);
            }
         }
         // else, we cloned to an existing item, so don't bother with sprites.

         return updated_item;
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_TALKY('init_add: item_agg:', item_agg);
         super.init_add(item_agg, soft_add);
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         m4_DEBUG('init_update: this:', this);
         m4_VERBOSE('Updating Track:', this);
         var track:Track = Geofeature.all[this.stack_id];
         if (track !== null) {
            m4_VERBOSE(' >> existing:', existing);
            m4_VERBOSE(' >> track:', track);
            m4_ASSERT((existing === null) || (existing === track));
            if ((!track.is_hydrated) || (this.is_hydrated)) {
               this.clone_item(track);
            }
            else {
               m4_DEBUG('init_update: not updating: tr:', existing);
            }
         }
         else {
            m4_WARNING('Track not found: stack_id:', this.stack_id);
         }
         return track;
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         m4_TALKY('is_item_loaded: item_agg:', item_agg);
         return super.is_item_loaded(item_agg);
      }

      // ***

      //
      public function compute_xys(xml:XMLList,
                                  trpoints:Array,
                                  xs:Array,
                                  ys:Array)
         :void
      {
         var i:int;
         var point_xml:XML;
         var point:Track_Point;

         var point_xs:Array;
         var point_ys:Array;

         for each (point_xml in xml) {
            point = new Track_Point(point_xml);
            trpoints.push(point);
            point_xs = new Array();
            point_ys = new Array();
            xs.push(point_xml.@x);
            ys.push(point_xml.@y);
         }
      }

      //
      override public function draw(is_drawable:Object=null) :void
      {
         var gr:Graphics = this.sprite.graphics;
         var point:Track_Point;
         var sx:Number;
         var sy:Number;
         var ex:Number;
         var ey:Number;
         var lbs:Map_Label;
         var lbe:Map_Label;
         var i:int = 0;
         var p_x:Array;
         var p_y:Array;
         var prompt:Object;

         super.draw();

         gr.clear();

         // remove old start/end map labels
         for each (label in this.labels) {
            if (label.parent === G.map.feat_labels) {
               G.map.feat_labels.removeChild(label);
            }
         }
         this.labels = new Array();

         if ((this.trpoints !== null) && this.is_drawable && this.visible) {

            Paint.line_draw(gr, this.xs, this.ys,
                            this.draw_width, 0x000000);
            Paint.line_draw(gr, this.xs, this.ys,
                            this.draw_width - 2, 0xff009900);

            gr.moveTo(sx, sy);
            sx = G.map.xform_x_map2cv(this.xs[0]);
	         sy = G.map.xform_y_map2cv(this.ys[0]);
	         ex = G.map.xform_x_map2cv(this.xs[this.xs.length-1]);
	         ey = G.map.xform_y_map2cv(this.ys[this.ys.length-1]);
	         var s_color:int = 0x00bb00;
	         var e_color:int = 0xff0000;

            this.draw_circle(s_color, sx, sy, 4);
            this.draw_circle(e_color, ex, ey, 4);

            var lbl:Map_Label;
            lbl = new Map_Label('Start', 12, 0, sx - 2, sy - 0, this);
            this.labels.push(lbl);
            G.map.feat_labels.addChild(lbl);
            lbl = new Map_Label('End', 12, 0, ex - 2, ey - 0, this);
            this.labels.push(lbl);
            G.map.feat_labels.addChild(lbl);

            for each (prompt in this.prompts) {
               if (prompt.selected) {
                  gr.beginFill(0xFF0000, 0.50);
               }
               else {
                  gr.beginFill(0x666666, 0.50);
               }
               gr.lineStyle(2, 0x000000);
               gr.drawCircle(G.map.xform_x_map2cv(prompt.coords[0]),
                             G.map.xform_y_map2cv(prompt.coords[1]),
                             50 * G.map.scale);
               gr.endFill();
            }
         }
      }

      //
      protected function draw_circle(color:int, x:int, y:int, radius:int) :void
      {
         var gr:Graphics = this.sprite.graphics;
         gr.beginFill(color);
         gr.lineStyle(2, 0x000000);
         gr.drawCircle(x, y, radius);
         gr.endFill();
      }

      // ***

      //
      override public function get actionable_at_raster() :Boolean
      {
         return true;
      }

      //
      public function get counterpart() :Track
      {
         return (this.counterpart_untyped as Track);
      }

      //
      override public function get counterpart_gf() :Geofeature
      {
         return this.counterpart;
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         return false;
      }

      //
      [Bindable] public function get filter_show() :Boolean
      {
         var fs:Boolean = ((!this.rev_is_working)
                           || (this.filter_show_));
         return fs;
      }

      //
      public function set filter_show(fs:Boolean) :void
      {
         if (this.filter_show_ != fs) {
            this.filter_show_ = fs;
            if (this.visible != this.is_drawable) {
               this.draw();
               this.visible = this.is_drawable;
            }

            if (!this.visible) {
               this.selected = false;
            }
        }
      }

      //
      override public function get is_clickable() :Boolean
      {
         return false;
      }

      //
      override public function get is_drawable() :Boolean
      {
         return true;
      }

      //
      public function get is_hydrated() :Boolean
      {
         return (this.trpoints !== null);
      }

      //
      public function set is_hydrated(ignored:Boolean) :void
      {
         m4_ASSURT(false);
      }

      // BUG nnnn: Makes tracks revisionless. Uncomment this:
      /*
      //
      override public function get is_revisionless() :Boolean
      {
         return true;
      }
      */

      //
      public function get trpoints() :Array
      {
         return this.trpoints_;
      }

      //
      public function set trpoints(trpoints:Array) :void
      {
         this.trpoints_ = trpoints;
         // Tell interested parties of our success.
         // 2013.04.30: This isn't the most robust solution, but it's better
         //             than what was coded, which was a tight loop in
         //             Route_Editor_UI waiting for this to happen (using a
         //             bunch of callLaters).
         // 2014.04.25: EXPLAIN: Why not this.dispatchEvent?
         G.item_mgr.dispatchEvent(new Event('trackPointsLoaded'));
      }

      //
      override public function get use_ornament_selection() :Boolean
      {
         return false;
      }

      //
      override public function set visible(v:Boolean) :void
      {
         super.visible = v;

         if (!v) {
            var label:Map_Label;
            for each (label in this.labels) {
               if (label.parent === G.map.feat_labels) {
                  G.map.feat_labels.removeChild(label);
               }
               else {
                  m4_DEBUG('visible: EXPLAIN: Why is label missing?:', label);
                  m4_DEBUG(' .. parent:', label.parent);
               }
            }
            this.labels = new Array();
         }
      }

      // ***

   }
}

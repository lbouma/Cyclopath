/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: Statewide UI: Is this a Diff class?

package items.feats {

   import flash.display.Sprite;
   import flash.display.Graphics;
   import flash.utils.getQualifiedClassName;

   import grax.Aggregator_Base;
   import items.Geofeature;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.geom.Dual_Rect;
   import utils.geom.Geometry;
   import utils.geom.MOBRable_DR;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.base.Map_Layer;
   import views.map_widgets.Shadow_Sprite;

   // FIXME: Add Geosummary to Item types: in client, server, and sql

   public class Geosummary extends Geofeature {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Geosummary');

      // *** Mandatory attributes

      public static const class_item_type:String = 'geosummary';
      public static const class_gwis_abbrev:String = 'gsum';
      //public static const class_item_type_id:int = Item_Type.GEOSUMMARY;

      // The Class of the details panel used to show info about this item.
      // Which doesn't exist for Geosummary.
      //public static const dpanel_class_static:Class = Panel_Item_Geosummary;

      // EXPLAIN: Magic numbers
      public static const Z_GEOSUMMARY:int = 160;

      // *** Instance variables

      public var color:int;
      public var rid:int;

      // Bounding box
      protected var min_x:int;
      protected var min_y:int;
      protected var max_x:int;
      protected var max_y:int;

      // Geosummary
      protected var gs_xs:Array;
      protected var gs_ys:Array;

      // XML
      protected var _xml:XML;

      // *** Constructor

      public function Geosummary(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         // EXPLAIN: 2014.02.28: Why is the compiler only now complaining? The
         // last edit on this file 2013.08.08, and the parent class,
         // Geofeature, doesn't have a third ctor variable. What the Hoth?
         // I also checked Geofeature's history and its ctor hasn't changed
         // recently.
         //  Weird...: super(xml, rev, false);
         super(xml, rev);

         this._xml = xml;

         this.shadow = new Shadow_Sprite(this);
         this.shadow.mouseEnabled = false;

         this.color = Conf.change_color;

         // NOTE: Skipping this.geofeature_layer_id
         this.z_level = Geosummary.Z_GEOSUMMARY;
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Geosummary = (to_other as Geosummary);
         super.clone_once(other);
         m4_ASSERT(false); // Not implemented. Maybe not supported, too.
         other.rid = this.rid;
         other.name_ = this.name_;
         other.min_x = this.min_x;
         other.min_y = this.min_y;
         other.max_x = this.max_x;
         other.max_y = this.max_y;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Geosummary = (to_other as Geosummary);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         var bbxs:Array = new Array();
         var bbys:Array = new Array();
         super.gml_consume(gml);
         if (gml !== null) {
            // The gml is from group_revision.py. This fcn. is called when we
            // load the recent changes list. At this time, we only get a vague
            // bbox of the change area. Later, if the user clicks a revision in
            // the list, we'll lazy-load the geosummary (see our fcn parse_gs).
            // NOTE: The group_revision objects in flashclient are kepy as an
            //       XML collection in the recent changes panel. We don't make
            //       Group_Revision objects from them (that class is currently
            //       not used in the client).
            this.rid = gml.@revision_id;
            this.name_ = (this.rid ? this.rid : '?rid?')
                         + ' (' + gml.@username + ')';

            Geometry.coords_string_to_xys(gml.@bbox, bbxs, bbys);
            if ((bbxs.length > 0) && (bbys.length > 0)) {
               this.min_x = bbxs[0];
               this.min_y = bbys[0];
               this.max_x = bbxs[1];
               this.max_y = bbys[1];
            }
            else {
               m4_WARNING('gml_consume: geomsumm: no geom:', this.toString());
            }
         }
         else {
            this.name_ = 'Invalid Geosummary';
         }
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         m4_DEBUG('init_add:', this);
         m4_ASSERT_SOFT(!soft_add);
         super.init_add(item_agg, soft_add);
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
            catch (e:ArgumentError) {
               // Error #2025: The supplied DisplayObject must be a child of
               //              the caller.
               // No-op
            }
            catch (e:TypeError) {
               // No-op
            }
         }

         super.item_cleanup(i, skip_delete);

         // Note that Geosummaries are part of Geofeature.all, so
         // Geofeature.cleanup_all is known to call us w/ skip_delete.
         if (!skip_delete) {
            // CcpV1: G.map.shadows[this.zplus].removeChildAt(i);
            if ((this.shadow) && (G.map.shadows[this.zplus] != undefined)) {
               try {
                  G.map.shadows[this.zplus].removeChild(this.shadow);
               }
               catch (e:ArgumentError) {
                  // No-op
               }
            }
         }
      }

      // Parse geosummary from xml (not done on instantiation)
      public function parse_gs(gxml:XML) :void
      {
         var o:Object;
         var xml:XML;
         var i:int = 0;
         var xs:Array;
         var ys:Array;

         this._xml = gxml;

         this.gs_xs = new Array();
         this.gs_ys = new Array();
         for each (o in gxml.geosummary.polygon) {
            xml = (o as XML);
            xs = new Array();
            ys = new Array();
            Geometry.coords_string_to_xys(xml.text(), xs, ys);
            if ((xs.length > 0) && (ys.length > 0)) {
               // close ring
               xs.push(xs[0]);
               ys.push(ys[0]);
            }
            else {
               m4_WARNING('parse_gs: geosumm: no geom:', this.toString());
            }
            this.gs_xs.push(xs);
            this.gs_ys.push(ys);
         }
      }

      //*** Getters and setters

      //
      public function get counterpart() :Geosummary
      {
         return (this.counterpart_untyped as Geosummary);
      }

      //
      override public function get counterpart_gf() :Geofeature
      {
         return this.counterpart;
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
      }

      //
      override public function get discardable() :Boolean
      {
         return G.tabs.changes_panel.allow_discard;
      }

      //
      override public function get draw_width() :Number
      {
         // MAYBE: Put this in, e.g., skin_bikeways?
         return 10;
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         return false;
      }

      // True after geosummary is loaded
      public function get has_gs() :Boolean
      {
         return (this.gs_xs !== null);
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
      override public function get is_labelable() :Boolean
      {
         // FIXME: enable labeling?
         return false;
      }

      // 3 for a triangle + 1 to close the polygon
      override public function get min_vertices() :int
      {
         return 4;
      }

      // NOTE: Uses fetched bbox dimensions rather than calculating from
      //       geosummary.
      override public function get mobr_dr() :Dual_Rect
      {
         var dr:Dual_Rect = new Dual_Rect();

         // Add buffer to make lookat show more of geosummary geometry
         var buffer:int = 100;

         // FIXME: order here is important.
         dr.map_min_x = this.min_x - buffer;  // left
         dr.map_max_y = this.max_y + buffer;  // top
         dr.map_max_x = this.max_x + buffer;  // right
         dr.map_min_y = this.min_y - buffer;  // bottom

         return dr;
      }

      //
      // FIXME: This fcn. is same as super's.
      override public function get persistent_vertex_selecting() :Boolean
      {
         return false;
      }

      //
      public function get xml() :XML
      {
         return this._xml;
      }

      // *** Draw-related instance methods

      //
      override public function draw(is_drawable:Object=null) :void
      {
         var grs:Graphics = this.shadow.graphics;

         super.draw();

         grs.clear();

         if (this.has_gs) {
            this.draw_gs(grs);
         }
         else {
            this.draw_bbox(grs);
         }
      }

      //
      private function draw_bbox(grs:Graphics) :void
      {
         var min_x:Number;
         var min_y:Number;
         var max_x:Number;
         var max_y:Number;

         grs.lineStyle(4, this.color);
         grs.beginFill(0x000000, .1);

         min_x = G.map.xform_x_map2cv(this.min_x);
         min_y = G.map.xform_y_map2cv(this.min_y);
         max_x = G.map.xform_x_map2cv(this.max_x);
         max_y = G.map.xform_y_map2cv(this.max_y);

         grs.moveTo(min_x, min_y);
         grs.lineTo(min_x, max_y);
         grs.lineTo(max_x, max_y);
         grs.lineTo(max_x, min_y);
         grs.lineTo(min_x, min_y);

         grs.endFill();
      }

      //
      private function draw_gs(grs:Graphics) :void
      {
         var i:int;
         var j:int;
         var x:Number;
         var y:Number;

         m4_ASSERT(this.has_gs);

         for (i = 0; i < gs_xs.length; i++) {

            grs.lineStyle(4, this.color);
            grs.beginFill(0x000000, .1);

            x = G.map.xform_x_map2cv(this.gs_xs[i][0]);
            y = G.map.xform_y_map2cv(this.gs_ys[i][0]);
            grs.moveTo(x, y);
            for (j = 1; j < gs_xs[i].length; j++) {
               x = G.map.xform_x_map2cv(this.gs_xs[i][j]);
               y = G.map.xform_y_map2cv(this.gs_ys[i][j]);
               grs.lineTo(x, y);
            }

            grs.endFill();
         }
      }

      //
      override protected function label_parms_compute() :void
      {
         this.label_x = G.map.xform_x_map2cv((this.min_x + this.max_x) / 2);
         this.label_y = G.map.xform_y_map2cv(this.min_y) + 10;
         this.label_rotation = 0;
      }

      // *** Developer methods

      //
      override public function toString() :String
      {
         // Geosummaries do not have normal item attributes.
         m4_ASSERT(!this.system_id);
         m4_ASSERT(!this.branch_id);
         m4_ASSERT(!this.stack_id);
         m4_ASSERT(!this.version);
         if ((this.item_stack !== null)
             && (!this.item_stack.informationless)) {
            m4_DEBUG('geosummary:', this.item_stack.toString());
         }
         m4_ASSERT_SOFT((this.item_stack === null)
                        || (this.item_stack.informationless));
         var rev_detail:String =
            ((this.rev !== null)
               ? ('@' + this.rev.short_name)
               : ('@?'));
         return (getQualifiedClassName(this)
                 + ' / name: "' + this.name_
                 + '" / rev: ' + rev_detail
                 );
      }

   }
}


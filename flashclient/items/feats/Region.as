/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.feats {

   import flash.display.Sprite;
   import flash.display.DisplayObject;
   import flash.display.Graphics;
   import flash.events.MouseEvent;
   import flash.geom.Point;
   import flash.utils.Dictionary;
   import mx.managers.ToolTipManager;
   import mx.core.IToolTip;

   import grax.Aggregator_Base;
   import items.Geofeature;
   import items.Item_Versioned;
   import items.Link_Value;
   import items.Record_Base;
   import items.attcs.Tag;
   import items.utils.Geofeature_Layer;
   import items.utils.Item_Type;
   import items.verts.Region_Vertex;
   import items.verts.Vertex;
   import utils.geom.Dual_Rect;
   import utils.geom.Geometry;
   import utils.geom.MOBRable_DR;
   import utils.misc.Collection;
   import utils.misc.Draggable;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Map_Label;
   import utils.rev_spec.*;
   import views.base.App_Action;
   import views.base.Map_Layer;
   import views.base.Paint;
   import views.map_widgets.Shadow_Sprite;
   import views.panel_items.Panel_Item_Region;
   import views.panel_util.Pointing_Widget;

   public class Region extends Geofeature implements Draggable, MOBRable_DR {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Region');

      // *** Mandatory attributes

      public static const class_item_type:String = 'region';
      public static const class_gwis_abbrev:String = 'rg';
      public static const class_item_type_id:int = Item_Type.REGION;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Region;

      // SYNC_ME: Search geofeature_layer table.
      public static const geofeature_layer_types:Array = [
         Geofeature_Layer.REGION_DEFAULT,
         ];

      // *** Other static variables

      // The ubiquitous item lookup.
      public static var all:Dictionary = new Dictionary();

      protected static var tooltip:IToolTip;

      // *** Instance variables

      public var labels:Array;

      public var crossbars:Sprite;

      // *** Constructor

      public function Region(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);

         // FIXME HACK HACK HACK - See bug 1375
         // EXPLAIN: Magic Number
         if (this.z_level < 149) {
            m4_VERBOSE2('this.z_level (is < 149; setting to 149):',
                        this.z_level, '/ stack_id:', this.stack_id);
            this.z_level = 149; // SYNC_ME: pyserver/item/feat/region.py
                                //          region.Geofeature_Layer.Z_DEFAULT*
         }
         else {
            m4_VERBOSE2('this.z_level (is >=149):', this.z_level,
                        '/ stack_id:', this.stack_id);
         }

         this.geofeature_layer_id = Geofeature_Layer.REGION_DEFAULT;

         this.label_rotation = NaN;
         this.labels = new Array();

         this.shadow = new Shadow_Sprite(this);
         this.shadow.mouseEnabled = false;
      }

      // *** Public Static methods

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var region:Region in Region.all) {
               region.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Region.all = new Dictionary();
      }

      // Put up a pointing widget (pointing to the given object) saying that
      // we turned on the regions layer and how to turn it off.
      public static function layer_turned_on_warn() :void
      {
         var target:DisplayObject = G.app.main_toolbar.map_layers;
         Pointing_Widget.show_pointer(
            'Regions layer turned on',
            new String(
               'Cyclopath has automatically turned on the region layer. ')
            .concat('To turn it off, uncheck "Regions" in Map Settings.'),
            target,
            300,     // max_width
            null,    // button_labels
            null,    // button_callbacks
            false,   // use_link_buttons
            10);     // timeout
      }

      // *** Shared instance methods

      //
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         //m4_DEBUG('item_cleanup:', this);
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

         this.label_reset();

         // CcpV1: G.map.shadows[this.zplus].removeChildAt(i);
         if ((this.shadow) && (G.map.shadows[this.zplus] != undefined)) {
            try {
               G.map.shadows[this.zplus].removeChild(this.shadow);
            }
            catch (e:ArgumentError) {
               // No-op
            }
         }

         // Remove self
         if (!skip_delete) {
            delete Region.all[this.stack_id];
         }
      }

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Region = (to_other as Region);
         super.clone_once(other);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Region = (to_other as Region);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            Geometry.coords_string_to_xys(gml.external.text(),
                                          this.xs, this.ys);
            if ((this.xs.length > 0) && (this.ys.length > 0)) {
               // close rings
               this.xs.push(this.xs[0]);
               this.ys.push(this.ys[0]);
            }
            else {
               m4_WARNING('gml_consume: region: no geom:', this.toString());
            }
         }
         // else, called via init_GetDefinitionByName.
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         gml.setName(Region.class_item_type); // 'region'
         return gml;
      }

      // *** Item Init/Update fcns.

      //
      override public function init_item(item_agg:Aggregator_Base,
                                         soft_add:Boolean=false)
         :Item_Versioned
      {
         var updated_item:Item_Versioned = super.init_item(item_agg, soft_add);
         return updated_item;
      }

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         /*
         if (d) {
            delete Region.all[this.stack_id];
         }
         else {
            if (this !== Region.all[this.stack_id]) {
               if (this.stack_id in Region.all) {
                  m4_WARNING2('set deleted: overwrite:',
                              Region.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Region.all[this.stack_id] = this;
            }
         }
         */
      }

      //
      override protected function init_add(item_agg:Aggregator_Base,
                                           soft_add:Boolean=false) :void
      {
         // Call the parent
         super.init_add(item_agg, soft_add);
         // Add to our own lookup
         if (!soft_add) {
            if (this !== Region.all[this.stack_id]) {
               if (this.stack_id in Region.all) {
                  m4_WARNING2('init_add: overwrite:',
                              Region.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Region.all[this.stack_id] = this;
            }
         }
      }

      //
      override protected function init_update(
         existing:Item_Versioned,
         item_agg:Aggregator_Base) :Item_Versioned
      {
         return super.init_update(existing, item_agg);
      }

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         this.update_item_all_lookup(Region, commit_info);
         super.update_item_committed(commit_info);
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         return (super.is_item_loaded(item_agg)
                 || (this.stack_id in Region.all));
      }

      // *** Draw-related instance methods

      //
      public function crosshairs_draw(gr:Graphics,
                                      highlight:Boolean,
                                      selected:Boolean) :void
      {
         var lbl:Map_Label;
         var lbl_c_x:Number;
         var lbl_c_y:Number;
         var i:int;
         var vert_1:Point = null;
         var vert_2:Point = null;
         var horz_1:Point = null;
         var horz_2:Point = null;
         var p:Point;
         var start:Point;
         var end:Point;
         var color:Number = this.draw_color;
         var alpha:Number = 0.5;
         var lbl_c:Point;
         var dr:Dual_Rect = this.mobr_dr;

         if (highlight) {
            if (selected) {
               color = Conf.selection_color;
               // alpha set above
            }
            else {
               color = G.map
                  .highlight_manager.get_layer_color(Conf.mouse_highlight);
               alpha = Conf.highlight_alpha;
            }
         }

         m4_VERBOSE('crosshairs_draw: calling label_center');
         lbl_c = this.label_center;

         lbl_c_x = dr.map_center_x;
         lbl_c_y = dr.map_center_y;

         if (lbl_c !== null) {
            for (i = 0; i < this.xs.length - 1; i++) {
               start = new Point(this.xs[i], this.ys[i]);
               end = new Point(this.xs[i + 1], this.ys[i + 1]);

               p = Geometry.intersection_line_seg(
                                 start, end,
                                 new Point(lbl_c_x, lbl_c_y - 10),
                                 new Point(lbl_c_x, lbl_c_y + 10));
               if (p !== null) {
                  if (vert_1 === null) {
                     vert_1 = new Point(p.x, p.y);
                  }
                  else {
                     vert_2 = new Point(p.x, p.y);
                  }
               }

               p = Geometry.intersection_line_seg(
                                 start, end,
                                 new Point(lbl_c_x - 10, lbl_c_y),
                                 new Point(lbl_c_x + 10, lbl_c_y));
               if (p !== null) {
                  if (horz_1 === null) {
                     horz_1 = new Point(p.x, p.y);
                  }
                  else {
                     horz_2 = new Point(p.x, p.y);
                  }
               }
            }

            // FIXME: 'if' put in here to prevent crashing on concave
            // polygons
            if (vert_1 !== null && vert_2 !== null
                && horz_1 !== null && horz_2 !== null) {
               // Making sure vert_1 is above vert_2 and horz_1 is to left of
               // horz_2
               p = new Point();

                if (vert_1.y < vert_2.y) {
                  p.x = vert_1.x;
                  p.y = vert_1.y;

                  vert_1.x = vert_2.x;
                  vert_1.y = vert_2.y;

                  vert_2.x = p.x;
                  vert_2.y = p.y;
               }

               if (horz_1.x > horz_2.x) {
                  p.x = horz_1.x;
                  p.y = horz_1.y;

                  horz_1.x = horz_2.x;
                  horz_1.y = horz_2.y;

                  horz_2.x = p.x;
                  horz_2.y = p.y;
               }

               vert_1.x = G.map.xform_x_map2cv(vert_1.x);
               vert_1.y = G.map.xform_y_map2cv(vert_1.y);

               vert_2.x = G.map.xform_x_map2cv(vert_2.x);
               vert_2.y = G.map.xform_y_map2cv(vert_2.y);

               horz_1.x = G.map.xform_x_map2cv(horz_1.x);
               horz_1.y = G.map.xform_y_map2cv(horz_1.y);

               horz_2.x = G.map.xform_x_map2cv(horz_2.x);
               horz_2.y = G.map.xform_y_map2cv(horz_2.y);

               lbl_c_x = G.map.xform_x_map2cv(lbl_c_x);
               lbl_c_y = G.map.xform_y_map2cv(lbl_c_y);

               gr.lineStyle((this.draw_width > 5 ? 2 : 1),
                            color, this.draw_alpha);

               // Crosshairs
               gr.moveTo(vert_1.x, vert_1.y);
               gr.lineTo(vert_2.x, vert_2.y);

               gr.moveTo(horz_1.x, horz_1.y);
               gr.lineTo(horz_2.x, horz_2.y);

               // Center box
               gr.lineStyle(0, color, alpha);
               gr.beginFill(color, alpha);

               lbl = new Map_Label(this.label_text,
                  this.draw_width + 10, 0, lbl_c.x, lbl_c.y, this);

               if (G.map.xform_xdelta_map2cv(dr.map_max_x - dr.map_min_x)
                     > lbl.width) {
                  gr.drawRect(lbl_c.x - lbl.width/2 + 2,
                              lbl_c.y - lbl.height/2,
                              lbl.width - 1, lbl.height - 1);
               }
               else {
                  gr.drawRect(lbl_c_x - 3, lbl_c_y - 3, 6, 6);
               }

               gr.endFill();
            }
         }
      }

      //
      override public function draw(is_drawable:Object=null) :void
      {
         //var gr:Graphics = this.graphics;
         var gr:Graphics = this.sprite.graphics;
         var grs:Graphics = this.shadow.graphics;
         var o:Object;
         //var tr:Tag_Region;
         var lv:Link_Value;
         var non_geo:Boolean = false;

         super.draw();

         // Clear the existing polygon, if any.
         gr.clear();

         //m4_DEBUG('draw: calling is_drawable');
         var drawable:Boolean;
         if (is_drawable !== null) {
            drawable = (is_drawable as Boolean);
         }
         else {
            drawable = this.is_drawable;
         }

         if (drawable) {

            Paint.line_draw(gr, this.xs, this.ys,
                            this.draw_width, this.draw_color, this.draw_alpha);
            Paint.line_draw(gr, this.xs, this.ys, 1, 0x000000, 1);

            // Ornaments
            if (this.selected) {
               this.orn_selection.draw();
            }
            if (this.highlighted) {
               G.map.highlight_manager.render_highlight(this);
            }

            grs.clear();

            if (this.rev_is_diffing) {
               // Border to highlight presence of nongeometric changes
               if (this.has_non_geo_changes()) {
                  Paint.line_draw(grs, this.xs, this.ys,
                                  (this.draw_width
                                   + 2 * this.comment_width
                                   + 2 * this.shadow_width),
                                  Conf.change_color);
               }
               Paint.line_draw(grs, this.xs, this.ys,
                               (this.draw_width
                                + 2 * this.shadow_width),
                               Conf.shadow_color);
            }

            // COUPLING: The item classes really shouldn't know about the
            // panels, even if this is a draw routine, but the settings panel
            // is pretty stable....
            else if ((G.tabs.settings.links_visible)
                     && (this.annotation_cnt || this.discussion_cnt)
                     && (!this.rev_is_diffing)) {
               // Highlight to indicate presense of annotations and/or posts
               Paint.line_draw(grs, this.xs, this.ys,
                               (this.draw_width
                                + 2 * this.comment_width
                                + 2 * this.shadow_width),
                               this.comment_color);
            }

            // Crosshairs, center square, invisible label background
            this.crosshairs_draw(gr, false, false);
         }
      }

      // Draw my labels. Note that if labels already exist, they will be
      // orphaned -- this method does not remove them from the label layer.
      override public function label_draw(halo_color:*=null) :void
      {
         var lbl:Map_Label;
         var lbl_x:Number;
         var lbl_y:Number;
         var lbl_c_x:Number;
         var lbl_c_y:Number;
         var lbl_rot:Number;
         var lblwidth:int;
         var i:int;
         var lbl_c:Point;
         var dr:Dual_Rect = this.mobr_dr;

         //m4_DEBUG('label_draw:', this, '/ xs.len:', this.xs.length);

         var tmp_label:Map_Label = new Map_Label(this.label_text,
            this.draw_width + 5, 0, 0, 0, this, halo_color);

         lblwidth = (tmp_label).width + 10;

         for (i = 0; i < this.xs.length - 1; i++) {
            if (lblwidth < G.distance_cv(this.xs[i], this.ys[i],
                                         this.xs[i + 1], this.ys[i + 1])) {
               lbl_x = G.map.xform_x_map2cv((this.xs[i] + this.xs[i + 1]) / 2);
               lbl_y = G.map.xform_y_map2cv((this.ys[i] + this.ys[i + 1]) / 2);

               // Compute rotation angle
               // Negated to convert CCW to CW rotation
               lbl_rot = -Math.atan2(this.ys[i] - this.ys[i + 1],
                                     this.xs[i] - this.xs[i + 1]);

               // Keep text upright
               if (lbl_rot < -Math.PI/2) {
                  lbl_rot += Math.PI;
               }
               if (lbl_rot > Math.PI/2) {
                  lbl_rot -= Math.PI;
               }

               lbl = new Map_Label(this.label_text,
                  this.draw_width + 5, lbl_rot, lbl_x, lbl_y, this);

               if (this.rev_is_diffing && this.is_vgroup_static) {
                  lbl.textColor = Conf.vgroup_static_label_color;
               }

               if (!G.map.feat_labels.child_collides(lbl)) {
                  this.labels.push(lbl);
               }
            }
         }

         m4_VERBOSE('label_draw: calling label_center');
         lbl_c = this.label_center;

         if (lbl_c !== null) {
            lbl = new Map_Label(this.label_text,
               this.draw_width + 10, 0, lbl_c.x, lbl_c.y, this);

            if (G.map.xform_xdelta_map2cv(dr.map_max_x - dr.map_min_x) >
                lbl.width) {
               if (this.rev_is_diffing && this.is_vgroup_static) {
                  lbl.textColor = Conf.vgroup_static_label_color;
               }
               this.labels.push(lbl);
            }
         }

         for (i = 0; i < this.labels.length; i++) {
            G.map.feat_labels.addChild(this.labels[i]);
         }
      }

      //
      override protected function label_parms_compute() :void
      {
         // No-op
      }

      // *** Double click detector mouse handlers

      //
      override public function on_mouse_down(ev:MouseEvent) :void
      {
         this.tooltip_display(false);
         super.on_mouse_down(ev);
      }

      // Skipping: on_mouse_up and on_mouse_doubleclick

      // *** Event handlers

      //
      override public function on_mouse_over(ev:MouseEvent) :void
      {
         super.on_mouse_over(ev);
         this.tooltip_display(true, ev);
      }

      //
      override public function on_mouse_out(ev:MouseEvent) :void
      {
         super.on_mouse_out(ev);
         this.tooltip_display(false);
      }

      // *** Getters and setters

      //
      override public function get actionable_at_raster() :Boolean
      {
         return true;
      }

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Region.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Region.all;
      }

/*/ Moved to Geofeature. FIXME: delete this block.
      //
      public function get comment_color() :int
      {
         if (this.rev_is_diffing) {
            return Conf.comment_color_diffing;
         }
         else {
            return Conf.comment_color;
         }
      }

/*/

      //
      public function get counterpart() :Region
      {
         return (this.counterpart_untyped as Region);
      }

      //
      override public function get counterpart_gf() :Geofeature {
         return this.counterpart;
      }

      //
      override public function get discardable() :Boolean
      {
         var discardable_:Boolean = super.discardable;
         m4_VERBOSE('get discardable:', discardable_);
         return discardable_;
      }

      //
      override public function get draw_color() :int
      {
// FIXME: route reactions
//         if (this.rev_is_diffing) {
// FIXME: What about G.map.rev_workcopy or rev_viewport?
//
         if (G.map.rmode == Conf.map_mode_historic) {
            m4_ASSERT(this.rev_is_diffing);
            return super.draw_color;
         }
         else if (G.map.rmode == Conf.map_mode_feedback) {
            return super.draw_color;
         }
         else {
            m4_ASSURT(G.map.rmode == Conf.map_mode_normal);
            if (G.item_mgr.region_of_the_day !== null
                && G.item_mgr.region_of_the_day.stack_id == this.stack_id) {
               return Conf.region_of_the_day_color;
            }
            else {
               return Conf.tile_skin.feat_pens[
                  String(Geofeature_Layer.REGION_DEFAULT)]['pen_color'];

            }
         }
      }

      //
      public function get draw_alpha() :Number
      {
         if (G.item_mgr.region_of_the_day !== null
             && G.item_mgr.region_of_the_day.stack_id == this.stack_id) {
            return 1;
         }
         else {
            return 0.5;
         }
      }

      //
      override public function get editable_at_current_zoom() :Boolean
      {
         return true;
      }

      // Return the coords of the center label if the center is inside the
      // polygon, and the polygon is of a mininum size.
      public function get label_center() :Point
      {
         var lbl_c_x:Number;
         var lbl_c_y:Number;
         var i:int;
         var result:Point = null;
         var dr:Dual_Rect = this.mobr_dr;

         lbl_c_x = dr.map_center_x;
         lbl_c_y = dr.map_center_y;

         if ((G.map.xform_xdelta_map2cv(dr.map_max_x - dr.map_min_x) > 30)
            && (G.map.xform_xdelta_map2cv(dr.map_max_y - dr.map_min_y) > 30)) {
            // Test for center to be inside the polygon.
            m4_VERBOSE('label_center: calling pt_in_poly');
            if (Geometry.pt_in_poly(this.xs, this.ys,
                                    new Point(lbl_c_x, lbl_c_y))) {
               lbl_c_x = G.map.xform_x_map2cv(lbl_c_x);
               lbl_c_y = G.map.xform_y_map2cv(lbl_c_y);
               result = new Point(lbl_c_x, lbl_c_y);
            }
         }

         return result;
      }

      // 3 for a triangle + 1 to close the polygon
      override public function get min_vertices() :int
      {
         return 4;
      }

      //
      override public function get persistent_vertex_selecting() :Boolean
      {
         return true;
      }

      //
      override public function set_selected(
         s:Boolean, nix:Boolean=false, solo:Boolean=false) :void
      {
         super.set_selected(s, nix, solo);
         // The regions layer is user-toggleable, but selecting a region turns
         // it on.
         if (s) {
            G.tabs.settings.regions_visible = true;
         }
      }

      //
      override public function get vertex_add_enabled() :Boolean
      {
         return true;
      }

      //
      override public function get vertex_editable() :Boolean
      {
         // 2013.05.07: Only show the thin blue line in view mode, and don't
         //             show geofeature vertices or allow them to be edited.
         //return true;
         return G.app.mode.is_allowed(App_Action.item_edit);
      }

      //
      override public function set visible(s:Boolean) :void
      {
         super.visible = s;
         this.labels.forEach(
            function (element:Map_Label, index:int, arr:Array) :void
            {
               element.visible = s;
            }
         );
         if (this.crossbars !== null) {
            this.crossbars.visible = s;
         }
      }

      // *** Other instance methods

      //
      public function drag(xdelta:Number, ydelta:Number) :void
      {
         // do nothing, this is a placeholder for dragging using
         // the region create tool (which handles updating the position).
      }

      // Return true if the given Region is currently hidden due to filter
      // settings, false otherwise.
      override public function hidden_by_filter() :Boolean
      {
         var rg_tags:Array;
         var t:Tag;

         //rg_tags = Tag_Region.all_tags(this);
         rg_tags = Link_Value.attachments_for_item(this, Tag);

         if (G.tabs.settings.regions_visible) {
            if (rg_tags.length == 0) {
               if (G.map.untagged.filter_show_tag) {
                  return false;
               }
            }
            else {
               for each (t in rg_tags) {
                  if (t.filter_show_tag) {
                     return false;
                  }
               }
            }
         }
         return true;
      }

      // Label myself if I need labeling, otherwise clear any leftover labels
      override public function label_maybe() :void
      {
// FIXME This takes a while!!
         //m4_DEBUG('label_maybe:', this);
         if (this.is_labelable) {
            if (this.labels.length == 0) {
               this.label_draw();
            }
         }
         else {
            while (this.labels.length > 0) {
               this.labels.pop();
            }
         }
      }

      // Reset labeling state.
      override public function label_reset() :void
      {
         while (this.labels.length > 0) {
            // Remove label from map, if it's there.
            try {
                G.map.feat_labels.removeChild(this.labels.pop());
            }
            catch (e:ArgumentError) {
               // nothing
            }
         }
         try {
            if (this.crossbars !== null) {
               G.map.feat_labels.removeChild(this.crossbars);
            }
         }
         catch (e:ArgumentError) {
            // nothing
         }
      }

      //
      protected function tooltip_display(on:Boolean, ev:MouseEvent = null)
         :void
      {
         if (on) {
            if (tooltip !== null) {
               ToolTipManager.destroyToolTip(tooltip);
            }
            if (this.is_labelable) {
               tooltip = ToolTipManager.createToolTip(this.name_,
                                                      ev.stageX, ev.stageY);
            }
         }
         else {
            if (tooltip !== null) {
               ToolTipManager.destroyToolTip(tooltip);
               tooltip = null;
            }
         }
      }

      //
      override public function vertex_create(index:int) :Vertex
      {
         return new Region_Vertex(index, this);
      }

      // Insert a new vertex at index j at the map coordinates (x,y).
      override public function vertex_insert_at(j:int, x:Number, y:Number)
         :void
      {
         var last:int = this.xs.length;

         if (j == 0 || j == last) {
            // If it is an end vertex, handle specially ..

            // Insert at first position.
            super.vertex_insert_at(0, x, y);

            // Complete the ring.
            this.xs[last] = this.xs[0];
            this.ys[last] = this.ys[0];

            // Reinitialize the last vertex.
            this.vertex_uninit(this.vertices[last]);
            this.vertex_init(last);

            this.draw_all();
         }
         else {
            // .. else handle regularly.
            super.vertex_insert_at(j, x, y);
         }
      }

      // Remove the vertex at index j (bubbling the remaining vertices down).
      override public function vertex_delete_at(j:int) :void
      {
         var last:int = this.xs.length - 1;

         if (j == 0 || j == last) {
            // If it is an end vertex, handle specially ..

            // Delete first vertex.
            super.vertex_delete_at(0);
            last--;

            // Complete the ring.
            this.xs[last] = this.xs[0];
            this.ys[last] = this.ys[0];

            // Reinitialize the last vertex.
            this.vertex_uninit(this.vertices[last]);
            this.vertex_init(last);
         }
         else {
            // .. else handle regularly.
            super.vertex_delete_at(j);
         }
      }

   }
}


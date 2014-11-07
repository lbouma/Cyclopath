/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.feats {

   import flash.display.Graphics;
   import flash.events.MouseEvent;
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
   import utils.geom.Geometry;
   //import utils.misc.Collection;
   import utils.misc.Draggable;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.rev_spec.*;
   import views.base.App_Action;
   import views.base.Map_Layer;
   import views.base.Paint;
   import views.map_widgets.Shadow_Sprite;
   import views.panel_items.Panel_Item_Waypoint;

   public class Waypoint extends Geofeature implements Draggable {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Waypoint');

      // *** Mandatory attributes

      public static const class_item_type:String = 'waypoint';
      public static const class_gwis_abbrev:String = 'pt';
      public static const class_item_type_id:int = Item_Type.WAYPOINT;

      // The Class of the details panel used to show info about this item
      public static const dpanel_class_static:Class = Panel_Item_Waypoint;

      // SYNC_ME: Search geofeature_layer table.
      public static const geofeature_layer_types:Array = [
         Geofeature_Layer.WAYPOINT_DEFAULT,
         ];

      // *** Other static variables

      // The ubiquitous item lookup.
      public static var all:Dictionary = new Dictionary();

      protected static var tooltip:IToolTip;

      // *** Constructor

      public function Waypoint(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
         this.shadow = new Shadow_Sprite(this);
         this.z_level = 140; // SYNC_ME: pyserver/item/feat/waypoint.py
                             //          waypoint.Geofeature_Layer.Z_DEFAULT
         this.label_rotation = Number.NaN;
         this.geofeature_layer_id = Geofeature_Layer.WAYPOINT_DEFAULT;
      }

      // *** Static methods

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var waypoint:Waypoint in Waypoint.all) {
               waypoint.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Waypoint.all = new Dictionary();
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Waypoint = (to_other as Waypoint);
         super.clone_once(other);
         // Skipping: tooltip
         // Geofeature does this: (in clone_update):
         //    other.xs = Collection.array_copy(this.xs);
         //    other.ys = Collection.array_copy(this.ys);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Waypoint = (to_other as Waypoint);
         super.clone_update(other, newbie);
      }


      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            Geometry.coords_string_to_xys(gml.text(), this.xs, this.ys);
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         gml.setName(Waypoint.class_item_type); // 'waypoint'
         return gml;
      }

      // ***

      //
      public function drag(xdelta:Number, ydelta:Number) :void
      {
         // Do nothing. This is a placeholder for dragging using the geopoint
         // create tool (which handles updating the position).
      }

      //
      override public function draw(is_drawable:Object=null) :void
      {
         var gr:Graphics = this.sprite.graphics;
         var grs:Graphics = this.shadow.graphics;
         var x:Number;
         var y:Number;
         var o:Object;
         var lv:Link_Value;
         var non_geo:Boolean = false;

         super.draw();

         m4_DEBUG2('draw: is_drawable:', is_drawable,
                   '/ this.is_drawable:', this.is_drawable);

         if (((is_drawable !== null) && (is_drawable as Boolean))
             || (this.is_drawable)) {

            x = this.x_cv;
            y = this.y_cv;

            // filled circle
            gr.clear();
            gr.beginFill(this.draw_color);
            gr.drawCircle(x, y, this.draw_width / 2);

            // ornaments
            if (this.selected) {
               this.orn_selection.draw();
            }
            if (this.highlighted)  {
               G.map.highlight_manager.render_highlight(this);
            }

            grs.clear();

            // Draw a ring to highlight presence of nongeometric changes (in
            // the case of a Diff rev) or of notes or posts attached.
            if (this.has_non_geo_changes()) {
               grs.drawCircle(x, y, (this.draw_width / 2 + this.shadow_width
                                     + this.comment_width));
            }
         // MAYBE: COUPLING: Statewide UI: This is coupled.
         //                  The item classes should not know about the view.
            else if ((G.tabs.settings.links_visible)
                     && (this.annotation_cnt || this.discussion_cnt)
                     && (!this.rev_is_diffing)) {
               grs.beginFill(this.comment_color);
               grs.drawCircle(x, y, (this.draw_width / 2 + this.shadow_width
                                     + this.comment_width));
            }

            // standard shadow
            grs.beginFill(Conf.shadow_color);
            grs.drawCircle(x, y, this.draw_width / 2 + this.shadow_width);

            // arrow from old version, if any
            if ((this.is_vgroup_new)
                && (this.counterpart !== null)
                && (this.digest_geo != this.counterpart.digest_geo)
                && (G.map.diff_show == Conf.hb_both)) {
               // The waypoint was moved. Draw an arrow from the old position
               // to the new position.
               Paint.arrow_draw(
                  grs, this.counterpart.x_cv, this.counterpart.y_cv, x, y,
                  0.75 * this.draw_width, Conf.vgroup_move_arrow_color, 1,
                  this.draw_width / 2);
            }
         }
      }

      // Return true if the given Waypoint is currently hidden due to filter
      // settings, false otherwise.
      override public function hidden_by_filter() :Boolean
      {
         var gp_tags:Array;
         var t:Tag;

         gp_tags = Link_Value.attachments_for_item(this, Tag)

         if (G.tabs.settings.points_visible) {
            if (gp_tags.length == 0) {
               if (G.map.untagged.filter_show_tag) {
                  return false;
               }
            }
            else {
               for each (t in gp_tags) {
                  if (t.filter_show_tag) {
                     return false;
                  }
               }
            }
         }
         return true;
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
               // ArgumentError: Error #2025:
               //  The supplied DisplayObject must be a child of the caller
               // No-op
            }
            catch (e:TypeError) {
               // No-op
            }
         }

         super.item_cleanup(i, skip_delete);

         // CcpV1: G.map.shadows[this.zplus].removeChildAt(i);
         if ((this.shadow) && (G.map.shadows[this.zplus] != undefined)) {
            try {
               G.map.shadows[this.zplus].removeChild(this.shadow);
            }
            catch (e:ArgumentError) {
               // No-op
            }
         }
         this.label_reset();

         // Remove self
         if (!skip_delete) {
            delete Waypoint.all[this.stack_id];
         }
      }

      // *** Item Init/Update fcns.

      //
      override public function set deleted(d:Boolean) :void
      {
         super.deleted = d;
         /*
         if (d) {
            delete Waypoint.all[this.stack_id];
         }
         else {
            if (this !== Waypoint.all[this.stack_id]) {
               if (this.stack_id in Waypoint.all) {
                  m4_WARNING2('set deleted: overwrite:',
                              Waypoint.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Waypoint.all[this.stack_id] = this;
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
            if (this !== Waypoint.all[this.stack_id]) {
               if (this.stack_id in Waypoint.all) {
                  m4_WARNING2('init_add: overwrite:',
                              Waypoint.all[this.stack_id]);
                  m4_WARNING('               with:', this);
                  m4_WARNING(Introspect.stack_trace());
               }
               Waypoint.all[this.stack_id] = this;
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
         this.update_item_all_lookup(Waypoint, commit_info);
         super.update_item_committed(commit_info);
      }

      //
      override protected function is_item_loaded(item_agg:Aggregator_Base)
         :Boolean
      {
         return (super.is_item_loaded(item_agg)
                 || (this.stack_id in Waypoint.all));
      }

      // *** Event handlers

      //
      override public function on_mouse_out(ev:MouseEvent) :void
      {
         if (tooltip !== null) {
            ToolTipManager.destroyToolTip(tooltip);
            tooltip = null;
         }
         super.on_mouse_out(ev);
      }

      //
      override public function on_mouse_over(ev:MouseEvent) :void
      {
         if (tooltip !== null) {
            ToolTipManager.destroyToolTip(tooltip);
         }
         tooltip = ToolTipManager.createToolTip(
            this.name_,
            G.map.xform_x_map2stage(this.x_map),
            G.map.xform_y_map2stage(this.y_map));
         super.on_mouse_over(ev);
      }

      // *** Getters/setters

      //
      override protected function get class_item_lookup() :Dictionary
      {
         return Waypoint.all;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         return Waypoint.all;
      }

      //
      public function get counterpart() :Waypoint
      {
         return (this.counterpart_untyped as Waypoint);
      }

      //
      override public function get counterpart_gf() :Geofeature
      {
         return this.counterpart;
      }

      //
      override public function get friendly_name() :String
      {
         return 'Point';
         //return 'Waypoint';
      }

      // Shorten long names with '...'
      override public function get label_text() :String
      {
         if (this.name_.length > Conf.max_point_label_len) {
            return this.name_.slice(0, Conf.max_point_label_len - 3) + '...';
         }
         else {
            return this.name_;
         }
      }

      //
      override public function get vertex_editable() :Boolean
      {
         // 2013.05.07: Only show the thin blue line in view mode, and don't
         //             show geofeature vertices or allow them to be edited.
         //return true;
         var is_editable:Boolean = G.app.mode.is_allowed(App_Action.item_edit);
         m4_DEBUG('vertex_editable: is_editable:', is_editable);
         return is_editable;
      }

      //
      public function get x_cv() :Number
      {
         return G.map.xform_x_map2cv(this.x_map);
      }

      //
      public function set x_cv(x:Number) :void
      {
         this.x_map = G.map.xform_x_cv2map(x);
      }

      //
      public function get x_map() :Number
      {
         return this.xs[0];
      }

      //
      public function set x_map(x:Number) :void
      {
         this.xs[0] = x;
      }

      //
      public function get y_cv() :Number
      {
         return G.map.xform_y_map2cv(this.y_map);
      }

      //
      public function set y_cv(y:Number) :void
      {
         this.y_map = G.map.xform_y_cv2map(y);
      }

      //
      public function get y_map() :Number
      {
         return this.ys[0];
      }

      //
      public function set y_map(y:Number) :void
      {
         this.ys[0] = y;
      }

      // *** Protected instance methods

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
      override protected function label_parms_compute() :void
      {
         var radius:Number = this.draw_width / 2;
         this.label_x = this.x_cv + radius - 1;
         this.label_y = this.y_cv - 4 * radius + 1;
      }

   }
}


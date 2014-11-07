/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets.tools {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.ui.Keyboard;
   import flash.utils.Dictionary;
   import mx.controls.Alert;
   import mx.core.UIComponent;

   import items.feats.Byway;
   import utils.geom.Geometry;
   import utils.misc.Logging;
   import views.base.Map_Canvas_Base;
   import views.commands.Command_Base;
   import views.commands.Node_Endpoint_Build;
   import views.map_widgets.Bubble_Node;

   public class Tool_Node_Endpoint_Build extends Map_Tool {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tool:NodeBld');

      // *** Instance variables

      protected var byway_over_1:Byway;
      protected var byway_over_2:Byway;
      protected var split_style:int;
      protected var intersection:Point;
      protected var sensitivity:int = Conf.nb_sensitivity;
      protected var dist_t_limit:int = Conf.nb_dist_t_limit;
      protected var max_radius:int = Conf.nb_circle_max_radius;
      protected var center_dot_radius:int = Conf.nb_circle_dot_radius;
      protected var circle_widget:Sprite;
      protected var circle_drawn:Boolean;

      // *** Constructor

      public function Tool_Node_Endpoint_Build(map:Map_Canvas_Base)
      {
         super(map);

         // We could use a custom mouse cursor, but it's slow --
         //  the mouse is drawn once per frame, so it's jerky (sans beef).
         //  this.cursor = UI.cursor_node_build;
         //  this.cursor_x = -1;
         //  this.cursor_y = -2;
      }

      // *** Event handlers

      //
      override public function on_mouse_move(x:Number, y:Number) :void
      {
         super.on_mouse_move(x, y);

         var objs:Array;
         var obj1:Object;
         var obj2:Object;
         var byway1:Byway;
         var byway2:Byway;
         var count:Number = 0;
         var split_style:int;

         var p:Point = new Point(x, y);
         p = G.map.globalToLocal(p);
         p.x = G.map.xform_x_cv2map(p.x);
         p.y = G.map.xform_y_cv2map(p.y);
         objs = G.map.intersection_detector.nearest_many(
            p.x, p.y, this.sensitivity * 2);

         for each (obj1 in objs) {
            if (obj1 is Byway) {
               byway1 = obj1 as Byway;
               for each (obj2 in objs) {
                  if (obj2 is Byway) {
                     byway2 = obj2 as Byway;
                     split_style = -1;
                     if (byway1 !== byway2) {
                        if (this.is_missed_x(byway1, byway2, p)) {
                           split_style = Node_Endpoint_Build
                                          .SPLIT_BOTH_AT_X_INTERSECTION;
                        }
                        else {
                           split_style = this.is_missed_t(byway1, byway2, p);
                        }
                        if (split_style > -1) {
                           count++;
                           if (   (this.byway_over_1 !== null)
                               && (this.byway_over_1 !== byway1)
                               && (this.byway_over_1 !== byway2)) {
                              this.byway_over_1.highlight_remove();
                              this.circle_remove();
                           }
                           if (   (this.byway_over_2 !== null)
                               && (this.byway_over_2 !== byway1)
                               && (this.byway_over_2 !== byway2)) {
                              this.byway_over_2.highlight_remove();
                              this.circle_remove();
                           }
                           if ((   (this.byway_over_1 !== byway1)
                                || (this.byway_over_2 !== byway2))
                               && (   (this.byway_over_1 !== byway2)
                                   || (this.byway_over_2 !== byway1))) {
                              this.byway_over_1 = byway1;
                              this.byway_over_2 = byway2;
                              this.split_style = split_style;
                              break;
                           }
                        }
                     }
                  }
               }
            }
         }

         if (count > 0) {
            if (this.byway_over_1 !== null) {
               this.byway_over_1.highlight_draw();
            }
            if (this.byway_over_2 !== null) {
               this.byway_over_2.highlight_draw();
            }
            this.circle_put();
         }
         else {
            if (this.byway_over_1 !== null) {
               this.byway_over_1.highlight_remove();
               this.byway_over_1 = null;
               this.circle_remove();
            }
            if (this.byway_over_2 !== null) {
               this.byway_over_2.highlight_remove();
               this.byway_over_2 = null;
               this.circle_remove();
            }
         }

         this.circle_update(p);
      }

      //
      override public function on_mouse_up(ev:MouseEvent, processed:Boolean)
         :Boolean
      {
         if (   (this.byway_over_1 !== null)
             && (this.byway_over_2 !== null)) {

            var cmd:Node_Endpoint_Build;
            cmd = new Node_Endpoint_Build(
                        this.byway_over_1,
                        this.byway_over_2,
                        this.intersection.x,
                        this.intersection.y,
                        this.split_style);

            // The node being built might involve map items that have never
            // been selected by the user and therefore have not had their
            // link_values et al lazy-loaded. So we need to use callbacks.
            G.map.cm.do_(cmd, this.on_node_endpoint_build_done,
                              this.on_node_endpoint_build_fail);
            m4_DEBUG('on_mouse_up: cmd.is_prepared:', cmd.is_prepared);
         }

         return super.on_mouse_up(ev, processed);
      }

      //
      public function on_node_endpoint_build_done(cmd:Command_Base) :void
      {
         m4_DEBUG('on_node_endpoint_build_done');
         if (this.byway_over_1 !== null) {
            this.byway_over_1.highlight_remove();
         }
         if (this.byway_over_2 !== null) {
            this.byway_over_2.highlight_remove();
         }
         m4_ASSERT_SOFT(   (   (this.byway_over_1 !== null)
                            && (this.byway_over_2 !== null))
                        || (   (this.byway_over_1 === null)
                            && (this.byway_over_2 === null)));
         this.circle_remove();
      }

      //
      public function on_node_endpoint_build_fail(cmd:Command_Base) :void
      {
         m4_WARNING('on_node_endpoint_build_fail');
      }

      // *** Instance methods

      //
      override public function activate() :void
      {
         m4_TALKY('activate');
         this.circle_widget = new Sprite();
         this.map.higherlights.addChild(this.circle_widget);
      }

      //
      override public function deactivate() :void
      {
         m4_TALKY('deactivate');
         this.map.higherlights.removeChild(this.circle_widget);
         this.circle_widget = null;
      }

      //
      override public function mouse_event_applies_to(target_:Object) :Boolean
      {
         var applies_to:Boolean = false;
         // Check that the byway is editable.
         // FIXME: There should be multiple byways that intersect that need to
         //        be checked.
         var bway:Byway = (target_ as Byway);
         applies_to = ((bway !== null) && (bway.can_edit));
         m4_DEBUG2('mouse_event_applies_to: target_:', target_,
                   '/ applies:', applies_to);
         return applies_to;
      }

      //
      override public function get tool_is_advanced() :Boolean
      {
         return true;
      }

      //
      override public function get tool_name() :String
      {
         return 'tools_node_endpoint_build';
      }

      // Check that the user has appropriate priveleges to edit the items
      // that are selected
      override public function get useable() :Boolean
      {
         // The user has to be able to edit byways and to create new byways.
         // But we don't know what byways are being edited yet -- this tool
         // is used on any byway, selected or unselected.
         return ((super.useable)
                 //&& (this.map.zoom_is_vector())
                 //&& (this.map.selectedset.length >= 0)
                 //&& (this.useable_check_type(Byway))
                 // This is redundant; see user_has_permissions:
                 && (G.item_mgr.create_allowed_get(Byway)));
      }

      // *** Helper methods

      //
      protected function circle_put() :void
      {
         if (!this.circle_drawn) {
            this.circle_render(this.max_radius);
            this.circle_drawn = true;
         }
      }

      //
      protected function circle_remove() :void
      {
         if (this.circle_drawn) {
            // If we lazy-loaded byways, deactivate was already called,
            // so this.circle_widget may already have been removed.
            if (this.circle_widget !== null) {
               this.circle_widget.graphics.clear();
            }
            this.circle_drawn = false;
         }
      }

      //
      protected function circle_render(radius:int) :void
      {
         var gr:Graphics = this.circle_widget.graphics;

         gr.clear();
         gr.beginFill(Conf.node_endpoint_builder_color, 0.4);
         gr.drawCircle(G.map.xform_x_map2cv(this.intersection.x),
                       G.map.xform_y_map2cv(this.intersection.y),
                       radius);
         gr.endFill();
         gr.beginFill(Conf.node_endpoint_builder_color, 1);
         gr.drawCircle(G.map.xform_x_map2cv(this.intersection.x),
                       G.map.xform_y_map2cv(this.intersection.y),
                       this.center_dot_radius);
         gr.endFill();
      }

      //
      protected function circle_update(mouse_pt:Point) :void
      {
         var dist:int;

         if (this.circle_drawn) {
            dist = Geometry.distance(this.intersection.x, this.intersection.y,
                                     mouse_pt.x, mouse_pt.y);
            this.circle_render(G.map.xform_scalar_map2cv(dist + 2));
         }
      }

      // Return true if given byways don't intersect, false otherwise.
      // 2012.08.13: The usage of the words "don't intersect" isn't quite
      // right; really, this is if the two byways don't share any endpoints.
      protected function do_not_intersect(byway1:Byway, byway2:Byway) :Boolean
      {
         return (   byway1.beg_node_id !== byway2.beg_node_id
                 && byway1.fin_node_id !== byway2.fin_node_id
                 && byway1.beg_node_id !== byway2.fin_node_id
                 && byway1.fin_node_id !== byway2.beg_node_id);
      }

      // Return which byway to extend if given byways are a case of a missed T.
      //
      // ----- : A missed T.        --o-- : Fixed T.
      //   |                          |
      //
      // If there are nultiple instances of missed T intersection, this will
      // pick the one nearest to near_here.
      protected function is_missed_t(byway1:Byway,
                                     byway2:Byway,
                                     near_here:Point) :int
      {
         var split_style:int = -1;

         if ((this.do_not_intersect(byway1, byway2))
             && (this.is_missed_t_asym(byway1, byway2, near_here))) {
            split_style = Node_Endpoint_Build.SPLIT_FIRST_EXTEND_SECOND;
         }
         else if ((this.do_not_intersect(byway1, byway2))
                  && (this.is_missed_t_asym(byway2, byway1, near_here))) {
            split_style = Node_Endpoint_Build.SPLIT_SECOND_EXTEND_FIRST;
         }

         return split_style;
      }

      // Asymmetric version of is_missed_T.
      // --- : byway_hor
      //  |  : byway_ver
      // The byway that needs to be extended is the vertical one and the other
      // one is the horizontal one.
      //
      // If there are multiple instances of missed T intersection, this will
      // pick the one nearest to near_here.
      protected function is_missed_t_asym(byway_hor:Byway,
                                          byway_ver:Byway,
                                          near_here:Point) :Boolean
      {
         var is_missed_t_asym:Boolean = false;
         var i:int;

         // beg_hor to fin_hor represents a segment of byway_hor.
         var beg_hor:Point = new Point();
         var fin_hor:Point = new Point();

         // ver_first_1 to ver_first_2 is the first segment of byway_ver.
         var ver_first_1:Point = new Point();
         var ver_first_2:Point = new Point();

         // ver_last_1 to ver_last_2 is the last segment of byway_ver.
         var ver_last_1:Point = new Point();
         var ver_last_2:Point = new Point();

         // ver_int is the possible point of intersection.
         var ver_int:Point = null;

         // How close should the byways be to qualify as a missed T?
         var dist_t:int;
         var dist_t_1:int;
         var dist_t_2:int;
         var bn:Bubble_Node;

         // How close should the mouse be to start being active (click-ready)?
         var min_dist:Number = G.map.xform_scalar_cv2map(this.sensitivity);
         var dist:int;

         // Need to count neighbors to ensure that at a missed T, byway_ver is
         // "hanging".
         var neighbor_count:int;
         var o:Object;

         // Load the first and last vertex points.
         ver_first_1.x = byway_ver.xs[0];
         ver_first_1.y = byway_ver.ys[0];
         ver_first_2.x = byway_ver.xs[1];
         ver_first_2.y = byway_ver.ys[1];
         ver_last_1.x = byway_ver.xs[byway_ver.xs.length - 2];
         ver_last_1.y = byway_ver.ys[byway_ver.ys.length - 2];
         ver_last_2.x = byway_ver.xs[byway_ver.xs.length - 1];
         ver_last_2.y = byway_ver.ys[byway_ver.ys.length - 1];

         // Check to see which one of the first and the last segments of
         // byway_ver is to be extended.

         for (i = 0; i < byway_hor.xs.length - 1; i++) {
            beg_hor.x = byway_hor.xs[i];
            beg_hor.y = byway_hor.ys[i];
            fin_hor.x = byway_hor.xs[i + 1];
            fin_hor.y = byway_hor.ys[i + 1];

            m4_VERBOSE('is_missed_t_asym: i:', i);
            if (!Geometry.opposite_side(beg_hor, fin_hor,
                                        ver_first_1, ver_first_2)
                && Geometry.opposite_side(ver_first_1, ver_first_2,
                                          beg_hor, fin_hor)) {
               // Check first segment.

               // Find out possible point of intersection.
               ver_int = Geometry.intersection_lines(beg_hor, fin_hor,
                                                     ver_first_1, ver_first_2);

               // Measure distance to see whether it is close enough to
               // qualify as a missed T.
               dist_t_1 = Geometry.distance(ver_int.x, ver_int.y,
                                            ver_first_1.x, ver_first_1.y);
               dist_t_2 = Geometry.distance(ver_int.x, ver_int.y,
                                            ver_first_2.x, ver_first_2.y);

               if (dist_t_1 < dist_t_2) {
                  dist_t = dist_t_1;
                  bn = G.map.node_snapper.nearest(ver_first_1.x,
                                                  ver_first_1.y,
                                                  Conf.byway_equal_thresh);
               }
               else {
                  dist_t = dist_t_2;
                  bn = G.map.node_snapper.nearest(ver_first_2.x,
                                                  ver_first_2.y,
                                                  Conf.byway_equal_thresh);
               }

               // Count neighbors to see whether byway is connected at that
               // node or not.
               neighbor_count = 0;
               if (bn !== null) {
                  if (bn.stack_id in G.map.nodes_adjacent) {
                     for each (o in G.map.nodes_adjacent[bn.stack_id]) {
                        neighbor_count++;
                     }
                  }
               }

               if (ver_int !== null) {
                  // Sensitivity check.
                  dist = Geometry.distance(ver_int.x, ver_int.y,
                                           near_here.x, near_here.y);

                  // If all conditions meet, then it is a missed T!
                  if (0 <= dist_t
                      && G.map.xform_scalar_map2cv(dist_t) < this.dist_t_limit
                      && dist < min_dist && neighbor_count == 1) {
                     is_missed_t_asym = true;
                     this.intersection = ver_int;
                     min_dist = dist;
                  }
               }
            }

            if ((!is_missed_t_asym)
                && (!Geometry.opposite_side(beg_hor, fin_hor,
                                           ver_last_1, ver_last_2))
                && (Geometry.opposite_side(ver_last_1, ver_last_2,
                                          beg_hor, fin_hor))) {

               // Check last segment.

               // Find out possible point of intersection.
               ver_int = Geometry.intersection_lines(beg_hor, fin_hor,
                                                     ver_last_1, ver_last_2);

               // Measure distance to see whether it is close enough to
               // qualify as a missed T.
               dist_t_1 = Geometry.distance(ver_int.x, ver_int.y,
                                            ver_last_1.x, ver_last_1.y);
               dist_t_2 = Geometry.distance(ver_int.x, ver_int.y,
                                            ver_last_2.x, ver_last_2.y);

               if (dist_t_1 < dist_t_2) {
                  dist_t = dist_t_1;
                  bn = G.map.node_snapper.nearest(ver_last_1.x,
                                                  ver_last_1.y,
                                                  Conf.byway_equal_thresh);
               }
               else {
                  dist_t = dist_t_2;
                  bn = G.map.node_snapper.nearest(ver_last_2.x,
                                                  ver_last_2.y,
                                                  Conf.byway_equal_thresh);
               }

               // Count neighbors to see whether byway is connected at that
               // node or not.
               neighbor_count = 0;
               if (bn !== null) {
                  if (bn.stack_id in G.map.nodes_adjacent) {
                     for each (o in G.map.nodes_adjacent[bn.stack_id]) {
                        neighbor_count++;
                     }
                  }
               }

               if (ver_int !== null) {
                  // Sensitivity check.
                  dist = Geometry.distance(ver_int.x, ver_int.y,
                                           near_here.x, near_here.y);

                  // If all conditions meet, then it is a missed T!
                  if (0 <= dist_t
                      && G.map.xform_scalar_map2cv(dist_t) < this.dist_t_limit
                      && dist < min_dist && neighbor_count == 1) {
                     is_missed_t_asym = true;
                     this.intersection = ver_int;
                     min_dist = dist;
                  }
               }
            }
         }

         return is_missed_t_asym;
      }

      // Return true if given byways are a case of a missed X.
      //
      //   |                          |
      // --|-- : A missed X.        --o-- : Fixed X.
      //   |                          |
      //
      // If there are nultiple instances of missed T intersection, this will
      // pick the one nearest to near_here.
      protected function is_missed_x(byway1:Byway,
                                     byway2:Byway,
                                     near_here:Point) :Boolean
      {
         m4_VERBOSE('is_missed_x');

         var is_missed_x:Boolean = false;
         var i:int;
         var j:int;

         // ver_beg_1 to ver_fin_1 represents a segment of byway1.
         var ver_beg_1:Point = new Point();
         var ver_fin_1:Point = new Point();

         // ver_beg_2 to ver_fin_2 represents a segment of byway2.
         var ver_beg_2:Point = new Point();
         var ver_fin_2:Point = new Point();

         // ver_int is the possible point of intersection.
         var ver_int:Point;

         // How close should the mouse be to start being active (click-ready)?
         // Using xdelta version because transforming distance (+ve)
         var min_dist:Number = G.map.xform_scalar_cv2map(this.sensitivity);
         var dist:Number;

         if (this.do_not_intersect(byway1, byway2)) {
            for (i = 0; i < byway1.xs.length - 1; i++) {
               for (j = 0; j < byway2.xs.length - 1; j++) {

                  // Load the start and end vertex points of the segment.
                  ver_beg_1.x = byway1.xs[i];
                  ver_beg_1.y = byway1.ys[i];
                  ver_fin_1.x = byway1.xs[i + 1];
                  ver_fin_1.y = byway1.ys[i + 1];
                  ver_beg_2.x = byway2.xs[j];
                  ver_beg_2.y = byway2.ys[j];
                  ver_fin_2.x = byway2.xs[j + 1];
                  ver_fin_2.y = byway2.ys[j + 1];

                  // Find out possible point of intersection.
                  ver_int = Geometry.intersection_segments(
                              ver_beg_1, ver_fin_1, ver_beg_2, ver_fin_2);

                  if (ver_int !== null) {

                     // Sensitivity check.
                     dist = Geometry.distance(ver_int.x, ver_int.y,
                                              near_here.x, near_here.y);

                     // If all conditions meet, then it is a missed X!
                     if (dist < min_dist) {
                        is_missed_x = true;
                        min_dist = dist;
                        this.intersection = ver_int;
                     }

                  }
               }
            }
         }

         return is_missed_x;
      }

   }
}


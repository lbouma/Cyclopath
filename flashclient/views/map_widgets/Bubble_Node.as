/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets {

   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;

   import items.feats.Byway;
   import utils.geom.Geometry;
   import utils.geom.MOBRable;
   import utils.misc.A_Star_Item;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Bubble_Node extends Sprite implements A_Star_Item, MOBRable {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Bubble_Node');

      // *** Instance variables

      protected var _b_x:Number;
      protected var _b_y:Number;
      // EXPLAIN: This is the node stack ID, right? Rename it?
      public var stack_id:int;

      public var bubble_radius:Number;

      protected var radius_last_zoom:int;
      protected var radius_:Number;
      protected var _mobr:Rectangle;

      // *** Constructor

      public function Bubble_Node(stack_id:int, x:Number, y:Number)
      {
         super();

         this.b_x = x;
         this.b_y = y;
         this.stack_id = stack_id;

         this.radius_last_zoom = -1;
         this.radius_ = 1;
      }

      // *** Getters and setters

      //
      public function get b_x() :Number
      {
         return this._b_x;
      }

      //
      public function set b_x(x:Number) :void
      {
         this._b_x = x;
         this._mobr = new Rectangle(this.b_x, this.b_y, 0.0001, 0.0001);
      }

      //
      public function get b_y() :Number
      {
         return this._b_y;
      }

      //
      public function set b_y(y:Number) :void
      {
         this._b_y = y;
         this._mobr = new Rectangle(this.b_x, this.b_y, 0.0001, 0.0001);
      }

      //

      //
      public function set radius(r:Number) :void
      {
         this.radius_ = r;
         this.radius_last_zoom = G.map.zoom_level;
      }

      //
      public function get radius() :Number
      {
         var byway:Byway;
         if ((this.radius_ <= 0)
             || (this.radius_last_zoom != G.map.zoom_level)) {
            this.radius_last_zoom = G.map.zoom_level;
            this.radius_ = 0.5;
            for each (byway in G.map.nodes_adjacent[this.stack_id]) {
               if (((byway.draw_width / 2.0) + 1) > this.radius_) {
                  this.radius_ = (byway.draw_width / 2.0) + 1;
               }
            }
            //m4_DEBUG('get radius: bubble_radius:', this.radius_);
            this.bubble_radius = this.radius_;
         }
         return this.radius_;
      }

      //
      public function get mobr() :Rectangle
      {
         return this._mobr;
      }

      // *** Draw methods

// EXPLAIN: How does this relate to Vertex.draw?
      //
      public function draw(color:int=0x444444, alpha:Number=1) :void
      {
         this.graphics.clear();
         this.graphics.beginFill(color, alpha);
         this.graphics.drawCircle(G.map.xform_x_map2cv(this.b_x),
                                  G.map.xform_y_map2cv(this.b_y),
                                  this.radius);
         this.graphics.endFill();
         this.graphics.beginFill(0x000000, .2);
         this.graphics.drawCircle(G.map.xform_x_map2cv(this.b_x),
                                  G.map.xform_y_map2cv(this.b_y),
                                  this.bubble_radius);
         this.graphics.endFill();
      }

      // *** Instance methods

      //
      public static function all() :Array
      {
         var a:Array = new Array();
         var id:Object;
         var bs:Set_UUID;

         for (id in G.map.bubble_nodes) {
            bs = G.map.nodes_adjacent[int(id)];
            if (!bs.empty) {
               a.push(G.map.bubble_nodes[int(id)]);
            }
         }

         return a;
      }

      //
      public function cost(neighbor:A_Star_Item) :Number
      {
// FIXME/BUG_FALL_2013: Holding Shift to select a series of connecting
//                      line segments seems broken.
//                      And we never had a problem with connecting_byway
//                      return null until 2014.02.
         var cost:Number = 0;
         var byway:Byway = this.connecting_byway(neighbor as Bubble_Node);
         if (byway !== null) {
            cost = byway.length;
         }
         else {
            m4_ASSERT_SOFT(false);
         }
         return cost;
      }

      //
      public function cost_estimate(goal:A_Star_Item) :Number
      {
         return Geometry.distance(this.b_x, this.b_y,
                                  (goal as Bubble_Node).b_x,
                                  (goal as Bubble_Node).b_y);
      }

      //
      public function connecting_byway(other:Bubble_Node) :Byway
      {
         var b1s:Set_UUID;
         var b2s:Set_UUID;
         var o1:Byway;
         var o2:Byway;

         if (this.stack_id == other.stack_id) {
            return null;
         }

         if ((this.stack_id in G.map.nodes_adjacent)
             && (other.stack_id in G.map.nodes_adjacent)) {
            b1s = G.map.nodes_adjacent[this.stack_id];
            b2s = G.map.nodes_adjacent[other.stack_id];
            for each (o1 in b1s) {
               for each (o2 in b2s) {
                  if (o1 === o2) {
                     return o1;
                  }
               }
            }
         }
         return null;
      }

      //
      public function neighbors(parent:A_Star_Item, array_out:Array) :void
      {
         var a:Array = this.successors();
         var i:Bubble_Node;

         for each (i in a) {
            if (i !== parent) {
               array_out.push(i);
            }
         }
      }

      // Returns all of the intersections that connect with this one
      public function successors() :Array
      {
         var a:Array = new Array();
         var visited:Dictionary = new Dictionary();
         var bs:Set_UUID;
         var b:Byway;
         var i:Bubble_Node;

         if (this.stack_id in G.map.nodes_adjacent) {
            bs = G.map.nodes_adjacent[this.stack_id];
            for each (b in bs) {
               if (b.beg_node_id != this.stack_id
                   && !(b.beg_node_id in visited)) {
                  i = G.map.bubble_nodes[b.beg_node_id];
                  a.push(i);
                  visited[b.beg_node_id] = i;
               }
               else if (b.fin_node_id != this.stack_id
                        && !(b.fin_node_id in visited)) {
                  i = G.map.bubble_nodes[b.fin_node_id];
                  a.push(i);
                  visited[b.fin_node_id] = i;
               }
            }
         }

         return a;
      }

      // ***

      //
      override public function toString() :String
      {
         //super.toString() // "[object Bubble_Node]"
         var what_is:String =
            'Bubble_Node:'
            + 'stack_id: ' + this.stack_id
            + ' at (' + this._b_x
            +    ', ' + this._b_y
            + '), radius: ' + this.bubble_radius
            + ', last_rad: ' + this.radius_last_zoom
            + ', radius_: ' + this.radius_
            + ', _mobr: ' + this._mobr
            ;
         return what_is;
      }

   }
}


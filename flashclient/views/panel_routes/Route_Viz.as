/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import flash.display.Graphics;

   import items.feats.Route;
   import items.feats.Route_Step;
   import utils.misc.Logging;

   public class Route_Viz {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@Route_Viz');

      // *** Instance variables

      public var id_:int;
      public var name:String;
      public var colors:Array;
      public var color_map:Function;

      public var alpha:Number;

      // *** Constructor

      public function Route_Viz(id_:int,
                                name:String,
                                colors:Array,
                                color_map:Function,
                                alpha:Number=Conf.route_alpha)
      {
         this.id_ = id_;
         this.name = name;
         this.colors = colors;
         this.color_map = color_map;
         this.alpha = alpha;
      }

      // *** Static class methods

      //
      public static function random() :Route_Viz
      {
         var viz_index:int = Math.floor(
            Math.random() * Conf.route_vizs.length);
         return Conf.route_vizs[viz_index];
      }

      // *** Instance methods

      //
      public function route_line_render(route:Route,
                                        rsteps:Array,
                                        alternate:Boolean=false)
         :void
      {
         var i:int;
         var step:Route_Step;
         var x:Number;
         var y:Number;
         var gr:Graphics = route.sprite.graphics;
         var xs:Array = alternate ? route.alternate_xs : route.xs;
         var ys:Array = alternate ? route.alternate_ys : route.ys;

         m4_DEBUG7('route_line_render: rsteps.length:',
                   (rsteps !== null) ? rsteps.length : 'null',
                   '/ route.sprite.visible:',
                   (route !== null) ? ((route.sprite !== null)
                                       ? route.sprite.visible : '!sprite')
                                      : '!route',
                   '/ route:', route);

         for each (step in rsteps) {
            x = G.map.xform_x_map2cv(xs[step.beg_index]);
            y = G.map.xform_y_map2cv(ys[step.beg_index]);
            gr.lineStyle(route.draw_width,
                         this.color_map(step),
                         this.alpha);
            gr.moveTo(x, y);
            for (i = step.beg_index + 1; i < step.fin_index; i++) {
               x = G.map.xform_x_map2cv(xs[i]);
               y = G.map.xform_y_map2cv(ys[i]);
               gr.lineTo(x, y);
            }
         }
      }

   }
}


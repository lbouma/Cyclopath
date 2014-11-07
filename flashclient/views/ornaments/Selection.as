/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.ornaments {

   import flash.display.Sprite;
   import flash.geom.Rectangle;

   import items.Geofeature;
   import items.feats.Region;
   import utils.misc.Logging;
   import views.base.Paint;

   public class Selection extends Ornament {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Selection');

      // *** Instance variables

      public var glow:Sprite;
      public var line:Sprite;

      // *** Constructor

      public function Selection(owner_:Geofeature)
      {
         super(owner_);

         this.glow = new Sprite();
         this.line = new Sprite();
      }

      // *** Getters and Setters

      //
      override public function set visible(s:Boolean) :void
      {
         this.glow.visible = s;
         this.line.visible = s;
      }

      // *** Instance methods

      //
      override public function draw() :void
      {
         var o:Geofeature = this.owner_;
         var r:Rectangle = o.sprite.getBounds(G.app.map_canvas);

         // FIXME: replace the black with a nicer color; can we just
         //        make a better selection (solid border w/ gap?) [rp]

         var draw_width:Number;
         var shadow_width:Number;
         var alpha:Number = 1;

         // is_drawable is a computed value, so cache it.
         var is_drawable:Boolean = o.is_drawable;

         if (is_drawable) {
            draw_width = o.draw_width;
            shadow_width = o.shadow_width;
         }
         else {
            draw_width = 1;
            shadow_width = 1;
         }

         if (is_drawable) {
            // r is only meaningful if o was drawn,
            // since the purpose of this check is for when we have a large
            // selection, we can safely ignore it if the feature isn't drawn
            // (which is because we've zoomed out so much).
            if ((r.left > G.app.map_canvas.width)
                || (r.right < 0)
                || (r.top > G.app.map_canvas.height)
                || (r.bottom < 0)) {
               this.glow.graphics.clear();
               this.line.graphics.clear();
               return;
            }
         }

         // line
         this.line.graphics.clear();
         Paint.line_draw(this.line.graphics, o.xs, o.ys,
                         Conf.selection_line_width,
                         Conf.selection_color,
                         //0x00ff00,
                         .5, true);

         // glow
         this.glow.graphics.clear();
         if (o.xs.length == 1) {
            // FIXME: hack
            this.glow.graphics.beginFill(Conf.selection_color, alpha);
            //this.glow.graphics.beginFill(0xff0000, alpha);
            this.glow.graphics.drawCircle(G.map.xform_x_map2cv(o.xs[0]),
                                          G.map.xform_y_map2cv(o.ys[0]),
                                          (draw_width / 2
                                           + shadow_width
                                           + Conf.selection_glow_radius));
         }
         else {
            Paint.line_draw(this.glow.graphics, o.xs, o.ys,
                            (draw_width + 2 * shadow_width
                                        + 2 * Conf.selection_glow_radius),
                            Conf.selection_color,
                            //0xff0000,
                            alpha);

            // FIXME: hack, this should be in Region. Make draw_after() fcn. in
            //        Geofeature?
            if (o is Region) {
               (o as Region).crosshairs_draw(this.glow.graphics, true, true);
            }
         }
      }

   }
}


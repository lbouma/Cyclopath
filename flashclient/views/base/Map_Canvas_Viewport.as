/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.base {

   import flash.events.KeyboardEvent;
   import flash.geom.Matrix;
   import flash.geom.Point;

   import items.Geofeature;
   import utils.geom.Dual_Rect;
   import utils.geom.Location;
   import utils.geom.MOBRable_DR;
   import utils.misc.Logging;
   import utils.misc.View_Stack;

   public class Map_Canvas_Viewport extends Map_Canvas_Tool {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('MC_Viewport');

      // *** Instance variables

      public var locations:Map_Layer_Passive;

      public var loc_visible:Location;

      public var view_stack:View_Stack;

      // Parameters to translate between map and canvas coordinates
      public var zoom_level:int;
      public var zoom_level_previous:Number = Number.NaN;
      public var map_x_at_canvas_origin:Number;
      public var map_y_at_canvas_origin:Number;

      // The view_rect is what the user's looking at The resident_rect is what
      // the client fetched, which is slightly larger than the view rect.
      public var view_rect:Dual_Rect;
      public var resident_rect:Dual_Rect;

      private var gfs_on_pan_called:Boolean;

      public var view_rect_keep:Dual_Rect;

      // *** Constructor

      public function Map_Canvas_Viewport()
      {
         super();

         this.view_stack = new View_Stack();
         this.view_rect = new Dual_Rect();
         this.view_rect_keep_update();
      }

      // *** Getters and setters

      //
      public function get scale() :Number
      {
         // MAGIC_NUMBER: Zoom 16 is 1:1, or scale 1.
         return Math.pow(2, this.zoom_level - 16);
      }

      // *** Event handlers

      // Schedule only one later call of gfs_on_pan().
      public function gfs_on_pan_later() :void
      {
         if (!this.gfs_on_pan_called) {
            this.gfs_on_pan_called = true;
            m4_DEBUG_CLLL('>callLater: this.gfs_on_pan');
            this.callLater(this.gfs_on_pan);
         }
      }

      // Call the on_pan() function of each geofeature, it if exists.
      public function gfs_on_pan() :void
      {
         var gf:Geofeature;
         m4_DEBUG_CLLL('<callLater: gfs_on_pan');
   // BUG nnnn/FIXME: This is wasteful. The Pointing_Widget sets on_pan
   //        on whatever Geofeature it points at. But we rarely use the
   //        Pointing_Widget. And we always comes through this fcn.
   //        whenever we pan. Oh, CcpV1, always doing things the tedious
   //        way! All Pointing_Widget cares about is when we pan the
   //        map: so why not just have the Pointing_Widget listen on
   //        an event that we'll throw on_pan, and then Pointing_Widget
   //        can just close whatever points at geofeatures on the map...
   //        or maybe we could make the widget smarter and just move
   //        it to point at the new location of the geofeature, or
   //        to close the pointing widget if the geofeature is outside
   //        of the viewport.
         for each (gf in Geofeature.all) {
            if (gf.on_pan !== null) {
               gf.on_pan();
            }
         }
         // Reset the flag so that more calls to gfs_on_pan can be scheduled.
         this.gfs_on_pan_called = false;
      }

      // *** Instance methods

      // Set l to be the visible location, replacing any existing visible
      // location point. If l is null, remove any existing visible location.
      public function location_show(l:Location, lookat:Boolean) :void
      {
         if (this.loc_visible !== null) {
            this.locations.removeChild(this.loc_visible);
         }
         this.loc_visible = l;
         if (l !== null) {
            this.locations.addChild(l);
            if (lookat) {
               this.lookat(l);
            }
         }
      }

      // Position the map over obj, and update. If zoom is 0, zoom in or
      // out to fit; otherwise, go to the given zoom.
      public function lookat(obj:MOBRable_DR, zoom:int=0) :void
      {
         this.lookat_dr(obj.mobr_dr, zoom);
      }

      //
      public function lookat_dr(obj_dr:Dual_Rect, zoom:int=0) :void
      {
         var newzoom:int;
         var obj_height:Number;
         var obj_width:Number;
         var vp_height:Number;
         var vp_width:Number;
         var zoomed_to:Boolean;

         m4_DEBUG('lookat_dr: zoom:', zoom, '/ obj_dr:', obj_dr.toString());
         m4_ASSERT(obj_dr is Dual_Rect);

         // adjust required height and width slightly to give a margin
         obj_height = 1.10 * (obj_dr.map_max_y - obj_dr.map_min_y);
         obj_width = 1.10 * (obj_dr.map_max_x - obj_dr.map_min_x);

         // height and width of a maximally-zoomed-in viewport
         vp_height = ((this.view_rect.map_max_y - this.view_rect.map_min_y)
                      * Math.pow(2, this.zoom_level - Conf.zoom_max));
         vp_width = ((this.view_rect.map_max_x - this.view_rect.map_min_x)
                     * Math.pow(2, this.zoom_level - Conf.zoom_max));

         // Find the largest zoom level that fits the whole object.
         // NOTE: This algorithm is numerically unrobust, but it's not a very
         //       demanding application.
         if (zoom != 0) {
            newzoom = zoom;
         }
         else {
            newzoom = Conf.zoom_max;
            while (vp_height < obj_height || vp_width < obj_width) {
               newzoom--;
               vp_height *= 2;
               vp_width *= 2;
            }
            // FIXME: Conf.zoom_max_lookat is 17 but that's still raster mode.
            // Are we zoomed out to raster mode but also selecting geofeatures?
            // See Widget_Attachment_Place_Widget.mxml, which calls us.
            if (newzoom > Conf.zoom_max_lookat) {
               newzoom = Conf.zoom_max_lookat;
            }
         }

         this.pan_and_zoomto(obj_dr.cv_center_x, obj_dr.cv_center_y, newzoom);
      }

      // Pan the map the given number of pixels along each axis.
      public function pan(x:Number, y:Number) :Boolean
      {
         var panned:Boolean = false;
         if ((x == 0) && (y == 0)) {
            m4_DEBUG('pan: no change');
         }
         else {
            this.view_stack.on_view_change(this.view_rect.map_center_x,
                                           this.view_rect.map_center_y,
                                           this.zoom_level);

            this.view_rect.move(-x, -y);
            this.view_rect_keep_update();

            m4_DEBUG3('pan: x:', x, '/ y:', y,
                      '/ map_center_x:', this.view_rect.map_center_x,
                      '/ map_center_y:', this.view_rect.map_center_y);

            this.update_draw_transform();
            this.orn_selection.draw();
            this.gfs_on_pan_later();

            panned = true;
         }

         return panned;
      }

      //
      public function pan_and_zoomto(x:Number, y:Number, zoom_level:*=null)
         :void
      {
         var panned_or_zoomed:Boolean = false;
         var did_panned:Boolean = false;
         var did_zoomed:Boolean = false;

         if ((x) && (y)) {

            // Ha! The ||= doesn't even bother with the right-hand side if the
            // left-hand side is already true. Ba-ha-ha-ha-ha, what a developer
            // trap!
            // NO: panned_or_zoomed ||= this.panto(x, y);
            //     panned_or_zoomed ||= this.zoomto(zoom_level as int);

            did_panned = this.panto(x, y);
            if (zoom_level !== null) {
               did_zoomed = this.zoomto(zoom_level as int);
            }
            panned_or_zoomed = did_panned || did_zoomed;

            m4_DEBUG3('pan_and_zoomto: x:', x, '/ y:', y,
                      '/ zoom_level:', zoom_level,
                      '/ panned_or_zoomed:', panned_or_zoomed);

            if (panned_or_zoomed) {
               this.update_viewport_items();
            }
         }
         else {
            m4_WARNING('pan_and_zoomto: invalid x:', x, '/ or y:', y);
            m4_ASSERT_SOFT(false);
         }
      }

      // Pan the map to the center of x and y using canvas coordinates
      public function panto(x:Number, y:Number) :Boolean
      {
         var panned_to:Boolean = false;
         if ((x) && (y)) {
            panned_to = this.pan(this.view_rect.cv_center_x - x,
                                 this.view_rect.cv_center_y - y);
         }
         else {
            m4_WARNING('panto: invalid x:', x, '/ or y:', y);
            m4_ASSERT_SOFT(false);
         }
         return panned_to;
      }

      // Dump the current pan & zoom in flash cookies
      public function panzoom_save_fcookies() :Boolean
      {
         G.fcookies_user.set('map_center_x', this.view_rect.map_center_x);
         G.fcookies_user.set('map_center_y', this.view_rect.map_center_y);
         G.fcookies_user.set('map_zoom', this.zoom_level, true);
         var finished:Boolean = true;
         return finished;
      }

      // Pan the map and update it. The amount of panning in each axis is
      // specified as a fraction of the _smaller_ of the height and width of
      // the visible portion of the map. For example, if the map is 200 pixels
      // wide and 300 tall, then pan_rel(0.4, 0.5) results in panning 0.4 *
      // 200 = 80 pixels right and 0.5 * 200 = 100 pixels down.
      public function pan_frac(x:Number, y:Number) :void
      {
         var base:Number = Math.min(this.parent.width, this.parent.height);
         m4_DEBUG('pan_frac: x:', x, '/ y:', y, '/ base:', base);
         this.pan(int(x * base), int(y * base));
         this.update_viewport_items();
      }

      // Center map on the clicked (stage) coordinates
      protected function recenter(x:Number, y:Number) :void
      {
         var nx:Number = this.xform_x_map2cv(this.xform_x_stage2map(x));
         var ny:Number = this.xform_y_map2cv(this.xform_y_stage2map(y));
         m4_DEBUG('recenter: x:', x, '/ y:', y, '/ nx:', nx, '/ ny:', ny);
         //this.panto(nx, ny);
         //this.update_viewport_items();
         this.pan_and_zoomto(nx, ny, null);
      }

      // Set the origin of the map and center the view on the given
      // coordinates.
      private function reoriginate(x:Number, y:Number) :void
      {
         // This fcn. is called just once per application session,
         // by startup().
         m4_DEBUG('reoriginate: x:', x, '/ y:', y)
         this.map_x_at_canvas_origin
            = x + this.xform_xdelta_cv2map(-G.app.map_canvas.width/2);
         this.map_y_at_canvas_origin
            = y + this.xform_ydelta_cv2map(-G.app.map_canvas.height/2);
         this.view_rect.moveto(0, 0);
         this.view_rect_keep_update();
         this.orn_selection.draw();
      }

      //
      override public function startup() :void
      {
         // Note: this.zoomto() is not yet working when this method is called.
         super.startup();

         var map_zoom:int;
         var map_center_x:Number;
         var map_center_y:Number;

         if ((G.fcookies_user.has('map_zoom'))
             && (G.fcookies_user.has('map_center_x'))
             && (G.fcookies_user.has('map_center_y'))) {
            m4_DEBUG('startup: has cookies')
            // use previous pan & zoom via flash cookies
            map_zoom = int(G.fcookies_user.get('map_zoom'));
            map_center_x = Number(G.fcookies_user.get('map_center_x'));
            map_center_y = Number(G.fcookies_user.get('map_center_y'));
         }

         // The zoom is currently 9 to 19.
         // 2013.09.18: The zoom is now 7 to 19.
         // 2013.09.19: The zoom is now 6 to 19.
         if ((map_zoom > Conf.zoom_max) || (map_zoom < Conf.zoom_min)) {
            map_zoom = Conf.map_zoom;
         }
         this.zoom_level = map_zoom;

         if ((isNaN(map_center_x)) || (!isFinite(map_center_x))) {
            map_center_x = Conf.map_center_x;
         }
         if ((isNaN(map_center_y)) || (!isFinite(map_center_y))) {
            map_center_y = Conf.map_center_y;
         }
         this.reoriginate(map_center_x, map_center_y);

         // FIXME: zoombar needs to be less dumb - we shouldn't have to set it
         //        with this mess. zoombar should do its own translation.
         G.app.zoombar.zoom_level = Conf.zoom_max - this.zoom_level + 1;
         // We must size the view_rect here, so GWIS_Base requests work.
         this.view_rect_resize();
         //this.zoom_level_previous = this.zoom_level;
      }

      // Update the transformation matrix used for drawing.
      public function update_draw_transform() :void
      {
         var m:Matrix = new Matrix();
         m.translate(-this.view_rect.cv_min_x, -this.view_rect.cv_min_y);
         this.transform.matrix = m;
         // m4_VERBOSE('update_draw_transform:', this.transform.matrix);
      }

      //
      protected function view_rect_keep_update() :void
      {
         this.view_rect_keep = this.view_rect.clone()
                                 .buffer(Conf.fetch_hys)
                                    .buffer(Conf.discard_hys);
      }

      // Adjust the cv_width and cv_height of the view_rect to match
      // the canvas's dimensions.
      public function view_rect_resize() :void
      {

         // BUG nnnn: One-way arrows are not always cleared when you zoom.

         // 2013.05.23: The parent is the new map_canvas_print, but we want
         //             map_canvas, otherwise tiles and geofeatures past a
         //             certain x,y, because this.parent's dimensions are not
         //             the same as map_canvas'.
         // E.g.s,
         //    this: main0.big_canvas._main_HBox1....map_canvas_print.map
         //    parent: ...map_toolbar_and_viewport.map_canvas.map_canvas_print
         //    parentDocument: main0
         //    map_canvas: main0....map_toolbar_and_viewport.map_canvas
         //            this.parent.width:  465 / height: 587
         //                  G.app.width: 1680 / height: 828
         //             map_canvas.width: 1224 / height: 732
         //    this.parentDocument.width: 1680 / height: 828
         // NO: this.view_rect.expandto(this.parent.width, this.parent.height);
         // Nor: this.view_rect.expandto(G.app.width, G.app.height);
         // Ya betcha:         
         this.view_rect.expandto(G.app.map_canvas.width,
                                 G.app.map_canvas.height);
         this.view_rect_keep_update();
      }

      // Methods to transform between map and canvas space.
      //
      // We could have used flash.geom.Matrix objects to do this, but didn't
      // for two reasons. First, that requires coordinate pairs to be stored
      // in Point objects (heavier weight). Second, both X and Y must be
      // transformed at the same time, which is awkward when only one or the
      // other is needed (e.g. Dual_Rect objects). This way enables everything
      // to use the same transforming code. (On the otherhand, this way
      // requires doing the math manually, which is tricky.)
      public function xform_x_map2cv(x:Number) :Number {
         return (x - this.map_x_at_canvas_origin) * this.scale;
      }
      public function xform_y_map2cv(y:Number) :Number {
         return (y - this.map_y_at_canvas_origin) * (-this.scale);
      }
      public function xform_xdelta_map2cv(xdelta:Number) :Number {
         return xdelta * this.scale;
      }
      public function xform_ydelta_map2cv(ydelta:Number) :Number {
         return ydelta * (-this.scale);
      }
      public function xform_scalar_map2cv(s:Number) :Number {
         return s * this.scale;
      }
      public function xform_x_cv2map(x:Number) :Number {
         return this.map_x_at_canvas_origin + x/this.scale;
      }
      public function xform_y_cv2map(y:Number) :Number {
         return this.map_y_at_canvas_origin - y/this.scale;
      }
      public function xform_xdelta_cv2map(xdelta:Number) :Number {
         return xdelta / this.scale;
      }
      public function xform_ydelta_cv2map(ydelta:Number) :Number {
         return ydelta / (-this.scale);
      }
      public function xform_scalar_cv2map(s:Number) :Number {
         return s / this.scale;
      }
      //
      public function xform_x_stage2map(x:Number) :Number {
         return this.xform_x_cv2map(this.globalToLocal(new Point(x, 0)).x);
      }
      public function xform_y_stage2map(y:Number) :Number {
         return this.xform_y_cv2map(this.globalToLocal(new Point(0, y)).y);
      }
      public function xform_x_map2stage(x:Number) :Number {
         return this.localToGlobal(new Point(this.xform_x_map2cv(x), 0)).x;
      }
      public function xform_y_map2stage(y:Number) :Number {
         return this.localToGlobal(new Point(0, this.xform_y_map2cv(y))).y;
      }

      // Zoom in by n levels and update the map.
      public function zoom_in(n:int) :void
      {
         this.zoomto(this.zoom_level + n);
      }

      // Return true if the given zoom level is vector mode. If zoom level
      // omitted or less than zero, use current zoom level.
      public function zoom_is_vector(zoom:Number=-1) :Boolean
      {
         var is_vector:Boolean = false;
         if (!isNaN(zoom)) {
            var zoom_level:int = int(zoom);
            if (zoom_level < 0) {
               zoom_level = this.zoom_level;
            }
            is_vector = (zoom_level > Conf.raster_only_zoom);
         }
         m4_VERBOSE2('zoom_is_vector: zoom:', zoom, '/ this.zoom_level:',
                     this.zoom_level, '/ is_vector:', is_vector);
         return is_vector;
      }

      // If the specified zoom level is not equal to the current zoom level,
      // zoom to level (with map center invariant), update the map, and return
      // true. Otherwise, do nothing and return false.
      //
      // If level is out of bounds, clamp it to the appropriate bound.
      //
      public function zoomto(level:int) :Boolean
      {
         var zoomed_to:Boolean = true;

         var listener:Map_Zoom_Listener;
         var cx:Number;
         var cy:Number;
         var rminx:Number;
         var rminy:Number;
         var rmaxx:Number;
         var rmaxy:Number;
         var start_time:Number = G.now();
         var zoom_level_new:int = level;
         var zoom_level_previous:int;

         // Clamp level if out of bounds.
         if (level < Conf.zoom_min) {
            zoom_level_new = Conf.zoom_min;
         }
         else if (level > Conf.zoom_max) {
            zoom_level_new = Conf.zoom_max;
         }

         m4_DEBUG3('zoomto: requested level:', level,
                   'corrected level:', zoom_level_new,
                   'current level:', this.zoom_level);

         // Bail out if zoom would be a no-op.
         if (zoom_level_new == this.zoom_level) {
            m4_DEBUG('  >> no change');
            zoomed_to = false;
            return zoomed_to;
         }

         // Remember the old zoom viewport so we can push it on the view stack.
         cx = this.view_rect.map_center_x;
         cy = this.view_rect.map_center_y;

         this.view_stack.on_view_change(cx, cy, this.zoom_level);

         // update sets this.zoom_level_previous, so remember locally
         zoom_level_previous = this.zoom_level;

         // Bail if no resident_rect is defined
         if (this.resident_rect === null) {
            m4_DEBUG('  >> no resident rect');
            //return false;
         }
         else {
            // Changing scale will invalidate the translation between map
            // and canvas coordinates, so we need to save and restore them.
            // FIXME I [lb] can't find where resident_rect gets clobbered
            rminx = this.resident_rect.map_min_x;
            rminy = this.resident_rect.map_min_y;
            rmaxx = this.resident_rect.map_max_x;
            rmaxy = this.resident_rect.map_max_y;
         }

         this.zoom_level = zoom_level_new;

         this.view_rect.moveto(
            this.xform_x_map2cv(cx) - (this.parent.width / 2),
            this.xform_y_map2cv(cy) - (this.parent.height / 2));
         this.view_rect_keep_update();

         if (this.resident_rect !== null) {
            // Must set upper left first; see bug #50.
            this.resident_rect.map_min_x = rminx;
            this.resident_rect.map_max_y = rmaxy;
            this.resident_rect.map_max_x = rmaxx;
            this.resident_rect.map_min_y = rminy;
            // NOTE We just set resident_rect so we can redraw while
            //      fetching; realize that update() causes Update_Base to
            //      set resident_rect again later.
         }

         // Resize the view area.
         this.update_draw_transform();

         // Update the map. This creates and queues a bunch of GWIS_Base
         // calls and processing functions. A work queue sends the GWIS_Base
         // requests off one by one, then goes through the processing
         // functions one by one, then waits for the GWIS_Base requests and
         // processes those in a particular order.
         // FIXME Rename, this serializes the remaining update tasks...
         //       or perhaps those tasks shared by
         //         this:                 zoomto, on_resize,
         //                                recenter, pan_frac, lookat_dr
         //         View_Stack:           view_port_show
         //         Tool_Pan_Select:      on_mouse_up
         this.update_viewport_items();

         // Redraw the geofeatures and labels that we're retaining while we
         // wait for the GWIS_Base responses.
         //m4_DEBUG_CLLL('>callLater: feats_redraw_and_relabl [zoomto]');
         // FIXME Cannot callLater unless it's serialized w/ update
         //this.callLater(this.geofeatures_redraw_and_relabel);
         // Can't call until features are discarded, else it holds things up
         //this.geofeatures_redraw_and_relabel();
         //this.geofeatures_labels_discard();

         // Toggle edit mode on/off if we changed from raster to vector or
         // back.
         this.zoom_ui_twiddle(zoom_level_new, zoom_level_previous);

         // Draw the geofeature ornaments, like highlights and shadows.
         this.orn_selection.draw();

         // Update the Control Panel's tag list.
         m4_DEBUG('zoomto: update_tags_list');
         G.tabs.settings.settings_panel.tag_filter_list.update_tags_list();

         // Notify zoom listeners.
         // MAYBE: The zoom_listeners is a CcpV1 holdover/faux pas. It's a
         //        colleciton of Map_Zoom_Listener interfaces, but really
         //        why not just use dispatchEvent/addEventListener?
         //        FIXME: Instead of for each, call dispatchEvent.
         for each (listener in G.map.zoom_listeners) {
            // NOTE zoom_level_previous not used by on_zoom
            listener.on_zoom(zoom_level_previous, this.zoom_level);
         }

         // Schedule the geofeature on_pan callbacks. Currently, the only
         // on_pan function is to hide the pointing widget if it's pointing
         // at anything.
         this.gfs_on_pan_later();

         m4_DEBUG2('zoomto: zoom_level_new:', zoom_level_new, 
                   '/ time:', (G.now() - start_time), 'ms');

         zoomed_to = true;
         return zoomed_to;
      }

      // Twiddle the UI according to the current zoom level.
      protected function zoom_ui_twiddle(zoom_next:int, zoom_last:int) :void
      {
         // We only do anything if we're in editing mode, because all we wanna
         // do is disable or enable those tools that do or do not work in
         // raster or vector mode.
         m4_DEBUG3('zoom_ui_twiddle: zoom_next:', zoom_next,
                   '/ zoom_last:', zoom_last,
                   '/ this.zoom_is_vector:', this.zoom_is_vector());

         if (G.app.mode === G.edit_mode) {
            var going_vector:Boolean = this.zoom_is_vector(zoom_next);
            if (going_vector != this.zoom_is_vector(zoom_last)) {
               m4_DEBUG('zoom_ui_twiddle: adjust_enabledness');
               // This is a no-op:
               G.app.tool_palette.adjust_enabledness(going_vector);
               // Enable/disable advanced tools.
               UI.editing_tools_update();
               // Change tools? This at least gets around a weird issue:
               // if you're zoomed in and choose the Create Byway tool
               // and then zoom out, that tool is disabled and the current
               // tool changes to the Create Region tool... and then you
               // click the map and you get a lineless byway (two vertices).
               G.map.tool_choose('tools_pan');
            }
         }
      }

      // ***

   }
}


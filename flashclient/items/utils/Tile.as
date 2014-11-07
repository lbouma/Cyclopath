/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Item class representing a map image tile (a raster graphic).

// COUPLING ALERT: This class relies on the global map canvas for scale.

package items.utils {

   import flash.display.Loader;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.geom.Rectangle;
   import flash.net.URLRequest;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import mx.core.IToolTip;
   import mx.managers.ToolTipManager;

   import items.Item_Base;
   import utils.geom.Dual_Rect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.base.Map_Layer;
   import views.base.UI;
   import views.map_widgets.Item_Sprite;

   public class Tile extends Item_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tile');

      // *** Mandatory attributes

      public static const class_item_type:String = 'tile';
      //public static const class_gwis_abbrev:String = 'tile';
      //public static const class_item_type_id:int = Item_Type.TILE;

      // *** Other static variables

      protected static var tiles_resident:Set_UUID = new Set_UUID();

      // Show a tooltip on mouse over.
      protected static var tooltip:IToolTip;

      // So that the conf file can contain user-friendly x,y pairs,
      // we make the code make the code-friendly rectangles (x,y,wdh,hgt).
      protected static var photo_layers_inited:Boolean = false;

      // *** Instance variables

      public var rect:Dual_Rect;

      protected var zoom_level:int;
      protected var xi:int;
      protected var yi:int;

      protected var url:String;
      protected var image:Loader;
      protected var layer_name:String;
      protected var tilename:String;
      protected var is_aerial:Boolean;

      protected var bbox_map_:Rectangle;

      // Like Geofeature, this class manages its own sprite

      public var sprite:Item_Sprite;

      protected var show_dev_tooltips:Boolean = false;
      protected var tooltip_timer:Timer;
      // The last mouse over event, needed for tooltip coords.
      protected var last_mouse_over:MouseEvent;

      // *** Constructor

      public function Tile(xi:int,
                           yi:int,
                           is_aerial:Boolean,
                           aerial_layer:Object=null)
      {
         super();

         this.xi = xi;
         this.yi = yi;
         this.is_aerial = is_aerial;
         this.zoom_level = G.map.zoom_level;

         this.rect = new Dual_Rect();
         this.rect.map_min_x = Tile.tileindex_to_coord(xi);
         this.rect.map_max_y = Tile.tileindex_to_coord(yi + 1);
         this.rect.cv_width = Conf.tile_size;
         this.rect.cv_height = Conf.tile_size;
         this.bbox_map_ = this.bbox_map_compute();

         this.image = new Loader();

         this.sprite = new Item_Sprite(this);
         this.sprite.addChild(this.image);

         // DEVS: Point wms_url_base at the server if you want to use the
         //       server's tiles. Otherwise, leave it blank and we'll fetch
         //       tiles from the same server as your Cyclopath installation.
         var wms_url:String = '';
         if (Conf.wms_url_base !== null) {
            wms_url = Conf.wms_url_base; // E.g., '' or 'http://localhost:8088'
         }
         else if (G.url_base !== null) {
            wms_url = G.url_base; // E.g., 'http://ccpv3'
         }
         else {
            m4_WARNING('Tile: No base url??');
         }

         var image_format:String;
         if (!is_aerial) {
            m4_ASSURT(aerial_layer === null);
            // The layer name specifies the instance, branch, and skin name.
            var branch_sid:String;
            try {
               branch_sid = String(G.item_mgr.active_branch.stack_id);
            }
            catch (e:TypeError) {
               // Error #1009: Cannot access a property or method of a null
               //              object reference.
               // If GWIS_Branch_Names_Get fails on bootstrap (e.g., because
               // user's token is bad and user needs to log off and log on
               // again), then G.item_mgr.active_branch is null.
               // MAGIC_NUMBER: Meaningless.
               branch_sid = 'XXXXXXX';
            }
            // CcpV1: this.layer_name = Conf.instance_name;
            // SYNC_ME: See tilecache_update.py (it calls tilecache_seed.py)
            //          and mapserver/tilecache.cfg.
            this.layer_name = Conf.instance_name
                              + '-'
                              + branch_sid
                              + '-'
                              // BUG nnnn: Support skinning. I.e., make
                              // other skins and make dropdown on user
                              // settings panel.
                              // MAGIC_NUMBER: See skins/skin_bikeways.py
                              + 'bikeways';
            image_format = 'image/png';
            wms_url += Conf.wms_url_cyclopath; // E.g., '/tilec?'
         }
         else {
            this.setup_aerial_layer(aerial_layer);
            image_format = 'image/jpeg';
            wms_url = Conf.wms_url_aerial; // E.g., 'http://geoint...'
         }

         this.url = (
            wms_url
            + '&SERVICE=WMS'
            + '&VERSION=1.1.1'
            + '&REQUEST=GetMap'
            + '&LAYERS=' + this.layer_name
            + '&SRS=EPSG:' + Conf.srid
            + '&BBOX=' + (  Tile.tileindex_to_coord(xi) + ','
                          + Tile.tileindex_to_coord(yi) + ','
                          + Tile.tileindex_to_coord(xi + 1) + ','
                          + Tile.tileindex_to_coord(yi + 1))
            + '&WIDTH=' + Conf.tile_size
            + '&HEIGHT=' + Conf.tile_size
            + '&FORMAT=' + image_format);

         // Friendly name for Flash log, e.g. "aerial,nga2008,12,115,1220"
         this.tilename = (
            (this.is_aerial ? 'aerial' : 'ccpwms')
            + ',' + this.layer_name
            + ',' + this.zoom_level
            + ',' + this.xi
            + ',' + this.yi);

         if (Conf_Instance.debug_goodies) {
            // MAYBE: Make a checkbox...
            //this.show_dev_tooltips = true;
         }

         if (this.show_dev_tooltips) {
            this.tooltip_timer = new Timer(Conf.byway_tooltip_time, 1);
            this.tooltip_timer.addEventListener(TimerEvent.TIMER,
                                                this.on_tooltip_timer,
                                                false, 0, true);
         }
      }

      // *** Static class methods

      //
      public static function cleanup_all() :void
      {
         if (Conf_Instance.recursive_item_cleanup) {
            var sprite_idx:int = -1;
            var skip_delete:Boolean = true;
            for each (var tile:Tile in Tile.tiles_resident) {
               tile.item_cleanup(sprite_idx, skip_delete);
            }
         }
         //
         Tile.tiles_resident = new Set_UUID();
      }

      // Return the tile index containing coordinate c at the current zoom
      // level. See the technical documentation for more information.
      public static function coord_to_tileindex(c:Number) :int
      {
         return int(c / meters_per_tile());
      }

      //
      public static function meters_per_tile() :Number
      {
         // Zoom 16 is 1:1 and the scale is 1. At Zoom 15, scale is 0.5;
         // at Zoom 17, scale is 2, etc.
         return (Conf.tile_size / G.map.scale);
      }

      //
      public static function tile_exists(tile:Tile) :Boolean
      {
         var exists:Boolean = false;
         for each (var t:Tile in Tile.tiles_resident) {
            if (t.equals(tile)) {
               exists = true;
               break;
            }
         }
         return exists;
      }

      // Return the coordinate of the smaller edge of the tile with index i.
      public static function tileindex_to_coord(i:int) :Number
      {
         return (i * Tile.meters_per_tile());
      }

      // *** Getters and setters

      //
      override public function get bbox_map() :Rectangle
      {
         return this.bbox_map_;
      }

      // *** Event listeners

      //
      protected function handler_complete(ev:Event) :void
      {
         m4_DEBUG('Tile fetched:', this.tilename);
         m4_ASSERT(!(Tile.tiles_resident.is_member(this)));
         if (this.zoom_level != G.map.zoom_level) {
            m4_DEBUG('Tile', this.tilename, 'ignored: wrong zoom level');
         }
         else if (this.is_aerial != G.map.aerial_enabled) {
            m4_DEBUG('Tile', this.tilename, 'ignored: wrong tile class');
         }
         else {
            this.sprite.x = this.rect.cv_min_x;
            this.sprite.y = this.rect.cv_min_y;
            G.map.tiles.addChild(this.sprite);
            Tile.tiles_resident.add(this);
         }
         this.listener_cleanup();
         UI.throbberers_decrement(this);

         if (this.show_dev_tooltips) {
            m4_DEBUG('item_cleanup: show_dev_tooltips: add listeners');
            this.sprite.addEventListener(MouseEvent.MOUSE_DOWN,
               this.on_mouse_down, false, 0, true);
            this.sprite.addEventListener(MouseEvent.MOUSE_OVER,
               this.on_mouse_over, false, 0, true);
            this.sprite.addEventListener(MouseEvent.MOUSE_OUT,
               this.on_mouse_out, false, 0, true);
         }
      }

      //
      protected function handler_ioerror(ev:IOErrorEvent) :void
      {
         m4_DEBUG('Loading tile', this.tilename, 'failed', '/ ', ev.text);
         // 2014.09.20: Happened at three times in the afternoon and once
         //             previously in the last month or so:
         //  Flex IOErrorEvent Error #2036: Load Never Completed
         G.sl.event('error/tiles/io',
            {url: this.url,
             tile: this.tilename,
             msg: ev.text // EXPLAIN: same as ev.errorID ?
             });
         this.listener_cleanup();
         UI.throbberers_decrement(this);
      }

      // *** Public instance methods

      //
      public function bbox_map_compute() :Rectangle
      {
         m4_ASSERT(G.map.zoom_level == this.zoom_level);
         return new Rectangle(this.rect.map_min_x,
                              this.rect.map_min_y,
                              (this.rect.map_max_x - this.rect.map_min_x),
                              (this.rect.map_max_y - this.rect.map_min_y));
      }

      // Removes the tile from the tile lookup, before the Tile is released
      override public function item_cleanup(
         i:int=-1, skip_delete:Boolean=false) :void
      {
         if (i == -1) {
            try {
               i = (G.map.tiles as Map_Layer).getChildIndex(this.sprite);
            }
            catch (e:ArgumentError) {
               // EXPLAIN: This might not really be worthy of a warning.
               //          This happens frequently, but [lb] not sure why.
               m4_WARNING('Tile sprite not found in layer:', this.tilename);
            }
         }
         super.item_cleanup(i, skip_delete);
         if (i != -1) {
            if (!skip_delete) {
               Tile.tiles_resident.remove(this);
            }
         }

         if (this.show_dev_tooltips) {
            m4_DEBUG('item_cleanup: show_dev_tooltips: remove listeners');
            this.sprite.removeEventListener(MouseEvent.MOUSE_DOWN,
                                            this.on_mouse_down);
            this.sprite.removeEventListener(MouseEvent.MOUSE_OVER,
                                            this.on_mouse_over);
            this.sprite.removeEventListener(MouseEvent.MOUSE_OUT,
                                            this.on_mouse_out);
         }
      }

      //
      public function equals(tile:Tile) :Boolean
      {
         m4_ASSERT(tile !== null);
         // Using layer_name is a bit hacky:
         //   'image/png'  is 3rd-party aerial photo
         //   'image/jpeg' is Cyclopath TileCache-generated image
         return (   (this.layer_name == tile.layer_name)
                 && (this.xi == tile.xi)
                 && (this.yi == tile.yi)
                 && (this.zoom_level == tile.zoom_level));
      }

      //
      public function fetch() :void
      {
         var req:URLRequest = new URLRequest(this.url);
         this.image.contentLoaderInfo.addEventListener(
            Event.COMPLETE, handler_complete);
         this.image.contentLoaderInfo.addEventListener(
            IOErrorEvent.IO_ERROR, handler_ioerror);
         m4_DEBUG('Tile fetch:', this.tilename, req.url);
         this.image.load(req);
         // NOTE Fetching tiles always causes the throbber to run
         UI.throbberers_increment(this);
      }

      //
      protected function listener_cleanup() :void
      {
         // Remove listeners since we're not using weak references
         this.image.contentLoaderInfo.removeEventListener(
            Event.COMPLETE, handler_complete);
         this.image.contentLoaderInfo.removeEventListener(
            IOErrorEvent.IO_ERROR, handler_ioerror);
      }

      // ***

      //
      public function on_mouse_down(ev:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_down');
         if (this.show_dev_tooltips) {
            this.tooltip_display(false);
            this.tooltip_timer.stop();
         }
      }

      //
      public function on_mouse_over(evt:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_over');
         // Begin the timer to show a tooltip at the location of evt
         if (this.show_dev_tooltips) {
            this.last_mouse_over = evt;
            this.tooltip_timer.reset();
            this.tooltip_timer.start();
         }
      }

      //
      public function on_mouse_out(evt:MouseEvent) :void
      {
         m4_DEBUG('on_mouse_out');
         if (this.show_dev_tooltips) {
            this.tooltip_display(false);
            this.tooltip_timer.stop();
         }
      }

      //
      public function on_tooltip_timer(evt:TimerEvent) :void
      {
         m4_DEBUG('on_tooltip_timer');
         if (this.show_dev_tooltips) {
            this.tooltip_display(true);
         }
      }

      //
      protected function tooltip_display(on:Boolean) :void
      {
         m4_DEBUG('tooltip_display');

         if (on) {
            m4_ASSERT(this.last_mouse_over !== null);

            // Remove existing tooltip.
            if (Tile.tooltip !== null) {
               ToolTipManager.destroyToolTip(Tile.tooltip);
            }

            // Assemble a dev-friendly message.
            var tt:String;
            tt = 
               'Tile: '
               + 'zoom_level: ' + String(this.zoom_level)
               + ' (' + String(this.xi) + ', ' + String(this.yi) + ')'

               // E.g., "minnesota-2500677-bikeways"
               + '\nlayer: ' + this.layer_name

               // E.g., "ccpwms,minnesota-2500677-bikeways,9,14,151"
               //+ '\ntilename: ' + this.tilename

               // E.g., "(x=458752, y=4947968, w=32768, h=32768)"
               + '\nbbox_map_: ' + this.bbox_map_.toString()

               //+ '\nurl: ' + this.url
               + '\nurl: see log file'
               ;

            m4_DEBUG('tooltip_display: tt:', tt);
            m4_DEBUG('tooltip_display: url:', this.url);

            // Show the tooltip at the last mouse event.
            var tx:Number = this.last_mouse_over.stageX;
            var ty:Number = this.last_mouse_over.stageY;
            Tile.tooltip = ToolTipManager.createToolTip(tt, tx, ty);
         }
         else {
            // hide and destroy the tooltip if it is visible
            if (Tile.tooltip !== null) {
               ToolTipManager.destroyToolTip(Tile.tooltip);
            }
            Tile.tooltip = null;
         }

         // clear last mouse over event
         this.last_mouse_over = null;
      }

      //

      //
      protected function setup_aerial_layer(aerial_layer:Object) :void
      {
         m4_ASSURT(aerial_layer !== null);
         m4_VERBOSE('setup_aerial_layer: _name:', aerial_layer._name);
         if (aerial_layer._name !== null) {
            m4_DEBUG2('setup_aerial_layer: using specific layer:',
                      aerial_layer._name);
            this.layer_name = aerial_layer._name;
         }
         else {
            // If _name is null, layers is set, and we should auto-pick the
            // layer based on the tile coordinates. If all four corners of
            // the tile are contained within one of a layer's bboxes, we'll
            // find a photo image using that layer, otherwise we should try
            // another layer.
            Tile.ensure_photo_layers_inited();
            var lobj:Object;
            for each (lobj in aerial_layer.layers) {
               if (this.enclosed_by(this.rect, lobj.rrects)) {
                  m4_DEBUG2('setup_aerial_layer: found matching layer:',
                            lobj._name);
                  this.layer_name = lobj._name;
                  break;
               }
            }
            if (!this.layer_name) {
               m4_DEBUG2('setup_aerial_layer: no matching layer; using last:',
                         lobj._name);
               this.layer_name = lobj._name;
            }
         }
      }

      //
      protected function enclosed_by(drect:Dual_Rect, rrects:Array) :Boolean
      {
         var all_enclosed:Boolean = true;

         var x:int;
         var y:int;

         m4_VERBOSE('enclosed_by: drect:', drect.toString());

         for (var i:int = 0; i < 4; i++) {

            // i/2 vals: 0=>0, 1=>0, 2=>1, 3=>1
            //x = drect.cv_min_x + (drect.cv_width * (i/2)); // canvas
            x = (i/2) ? drect.map_min_x : drect.map_max_x; // map

            // i%2 vals: 0=>0, 1=>1, 2=>0, 3=>1
            //y = drect.cv_min_y + (drect.cv_height * (i%2)); // canvas
            y = (i%2) ? drect.map_min_y : drect.map_max_y; // map

            m4_VERBOSE('enclosed_by: i:', i, '/ x:', x, '/ y:', y);

            var pt_enclosed:Boolean = false;
            for each (var lrect:Rectangle in rrects) {
               m4_VERBOSE('enclosed_by: lrect:', lrect.toString());
               if (lrect.contains(x, y)) {
                  pt_enclosed = true;
                  break;
               }
            }
            if (!pt_enclosed) {
               all_enclosed = false;
               break;
            }
         }

         return all_enclosed;
      }

      //
      protected static function ensure_photo_layers_inited() :void
      {
         // The values in Conf_Instance are the lower-left and upper-right
         // coordinates of the rectable, but we use Rectangles, and those
         // work on the lower-left coordinates and a width and height.
         if (!Tile.photo_layers_inited) {
            for each (var oobj:Object in Conf.photo_layers) {
               if (oobj._name === null) {
                  for each (var iobj:Object in oobj.layers) {
                     var new_bboxes:Array = new Array();
                     for each (var xy_pair:Array in iobj.bboxes) {
                        var rect:Rectangle = new Rectangle(
                           xy_pair[0][0], // x
                           xy_pair[0][1], // y
                           xy_pair[1][0] - xy_pair[0][0],  // width
                           xy_pair[1][1] - xy_pair[0][1]); // height
                        new_bboxes.push(rect);
                     }
                     iobj.rrects = new_bboxes;
                  }
               }
            }
            Tile.photo_layers_inited = true;
         }
      }

   }
}


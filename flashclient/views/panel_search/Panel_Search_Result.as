/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Search Result object

// FIXME: This file is named wrong, it's not a Panel...

package views.panel_search {

   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.geom.Point;
   import flash.utils.Dictionary;
   import mx.controls.Alert;
   import mx.utils.StringUtil;

   import items.utils.Item_Type;
   import utils.geom.Dual_Rect;
   import utils.geom.Geometry;
   import utils.geom.MOBRable_DR;
   import utils.misc.Logging;
   import utils.misc.Map_Label;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.base.Paint;

   public class Panel_Search_Result extends Sprite implements MOBRable_DR {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@Pnl_SearchR');

      // FIXME: Is this lookup really needed?
      // SYNC_ME: Search text search vect types.
      protected static var ts_vects:Set_UUID = null;

      // *** Object attributes

      // The name and geofeature type id of this result.

      public var gf_name:String;
      public var gf_type_id:int;
      // FIXME: We hardcode item type strings in the code, so if Item_Type
      //        changes, search usages of gf_type_str.
      // SYNC_ME: Search: Item_Type table.
      public var gf_type_str:String;

      // For byway type results, multiple byways may have been grouped into one
      // result; their geometries and other unique details are stored in this
      // lookup. For other geofeature type results, this collection just has
      // one member, since other geofeature type results are not grouped.
      // Each object in the array specifies the geofeature's stack_id, x, and
      // y, and sometimes geometry (e.g., waypoints have x, y, but no geometry)

      protected var locs:Array;

      // The include and exclude lookups indicate which query parts matched.

      public var includes:Dictionary;
      public var excludes:Dictionary;

      // View-related members. The letter (A through J (i.e., 10 results/page))
      // is drawn in a circle (geo_sprite) on the map in one of two colors
      // (depending on highlighted).

      public var letter:String;
      public var geo_sprite:Sprite;
      // If the user is mousing over the search result list entry and we should
      // highlight the geofeature on the map.
      public var highlighted:Boolean;

      // *** Constructor

      public function Panel_Search_Result(xml:XML = null)
      {
         var xml_doc:XML;

         this.locs = new Array();

         this.includes = new Dictionary();
         this.excludes = new Dictionary();

         this.letter = '';
         this.geo_sprite = new Sprite();
         this.highlighted = false;

         Panel_Search_Result.ts_vects_init();

         if (xml !== null) {

            //m4_DEBUG('Panel_Search_Result: xml:', xml.toXMLString());

            this.gf_name = xml.@gf_name;
            this.gf_type_id = int(xml.@gf_type_id);
            this.gf_type_str = Item_Type.id_to_str(this.gf_type_id);

            m4_TALKY('Panel_Search_Result: gf_name:', this.gf_name);

            // E.g., <ts_in all="0" addr="0" ... />
            //       <ts_ex all="0" addr="0" ... />

            // NOTE: xml.@* same as xml.attributes()
            for each (xml_doc in xml.ts_in.@*) {
               // NOTE: This following fails:
               //          this.includes[xml_doc.name()] = 'foo';
               //       "ReferenceError: Error #1056: Cannot create property
               //        @all on flash.utils.Dictionary."
               //       Because name() returns a QName. We want just a String.
               m4_ASSERT2(
                  Panel_Search_Result.ts_vects.is_member(xml_doc.localName()));
               // This is weird: if you get the doc itself, you get its value.
               this.includes[xml_doc.localName()] = Boolean(int(xml_doc));
               if (this.includes[xml_doc.localName()]) {
                  m4_TALKY(' >> includes:', xml_doc.localName());
               }
            }
            for each (xml_doc in xml.ts_ex.@*) {
               m4_ASSERT2(
                  Panel_Search_Result.ts_vects.is_member(xml_doc.localName()));
               this.excludes[xml_doc.localName()] = Boolean(int(xml_doc));
               if (this.excludes[xml_doc.localName()]) {
                  m4_TALKY(' >> excludes:', xml_doc.localName());
               }
            }
            // Should give same results as:
            /*
            for each (var vect:String in Panel_Search_Result.ts_vects) {
               this.includes[vect] = Boolean(int(xml.ts_in.@[vect]));
               this.excludes[vect] = Boolean(int(xml.ts_ex.@[vect]));
            }
            */

            //m4_DEBUG('xml.gf_item.@*:', xml.gf_item.@*);
            for each (xml_doc in xml.gf_item) {
               //m4_DEBUG2('xml_doc: stack_id:', xml_doc.@stack_id,
               //          '/ x:', xml_doc.@x, '/ y:', xml_doc.@y);
               // FIXME: Don't care about stack_id?
               var o:Object = new Object();
               var xs:Array = new Array();
               var ys:Array = new Array();
               o.x = Number(xml_doc.@x);
               o.y = Number(xml_doc.@y);
               var coord_str:String = xml_doc.@geometry;
               if (coord_str != '') {
                  Geometry.coords_string_to_xys(coord_str, xs, ys);
                  //m4_DEBUG2('Panel_Search_Result: coords_string_to_xys:',
                  //          coord_str, '/ xs:', xs, '/ ys:', ys);
               }
               else {
                  //m4_DEBUG('Panel_Search_Result: o.x:', o.x, '/ o.y:', o.y);
                  xs.push(o.x)
                  ys.push(o.y)
               }
               //m4_DEBUG('xs:', xs, '/ ys:', ys);
               if ((xs.length > 0) && (ys.length > 0)) {
                  o.xs = xs
                  o.ys = ys
                  // So: o has members: x, y, xs, ys
                  // FIXME: Make this a real class?
                  this.locs.push(o);
               }
               else {
                  m4_ERROR2('Panel_Search_Result: missing xs and ys:',
                            'xml_doc:', xml_doc.toString());
                  m4_ASSERT_SOFT(false);
               }
            }
            m4_ASSERT_SOFT(this.locs.length > 0);
         }
      }

      //
      public static function ts_vects_init() :void
      {
         if (Panel_Search_Result.ts_vects === null) {
            ts_vects = new Set_UUID();
            ts_vects.add('all' );
            ts_vects.add('addr');
            ts_vects.add('name');
            ts_vects.add('hood');
            ts_vects.add('tag' );
            ts_vects.add('note');
            ts_vects.add('post');
            Panel_Search_Result.ts_vects = ts_vects
         }
      }

      // *** Getter and Setters

      // returns the coordinates of the letter label.
      public function get label_coords() :Point
      {
         var ctr_point:Point;
         var loc:Object = this.closest_to_center();
         if (loc !== null) {
            ctr_point = new Point(loc.x, loc.y);
         }
         return ctr_point;
      }

      //
      [Bindable] public function get list_text() :String
      {
         var list_text:String = this.letter + '. ' + this.gf_name;
         if (this.locs.length > 1) {
            list_text += ' (' + this.locs.length + ' blocks)';
         }
         else if ((this.locs.length == 1) && (this.gf_type_str == 'byway')) {
            list_text += ' (' + this.locs.length + ' block)';
         }
         return list_text;
      }

      // NOTE: This function is required for binding without warnings
      public function set list_text(s:String) :void
      {
      }

      //
      public function get mobr_dr() :Dual_Rect
      {
         var loc:Object;
         var dr:Dual_Rect;
         var x:Number;
         var y:Number;
         var minx:Number = Number.POSITIVE_INFINITY;
         var miny:Number = Number.POSITIVE_INFINITY;
         var maxx:Number = Number.NEGATIVE_INFINITY;
         var maxy:Number = Number.NEGATIVE_INFINITY;
         var i:int;

         for each (loc in this.locs) {
            for (i = 0; i < loc.xs.length; i++) {
               x = Number(loc.xs[i]);
               y = Number(loc.ys[i]);
               minx = Math.min(minx, x);
               miny = Math.min(miny, y);
               maxx = Math.max(maxx, x);
               maxy = Math.max(maxy, y);
            }
         }

         dr = new Dual_Rect();
         dr.map_min_x = minx; // left
         dr.map_max_y = maxy; // top
         dr.map_max_x = maxx; // right
         dr.map_min_y = miny; // bottom

         m4_DEBUG('mobr_dr: dr:', dr);

         return dr;
      }

      // *** Geometry helpers

      // Return the object that is closest to the center of this collection
      // of results.
      protected function closest_to_center() :Object
      {
         var dr:Dual_Rect = this.mobr_dr;
         var dist:Number = Number.POSITIVE_INFINITY;
         var new_dist:Number;
         var loc:Object;
         var obj:Object = null;
         for each (loc in this.locs) {
            new_dist = Math.sqrt(
               Math.pow(loc.y - (dr.map_max_y + dr.map_min_y) / 2, 2)
               + Math.pow(loc.x - (dr.map_max_x + dr.map_min_x) / 2, 2));
            if (new_dist < dist) {
               dist = new_dist;
               obj = loc;
            }
         }
         m4_ASSERT_SOFT(obj !== null);
         return obj;
      }

      //
      public function draw() :void
      {
         var gr:Graphics = this.graphics;
         var geo_gr:Graphics;
         var startx:Number;
         var starty:Number;
         var label:Map_Label;
         var loc:Object;
         var color:int = Conf.search_result_color;
         var border_color:int = Conf.search_result_border_color;
         var radius:int = 8;

         if (this.highlighted) {
            color = Conf.search_result_highlighted_color;
            border_color = Conf.search_result_highlighted_border_color;
         }
         gr.clear();
         while (this.numChildren > 0) {
            this.removeChildAt(0);
         }

         loc = this.closest_to_center();
         if (loc !== null) {

            startx = G.map.xform_x_map2cv(loc.x);
            starty = G.map.xform_y_map2cv(loc.y);
            m4_ASSERT(!(isNaN(startx) || isNaN(starty)));

            // Draw a letter within a circle at the center of the result geom.
            gr.beginFill(color);
            gr.lineStyle(2, border_color);
            gr.drawCircle(startx, starty, radius);
            gr.endFill();
            label = new Map_Label(this.letter,
                                  Conf.search_result_letter_size,
                                  0,
                                  startx - 2,
                                  starty);
            this.addChild(label);

            // SYNC_ME: Search: Item_Type table.
            if ((this.gf_type_str == 'addy_coordinate')
                || (this.gf_type_str == 'addy_geocode')) {
               label = new Map_Label(this.gf_name,
                                     Conf.search_result_label_size,
                                     0,
                                     startx - 2,
                                     starty - 24);
               this.addChild(label);
            }
            else if ((this.gf_type_str == 'byway')
                     || (this.gf_type_str == 'region')) {
               // Draw geometry -- highlight the byway or region on the map to
               // indicate that it's associated with a search result.
               geo_sprite = new Sprite();
               geo_gr = geo_sprite.graphics;
               geo_gr.clear();
               for each (loc in this.locs) {
                  Paint.line_draw(geo_gr, loc.xs, loc.ys, radius, color);
               }
            }
            else if (!((this.gf_type_str == 'waypoint')
                       || (this.gf_type_str == 'terrain'))) {
               m4_WARNING('Unknown this.gf_type_str:', this.gf_type_str);
               m4_ASSERT_SOFT(false);
            }
         }
      }

   }
}


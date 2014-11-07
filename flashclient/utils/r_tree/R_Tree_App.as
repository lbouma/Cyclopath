/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This program controls the R-Tree demo/debugging app.

// FIXME 2010.11.23 Is this file still used?

package utils.r_tree {

   import mx.core.UIComponent;
   import flash.geom.Rectangle;
   import flash.events.MouseEvent;
   import mx.core.Application;
   import flash.display.Graphics;
   import flash.events.TimerEvent;
   import flash.net.LocalConnection;

   public class R_Tree_App extends UIComponent {

      public static const NEW_ENTRY:int = 1;
      public static const NEW_QUERY:int = 2;

      private var sX:Number;
      private var sY:Number;
      private var eX:Number;
      private var eY:Number;
      private var start_new_rect:Boolean;
      private var tree:R_Tree;
      public var gr:Graphics;
      private var rect_mode:int;
      private var selection:Array;

      public function R_Tree_App()
      {
         this.start_new_rect = true;
         this.tree = new R_Tree(2, 4);
         R_Tree.do_force_reinserts = false;
         this.selection = new Array();
         this.mode = NEW_ENTRY;
      }

      public function get mode() :int
      {
         return rect_mode;
      }

      public function set mode(m:int) :void
      {
         this.start_new_rect = true;
         this.rect_mode = m;
      }

      // We're using an R-Tree in canvas space, so the rectangle doesn't need
      // to be transformed any
      public function simple_trans(r:Rectangle) :Rectangle
      {
         return r;
      }

      public function clear_tree() :void
      {
         this.tree.clear();
         this.clear_selection();
      }

      public function delete_selection() :void
      {
         var i:int;
         for (i = 0; i < this.selection.length; i++)
            this.tree.remove(this.selection[i]);

         this.clear_selection();
      }

      public function clear_selection() :void
      {
         this.selection = new Array();
         this.gr.clear();
         this.tree.draw_tree(this.gr, simple_trans);
         this.start_new_rect = true;
      }

      public function build_random_tree() :void
      {
         this.clear_tree();
         var i:int;
         var r:_Rectangle;
         for (i = 0; i < 256; i++) {
            r = new _Rectangle();
            r.width = Math.random() * this.parent.width * .05;
            r.height = Math.random() * this.parent.height * .05;
            r.x = Math.random() * (this.parent.width - r.width);
            r.y = Math.random() * (this.parent.height - r.height);
            this.tree.insert(r);
         }
         this.gr.clear();
         this.tree.draw_tree(this.gr, this.simple_trans);
      }

      public function on_timer(evt:TimerEvent) :void
      {
         this.force_gc();
      }

      // an unsupported hack found on the web that supposedly causes a full gc
      public function force_gc() :void
      {
         try
         {
            var lc1:LocalConnection = new LocalConnection();
            var lc2:LocalConnection = new LocalConnection();
            lc1.connect('name');
            lc2.connect('name');
         } catch(e:Error) {}
      }

      public function on_mouse_down(evt:MouseEvent) :void
      {
         if (start_new_rect) {
            sX = evt.localX;
            sY = evt.localY;
            start_new_rect = false;
            this.gr.lineStyle(1, 0x6666dd);
            this.gr.drawRect(sX-1,sY-1,2,2);
         }
         else {
            eX = evt.localX;
            eY = evt.localY;

            var r:_Rectangle = new _Rectangle();
            var temp:Number;
            if (sX > eX) {
               temp = sX;
               sX = eX;
               eX = temp;
            }
            if (sY > eY) {
               temp = sY;
               sY = eY;
               eY = temp;
            }

            r.top = sY;
            r.bottom = eY;
            r.left = sX;
            r.right = eX;

            if (this.mode == NEW_ENTRY) {
               this.tree.insert(r);
            }
            else if (this.mode == NEW_QUERY) {
               this.selection = tree.query(r);
            }

            this.gr.clear();
            this.tree.draw_tree(this.gr, this.simple_trans);
            this.gr.lineStyle(1, 0xcc3333);
            this.gr.beginFill(0x000000, 0);
            this.gr.drawRect(sX, sY, eX-sX, eY-sY);

            var tc:Rectangle;
            var i:int;

            for (i = 0; i < selection.length; i++) {
               tc  = this.simple_trans(selection[i].mobr);
               gr.lineStyle(2, 0x33cc33);
               gr.drawRect(tc.x, tc.y, tc.width, tc.height);
            }

            this.start_new_rect = true;
            this.force_gc();
         }

      }
   }

}

import flash.geom.Rectangle;
import utils.geom.MOBRable;

class _Rectangle extends Rectangle implements MOBRable
{

   //
   public function get mobr() :Rectangle
   {
      return this;
   }

}


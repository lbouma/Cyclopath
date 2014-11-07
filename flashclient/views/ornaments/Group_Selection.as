/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.ornaments {

   import flash.display.Sprite;
   import flash.filters.GlowFilter;

   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Group_Selection extends Ornament {

      // *** Instance variables

      public var glows:Sprite;
      protected var lines:Sprite;
      protected var selections:Set_UUID;

      // *** Constructor

      public function Group_Selection()
      {
         super(null);

         this.glows = new Sprite();
         this.lines = new Sprite();
         this.addChild(this.glows);
         this.addChild(this.lines);

         this.selections = new Set_UUID();

         // This is the big blue oval around byways when you select 'em.
         this.glows.filters = [
            new GlowFilter(
               Conf.selection_color,
               .9, 4, 4, 12, 3,  // alpha, blurX, blurY, strength, quality
               true, true)       // inner, knockout
            ];
      }

      // *** Instance methods: Add/Remove

      //
      public function add(sel:Selection) :void
      {
         if (!(this.selections.is_member(sel))) {
            this.selections.add(sel);
            this.glows.addChild(sel.glow);
            this.lines.addChild(sel.line);
         }
      }

      //
      public function remove(sel:Selection) :void
      {
         if (this.selections.is_member(sel)) {
            this.selections.remove(sel);
            this.glows.removeChild(sel.glow);
            this.lines.removeChild(sel.line);
         }
      }

      // *** Instance methods: Draw

      //
      override public function draw() :void
      {
         var o:Selection;
         this.glows.graphics.clear();
         this.lines.graphics.clear();

         for each (o in this.selections) {
            o.draw();
         }
      }

   }
}


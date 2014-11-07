/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.section_launchers {

   import flash.display.DisplayObject;
   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.events.Event;

   import mx.controls.Button;
   import mx.events.IndexChangedEvent;
   import mx.events.PropertyChangeEvent;
   import mx.skins.ProgrammaticSkin;

   import utils.misc.Logging;

   public class Launcher_Skin extends ProgrammaticSkin {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@SctL_LncSkn');

      // *** Instance attributes

      protected var background_color:Number;
      protected var border_color:Number;
      protected var text_color:Number;
      protected var notch_visible:Boolean;

      // *** Instance methods

      // *** Constructor

      //
      public function Launcher_Skin()
      {
         super();
      }

      // ***

      // The is called on addChild.
      override protected function updateDisplayList(w:Number, h:Number) :void
      {
         var btn:Button = this.parent as Button;

         // MAYBE: We're being called a lot. But maybe that's how it works...
         // m4_DEBUG('updateDisplayList: this:', this);
         // m4_DEBUG('updateDisplayList: parent:', this.parent);
         // m4_DEBUG('updateDisplayList: w:', w, '/ h', h);

         // FIXME: Sometimes, when you quickly collapse the left panel after
         //        application load (basically before the panel has been opened
         //        for the first time ever), btn ends up being null.
         if (btn === null) {
            return;
         }

         btn.buttonMode = true;

         var g:Graphics = this.graphics;
         g.clear();

         g.beginFill(this.background_color, 1.0);
         g.lineStyle(1.0, this.border_color);
         g.drawRect(0, 0, w, h);
         g.endFill();

         // This is the little triangle guy that points at the active panel's
         // tab. Note that the mouse is active over this part of the button.
         if (this.notch_visible) {
            g.beginFill(this.background_color, 1.0);
            g.lineStyle(1.0, this.border_color);
            g.moveTo(w + 1, h/2);
            g.lineTo(w + 1 + G.app.pad, h/2 - G.app.pad + 2);
            g.lineTo(w + 1 + G.app.pad, h/2 + G.app.pad - 2);
            g.lineTo(w + 1, h/2);
            g.endFill();
         }
      }

   }
}


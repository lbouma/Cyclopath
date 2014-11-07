/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_util {

   import flash.events.Event;
   import mx.containers.VBox;
   import mx.effects.Fade;
   import mx.effects.Resize;
   import mx.events.EffectEvent;
   import mx.events.FlexEvent;
   import mx.events.ItemClickEvent;
   import mx.events.ResizeEvent;

   import utils.misc.Logging;

   public class Fadeawayable_VBox extends VBox {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#FdAwayablVB');

      // *** Instance variables

      // Fade effect to show/hide this component.
      protected var effect_fade:Fade;
      protected var effect_resize_fwd:Resize = new Resize();
      protected var effect_resize_rwd:Resize = new Resize();

      public var original_height:int = -1;

      // ***

      public function Fadeawayable_VBox()
      {
         super();
      }

      // ***

      //
      public function component_fade_away() :void
      {
         m4_DEBUG2('component_fade_away: height:', this.height,
                   '/ visible:', this.visible);

         if (this.visible) {

            this.original_height = this.height;

            var targets:Array = [this,];

            this.effect_fade = new Fade();
            this.effect_fade.targets = targets;
            this.effect_fade.duration = 750;
            if (false) {
               this.effect_fade.alphaFrom = 0.0;
               this.effect_fade.alphaTo = 1.0;
               this.visible = true;
               this.includeInLayout = true;
            }
            else {
               this.effect_fade.alphaFrom = 1.0;
               this.effect_fade.alphaTo = 0.0;
            }

            this.effect_fade.addEventListener(
               EffectEvent.EFFECT_END, this.on_effect_fade_end);

            m4_DEBUG('message_fade_away: starting fade');

            this.effect_fade.end();
            this.effect_fade.play();
         }
      }

      //
      protected function on_effect_fade_end(ev:EffectEvent) :void
      {
         m4_DEBUG('on_effect_fade_end: ev:', ev, '/ tgt:', ev.target);
         this.effect_fade.end();
         this.effect_fade.removeEventListener(
            EffectEvent.EFFECT_END, this.on_effect_fade_end);
         if ((ev.target as Fade).alphaTo == 0.0) {
            this.effect_resize_fwd.target = this;
            this.effect_resize_fwd.duration = 400;
            this.effect_resize_fwd.heightTo = 0;
            this.effect_resize_fwd.heightFrom = this.height;
            this.effect_resize_fwd.end();
            this.effect_resize_fwd.addEventListener(
               EffectEvent.EFFECT_END, this.on_effect_resize_fwd_end);
            this.effect_resize_fwd.play();
         }
         else {
            m4_ASSERT(false);
         }
         this.effect_fade = null;
      }

      //
      protected function on_effect_resize_fwd_end(ev:EffectEvent) :void
      {
         this.effect_resize_fwd.end();
         this.effect_resize_fwd.removeEventListener(
            EffectEvent.EFFECT_END, this.on_effect_resize_fwd_end);
         // Restore the alpha since the window is hidden and we don't fade
         // it in; we just show it when the user clicks the show link.
         this.alpha = 1.0;
         this.visible = false;
         this.includeInLayout = false;
      }

      // ***

      //
      public function component_fade_into(
         is_later:Boolean=false,
         force:Boolean=false,
         height:int=-1) :void
      {
         m4_DEBUG2('component_fade_into: this.height:', this.height,
                   '/ height:', height);
         if ((!is_later) && ((!this.visible) || (force))) {
            this.alpha = 0.0;
            this.visible = true;
            this.includeInLayout = false;
            if (height < 0) {
               this.percentHeight = 100;
            }
            else {
               this.height = height;
            }
            is_later = true;
            G.map.callLater(this.component_fade_into, [is_later,]);
         }
         else if (is_later) {
            m4_DEBUG2('component_fade_into: is_later: cntr. height:',
                      this.height);
            this.effect_resize_rwd.target = this;
            this.effect_resize_rwd.duration = 400;
            this.effect_resize_rwd.heightFrom = 0;
            if (height < 0) {
               this.effect_resize_rwd.heightTo = this.height;
            }
            else {
               this.effect_resize_rwd.heightTo = height;
            }
            this.alpha = 1.0;
            m4_DEBUG('component_fade_into: cntr_save_new_or_changes: show');
            this.visible = true;
            this.includeInLayout = true;
            this.height = 0;

            this.effect_resize_rwd.end();
            this.effect_resize_rwd.addEventListener(
               EffectEvent.EFFECT_END, this.on_effect_resize_rwd_end);
            this.effect_resize_rwd.play();
         }
         else {
            m4_DEBUG('component_fade_into: already faded in');
         }
      }

      //
      protected function on_effect_resize_rwd_end(ev:EffectEvent) :void
      {
         m4_DEBUG('on_effect_resize_rwd_end: this.height:', this.height);
         this.effect_resize_rwd.end();
         this.effect_resize_rwd.removeEventListener(
            EffectEvent.EFFECT_END, this.on_effect_resize_rwd_end);
         this.includeInLayout = true;
      }

   }
}


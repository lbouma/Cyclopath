/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets {

   import flash.display.GradientType;
   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.geom.Matrix;
   import flash.geom.Point;
   import flash.geom.Rectangle;

   import items.Geofeature;
   import items.feats.Byway;
   import items.links.Link_Geofeature;
   import items.utils.Item_Type;
   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Map_Label;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.map_widgets.tools.Tool_Pan_Select;

   /**
    * Selection_Resolver is a ui widget that controls selecting Geofeatures
    * on the map.  If multiple Geofeatures lie underneath a mouse click,
    * a menu appears offering the user a choice.  Otherwise the single feature
    * is selected automatically.
    */
   public class Selection_Resolver extends Sprite {

      // *** Class variables

      protected static var log:Logging = Logging.get_logger('Selctn_Rslvr');

      // *** Instance variables

      protected var resolver_active:Boolean; // true if processing a click
      protected var toggle:Boolean; // true if sel should be toggle on complete
      protected var candidates:Array; // all choices for selection

      protected var current_index:int;

      // canvas coord location of top-left corner
      protected var m_x:Number;
      protected var m_y:Number;
      protected var bg_rect:Rectangle;

      protected var bg:Sprite;
      protected var list:Sprite;

      public var last_candidate_count:int = 0;

      // *** Constructor

      public function Selection_Resolver()
      {
         super();

         this.bg = new Sprite();
         this.bg.mouseEnabled = false;

         this.current_index = -1;

         this.list = new Sprite();
         this.list.mouseEnabled = false;
         this.list.mouseChildren = false;

         this.addChild(this.bg);
         this.addChild(this.list);

         // install listeners
         this.addEventListener(MouseEvent.MOUSE_OVER, this.on_mouse_over,
                               false, 0, true);
         this.addEventListener(MouseEvent.MOUSE_MOVE, this.on_mouse_move,
                               false, 0, true);
         this.addEventListener(MouseEvent.MOUSE_OUT, this.on_mouse_out,
                               false, 0, true);
         // Bug 2776 - Flashclient: Mouse Up causes item selection
// FIXME: Should this be mouse up? And then we coordinate with Pan/Select?
         this.addEventListener(MouseEvent.CLICK, this.on_click,
                               false, 0, true);
      }

      // *** Instance methods

      // cancel any ongoing resolve
      public function reset_resolver() :void
      {
         m4_DEBUG('reset_resolver');
         if (this.resolver_active) {
            this.resolver_active = false;
            this.candidates = null;
            this.toggle = false;

            this.current_index = -1;

            this.m_x = 0;
            this.m_y = 0;
            this.bg_rect = null;

            this.graphics_clear();
            G.map.highlight_manager.set_layer_visible(Conf.resolver_highlight,
                                                      false);
         }
      }

      // Returns true if something was selected immediately
      public function do_resolve(ev:MouseEvent, two_plus:Boolean) :Geofeature
      {
         m4_DEBUG('do_resolve: ev:', ev.target);

         var the_one_item:Geofeature = null;

         this.last_candidate_count = 0;

         // FIXME: route reactions.
         //        In Geofeature.as you'll find, in on_click_maybe:
         //            if (G.map.rmode == Conf.map_mode_feedback) {
         //               ev.ctrlKey = false;
         //            }
         // but now we've got the double-click resolver...
         // and this code probably just prevents multi-selecting, right?
         // Verify the code works and then delete this comment.

         if (G.map.tool_cur is Tool_Pan_Select) {
            var tool:Tool_Pan_Select = (G.map.tool_cur as Tool_Pan_Select);
            // Tool_Pan_Select tool takes care of clearing selection.
            // If we're dragging, don't select, and if shift is down, it's
            // the multi-item-selector tool handling the event.
            if ((!tool.dragging) && (!tool.shift_down)) {
               // circumstances allow for a selection
               the_one_item = this.resolver_init(ev, tool, two_plus);
            }
            //m4_DEBUG('do_resolve: calling stopPropagation');
            //ev.stopPropagation();
         }
         m4_ASSERT_ELSE_SOFT;

         return the_one_item;
      }

      // *** Event listeners

      //
      protected function on_click(ev:MouseEvent) :void
      {
         m4_DEBUG3('on_click: target:', ev.target,
                   '/ active:', this.resolver_active,
                   '/ no. candidates:', this.candidates.length);

         if (this.resolver_active) {
            var index:int = this.index(ev.localX, ev.localY);
            if ((index >= 0) && (index < this.candidates.length)) {
               this.resolver_complete(this.candidates[index]);
            }
            else {
               this.reset_resolver();
            }
         }
      }

      //
      protected function on_mouse_move(ev:MouseEvent) :void
      {
         var index:int;

         m4_VERBOSE('on_mouse_move', ev.target);

         if (this.resolver_active) {
            index = this.index(ev.localX, ev.localY);

            if (this.current_index != index) {
               this.bg_draw(index);
            }
            this.current_index = index;
         }
      }

      //
      protected function on_mouse_out(ev:MouseEvent) :void
      {
         m4_VERBOSE('on_mouse_out', ev.target);
         if (this.resolver_active) {
            this.bg_draw(-1); // clears highlighted entry
            this.current_index = -1;
            // Tell pan select to clear selection on mouse up
            G.map.tool_cur.void_next_clear = false;
         }
      }

      //
      protected function on_mouse_over(ev:MouseEvent) :void
      {
         m4_TALKY('on_mouse_over', ev.target);
         if (this.resolver_active) {
            // remind Tool_Pan_Select who's boss
            G.map.tool_cur.void_next_clear = true;
         }
      }

      // *** Other methods

      //
      protected function bg_draw(index:int) :void
      {
         m4_ASSERT(this.resolver_active);

         var g:Graphics = this.bg.graphics;
         var entry_size:Number = this.bg_rect.height / this.candidates.length;

         var grad:Matrix = new Matrix();
         g.clear();

         // primary background
         g.beginFill(0x999999, .8); // FIXME: choose better colors
         g.drawRect(this.bg_rect.x, this.bg_rect.y,
                    this.bg_rect.width, this.bg_rect.height);
         g.endFill();

         // fancier background behind Select? label
         grad.createGradientBox(this.bg_rect.width, entry_size, Math.PI / 2,
                                this.bg_rect.x, this.bg_rect.y - entry_size);
         g.lineStyle(1);
         g.lineGradientStyle(GradientType.LINEAR, [0xb5b8ba, 0x9c9fa0],
                             [1, 1], [0, 255], grad);
         g.beginGradientFill(GradientType.LINEAR, [0xffffff, 0xd4d4d4],
                             [1, 1], [0, 255], grad);
         g.drawRect(this.bg_rect.x, this.bg_rect.y - entry_size,
                    this.bg_rect.width, entry_size);
         g.endFill();

         G.map.highlights_clear(Conf.resolver_highlight);

         // background over selected entry
         if ((index >= 0) && (index < this.candidates.length)) {
            // make the gradient fit the entry box
            grad.createGradientBox(this.bg_rect.width, entry_size, Math.PI / 2,
                                   this.bg_rect.x,
                                   this.bg_rect.y + index * entry_size);

            g.lineStyle(1);
            g.lineGradientStyle(GradientType.LINEAR, [0x009dff, 0x0055b7],
                                [1, 1], [0, 255], grad);
            g.beginGradientFill(GradientType.LINEAR, [0xf7f7f7, 0xdbdbdc],
                                [1, 1], [0, 255], grad);
            g.drawRect(this.bg_rect.x, this.bg_rect.y + index * entry_size,
                       this.bg_rect.width, entry_size);
            g.endFill();

            this.candidates[index].set_highlighted(
                     true, Conf.resolver_highlight);
         }
      }

      //
      protected function graphics_clear() :void
      {
         G.map.highlights_clear(Conf.resolver_highlight);
         this.bg.graphics.clear();

         // list contains map-labels, so clearing just removes everything
         while (this.list.numChildren > 0) {
            this.list.removeChildAt(this.list.numChildren - 1);
         }
      }

      // mouse_x and mouse_y should be in canvas coordinates
      protected function index(mouse_x:Number, mouse_y:Number) :int
      {
         m4_ASSERT(this.resolver_active);

         var entry_size:Number = this.bg_rect.height / this.candidates.length;

         if (   (mouse_x >= this.bg_rect.x)
             && (mouse_x <= this.bg_rect.right)
             && (mouse_y >= this.bg_rect.y)
             && (mouse_y <= this.bg_rect.bottom)) {
            // inside the widget
            return int(Math.floor((mouse_y - this.bg_rect.y) / entry_size));
         }
         else {
            // outside of the widget, no index available
            return -1;
         }
      }

      // Resolve the clickable items under the mouse cursor. If there's
      // nothing, return nothing; if there's one item, return that; if there
      // are two or more items, ask the user to choose, and then return that.
      protected function resolver_init(
         ev:MouseEvent,
         tool:Tool_Pan_Select,
         two_plus:Boolean)
            :Geofeature
      {
         var one_selected:Geofeature = null;

         var features_added:Set_UUID = new Set_UUID();

         this.resolver_active = true;

         this.graphics_clear();

         // 2013.04.25: Added attachment_mode_*.
         this.toggle = ev.ctrlKey || G.map.attachment_mode_on;

         var results:Array;

         // Note re: getObjectsUnderPoint. This is weird. G.app.map_canvas says
         // only one item under the cursor: the top-most item. But using state
         // works just fine, or even G.app.
         //  Returns just the top-most item:
         //   results = G.app.map_canvas.getObjectsUnderPoint(stage_pt);
         //   results = G.app.map_canvas_print.getObjectsUnderPoint(stage_pt);
         //   results = G.app.map.getObjectsUnderPoint(stage_pt);
         //   results = G.map.getObjectsUnderPoint(stage_pt);
         //  [lb] also checked areInaccessibleObjectsUnderPoint which says no.
         results = this.stage.getObjectsUnderPoint(
                  new Point(ev.stageX, ev.stageY));
         m4_DEBUG('on_mouse_down: no. under mouse: stage:', results.length);

         // This fcn. is only called when a real item was clicked, because of
         // how the double-click detector works (it remembers the item that
         // flex was clicked, and then it waits to see if the user is double-
         // clicking, so this fcn. is called with the item that was clicked).
         var item_sprite:Item_Sprite = (ev.target as Item_Sprite);
         m4_ASSURT(item_sprite !== null);
         // Which means the item should have been found under the point...
         // unless the user clicked on the item and then moused away fast
         // and finished the double click elsewhere.
         var original_item:Object = item_sprite.item;
         m4_DEBUG('resolver_init: original_item:', original_item);
         // always add the event's target
         //results.push((ev.currentTarget as Item_Sprite).item);
         // 2011.03.26:
         var found_original:Object = null;

         for each (var o:Object in results) {

            var gf:Geofeature = (o as Geofeature);

            if ((gf === null) && (o is Shadow_Sprite)) {
               // o is not a Geofeature since gf is null; it's a Shadow_Sprite
               gf = (o as Shadow_Sprite).feature;
            }
            // else, gf is already a geofeature

            // Remember the selected Geofeature if it's not already remembered,
            // and if it's counterpart also isn't remembered
            // FIXME Why not remember if counterpart is remember?
            if ((gf !== null)
                && (gf.is_clickable)
                && (!features_added.is_member(gf))
                && (!features_added.is_member(gf.counterpart_gf))) {
               features_added.add(gf);
               m4_DEBUG('resolver_init: found gf', gf);
            }
            else {
               m4_DEBUG('resolver_init: not a gf:', o);
            }

            if (original_item === o) {
               found_original = o;
            }
            // EXPLAINED: There's one item less in the hit array in the mouse
            // down that Map_Tool handled just before the double-click timeout
            // fired and called us. And that item is... the mouseCatcher!
            // (So then, EXPLAIN: G.app.map_mousecatcher, Map_Mouse_Catcher:
            //  [lb] thinks it processes the mouse down mouse click and so
            //  it's part of the map at that point, but since this fcn. is
            //  called via a timeout callback, the mouse catcher is no longer
            //  part of the map.)
            // if (!Collection.array_in(o, tool.items_down_under)) {
            //    m4_DEBUG('resolver_init: not in items_down_under:', o);
            // }
         }

         if (found_original !== null) {
            m4_WARNING2('resolver_init: unexpected: found_orig already:',
                        found_original);
         }
         else {
            // See comments above about getObjectsUnderPoint. The item
            // that was originally clicked is the only one that map_canvas
            // returns, and though using stage returns a bunch more items,
            // stage omits the item that was originally clicked. So weird.
            if ((original_item.is_clickable)
                && (original_item.master_item === null)) {
               features_added.add(original_item);
            }
         }

         this.candidates = features_added.as_Array();
         //this.candidates.sortOn('z_level', Array.NUMERIC | Array.DESCENDING);
         this.candidates.sortOn(['z_level', 'sprite_order',],
                                Array.NUMERIC | Array.DESCENDING);

         this.last_candidate_count = this.candidates.length;
         m4_DEBUG('resolver_init: no. candidates:', this.candidates.length);
         for each (var candidate_gf:Geofeature in this.candidates) {
            m4_DEBUG('resolver_init: .. candidate_gf:', candidate_gf);
         }

         // initially place widget to go towards the bottom right
         this.m_x = ev.localX + 10;
         this.m_y = ev.localY - 5;

         if ((!two_plus)
             && ((this.candidates.length == 1)
                 || ((this.candidates.length > 1)
                     && (!G.tabs.settings.always_resolve_multiple_on_click)
                     && (Item_Type.byways_all(this.candidates))))) {
            one_selected = (this.candidates[0] as Geofeature);
            this.resolver_complete(one_selected);
         }
         else {
            if (this.candidates.length > 0) {
               this.resolver_choose();
               if (two_plus) {
                  // This couples this class and Tool_Pan_Select but they're
                  // pretty tight as it is.
                  tool.handled_in_long_press = true;
               }
            }
            else {
               this.reset_resolver();
            }
         }

         return one_selected;
      }

      // complete the selection for the given object and reset everything
      protected function resolver_complete(feat:Geofeature) :void
      {
         var selected:Boolean = true;
         var nix_from_feat_panel:Boolean = false;
         var use_solo_panel:Boolean = false;
         var highlighted:Boolean = true;
         // This only makes sense if we're active.
         m4_ASSERT(this.resolver_active);
         // If we set this.toggle, it means the user had the ctrl key down,
         // i.e., ev.ctrlKey. If the item is already selected, we not only
         // deselect the item from the map, we also remove it from the panel's
         // items_selected list. Otherwise, if the item is not already
         // selected, we'll set it selected, and Geofeature.set_selected will
         // add the item to the active panel and add it to the map selection
         // set.
         if (this.toggle) {
            // Toggle the selection.
            selected = !feat.is_selected();
            highlighted = !feat.is_highlighted(Conf.attachment_highlight);
            // Maybe remove item from the active panel's items_selected list.
            if (!selected) {
               nix_from_feat_panel = true;
            }
            // else, item will be added to active panel.
         }
         else {
            // No ctrlKey modifier, so selected = true, and we want to use a
            // solo panel.
            use_solo_panel = true;
         }

         if (G.map.attachment_mode_on) {
            // Highlight or de-highlight the item.
            var success:Boolean = false;
            if (highlighted) {
               // Add it to the attachment_placebox.
               var link_gf:Link_Geofeature
                  = G.map.attachment_placebox.place_add_smart(feat.stack_id);
               if (link_gf !== null) {
                  success = true;
               }
            }
            else {
               // Remove from the attachment placebox.
               var removed:Array =
                  G.map.attachment_placebox.place_remove_smart(feat.stack_id);
               if (removed.length > 0) {
                  success = true;
               }
            }
            m4_TALKY2('resolver_complete: set_highlighted?:', success,
                      '/', feat);
            if (success) {
               feat.set_highlighted(highlighted, Conf.attachment_highlight);
            }
         }
         else {
            // Select or de-select the item.
            m4_TALKY3('resolver_complete: set_selected?:', selected,
                      '/ nix:', nix_from_feat_panel,
                      '/ solo:', use_solo_panel, '/', feat);
            feat.set_selected(selected, nix_from_feat_panel, use_solo_panel);
         }

         // Reset the selection resolver.
         this.reset_resolver();
      }

      // display a choice menu for users
      protected function resolver_choose() :void
      {
         var y_offset:Number = 0;
         var feature:Geofeature;
         var label:Map_Label;
         var text:String;

         m4_ASSERT(this.resolver_active);

         // build the list of feature names
         this.bg_rect = null;

         for each (feature in this.candidates) {

            text = feature.name_;
            if (text === null || text == '') {
               if (feature is Byway) {
                  text =
                     'Unnamed '
                     + Conf.tile_skin.feat_pens
                        [String(feature.geofeature_layer_id)]['friendly_name'];
               }
               else {
                  text = 'Unnamed Item'; // shouldn't happen often
               }
            }

            // shorten really long names to keep menu a reasonable size
            if (text.length > 25) {
               text = text.substring(0, 25) + '...';
            }

            label = new Map_Label(text, 12, NaN, this.m_x, this.m_y+y_offset);
            label.filters = null; // clear glow filter

            this.list.addChild(label);
            y_offset += (label.max_y - label.min_y);

            // determine size of the background
            if (this.bg_rect === null) {
               this.bg_rect = new Rectangle(label.min_x, label.min_y,
                                            label.max_x - label.min_x,
                                            label.max_y - label.min_y);
            }
            else {
               // merge rect with label's bbox
               this.bg_rect.x = Math.min(label.min_x, this.bg_rect.x);
               this.bg_rect.y = Math.min(label.min_y, this.bg_rect.y);

               this.bg_rect.right = Math.max(label.max_x, this.bg_rect.right);
               this.bg_rect.bottom = Math.max(label.max_y,
                                              this.bg_rect.bottom);
            }
         }

         // Add a title label, too.
         label = new Map_Label(
            'Select Which Item?', 12, NaN, this.m_x,
            this.m_y - this.bg_rect.height / this.candidates.length);
         label.filters = null;
         this.list.addChild(label);
         this.bg_rect.x = Math.min(label.min_x, this.bg_rect.x);
         this.bg_rect.right = Math.max(label.max_x, this.bg_rect.right);

         // Adjust label positioning if it would hit edges.
         if (this.bg_rect.right > G.map.view_rect.cv_max_x) {
            this.widget_translate(-this.bg_rect.width - 3, 0);
         }

         // HACK: Adjust max_y by -25 to account for Map_Key_Button widget.
         if (this.bg_rect.bottom > (G.map.view_rect.cv_max_y - 25)) {
            this.widget_translate(0, -this.bg_rect.height);
         }

         G.map.highlight_manager.set_layer_visible(Conf.resolver_highlight,
                                                   true);
         this.bg_draw(-1);
      }

      //
      protected function widget_translate(dx:Number, dy:Number) :void
      {
         var i:int;
         var label:Map_Label;
         var m:Matrix;

         this.bg_rect.x = this.bg_rect.x + dx;
         this.bg_rect.y = this.bg_rect.y + dy;

         for (i = 0; i < this.list.numChildren; i++) {
            label = this.list.getChildAt(i) as Map_Label;
            m = label.transform.matrix;
            m.translate(dx, dy);
            label.transform.matrix = m;
         }
      }

   }
}


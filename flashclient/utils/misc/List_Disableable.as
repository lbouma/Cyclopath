/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.display.DisplayObject;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.ui.Keyboard;
   import mx.core.ClassFactory;
   import mx.controls.List;
   import mx.controls.listClasses.IListItemRenderer;
   import mx.controls.listClasses.ListItemRenderer;
   import mx.events.ScrollEvent;
   import mx.events.ScrollEventDetail;
   import mx.events.ScrollEventDirection;

   public class List_Disableable extends List {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('_Ls_Disabble');

      // ***

      [Bindable] public var customClickHandler:Function = null;

      // *** Constructor

      public function List_Disableable()
      {
         super();
         // Replace the default dropdown item list renderer
         // with one that understands enabling and disabling
         this.itemRenderer = new ClassFactory(
            List_Item_Renderer_Disableable);
      }

      // *** Instance methods

      // Ignore mouse over when disabled
      override protected function mouseOverHandler(ev:MouseEvent) :void
      {
         if (item_disabled(ev)) {
            // No-op; disabled
         }
         else {
            super.mouseOverHandler(ev);
         }
      }

      // Ignore mouse down when disabled
      override protected function mouseDownHandler(ev:MouseEvent) :void
      {
         m4_DEBUG('mouseDownHandler');
         if (item_disabled(ev)) {
            // No-op; disabled
         }
         else {
            super.mouseDownHandler(ev);
         }
      }

      // Ignore mouse up when disabled
      override protected function mouseUpHandler(ev:MouseEvent) :void
      {
         m4_DEBUG('mouseUpHandler');
         if (item_disabled(ev)) {
            // No-op; disabled
         }
         else {
            super.mouseUpHandler(ev);
         }
      }

      // Ignore mouse click when disabled
      override protected function mouseClickHandler(ev:MouseEvent) :void
      {
         m4_TALKY3('mouseClickHandler: customClickHandler:',
                   ((this.customClickHandler !== null)
                    ? this.customClickHandler : 'null'));
         var item:IListItemRenderer = this.resolve_clicked_item(ev);
         if (item !== null) {
            super.mouseClickHandler(ev);
            // The item clicked is enabled. If the item is not already the
            // selected item, the List super class will dispatch a listEvent.
            // But if the item is already selected, and the dropdown is not
            // active, we want to make sure it's active.
            if (this.customClickHandler !== null) {
               this.customClickHandler(item.data);
            }
         }
         // else, item is disabled, so ignore click.
      }

      // Ignore double click when disabled
      override protected function mouseDoubleClickHandler(ev:MouseEvent)
         :void
      {
         m4_DEBUG('mouseDoubleClickHandler');
         if (item_disabled(ev)) {
            // Prevent double click default
            ev.preventDefault();
         }
         else {
            super.mouseDoubleClickHandler(ev);
         }
      }

      //
      override protected function keyDownHandler(ev:KeyboardEvent) :void
      {
         // 2013.05.30: [lb] is so amusingly surprised that this worked:
         // for the longest time, we just hacked away and spaghettied our
         // way to the object that cared when the used mouse clicked while
         // the combobox dropdown was open:
         //    if (G.app.tool_palette.handle_on_dropdown_key_down(ev)) { }
         // which of course breaks every rule in the book: first and foremost,
         // this is a utility class, so hard-coding a reference to a view
         // component defined at application level is, well, laughable. haHA!
         // It's also Bad Form on Every Other Level. Anyway, here's a New Hack,
         // Not The Same as the Old Hack.
         // FYI, You'll get a ReferenceError if your parent ownerer doesn't
         // define this fcn. But currently we're just Combo_Box_V2's
         if (this.parentDocument.handle_on_dropdown_key_down(ev)) {
            m4_DEBUG('keyDownHandler: calling stopPropagation');
            ev.stopPropagation();
         }
         else {
            m4_DEBUG('keyDownHandler: passing event to parent');
            super.keyDownHandler(ev);
         }
      }

      //
      private function item_disabled(ev:MouseEvent) :Boolean
      {
         var disabled:Boolean = false;
         var item:IListItemRenderer = mouseEventToItemRenderer(ev);
         if ((item !== null)
             && (item.data !== null)
              && (((item.data is XML) && (item.data.@enabled == 'false'))
                  || (item.data.enabled == false)
                  || (item.data.enabled == 'false'))) {
            m4_TALKY('item_disabled: yup');
            disabled = true;
         }
         else {
            m4_TALKY('item_disabled: not');
            disabled = false;
         }
         return disabled;
      }

      //
      protected function resolve_clicked_item(ev:MouseEvent)
         :IListItemRenderer
      {
         var disabled:Boolean = false;
         var item:IListItemRenderer = mouseEventToItemRenderer(ev);
         if ((item !== null)
             && (item.data !== null)
              && (((item.data is XML) && (item.data.@enabled == 'false'))
                  || (item.data.enabled == false)
                  || (item.data.enabled == 'false'))) {
            m4_DEBUG('resolve_clicked_item: not enabled: item:', item);
            item = null;
         }
         else {
            m4_DEBUG2('resolve_clicked_item: yes enabled: item:',
                      ((item !== null) ? item : '(null)'));
         }
         return item;
      }

      // ***

      /*/

      //
      override public function createItemEditor(colIndex:int, rowIndex:int)
         :void
      {
         super.createItemEditor(colIndex, rowIndex);
         m4_DEBUG2('destroyItemEditor: colIndex:', colIndex,
                   '/ rowIndex:', rowIndex);
         if (this.itemEditorInstance !== null) {
            DisplayObject(this.itemEditorInstance).addEventListener(
               KeyboardEvent.KEY_DOWN, editor_key_down_handler);
         }
      }

      //
      override public function destroyItemEditor() :void
      {
         super.destroyItemEditor();
         m4_DEBUG('destroyItemEditor');
         if (this.itemEditorInstance !== null) {
            DisplayObject(this.itemEditorInstance).removeEventListener(
               KeyboardEvent.KEY_DOWN, editor_key_down_handler);
         }
      }

      //
      protected function editor_key_down_handler(event:KeyboardEvent) :void
      {
         m4_DEBUG('editor_key_down_handler: keyCode:', event.keyCode);
      }

      /*/

      // ***

      // 2013.04.12: Some updates from
      //    https://github.com/baonhan/DisabledOptionComboBox

      /*/

      // adjust keyboard behaviour to prevent selecting disabled items
      override protected function moveSelectionVertically(code:uint,
                                                          shiftKey:Boolean,
                                                          ctrlKey:Boolean):void
      {
         var rowCount:int = listItems.length;
         var onscreenRowCount:int = listItems.length
                                    - offscreenExtraRowsTop
                                    - offscreenExtraRowsBottom;
         var partialRow:int =
            (rowInfo[rowCount - offscreenExtraRowsBottom - 1].y
             + rowInfo[rowCount - offscreenExtraRowsBottom - 1].height
             > listContent.heightExcludingOffsets - listContent.topOffset)
            ? 1 : 0;

         var i:int;
         var expectedNewIndex:int;
         var newIndex:int = caretIndex;

         switch (code) {

            case Keyboard.UP: {
               // check if there is any enabled element above selected element
               for (i = caretIndex - 1; i >= 0; i--) {
                  if (!rowItemDisabled(i)) {
                     newIndex = i;
                     break;
                  }
               }
               break;
            }

            case Keyboard.DOWN: {
               for (i = caretIndex + 1; i < rowCount; i++) {
                  if (!rowItemDisabled(i)) {
                     newIndex = i;
                     break;
                  }
               }
               break;
            }

            case Keyboard.PAGE_UP: {
               if ((caretIndex > verticalScrollPosition)
                   && (caretIndex
                       < verticalScrollPosition + onscreenRowCount)) {
                  expectedNewIndex = verticalScrollPosition;
               }
               else {
                  // paging up is really hard because we don't know how many
                  // rows to move because of variable row height.  We would
                  // have to double-buffer a previous screen in order to get
                  // this exact so we just guess for now based on current
                  // rowCount
                  expectedNewIndex =
                     Math.max(caretIndex
                              - Math.max(onscreenRowCount - partialRow, 1), 0);
               }
               // check if this row is enabled. if not, try next row below that
               // until it reaches the current row
               for (i = expectedNewIndex; i < caretIndex; i++) {
                  if (!rowItemDisabled(i)) {
                     newIndex = i;
                     break;
                  }
               }
               // if there is no enabled below the expected index
               if (newIndex == caretIndex) {
                  // try to see if there is any enabled row above that
                  for (i = expectedNewIndex - 1; i >= 0; i--) {
                     if (!rowItemDisabled(i)) {
                        newIndex = i;
                        break;
                     }
                  }
               }

               break;
            }

            case Keyboard.PAGE_DOWN: {
               // if the caret is on-screen, but not at the bottom row
               // just move the caret to the bottom row (not partial row)
               if ((caretIndex >= verticalScrollPosition)
                   && (caretIndex < verticalScrollPosition
                                    + onscreenRowCount - partialRow - 1)) {
                  expectedNewIndex = verticalScrollPosition
                                     + onscreenRowCount
                                     - partialRow - 1;
               }

               // move up it the expected row is disabled
               for (i = expectedNewIndex; i > caretIndex; i--) {
                  if (!rowItemDisabled(i)) {
                     newIndex = i;
                     break;
                  }
               }

               // move down if there is still no enabled row
               if (newIndex == caretIndex) {
                  for (i = expectedNewIndex + 1; i < rowCount; i++) {
                     if (!rowItemDisabled(i)) {
                        newIndex = i;
                        break;
                     }
                  }
               }

               break;
            }

            case Keyboard.HOME: {
               for (i = 0; i < caretIndex; i++) {
                  if (!rowItemDisabled(i)) {
                     newIndex = i;
                     break;
                  }
               }
               break;
            }

            case Keyboard.END: {
               for (i = collection.length - 1; i > caretIndex; i--) {
                  if (!rowItemDisabled(i)) {
                     newIndex = i;
                     break;
                  }
               }
               break;
            }
         }

         // now move it
         var distance:int;
         if (newIndex > caretIndex) {
            distance = newIndex - caretIndex;
            for (i = 0; i < distance; i++) {
               super.moveSelectionVertically(Keyboard.DOWN, shiftKey, ctrlKey);
            }
         }
         else {
            distance = caretIndex-newIndex;
            for (i = 0; i < distance; i++) {
               super.moveSelectionVertically(Keyboard.UP, shiftKey, ctrlKey);
            }
         }

      }

      // disable finding an item in the list based on a String
      override public function findString(str:String):Boolean
      {
         return false;
      }

      //
      protected function rowItemDisabled(index:int):Boolean
      {
         var rowItems:Array = listItems[index] as Array;
         var item:IListItemRenderer = rowItems[0];
         if (itemDisabled(item)) {
            return true;
         }
         return false;
      }

      /*/

   }
}


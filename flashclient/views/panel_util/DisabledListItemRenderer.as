/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Based on: https://github.com/baonhan/DisabledOptionComboBox

/* NOTE: Added 2014.04.12, but this is basically a duplicate of
   List_Item_Renderer_Disableable.as, which is used by the
   Combo_Box_V2 control, albeit Combo_Box_V2 sets
      this.itemRenderer = new ClassFactory(List_Item_Renderer_Disableable);
   and DisabledComboBox sets it via MXML
      <mx:itemRenderer>
         <mx:Component>
            <components:DisabledListItemRenderer/>
         </mx:Component>
      </mx:itemRenderer>
*/

package views.panel_util {

	import mx.controls.listClasses.ListItemRenderer;
   import mx.core.IToolTip;
   import mx.events.ToolTipEvent;

   import utils.misc.Logging;

	public class DisabledListItemRenderer extends ListItemRenderer {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('DisabledLsIR');

      // ***

      //
		override protected function updateDisplayList(unscaledWidth:Number,
                                                    unscaledHeight:Number)
                                                      :void
      {
         //m4_DEBUG('_DisplayList: w:', unscaledWidth, 'h: ', unscaledHeight);

         if (this.data !== null) {
            if ((this.data.enabled !== null)
                && (this.data.enabled == false)) {
               this.enabled = false;
               this.setStyle('disabledColor', '0x888888');
            }

            // The toolTip obscures the list item. Unless we override
            // toolTipShowHandler. So weird.
            this.toolTip = this.data.toolTip;
         }
         else {
            // Hmmm... this.data is null and nothing appears the matter...
            //   m4_ASSERT_SOFT(false);
         }

			super.updateDisplayList(unscaledWidth, unscaledHeight);
		}


      //
      override protected function toolTipShowHandler(event:ToolTipEvent) :void
      {
         // STRANGE: The default position of the toolTip is fine, but if we
         // call the base class, it puts it right under the cursor, completely
         // covering the ComboCox item, so you cannot see the row at all.
         // Weird. But simply not calling the parent seems to work fine....
         // See also: flex/frameworks/projects/framework/src/mx/controls/
         //             listClasses/ListItemRenderer.as
         /*/ 
         m4_DEBUG('toolTipShowHandler: event:', event);
         var toolTip:IToolTip = event.toolTip;
         m4_DEBUG4('toolTipShowHandler/1: toolTip.x:', toolTip.x,
                   '/ y:', toolTip.y,
                   '/ w:', toolTip.width,
                   '/ h:', toolTip.height);
         // Don't call. It messes up placement:
         //    super.toolTipShowHandler(event);
         m4_DEBUG4('toolTipShowHandler/2: toolTip.x:', toolTip.x,
                   '/ y:', toolTip.y,
                   '/ w:', toolTip.width,
                   '/ h:', toolTip.height);
         // Maybe correct the parent's placement?
         //  toolTip.move(toolTip.x + 100), toolTip.y);
         /*/
      }

	}
}


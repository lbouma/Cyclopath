/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class is added for Statewide UI. We're bucking the naming trend
// (Capitalized_Words_Separated_By_Underscores) and calling ourselves
// Multi_ToggleButtonBar to emphasize that we're derived from the Flex
// base class, ToggleButtonBar.

// NOTE: This class is not used.

// MAYBE: This class might fit better in the views.panel_util package.

package utils.misc {

   import mx.controls.Button
   import mx.controls.ToggleButtonBar
   import mx.core.mx_internal;

   use namespace mx_internal;

   // Simplified from:
   // http://tech.dir.groups.yahoo.com/group/flexcoders/message/56184
   //
   public class Multi_ToggleButtonBar extends ToggleButtonBar
   {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('_TgglBttnBar');

      // ***

      public function Multi_ToggleButtonBar() :void
      {
         super();
      }

      // Override ToggleButtonBar fcn.
      override protected function hiliteSelectedNavItem(index:int) :void
      {
         var child:Button;
         var selectedchild:Button;

         child = this.getChildAt(index) as Button;

         var selectedButtonTextStyleName:String =
            this.getStyle(selectedButtonTextStyleNameProp);

         child.getTextField().styleName = (
            selectedButtonTextStyleName ?
            selectedButtonTextStyleName :
            'activeButtonStyle');

         m4_DEBUG('hiliteSelectedNavItem: index:', index);
         child.invalidateDisplayList();
      }

   }
}


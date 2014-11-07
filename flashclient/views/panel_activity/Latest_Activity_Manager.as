/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class manages the 'Latest Activity' panel, which is a panel that
// contains three tab-panels: the Discussions panel, the Route Reactions
// panel, and the Recent Changes panel.

package views.panel_activity {

   import mx.controls.Alert;

   import utils.misc.Logging;

   public class Latest_Activity_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('LatAct_Mgr');

      // *** Instance attributes

      public var activities:Latest_Activity_Panels;

      // *** Constructor

      //
      public function Latest_Activity_Manager() :void
      {
         m4_DEBUG('Welcome to the Latest_Activity_Manager!');

         // We don't really need to register the activity_panel with the
         // Panel_Manager -- it's just used when something big happens to mark
         // all panels dirty, and since the activity_panel is now (in CcpV3) a
         // tab navigator, repopulate()d it is a no-op, essentially. But we
         // keep this code just for consistency.
         G.panel_mgr.panel_register(G.app.activity_panel);

         // Make a shortcut to the Latest Activity ToggleButtonBar/ViewStack.
         this.activities = G.app.activity_panel;
      }

   }
}


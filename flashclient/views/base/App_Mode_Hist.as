/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.base {

   import flash.filters.GlowFilter;

   import utils.misc.Logging;

   public class App_Mode_Hist extends App_Mode_Base {

      // Class attributes.

      protected static var log:Logging = Logging.get_logger('App_Mde_Hist');

      // *** Constructor

      //
      public function App_Mode_Hist()
      {
         this.name_ = 'Historic';
         this.glow_filters =
            [new GlowFilter(0x000000, 0.8, 32, 32, 2, 1, true),];

         // See App_Action for the complete list of App_Actions.
         // What Hist Mode doesn't use is commented out below.

         this.allowed = [

            // Map Operations
            App_Action.map_pan_zoom,
            //App_Action.item_edit,
            //App_Action.item_tag,
            //App_Action.item_annotate,
            //App_Action.byway_rate,

            // Discussions
            //App_Action.post_create,

            // Route Planning
            //App_Action.route_request,
            //App_Action.route_lib_view,
            //App_Action.route_hist_view,
            //App_Action.route_modify_new,
            //App_Action.route_modify_own,
            //App_Action.route_modify_all,
            //App_Action.route_print,
            //App_Action.route_edit,

            // Search
            App_Action.search_anything,

            // Item Watching and Subscriptions
            //App_Action.item_watcher_edit,

            // Settings
            App_Action.settings_edit,
         ];
      }

      // ***

      //
      override public function activate() :void
      {
         super.activate();
         G.app.main_toolbar.setup_viewing_or_editing(
            /*editing_okay=*/false,
            /*hide_options=*/null);
      }

   }
}


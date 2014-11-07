/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.base {

   import flash.events.Event;

   import utils.misc.Logging;
   import views.panel_activity.Latest_Activity_Manager;
   import views.panel_discussions.Discussions_Manager;
   import views.panel_discussions.Tab_Discussions_Posts;
   import views.panel_discussions.Tab_Discussions_Reactions;
   import views.panel_history.History_Manager;
   import views.panel_history.Panel_Recent_Changes;
   import views.panel_routes.Find_Route_Manager;
   import views.panel_search.Search_Manager;
   import views.panel_settings.Settings_Manager;

   public class Tab_Managers {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Tabs_Mgr');

      // *** The tab managers.
      //
      // This is really just a dumping ground for a bunch of singleton
      // class instances that manage the various panels.

      //
      public var route:Find_Route_Manager;

      // MEH: Discussions lives on the Latest Activity panel now, so combine
      //      these two managers?
      public var activity:Latest_Activity_Manager;
      public var discussions:Discussions_Manager;
      // Skipping: The History_Browser is part of activity.
      //           So is the route reactions panel.

      //
      public var search:Search_Manager;

      // The panels managed by these managers are not permanent in the tab bar,
      // but they are permanent in memory.
      public var settings:Settings_Manager;
      public var changes:History_Manager;

      // *** Constructor

      //
      public function Tab_Managers() :void
      {
         m4_DEBUG('Welcome to the Tab_Managers!');
      }

      // ***

      //
      public function init() :void
      {
         m4_DEBUG('Tab_Managers:init');
         this.route = new Find_Route_Manager();
         this.activity = new Latest_Activity_Manager();
         this.discussions = new Discussions_Manager();
         this.search = new Search_Manager();
         this.settings = new Settings_Manager();
         this.changes = new History_Manager();
      }

      // *** Convenience fcns.

      //
      public function get changes_panel() :Panel_Recent_Changes
      {
         return this.activity.activities.changes_panel;
      }

      //
      public function get discuss_panel() :Tab_Discussions_Posts
      {
         return this.activity.activities.general;
      }

      // //
      // public function get reactions_panel() :Tab_Discussions_Reactions
      // {
      //    return this.activity.activities.reactions;
      // }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.base {

   import utils.misc.Logging;

   public class App_Action {

      // Constants representing actions that are allowed/disallowed.

      // Map Operations
      public static const map_pan_zoom:String = 'map_pan_zoom';
      public static const item_edit:String = 'item_edit';
      public static const item_tag:String = 'item_tag';
      public static const item_annotate:String = 'item_annotate';
      public static const byway_rate:String = 'byway_rate';

      // Discussions
      public static const post_create:String = 'post_create';

      // Route Planning
      public static const route_request:String = 'route_request';
      public static const route_lib_view:String = 'route_lib_view';
      public static const route_hist_view:String = 'route_hist_view';
      public static const route_modify_new:String = 'route_modify_new';
      public static const route_modify_own:String = 'route_modify_own';
      public static const route_modify_all:String = 'route_modify_all';
      public static const route_print:String = 'route_print';
      public static const route_edit:String = 'route_edit';

      // Search
      public static const search_anything:String = 'search_anything';

      // Item Watching and Subscriptions
      public static const item_watcher_edit:String = 'item_watcher_edit';

      // Settings
      public static const settings_edit:String = 'settings_edit';

      // Cycloplan Tools
      // FIXME: Enumerate these.

   }
}


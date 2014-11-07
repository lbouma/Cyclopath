/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_search {

   import flash.events.MouseEvent;

   import utils.misc.Logging;

   public class Search_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Search_Mgr');

      // *** Constructor

      //
      public function Search_Manager() :void
      {
         m4_DEBUG('Welcome to the Search_Manager!');

         G.panel_mgr.panel_register(G.app.search_panel);
      }

      // *** Search panel

      //
      public function search_open() :void
      {
         G.panel_mgr.panel_activate(G.app.search_panel);
      }

      // All this does is open the search panel, type in the query in the box,
      // and fire the search in one step.
      public function search(query:String) :void
      {
         this.search_open();
         G.app.search_panel.search_input.text = query;
         G.app.search_panel.submit_query();
      }

   }
}


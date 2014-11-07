/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import flash.external.ExternalInterface;

   import gwis.GWIS_Route_Get_Saved;
   import items.feats.Route;
   import utils.misc.Logging;
   import views.base.UI;

   // Coupling alert: This whole class is very intimate with Panel_Routes_New.

   public class Find_Route_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@FndRtes_MGR');

      // This class used to be all static variables. It's now a regular object
      // class that gets instantiated, albeit probably just once. Flex makes
      // static classes 'easy' -- you don't have to prefix your static class
      // variable names with the class name. I [lb] am curious why Flex is this
      // lax, especially since the compiler doesn't complain if you make a
      // local variable with the same name as a global variable. In any case,
      // instantiable objects are more flexible that static class defintions,
      // and we avoid any issues with variable names and scope, and that's the
      // history of this class.
      // Addendum: This class was mostly just calling this.find_panel.blah in
      // most of its fcns., so those fcns. were moved to Panel_Routes_New. Ya
      // know, decoupling...

      // ***

      // We point find_panel at G.app.routes_panel.routes_new.
      public var find_panel_:Panel_Routes_New;

      protected var feedback_window:Route_Feedback_Popup;


      // *** Constructor

      public function Find_Route_Manager() :void
      {
         m4_DEBUG('Welcome to the Find_Route_Manager!');

         G.panel_mgr.panel_register(G.app.routes_panel);
      }

      // ***

      //
      public function get find_panel() :Panel_Routes_New
      {
         if (this.find_panel_ === null) {
            this.find_panel_ = G.app.routes_panel.routes_new;
         }
         return this.find_panel_;
      }

      //
      // Switch to the "find Route" panel.
      public function panel_routes_new_open(src:String) :void
      {
         // Called from main.mxml's init().
         this.find_panel.panel_routes_new_open(src);
      }

      // ***

      // Begin downloading the active route to a gpx file
      public function gpx_download_start(route:Route) :void
      {
         // MAYBE: Why can't we just write the route from the client?
         //        The Save GPX button is on the route cue sheet, so
         //        we've got all the steps and stops in the client already.
         var req:GWIS_Route_Get_Saved;
         m4_DEBUG('gpx_download_start: getting route from server:', route);
         req = new GWIS_Route_Get_Saved(
            route.stack_id,
            /*source=*/'routes_gpx',
            /*callback_okay=*/null,
            /*callback_fail=*/null,
            /*as_gpx=*/true,
            /*check_invalid=*/false,
            /*gia_use_sessid=*/route.unlibraried,
            /*get_steps_and_stops=*/true, // Client sets anyway b/c of as_gpx.
            /*compute_landmarks=*/route.show_landmarks);
         req.download_file('cyclopath.gpx');
      }

      // ***

      // Creates the popup browser window that displays the directions as html
      // text.
      public function printer_friendly_show(route:Route,
                                            original:Boolean=true) :void
      {
         // Panel_Item_Route_Details is our only caller and it sets
         //    original = ((this.route.alternate_steps === null)
         //                || this.conflict_old.selected)
         var dirs:String;
         dirs = original ? route.html_text : route.alternate_html_text;
         // Call htdocs/main.html::show_directions.
         ExternalInterface.call('show_directions', dirs);
      }

      // ***

      // Open the "Route Feedback" popup
      public function route_feedback_popup_open(route:Route) :void
      {
         if (this.feedback_window === null) {
            this.feedback_window = new Route_Feedback_Popup();
         }
         UI.popup(this.feedback_window, 'purpose');
         this.feedback_window.route = route;
         this.feedback_window.purpose.selectedIndex = 0;
         this.feedback_window.satisfaction.selection = null;
         this.feedback_window.comments.text = '';
      }

      // *** Deep Link callbacks

      //
      public function deep_link_single(deep_link_params:Object) :void
      {
         m4_DEBUG4('deep_link_single: deep_link_params.from_addr:',
                  deep_link_params.from_addr,
                  ' / deep_link_params.to_addr:',
                  deep_link_params.to_addr);

         this.find_panel.geocoded_clear();

         // set the start location

         // MEH: This is technically wrong (proper_address should be set
         //      be the resolver class once the address is resolved), but
         //      it's [lb]'s 2014.08.17 stopgap to get the homepage-to-route
         //      deep_link working.
         this.find_panel.beg_addr_resolver.addy_chosen.proper_address =
            deep_link_params.from_addr;

         this.find_panel.beg_addr_resolver.raw_addr_input.text =
            deep_link_params.from_addr;

         // set the destination

         // See comment about the last proper_address; this is a hack.
         this.find_panel.fin_addr_resolver.addy_chosen.proper_address =
            deep_link_params.to_addr;

         this.find_panel.fin_addr_resolver.raw_addr_input.text =
            deep_link_params.to_addr;

         this.panel_routes_new_open('deeplink');
         if (   (deep_link_params.auto_find !== null)
             && (deep_link_params.auto_find.toLowerCase() == 'true')
             && (deep_link_params.from_addr !== null)
             && (deep_link_params.to_addr !== null)) {
            // start searching
            this.find_panel.find_route_start();
         }
      }

      // This is for CcpV1-style links.
      public function deep_link_shared(deep_link_params:Object) :void
      {
         m4_DEBUG('deep_link_shared: deep_link_params:', deep_link_params);

         if (deep_link_params.id > 0) {
            G.item_mgr.deep_link_get(
               {'type': 'route',
                'link': deep_link_params.id});
         }
         else {
            m4_WARNING('deep_link_shared: unexpected deep_link_params');
         }
      }

   }
}


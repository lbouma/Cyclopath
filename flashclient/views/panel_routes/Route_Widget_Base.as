/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import flash.utils.getQualifiedClassName;
   import mx.core.Container;
   import mx.events.FlexEvent;

   import items.feats.Route;
   import utils.misc.Logging;
   import views.panel_base.Detail_Panel_Widget;

   public class Route_Widget_Base extends Detail_Panel_Widget {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@RteWdgtBase');

      // *** Instance variables

      // *** Constructor

      public function Route_Widget_Base()
      {
         super();
      }

      // *** Getters/Setters

      //
      public function get route() :Route
      {
         var the_route:Route = null;
         var route_panel:Panel_Item_Route = (this.dp as Panel_Item_Route);
         m4_VERBOSE('route: get route: route_panel:', route_panel);
         if (route_panel !== null) {
            the_route = route_panel.route;
            m4_VERBOSE('get route: the_route:', the_route);
         }
         else {
            m4_DEBUG('get route: no dp no route:', this);
         }
         return the_route;
      }

      //
      public function set route(rt:Route) :void
      {
         m4_ASSERT(false);
      }

   }
}


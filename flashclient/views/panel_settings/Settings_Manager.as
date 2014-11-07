/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class manages the so-called 'Side Panel'.

package views.panel_settings {

   import grax.Item_Manager;
   import utils.misc.Logging;
   import views.panel_watchers.Panel_Watchers;
   import views.section_toolbar.Map_Layer_Toggler;

   public class Settings_Manager {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Settings_Mgr');

      public var settings_panel:Panel_Settings;
      // The Item Watchers panel used to live under a tab in the settings
      // panel. The two panels have since been separated, but Item Watchers are
      // still a type of settings, and managing the panel here is easy since
      // it's similar to settings_panel.
      // MAYBE: Find a better place for this panel...
      public var watchers_panel:Panel_Watchers;

      //
      protected var _facils_visible:Boolean = Conf.map_default_show_facils;
      protected var _points_visible:Boolean = Conf.map_default_show_points;
      protected var _regions_visible:Boolean = Conf.map_default_show_regions;
      protected var _links_visible:Boolean = Conf.map_default_show_links;

      protected var _shade_by_rating:Boolean = true;

      // *** Constructor

      //
      public function Settings_Manager() :void
      {
         m4_DEBUG('Welcome to the Settings_Manager!');
         m4_ASSERT(G.tabs.settings === null);

         this.settings_panel = new Panel_Settings();
         this.settings_panel.settings_options = new Tab_Settings_Options();
         this.settings_panel.addChild(this.settings_panel.settings_options);
         //
         G.panel_mgr.panel_register(this.settings_panel);

         this.watchers_panel = new Panel_Watchers();
         //
         G.panel_mgr.panel_register(this.watchers_panel);
      }

      // *** Settings panel

      //
      public function get always_editing_cbox() :Boolean
      {
         return this.settings_panel.settings_options.always_editing_cbox
                .selected;
      }

      //
      public function set always_editing_cbox(do_enable:Boolean) :void
      {
         if (do_enable != this.always_editing_cbox) {
            this.settings_panel.settings_options.always_editing_cbox.selected
               = do_enable;
         }
      }

      //
      public function get always_resolve_multiple_on_click() :Boolean
      {
         var tso:Tab_Settings_Options = this.settings_panel.settings_options;
         return tso.always_resolve_multiple_on_click.selected;
      }

      //
      public function set always_resolve_multiple_on_click(do_enable:Boolean)
         :void
      {
         var tso:Tab_Settings_Options = this.settings_panel.settings_options;
         if (do_enable != this.always_resolve_multiple_on_click) {
            tso.always_resolve_multiple_on_click.selected = do_enable;
         }
      }

      //
      public function get byway_tooltips() :Boolean
      {
         return this.settings_panel.settings_options.byway_tooltips_cbox
                .selected;
      }

      //
      public function set byway_tooltips(do_enable:Boolean) :void
      {
         if (do_enable != this.byway_tooltips) {
            this.settings_panel.settings_options.byway_tooltips_cbox.selected
               = do_enable;
            // FIXME: If enabled, fetch notes.
            // FIXME: Toggle the layer display...
         }
      }

      //
      public function get close_panel_on_noselect() :Boolean
      {
         return this.settings_panel.settings_options.close_panel_on_noselect
                .selected;
      }

      //
      public function set close_panel_on_noselect(do_enable:Boolean) :void
      {
         if (do_enable != this.close_panel_on_noselect) {
            this.settings_panel.settings_options.close_panel_on_noselect.selected
               = do_enable;
         }
      }

      //
      public function get connectivity() :Boolean
      {
         return this.settings_panel.settings_options.connectivity_cbox
                .selected;
      }

      //
      public function set connectivity(do_enable:Boolean) :void
      {
         if (do_enable != this.connectivity) {
            this.settings_panel.settings_options.connectivity_cbox.selected
               = do_enable;
         }
      }

      //
      public function get multiselections_cbox() :Boolean
      {
         return this.settings_panel.settings_options.multiselections_cbox
                  .selected;
      }

      //
      public function set multiselections_cbox(do_enable:Boolean) :void
      {
         if (do_enable != this.multiselections_cbox) {
            this.settings_panel.settings_options.multiselections_cbox.selected
               = do_enable;
         }
      }

      //
      public function get facils_visible() :Boolean
      {
         return this._facils_visible;
      }

      //
      public function set facils_visible(do_enable:Boolean) :void
      {
         if (do_enable != this._facils_visible) {
            this._facils_visible = do_enable;
            //
            this.settings_panel.settings_options.bike_facil_vis.selected
               = do_enable;
            G.app.main_toolbar.map_layers.set_checked(
               Map_Layer_Toggler.map_layer_facils, do_enable);
            //
            Item_Manager.show_facils = do_enable;
         }
      }

      //
      public function get links_visible() :Boolean
      {
         return this._links_visible;
      }

      //
      public function set links_visible(do_enable:Boolean) :void
      {
         if (do_enable != this._links_visible) {
            this._links_visible = do_enable;
            //
            this.settings_panel.settings_options
               .gf_links_exist_highlight.selected = do_enable;
            G.app.main_toolbar.map_layers.set_checked(
               Map_Layer_Toggler.map_layer_links, do_enable);
            //
            Item_Manager.show_links = do_enable;
         }
      }

      //
      public function get points_visible() :Boolean
      {
         return this._points_visible;
      }

      //
      public function set points_visible(do_enable:Boolean) :void
      {
         if (do_enable != this._points_visible) {
            this._points_visible = do_enable;
            //
            this.settings_panel.settings_options.pt_vis.selected = do_enable;
            G.app.main_toolbar.map_layers.set_checked(
               Map_Layer_Toggler.map_layer_points, do_enable);
            //
            Item_Manager.show_points = do_enable;
         }
      }

      //
      public function get regions_visible() :Boolean
      {
         return this._regions_visible;
      }

      //
      public function set regions_visible(do_enable:Boolean) :void
      {
         if (do_enable != this._regions_visible) {
            this._regions_visible = do_enable;
            //
            this.settings_panel.settings_options.wr_vis.selected = do_enable;
            G.app.main_toolbar.map_layers.set_checked(
               Map_Layer_Toggler.map_layer_regions, do_enable);
            //
            Item_Manager.show_regions = do_enable;
            if (this._regions_visible) {
               G.map.update_viewport_items();
            }
         }
      }

      //
      public function get routes_clickable() :Boolean
      {
         return this.settings_panel.settings_options.opts_routes_clickable
                  .selected;
      }

      //
      public function set routes_clickable(do_enable:Boolean) :void
      {
         if (do_enable != this.routes_clickable) {
            this.settings_panel.settings_options.opts_routes_clickable.selected
               = do_enable;
         }
      }

      //
      public function get routes_hide_old() :Boolean
      {
         return this.settings_panel.settings_options.opts_routes_hide_old
                  .selected;
      }

      //
      public function set routes_hide_old(do_enable:Boolean) :void
      {
         if (do_enable != this.routes_hide_old) {
            this.settings_panel.settings_options.opts_routes_hide_old.selected
               = do_enable;
         }
      }

      //
      public function get route_color_picker() :int
      {
         return this.settings_panel.settings_options.route_color_picker
                  .selectedColor;
      }

      //
      public function set route_color_picker(color_picker_value:int) :void
      {
         if (color_picker_value != this.route_color_picker) {
            this.settings_panel.settings_options.route_color_picker
               .selectedColor = color_picker_value;
            m4_DEBUG2('route_color_picker: rte_color_picker.selectedColor:',
                      color_picker_value);
         }
      }

      //
      public function get route_geocoder_show_details() :Boolean
      {
         return this.settings_panel.settings_options
                  .route_geocoder_show_details.selected;
      }

      //
      public function set route_geocoder_show_details(do_show_details:Boolean)
         :void
      {
         if (do_show_details != this.route_geocoder_show_details) {
            this.settings_panel.settings_options
                  .route_geocoder_show_details.selected
               = do_show_details;
         }
      }

      //
      public function get shade_roads_by_rating() :Boolean
      {
         return this._shade_by_rating;
      }

      //
      public function set shade_roads_by_rating(do_enable:Boolean) :void
      {
         m4_DEBUG2('set shade_roads_by_rating: this.shade_roads_by_rating',
                   this.shade_roads_by_rating, '/ do_enable:', do_enable);
         if (do_enable != this.shade_roads_by_rating) {
            this._shade_by_rating = do_enable;
            //
            this.settings_panel.settings_options
               .gf_shade_roads_by_rating.selected = do_enable;
            if (G.map.zoom_is_vector()) {
               m4_DEBUG('set shade_roads_by_rating: geofeatures_redraw');
               G.map.geofeatures_redraw();
            }
         }
      }

      //
      public function get show_node_stack_ids_cbox() :Boolean
      {
         return this.settings_panel.settings_options.show_node_stack_ids_cbox
                  .selected;
      }

      //
      public function set show_node_stack_ids_cbox(do_enable:Boolean) :void
      {
         if (do_enable != this.show_node_stack_ids_cbox) {
            this.settings_panel.settings_options.show_node_stack_ids_cbox
               .selected = do_enable;
         }
      }

      //
      public function get show_item_stack_ids_cbox() :Boolean
      {
         return this.settings_panel.settings_options.show_item_stack_ids_cbox
                  .selected;
      }

      //
      public function set show_item_stack_ids_cbox(do_enable:Boolean) :void
      {
         if (do_enable != this.show_item_stack_ids_cbox) {
            this.settings_panel.settings_options.show_item_stack_ids_cbox
               .selected = do_enable;
         }
      }

      //
      public function get sticky_intersections() :Boolean
      {
         return this.settings_panel.settings_options.sticky_intersections
                  .selected;
      }

      //
      public function set sticky_intersections(do_enable:Boolean) :void
      {
         if (do_enable != this.sticky_intersections) {
            this.settings_panel.settings_options.sticky_intersections.selected
               = do_enable;
         }
      }

      // Skipping: From Tab_Settings_Options: CheckBox/ComboBox:
      //  map_sknnng_enable/map_sknnng_select
      //  panel_layout_enable/panel_layout_select
      //  aerial_cbox/aerial_layer
      //  alpha_slider

   }
}


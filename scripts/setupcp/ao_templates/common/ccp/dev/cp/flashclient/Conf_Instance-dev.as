/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* NOTE: This is a template file to make it easier to test on development
   machines. Copy this file to Conf_Instance.as and replace the URL of the
   instance you want to test with that of your local Apache installation.
   See the Object named config, below. */

package {

   import mx.collections.ArrayCollection;

   import utils.geom.Dual_Rect;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import views.map_components.instance_messages.*;

   public class Conf_Instance {

      // FIXME: Debugging...
      public static const debug_goodies:Boolean = false;
      public static const bug_0694_terr:Boolean = false;
      public static const bug_2077_grac:Boolean = false;
      public static const bug_2424_brcx:Boolean = false;
      // FIXME: Statewide UI
      public static const recursive_item_cleanup:Boolean = false;
      public static const panel_layout_enable:Boolean = false;

      // Bug 2714: Route Feedback Drag feature, circa 2012.
      public static const bug_2714_rtfb_drag:Boolean = false;
      public static const bug_2714_rtfb_link:String =
         'http://www.youtube.com/watch?v=qOL59OKtlOo';

      // Landmarks Experiment, circa 2013-4.
      public static var landmark_experiment_on:Boolean = true;

      // Cycloplan
      public static const metrocouncil_group_name:String =
         'Metc Bikeways 2012 Editors';
      public static const metrocouncil_cycloplan_url:String =
         'http://www.metrocouncil.org/Transportation/Planning/Transportation-Resources/Bicycle-System-Master-Study.aspx';

      // *** Static class variables

      protected static const welcome_text_base:String = 'Find bike routes that match the way you ride. Share your cycling knowledge with the community!';

      // *** 'Minnesota' instance

      [Embed(source="/assets/img/transit_logo_metrotransit.png")]
      public static const icon_transit_mn:Class;

      public static const config_mn:Object = {

         instance_name: 'minnesota',

         srid: 26915, // UTM Zone 15N

         // Historically, when Cyclopath loads for someone for the first time,
         // it centers on a place called "Burlington Pond" -- this puts both
         // downtowns within the viewport on 1024x768 monitor.
         //
         // Burlington Pond:
         //
         //   map_zoom: 11,
         //   map_center_x: 485572,
         //   map_center_y: 4979716,
         //
         // For Statewide, we want to show the whole state. This should also
         // make booting a little quicker, since we're grabbing raster tiles
         // instead of vector geometries and lots of item metadata.
         //
         // St. Cloud:
         //
         //    SELECT ST_AsText(ST_Centroid(gf.geometry))
         //    FROM _rg JOIN geofeature AS gf ON (gf.system_id = _rg.sys_id)
         //    WHERE nom = 'Saint Cloud';
         //
         map_zoom: 6,
         map_center_x: 408204,
         map_center_y: 5042758,

         // DEVS: Here are some other places to start at centered and zoomed.
         //
         // Downtown Minneapolis:
         //
         //   SELECT ST_AsText(geometry) FROM geofeature
         //      JOIN item_versioned USING (system_id)
         //      WHERE name = 'Gateway Fountain';
         //
         //   map_zoom: 16,
         //   map_center_x: 478931, // .745,
         //   map_center_y: 4981081, // .505,
         //
         // The meet up for the No Name:
         //
         //    SELECT ST_AsText(geometry) FROM geofeature
         //       JOIN item_versioned USING (system_id)
         //       WHERE name = 'Hennepin Bluffs Gazebo';
         //
         //   map_center_x: 480208,
         //   map_center_y: 4980957,
         //
         // Lake St. and Midtown Greenway
         //    Search, e.g.: ... map_center_x: 474145 / map_center_y: 4977153

         // WMS settings. This is just for tiles.
         //
         // - Leave empty for local tiles.
         wms_url_base: '',
         //
         // - Set to a mapped port (using ssh -L) for tiles on a remote box.
         //wms_url_base: 'http://localhost:8088',
         //
         // - Or just set to the server itself.
         //wms_url_base: 'http://my.production.server',

         // *** Aerial photos.
         //
         // We use tiles published by the State:
         //
         // www.mngeo.state.mn.us/chouse/wms/wms_image_server_layers.html
         // www.mngeo.state.mn.us/chouse/wms/wms_image_server_specs.html
         // http://geoint.lmic.state.mn.us/cgi-bin
         //         /wms?VERSION=1.3.0&SERVICE=WMS&REQUEST=GetCapabilities
         //
         wms_url_aerial: 'http://geoint.lmic.state.mn.us/cgi-bin/wms?',
         //
         // To use these tiles in OpenJump, Right-click Working, choose Open...
         // click WMS layer, add "http://geoint.lmic.state.mn.us/cgi-bin/wms?",
         // and choose Version: "1.3.0". On the next screen, you can add
         // higher-resolution metro tiles and lesser resolution State tiles.
         //
         // NOTE/MAGIC_NAME: The "_name" value is the MnGeo layer name.
         //
         // NOTE/MAGIC_NUMBERS: The "bboxes" is a list of rectangles'
         // coordinates. If the bbox of a tile being requested for a layer
         // isn't completely enclosed by the indicated bboxes, we'll know
         // the current layer doesn't have any or all of the tiles for the
         // current viewport (and if the user has left the auto-switch option
         // enabled, we can walk the list of aerial layers looking for a photo
         // layer that matches the current viewport).
         // CAVEAT: The MnGeo metadata indicates each layer's bbox, but the
         // bbox for the metro is an orthogonal rectangle, i.e., it's not a
         // simple rectangle, so the bbox includes areas that don't have tiles.
         // One work around is to check if a photo we received for the metro
         // layer is pure white, and then to re-request a tile for the state
         // layer, but that seems computationally and networkally wasteful,
         // and it also assumes we know how to work with a Flex Loader object
         // to determine if the image it contains is essentially blank. A
         // better work around is to just use a list of bboxes such that none
         // of the bboxes include any areas without photo tiles. To do this, I
         // [lb] loaded the aerial layer in OpenJump and then just drew a
         // handful of rectangular polygons to cover the aerial layer, and then
         // copied there coordinates here. Since MnGeo dates their layers, I
         // assume they won't be adding or removing photos, so we shouldn't
         // have to worry about maintaining the bboxes values (though we
         // will have to calculate them anew for each new layer that MnGeo
         // publishes in the future).
         //
         photo_layers: new ArrayCollection([
            { _name: null,
              label: '2012 Cities + 2013 State',
              layers: [
               {
                 _name: 'nga2012',
                 // The four bboxes are ordered large to small. If the viewport
                 // is in the heart of the metro, the spatial comparison will
                 // be able to short-circuit after checking the first bbox.
                 bboxes: [[[459500.1, 4941000.3,], [490999.8, 5024999.8,],],
                          [[450500.1, 4954500.0,], [510499.8, 4998000.0,],],
                          [[440000.0, 4954500.0,], [510499.8, 4984500.2,],],
                          [[459501.8, 4954500.0,], [501499.8, 5011500.0,],],],
                 rrects: null
               },
               {
                 _name: 'fsa2013',
                 bboxes: [[[187392.0, 766464.0,], [4808960.0, 5478912.0,],],],
                 rrects: null
               }]},
            { _name: 'nga2012', label: '2012 Twin Cities' },
            // EXPLAIN: The difference btw. layers "fsa2013" and "fsa2013cir"?
            { _name: 'fsa2013', label: '2013 Minnesota' },
            { _name: 'met10',   label: '2010 Twin Cities' },
            { _name: 'fsa2010', label: '2010 State low res.' },
            { _name: 'fsa2009', label: '2009 State low res.' },
            { _name: 'fsa2008', label: '2008 State low res.' },
            { _name: 'nga2008', label: '2008 Metro' },
            { _name: 'msp2006', label: '2006 Metro' },
            { _name: 'metro',   label: '2004 Metro' },
            { _name: 'fsa',     label: '2003 State low res.' },
            { _name: 'bw2000',  label: '2000 Metro medium res. b&w' },
            { _name: 'bw1997',  label: '1997 Metro medium res. b&w' },
            { _name: 'doq',     label: '1991-92 B&W Low-Res' },
         ]),

         // Multimodal configuration.
         transit_services: {
            'Minnesota': {_name: 'Metro Transit', icon: icon_transit_mn }
         },

         // ***

         // YOU_HAVE_BEEN_WARNED: This text is applied to a label, so make sure
         //                       you <br> appropriately, otherwise you'll clip
         //                       or get a horizontal scroll bar.
         // PARALLELISM: The hints and the examples match orderwise.
         address_example:
            //'<i>Hint:</i> ' +
            'Use addresses, intersections, and names. Examples:'
            + '<br/>'
            +     '<i>200 Union St SE Mpls</i>'
            +     ' | <i>Union St @ Washington Ave Mpls</i>'
            //+     ' | <i>Tin Man</i>'
            //+     ' / etc.'
            + '<br/>'
            ,

         welcome_popup: null,

         // Welcome text displayed in the help panel
         //welcome_text: ('Welcome to Cyclopath! ' + welcome_text_base)
         welcome_text: welcome_text_base
      }

      // *** 'Colorado' instance

      /*/

      public static const config_co:Object = {

         instance_name: 'colorado',

         srid: 26913, // UTM Zone 13N

         // Center on a place called "Indian Tree Golf Course" which puts
         // both Denver and Boulder within the viewport on 1024x768.
         map_zoom: 9,
         map_center_x: 492600,
         map_center_y: 4409200,

         // WMS settings
         wms_url_base: '',
         wms_url_aerial: '/tilec?', // These layers are cached by TileCache
         photo_layers: new ArrayCollection([
            {_name: 'UrbanArea', label: '2006 Color High-Res'},
            {_name: 'USGS2008',  label: '2008 Color Low-Res'},
         ]),

         transit_services: null,

         // ***

         address_example: 'address / intersection / point / region<br>e.g.,'
            + ' <i>1250 14th St., Denver, CO</i> or <i>Boulder</i>',

         welcome_popup: Splash_Colorado,

         //welcome_text: ('Welcome to Cyclopath Colorado! '
         //               + welcome_text_base)
         welcome_text: welcome_text_base
      }

      /*/

      public static const config:Object = {

         // == For the production server ==
         //
         // SYNC_ME: Search hostname.
         //'http://cycloplan.cyclopath.org': config_mn,
         // So that we don't screw up people's bookmarks to the old CcpV1.
         //'http://magic.cyclopath.org': config_mn,
         // Maybe if you have other instances running on the same machine,
         // using the same codebase. ([lb] would encourage one to use branches
         // or to use separate apache virtualhosts for each instance.)
         //'http://co.cyclopath.org': config_co,

         // == Examples for development machines ==
         //
         // Uncomment for local development:
         // , 'http://localhost': config_mn
         // Uncomment for intranet development:
         // , 'http://your-machine': config_mn
         // , 'http://your-machine.cs.umn.edu': config_mn
         // , 'http://your-machine.cs.umn.edu:8080': config_mn
         // Uncomment for remote development:
         // , 'http://localhost:8080': config_mn
         // For the test server:
         // , 'http://cp-test.cs.umn.edu': config_mn
         // , 'http://cp-test.cs.umn.edu:8080': config_co
         // For remotely testing the test server, i.e., if you
         //     'ssh -L 80080:localhost:80
         //          -L 80081:localhost:8080
         //          $CS_USERNAME@cp-test.cs.umn.edu':
         // , 'http://localhost:80080': config_mn
         // , 'http://localhost:80081': config_co
         //'http://localhost': config_mn,
         //'http://localhost:8080': config_mn,
         //'http://localhost:8081': config_mn,
         //'http://localhost:8082': config_mn,
         //'http://localhost:8083': config_mn,
         //'http://localhost:8084': config_mn,
         //'http://localhost:8085': config_mn,
         //'http://127.0.0.1': config_mn,
         //'http://127.0.0.1:8080': config_mn,
         //'http://127.0.0.1:8081': config_mn,
         //'http://127.0.0.1:8082': config_mn,
         //'http://127.0.0.1:8083': config_mn,
         //'http://127.0.0.1:8084': config_mn,
         //'http://127.0.0.1:8085': config_mn,
         //
         // This is for your dev machine.
         //'http://TARGETHOST()': config_mn,
         //'http://TARGETHOST().TARGETDOMAIN()': config_mn,
         //'http://TARGETHOST().TARGETDOMAIN():8081': config_mn,
         //'http://TARGETHOST().TARGETDOMAIN():8082': config_mn,
         //'http://TARGETHOST().TARGETDOMAIN():8083': config_mn,
         //'http://TARGETHOST().TARGETDOMAIN():8084': config_mn,
         //'http://TARGETHOST().TARGETDOMAIN():8085': config_mn,
         //'http://TARGETHOST().TARGETDOMAIN():HTTPD_PORT_NUM()': config_mn,

         // == For DEVs debugging via ssh -L ==
         //'http://localhost:8084': config_mn
         //'http://127.0.0.1:8084': config_mn
         //'http://ccp:8084': config_mn
         //'http://ccp.server.tld:8084': config_mn

         // DEVS: For Adobe Flash Builder (under Windows), you'll want, e.g.,:
         //'file:///C:/ccp/dev/cp/bin-debug/main.swf': config_mn,

         // The ccp URL is for the community developer virtual machine.
         'http://VIRTUAL_HOSTNAME()': config_mn
      }

      // Use null so that main.mxml deduces it from loaderInfo.url,
      // so that debugging the next release off the server works.
      // See:
     // http://wiki.grouplens.org/index.php/Cyclopath/Production_and_Deployment
      public static const url_base:String = null;
      //public static const url_base:String = 
      //   'http://TARGETHOST().TARGETDOMAIN():HTTPD_PORT_NUM()';
      // DEVS: Set the port (e.g., 8084) to your SSH -L mapped port
      //       of the remote pyserver.
      public static const url_base_if_file:String =
         'http://TARGETHOST().TARGETDOMAIN():8084';

      // *** Debug Logging Setup

      // Set the default log level for trace messages. Choose from:
      // 'VERBOSE', 'TALKY', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'.
      // You can override this for individuals modules.
      // See utils.misc.Logging.lookup_obj for more info.
      public static const debug_logging_level_default:String = 'DEBUG';
      public static const debug_logging_level_override:Boolean = false;
      public static const debug_loggers_enabled:Set_UUID =
         new Set_UUID([]);
         //new Set_UUID(['call_later',]);
         //new Set_UUID(['pixel_push',]);
         //new Set_UUID(['call_later', 'pixel_push',]);

      // Set this to the width of your preferred terminal or text editor: that
      // application which you'll use to tail or view the Flash logfile. For
      // long lines, the log facility uses this number to pretty-wrap lines.
      // If it's zero, the log facility won't wrap the output.
      // FIXME: I [lb] think this is wrong: this is the msg len, not the
      //        complete line len. Or maybe that's how this is suppose
      //        to work... but it differs from a similar setting in
      //        pyserver/CONFIG. If this is just the msg len, it should be
      //        renamed, maybe to debug_logging_col_width:int = 95;
      //public static var debug_logging_line_length_default:int = 95;
      public static var debug_logging_line_length_default:int = 190;

      // The logging version sets the style of trace messages
      //   0: Off       / No Logging
      //   1: Simple    / Just the log message
      //   2: New Style / Log msg., plus timestamp, level, and logger name
      public static const debug_logging_version:int = 2;

      // *** Other Debug Switches

      // Bug 2715: CcpV1's Alert.show often included the URL, but it's messy
      // (e.g., "The URL that failed was: http://ccpv2/gwis?rqst=item_names_get
      // &ityp=branch&gwv=3&browid=E9FCC615-9121-1720-EA6F-8F8BAAD59AC7
      // &sessid=F6CEAD55-3370-4EE8-144F-321BAD2629A7&body=yes") and it's not
      // useful or meaningful to users. But maybe some devs want to see it...
      public static const debug_alert_show_url:Boolean = false;

      // GWIS Request timeout (in seconds)
      //
      // DEVs: If you're connecting to a remote database or on a slow machine,
      // you might need a little more time to process GWIS requests.
      //
      // FIXME: 2011.06.28: Increasing to two minutes for multimodal. Just to
      //        be safe. We should see about resetting this back to 60 seconds.
      //  public static const gwis_timeout:int = 60;
      // FIXME: This is temporary: Retrieving links for leafy branches is slow.
      //        We need flashclient to checkout links based on stack IDs,
      //        rather than checking out links based on bbox.
      //  public static const gwis_timeout:int = 6000;
      // 2013.02.15: Trying 90 seconds. Maybe retreat to 60 eventually.
      // SYNC_ME: pyserver.conf.gwis_timeout and flashclient.Conf.gwis_timeout.
      //public static const gwis_timeout:int = 90;
      // Ok, ok, try 3 minutes.
      public static const gwis_timeout:int = 180;
      // [lb] uses this on his dev. mach., which is slower than the server:
      //public static const gwis_timeout:int = 900;
      // For Statewide, routes can take a while longer.
      public static const get_route_timeout:int = 900;

      // *** Static class methods

      //
      public static function get active_config() :Object
      {
         if (G.url_base in Conf_Instance.config) {
            return Conf_Instance.config[G.url_base];
         }
         else {
            // NOTE: can't use m4_ASSERT here since G.sl might not be init'd
            throw new Error('No config found for ' + G.url_base
                            + ' in Instance.as');
         }
      }

   }
}


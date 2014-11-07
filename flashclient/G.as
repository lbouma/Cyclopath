/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This class holds (as class attributes) some global variables.

package {

   import flash.utils.Dictionary;
   import flash.utils.getTimer;
   import mx.collections.ArrayCollection;
   import mx.controls.Alert;
   import mx.controls.ComboBox;
   import mx.utils.UIDUtil;

   import grax.Deep_Link;
   import grax.Grac_Manager;
   import grax.Item_Manager;
   import grax.User;
   import gwis.utils.Heartbeat;
   import gwis.utils.Log_S;
   import items.feats.Track;
   import utils.geom.Geometry;
   import utils.misc.Flash_Cookies;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import utils.misc.Throbber;
   import views.base.App_Mode_Edit;
   import views.base.App_Mode_Hist;
   import views.base.App_Mode_View;
   import views.base.Map_Canvas;
   import views.base.Panel_Manager;
   import views.base.Tab_Managers;

   public class G {

      // *** Static class variables

      // Reference to the base Application object.
      [Bindable] public static var app:main;

      // True if we are done initializing the application.
      // EXPLAIN: How is this used? I [lb] hooked more app startup events and I
      //          think this boolean isn't really needed anymore, since we do a
      //          better job of deliberately loading subsystems on bootup.
      public static var initialized:Boolean = false;

      // Reference to the global map object.
      public static var map:Map_Canvas;

      // App "modes".
      // 2013.05.07: See also Panel_Item_Versioned.is_action_actionable.
      //             App_Mode_* is [mm]'s and is_action_actionable is [lb]'s.
      //             They are similar but App_Mode_* applies more globally
      //             whereas is_action_actionable depends on what's selected.
      public static var edit_mode:App_Mode_Edit = new App_Mode_Edit();
      public static var hist_mode:App_Mode_Hist = new App_Mode_Hist();
      public static var view_mode:App_Mode_View = new App_Mode_View();

      // Global user object.
      public static var user:User;

      // Global object to manage group access control.
      public static var grac:Grac_Manager;

      // Global object to manage items.
      public static var item_mgr:Item_Manager;

      // Global object to manage the side panel panels.
      public static var panel_mgr:Panel_Manager;

      // Global object to manage the apps.
      public static var tabs:Tab_Managers;

      // Global object to manage deep links.
      public static var deep_link:Deep_Link;

      // The base URL of the SWF file (e.g. if SWF loaded from,
      // http://foo.com/main.swf, this is http://foo.com).
      public static var url_base:String;
      // If debugging on Windows, this is the local file:/// path.
      public static var file_base:String;

      // How many assertion failure exceptions thrown (to limit an explosion
      // of assertion failure windows).
      protected static var assertion_failures:int = 0;

      // Server log object.
      public static var sl:Log_S;

      // Heartbeat object.
      public static var heartbeat:Heartbeat;

      // Flash cookie object for logged-in user.
      public static var fcookies_user:Flash_Cookies;

      // Flash cookie object for anonymous tracking.
      public static var fcookies_anon:Flash_Cookies;

      // UUID for this browser profile, so we can anonymously track folks.
      public static var browid:String = null;

      // Random ID for this *instance* of flashclient app, so we can detect if
      // the user is running multiple clients and to track sessions better

      /* BUG nnnn: The session ID should come from the server, so it can be
                   checked, and validated (so two clients don't use the same,
                   though it is a GUID), and so client cannot spoof. */
      public static var sessid:String = UIDUtil.createUID();

      // Version checking.
      public static var version_major:String;
      public static var version_griped:Boolean = false;

      // Semi-protected.
      public static var semiprotect_griped:Boolean = false;

      // Enable point types.
      // FIXME: This var seems misplaced. See the Control_Panel mgr.
      public static var point_layers_enabled:Boolean = false;

      // Developer logging facility.
      public static var log:Logging;
      // Create a logger for special classes of logging. These loggers are
      // system-wide, as opposed to most loggers, which are class-specific.
      // NOTE See m4_DEBUG_CLLL; these all get replaced when Bug nnnn is
      // implemented, which gaits all CallLater calls through one function.
      public static var log_time:Logging = Logging.get_logger('==TIME.IT==');
      public static var log_clll:Logging = Logging.get_logger('=CALLLATER=');

      // Pointer to the throbber. Moved from G.app so that it can be placed
      // anywhere in the interface, but this will be the pointer to it.
      public static var throbber:Throbber;

      // *** Constructor

      public function G() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class methods

      //
      public static function alert_broke(ignore_goodies:Boolean=false) :void
      {
         m4_WARNING('FIXME: This feature is broken!');
         m4_WARNING(Introspect.stack_trace());
         if ((!Conf_Instance.debug_goodies) || (ignore_goodies)) {
            Alert.show(
               "Oops! The team is fixing this feature! "
               + "We'll have it working again soon...",
               'Broken Feature');
         }
      }

      // Return an index into the Conf.bearing angle classification array
      // based on the angle formed by (0,0) to (xdelta,ydelta).
      public static function angle_class_idx(xdelta:Number,
                                             ydelta:Number) :int
      {
         m4_VERBOSE('angle_class_idx: xdelta:', xdelta, '/ ydelta:', ydelta);
         return G.angle_class_id(Geometry.arctan(xdelta, ydelta));
      }

      // Return an index into the Conf.bearing angle classification array
      // based on the angle (0 to 360 degrees).
      public static function angle_class_id(angle:Number) :int
      {
         m4_VERBOSE('angle_class_id: angle:', angle);
         m4_ASSERT((angle < 360) && (angle >= 0));

         var i:int;
         for (i = 0; i < Conf.bearing.length; i++) {
            if (angle < Conf.bearing[i][Conf.max_angle]) {
               return i;
            }
         }

         m4_ASSERT(false);
         return 0;
      }

      // Return the cardinal abbreviation for the given angle.
      public static function angle_class_cabbrev(xdelta:Number,
                                                 ydelta:Number) :String
      {
         return Conf.bearing[G.angle_class_idx(xdelta, ydelta)][Conf.c_name];
      }

      // Set the given combobox to the item having attribute 'id' equal to
      // the given value. If none exists, set it to undefined.
      // NOTE: ComboBox.dataProvider is an Array of {id: n, label: ''} objects.
      public static function combobox_code_set(menu:ComboBox, id:*) :void
      {
         var i:int;
         var ac:ArrayCollection = (menu.dataProvider as ArrayCollection);

         //m4_INFO('ac:', ac, 'menu:', menu, 'dp:', menu.dataProvider);

         // Reset the ComboBox
         menu.selectedIndex = -1;
         menu.setStyle('fontStyle', 'normal');

         // Try to find a matching ID.
         for (i = 0; i < ac.length; i++) {
            //m4_DEBUG2('ac:', ac, 'i:', i, 'ac.getItemAt(i):',
            //          ac.getItemAt(i));
            if (id == ac.getItemAt(i).id) {
               menu.selectedIndex = i;
               break;
            }
         }

         //m4_DEBUG('combobox_code_set: selectedIndex:', menu.selectedIndex);

         // If the ID wasn't found and it's -1, it's a MAGIC NUMBER meaning
         // there was no consensus on what the value should be. So display
         // 'Varies'.
         // 2013.05.29: Deprecated. It is recommended that you use a
         //             Combo_Box_V2, whose textInput you can set to italic.
         //             This code makes not only the Combobox button text
         //             italic, but also all of the dropdown options. And
         //             textInput is protected, which is why you want to use
         //             Combo_Box_V2.textInput_.
         // if ((id == -1) || (id === null)) {
         //    // NOTE: This only does anything on basic combo boxes, i.e., 
         //    //       this has no effect on Combo_Box_V2 generally.
         //    //
         //    // BUG nnnn: I18N / L10N: Move to localization file.
         //    menu.text = 'Varies';
         //    // BUG nnnn: CSS: Move to style file?
         //    menu.setStyle('fontStyle', 'italic');
         // }
      }

      // Return the distance in canvas space, for two map points.
      public static function distance_cv(mx1:Number, my1:Number,
                                         mx2:Number, my2:Number) :Number
      {
         return Geometry.distance(G.map.xform_x_map2cv(mx1),
                                  G.map.xform_y_map2cv(my1),
                                  G.map.xform_x_map2cv(mx2),
                                  G.map.xform_y_map2cv(my2));
      }

      //
      public static function gui_starved(tstart:int) :Boolean
      {
         var starved:Boolean = false;
         if (tstart != 0) {
            starved = ((G.now() - tstart)
                       >= Conf.callLater_take_a_break_threshold_ms);
         }
         return starved;
      }

      //
      public static function map_from_xmllist(xl:XMLList, key:String,
                                              value:String) :Dictionary
      {
         var d:Dictionary = new Dictionary();
         var x:XML;

         for each (x in xl) {
            d[int(x.@[key])] = int(x.@[value]);
         }

         return d;
      }

      // Return the time in milliseconds since an arbitrary reference point.
      // (The arbitrary reference point in this case -- from getTimer -- is the
      // "number of milliseconds that have elapsed since Adobe(r) Flash(r)
      //  Player or Adobe AIR(tm) was initialized. This indicates the amount of
      //  time since the application began playing."
      public static function now() :int
      {
         return getTimer();
      }

      // *** Developer helpers

      // If the argument is false, throw an exception.
      public static function assert(a:Boolean, msg:String) :void
      {
         var stack:String;

         if (!a) {
            if (G.assertion_failures < 5) {
               G.assertion_failures += 1;
               stack = Introspect.stack_trace();
               if (G.sl !== null) {
                  var log_kv:Object =
                     { message: msg,
                       fail_count: G.assertion_failures };
                  if (stack !== null) {
                     log_kv.stack = stack;
                  }
                  G.sl.event('error/assert_hard', log_kv);
               }
               throw new Error('assertion failed: ' + msg,
                               G.assertion_failures);
            }
            else {
               // 2014.02.26: Does this really happen? Hopefully m4_ERROR will
               //             be able to send the server an error log message.
               m4_ERROR('ASSERTION FAILURE (exception limit exceeded):', msg);
               G.assert_soft(a, msg);
            }
         }
      }

      // DEVS: This is for easy breakpoints when debugging with fdb.
      public static function break_here() :int
      {
         var do_nothing:int = 1;
         do_nothing += 1;
         return do_nothing;
      }

      // If the argument is false, log an event for a known issue.
      public static function assert_known(a:Boolean, msg:String) :void
      {
         if (!a) {
            var stack:String = Introspect.stack_trace();
            m4_WARNING('assert_known:', msg, '/', stack);
            // CAVEAT: Stack trace is null in production builds.
            //         We always want msg, but stack is usually not set.
            if (G.sl !== null) {
               G.sl.event('info/assert_known',
                          {message: msg,
                           stack: (stack === null ? '(null/prod)' : stack)});
            }
         }
      }

      // If the argument is false, throw an exception.
      public static function assert_soft(a:Boolean, msg:String) :void
      {
         if (!a) {
            var stack:String = Introspect.stack_trace();
            m4_WARNING('assert_soft:', msg, '/', stack);
            // CAVEAT: Stack trace is null in production builds.
            //         We always want msg, but stack is usually not set.
            if (G.sl !== null) {
               G.sl.event('error/assert_soft',
                          {message: msg,
                           stack: (stack === null ? '(null/prod)' : stack)});
            }
         }
      }

      // trace() the exception error message and its stacktrace.
      public static function ignore_exception(x:Error) :void
      {
         m4_WARNING('WARNING: ignoring exception, stack trace follows');
         m4_WARNING(x.getStackTrace());
      }

      // Initializes the logging facility and prints a pretty picture.
      public static function init_logging() :void
      {
         // Init the logging class
         Logging.init_formatting(
            Conf_Instance.debug_logging_line_length_default,
            Conf_Instance.debug_logging_version);
         // Init the root logger
         G.log = Logging.get_logger('root');
         G.log.level = Conf_Instance.debug_logging_level_default;
         // Init each of the modules' loggers
         if (!Conf_Instance.debug_logging_level_override) {
            var logger:Logging;
            // Make sure -- even if we forget to/don't specify the new level in
            // Config_Logging.as -- that we change all loggers' levels to at
            // least the default.
            for each (logger in Logging.loggers) {
               logger.level = Conf_Instance.debug_logging_level_default;
            }
            //trace('init_logging: Traversing debug_logging_levels');
            for each (var arr:Array in Config_Logging.debug_logging_levels) {
               // Uncomment for testing:
               //trace('init_logging:',
               //      Strutil.string_pad(arr[0], ' ', 14, true), '/', arr[1]);
               // I.e., ['root', 'DEBUG']
               logger = Logging.get_logger(arr[0]);
               logger.level = arr[1];
            }
         }
         // Print some pretty ASCII artwork
         G.init_logging_say_hello();
      }

      // Initializes the logging facility and prints a pretty picture.
      protected static function init_logging_say_hello() :void
      {
         var random_1:int = Math.floor(Math.random()
                                       * G.log_splash_ascii_art.length);
         var random_2:int = Math.floor(Math.random()
                                       * G.log_splash_hello_msg.length);
         G.log.info(' ');
         for each (var line:String in G.log_splash_ascii_art[random_1]) {
            G.log.info(line);
         }
         G.log.info(G.log_splash_hello_msg[random_2]);
         G.log.info(' ');
      }

      // *** Logging facility initialization

      // Developer welcome messages and artwork.
      //
      // The system randomly chooses one hello message and one ascii painting
      // every time the client boots. Please add your own messages and art!

      //
      protected static var log_splash_hello_msg:Array = [
         "Chain lubed, tires pumped, helmet fastened, let's ride!",
         "Starting application, please mind the rotor wash",
         "Three..Two..One..CYCLOPATH!",
         "All your routes are belong to us.",
         "Something Something Gophers",
         "Passing on your left!",
         ];

      // ASCII Bicycles courtesy
      //   http://www.cascade.org/Community/ascii_bicycle_art.cfm
      protected static var log_splash_ascii_art:Array = [
         [ // Fixie rider/messenger
         '                                                ',
         '                    o__ _                       ',
         '                   _.>/ _                       ',
         '__________________(_)_\\(_)______________________',
         '                            mind the rotor wash ',
         '                                                ',
         //'',
         ],
         [ // "Barbie bike" death racers
         '                                                ',
         '   ____     __o   __o      ____    __o          ',
         ' ____      -\\<,  -\\<,    ____     -\\<,          ',
         '...........0/ 0..0/ 0.............0/ 0 .........',
         '                                                ',
         //'',
         ],
         [ // Wheelie
         '                                                ',
         '    __._. __.. O                                ',
         '   ____ ._..  /\\,                               ',
         '             -|~(*)                             ',
         ':::::::::.  (*)                                 ',
         '-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=',
         '                                                ',
         //'',
         ],
         [ // Long-hair on a long-tail (utility bike)
         '                                                ',
         '        ~~~O                                    ',
         '          /\\_,                                  ',
         '      ###-\\                                     ',
         '     (*) / (*)                                  ',
         '*o*o**o*o**o*o**o*o**o*o**o*o**o*o**o*o**o*o**o*',
         '                                                ',
         //'',
         ],
         [ // Portrait of a mountain biker (includes trail dawg)
         '                                                ',
         '+----------------------------------------------+',
         '|                O               /^^\\          |',
         '|               /\\,            /^    ^^\\       |',
         '|              -\\ -       /^^^^ /^^\\    ^\\     |',
         '|               /(*)  /^^^   /^^    ^     ^^   |',
         '|   \\___Q    (*) /^^^^   /^^^                  |',
         '|   /\\ /\\    ^^^^                              |',
         '+----------------------------------------------+',
         '                                                ',
         //'',
         ],
         [ // Recumbant
         '                                                ',
         '                  ---  0                        ',
         '         ==        -- _|\\_/\\_                   ',
         '_____________________(_)____()__________________',
         '                                                ',
         //'',
         ],
         [ // Trailer (Peace Coffee, Velo Veggies?)
         '                                                ',
         '      .___.                                     ',
         '      |   |     ,__o                            ',
         '      !___!   _-\\_<,                            ',
         "      <(*)>--(*)/'(*)                           ",
         '================================================',
         '                                                ',
         //'',
         ],
         [ // Tandem
         '                                                ',
         '    __@ __@                                     ',
         '  _-\\<,-\\<,                                     ',
         ' (*)/---/(*)                                    ',
         '::::::::::::::::::::::::::::::::::::::::::::::::',
         //'',
         ],
         [ // Group ride
         '                                                ',
         '                     __o                        ',
         '   ------- __o     _^\\<,_      __o              ',
         '  ------ _^\\<,_   (*)/ (*)   _^\\<,_             ',
         ' ------ (*)/ (*)            (*)/ (*)            ',
         '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
         '                                                ',
         //'',
         ],
         [ // Parent and child
         '                                                ',
         '                                      0         ',
         '                         ___    >%  / \\_        ',
         '                        / 0 \\    |_=\\__\\        ',
         '   =================== |  O=_| = |/ \\ |/\\_%< == ',
         "                        -(*)----(*)---' (*)     ",
         '================================================',
         '                                                ',
         //'',
         ],
         [ // Penny farthing
         '                                                ',
         '              _                                 ',
         '            // \\                                ',
         '           /( 6 )                               ',
         '          () \\_/   { penny.farthing }           ',
         '                                                ',
         //'',
         ],
      ];

      /*/

         As long as we're doing ASCII art... check out Minnesota! =)

               width="100%"
               borderStyle="solid"
               verticalAlign="middle"
               horizontalGap="3"
               paddingLeft="6"
               paddingTop="6"
               paddingRight="6"
               paddingBottom="6">

      /*/
   }

}


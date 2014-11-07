/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.base {

   import flash.events.Event;

   //import utils.misc.Introspect;
   import utils.misc.Logging;

   public class App_Mode_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@App_Md_Bse');

      protected var name_:String;

      // List of allowed actions.
      //
      // FIXME: Maybe, in the future, we can have multiple lists like allowed,
      //        allowed_if_logged_in, etc. for finer-grained control...
      protected var allowed:Array;

      protected var glow_filters:Array;

      // *** Constructor

      //
      public function App_Mode_Base()
      {
         this.allowed = new Array();
         this.glow_filters = new Array();
      }

      // *** Getters and Setters

      //
      public function get unavailable_text() :String
      {
         return 'This feature is unavailable in ' + this.name_ + ' mode.';
      }

      // *** Instance Methods

      //
      public function activate() :void
      {
         // Note that, once this fcn. is called, there's no going back -- well,
         // if the user has unsaved changes, they'll remain unsaved and we'll
         // hide the editing tool palette, which the user can get back by
         // re-entering edit mode. So, really, callers should check first if
         // the user has edited items and ask before calling activate().
         if (G.app.mode !== this) {
            m4_DEBUG('activate: mode:', this);
            // DEVS: Curious whose changing the mode on you? Uncomment this:
            //m4_DEBUG('stack_trace():', Introspect.stack_trace());
            G.app.mode = this;
            G.app.map_canvas.filters = this.glow_filters;
            // MAYBE: Mark all panels dirty, which causes a slight flicker.
            //        So there's probably a callLater or two happening, such
            //        that components are not all re-rendering in the same
            //        Flex frame. Oh, well...
            G.panel_mgr.panels_mark_dirty(null);
         }
         // else, on startup we're known to dispatch the same event twice
         //       in a row, but before and after setting G.initialized.
         G.app.dispatchEvent(new Event('modeChange'));
      }

      //
      public function is_allowed(app_action:String) :Boolean
      {
         var is_allowed:Boolean = false;
         m4_ASSERT(this.allowed !== null);
         m4_ASSERT(this.allowed is Array);
         if (this.allowed.indexOf(app_action) >= 0) {
            is_allowed = true;
         }
         return is_allowed;
      }

      //
      public function get uses_editing_tool_palette() :Boolean
      {
         return false;
      }

   }
}


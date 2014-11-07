/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// The UI_Wrapper classes provide infrastructure to make UI widgets generate
// appropriate data modification commands without modifying those widgets.

package views.commands {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.core.UIComponent;

   import utils.misc.Logging;

   public class UI_Wrapper {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Wrap');

      // We need this to maintain our own set of listeners because Flex is
      // dump. We can't use anonymous closures directly as the listeners
      // because we can't later reset or remove those closures because Flex
      // requires specifying the listening function in removeEventListener.
      protected static var listeners:Dictionary = new Dictionary();

      // *** Constructor

      public function UI_Wrapper()
      {
         m4_ASSERT(false); // Abstract
      }

      // *** Static class methods

      // Note: Most event listeners use string-valued constants to define
      // which events to listen for, but we use strings directly in order to
      // generalize more effectively. For example, there are a variety of
      // *.CHANGE event constants, but their values are all the same string,
      // so we use that here in order to generalize.
      protected static function listener_set(event:String,
                                             w:UIComponent,
                                             f:Function) :void
      {
         UI_Wrapper.listeners[w] = f;

         if (!w.hasEventListener(event)) {
            w.addEventListener(event, on_change, false, 0, true);
         }
      }

      //
      public static function on_change(ev:Event) :void
      {
         m4_DEBUG('on_change: ev.target:', ev.target);
         (UI_Wrapper.listeners[ev.target] as Function)(ev);
      }

   }
}


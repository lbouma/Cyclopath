/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import flash.events.Event;
   import flash.utils.Dictionary;
   import mx.core.UIComponent;

   import utils.misc.Logging;
   import utils.misc.Objutil;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class UI_Wrapper_Scalar extends UI_Wrapper {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Wrp_Sca');

      // *** Constructor

      public function UI_Wrapper_Scalar()
      {
         m4_ASSERT(false); // Never instantiated
      }

      // *** Static class methods

      //
      public static function wrap(widget:UIComponent,
                                  wattr:String,
                                  features:Set_UUID,
                                  fattr:String,
                                  fdefault:*=undefined) :void
      {
         var func:Function;

         // Set widget value.
         widget[wattr] = Objutil.consensus(features, fattr, fdefault);

         // Set up event listener.
         m4_ASSERT(features.length > 0);

         func = function(ev:Event) :void
         {
            var cmd:Command_Scalar_Edit;
            cmd = new Command_Scalar_Edit(
               features.clone(), fattr, widget[wattr]);
            G.map.cm.do_(cmd);
            // The item(s) whose attrs are being edited should be hydrated.
            m4_ASSERT_SOFT(cmd.is_prepared !== null);
         }

         UI_Wrapper.listener_set('change', widget, func);
      }

   }
}


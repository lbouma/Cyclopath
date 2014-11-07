/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   import flash.events.Event;

   import utils.misc.Logging;

   // [Event(name="grpaChanged", type="items.utils.Grpa_Change_Event")]

   public class Grpa_Change_Event extends Item_Change_Event {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Grpa_Chg_Ev');

      public static const EVENT_TYPE:String = 'grpaChanged';

      // *** Constructor

      public function Grpa_Change_Event(stack_id:int)
      {
         super(Grpa_Change_Event.EVENT_TYPE, stack_id);
      }

      // Override the inherited clone() method.
      override public function clone() :Event
      {
         return new Grpa_Change_Event(this.stack_id);
      }

   }
}


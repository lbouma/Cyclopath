/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   import flash.events.Event;

   import utils.misc.Logging;

   // [Event(name="itemChanged", type="items.utils.Item_Change_Event")]

   public class Item_Change_Event extends Event {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Chg_Ev');

      // ***

      public var stack_id:int;

      // *** Constructor

      public function Item_Change_Event(event_type:String, stack_id:int)
      {
         super(event_type);
         this.stack_id = stack_id;
      }

      // Override the inherited clone() method.
      override public function clone() :Event
      {
         return new Item_Change_Event(this.type, this.stack_id);
      }

   }
}


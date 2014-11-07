/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.events.Event;

   //import utils.misc.Logging;

   public dynamic class Data_Change_Event extends Event {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##DataChgEvt');

      // ***

      public var data:*;

      // *** Constructor

      public function Data_Change_Event(type:String,
                                        data:*,
                                        bubbles:Boolean=false,
                                        cancelable:Boolean=false)
      {
         super(type, bubbles, cancelable);

         this.data = data;
      }

      // According to Flex help's "Dispatching custom events" you must
      // override the clone fcn.
      //   http://livedocs.adobe.com/flex/3/html/help.html
      //    ?content=createevents_3.html
      // Override the inherited clone() method.
      override public function clone() :Event
      {
         return new Data_Change_Event(
            this.type, this.data, this.bubbles, this.cancelable);
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.map_widgets {

   import flash.display.Sprite;

   import items.Item_Base;

   // This class implements the GUI aspect of our Cyclopath items. Only two
   // types of Items use sprites: Geofeatures and Tiles.
   //
   // NOTE: I [lb] thought about implementing event listeners for mouse events,
   //       but this seems unnecessarily complex without a positive benefit.
   //       Firstly, the map canvas already knows about this class, so who
   //       cares if it already knows about the item classes (i.e., who cares
   //       about coupling). Secondly, this adds overhead to the system,
   //       because every Item_Sprite would have to register one or more event
   //       listeners (though I'm not sure the memory or resource usage would
   //       actually be detectable). Thirdly, while the map gets a MouseEvent,
   //       we'd have to create a new Event of our own, which adds complexity
   //       to an already complex system.
   //
   //       If you want to know more, see "Manually dispatching events":
   //   http://livedocs.adobe.com/flex/3/html/help.html?content=events_07.html

   public class Item_Sprite extends Sprite {

      // *** Instance variables

      public var item:Item_Base;

      // *** Constructor

      public function Item_Sprite(item:Item_Base)
      {
         super();
         this.item = item;
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// MAYBE: This is a CcpV1 leftover, in that instead of using a Class interface,
//        we should use an Event to react to items being added.

package views.map_widgets {

   public interface Items_Added_Listener
   {

      // Called by Map_Canvas when the features have been added
      function on_items_added(items_added:Array=null) :void;

   }
}


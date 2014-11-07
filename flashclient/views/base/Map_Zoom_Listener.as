/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.base {

   public interface Map_Zoom_Listener
   {

      // Called by the Map_Canvas when a zoom occurs, o_level was the original
      // zoom level, n_level is the new/current zoom level.
      function on_zoom(o_level:int, n_level:int) :void;

   }
}


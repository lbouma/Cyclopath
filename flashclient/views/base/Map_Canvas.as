/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Class representing the map.
//
// Actually, this is just a shell; the class used to be one big file. It's
// since been split into multiple files representing a hierarchy of
// functionality. While this doesn't decouple the code, per se, it does reduce
// the complexity by combining common functionality into disparate files,
// which, some might argue, does decouple the code somewhat. Another plus is
// that, by dividing the code into smaller chucks, it's less likely that two
// engineers will be submitting changes to the same file (or it's at least less
// painful when it does happen). Mostly, smaller files are easier to work on!
// Anyway, on with the show.

package views.base {

   import utils.misc.Logging;

   public class Map_Canvas extends Map_Canvas_Controller {

      protected static var log:Logging = Logging.get_logger('MC!MapCanvas');

      // *** Constructor

      public function Map_Canvas()
      {
         super();
         // Initialize features
         this.discard_reset();
         this.discard_restore(); // Make sure deleteset gets created
      }

      // Reset features and related infrastructure.
      override protected function discard_reset() :void
      {
         var tstart:int = G.now();
         super.discard_reset();
         m4_DEBUG_TIME('Map_Canvas.discard_reset:');
      }

      //
      override protected function discard_restore() :void
      {
         super.discard_restore();
         // This fcn. is triggered by G.map.discard_and_update, which means
         // everything is changing and nothing's to be trusted, so mark all the
         // panels dirty.
         m4_ASSERT(G.panel_mgr !== null);
         m4_DEBUG('discard_restore: panels_mark_dirty: null');
         G.panel_mgr.panels_mark_dirty(
            /*dirty_panels_arr=*/null,
            /*dirty_reason=*/0,
            /*schedule_activate=*/true);
         // Update the highlights. That is to say, clear the highlights.
         // They'll get redrawn as necessary when we rebuild the item
         // collections.
         UI.attachment_highlights_update();
      }

   }
}


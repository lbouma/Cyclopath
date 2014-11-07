/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import flash.utils.Dictionary;

   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class Grac_Record extends Item_Versioned {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#items.Grac');

      // *** Constructor

      public function Grac_Record(
         xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // ***

      // Editing Group Access objects is not zoom-dependent.
      override public function get actionable_at_raster() :Boolean
      {
         m4_DEBUG('actionable_at_raster: always true');
         return true;
      }

      // FIXME: When you implement GRAC editing (of Group and New_Item_Policy
      //        records), edit or delete this:
      //
      override public function get editable_at_current_zoom() :Boolean
      {
         m4_DEBUG('editable_at_current_zoom: always false');
         m4_ASSERT(false); // Is this fcn. used by this class's lineage?
         return true;
      }

   }
}


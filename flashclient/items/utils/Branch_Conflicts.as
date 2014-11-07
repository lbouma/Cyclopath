/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.utils {

   import utils.misc.Logging;
   import utils.rev_spec.*;

   // NOTE: This class is dynamic because that's what you do when you extend
   //       Dictionary or Array.

   public dynamic class Branch_Conflicts extends Array {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Brnch_Cflx');

      // *** Mandatory attributes

      // FIXME Does this belong in Branch_Conflicts.as or Branch_Conflict.as?
      public static const class_item_type:String = 'branch_conflicts';
      //public static const class_gwis_abbrev:String = 'bcfx';
      //public static const class_item_type_id:int = Item_Type.BRANCH_CONFLICTS;

      // *** Constructor

      public function Branch_Conflicts(xml:XML=null,
                                       rev:utils.rev_spec.Base=null)
      {
         /*
         super(xml, rev);
         if (xml !== null) {
         }
         */
      }

   }
}


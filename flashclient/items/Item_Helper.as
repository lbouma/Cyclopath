/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import utils.misc.Logging;
   import utils.rev_spec.*;

   // FIXME: In pyserver item_helper derives from item_base, which is what
   //        item_versioned is derived from, but in flashclient, Item_Versioned
   //        derives from Item_Revisioned (which derives from Item_Base) but
   //        Item_Helper derives directly from Record_Base. So is pyserver
   //        missing item_revisioned (or is it part of item_versioned) and is
   //        item_base a hybrid Record_Base/Item_Base object? Hrmm....
   //public class Item_Versioned extends Item_Revisioned
   public class Item_Helper extends Record_Base
   {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Helper');

      // *** Mandatory attributes

      public static const class_item_type:String = 'item_helper';
      //public static const class_gwis_abbrev:String = 'itmh';
      //public static const class_item_type_id:int = Item_Type.Item_Helper;

      // *** Other static variables

      // *** Constructor

      public function Item_Helper(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // *** Protected methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Item_Helper = (to_other as Item_Helper);
         super.clone_once(other);
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Item_Helper = (to_other as Item_Helper);
         super.clone_update(other, newbie);
      }

   }
}


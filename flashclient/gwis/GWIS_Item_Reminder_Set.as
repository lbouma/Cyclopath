/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Item_User_Access;
   import utils.misc.Logging;

   public class GWIS_Item_Reminder_Set extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/RmndrSet');

      // *** Constructor

      //
      public function GWIS_Item_Reminder_Set(
         the_item:Item_User_Access,
         remind_when:String,
         callback_load:Function=null,
         callback_fail:Function=null)
            :void
      {
         var url:String = this.url_base('item_reminder_set');
         url += ('&sid=' + the_item.stack_id);
         url += ('&type=' + the_item.get_class_item_type);
         url += ('&when=' + remind_when);

         var doc:XML = null;
         var throb:Boolean = false;
         var qfs:Query_Filters = null;
         var upb:Update_Base = null;
         super(url, doc, throb, qfs, upb, callback_load, callback_fail);
      }

      // ***

      // This is an out-of-band command, so overlapping is okay.
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

   }
}


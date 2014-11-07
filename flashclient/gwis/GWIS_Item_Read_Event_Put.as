/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   public class GWIS_Item_Read_Event_Put extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Put_ThRE');

      // *** Constructor

      // The caller sends us a list of system_id values.
      // The server stores the system_id and a revision ID, so, basically,
      // it's a list of views. But it doesn't store the stack_id, so different
      // versions of an item (earlier version,s later versions, versions in
      // other branches), will all appear unread unless there's a system_id
      // record of the viewing.
      public function GWIS_Item_Read_Event_Put(
         system_ids:Array,
         callback_load:Function=null)
            :void
      {
         var url:String = this.url_base('item_read_event_put');

         var doc:XML = this.doc_empty();
         var th:XML = <items_read />;
         for each (var system_id:int in system_ids) {
            th.appendChild(<item ssid={system_id} />);
         }
         doc.appendChild(th);

         var throb:Boolean = false;
         var qfs:Query_Filters = null;
         var ur:Update_Base = null;
         var cfail:Function = null;
         super(url, doc, throb, qfs, ur, callback_load, cfail);
      }

      // ***

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import flash.utils.Dictionary;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Item_User_Access;
   import items.utils.Stack_Id_Array;
   import utils.misc.Logging;

   public class GWIS_Item_Findability_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Fbil_Get');

      // *** Instance attributes

      protected var item_sids:Stack_Id_Array = new Stack_Id_Array();

      // *** Constructor

      //
      public function GWIS_Item_Findability_Get(
         items_lookup:Dictionary,
         callback_load:Function=null,
         callback_fail:Function=null) :void
      {
         var doc:XML = this.doc_empty();
         var url:String = this.url_base('item_findability_get');

         for each (var item:Item_User_Access in items_lookup) {
            this.item_sids.push(item.stack_id);
         }
         // <fbil_sids>1,2,3,4,5</fbil_sids>
         Query_Filters.append_ids_compact(doc, 'fbil_sids', this.item_sids);

         this.items_in_request = items_lookup;

         var throb:Boolean = false;
         var query_filters:Query_Filters = null;
         var update_req:Update_Base = null;

         super(url, doc, throb, query_filters, update_req,
               callback_load, callback_fail);
      }

      // *** Instance methods

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

      //
      override public function is_similar(other:GWIS_Base) :Boolean
      {
         m4_DEBUG('is_similar: this:', this);
         m4_DEBUG('is_similar: other:', other);
         return super.is_similar(other);
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);

         // E.g.,
         //  <data major="not_a_working_copy" gwis_version="3" semiprotect="0">
         //   <fbilities>
         //    <fbility sid="1588111" unom="landonb" sqel="0" hist="1"/>
         //   </fbilities>
         //  </data>
         m4_VERBOSE('resultset_process: rset:', rset.toString());
         m4_VERBOSE2('resultset_process: rset.fbilities[0]:',
                     rset.fbilities[0].toString());
         m4_VERBOSE2('resultset_process: rset.fbilities[0].@sid:',
                     rset.fbilities[0].fbility[0].@sid);
         // item_findability.username
         m4_VERBOSE2('resultset_process: rset.fbilities[0].@unom:',
                     rset.fbilities[0].fbility[0].@unom);
         // item_findability.library_squelch; see Library_Squelch:
         //  squelch_off            = 0
         //  squelch_searches_only  = 1
         //  squelch_always_hide    = 2
         m4_VERBOSE2('resultset_process: rset.fbilities[0].@sqel:',
                     rset.fbilities[0].fbility[0].@sqel);
         // item_findability.show_in_history (bool)
         m4_VERBOSE2('resultset_process: rset.fbilities[0].@hist:',
                     rset.fbilities[0].fbility[0].@hist);

         var item:Item_User_Access;
         //for each (var sub_xml:XMLList in rset.fbilities) {
         for each (var sub_xml:XML in rset..fbility) {
            // Why doesn't this print anything?:
            //  m4_DEBUG('resultset_process: sub_xml:', sub_xml.toString());
            m4_VERBOSE('resultset_process: sub_xml.@sid:', sub_xml.@sid);
            m4_VERBOSE('resultset_process: sub_xml.@unom:', sub_xml.@unom);
            m4_VERBOSE('resultset_process: sub_xml.@sqel:', sub_xml.@sqel);
            m4_VERBOSE('resultset_process: sub_xml.@hist:', sub_xml.@hist);

            // NOTE: We cast to int, else the Dictionary lookup returns naught.
            var stack_id:int = int(sub_xml.@sid)
            item = (this.items_in_request[stack_id] as Item_User_Access);

            if (item !== null) {
               m4_VERBOSE('resultset_process: item:', item);

               //item.library_squelch = sub_xml.@sqel;
               //item.show_in_history = sub_xml.@hist;
               var username:String = sub_xml.@unom;
               if (username == G.user.username) {
                  item.fbilty_usr_libr_squel = sub_xml.@sqel;
                  item.fbilty_usr_histy_show = sub_xml.@hist;
               }
               // MAGIC_NUMBER: Usernames prefixed with a floorbar are special.
               else if (username == '_anonymous') {
                  item.fbilty_pub_libr_squel = sub_xml.@sqel;
                  // There's no public equivalent of the recent route list
                  // for anonymous users.
                  // Nope: item.fbilty_pub_histy_show = sub_xml.@hist;
               }
               else {
                  // 2014.09.25: On production, fired a half-dozen times.
                  m4_ERROR('resultset_process: unexpected usernom:', username);
                  m4_ASSERT_SOFT(false);
                  G.sl.event('error/resultset_process/unk_unom', {item: item});
               }

               // NOTE: The callers of GWIS_Item_Findability_Get will signal
               //       events, like linksLoaded, on which other objects can
               //       listen (we don't actively do anything here, other than
               //       setting the item object's data).
            }
            else {
               m4_ERROR('resultset_process: stk id not found:', sub_xml.@sid);
               m4_WARNING('resultset_process: items_in_request:',
                          this.items_in_request);
            }
         }
      }

      // ***

      //
      override public function toString() :String
      {
         return (super.toString() + ' / stk_ids: '
                 + String(this.item_sids));
      }

   }
}


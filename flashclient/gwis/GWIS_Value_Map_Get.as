/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/* 2013.05.06: This command is deprecated, or at least no longer used.
               Now we compile the skin colors into flashclient, rather
               than asking the server for the draw class config. We've
               never changed colors on the fly, and for Statewide we
               need access to the mapserver/skins colors, but it seems
               like more work to make a new GWIS class that to just hardcode
               the skin colors as const classes (auto-generated from the
               mapserver/skins resources, 'natch).

               Note that this command still works: it'll get the draw_class,
               draw_param_joined, and tilecaches_mapserver_zoom tables, and
               we could just store each as the XML that's returned, since XML
               provides good random access to data. But for developers it's a
               lot easier if the skin data is just another ActionScript class.
               */

package gwis {

   //import flash.utils.getDefinitionByName;

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   // FIXME: This class has a funny name.
   public class GWIS_Value_Map_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Cfg_Draw');

      // *** Constructor

      public function GWIS_Value_Map_Get(update_req:Update_Base) :void
      {
         var url:String = this.url_base('item_draw_class_get');
         var throb:Boolean = true;
         var qfs:Query_Filters = null;
         super(url, this.doc_empty(), throb, qfs, update_req);
      }

      // *** Instance methods

      //
      override public function get allow_overlapped_requests() :Boolean
      {
         return true;
      }

      //
      override public function equals(other:GWIS_Base) :Boolean
      {
         return false;
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
         //m4_DEBUG('*Resp: GetConfig_Draw: resultset_process:', rset);
         // Process config element, if present.
         if (rset.config !== null) {
            Conf.import_xml(rset.config[0]);
            G.app.map_key.fill_values();
         }
         else {
            m4_ASSERT(false);
         }
         // EXPLAIN: Why is this being deleted -- doesn't rset get deleted
         //          anyway? Or are we trying to prevent the XML from being
         //          processed by another handler? Probably not a big deal.
         delete rset.config;
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_nothing;
      }

   }
}


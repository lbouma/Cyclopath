/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.utils.Query_Filters;
   import utils.misc.Logging;
   import views.panel_history.Panel_Recent_Changes;
   import views.panel_util.Paginator_Widget;

   public class GWIS_Revision_History_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rev_Hist');

      // *** Protected instance variables

      // Reference to the history browser we serve.
      protected var hb:Panel_Recent_Changes;

      protected var paginator:Paginator_Widget;

      // *** Constructor

      public function GWIS_Revision_History_Get(
         hb:Panel_Recent_Changes, // FIXME: Make this a pair of callbacks?
         query_filters:Query_Filters,
         paginator:Paginator_Widget) :void
      {
         //var url:String = (this.url_base('grac_get')
         //                  + '&control_type=' + 'group_revision'
         //                  + '&control_context=' + 'user');
         var url:String = this.url_base('revision_get');

         var doc:XML = this.doc_empty();

         this.hb = hb;

         // C.f. GWIS_Checkout_Base

         //if (rev !== null) {
         //   url += '&rev=' + rev;
         //}
         //this.rev = rev;

         this.paginator = paginator;

         if (query_filters !== null) {
            /*/
            if (this.paginator !== null) {
               this.paginator.configure_query_filters(query_filters);
               if (this.paginator.records_total_count == 0) {
                  query_filters.pagin_total = true;
               }
            }
            /*/
            //
            url = query_filters.url_append_filters(url);
            query_filters.xml_append_filters(doc);
         }
         //this.query_filters = query_filters;

         var throb:Boolean = true;
         super(url, doc, throb, query_filters);
      }

      // *** Instance methods

      // Parse the incoming revisions and add them to the history browser.
      override protected function resultset_process(rset:XML) :void
      {

// NOTE: Should we derive from GWIS_Grac_Get? It populates this.resp_items in
//       resultset_process, and then the grac_mgr in gwis_complete_callback;

         super.resultset_process(rset);

/*/ FIXME: route reactions. this from CcpV1. set_correct_heights is new to
           route reactions. this is the complete CcpV1 fcn... [lb] can't
           remember what I did to get rid of the Conf.hb_* vars... I think I
           just use include_geosummary... and we don't prepend/postpend in
           CcpV2?
         switch (this.mode) {
         case Conf.hb_append:
            this.hb.append(rset.revision[0]);
            this.hb.set_correct_heights();
            break;
         case Conf.hb_prepend:
            this.hb.prepend(rset.revision[0]);
            this.hb.set_correct_heights();
            break;
         case Conf.hb_replace:
            this.hb.replace(rset.revision[0]);
            this.hb.set_correct_heights();
            break;
         case Conf.hb_geosummary:
            this.hb.geosummary(rset.revision[0]);
            break;
         default:
            m4_ASSERT(false);
         }
/*/

         var revs:XML = rset.revision[0];

         if (revs.@total > 0) {
            if (this.paginator !== null) {
               this.paginator.records_total_count = int(revs.@total);
            }
         }

         if (this.query_filters.include_geosummary) {
            m4_DEBUG('resultset_process: geosummary:', rset.revision[0]);
            this.hb.geosummary(rset.revision[0]);
         }
         else {
            m4_DEBUG('resultset_process: replace:', rset.revision[0]);
            this.hb.replace(rset.revision[0]);
         }
         m4_DEBUG_CLLL('>callLater: resultset_process: set_correct_heights');
         // FIXME: 2013.04.08: set_correct_heights probably no longer needed:
         G.map.callLater(this.hb.set_correct_heights);
      }

   }
}


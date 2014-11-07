/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.controls.Alert;

   import utils.misc.Logging;

   public class GWIS_Revert extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/REVERT');

      // *** Constructor

      public function GWIS_Revert(revs:Array, changenote:String) :void
      {
         var doc:XML = this.doc_empty();
         var url:String = this.url_base('revision_revert');

         m4_ASSERT(revs.length >= 1);

         url += '&revs=' + revs.join(',');
         doc.metadata.appendChild(
            <changenote>
               {changenote}
            </changenote>
            );

         super(url, doc);
      }

      // *** Instance methods

      //
      override protected function error_present(text:String) :void
      {
         Alert.show(text, "Can't revert revisions");
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);

         var the_alert:Alert = Alert.show(
            'The revision(s) were successfully reverted.\n\n'
            + 'Please note that geometric changes may not appear immediately '
            + 'on the map in some zoom levels (our server has to rebuild '
            + 'the affected map tiles first).',
            'Revision revert successful');

         //?: G.map.rev_loadnext = new utils.rev_spec.Current();

         G.map.discard_and_update();

         G.tabs.changes_panel.refetch();

         the_alert.setFocus();
      }

   }
}


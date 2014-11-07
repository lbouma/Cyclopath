/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import mx.controls.Alert;

   import items.feats.Region;
   import utils.misc.Logging;
   import views.map_components.Invitation_Bar;

   public class GWIS_Region_Stats_Get extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rg_Stats');

      // *** Instance variables

      protected var invitation_bar:Invitation_Bar;

      // *** Constructor

      public function GWIS_Region_Stats_Get(invitation_bar:Invitation_Bar)
         :void
      {
         var url:String = this.url_base('region_stats_get');
         this.invitation_bar = invitation_bar;

         super(url, this.doc_empty());
      }

      // *** Instance methods

      // Process the incoming result set. The presence of a result set tells
      // us that login was successful.
      override protected function resultset_process(rset:XML) :void
      {
         var username:String;

         super.resultset_process(rset);

         if (rset.rod[0].children().length() > 0) {

            G.item_mgr.region_of_the_day = new Region(rset.rod[0].region[0]);

            if (G.item_mgr.region_of_the_day !== null) {
               this.invitation_bar.invitation_region.text = rset.rod[0].@bar;
               this.invitation_bar.reason_title = rset.rod[0].@title;
               this.invitation_bar.reason_message = rset.rod[0].@call;
               this.invitation_bar.accept.enabled = true;
               this.invitation_bar.show();
               // FIXME This couples these two together; make the panel_window
               //       listen instead
               G.app.panel_window_canvas.y = G.app.invitation_bar.height;

               var region:Region;
               for each (region in Region.all) {
                   if (region.stack_id
                       == G.item_mgr.region_of_the_day.stack_id) {
                  region.draw_all();
                  }
               }
            }
            m4_ASSERT_ELSE_SOFT;
         }
      }

   }
}


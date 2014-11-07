/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: See results_style='rezs_name' and use Checkout; remove this file.

package gwis {

   import flash.events.Event;
   import mx.collections.ArrayCollection;
   import mx.controls.Alert;

   import gwis.update.Update_Base;
   import items.feats.Branch;
   import utils.misc.Logging;

   public class GWIS_Branch_Names_Get extends GWIS_Item_Names_Get {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Brn_Noms');

      // *** Constructor

      public function GWIS_Branch_Names_Get(update_req:Update_Base=null)
         :void
      {
         super(update_req, 'branch');

         this.callback_fail = this.branch_names_get_fail;
      }

      // *** Instance methods

      // MAYBE: Maybe the GWIS_Branch_Names_Get caller should register a
      // callback and we can move this fcn. there, decoupling it from the
      // network code. But, also, meh, there's a lot of coupled GWIS code.

      // Process the incoming result set.
      override protected function resultset_process(rset:XML) :void
      {
         //m4_DEBUG('resultset_process: rset:', rset.toString());
         if (Logging.get_level_key('DEBUG') >= GWIS_Base.log.current_level) {
            for each (var xml_line:String in rset.toString().split('\n')) {
               m4_DEBUG('resultset_process:', xml_line);
            }
         }
         super.resultset_process(rset);
         G.map.branches_list = new Array();
         for each (var doc:XML in rset.branch) {
            var branch:Branch = new Branch(doc);
            // The branch's init_add and init_update set the branch
            // object as G.item_mgr.active_branch.
            m4_DEBUG('resultset_proc: adding new branch:', branch.toString());
            G.map.branches_list.push(branch);
         }
         m4_ASSERT(Branch.ID_PUBLIC_BASEMAP > 0);
         // Instead of twiddling the view from here, signal an event.
         // NO:
         //    G.app.my_maps_panel.widget_branch_list.branch_list.dataProvider
         //       = G.map.branches_list;
         //    G.panel_mgr.panels_mark_dirty([G.app.my_maps_panel]);
         m4_DEBUG('dispatchEvent: branchListLoaded');
         G.item_mgr.dispatchEvent(new Event('branchListLoaded'));
         // Hide/Show the MAPS tab as appropriate.
         // FIXME: If the user has the tab active this might seem weird to hide

         m4_DEBUG('resultset_process: done');
      }

      //
      protected function branch_names_get_fail(
         gwis_req:GWIS_Branch_Names_Get,
         xml:XML) :void
      {
         // This can happen if the token is bad, and the user needs to relogin.
         // [lb] guessing this should only ever happen to DEVs, i.e., if you
         // clobber ccpv3_test with a fresh copy of the live database, your
         // test site token cookie is probably wrong.
         m4_WARNING('branch_names_get_fail');
         // [lb] thought at first we might need to fake a
         // G.item_mgr.active_branch to avoid null pointer
         // references, but the client recovers nicely:
         // the GUI loads (but no tiles or map data), and
         // a login popups with the username pre-filled and
         // the password box empty and ready to be filled.
         if (false) {
            // Only maybe do this if code is null-bombing.
            var branch:Branch = new Branch();
            branch.stack_id = Conf_Instance.cheater_branch_sid;
            m4_DEBUG('branch_names_get_fail: faking new branch:', branch);
            G.map.branches_list.push(branch);
         }
      }

   }
}


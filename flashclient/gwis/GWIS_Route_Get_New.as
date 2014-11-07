/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import flash.events.Event;
   import mx.controls.Alert;
   import mx.managers.PopUpManager;

   import items.feats.Route;
   import items.utils.Travel_Mode;
   import utils.misc.Introspect;
   import utils.misc.Logging;
   import views.base.UI;
   import views.panel_util.Alert_Dialog;

   public class GWIS_Route_Get_New extends GWIS_Route_Get_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rte_GNew');

      // ***

      public var beg_addr:String = '';
      public var beg_pt_x:Number = NaN;
      public var beg_pt_y:Number = NaN;
      public var fin_addr:String = '';
      public var fin_pt_x:Number = NaN;
      public var fin_pt_y:Number = NaN;

      public var travel_mode:int = Travel_Mode.bicycle;
      public var p2_depart_at:String = '';
      public var p2_transit_pref:int = 0;

      // *** Constructor

      public function GWIS_Route_Get_New(
         beg_addr:String,
         beg_pt_x:Number,
         beg_pt_y:Number,
         fin_addr:String,
         fin_pt_x:Number,
         fin_pt_y:Number,
         caller_source:String='',
         callback_okay:Function=null,
         callback_fail:Function=null,
         callback_obj:*=null,
         preferences:XML=null,
         ref_route:Route=null,
         dont_save:Boolean=false,
         compute_landmarks:Boolean=false,
         travel_mode:int=Travel_Mode.bicycle,
         p2_depart_at:String='',
         p2_transit_pref:int=0)
      {
         this.beg_addr = beg_addr;
         this.beg_pt_x = beg_pt_x;
         this.beg_pt_y = beg_pt_y;
         this.fin_addr = fin_addr;
         this.fin_pt_x = fin_pt_x;
         this.fin_pt_y = fin_pt_y;

         if (callback_okay === null) {
            // Callers should specify a callback. Our default is to just print
            // a warning that callers should specify a callback.
            callback_okay = this.gwis_route_get_new_okay;
         }
         // Parent will handle: callback_okay, callback_fail, callback_obj

         // Not storing: this.preferences = preferences;

         // Parent will handle: ref_route, dont_save, compute_landmarks

         this.travel_mode = travel_mode;
         this.p2_depart_at = p2_depart_at;
         this.p2_transit_pref = p2_transit_pref;

         var url:String = this.url_base('route_get');

         var doc:XML = this.doc_empty();
         if (preferences !== null) {
            doc.appendChild(preferences);
         }

         super(url, doc, caller_source,
               callback_okay, callback_fail, callback_obj,
               ref_route, dont_save, compute_landmarks);

         this.popup_enabled = true;
      }

      // *** Instance methods

      // Report problems to the user
      override protected function error_present(text:String) :void
      {
         Alert_Dialog.show('Unable to Find Route', text);
      }

      //
      override protected function fetch_impl(gwis_timeout:int=0) :void
      {
         super.fetch_impl(Conf_Instance.get_route_timeout);
      }

      //
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);

         url =   '&beg_addr='    + encodeURIComponent(this.beg_addr)
               + '&beg_ptx='     + encodeURIComponent(this.beg_pt_x.toString())
               + '&beg_pty='     + encodeURIComponent(this.beg_pt_y.toString())
               + '&fin_addr='    + encodeURIComponent(this.fin_addr)
               + '&fin_ptx='     + encodeURIComponent(this.fin_pt_x.toString())
               + '&fin_pty='     + encodeURIComponent(this.fin_pt_y.toString())
               + '&travel_mode=' + encodeURIComponent(Travel_Mode.lookup[
                                                         this.travel_mode])

         if (this.p2_depart_at) {
            url += '&p2_depart=' + encodeURIComponent(this.p2_depart_at);
            url += '&p2_txpref=' + encodeURIComponent(this.p2_transit_pref
                                                         .toString());
         }

         // You have to make a route route before you can retrieve it
         // as GPX. See GWIS_Route_Get_Saved for asgpx=1.
         url += '&asgpx=0';

         return super.finalize(url);
      }

      //
      protected function gwis_route_get_new_okay(
         gwis_cmd:GWIS_Route_Get_New, route:Route) :void
      {
         m4_DEBUG2('gwis_route_get_new_okay: dont_save:', this.dont_save,
                   '/ route:', route);
         m4_WARNING('gwis_route_get_new_okay: caller should specify callback');
         m4_ASSERT_SOFT(false);
      }

      // Parse the incoming Route and notify the map that it's here.
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
      }

   }
}


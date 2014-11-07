/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import items.Geofeature;
   import items.feats.Route;
   import utils.misc.Logging;

   public class GWIS_Route_Get_Base extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rt_GBase');

      // *** Instance attributes

      public var caller_source:String;

      // GWIS_Base has its own callback_load and callback_fail.
      // We provide a secondoary callback_okay fcn.
      public var callback_okay:Function = null;
      // Just use GWIS_Base's: public var callback_fail:Function = null;
      public var callback_obj:* = null;

      public var ref_route:Route = null
      public var dont_save:Boolean = false;

      public var compute_landmarks:Boolean = false;

      // For item version history, sometimes we get a specific item.
      // This value is just for callers -- it's not part of the command.
      public var item_version:int = 0;

      // *** Constructor

      public function GWIS_Route_Get_Base(url:String,
                                          data:XML=null,
                                          caller_source:String='',
                                          callback_okay:Function=null,
                                          callback_fail:Function=null,
                                          callback_obj:*=null,
                                          ref_route:Route=null,
                                          dont_save:Boolean=false,
                                          compute_landmarks:Boolean=false)
      {

         if (data === null) {
            data = this.doc_empty();
         }

         // For devs: what code is generating this route request.
         this.caller_source = caller_source;

         this.callback_okay = callback_okay;
         // Stored in parent: callback_fail;
         this.callback_obj = callback_obj;

         this.ref_route = ref_route;
         this.dont_save = dont_save;
         this.compute_landmarks = compute_landmarks;

         var throb:Boolean = true;
         var qfs:Query_Filters = null;
         var update_req:Update_Base = null;
         // Note that we set the parent's okay callback null, so that we can
         // control when the load callback fires.
         var callback_load:Function = null;
         super(url, data, throb, qfs, update_req,
               callback_load, callback_fail);

         this.popup_enabled = true;
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
         // BUG nnnn: Revisit equals and allow_overlapped_requests...
         //           they're probably overkill, and they cause
         //           unforeseen problems... and the only problem
         //           they solve is bandwidth and server usage (e.g.,
         //           like the CcpV1 problem where flashclient sends
         //           twenty of the same get-discussions requests on
         //           startup).
         return false;
      }

      //
      override public function finalize(url:String=null) :void
      {
         if (url === null) {
            url = '';
         }

         url += '&source=' + encodeURIComponent(this.caller_source);

         if (this.dont_save) {
            url += '&dont_save=' + int(this.dont_save);
         }

         // BUG nnnn: Mobile doesn't send this command. But [lb] is making it
         // opt-in, since it adds a lot of seconds to the route request, and
         // I'm seeing timeouts trying to get routes on mobile. We'll still
         // compute landmarks for the experiment, but the feature should
         // otherwise be opt-in.
         if (this.compute_landmarks) {
            url += '&add_lmrks=' + int(this.compute_landmarks);
         }

         return super.finalize(url);
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);

         // BUGTEST: Add this to testing: Search for route and then change
         //          branches... maybe just do lots of things and then change
         //          to another map.
// 2012.05.15: [lb] still seeing "No saved route..." error when changing
// branches.

         var route:Route;
         route = new Route(rset.route[0]);
         m4_DEBUG('resultset_process: route:', route);

         route.landmarks_loaded = this.compute_landmarks;

         // If a new route, add it. If an existing route that was edited,
         // update it. If a saved route that was simply fetched, add it.
         // Note that we re-fetch routes after a route reaction is submitted.
         // 2014.05.13: Don't add route is an historic item version.
         if ((route.stack_id > 0) && (this.item_version == 0)) {
            G.map.items_add([route,]);
         }
         else {
            // This is a route segment or an historic route.
            m4_ASSERT_SOFT(this.dont_save);
            m4_ASSERT_SOFT((this.ref_route !== null)
                           || (this.item_version > 0));
         }

         // Restore old route selection (if any).
         // FIXME: route reactions. this is new.
         /*/ FIXME: Statewide UI: Test submitting route reaction and see what
                                  happens to selected route, then decide what
                                  to do with selectedset_old.
         var o:Object;
         for each (o in G.map.selectedset_old) {
            var some_route:Route = (o as Route);
            if (some_route !== null) {
               if (some_route.stack_id == route.stack_id) {
                  route.set_selected(true);
               }
            }
         }
         /*/

         // Run the callback.
         if (this.callback_okay !== null) {
            // items_add may have updated an existing Route.
            var the_route:Route = route;
            if ((the_route.stack_id > 0) && (this.item_version == 0)) {
               var actual_rt:Route = Geofeature.all[the_route.stack_id];
               if (actual_rt === null) {
                  // We called items_add so this path is unreachable.
                  m4_DEBUG('resultset_process: using new route:', the_route);
                  m4_ASSERT_SOFT(false);
               }
               else if (actual_rt !== route) {
                  the_route = actual_rt;
                  m4_DEBUG('resultset_process: using real route:', the_route);
               }
               else {
                  // This is the first time we've seen the item from the server
                  // (otherwise we'd have updated an existing item instead), or
                  // some caller is re-inserting an item that was previously
                  // removed from the map.
                  m4_DEBUG('resultset_process: using same route:', the_route);
               }
            }
            // else, this is an unsaved route, i.e., for route editing
            //       sub-segments, and the_route.stack_id == 0, or
            //       this is an historic route, and item_version > 0.
            m4_ASSERT_SOFT(the_route !== null);
            this.callback_okay(this, the_route);
         }

         // We do not focus on the route because GWIS_Route_Get_Base is used
         // for route reloading or for GPX downloads.
         //
         // See GWIS_Route_Get_New for fetching 'new' routes into the client;
         // and existing routes are checked out via GWIS_Checkout and
         // GWIS_Route_Get_Saved (the latter gets the route steps, the
         // former just normal itemy stuff).
      }

      // ***

      //
      override public function toString() :String
      {
         return super.toString()
             + ' / vers. ' + this.item_version;
      }

   }
}


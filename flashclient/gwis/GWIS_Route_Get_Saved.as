/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// The GWIS_Route_Get_Saved is an overloaded version of GWIS_Route_Get_New that
// serves up saved routes. This is a separate class because Flash doesn't allow
// multiple constructors, and it doesn't require the overloaded cleanup, error
// and resultset_process operations.

// FIXME: PERFORMANCE: 2012.02.27: [lb] is seeing this take 16 seconds. Ug.

package gwis {

   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   public class GWIS_Route_Get_Saved extends GWIS_Route_Get_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rt_GSved');

      // ***

      public var route_stack_id:int;
      public var as_gpx:Boolean = false;
      public var check_invalid:Boolean = false;
      public var gia_use_sessid:Boolean = false;
      public var get_steps_and_stops:Boolean = false;

      // NOTE: exp_landmarks_uid is not really user_.id, it's a value from
      //       (0,1,2) -- for the experiment, we show the user three versions
      //       of the same route with landmarks indicated by one of three
      //       different users (identified as 0, 1, 2).
      public var exp_landmarks_uid:int;

      public var used_sessid:Boolean = false;

      // *** Constructor

      public function GWIS_Route_Get_Saved(route_stack_id:int,
                                           caller_source:String,
                                           callback_okay:Function=null,
                                           callback_fail:Function=null,
                                           as_gpx:Boolean=false,
                                           check_invalid:Boolean=false,
                                           gia_use_sessid:Boolean=false,
                                           get_steps_and_stops:Boolean=false,
                                           compute_landmarks:Boolean=false,
                                           exp_landmarks_uid:Number=-1)
      {
         m4_DEBUG('GWIS_Route_Get_Saved: gia_use_sessid:', gia_use_sessid);
         m4_DEBUG2('GWIS_Route_Get_Saved: int(gia_use_sessid):',
                   int(gia_use_sessid));

         // The route stack ID.
         //
         // Note: If you want an historic version of a specific item,
         // get that item's version history and then use a system id
         // to set query_filters.only_system_id.
         //
         this.route_stack_id = route_stack_id;

         // Users can request a version of the route that they can save to
         // their drive and then upload to a GPS device.
         this.as_gpx = as_gpx;
         // Callers can set check_invalid to repair a route and get
         // an alternate route suggestion.
         this.check_invalid = check_invalid;
         // If a user gets a route anonymously and then logs in, they
         // can get arbiter access to the route using their session ID.
         this.gia_use_sessid = gia_use_sessid;
         // For the route lists, we don't want to use the resources
         // necessary to fetch route steps and route stops.
         this.get_steps_and_stops = get_steps_and_stops;
         // Landmarks experiment.
         this.exp_landmarks_uid = exp_landmarks_uid;
         // This is set if route.unlibraried, but we only get the stack ID,
         // so callers should set this accordingly.
         this.used_sessid = gia_use_sessid;

         // [lb] got rid of GWIS_Route_Get_By_Hash, which is replaced by
         // Query_Filters.use_stealth_secret -- but now it's a two-step
         // process: use GWIS_Checkout first to get the route details, then use
         // GWIS_Route_Get_Saved with the resolved stack ID to get the fully
         // hydrated route, steps, stops, and all.

         var url:String = this.url_base('route_get');

         var doc:XML = null;

         super(url, doc, caller_source,
               callback_okay, callback_fail, /*callback_obj=*/null,
               /*ref_route=*/null, /*dont_save=*/true, compute_landmarks);

         // Called after super() so that this.query_filters is prepared.
         if (get_steps_and_stops) {
            this.query_filters.include_item_aux = true;
         }

         this.popup_enabled = false;
      }

      // *** Instance methods

      //
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);

         url =   '&rt_sid=' + this.route_stack_id
               + '&asgpx=' + int(this.as_gpx)
               + '&checkinvalid=' + int(this.check_invalid)
               + '&guss=' + int(this.gia_use_sessid);

         if (this.exp_landmarks_uid >= 0) {
            url += '&exp_landmarks_uid=' + this.exp_landmarks_uid;
         }

         return super.finalize(url);
      }

      //
      override protected function resultset_process(rset:XML) :void
      {
         super.resultset_process(rset);
      }

   }
}


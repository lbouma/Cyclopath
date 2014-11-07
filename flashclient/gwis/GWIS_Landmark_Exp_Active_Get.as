/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package gwis {

   import gwis.update.Update_Base;
   import gwis.utils.Query_Filters;
   import utils.misc.Logging;

   // This command returns:
   //    active      # 'true' or 'false', depending on pyserver's
   //                #     CONFIG.landmarks_experiment_active
   //    routes_togo # Number of routes left for user, if experiment started.
   //    routes_done # Number of routes user has completed, if exp. started.

   public class GWIS_Landmark_Exp_Active_Get extends GWIS_Landmark_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/LmrkActG');

      public var experiment_part:int = -1;

      // *** Constructor

      public function GWIS_Landmark_Exp_Active_Get(
         experiment_part:int=1,
         callback_load:Function=null) :void
      {
         var url:String = this.url_base('landmark_exp_active_get');
         super(url,
               /*data=*/this.doc_empty(),
               /*throb=*/true,
               /*query_filters=*/null,
               /*update_req=*/null,
               /*callback_load=*/callback_load,
               /*callback_fail=*/null,
               /*caller_data=*/null);
         this.experiment_part = experiment_part;
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
         var equal:Boolean = false;
         var other_:GWIS_Landmark_Exp_Active_Get;
         other_ = (other as GWIS_Landmark_Exp_Active_Get);
         m4_ASSERT(this !== other_);
         equal = ((super.equals(other_))
                  && (this.experiment_part == other_.experiment_part)
                  );
         // Base class prints this and other_ so just print our equals.
         m4_VERBOSE('equals?:', equal);
         return equal;
      }

      //
      override public function finalize(url:String=null) :void
      {
         m4_ASSERT(url === null);
         url = '';
         if (this.experiment_part != -1) {
            url += '&exp_part=' + this.experiment_part;
         }
         return super.finalize(url);
      }

   }
}


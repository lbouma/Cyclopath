/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import items.feats.Route;
   import utils.misc.Logging;
   import views.panel_routes.Route_Stop;

   public class Route_Segment {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('RouteSegment');

      // *** Instance attributes

      public var ref_route:Route;
      public var seg_route:Route;

      public var lhs_rstop:Route_Stop;
      public var rhs_rstop:Route_Stop;

      public var xs:Array;
      public var ys:Array;

      public var seg_rsteps:Array;
      // This probably isn't necessary:
      public var seg_rstops:Array;

      public var rsn_len:Number;
      public var avg_cost:Number;

      public var seg_error:Boolean;

      public var lhs_version:int;
      public var rhs_version:int;

      // *** Constructor

      public function Route_Segment() :void
      {
         ; // No-op.
      }

      // ***

      //
      public function toString() :String
      {
         return ('Rte Segment:'
                 + ' / xs.len: ' + ((this.xs !== null)
                                    ? this.xs.length : 'none')
                 + ' / ys.len: ' + ((this.ys !== null)
                                    ? this.ys.length : 'none')
                 + ' / steps.len: ' + ((this.seg_rsteps !== null)
                                       ? this.seg_rsteps.length : 'none')
                 + ' / rsn_len: ' + this.rsn_len
                 + ' / avg_cost: ' + this.avg_cost
                 + ' / err?: ' + this.seg_error
                 + ' / lhs_v: ' + this.lhs_version
                 + ' / rhs_v: ' + this.rhs_version
                 );
      }

      //
      public function toString_Verbose() :String
      {
         return (this.toString()
                 + ' / lhs_rstop: ' + this.lhs_rstop
                 + ' / rhs_rstop: ' + this.rhs_rstop
                 );
      }

      // ***

   }
}


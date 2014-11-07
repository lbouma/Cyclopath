/* Copyright (c) 2006-2014 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_routes {

   import items.feats.Route;
   import utils.misc.Logging;
   import views.panel_routes.Route_Stop;

   public class Route_Stop_Editor {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('RteStopEditr');

      // *** Instance attributes

      // These are all from Route_Stop.

      public var name_:String;

      // Here, 'node_id' refers to the beg_node_id or fin_node_id of a
      // route step (or byway instance)
      public var node_id:int;
      public var stop_version:int;

      public var x_map:Number = NaN;
      public var y_map:Number = NaN;

      public var is_endpoint:Boolean;
      public var is_pass_through:Boolean;
      public var is_transit_stop:Boolean;
      public var internal_system_id:int;
      public var external_result:Boolean;

      public var street_name_:String;

      public var orig_stop:Route_Stop_Editor; // Infinite tree?
      public var dirty_stop:Boolean;

      // This is the only instance variable that's not also in Route_Stop.
      // Here, this.editor.orig_stop === pt
      //   except editor is null when not selected.
      public var editor:Route_Stop;

      // *** Constructor

      public function Route_Stop_Editor() :void
      {
         ; // No-op.
      }

      // ***

      //
      public function toString() :String
      {
         return ('Rte Stp Editor:'
                 + ' / name_: ' + this.name_
                 + ' / nid: ' + this.node_id
                 + ' / ver: ' + this.stop_version
                 + ' / x_m: ' + this.x_map
                 + ' / y_m: ' + this.y_map
                 + ' / endpt? ' + this.is_endpoint
                 + ' / xthru? ' + this.is_pass_through
                 + ' / txstop? ' + this.is_transit_stop
                 + ' / int_sid? ' + this.internal_system_id
                 + ' / ext_res? ' + this.external_result
                 + ' / st_nom: ' + this.street_name_
                 + ' / orig: ' + this.orig_stop
                 + ' / dirty? ' + this.dirty_stop
                 + ' / editor: ' + this.editor
                 );
      }

      // ***

   }
}


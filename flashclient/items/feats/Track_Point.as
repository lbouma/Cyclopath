/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.feats {

   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;

   public class Track_Point extends Record_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Track_Pt');

      // *** Mandatory attributes

      public static const class_item_type:String = 'track_point';
      public static const class_gwis_abbrev:String = 'tp';
      public static const class_item_type_id:int = Item_Type.TRACK_POINT;
      
      public var timestamp:Number;
      public var x:int;
      public var y:int;
      public var altitude:Number;
      public var bearing:Number;
      public var speed:Number;
      public var orientation:Number;

      // *** Constructor

      public function Track_Point(xml:XML=null)
      {
         super(xml);
      }
      
      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Track_Point = (to_other as Track_Point);
         super.clone_once(other);
         m4_ASSERT(false); // Not implemented.
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Track_Point = (to_other as Track_Point);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         if (gml !== null) {
            this.timestamp = Number(gml.@timestamp); // FIXME
            this.altitude = Number(gml.@altitude);
            this.bearing = Number(gml.@bearing);
            this.speed = Number(gml.@speed);
            this.orientation = Number(gml.@orientation);
            this.x = Number(gml.@x);
            this.y = Number(gml.@y);
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         m4_ASSERT(false); // Not implemented; doesn't make sense
         return gml;
      }     

   }
}


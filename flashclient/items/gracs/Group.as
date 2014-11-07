/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.gracs {

   import flash.utils.Dictionary;

   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class Group extends Group_Access_Scope {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('Group');

      // *** Mandatory attributes

      public static const class_item_type:String = 'group';
      public static const class_gwis_abbrev:String = 'gp';
      public static const class_item_type_id:int = Item_Type.GROUP;

      // *** Member variables

      [Bindable] public var description:String;

      // *** Constructor

      public function Group(xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Group = (to_other as Group);
         super.clone_once(other);
         other.description = this.description;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Group = (to_other as Group);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.description = gml.@description;
         }
         else {
            this.description = '';
         }
      }

      //
      override public function gml_produce() :XML
      {
         var gml:XML = super.gml_produce();
         gml.setName(Group.class_item_type); // 'group'
         gml.@description = this.description;
         return gml;
      }

      // ***

      //
      override public function get friendly_name() :String
      {
         return 'Group';
      }

      // ***

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' | desc: ' + this.description
                 );
      }

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.links {

   import items.Item_Base;
   import items.Record_Base;
   import items.utils.Item_Type;
   import utils.misc.Logging;

   public class Branch_Conflict extends Item_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('##Brnch_Cflt');

      // *** Mandatory attributes

      public static const class_item_type:String = 'branch_conflict';
      public static const class_gwis_abbrev:String = 'brct';
      public static const class_item_type_id:int = Item_Type.BRANCH_CONFLICT;

      // *** Instance variables

      // When two items are in conflict, the server indicates one as the left
      // item and one as the right item. In many conflict classes (such as
      // Flex's mx.data.Conflicts), you'd really see them labeled as _server_
      // and _client_, but that's not always the case for us. Our conflicts
      // could be client vs. server (that is, a working copy vs. what's in the
      // repository), but our conflicts could also be branch vs. branch (that
      // is, some branch at revision X against its mainline (parent branch)
      // also at revision X).
      // FIXME Does the user need to know what left is and what right is? That
      //       is, do we need an accept_all_left or accept_all_right fcn., and
      //       does the user need to know if their changes are left or right?
      public var item_left_id:int;
      public var item_right_id:int;
      protected var resolved_:Boolean = false;

      // *** Constructor

      public function Branch_Conflict(xml:XML=null)
      {
         super(xml);
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Branch_Conflict = (to_other as Branch_Conflict);
         super.clone_once(other);
         other.item_left_id = this.item_left_id;
         other.item_right_id = this.item_right_id;
         other.resolved_ = this.resolved_;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Branch_Conflict = (to_other as Branch_Conflict);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.item_left_id = int(gml.@item_left_id);
            this.item_right_id = int(gml.@item_right_id);
            this.resolved_ = Boolean(int(gml.@is_resolved));
         }
      }

      // *** Getters and setters

      //
      public function get resolved() :Boolean
      {
         return this.resolved_;
      }

      //
      // FIXME Does this cause a name conflict?
      public function set resolved(resolved:Boolean) :void
      {
         this.resolved_ = resolved;
      }

   }
}


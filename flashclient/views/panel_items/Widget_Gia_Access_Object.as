/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.panel_items {

   import grax.Access_Scope;
   import items.gracs.Group;
   import utils.misc.Logging;
   import views.panel_base.Detail_Panel_Base;

   public class Widget_Gia_Access_Object {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@Wgt_Gia_Obj');

      // ***

      [Bindable] public var dp:Detail_Panel_Base;
      [Bindable] public var group:Group;
      [Bindable] public var is_settable:Boolean;

      // *** Constructor

      public function Widget_Gia_Access_Object()
      {
      }

      // *** Instance methods

      //
      public function toString() :String
      {
         return 'group: ' + this.group.name_
                + ' / settable: ' + String(this.is_settable)
                + ' / dp: ' + String(this.dp)
                ;
      }

      //
      // C.f. Group_Access_Scope.compare_scope.
      public static function compare_gaos(lhs:Widget_Gia_Access_Object,
                                          rhs:Widget_Gia_Access_Object) :int
      {
         // Compare the left-hand-side to the right-hand-side
         var comparison:int = 0;
         if (int(lhs.is_settable) ^ int(rhs.is_settable)) {
            // Objects that are not settable should be lower in the list.
            comparison = (lhs.is_settable) ? -1 : 1;
         }
         else if ((lhs.is_settable && rhs.is_settable)
                  || (lhs.group.access_scope_id
                      == rhs.group.access_scope_id)) {
            // The scope is the same for both items, so just compare names.
            comparison = lhs.group.name_.localeCompare(rhs.group.name_);
         }
         else {
            // The scope is different for both items. We want the sort order to
            // be private first, then public, and then shared (since there's
            // only one private and one public group, but many shared).
            //
            // Start by checking if one of 'em is private;
            if (lhs.group.access_scope_id == Access_Scope.scope_private) {
               comparison = -1;
            }
            else if (rhs.group.access_scope_id == Access_Scope.scope_private) {
               comparison = 1;
            }
            // else, neither are private, so check public;
            else if (lhs.group.access_scope_id == Access_Scope.scope_public) {
               comparison = -1;
            }
            else if (rhs.group.access_scope_id == Access_Scope.scope_public) {
               comparison = 1;
            }
            // else, neither are public or private, and both aren't shared, so
            // one is shared and one is undefined.
            else {
               m4_ASSERT(false); // Does this happen?
               comparison = rhs.group.access_scope_id
                            - lhs.group.access_scope_id;
            }
         }
         return comparison;
      }

   }
}


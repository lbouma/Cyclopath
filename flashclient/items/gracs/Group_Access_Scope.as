/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.gracs {

   import flash.utils.Dictionary;

   import grax.Access_Scope;
   import items.Grac_Record;
   import items.Record_Base;
   import utils.misc.Logging;
   import utils.rev_spec.*;

   public class Group_Access_Scope extends Grac_Record {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Grp_Acc_Scp');

      // *** Instance variables

      protected var access_scope_id_:int = Access_Scope.scope_undefined;

      // *** Constructor

      public function Group_Access_Scope(
         xml:XML=null, rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // ***

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Group_Access_Scope = (to_other as Group_Access_Scope);
         super.clone_once(other);
         // Like Item_User_Access, we don't copy permissions when copying
         // items.
         other.access_scope_id = Access_Scope.scope_undefined;
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Group_Access_Scope = (to_other as Group_Access_Scope);
         super.clone_update(other, newbie);
      }

      // Use contents of XML element to init myself.
      /*/
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.access_scope_id_ = int(gml.@access_scope_id);
         }
         else {
            this.access_scope_id_ = Access_Scope.scope_undefined;
         }
      }
      /*/

      // Skipping: function gml_produce: access_scope is not settable.

      // *** Getters and setters

      //
      public function get access_scope_id() :int
      {
         return this.access_scope_id_;
      }

      //
      public function set access_scope_id(access_scope_id:int) :void
      {
         this.access_scope_id_ = access_scope_id;
      }

      // A public item is visible to the public group.
      [Bindable] public function get is_public() :Boolean
      {
         return (this.access_scope_id == Access_Scope.scope_public);
      }

      //
      public function set is_public(enable:Boolean) :void
      {
         m4_ASSERT(enable); // Cannot set scope this way. Use another fcn.
         this.access_scope_id = Access_Scope.scope_public;
      }

      //
      [Bindable] public function get is_shared() :Boolean
      {
         return (this.access_scope_id == Access_Scope.scope_shared);
      }

      //
      public function set is_shared(enable:Boolean) :void
      {
         m4_ASSERT(false); // This fcn. is never called...
         m4_ASSERT(enable); // Unsetting is undefined. Use another fcn.
         this.access_scope_id = Access_Scope.scope_shared;
      }

      // A private item is only accessible by the current user.
      [Bindable] public function get is_private() :Boolean
      {
         return (this.access_scope_id == Access_Scope.scope_private);
      }

      // A shared item is neither private nor public; it can be accessed by two
      // or more users or groups, but not by the public.
      public function set is_private(enable:Boolean) :void
      {
         m4_ASSERT(enable); // Unsetting is undefined. Use another fcn.
// FIXME_2013_06_11: What about access_infer?
         this.access_scope_id = Access_Scope.scope_private;
      }

      // Make an item private. Remove access to it by other groups. This is a
      // convenience fcn. for the user to manage item access.
      public function privatize() :void
      {
         m4_ASSERT(false); // Implement me!
         // Check that the user owns this item
         //if (this.access_level_id == Access_Level.owner) {
            // FIXME: Take away rights from other groups!
         //   this.is_private = true;
         //}
      }

      //
      // FIXME: What's a good name for this function?
      [Bindable] public function get access_scope() :String
      {
         return (
            (this.is_public ? 'Public'
            : (this.is_shared ? 'Shared'
            : (this.is_private ? 'Private'
                                 : 'Unknown'))));

      }

      //
      public function set access_scope(scope:String) :void
      {
         // No-op (fcn. needed for [Bindable]).
      }

      // ***

      // Comparison function for sorting lists of numeric tuples.
      // This fcn is no longer used. See Widget_Gia_Access_Object.compare_gaos.
      public static function compare_scope(lhs:Group_Access_Scope,
                                           rhs:Group_Access_Scope) :int
      {
         m4_ASSERT(false); // Probably works, but not called; might be stale.

         // Compare the left-hand-side to the right-hand-side
         var comparison:int = 0;
         if (lhs.access_scope_id == rhs.access_scope_id) {
            // The scope is the same for both items, so just compare names.
            comparison = lhs.name_.localeCompare(rhs.name_);
         }
         else {
            // The scope is different for both items. We want the sort order to
            // be private first, then public, and then shared (since there's
            // only one private and one public group, but many shared).
            //
            // Start by checking if one of 'em is private;
            if (lhs.access_scope_id == Access_Scope.scope_private) {
               comparison = -1;
            }
            else if (rhs.access_scope_id == Access_Scope.scope_private) {
               comparison = 1;
            }
            // else, neither are private, so check public;
            else if (lhs.access_scope_id == Access_Scope.scope_public) {
               comparison = -1;
            }
            else if (rhs.access_scope_id == Access_Scope.scope_public) {
               comparison = 1;
            }
            // else, neither are public or private, and both aren't shared, so
            // one is shared and one is undefined.
            else {
               m4_ASSERT(false); // Does this happen?
               comparison = rhs.access_scope_id - lhs.access_scope_id;
            }
         }
         return comparison;
      }

      // *** Convenience methods

      //
      override public function toString() :String
      {
         return (super.toString()
                 + ' / ' + 'Scp ' + this.access_scope.substr(0,3));
      }

   }
}


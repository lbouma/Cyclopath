/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items {

   import flash.utils.Dictionary;

   import utils.misc.Collection;
   import utils.misc.Logging;
   import utils.misc.Objutil;
   import utils.rev_spec.*;

   public class Item_Revisioned extends Item_Base
   {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Revsnd');

      // An item is revisioned if it's state is historically significant. That
      // is, an item can have a different set of values at different times,
      // or revisions.  For all items, time is measured by a revision ID,
      // such that each item has some representation at some revision. Items
      // themselves are uniquely indentified by a stack ID, which is the
      // same for each item as it evolves through time.
      //
      // But beware -- when the client wants to "do a diff" of two revisions
      // (compare the state of items at one revision against the state of items
      // at another revision), the client gets two sets of items, some with the
      // same stack IDs. To distinguish between those items from the old
      // revision and those items from the new revision, the stack ID is
      // hacked with a bit mask, which we put in the upper nibble of the int,
      // which is being assumed to be a 32-bit WORD.
      //
      // NOTE We support IDs up to 0x10000000, or 268,435,456.

      // Bit masks for computing counterpart IDs
      public static const MASK_ID_TAGS:int = 0x60000000;
      public static const MASK_OLD:int     = 0x40000000;
      public static const MASK_NEW:int     = 0x20000000;

      // *** Instance variables

      // What revision am I from?
      protected var rev:utils.rev_spec.Base;

      public var diff_group:String = '';

      // Values calculated by the server

      // To quickly compare two revisions of the same item without having to
      // individually compare each member, the server sends us a hash of all
      // the non-geometric values of the item.
      public var digest_nongeo:String;

      // *** Constructor

      public function Item_Revisioned(xml:XML=null,
                                      rev:utils.rev_spec.Base=null)
      {
         super(xml);
         // EXPLAIN: When is rev passed in, and when do we just use G.map?
         if (rev !== null) {
            this.rev = rev;
         }
         else if (G.map !== null) {
            //m4_ASSERT(!(G.map.rev_viewport is utils.rev_spec.Current));
            // This is the abnormal case. When we get items from the server, we
            // know their revision. When we create items locally, i.e., dummy
            // items or new items, we should use the working revision.
            //this.rev = G.map.rev_viewport;
            // Not true for G.map.untagged:
            //    m4_ASSERT(G.map.rev_workcopy !== null);
            this.rev = G.map.rev_workcopy;
         }
         // else, being called from init_GetDefinitionByName()
      }

      // ***

      //
      // FIXME: Use this instead of sending to ctor?
      public function set_revision(rev:utils.rev_spec.Base) :void
      {
         this.rev = rev;
      }

      // ***

      //
      // Wrapper over Objutil.consensus that also respects diffing items.
      public static function consensus(itms:*, // Set, Set_UUID, Dictionary...
                                       field_name:String=null,
                                       default_:*=undefined,
                                       on_empty:*=undefined) :*
      {
         var cons:*;

         var suc:Boolean = false;

         // Note that we expect just two items, unlike the Collection.consensus
         // function, which can handle however many.
         if (itms.length == 2) {

            var itms_arr:Array = Collection.something_as_array(itms);
            try {
               if ((itms_arr[0] !== itms_arr[1])
                   && (itms_arr[0].counterpart === itms_arr[1])) {
                  var new_itm:*;
                  var old_itm:*;
                  if (itms_arr[0].is_vgroup_new) {
                     new_itm = itms_arr[0];
                     old_itm = itms_arr[1];
                  }
                  else {
                     m4_ASSERT(itms_arr[1].is_vgroup_new);
                     new_itm = itms_arr[1];
                     old_itm = itms_arr[0];
                  }
                  m4_DEBUG('consensus: new_itm:', new_itm);
                  m4_DEBUG('consensus: old_itm:', old_itm);
                  // Update the object only if old_value != new_value.
                  if (new_itm[field_name] != old_itm[field_name]) {
                     // MAYBE: Is this appropriate for all situations?
                     // MAYBE: Use SequenceMatcher.diff_html instead.
                     cons = old_itm[field_name] + ' -> ' + new_itm[field_name];
                  }
                  else {
                     cons = new_itm[field_name];
                  }
                  suc = true;
                  /*
                  m4_DEBUG2('consensus: itms_arr[0].diff_group:',
                            itms_arr[0].diff_group);
                  m4_DEBUG2('consensus: itms_arr[1].diff_group:',
                            itms_arr[1].diff_group);
                  m4_DEBUG2('consensus: itms_arr[0].rev:',
                            itms_arr[0].rev);
                  m4_DEBUG2('consensus: itms_arr[1].rev:',
                            itms_arr[1].rev);
                  // E.g., the following is all True.
                  m4_ASSERT(itms_arr[0].rev_is_diffing);
                  m4_ASSERT(itms_arr[1].rev_is_diffing);
                  m4_ASSERT(itms_arr[0].diff_group);
                  m4_ASSERT(itms_arr[1].diff_group);
                  m4_ASSERT(!itms_arr[0].is_vgroup_none);
                  m4_ASSERT(!itms_arr[1].is_vgroup_none);
                  m4_ASSERT(itms_arr[0].is_vgroup_new
                            || itms_arr[0].is_vgroup_old
                            || itms_arr[0].is_vgroup_new);
                  m4_ASSERT(itms_arr[1].is_vgroup_new
                            || itms_arr[1].is_vgroup_old
                            || itms_arr[1].is_vgroup_new);
                  m4_ASSERT(G.map.rev_viewport is utils.rev_spec.Diff);
                  */
               }
               else {
                  suc = false;
                  /*
                  // E.g., the following is all True.
                  m4_ASSERT(itms_arr[0].counterpart === itms_arr[0]);
                  m4_ASSERT(!itms_arr[0].rev_is_diffing);
                  m4_ASSERT(!itms_arr[1].rev_is_diffing);
                  m4_ASSERT(!itms_arr[0].diff_group);
                  m4_ASSERT(!itms_arr[1].diff_group);
                  m4_ASSERT(itms_arr[0].is_vgroup_none);
                  m4_ASSERT(itms_arr[1].is_vgroup_none);
                  m4_ASSERT(!(G.map.rev_viewport is utils.rev_spec.Diff));
                  */
               }
            }
            catch (e:TypeError) {
               suc = false;
               m4_ASSERT_SOFT(false); // This path is never followed...
            }
         } // end: if (itms.length == 2)
         if (!suc) {
            cons = Objutil.consensus(itms, field_name, default_, on_empty);
         }

         m4_DEBUG('consensus: returning:', cons);
         return cons;
      }

      // *** Public static class method

      //
      public static function id_exists(item:Item_Revisioned)
         :Boolean
      {
         var item:Item_Revisioned
            = Item_Revisioned.item_find_new_old_any(item);
         return (item !== null);
      }

      // Check if stack ID, or its new or old version, exists in one of the
      // lookups.
      // MAYBE: Should this fcn. be moved to Item_Manager?
      public static function item_find_new_old_any(
         item:Item_Revisioned, ignore_deleted:Boolean=false)
            :Item_Revisioned
      {
         // item.class_item_lookup is the static class lookup, e.g.,
         // Byway.all, Waypoint.all, etc.
         return Item_Revisioned.item_find_new_old_any_id(
            item.stack_id, item.class_item_lookup, ignore_deleted);
      }

      //
      public static function item_find_new_old_any_id(
         stack_id:int, lookup:Dictionary, ignore_deleted:Boolean=false)
            :Item_Revisioned
      {
         var found:Item_Revisioned = null;
         var hack_id:int;
         if (found === null) { // I know, I know, found is already null...
            hack_id = stack_id;
            if (hack_id in lookup) {
               found = lookup[hack_id];
            }
            else if (!ignore_deleted) {
               found = G.item_mgr.item_deleted_get(hack_id);
            }
         }
         if (found === null) {
            hack_id = Item_Revisioned.version_id_hack(stack_id, true);
            if (hack_id in lookup) {
               found = lookup[hack_id];
            }
         }
         if (found === null) {
            hack_id = Item_Revisioned.version_id_hack(stack_id, false);
            if (hack_id in lookup) {
               found = lookup[hack_id];
            }
         }
         return found;
      }

      // Given an int or an item object, returns its sequence ID.
      protected static function item_get_stack_id(item:Object) :int
      {
         var stack_id:int = 0;

         if (item is int) {
            stack_id = Item_Revisioned.version_id_unhack((item as int));
         }
         else if (item is Item_Base) {
            stack_id = item.base_id;
         }
         else if (item !== null) {
            m4_ASSERT_SOFT(false);
         }
         m4_ASSERT_ELSE_SOFT;

         return stack_id;
      }

      // *** Protected static class methods

      // Hacks the given id to represent a new or old version of the
      // id (assumes new if old since static is the same as base).
      public static function version_id_hack(base:int, old:Boolean) :int
      {
         m4_ASSERT(base != 0);
         if (base < 0) {
            return base;
         }
         return (base | (old ? Item_Revisioned.MASK_OLD :
                               Item_Revisioned.MASK_NEW));
      }

      // Unhacks the given id to represent the base version
      // If old is false, it assumes the id has been hacked to be new.
      public static function version_id_unhack(id:int) :int
      {
         if (id < 0) {
            return id;
         }
         return (id & ~Item_Revisioned.MASK_ID_TAGS);
      }

      // *** Instance methods

      //
      override protected function clone_once(to_other:Record_Base) :void
      {
         var other:Item_Revisioned = (to_other as Item_Revisioned);
         super.clone_once(other);
         // Skipping: rev
         // Skipping: digest_nongeo
      }

      //
      override protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         var other:Item_Revisioned = (to_other as Item_Revisioned);
         super.clone_update(other, newbie);
      }

      //
      override public function gml_consume(gml:XML) :void
      {
         super.gml_consume(gml);
         if (gml !== null) {
            this.diff_group = gml.@dgrp;
         }
         else {
            this.diff_group = '';
         }
      }

      // The client should pass in a unique stack ID for the new item.
      // We might set a bitmask if this is a diff revision.
      protected function revisioned_id_init(seq_id:int) :void
      {
         var rev_diff:utils.rev_spec.Diff;
         this.stack_id = seq_id;
         // Hack ID if we're a new or old diff.
         rev_diff = (this.rev as utils.rev_spec.Diff);
         if (rev_diff !== null) {
            if (this.diff_group == 'former') {
               this.stack_id = Item_Revisioned.version_id_hack(this.stack_id,
                                                               true);
            }
            else if (this.diff_group == 'latter') {
               this.stack_id = Item_Revisioned.version_id_hack(this.stack_id,
                                                               false);
            }
            else {
               // Nothing to hack
               //m4_DEBUG('revisd_id_init: nothing to hack:', this.stack_id);
               m4_ASSERT((this.diff_group == 'static')
                         || (this.diff_group == ''));
            }
         }
         else {
            //m4_DEBUG('revisd_id_init: not diffing:', this.stack_id);
         }
      }

      // *** Getters and setters

      // Return the unhacked id of this feature
      public function get base_id() :int
      {
         return Item_Revisioned.version_id_unhack(this.stack_id);
      }

      // The counterpart is: if I am in version groups "old" or "new", then
      // counterpart is the new or old version of myself, respectively;
      // otherwise, it's myself. Note that newly added or deleted features
      // have NO counterpart, though subclasses may return a dummy counterpart
      // in this case.
      //
      // NOTE To find the couterpart item, it's up to the subclasses or another
      //      system component to implement an ID lookup. I [lb] tried using a
      //      global item lookup earlier (late 2010) but it seemed to bog down
      //      my Flash plugin. See Geofeature.all, Attachment.all, etc., and
      //      Item_Manager.as for some examples of the ID lookups
      public function get counterpart_untyped() :Item_Revisioned
      {
         var id_c:int;
         var item_lookup:Dictionary;
         if (this.is_vgroup_old || this.is_vgroup_new) {
            // The class_item_lookup is defined by the three intermediate
            // classes, Attachment, Geofeature, and Link_Value.
            item_lookup = this.class_item_lookup;
            // Get the unhacked id, which is unchanged if < 0,
            // otherwise, we unmask the hacked stack ID.
            id_c = Item_Revisioned.version_id_hack(
               this.base_id, !this.is_vgroup_old);
            if (id_c in item_lookup) {
               return item_lookup[id_c];
            }
            else {
               return null; // I.e., item doesn't exist in the other revision
            }
         }
         else {
            return this; // I.e., not diffing, so counterpart is us
         }
      }

      // Used by derived classes to help counterpart_untyped()
      protected function get class_item_lookup() :Dictionary
      {
         m4_ASSERT(false); // Abstract.
         return null;
      }

      //
      public static function get_class_item_lookup() :Dictionary
      {
         m4_ASSERT(false); // Not called.
         return null;
      }

      // True if object is not on the server, i.e. created by the user and not
      // yet saved (but capable of being saved, see invalid).
      public function get fresh() :Boolean
      {
         return (this.stack_id < 0);
      }

      //
      public function set fresh(fresh:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      override public function get hydrated() :Boolean
      {
         // We assume items in memory that have either a client or server stack
         // ID are fully hydrated, i.e., there's no more data about the item.
         // However, some classes, like Geofeatures and Routes, are only
         // partially fetched the first time, and their remaining data has to
         // be lazy loaded.
         return (!this.invalid);
      }

      //
      public function get invalid() :Boolean
      {
         return (this.stack_id == 0);
      }

      //
      public function set invalid(invalid:Boolean) :void
      {
         m4_ASSERT(false);
      }

      //
      public function get is_vgroup_new() :Boolean
      {
         // FIXME: Why is there bitmath being used here? This adds complexity
         //        where a boolean would be just as fast? Like, why doesn't
         //        this.rev (a Diff) tell us if this is new, old, or static?
         //        Also, this reduces the useable size of stack_ids by 2 pows.
         return ((!this.fresh)
                 && ((this.stack_id & Item_Revisioned.MASK_NEW) != 0));
      }

      //
      public function get is_vgroup_old() :Boolean
      {
         return ((!this.fresh)
                 && ((this.stack_id & Item_Revisioned.MASK_OLD) != 0));
      }

      //
      public function get is_vgroup_static() :Boolean
      {
         return (this.rev is utils.rev_spec.Diff
                 && (this.rev as utils.rev_spec.Diff).is_static);
      }

      //
      public function get is_vgroup_none() :Boolean
      {
         m4_ASSERT(this.rev !== null); // System should never leave null.
         return ((this.rev === null) || (!(this.rev is utils.rev_spec.Diff)));
      }

      //
      public function get revision() :utils.rev_spec.Base
      {
         return this.rev;
      }
      // NOTE: See the function, set_revision().

      //
      public function get rev_is_working() :Boolean
      {
         // The rev should only be null on startup, before this fcn. is called.
         m4_ASSERT(this.rev !== null); // System should never leave null.
         //return((this.rev === null) || (this.rev is utils.rev_spec.Working));
         return ((this.rev === null) || (this.rev is utils.rev_spec.Follow));
      }

      //
      public function get rev_is_diffing() :Boolean
      {
         return (this.rev is utils.rev_spec.Diff);
      }

      //
      public function get rev_is_historic() :Boolean
      {
         return (this.rev is utils.rev_spec.Historic);
      }

      //
      public function get trust_rid_latest() :Boolean
      {
         return false;
      }

   }
}


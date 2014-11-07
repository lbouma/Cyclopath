/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// Base class for wiki items. Called Record_Base because each item object is
// basically a row in a wiki database.
//
// This basic values are:
//
//   Is the item modified (dirty) in the working copy?
//   Can the item be discarded from the working copy? (Usually: !dirty)

package items {

   import flash.utils.getQualifiedClassName;

   import grax.Dirty_Reason;
   import utils.misc.Introspect;
   import utils.misc.Logging;

   // These are comments from years ago...
   //    "2011.08.11 dynamic classes have type-checking done at runtime. How
   //                much does this impede performance? Does flashclient really
   //                need items to be dynamic?"
   // [lb] assumes dynamic is not needed, since this switch was made years ago.
   //    "Confirm: dynamic needed for things like Command_Scalar_Edit.alter
   //              e.g., item[attr] = something;"
   //public dynamic class Record_Base {
   public class Record_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Record_Base');

      // *** Mandatory attributes

      public static const class_item_type:String = 'record_base';

      // *** Instance variables

      protected var dirty_reason:uint = Dirty_Reason.not_dirty;

      // *** Constructor

      public function Record_Base(xml:XML=null)
      {
         this.gml_consume(xml);
      }

      // ***

      //
      public function clone_item(cl:Record_Base=null) :Record_Base
      {
         if (this === cl) {
            // We can't clone ourselves, because the derived clone_once fcns.
            // clobber cl and then copy from this, which doesn't work.
            // But this happens a lot, and it seems like it'd be too messy
            // and too pointless to have callers check this vs. cl and to not
            // call clone. We're also called from init_add, which does other
            // things than trying to clone the same item into the same item,
            // so we should accommodate this behaviour.
            //m4_WARNING('clone: cannot clone against self:', this);
            //m4_WARNING(Introspect.stack_trace());
            cl = this;
         }
         else {
            var newbie:Boolean = false;
            if (cl === null) {
               cl = new (Introspect.get_constructor(this) as Class)();
               this.clone_once(cl);
               newbie = true;
            }
            // else, note that we're not calling clone_once, which
            // mostly copies singular members and not collection-type
            // members. Currently, just Item_Stack and Link_Values are fetched
            // lazily, which is when clone_once() isn't called; clone_once is
            // called from some commands, like Byway_Merge and Byway_Split.

            // BUG nnnn: Working copy update (updating flashclient working copy
            // to current server revision, i.e., after other users save the
            // map). This is... low priority. For now, flashclient should
            // always use the same revision when checkingout. The revision only
            // changes if the user changes branches, logs in or out, reloads
            // flashclient, or otherwise causes an item reload.

            // Always clone_update.
            this.clone_update(cl, newbie);
         }

         return cl;
      }

      // The clone_once function copies everything except unique identifiers.
      protected function clone_once(to_other:Record_Base) :void
      {
         m4_DEBUG('clone_once: to_other.dirty_reason:', to_other.dirty_reason);
         m4_DEBUG('clone_once: this.dirty_reason:', this.dirty_reason);
         // We... shouldn't do this, right?:
         //  to_other.dirty_reason = this.dirty_reason;
      }

      //
      public function clone_once_pub(to_other:Record_Base) :void
      {
         this.clone_once(to_other);
      }

      //
      public function clone_id(to_other:Record_Base) :void
      {
         m4_ASSERT(false); // Derived classes better override.
      }

      //
      protected function clone_update( // no-op
         to_other:Record_Base, newbie:Boolean) :void
      {
         // Nothing tuh da.
      }

      //
      public function clone_update_pub(to_other:Record_Base, newbie:Boolean)
         :void
      {
         this.clone_update(to_other, newbie);
      }

      //
      // Use contents of XML element to init myself.
      public function gml_consume(gml:XML) :void
      {
         // No-op
      }

      //
      // Return an XML element representing myself.
      public function gml_produce() :XML
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      // ***

      //
      public function get dirty() :Boolean
      {
         return (this.dirty_reason != Dirty_Reason.not_dirty);
      }

      //
      public function get_dirty_reason() :uint
      {
         return this.dirty_reason;
      }

      //
      public function get discardable() :Boolean
      {
         return !this.dirty;
      }

      //
      public function get get_class_item_type() :String
      {
         return Introspect.get_constructor(this).class_item_type;
      }

      //
      public function set get_class_item_type(class_item_type:String) :void
      {
         ; // no-op
      }

      // Return true if the item is dirty because of reason. If reason is
      // not_dirty, returns True because of any reason.
      //
      // Reasons are used when committing to know exactly what to commit.
      public function dirty_get(reason:*=null) :Boolean
      {
         // EXPLAIN: dirty_reason & null ==> true if dirty_reason != 0?
         // m4_DEBUG('EXPLAIN: what is 0 & null?:', (0 & null)); // prints: 0
         // m4_DEBUG('EXPLAIN: what is 1 & null?:', (1 & null)); // prints: 0
         if (reason === null) {
            // Set to, i.e., 0xFFFFFFFF.
            // reason = uint(Dirty_Reason.mask_revisioned
            //               | Dirty_Reason.mask_non_wiki);
            reason = Dirty_Reason.all_reasons;
            m4_ASSERT(reason == uint(0xFFFFFFFF));
         }
         return Boolean(this.dirty_reason & reason);
      }

      // Set this dirty or not dirty because of reason.
      // WARNING: As this meddles with G.item_mgr.dirtyset, you should not call
      //          it dirty while iterating through dirtyset.
      public function dirty_set(reason:uint, d:Boolean) :void
      {
         m4_VERBOSE('dirty_set:', Dirty_Reason.lookup_key[reason], '/ d:', d);
         // We ignore Dirty_Reason.not_dirty, but it lets callers not have to
         // always check it. The alternative is to treat not_dirty as
         // dirty_clear.
         if (reason != Dirty_Reason.not_dirty) {
            // Skipping: this.dirty_get(reason). We don't care if it's already
            // dirty, since derived classes can override this behavior.
            m4_VERBOSE(' >> dirty_set: setting:', this);
            if (d) {
               this.dirtyset_add(reason);
            }
            else {
               this.dirtyset_del(reason);
            }
         }
      }

      //
      public function dirtyset_add(reason:uint) :void
      {
         // COUPLING. Ug. ly.
         if (!this.is_revisionless) {
            G.item_mgr.dirtyset.add(this);
         }
         // else, a route/track/post/thread/nonwiki_item, and those item types
         //       have their own special ways of being saved.
         this.dirty_reason |= reason;
      }

      //
      public function dirtyset_del(reason:uint) :void
      {
         this.dirty_reason &= ~reason;

// BUG_FALL_2013: still testing map editing and route changes and logging out
// when you undo all changes, contains_dirty_revisioned
//  and contains_dirty_revisionless still say yes...
//  meaning, item still says dirty. not too big a deal...
         m4_DEBUG3('dirtyset_del: reason: 0x', reason.toString(16),
                   '/ dirty_reason:', this.dirty_reason,
                   '/ dirty:', this.dirty);
         if (!this.dirty) {
            G.item_mgr.dirtyset.remove(this);
         }
      }

      //
      public function get hydrated() :Boolean
      {
         m4_ASSURT(false);
         return false;
      }

      //
      public function set hydrated(ignored:Boolean) :void
      {
         m4_ASSURT(false);
      }

      //
      public function get is_revisionless() :Boolean
      {
         return false;
      }

      // *** Developer methods

      //
      // Both AutoComplete logs and Logging.debug use this fcn. to produce a
      // friendly name for the item.
      public function toString() :String
      {
         return (getQualifiedClassName(this));
      }

      //
      public function get loudstr() :String
      {
         return this.toString_Verbose();
      }

      //
      public function get softstr() :String
      {
         return this.toString_Terse();
      }

      //
      public function toString_Terse() :String
      {
         return '';
      }

      //
      public function toString_Verbose() :String
      {
         return this.toString();
      }

   }
}


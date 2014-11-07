/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// MAYBE: Can we get rid of this intermediate item class?

package items {

   import grax.Dirty_Reason;
   import items.attcs.Attribute;
   import items.utils.Watcher_Frequency;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;
   import utils.rev_spec.*;

   public class Item_Watcher_Shim extends Item_User_Access
   {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Itm_Wr_Shim');

      // *** Instance variables

      // *** Constructor

      public function Item_Watcher_Shim(xml:XML=null,
                                        rev:utils.rev_spec.Base=null)
      {
         super(xml, rev);
      }

      // ***

      //
      override public function update_item_committed(commit_info:Object) :void
      {
         // FIXME: Implement both of these.
         // 2013.03.27: Is this class still needed in the item class hierarchy?
         if (this.dirty_get(Dirty_Reason.item_watcher)) {
            this.dirty_set(Dirty_Reason.item_watcher, false);
         }
         if (this.dirty_get(Dirty_Reason.item_read_evt)) {
            this.dirty_set(Dirty_Reason.item_read_evt, false);
         }
         super.update_item_committed(commit_info);
      }

// FIXME_2013_06_11: Remove enabled and just use freq.
      //
      [Bindable] public function get watcher_enabled() :Boolean
      {
         var watcher_enabled:Boolean = false;
         if (
            (this.watcher_freq > Watcher_Frequency.never)
// FIXME: do we support user-wide email enable _and_ per-item email enable?
//        probably: think work_items...
             //|| ()
             ) {
            watcher_enabled = true;
         }
         m4_DEBUG('get watcher_enabled:', watcher_enabled);
         return watcher_enabled;
      }

      //
      public function set watcher_enabled(watcher_enabled:Boolean) :void
      {
         // m4_ASSERT(false); // FIXME: implement?
         m4_DEBUG('set watcher_enabled:', watcher_enabled);
         if (!watcher_enabled) {
// FIXME: set link_value to never
// FIXME: maybe cache the link_value so we're not always looking it up
         }
         else {
         }
      }

      //
      [Bindable] public function get watcher_freq() :int
      {
         var internal_name:String = '/item/alert_email';
         // It seems hokey, but Flex lets us reference a derived child's class.
         var alert_attr:Attribute = Attribute.all_named[internal_name];
         var feats:Set_UUID = new Set_UUID([this,]);
         var default_:* = -2; // When multiple values occur; shouldn't happen.
         var on_empty:* = -1;
         var watcher_freq:int = Attribute.consensus(
               feats, alert_attr, default_, on_empty);
         if (watcher_freq == -1) {
            watcher_freq = Watcher_Frequency.never;
         }
         else {
            m4_ASSERT(Watcher_Frequency.is_defined(watcher_freq));
         }
         return watcher_freq;
      }

      //
      public function set watcher_freq(watcher_freq:int) :void
      {
         m4_DEBUG('set watcher_freq:', watcher_freq);
         m4_ASSERT(Watcher_Frequency.is_defined(watcher_freq));
//m4_ASSERT(false); // FIXME: implement
      }

   }
}


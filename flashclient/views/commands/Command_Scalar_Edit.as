/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Dirty_Reason;
   import items.Geofeature;
   import items.Item_Versioned;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Command_Scalar_Edit extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Scal_Ed');

      // *** Instance variables

      protected var attr:String;

      // This command applies to one or more targets, and it sets the value of
      // a common property of those targets. NOTE: This class uses the access
      // operator on the targets, so the target class needs to be declared
      // 'dynamic'.
      protected var property_name:String;

      // When applied, this command sets the property of each item to the same
      // value, so there's only one new value. To be undone, this command also
      // remembers each items' property's former value.
      protected var value_new:*;
      protected var value_old:Array;

      // *** Constructor

      public function Command_Scalar_Edit(targets:Set_UUID,
                                          property_name:String,
                                          value_new:*,
                                          reason:int=0)
         :void
      {
         if (reason == 0) {
            reason = Dirty_Reason.item_data
         }

         super(targets.as_Array(), reason);

         this.property_name = property_name;

         var item:Item_Versioned;
         this.value_new = value_new;
         this.value_old = new Array();
         for each (item in this.edit_items) {
            //m4_DEBUG2('Command_Scalar_Edit: item[this.property_name]',
            //          item[this.property_name]);
            this.value_old.push(item[this.property_name]);
         }
      }

      // *** Instance methods

      //
      protected function alter(i:int, from:*, to:*) :void
      {
         // NOTE: Ignoring variable 'from'
         var item:Item_Versioned = (this.edit_items[i] as Item_Versioned);
         var feat:Geofeature = (this.edit_items[i] as Geofeature);

         item[this.property_name] = to;
         if (feat !== null) {
            //m4_DEBUG('alter: draw_all: feat:', feat.toString());
            feat.draw_all();
         }
      }

      //
      override public function do_() :void
      {
         var i:int;

         super.do_();
         for (i = 0; i < this.edit_items.length; i++) {
            this.alter(i, this.value_old[i], this.value_new);
         }

         // FIXME: See FIXME in undo.
         // MAYBE: This marks *all* panels dirty. We could just tell the Item
         //        Details panel and its children. See other places
         //        panels_mark_dirty() is called without args.
         m4_DEBUG('do_: panels_mark_dirty');
         G.panel_mgr.panels_mark_dirty();
      }

      //
      override public function undo() :void
      {
         var i:int;

         super.undo();
         for (i = 0; i < this.edit_items.length; i++) {
            this.alter(i, this.value_new, this.value_old[i]);
         }

         // See Bug 2089: Update the details panel, which updates Text Edit.
         // FIXME: Selectively update the appropriate details panel, not all of
         //        them...
         m4_DEBUG('undo: panels_mark_dirty');
         G.panel_mgr.panels_mark_dirty();
      }

      // ***

      //
      override public function get performable() :Boolean
      {
         // This command is not performable if there are no links.
         // FIXME Why doesn't this apply to all attachments?
         return ((this.edit_items.length > 0) && (super.performable));
      }

      // ***

   }
}


/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Dirty_Reason;
   import items.Geofeature;
   import items.Item_Versioned;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Command_Scalar_Edit_2 extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Scl_Ed2');

      // *** Instance variables

      // This command applies to one or more targets, and it sets the value of
      // a common property of those targets. NOTE: This class uses the access
      // operator on the targets, so the target class needs to be declared
      // 'dynamic'.
      // For e.g.s, see property_fcns: edit_stop_name_fcn, groups_access_fcn.
      protected var property_fcn:String;
      protected var property_key:*;

      // When applied, this command sets the property of each item to the same
      // value, so there's only one new value. To be undone, this command also
      // remembers each items' property's former value.
      protected var value_new:*;
      protected var value_old:Array;

      // *** Constructor

      public function Command_Scalar_Edit_2(targets:Set_UUID,
                                            property_fcn:String,
                                            property_key:*,
                                            value_new:*,
                                            reason:int=0)
         :void
      {
         var item:Item_Versioned;

         if (reason == 0) {
            reason = Dirty_Reason.item_data;
         }

         super(targets.as_Array(), reason);

         this.property_fcn = property_fcn;
         this.property_key = property_key;

         this.value_new = value_new;
         this.value_old = new Array();

         for each (item in this.edit_items) {
            var rstop_name:String = item[this.property_fcn](this.property_key);
            this.value_old.push(rstop_name);
         }
      }

      // *** Instance methods

      //
      protected function alter(i:int, from:*, to:*, do_or_undo:Boolean) :void
      {
         // NOTE: Ignoring variable 'from'.
         var item:Item_Versioned = (this.edit_items[i] as Item_Versioned);
         var feat:Geofeature = (this.edit_items[i] as Geofeature);

         m4_DEBUG2('alter: fcn:', this.property_fcn,
                   '/ key:', this.property_key, '/ to:', to, '/', item);

         item[this.property_fcn](this.property_key, to, do_or_undo);
         if (feat !== null) {
            //m4_DEBUG('alter: draw_all: feat:', feat.toString());
            feat.draw_all();
         }
      }

      // NOTE: Next two fcns. c.f. Command_Scalar_Edit.

      //
      override public function do_() :void
      {
         var i:int;

         super.do_();
         for (i = 0; i < this.edit_items.length; i++) {
            m4_DEBUG2('do_: value_old[', i, ']:', this.value_old[i],
                      'value_new:', this.value_new);
            this.alter(i, this.value_old[i], this.value_new,
                       /*do_or_undo=*/true);
         }

         // FIXME: See FIXME in undo.
         m4_DEBUG('do_: panels_mark_dirty');
         G.panel_mgr.panels_mark_dirty();
      }

      //
      override public function undo() :void
      {
         var i:int;

         super.undo();
         for (i = 0; i < this.edit_items.length; i++) {
            this.alter(i, this.value_new, this.value_old[i],
                       /*do_or_undo=*/false);
         }

         // See Bug 2089: Update the details panel, which updates Text Edit.
         // FIXME: Selectively update the appropriate details panel, not all of
         //        them...
         m4_DEBUG('undo: panels_mark_dirty');
         G.panel_mgr.panels_mark_dirty();
      }

   }
}


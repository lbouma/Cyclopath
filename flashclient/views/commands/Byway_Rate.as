/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.commands {

   import grax.Access_Level;
   import grax.Dirty_Reason;
   import utils.misc.Logging;
   import utils.misc.Set;
   import utils.misc.Set_UUID;

   public class Byway_Rate extends Command_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Cmd_Bway_Rt');

      // *** Instance variables

      protected var rating_old:Array;
      protected var rating_new:Number;

      // *** Constructor

      public function Byway_Rate(bys:Set_UUID, rating:Number)
      {
         var b:Byway;

         super(bys.as_Array(), Dirty_Reason.item_rating);
         this.rating_old = new Array();

         for each (b in this.edit_items) {
            this.rating_old.push(b.user_rating);
         }

         this.rating_new = rating;
      }

      // *** Instance methods

      //
      override public function get descriptor() :String
      {
         return 'rate block(s)';
      }

      //
      override public function do_() :void
      {
         var by:Byway;

         super.do_();

         for each (by in this.edit_items) {
            by.user_rating = this.rating_new;
            by.draw_all();
         }
         this.ui_adjust();
      }

      // Since we're not really editing the Byway, the user doesn't need editor
      // access to the Byway. They just need to be able to see it.
      override protected function get prepare_items_access_min() :int
      {
         // MAYBE: If byway_rating is to be an attribute, this fcn. doesn't
         //        make sense, since the attribute and its link_value with have
         //        nips.
         //return Access_Level.viewer;
         return Access_Level.client;
      }

      // Rating only applies to existing items, so it wouldn't make sense if
      // this command dealt with new (invalid) objects.
      override protected function get prepare_items_must_exist() :Boolean
      {
         return true;
      }

      // Adjust the UI rating widget, if there is one, to reflect the byway's
      // or byways' new rating(s).
      protected function ui_adjust() :void
      {
         G.panel_mgr.item_panels_mark_dirty(this.edit_items);
      }

      //
      override public function undo() :void
      {
         var by:Byway;
         var i:int;
         super.undo();

         for (i = 0; i < this.edit_items.length; i++) {
            by = this.edit_items[i] as Byway;
            by.user_rating = this.rating_old[i];
            by.draw_all();
         }
         this.ui_adjust();
      }

  }
}


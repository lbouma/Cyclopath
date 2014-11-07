/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.rev_spec {

   public class Diff extends Pinned {

      // *** Class attributes

      // Tags defining a feature's diff group
      public static const NONE:int = 0;
      public static const OLD:int = 1;
      public static const NEW:int = 2;
      public static const STATIC:int = 3;
      //
      // Strings representing the above -- careful with order & indices...
      protected static const GROUP_STR:Array = ['', 'old', 'new', 'static',];

      // *** Instance variables

      public var rid_old:int;
      public var rid_new:int;
      public var group_:int;

      // *** Constructor

      public function Diff(rid_old:int, rid_new:int) :void
      {
         super();
         m4_ASSERT(rid_old > 0 && rid_new > 0);
         this.rid_old = rid_old;
         this.rid_new = rid_new;
         this.group_ = NONE;
      }

      // *** Public instance methods

      //
      // NOTE: None of the other revision classes define this fcn.
      public function clone(group:int) :Diff
      {
         var c:Diff = new Diff(this.rid_old, this.rid_new);
         c.group_ = group;
         return c;
      }

      //
      override public function equals(rev:Base) :Boolean
      {
         var other:Diff = (rev as Diff);
         return ((other !== null)
                 && (super.equals(other))
                 && (other.rid_old == this.rid_old)
                 && (other.rid_new == this.rid_new)
                 && (other.group_ == this.group_));
      }

      //
      override public function toString() :String
      {
         // var rid_grp:String = Diff.GROUP_STR[this.group_];
         // return (this.rid_old + ':' + this.rid_new + ':' + rid_grp);
         return (this.rid_old + ':' + this.rid_new);
      }

      //
      override public function get friendly_name() :String
      {
         return String(this.toString() + ' [diff]');
      }

      //
      override public function get short_name() :String
      {
         var sname:String = 'd:' + this.toString();
         return sname;
      }

      // *** Getters and setters

      //
      public function get group() :int
      {
         return this.group_;
      }

      //
      public function get is_old() :Boolean
      {
         return this.group_ == OLD;
      }

      //
      public function get is_new() :Boolean
      {
         return this.group_ == NEW;
      }

      //
      public function get is_static() :Boolean
      {
         return this.group_ == STATIC;
      }

   }
}


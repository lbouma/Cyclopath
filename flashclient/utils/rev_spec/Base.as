/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

/*

   For historic reasons, this package is called rev_spec (currently,
   utils.rev_spec). Also, this package contains many modules, in contrast to
   pyserver, wherein you'll find just one, pyserver.util.revision.

   The revision classes hierarchy is split into two groups:
   one group for editable items, and one group for historic
   items. The former group is called 'follow', as in, the
   items follow the latest items on the server. The latter
   is called 'pinned', since the items are checked out just
   once and are not editable.

      Base
      |
      | - Follow
      | |
      | | - Current
      | | |
      | | | - Changed
      | |
      | | - Working
      |
      | - Pinned
      | |
      | | - Diff
      | |
      | | - Historic

   In G.map, there's now rev_workcopy and rev_viewport. The
   latter, rev_viewport, always reflects the state of the map
   (set to either follow or pinned; if follow, set to same
   object as rev_workcopy.) The former, rev_workcopy, just
   tracks the follow state: it begins life as Current and
   then cycles between Working and Changed.

   */

package utils.rev_spec {

   public class Base {

      // *** Constructor

      public function Base() :void
      {
         // no-op
      }

      // *** Public instance methods

      //
      public function equals(rev:Base) :Boolean
      {
         m4_ASSERT(false); // Abstract
         return false;
      }

      // toString is used by GWIS_Base to construct the HTTP GET request.
      public function toString() :String
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      // friendly_name is used in lieu of toString, and is meant to show the
      // revision object to developers or users
      public function get friendly_name() :String
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

      //
      public function get short_name() :String
      {
         m4_ASSERT(false); // Abstract
         return null;
      }

   }
}


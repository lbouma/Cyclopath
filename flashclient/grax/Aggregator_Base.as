/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// This file is needed simply to provide a common base class for Grac_Manager
// and Item_Manager.

package grax {

   import utils.misc.Logging;

   public class Aggregator_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('#Item_Agg');

      // *** Constructor

      public function Aggregator_Base()
      {
         // no-op
      }

      // *** Public interface

   }
}


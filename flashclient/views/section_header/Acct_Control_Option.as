/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package views.section_header {

   import utils.misc.Logging;

   public class Acct_Control_Option {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('@SctH_ACtOpt');

      // *** Instance variables

      [Bindable]
      public var label:String;

      [Bindable]
      public var action:String;

      // *** Constructor

      public function Acct_Control_Option()
      {
         super();
      }

      // ***

   }
}



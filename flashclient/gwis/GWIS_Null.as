/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// The Null request does nothing. It's just an easy way to touch the server
// (e.g., to put something in the Apache log).
//
// We can also use the Null request to get the latest revision ID.

package gwis {

   import utils.misc.Logging;
   import utils.misc.Set_UUID;

   public class GWIS_Null extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/NULL');

      // *** Constructor

      public function GWIS_Null(url_extra:String) :void
      {
         var url:String = this.url_base('null') + '&' + url_extra;
         super(url, this.doc_empty());
      }

      //
      override protected function get trump_list() :Set_UUID
      {
         return GWIS_Base.trumped_by_nothing;
      }

   }
}


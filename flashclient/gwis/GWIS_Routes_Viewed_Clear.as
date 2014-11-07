/* Copyright (c) 2006-2010 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

// FIXME: route manip.

package gwis {

   import utils.misc.Logging;

   public class GWIS_Routes_Viewed_Clear extends GWIS_Base {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('~GW/Rt_ClrH');

      // *** Constructor

      public function GWIS_Routes_Viewed_Clear()
      {
         super(this.url_base('routes_viewed_clear'), this.doc_empty());
      }

   }
}


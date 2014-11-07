/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.jobsq {

   import flash.utils.Dictionary;

   import utils.misc.Logging;

   // SYNC_ME: tables: public.job_status
   //                  public.enum_definition.
   //         sources: flashclient/items/jobsq/Job_Status.py
   //                  pyserver/item/jobsq/job_status.py

   public class Job_Status {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('__Job_Status');

      // SYNC_ME: Search: Job Statuses.
      public static const lookup_obj:Array =
         [
            /* Out of bounds. */
            { e_key:  -1, e_val:    'invalid' },
            { e_key:   0, e_val:     'notset' },
            /* Universal statuses. */
            { e_key:   1, e_val:   'complete' },
            { e_key:   2, e_val:     'failed' },
            { e_key:   3, e_val:     'queued' },
            { e_key:   4, e_val:   'starting' },
            { e_key:   5, e_val:    'working' },
            { e_key:   6, e_val:    'aborted' },
            { e_key:   7, e_val:  'canceling' },
            { e_key:   8, e_val: 'suspending' },
            { e_key:   9, e_val:   'canceled' },
            { e_key:  10, e_val:  'suspended' },
            /* */
         ];

      public static var lookup_key:Dictionary = new Dictionary();
      public static var lookup_val:Dictionary = new Dictionary();
      //public static const lookup_key:Dictionary = new Dictionary();
      //public static const lookup_val:Dictionary = new Dictionary();
      private static function hack_attack() :void
      {
         // NOTE: Not prefacing with Job_Status. because not defined yet.
         for each (var o:Object in lookup_obj) {
            m4_DEBUG('hack_attack: e_key:', o.e_key, '/ e_val:', o.e_val);
            lookup_key[o.e_key] = o.e_val;
            lookup_val[o.e_val] = o.e_key;
         }
      }
      hack_attack();
      // FIXME: Is this my base class for enums?

      //// SYNC_ME: Search: Job Statuses.
      ///* Out of bounds. */
      //public static const invalid:int = -1;
      //public static const notset:int = 0;
      ///* Universal statuses. */
      //public static const queued:int = 1;
      //public static const started:int = 2;
      //public static const working:int = 3;
      //public static const complete:int = 4;
      //public static const failed:int = 5;

      //public static var lookup:Array = new Array();

      // *** Constructor

      public function Job_Status() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Static class initialization

      // *** Static class methods

   }
}



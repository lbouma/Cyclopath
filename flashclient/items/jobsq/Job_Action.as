/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package items.jobsq {

   import flash.utils.Dictionary;

   import utils.misc.Logging;

   // SYNC_ME: tables: public.job_action
   //                  public.enum_definition.
   //         sources: flashclient/items/jobsq/Job_Action.py
   //                  pyserver/item/jobsq/job_action.py

   public class Job_Action {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('__Job_Action');

      // SYNC_ME: Search: Job Actions.
      public static const lookup_obj:Array =
         [
            /* Out of bounds. */
            { e_key:  -1, e_val:  'invalid' },
            { e_key:   0, e_val:   'notset' },
            /* Universal actions. */
            { e_key:   1, e_val:   'create' },
            { e_key:   2, e_val:   'cancel' },
            { e_key:   3, e_val:   'delist' },
            { e_key:   4, e_val:  'suspend' },
            { e_key:   5, e_val:  'restart' },
            { e_key:   6, e_val:   'resume' },
            /* Custom actions: file actions. */
            { e_key:   7, e_val: 'download' },
            { e_key:   8, e_val:   'upload' },
            { e_key:   9, e_val:   'delete' }
            /* */
         ];
      public static var lookup_key:Dictionary = new Dictionary();
      public static var lookup_val:Dictionary = new Dictionary();
      private static function hack_attack() :void
      {
         for each (var o:Object in lookup_obj) {
            m4_DEBUG('hack_attack: e_key:', o.e_key, '/ e_val:', o.e_val);
            lookup_key[o.e_key] = o.e_val;
            lookup_val[o.e_val] = o.e_key;
         }
      }
      hack_attack();

      // *** Constructor

      public function Job_Action() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // ***

   }
}


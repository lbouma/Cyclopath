/* Copyright (c) 2006-2013 Regents of the University of Minnesota.
   For licensing terms, see the file LICENSE. */

package utils.misc {

   import flash.utils.getQualifiedClassName;

   public class Objutil {

      // *** Class attributes

      protected static var log:Logging = Logging.get_logger('ObjUtil');

      // *** Constructor

      public function Objutil() :void
      {
         m4_ASSERT(false); // Not instantiable
      }

      // *** Public static class methods

      //
      // If all objects in collection have the same value in attribute
      // object_key, return that value; otherwise return default_ if two
      // or more items in collection, or on_empty if zero items.
      public static function consensus(collection:*,
                                       object_key:String,
                                       default_value:*=undefined,
                                       on_empty:*=undefined) :*
      {
         var consensus:* = default_value;
         var visitor:Object;
         var first_visit:Boolean = true;
         for each (visitor in collection) {
            if (first_visit) {
               consensus = visitor[object_key];
               first_visit = false;
            }
            else {
               if (visitor[object_key] != consensus) {
                  //m4_DEBUG('consensus: differs/using default:', default_value);
                  consensus = default_value;
                  break;
               }
            }
         }
         if (first_visit) {
            // No items.
            if (on_empty !== undefined) {
               //m4_DEBUG('consensus: using empty default:', on_empty);
               consensus = on_empty;
            }
            //else {
            //   m4_DEBUG('consensus: empty/using normal default:', consensus);
            //}
         }
         //else {
         //   m4_DEBUG('consensus: all agree:', consensus);
         //}
         return consensus;
      }

      //
      public static function consensus_b(collection:*,
                                         object_key:String,
                                         default_value:Boolean=false) :Boolean
      {
         m4_ASSERT((collection is Array)
                   || (collection is Set)
                   || (collection is Set_UUID));
         var consensus:* = Objutil.consensus(collection, object_key, null);
         if (consensus === null) {
            consensus = default_value;
         }
         else {
            m4_ASSERT(consensus is Boolean);
         }
         return consensus;
      }

      //
      public static function consensus_fcn(collection:*,
                                           property_fcn:String,
                                           property_key:*,
                                           default_value:*=undefined) :*
      {
         var consensus:* = default_value;
         var visitor:Object;
         var first_visit:Boolean = true;
         for each (visitor in collection) {
            if (first_visit) {
               consensus = visitor[property_fcn](property_key);
               first_visit = false;
            }
            else {
               if (consensus != visitor[property_fcn](property_key)) {
                  consensus = default_value;
                  break;
               }
            }
         }
         m4_DEBUG('consensus_fcn:', consensus);
         return consensus;
      }

      // Utility function that returns value if not null, otherwise dflt
      public static function null_replace(value:*, dflt:*) :*
      {
         return (value === null ? dflt : value);
      }

      //
      // NOTE: Objects in Array a must be from a 'dynamic' class (so that the
      //       [] operator works).
      public static function values_collect(collection:*, attr:String) :Array
      {
         var values:Array = new Array();

         for each (var o:Object in collection) {
            values.push(o[attr]);
         }

         return values;
      }

   }
}

